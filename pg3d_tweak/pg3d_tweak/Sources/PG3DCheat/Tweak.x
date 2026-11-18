/*
 * PG3D Cheat — Tweak.x
 * Target  : Pixel Gun 3D (com.rilisoft.pixelgun3d)
 * Build   : arm64e, iOS 16.6, Nathanlr / NativeRootHide
 * Dump    : Assembly-CSharp — Image 0
 *
 * Key layout from dump (Player_move_c, Token 0x20005A1):
 *   +0x4D0  photonView          → PhotonView
 *   +0x540  PlayerHeadTransform → Transform   (aim target)
 *   +0x1B0  _aimCollider        → Collider
 *   +0x1C0  _headAimCollider    → Collider
 *   +0x260  bodyCollayder       → CapsuleCollider
 *   +0x4A8  nickLabel           → TextMesh
 *   +0x478  myCameraContainer   → Transform
 *   +0x778  世丁丆丛专丝万上丏  → PlayerDamageable
 *
 * Global player list: class 东七丑万下丁丟丗业, static field @ index 0
 *   accessed via il2cpp_field_static_get_value
 *
 * PhotonView::get_isMine  RVA 0x4C29D18
 * PlayerDamageable::IsDead RVA 0x4C53684
 * PlayerDamageable::IsEnemyTo RVA 0x4C53268
 */

#import <substrate.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

#import "il2cpp_helpers.h"
#import "PG3DConfig.h"
#import "ESPOverlayView.h"
#import "AimHelper.h"

// ─────────────────────────────────────────────
//  il2cpp base
// ─────────────────────────────────────────────
static uintptr_t s_il2cppBase = 0;

static uintptr_t getBase(void) {
    if (s_il2cppBase) return s_il2cppBase;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            s_il2cppBase = (uintptr_t)_dyld_get_image_header(i);
            return s_il2cppBase;
        }
    }
    // fallback: main image
    s_il2cppBase = (uintptr_t)_dyld_get_image_header(0);
    return s_il2cppBase;
}

#define RVA(off) ((void*)(getBase() + (off)))

// ─────────────────────────────────────────────
//  Function pointer typedefs (resolved at runtime)
// ─────────────────────────────────────────────
typedef bool  (*t_PhotonView_isMine)(void* self);
typedef bool  (*t_PD_IsDead)(void* self);
typedef bool  (*t_PD_IsEnemyTo)(void* self, void* localPlayer);
typedef void* (*t_Transform_get_position)(void* self);   // returns Vector3*
typedef void* (*t_Camera_WorldToScreenPoint)(void* self, void* vec3); // returns Vector3

static t_PhotonView_isMine  fn_isMine    = NULL;
static t_PD_IsDead          fn_isDead    = NULL;
static t_PD_IsEnemyTo       fn_isEnemyTo = NULL;

// ─────────────────────────────────────────────
//  il2cpp runtime helpers (inlined, no SDK needed)
// ─────────────────────────────────────────────
// Vector3 layout in il2cpp
typedef struct { float x, y, z; } Vec3;

// Read a pointer field from an il2cpp object
static inline void* readPtr(void* obj, size_t off) {
    if (!obj) return NULL;
    return *(void**)((uintptr_t)obj + off);
}
static inline float readFloat(void* obj, size_t off) {
    if (!obj) return 0.0f;
    return *(float*)((uintptr_t)obj + off);
}
static inline bool readBool(void* obj, size_t off) {
    if (!obj) return false;
    return *(bool*)((uintptr_t)obj + off);
}

// il2cpp List<T>:  +0x10 = T* _items (array), +0x18 = int _size
static inline int   listCount(void* list) { return list ? *(int*)((uintptr_t)list + 0x18) : 0; }
static inline void* listItem(void* list, int i) {
    void* arr = readPtr(list, 0x10);
    if (!arr) return NULL;
    // il2cpp array: data starts at +0x20
    return *(void**)((uintptr_t)arr + 0x20 + i * sizeof(void*));
}

// ─────────────────────────────────────────────
//  Offsets inside Player_move_c
// ─────────────────────────────────────────────
#define OFF_PHOTONVIEW          0x4D0
#define OFF_HEAD_TRANSFORM      0x540
#define OFF_AIM_COLLIDER        0x1B0
#define OFF_HEAD_AIM_COLLIDER   0x1C0
#define OFF_BODY_COLLIDER       0x260
#define OFF_NICK_LABEL          0x4A8
#define OFF_CAMERA_CONTAINER    0x478
#define OFF_PLAYER_DAMAGEABLE   0x778

// ─────────────────────────────────────────────
//  Camera / Unity engine helpers via il2cpp
//  We call Camera.main through the managed side
//  using method lookups cached after scene load.
// ─────────────────────────────────────────────

// Cache of active Camera pointer — refreshed each frame via hook
static void* s_mainCamera = NULL;

// WorldToScreenPoint — we call it via a resolved method pointer
// Resolved in: hookUnityFrame
typedef Vec3 (*t_WorldToScreen)(void* cam, Vec3 point, int eye);
static t_WorldToScreen fn_WorldToScreen = NULL;

static Vec3 worldToScreen(Vec3 worldPos) {
    if (!s_mainCamera || !fn_WorldToScreen) return (Vec3){-1,-1,-1};
    return fn_WorldToScreen(s_mainCamera, worldPos, 0 /*mono eye*/);
}

// ─────────────────────────────────────────────
//  Globals  (config accessed from ESPOverlay / AimHelper)
// ─────────────────────────────────────────────
PG3DConfig* g_config = nil;
ESPOverlayView* g_espView = nil;

// Local player pointer (updated each frame)
static void* s_localPlayer = NULL;

// All-player list pointer (class static, resolved once)
static void** s_playerListPtr = NULL;  // pointer to the managed List<Player_move_c>

// ─────────────────────────────────────────────
//  Resolve function pointers once base is known
// ─────────────────────────────────────────────
static void resolveFunctions(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uintptr_t base = getBase();
        fn_isMine    = (t_PhotonView_isMine) (base + 0x4C29D18);
        fn_isDead    = (t_PD_IsDead)         (base + 0x4C53684);
        fn_isEnemyTo = (t_PD_IsEnemyTo)      (base + 0x4C53268);

        // Camera.WorldToScreenPoint — il2cpp internal; find via
        // UnityEngine.Camera::WorldToScreenPoint(Vector3,Camera.MonoOrStereoscopicEye)
        // RVA not in dump; use a name-based lookup from the il2cpp metadata
        // (fallback: iterate known camera transforms manually — see AimHelper)
        // For now we patch the address discovered via il2cpp_resolve_icall
        typedef void* (*t_resolve_icall)(const char*);
        t_resolve_icall resolve_icall = (t_resolve_icall)(base + 0x2C13124); // placeholder
        // Real icall lookup done in hookUnityFrame after il2cpp is fully inited
    });
}

// ─────────────────────────────────────────────
//  Collect enemies each frame
// ─────────────────────────────────────────────
static NSMutableArray* s_enemies = nil;  // array of raw void* Player_move_c

static void collectEnemies(void* localPlayer) {
    [s_enemies removeAllObjects];
    if (!s_playerListPtr || !*s_playerListPtr) return;
    void* list = *s_playerListPtr;
    int count = listCount(list);
    for (int i = 0; i < count; i++) {
        void* p = listItem(list, i);
        if (!p || p == localPlayer) continue;

        void* pv = readPtr(p, OFF_PHOTONVIEW);
        if (pv && fn_isMine && fn_isMine(pv)) continue;  // is local

        void* pd = readPtr(p, OFF_PLAYER_DAMAGEABLE);
        if (pd && fn_isDead && fn_isDead(pd)) continue;  // dead

        [s_enemies addObject:[NSValue valueWithPointer:p]];
    }
}

// ─────────────────────────────────────────────
//  AimLock — snap/pull towards closest enemy head
// ─────────────────────────────────────────────
static void applyAimLock(void* localPlayer) {
    if (!g_config.aimEnabled) return;
    if (!s_enemies.count) return;

    // Screen centre
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat cx = screen.width  * 0.5f;
    CGFloat cy = screen.height * 0.5f;

    void*   bestPlayer    = NULL;
    CGFloat bestDistSq    = g_config.aimRadius * g_config.aimRadius;

    for (NSValue* v in s_enemies) {
        void* p = v.pointerValue;
        void* headTr = readPtr(p, OFF_HEAD_TRANSFORM);
        if (!headTr) continue;

        // Get head world position — Transform.position is a property,
        // but its backing field is at +0x10 for position (il2cpp Vector3 inline)
        // Real path: call get_position via vtable or cached method pointer.
        // Conservative path: read Transform.position backing field directly.
        // In Unity il2cpp, UnityEngine.Transform wraps a native TransformAccess;
        // position is NOT stored inline — we must call the C++ getter.
        // We use a trampoline approach: read from the transform component's
        // native object via UnityEngine_Transform_get_position icall.
        // Placeholder: use the collider position approximation until camera
        // WorldToScreen is verified.
        // *** INTEGRATION GAP — see note in delivery ***

        // Approximation: read CapsuleCollider center world position
        // from the player's root transform (not stored inline; needs icall)
        // This is flagged as UNVERIFIED — see delivery notes.
    }

    if (!bestPlayer) return;

    // Pull / snap logic is applied externally via TouchInjection (see AimHelper.mm)
    [AimHelper aimAtPlayer:bestPlayer
                 config:g_config
           localPlayer:localPlayer];
}

// ─────────────────────────────────────────────
//  ESP — build rects for the overlay
// ─────────────────────────────────────────────
static void updateESP(void) {
    if (!g_config.espEnabled) return;
    NSMutableArray<ESPEntry*>* entries = [NSMutableArray array];

    CGSize screen = [UIScreen mainScreen].bounds.size;

    for (NSValue* v in s_enemies) {
        void* p = v.pointerValue;

        // Nick from TextMesh.text (string*) — il2cpp System.String:
        // +0x10 = int32 length, +0x14 = char16_t chars[]
        void* nickLabel = readPtr(p, OFF_NICK_LABEL);
        NSString* nick = @"?";
        if (nickLabel) {
            void* textStr = readPtr(nickLabel, 0x28); // TextMesh.m_Text offset
            if (textStr) {
                int len = *(int32_t*)((uintptr_t)textStr + 0x10);
                if (len > 0 && len < 32) {
                    unichar buf[32];
                    memcpy(buf, (void*)((uintptr_t)textStr + 0x14), len * 2);
                    nick = [NSString stringWithCharacters:buf length:len];
                }
            }
        }

        // Head screen position
        // See INTEGRATION GAP above — WorldToScreen requires verified icall.
        // ESPEntry will be built once AimHelper has the screen coords.
        ESPEntry* e = [[ESPEntry alloc] init];
        e.nick = nick;
        e.headScreenPos = CGPointZero;   // UNVERIFIED — filled by AimHelper
        e.valid = NO;
        [entries addObject:e];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [g_espView updateEntries:entries];
    });
}

// ─────────────────────────────────────────────
//  Per-frame hook — hooked onto Update or
//  UnityEngine.Camera::Render for timing
// ─────────────────────────────────────────────

// Hook on UnityEngine.Camera.Render (called once per frame per camera)
// RVA not in dump — resolved via il2cpp_resolve_icall("UnityEngine.Camera::Render()")
// We instead hook the managed Update of a convenient MonoBehaviour.
// Best target: Player_move_c.Update or InGameGUI.Update.
// Using MSHookFunction on the native function pointer looked up at runtime.

static void (*orig_UnityFrame)(void* cam) = NULL;

static void hook_UnityFrame(void* cam) {
    orig_UnityFrame(cam);

    if (!g_config.masterSwitch) return;

    // Resolve player list once
    static dispatch_once_t resolvedList;
    dispatch_once(&resolvedList, ^{
        // The class 东七丑万下丁丟丗业 holds a static List<Player_move_c> at field index 0.
        // We locate it via il2cpp metadata at runtime.
        // Approach: scan for the class by token 0x2000DA4 in Image 0,
        // then get_static_field_data() for the List pointer.
        // This is done in il2cpp_helpers.mm — see resolvePlayerList().
        s_playerListPtr = resolvePlayerList();
        if (!s_playerListPtr) {
            NSLog(@"[mc1h] WARN: playerListPtr not resolved");
        }
    });

    // Find local player
    s_localPlayer = NULL;
    if (s_playerListPtr && *s_playerListPtr) {
        void* list = *s_playerListPtr;
        int count = listCount(list);
        for (int i = 0; i < count; i++) {
            void* p = listItem(list, i);
            if (!p) continue;
            void* pv = readPtr(p, OFF_PHOTONVIEW);
            if (pv && fn_isMine && fn_isMine(pv)) {
                s_localPlayer = p;
                break;
            }
        }
    }

    if (!s_localPlayer) return;

    collectEnemies(s_localPlayer);
    applyAimLock(s_localPlayer);
    updateESP();
}

// ─────────────────────────────────────────────
//  Anti-cheat bypass hooks
// ─────────────────────────────────────────────

/*
 * PG3D on iOS uses Firebase AppCheck + Apple AppAttest for device attestation.
 * The flow:
 *   1. App calls AppCheck.getToken() → Apple AppAttest verifies device integrity
 *   2. Token sent to Rilisoft server as part of session auth
 *   3. If token is invalid/missing → CheatDetectedBanner shown
 *
 * Nathanlr + NativeRootHide already handles the jailbreak detection layer.
 * The remaining risk: AppAttest itself fails on jailbroken devices unless
 * the AppAttest API is spoofed or the game's fallback path is taken.
 *
 * Strategy:
 *   A) Hook the DeviceAttestation manager (class 万丈专丆丗上丆丐丅, token 0x20039F3)
 *      method 丏丒世一丒下七业丝 (get_IsReady) to always return true,
 *      and 丛万与三丛世丛丁丅 (get_Token) to return a cached/static non-null string.
 *      This makes the game skip the "token denied" branch.
 *
 *   B) Hook CheatDetectedBanner's show trigger
 *      (与与不丈与东丛下丂 at RVA 0x5062AF0) to no-op it.
 *
 *   C) Hook the Firebase AppCheck provider's IAppCheckProviderFactory result
 *      to return a stub token (see AppCheckBypass.mm).
 *
 * Note: server-side validation of the token hash may still trigger a ban
 * if the server validates token signatures cryptographically.
 * The hooks below prevent the CLIENT from showing the ban UI and from
 * entering the "cheat detected" state; server-side is a separate concern.
 */

// Hook A: DeviceAttestation manager — IsAvailable always true
static bool (*orig_DA_IsAvailable)(void* self) = NULL;
static bool hook_DA_IsAvailable(void* self) {
    return true;
}

// Hook A2: DeviceAttestation manager — IsDenied always false
static bool (*orig_DA_IsDenied)(void* self) = NULL;
static bool hook_DA_IsDenied(void* self) {
    return false;
}

// Hook B: CheatDetectedBanner::与与不丈与东丛下丂 (static show method)
// RVA 0x5062AF0
static void (*orig_CheatBanner_Show)(void) = NULL;
static void hook_CheatBanner_Show(void) {
    NSLog(@"[mc1h] CheatDetectedBanner::Show suppressed");
    // no-op
}

// Hook C: 丆与下世丌东丘丆丟::丘丛万业丈丈专上丂 (IsJailbroken check)
// RVA 0x470DBC8
static bool (*orig_IsJailbroken)(void) = NULL;
static bool hook_IsJailbroken(void) {
    return false;
}

// ─────────────────────────────────────────────
//  Logos hooks — UIWindow for overlay injection
// ─────────────────────────────────────────────

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // Setup config
            g_config = [PG3DConfig sharedConfig];

            // Setup ESP overlay
            g_espView = [[ESPOverlayView alloc] initWithFrame:self.bounds];
            g_espView.userInteractionEnabled = NO;
            [self addSubview:g_espView];
            [self bringSubviewToFront:g_espView];

            // Setup config UI (floating button)
            UIButton* configBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            configBtn.frame = CGRectMake(10, 80, 44, 44);
            configBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
            configBtn.layer.cornerRadius = 8;
            [configBtn setTitle:@"⚙" forState:UIControlStateNormal];
            [configBtn.titleLabel setFont:[UIFont systemFontOfSize:22]];
            [configBtn addTarget:g_config
                          action:@selector(toggleConfigPanel)
                forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:configBtn];
            [self bringSubviewToFront:configBtn];

            NSLog(@"[mc1h] PG3D overlay injected");
        });
    });
}

%end

// ─────────────────────────────────────────────
//  Constructor — hook installation
// ─────────────────────────────────────────────

%ctor {
    NSLog(@"[mc1h] PG3D Cheat loading...");

    s_enemies = [NSMutableArray array];

    // Wait for UnityFramework to be loaded before resolving RVAs
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uintptr_t base = getBase();
        if (!base) {
            NSLog(@"[mc1h] ERROR: could not find image base");
            return;
        }
        NSLog(@"[mc1h] image base = 0x%lx", base);

        resolveFunctions();

        // Hook anti-cheat functions
        MSHookFunction(RVA(0x5062AF0),
                       (void*)hook_CheatBanner_Show,
                       (void**)&orig_CheatBanner_Show);

        MSHookFunction(RVA(0x470DBC8),
                       (void*)hook_IsJailbroken,
                       (void**)&orig_IsJailbroken);

        // DeviceAttestation hooks — 万丈专丆丗上丆丐丅
        // 丘不东丕万丅下丞下 = IsAvailable RVA 0x470DED4
        MSHookFunction(RVA(0x470DED4),
                       (void*)hook_DA_IsAvailable,
                       (void**)&orig_DA_IsAvailable);

        // 下七丛丘专且丏丞世 = IsDenied RVA 0x470DF2C
        MSHookFunction(RVA(0x470DF2C),
                       (void*)hook_DA_IsDenied,
                       (void**)&orig_DA_IsDenied);

        // Per-frame hook — hook Camera.Render for consistent timing
        // Camera.Render il2cpp icall resolved at runtime in il2cpp_helpers
        void* cameraRenderFn = resolveCameraRenderFn(base);
        if (cameraRenderFn) {
            MSHookFunction(cameraRenderFn,
                           (void*)hook_UnityFrame,
                           (void**)&orig_UnityFrame);
            NSLog(@"[mc1h] Camera.Render hooked at %p", cameraRenderFn);
        } else {
            NSLog(@"[mc1h] WARN: Camera.Render not found — per-frame hook inactive");
        }

        NSLog(@"[mc1h] all hooks installed");
    });
}
