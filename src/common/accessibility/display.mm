#include "display.h"
#include "../misc/assert.h"

#include <Cocoa/Cocoa.h>

#define internal static
#define CGSDefaultConnection _CGSDefaultConnection()
typedef int CGSConnectionID;

extern "C" CGSConnectionID _CGSDefaultConnection(void);

extern "C" CGSSpaceType CGSSpaceGetType(CGSConnectionID Connection, CGSSpaceID Id);
extern "C" CFArrayRef CGSCopyManagedDisplaySpaces(const CGSConnectionID Connection);
extern "C" CFArrayRef CGSCopySpacesForWindows(CGSConnectionID Connection, CGSSpaceSelector Type, CFArrayRef Windows);
extern "C" CGSSpaceID CGSManagedDisplayGetCurrentSpace(CGSConnectionID Connection, CFStringRef DisplayRef);
extern "C" CFStringRef CGSCopyManagedDisplayForSpace(const CGSConnectionID Connection, CGSSpaceID Space);

/* NOTE(koekeishiya): Find the UUID associated with a CGDirectDisplayID. */
internal CFStringRef
AXLibDisplayIdentifier(CGDirectDisplayID Id)
{
    CFUUIDRef UUIDRef = CGDisplayCreateUUIDFromDisplayID(Id);
    if(UUIDRef)
    {
        CFStringRef Ref = CFUUIDCreateString(NULL, UUIDRef);
        CFRelease(UUIDRef);
        return Ref;
    }

    return NULL;
}

/* NOTE(koekeishiya): Caller is responsible for calling 'AXLibDestroyDisplay()'. */
macos_display *AXLibConstructDisplay(CGDirectDisplayID Id, unsigned Arrangement)
{
    macos_display *Display = (macos_display *) malloc(sizeof(macos_display));

    Display->Ref = AXLibDisplayIdentifier(Id);
    Display->Id = Id;
    Display->Arrangement = Arrangement;

    CGRect Frame = CGDisplayBounds(Id);

    Display->X = Frame.origin.x;
    Display->Y = Frame.origin.y;

    Display->Width = Frame.size.width;
    Display->Height = Frame.size.height;

    return Display;
}

/* NOTE(koekeishiya): Caller is responsible for passing a valid display! */
void AXLibDestroyDisplay(macos_display *Display)
{
    ASSERT(Display && Display->Ref);

    CFRelease(Display->Ref);
    free(Display);
}

/* NOTE(koekeishiya): Caller is responsible for all memory (list and entries). */
#define MAX_DISPLAY_COUNT 10
macos_display **AXLibDisplayList(unsigned *Count)
{
    CGDirectDisplayID *CGDisplayList =
        (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MAX_DISPLAY_COUNT);

    *Count = 0;
    CGGetActiveDisplayList(MAX_DISPLAY_COUNT, CGDisplayList, Count);

    macos_display **DisplayList =
        (macos_display **) malloc(*Count * sizeof(macos_display *));

    for(size_t Index = 0;
        Index < *Count;
        ++Index)
    {
        CGDirectDisplayID Id = CGDisplayList[Index];
        DisplayList[Index] = AXLibConstructDisplay(Id, Index);
    }

    free(CGDisplayList);
    return DisplayList;
}

CGRect AXLibGetDisplayBounds(CFStringRef DisplayRef)
{
    CGRect Result = {};

    CGDirectDisplayID *CGDisplayList =
        (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MAX_DISPLAY_COUNT);

    unsigned Count = 0;
    CGGetActiveDisplayList(MAX_DISPLAY_COUNT, CGDisplayList, &Count);

    for(size_t Index = 0;
        Index < Count;
        ++Index)
    {
        CGDirectDisplayID Id = CGDisplayList[Index];
        CFStringRef UUID = AXLibDisplayIdentifier(Id);
        if(UUID)
        {
            if(CFStringCompare(DisplayRef, UUID, 0) == kCFCompareEqualTo)
            {
                Result = CGDisplayBounds(Id);
                CFRelease(UUID);
                break;
            }
            else
            {
                CFRelease(UUID);
            }
        }
    }

    free(CGDisplayList);
    return Result;
}

/* NOTE(koekeishiya): Caller is responsible for calling CFRelease. */
CFStringRef AXLibGetDisplayIdentifierFromSpace(CGSSpaceID Space)
{
    return CGSCopyManagedDisplayForSpace(CGSDefaultConnection, Space);
}


internal CGSSpaceID
AXLibActiveSpaceIdentifier(CFStringRef DisplayRef, CFStringRef *SpaceRef)
{
    CGSSpaceID ActiveSpaceId = 0;
    NSString *CurrentIdentifier = (__bridge NSString *) DisplayRef;

    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *) DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            *SpaceRef = (__bridge CFStringRef) [[NSString alloc] initWithString:DisplayDictionary[@"Current Space"][@"uuid"]];
            ActiveSpaceId = [DisplayDictionary[@"Current Space"][@"id64"] intValue];
            break;
        }
    }

    CFRelease(DisplayDictionaries);
    return ActiveSpaceId;
}

internal macos_space *
AXLibConstructSpace(CFStringRef Ref, CGSSpaceID Id, CGSSpaceType Type)
{
    macos_space *Space = (macos_space *) malloc(sizeof(macos_space));

    Space->Ref = Ref;
    Space->Id = Id;
    Space->Type = Type;

    return Space;
}

CGSSpaceID AXLibActiveCGSSpaceID(CFStringRef DisplayRef)
{
    return CGSManagedDisplayGetCurrentSpace(CGSDefaultConnection, DisplayRef);
}

/* NOTE(koekeishiya): Returns a macos_space representing the active space
for the given display. Caller is responsible for calling 'AXLibDestroySpace()'. */
macos_space *AXLibActiveSpace(CFStringRef DisplayRef)
{
    ASSERT(DisplayRef);

    CFStringRef SpaceRef;
    CGSSpaceID SpaceId = AXLibActiveSpaceIdentifier(DisplayRef, &SpaceRef);
    CGSSpaceType SpaceType = CGSSpaceGetType(CGSDefaultConnection, SpaceId);

    macos_space *Space = AXLibConstructSpace(SpaceRef, SpaceId, SpaceType);
    return Space;
}

/* NOTE(koekeishiya): Construct a macos_space representing the active space for the
 * display that currently holds the window that accepts key-input.
 * Caller is responsible for calling 'AXLibDestroySpace()'. */
bool AXLibActiveSpace(macos_space **Space)
{
    bool Result = false;

    NSDictionary *ScreenDictionary = [[NSScreen mainScreen] deviceDescription];
    NSNumber *ScreenID = [ScreenDictionary objectForKey:@"NSScreenNumber"];
    CGDirectDisplayID DisplayID = [ScreenID unsignedIntValue];

    CFUUIDRef DisplayUUID = CGDisplayCreateUUIDFromDisplayID(DisplayID);
    if(DisplayUUID)
    {
        CFStringRef Identifier = CFUUIDCreateString(NULL, DisplayUUID);
        *Space = AXLibActiveSpace(Identifier);

        CFRelease(DisplayUUID);
        CFRelease(Identifier);

        Result = true;
    }

    return Result;
}

/* NOTE(koekeishiya): Caller is responsible for passing a valid space! */
void AXLibDestroySpace(macos_space *Space)
{
    ASSERT(Space && Space->Ref);

    CFRelease(Space->Ref);
    free(Space);
}

/* NOTE(koekeishiya): Translate a CGSSpaceID to the index shown in mission control. Also
 * assign the arrangement index of the display that the space belongs to.
 *
 * It is safe to pass NULL for OutArrangement and OutDesktopId in case this information
 * is not of importance to the caller.
 *
 * The function returns a bool specifying if the CGSSpaceID was properly translated. */
bool AXLibCGSSpaceIDToDesktopID(CGSSpaceID SpaceId, unsigned *OutArrangement, unsigned *OutDesktopId)
{
    bool Result = false;
    unsigned Arrangement = 0;
    unsigned DesktopId = 0;

    unsigned SpaceIndex = 1;
    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *) ScreenDictionaries)
    {
        NSArray *SpaceDictionaries = ScreenDictionary[@"Spaces"];
        for(NSDictionary *SpaceDictionary in (__bridge NSArray *) SpaceDictionaries)
        {
            if(SpaceId == [SpaceDictionary[@"id64"] intValue])
            {
                DesktopId = SpaceIndex;
                Result = true;
                goto End;
            }

            ++SpaceIndex;
        }

        ++Arrangement;
    }

End:
    if(OutArrangement)
    {
        *OutArrangement = Arrangement;
    }

    if(OutDesktopId)
    {
        *OutDesktopId = DesktopId;
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

/* NOTE(koekeishiya): Translate the space index shown in mission control to a CGSSpaceID.
 * Also assign the arrangement index of the display that the space belongs to.
 *
 * It is safe to pass NULL for OutArrangement and OutSpaceId in case this information
 * is not of importance to the caller.
 *
 * The function returns a bool specifying if the index was properly translated. */
bool AXLibCGSSpaceIDFromDesktopID(unsigned DesktopId, unsigned *OutArrangement, CGSSpaceID *OutSpaceId)
{
    bool Result = false;
    CGSSpaceID SpaceId = 0;
    unsigned Arrangement = 0;
    unsigned SpaceIndex = 1;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *) ScreenDictionaries)
    {
        NSArray *SpaceDictionaries = ScreenDictionary[@"Spaces"];
        for(NSDictionary *SpaceDictionary in (__bridge NSArray *) SpaceDictionaries)
        {
            if(SpaceIndex == DesktopId)
            {
                SpaceId = [SpaceDictionary[@"id64"] intValue];
                Result = true;
                goto End;
            }
            ++SpaceIndex;
        }

        ++Arrangement;
    }

End:
    if(OutArrangement)
    {
        *OutArrangement = Arrangement;
    }

    if(OutSpaceId)
    {
        *OutSpaceId = SpaceId;
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

bool AXLibSpaceHasWindow(CGSSpaceID SpaceId, uint32_t WindowId)
{
    bool Result = false;

    NSArray *NSArrayWindow = @[ @(WindowId) ];
    CFArrayRef Spaces = CGSCopySpacesForWindows(CGSDefaultConnection, kCGSSpaceAll, (__bridge CFArrayRef) NSArrayWindow);
    int NumberOfSpaces = CFArrayGetCount(Spaces);

    for(int Index = 0;
        Index < NumberOfSpaces;
        ++Index)
    {
        NSNumber *Id = (__bridge NSNumber *) CFArrayGetValueAtIndex(Spaces, Index);
        if(SpaceId == [Id intValue])
        {
            Result = true;
            break;
        }
    }

    CFRelease(Spaces);
    [NSArrayWindow release];

    return Result;
}

bool AXLibStickyWindow(uint32_t WindowId)
{
    bool Result = false;

    NSArray *NSArrayWindow = @[ @(WindowId) ];
    CFArrayRef Spaces = CGSCopySpacesForWindows(CGSDefaultConnection, kCGSSpaceAll, (__bridge CFArrayRef) NSArrayWindow);
    int NumberOfSpaces = CFArrayGetCount(Spaces);

    Result = NumberOfSpaces > 1;

    CFRelease(Spaces);
    [NSArrayWindow release];

    return Result;
}
