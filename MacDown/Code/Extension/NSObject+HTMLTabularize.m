//
//  NSObject+HTMLTabularize.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 13/7.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "NSObject+HTMLTabularize.h"
#import "MPUtilities.h"
#import "MacDown-Swift.h"


// Builds the key/value table shared by NSDictionary and MPOrderedDictionary:
// a header row of keys and a single body row of the matching values. Keys and
// objects must be parallel (objects[i] is the value for keys[i]).
static NSString *MPHTMLKeyedTable(NSArray *keys, NSArray *objects)
{
    NSMutableString *html =
        [NSMutableString stringWithString:@"<table><thead><tr>"];
    for (id key in keys)
        [html appendFormat:@"<th>%@</th>", [key HTMLTable]];
    [html appendString:@"</tr></thead><tbody><tr>"];
    for (id object in objects)
        [html appendFormat:@"<td>%@</td>", [object HTMLTable]];
    [html appendString:@"</tr></tbody></table>"];
    return html;
}


@implementation NSObject (HTMLTabularize)

- (NSString *)HTMLTable
{
    return MPHTMLEscapeString(self.description);
}

@end


@implementation NSNull (HTMLTabularize)

- (NSString *)HTMLTable
{
    return @"";
}

@end


@implementation NSArray (HTMLTabularize)

- (NSString *)HTMLTable
{
    NSMutableString *html =
        [NSMutableString stringWithString:@"<table><tbody><tr>"];
    for (id object in self)
        [html appendFormat:@"<td>%@</td>", [object HTMLTable]];
    [html appendString:@"</tr></tbody></table>"];
    return html;
}

@end


@implementation NSDictionary (HTMLTabularize)

- (NSString *)HTMLTable
{
    NSArray *keys = self.allKeys;
    NSMutableArray *objects = [NSMutableArray array];
    for (id key in keys)
        [objects addObject:self[key]];
    return MPHTMLKeyedTable(keys, objects);
}

@end


@implementation MPOrderedDictionary (HTMLTabularize)

- (NSString *)HTMLTable
{
    return MPHTMLKeyedTable(self.allKeys, self.allObjects);
}

@end
