//
//  UIColor+WMFStyle.m
//  Wikipedia
//
//  Created by Brian Gerstle on 7/31/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import "UIColor+WMFStyle.h"

@implementation UIColor (WMFStyle)

+ (instancetype)wmf_logoBlue {
    return [self wmf_logoBlueWithAlpha:1.0];
}

+ (instancetype)wmf_logoBlueWithAlpha:(CGFloat)alpha {
    // measured from WMF logo using DigitalColorMeter
    return [UIColor colorWithRed:0.08203125 green:0.40625 blue:0.5859375 alpha:alpha];
}

+ (instancetype)wmf_summaryTextColor {
    return [UIColor colorWithRed:0.118 green:0.118 blue:0.118 alpha:1];
}

+ (instancetype)wmf_lightGrayColor {
    return [UIColor colorWithWhite:0.8671875 alpha:1.0];
}

+ (instancetype)wmf_tableOfContentsHeaderTextColor {
    return [self wmf_tableOfContentsSectionTextColor];
}

+ (instancetype)wmf_tableOfContentsSelectionBackgroundColor {
    static UIColor* c = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c = [UIColor colorWithRed:0.929 green:0.929 blue:0.929 alpha:1];
    });
    return c;
}

+ (instancetype)wmf_tableOfContentsSelectionIndicatorColor {
    static UIColor* c = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c = [UIColor colorWithRed:0.192 green:0.334 blue:0.811 alpha:1];
    });
    return c;
}

+ (instancetype)wmf_tableOfContentsSectionTextColor {
    static UIColor* c = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1];
    });
    return c;
}

+ (instancetype)wmf_tableOfContentsSubsectionTextColor {
    static UIColor* c = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        c = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1];
    });
    return c;
}

@end
