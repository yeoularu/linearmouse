// MIT License
// Copyright (c) 2026 LinearMouse

#import "InstantSpaceSwitch.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import <objc/message.h>
#import <string.h>

// macOS 27's bridge entry point is a local symbol, rather than a dlsym export.
static void *resolveBridge(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)) return NULL;
        const char *name = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation";
        void *found = NULL;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *path = _dyld_get_image_name(i);
            if (!path || ![[NSString stringWithUTF8String:path] hasSuffix:@"/SkyLight"]) continue;
            const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
            if (header->magic != MH_MAGIC_64) return NULL;
            const uint8_t *cursor = (const void *)(header + 1);
            const uint8_t *end = cursor + header->sizeofcmds;
            const struct symtab_command *symbols = NULL;
            const struct segment_command_64 *linkedit = NULL;
            for (uint32_t c = 0; c < header->ncmds; c++) {
                if ((size_t)(end - cursor) < sizeof(struct load_command)) return NULL;
                const struct load_command *command = (const void *)cursor;
                if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return NULL;
                if (command->cmd == LC_SYMTAB && command->cmdsize >= sizeof(struct symtab_command)) symbols = (const void *)command;
                if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
                    const struct segment_command_64 *segment = (const void *)command;
                    if (strncmp(segment->segname, "__LINKEDIT", 16) == 0) linkedit = segment;
                }
                cursor += command->cmdsize;
            }
            if (!symbols || !linkedit) return NULL;
            if (symbols->symoff < linkedit->fileoff || symbols->stroff < linkedit->fileoff ||
                (uint64_t)symbols->symoff + (uint64_t)symbols->nsyms * sizeof(struct nlist_64) > linkedit->fileoff + linkedit->filesize ||
                (uint64_t)symbols->stroff + symbols->strsize > linkedit->fileoff + linkedit->filesize) return NULL;
            uintptr_t base = (uintptr_t)_dyld_get_image_vmaddr_slide(i) + linkedit->vmaddr - linkedit->fileoff;
            const struct nlist_64 *table = (const void *)(base + symbols->symoff);
            const char *strings = (const void *)(base + symbols->stroff);
            for (uint32_t s = 0; s < symbols->nsyms; s++) {
                uint32_t offset = table[s].n_un.n_strx;
                if (offset >= symbols->strsize || !memchr(strings + offset, 0, symbols->strsize - offset)) continue;
                if (strcmp(strings + offset, name) == 0 && table[s].n_value != 0) found = (void *)((uintptr_t)_dyld_get_image_vmaddr_slide(i) + table[s].n_value);
            }
        }
        return found;
    }
}

static BOOL validInitializer(Class cls, SEL selector, BOOL setsSpace) {
    NSMethodSignature *signature = [cls instanceMethodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == (setsSpace ? 4 : 3) &&
        signature.methodReturnType[0] == '@' && [signature getArgumentTypeAtIndex:2][0] == '@' &&
        (!setsSpace || strcmp([signature getArgumentTypeAtIndex:3], @encode(uint64_t)) == 0);
}

@implementation LMInstantSpaceSwitch
+ (void *)library {
    static void *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    });
    return library;
}
+ (void *)bridge {
    if (@available(macOS 27.0, *)) {
        static void *bridge;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ bridge = resolveBridge(); });
        return bridge;
    }
    return NULL;
}
+ (NSArray<NSDictionary *> *)displays {
    void *library = [self library];
    if (!library) return nil;
    int32_t (*connection)(void) = dlsym(library, "SLSMainConnectionID");
    CFArrayRef (*copy)(int32_t, CFArrayRef) = dlsym(library, "SLSCopyManagedDisplaySpaces");
    if (!connection || !copy) return nil;
    return CFBridgingRelease(copy(connection(), NULL));
}
+ (NSNumber *)currentSpaceForDisplay:(NSString *)display {
    void *library = [self library];
    if (!library) return nil;
    int32_t (*connection)(void) = dlsym(library, "SLSMainConnectionID");
    uint64_t (*current)(int32_t, CFStringRef) = dlsym(library, "SLSManagedDisplayGetCurrentSpace");
    if (!connection || !current) return nil;
    uint64_t identifier = current(connection(), (__bridge CFStringRef)display);
    return identifier ? @(identifier) : nil;
}
+ (BOOL)selectionIsCurrent:(NSString *)display target:(uint64_t)target original:(uint64_t)original {
    NSDictionary *record = nil;
    for (NSDictionary *candidate in [self displays]) {
        if ([candidate[@"Display Identifier"] isEqual:display]) { record = candidate; break; }
    }
    NSNumber *current = [self currentSpaceForDisplay:display];
    if (!record || !current || current.unsignedLongLongValue != original ||
        [record[@"Current Space"][@"ManagedSpaceID"] unsignedLongLongValue] != original) return NO;
    for (NSDictionary *space in record[@"Spaces"]) {
        NSNumber *type = space[@"type"];
        if ([space[@"ManagedSpaceID"] unsignedLongLongValue] == target &&
            ([type isEqual:@0] || [type isEqual:@4])) return target != original;
    }
    return NO;
}
+ (BOOL)submitBridgedDisplay:(NSString *)display toSpace:(uint64_t)target fromSpace:(uint64_t)original {
    void (*perform)(id) = [self bridge];
    Class showClass = NSClassFromString(@"SLSBridgedShowSpacesOperation");
    Class setClass = NSClassFromString(@"SLSBridgedManagedDisplaySetCurrentSpaceOperation");
    Class hideClass = NSClassFromString(@"SLSBridgedHideSpacesOperation");
    SEL spacesSelector = NSSelectorFromString(@"initWithSpaces:");
    SEL setSelector = NSSelectorFromString(@"initWithDisplayIdentifier:spaceID:");
    if (!perform || !validInitializer(showClass, spacesSelector, NO) ||
        !validInitializer(hideClass, spacesSelector, NO) || !validInitializer(setClass, setSelector, YES)) return NO;
    id show = ((id (*)(id, SEL, id))objc_msgSend)([showClass alloc], spacesSelector, @[@(target)]);
    id set = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([setClass alloc], setSelector, display, target);
    id hide = ((id (*)(id, SEL, id))objc_msgSend)([hideClass alloc], spacesSelector, @[@(original)]);
    if (!show || !set || !hide) return NO;
    perform(show);
    perform(set);
    perform(hide);
    return YES;
}
+ (BOOL)submitSwitchDisplay:(NSString *)display toSpace:(uint64_t)target fromSpace:(uint64_t)original {
    if (!NSThread.isMainThread || ![self selectionIsCurrent:display target:target original:original]) return NO;
    if (@available(macOS 27.0, *)) {
        return [self submitBridgedDisplay:display toSpace:target fromSpace:original];
    }
    return NO;
}
@end
