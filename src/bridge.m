#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <stdio.h>

#import "bridge.h"

#ifndef kAXFullScreenAttribute
#define kAXFullScreenAttribute CFSTR("AXFullScreen")
#endif

static NSStatusItem *gStatusItem = nil;
static NSMenu *gStatusMenu = nil;
static NSString *gIconPath = nil;
static id gMenuHandler = nil;

@interface ShiftItMenuHandler : NSObject
@end

@implementation ShiftItMenuHandler
- (void)onMenuAction:(id)sender {
    // Forward menu clicks to the same action pipeline as hotkeys.
    NSInteger actionId = [sender tag];
    SI_PerformAction((int)actionId);
}
@end

static int gSizeDeltaType = 0;
static double gFixedW = 50;
static double gFixedH = 28;
static double gWindowPct = 10.0;
static double gScreenPct = 6.25;
static int gDebug = 0;
// 0 = no flip, 1 = flip Y axis (AX top-left)

// Action ids (must match Go)
enum {
    ActionLeft = 1,
    ActionRight,
    ActionTop,
    ActionBottom,
    ActionTopLeft,
    ActionTopRight,
    ActionBottomLeft,
    ActionBottomRight,
    ActionLeftThirdTop,
    ActionLeftThirdBottom,
    ActionCenterThirdTop,
    ActionCenterThirdBottom,
    ActionRightThirdTop,
    ActionRightThirdBottom,
    ActionLeftThird,
    ActionCenterThird,
    ActionRightThird,
    ActionCenter,
    ActionToggleZoom,
    ActionMaximize,
    ActionToggleFullScreen,
    ActionIncrease,
    ActionReduce,
    ActionNextScreen,
    ActionPreviousScreen,
};

static UInt32 CocoaToCarbonFlags(NSUInteger cocoaFlags) {
    // Carbon hotkey registration still expects Carbon modifier flags.
    UInt32 carbon = 0;
    if (cocoaFlags & NSEventModifierFlagCommand) carbon |= cmdKey;
    if (cocoaFlags & NSEventModifierFlagOption) carbon |= optionKey;
    if (cocoaFlags & NSEventModifierFlagControl) carbon |= controlKey;
    if (cocoaFlags & NSEventModifierFlagShift) carbon |= shiftKey;
    return carbon;
}

static void EnsureStatusItem(void) {
    if (gStatusItem) return;
    // Ensure NSApp exists before creating status item/menu.
    [NSApplication sharedApplication];
    gStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    gStatusMenu = [[NSMenu alloc] initWithTitle:@"ShiftIt"];

    gMenuHandler = [[ShiftItMenuHandler alloc] init];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [quit setTarget:NSApp];
    [gStatusMenu addItem:quit];

    [gStatusItem setMenu:gStatusMenu];
    NSStatusBarButton *button = gStatusItem.button;
    if (button) {
        NSButtonCell *cell = (NSButtonCell *)button.cell;
        if (cell) {
            cell.highlightsBy = NSContentsCellMask;
        }
    }

    if (gIconPath) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:gIconPath];
        [img setTemplate:YES];
        if (button) {
            button.image = img;
        }
    }
}

void SI_AddMenuItem(int actionId, const char *title) {
    if (!title) return;
    EnsureStatusItem();

    NSString *itemTitle = [NSString stringWithUTF8String:title];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:itemTitle action:@selector(onMenuAction:) keyEquivalent:@""];
    [item setTarget:gMenuHandler];
    [item setTag:actionId];

    NSInteger insertIndex = [gStatusMenu numberOfItems] - 1;
    if (insertIndex < 0) insertIndex = 0;
    [gStatusMenu insertItem:item atIndex:insertIndex];
}

void SI_SetStatusIcon(const char *path) {
    // Store icon path and update the status item if it already exists.
    if (!path) return;
    gIconPath = [NSString stringWithUTF8String:path];
    if (gStatusItem) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:gIconPath];
        [img setTemplate:YES];
        NSStatusBarButton *button = gStatusItem.button;
        if (button) {
            button.image = img;
        }
    }
}

OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    // Carbon hotkey callback -> Go action handler.
    EventHotKeyID hkCom;
    GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkCom), NULL, &hkCom);
    if (gDebug) {
        fprintf(stderr, "[ShiftItGo] hotkey pressed actionId=%u\n", (unsigned int)hkCom.id);
        fflush(stderr);
    }
    GoHandleAction((int)hkCom.id);
    return noErr;
}

void SI_RegisterHotKey(int actionId, int keyCode, unsigned int cocoaFlags) {
    // Register a Carbon hotkey once, then add per-action keys.
    static int installed = 0;
    if (!installed) {
        EventTypeSpec eventType;
        eventType.eventClass = kEventClassKeyboard;
        eventType.eventKind = kEventHotKeyPressed;
        InstallApplicationEventHandler(&HotKeyHandler, 1, &eventType, NULL, NULL);
        installed = 1;
    }

    EventHotKeyRef ref = NULL;
    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'SIFT';
    hotKeyID.id = (UInt32)actionId;

    UInt32 carbonFlags = CocoaToCarbonFlags(cocoaFlags);
    OSStatus status = RegisterEventHotKey((UInt32)keyCode, carbonFlags, hotKeyID, GetApplicationEventTarget(), 0, &ref);
    if (status != noErr) {
        fprintf(stderr, "[ShiftItGo] RegisterEventHotKey failed actionId=%d keyCode=%d cocoaFlags=%u carbonFlags=%u status=%d\n",
                actionId, keyCode, cocoaFlags, carbonFlags, (int)status);
        fflush(stderr);
    }
    if (gDebug) {
        fprintf(stderr, "[ShiftItGo] register hotkey actionId=%d keyCode=%d cocoaFlags=%u carbonFlags=%u\n",
                actionId, keyCode, cocoaFlags, carbonFlags);
        fflush(stderr);
    }
}

void SI_SetSizeDeltaConfig(int type, double fixedW, double fixedH, double windowPct, double screenPct) {
    // Configure how Increase/Reduce actions change window size.
    gSizeDeltaType = type;
    gFixedW = fixedW;
    gFixedH = fixedH;
    gWindowPct = windowPct;
    gScreenPct = screenPct;
}

void SI_SetDebug(int enabled) {
    // Enable Objective-C side debug logging.
    gDebug = enabled ? 1 : 0;
    if (gDebug) {
        fprintf(stderr, "[ShiftItGo] debug enabled\n");
        fflush(stderr);
    }
}

static CGFloat PrimaryScreenHeight(void) {
    // Needed to convert between Cocoa and AX coordinate systems.
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (screens.count == 0) return 0;
    return screens[0].frame.size.height;
}

static CGRect CocoaToScreenRect(CGRect cocoa) {
    // Cocoa origin is bottom-left; AX uses top-left of primary screen.
    CGFloat h = PrimaryScreenHeight();
    cocoa.origin.y = h - cocoa.size.height - cocoa.origin.y;
    return cocoa;
}

static CGRect ScreenToCocoaRect(CGRect screen) {
    // Same transform as CocoaToScreenRect (involutive).
    CGFloat h = PrimaryScreenHeight();
    screen.origin.y = h - screen.size.height - screen.origin.y;
    return screen;
}

static NSScreen *ScreenForRect(CGRect screenRect) {
    NSScreen *fitScreen = [NSScreen mainScreen];
    double maxSize = 0;

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect s = CocoaToScreenRect([screen frame]);
        NSRect intersectRect = NSIntersectionRect(s, screenRect);
        if (intersectRect.size.width > 0) {
            double size = intersectRect.size.width * intersectRect.size.height;
            if (size > maxSize) {
                fitScreen = screen;
                maxSize = size;
            }
        }
    }

    return fitScreen;
}

static BOOL GetFocusedWindow(AXUIElementRef *outWindow, CGRect *outCocoaRect) {
    // Find focused window of the active app (or system-wide fallback).
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    AXUIElementRef window = NULL;
    AXUIElementRef app = NULL;
    if (AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute, (CFTypeRef *)&app) == kAXErrorSuccess && app) {
        if (AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, (CFTypeRef *)&window) != kAXErrorSuccess || !window) {
            AXUIElementRef focusedUI = NULL;
            if (AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute, (CFTypeRef *)&focusedUI) == kAXErrorSuccess && focusedUI) {
                AXUIElementCopyAttributeValue(focusedUI, kAXWindowAttribute, (CFTypeRef *)&window);
                CFRelease(focusedUI);
            }
        }
    }
    if (!window) {
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute, (CFTypeRef *)&window);
    }
    if (!window) {
        if (app) CFRelease(app);
        CFRelease(systemWide);
        return NO;
    }

    AXValueRef posValue = NULL;
    AXValueRef sizeValue = NULL;
    if (AXUIElementCopyAttributeValue(window, kAXPositionAttribute, (CFTypeRef *)&posValue) != kAXErrorSuccess) {
        CFRelease(window);
        if (app) CFRelease(app);
        CFRelease(systemWide);
        return NO;
    }
    if (AXUIElementCopyAttributeValue(window, kAXSizeAttribute, (CFTypeRef *)&sizeValue) != kAXErrorSuccess) {
        CFRelease(posValue);
        CFRelease(window);
        if (app) CFRelease(app);
        CFRelease(systemWide);
        return NO;
    }

    CGPoint axPos;
    CGSize axSize;
    AXValueGetValue(posValue, kAXValueCGPointType, &axPos);
    AXValueGetValue(sizeValue, kAXValueCGSizeType, &axSize);

    if (outCocoaRect) {
        // AX coordinates are in screen coordinates (origin at top-left of primary screen).
        *outCocoaRect = CGRectMake(axPos.x, axPos.y, axSize.width, axSize.height);
    }
    if (outWindow) {
        *outWindow = window; // caller releases
    } else {
        CFRelease(window);
    }

    CFRelease(posValue);
    CFRelease(sizeValue);
    if (app) CFRelease(app);
    CFRelease(systemWide);
    return YES;
}

static void SetWindowRect(AXUIElementRef window, CGRect cocoaRect) {
    // Apply new position/size via AX attributes.
    CGPoint axPos = cocoaRect.origin;
    AXValueRef posValue = AXValueCreate(kAXValueCGPointType, &axPos);
    AXValueRef sizeValue = AXValueCreate(kAXValueCGSizeType, &cocoaRect.size);
    AXUIElementSetAttributeValue(window, kAXPositionAttribute, posValue);
    AXUIElementSetAttributeValue(window, kAXSizeAttribute, sizeValue);
    if (posValue) CFRelease(posValue);
    if (sizeValue) CFRelease(sizeValue);
}

static CGRect ClampToScreen(CGRect rect, CGRect screen) {
    // Ensure target rect stays within the visible screen bounds.
    if (rect.size.width > screen.size.width) rect.size.width = screen.size.width;
    if (rect.size.height > screen.size.height) rect.size.height = screen.size.height;
    if (rect.origin.x < screen.origin.x) rect.origin.x = screen.origin.x;
    if (rect.origin.y < screen.origin.y) rect.origin.y = screen.origin.y;
    if (rect.origin.x + rect.size.width > screen.origin.x + screen.size.width)
        rect.origin.x = screen.origin.x + screen.size.width - rect.size.width;
    if (rect.origin.y + rect.size.height > screen.origin.y + screen.size.height)
        rect.origin.y = screen.origin.y + screen.size.height - rect.size.height;
    return rect;
}

static CGRect RectForAction(int actionId, CGRect window, CGRect screen) {
    // Compute target rect for standard actions.
    CGRect r = window;
    CGFloat w = screen.size.width;
    CGFloat h = screen.size.height;
    CGFloat x = screen.origin.x;
    CGFloat y = screen.origin.y;

    switch (actionId) {
        case ActionLeft:
            r = CGRectMake(x, y, w/2.0, h);
            break;
        case ActionRight:
            r = CGRectMake(x + w/2.0, y, w/2.0, h);
            break;
        case ActionTop:
            r = CGRectMake(x, y + h/2.0, w, h/2.0);
            break;
        case ActionBottom:
            r = CGRectMake(x, y, w, h/2.0);
            break;
        case ActionTopLeft:
            r = CGRectMake(x, y + h/2.0, w/2.0, h/2.0);
            break;
        case ActionTopRight:
            r = CGRectMake(x + w/2.0, y + h/2.0, w/2.0, h/2.0);
            break;
        case ActionBottomLeft:
            r = CGRectMake(x, y, w/2.0, h/2.0);
            break;
        case ActionBottomRight:
            r = CGRectMake(x + w/2.0, y, w/2.0, h/2.0);
            break;
        case ActionLeftThirdTop:
            r = CGRectMake(x, y + h/2.0, w/3.0, h/2.0);
            break;
        case ActionLeftThirdBottom:
            r = CGRectMake(x, y, w/3.0, h/2.0);
            break;
        case ActionCenterThirdTop:
            r = CGRectMake(x + w/3.0, y + h/2.0, w/3.0, h/2.0);
            break;
        case ActionCenterThirdBottom:
            r = CGRectMake(x + w/3.0, y, w/3.0, h/2.0);
            break;
        case ActionRightThirdTop:
            r = CGRectMake(x + 2.0*w/3.0, y + h/2.0, w/3.0, h/2.0);
            break;
        case ActionRightThirdBottom:
            r = CGRectMake(x + 2.0*w/3.0, y, w/3.0, h/2.0);
            break;
        case ActionLeftThird:
            r = CGRectMake(x, y, w/3.0, h);
            break;
        case ActionCenterThird:
            r = CGRectMake(x + w/3.0, y, w/3.0, h);
            break;
        case ActionRightThird:
            r = CGRectMake(x + 2.0*w/3.0, y, w/3.0, h);
            break;
        case ActionCenter:
            r.origin.x = x + (w - window.size.width) / 2.0;
            r.origin.y = y + (h - window.size.height) / 2.0;
            r.size = window.size;
            break;
        case ActionMaximize:
            r = screen;
            break;
        default:
            break;
    }
    return r;
}

static void ResizeWithDelta(AXUIElementRef window, CGRect windowRect, CGRect screenRect, BOOL increase) {
    // Increase/Reduce window size with configured deltas.
    double kw = 0;
    double kh = 0;
    switch (gSizeDeltaType) {
        case 3001: // fixed
            kw = gFixedW;
            kh = gFixedH;
            break;
        case 3002: // window percent
            kw = windowRect.size.width * (gWindowPct / 100.0);
            kh = windowRect.size.height * (gWindowPct / 100.0);
            break;
        case 3003: // screen percent
            kw = screenRect.size.width * (gScreenPct / 100.0);
            kh = screenRect.size.height * (gScreenPct / 100.0);
            break;
        default:
            kw = gFixedW;
            kh = gFixedH;
            break;
    }

    int inc = increase ? 1 : -1;
    CGRect r = windowRect;
    r.origin.x -= (kw * inc) / 2.0;
    r.origin.y -= (kh * inc) / 2.0;
    r.size.width += kw * inc;
    r.size.height += kh * inc;

    if (r.size.width < kw) r.size.width = kw;
    if (r.size.height < kh) r.size.height = kh;

    r = ClampToScreen(r, screenRect);
    SetWindowRect(window, r);
}

static void MoveToAdjacentScreen(AXUIElementRef window, CGRect windowRect, BOOL next) {
    // Move window to adjacent screen, preserving relative position/size.
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (screens.count == 0) return;

    NSScreen *current = ScreenForRect(windowRect);
    NSUInteger idx = [screens indexOfObject:current];
    if (idx == NSNotFound) idx = 0;

    NSUInteger nextIdx = next ? (idx + 1) % screens.count : (idx + screens.count - 1) % screens.count;
    NSScreen *target = screens[nextIdx];

    CGRect cur = CocoaToScreenRect([current visibleFrame]);
    CGRect tgt = CocoaToScreenRect([target visibleFrame]);

    double kw = tgt.size.width / cur.size.width;
    double kh = tgt.size.height / cur.size.height;

    CGRect r;
    r.size.width = windowRect.size.width * kw;
    r.size.height = windowRect.size.height * kh;
    r.origin.x = tgt.origin.x + (windowRect.origin.x - cur.origin.x) * kw;
    r.origin.y = tgt.origin.y + (windowRect.origin.y - cur.origin.y) * kh;

    r = ClampToScreen(r, tgt);
    SetWindowRect(window, r);
}

void SI_PerformAction(int actionId) {
    // Main action dispatcher used by both hotkeys and menu clicks.
    AXUIElementRef window = NULL;
    CGRect windowRect = CGRectZero;
    if (!GetFocusedWindow(&window, &windowRect)) {
        if (gDebug) {
            fprintf(stderr, "[ShiftItGo] no focused window for actionId=%d\n", actionId);
            fflush(stderr);
        }
        return;
    }

    NSScreen *screen = ScreenForRect(windowRect);
    CGRect screenRect = CocoaToScreenRect([screen visibleFrame]);

    switch (actionId) {
        case ActionToggleZoom: {
            AXUIElementRef zoomButton = NULL;
            if (AXUIElementCopyAttributeValue(window, kAXZoomButtonAttribute, (CFTypeRef *)&zoomButton) == kAXErrorSuccess && zoomButton) {
                AXUIElementPerformAction(zoomButton, kAXPressAction);
                CFRelease(zoomButton);
            }
            break;
        }
        case ActionToggleFullScreen: {
            CFTypeRef value = NULL;
            if (AXUIElementCopyAttributeValue(window, kAXFullScreenAttribute, &value) == kAXErrorSuccess && value) {
                Boolean flag = CFBooleanGetValue((CFBooleanRef)value);
                CFRelease(value);
                AXUIElementSetAttributeValue(window, kAXFullScreenAttribute, flag ? kCFBooleanFalse : kCFBooleanTrue);
            }
            break;
        }
        case ActionIncrease:
            ResizeWithDelta(window, windowRect, screenRect, YES);
            break;
        case ActionReduce:
            ResizeWithDelta(window, windowRect, screenRect, NO);
            break;
        case ActionNextScreen:
            MoveToAdjacentScreen(window, windowRect, YES);
            break;
        case ActionPreviousScreen:
            MoveToAdjacentScreen(window, windowRect, NO);
            break;
        default: {
            CGRect cocoaWindow = ScreenToCocoaRect(windowRect);
            CGRect cocoaScreen = ScreenToCocoaRect(screenRect);
            CGRect target = RectForAction(actionId, cocoaWindow, cocoaScreen);
            target = ClampToScreen(target, cocoaScreen);
            CGRect targetScreen = CocoaToScreenRect(target);
            SetWindowRect(window, targetScreen);
            break;
        }
    }

    if (window) CFRelease(window);
}

void SI_RunApp(void) {
    // Set up accessibility permissions, status item, and start event loop.
    @autoreleasepool {
        if (!AXIsProcessTrusted()) {
            fprintf(stderr, "[ShiftItGo] Accessibility permission required.\n");
            fprintf(stderr, "[ShiftItGo] Open System Settings -> Privacy & Security -> Accessibility,\n");
            fprintf(stderr, "[ShiftItGo] add ShiftItGo and enable the toggle.\n");
            NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
            if (gDebug) {
                fprintf(stderr, "[ShiftItGo] AXIsProcessTrusted=NO (prompted)\n");
                fflush(stderr);
            }
        } else if (gDebug) {
            fprintf(stderr, "[ShiftItGo] AXIsProcessTrusted=YES\n");
            fflush(stderr);
        }
        [NSApplication sharedApplication];
        EnsureStatusItem();
        [NSApp run];
    }
}
