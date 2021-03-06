//
//  WALMasterViewController.m
//  Wallabag
//
//  Created by Kevin Meyer on 19.02.14.
//  Copyright (c) 2014 Wallabag. All rights reserved.
//

#import "WALFeedTableViewController.h"
#import "WALArticleViewController.h"
#import "WALSettingsTableViewController.h"
#import "WALAddArticleTableViewController.h"
#import "WALNavigationController.h"
#import "WALArticleTableViewCell.h"

#import "WALServerConnection.h"
#import "WALThemeOrganizer.h"
#import "WALTheme.h"
#import "WALIcons.h"

#import "WALArticle.h"
#import "WALArticleList.h"
#import "WALSettings.h"

#import <AFNetworking/AFHTTPRequestOperationManager.h>

@interface WALFeedTableViewController ()

@property (strong) WALArticleList *articleList;
@property (strong) WALArticleList *articleListFavorite;
@property (strong) WALArticleList *articleListArchive;

@property (strong) WALSettings* settings;
@property BOOL showAllArticles;
- (IBAction)actionsButtonPushed:(id)sender;

@property (strong) UIActionSheet* actionSheet;

@property (weak) IBOutlet UISegmentedControl *headerSegmentedControl;
- (IBAction)headerSegmentedControlValueDidChange:(id)sender;
@end

@implementation WALFeedTableViewController

- (void)awakeFromNib
{
	self.showAllArticles = NO;
		
	WALThemeOrganizer *themeOrganizer = [WALThemeOrganizer sharedThemeOrganizer];
	[self updateWithTheme:[themeOrganizer getCurrentTheme]];
	[themeOrganizer subscribeToThemeChanges:self];
	
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(triggeredRefreshControl) forControlEvents:UIControlEventValueChanged];
	[super awakeFromNib];
	
	self.articleList = [[WALArticleList alloc] initAsType:WALArticleListTypeUnread];
	[self.articleList loadArticlesFromDisk];

	self.settings = [WALSettings settingsFromSavedSettings];
	[self updateArticleList];
	
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad && [self.articleList getNumberOfUnreadArticles] > 0)
	{
		NSIndexPath *firstCellIndex = [NSIndexPath indexPathForRow:0 inSection:0];
		[self performSegueWithIdentifier:@"PushToArticle" sender:[self.tableView cellForRowAtIndexPath:firstCellIndex]];
		[self.tableView selectRowAtIndexPath:firstCellIndex animated:NO scrollPosition:UITableViewScrollPositionNone];
	}
}

- (void) viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self.navigationController setToolbarHidden:YES];
	
	if (!self.settings)
		[self performSegueWithIdentifier:@"ModalToSettings" sender:self];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self.navigationController setToolbarHidden:animated];
}

- (void)triggeredRefreshControl
{
	[self updateArticleList];
}

#pragma mark -

- (IBAction)headerSegmentedControlValueDidChange:(id)sender {
	UISegmentedControl *control = (UISegmentedControl*) sender;

	WALArticleList *list = [self getCurrentArticleList];
	
	if (!list) {
		if (control.selectedSegmentIndex == 1) {
			self.articleListFavorite = [[WALArticleList alloc] initAsType:WALArticleListTypeFavorites];
		} else if (control.selectedSegmentIndex == 2) {
			self.articleListArchive = [[WALArticleList alloc] initAsType:WALArticleListTypeArchive];
		}

		list = [self getCurrentArticleList];
		[list loadArticlesFromDisk];
		[self updateArticleList];
	}
	
	[self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
	[self.tableView reloadData];
}

- (WALArticleList*)getCurrentArticleList {
	if (self.headerSegmentedControl.selectedSegmentIndex == 2) {
		return self.articleListArchive;
	} else if (self.headerSegmentedControl.selectedSegmentIndex == 1) {
		return self.articleListFavorite;
	}
	
	return self.articleList;
}

- (void)updateArticleList
{
	if (!self.settings)
	{
		[self.refreshControl endRefreshing];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		[self performSegueWithIdentifier:@"ModalToSettings" sender:self];
		return;
	}
	
	WALServerConnection *server = [[WALServerConnection alloc] init];
	WALArticleList *currentValidArticleList = [self getCurrentArticleList];
	[server loadArticlesOfListType:[currentValidArticleList getListType] withSettings:self.settings OldArticleList:currentValidArticleList delegate:self];
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	[self.refreshControl beginRefreshing];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	WALArticleList *articleList = [self getCurrentArticleList];
	
	if (self.showAllArticles)
		return [articleList getNumberOfAllArticles];
	
	return [articleList getNumberOfUnreadArticles];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	WALArticleList *articleList = [self getCurrentArticleList];
	
	WALArticle *currentArticle;
	if (self.showAllArticles)
		currentArticle = [articleList getArticleAtIndex:indexPath.row];
	else
		currentArticle = [articleList getUnreadArticleAtIndex:indexPath.row];
	
	WALTheme *currentTheme = [[WALThemeOrganizer sharedThemeOrganizer] getCurrentTheme];
	
    WALArticleTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ArticleCell" forIndexPath:indexPath];
	cell.titleLabel.text = currentArticle.title;
	cell.titleLabel.textColor = [currentTheme getTextColor];
	cell.detailLabel.text = currentArticle.link.host;
	cell.detailLabel.textColor = [currentTheme getTintColor];
	cell.backgroundColor = [currentTheme getBackgroundColor];
	
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	WALArticleList *articleList = [self getCurrentArticleList];

	
	CGFloat constantHeight = 15.0f + 8.0f;
	NSString *cellTitle = self.showAllArticles ? [articleList getArticleAtIndex:indexPath.row].title : [articleList getUnreadArticleAtIndex:indexPath.row].title;
	CGFloat tableWidth = floor(tableView.bounds.size.width);
	CGSize maximumLabelSize = CGSizeMake(tableWidth - (15.0f + 12.0f + 33.0f), FLT_MAX);
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		maximumLabelSize = CGSizeMake(tableWidth - (15.0f + 15.0f), FLT_MAX);
	}

	CGRect expectedLabelSize = [cellTitle boundingRectWithSize:maximumLabelSize
													   options:NSStringDrawingUsesLineFragmentOrigin
													attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
													   context:nil];

	return constantHeight + ceil(expectedLabelSize.size.height);
}

#pragma mark - Theming

- (void)themeOrganizer:(WALThemeOrganizer *)organizer setNewTheme:(WALTheme *)theme
{
	[self updateWithTheme:theme];
	[self.tableView reloadData];
}

- (void) updateWithTheme:(WALTheme*) theme
{
	self.tableView.backgroundColor = [theme getBackgroundColor];
	self.refreshControl.tintColor = [theme getTextColor];
}

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"PushToArticle"])
	{
		NSIndexPath *indexPath = [self.tableView indexPathForCell:sender];
		WALArticleList *articleList = [self getCurrentArticleList];
		
		WALArticle *articleToSet;
		if (self.showAllArticles)
			articleToSet = [articleList getArticleAtIndex:indexPath.row];
		else
			articleToSet = [articleList getUnreadArticleAtIndex:indexPath.row];
		
		WALArticleViewController *articleVC;
		
		if ([segue.destinationViewController isKindOfClass:[UINavigationController class]])
		{
			UINavigationController *navigationVC = (UINavigationController*) segue.destinationViewController;
			articleVC = (WALArticleViewController*) navigationVC.viewControllers[0];
		}
		else
			articleVC = (WALArticleViewController*) segue.destinationViewController;
			
		[articleVC setDetailArticle:articleToSet];
		
		[[self.tableView cellForRowAtIndexPath:indexPath] setSelected:false animated:TRUE];
	}
	else if ([[segue identifier] isEqualToString:@"ModalToSettings"])
	{
		WALSettingsTableViewController *targetViewController = ((WALSettingsTableViewController*)[segue.destinationViewController viewControllers][0]);
		targetViewController.delegate = self;
		[targetViewController setSettings:self.settings];
	}
	else if ([[segue identifier] isEqualToString:@"ModalToAddArticle"])
	{
		WALAddArticleTableViewController *targetViewController = ((WALAddArticleTableViewController*)[segue.destinationViewController viewControllers][0]);
		targetViewController.delegate = self;
	}
}

- (IBAction)actionsButtonPushed:(id)sender
{
	if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {
		if (self.actionSheet)
		{
			[self.actionSheet dismissWithClickedButtonIndex:-1 animated:YES];
			self.actionSheet = nil;
			return;
		}
		
		self.actionSheet = [[UIActionSheet alloc] init];
		self.actionSheet.title = NSLocalizedString(@"Actions", nil);
		
		[self.actionSheet addButtonWithTitle:NSLocalizedString(@"Add Article", nil)];
		[self.actionSheet addButtonWithTitle:NSLocalizedString(@"Change Theme", nil)];
		
		if (self.showAllArticles)
			[self.actionSheet addButtonWithTitle:NSLocalizedString(@"Show unread Articles", nil)];
		else
			[self.actionSheet addButtonWithTitle:NSLocalizedString(@"Show all Articles", nil)];
		
		[self.actionSheet addButtonWithTitle:NSLocalizedString(@"cancel", nil)];
		
		[self.actionSheet setCancelButtonIndex:3];
		[self.actionSheet setTag:1];
		[self.actionSheet setDelegate:self];
		[self.actionSheet showFromBarButtonItem:sender animated:YES];
	} else {
		UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Actions", nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		
		[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Add Article", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self actionsAddArticlePushed];
		}]];
		[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Change Theme", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self actionsChangeThemePushed];
		}]];
		
		if (self.showAllArticles)
			[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Show unread Articles", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[self actionsShowArticlesPushed];
			}]];
		else
			[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Show all Articles", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[self actionsShowArticlesPushed];
			}]];
		
		[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
		
		UIPopoverPresentationController *popoverController = alertController.popoverPresentationController;
		popoverController.barButtonItem = self.navigationItem.rightBarButtonItem;
		popoverController.permittedArrowDirections = UIPopoverArrowDirectionAny;
		
		[self presentViewController:alertController animated:YES completion:nil];
	}
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (actionSheet.tag == 1)
	{
		if (buttonIndex == 0)
		{
			[self actionsAddArticlePushed];
		}
		else if (buttonIndex == 1)
		{
			[self actionsChangeThemePushed];
		}
		else if (buttonIndex == 2)
		{
			[self actionsShowArticlesPushed];
		}
	}
	self.actionSheet = nil;
}

- (void) actionsAddArticlePushed {
	[self performSelector:@selector(showAddArticleViewController) withObject:nil afterDelay:0];
}

- (void) actionsChangeThemePushed {
	WALThemeOrganizer *themeOrganizer = [WALThemeOrganizer sharedThemeOrganizer];
	[themeOrganizer changeTheme];
}

- (void) actionsShowArticlesPushed {
	self.showAllArticles = !self.showAllArticles;
	[self.tableView reloadData];
}

- (void) showAddArticleViewController {
	[self performSegueWithIdentifier:@"ModalToAddArticle" sender:self];
}

#pragma mark - Callback Delegates

- (void)serverConnection:(WALServerConnection *)connection didFinishWithArticleList:(WALArticleList *)articleList
{
	switch ([articleList getListType]) {
		case WALArticleListTypeUnread:
			[self.articleList deleteCachedArticles];
			self.articleList = articleList;
			[self.articleList saveArticlesFromDisk];
			[self.articleList updateUnreadArticles];
			break;
			
		case WALArticleListTypeFavorites:
			[self.articleListFavorite deleteCachedArticles];
			self.articleListFavorite = articleList;
			[self.articleListFavorite saveArticlesFromDisk];
			[self.articleListFavorite updateUnreadArticles];
			break;
			
		case WALArticleListTypeArchive:
			[self.articleListArchive deleteCachedArticles];
			self.articleListArchive = articleList;
			[self.articleListArchive saveArticlesFromDisk];
			[self.articleListArchive updateUnreadArticles];
			break;
	}
	
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	[self.refreshControl endRefreshing];
	
	[self.tableView reloadData];
}

- (void)serverConnection:(WALServerConnection *)connection didFinishWithError:(NSError *)error
{
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	[self.refreshControl endRefreshing];
	
	[self informUserConnectionError:error];
}

- (void)settingsController:(WALSettingsTableViewController *)settingsTableViewController didFinishWithSettings:(WALSettings*)settings
{
	if (settings)
	{
		self.settings = settings;
		[settings saveSettings];
		[self updateArticleList];
	}
	[self.navigationController dismissViewControllerAnimated:true completion:nil];
}

- (void)addArticleController:(WALAddArticleTableViewController *)addArticleController didFinishWithURL:(NSURL *)url
{
	[self.navigationController dismissViewControllerAnimated:true completion:nil];
	
	if (url)
	{
		NSURL *myUrl = [self.settings getURLToAddArticle:url];
		if ([[UIApplication sharedApplication] canOpenURL:myUrl])
			[[UIApplication sharedApplication] openURL:myUrl];
	}
}

#pragma mark - Error Handling

- (void) informUserConnectionError:(NSError*) error
{
	[self showMessageWithTitle:NSLocalizedString(@"Error", nil) andMessage:error.localizedDescription];
}

- (void) informUserWrongServerAddress
{
	[self showMessageWithTitle:NSLocalizedString(@"Error", nil) andMessage:NSLocalizedString(@"Could not connect to server. Maybe wrong URL?", @"error description: HTTP Status Code not 2xx")];
}

- (void) informUserWrongAuthentication
{
	[self showMessageWithTitle:NSLocalizedString(@"Error", nil) andMessage:NSLocalizedString(@"Could load feed. Maybe wrong user credentials?", @"error description: response is not a rss feed")];
}

- (void) informUserNoArticlesInFeed
{
	[self showMessageWithTitle:NSLocalizedString(@"Error", nil) andMessage:NSLocalizedString(@"No unread article in Feed. Get started by adding links to your wallabag.", @"error description: No article in home-feed")];
}

- (void)showMessageWithTitle:(NSString *) title andMessage:(NSString *) message {
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
	[alertView show];

}

@end
