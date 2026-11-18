#import "ESPOverlayView.h"
#import "PG3DConfig.h"

extern PG3DConfig* g_config;

@implementation ESPEntry
@end

@interface ESPOverlayView () {
    NSArray<ESPEntry*>* _entries;
}
@end

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _entries = @[];
    }
    return self;
}

- (void)updateEntries:(NSArray<ESPEntry*>*)entries {
    _entries = [entries copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay];
    });
}

- (void)drawRect:(CGRect)rect {
    if (!g_config.espEnabled) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGSize screen = self.bounds.size;
    CGFloat cx = screen.width  * 0.5f;
    CGFloat cy = screen.height * 0.5f;

    // Fonts
    UIFont* nickFont = [UIFont boldSystemFontOfSize:11];
    UIFont* distFont = [UIFont systemFontOfSize:10];

    NSDictionary* nickAttrs = @{
        NSFontAttributeName: nickFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-2)
    };
    NSDictionary* distAttrs = @{
        NSFontAttributeName: distFont,
        NSForegroundColorAttributeName: [UIColor colorWithRed:1 green:0.9 blue:0.3 alpha:1],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-1.5)
    };

    for (ESPEntry* e in _entries) {
        if (!e.valid) continue;

        CGPoint head = e.headScreenPos;
        CGPoint feet = e.feetScreenPos;

        // Flip Y: Unity screen space Y=0 is bottom; UIKit Y=0 is top
        head.y = screen.height - head.y;
        feet.y = screen.height - feet.y;

        // Clamp to visible area
        if (head.x < 0 || head.x > screen.width) continue;
        if (head.y < 0 || head.y > screen.height) continue;

        CGFloat boxH = ABS(feet.y - head.y);
        CGFloat boxW = boxH * 0.55f;  // approximate character aspect
        CGRect  box  = CGRectMake(head.x - boxW*0.5f, head.y, boxW, boxH);

        CGFloat alpha = g_config.espBoxAlpha;

        // ── Box ──
        if (g_config.espShowBox) {
            CGContextSetStrokeColorWithColor(ctx, [[UIColor colorWithRed:1 green:0.15 blue:0.15 alpha:alpha] CGColor]);
            CGContextSetLineWidth(ctx, 1.5f);
            // Corner-style box (4 corners only)
            CGFloat cs = boxW * 0.25f; // corner segment length
            // Top-left
            CGContextMoveToPoint(ctx, box.origin.x, box.origin.y + cs);
            CGContextAddLineToPoint(ctx, box.origin.x, box.origin.y);
            CGContextAddLineToPoint(ctx, box.origin.x + cs, box.origin.y);
            // Top-right
            CGContextMoveToPoint(ctx, CGRectGetMaxX(box) - cs, box.origin.y);
            CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), box.origin.y);
            CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), box.origin.y + cs);
            // Bottom-left
            CGContextMoveToPoint(ctx, box.origin.x, CGRectGetMaxY(box) - cs);
            CGContextAddLineToPoint(ctx, box.origin.x, CGRectGetMaxY(box));
            CGContextAddLineToPoint(ctx, box.origin.x + cs, CGRectGetMaxY(box));
            // Bottom-right
            CGContextMoveToPoint(ctx, CGRectGetMaxX(box) - cs, CGRectGetMaxY(box));
            CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), CGRectGetMaxY(box));
            CGContextAddLineToPoint(ctx, CGRectGetMaxX(box), CGRectGetMaxY(box) - cs);
            CGContextStrokePath(ctx);
        }

        // ── Snapline ──
        if (g_config.espShowSnapline) {
            CGContextSetStrokeColorWithColor(ctx, [[UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:0.5*alpha] CGColor]);
            CGContextSetLineWidth(ctx, 1.0f);
            CGContextMoveToPoint(ctx, cx, screen.height);
            CGContextAddLineToPoint(ctx, head.x, head.y + boxH*0.5f);
            CGContextStrokePath(ctx);
        }

        // ── Nick ──
        if (g_config.espShowNick && e.nick.length) {
            [e.nick drawAtPoint:CGPointMake(head.x - [e.nick sizeWithAttributes:nickAttrs].width*0.5f,
                                             head.y - 14)
                 withAttributes:nickAttrs];
        }

        // ── Distance ──
        if (g_config.espShowDist && e.distanceM > 0) {
            NSString* distStr = [NSString stringWithFormat:@"%.0fm", e.distanceM];
            [distStr drawAtPoint:CGPointMake(head.x - [distStr sizeWithAttributes:distAttrs].width*0.5f,
                                              CGRectGetMaxY(box) + 2)
                  withAttributes:distAttrs];
        }

        // ── Aim radius circle (draw only once, centered) ──
        // Drawn separately — see below
    }

    // ── Aim radius indicator ──
    if (g_config.aimEnabled) {
        CGFloat r = g_config.aimRadius;
        CGContextSetStrokeColorWithColor(ctx, [[UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.35] CGColor]);
        CGContextSetLineWidth(ctx, 1.0f);
        // Dashed
        CGFloat dashes[] = {4, 4};
        CGContextSetLineDash(ctx, 0, dashes, 2);
        CGContextAddEllipseInRect(ctx, CGRectMake(cx-r, cy-r, r*2, r*2));
        CGContextStrokePath(ctx);
        CGContextSetLineDash(ctx, 0, NULL, 0);
    }
}

@end
