//
//  MPPrintPreferencesViewController.m
//  MacDown
//

#import "MPPrintPreferencesViewController.h"
#import "MPPreferences.h"
#import "MPGlobals.h"


// The margin preferences are stored in points (so they feed NSPrintInfo
// directly); the fields show inches. This transformer bridges the two.
@interface MPPointsToInchesValueTransformer : NSValueTransformer
@end

@implementation MPPointsToInchesValueTransformer

+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }

- (id)transformedValue:(id)value      // points -> inches
{
    if (!value)
        return nil;
    return @([value doubleValue] / kMPPointsPerInch);
}

- (id)reverseTransformedValue:(id)value   // inches -> points
{
    if (!value)
        return nil;
    return @([value doubleValue] * kMPPointsPerInch);
}

@end


@implementation MPPrintPreferencesViewController

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"PrintPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageWithSystemSymbolName:@"printer"
                    accessibilityDescription:@"Print"];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"Print", @"Preference pane title.");
}

#pragma mark - View

- (void)loadView
{
    NSValueTransformer *toInches =
        [[MPPointsToInchesValueTransformer alloc] init];

    // One formatter shared by all four fields (they are identically
    // configured): non-negative, up to two fraction digits.
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @0;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;

    NSTextField *header = [NSTextField labelWithString:NSLocalizedString(
        @"Default print & PDF margins (inches)",
        @"Print settings section header.")];
    header.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        [self rowForLabel:NSLocalizedString(@"Top:", @"Margin field label.")
                  keyPath:@"preferences.printMarginTop"
              transformer:toInches formatter:formatter],
        [self rowForLabel:NSLocalizedString(@"Left:", @"Margin field label.")
                  keyPath:@"preferences.printMarginLeft"
              transformer:toInches formatter:formatter],
        [self rowForLabel:NSLocalizedString(@"Bottom:", @"Margin field label.")
                  keyPath:@"preferences.printMarginBottom"
              transformer:toInches formatter:formatter],
        [self rowForLabel:NSLocalizedString(@"Right:", @"Margin field label.")
                  keyPath:@"preferences.printMarginRight"
              transformer:toInches formatter:formatter],
    ]];
    grid.columnSpacing = 6.0;
    grid.rowSpacing = 8.0;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:2].xPlacement = NSGridCellPlacementLeading;
    // Keep the grid at its intrinsic width so the unit label hugs the field
    // rather than being stretched out to the trailing window edge.
    [grid setContentHuggingPriority:NSLayoutPriorityRequired
                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *note = [NSTextField wrappingLabelWithString:NSLocalizedString(
        @"Margins are enlarged automatically if smaller than the printer's "
        @"printable area.", @"Print settings footnote.")];
    note.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    note.textColor = [NSColor secondaryLabelColor];
    [note.widthAnchor constraintLessThanOrEqualToConstant:360.0].active = YES;

    NSStackView *stack =
        [NSStackView stackViewWithViews:@[header, grid, note]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 460.0,
                                                            180.0)];
    [root addSubview:stack];
    // Pin leading/top so content sits top-left; trailing/bottom are <= so the
    // content keeps its intrinsic size (the grid does not stretch). The pane's
    // overall width is normalised across all panes in MPMainController.
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor
                                            constant:20.0],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:20.0],
        [stack.trailingAnchor
            constraintLessThanOrEqualToAnchor:root.trailingAnchor
                                     constant:-20.0],
        [stack.bottomAnchor
            constraintLessThanOrEqualToAnchor:root.bottomAnchor
                                     constant:-20.0],
    ]];
    self.view = root;
}

#pragma mark - Private

- (NSArray<NSView *> *)rowForLabel:(NSString *)label
                           keyPath:(NSString *)keyPath
                       transformer:(NSValueTransformer *)transformer
                         formatter:(NSNumberFormatter *)formatter
{
    NSTextField *caption = [NSTextField labelWithString:label];

    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = formatter;
    field.alignment = NSTextAlignmentRight;
    [field.widthAnchor constraintEqualToConstant:64.0].active = YES;
    [field bind:NSValueBinding toObject:self withKeyPath:keyPath
        options:@{
            NSValueTransformerBindingOption: transformer,
            NSContinuouslyUpdatesValueBindingOption: @YES,
        }];

    NSTextField *unit = [NSTextField labelWithString:NSLocalizedString(
        @"in", @"Inches unit abbreviation after a margin field.")];

    return @[caption, field, unit];
}

@end
