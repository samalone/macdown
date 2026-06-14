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
 * How far outside the document's own directory the handler may read local
 * resources. The default WebView had no gate (any readable file); these scopes
 * trade that broad access back for defense-in-depth against an untrusted
 * document's script reading arbitrary local files. The app's own roots (bundle,
 * Application Support, temp) are always served regardless of scope.
 */
typedef NS_ENUM(NSInteger, MPAssetLocalAccessScope) {
    /** Only the document's directory subtree. The safe default. */
    MPAssetLocalAccessDocumentDirectory = 0,
    /** Also the document directory's parent subtree (sibling folders). */
    MPAssetLocalAccessParentDirectory   = 1,
    /** Any readable file, restoring the legacy WebView's behavior. */
    MPAssetLocalAccessAnyReadableFile   = 2,
};

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

/**
 * Rewrite explicit file:// URLs in src/href attributes of rendered HTML to
 * MPAssetURLScheme so they load — WKWebView blocks file:// subresources from an
 * asset-scheme page, so a file URL the user inserted (e.g. via Insert Image from
 * a Finder URL) would otherwise silently fail. Relative and bare-absolute paths
 * already resolve against the asset-scheme base URL and need no rewriting; the
 * rewritten URLs remain subject to the handler's access gate.
 */
extern NSString *MPHTMLByRewritingFileURLsToAssetScheme(NSString *html);


@interface MPAssetSchemeHandler : NSObject <WKURLSchemeHandler>

/**
 * An extra directory the handler may serve from, in addition to the app bundle
 * and Application Support. Set to the current document's directory so relative
 * resources (e.g. images) resolve through the scheme rather than file://, which
 * WKWebView blocks for -loadHTMLString: pages. May be nil.
 */
@property (atomic, copy) NSString *documentDirectory;

/**
 * How far outside @c documentDirectory the handler may read. Defaults to
 * MPAssetLocalAccessDocumentDirectory (subtree only). Set from the user's
 * Rendering preference before each load.
 */
@property (atomic, assign) MPAssetLocalAccessScope localAccessScope;

@end
