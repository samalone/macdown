//
//  MPDocumentPreferencesTests.m
//  MacDown
//
//  The document-scoped resolver (bead macdown-siy.2): transparent when no
//  overrides are set (Phase 0 = zero behavior change), resolves an override for
//  every overridable schema key, and refuses to override app-only keys.
//

#import <XCTest/XCTest.h>
#import "MPDocumentPreferences.h"
#import "MPPreferences.h"
#import "MPSettingsSchema.h"

@interface MPDocumentPreferencesTests : XCTestCase
@end


@implementation MPDocumentPreferencesTests

- (void)testTransparentWhenNoOverrides
{
    // With nothing overridden the resolver returns the shared app values.
    MPDocumentPreferences *p = [[MPDocumentPreferences alloc] init];
    MPPreferences *app = [MPPreferences sharedInstance];
    XCTAssertEqual(p.htmlMathJax, app.htmlMathJax);
    XCTAssertEqual(p.extensionTables, app.extensionTables);
    XCTAssertEqualObjects(p.htmlStyleName, app.htmlStyleName);
    XCTAssertEqual(p.htmlAssetLocalAccessScope, app.htmlAssetLocalAccessScope);
    XCTAssertEqualObjects(p.editorStyleName, app.editorStyleName);
}

- (void)testEveryOverridableKeyResolvesAnOverride
{
    // Drift guard: every key the schema marks overridable must have a working
    // override accessor on MPDocumentPreferences. Inject an override and read
    // it back through KVC (which invokes the typed getter).
    MPSettingsSchema *schema = MPSettingsSchema.sharedSchema;
    for (NSString *key in schema.allOverridableKeys)
    {
        MPDocumentPreferences *p = [[MPDocumentPreferences alloc] init];
        switch ([schema descriptorForKey:key].type)
        {
            case MPSettingTypeBool:
                for (NSNumber *v in @[@NO, @YES])
                {
                    [p setOverrideValue:v forKey:key];
                    XCTAssertEqual([[p valueForKey:key] boolValue], v.boolValue,
                                   @"bool override not honored for %@", key);
                }
                break;
            case MPSettingTypeInteger:
                for (NSNumber *v in @[@0, @999])
                {
                    [p setOverrideValue:v forKey:key];
                    XCTAssertEqual([[p valueForKey:key] integerValue],
                                   v.integerValue,
                                   @"int override not honored for %@", key);
                }
                break;
            case MPSettingTypeDouble:
                [p setOverrideValue:@(3.5) forKey:key];
                XCTAssertEqualWithAccuracy([[p valueForKey:key] doubleValue],
                                           3.5, 0.0001,
                                           @"double override for %@", key);
                break;
            case MPSettingTypeString:
                [p setOverrideValue:@"sentinel" forKey:key];
                XCTAssertEqualObjects([p valueForKey:key], @"sentinel",
                                      @"string override for %@", key);
                break;
        }
    }
}

- (void)testClearingOverrideFallsBack
{
    MPDocumentPreferences *p = [[MPDocumentPreferences alloc] init];
    BOOL appValue = [MPPreferences sharedInstance].htmlMathJax;
    [p setOverrideValue:@(!appValue) forKey:@"htmlMathJax"];
    XCTAssertEqual(p.htmlMathJax, !appValue);
    [p setOverrideValue:nil forKey:@"htmlMathJax"];
    XCTAssertEqual(p.htmlMathJax, appValue);
}

- (void)testAppOnlyKeyCannotBeOverridden
{
    // Setting an override on an app-only key is a no-op: the schema's
    // categorization is enforced at the resolver.
    MPDocumentPreferences *p = [[MPDocumentPreferences alloc] init];
    NSString *appValue = [MPPreferences sharedInstance].editorStyleName;
    [p setOverrideValue:@"hacked-theme" forKey:@"editorStyleName"];
    XCTAssertEqualObjects(p.editorStyleName, appValue,
                          @"app-only editorStyleName must ignore overrides");
}

@end
