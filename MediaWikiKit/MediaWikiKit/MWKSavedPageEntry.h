//
//  MWKSavedPageEntry.h
//  MediaWikiKit
//
//  Created by Brion on 11/10/14.
//  Copyright (c) 2014 Wikimedia Foundation. All rights reserved.
//

#import "MWKSiteDataObject.h"
#import "MWKList.h"

@interface MWKSavedPageEntry : MWKSiteDataObject
    <MWKListObject>

@property (readonly, strong, nonatomic) MWKTitle* title;

- (instancetype)initWithTitle:(MWKTitle*)title;
- (instancetype)initWithDict:(NSDictionary*)dict;

///
/// @name Legacy Data Migration Flags
///

/// Whether or not image data was migrated from `MWKDataStore` to `WMFImageController`.
@property (nonatomic) BOOL didMigrateImageData;

@end
