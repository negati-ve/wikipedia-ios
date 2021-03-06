#import "WMFRelatedSectionController.h"

// Networking & Model
#import "WMFRelatedSearchFetcher.h"
#import "MWKTitle.h"
#import "WMFRelatedSearchResults.h"
#import "MWKRelatedSearchResult.h"
#import "MWKSavedPageList.h"

// Controllers
#import "WMFRelatedTitleListDataSource.h"

// Frameworks
#import "Wikipedia-Swift.h"

// View
#import "WMFArticlePreviewCell.h"
#import "UIView+WMFDefaultNib.h"

// Style
#import "UIFont+WMFStyle.h"

static NSString* const WMFRelatedSectionIdentifierPrefix = @"WMFRelatedSectionIdentifier";
static NSUInteger const WMFNumberOfExtractLines          = 4;
static NSUInteger const WMFRelatedSectionMaxResults      = 3;

@interface WMFRelatedSectionController ()

@property (nonatomic, strong, readwrite) MWKTitle* title;
@property (nonatomic, strong, readwrite) WMFRelatedSearchFetcher* relatedSearchFetcher;
@property (nonatomic, strong) MWKSavedPageList* savedPageList;

@property (nonatomic, strong) WMFRelatedTitleListDataSource* relatedTitleDataSource;

@end

@implementation WMFRelatedSectionController
@synthesize relatedTitleDataSource = _relatedTitleDataSource;

@synthesize delegate = _delegate;

- (instancetype)initWithArticleTitle:(MWKTitle*)title
                            delegate:(id<WMFHomeSectionControllerDelegate>)delegate {
    return [self initWithArticleTitle:title
                             delegate:delegate
                 relatedSearchFetcher:[[WMFRelatedSearchFetcher alloc] init]];
}

- (instancetype)initWithArticleTitle:(MWKTitle*)title
                            delegate:(id<WMFHomeSectionControllerDelegate>)delegate
                relatedSearchFetcher:(WMFRelatedSearchFetcher*)relatedSearchFetcher {
    NSParameterAssert(title);
    NSParameterAssert(relatedSearchFetcher);
    self = [super init];
    if (self) {
        self.relatedSearchFetcher = relatedSearchFetcher;
        self.title                = title;
        self.delegate             = delegate;
    }
    return self;
}

- (void)setSavedPageList:(MWKSavedPageList*)savedPageList {
    /*
       HAX: can't fetch titles until we get the saved page list, since it's needed to create articles
          and configure cells
     */
    _savedPageList = savedPageList;
    [self fetchRelatedArticles];
}

- (id)sectionIdentifier {
    return [WMFRelatedSectionIdentifierPrefix stringByAppendingString:self.title.text];
}

- (NSAttributedString*)headerText {
    NSMutableAttributedString* link = [[NSMutableAttributedString alloc] initWithString:self.title.text];
    [link addAttribute:NSLinkAttributeName value:self.title.desktopURL range:NSMakeRange(0, link.length)];
    // TODO: localize
    [link insertAttributedString:[[NSAttributedString alloc] initWithString:@"Because you read " attributes:nil] atIndex:0];
    return link;
}

- (NSString*)footerText {
    // TODO: localize
    return [NSString stringWithFormat:@"More like %@", self.title.text];
}

- (NSArray*)items {
    return [self.relatedTitleDataSource.relatedTitleResults
            wmf_safeSubarrayWithRange:NSMakeRange(0, WMFRelatedSectionMaxResults)];
}

- (MWKTitle*)titleForItemAtIndex:(NSUInteger)index {
    MWKSearchResult* result = self.items[index];
    MWKSite* site           = self.title.site;
    MWKTitle* title         = [site titleWithString:result.displayTitle];
    return title;
}

- (void)registerCellsInCollectionView:(UICollectionView* __nonnull)collectionView {
    [collectionView registerNib:[WMFArticlePreviewCell wmf_classNib] forCellWithReuseIdentifier:[WMFArticlePreviewCell identifier]];
}

- (UICollectionViewCell*)dequeueCellForCollectionView:(UICollectionView*)collectionView atIndexPath:(NSIndexPath*)indexPath {
    return [WMFArticlePreviewCell cellForCollectionView:collectionView indexPath:indexPath];
}

- (void)configureCell:(UICollectionViewCell*)cell
           withObject:(id)object
     inCollectionView:(UICollectionView*)collectionView
          atIndexPath:(NSIndexPath*)indexPath {
    if ([cell isKindOfClass:[WMFArticlePreviewCell class]]) {
        WMFArticlePreviewCell* previewCell = (id)cell;
        previewCell.summaryLabel.numberOfLines = WMFNumberOfExtractLines;
        MWKRelatedSearchResult* result = object;
        previewCell.title           = [self titleForItemAtIndex:indexPath.row];
        previewCell.descriptionText = result.wikidataDescription;
        previewCell.imageURL        = result.thumbnailURL;
        [previewCell setSummaryHTML:result.extractHTML fromSite:self.title.site];
        [previewCell setSavedPageList:self.savedPageList];
        NSAssert (^{
            UIFont* actualFont = [previewCell.summaryLabel.attributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil] ? : previewCell.summaryLabel.font;
            UIFont* requiredFont = [UIFont wmf_htmlBodyFont];
            return [actualFont.familyName isEqualToString:requiredFont.familyName]
            && (fabs(actualFont.pointSize - requiredFont.pointSize) < 0.01);
        } (), @"Expected previewCell to use standard HTML body font! Needed for numberOfExtactCharactersToFetch.");
    }
}

- (WMFRelatedTitleListDataSource*)relatedTitleDataSource {
    if (!_relatedTitleDataSource) {
        /*
           HAX: Need to use the "more" data source to fetch data and keep it around since morelike: searches for the same
           title don't have the same results in order. might need to look into continuation soon
         */
        _relatedTitleDataSource = [[WMFRelatedTitleListDataSource alloc]
                                   initWithTitle:self.title
                                        dataStore:self.savedPageList.dataStore
                                    savedPageList:self.savedPageList
                        numberOfExtractCharacters:[self numberOfExtractCharactersToFetch]
                                      resultLimit:WMFMaxRelatedSearchResultLimit
                                          fetcher:self.relatedSearchFetcher];
    }
    return _relatedTitleDataSource;
}

- (SSArrayDataSource<WMFArticleListDataSource>*)extendedListDataSource {
    if (!self.relatedSearchFetcher.isFetching && !self.relatedTitleDataSource.relatedTitleResults) {
        [self.relatedTitleDataSource fetch];
    }
    return self.relatedTitleDataSource;
}

#pragma mark - Section Updates

- (void)updateSectionWithResults:(WMFRelatedSearchResults*)results {
}

- (void)updateSectionWithSearchError:(NSError*)error {
}

#pragma mark - Fetch

- (NSUInteger)numberOfExtractCharactersToFetch {
    CGFloat maxLabelWidth = [self.delegate maxItemWidth];
    NSParameterAssert(maxLabelWidth > 0);
    UIFont* summaryHTMLFont           = [UIFont wmf_htmlBodyFont];
    CGFloat approximateCharacterWidth = summaryHTMLFont.xHeight;
    NSUInteger charsPerLine           = ceilf(maxLabelWidth / approximateCharacterWidth);
    // and some extra lines to force UILabel to truncate the string, and hopefully have enough for landscape to truncate it too
    return charsPerLine * (WMFNumberOfExtractLines + 3.0);
}

- (void)fetchRelatedArticles {
    if (self.relatedSearchFetcher.isFetching) {
        return;
    }
    @weakify(self);
    [self.relatedTitleDataSource fetch]
    .then(^(WMFRelatedSearchResults* _){
        @strongify(self);
        [self.delegate controller:self didSetItems:self.items];
    })
    .catch(^(NSError* error){
        @strongify(self);
        [self updateSectionWithSearchError:error];
    });
}

@end
