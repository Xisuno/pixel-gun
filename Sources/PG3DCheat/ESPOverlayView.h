#pragma once
#import <UIKit/UIKit.h>

@interface ESPEntry : NSObject
@property (nonatomic, copy)   NSString* nick;
@property (nonatomic, assign) CGPoint   headScreenPos;   // screen coords
@property (nonatomic, assign) CGPoint   feetScreenPos;
@property (nonatomic, assign) float     distanceM;        // approx metres
@property (nonatomic, assign) BOOL      valid;            // screen-space valid
@end

@interface ESPOverlayView : UIView
- (void)updateEntries:(NSArray<ESPEntry*>*)entries;
@end
