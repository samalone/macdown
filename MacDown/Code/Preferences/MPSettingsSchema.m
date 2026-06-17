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


static MPSettingType MPSettingTypeFromString(NSString *s)
{
    if ([s isEqualToString:@"bool"])
        return MPSettingTypeBool;
    if ([s isEqualToString:@"int"])
        return MPSettingTypeInteger;
    if ([s isEqualToString:@"double"])
        return MPSettingTypeDouble;
    return MPSettingTypeString;
}

static MPSettingWritePolicy MPSettingWritePolicyFromString(NSString *s)
{
    if ([s isEqualToString:@"explicit"])
        return MPSettingWriteExplicitOnly;
    if ([s isEqualToString:@"never"])
        return MPSettingWriteNever;
    return MPSettingWriteNormal;
}

static MPSettingLayers MPSettingLayersFromArray(NSArray *names)
{
    // Default: readable from every layer.
    if (![names isKindOfClass:[NSArray class]])
        return MPSettingLayerApp | MPSettingLayerFolder | MPSettingLayerDocument;

    MPSettingLayers layers = 0;
    for (NSString *name in names)
    {
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
    NSURL *url = [bundle URLForResource:@"MPSettingsSchema" withExtension:@"json"];
    if (!url)
        url = [[NSBundle mainBundle] URLForResource:@"MPSettingsSchema"
                                      withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    NSDictionary *root = nil;
    if (data)
        root = [NSJSONSerialization JSONObjectWithData:data options:0
                                                 error:NULL];

    NSDictionary *settings = root[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]])
    {
        NSAssert(NO, @"MPSettingsSchema.json missing or malformed");
        return @{};
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [settings enumerateKeysAndObjectsUsingBlock:^(NSString *key,
                                                  NSDictionary *spec,
                                                  BOOL *stop) {
        MPSettingDescriptor *d = [[MPSettingDescriptor alloc] init];
        d.key = key;
        d.type = MPSettingTypeFromString(spec[@"type"]);
        d.readableLayers = MPSettingLayersFromArray(spec[@"readableFrom"]);
        d.writePolicy = MPSettingWritePolicyFromString(spec[@"appWritable"]);
        d.securitySensitive = [spec[@"security"] boolValue];
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
