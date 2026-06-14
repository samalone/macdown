//
//  MPPreferencesTests.m
//  MPPreferencesTests
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPPreferences.h"

@interface MPPreferencesTests : XCTestCase
@property MPPreferences *preferences;
@property NSDictionary *oldFontInfo;
@property CGFloat oldMarginTop;
@property CGFloat oldMarginLeft;
@property CGFloat oldMarginBottom;
@property CGFloat oldMarginRight;
@end


@implementation MPPreferencesTests

- (void)setUp
{
    [super setUp];
    self.preferences = [MPPreferences sharedInstance];
    self.oldFontInfo = [self.preferences.editorBaseFontInfo copy];
    self.oldMarginTop = self.preferences.printMarginTop;
    self.oldMarginLeft = self.preferences.printMarginLeft;
    self.oldMarginBottom = self.preferences.printMarginBottom;
    self.oldMarginRight = self.preferences.printMarginRight;
}

- (void)tearDown
{
    self.preferences.editorBaseFontInfo = self.oldFontInfo;
    self.preferences.printMarginTop = self.oldMarginTop;
    self.preferences.printMarginLeft = self.oldMarginLeft;
    self.preferences.printMarginBottom = self.oldMarginBottom;
    self.preferences.printMarginRight = self.oldMarginRight;
    [self.preferences synchronize];
    [super tearDown];
}

- (void)testFont
{
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    self.preferences.editorBaseFont = font;

    XCTAssertTrue([self.preferences synchronize],
                  @"Failed to synchronize user defaults.");

    NSFont *result = [self.preferences.editorBaseFont copy];
    XCTAssertEqualObjects(font, result,
                          @"Preferences not preserving font info correctly.");
}

// The print margins must persist through NSUserDefaults so a chosen margin
// survives across launches and feeds MPDocument -printInfo (macdown-ppi.1).
- (void)testPrintMarginsRoundTrip
{
    self.preferences.printMarginTop = 36.0;
    self.preferences.printMarginLeft = 54.0;
    self.preferences.printMarginBottom = 18.0;
    self.preferences.printMarginRight = 90.0;

    XCTAssertTrue([self.preferences synchronize],
                  @"Failed to synchronize user defaults.");

    XCTAssertEqual(self.preferences.printMarginTop, 36.0);
    XCTAssertEqual(self.preferences.printMarginLeft, 54.0);
    XCTAssertEqual(self.preferences.printMarginBottom, 18.0);
    XCTAssertEqual(self.preferences.printMarginRight, 90.0);
}

@end
