#pragma once
#import <UIKit/UIKit.h>
#import "PG3DConfig.h"

@interface AimHelper : NSObject
// Called per-frame when a target is selected.
// Applies a smoothed touch-delta toward the target's screen position.
+ (void)aimAtPlayer:(void*)player
             config:(PG3DConfig*)config
        localPlayer:(void*)localPlayer;

// Returns screen position of the best aim point on the player
// (head or torso depending on config.aimMode).
// Returns CGPointMake(-1,-1) if off-screen.
+ (CGPoint)screenPosForPlayer:(void*)player
                       config:(PG3DConfig*)config;
@end
