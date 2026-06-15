//
//  MPStringLookupTests.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 11/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSString+Lookup.h"

@interface MPStringLookupTests : XCTestCase
@end


@implementation MPStringLookupTests

- (void)testPreviousNewline
{
    NSInteger location;
    NSString *string;

    string = @"123\n45";
    for (NSUInteger i = 0; i < 4; i++)
    {
        location = [string locationOfFirstNewlineBefore:i];
        XCTAssertEqual(location, -1, @"Index %lu of \"%@\".", i, string);
    }
    for (NSUInteger i = 4; i < string.length; i++)
    {
        location = [string locationOfFirstNewlineBefore:i];
        XCTAssertEqual(location, 3, @"Index %lu of \"%@\".", i, string);
    }
    location = [string locationOfFirstNewlineBefore:10000];
    XCTAssertEqual(location, 3, @"Should check bounds and return last NL.");

    string = @"\n1234";
    location = [string locationOfFirstNewlineBefore:0];
    XCTAssertEqual(location, -1, @"Index 0 of \"%@\".", string);
    for (NSUInteger i = 1; i < string.length; i++)
    {
        location = [string locationOfFirstNewlineBefore:i];
        XCTAssertEqual(location, 0, @"Index %lu of \"%@\".", i, string);
    }

    string = @"1234\n";
    location = [string locationOfFirstNewlineBefore:string.length];
    XCTAssertEqual(location, 4,@"Index %lu of \"%@\".", string.length, string);

    string = @"1234";
    for (NSUInteger i = 0; i < 6; i++)
    {
        location = [string locationOfFirstNewlineBefore:i];
        XCTAssertEqual(location, -1, @"Index %lu of \"%@\".", i, string);
    }
}

- (void)testNextNewline
{
    NSUInteger location;
    NSString *string;

    string = @"123\n45";
    for (NSUInteger i = 0; i < 3; i++)
    {
        location = [string locationOfFirstNewlineAfter:i];
        XCTAssertEqual(location, 3, @"Index %lu of \"%@\".", i, string);
    }
    for (NSUInteger i = 3; i < 6; i++)
    {
        location = [string locationOfFirstNewlineAfter:i];
        XCTAssertEqual(location, 6, @"Index %lu of \"%@\".", i, string);
    }
    location = [string locationOfFirstNewlineAfter:10000];
    XCTAssertEqual(location, string.length,
                   @"Should check bounds and return end of string");

    string = @"1234\n";
    for (NSUInteger i = 0; i < 4; i++)
    {
        location = [string locationOfFirstNewlineAfter:i];
        XCTAssertEqual(location, 4, @"Index %lu of \"%@\".", i, string);
    }
    location = [string locationOfFirstNewlineAfter:4];
    XCTAssertEqual(location, 5, @"Index 4 of \"%@\".", string);
}

- (void)testFirstNonWhitespace
{
    NSUInteger location;
    NSString *string;

    string = @"12345";
    for (NSUInteger i = 0; i < string.length; i++)
    {
        location = [string locationOfFirstNonWhitespaceCharacterInLineBefore:i];
        XCTAssertEqual(location, 0, @"Index %lu of \"%@\".", i, string);
    }

    string = @"  12345";
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:0],
                   0, @"Index 0 of \"%@\".", string);
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:1],
                   1, @"Index 1 of \"%@\".", string);
    for (NSUInteger i = 2; i < string.length; i++)
    {
        location = [string locationOfFirstNonWhitespaceCharacterInLineBefore:i];
        XCTAssertEqual(location, 2, @"Index %lu of \"%@\".", i, string);
    }

    string = @"\n12345";
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:0],
                   0, @"Index 0 of \"%@\".", string);
    for (NSUInteger i = 1; i < string.length; i++)
    {
        location = [string locationOfFirstNonWhitespaceCharacterInLineBefore:i];
        XCTAssertEqual(location, 1, @"Index %lu of \"%@\".", i, string);
    }

    string = @"\n  12345";
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:0],
                   0, @"Index 0 of \"%@\".", string);
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:1],
                   1, @"Index 0 of \"%@\".", string);
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:2],
                   2, @"Index 1 of \"%@\".", string);
    for (NSUInteger i = 3; i < string.length; i++)
    {
        location = [string locationOfFirstNonWhitespaceCharacterInLineBefore:i];
        XCTAssertEqual(location, 3, @"Index %lu of \"%@\".", i, string);
    }

    string = @"\n\n 12";
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:1],
                   1, @"Index 0 of \"%@\".", string);
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:4],
                   3, @"Index 0 of \"%@\".", string);
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:9],
                   3, @"Should check bounds and return for the last line.");

    string = @"\n\n1\n";
    XCTAssertEqual([string locationOfFirstNonWhitespaceCharacterInLineBefore:9],
                   4, @"Should check bounds and return for the last line.");
}

- (void)testTitleString
{
    NSString *string;
    NSString *title;

    string = @"# 123";
    title = [string titleString];
    XCTAssertEqualObjects(title, @"123", @"Incorrect title.");

    string = @"#123";
    title = [string titleString];
    XCTAssertNil(title, @"Incorrect title.");

    string = @"\n# 123\n";
    title = [string titleString];
    XCTAssertEqualObjects(title, @"123", @"Incorrect title.");

    string = @"## 123\n# 456\n789";
    title = [string titleString];
    XCTAssertEqualObjects(title, @"456", @"Incorrect title.");

    string = @"456\n## 123\n\n789\n";
    title = [string titleString];
    XCTAssertEqualObjects(title, @"123", @"Incorrect title.");

    string = @"123\n456\n";
    title = [string titleString];
    XCTAssertNil(title, @"Incorrect title.");

    string = @"####### 123\n";
    title = [string titleString];
    XCTAssertNil(title, @"Incorrect title.");
}

- (void)testHasExtension
{
    XCTAssertTrue([@"foo.css" hasExtension:@"css"], @"Wrong extension.");
    XCTAssertTrue([@"foo.min.css" hasExtension:@"css"], @"Wrong extension.");
    XCTAssertFalse([@"foo.csss" hasExtension:@"css"], @"Wrong extension.");
}

// Front matter is parsed by MPFrontMatterParser (swift-yaml, macdown-5mi).
// These lock the contract MacDown relies on: a title scalar can be read back,
// and key order is preserved (the preview renders front matter as a table).

- (void)testFrontMatterExtractsTitleAndPreservesKeyOrder
{
    NSUInteger offset = 0;
    NSString *md = @"---\nlayout: default\ntitle: Hello World\nnav_order: 3\n"
                    "---\nBody.";
    id fm = [md frontMatter:&offset];
    XCTAssertNotNil(fm, @"Front matter should parse.");
    XCTAssertEqualObjects([fm objectForKey:@"title"], @"Hello World",
                          @"Title scalar should be read back as a string.");
    XCTAssertEqualObjects([fm allKeys],
                          (@[@"layout", @"title", @"nav_order"]),
                          @"Front-matter key order must be preserved.");
    XCTAssertTrue(offset > 0, @"Content offset should advance past the block.");
}

- (void)testFrontMatterParsesSequenceValue
{
    NSString *md = @"---\ntitle: Tagged\ntags: [swift, macos]\n---\nBody.";
    id fm = [md frontMatter:NULL];
    XCTAssertEqualObjects([fm objectForKey:@"tags"],
                          (@[@"swift", @"macos"]),
                          @"A flow sequence should parse to an NSArray.");
}

- (void)testFrontMatterAbsentReturnsNil
{
    NSUInteger offset = 99;
    XCTAssertNil([@"# Just a heading\n" frontMatter:&offset],
                 @"No front matter should return nil.");
    XCTAssertEqual(offset, (NSUInteger)0, @"Offset should reset when absent.");
}

- (void)testFrontMatterRejectsTrailingTokens
{
    // Malformed front matter (trailing junk after a valid node) must be
    // rejected, not silently accepted with the junk dropped.
    NSUInteger offset = 99;
    NSString *md = @"---\n{title: Good} garbage\n---\nBody.";
    XCTAssertNil([md frontMatter:&offset],
                 @"Trailing tokens should make the block invalid.");
    XCTAssertEqual(offset, (NSUInteger)0, @"Offset should reset when invalid.");
}

@end
