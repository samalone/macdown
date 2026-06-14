//
//  MPDocument.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocument.h"
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <JJPluralForm/JJPluralForm.h>
#import <hoedown/html.h>
#import "hoedown_html_patch.h"
#import "HGMarkdownHighlighter.h"
#import "MPUtilities.h"
#import "MPAutosaving.h"
#import "NSColor+HTML.h"
#import "NSDocumentController+Document.h"
#import "NSPasteboard+Types.h"
#import "NSString+Lookup.h"
#import "NSTextView+Autocomplete.h"
#import "MPPreferences.h"
#import "MPDocumentSplitView.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPExportPanelAccessoryViewController.h"
#import "MPAssetSchemeHandler.h"
#import "MPToolbarController.h"

static NSString * const kMPDefaultAutosaveName = @"Untitled";

// Name of the script message MathJax's init.js posts when it finishes the
// initial typeset (see Resources/MathJax/init.js).
static NSString * const kMPMathJaxEndMessageName = @"mathJaxEnd";

// Counts words/characters in the rendered preview the way DOMNode+Text did
// (the legacy WebView's synchronous DOM walk): skip script/style/head; a
// <pre><code> block contributes no words; an inline <code> counts as one word
// if it has word content; characters exclude newlines, and "no spaces" also
// excludes whitespace. Returns {words, characters, charsNoSpace}.
static NSString * const kMPWordCountScript =
    @"(function(){"
    @"var seg=(typeof Intl!=='undefined'&&Intl.Segmenter)?"
    @"new Intl.Segmenter(undefined,{granularity:'word'}):null;"
    @"function wc(t){if(seg){var n=0,s;"
    // Older WebKit (pre-Safari 27) reports isWordLike===false for purely
    // numeric segments, which would drop numbers like "2026" from the
    // count; also treat any letter/number segment as a word.
    @"for(s of seg.segment(t)){"
    @"if(s.isWordLike||/[\\p{L}\\p{N}]/u.test(s.segment)){n++;}"
    @"}return n;}"
    @"var m=t.match(/\\S+/g);return m?m.length:0;}"
    @"var nl=/[\\u000A-\\u000D\\u0085\\u2028\\u2029]/g;"
    @"var ws=/[\\s\\u0085]/g;"
    @"function kids(node,a){"
    @"for(var c=node.firstChild;c;c=c.nextSibling){walk(c,a);}}"
    @"function walk(node,a){var ty=node.nodeType;"
    @"if(ty===3||ty===4){var v=node.nodeValue||'';"
    @"a.w+=wc(v);a.c+=v.replace(nl,'').length;"
    @"a.s+=v.replace(ws,'').length;return;}"
    @"if(ty!==1&&ty!==9&&ty!==11){return;}"
    @"var tag=node.tagName?node.tagName.toUpperCase():'';"
    @"if(tag==='SCRIPT'||tag==='STYLE'||tag==='HEAD'){return;}"
    @"if(tag==='CODE'){var sub={w:0,c:0,s:0};kids(node,sub);"
    @"a.c+=sub.c;a.s+=sub.s;var p=node.parentElement;"
    @"var pre=p&&p.tagName&&p.tagName.toUpperCase()==='PRE';"
    @"if(!pre){a.w+=sub.w>0?1:0;}return;}"
    @"kids(node,a);}"
    @"var a={w:0,c:0,s:0};"
    @"if(document.body){walk(document.body,a);}"
    @"return {words:a.w,characters:a.c,charsNoSpace:a.s};"
    @"})();";

// Reads the preview's scroll-sync metrics in one round trip: the absolute
// document-Y position of every header / standalone image (the reference nodes
// the editor scroll is mapped onto), plus the document and viewport heights.
// Header tops are made absolute (getBoundingClientRect is viewport-relative)
// by adding the current scroll offset, matching window.scrollTo's coordinates.
static NSString * const kMPPreviewMetricsScript =
    @"(function(){"
    @"var ns=document.querySelectorAll("
    @"'h1,h2,h3,h4,h5,h6,img:only-child');"
    @"var sy=window.scrollY||0;var hs=[];"
    @"for(var i=0;i<ns.length;i++){"
    @"hs.push(ns[i].getBoundingClientRect().top+sy);}"
    @"return {headers:hs,"
    @"contentHeight:document.documentElement.scrollHeight,"
    @"visibleHeight:window.innerHeight};"
    @"})();";


// WKUserContentController retains its script-message handlers strongly, which
// would form a retain cycle through the web view's configuration back to the
// document. This forwards messages to a weakly-held delegate instead.
@interface MPWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate;
@end

@implementation MPWeakScriptMessageHandler
{
    __weak id<WKScriptMessageHandler> _delegate;
}

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate
{
    self = [super init];
    if (self)
        _delegate = delegate;
    return self;
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    [_delegate userContentController:controller
            didReceiveScriptMessage:message];
}

@end


NS_INLINE NSString *MPEditorPreferenceKeyWithValueKey(NSString *key)
{
    if (!key.length)
        return @"editor";
    NSString *first = [[key substringToIndex:1] uppercaseString];
    NSString *rest = [key substringFromIndex:1];
    return [NSString stringWithFormat:@"editor%@%@", first, rest];
}

NS_INLINE NSDictionary *MPEditorKeysToObserve()
{
    static NSDictionary *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = @{@"automaticDashSubstitutionEnabled": @NO,
                 @"automaticDataDetectionEnabled": @NO,
                 @"automaticQuoteSubstitutionEnabled": @NO,
                 @"automaticSpellingCorrectionEnabled": @NO,
                 @"automaticTextReplacementEnabled": @NO,
                 @"continuousSpellCheckingEnabled": @NO,
                 @"enabledTextCheckingTypes": @(NSTextCheckingAllTypes),
                 @"grammarCheckingEnabled": @NO};
    });
    return keys;
}

NS_INLINE NSSet *MPEditorPreferencesToObserve()
{
    static NSSet *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = [NSSet setWithObjects:
            @"editorBaseFontInfo", @"extensionFootnotes",
            @"editorHorizontalInset", @"editorVerticalInset",
            @"editorWidthLimited", @"editorMaximumWidth", @"editorLineSpacing",
            @"editorOnRight", @"editorStyleName", @"editorShowWordCount",
            @"editorScrollsPastEnd", nil
        ];
    });
    return keys;
}

NS_INLINE NSString *MPRectStringForAutosaveName(NSString *name)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"NSWindow Frame %@", name];
    NSString *rectString = [defaults objectForKey:key];
    return rectString;
}

@implementation NSURL (Convert)

- (NSString *)absoluteBaseURLString
{
    // Remove fragment (#anchor) and query string.
    NSString *base = self.absoluteString;
    base = [base componentsSeparatedByString:@"?"].firstObject;
    base = [base componentsSeparatedByString:@"#"].firstObject;
    return base;
}

@end


@implementation MPPreferences (Hoedown)
- (int)extensionFlags
{
    int flags = 0;
    if (self.extensionAutolink)
        flags |= HOEDOWN_EXT_AUTOLINK;
    if (self.extensionFencedCode)
        flags |= HOEDOWN_EXT_FENCED_CODE;
    if (self.extensionFootnotes)
        flags |= HOEDOWN_EXT_FOOTNOTES;
    if (self.extensionHighlight)
        flags |= HOEDOWN_EXT_HIGHLIGHT;
    if (!self.extensionIntraEmphasis)
        flags |= HOEDOWN_EXT_NO_INTRA_EMPHASIS;
    if (self.extensionQuote)
        flags |= HOEDOWN_EXT_QUOTE;
    if (self.extensionStrikethough)
        flags |= HOEDOWN_EXT_STRIKETHROUGH;
    if (self.extensionSuperscript)
        flags |= HOEDOWN_EXT_SUPERSCRIPT;
    if (self.extensionTables)
        flags |= HOEDOWN_EXT_TABLES;
    if (self.extensionUnderline)
        flags |= HOEDOWN_EXT_UNDERLINE;
    if (self.htmlMathJax)
        flags |= HOEDOWN_EXT_MATH;
    if (self.htmlMathJaxInlineDollar)
        flags |= HOEDOWN_EXT_MATH_EXPLICIT;
    return flags;
}

- (int)rendererFlags
{
    int flags = 0;
    if (self.htmlTaskList)
        flags |= HOEDOWN_HTML_USE_TASK_LIST;
    if (self.htmlLineNumbers)
        flags |= HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS;
    if (self.htmlHardWrap)
        flags |= HOEDOWN_HTML_HARD_WRAP;
    if (self.htmlCodeBlockAccessory == MPCodeBlockAccessoryCustom)
        flags |= HOEDOWN_HTML_BLOCKCODE_INFORMATION;
    return flags;
}
@end


@interface MPDocument ()
    <NSSplitViewDelegate, NSTextViewDelegate,
     WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
     MPAutosaving, MPRendererDataSource, MPRendererDelegate>

typedef NS_ENUM(NSUInteger, MPWordCountType) {
    MPWordCountTypeWord,
    MPWordCountTypeCharacter,
    MPWordCountTypeCharacterNoSpaces,
};

@property (weak) IBOutlet NSToolbar *toolbar;
@property (weak) IBOutlet MPDocumentSplitView *splitView;
@property (weak) IBOutlet NSView *editorContainer;
@property (unsafe_unretained) IBOutlet MPEditorView *editor;
@property (weak) IBOutlet NSLayoutConstraint *editorPaddingBottom;
@property (weak) IBOutlet NSView *previewContainer;
@property (strong) WKWebView *preview;
@property (weak) IBOutlet NSPopUpButton *wordCountWidget;
@property (strong) IBOutlet MPToolbarController *toolbarController;
@property (copy, nonatomic) NSString *autosaveName;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (strong) MPRenderer *renderer;
@property (strong) MPAssetSchemeHandler *schemeHandler;
@property CGFloat previousSplitRatio;
@property BOOL manualRender;
@property BOOL copying;
@property BOOL printing;
@property BOOL shouldHandleBoundsChange;
@property BOOL isPreviewReady;
@property (strong) NSURL *currentBaseUrl;
@property (nonatomic, readonly) BOOL needsHtml;
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (strong) NSMenuItem *wordsMenuItem;
@property (strong) NSMenuItem *charMenuItem;
@property (strong) NSMenuItem *charNoSpacesMenuItem;
@property (nonatomic) BOOL needsToUnregister;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) BOOL renderToWebPending;
// Whether the load-completion handler has already run for the current page
// load (it fires once, from either the MathJax message or didFinishNavigation).
@property (nonatomic) BOOL previewLoadCompleted;
// Whether the current navigation has finished loading. A mathJaxEnd message is
// only honored once this is YES, so a stale message from a superseded load
// (delivered during the next load's provisional phase) can't complete it early
// — before commit disables window flush — and freeze the preview.
@property (nonatomic) BOOL previewNavigationFinished;
// Whether a mathJaxEnd message has been received for the current load. MathJax
// 2 can finish before didFinishNavigation (e.g. cached/simple math), so an
// early message is recorded here and consumed when the navigation finishes,
// rather than discarded (which would stall completion until the fallback).
@property (nonatomic) BOOL previewMathJaxReported;
// Bumped at the start of each page load, so a deferred fallback can tell
// whether it still belongs to the load that scheduled it.
@property (nonatomic) NSUInteger previewLoadGeneration;
// Whether the HTML currently loaded in the preview was rendered with MathJax,
// captured at load time so completion timing doesn't depend on the live
// preference (which the user could toggle mid-load).
@property (nonatomic) BOOL currentLoadHasMathJax;
// The preview body's background color, read asynchronously after each load and
// cached so -redrawDivider can use it synchronously (WKWebView has no
// synchronous DOM). Nil until the first read completes.
@property (nonatomic, strong) NSColor *previewBackgroundColor;
// The web view's user content controller, held strongly so the mathJaxEnd
// handler is removed from the same instance it was added to (-[WKWebView
// configuration] returns a copy, not the live controller).
@property (nonatomic, strong) WKUserContentController *userContentController;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
// Preview scroll metrics (document height and viewport height), read
// asynchronously from JS after each load / at scroll start and cached so
// -syncScrollers can run synchronously per scroll frame. WKWebView exposes no
// AppKit scroll view to query, so these stand in for the legacy
// documentView/contentView bounds heights.
@property (nonatomic) CGFloat previewContentHeight;
@property (nonatomic) CGFloat previewVisibleHeight;
@property (nonatomic) BOOL inLiveScroll;

// Store file content in initializer until nib is loaded.
@property (copy) NSString *loadedString;

- (void)scaleWebview;
- (void)syncScrollers;
- (void)refreshPreviewBackground;
- (void)updateHeaderLocations;
- (void)updateEditorHeaderLocations;
- (void)refreshPreviewHeaderLocations;

@end

static void (^MPGetPreviewLoadingCompletionHandler(MPDocument *doc))()
{
    __weak MPDocument *weakObj = doc;
    return ^{
        MPDocument *strongObj = weakObj;
        if (!strongObj)
            return;
        WKWebView *webView = strongObj.preview;
        NSWindow *window = webView.window;
        if (window)
        {
            @synchronized(window) {
                if (window.isFlushWindowDisabled)
                    [window enableFlushWindow];
            }
        }
        [strongObj scaleWebview];
        [strongObj refreshPreviewBackground];

        // Restore the editor→preview scroll alignment after a load. The editor
        // header locations are computed synchronously here; the preview header
        // tops and scroll metrics are fetched asynchronously and re-run
        // -syncScrollers once they arrive (the synchronous call below uses
        // whatever is still cached, then the async one corrects it against the
        // freshly-laid-out preview). The preview→editor direction is not
        // restored: WKWebView exposes no scroll view to observe.
        if (strongObj.preferences.editorSyncScrolling)
        {
            [strongObj updateHeaderLocations];
            [strongObj syncScrollers];
        }
    };
}


@implementation MPDocument

#pragma mark - Accessor

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSString *)markdown
{
    return self.editor.string;
}

- (void)setMarkdown:(NSString *)markdown
{
    self.editor.string = markdown;
}

- (NSString *)html
{
    return self.renderer.currentHtml;
}

- (BOOL)toolbarVisible
{
    return self.windowForSheet.toolbar.visible;
}

- (BOOL)previewVisible
{
    return (self.preview.frame.size.width != 0.0);
}

- (BOOL)editorVisible
{
    return (self.editorContainer.frame.size.width != 0.0);
}

- (BOOL)needsHtml
{
    if (self.preferences.markdownManualRender)
        return NO;
    return (self.previewVisible || self.preferences.editorShowWordCount);
}

- (void)setTotalWords:(NSUInteger)value
{
    _totalWords = value;
    NSString *key = NSLocalizedString(@"WORDS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.wordsMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharacters:(NSUInteger)value
{
    _totalCharacters = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharactersNoSpaces:(NSUInteger)value
{
    _totalCharactersNoSpaces = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_NO_SPACES_PLURAL_STRING",
                                      @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charNoSpacesMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setAutosaveName:(NSString *)autosaveName
{
    _autosaveName = autosaveName;
    self.splitView.autosaveName = autosaveName;
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.isPreviewReady = NO;
    self.shouldHandleBoundsChange = YES;
    self.previousSplitRatio = -1.0;
    
    return self;
}

- (NSString *)windowNibName
{
    return @"MPDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // All files use their absolute path to keep their window states.
    NSString *autosaveName = kMPDefaultAutosaveName;
    if (self.fileURL)
        autosaveName = self.fileURL.absoluteString;
    controller.window.frameAutosaveName = autosaveName;
    self.autosaveName = autosaveName;

    // Perform initial resizing manually because for some reason untitled
    // documents do not pick up the autosaved frame automatically in 10.10.
    NSString *rectString = MPRectStringForAutosaveName(autosaveName);
    if (!rectString)
        rectString = MPRectStringForAutosaveName(kMPDefaultAutosaveName);
    if (rectString)
        [controller.window setFrameFromString:rectString];

    self.highlighter =
        [[HGMarkdownHighlighter alloc] initWithTextView:self.editor
                                           waitInterval:0.0];
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self;
    self.renderer.delegate = self;

    for (NSString *key in MPEditorPreferencesToObserve())
    {
        [defaults addObserver:self forKeyPath:key
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
    for (NSString *key in MPEditorKeysToObserve())
    {
        [self.editor addObserver:self forKeyPath:key
                         options:NSKeyValueObservingOptionNew context:NULL];
    }

    self.editor.postsFrameChangedNotifications = YES;

    // Create the preview WKWebView in code: the asset scheme handler must be
    // registered on the configuration before the view exists, which an
    // IB-instantiated WKWebView does not allow.
    self.schemeHandler = [[MPAssetSchemeHandler alloc] init];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config setURLSchemeHandler:self.schemeHandler
                   forURLScheme:MPAssetURLScheme];
    // MathJax's init.js posts here when it finishes typesetting, so the
    // load-completion handler can run after the math is laid out. The weak
    // wrapper avoids a retain cycle (the controller retains its handlers).
    MPWeakScriptMessageHandler *mathJaxHandler =
        [[MPWeakScriptMessageHandler alloc] initWithDelegate:self];
    WKUserContentController *content = config.userContentController;
    self.userContentController = content;
    [content addScriptMessageHandler:mathJaxHandler
                                name:kMPMathJaxEndMessageName];
    WKWebView *preview =
        [[WKWebView alloc] initWithFrame:self.previewContainer.bounds
                           configuration:config];
    preview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    preview.navigationDelegate = self;
    preview.UIDelegate = self;
    [self.previewContainer addSubview:preview];
    self.preview = preview;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(editorTextDidChange:)
                   name:NSTextDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(userDefaultsDidChange:)
                   name:NSUserDefaultsDidChangeNotification
                 object:[NSUserDefaults standardUserDefaults]];
    [center addObserver:self selector:@selector(editorBoundsDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.editor.enclosingScrollView.contentView];
    [center addObserver:self selector:@selector(editorFrameDidChange:)
                   name:NSViewFrameDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(didRequestEditorReload:)
                   name:MPDidRequestEditorSetupNotification object:nil];
    [center addObserver:self selector:@selector(didRequestPreviewReload:)
                   name:MPDidRequestPreviewRenderNotification object:nil];
    [center addObserver:self selector:@selector(willStartLiveScroll:)
                   name:NSScrollViewWillStartLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    [center addObserver:self selector:@selector(didEndLiveScroll:)
                   name:NSScrollViewDidEndLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    // (Preview live-scroll observation is restored with scroll-sync in
    //  macdown-8tk.5.4; WKWebView exposes no AppKit scroll view to observe.)

    self.needsToUnregister = YES;

    self.wordsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                             keyEquivalent:@""];
    self.charMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                            keyEquivalent:@""];
    self.charNoSpacesMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                           action:NULL
                                                    keyEquivalent:@""];

    NSPopUpButton *wordCountWidget = self.wordCountWidget;
    [wordCountWidget removeAllItems];
    [wordCountWidget.menu addItem:self.wordsMenuItem];
    [wordCountWidget.menu addItem:self.charMenuItem];
    [wordCountWidget.menu addItem:self.charNoSpacesMenuItem];
    [wordCountWidget selectItemAtIndex:self.preferences.editorWordCountType];
    wordCountWidget.alphaValue = 0.9;
    wordCountWidget.hidden = !self.preferences.editorShowWordCount;
    wordCountWidget.enabled = NO;

    // These needs to be queued until after the window is shown, so that editor
    // can have the correct dimention for size-limiting and stuff. See
    // https://github.com/uranusjr/macdown/issues/236
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self setupEditor:nil];
        [self redrawDivider];
        [self reloadFromLoadedString];
    }];
}

- (void)reloadFromLoadedString
{
    if (self.loadedString && self.editor && self.renderer && self.highlighter)
    {
        self.editor.string = self.loadedString;
        self.loadedString = nil;
        [self.renderer parseAndRenderNow];
        [self.highlighter parseAndHighlightNow];
    }
}

- (void)close
{
    if (self.needsToUnregister) 
    {
        // Close can be called multiple times, but this can only be done once.
        // http://www.cocoabuilder.com/archive/cocoa/240166-nsdocument-close-method-calls-itself.html
        self.needsToUnregister = NO;

        // Need to cleanup these so that callbacks won't crash the app.
        [self.highlighter deactivate];
        self.highlighter.targetTextView = nil;
        self.highlighter = nil;
        self.renderer = nil;
        self.preview.navigationDelegate = nil;
        self.preview.UIDelegate = nil;
        [self.userContentController
            removeScriptMessageHandlerForName:kMPMathJaxEndMessageName];

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        for (NSString *key in MPEditorPreferencesToObserve())
            [defaults removeObserver:self forKeyPath:key];
        for (NSString *key in MPEditorKeysToObserve())
            [self.editor removeObserver:self forKeyPath:key];
    }

    [super close];
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

+ (NSArray *)writableTypes
{
    return @[@"net.daringfireball.markdown"];
}

- (BOOL)isDocumentEdited
{
    // Prevent save dialog on an unnamed, empty document. The file will still
    // show as modified (because it is), but no save dialog will be presented
    // when the user closes it.
    if (!self.presentedItemURL && !self.editor.string.length)
        return NO;
    return [super isDocumentEdited];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
             error:(NSError *__autoreleasing *)outError
{
    if (self.preferences.editorEnsuresNewlineAtEndOfFile)
    {
        NSCharacterSet *newline = [NSCharacterSet newlineCharacterSet];
        NSString *text = self.editor.string;
        NSUInteger end = text.length;
        if (end && ![newline characterIsMember:[text characterAtIndex:end - 1]])
        {
            NSRange selection = self.editor.selectedRange;
            [self.editor insertText:@"\n" replacementRange:NSMakeRange(end, 0)];
            self.editor.selectedRange = selection;
        }
    }
    return [super writeToURL:url ofType:typeName error:outError];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    return [self.editor.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
               error:(NSError **)outError
{
    NSString *content = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!content)
        return NO;

    self.loadedString = content;
    [self reloadFromLoadedString];
    return YES;
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
    savePanel.extensionHidden = NO;
    if (self.fileURL && self.fileURL.isFileURL)
    {
        NSString *path = self.fileURL.path;

        // Use path of parent directory if this is a file. Otherwise this is it.
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path
                                                           isDirectory:&isDir];
        if (!exists || !isDir)
            path = [path stringByDeletingLastPathComponent];

        savePanel.directoryURL = [NSURL fileURLWithPath:path];
    }
    else
    {
        // Suggest a file name for new documents.
        NSString *fileName = self.presumedFileName;
        if (fileName && ![fileName hasExtension:@"md"])
        {
            fileName = [fileName stringByAppendingPathExtension:@"md"];
            savePanel.nameFieldStringValue = fileName;
        }
    }
    
    // Get supported content types from plist
    static NSArray<UTType *> *supportedTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<UTType *> *types = [NSMutableArray array];
        NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
        for (NSDictionary *docType in infoDict[@"CFBundleDocumentTypes"])
        {
            NSArray *exts = docType[@"CFBundleTypeExtensions"];
            for (NSString *ext in exts)
            {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                if (type)
                    [types addObject:type];
            }
        }
        supportedTypes = [types copy];
    });

    savePanel.allowedContentTypes = supportedTypes;
    savePanel.allowsOtherFileTypes = YES; // Allow all extensions.
    
    return [super prepareSavePanel:savePanel];
}

- (NSPrintInfo *)printInfo
{
    NSPrintInfo *info = [super printInfo];
    if (!info)
        info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSPrintingPaginationModeAutomatic;
    info.verticalPagination = NSPrintingPaginationModeAutomatic;
    info.verticallyCentered = NO;
    info.topMargin = 50.0;
    info.leftMargin = 0.0;
    info.rightMargin = 0.0;
    info.bottomMargin = 50.0;
    return info;
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings
                                           error:(NSError *__autoreleasing *)e
{
    NSPrintInfo *info = [self.printInfo copy];
    [info.dictionary addEntriesFromDictionary:printSettings];

    NSPrintOperation *op = [self.preview printOperationWithPrintInfo:info];
    return op;
}

- (void)printDocumentWithSettings:(NSDictionary *)printSettings
                   showPrintPanel:(BOOL)showPrintPanel delegate:(id)delegate
                 didPrintSelector:(SEL)selector contextInfo:(void *)contextInfo
{
    self.printing = YES;
    NSInvocation *invocation = nil;
    if (delegate && selector)
    {
        NSMethodSignature *signature =
            [NSMethodSignature methodSignatureForSelector:selector];
        invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = delegate;
        if (contextInfo)
            [invocation setArgument:&contextInfo atIndex:2];
    }
    [super printDocumentWithSettings:printSettings
                      showPrintPanel:showPrintPanel delegate:self
                    didPrintSelector:@selector(document:didPrint:context:)
                         contextInfo:(void *)invocation];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    BOOL result = [super validateUserInterfaceItem:item];
    SEL action = item.action;
    if (action == @selector(toggleToolbar:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.title = self.toolbarVisible ?
            NSLocalizedString(@"Hide Toolbar",
                              @"Toggle reveal toolbar") :
            NSLocalizedString(@"Show Toolbar",
                              @"Toggle reveal toolbar");
    }
    else if (action == @selector(togglePreviewPane:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.hidden = (!self.previewVisible && self.previousSplitRatio < 0.0);
        it.title = self.previewVisible ?
            NSLocalizedString(@"Hide Preview Pane",
                              @"Toggle preview pane menu item") :
            NSLocalizedString(@"Restore Preview Pane",
                              @"Toggle preview pane menu item");

    }
    else if (action == @selector(toggleEditorPane:))
    {
        NSMenuItem *it = (NSMenuItem*)item;
        it.title = self.editorVisible ?
        NSLocalizedString(@"Hide Editor Pane",
                          @"Toggle editor pane menu item") :
        NSLocalizedString(@"Restore Editor Pane",
                          @"Toggle editor pane menu item");
    }
    return result;
}


#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [self redrawDivider];
    self.editor.editable = self.editorVisible;
}


#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertTab:))
        return ![self textViewShouldInsertTab:textView];
    else if (commandSelector == @selector(insertBacktab:))
        return ![self textViewShouldInsertBacktab:textView];
    else if (commandSelector == @selector(insertNewline:))
        return ![self textViewShouldInsertNewline:textView];
    else if (commandSelector == @selector(deleteBackward:))
        return ![self textViewShouldDeleteBackward:textView];
    else if (commandSelector == @selector(moveToLeftEndOfLine:))
        return ![self textViewShouldMoveToLeftEndOfLine:textView];
    return NO;
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range
                                              replacementString:(NSString *)str
{
    // Ignore if this originates from an IM marked text commit event.
    if (NSIntersectionRange(textView.markedRange, range).length)
        return YES;

    if (self.preferences.editorCompleteMatchingCharacters)
    {
        BOOL strikethrough = self.preferences.extensionStrikethough;
        if ([textView completeMatchingCharactersForTextInRange:range
                                                    withString:str
                                          strikethroughEnabled:strikethrough])
            return NO;
    }
    
	// For every change, set the typing attributes
	if (range.location > 0) {
		NSRange prevRange = range;
		prevRange.location -= 1;
		prevRange.length = 1;

		NSDictionary *attr = [[textView attributedString] fontAttributesInRange:prevRange];
		[textView setTypingAttributes:attr];
	}

    return YES;
}

#pragma mark - Fake NSTextViewDelegate

- (BOOL)textViewShouldInsertTab:(NSTextView *)textView
{
    if (textView.selectedRange.length != 0)
    {
        [self indent:nil];
        return NO;
    }
    else if (self.preferences.editorConvertTabs)
    {
        [textView insertSpacesForTab];
        return NO;
    }
    return YES;
}

- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView
{
    [self unindent:nil];
    return NO;
}

- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView
{
    if ([textView insertMappedContent])
        return NO;

    BOOL inserts = self.preferences.editorInsertPrefixInBlock;
    if (inserts && [textView completeNextListItem:
            self.preferences.editorAutoIncrementNumberedLists])
        return NO;
    if (inserts && [textView completeNextBlockquoteLine])
        return NO;
    if ([textView completeNextIndentedLine])
        return NO;
    return YES;
}

- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView
{
    NSRange selectedRange = textView.selectedRange;
    if (self.preferences.editorCompleteMatchingCharacters)
    {
        NSUInteger location = selectedRange.location;
        if ([textView deleteMatchingCharactersAround:location])
            return NO;
    }
    if (self.preferences.editorConvertTabs && !selectedRange.length)
    {
        NSUInteger location = selectedRange.location;
        if ([textView unindentForSpacesBefore:location])
            return NO;
    }
    return YES;
}

- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView
{
    if (!self.preferences.editorSmartHome)
        return YES;
    NSUInteger cur = textView.selectedRange.location;
    NSUInteger location =
        [textView.string locationOfFirstNonWhitespaceCharacterInLineBefore:cur];
    if (location == cur || cur == 0)
        return YES;
    else if (cur >= textView.string.length)
        cur = textView.string.length - 1;

    // We don't want to jump rows when the line is wrapped. (#103)
    // If the line is wrapped, the target will be higher than the current glyph.
    NSLayoutManager *manager = textView.layoutManager;
    NSTextContainer *container = textView.textContainer;
    NSRect targetRect =
        [manager boundingRectForGlyphRange:NSMakeRange(location, 1)
                           inTextContainer:container];
    NSRect currentRect =
        [manager boundingRectForGlyphRange:NSMakeRange(cur, 1)
                           inTextContainer:container];
    if (targetRect.origin.y != currentRect.origin.y)
        return YES;

    textView.selectedRange = NSMakeRange(location, 0);
    return NO;
}


#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:
        (void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURLRequest *request = navigationAction.request;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated)
    {
        // If the target is exactly as the current one, ignore.
        if ([self.currentBaseUrl isEqual:request.URL])
        {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        // If this is a different page, intercept and handle ourselves. Map
        // asset-scheme link targets back to file URLs (external URLs such as
        // http(s) pass through unchanged).
        else if (![self isCurrentBaseUrl:request.URL])
        {
            decisionHandler(WKNavigationActionPolicyCancel);
            [self openOrCreateFileForUrl:
                MPFileURLForAssetSchemeURL(request.URL)];
            return;
        }
        // Otherwise this is somewhere else on the same page. Jump there.
    }
    else if (navigationAction.targetFrame.isMainFrame)
    {
        // Block unexpected main-frame navigations (e.g. a file or text
        // dropped onto the preview) that would replace the rendered document.
        // Only our own asset-scheme load (and about:blank) get through; this
        // stands in for the legacy WebUIDelegate drop block.
        NSURL *url = request.URL;
        if (![url.scheme isEqualToString:MPAssetURLScheme]
            && ![url.absoluteString isEqualToString:@"about:blank"])
        {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
    didStartProvisionalNavigation:(WKNavigation *)navigation
{
    // A new load is starting (this fires before commit, and before a
    // provisional failure), so reset the per-load state for it. The load
    // generation/token is bumped earlier, in -renderer:didProduceHTMLOutput:,
    // so it can be injected into the page before the load begins.
    self.previewLoadCompleted = NO;
    self.previewNavigationFinished = NO;
    self.previewMathJaxReported = NO;
}

- (void)webView:(WKWebView *)webView
    didCommitNavigation:(WKNavigation *)navigation
{
    NSWindow *window = webView.window;
    if (window)
    {
        @synchronized(window) {
            if (!window.isFlushWindowDisabled)
                [window disableFlushWindow];
        }
    }
}

// Runs the load-completion handler (re-enable flush, scale, scroll-sync) once
// per page load, whichever of the MathJax message / didFinishNavigation fires.
- (void)runPreviewLoadCompletionHandler
{
    if (self.previewLoadCompleted)
        return;
    self.previewLoadCompleted = YES;
    id callback = MPGetPreviewLoadingCompletionHandler(self);
    [[NSOperationQueue mainQueue] addOperationWithBlock:callback];
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (![message.name isEqualToString:kMPMathJaxEndMessageName])
        return;
    // Reject a late message from a superseded load: the page echoes back the
    // generation token injected at load time, so a mismatch means the message
    // belongs to an old navigation.
    if ([message.body unsignedIntegerValue] != self.previewLoadGeneration)
        return;
    // MathJax reported for the current load. If the navigation has finished,
    // complete now; otherwise record it (MathJax can finish before
    // didFinishNavigation, e.g. cached/simple math) and let that callback
    // consume it.
    self.previewMathJaxReported = YES;
    if (self.previewNavigationFinished)
        [self runPreviewLoadCompletionHandler];
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
    self.previewNavigationFinished = YES;

    // When this load's HTML has MathJax, the completion handler runs from its
    // typeset-complete message (so scroll-sync measures the final layout);
    // otherwise run it now. Use the per-load flag, not the live preference, so
    // toggling MathJax mid-load doesn't mis-time completion.
    if (!self.currentLoadHasMathJax)
    {
        [self runPreviewLoadCompletionHandler];
    }
    else if (self.previewMathJaxReported)
    {
        // MathJax already reported (it can finish before this callback for
        // cached/simple math); complete now instead of waiting on the fallback.
        [self runPreviewLoadCompletionHandler];
    }
    else
    {
        // Fallback: if MathJax never reports completion (e.g. it failed to
        // load), still run the handler after a short delay — but only if this
        // same load is still current, so it can't complete a later load. The
        // flag in -runPreviewLoadCompletionHandler keeps it exactly-once.
        // NOTE: a stale mathJaxEnd message arriving after a new load starts can
        // still satisfy that load's guard early; harmless while scroll-sync is
        // stubbed, to be made load-exact with the rebuild (macdown-8tk.5.4).
        NSUInteger generation = self.previewLoadGeneration;
        __weak MPDocument *weakSelf = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                MPDocument *strongSelf = weakSelf;
                if (strongSelf
                    && strongSelf.previewLoadGeneration == generation)
                    [strongSelf runPreviewLoadCompletionHandler];
            });
    }

    self.isPreviewReady = YES;

    // Update word count
    if (self.preferences.editorShowWordCount)
        [self updateWordCount];

    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;
}

// A navigation we cancel in -decidePolicyForNavigationAction: (e.g. a clicked
// link we handle ourselves) surfaces here as a failure. It is not a finished
// load, so it must not run the load-completion path or drain the render queue.
- (BOOL)navigationErrorIsCancellation:(NSError *)error
{
    if ([error.domain isEqualToString:NSURLErrorDomain]
            && error.code == NSURLErrorCancelled)
        return YES;
    // WebKit reports a policy-cancelled nav as a frame-load interruption.
    if ([error.domain isEqualToString:@"WebKitErrorDomain"]
            && error.code == 102)
        return YES;
    return NO;
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    if ([self navigationErrorIsCancellation:error])
        return;
    [self webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error
{
    if ([self navigationErrorIsCancellation:error])
        return;
    [self webView:webView didFinishNavigation:navigation];
}

#pragma mark - MPRendererDataSource

- (BOOL)rendererLoading {
	return self.preview.loading;
}
    
- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.editor.string;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    NSString *n = self.fileURL.lastPathComponent.stringByDeletingPathExtension;
    return n ? n : @"";
}


#pragma mark - MPRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.preferences.extensionFlags;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.preferences.extensionSmartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.preferences.htmlRendersTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.preferences.htmlStyleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.preferences.htmlDetectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.preferences.htmlSyntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.preferences.htmlMermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.preferences.htmlGraphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.preferences.htmlCodeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.preferences.htmlMathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.preferences.htmlHighlightingThemeName;
}

- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    if (self.alreadyRenderingInWeb)
    {
        self.renderToWebPending = YES;
        return;
    }
    
    if (self.printing)
        return;
    
    self.alreadyRenderingInWeb = YES;

    // Delayed copying for -copyHtml.
    if (self.copying)
    {
        self.copying = NO;
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard writeObjects:@[self.renderer.currentHtml]];
    }

    NSURL *baseUrl = self.fileURL;
    if (!baseUrl)   // Unsaved doument; just use the default URL.
        baseUrl = self.preferences.htmlDefaultDirectoryUrl;

    self.manualRender = self.preferences.markdownManualRender;

#if 0
    // Unfortunately this DOM-replacing causes a lot of problems...
    // 1. MathJax needs to be triggered.
    // 2. Prism rendering is lost.
    // 3. Potentially more.
    // Essentially all JavaScript needs to be run again after we replace
    // the DOM. I have no idea how many more problems there are, so we'll have
    // to back off from the path for now... :(

    // If we're working on the same document, try not to reload.
    if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl])
    {
        // HACK: Ideally we should only inject the parts that changed, and only
        // get the parts we need. For now we only get a complete HTML codument,
        // and rely on regex to get the parts we want in the DOM.

        // Use the existing tree if available, and replace the content.
        DOMDocument *doc = self.preview.mainFrame.DOMDocument;
        DOMNodeList *htmlNodes = [doc getElementsByTagName:@"html"];
        if (htmlNodes.length >= 1)
        {
            static NSString *pattern = @"<html>(.*)</html>";
            static int opts = NSRegularExpressionDotMatchesLineSeparators;

            // Find things inside the <html> tag.
            NSRegularExpression *regex =
                [[NSRegularExpression alloc] initWithPattern:pattern
                                                     options:opts error:NULL];
            NSTextCheckingResult *result =
                [regex firstMatchInString:html options:0
                                    range:NSMakeRange(0, html.length)];
            html = [html substringWithRange:[result rangeAtIndex:1]];

            // Replace everything in the old <html> tag.
            DOMElement *htmlNode = (DOMElement *)[htmlNodes item:0];
            htmlNode.innerHTML = html;

            return;
        }
    }
#endif

    // Serve the document's own directory through the asset scheme so relative
    // resources (e.g. images) resolve — WKWebView blocks file:// subresources
    // from a -loadHTMLString: page. The page is loaded and navigates entirely
    // in asset-scheme space; link targets are mapped back to file URLs in
    // -webView:decidePolicyForNavigationAction:decisionHandler:.
    NSURL *docDir = self.fileURL ? self.fileURL.URLByDeletingLastPathComponent
                                 : self.preferences.htmlDefaultDirectoryUrl;
    self.schemeHandler.documentDirectory = docDir.isFileURL ? docDir.path : nil;

    NSURL *schemeBase =
        [NSURL URLWithString:MPAssetSchemeURLStringForFileURL(baseUrl)];
    // Capture whether this load's HTML has MathJax (the completion handler
    // keys its timing off this, not the live preference).
    self.currentLoadHasMathJax = self.preferences.htmlMathJax;

    // Tag this load with a generation token, injected at document start so the
    // page's init.js echoes it back with the mathJaxEnd message; a late message
    // from a superseded load then fails the token check (see the handler).
    self.previewLoadGeneration++;
    NSString *tokenJS = [NSString stringWithFormat:@"window.__mpLoadToken=%lu;",
                         (unsigned long)self.previewLoadGeneration];
    WKUserScript *tokenScript = [[WKUserScript alloc]
        initWithSource:tokenJS
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
    [self.userContentController removeAllUserScripts];
    [self.userContentController addUserScript:tokenScript];

    [self.preview loadHTMLString:html baseURL:schemeBase];
    self.currentBaseUrl = schemeBase;
}


#pragma mark - Notification handler

- (void)editorTextDidChange:(NSNotification *)notification
{
    if (self.needsHtml)
        [self.renderer parseAndRenderLater];
}

- (void)userDefaultsDidChange:(NSNotification *)notification
{
    MPRenderer *renderer = self.renderer;

    // Force update if we're switching from manual to auto, or renderer settings
    // changed.
    int rendererFlags = self.preferences.rendererFlags;
    if ((!self.preferences.markdownManualRender && self.manualRender)
            || renderer.rendererFlags != rendererFlags)
    {
        renderer.rendererFlags = rendererFlags;
        [renderer parseAndRenderLater];
    }
    else
    {
        [renderer parseIfPreferencesChanged];
        [renderer renderIfPreferencesChanged];
    }
}

- (void)editorFrameDidChange:(NSNotification *)notification
{
    if (self.preferences.editorWidthLimited)
        [self adjustEditorInsets];
}

- (void)willStartLiveScroll:(NSNotification *)notification
{
    [self updateHeaderLocations];
    _inLiveScroll = YES;
}

-(void)didEndLiveScroll:(NSNotification *)notification
{
    _inLiveScroll = NO;
}

- (void)editorBoundsDidChange:(NSNotification *)notification
{
    if (!self.shouldHandleBoundsChange)
        return;

    if (self.preferences.editorSyncScrolling)
    {
        @synchronized(self) {
            self.shouldHandleBoundsChange = NO;
            if(!_inLiveScroll){
                [self updateHeaderLocations];
            }
            
            [self syncScrollers];
            self.shouldHandleBoundsChange = YES;
        }
    }
}

- (void)didRequestEditorReload:(NSNotification *)notification
{
    NSString *key =
        notification.userInfo[MPDidRequestEditorSetupNotificationKeyName];
    [self setupEditor:key];
}

- (void)didRequestPreviewReload:(NSNotification *)notification
{
    [self render:nil];
}

- (void)previewDidLiveScroll:(NSNotification *)notification
{
    // TODO(macdown-8tk.5.4): cache the preview scroll position via JS during
    // the WKWebView migration (no AppKit scroll view to read). Currently
    // unregistered as an observer; kept as a stub for the scroll-sync rebuild.
}


#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (object == self.editor)
    {
        if (!self.highlighter.isActive)
            return;
        id value = change[NSKeyValueChangeNewKey];
        NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(keyPath);
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:value forKey:preferenceKey];
    }
    else if (object == [NSUserDefaults standardUserDefaults])
    {
        if (self.highlighter.isActive)
            [self setupEditor:keyPath];
        [self redrawDivider];
    }
}


#pragma mark - IBAction

- (IBAction)copyHtml:(id)sender
{
    // (Clearing the preview's selection to signal we copy the whole document,
    //  not the selection, is restored with WKWebView selection work later.)

    // If the preview is hidden, the HTML are not updating on text change.
    // Perform one extra rendering so that the HTML is up to date, and do the
    // copy in the rendering callback.
    if (!self.needsHtml)
    {
        self.copying = YES;
        [self.renderer parseAndRenderNow];
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[self.renderer.currentHtml]];
}

- (IBAction)exportHtml:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeHTML];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    MPExportPanelAccessoryViewController *controller =
        [[MPExportPanelAccessoryViewController alloc] init];
    controller.stylesIncluded = (BOOL)self.preferences.htmlStyleName;
    controller.highlightingIncluded = self.preferences.htmlSyntaxHighlighting;
    panel.accessoryView = controller.view;

    NSWindow *w = self.windowForSheet;
    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSModalResponseOK)
            return;
        BOOL styles = controller.stylesIncluded;
        BOOL highlighting = controller.highlightingIncluded;
        NSString *html = [self.renderer HTMLForExportWithStyles:styles
                                                   highlighting:highlighting];
        [html writeToURL:panel.URL atomically:NO encoding:NSUTF8StringEncoding
                   error:NULL];
    }];
}

- (IBAction)exportPdf:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePDF];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;
    
    NSWindow *w = nil;
    NSArray *windowControllers = self.windowControllers;
    if (windowControllers.count > 0)
        w = [windowControllers[0] window];

    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSModalResponseOK)
            return;

        NSDictionary *settings = @{
            NSPrintJobDisposition: NSPrintSaveJob,
            NSPrintJobSavingURL: panel.URL,
        };
        [self printDocumentWithSettings:settings showPrintPanel:NO delegate:nil
                       didPrintSelector:NULL contextInfo:NULL];
    }];
}

- (IBAction)convertToH1:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:1];
}

- (IBAction)convertToH2:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:2];
}

- (IBAction)convertToH3:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:3];
}

- (IBAction)convertToH4:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:4];
}

- (IBAction)convertToH5:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:5];
}

- (IBAction)convertToH6:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:6];
}

- (IBAction)convertToParagraph:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:0];
}

- (IBAction)toggleStrong:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"**" suffix:@"**"];
}

- (IBAction)toggleEmphasis:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"*" suffix:@"*"];
}

- (IBAction)toggleInlineCode:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"`" suffix:@"`"];
}

- (IBAction)toggleStrikethrough:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"~~" suffix:@"~~"];
}

- (IBAction)toggleUnderline:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"_" suffix:@"_"];
}

- (IBAction)toggleHighlight:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"==" suffix:@"=="];
}

- (IBAction)toggleComment:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"<!--" suffix:@"-->"];
}

- (IBAction)toggleLink:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"[" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

- (IBAction)toggleImage:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"![" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

- (IBAction)toggleOrderedList:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^[0-9]+ \\S" prefix:@"1. "];
}

- (IBAction)toggleUnorderedList:(id)sender
{
    NSString *marker = self.preferences.editorUnorderedListMarker;
    [self.editor toggleBlockWithPattern:@"^[\\*\\+-] \\S" prefix:marker];
}

- (IBAction)toggleBlockquote:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^> \\S" prefix:@"> "];
}

- (IBAction)indent:(id)sender
{
    NSString *padding = @"\t";
    if (self.preferences.editorConvertTabs)
        padding = @"    ";
    [self.editor indentSelectedLinesWithPadding:padding];
}

- (IBAction)unindent:(id)sender
{
    [self.editor unindentSelectedLines];
}

- (IBAction)insertNewParagraph:(id)sender
{
    NSRange range = self.editor.selectedRange;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSString *content = self.editor.string;
    NSInteger newlineBefore = [content locationOfFirstNewlineBefore:location];
    NSUInteger newlineAfter =
        [content locationOfFirstNewlineAfter:location + length - 1];

    // If we are on an empty line, treat as normal return key; otherwise insert
    // two newlines.
    if (location == newlineBefore + 1 && location == newlineAfter)
        [self.editor insertNewline:self];
    else
        [self.editor insertText:@"\n\n"
               replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (IBAction)setEditorOneQuarter:(id)sender
{
    [self setSplitViewDividerLocation:0.25];
}

- (IBAction)setEditorThreeQuarters:(id)sender
{
    [self setSplitViewDividerLocation:0.75];
}

- (IBAction)setEqualSplit:(id)sender
{
    [self setSplitViewDividerLocation:0.5];
}

- (IBAction)toggleToolbar:(id)sender
{
    [self.windowForSheet toggleToolbarShown:sender];
}

- (IBAction)togglePreviewPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:NO];
}

- (IBAction)toggleEditorPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:YES];
}

- (IBAction)render:(id)sender
{
    [self.renderer parseAndRenderLater];
}


#pragma mark - Private

- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane
{
    BOOL isVisible = forEditorPane ? self.editorVisible : self.previewVisible;
    BOOL editorOnRight = self.preferences.editorOnRight;

    float targetRatio = ((forEditorPane == editorOnRight) ? 1.0 : 0.0);

    if (isVisible)
    {
        CGFloat oldRatio = self.splitView.dividerLocation;
        if (oldRatio != 0.0 && oldRatio != 1.0)
        {
            // We don't want to save these values, since they are meaningless.
            // The user should be able to switch between 100% editor and 100%
            // preview without losing the old ratio.
            self.previousSplitRatio = oldRatio;
        }
        [self setSplitViewDividerLocation:targetRatio];
    }
    else
    {
        // We have an inconsistency here, let's just go back to 0.5,
        // otherwise nothing will happen
        if (self.previousSplitRatio < 0.0)
            self.previousSplitRatio = 0.5;

        [self setSplitViewDividerLocation:self.previousSplitRatio];
    }
}

- (void)setupEditor:(NSString *)changedKey
{
    [self.highlighter deactivate];

    if (!changedKey || [changedKey isEqualToString:@"extensionFootnotes"])
    {
        int extensions = pmh_EXT_NOTES;
        if (self.preferences.extensionFootnotes)
            extensions = pmh_EXT_NONE;
        self.highlighter.extensions = extensions;
    }

    if (!changedKey || [changedKey isEqualToString:@"editorHorizontalInset"]
            || [changedKey isEqualToString:@"editorVerticalInset"]
            || [changedKey isEqualToString:@"editorWidthLimited"]
            || [changedKey isEqualToString:@"editorMaximumWidth"])
    {
        [self adjustEditorInsets];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorBaseFontInfo"]
            || [changedKey isEqualToString:@"editorStyleName"]
            || [changedKey isEqualToString:@"editorLineSpacing"])
    {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = self.preferences.editorLineSpacing;
        self.editor.defaultParagraphStyle = [style copy];
        NSFont *font = [self.preferences.editorBaseFont copy];
        if (font)
            self.editor.font = font;
        self.editor.textColor = nil;
        self.editor.backgroundColor = [NSColor clearColor];
        self.highlighter.styles = nil;
        [self.highlighter readClearTextStylesFromTextView];

        NSString *themeName = [self.preferences.editorStyleName copy];
        if (themeName.length)
        {
            NSString *path = MPThemePathForName(themeName);
            NSString *themeString = MPReadFileOfPath(path);
            [self.highlighter applyStylesFromStylesheet:themeString
                                       withErrorHandler:
                ^(NSArray *errorMessages) {
                    self.preferences.editorStyleName = nil;
                }];
        }

        CALayer *layer = [CALayer layer];
        CGColorRef backgroundCGColor = self.editor.backgroundColor.CGColor;
        if (backgroundCGColor)
            layer.backgroundColor = backgroundCGColor;
        self.editorContainer.layer = layer;
    }
    
    if ([changedKey isEqualToString:@"editorBaseFontInfo"])
    {
        [self scaleWebview];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowWordCount"])
    {
        if (self.preferences.editorShowWordCount)
        {
            self.wordCountWidget.hidden = NO;
            self.editorPaddingBottom.constant = 35.0;
            [self updateWordCount];
        }
        else
        {
            self.wordCountWidget.hidden = YES;
            self.editorPaddingBottom.constant = 0.0;
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorScrollsPastEnd"])
    {
        self.editor.scrollsPastEnd = self.preferences.editorScrollsPastEnd;
        NSRect contentRect = self.editor.contentRect;
        NSSize minSize = self.editor.enclosingScrollView.contentSize;
        if (contentRect.size.height < minSize.height)
            contentRect.size.height = minSize.height;
        if (contentRect.size.width < minSize.width)
            contentRect.size.width = minSize.width;
        self.editor.frame = contentRect;
    }

    if (!changedKey)
    {
        NSClipView *contentView = self.editor.enclosingScrollView.contentView;
        contentView.postsBoundsChangedNotifications = YES;

        NSDictionary *keysAndDefaults = MPEditorKeysToObserve();
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in keysAndDefaults)
        {
            NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(key);
            id value = [defaults objectForKey:preferenceKey];
            value = value ? value : keysAndDefaults[key];
            [self.editor setValue:value forKey:key];
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorOnRight"])
    {
        BOOL editorOnRight = self.preferences.editorOnRight;
        NSArray *subviews = self.splitView.subviews;
        // The preview WKWebView lives inside previewContainer, which is the
        // actual split-view pane.
        if ((!editorOnRight && subviews[0] == self.previewContainer)
            || (editorOnRight && subviews[1] == self.previewContainer))
        {
            [self.splitView swapViews];
            if (!self.previewVisible && self.previousSplitRatio >= 0.0)
                self.previousSplitRatio = 1.0 - self.previousSplitRatio;

            // Need to queue this or the views won't be initialised correctly.
            // Don't really know why, but this works.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.splitView.needsLayout = YES;
            }];
        }
    }

    [self.highlighter activate];
    self.editor.automaticLinkDetectionEnabled = NO;
}

- (void)adjustEditorInsets
{
    CGFloat x = self.preferences.editorHorizontalInset;
    CGFloat y = self.preferences.editorVerticalInset;
    if (self.preferences.editorWidthLimited)
    {
        CGFloat editorWidth = self.editor.frame.size.width;
        CGFloat maxWidth = self.preferences.editorMaximumWidth;
        if (editorWidth > 2 * x + maxWidth)
            x = (editorWidth - maxWidth) * 0.45;
        // We tend to expect things in an editor to shift to left a bit.
        // Hence the 0.45 instead of 0.5 (which whould feel a bit too much).
    }
    self.editor.textContainerInset = NSMakeSize(x, y);
}

- (void)redrawDivider
{
    if (!self.editorVisible)
    {
        // If the editor is not visible, match the preview's background color.
        // It's read asynchronously after each load (-refreshPreviewBackground)
        // and cached, since WKWebView has no synchronous DOM access; a nil
        // cache (before the first read) leaves the default divider color.
        self.splitView.dividerColor = self.previewBackgroundColor;
    }
    else if (!self.previewVisible)
    {
        // If the editor is visible, match its background color.
        self.splitView.dividerColor = self.editor.backgroundColor;
    }
    else
    {
        // If both sides are visible, draw a default "transparent" divider.
        // This works around the possibile problem of divider's color being too
        // similar to both the editor and preview and being obscured.
        self.splitView.dividerColor = nil;
    }
}

// Read the preview body's background color asynchronously and cache it for
// -redrawDivider (WKWebView has no synchronous DOM). Refreshed after each load
// since the style can change between loads.
- (void)refreshPreviewBackground
{
    NSString *js = @"getComputedStyle(document.body).backgroundColor";
    NSUInteger generation = self.previewLoadGeneration;
    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:js
                  completionHandler:^(id result, NSError *error) {
        MPDocument *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.previewLoadGeneration != generation)
            return;
        // Assign even when the read fails: -redrawDivider treats a nil cache
        // as the default divider color, so a new document whose background
        // can't be read or parsed resets rather than retaining the previous
        // document's color. (colorWithHTMLName: must not be passed nil.)
        if (![result isKindOfClass:[NSString class]])
        {
            strongSelf.previewBackgroundColor = nil;
        }
        else
        {
            // A body with no explicit background reports rgba(0,0,0,0), which
            // parses to a valid but fully transparent color. Treat (near-)
            // transparent as nil so -redrawDivider falls back to the default
            // divider instead of an invisible, fully transparent one.
            NSColor *color = [NSColor colorWithHTMLName:result];
            strongSelf.previewBackgroundColor =
                color.alphaComponent > 0.01 ? color : nil;
        }
        [strongSelf redrawDivider];
    }];
}

- (void)scaleWebview
{
    if (!self.preferences.previewZoomRelativeToBaseFontSize)
        return;

    CGFloat fontSize = self.preferences.editorBaseFontSize;
    if (fontSize <= 0.0)
        return;

    static const CGFloat defaultSize = 14.0;
    CGFloat scale = fontSize / defaultSize;

    self.preview.pageZoom = scale;
}

// Refresh both halves of the scroll-sync caches. The editor reference-node
// positions are computed synchronously; the preview's are fetched
// asynchronously (see -refreshPreviewHeaderLocations).
- (void)updateHeaderLocations
{
    [self updateEditorHeaderLocations];
    [self refreshPreviewHeaderLocations];
}

// Cache the vertical positions of the editor's reference nodes (Markdown
// headers and standalone images). This is pure AppKit text layout, so it stays
// synchronous. Headers within the last screen of the document are skipped:
// -syncScrollers interpolates to the end of the document there instead, to
// avoid jumping the preview as headers taper off the bottom.
- (void)updateEditorHeaderLocations
{
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];
    NSInteger characterCount = 0;
    NSLayoutManager *layoutManager = [self.editor layoutManager];
    NSArray<NSString *> *documentLines =
        [self.editor.string componentsSeparatedByString:@"\n"];

    // Patterns for Markdown headers and standalone (non-inline) images. A line
    // of dashes under a text line is a setext header, handled via the
    // previous-line-had-content flag. Compiled once: this method runs on scroll
    // and resize, and recompiling per call is needless overhead.
    static NSRegularExpression *dashRegex = nil;
    static NSRegularExpression *headerRegex = nil;
    static NSRegularExpression *imgRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dashRegex = [NSRegularExpression
            regularExpressionWithPattern:@"^([-]+)$" options:0 error:nil];
        headerRegex = [NSRegularExpression
            regularExpressionWithPattern:@"^(#+)\\s" options:0 error:nil];
        imgRegex = [NSRegularExpression
            regularExpressionWithPattern:@"^!\\[[^\\]]*\\]\\([^)]*\\)$"
                                 options:0 error:nil];
    });
    BOOL previousLineHadContent = NO;

    CGFloat editorContentHeight =
        ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight =
        ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));

    for (NSInteger lineNumber = 0; lineNumber < documentLines.count;
         lineNumber++)
    {
        NSString *line = documentLines[lineNumber];
        NSRange lineRange = NSMakeRange(0, line.length);

        if ((previousLineHadContent
                && [dashRegex numberOfMatchesInString:line options:0
                                                range:lineRange])
            || [imgRegex numberOfMatchesInString:line options:0
                                           range:lineRange]
            || [headerRegex numberOfMatchesInString:line options:0
                                              range:lineRange])
        {
            // Where this reference node sits vertically in the editor.
            NSRange glyphRange = [layoutManager
                glyphRangeForCharacterRange:NSMakeRange(characterCount,
                                                        line.length)
                       actualCharacterRange:nil];
            NSRect topRect = [layoutManager
                boundingRectForGlyphRange:glyphRange
                          inTextContainer:self.editor.textContainer];
            CGFloat headerY = NSMidY(topRect);

            if (headerY <= editorContentHeight - editorVisibleHeight)
                [locations addObject:@(headerY)];
        }

        previousLineHadContent = line.length
            && ![dashRegex numberOfMatchesInString:line options:0
                                             range:lineRange];

        characterCount += line.length + 1;
    }

    self.editorHeaderLocations = [locations copy];
}

// Fetch the preview's reference-node positions and scroll metrics
// asynchronously (WKWebView has no synchronous DOM) and cache them for
// -syncScrollers, which must run synchronously on every scroll frame. Once
// fresh metrics arrive, re-run -syncScrollers so a just-completed load or a
// just-warmed cache lands the preview at the editor's current position. Guarded
// by the load generation so a reply from a superseded load is dropped.
- (void)refreshPreviewHeaderLocations
{
    NSUInteger generation = self.previewLoadGeneration;
    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:kMPPreviewMetricsScript
                   completionHandler:^(id result, NSError *error) {
        MPDocument *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.previewLoadGeneration != generation)
            return;
        // A failed/aborted evaluation yields a nil or non-dictionary result.
        // Clear the caches rather than keep a previous load's metrics — stale
        // coordinates would scroll the preview to the wrong place, and a zero
        // content height makes -syncScrollers bail until the next good read.
        // (The values come straight from JS, so type-check before -doubleValue:
        // a JSON null bridges to NSNull, which would raise on -doubleValue.)
        NSDictionary *metrics =
            [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSArray *headers = metrics[@"headers"];
        NSNumber *contentHeight = metrics[@"contentHeight"];
        NSNumber *visibleHeight = metrics[@"visibleHeight"];
        strongSelf.webViewHeaderLocations =
            [headers isKindOfClass:[NSArray class]] ? headers : @[];
        strongSelf.previewContentHeight =
            [contentHeight isKindOfClass:[NSNumber class]]
                ? contentHeight.doubleValue : 0;
        strongSelf.previewVisibleHeight =
            [visibleHeight isKindOfClass:[NSNumber class]]
                ? visibleHeight.doubleValue : 0;
        if (strongSelf.preferences.editorSyncScrolling)
            [strongSelf syncScrollers];
    }];
}

// Map the editor's current scroll position onto the preview and drive the
// preview there with a fire-and-forget window.scrollTo. The editor metrics are
// read live (synchronous AppKit); the preview metrics come from the caches
// warmed by -refreshPreviewHeaderLocations.
- (void)syncScrollers
{
    // Nothing measured yet (no load has completed) — bail rather than scroll to
    // a bogus position.
    if (self.previewContentHeight <= 0)
        return;

    CGFloat editorContentHeight =
        ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight =
        ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    // editorVisibleHeight is a divisor for the taper; a zero-height editor
    // (e.g. mid-teardown, or syncScrollers reached from the async metrics
    // callback before the editor is laid out) would otherwise yield NaN and
    // scroll the preview to the top.
    if (editorVisibleHeight <= 0)
        return;
    CGFloat previewContentHeight = ceilf(self.previewContentHeight);
    CGFloat previewVisibleHeight = ceilf(self.previewVisibleHeight);
    NSInteger relativeHeaderIndex = -1; // -1 = before any header
    CGFloat currY = NSMinY(self.editor.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;

    // Align the documents at the middle of the screen, tapering to the top at
    // the very top of the document and to the bottom at the very bottom. The
    // tapers are unitless (driven by the editor scroll fraction) and shared by
    // both sides; the half-screen centring offset must be in each side's own
    // coordinate space. The editor is in AppKit points; the preview is in CSS
    // pixels, which differ from points whenever -scaleWebview applies a
    // pageZoom != 1 (preview-zoom-relative-to-font enabled at a non-14pt base
    // font). Using the editor offset on preview anchors would drift the
    // alignment around every header at non-1.0 zoom.
    CGFloat topTaper = MAX(0, MIN(1.0, currY / editorVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0,
        (currY - editorContentHeight + 2 * editorVisibleHeight)
            / editorVisibleHeight));
    CGFloat adjustmentForScroll =
        topTaper * bottomTaper * editorVisibleHeight / 2;
    CGFloat previewAdjustmentForScroll =
        topTaper * bottomTaper * previewVisibleHeight / 2;

    for (NSNumber *headerYNum in self.editorHeaderLocations)
    {
        CGFloat headerY = headerYNum.floatValue - adjustmentForScroll;

        if (headerY < currY)
        {
            // Reference node before the current position; the closest is our
            // top anchor.
            relativeHeaderIndex += 1;
            minY = headerY;
        }
        else if (maxY == 0
                && headerY < editorContentHeight - editorVisibleHeight)
        {
            // First reference node after the current position becomes the
            // bottom anchor (those in the last screen are skipped — we
            // interpolate to the end of the document instead).
            maxY = headerY;
        }
    }

    // Usually we scroll between two reference nodes; near the end of the
    // document we anchor the bottom to the end instead.
    BOOL interpolateToEndOfDocument = NO;
    if (maxY == 0)
    {
        maxY = editorContentHeight - editorVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    // currY is between minY and maxY, the nodes at relativeHeaderIndex and
    // relativeHeaderIndex+1. Normalise to a fraction of that span.
    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    // Guard the division: the two anchors can collapse to the same position
    // (e.g. a reference node sitting at the very end of the document), and
    // 0.0/0.0 is NaN, which would propagate into the scroll target.
    CGFloat percentScrolledBetweenHeaders =
        maxY > 0 ? MAX(0, MIN(1.0, currY / maxY)) : 0;

    // Find the matching span in the preview.
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight - previewVisibleHeight;

    // relativeHeaderIndex is -1 when no reference node precedes the current
    // position, so guard the lower bound explicitly rather than rely on the
    // signed→unsigned promotion of the comparison with .count (NSUInteger).
    // Elements come from JS, so type-check before -doubleValue (matching the
    // scalar-metric guards in -refreshPreviewHeaderLocations): a JSON null
    // would bridge to NSNull, which raises on -doubleValue.
    if (relativeHeaderIndex >= 0
            && (NSUInteger)relativeHeaderIndex
                < self.webViewHeaderLocations.count)
    {
        id top = self.webViewHeaderLocations[relativeHeaderIndex];
        if ([top isKindOfClass:[NSNumber class]])
            topHeaderY = floorf([top doubleValue]) - previewAdjustmentForScroll;
    }
    if (!interpolateToEndOfDocument
            && (NSUInteger)(relativeHeaderIndex + 1)
                < self.webViewHeaderLocations.count)
    {
        id bottom = self.webViewHeaderLocations[relativeHeaderIndex + 1];
        if ([bottom isKindOfClass:[NSNumber class]])
            bottomHeaderY =
                ceilf([bottom doubleValue]) - previewAdjustmentForScroll;
    }

    CGFloat previewY = topHeaderY
        + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;

    NSString *js = [NSString stringWithFormat:@"window.scrollTo(0,%f);",
                                              previewY];
    [self.preview evaluateJavaScript:js completionHandler:nil];
}

- (void)setSplitViewDividerLocation:(CGFloat)ratio
{
    BOOL wasVisible = self.previewVisible;
    [self.splitView setDividerLocation:ratio];
    if (!wasVisible && self.previewVisible
            && !self.preferences.markdownManualRender)
        [self.renderer parseAndRenderNow];
    [self setupEditor:NSStringFromSelector(@selector(editorHorizontalInset))];
}

- (NSString *)presumedFileName
{
    if (self.fileURL)
        return self.fileURL.lastPathComponent.stringByDeletingPathExtension;

    NSString *title = nil;
    NSString *string = self.editor.string;
    if (self.preferences.htmlDetectFrontMatter)
        title = [[[string frontMatter:NULL] objectForKey:@"title"] description];
    if (title)
        return title;

    title = string.titleString;
    if (!title)
        return NSLocalizedString(@"Untitled", @"default filename if no title can be determined");

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"[/|:]"
                                                          options:0 error:NULL];
    });

    NSRange range = NSMakeRange(0, title.length);
    title = [regex stringByReplacingMatchesInString:title options:0 range:range
                                       withTemplate:@"-"];
    return title;
}

- (void)updateWordCount
{
    NSUInteger generation = self.previewLoadGeneration;
    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:kMPWordCountScript
                  completionHandler:^(id result, NSError *error) {
        MPDocument *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.previewLoadGeneration != generation
            || ![result isKindOfClass:[NSDictionary class]])
            return;
        strongSelf.totalWords = [result[@"words"] unsignedIntegerValue];
        strongSelf.totalCharacters =
            [result[@"characters"] unsignedIntegerValue];
        strongSelf.totalCharactersNoSpaces =
            [result[@"charsNoSpace"] unsignedIntegerValue];
        if (strongSelf.isPreviewReady)
            strongSelf.wordCountWidget.enabled = YES;
    }];
}

- (BOOL)isCurrentBaseUrl:(NSURL *)another
{
    NSString *mine = self.currentBaseUrl.absoluteBaseURLString;
    NSString *theirs = another.absoluteBaseURLString;
    return mine == theirs || [mine isEqualToString:theirs];
}


#define OPEN_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"Please check the path of your link is correct. Turn on \
“Automatically create link targets” If you want MacDown to \
create nonexistent link targets for you.", \
@"preview navigation error information")

#define AUTO_CREATE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"MacDown can’t create a file for the clicked link because \
the current file is not saved anywhere yet. Save the \
current file somewhere to enable this feature.", \
@"preview navigation error information")


- (void)openOrCreateFileForUrl:(NSURL *)url
{
    // Simply open the file if it is not local, or exists already.
    BOOL file = url.isFileURL;
    BOOL reachable = !file || [url checkResourceIsReachableAndReturnError:NULL];
    
    // If the file is local but doesn't exist, check if a file with
    // the .md extension exists.
    if (file && !reachable && [url.pathExtension isEqualToString:@""])
    {
        NSURL *markdownURL = [url URLByAppendingPathExtension:@"md"];
        if ([markdownURL checkResourceIsReachableAndReturnError:NULL])
        {
            reachable = YES;
            url = markdownURL;
        }
    }
    
    if (reachable)
    {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // Show an error if the user doesn't want us to create it automatically.
    if (!self.preferences.createFileForLinkTarget)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"File not found at path:\n%@",
            @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template, url.path];
        alert.informativeText = OPEN_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    // We can only create a file if the current file is saved. (Why?)
    if (!self.fileURL)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@", @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template,
                             url.lastPathComponent];
        alert.informativeText = AUTO_CREATE_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
    }

    // Try to created the file.
    NSDocumentController *controller =
        [NSDocumentController sharedDocumentController];

    NSError *error = nil;
    id doc = [controller createNewEmptyDocumentForURL:url
                                              display:YES error:&error];
    if (!doc)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@",
            @"preview navigation error message");
        alert.messageText =
            [NSString stringWithFormat:template, url.lastPathComponent];
        template = NSLocalizedString(
            @"An error occurred while creating the file:\n%@",
            @"preview navigation error information");
        alert.informativeText =
            [NSString stringWithFormat:template, error.localizedDescription];
        [alert runModal];
    }
}


- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
{
    if ([doc respondsToSelector:@selector(setPrinting:)])
        ((MPDocument *)doc).printing = NO;
    if (context)
    {
        NSInvocation *invocation = (__bridge NSInvocation *)context;
        if ([invocation isKindOfClass:[NSInvocation class]])
        {
            [invocation setArgument:&doc atIndex:0];
            [invocation setArgument:&ok atIndex:1];
            [invocation invoke];
        }
    }
}

@end
