//
//  MPSettingsSchemaTests.m
//  MacDown
//
//  Validates the settings schema (bead macdown-siy.1): it loads, every key maps
//  to a real preference, and the attribute model (including the security
//  categorization of htmlAssetLocalAccessScope) is as decided.
//

#import <XCTest/XCTest.h>
#import "MPSettingsSchema.h"

@interface MPSettingsSchemaTests : XCTestCase
@end


@implementation MPSettingsSchemaTests

- (void)testSchemaLoads
{
    MPSettingsSchema *schema = MPSettingsSchema.sharedSchema;
    XCTAssertNotNil(schema);
    XCTAssertGreaterThan(schema.allOverridableKeys.count, 0,
                         @"Schema should define overridable keys");
}

- (void)testEveryKeyIsBackedByARealPreference
{
    // Guards against the schema drifting from the actual MPPreferences
    // properties (a key typo would make a setting silently un-overridable).
    NSArray<NSString *> *missing =
        MPSettingsSchema.sharedSchema.keysNotBackedByPreference;
    XCTAssertEqualObjects(missing, @[],
                          @"Schema keys with no matching preference: %@",
                          missing);
}

- (void)testTypicalKeyIsNormalAndNonSecurity
{
    MPSettingDescriptor *d =
        [MPSettingsSchema.sharedSchema descriptorForKey:@"htmlStyleName"];
    XCTAssertNotNil(d);
    XCTAssertEqual(d.type, MPSettingTypeString);
    XCTAssertEqual(d.writePolicy, MPSettingWriteNormal);
    XCTAssertFalse(d.isSecuritySensitive);
    XCTAssertTrue(d.readableLayers & MPSettingLayerDocument);
    XCTAssertTrue(d.readableLayers & MPSettingLayerFolder);
}

- (void)testAccessScopeIsOverridableButGuarded
{
    // The decision (macdown-siy.1): overridable for reading, but never
    // auto-persisted, and security-sensitive so loosening needs consent.
    MPSettingsSchema *schema = MPSettingsSchema.sharedSchema;
    MPSettingDescriptor *d =
        [schema descriptorForKey:@"htmlAssetLocalAccessScope"];
    XCTAssertNotNil(d, @"access scope should be overridable");
    XCTAssertEqual(d.type, MPSettingTypeInteger);
    XCTAssertEqual(d.writePolicy, MPSettingWriteExplicitOnly);
    XCTAssertTrue(d.isSecuritySensitive);
    XCTAssertTrue(d.readableLayers & MPSettingLayerDocument);
}

- (void)testEditorSettingsAreAppOnly
{
    // Editor settings are the author's environment, not output: not overridable.
    MPSettingsSchema *schema = MPSettingsSchema.sharedSchema;
    XCTAssertFalse([schema isKeyOverridable:@"editorStyleName"]);
    XCTAssertNil([schema descriptorForKey:@"editorOnRight"]);
}

@end
