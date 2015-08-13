#import "WMFArticleViewController_Private.h"

#import "SessionSingleton.h"

// Frameworks
#import <Masonry/Masonry.h>
#import <BlocksKit/BlocksKit+UIKit.h>
#import "Wikipedia-Swift.h"
#import "PromiseKit.h"

//Analytics
#import <PiwikTracker/PiwikTracker.h>
#import "MWKArticle+WMFAnalyticsLogging.h"

// Models & Controllers
#import "WebViewController.h"
#import "WMFArticleHeaderImageGalleryViewController.h"
#import "WMFArticleFetcher.h"
#import "WMFSearchFetcher.h"
#import "WMFSearchResults.h"
#import "MWKArticlePreview.h"
#import "MWKArticle.h"
#import "WMFImageGalleryViewController.h"
#import "ReferencesVC.h"
#import "MWKCitation.h"

// Views
#import "WMFArticleTableHeaderView.h"
#import "WMFArticleSectionCell.h"
#import "PaddedLabel.h"
#import "WMFArticleSectionHeaderView.h"
#import "WMFMinimalArticleContentCell.h"
#import "WMFArticleReadMoreCell.h"
#import "WMFArticleNavigationDelegate.h"

// Categories
#import "NSString+Extras.h"
#import "UIButton+WMFButton.h"
#import "UIStoryboard+WMFExtensions.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "MWKArticle+WMFSharing.h"
#import "UIView+WMFDefaultNib.h"
#import "NSAttributedString+WMFHTMLForSite.h"

#import "WMFArticlePopupTransition.h"

typedef NS_ENUM (NSInteger, WMFArticleSectionType) {
    WMFArticleSectionTypeSummary,
    WMFArticleSectionTypeTOC,
    WMFArticleSectionTypeReadMore
};

NS_ASSUME_NONNULL_BEGIN

@interface WMFArticleViewController ()
<UITableViewDataSource,
 UITableViewDelegate,
 WMFArticleHeaderImageGalleryViewControllerDelegate,
 WMFImageGalleryViewControllerDelegate,
 WMFWebViewControllerDelegate,
 WMFArticleNavigationDelegate>

@property (nonatomic, weak) IBOutlet UIView* galleryContainerView;
@property (nonatomic, weak) IBOutlet WMFArticleTableHeaderView* headerView;

@property (nonatomic, strong, readwrite) MWKDataStore* dataStore;
@property (nonatomic, strong, readwrite) MWKSavedPageList* savedPages;
@property (nonatomic, assign, readwrite) WMFArticleControllerMode mode;

@property (nonatomic, strong) WMFArticlePreviewFetcher* articlePreviewFetcher;
@property (nonatomic, strong) WMFArticleFetcher* articleFetcher;

@property (nonatomic, strong, nullable) AnyPromise* articleFetcherPromise;

@property (nonatomic, strong) WMFSearchFetcher* readMoreFetcher;
@property (nonatomic, strong) WMFSearchResults* readMoreResults;

@property (nonatomic, strong) WMFArticleHeaderImageGalleryViewController* headerGalleryViewController;
@property (nonatomic, weak) IBOutlet UITapGestureRecognizer* expandGalleryTapRecognizer;

@property (nonatomic, strong) WebViewController* webViewController;

@property (strong, nonatomic) WMFArticlePopupTransition* popupTransition;

@end

@implementation WMFArticleViewController

+ (instancetype)articleViewControllerWithDataStore:(MWKDataStore*)dataStore savedPages:(MWKSavedPageList*)savedPages {
    WMFArticleViewController* vc = [self wmf_initialViewControllerFromClassStoryboard];
    vc.dataStore  = dataStore;
    vc.savedPages = savedPages;
    return vc;
}

- (void)dealloc {
    [self unobserveSavedPages];
}

#pragma mark - Accessors

- (void)setHeaderGalleryViewController:(WMFArticleHeaderImageGalleryViewController* __nonnull)galleryViewController {
    _headerGalleryViewController = galleryViewController;
    [_headerGalleryViewController setImagesFromArticle:self.article];
}

- (void)setArticle:(MWKArticle* __nullable)article {
    if (WMF_EQUAL(_article, isEqualToArticle:, article)) {
        return;
    }

    [self unobserveArticleUpdates];
    [[WMFImageController sharedInstance] cancelFetchForURL:[NSURL wmf_optionalURLWithString:[_article bestThumbnailImageURL]]];

    // TODO cancel
    [self.articlePreviewFetcher cancelFetchForPageTitle:_article.title];
    [self.articleFetcher cancelFetchForPageTitle:_article.title];

    _article = article;

    [self.headerGalleryViewController setImagesFromArticle:article];

    [self updateUI];
    [self observeAndFetchArticleIfNeeded];
}

- (void)setMode:(WMFArticleControllerMode)mode animated:(BOOL)animated {
    if (_mode == mode) {
        return;
    }

    _mode = mode;

    [self updateUIForMode:mode animated:animated];
    [self observeAndFetchArticleIfNeeded];
}

- (BOOL)isSaved {
    return [self.savedPages isSaved:self.article.title];
}

- (UIButton*)saveButton {
    return [[self headerView] saveButton];
}

- (WMFArticlePreviewFetcher*)articlePreviewFetcher {
    if (!_articlePreviewFetcher) {
        _articlePreviewFetcher = [[WMFArticlePreviewFetcher alloc] init];
    }
    return _articlePreviewFetcher;
}

- (WMFArticleFetcher*)articleFetcher {
    if (!_articleFetcher) {
        _articleFetcher = [[WMFArticleFetcher alloc] initWithDataStore:self.dataStore];
    }
    return _articleFetcher;
}

- (WebViewController*)webViewController {
    if (!_webViewController) {
        _webViewController          = [WebViewController wmf_initialViewControllerFromClassStoryboard];
        _webViewController.delegate = self;
    }
    return _webViewController;
}

#pragma mark - Saved Pages KVO

- (void)observeSavedPages {
    [self.KVOControllerNonRetaining observe:self.savedPages
                                    keyPath:WMF_SAFE_KEYPATH(self.savedPages, entries)
                                    options:0
                                      block:^(WMFArticleViewController* observer, id object, NSDictionary* change) {
        [observer updateSavedButtonState];
    }];
}

- (void)unobserveSavedPages {
    [self.KVOControllerNonRetaining unobserve:self.savedPages keyPath:WMF_SAFE_KEYPATH(self.savedPages, entries)];
}

#pragma mark - Article Notifications

- (void)observeArticleUpdates {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(articleUpdatedWithNotification:) name:MWKArticleSavedNotification object:nil];
}

- (void)unobserveArticleUpdates {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MWKArticleSavedNotification object:nil];
}

- (void)articleUpdatedWithNotification:(NSNotification*)note {
    MWKArticle* article = note.userInfo[MWKArticleKey];
    if ([self.article.title isEqualToTitle:article.title]) {
        self.article = article;
    }
}

#pragma mark - Analytics

- (NSString*)analyticsName {
    NSParameterAssert(self.article);
    if (self.article == nil) {
        return @"";
    }
    return [(id < WMFAnalyticsLogging >)self.article analyticsName];
}

- (void)logPreview {
    if (self.mode == WMFArticleControllerModePopup && self.article.title.text) {
        NSLog(@"log preview page view");
        [[PiwikTracker sharedInstance] sendViewsFromArray:@[@"Article-Preview", [self analyticsName]]];
    }
}

- (void)logPageView {
    if (self.mode == WMFArticleControllerModeNormal && self.article.title.text) {
        NSLog(@"log full page view");
        [[PiwikTracker sharedInstance] sendViewsFromArray:@[@"Article", [self analyticsName]]];
    }
}

#pragma mark - Article Fetching

- (void)observeAndFetchArticleIfNeeded {
    if (!self.article) {
        // nothing to fetch or observe
        return;
    }

    if (self.mode == WMFArticleControllerModeList) {
        // don't update or fetch while in list mode
        return;
    }

    if ([self.article isCached]) {
        // observe immediately
        [self loadWebViewController];
        [self observeArticleUpdates];
    } else {
        // fetch then observe
        [self fetchArticle];
    }
}

- (void)fetchArticle {
    [self fetchArticleForTitle:self.article.title];
}

- (void)fetchArticleForTitle:(MWKTitle*)title {
    @weakify(self)
    [self.articlePreviewFetcher fetchArticlePreviewForPageTitle : title progress : NULL].then(^(MWKArticlePreview* articlePreview){
        @strongify(self)
        AnyPromise * fullArticlePromise = [self.articleFetcher fetchArticleForPageTitle:title progress:NULL];
        self.articleFetcherPromise = fullArticlePromise;
        return fullArticlePromise;
    }).then(^(MWKArticle* article){
        @strongify(self)
        [self.headerGalleryViewController setImagesFromArticle : article];
        self.article = article;
        [self loadWebViewController];
    }).catch(^(NSError* error){
        @strongify(self)
        if ([error wmf_isWMFErrorOfType:WMFErrorTypeRedirected]) {
            [self fetchArticleForTitle:[[error userInfo] wmf_redirectTitle]];
        } else if (!self.presentingViewController) {
            // only do error handling if not presenting gallery
            DDLogError(@"Article Fetch Error: %@", [error localizedDescription]);
        }
    }).finally(^{
        @strongify(self);
        self.articleFetcherPromise = nil;
    });;
}

- (void)fetchReadMoreForTitle:(MWKTitle*)title {
    // Note: can't set the readMoreFetcher when the article changes because the article changes *a lot* because the
    // card collection view controller sets it a lot as you scroll through the cards. "fetchReadMoreForTitle:" however
    // is only called when the card is expanded, so self.readMoreFetcher is set here as well so it's not needlessly
    // repeatedly set.
    self.readMoreFetcher =
        [[WMFSearchFetcher alloc] initWithSearchSite:self.article.title.site dataStore:self.dataStore];
    self.readMoreFetcher.maxSearchResults = 3;

    @weakify(self)
    [self.readMoreFetcher searchFullArticleTextForSearchTerm :[@"morelike:" stringByAppendingString:title.text] appendToPreviousResults : nil]
    .then(^(WMFSearchResults* results) {
        @strongify(self)
        self.readMoreResults = results;
        [self.tableView reloadData];
    })
    .catch(^(NSError* err) {
        DDLogError(@"Failed to fetch readmore: %@", err);
    });
}

- (void)loadWebViewController {
    [self.webViewController navigateToPage:self.article.title discoveryMethod:MWKHistoryDiscoveryMethodReloadFromCache];
}

#pragma mark - View Updates

- (void)updateUI {
    if (![self isViewLoaded]) {
        return;
    }

    if (self.article) {
        [self updateHeaderView];
    } else {
        [self clearHeaderView];
    }

    [self updateSavedButtonState];
    [self.tableView reloadData];
}

- (void)updateHeaderView {
    WMFArticleTableHeaderView* headerView = [self headerView];

//TODO: progressively reduce title/description font to some floor size based on length of string
//      see old LeadImageTitleAttributedString.m for example from old native lead image
    headerView.titleLabel.text       = [self.article.title.text wmf_stringByRemovingHTML];
    headerView.descriptionLabel.text = [self.article.entityDescription wmf_stringByCapitalizingFirstCharacter];
}

- (void)clearHeaderView {
    WMFArticleTableHeaderView* headerView = [self headerView];
    headerView.titleLabel.attributedText = nil;
}

- (void)updateSavedButtonState {
    [self headerView].saveButton.selected = [self isSaved];
}

- (void)updateUIForMode:(WMFArticleControllerMode)mode animated:(BOOL)animated {
    switch (mode) {
        case WMFArticleControllerModeNormal: {
            self.tableView.scrollEnabled = YES;
            [self observeAndFetchArticleIfNeeded];
            break;
        }
        default: {
            [self.tableView setContentOffset:CGPointZero animated:animated];
            self.tableView.scrollEnabled = NO;
            [self unobserveArticleUpdates];
            break;
        }
    }
    self.headerGalleryViewController.view.userInteractionEnabled = mode == WMFArticleControllerModeNormal;
}

#pragma mark - Actions

- (IBAction)readButtonTapped:(id)sender {
    UINavigationController* nc = [[UINavigationController alloc] initWithRootViewController:self.webViewController];
    [self presentViewController:nc animated:YES completion:NULL];
}

- (IBAction)toggleSave:(id)sender {
    if (![self.article isCached]) {
        [self fetchArticle];
    }

    [self unobserveSavedPages];
    [self.savedPages toggleSavedPageForTitle:self.article.title];
    [self.savedPages save];
    [self observeSavedPages];
    [self updateSavedButtonState];
}

#pragma mark - Configuration

- (void)configureForDynamicCellHeight {
    self.tableView.rowHeight                    = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight           = 80;
    self.tableView.sectionHeaderHeight          = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 80;
}

#pragma mark - UIViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue*)segue sender:(id)sender {
    [super prepareForSegue:segue sender:sender];
    if ([segue.destinationViewController isKindOfClass:[WMFArticleHeaderImageGalleryViewController class]]) {
        self.headerGalleryViewController          = segue.destinationViewController;
        self.headerGalleryViewController.delegate = self;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.automaticallyAdjustsScrollViewInsets = NO;

    UICollectionViewFlowLayout* galleryLayout = (UICollectionViewFlowLayout*)_headerGalleryViewController.collectionViewLayout;
    galleryLayout.minimumInteritemSpacing = 0;
    galleryLayout.minimumLineSpacing      = 0;
    galleryLayout.scrollDirection         = UICollectionViewScrollDirectionHorizontal;

    [self.tableView registerClass:[WMFMinimalArticleContentCell class]
           forCellReuseIdentifier:[WMFMinimalArticleContentCell wmf_nibName]];

    [self observeSavedPages];
    [self clearHeaderView];
    [self configureForDynamicCellHeight];
    [self updateUI];
    [self updateUIForMode:self.mode animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self logPreview];
    [self updateUI];

    // Note: do not call "fetchReadMoreForTitle:" in updateUI! Because we don't save the read more results to the data store, we need to fetch
    // them, but not every time the card controller causes the ui to be updated (ie on scroll as it recycles article views).
    if (self.mode != WMFArticleControllerModeList) {
        if (self.article.title) {
            [self fetchReadMoreForTitle:self.article.title];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self logPageView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case WMFArticleSectionTypeSummary:
            return 1;
            break;
        case WMFArticleSectionTypeTOC:
            return self.article.sections.count - 1;
            break;
        case WMFArticleSectionTypeReadMore:
            return self.readMoreResults.articleCount;
            break;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section != WMFArticleSectionTypeSummary) {
        return UITableViewAutomaticDimension;
    }
    DTAttributedTextCell* cell = [self contentCellAtIndexPath:indexPath];
    return [cell requiredRowHeightInTableView:tableView];
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    switch ((WMFArticleSectionType)indexPath.section) {
        case WMFArticleSectionTypeSummary: return [self contentCellAtIndexPath:indexPath];
        case WMFArticleSectionTypeTOC: return [self tocSectionCellAtIndexPath:indexPath];
        case WMFArticleSectionTypeReadMore: return [self readMoreCellAtIndexPath:indexPath];
    }
}

- (WMFMinimalArticleContentCell*)contentCellAtIndexPath:(NSIndexPath*)indexPath {
    WMFMinimalArticleContentCell* cell =
        [self.tableView dequeueReusableCellWithIdentifier:[WMFMinimalArticleContentCell wmf_nibName]];
    cell.attributedString          = self.article.summaryHTML;
    cell.articleNavigationDelegate = self;
    return cell;
}

- (WMFArticleSectionCell*)tocSectionCellAtIndexPath:(NSIndexPath*)indexPath {
    WMFArticleSectionCell* cell = [self.tableView dequeueReusableCellWithIdentifier:[WMFArticleSectionCell wmf_nibName]];
    cell.level           = self.article.sections[indexPath.row + 1].level;
    cell.titleLabel.text = [self.article.sections[indexPath.row + 1].line wmf_stringByRemovingHTML];
    return cell;
}

- (WMFArticleReadMoreCell*)readMoreCellAtIndexPath:(NSIndexPath*)indexPath {
    WMFArticleReadMoreCell* cell = [self.tableView dequeueReusableCellWithIdentifier:[WMFArticleReadMoreCell wmf_nibName]];
    MWKArticle* readMoreArticle  = self.readMoreResults.articles[indexPath.row];
    cell.titleLabel.text       = readMoreArticle.title.text;
    cell.descriptionLabel.text = readMoreArticle.entityDescription;

    // Not sure why long titles won't wrap without this... the TOC cells seem to...
    [cell setNeedsDisplay];
    [cell layoutIfNeeded];

    NSURL* url = [NSURL wmf_optionalURLWithString:readMoreArticle.thumbnailURL];
    [[WMFImageController sharedInstance] fetchImageWithURL:url].then(^(UIImage* image){
        cell.thumbnailImageView.image = image;
    }).catch(^(NSError* error){
        NSLog(@"Image Fetch Error: %@", [error localizedDescription]);
    });

    return cell;
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    WMFArticleSectionHeaderView* header =
        [tableView dequeueReusableCellWithIdentifier:[WMFArticleSectionHeaderView wmf_nibName]];
    //TODO(5.0): localize these!
    switch (section) {
        case WMFArticleSectionTypeSummary:
            header.sectionHeaderLabel.text = @"Summary";
            break;
        case WMFArticleSectionTypeTOC:
            header.sectionHeaderLabel.text = @"Table of contents";
            break;
        case WMFArticleSectionTypeReadMore:
            header.sectionHeaderLabel.text = @"Read more";
            break;
    }
    return header;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [self presentArticleScrolledToSectionForIndexPath:indexPath];
}

#pragma mark - Article Link Presentation

- (BOOL)isTitleReferenceToCurrentArticle:(MWKTitle*)title {
    return [[self.article title] isEqualToTitleExcludingFragment:title];
}

- (void)presentArticleScrolledToSectionForIndexPath:(NSIndexPath*)indexPath {
    MWKTitle* titleWithFragment = [self titleForSelectedIndexPath:indexPath];
    if ([self isTitleReferenceToCurrentArticle:titleWithFragment]) {
        [self.webViewController scrollToFragment:titleWithFragment.fragment];
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:self.webViewController] animated:YES completion:NULL];
    } else {
        [self presentPopupForTitle:titleWithFragment];
    }
}

- (MWKTitle*)titleForSelectedIndexPath:(NSIndexPath*)indexPath {
    switch ((WMFArticleSectionType)indexPath.section) {
        case WMFArticleSectionTypeSummary:
            return [[MWKTitle alloc] initWithSite:self.article.title.site
                                  normalizedTitle:self.article.title.text
                                         fragment:nil];
        case WMFArticleSectionTypeTOC:
            return [[MWKTitle alloc] initWithSite:self.article.title.site
                                  normalizedTitle:self.article.title.text
                                         fragment:self.article.sections[indexPath.row + 1].anchor];
        case WMFArticleSectionTypeReadMore: {
            MWKArticle* readMoreArticle = ((MWKArticle*)self.readMoreResults.articles[indexPath.row]);
            return [[MWKTitle alloc] initWithSite:readMoreArticle.site
                                  normalizedTitle:readMoreArticle.title.text
                                         fragment:nil];
        }
    }
}

- (void)presentPopupForTitle:(MWKTitle*)title {
    MWKArticle* article          = [self.dataStore articleWithTitle:title];
    WMFArticleViewController* vc = [WMFArticleViewController articleViewControllerWithDataStore:self.dataStore savedPages:self.savedPages];
    [vc setMode:WMFArticleControllerModePopup animated:NO];
    vc.article = article;

    self.popupTransition                        = [[WMFArticlePopupTransition alloc] initWithPresentingViewController:self presentedViewController:vc contentScrollView:nil];
    self.popupTransition.nonInteractiveDuration = 0.5;
    vc.transitioningDelegate                    = self.popupTransition;
    vc.modalPresentationStyle                   = UIModalPresentationCustom;

    [self presentViewController:vc animated:YES completion:NULL];
}

#pragma mark - WMFWebViewControllerDelegate

- (void)webViewController:(WebViewController*)controller didTapOnLinkForTitle:(MWKTitle*)title {
    [self presentPopupForTitle:title];
}

#pragma mark - WMFArticleHeadermageGalleryViewControllerDelegate

- (void)headerImageGallery:(WMFArticleHeaderImageGalleryViewController* __nonnull)gallery
     didSelectImageAtIndex:(NSUInteger)index {
    NSParameterAssert(![self.presentingViewController isKindOfClass:[WMFImageGalleryViewController class]]);
    WMFImageGalleryViewController* detailGallery = [[WMFImageGalleryViewController alloc] initWithArticle:nil];
    detailGallery.delegate = self;
    if (self.article.isCached) {
        detailGallery.article     = self.article;
        detailGallery.currentPage = index;
    } else {
        if (![self.articleFetcher isFetchingArticleForTitle:self.article.title]) {
            [self fetchArticle];
        }
        [detailGallery setArticleWithPromise:self.articleFetcherPromise];
    }
    [self presentViewController:detailGallery animated:YES completion:nil];
}

#pragma mark - WMFImageGalleryViewControllerDelegate

- (void)willDismissGalleryController:(WMFImageGalleryViewController* __nonnull)gallery {
    self.headerGalleryViewController.currentPage = gallery.currentPage;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - WMFArticleNavigation

- (void)scrollToFragment:(NSString* __nonnull)fragment animated:(BOOL)animated {
}

- (void)scrollToLink:(NSURL* __nonnull)linkURL animated:(BOOL)animated {
}

#pragma mark - WMFArticleNavigationDelegate

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
      didTapCitationLink:(NSString* __nonnull)citationFragment {
    if (self.article.isCached) {
        [self showCitationWithFragment:citationFragment];
    } else {
        if (!self.articleFetcherPromise) {
            [self fetchArticle];
        }
        @weakify(self);
        self.articleFetcherPromise.then(^(MWKArticle* _) {
            @strongify(self);
            [self showCitationWithFragment:citationFragment];
        });
    }
}

- (void)showCitationWithFragment:(NSString*)fragment {
    NSParameterAssert(self.article.isCached);
    MWKCitation* tappedCitation = [self.article.citations bk_match:^BOOL (MWKCitation* citation) {
        return [citation.citationIdentifier isEqualToString:fragment];
    }];
    DDLogInfo(@"Tapped citation %@", tappedCitation);
//    if (!tappedCitation) {
//        DDLogWarn(@"Failed to parse citation for article %@", self.article);
    // TEMP: show webview until we figure out what to do w/ ReferencesVC
    [self.webViewController scrollToFragment:fragment];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:self.webViewController]
                       animated:YES
                     completion:NULL];
//    }
}

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
        didTapLinkToPage:(MWKTitle* __nonnull)title {
    [self presentPopupForTitle:title];
}

- (void)articleNavigator:(id<WMFArticleNavigation> __nullable)sender
      didTapExternalLink:(NSURL* __nonnull)externalURL {
    [[[SessionSingleton sharedInstance] zeroConfigState] showWarningIfNeededBeforeOpeningURL:externalURL];
}

#pragma mark - UINavigationControllerDelegate

// placeholder

@end

NS_ASSUME_NONNULL_END
