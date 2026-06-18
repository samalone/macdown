//
//  MPDocumentPreferences.h
//  MacDown
//
//  A document-scoped preferences resolver (bead macdown-siy.2). Returned by
//  -[MPDocument preferences] in place of the shared MPPreferences singleton, so
//  every existing `self.preferences.<x>` read on the document/render path
//  resolves through the layered settings cascade. Overridable getters (per
//  MPSettingsSchema) consult per-document override layers first, then fall
//  through to the app (NSUserDefaults) layer inherited from MPPreferences.
//
//  Phase 0 wires no override layers, so every read resolves to the app value
//  (identical behavior). Phases 3+ populate the layers via -setOverrideValue:.
//

#import "MPPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface MPDocumentPreferences : MPPreferences

// Sets (or clears, with nil) the resolved override for an overridable setting.
// App-only keys (absent from MPSettingsSchema) are ignored, so the schema's
// app-only categorization is enforced here regardless of the caller. Intended
// for the layer-population code (Phases 3+) and tests.
- (void)setOverrideValue:(nullable id)value forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
