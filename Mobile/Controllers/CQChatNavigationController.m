#import "CQChatNavigationController.h"

#import "CQChatController.h"
#import "CQChatListViewController.h"
#import "CQColloquyApplication.h"

@implementation CQChatNavigationController
- (id) init {
	if (!(self = [super init]))
		return nil;

	self.title = NSLocalizedString(@"Colloquies", @"Colloquies tab title");
	self.tabBarItem.image = [UIImage imageNamed:@"colloquies.png"];

	self.navigationBar.tintColor = [CQColloquyApplication sharedApplication].tintColor;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_unreadCountChanged) name:CQChatControllerChangedTotalImportantUnreadCountNotification object:nil];

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_chatListViewController release];

	[super dealloc];
}

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	if (!_chatListViewController) {
		_chatListViewController = [[CQChatListViewController alloc] init];
		[self pushViewController:_chatListViewController animated:NO];
	}

	[[CQChatController defaultController] showPendingChatControllerAnimated:NO];
}

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];

	[CQChatController defaultController].totalImportantUnreadCount = 0;

	_active = YES;
}

- (void) viewWillDisappear:(BOOL) animated {
	[super viewWillDisappear:animated];

	_active = NO;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation) interfaceOrientation {
	return ![[NSUserDefaults standardUserDefaults] boolForKey:@"CQDisableLandscape"];
}

#pragma mark -

- (void) pushViewController:(UIViewController *) controller animated:(BOOL) animated {
	if ([controller conformsToProtocol:@protocol(CQChatViewController)])
		[_chatListViewController selectChatViewController:(id <CQChatViewController>)controller animatedSelection:NO animatedScroll:animated];
	[super pushViewController:controller animated:animated];
}

#pragma mark -

- (void) _unreadCountChanged {
	NSInteger totalImportantUnreadCount = [CQChatController defaultController].totalImportantUnreadCount;
	if ((!_active || self.topViewController != _chatListViewController) && totalImportantUnreadCount) {
		_chatListViewController.navigationItem.title = [NSString stringWithFormat:NSLocalizedString(@"%@ (%u)", @"Unread count view title, uses the view's normal title with a number"), self.title, totalImportantUnreadCount];
		self.tabBarItem.badgeValue = [NSString stringWithFormat:@"%u", totalImportantUnreadCount];
	} else {
		_chatListViewController.navigationItem.title = self.title;
		self.tabBarItem.badgeValue = nil;
	}
}
@end