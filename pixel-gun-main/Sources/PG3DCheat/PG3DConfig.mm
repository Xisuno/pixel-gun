#import "PG3DConfig.h"
#import <objc/runtime.h>
static const void *kSetterKey = &kSetterKey;

static PG3DConfig* s_instance = nil;

@interface PG3DConfig () {
    UIView*  _panel;
    BOOL     _panelVisible;
}
- (void)buildPanel;
- (void)saveSettings;
@end

@implementation PG3DConfig

+ (instancetype)sharedConfig {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s_instance = [[PG3DConfig alloc] init]; });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // defaults
        _masterSwitch  = YES;
        _aimEnabled    = YES;
        _espEnabled    = YES;
        _aimMode       = AimModeHead;
        _aimRadius     = 120.0f;   // px
        _aimSmoothing  = 0.25f;
        _espBoxAlpha   = 0.85f;
        _espShowNick   = YES;
        _espShowDist   = YES;
        _espShowBox    = YES;
        _espShowSnapline = NO;
        _panelVisible  = NO;

        // Restore panel preferences from the previous session.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:@"pg3d.masterSwitch"]) _masterSwitch = [defaults boolForKey:@"pg3d.masterSwitch"];
        if ([defaults objectForKey:@"pg3d.aimEnabled"]) _aimEnabled = [defaults boolForKey:@"pg3d.aimEnabled"];
        if ([defaults objectForKey:@"pg3d.espEnabled"]) _espEnabled = [defaults boolForKey:@"pg3d.espEnabled"];
        if ([defaults objectForKey:@"pg3d.aimMode"]) _aimMode = (AimMode)[defaults integerForKey:@"pg3d.aimMode"];
        if ([defaults objectForKey:@"pg3d.aimRadius"]) _aimRadius = [defaults floatForKey:@"pg3d.aimRadius"];
        if ([defaults objectForKey:@"pg3d.aimSmoothing"]) _aimSmoothing = [defaults floatForKey:@"pg3d.aimSmoothing"];
        if ([defaults objectForKey:@"pg3d.espBoxAlpha"]) _espBoxAlpha = [defaults floatForKey:@"pg3d.espBoxAlpha"];
        if ([defaults objectForKey:@"pg3d.espShowNick"]) _espShowNick = [defaults boolForKey:@"pg3d.espShowNick"];
        if ([defaults objectForKey:@"pg3d.espShowDist"]) _espShowDist = [defaults boolForKey:@"pg3d.espShowDist"];
        if ([defaults objectForKey:@"pg3d.espShowBox"]) _espShowBox = [defaults boolForKey:@"pg3d.espShowBox"];
        if ([defaults objectForKey:@"pg3d.espShowSnapline"]) _espShowSnapline = [defaults boolForKey:@"pg3d.espShowSnapline"];
    }
    return self;
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.masterSwitch forKey:@"pg3d.masterSwitch"];
    [defaults setBool:self.aimEnabled forKey:@"pg3d.aimEnabled"];
    [defaults setBool:self.espEnabled forKey:@"pg3d.espEnabled"];
    [defaults setInteger:self.aimMode forKey:@"pg3d.aimMode"];
    [defaults setFloat:self.aimRadius forKey:@"pg3d.aimRadius"];
    [defaults setFloat:self.aimSmoothing forKey:@"pg3d.aimSmoothing"];
    [defaults setFloat:self.espBoxAlpha forKey:@"pg3d.espBoxAlpha"];
    [defaults setBool:self.espShowNick forKey:@"pg3d.espShowNick"];
    [defaults setBool:self.espShowDist forKey:@"pg3d.espShowDist"];
    [defaults setBool:self.espShowBox forKey:@"pg3d.espShowBox"];
    [defaults setBool:self.espShowSnapline forKey:@"pg3d.espShowSnapline"];
}

- (void)toggleConfigPanel {
    // UIKit views must be created and changed on the main thread.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toggleConfigPanel];
        });
        return;
    }

    if (!_panel || !_panel.superview) {
        _panel = nil;
        [self buildPanel];
    }
    if (!_panel) return;

    _panelVisible = !_panelVisible;
    _panel.hidden = !_panelVisible;
}

// ── Build config panel ──────────────────────────────────────────────────
- (void)buildPanel {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *win = nil;

    // Resolve the foreground game's actual window. Unity may not mark its
    // rendering window as key, so do not rely on app.keyWindow alone.
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.hidden || candidate.alpha <= 0.0 || CGRectIsEmpty(candidate.bounds)) continue;
                if (candidate.isKeyWindow) { win = candidate; break; }
                if (!win) win = candidate;
            }
            if (win) break;
        }
    }
    if (!win) {
        for (UIWindow *candidate in app.windows) {
            if (candidate.hidden || candidate.alpha <= 0.0 || CGRectIsEmpty(candidate.bounds)) continue;
            if (candidate.isKeyWindow) { win = candidate; break; }
            if (!win) win = candidate;
        }
    }

    if (!win) {
        NSLog(@"[mc1h] Config panel: no active game window found");
        return;
    }

    CGFloat W = 292, H = 470;
    CGFloat x = (win.bounds.size.width  - W) * 0.5f;
    CGFloat y = (win.bounds.size.height - H) * 0.5f;

    _panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, W, H)];
    _panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.93];
    _panel.layer.cornerRadius = 12;
    _panel.layer.borderWidth  = 1;
    _panel.layer.borderColor  = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.6].CGColor;
    _panel.hidden = YES;

    // drag gesture
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(handlePan:)];
    [_panel addGestureRecognizer:pan];

    // ── Title ──
    UILabel* title = [self labelWithText:@"PG3D CHEAT  [mc1h]"
                                    font:[UIFont boldSystemFontOfSize:14]
                                   frame:CGRectMake(0, 8, W, 24)];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:1.0];
    [_panel addSubview:title];

    // ── Toggles ──
    CGFloat rowH = 32, startY = 38;

    [self addToggle:@"Master Switch"
             getter:^BOOL{ return self.masterSwitch; }
             setter:^(BOOL v){ self.masterSwitch = v; }
                  y:startY + rowH*0 toView:_panel W:W];

    [self addToggle:@"Aim Assist / AimLock"
             getter:^BOOL{ return self.aimEnabled; }
             setter:^(BOOL v){ self.aimEnabled = v; }
                  y:startY + rowH*1 toView:_panel W:W];

    [self addToggle:@"ESP"
             getter:^BOOL{ return self.espEnabled; }
             setter:^(BOOL v){ self.espEnabled = v; }
                  y:startY + rowH*2 toView:_panel W:W];

    [self addToggle:@"Aim: Head"
             getter:^BOOL{ return self.aimMode == AimModeHead; }
             setter:^(BOOL v){ self.aimMode = v ? AimModeHead : AimModeTorso; }
                  y:startY + rowH*3 toView:_panel W:W];

    [self addToggle:@"ESP Nicks"
             getter:^BOOL{ return self.espShowNick; }
             setter:^(BOOL v){ self.espShowNick = v; }
                  y:startY + rowH*4 toView:_panel W:W];

    [self addToggle:@"ESP Distance"
             getter:^BOOL{ return self.espShowDist; }
             setter:^(BOOL v){ self.espShowDist = v; }
                  y:startY + rowH*5 toView:_panel W:W];

    [self addToggle:@"ESP Box"
             getter:^BOOL{ return self.espShowBox; }
             setter:^(BOOL v){ self.espShowBox = v; }
                  y:startY + rowH*6 toView:_panel W:W];

    [self addToggle:@"ESP Snaplines"
             getter:^BOOL{ return self.espShowSnapline; }
             setter:^(BOOL v){ self.espShowSnapline = v; }
                  y:startY + rowH*7 toView:_panel W:W];

    // ── Sliders ──
    CGFloat sliderY = startY + rowH*8 + 3;

    [self addSlider:@"Aim Radius"
                min:40 max:300 step:1
             getter:^float{ return self.aimRadius; }
             setter:^(float v){ self.aimRadius = v; }
                  y:sliderY toView:_panel W:W];

    [self addSlider:@"Aim Smooth"
                min:0 max:1 step:0.05f
             getter:^float{ return self.aimSmoothing; }
             setter:^(float v){ self.aimSmoothing = v; }
                  y:sliderY + 52 toView:_panel W:W];

    [self addSlider:@"ESP Opacity"
                min:0.1f max:1.0f step:0.05f
             getter:^float{ return self.espBoxAlpha; }
             setter:^(float v){ self.espBoxAlpha = v; }
                  y:sliderY + 104 toView:_panel W:W];

    // ── Close button ──
    UIButton* close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(W - 40, 4, 36, 28);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.tintColor = [UIColor colorWithWhite:0.6 alpha:1];
    [close addTarget:self action:@selector(toggleConfigPanel)
    forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:close];

    [win addSubview:_panel];
    [win bringSubviewToFront:_panel];
}

// ── Helpers ───────────────────────────────────────────────────────────

- (UILabel*)labelWithText:(NSString*)text font:(UIFont*)font frame:(CGRect)frame {
    UILabel* lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.font = font;
    lbl.textColor = [UIColor whiteColor];
    return lbl;
}

typedef BOOL (^BoolGetter)(void);
typedef void (^BoolSetter)(BOOL);
typedef float (^FloatGetter)(void);
typedef void (^FloatSetter)(float);

- (void)addToggle:(NSString*)label
           getter:(BoolGetter)getter
           setter:(BoolSetter)setter
                y:(CGFloat)y
           toView:(UIView*)parent
                W:(CGFloat)W {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 90, 31)];
    lbl.text = label;
    lbl.textColor = UIColor.whiteColor;
    lbl.font = [UIFont systemFontOfSize:14];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(W - 64, y, 51, 31)];
    sw.on = getter ? getter() : NO;

    objc_setAssociatedObject(sw, kSetterKey, setter, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

    [parent addSubview:lbl];
    [parent addSubview:sw];
}

- (void)switchChanged:(UISwitch*)sw {
    BoolSetter cb = objc_getAssociatedObject(sw, kSetterKey);
    if (cb) {
        cb(sw.isOn);
        [self saveSettings];
    }
}

    // Use a block callback via objc associated objects

- (void)addSlider:(NSString*)label
              min:(float)minVal max:(float)maxVal step:(float)step
           getter:(FloatGetter)getter
           setter:(FloatSetter)setter
                y:(CGFloat)y
           toView:(UIView*)parent
                W:(CGFloat)W {
    UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(14, y, W-28, 18)];
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textColor = [UIColor colorWithWhite:0.75 alpha:1];

    NSString* valFmt = (step > 0 && step < 0.1f) ? @"%.2f" : @"%.0f";
    NSString* valStr = [NSString stringWithFormat:valFmt, getter()];
    lbl.text = [NSString stringWithFormat:@"%@ : %@", label, valStr];
    [parent addSubview:lbl];

    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(14, y+18, W-28, 28)];
    sl.minimumValue = minVal;
    sl.maximumValue = maxVal;
    sl.value        = getter();
    sl.minimumTrackTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];

    objc_setAssociatedObject(sl, "sliderSetter", setter, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(sl, "sliderLabel",  lbl,    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(sl, "sliderName",   label,  OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(sl, "sliderStep",   @(step),OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sl];
}

- (void)sliderChanged:(UISlider*)sl {
    FloatSetter setter = objc_getAssociatedObject(sl, "sliderSetter");
    UILabel* lbl       = objc_getAssociatedObject(sl, "sliderLabel");
    NSString* name     = objc_getAssociatedObject(sl, "sliderName");
    NSNumber* step     = objc_getAssociatedObject(sl, "sliderStep");
    if (!lbl || !name) return;

    float v = sl.value;
    if (step) {
        float s = step.floatValue;
        if (s > 0) v = roundf(v / s) * s;
    }
    if (setter) {
        setter(v);
        [self saveSettings];
    }

    NSString* fmt = (step && step.floatValue < 0.1f) ? @"%.2f" : @"%.0f";
    lbl.text = [NSString stringWithFormat:[@"%@ : " stringByAppendingString:fmt], name, v];
}

- (void)handlePan:(UIPanGestureRecognizer*)pan {
    CGPoint delta = [pan translationInView:_panel.superview];
    _panel.center = CGPointMake(_panel.center.x + delta.x, _panel.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:_panel.superview];
}

@end
