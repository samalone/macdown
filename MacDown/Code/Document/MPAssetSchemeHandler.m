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


/** The directory subtrees this handler is allowed to serve from. */
NS_INLINE NSArray<NSString *> *MPAssetAllowedRoots(void)
{
    static NSArray<NSString *> *roots = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        NSString *bundle = [NSBundle mainBundle].resourcePath;
        if (bundle)
            [paths addObject:bundle.stringByStandardizingPath];
        NSString *data = MPDataDirectory(nil);
        if (data)
            [paths addObject:data.stringByStandardizingPath];
        roots = [paths copy];
    });
    return roots;
}

/** Whether @c resolved (already standardized) sits inside @c root. */
NS_INLINE BOOL MPPathIsUnderRoot(NSString *resolved, NSString *root)
{
    if (!root.length)
        return NO;
    NSString *standardRoot = root.stringByStandardizingPath;
    NSString *prefix = [standardRoot stringByAppendingString:@"/"];
    return [resolved isEqualToString:standardRoot]
        || [resolved hasPrefix:prefix];
}

/** Whether @c path resolves inside an allowed root or @c documentRoot. */
NS_INLINE BOOL MPAssetPathIsAllowed(NSString *path, NSString *documentRoot)
{
    NSString *resolved = path.stringByStandardizingPath;
    for (NSString *root in MPAssetAllowedRoots())
    {
        if (MPPathIsUnderRoot(resolved, root))
            return YES;
    }
    return MPPathIsUnderRoot(resolved, documentRoot);
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
    _liveTasks = [NSHashTable weakObjectsHashTable];
    return self;
}

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    @synchronized(self) {
        [self.liveTasks addObject:urlSchemeTask];
    }

    NSString *path = urlSchemeTask.request.URL.path;
    NSError *error = nil;
    NSData *data = nil;
    if (MPAssetPathIsAllowed(path, self.documentDirectory))
        data = [NSData dataWithContentsOfFile:path options:0 error:&error];

    if (!data)
    {
        if (!error)
            error = [NSError errorWithDomain:NSURLErrorDomain
                                        code:NSURLErrorResourceUnavailable
                                    userInfo:nil];
        [self finishTask:urlSchemeTask withError:error];
        return;
    }

    NSDictionary<NSString *, NSString *> *headers = @{
        @"Content-Type": MPAssetMIMETypeForPath(path),
        @"Content-Length": @(data.length).stringValue,
        @"Access-Control-Allow-Origin": @"*",
    };
    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:urlSchemeTask.request.URL
                                    statusCode:200 HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];

    @synchronized(self) {
        if (![self.liveTasks containsObject:urlSchemeTask])
            return;
        [urlSchemeTask didReceiveResponse:response];
        [urlSchemeTask didReceiveData:data];
        [urlSchemeTask didFinish];
        [self.liveTasks removeObject:urlSchemeTask];
    }
}

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    @synchronized(self) {
        [self.liveTasks removeObject:urlSchemeTask];
    }
}

- (void)finishTask:(id<WKURLSchemeTask>)task withError:(NSError *)error
{
    @synchronized(self) {
        if (![self.liveTasks containsObject:task])
            return;
        [task didFailWithError:error];
        [self.liveTasks removeObject:task];
    }
}

@end
