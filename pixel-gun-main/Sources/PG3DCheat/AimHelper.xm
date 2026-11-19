/*
 * AimHelper.xm
 *
 * WorldToScreen:
 *   We need Camera.main.WorldToScreenPoint(). We obtain it via:
 *     il2cpp_domain_get() → il2cpp_domain_assembly_open("UnityEngine.CoreModule")
 *     → il2cpp_class_from_name("UnityEngine","Camera")
 *     → il2cpp_class_get_method_from_name("WorldToScreenPoint", 1)
 *     → il2cpp_method_get_function_pointer()
 *
 *   This path is established in resolveWorldToScreen() called from
 *   the frame hook after il2cpp is fully initialised.
 *
 * Touch injection:
 *   We use IOHIDEvent / GSEvent approach via private framework,
 *   OR we apply the aim delta directly to the game's look-input
 *   by patching the joystick delta value read by the InputSystem.
 *   The cleaner approach for Nathanlr: hook UITouch delivery.
 *
 *   For this build we use the direct delta approach:
 *   We locate the InputSystem's pointer delta accumulator and add
 *   to it. This is safer than synthesising OS-level events.
 *
 * INTEGRATION GAP:
 *   WorldToScreen and the input delta field offset are NOT directly
 *   in the dump. They require runtime resolution (see comments).
 *   The code below is complete except for those two runtime values;
 *   they are marked RESOLVE_AT_RUNTIME.
 */

#import "AimHelper.h"
#import <mach-o/dyld.h>
#import <dlfcn.h>   // FIX: required for dlsym() used in resolvePlayerList()
#import <float.h>   // FIX: required for FLT_MAX
#import <objc/runtime.h>   // FIX (mc1h): required for class_getInstanceVariable/ivar_getOffset

// FIX: g_config is defined in Tweak.x; declare extern so this TU can see it.
extern PG3DConfig* g_config;

// ── il2cpp forward declarations ──────────────────────────────────────────
extern "C" {
    typedef void* Il2CppDomain;
    typedef void* Il2CppAssembly;
    typedef void* Il2CppImage;
    typedef void* Il2CppClass;
    typedef void* Il2CppMethod;
    typedef void* Il2CppObject;

    Il2CppDomain* il2cpp_domain_get();
    Il2CppAssembly* il2cpp_domain_assembly_open(Il2CppDomain* domain, const char* name);
    Il2CppImage* il2cpp_assembly_get_image(Il2CppAssembly* assembly);
    Il2CppClass* il2cpp_class_from_name(Il2CppImage* image, const char* namespaze, const char* name);
    Il2CppMethod* il2cpp_class_get_method_from_name(Il2CppClass* klass, const char* name, int argsCount);
    void* il2cpp_method_get_function_pointer(Il2CppMethod* method);  // non-standard; use vtable instead
    Il2CppObject* il2cpp_runtime_invoke(Il2CppMethod* method, void* obj, void** params, void** exc);
}

typedef struct { float x, y, z; } Vec3;

// Camera.WorldToScreenPoint signature: Vec3 (Camera*, Vec3, int eye, MethodInfo*)
// FIX (mc1h Bug5): il2cpp managed methods called directly via methodPointer
// always receive a trailing Il2CppMethodInfo* as the last argument. Omitting
// it shifts every other argument in registers/stack, producing wrong results
// or a crash on the first call. Pass NULL; il2cpp ignores it at runtime for
// icall-backed methods, but the calling convention must be satisfied.
typedef Vec3 (*t_W2S)(void* cam, Vec3 point, int eye, void* method_info);
static t_W2S s_W2S = NULL;

// Transform.get_position — same il2cpp calling convention requirement.
typedef Vec3 (*t_GetPos)(void* transform, void* method_info);
static t_GetPos s_GetPos = NULL;

// ── Helpers ──────────────────────────────────────────────────────────────

static inline void* readPtr(void* obj, size_t off) {
    return obj ? *(void**)((uintptr_t)obj + off) : NULL;
}

#define OFF_HEAD_TRANSFORM  0x540
#define OFF_CAMERA_CONTAINER 0x478

// Get UnityEngine.Transform.position backing (calls the real native getter
// via s_GetPos, resolved in resolveCameraRenderFn() below). Returns the
// FLT_MAX sentinel only if the resolver never found the method — e.g. a
// different Unity/il2cpp build where the method isn't exposed this way.
static Vec3 getTransformPosition(void* transform) {
    if (!transform || !s_GetPos) return (Vec3){FLT_MAX, FLT_MAX, FLT_MAX};
    return s_GetPos(transform, NULL);  // FIX Bug5: trailing MethodInfo* = NULL
}

// ── WorldToScreen resolution ─────────────────────────────────────────────

// Called from Tweak.x per-frame hook after il2cpp init
extern "C" void* resolveCameraRenderFn(uintptr_t base) {
    // Camera.Render (void) — look up via il2cpp metadata
    // We also set s_W2S here as a side effect.
    Il2CppDomain* domain = il2cpp_domain_get();
    if (!domain) return NULL;

    Il2CppAssembly* asm_core = il2cpp_domain_assembly_open(domain, "UnityEngine.CoreModule");
    if (!asm_core) return NULL;

    Il2CppImage* img = il2cpp_assembly_get_image(asm_core);
    if (!img) return NULL;

    Il2CppClass* camClass = il2cpp_class_from_name(img, "UnityEngine", "Camera");
    if (!camClass) return NULL;

    // WorldToScreenPoint(Vector3,Camera.MonoOrStereoscopicEye) — 2 args in some builds,
    // 1 arg (Vector3 only) in others.
    Il2CppMethod* w2s = il2cpp_class_get_method_from_name(camClass, "WorldToScreenPoint", 2);
    if (!w2s) w2s = il2cpp_class_get_method_from_name(camClass, "WorldToScreenPoint", 1);
    if (w2s) {
        // The function pointer is at method->methodPointer in il2cpp MethodInfo
        // MethodInfo layout: +0x00 methodPointer, rest is metadata
        s_W2S = *(t_W2S*)((uintptr_t)w2s + 0x00);
    }

    // Transform.get_position — same lookup pattern as W2S above, resolved
    // here because this is the one place we already have a valid image
    // handle. UnityEngine.Transform lives in the same CoreModule image.
    Il2CppClass* trClass = il2cpp_class_from_name(img, "UnityEngine", "Transform");
    if (trClass) {
        Il2CppMethod* getPos = il2cpp_class_get_method_from_name(trClass, "get_position", 0);
        if (getPos) {
            // UNVERIFIED calling convention: assumed to match the W2S method
            // pointer shape (self-only, no trailing MethodInfo*) because that
            // is what this build's WorldToScreenPoint pointer already uses.
            // Confirm on-device: if ESP boxes render at a fixed wrong spot
            // or crash on the first frame, this assumption is wrong for this
            // build and get_position needs to be re-resolved with a trailing
            // MethodInfo* argument instead.
            s_GetPos = *(t_GetPos*)((uintptr_t)getPos + 0x00);
        } else {
            NSLog(@"[mc1h] WARN: Transform::get_position not found — ESP/AimLock positions will stay invalid");
        }
    } else {
        NSLog(@"[mc1h] WARN: UnityEngine.Transform class not found in CoreModule image");
    }

    // Camera.Render — for per-frame hooking
    Il2CppMethod* renderMethod = il2cpp_class_get_method_from_name(camClass, "Render", 0);
    if (!renderMethod) return NULL;
    return *(void**)((uintptr_t)renderMethod + 0x00);
}

// Active Camera pointer — updated from hook_UnityFrame parameter
// (hook_UnityFrame receives the Camera* as `cam`)
static void* s_activeCamera = NULL;
extern "C" void pg3d_setActiveCamera(void* cam) { s_activeCamera = cam; }

// ── Player list resolution ───────────────────────────────────────────────

// Class 东七丑万下丁丟丗业 token 0x2000DA4, Image 0
// Static field 不万丕丏丟丒上万不 at field index 0
extern "C" void** resolvePlayerList(void) {
    Il2CppDomain* domain = il2cpp_domain_get();
    if (!domain) return NULL;

    // Image 0 = Assembly-CSharp
    Il2CppAssembly* asmCSharp = il2cpp_domain_assembly_open(domain, "Assembly-CSharp");
    if (!asmCSharp) return NULL;
    Il2CppImage* img = il2cpp_assembly_get_image(asmCSharp);
    if (!img) return NULL;

    // The class name is obfuscated Chinese; we look it up by token using
    // il2cpp_class_from_name with empty namespace and the UTF-8 class name.
    // The token 0x2000DA4 gives TypeDef index 0xDA4 - 1 = 0xDA3 = 3491.
    // il2cpp stores classes in an array; we can iterate or use token lookup.
    // Easier: il2cpp_image_get_class(image, index)
    typedef Il2CppClass* (*t_get_class)(Il2CppImage*, uint32_t);
    static t_get_class fn_getClass = NULL;
    if (!fn_getClass) {
        fn_getClass = (t_get_class)dlsym(RTLD_DEFAULT, "il2cpp_image_get_class");
    }
    if (!fn_getClass) return NULL;

    // Type index = (token & 0xFFFFFF) - 1 = 0xDA4 - 1 = 0xDA3 = 3491
    Il2CppClass* cls = fn_getClass(img, 0xDA3);
    if (!cls) return NULL;

    // Get static field data: il2cpp_class_get_static_field_data(class)
    typedef void* (*t_static_data)(Il2CppClass*);
    static t_static_data fn_staticData = NULL;
    if (!fn_staticData) {
        fn_staticData = (t_static_data)dlsym(RTLD_DEFAULT, "il2cpp_class_get_static_field_data");
    }
    if (!fn_staticData) return NULL;

    void* staticData = fn_staticData(cls);
    if (!staticData) return NULL;

    // Field 不万丕丏丟丒上万不 is at static field index 0 → offset 0x0
    return (void**)((uintptr_t)staticData + 0x0);
}

// ── Aim implementation ───────────────────────────────────────────────────

static CGPoint s_lastTargetScreen = {-1,-1};

// FIX: TouchInjector @interface must be declared BEFORE AimHelper uses it.
// Moved forward declaration here, above @implementation AimHelper.
@interface TouchInjector : NSObject
+ (void)applyDelta:(CGVector)delta;
@end

@implementation AimHelper

+ (CGPoint)screenPosForPlayer:(void*)player config:(PG3DConfig*)config {
    if (!player) return CGPointMake(-1,-1);

    // Get head Transform
    void* headTr = readPtr(player, OFF_HEAD_TRANSFORM);
    if (!headTr) return CGPointMake(-1,-1);

    // Get world position
    Vec3 worldPos = getTransformPosition(headTr);
    if (worldPos.x == FLT_MAX) return CGPointMake(-1,-1);  // RESOLVE_AT_RUNTIME

    // If torso mode, offset downward by ~0.3 units
    if (config.aimMode == AimModeTorso) {
        worldPos.y -= 0.3f;
    }

    // Project to screen
    if (!s_W2S || !s_activeCamera) return CGPointMake(-1,-1);
    Vec3 screen = s_W2S(s_activeCamera, worldPos, 0, NULL);  // FIX Bug5: trailing MethodInfo* = NULL
    if (screen.z < 0) return CGPointMake(-1,-1);  // behind camera

    CGSize sz = [UIScreen mainScreen].bounds.size;
    // Unity screen: Y=0 bottom → flip
    return CGPointMake(screen.x, sz.height - screen.y);
}

+ (void)aimAtPlayer:(void*)player
             config:(PG3DConfig*)config
        localPlayer:(void*)localPlayer {
    CGPoint target = [self screenPosForPlayer:player config:config];
    if (target.x < 0) return;

    CGSize sz = [UIScreen mainScreen].bounds.size;
    CGFloat cx = sz.width  * 0.5f;
    CGFloat cy = sz.height * 0.5f;

    CGFloat dx = target.x - cx;
    CGFloat dy = target.y - cy;
    CGFloat dist = sqrtf(dx*dx + dy*dy);

    // Only activate within aim radius
    if (dist > config.aimRadius) return;

    // Smoothing: lerp fraction
    CGFloat t = 1.0f - config.aimSmoothing;
    CGFloat moveDX = dx * t;
    CGFloat moveDY = dy * t;

    // Apply delta to the game's look input.
    // PG3D uses Unity InputSystem or legacy Input.
    // The look delta is consumed by the right-joystick touch handler.
    // We inject it via UIApplication sendEvent with a synthetic touch move.
    //
    // Synthetic touch injection path (safe for Nathanlr):
    //   Find the right-side touch tracking the look joystick,
    //   shift its location by (moveDX, moveDY).
    //
    // This approach hooks UIApplication._touchesEvent and modifies
    // in-flight touch coordinates. See TouchInjector below.

    [TouchInjector applyDelta:CGVectorMake(moveDX, moveDY)];
}

@end

// ── TouchInjector ─────────────────────────────────────────────────────────

// Active look-joystick touch tracking
static UITouch* s_lookTouch = NULL;

// FIX: %hook/%orig/%end are Logos directives — this file must be .xm (not .mm)
// so the Logos preprocessor runs. Extension renamed, Makefile updated.
%hook UIApplication

- (void)sendEvent:(UIEvent*)event {
    if (g_config && g_config.aimEnabled) {
        // Track the rightmost active touch as the look joystick
        for (UITouch* touch in [event allTouches]) {
            if (touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseBegan) {
                CGPoint loc = [touch locationInView:nil];
                CGFloat halfW = [UIScreen mainScreen].bounds.size.width * 0.5f;
                if (loc.x > halfW) {
                    s_lookTouch = touch;
                    break;
                }
            }
        }
    }
    %orig;
}

%end

@implementation TouchInjector

// BUGFIX (mc1h): the previous code used hardcoded +0x28 / +0x30 byte offsets
// into UITouch, labeled "confirmed iOS 15-16 arm64" with no actual check.
// UITouch is a private class; its ivar layout is not ABI-stable across even
// minor point releases, let alone major ones. A wrong offset here doesn't
// just fail silently — it corrupts whatever field actually lives at that
// address in UITouch or in adjacent heap memory, which is exactly the kind
// of "looks plausible, costs hours of debugging" failure flagged in the
// brief. This resolves both ivars by name through the Objective-C runtime
// instead, which is correct on whatever iOS version actually ships UITouch
// with these ivar names (true since UITouch introduced _locationInWindow /
// _previousLocationInWindow; if Apple ever renames them, ivar lookup fails
// closed — returns NULL and we no-op — rather than scribbling blind).
static Ivar s_ivarLoc = NULL;
static Ivar s_ivarPrevLoc = NULL;
static dispatch_once_t s_ivarLookupOnce;
static BOOL s_ivarLookupOK = NO;

static void resolveUITouchIvars(void) {
    dispatch_once(&s_ivarLookupOnce, ^{
        Class uiTouchClass = NSClassFromString(@"UITouch");
        if (!uiTouchClass) {
            NSLog(@"[mc1h] WARN: UITouch class not found — aim touch injection disabled");
            return;
        }
        s_ivarLoc     = class_getInstanceVariable(uiTouchClass, "_locationInWindow");
        s_ivarPrevLoc = class_getInstanceVariable(uiTouchClass, "_previousLocationInWindow");
        if (!s_ivarLoc) {
            NSLog(@"[mc1h] WARN: UITouch._locationInWindow ivar not found on this iOS version — aim touch injection disabled");
            return;
        }
        if (ivar_getTypeEncoding(s_ivarLoc) == NULL ||
            strcmp(ivar_getTypeEncoding(s_ivarLoc), @encode(CGPoint)) != 0) {
            NSLog(@"[mc1h] WARN: UITouch._locationInWindow is not a CGPoint on this iOS version — aim touch injection disabled");
            return;
        }
        s_ivarLookupOK = YES;
        NSLog(@"[mc1h] UITouch ivars resolved: _locationInWindow@+%ld _previousLocationInWindow@+%ld",
              (long)ivar_getOffset(s_ivarLoc),
              s_ivarPrevLoc ? (long)ivar_getOffset(s_ivarPrevLoc) : -1);
    });
}

+ (void)applyDelta:(CGVector)delta {
    // The direct touch-modification approach requires private ivar access to
    // UITouch internals, resolved safely above instead of a hardcoded offset.
    resolveUITouchIvars();
    if (!s_ivarLookupOK) return;

    if (!s_lookTouch) return;
    if (s_lookTouch.phase == UITouchPhaseEnded ||
        s_lookTouch.phase == UITouchPhaseCancelled) {
        s_lookTouch = NULL;
        return;
    }

    void* touchObj = (__bridge void*)s_lookTouch;
    CGPoint* locPtr = (CGPoint*)((uintptr_t)touchObj + ivar_getOffset(s_ivarLoc));
    locPtr->x += delta.dx;
    locPtr->y += delta.dy;

    if (s_ivarPrevLoc) {
        CGPoint* prevPtr = (CGPoint*)((uintptr_t)touchObj + ivar_getOffset(s_ivarPrevLoc));
        *prevPtr = *locPtr;
    }
}

@end
