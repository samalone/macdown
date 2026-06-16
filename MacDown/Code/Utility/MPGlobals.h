//
//  MPGlobals.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "version.h"

// These should match the main bundle's values.
static NSString * const kMPApplicationName = @"MacDown";

#ifdef DEBUG
static NSString * const kMPApplicationBundleIdentifier = @"com.llamagraphics.macdown-debug";
#else
static NSString * const kMPApplicationBundleIdentifier = @"com.llamagraphics.macdown";
#endif

static NSString * const kMPApplicationSuiteName = @"com.llamagraphics.macdown";

static NSString * const MPCommandInstallationPath = @"/usr/local/bin/macdown";
static NSString * const kMPCommandName = @"macdown";

static NSString * const kMPHelpKey = @"help";
static NSString * const kMPVersionKey = @"version";

static NSString * const kMPFilesToOpenKey = @"filesToOpenOnNextLaunch";
static NSString * const kMPPipedContentFileToOpen = @"pipedContentFileToOpenOnNextLaunch";

// Typographic points per inch, shared by the print-margin default and the
// Print settings pane's inch <-> point conversion.
static const CGFloat kMPPointsPerInch = 72.0;
