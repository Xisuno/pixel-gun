#import "PG3DConfig.h"
#import <objc/runtime.h>

static PG3DConfig* s_instance = nil;

@interface PG3DConfig () {
    UIView*  _panel;
    BOOL     _panelVisible;
}
- (void)buildPanel;
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
    }
    return self;
}

- (void)toggleConfigPanel {
    if (!_panel) {
        [self buildPanel];
    }
    _panelVisible = !_panelVisible;
    _panel.hidden = !_panelVisible;
}

// ── Build config panel ──────────────────────────────────────────────────
- (void)buildPanel {
    UIWindow* win = [UIApplication sharedApplication].keyWindow;
    CGFloat W = 280, H = 390;
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
    CGFloat rowH = 36, startY = 40;

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

    [self addToggle:@"ESP Snaplines"
             getter:^BOOL{ return self.espShowSnapline; }
             setter:^(BOOL v){ self.espShowSnapline = v; }
                  y:startY + rowH*6 toView:_panel W:W];

    // ── Sliders ──
    CGFloat sliderY = startY + rowH*7 + 4;

    [self addSlider:@"Aim Radius"
                min:40 max:300 step:1
             getter:^float{ return self.aimRadius; }
             setter:^(float v){ self.aimRadius = v; }
                  y:sliderY toView:_panel W:W];

    [self addSlider:@"Aim Smooth"
                min:0 max:1 step:0.05f
             getter:^float{ return self.aimSmoothing; }
             setter:^(float v){ self.aimSmoothing = v; }
                  y:sliderY + 54 toView:_panel W:W];

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
    UILabel* lbl = [self labelWithText:label
                                  font:[UIFont systemFontOfSize:13]
                                 frame:CGRectMake(14, y+8, W-80, 20)];
    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(W-70, y+6, 51, 31)];
    sw.on = getter();
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
    sw.transform = CGAffineTransformMakeScale(0.8, 0.8);

    // Use a block callback via objc associated objects
    objc_setAssociatedObject(sw, "setter", setter, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

    [parent addSubview:lbl];
    [parent addSubview:sw];
}

- (void)switchChanged:(UISwitch*)sw {
    BoolSetter setter = objc_getAssociatedObject(sw, "setter");
    if (setter) setter(sw.on);
}

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

    NSString* valStr = [NSString stringWithFormat:@"%.0f", getter()];
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

    float v = sl.value;
    if (step) {
        float s = step.floatValue;
        if (s > 0) v = roundf(v / s) * s;
    }
    if (setter) setter(v);

    NSString* fmt = (step && step.floatValue < 0.1f) ? @"%.2f" : @"%.0f";
    lbl.text = [NSString stringWithFormat:[@"%@ : " stringByAppendingString:fmt], name, v];
}

- (void)handlePan:(UIPanGestureRecognizer*)pan {
    CGPoint delta = [pan translationInView:_panel.superview];
    _panel.center = CGPointMake(_panel.center.x + delta.x, _panel.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:_panel.superview];
}

@end
