#import <UIKit/UIKit.h>
#include <sys/stat.h>
#include <stdlib.h>

@interface PSSpecifier : NSObject
- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface PSViewController : UIViewController
@end

@interface PSListController : PSViewController <UITableViewDelegate, UITableViewDataSource> {
    id _specifiers;
}
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface VideoControlsPlusListController : PSListController
@end

static BOOL isIFileInstalled() {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/iFile.app"];
}

static BOOL isIFileSuidCleared() {
    struct stat st;
    if (stat("/Applications/iFile.app/iFile5", &st) == 0) {
        return (st.st_mode & S_ISUID) == 0;
    }
    if (stat("/Applications/iFile.app/iFile", &st) == 0) {
        return (st.st_mode & S_ISUID) == 0;
    }
    return NO;
}

@implementation VideoControlsPlusListController

- (id)specifiers {
    if (_specifiers == nil) {
        NSMutableArray *specs = [self loadSpecifiersFromPlistName:@"VideoControlsPlus" target:self];
        
        if (!isIFileInstalled()) {
            NSMutableArray *filtered = [NSMutableArray array];
            for (PSSpecifier *spec in specs) {
                NSString *ident = [spec propertyForKey:@"id"];
                if ([ident isEqualToString:@"IFileGroup"] || [ident isEqualToString:@"IFileSwitch"]) {
                    continue;
                }
                [filtered addObject:spec];
            }
            _specifiers = filtered;
        } else {
            _specifiers = specs;
        }
    }
    return _specifiers;
}

- (id)getIFileEnabled:(PSSpecifier *)specifier {
    return @(isIFileSuidCleared());
}

- (void)setIFileEnabled:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enable = [value boolValue];
    if (enable) {
        system("/usr/libexec/vcphelper on");
    } else {
        system("/usr/libexec/vcphelper off");
    }
}

@end
