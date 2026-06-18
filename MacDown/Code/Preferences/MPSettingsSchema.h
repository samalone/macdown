//
//  MPSettingsSchema.h
//  MacDown
//
//  The single source of truth for which preferences participate in the layered
//  settings cascade (app defaults -> .macdown.yml -> document front matter) and
//  how. Loaded from MPSettingsSchema.json (bead macdown-siy.1). A preference is
//  overridable only if it appears in the schema; everything else is app-only.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The value type of a setting; must match its MPPreferences property. */
typedef NS_ENUM(NSInteger, MPSettingType)
{
    MPSettingTypeBool,
    MPSettingTypeInteger,
    MPSettingTypeDouble,
    MPSettingTypeString,
};

/** The layers that may supply a value for a setting. */
typedef NS_OPTIONS(NSUInteger, MPSettingLayers)
{
    MPSettingLayerApp      = 1 << 0,
    MPSettingLayerFolder   = 1 << 1,
    MPSettingLayerDocument = 1 << 2,
};

/** Whether automated settings-writing may persist a setting for the user. */
typedef NS_ENUM(NSInteger, MPSettingWritePolicy)
{
    MPSettingWriteNormal,        // may be written at any scope (normal consent)
    MPSettingWriteExplicitOnly,  // only via deliberate, explicit user action
    MPSettingWriteNever,         // never written by the app
};


/** An immutable description of one overridable setting. */
@interface MPSettingDescriptor : NSObject

/** The preference key (identical to its MPPreferences property/getter name). */
@property (readonly, copy) NSString *key;
@property (readonly) MPSettingType type;
@property (readonly) MPSettingLayers readableLayers;
@property (readonly) MPSettingWritePolicy writePolicy;

/** YES if an override widens a capability (subject to the read-side consent
 *  asymmetry decided in macdown-siy.1: tighten freely, loosen with consent). */
@property (readonly, getter=isSecuritySensitive) BOOL securitySensitive;

@end


@interface MPSettingsSchema : NSObject

/** The schema loaded from the bundled MPSettingsSchema.json. */
@property (class, readonly) MPSettingsSchema *sharedSchema;

/** The descriptor for @c key, or nil if @c key is app-only (not
 *  overridable). */
- (nullable MPSettingDescriptor *)descriptorForKey:(NSString *)key;

/** Convenience: YES iff @c key is overridable (has a descriptor). */
- (BOOL)isKeyOverridable:(NSString *)key;

/** All overridable keys, unordered. */
@property (readonly) NSArray<NSString *> *allOverridableKeys;

/** Validation: schema keys that do NOT correspond to a real MPPreferences
 *  property (i.e. MPPreferences does not respond to a getter of that name).
 *  Should be empty; the unit test asserts it. */
- (NSArray<NSString *> *)keysNotBackedByPreference;

@end

NS_ASSUME_NONNULL_END
