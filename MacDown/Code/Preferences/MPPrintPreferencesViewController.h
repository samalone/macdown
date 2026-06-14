//
//  MPPrintPreferencesViewController.h
//  MacDown
//
//  Settings pane for print / PDF defaults (macdown-ppi.1). Currently exposes
//  the four preferred margins; clamped to the printer's imageable area at
//  print time. Its view is built programmatically (no nib).
//

#import "MPPreferencesViewController.h"
#import <MASPreferences/MASPreferencesViewController.h>

@interface MPPrintPreferencesViewController : MPPreferencesViewController
    <MASPreferencesViewController>

@end
