//
//  MPAutocompleteTests.m
//  MacDownTests
//
//  Characterization tests for NSTextView+Autocomplete (macdown-6st: list/
//  indent continuation; macdown-3rn: matching-character pairing, selection
//  wrapping, markup/header toggles). These methods are pure text manipulation
//  driven from the editor's key handling, but were untouched by tests through
//  the PR2 deprecation cleanup. The goal here is to PIN the current behaviour
//  — quirks included — so the upcoming Swift-interop pass and other refactors
//  can't silently change how the editor continues lists, pairs brackets,
//  wraps selections, and toggles markup.
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

#pragma mark - completeMatchingCharacterForText:atLocation:

- (void)testAutoPairInsertsClosingBracket
{
    NSTextView *tv = [self textViewWithString:@"" selection:NSMakeRange(0, 0)];
    BOOL handled = [tv completeMatchingCharacterForText:@"(" atLocation:0];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"()");
    // Cursor lands between the inserted pair.
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
}

- (void)testAutoPairStraightQuoteWhenSubstitutionOff
{
    NSTextView *tv = [self textViewWithString:@"" selection:NSMakeRange(0, 0)];
    tv.automaticQuoteSubstitutionEnabled = NO;
    BOOL handled = [tv completeMatchingCharacterForText:@"\"" atLocation:0];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"\"\"");
}

- (void)testAutoPairCurlyQuoteWhenSubstitutionOn
{
    // With smart quotes on, a single opening curly quote is inserted (no pair).
    NSTextView *tv = [self textViewWithString:@"" selection:NSMakeRange(0, 0)];
    tv.automaticQuoteSubstitutionEnabled = YES;
    BOOL handled = [tv completeMatchingCharacterForText:@"\"" atLocation:0];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"“");
}

- (void)testAutoPairSkippedWhenNextCharNotBoundary
{
    // Next char is a letter (not a boundary), so no pairing happens.
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 0)];
    BOOL handled = [tv completeMatchingCharacterForText:@"(" atLocation:0];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"x");
}

- (void)testTypingClosingBracketStepsOverExistingOne
{
    // Typing ')' immediately before an existing ')' just moves the cursor.
    NSTextView *tv = [self textViewWithString:@")" selection:NSMakeRange(0, 0)];
    BOOL handled = [tv completeMatchingCharacterForText:@")" atLocation:0];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @")");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
}

#pragma mark - completeMatchingCharactersForTextInRange:withString:

- (void)testInsertDispatcherPairsOnEmptySelection
{
    NSTextView *tv = [self textViewWithString:@"" selection:NSMakeRange(0, 0)];
    BOOL handled = [tv completeMatchingCharactersForTextInRange:NSMakeRange(0, 0)
                                                     withString:@"["
                                           strikethroughEnabled:NO];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"[]");
}

- (void)testInsertDispatcherWrapsNonEmptySelection
{
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 1)];
    BOOL handled = [tv completeMatchingCharactersForTextInRange:NSMakeRange(0, 1)
                                                     withString:@"*"
                                           strikethroughEnabled:NO];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"*x*");
}

#pragma mark - wrapMatchingCharactersOfCharacter:

- (void)testWrapSelectionInBrackets
{
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 1)];
    BOOL handled = [tv wrapMatchingCharactersOfCharacter:'('
                                       aroundTextInRange:NSMakeRange(0, 1)
                                    strikethroughEnabled:NO];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"(x)");
}

- (void)testWrapSelectionInStrikethroughWhenEnabled
{
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 1)];
    BOOL handled = [tv wrapMatchingCharactersOfCharacter:'~'
                                       aroundTextInRange:NSMakeRange(0, 1)
                                    strikethroughEnabled:YES];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"~x~");
}

- (void)testWrapStrikethroughIgnoredWhenDisabled
{
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 1)];
    BOOL handled = [tv wrapMatchingCharactersOfCharacter:'~'
                                       aroundTextInRange:NSMakeRange(0, 1)
                                    strikethroughEnabled:NO];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"x");
}

#pragma mark - deleteMatchingCharactersAround:

- (void)testDeleteEmptyPair
{
    NSTextView *tv = [self textViewWithString:@"()" selection:NSMakeRange(1, 0)];
    BOOL handled = [tv deleteMatchingCharactersAround:1];
    XCTAssertTrue(handled);
    XCTAssertEqualObjects(tv.string, @"");
}

- (void)testDeleteMatchingReturnsNoForNonPair
{
    NSTextView *tv = [self textViewWithString:@"ab" selection:NSMakeRange(1, 0)];
    BOOL handled = [tv deleteMatchingCharactersAround:1];
    XCTAssertFalse(handled);
    XCTAssertEqualObjects(tv.string, @"ab");
}

#pragma mark - substringInRange:isSurroundedByPrefix:suffix:

- (void)testSurroundedByDetectsCodeSpan
{
    NSTextView *tv =
        [self textViewWithString:@"`x`" selection:NSMakeRange(0, 0)];
    XCTAssertTrue([tv substringInRange:NSMakeRange(1, 1)
                  isSurroundedByPrefix:@"`" suffix:@"`"]);
}

- (void)testSurroundedByEmphasisDistinguishesStrong
{
    // The */**/*** special-casing: single * is emphasis (YES), ** is strong
    // (NO for the emphasis query), *** is emphasis again (YES).
    NSTextView *em =
        [self textViewWithString:@"*x*" selection:NSMakeRange(0, 0)];
    XCTAssertTrue([em substringInRange:NSMakeRange(1, 1)
                  isSurroundedByPrefix:@"*" suffix:@"*"]);

    NSTextView *strong =
        [self textViewWithString:@"**x**" selection:NSMakeRange(0, 0)];
    XCTAssertFalse([strong substringInRange:NSMakeRange(2, 1)
                       isSurroundedByPrefix:@"*" suffix:@"*"]);

    NSTextView *both =
        [self textViewWithString:@"***x***" selection:NSMakeRange(0, 0)];
    XCTAssertTrue([both substringInRange:NSMakeRange(3, 1)
                    isSurroundedByPrefix:@"*" suffix:@"*"]);
}

#pragma mark - toggleForMarkupPrefix:suffix:

- (void)testToggleMarkupAddsEmphasis
{
    NSTextView *tv = [self textViewWithString:@"x" selection:NSMakeRange(0, 1)];
    BOOL isOn = [tv toggleForMarkupPrefix:@"*" suffix:@"*"];
    XCTAssertTrue(isOn);
    XCTAssertEqualObjects(tv.string, @"*x*");
}

- (void)testToggleMarkupRemovesEmphasis
{
    // "x" is selected inside the existing emphasis markers.
    NSTextView *tv =
        [self textViewWithString:@"*x*" selection:NSMakeRange(1, 1)];
    BOOL isOn = [tv toggleForMarkupPrefix:@"*" suffix:@"*"];
    XCTAssertFalse(isOn);
    XCTAssertEqualObjects(tv.string, @"x");
}

#pragma mark - toggleBlockWithPattern:prefix:

- (void)testToggleBlockAddsPrefix
{
    NSTextView *tv = [self textViewWithString:@"a" selection:NSMakeRange(0, 1)];
    [tv toggleBlockWithPattern:@"^> " prefix:@"> "];
    XCTAssertEqualObjects(tv.string, @"> a");
}

- (void)testToggleBlockRemovesPrefix
{
    NSTextView *tv =
        [self textViewWithString:@"> a" selection:NSMakeRange(0, 3)];
    [tv toggleBlockWithPattern:@"^> " prefix:@"> "];
    XCTAssertEqualObjects(tv.string, @"a");
}

#pragma mark - makeHeaderForSelectedLinesWithLevel:

- (void)testMakeHeaderAddsHashes
{
    NSTextView *tv =
        [self textViewWithString:@"title" selection:NSMakeRange(0, 5)];
    [tv makeHeaderForSelectedLinesWithLevel:2];
    XCTAssertEqualObjects(tv.string, @"## title");
}

- (void)testMakeHeaderReplacesExistingLevel
{
    NSTextView *tv =
        [self textViewWithString:@"## title" selection:NSMakeRange(0, 8)];
    [tv makeHeaderForSelectedLinesWithLevel:3];
    XCTAssertEqualObjects(tv.string, @"### title");
}

- (void)testMakeHeaderLevelZeroStripsToParagraph
{
    NSTextView *tv =
        [self textViewWithString:@"## title" selection:NSMakeRange(0, 8)];
    [tv makeHeaderForSelectedLinesWithLevel:0];
    XCTAssertEqualObjects(tv.string, @"title");
}

#pragma mark - insertMappedContent

- (void)testInsertMappedContentReturnsNoForLongContent
{
    // Bails out for content longer than 20 characters (never a shortcut key).
    NSString *longText = @"this is far too long to be mapped";
    NSTextView *tv =
        [self textViewWithString:longText
                       selection:NSMakeRange(longText.length, 0)];
    XCTAssertFalse([tv insertMappedContent]);
    XCTAssertEqualObjects(tv.string, longText);
}

- (void)testInsertMappedContentReturnsNoForUnknownContent
{
    NSTextView *tv =
        [self textViewWithString:@"zzqqz" selection:NSMakeRange(5, 0)];
    XCTAssertFalse([tv insertMappedContent]);
    XCTAssertEqualObjects(tv.string, @"zzqqz");
}

@end
