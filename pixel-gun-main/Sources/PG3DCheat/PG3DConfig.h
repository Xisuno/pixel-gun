#pragma once
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, AimMode) {
    AimModeHead  = 0,
    AimModeTorso = 1,
};

@interface PG3DConfig : NSObject

@property (nonatomic, assign) BOOL   masterSwitch;   // global on/off
@property (nonatomic, assign) BOOL   aimEnabled;      // aim assist / lock
@property (nonatomic, assign) BOOL   espEnabled;      // ESP boxes + nicks
@property (nonatomic, assign) AimMode aimMode;        // Head / Torso
@property (nonatomic, assign) CGFloat aimRadius;      // screen-space fov radius (px)
@property (nonatomic, assign) CGFloat aimSmoothing;   // 0 = instant, 1 = slow
@property (nonatomic, assign) CGFloat espBoxAlpha;    // 0.0 – 1.0
@property (nonatomic, assign) BOOL   espShowNick;
@property (nonatomic, assign) BOOL   espShowDist;
@property (nonatomic, assign) BOOL   espShowBox;
@property (nonatomic, assign) BOOL   espShowSnapline;

+ (instancetype)sharedConfig;
- (void)toggleConfigPanel;

@end
