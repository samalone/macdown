//
//  MacDown-Bridging-Header.h
//  MacDown
//
//  Objective-C declarations exposed to Swift. As Swift code begins calling
//  into existing MacDown classes, import their headers here (see macdown-5xp.1
//  / the modernization direction in macdown-5xp).
//

// MPFrontMatterParser builds ordered front-matter dictionaries (macdown-5mi).
#import <M13OrderedDictionary/M13OrderedDictionary.h>
