//
//  UIScrollView+WMFContentOffsetUtils.h
//  Wikipedia
//
//  Created by Brian Gerstle on 8/8/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIScrollView (WMFContentOffsetUtils)

/**
 *  @return The offset at which the receiver would rest after scrolling to the top.
 */
- (CGPoint)wmf_topContentOffset;

/**
 *  Scroll the receiver to the top of its content.
 *
 *  Use this instead of setting `contentOffset = CGPointZero`, as some scroll views have `contentInset != CGPointZero`.
 *
 *  @see wmf_topContentOffset
 */
- (void)wmf_scrollToTop:(BOOL)animated;

@end
