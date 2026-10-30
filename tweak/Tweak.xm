#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface MPAVController : NSObject
- (double)currentTime;
- (void)setCurrentTime:(double)time;
- (double)durationOfCurrentItemIfAvailable;
- (float)rate;
- (void)setRate:(float)rate;
- (BOOL)isPlaying;
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

static BOOL sTweakEnabled = YES;

static void loadPreferences() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.noname122021.videocontrolsplus.plist"];
    if (prefs && [prefs objectForKey:@"enabled"]) {
        sTweakEnabled = [[prefs objectForKey:@"enabled"] boolValue];
    } else {
        sTweakEnabled = YES;
    }
}

// Global target speed multiplier chosen by the user for the current session
static float sCurrentTargetRate = 1.0f;
static MPTransportControls *sActiveTransportControls = nil;

// Seek aggregation state
static double sTargetSeekTime = -1.0;
static double sCommittedSeekTime = -1.0;
static NSTimeInterval sLastSeekCommitTime = 0.0;
static NSTimeInterval sLastSeekTapTime = 0.0;
static BOOL sSeekTimerScheduled = NO;
static MPAVController *sPendingSeekPlayer = nil;

@interface VCPSeekDispatcher : NSObject
+ (instancetype)sharedInstance;
- (void)handleSeekDelta:(double)delta withPlayer:(MPAVController *)player;
- (void)flushPendingSeek;
- (void)reset;
@end

@implementation VCPSeekDispatcher

+ (instancetype)sharedInstance {
    static VCPSeekDispatcher *sInstance = nil;
    if (!sInstance) {
        sInstance = [[VCPSeekDispatcher alloc] init];
    }
    return sInstance;
}

- (void)handleSeekDelta:(double)delta withPlayer:(MPAVController *)player {
    if (!player) return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double dur = [player durationOfCurrentItemIfAvailable];

    // If idle (>1.5s since last tap) or uninitialized, start a new seek series from player's current position
    if (sTargetSeekTime < 0.0 || (now - sLastSeekTapTime) > 1.5) {
        sTargetSeekTime = [player currentTime] + delta;
        sCommittedSeekTime = -1.0;
    } else {
        // Tapping in progress: accumulate continuously
        sTargetSeekTime += delta;
    }

    // Clamp within valid video boundaries
    if (sTargetSeekTime < 0.0) sTargetSeekTime = 0.0;
    if (dur > 0.0 && sTargetSeekTime > dur) sTargetSeekTime = dur;

    sLastSeekTapTime = now;
    sPendingSeekPlayer = player;

    NSTimeInterval elapsedSinceCommit = now - sLastSeekCommitTime;

    // Minimum hardware turnaround time (~0.5s) between consecutive seeks on Apple A4/A5
    if (elapsedSinceCommit >= 0.50) {
        // Safe to execute immediately: no in-flight hardware seek lock
        [self dispatchSeekNow];
    } else if (!sSeekTimerScheduled) {
        // Hardware is still demuxing the previous seek: buffer this tap and fire as soon as turnaround finishes
        sSeekTimerScheduled = YES;
        NSTimeInterval remaining = 0.50 - elapsedSinceCommit;
        if (remaining < 0.01) remaining = 0.01;
        [self performSelector:@selector(flushPendingSeek) withObject:nil afterDelay:remaining];
    }
}

- (void)dispatchSeekNow {
    if (sPendingSeekPlayer && sTargetSeekTime >= 0.0) {
        sCommittedSeekTime = sTargetSeekTime;
        sLastSeekCommitTime = [NSDate timeIntervalSinceReferenceDate];
        [sPendingSeekPlayer setCurrentTime:sTargetSeekTime];
    }
}

- (void)flushPendingSeek {
    sSeekTimerScheduled = NO;
    if (sPendingSeekPlayer && sTargetSeekTime >= 0.0) {
        // If user tapped more while hardware was seeking, commit the newly accumulated target immediately
        if (fabs(sTargetSeekTime - sCommittedSeekTime) > 0.01) {
            [self dispatchSeekNow];
        }
    }
}

- (void)reset {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushPendingSeek) object:nil];
    sSeekTimerScheduled = NO;
    sTargetSeekTime = -1.0;
    sCommittedSeekTime = -1.0;
    sLastSeekCommitTime = 0.0;
    sLastSeekTapTime = 0.0;
    sPendingSeekPlayer = nil;
}

@end

static UIImage *loadImageNamed(NSString *name) {
    NSString *base = @"/Library/Application Support/VideoControlsPlus";
    CGFloat scale = [[UIScreen mainScreen] scale];
    if (scale > 1.5f) {
        NSString *path2x = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.png", name]];
        UIImage *raw = [UIImage imageWithContentsOfFile:path2x];
        if (raw) {
            return [UIImage imageWithCGImage:[raw CGImage] scale:2.0f orientation:UIImageOrientationUp];
        }
    }
    NSString *path1x = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", name]];
    return [UIImage imageWithContentsOfFile:path1x];
}

static void loadCustomImagesIfNeeded() {
    if (!sSkipBack10) {
        sSkipBack10 = [loadImageNamed(@"skip_back_10") retain];
        sSkipForward10 = [loadImageNamed(@"skip_forward_10") retain];
        
        sSpeedImages = [[NSMutableDictionary alloc] init];
        NSArray *rates = @[@"0.5x", @"0.75x", @"1x", @"1.25x", @"1.5x", @"2x"];
        for (NSString *r in rates) {
            UIImage *img = loadImageNamed([NSString stringWithFormat:@"speed_%@", r]);
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
    if (sActiveTransportControls && [sActiveTransportControls window]) {
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
    if (sTweakEnabled && rate > 0.0f && sCurrentTargetRate > 0.0f && sCurrentTargetRate != 1.0f) {
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
    [[VCPSeekDispatcher sharedInstance] reset];
    %orig;
    updateSpeedButtonUI();
}

- (void)_itemPlaybackDidEnd:(id)notification {
    sCurrentTargetRate = 1.0f;
    [[VCPSeekDispatcher sharedInstance] reset];
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
    if ([self.player isPlaying]) {
        [self.player setRate:rate];
    }
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

    // Find the enclosing video overlay (MPFullScreenVideoOverlay, MPPadFullScreenVideoOverlay, or MPSwipableView)
    // The overlay has the exact orientation and coordinate system of the rotating video player.
    UIView *container = nil;
    UIView *v = parentView;
    while (v) {
        if ([v isKindOfClass:objc_getClass("MPVideoOverlay")] ||
            [v isKindOfClass:objc_getClass("MPFullScreenVideoOverlay")] ||
            [v isKindOfClass:objc_getClass("MPSwipableView")]) {
            container = v;
            break;
        }
        v = [v superview];
    }
    if (!container) {
        container = [parentView window] ?: [[UIApplication sharedApplication] keyWindow];
    }
    if (!container) return;

    CGRect pFrame = [parentView convertRect:parentView.bounds toView:container];
    CGFloat hudW = 310.0f;
    CGFloat hudH = 40.0f;
    CGFloat hudX = (container.bounds.size.width - hudW) / 2.0f;
    CGFloat hudY;

    if (pFrame.origin.y < container.bounds.size.height / 2.0f) {
        hudY = CGRectGetMaxY(pFrame) + 10.0f;
    } else {
        hudY = pFrame.origin.y - hudH - 10.0f;
    }

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

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (alpha <= 0.05f) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (unsigned long long)_visiblePartsForTransportControlsWithParts:(unsigned long long)parts {
    unsigned long long orig = %orig(parts);
    if (!sTweakEnabled) return orig;
    // ONLY show speed button (part 0x80) in landscape orientation on iPhone!
    // In portrait, do not add 0x80 to prevent the HUD bar from overflowing the screen width.
    int orient = [self interfaceOrientation];
    if (UIInterfaceOrientationIsLandscape(orient)) {
        return orig | 0x80;
    }
    return orig & ~0x80;
}

%end

%hook MPPadFullScreenVideoOverlay

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (alpha <= 0.05f) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (void)setVisibleParts:(unsigned long long)parts animate:(BOOL)animate {
    if (sTweakEnabled) {
        parts |= 0x80;
    }
    %orig(parts, animate);
}

- (void)setDesiredParts:(unsigned long long)parts animate:(BOOL)animate {
    if (sTweakEnabled) {
        parts |= 0x80;
    }
    %orig(parts, animate);
}

%end

%hook MPTransportControls

- (void)dealloc {
    if (sActiveTransportControls == self) {
        sActiveTransportControls = nil;
    }
    %orig;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (!newWindow && sActiveTransportControls == self) {
        sActiveTransportControls = nil;
    }
}

- (void)didMoveToWindow {
    %orig;
    if (isVideoTransport(self)) {
        sActiveTransportControls = self;
    }
}

- (void)_handleTapForPart:(unsigned long long)part {
    if (sTweakEnabled && isVideoTransport(self)) {
        sActiveTransportControls = self;
        if (part == 2) { // Prev -> -10s
            MPAVController *p = [self player];
            [[VCPSeekDispatcher sharedInstance] handleSeekDelta:-10.0 withPlayer:p];
            return;
        }
        if (part == 4) { // Next -> +10s
            MPAVController *p = [self player];
            [[VCPSeekDispatcher sharedInstance] handleSeekDelta:10.0 withPlayer:p];
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
    if (sTweakEnabled && isVideoTransport(self) && (part == 2 || part == 4 || part == 0x80)) {
        return; // block continuous scan seeking
    }
    %orig;
}

- (void)setVisibleParts:(unsigned long long)parts animated:(BOOL)animated {
    if (sTweakEnabled && isVideoTransport(self)) {
        parts |= 0x80;
    }
    %orig(parts, animated);
}

- (void)setVisibleParts:(unsigned long long)parts {
    if (sTweakEnabled && isVideoTransport(self)) {
        parts |= 0x80;
    }
    %orig(parts);
}

- (void)setDesiredParts:(unsigned long long)parts animated:(BOOL)animated {
    if (sTweakEnabled && isVideoTransport(self)) {
        parts |= 0x80;
    }
    %orig(parts, animated);
}

- (void)setDesiredParts:(unsigned long long)parts {
    if (sTweakEnabled && isVideoTransport(self)) {
        parts |= 0x80;
    }
    %orig(parts);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (alpha <= 0.05f) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    if (hidden) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (UIImage *)buttonImageForPart:(unsigned long long)part {
    if (sTweakEnabled && isVideoTransport(self)) {
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

// Explicitly hook MPPadFullScreenTransportControls on iPad because it overrides buttonImageForPart:
%hook MPPadFullScreenTransportControls

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (alpha <= 0.05f) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    if (hidden) {
        [[VCPSpeedHUD sharedHUD] dismissAnimated];
    }
}

- (UIImage *)buttonImageForPart:(unsigned long long)part {
    if (sTweakEnabled) {
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

static void preferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
}

%ctor {
    loadPreferences();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        preferencesChangedCallback,
        CFSTR("com.noname122021.videocontrolsplus/settingschanged"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}
