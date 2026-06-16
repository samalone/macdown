//
//  MPRendererTests.m
//  MacDown
//
//  Characterization tests for MPRenderer's Markdown -> HTML conversion.
//
//  These pin the CURRENT body-HTML that MPRenderer produces for common
//  Markdown constructs. MPRenderer builds the body as a plain string,
//  independent of the WebView, so this is a stable seam to lock down before
//  the WKWebView migration (macdown-8tk.5): if these stay green through that
//  work, only the display layer changed, not the generated HTML.
//
//  We drive the synchronous -parseMarkdown: worker directly (the public
//  -parseAndRenderNow path hops through an NSOperationQueue and the main run
//  loop), then read back -currentHtml.
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"


// Mirror of the hoedown extension bit flags we exercise (hoedown/document.h),
// defined locally so the test target needs no pod header search paths. The
// renderer is driven through the host app, where hoedown is linked; we only
// pass these as a plain int via the delegate.
static const int kMPExtTables          = (1 << 0);
static const int kMPExtFencedCode      = (1 << 1);
static const int kMPExtAutolink        = (1 << 3);
static const int kMPExtStrikethrough   = (1 << 4);
static const int kMPExtNoIntraEmphasis = (1 << 11);


// -parseMarkdown: is private; redeclare it so the tests can drive the
// synchronous parse without the async render path.
@interface MPRenderer (Testing)
- (void)parseMarkdown:(NSString *)markdown;
@end


// A configurable stand-in for MPDocument as the renderer's delegate.
// -parseMarkdown: only consults the four parse-affecting hooks; the rest are
// implemented to satisfy the protocol and return inert defaults.
@interface MPTestRendererDelegate : NSObject <MPRendererDelegate>
@property (nonatomic) int extensions;
@property (nonatomic) BOOL smartyPants;
@property (nonatomic) BOOL rendersTOC;
@property (nonatomic) BOOL detectsFrontMatter;
@end


@implementation MPTestRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer { return self.extensions; }
- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.smartyPants;
}
- (BOOL)rendererRendersTOC:(MPRenderer *)renderer { return self.rendersTOC; }
- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.detectsFrontMatter;
}

// Unused by -parseMarkdown:; inert defaults.
- (NSString *)rendererStyleName:(MPRenderer *)renderer { return nil; }
- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer { return NO; }
- (BOOL)rendererHasMermaid:(MPRenderer *)renderer { return NO; }
- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer { return NO; }
- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return MPCodeBlockAccessoryNone;
}
- (BOOL)rendererHasMathJax:(MPRenderer *)renderer { return NO; }
- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return nil;
}
- (void)renderer:(MPRenderer *)renderer
    didProduceHTMLOutput:(NSString *)html {}

@end


@interface MPRendererTests : XCTestCase
@property (strong) MPRenderer *renderer;
@property (strong) MPTestRendererDelegate *delegate;
@end


@implementation MPRendererTests

- (void)setUp
{
    [super setUp];
    self.delegate = [[MPTestRendererDelegate alloc] init];

    // A representative everyday configuration: the common block/span
    // extensions on, smartypants off, no TOC or front matter.
    self.delegate.extensions =
        kMPExtTables | kMPExtFencedCode | kMPExtAutolink
        | kMPExtStrikethrough | kMPExtNoIntraEmphasis;

    self.renderer = [[MPRenderer alloc] init];
    self.renderer.delegate = self.delegate;
    self.renderer.rendererFlags = 0;
}

- (void)tearDown
{
    self.renderer = nil;
    self.delegate = nil;
    [super tearDown];
}

/** Parse @c markdown synchronously and return the produced body HTML. */
- (NSString *)htmlForMarkdown:(NSString *)markdown
{
    [self.renderer parseMarkdown:markdown];
    return self.renderer.currentHtml;
}

#pragma mark - Headings

// Every heading gets an id="toc_N" because MPRenderer always builds the HTML
// renderer with a non-zero TOC nesting level (kMPRendererTOCLevel = 6).
- (void)testHeadingLevel1HasTOCId
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"# Hello"],
                          @"<h1 id=\"toc_0\">Hello</h1>\n");
}

- (void)testHeadingLevel2HasTOCId
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"## Sub"],
                          @"<h2 id=\"toc_0\">Sub</h2>\n");
}

#pragma mark - Inline spans

- (void)testParagraph
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"Plain paragraph."],
                          @"<p>Plain paragraph.</p>\n");
}

- (void)testBold
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"**bold**"],
                          @"<p><strong>bold</strong></p>\n");
}

- (void)testItalic
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"*italic*"],
                          @"<p><em>italic</em></p>\n");
}

// Pins the NoIntraEmphasis extension (enabled in setUp): underscores inside
// a word do NOT start emphasis, so snake_case survives verbatim.
- (void)testNoIntraWordEmphasis
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"foo_bar_baz"],
                          @"<p>foo_bar_baz</p>\n");
}

- (void)testInlineCode
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"`inline`"],
                          @"<p><code>inline</code></p>\n");
}

- (void)testLink
{
    NSString *md = @"[MacDown](https://example.com)";
    NSString *expected =
        @"<p><a href=\"https://example.com\">MacDown</a></p>\n";
    XCTAssertEqualObjects([self htmlForMarkdown:md], expected);
}

// Pins the Autolink extension (enabled in setUp): a bare URL becomes a link.
- (void)testAutolinkBareURL
{
    NSString *expected =
        @"<p><a href=\"https://example.com\">https://example.com</a></p>\n";
    XCTAssertEqualObjects([self htmlForMarkdown:@"https://example.com"],
                          expected);
}

- (void)testStrikethrough
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"~~gone~~"],
                          @"<p><del>gone</del></p>\n");
}

#pragma mark - Blocks

- (void)testUnorderedList
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"- one\n- two"],
                          @"<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n");
}

- (void)testOrderedList
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"1. one\n2. two"],
                          @"<ol>\n<li>one</li>\n<li>two</li>\n</ol>\n");
}

- (void)testBlockquote
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"> quoted"],
                          @"<blockquote>\n<p>quoted</p>\n</blockquote>\n");
}

// MacDown patches hoedown's blockcode renderer to wrap code in <div> and to
// tag the language class (Prism-compatible), defaulting to "language-none".
- (void)testFencedCodeBlockNoLanguage
{
    NSString *md = @"```\ncode line\n```";
    NSString *expected =
        @"<div><pre><code class=\"language-none\">code line"
        @"</code></pre></div>\n";
    XCTAssertEqualObjects([self htmlForMarkdown:md], expected);
}

#pragma mark - Escaping

- (void)testHTMLSpecialCharactersAreEscaped
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"a < b & c > d"],
                          @"<p>a &lt; b &amp; c &gt; d</p>\n");
}

#pragma mark - Tables

- (void)testTableProducesTableMarkup
{
    // hoedown requires at least three dashes per delimiter cell.
    NSString *md =
        @"| A | B |\n| --- | --- |\n| 1 | 2 |";
    NSString *html = [self htmlForMarkdown:md];
    XCTAssertTrue([html containsString:@"<table>"],
                  @"Tables extension should emit a <table>: %@", html);
    XCTAssertTrue([html containsString:@"<th>A</th>"],
                  @"Header cell expected: %@", html);
    XCTAssertTrue([html containsString:@"<td>1</td>"],
                  @"Body cell expected: %@", html);
}

#pragma mark - SmartyPants toggle

- (void)testSmartyPantsConvertsQuotesWhenEnabled
{
    self.delegate.smartyPants = YES;
    NSString *html = [self htmlForMarkdown:@"\"quoted\""];
    XCTAssertTrue([html containsString:@"&ldquo;"],
                  @"Opening curly quote expected: %@", html);
    XCTAssertTrue([html containsString:@"&rdquo;"],
                  @"Closing curly quote expected: %@", html);
}

- (void)testSmartyPantsLeavesQuotesWhenDisabled
{
    self.delegate.smartyPants = NO;
    // hoedown's HTML escaper always turns " into &quot; in body text; with
    // SmartyPants off the quotes stay straight (no curly entities).
    XCTAssertEqualObjects([self htmlForMarkdown:@"\"quoted\""],
                          @"<p>&quot;quoted&quot;</p>\n");
}

#pragma mark - Table of contents

- (void)testTableOfContentsReplacesMarkerWhenEnabled
{
    self.delegate.rendersTOC = YES;
    NSString *md = @"[TOC]\n\n# One\n\n## Two";
    NSString *html = [self htmlForMarkdown:md];
    XCTAssertTrue([html containsString:@"<ul class=\"toc\">"],
                  @"[TOC] marker should expand to a toc list: %@", html);
    XCTAssertFalse([html containsString:@"[TOC]"],
                   @"[TOC] marker should be consumed: %@", html);
}

#pragma mark - Front matter

// With front-matter detection on, a YAML block is parsed and prepended to the
// body as an HTML table (via -HTMLTable); the remaining Markdown still renders.
- (void)testFrontMatterRendersAsTablePrependedToBody
{
    self.delegate.detectsFrontMatter = YES;
    NSString *md = @"---\nkey: value\n---\nParagraph.";
    NSString *html = [self htmlForMarkdown:md];
    XCTAssertTrue([html containsString:@"<table>"],
                  @"Front matter should render as a table: %@", html);
    XCTAssertTrue([html containsString:@"<th>key</th>"],
                  @"Front matter key expected in table head: %@", html);
    XCTAssertTrue([html containsString:@"<td>value</td>"],
                  @"Front matter value expected in table body: %@", html);
    XCTAssertTrue([html containsString:@"<p>Paragraph.</p>"],
                  @"Body Markdown after front matter should still render: %@",
                  html);
}

#pragma mark - Document skeleton (macdown-j8g)

// -HTMLForExportWithStyles:highlighting: wraps the parsed body in the full
// HTML document via MPGetHTML, which replaced the Default.handlebars template
// when handlebars-objc was retired. This pins that the skeleton wraps the
// body (here a front-matter table) in a well-formed document: doctype, a
// <head>, the body content, and a closing </html>.
- (void)testExportDocumentSkeletonWrapsBody
{
    self.delegate.detectsFrontMatter = YES;
    [self.renderer parseMarkdown:@"---\nkey: value\n---\nParagraph."];
    NSString *doc = [self.renderer HTMLForExportWithStyles:NO
                                             highlighting:NO];
    XCTAssertTrue([doc hasPrefix:@"<!DOCTYPE html>\n<html>"],
                  @"Document should open with the HTML skeleton: %@", doc);
    XCTAssertTrue([doc containsString:@"<meta charset=\"utf-8\">"],
                  @"Head should carry the charset meta: %@", doc);
    XCTAssertTrue([doc containsString:@"<th>key</th>"],
                  @"Front-matter table should be embedded in the body: %@", doc);
    XCTAssertTrue([doc containsString:@"<p>Paragraph.</p>"],
                  @"Body Markdown should be embedded in the document: %@", doc);
    XCTAssertTrue([doc hasSuffix:@"</html>\n"],
                  @"Document should close the html element: %@", doc);
}

#pragma mark - Scroll-sync reference nodes (macdown-4y8)

// The preview's scroll-sync metrics select reference nodes with
// 'h1,h2,h3,h4,h5,h6,img:only-child' and the editor mirrors the HEADING set
// with per-line regexes. These pin the rendered heading shapes that keep the
// two sides index-symmetric. (Image reference-node alignment is imperfect
// and tracked separately in macdown-y9j.)

// A setext H1 ('===' underline) must render as an <h1> so the preview anchors
// it. The editor only gained a matching anchor once its setext-underline
// regex accepted '=' as well as '-' (asymmetry #1).
- (void)testSetextH1RendersAsH1ReferenceNode
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"Title\n==="],
                          @"<h1 id=\"toc_0\">Title</h1>\n");
}

// A setext H2 ('---' underline) renders as an <h2> (the path that already
// worked); pinned here so the H1 fix can't regress it.
- (void)testSetextH2RendersAsH2ReferenceNode
{
    XCTAssertEqualObjects([self htmlForMarkdown:@"Title\n---"],
                          @"<h2 id=\"toc_0\">Title</h2>\n");
}

@end
