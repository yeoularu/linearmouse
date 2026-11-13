// MIT License
// Copyright (c) 2026 LinearMouse

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Private SkyLight space switch. Missing symbols and rejected requests return NO.
@interface LMInstantSpaceSwitch : NSObject
+ (nullable NSArray<NSDictionary *> *)displays;
+ (BOOL)submitSwitchDisplay:(NSString *)display
                    toSpace:(uint64_t)target
                  fromSpace:(uint64_t)original;
@end

NS_ASSUME_NONNULL_END
