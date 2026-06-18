//
//  MPSettingsSchema.m
//  MacDown
//

#import "MPSettingsSchema.h"
#import "MPPreferences.h"


@interface MPSettingDescriptor ()
@property (copy) NSString *key;
@property MPSettingType type;
@property MPSettingLayers readableLayers;
@property MPSettingWritePolicy writePolicy;
@property (getter=isSecuritySensitive) BOOL securitySensitive;
@end


@implementation MPSettingDescriptor
@end


// The *FromString helpers type-check their input so a malformed schema value
// (a JSON null bridges to NSNull, not nil) can't raise an unrecognized selector
// at launch; an unrecognized value falls back to the safe default.
static MPSettingType MPSettingTypeFromString(NSString *s)
{
    // type is required on every entry; default safely but assert so a missing
    // or misspelled token surfaces in development rather than masquerading.
    if ([s isKindOfClass:[NSString class]])
    {
        if ([s isEqualToString:@"bool"])
            return MPSettingTypeBool;
        if ([s isEqualToString:@"int"])
            return MPSettingTypeInteger;
        if ([s isEqualToString:@"double"])
            return MPSettingTypeDouble;
        if ([s isEqualToString:@"string"])
            return MPSettingTypeString;
    }
    NSCAssert(NO, @"Invalid or missing setting type in schema: %@", s);
    return MPSettingTypeString;
}

static MPSettingWritePolicy MPSettingWritePolicyFromString(NSString *s)
{
    // appWritable is optional; absence means the default (normal). A present
    // but unrecognized token is a typo -- assert so it doesn't silently relax
    // policy (e.g. "explicitt" quietly becoming normal).
    if (![s isKindOfClass:[NSString class]])
        return MPSettingWriteNormal;
    if ([s isEqualToString:@"yes"])
        return MPSettingWriteNormal;
    if ([s isEqualToString:@"explicit"])
        return MPSettingWriteExplicitOnly;
    if ([s isEqualToString:@"never"])
        return MPSettingWriteNever;
    NSCAssert(NO, @"Unknown appWritable in schema: %@", s);
    return MPSettingWriteNormal;
}

static MPSettingLayers MPSettingLayersFromArray(NSArray *names)
{
    // Default: readable from every layer.
    if (![names isKindOfClass:[NSArray class]])
        return MPSettingLayerApp | MPSettingLayerFolder
               | MPSettingLayerDocument;

    MPSettingLayers layers = 0;
    for (id name in names)
    {
        if (![name isKindOfClass:[NSString class]])
            continue;
        if ([name isEqualToString:@"app"])
            layers |= MPSettingLayerApp;
        else if ([name isEqualToString:@"folder"])
            layers |= MPSettingLayerFolder;
        else if ([name isEqualToString:@"document"])
            layers |= MPSettingLayerDocument;
    }
    return layers;
}


@implementation MPSettingsSchema
{
    NSDictionary<NSString *, MPSettingDescriptor *> *_descriptors;
}

+ (MPSettingsSchema *)sharedSchema
{
    static MPSettingsSchema *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    _descriptors = [[self class] loadDescriptors];
    return self;
}

+ (NSDictionary<NSString *, MPSettingDescriptor *> *)loadDescriptors
{
    // The resource ships in the same bundle as this class (the app);
    // fall back to the main bundle just in case.
    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSURL *url = [bundle URLForResource:@"MPSettingsSchema"
                          withExtension:@"json"];
    if (!url)
        url = [[NSBundle mainBundle] URLForResource:@"MPSettingsSchema"
                                      withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    id root = nil;
    if (data)
        root = [NSJSONSerialization JSONObjectWithData:data options:0
                                                 error:NULL];
    // A malformed top-level value (e.g. an array) must not be subscripted.
    if (![root isKindOfClass:[NSDictionary class]])
        root = nil;

    NSDictionary *settings = root[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]])
    {
        NSAssert(NO, @"MPSettingsSchema.json missing or malformed");
        return @{};
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [settings enumerateKeysAndObjectsUsingBlock:^(NSString *key, id spec,
                                                  BOOL *stop) {
        if (![spec isKindOfClass:[NSDictionary class]])
        {
            NSAssert(NO, @"Malformed schema entry for key %@", key);
            return;
        }
        id security = spec[@"security"];
        MPSettingDescriptor *d = [[MPSettingDescriptor alloc] init];
        d.key = key;
        d.type = MPSettingTypeFromString(spec[@"type"]);
        d.readableLayers = MPSettingLayersFromArray(spec[@"readableFrom"]);
        d.writePolicy = MPSettingWritePolicyFromString(spec[@"appWritable"]);
        d.securitySensitive = [security isKindOfClass:[NSNumber class]]
                              && [security boolValue];
        result[key] = d;
    }];
    return result;
}

- (MPSettingDescriptor *)descriptorForKey:(NSString *)key
{
    return _descriptors[key];
}

- (BOOL)isKeyOverridable:(NSString *)key
{
    return _descriptors[key] != nil;
}

- (NSArray<NSString *> *)allOverridableKeys
{
    return _descriptors.allKeys;
}

- (NSArray<NSString *> *)keysNotBackedByPreference
{
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *key in _descriptors)
    {
        // The getter selector is identical to the key (and the defaults key).
        SEL getter = NSSelectorFromString(key);
        if (![MPPreferences instancesRespondToSelector:getter])
            [missing addObject:key];
    }
    return missing;
}

@end
