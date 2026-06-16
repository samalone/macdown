//
//  MPAsset.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 29/6.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPAsset.h"
#import "MPUtilities.h"
#import "MPAssetSchemeHandler.h"


NSString * const kMPPlainType = @"text/plain";
NSString * const kMPCSSType = @"text/css";
NSString * const kMPJavaScriptType = @"text/javascript";
NSString * const kMPMathJaxConfigType = @"text/x-mathjax-config";


@interface MPAsset ()
@property (strong) NSURL *url;
@property (copy, nonatomic) NSString *typeName;
@property (readonly) NSString *defaultTypeName;

// Subclass hooks producing the markup for an inlined asset (its file contents)
// and for a linked asset (a URL). Abstract on MPAsset; overridden by the
// concrete subclasses.
- (NSString *)embeddedHTMLWithContent:(NSString *)content;
- (NSString *)linkedHTMLWithURL:(NSString *)url;
@end


@implementation MPAsset

- (NSString *)typeName
{
    return _typeName ? _typeName : self.defaultTypeName;
}

- (NSString *)defaultTypeName
{
    return kMPPlainType;
}


+ (instancetype)assetWithURL:(NSURL *)url andType:(NSString *)typeName
{
    return [[self alloc] initWithURL:url andType:typeName];
}

- (instancetype)initWithURL:(NSURL *)url andType:(NSString *)typeName
{
    self = [super init];
    if (!self)
        return nil;
    self.url = [url copy];
    self.typeName = typeName;
    return self;
}

- (instancetype)init
{
    return [self initWithURL:nil andType:nil];
}

- (NSString *)embeddedHTMLWithContent:(NSString *)content
{
    NSString *reason =
        [NSString stringWithFormat:@"Method %@ requires overriding",
                                   NSStringFromSelector(_cmd)];
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:reason userInfo:nil];
}

- (NSString *)linkedHTMLWithURL:(NSString *)url
{
    NSString *reason =
        [NSString stringWithFormat:@"Method %@ requires overriding",
                                   NSStringFromSelector(_cmd)];
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:reason userInfo:nil];
}

- (NSString *)htmlForOption:(MPAssetOption)option
{
    // A nil URL has no asset to embed or link; skip it rather than emit a tag
    // with a "(null)" href/src.
    if (option == MPAssetNone || !self.url)
        return nil;

    if (option == MPAssetEmbedded && self.url.isFileURL)
    {
        NSString *content = MPReadFileOfPath(self.url.path);
        if ([content hasSuffix:@"\n"])
            content = [content substringToIndex:content.length - 1];
        return [self embeddedHTMLWithContent:content];
    }

    // A full link, or an embedded non-file URL treated as one. Bundle and
    // App-Support file URLs are served to the WKWebView preview over the
    // custom asset scheme; other URLs pass through unchanged.
    NSString *url = MPAssetSchemeURLStringForFileURL(self.url);
    return [self linkedHTMLWithURL:url];
}

@end


@implementation MPStyleSheet

- (NSString *)defaultTypeName
{
    return kMPCSSType;
}

+ (instancetype)CSSWithURL:(NSURL *)url
{
    return [super assetWithURL:url andType:kMPCSSType];
}

- (NSString *)embeddedHTMLWithContent:(NSString *)content
{
    return [NSString stringWithFormat:@"<style type=\"%@\">\n%@\n</style>",
            MPHTMLEscapeString(self.typeName), content];
}

- (NSString *)linkedHTMLWithURL:(NSString *)url
{
    return [NSString stringWithFormat:
            @"<link rel=\"stylesheet\" type=\"%@\" href=\"%@\">",
            MPHTMLEscapeString(self.typeName), MPHTMLEscapeString(url)];
}

@end


@implementation MPScript

- (NSString *)defaultTypeName
{
    return kMPJavaScriptType;
}

+ (instancetype)javaScriptWithURL:(NSURL *)url
{
    return [super assetWithURL:url andType:kMPJavaScriptType];
}

- (NSString *)embeddedHTMLWithContent:(NSString *)content
{
    return [NSString stringWithFormat:@"<script type=\"%@\">\n%@\n</script>",
            MPHTMLEscapeString(self.typeName), content];
}

- (NSString *)linkedHTMLWithURL:(NSString *)url
{
    return [NSString stringWithFormat:
            @"<script type=\"%@\" src=\"%@\"></script>",
            MPHTMLEscapeString(self.typeName), MPHTMLEscapeString(url)];
}

@end


@implementation MPEmbeddedScript

- (NSString *)htmlForOption:(MPAssetOption)option
{
    if (option == MPAssetFullLink)
        option = MPAssetEmbedded;
    return [super htmlForOption:option];
}

@end
