//
//  MPPrintPreferencesViewControllerTests.m
//  MacDownTests
//
//  The Print settings pane builds its view in code (no nib), so a crash in
//  -loadView or a bad binding would only surface at runtime. Exercise it here:
//  accessing -view triggers -loadView and wires the margin-field bindings.
//

#import <XCTest/XCTest.h>
#import "MPPrintPreferencesViewController.h"


@interface MPPrintPreferencesViewControllerTests : XCTestCase
@end


@implementation MPPrintPreferencesViewControllerTests

- (void)testPaneLoadsViewWithoutCrashing
{
    MPPrintPreferencesViewController *vc =
        [[MPPrintPreferencesViewController alloc] init];

    // Triggers -loadView and the value/transformer bindings.
    XCTAssertNotNil(vc.view);
    XCTAssertTrue(vc.view.subviews.count > 0,
                  @"The pane should build a non-empty view hierarchy.");
}

- (void)testMASPreferencesMetadata
{
    MPPrintPreferencesViewController *vc =
        [[MPPrintPreferencesViewController alloc] init];

    XCTAssertEqualObjects(vc.viewIdentifier, @"PrintPreferences");
    XCTAssertTrue(vc.toolbarItemLabel.length > 0,
                  @"The pane needs a toolbar label.");
}

@end
