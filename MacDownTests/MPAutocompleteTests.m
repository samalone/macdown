//
//  MPAutocompleteTests.m
//  MacDownTests
//
//  Characterization tests for the list-continuation and indentation logic in
//  NSTextView+Autocomplete (macdown-6st). These methods are pure text
//  manipulation driven from the editor's key handling, but were untouched by
//  tests through the PR2 deprecation cleanup. The goal here is to PIN the
//  current behaviour — quirks included — so the upcoming Swift-interop pass
//  and other refactors can't silently change how the editor continues lists,
//  blockquotes, and indentation.
//
//  Each test drives a real NSTextView (the category's receiver) with a known
//  string + selection, invokes one method, and asserts the resulting text and,
//  where it is deterministic, the resulting selection.
//

#import <XCTest/XCTest.h>
#import "NSTextView+Autocomplete.h"


@interface MPAutocompleteTests : XCTestCase
@end


@implementation MPAutocompleteTests

/// Build a standalone, editable text view seeded with `string` and `selection`.
/// initWithFrame: gives it its own text storage / layout / container, so the
/// category's insertText:/insertNewline: calls mutate it directly.
- (NSTextView *)textViewWithString:(NSString *)string
                         selection:(NSRange)selection
{
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)];
    tv.string = string;
    tv.selectedRange = selection;
    return tv;
}

#pragma mark - insertSpacesForTab

- (void)testInsertSpacesForTabAtLineStartInsertsFour
{
    NSTextView *tv = [self textViewWithString:@"" selection:NSMakeRange(0, 0)];
    [tv insertSpacesForTab];
    XCTAssertEqualObjects(tv.string, @"    ");
}

- (void)testInsertSpacesForTabRoundsUpToNextStop
{
    // Column 2 → two spaces complete the run to the next 4-column tab stop.
    NSTextView *tv = [self textViewWithString:@"ab" selection:NSMakeRange(2, 0)];
    [tv insertSpacesForTab];
    XCTAssertEqualObjects(tv.string, @"ab  ");
}

- (void)testInsertSpacesForTabOnStopInsertsFullTab
{
    // Already on a tab stop (column 4) → a full four-space tab.
    NSTextView *tv =
        [self textViewWithString:@"abcd" selection:NSMakeRange(4, 0)];
    [tv insertSpacesForTab];
    XCTAssertEqualObjects(tv.string, @"abcd    ");
}

#pragma mark - unindentForSpacesBefore:

- (void)testUnindentRemovesFullTabOfLeadingSpaces
{
    NSTextView *tv =
        [self textViewWithString:@"    foo" selection:NSMakeRange(4, 0)];
    BOOL changed = [tv unindentForSpacesBefore:4];
    XCTAssertTrue(changed);
    XCTAssertEqualObjects(tv.string, @"foo");
}

- (void)testUnindentRemovesTwoSpaces
{
    NSTextView *tv =
        [self textViewWithString:@"  foo" selection:NSMakeRange(2, 0)];
    BOOL changed = [tv unindentForSpacesBefore:2];
    XCTAssertTrue(changed);
    XCTAssertEqualObjects(tv.string, @"foo");
}

- (void)testUnindentDoesNothingForSingleSpace
{
    // Fewer than two spaces: left untouched (a single space is not an indent).
    NSTextView *tv =
        [self textViewWithString:@" foo" selection:NSMakeRange(1, 0)];
    BOOL changed = [tv unindentForSpacesBefore:1];
    XCTAssertFalse(changed);
    XCTAssertEqualObjects(tv.string, @" foo");
}

- (void)testUnindentRemovesOnlyOneTabStopFromDeepIndent
{
    // Eight leading spaces, cursor at column 8 → removes one 4-space stop.
    NSTextView *tv =
        [self textViewWithString:@"        foo" selection:NSMakeRange(8, 0)];
    BOOL changed = [tv unindentForSpacesBefore:8];
    XCTAssertTrue(changed);
    XCTAssertEqualObjects(tv.string, @"    foo");
}

#pragma mark - indentSelectedLinesWithPadding:

- (void)testIndentSingleLine
{
    NSTextView *tv = [self textViewWithString:@"a" selection:NSMakeRange(0, 1)];
    [tv indentSelectedLinesWithPadding:@"    "];
    XCTAssertEqualObjects(tv.string, @"    a");
}

- (void)testIndentMultipleLines
{
    NSTextView *tv =
        [self textViewWithString:@"a\nb" selection:NSMakeRange(0, 3)];
    [tv indentSelectedLinesWithPadding:@"    "];
    XCTAssertEqualObjects(tv.string, @"    a\n    b");
}

- (void)testIndentLeavesTrailingEmptyLineUnpadded
{
    NSTextView *tv =
        [self textViewWithString:@"a\n" selection:NSMakeRange(0, 2)];
    [tv indentSelectedLinesWithPadding:@"    "];
    XCTAssertEqualObjects(tv.string, @"    a\n");
}

#pragma mark - unindentSelectedLines

- (void)testUnindentSelectedSingleLine
{
    NSTextView *tv =
        [self textViewWithString:@"    a" selection:NSMakeRange(4, 1)];
    [tv unindentSelectedLines];
    XCTAssertEqualObjects(tv.string, @"a");
}

- (void)testUnindentSelectedPartialIndent
{
    // Only two leading spaces present: all of them are removed.
    NSTextView *tv =
        [self textViewWithString:@"  a" selection:NSMakeRange(2, 1)];
    [tv unindentSelectedLines];
    XCTAssertEqualObjects(tv.string, @"a");
}

- (void)testUnindentSelectedMultipleLines
{
    NSTextView *tv =
        [self textViewWithString:@"    a\n    b" selection:NSMakeRange(4, 7)];
    [tv unindentSelectedLines];
    XCTAssertEqualObjects(tv.string, @"a\nb");
}

#pragma mark - completeNextListItem:

- (void)testCompleteUnorderedListItem
{
    NSTextView *tv =
        [self textViewWithString:@"- foo" selection:NSMakeRange(5, 0)];
    BOOL handled = [tv completeNextListItem:YES];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"- foo\n- ");
}

- (void)testCompleteOrderedListItemIncrements
{
    NSTextView *tv =
        [self textViewWithString:@"1. foo" selection:NSMakeRange(6, 0)];
    BOOL handled = [tv completeNextListItem:YES];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"1. foo\n2. ");
}

- (void)testCompleteOrderedListItemWithoutIncrement
{
    NSTextView *tv =
        [self textViewWithString:@"1. foo" selection:NSMakeRange(6, 0)];
    BOOL handled = [tv completeNextListItem:NO];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"1. foo\n1. ");
}

- (void)testCompleteListItemReturnsNoOnBlankLine
{
    // Whitespace-only line before the cursor: nothing to continue.
    NSTextView *tv =
        [self textViewWithString:@"   " selection:NSMakeRange(3, 0)];
    BOOL handled = [tv completeNextListItem:YES];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"   ");
}

#pragma mark - completeNextBlockquoteLine

- (void)testCompleteBlockquoteLine
{
    NSTextView *tv =
        [self textViewWithString:@"> foo" selection:NSMakeRange(5, 0)];
    BOOL handled = [tv completeNextBlockquoteLine];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"> foo\n> ");
}

- (void)testCompleteBlockquoteReturnsNoWhenNotBlockquote
{
    NSTextView *tv =
        [self textViewWithString:@"foo" selection:NSMakeRange(3, 0)];
    BOOL handled = [tv completeNextBlockquoteLine];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"foo");
}

#pragma mark - completeNextIndentedLine

- (void)testCompleteIndentedLine
{
    NSTextView *tv =
        [self textViewWithString:@"    code" selection:NSMakeRange(8, 0)];
    BOOL handled = [tv completeNextIndentedLine];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"    code\n    ");
}

- (void)testCompleteIndentedLineReturnsNoWhenNotIndented
{
    NSTextView *tv =
        [self textViewWithString:@"code" selection:NSMakeRange(4, 0)];
    BOOL handled = [tv completeNextIndentedLine];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"code");
}

@end
