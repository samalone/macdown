//
//  MPAssetTests.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 13/7.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPAsset.h"
#import "MPAssetSchemeHandler.h"


@interface MPAsset ()
@property (readonly, nonatomic) NSString *typeName;
@end


@interface MPAssetTests : XCTestCase
@property (strong) NSBundle *bundle;
@end


@implementation MPAssetTests

- (void)setUp
{
    [super setUp];
    self.bundle = [NSBundle bundleForClass:[self class]];
}

- (void)testDefaultAssetType
{
    MPAsset *asset = [[MPAsset alloc] init];
    XCTAssertEqualObjects(asset.typeName, @"text/plain");

    MPStyleSheet *css = [[MPStyleSheet alloc] init];
    XCTAssertEqualObjects(css.typeName, @"text/css");

    MPScript *script = [[MPScript alloc] init];
    XCTAssertEqualObjects(script.typeName, @"text/javascript");
}

- (void)testAssetNone
{
    XCTAssertNil([[[MPScript alloc] init] htmlForOption:MPAssetNone],
                 @"Init and NULL rendering");
}

- (void)testAssetConvinienceAndEmbedded
{
    NSURL *url = [self.bundle URLForResource:@"test" withExtension:@"txt"];
    MPScript *script = [MPScript assetWithURL:url andType:@"text/plain"];

    NSString *expected =
        @"<script type=\"text/plain\">\nFoobar\n</script>";
    XCTAssertEqualObjects([script htmlForOption:MPAssetEmbedded], expected,
                          @"Convinience and embedded");
}

- (void)testAssetInitAndFullLink
{
    NSURL *url = [self.bundle URLForResource:@"test" withExtension:@"txt"];
    MPScript *script = [[MPScript alloc] initWithURL:url
                                             andType:@"text/plain"];
    NSString *expected = @"<script type=\"text/plain\" src=\"%@\"></script>";
    // Full-link file assets are served to the preview over the custom scheme.
    expected = [NSString stringWithFormat:expected,
                MPAssetSchemeURLStringForFileURL(url)];
    XCTAssertEqualObjects([script htmlForOption:MPAssetFullLink], expected,
                          @"Convinience and full link");

}

- (void)testCSS
{
    NSURL *url = [self.bundle URLForResource:@"test" withExtension:@"css"];
    MPStyleSheet *ss = [MPStyleSheet CSSWithURL:url];

    NSString *linkTag =
        @"<link rel=\"stylesheet\" type=\"text/css\" href=\"%@\">";
    linkTag = [NSString stringWithFormat:linkTag,
               MPAssetSchemeURLStringForFileURL(url)];
    NSString *styleTag =
        @"<style type=\"text/css\">\nbody { font-size: 15px; }\n</style>";
    XCTAssertNil([ss htmlForOption:MPAssetNone], @"CSS, NULL rendering");
    XCTAssertEqualObjects([ss htmlForOption:MPAssetEmbedded], styleTag,
                          @"CSS, embedded");
    XCTAssertEqualObjects([ss htmlForOption:MPAssetFullLink], linkTag,
                          @"CSS, full link");
}

- (void)testJavaScript
{
    NSURL *url = [self.bundle URLForResource:@"test" withExtension:@"js"];
    MPScript *script = [MPScript javaScriptWithURL:url];

    NSString *linkedTag =
        @"<script type=\"text/javascript\" src=\"%@\"></script>";
    linkedTag = [NSString stringWithFormat:linkedTag,
                 MPAssetSchemeURLStringForFileURL(url)];
    NSString *embeddedTag =
        @"<script type=\"text/javascript\">\nconsole.log('test');\n</script>";
    XCTAssertNil([script htmlForOption:MPAssetNone], @"JS, NULL rendering");
    XCTAssertEqualObjects([script htmlForOption:MPAssetEmbedded], embeddedTag,
                          @"JS, embedded");
    XCTAssertEqualObjects([script htmlForOption:MPAssetFullLink], linkedTag,
                          @"JS, full link");
}

- (void)testEmbedded
{
    NSURL *url = [self.bundle URLForResource:@"test" withExtension:@"js"];
    MPEmbeddedScript *script =
        [MPEmbeddedScript assetWithURL:url andType:kMPMathJaxConfigType];

    NSString *tag = @"<script type=\"text/x-mathjax-config\">\n"
                    @"console.log('test');\n</script>";
    XCTAssertNil([script htmlForOption:MPAssetNone], @"JS, NULL rendering");
    XCTAssertEqualObjects([script htmlForOption:MPAssetEmbedded], tag,
                          @"Embedded");
    XCTAssertEqualObjects([script htmlForOption:MPAssetFullLink], tag,
                          @"Forced embedded");
}

#pragma mark - Asset URL scheme

- (void)testSchemeURLMapsFileURLPreservingPathAndQuery
{
    NSURL *fileURL = [NSURL fileURLWithPath:@"/tmp/MathJax/MathJax.js"];
    NSURLComponents *comps =
        [NSURLComponents componentsWithURL:fileURL resolvingAgainstBaseURL:NO];
    comps.query = @"config=TeX-AMS-MML_HTMLorMML";

    NSString *mapped = MPAssetSchemeURLStringForFileURL(comps.URL);
    XCTAssertEqualObjects(
        mapped,
        @"macdown-asset://localhost/tmp/MathJax/MathJax.js"
        @"?config=TeX-AMS-MML_HTMLorMML",
        @"File URL should map to the asset scheme, preserving path and query");
}

- (void)testSchemeURLPassesNonFileURLsThrough
{
    NSURL *http = [NSURL URLWithString:@"https://example.com/x.js"];
    XCTAssertEqualObjects(MPAssetSchemeURLStringForFileURL(http),
                          @"https://example.com/x.js",
                          @"Non-file URLs should pass through unchanged");
}

- (void)testSchemeURLKeepsTrailingSlashForDirectoryURLs
{
    NSURL *dir = [NSURL fileURLWithPath:@"/Users/me/docs" isDirectory:YES];
    XCTAssertEqualObjects(MPAssetSchemeURLStringForFileURL(dir),
                          @"macdown-asset://localhost/Users/me/docs/",
                          @"Directory URLs should keep their trailing slash");
}

- (void)testFileURLForAssetSchemeURLPreservesPathQueryAndFragment
{
    NSURL *assetURL = [NSURL URLWithString:
        @"macdown-asset://localhost/tmp/doc.md?v=1#section"];
    XCTAssertEqualObjects(
        MPFileURLForAssetSchemeURL(assetURL).absoluteString,
        @"file:///tmp/doc.md?v=1#section",
        @"Asset URL maps back to a file URL, keeping path/query/fragment");
}

- (void)testFileURLForAssetSchemeURLPassesNonAssetURLsThrough
{
    NSURL *http = [NSURL URLWithString:@"https://example.com/x"];
    XCTAssertEqualObjects(MPFileURLForAssetSchemeURL(http), http,
                          @"Non-asset URLs should pass through unchanged");
}

#pragma mark - Body file:// rewriting

- (void)testRewriteRewritesFileURLInImgSrc
{
    NSString *html = @"<p><img src=\"file:///Users/me/photo.png\"></p>";
    NSString *expected =
        @"<p><img src=\"macdown-asset://localhost/Users/me/photo.png\"></p>";
    XCTAssertEqualObjects(MPHTMLByRewritingFileURLsToAssetScheme(html), expected,
                          @"An explicit file:// src should map to the scheme");
}

- (void)testRewriteHandlesHrefAndSingleQuotes
{
    NSString *html = @"<a href='file:///tmp/a%20b.txt'>x</a>";
    NSString *expected =
        @"<a href='macdown-asset://localhost/tmp/a%20b.txt'>x</a>";
    XCTAssertEqualObjects(MPHTMLByRewritingFileURLsToAssetScheme(html), expected,
                          @"href and single-quoted values are rewritten too");
}

- (void)testRewriteLeavesRelativeAndRemoteURLsUnchanged
{
    NSString *html = @"<img src=\"../images/x.png\">"
                     @"<a href=\"https://example.com/\">y</a>";
    XCTAssertEqualObjects(MPHTMLByRewritingFileURLsToAssetScheme(html), html,
                          @"Relative and remote URLs are left untouched");
}

- (void)testRewriteHandlesMultipleURLs
{
    NSString *html = @"<img src=\"file:///a.png\"><img src=\"file:///b.png\">";
    NSString *expected =
        @"<img src=\"macdown-asset://localhost/a.png\">"
        @"<img src=\"macdown-asset://localhost/b.png\">";
    XCTAssertEqualObjects(MPHTMLByRewritingFileURLsToAssetScheme(html), expected,
                          @"Every file:// occurrence is rewritten");
}

@end
