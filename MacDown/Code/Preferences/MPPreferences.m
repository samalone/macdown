//
//  MPPreferences.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPPreferences.h"
#import "NSUserDefaults+Suite.h"
#import "MPGlobals.h"


typedef NS_ENUM(NSUInteger, MPUnorderedListMarkerType)
{
    MPUnorderedListMarkerAsterisk = 0,
    MPUnorderedListMarkerPlusSign = 1,
    MPUnorderedListMarkerMinusSign = 2,
};



NSString * const MPDidDetectFreshInstallationNotification =
    @"MPDidDetectFreshInstallationNotificationName";

static NSString * const kMPDefaultEditorFontNameKey = @"name";
static NSString * const kMPDefaultEditorFontPointSizeKey = @"size";
static NSString * const kMPDefaultEditorFontName = @"Menlo-Regular";
static CGFloat    const kMPDefaultEditorFontPointSize = 14.0;
static CGFloat    const kMPDefaultEditorHorizontalInset = 15.0;
static CGFloat    const kMPDefaultEditorVerticalInset = 30.0;
static CGFloat    const kMPDefaultEditorLineSpacing = 3.0;
static BOOL       const kMPDefaultEditorSyncScrolling = YES;
static NSString * const kMPDefaultEditorThemeName = @"Tomorrow+";
static NSString * const kMPDefaultHtmlStyleName = @"GitHub2";


@implementation MPPreferences

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    [self cleanupObsoleteAutosaveValues];

    NSString *version =
        [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];

    // This is a fresh install. Set default preferences.
    if (!self.firstVersionInstalled)
    {
        self.firstVersionInstalled = version;
        [self loadDefaultPreferences];

        // Post this after the initializer finishes to give others to listen
        // to this on construction.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
            [c postNotificationName:MPDidDetectFreshInstallationNotification
                             object:self];
        }];
    }
    [self loadDefaultUserDefaults];
    self.latestVersionInstalled = version;
    return self;
}


#pragma mark - Singleton

+ (instancetype)sharedInstance
{
    static MPPreferences *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSUserDefaults *)userDefaults
{
    return [NSUserDefaults standardUserDefaults];
}

- (BOOL)synchronize
{
    return [self.userDefaults synchronize];
}


#pragma mark - Accessors

// Each preference property is backed by an NSUserDefaults key of the same
// name. These macros expand a property into the matching typed getter/setter,
// replacing the runtime @dynamic synthesis the former PAPreferences base class
// provided. The first argument is the property/getter name (also the defaults
// key, via stringification); the second is its capitalized form for the setter
// selector.

#define MP_BOOL_PREF(name, Name) \
    - (BOOL)name { return [self.userDefaults boolForKey:@#name]; } \
    - (void)set##Name:(BOOL)value { \
        [self.userDefaults setBool:value forKey:@#name]; }

#define MP_INTEGER_PREF(name, Name) \
    - (NSInteger)name { return [self.userDefaults integerForKey:@#name]; } \
    - (void)set##Name:(NSInteger)value { \
        [self.userDefaults setInteger:value forKey:@#name]; }

#define MP_DOUBLE_PREF(name, Name) \
    - (CGFloat)name { return [self.userDefaults doubleForKey:@#name]; } \
    - (void)set##Name:(CGFloat)value { \
        [self.userDefaults setDouble:value forKey:@#name]; }

// The object setters route a nil value to -removeObjectForKey: (clearing the
// default) rather than -setObject:nil, which would raise. Setting these to nil
// is a real "reset to default" path (e.g. clearing editorStyleName).
#define MP_STRING_PREF(name, Name) \
    - (NSString *)name { return [self.userDefaults stringForKey:@#name]; } \
    - (void)set##Name:(NSString *)value { \
        if (value) \
            [self.userDefaults setObject:value forKey:@#name]; \
        else \
            [self.userDefaults removeObjectForKey:@#name]; }

#define MP_URL_PREF(name, Name) \
    - (NSURL *)name { return [self.userDefaults URLForKey:@#name]; } \
    - (void)set##Name:(NSURL *)value { \
        if (value) \
            [self.userDefaults setURL:value forKey:@#name]; \
        else \
            [self.userDefaults removeObjectForKey:@#name]; }

#define MP_DICTIONARY_PREF(name, Name) \
    - (NSDictionary *)name \
        { return [self.userDefaults dictionaryForKey:@#name]; } \
    - (void)set##Name:(NSDictionary *)value { \
        if (value) \
            [self.userDefaults setObject:value forKey:@#name]; \
        else \
            [self.userDefaults removeObjectForKey:@#name]; }

MP_STRING_PREF(firstVersionInstalled, FirstVersionInstalled)
MP_STRING_PREF(latestVersionInstalled, LatestVersionInstalled)
MP_BOOL_PREF(updateIncludesPreReleases, UpdateIncludesPreReleases)
MP_BOOL_PREF(supressesUntitledDocumentOnLaunch,
             SupressesUntitledDocumentOnLaunch)
MP_BOOL_PREF(createFileForLinkTarget, CreateFileForLinkTarget)

MP_BOOL_PREF(extensionIntraEmphasis, ExtensionIntraEmphasis)
MP_BOOL_PREF(extensionTables, ExtensionTables)
MP_BOOL_PREF(extensionFencedCode, ExtensionFencedCode)
MP_BOOL_PREF(extensionAutolink, ExtensionAutolink)
MP_BOOL_PREF(extensionStrikethough, ExtensionStrikethough)
MP_BOOL_PREF(extensionUnderline, ExtensionUnderline)
MP_BOOL_PREF(extensionSuperscript, ExtensionSuperscript)
MP_BOOL_PREF(extensionHighlight, ExtensionHighlight)
MP_BOOL_PREF(extensionFootnotes, ExtensionFootnotes)
MP_BOOL_PREF(extensionQuote, ExtensionQuote)
MP_BOOL_PREF(extensionSmartyPants, ExtensionSmartyPants)

MP_BOOL_PREF(markdownManualRender, MarkdownManualRender)

MP_BOOL_PREF(editorAutoIncrementNumberedLists,
             EditorAutoIncrementNumberedLists)
MP_BOOL_PREF(editorConvertTabs, EditorConvertTabs)
MP_BOOL_PREF(editorInsertPrefixInBlock, EditorInsertPrefixInBlock)
MP_BOOL_PREF(editorCompleteMatchingCharacters,
             EditorCompleteMatchingCharacters)
MP_BOOL_PREF(editorSyncScrolling, EditorSyncScrolling)
MP_BOOL_PREF(editorSmartHome, EditorSmartHome)
MP_STRING_PREF(editorStyleName, EditorStyleName)
MP_DOUBLE_PREF(editorHorizontalInset, EditorHorizontalInset)
MP_DOUBLE_PREF(editorVerticalInset, EditorVerticalInset)
MP_DOUBLE_PREF(editorLineSpacing, EditorLineSpacing)
MP_BOOL_PREF(editorWidthLimited, EditorWidthLimited)
MP_DOUBLE_PREF(editorMaximumWidth, EditorMaximumWidth)
MP_BOOL_PREF(editorOnRight, EditorOnRight)
MP_BOOL_PREF(editorShowWordCount, EditorShowWordCount)
MP_INTEGER_PREF(editorWordCountType, EditorWordCountType)
MP_BOOL_PREF(editorScrollsPastEnd, EditorScrollsPastEnd)
MP_BOOL_PREF(editorEnsuresNewlineAtEndOfFile,
             EditorEnsuresNewlineAtEndOfFile)
MP_INTEGER_PREF(editorUnorderedListMarkerType, EditorUnorderedListMarkerType)

MP_BOOL_PREF(previewZoomRelativeToBaseFontSize,
             PreviewZoomRelativeToBaseFontSize)

MP_STRING_PREF(htmlTemplateName, HtmlTemplateName)
MP_STRING_PREF(htmlStyleName, HtmlStyleName)
MP_BOOL_PREF(htmlDetectFrontMatter, HtmlDetectFrontMatter)
MP_BOOL_PREF(htmlTaskList, HtmlTaskList)
MP_BOOL_PREF(htmlHardWrap, HtmlHardWrap)
MP_BOOL_PREF(htmlMathJax, HtmlMathJax)
MP_BOOL_PREF(htmlMathJaxInlineDollar, HtmlMathJaxInlineDollar)
MP_BOOL_PREF(htmlSyntaxHighlighting, HtmlSyntaxHighlighting)
MP_URL_PREF(htmlDefaultDirectoryUrl, HtmlDefaultDirectoryUrl)
MP_STRING_PREF(htmlHighlightingThemeName, HtmlHighlightingThemeName)
MP_BOOL_PREF(htmlLineNumbers, HtmlLineNumbers)
MP_BOOL_PREF(htmlGraphviz, HtmlGraphviz)
MP_BOOL_PREF(htmlMermaid, HtmlMermaid)
MP_INTEGER_PREF(htmlCodeBlockAccessory, HtmlCodeBlockAccessory)
MP_BOOL_PREF(htmlRendersTOC, HtmlRendersTOC)
MP_INTEGER_PREF(htmlAssetLocalAccessScope, HtmlAssetLocalAccessScope)

MP_DOUBLE_PREF(printMarginTop, PrintMarginTop)
MP_DOUBLE_PREF(printMarginLeft, PrintMarginLeft)
MP_DOUBLE_PREF(printMarginBottom, PrintMarginBottom)
MP_DOUBLE_PREF(printMarginRight, PrintMarginRight)

// Private preference.
MP_DICTIONARY_PREF(editorBaseFontInfo, EditorBaseFontInfo)

#undef MP_BOOL_PREF
#undef MP_INTEGER_PREF
#undef MP_DOUBLE_PREF
#undef MP_STRING_PREF
#undef MP_URL_PREF
#undef MP_DICTIONARY_PREF

- (NSString *)editorBaseFontName
{
    return [self.editorBaseFontInfo[kMPDefaultEditorFontNameKey] copy];
}

- (CGFloat)editorBaseFontSize
{
    NSDictionary *info = self.editorBaseFontInfo;
    return [info[kMPDefaultEditorFontPointSizeKey] doubleValue];
}

- (NSFont *)editorBaseFont
{
    return [NSFont fontWithName:self.editorBaseFontName
                           size:self.editorBaseFontSize];
}

- (void)setEditorBaseFont:(NSFont *)font
{
    NSDictionary *info = @{
        kMPDefaultEditorFontNameKey: font.fontName,
        kMPDefaultEditorFontPointSizeKey: @(font.pointSize)
    };
    self.editorBaseFontInfo = info;
}

- (NSString *)editorUnorderedListMarker
{
    switch (self.editorUnorderedListMarkerType)
    {
        case MPUnorderedListMarkerAsterisk:
            return @"* ";
        case MPUnorderedListMarkerPlusSign:
            return @"+ ";
        case MPUnorderedListMarkerMinusSign:
            return @"- ";
        default:
            return @"* ";
    }
}

- (NSArray *)filesToOpen
{
    return [self.userDefaults objectForKey:kMPFilesToOpenKey
                              inSuiteNamed:kMPApplicationSuiteName];
}

- (void)setFilesToOpen:(NSArray *)filesToOpen
{
    [self.userDefaults setObject:filesToOpen
                          forKey:kMPFilesToOpenKey
                    inSuiteNamed:kMPApplicationSuiteName];
}

- (NSString *)pipedContentFileToOpen {
    return [self.userDefaults objectForKey:kMPPipedContentFileToOpen
                              inSuiteNamed:kMPApplicationSuiteName];
}

- (void)setPipedContentFileToOpen:(NSString *)pipedContentFileToOpenPath {
    [self.userDefaults setObject:pipedContentFileToOpenPath
                          forKey:kMPPipedContentFileToOpen
                    inSuiteNamed:kMPApplicationSuiteName];
}


#pragma mark - Private

- (void)cleanupObsoleteAutosaveValues
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *keysToRemove = [NSMutableArray array];
    for (NSString *key in defaults.dictionaryRepresentation)
    {
        for (NSString *p in @[@"NSSplitView Subview Frames", @"NSWindow Frame"])
        {
            if (![key hasPrefix:p] || key.length < p.length + 1)
                continue;
            NSString *path = [key substringFromIndex:p.length + 1];
            NSURL *url = [NSURL URLWithString:path];
            if (!url.isFileURL)
                continue;

            NSFileManager *manager = [NSFileManager defaultManager];
            if (![manager fileExistsAtPath:url.path])
                [keysToRemove addObject:key];
            break;
        }
    }
    for (NSString *key in keysToRemove)
        [defaults removeObjectForKey:key];
}

/** Load app-default preferences on first launch.
 *
 * Preferences that need to be initialized manually are put here, and will be
 * applied when the user launches MacDown the first time.
 *
 * Avoid putting preferences that doe not need initialization here. E.g. a
 * boolean preference defaults to `NO` implicitly (because `nil.booleanValue` is
 * `NO` in Objective-C), thus does not need initialization.
 *
 * Note that since this is called only when the user launches the app the first
 * time, new preferences that breaks backward compatibility should NOT be put
 * here. An example would be adding a boolean config to turn OFF an existing
 * functionality. If you add the defualt-loading code here, existing users
 * upgrading from an old version will not have this method invoked, thus
 * effecting app behavior.
 *
 * @see -loadDefaultUserDefaults
 */
- (void)loadDefaultPreferences
{
    self.extensionIntraEmphasis = YES;
    self.extensionTables = YES;
    self.extensionFencedCode = YES;
    self.extensionFootnotes = YES;
    self.editorBaseFontInfo = @{
        kMPDefaultEditorFontNameKey: kMPDefaultEditorFontName,
        kMPDefaultEditorFontPointSizeKey: @(kMPDefaultEditorFontPointSize),
    };
    self.editorStyleName = kMPDefaultEditorThemeName;
    self.editorHorizontalInset = kMPDefaultEditorHorizontalInset;
    self.editorVerticalInset = kMPDefaultEditorVerticalInset;
    self.editorLineSpacing = kMPDefaultEditorLineSpacing;
    self.editorSyncScrolling = kMPDefaultEditorSyncScrolling;
    self.htmlStyleName = kMPDefaultHtmlStyleName;
    self.htmlDefaultDirectoryUrl = [NSURL fileURLWithPath:NSHomeDirectory()
                                              isDirectory:YES];
}

/** Load default preferences when the app launches.
 *
 * Preferences that need to be initialized manually are put here, and will be
 * applied when the user launches MacDown.
 *
 * This differs from -loadDefaultPreferences in that it is invoked *every time*
 * MacDown is launched, making it suitable to perform backward-compatibility
 * checks.
 *
 * @see -loadDefaultPreferences
 */
- (void)loadDefaultUserDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:@"editorMaximumWidth"])
        self.editorMaximumWidth = 1000.0;
    if (![defaults objectForKey:@"editorAutoIncrementNumberedLists"])
        self.editorAutoIncrementNumberedLists = YES;
    if (![defaults objectForKey:@"editorInsertPrefixInBlock"])
        self.editorInsertPrefixInBlock = YES;
    if (![defaults objectForKey:@"htmlTemplateName"])
        self.htmlTemplateName = @"Default";
    // Default print/PDF margins: 1 inch on every side.
    if (![defaults objectForKey:@"printMarginTop"])
        self.printMarginTop = kMPPointsPerInch;
    if (![defaults objectForKey:@"printMarginLeft"])
        self.printMarginLeft = kMPPointsPerInch;
    if (![defaults objectForKey:@"printMarginBottom"])
        self.printMarginBottom = kMPPointsPerInch;
    if (![defaults objectForKey:@"printMarginRight"])
        self.printMarginRight = kMPPointsPerInch;
}

@end
