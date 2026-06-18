//
//  MPDocumentPreferences.m
//  MacDown
//

#import "MPDocumentPreferences.h"
#import "MPSettingsSchema.h"


@implementation MPDocumentPreferences
{
    NSMutableDictionary<NSString *, id> *_overrides;
}

// _overrides is initialized here (not in -init) because
// initWithoutFirstLaunchSetup is a public initializer inherited from
// MPPreferences; routing through it keeps _overrides set no matter which
// initializer a caller uses.
- (instancetype)initWithoutFirstLaunchSetup
{
    self = [super initWithoutFirstLaunchSetup];
    if (!self)
        return nil;
    _overrides = [NSMutableDictionary dictionary];
    return self;
}

- (instancetype)init
{
    // A per-document resolver only reads shared defaults plus its own override
    // layers; it must not re-run MPPreferences's one-time first-launch setup.
    return [self initWithoutFirstLaunchSetup];
}

- (void)setOverrideValue:(id)value forKey:(NSString *)key
{
    // A nil key would throw on the dictionary lookup; only overridable keys may
    // carry an override (this enforces the schema's app-only categorization).
    if (!key || ![MPSettingsSchema.sharedSchema isKeyOverridable:key])
        return;

    // Synchronized: later phases set overrides on the main thread while the
    // renderer reads them via -resolvedValueForKey: on its background
    // parseQueue. NSMutableDictionary is not safe for concurrent access.
    @synchronized (self)
    {
        // Treat NSNull (e.g. a YAML null parsed by a later phase) as "clear the
        // override" rather than storing a value the typed getters can't coerce.
        if (value && value != [NSNull null])
            _overrides[key] = value;
        else
            [_overrides removeObjectForKey:key];
    }
}

// The resolved override for an overridable key, or nil to fall through to the
// app layer. Phase 0: _overrides is empty unless a caller/test injects one, so
// every getter below resolves to the inherited app (NSUserDefaults) value.
- (id)resolvedValueForKey:(NSString *)key
{
    @synchronized (self)
    {
        return _overrides[key];
    }
}


#pragma mark - Overridable accessors

// Each overridable getter funnels through the resolver, falling through to
// super (the app value) when there is no override. These mirror MPPreferences's
// MP_*_PREF accessors; the getter name is also the schema key. The set below
// must match the overridable keys in MPSettingsSchema.json -- a drift test
// (MPDocumentPreferencesTests) injects an override for every schema key and
// fails if any key lacks a working override here.

#define MP_RESOLVE_BOOL(name) \
    - (BOOL)name { \
        id v = [self resolvedValueForKey:@#name]; \
        return v ? [v boolValue] : [super name]; }
#define MP_RESOLVE_INTEGER(name) \
    - (NSInteger)name { \
        id v = [self resolvedValueForKey:@#name]; \
        return v ? [v integerValue] : [super name]; }
#define MP_RESOLVE_STRING(name) \
    - (NSString *)name { \
        id v = [self resolvedValueForKey:@#name]; \
        return v ? v : [super name]; }

MP_RESOLVE_BOOL(extensionIntraEmphasis)
MP_RESOLVE_BOOL(extensionTables)
MP_RESOLVE_BOOL(extensionFencedCode)
MP_RESOLVE_BOOL(extensionAutolink)
MP_RESOLVE_BOOL(extensionStrikethough)
MP_RESOLVE_BOOL(extensionUnderline)
MP_RESOLVE_BOOL(extensionSuperscript)
MP_RESOLVE_BOOL(extensionHighlight)
MP_RESOLVE_BOOL(extensionFootnotes)
MP_RESOLVE_BOOL(extensionQuote)
MP_RESOLVE_BOOL(extensionSmartyPants)

MP_RESOLVE_BOOL(markdownManualRender)

MP_RESOLVE_BOOL(htmlSyntaxHighlighting)
MP_RESOLVE_BOOL(htmlLineNumbers)
MP_RESOLVE_BOOL(htmlTaskList)
MP_RESOLVE_BOOL(htmlHardWrap)
MP_RESOLVE_BOOL(htmlMathJax)
MP_RESOLVE_BOOL(htmlMathJaxInlineDollar)
MP_RESOLVE_BOOL(htmlGraphviz)
MP_RESOLVE_BOOL(htmlMermaid)
MP_RESOLVE_BOOL(htmlDetectFrontMatter)
MP_RESOLVE_BOOL(htmlRendersTOC)
MP_RESOLVE_BOOL(previewZoomRelativeToBaseFontSize)

MP_RESOLVE_INTEGER(htmlCodeBlockAccessory)
MP_RESOLVE_INTEGER(htmlAssetLocalAccessScope)

MP_RESOLVE_STRING(htmlStyleName)
MP_RESOLVE_STRING(htmlHighlightingThemeName)

#undef MP_RESOLVE_BOOL
#undef MP_RESOLVE_INTEGER
#undef MP_RESOLVE_STRING

@end
