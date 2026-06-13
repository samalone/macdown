//
//  MPAssetSchemeHandler.h
//  MacDown
//
//  Serves MacDown's bundled and Application Support assets (Prism, MathJax,
//  styles, themes, …) to a WKWebView preview over a custom URL scheme.
//
//  WKWebView will not load file:// subresources from a -loadHTMLString:baseURL:
//  page, so the preview's <link>/<script> URLs are rewritten to this scheme and
//  served back from disk here, behind a path-security gate.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>


/** The custom scheme MacDown serves app-controlled assets over. */
extern NSString * const MPAssetURLScheme;

/**
 * Map a file URL into an MPAssetURLScheme URL string, preserving the path and
 * query. Non-file URLs are returned unchanged (via -absoluteString). Used when
 * emitting MPAssetFullLink tags so bundle/App-Support assets load under the
 * scheme instead of file://.
 */
extern NSString *MPAssetSchemeURLStringForFileURL(NSURL *fileURL);

/**
 * The reverse of MPAssetSchemeURLStringForFileURL: map an MPAssetURLScheme URL
 * back to a file URL (by its path). Returns the URL unchanged if it is not an
 * asset-scheme URL. Used to recover file targets for link navigation.
 */
extern NSURL *MPFileURLForAssetSchemeURL(NSURL *url);


@interface MPAssetSchemeHandler : NSObject <WKURLSchemeHandler>

/**
 * An extra directory the handler may serve from, in addition to the app bundle
 * and Application Support. Set to the current document's directory so relative
 * resources (e.g. images) resolve through the scheme rather than file://, which
 * WKWebView blocks for -loadHTMLString: pages. May be nil.
 */
@property (atomic, copy) NSString *documentDirectory;

@end
