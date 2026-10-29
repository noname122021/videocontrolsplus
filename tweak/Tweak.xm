#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface MPAVController : NSObject
- (double)currentTime;
- (void)setCurrentTime:(double)time;
- (double)durationOfCurrentItemIfAvailable;
- (float)rate;
- (void)setRate:(float)rate;
@end

@interface MPAVItem : NSObject
- (BOOL)isVideo;
@end

@interface MPTransportControls : UIView
- (MPAVController *)player;
- (MPAVItem *)item;
- (UIButton *)buttonForPart:(unsigned long long)part;
- (void)_updateButtonImageForPart:(unsigned long long)part;
- (UIImage *)buttonImageForPart:(unsigned long long)part;
@end

@interface MPFullScreenVideoOverlay : UIView
- (int)interfaceOrientation;
@end

@interface MPInlineTransportControls : MPTransportControls
@end

@interface MPFullScreenTransportControls : MPTransportControls
@end

@interface MPPadFullScreenTransportControls : MPTransportControls
@end

static UIImage *sSkipBack10 = nil;
static UIImage *sSkipForward10 = nil;
static NSMutableDictionary *sSpeedImages = nil;

// Global target speed multiplier chosen by the user for the current session
static float sCurrentTargetRate = 1.0f;
static MPTransportControls *sActiveTransportControls = nil;

static void loadCustomImagesIfNeeded() {
    if (!sSkipBack10) {
        NSString *base = @"/Library/Application Support/VideoControlsPlus";
        sSkipBack10 = [[UIImage alloc] initWithContentsOfFile:[base stringByAppendingPathComponent:@"skip_back_10@2x.png"]];
        sSkipForward10 = [[UIImage alloc] initWithContentsOfFile:[base stringByAppendingPathComponent:@"skip_forward_10@2x.png"]];
        
        sSpeedImages = [[NSMutableDictionary alloc] init];
        NSArray *rates = @[@"0.5x", @"0.75x", @"1x", @"1.25x", @"1.5x", @"2x"];
        for (NSString *r in rates) {
            NSString *p = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"speed_%@@2x.png", r]];
            UIImage *img = [[UIImage alloc] initWithContentsOfFile:p];
            if (img) [sSpeedImages setObject:img forKey:r];
        }
    }
}

static UIImage *speedImageForRate(float rate) {
    loadCustomImagesIfNeeded();
    NSString *key = @"1x";
    if (rate >= 0.40f && rate <= 0.60f) key = @"0.5x";
    else if (rate >= 0.70f && rate <= 0.80f) key = @"0.75x";
    else if (rate >= 0.95f && rate <= 1.05f) key = @"1x";
    else if (rate >= 1.20f && rate <= 1.30f) key = @"1.25x";
    else if (rate >= 1.45f && rate <= 1.55f) key = @"1.5x";
    else if (rate >= 1.95f && rate <= 2.05f) key = @"2x";
    return [sSpeedImages objectForKey:key] ?: [sSpeedImages objectForKey:@"1x"];
}

static BOOL isVideoTransport(MPTransportControls *self) {
    if ([self isKindOfClass:objc_getClass("MPInlineTransportControls")] ||
        [self isKindOfClass:objc_getClass("MPFullScreenTransportControls")] ||
        [self isKindOfClass:objc_getClass("MPPadFullScreenTransportControls")]) {
        return YES;
    }
    MPAVItem *item = [self item];
    if (item && [item respondsToSelector:@selector(isVideo)] && [item isVideo]) {
        return YES;
    }
    return NO;
}

static void updateSpeedButtonUI() {
    if (sActiveTransportControls) {
        UIButton *btn = [sActiveTransportControls buttonForPart:0x80];
        if (btn) {
            UIImage *newImg = speedImageForRate(sCurrentTargetRate);
            [btn setImage:newImg forState:UIControlStateNormal];
        }
        if ([sActiveTransportControls respondsToSelector:@selector(_updateButtonImageForPart:)]) {
            [sActiveTransportControls _updateButtonImageForPart:0x80];
        }
    }
}

// Hook AVPlayer setRate: to preserve custom speed during pause, seek, and scrub
%hook AVPlayer

- (void)setRate:(float)rate {
    if (rate > 0.0f && sCurrentTargetRate > 0.0f && sCurrentTargetRate != 1.0f) {
        %orig(sCurrentTargetRate);
    } else {
        %orig(rate);
    }
}

%end

// Reset speed when an item changes or ends
%hook MPAVController

- (void)_itemDidChange:(id)item {
    sCurrentTargetRate = 1.0f;
    %orig;
    updateSpeedButtonUI();
}

- (void)_itemPlaybackDidEnd:(id)notification {
    sCurrentTargetRate = 1.0f;
    %orig;
    updateSpeedButtonUI();
}

%end

@interface VCPSpeedHUD : UIView
@property (nonatomic, assign) MPAVController *player;
@property (nonatomic, retain) UISegmentedControl *segmentedControl;
+ (instancetype)sharedHUD;
- (void)toggleInView:(UIView *)parentView withPlayer:(MPAVController *)player;
- (void)dismissAnimated;
@end

@implementation VCPSpeedHUD

+ (instancetype)sharedHUD {
    static VCPSpeedHUD *sHUD = nil;
    if (!sHUD) {
        sHUD = [[VCPSpeedHUD alloc] initWithFrame:CGRectMake(0, 0, 310, 40)];
    }
    return sHUD;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.75f];
        self.layer.cornerRadius = 8.0f;
        self.layer.borderColor = [[UIColor colorWithWhite:1.0f alpha:0.25f] CGColor];
        self.layer.borderWidth = 1.0f;
        self.layer.masksToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;

        NSArray *items = @[@"0.5x", @"0.75x", @"1x", @"1.25x", @"1.5x", @"2x"];
        _segmentedControl = [[UISegmentedControl alloc] initWithItems:items];
        _segmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
        _segmentedControl.tintColor = [UIColor darkGrayColor];
        _segmentedControl.frame = CGRectMake(5, 5, frame.size.width - 10, frame.size.height - 10);
        _segmentedControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_segmentedControl addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_segmentedControl];
    }
    return self;
}

- (void)speedChanged:(UISegmentedControl *)sender {
    if (!self.player) return;
    float rate = 1.0f;
    switch (sender.selectedSegmentIndex) {
        case 0: rate = 0.5f; break;
        case 1: rate = 0.75f; break;
        case 2: rate = 1.0f; break;
        case 3: rate = 1.25f; break;
        case 4: rate = 1.5f; break;
        case 5: rate = 2.0f; break;
    }
    sCurrentTargetRate = rate;
    [self.player setRate:rate];
    updateSpeedButtonUI();

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissAnimated) object:nil];
    [self performSelector:@selector(dismissAnimated) withObject:nil afterDelay:0.3];
}

- (void)updateSelectedIndex {
    int idx = 2; // default 1x
    if (sCurrentTargetRate >= 0.40f && sCurrentTargetRate <= 0.60f) idx = 0;
    else if (sCurrentTargetRate >= 0.70f && sCurrentTargetRate <= 0.80f) idx = 1;
    else if (sCurrentTargetRate >= 0.95f && sCurrentTargetRate <= 1.05f) idx = 2;
    else if (sCurrentTargetRate >= 1.20f && sCurrentTargetRate <= 1.30f) idx = 3;
    else if (sCurrentTargetRate >= 1.45f && sCurrentTargetRate <= 1.55f) idx = 4;
    else if (sCurrentTargetRate >= 1.95f && sCurrentTargetRate <= 2.05f) idx = 5;
    _segmentedControl.selectedSegmentIndex = idx;
}

- (void)toggleInView:(UIView *)parentView withPlayer:(MPAVController *)player {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissAnimated) object:nil];
    if (self.superview && self.alpha > 0.0f) {
        [self dismissAnimated];
        return;
    }

    self.player = player;
    [self updateSelectedIndex];

    // Position above parentView (usually MPTransportControls at the bottom)
    UIView *container = [parentView superview] ?: parentView;
    CGRect pFrame = [parentView convertRect:parentView.bounds toView:container];
    CGFloat hudW = 310.0f;
    CGFloat hudH = 40.0f;
    CGFloat hudX = (container.bounds.size.width - hudW) / 2.0f;
    CGFloat hudY = pFrame.origin.y - hudH - 8.0f;

    self.frame = CGRectMake(hudX, hudY, hudW, hudH);
    self.alpha = 0.0f;
    [container addSubview:self];

    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1.0f;
    }];

    // Auto dismiss after 4 seconds of inactivity
    [self performSelector:@selector(dismissAnimated) withObject:nil afterDelay:4.0];
}

- (void)dismissAnimated {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissAnimated) object:nil];
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0.0f;
    } completion:^(BOOL finished) {
        if (self.alpha == 0.0f) {
            [self removeFromSuperview];
        }
    }];
}

@end

%hook MPFullScreenVideoOverlay

- (unsigned long long)_visiblePartsForTransportControlsWithParts:(unsigned long long)parts {
    unsigned long long orig = %orig(parts);
    // ONLY show speed button (part 0x80) in landscape orientation!
    // In portrait, do not add 0x80 to prevent the HUD bar from overflowing the screen width.
    int orient = [self interfaceOrientation];
    if (UIInterfaceOrientationIsLandscape(orient)) {
        return orig | 0x80;
    }
    return orig & ~0x80;
}

%end

%hook MPTransportControls

- (void)didMoveToWindow {
    %orig;
    if (isVideoTransport(self)) {
        sActiveTransportControls = self;
    }
}

- (void)_handleTapForPart:(unsigned long long)part {
    if (isVideoTransport(self)) {
        sActiveTransportControls = self;
        if (part == 2) { // Prev -> -10s
            MPAVController *p = [self player];
            double t = [p currentTime] - 10.0;
            [p setCurrentTime:(t > 0.0 ? t : 0.0)];
            return;
        }
        if (part == 4) { // Next -> +10s
            MPAVController *p = [self player];
            double t = [p currentTime] + 10.0;
            double dur = [p durationOfCurrentItemIfAvailable];
            if (dur > 0.0 && t > dur) t = dur;
            [p setCurrentTime:t];
            return;
        }
        if (part == 0x80) { // Bookmark button in landscape -> Speed Selector HUD
            MPAVController *p = [self player];
            [[VCPSpeedHUD sharedHUD] toggleInView:self withPlayer:p];
            return;
        }
    }
    %orig;
}

- (void)_handleHoldForPart:(unsigned long long)part {
    if (isVideoTransport(self) && (part == 2 || part == 4 || part == 0x80)) {
        return; // block continuous scan seeking
    }
    %orig;
}

- (UIImage *)buttonImageForPart:(unsigned long long)part {
    if (isVideoTransport(self)) {
        loadCustomImagesIfNeeded();
        if (part == 2 && sSkipBack10) {
            return sSkipBack10;
        }
        if (part == 4 && sSkipForward10) {
            return sSkipForward10;
        }
        if (part == 0x80) {
            return speedImageForRate(sCurrentTargetRate);
        }
    }
    return %orig;
}

%end
