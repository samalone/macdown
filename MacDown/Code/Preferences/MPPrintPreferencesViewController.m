//
//  MPPrintPreferencesViewController.m
//  MacDown
//

#import "MPPrintPreferencesViewController.h"
#import "MPPreferences.h"
#import "MacDown-Swift.h"


// The margin preferences are stored in points (so they feed NSPrintInfo
// directly); the fields show a locale-aware unit (inches or centimetres). This
// transformer bridges the two, using the points-per-unit factor from
// MPMarginUnit.
@interface MPPointsToUnitValueTransformer : NSValueTransformer

- (instancetype)initWithPointsPerUnit:(CGFloat)pointsPerUnit;

@end

@implementation MPPointsToUnitValueTransformer
{
    CGFloat _pointsPerUnit;
}

- (instancetype)initWithPointsPerUnit:(CGFloat)pointsPerUnit
{
    self = [super init];
    if (self)
        _pointsPerUnit = pointsPerUnit;
    return self;
}

+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }

- (id)transformedValue:(id)value      // points -> display unit
{
    if (!value)
        return nil;
    return @([value doubleValue] / _pointsPerUnit);
}

- (id)reverseTransformedValue:(id)value   // display unit -> points
{
    if (!value)
        return nil;
    return @([value doubleValue] * _pointsPerUnit);
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
    MPMarginUnit *unit = [MPMarginUnit current];
    NSValueTransformer *toUnit = [[MPPointsToUnitValueTransformer alloc]
        initWithPointsPerUnit:unit.pointsPerUnit];

    // One formatter shared by all four fields (they are identically
    // configured): non-negative, up to two fraction digits.
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @0;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;

    // %@ is the locale's unit symbol ("in", "cm").
    NSString *headerFormat = NSLocalizedString(
        @"Default print & PDF margins (%@)",
        @"Print settings section header; %@ is a unit symbol like in or cm.");
    NSTextField *header = [NSTextField labelWithString:
        [NSString stringWithFormat:headerFormat, unit.abbreviation]];
    header.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        [self rowForLabel:NSLocalizedString(@"Top:", @"Margin field label.")
                  keyPath:@"preferences.printMarginTop"
              transformer:toUnit formatter:formatter unitText:unit.abbreviation],
        [self rowForLabel:NSLocalizedString(@"Left:", @"Margin field label.")
                  keyPath:@"preferences.printMarginLeft"
              transformer:toUnit formatter:formatter unitText:unit.abbreviation],
        [self rowForLabel:NSLocalizedString(@"Bottom:", @"Margin field label.")
                  keyPath:@"preferences.printMarginBottom"
              transformer:toUnit formatter:formatter unitText:unit.abbreviation],
        [self rowForLabel:NSLocalizedString(@"Right:", @"Margin field label.")
                  keyPath:@"preferences.printMarginRight"
              transformer:toUnit formatter:formatter unitText:unit.abbreviation],
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
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [note.widthAnchor constraintLessThanOrEqualToConstant:360.0].active = YES;

    NSStackView *stack =
        [NSStackView stackViewWithViews:@[header, grid, note]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    // Tall enough for the header, the four-row grid, and a two-line footnote
    // plus the 20pt insets (~224pt of content); MASPreferences sizes the
    // window to this frame, and the <= bottom constraint leaves any slack
    // below rather than clipping.
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 460.0,
                                                            240.0)];
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
                          unitText:(NSString *)unitText
{
    NSTextField *caption = [NSTextField labelWithString:label];

    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.formatter = formatter;
    field.alignment = NSTextAlignmentRight;
    [field.widthAnchor constraintEqualToConstant:64.0].active = YES;
    [field bind:NSValueBinding toObject:self withKeyPath:keyPath
        options:@{
            NSValueTransformerBindingOption: transformer,
            NSContinuouslyUpdatesValueBindingOption: @YES,
        }];

    NSTextField *unit = [NSTextField labelWithString:unitText];

    return @[caption, field, unit];
}

@end
