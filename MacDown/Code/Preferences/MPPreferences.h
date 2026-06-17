//
//  MPPreferences.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>


extern NSString * const MPDidDetectFreshInstallationNotification;


// A singleton wrapper over NSUserDefaults. Each property below is backed by a
// standardUserDefaults key of the same name (see the typed accessor macros in
// MPPreferences.m). Replaces the former PAPreferences base class, whose runtime
// @dynamic synthesis this makes explicit (bead macdown-e2h).
@interface MPPreferences : NSObject

+ (instancetype)sharedInstance;
- (NSUserDefaults *)userDefaults;
- (BOOL)synchronize;

@property (assign) NSString *firstVersionInstalled;
@property (assign) NSString *latestVersionInstalled;
@property (assign) BOOL updateIncludesPreReleases;
@property (assign) BOOL supressesUntitledDocumentOnLaunch;
@property (assign) BOOL createFileForLinkTarget;

// Extension flags.
@property (assign) BOOL extensionIntraEmphasis;
@property (assign) BOOL extensionTables;
@property (assign) BOOL extensionFencedCode;
@property (assign) BOOL extensionAutolink;
@property (assign) BOOL extensionStrikethough;
@property (assign) BOOL extensionUnderline;
@property (assign) BOOL extensionSuperscript;
@property (assign) BOOL extensionHighlight;
@property (assign) BOOL extensionFootnotes;
@property (assign) BOOL extensionQuote;
@property (assign) BOOL extensionSmartyPants;

@property (assign) BOOL markdownManualRender;

@property (assign) NSDictionary *editorBaseFontInfo;
@property (assign) BOOL editorAutoIncrementNumberedLists;
@property (assign) BOOL editorConvertTabs;
@property (assign) BOOL editorInsertPrefixInBlock;
@property (assign) BOOL editorCompleteMatchingCharacters;
@property (assign) BOOL editorSyncScrolling;
@property (assign) BOOL editorSmartHome;
@property (assign) NSString *editorStyleName;
@property (assign) CGFloat editorHorizontalInset;
@property (assign) CGFloat editorVerticalInset;
@property (assign) CGFloat editorLineSpacing;
@property (assign) BOOL editorWidthLimited;
@property (assign) CGFloat editorMaximumWidth;
@property (assign) BOOL editorOnRight;
@property (assign) BOOL editorShowWordCount;
@property (assign) NSInteger editorWordCountType;
@property (assign) BOOL editorScrollsPastEnd;
@property (assign) BOOL editorEnsuresNewlineAtEndOfFile;
@property (assign) NSInteger editorUnorderedListMarkerType;

@property (assign) BOOL previewZoomRelativeToBaseFontSize;

@property (assign) NSString *htmlStyleName;
@property (assign) BOOL htmlDetectFrontMatter;
@property (assign) BOOL htmlTaskList;
@property (assign) BOOL htmlHardWrap;
@property (assign) BOOL htmlMathJax;
@property (assign) BOOL htmlMathJaxInlineDollar;
@property (assign) BOOL htmlSyntaxHighlighting;
@property (assign) NSString *htmlHighlightingThemeName;
@property (assign) BOOL htmlLineNumbers;
@property (assign) BOOL htmlGraphviz;
@property (assign) BOOL htmlMermaid;
@property (assign) NSInteger htmlCodeBlockAccessory;
@property (assign) NSURL *htmlDefaultDirectoryUrl;
@property (assign) BOOL htmlRendersTOC;

// How far outside the document's directory the preview may read local
// resources. Maps to MPAssetLocalAccessScope; 0 (document subtree) is the
// safe default.
@property (assign) NSInteger htmlAssetLocalAccessScope;

// Preferred print / PDF margins, in points. Each defaults to 72 (1 inch) and
// is clamped up to the printer's imageable area at print time (macdown-ppi.1).
@property (assign) CGFloat printMarginTop;
@property (assign) CGFloat printMarginLeft;
@property (assign) CGFloat printMarginBottom;
@property (assign) CGFloat printMarginRight;

// Calculated values.
@property (readonly) NSString *editorBaseFontName;
@property (readonly) CGFloat editorBaseFontSize;
@property (nonatomic, assign) NSFont *editorBaseFont;
@property (readonly) NSString *editorUnorderedListMarker;

- (instancetype)init;

// Convinience methods.
@property (nonatomic, assign) NSArray *filesToOpen;
@property (nonatomic, assign) NSString *pipedContentFileToOpen;

@end
