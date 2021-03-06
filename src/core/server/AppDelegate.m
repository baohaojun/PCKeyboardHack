#import "AppDelegate.h"
#import "ClientForKernelspace.h"
#import "OutlineView_mixed.h"
#import "PreferencesController.h"
#import "Updater.h"
#include "bridge.h"

@implementation AppDelegate

@synthesize window;
@synthesize clientForKernelspace;

// ------------------------------------------------------------
static void observer_IONotification(void* refcon, io_iterator_t iterator) {
  dispatch_async(dispatch_get_main_queue(), ^{
                   NSLog (@"observer_IONotification");

                   AppDelegate* self = refcon;
                   if (! self) {
                     NSLog (@"[ERROR] observer_IONotification refcon == nil\n");
                     return;
                   }

                   for (;; ) {
                     io_object_t obj = IOIteratorNext (iterator);
                     if (! obj) break;

                     IOObjectRelease (obj);
                   }
                   // Do not release iterator.

                   // = Documentation of IOKit =
                   // - Introduction to Accessing Hardware From Applications
                   //   - Finding and Accessing Devices
                   //
                   // In the case of IOServiceAddMatchingNotification, make sure you release the iterator only if you’re also ready to stop receiving notifications:
                   // When you release the iterator you receive from IOServiceAddMatchingNotification, you also disable the notification.

                   // ------------------------------------------------------------
                   [[self clientForKernelspace] refresh_connection_with_retry];
                   [[self clientForKernelspace] send_config_to_kext];
                 });
}

- (void) unregisterIONotification {
  if (notifyport_) {
    if (loopsource_) {
      CFRunLoopSourceInvalidate(loopsource_);
      loopsource_ = nil;
    }
    IONotificationPortDestroy(notifyport_);
    notifyport_ = nil;
  }
}

- (void) registerIONotification {
  [self unregisterIONotification];

  notifyport_ = IONotificationPortCreate(kIOMasterPortDefault);
  if (! notifyport_) {
    NSLog(@"[ERROR] IONotificationPortCreate failed\n");
    return;
  }

  // ----------------------------------------------------------------------
  io_iterator_t it;
  kern_return_t kernResult;

  kernResult = IOServiceAddMatchingNotification(notifyport_,
                                                kIOMatchedNotification,
                                                IOServiceNameMatching("org_pqrs_driver_PCKeyboardHack"),
                                                &observer_IONotification,
                                                self,
                                                &it);
  if (kernResult != kIOReturnSuccess) {
    NSLog(@"[ERROR] IOServiceAddMatchingNotification failed");
    return;
  }
  observer_IONotification(self, it);

  // ----------------------------------------------------------------------
  loopsource_ = IONotificationPortGetRunLoopSource(notifyport_);
  if (! loopsource_) {
    NSLog(@"[ERROR] IONotificationPortGetRunLoopSource failed");
    return;
  }
  CFRunLoopAddSource(CFRunLoopGetCurrent(), loopsource_, kCFRunLoopDefaultMode);
}

// ------------------------------------------------------------
- (void) observer_NSWorkspaceSessionDidBecomeActiveNotification:(NSNotification*)notification
{
  dispatch_async(dispatch_get_main_queue(), ^{
                   NSLog (@"observer_NSWorkspaceSessionDidBecomeActiveNotification");

                   [self registerIONotification];
                 });
}

- (void) observer_NSWorkspaceSessionDidResignActiveNotification:(NSNotification*)notification
{
  dispatch_async(dispatch_get_main_queue(), ^{
                   NSLog (@"observer_NSWorkspaceSessionDidResignActiveNotification");

                   [self unregisterIONotification];
                   [clientForKernelspace disconnect_from_kext];
                 });
}

// ------------------------------------------------------------
- (void) applicationDidFinishLaunching:(NSNotification*)aNotification {
  [self registerIONotification];

  // ------------------------------------------------------------
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceSessionDidBecomeActiveNotification:)
                                                             name:NSWorkspaceSessionDidBecomeActiveNotification
                                                           object:nil];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceSessionDidResignActiveNotification:)
                                                             name:NSWorkspaceSessionDidResignActiveNotification
                                                           object:nil];

  [outlineView_mixed_ initialExpandCollapseTree];
  [updater_ checkForUpdatesInBackground:nil];
}

- (BOOL) applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)flag
{
  [preferencesController_ show];
  return YES;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

// ------------------------------------------------------------
- (IBAction) launchUninstaller:(id)sender
{
  system("/Applications/PCKeyboardHack.app/Contents/Library/extra/launchUninstaller.sh");
}

@end
