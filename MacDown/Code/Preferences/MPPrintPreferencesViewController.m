//
//  MPPrintPreferencesViewController.m
//  MacDown
//

#import "MPPrintPreferencesViewController.h"
#import "MPPreferences.h"


static const CGFloat kMPPointsPerInch = 72.0;


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

    NSTextField *header = [NSTextField labelWithString:NSLocalizedString(
        @"Default print & PDF margins (inches)",
        @"Print settings section header.")];
    header.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        [self rowForLabel:NSLocalizedString(@"Top:", @"Margin field label.")
                  keyPath:@"preferences.printMarginTop"
              transformer:toInches],
        [self rowForLabel:NSLocalizedString(@"Left:", @"Margin field label.")
                  keyPath:@"preferences.printMarginLeft"
              transformer:toInches],
        [self rowForLabel:NSLocalizedString(@"Bottom:", @"Margin field label.")
                  keyPath:@"preferences.printMarginBottom"
              transformer:toInches],
        [self rowForLabel:NSLocalizedString(@"Right:", @"Margin field label.")
                  keyPath:@"preferences.printMarginRight"
              transformer:toInches],
    ]];
    grid.columnSpacing = 8.0;
    grid.rowSpacing = 8.0;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;

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
    stack.edgeInsets = NSEdgeInsetsMake(20.0, 20.0, 20.0, 20.0);

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0,
                                                            200.0)];
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
}

#pragma mark - Private

- (NSArray<NSView *> *)rowForLabel:(NSString *)label
                           keyPath:(NSString *)keyPath
                       transformer:(NSValueTransformer *)transformer
{
    NSTextField *caption = [NSTextField labelWithString:label];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @0;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;

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
