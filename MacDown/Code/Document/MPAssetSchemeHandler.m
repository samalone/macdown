//
//  MPAssetSchemeHandler.m
//  MacDown
//

#import "MPAssetSchemeHandler.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "MPUtilities.h"


NSString * const MPAssetURLScheme = @"macdown-asset";

// Host component of generated URLs. A fixed host keeps the URLs well-formed;
// the real payload is the (percent-encoded) absolute file path in the path.
static NSString * const kMPAssetURLHost = @"localhost";


NSString *MPAssetSchemeURLStringForFileURL(NSURL *fileURL)
{
    if (!fileURL.isFileURL)
        return fileURL.absoluteString;

    NSURLComponents *source =
        [NSURLComponents componentsWithURL:fileURL resolvingAgainstBaseURL:NO];

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = MPAssetURLScheme;
    components.host = kMPAssetURLHost;
    components.path = fileURL.path;
    components.percentEncodedQuery = source.percentEncodedQuery;
    return components.URL.absoluteString;
}

NSURL *MPFileURLForAssetSchemeURL(NSURL *url)
{
    if (![url.scheme isEqualToString:MPAssetURLScheme])
        return url;
    return [NSURL fileURLWithPath:url.path];
}


// Standardize (~, ..) then resolve symbolic links so the allow-check sees the
// real on-disk path: a symlink inside an allowed root (e.g. in an untrusted
// document's directory) must not smuggle a read outside it. Applied to both the
// request and every root so the canonicalized comparison matches.
NS_INLINE NSString *MPCanonicalPath(NSString *path)
{
    return path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
}

/** The (canonical) directory subtrees this handler is allowed to serve from. */
NS_INLINE NSArray<NSString *> *MPAssetAllowedRoots(void)
{
    static NSArray<NSString *> *roots = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        NSString *bundle = [NSBundle mainBundle].resourcePath;
        if (bundle)
            [paths addObject:MPCanonicalPath(bundle)];
        NSString *data = MPDataDirectory(nil);
        if (data)
            [paths addObject:MPCanonicalPath(data)];
        // Mapped-content autocomplete writes images here and references them by
        // absolute path (see -[NSTextView(Autocomplete) insertMappedContent]).
        [paths addObject:MPCanonicalPath(NSTemporaryDirectory())];
        roots = [paths copy];
    });
    return roots;
}

/** Whether @c canonical sits inside the already-canonical @c canonicalRoot. */
NS_INLINE BOOL MPPathIsUnderRoot(NSString *canonical, NSString *canonicalRoot)
{
    if (!canonicalRoot.length)
        return NO;
    NSString *prefix = [canonicalRoot stringByAppendingString:@"/"];
    return [canonical isEqualToString:canonicalRoot]
        || [canonical hasPrefix:prefix];
}

/** Whether @c path resolves inside an allowed root or @c documentRoot. */
NS_INLINE BOOL MPAssetPathIsAllowed(NSString *path, NSString *documentRoot)
{
    NSString *canonical = MPCanonicalPath(path);
    for (NSString *root in MPAssetAllowedRoots())
    {
        if (MPPathIsUnderRoot(canonical, root))
            return YES;
    }
    return MPPathIsUnderRoot(canonical, MPCanonicalPath(documentRoot));
}

NS_INLINE NSString *MPAssetMIMETypeForPath(NSString *path)
{
    NSString *ext = path.pathExtension;
    if (ext.length)
    {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        NSString *mime = type.preferredMIMEType;
        if (mime)
            return mime;
    }
    return @"application/octet-stream";
}


@interface MPAssetSchemeHandler ()
@property (strong) NSHashTable<id<WKURLSchemeTask>> *liveTasks;
@end


@implementation MPAssetSchemeHandler

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    // Strong refs, removed on every finish/fail/stop path, so a still-live task
    // is never dropped (a weak table could zero one WebKit hasn't stopped yet).
    _liveTasks = [NSHashTable hashTableWithOptions:NSHashTableStrongMemory];
    return self;
}

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    @synchronized(self) {
        [self.liveTasks addObject:urlSchemeTask];
    }

    // Read off the main thread so a large asset (e.g. mermaid.min.js ~1MB)
    // doesn't block the UI, then reply on the main queue. WKURLSchemeTask
    // callbacks may run on any thread as long as they stay serialized per task
    // and stop once it is finished/failed/stopped (guarded by liveTasks).
    NSString *path = urlSchemeTask.request.URL.path;
    NSString *documentDirectory = self.documentDirectory;
    dispatch_queue_t queue =
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        NSError *error = nil;
        NSData *data = nil;
        if (MPAssetPathIsAllowed(path, documentDirectory))
            data = [NSData dataWithContentsOfFile:path options:0 error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(self) {
                if (![self.liveTasks containsObject:urlSchemeTask])
                    return;

                if (!data)
                {
                    NSError *failure = error;
                    if (!failure)
                        failure = [NSError
                            errorWithDomain:NSURLErrorDomain
                                       code:NSURLErrorResourceUnavailable
                                   userInfo:nil];
                    [urlSchemeTask didFailWithError:failure];
                    [self.liveTasks removeObject:urlSchemeTask];
                    return;
                }

                NSDictionary<NSString *, NSString *> *headers = @{
                    @"Content-Type": MPAssetMIMETypeForPath(path),
                    @"Content-Length": @(data.length).stringValue,
                };
                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
                    initWithURL:urlSchemeTask.request.URL statusCode:200
                    HTTPVersion:@"HTTP/1.1" headerFields:headers];

                [urlSchemeTask didReceiveResponse:response];
                [urlSchemeTask didReceiveData:data];
                [urlSchemeTask didFinish];
                [self.liveTasks removeObject:urlSchemeTask];
            }
        });
    });
}

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    @synchronized(self) {
        [self.liveTasks removeObject:urlSchemeTask];
    }
}

@end
