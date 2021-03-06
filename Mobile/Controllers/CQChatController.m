#import "CQChatController.h"

#import "CQAlertView.h"
#import "CQChatCreationViewController.h"
#import "CQChatListViewController.h"
#import "CQChatNavigationController.h"
#import "CQChatOrderingController.h"
#import "CQChatPresentationController.h"
#import "CQChatRoomController.h"
#import "CQColloquyApplication.h"
#import "CQConnectionsController.h"
#import "CQConsoleController.h"
#import "CQDirectChatController.h"
#if ENABLE(FILE_TRANSFERS)
#import "CQFileTransferController.h"
#endif
#import "CQSoundController.h"

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatUser.h>
#import <ChatCore/MVDirectChatConnection.h>
#if ENABLE(FILE_TRANSFERS)
#import <ChatCore/MVFileTransfer.h>
#endif

NSString *CQChatControllerAddedChatViewControllerNotification = @"CQChatControllerAddedChatViewControllerNotification";
NSString *CQChatControllerRemovedChatViewControllerNotification = @"CQChatControllerRemovedChatViewControllerNotification";
NSString *CQChatControllerChangedTotalImportantUnreadCountNotification = @"CQChatControllerChangedTotalImportantUnreadCountNotification";

#define ChatRoomInviteAlertTag 1
#if ENABLE(FILE_TRANSFERS)
#define FileDownloadAlertTag 2
#endif

#define NewChatActionSheetTag 1
#define NewConnectionActionSheetTag 2
#if ENABLE(FILE_TRANSFERS)
#define SendFileActionSheetTag 3
#define FileTypeActionSheetTag 4
#endif

static NSInteger alwaysShowNotices;
static NSString *chatRoomInviteAction;
static BOOL vibrateOnHighlight;
static CQSoundController *highlightSound;

#if ENABLE(FILE_TRANSFERS)
static BOOL vibrateOnFileTransfer;
static CQSoundController *fileTransferSound;
#endif

#pragma mark -

@implementation CQChatController
@synthesize nextRoomConnection = _nextRoomConnection;

+ (void) userDefaultsChanged {
	if (![NSThread isMainThread])
		return;

	alwaysShowNotices = [[CQSettingsController settingsController] integerForKey:@"JVChatAlwaysShowNotices"];
	vibrateOnHighlight = [[CQSettingsController settingsController] boolForKey:@"CQVibrateOnHighlight"];

	id old = chatRoomInviteAction;
	chatRoomInviteAction = [[[CQSettingsController settingsController] stringForKey:@"CQChatRoomInviteAction"] copy];
	[old release];

	NSString *soundName = [[CQSettingsController settingsController] stringForKey:@"CQSoundOnHighlight"];

	old = highlightSound;
	highlightSound = ([soundName isEqualToString:@"None"] ? nil : [[CQSoundController alloc] initWithSoundNamed:soundName]);
	[old release];

#if ENABLE(FILE_TRANSFERS)
	vibrateOnFileTransfer = [[CQSettingsController settingsController] boolForKey:@"CQVibrateOnFileTransfer"];

	soundName = [[CQSettingsController settingsController] stringForKey:@"CQSoundOnFileTransfer"];

	old = fileTransferSound;
	fileTransferSound = ([soundName isEqualToString:@"None"] ? nil : [[CQSoundController alloc] initWithSoundNamed:soundName]);
	[old release];
#endif
}

+ (void) initialize {
	static BOOL userDefaultsInitialized;

	if (userDefaultsInitialized)
		return;

	userDefaultsInitialized = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsChanged) name:CQSettingsDidChangeNotification object:nil];

	[self userDefaultsChanged];
}

+ (CQChatController *) defaultController {
	static BOOL creatingSharedInstance = NO;
	static CQChatController *sharedInstance = nil;

	if (!sharedInstance && !creatingSharedInstance) {
		creatingSharedInstance = YES;
		sharedInstance = [[self alloc] init];
	}

	return sharedInstance;
}

#pragma mark -

- (id) init {
	if (!(self = [super init]))
		return nil;

	_chatNavigationController = [[CQChatNavigationController alloc] init];

	if ([[UIDevice currentDevice] isPadModel])
		_chatPresentationController = [[CQChatPresentationController alloc] init];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_joinedRoom:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotRoomMessage:) name:MVChatRoomGotMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotPrivateMessage:) name:MVChatConnectionGotPrivateMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotDirectChatMessage:) name:MVDirectChatConnectionGotMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_invitedToRoom:) name:MVChatRoomInvitedNotification object:nil];
#if ENABLE(FILE_TRANSFERS)
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotFileDownloadOffer:) name:MVDownloadFileTransferOfferNotification object:nil];
#endif

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:_chatPresentationController];

	[_chatNavigationController release];
	[_chatPresentationController release];
	[_nextController release];
	[_nextRoomConnection release];
	[_fileUser release];

	[super dealloc];
}

#pragma mark -

- (void) _joinedRoom:(NSNotification *) notification {
	MVChatRoom *room = notification.object;
	CQChatRoomController *roomController = [[CQChatOrderingController defaultController] chatViewControllerForRoom:room ifExists:NO];
	[roomController didJoin];
}

- (void) _gotRoomMessage:(NSNotification *) notification {
	// We do this here to make sure we catch early messages right when we join (this includes dircproxy's dump).
	MVChatRoom *room = notification.object;

	CQChatRoomController *controller = [[CQChatOrderingController defaultController] chatViewControllerForRoom:room ifExists:NO];
	[controller addMessage:notification.userInfo];
}

- (void) _gotPrivateMessage:(NSNotification *) notification {
	MVChatUser *user = notification.object;

	if (user.localUser && [notification.userInfo objectForKey:@"target"])
		user = [notification.userInfo objectForKey:@"target"];

	BOOL hideFromUser = NO;
	if ([[notification.userInfo objectForKey:@"notice"] boolValue]) {
		if (![[CQChatOrderingController defaultController] chatViewControllerForUser:user ifExists:YES])
			hideFromUser = YES;

		if ( alwaysShowNotices == 1 || ( alwaysShowNotices == 0 && ![[notification userInfo] objectForKey:@"handled"] ) )
			hideFromUser = NO;
	}

	if (!hideFromUser) {
		CQDirectChatController *controller = [[CQChatOrderingController defaultController] chatViewControllerForUser:user ifExists:NO userInitiated:NO];
		[controller addMessage:notification.userInfo];
	}
}

- (void) _gotDirectChatMessage:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;

	CQDirectChatController *controller = [[CQChatOrderingController defaultController] chatViewControllerForDirectChatConnection:connection ifExists:NO];
	[controller addMessage:notification.userInfo];
}

#if ENABLE(FILE_TRANSFERS)
- (void) _gotFileDownloadOffer:(NSNotification *) notification {
	MVDownloadFileTransfer *transfer = notification.object;

	NSString *action = [[CQSettingsController settingsController] stringForKey:@"CQFileDownloadAction"];
	if ([action isEqualToString:@"Auto-Accept"]) {
		[self chatViewControllerForFileTransfer:transfer ifExists:NO];

		NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:transfer.originalFileName];
		[transfer setDestination:filePath renameIfFileExists:YES];
		[transfer acceptByResumingIfPossible:YES];
		return;
	} else if ([action isEqualToString:@"Auto-Deny"]) {
		[transfer reject];
		return;
	}

	[self chatViewControllerForFileTransfer:transfer ifExists:NO];

	NSString *file = transfer.originalFileName;
	NSString *user = transfer.user.displayName;

	UIAlertView *alert = [[UIAlertView alloc] init];
	alert.tag = FileDownloadAlertTag;
	alert.delegate = self;
	alert.title = NSLocalizedString(@"File Download", "File Download alert title");
	alert.message = [NSString stringWithFormat:NSLocalizedString(@"%@ wants to send you \"%@\".", "File download alert message"), user, file];

	[alert associateObject:transfer forKey:@"transfer"];
	[alert addButtonWithTitle:NSLocalizedString(@"Accept", @"Accept alert button title")];

	alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Deny", @"Deny alert button title")];

	if (vibrateOnFileTransfer)
		[CQSoundController vibrate];

	[fileTransferSound playSound];

	[alert show];

	[alert release];
}

- (void) _sendImage:(UIImage *) image asPNG:(BOOL) asPNG {
	NSData *data = nil;
	if (asPNG) data = UIImagePNGRepresentation(image);
	else data = UIImageJPEGRepresentation(image, 0.83333333f);

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd-A"];

	NSString *name = [[formatter stringFromDate:[NSDate date]] stringByAppendingString:@".png"];
	[formatter release];

	name = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	[data writeToFile:path atomically:NO];

	MVUploadFileTransfer *transfer = [_fileUser sendFile:path passively:YES];
	[self chatViewControllerForFileTransfer:transfer ifExists:NO];
	[_fileUser release];
}
#endif

- (void) _invitedToRoom:(NSNotification *) notification {
	NSString *roomName = [[notification userInfo] objectForKey:@"room"];
	MVChatConnection *connection = [notification object];

	if ([chatRoomInviteAction isEqualToString:@"Auto-Join"]) {
		[connection joinChatRoomNamed:roomName];
		return;
	} else if ([chatRoomInviteAction isEqualToString:@"Auto-Deny"]) {
		return;
	}

	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	MVChatRoom *room = [connection chatRoomWithName:roomName];

	NSString *message = [NSString stringWithFormat:NSLocalizedString(@"You are invited to \"%@\" by \"%@\" on \"%@\".", "Invited to join room alert message"), room.displayName, user.displayName, connection.displayName];

	if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
		UILocalNotification *localNotification = [[UILocalNotification alloc] init];

		localNotification.alertBody = message;
		localNotification.alertAction = NSLocalizedString(@"Join", "Join button title");
		localNotification.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:connection.uniqueIdentifier, @"c", room.name, @"r", @"j", @"a", nil];
		localNotification.soundName = UILocalNotificationDefaultSoundName;

		[[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];

		[localNotification release];
		return;
	}

	CQAlertView *alert = [[CQAlertView alloc] init];
	alert.tag = ChatRoomInviteAlertTag;
	alert.delegate = self;
	alert.title = NSLocalizedString(@"Invited to Room", "Invited to room alert title");
	alert.message = message;

	alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Dismiss", @"Dismiss alert button title")];

	[alert associateObject:room forKey:@"userInfo"];
	[alert addButtonWithTitle:NSLocalizedString(@"Join", @"Join button title")];

	if (vibrateOnHighlight)
		[CQSoundController vibrate];

	if (highlightSound)
		[highlightSound playSound];

	[alert show];

	[alert release];
}

#pragma mark -

- (void) alertView:(UIAlertView *) alertView clickedButtonAtIndex:(NSInteger) buttonIndex {
	id userInfo = [alertView associatedObjectForKey:@"userInfo"];

	if (buttonIndex == alertView.cancelButtonIndex) {
#if ENABLE(FILE_TRANSFERS)
		if (alertView.tag == FileDownloadAlertTag)
			[(MVDownloadFileTransfer *)userInfo reject];
#endif
		return;
	}

	if (alertView.tag == ChatRoomInviteAlertTag) {
		MVChatRoom *room = userInfo;
		[[CQChatController defaultController] showChatControllerWhenAvailableForRoomNamed:room.name andConnection:room.connection];
		[room join];
#if ENABLE(FILE_TRANSFERS)
	} else if (alertView.tag == FileDownloadAlertTag) {
		MVDownloadFileTransfer *transfer = userInfo;
		NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:transfer.originalFileName];
		[self chatViewControllerForFileTransfer:transfer ifExists:NO];
		[transfer setDestination:filePath renameIfFileExists:YES];
		[transfer acceptByResumingIfPossible:YES];
#endif
	}
}

#pragma mark -

- (void) actionSheet:(UIActionSheet *) actionSheet clickedButtonAtIndex:(NSInteger) buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex) {
		[_fileUser release];
		_fileUser = nil;
		return;
	}

	if (actionSheet.tag == NewChatActionSheetTag) {
		CQChatCreationViewController *creationViewController = [[CQChatCreationViewController alloc] init];

		if (buttonIndex == 0)
			creationViewController.roomTarget = YES;

		[[CQColloquyApplication sharedApplication] presentModalViewController:creationViewController animated:YES];
		[creationViewController release];
	} else if (actionSheet.tag == NewConnectionActionSheetTag) {
		if (buttonIndex == 0) {
			[[CQConnectionsController defaultController] showNewConnectionPrompt:[actionSheet associatedObjectForKey:@"userInfo"]];
		} else if (buttonIndex == 1) {
			[self joinSupportRoom];
		}
#if ENABLE(FILE_TRANSFERS)
	} else if (actionSheet.tag == SendFileActionSheetTag) {
		BOOL sendExistingPhoto = NO;
		BOOL takeNewPhoto = NO;
		BOOL sendContact = NO;

		if (buttonIndex == 0) {
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
				takeNewPhoto = YES;
            } else if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
				sendExistingPhoto = YES;
            } else {
                sendContact = YES;
            }
        } else if (buttonIndex == 1) {
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
				sendExistingPhoto = YES;
            } else {
                sendContact = YES;
            }
        } else {
			sendContact = YES;
        }

		if (takeNewPhoto) {
			UIImagePickerController *picker = [[UIImagePickerController alloc] init];
			picker.delegate = self;
			picker.allowsEditing = YES;
			picker.sourceType = UIImagePickerControllerSourceTypeCamera;
			[[CQColloquyApplication sharedApplication] presentModalViewController:picker animated:YES];
			[picker release];
		} else if (sendExistingPhoto) {
			UIImagePickerController *picker = [[UIImagePickerController alloc] init];
			picker.delegate = self;
			picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
			[[CQColloquyApplication sharedApplication] presentModalViewController:picker animated:YES];
			[picker release];
		} else if (sendContact) {
			NSAssert(NO, @"Contact sending not implemented.");
		}
    } else if (actionSheet.tag == FileTypeActionSheetTag) {
		[self _sendImage:[actionSheet associatedObjectForKey:@"image"] asPNG:(buttonIndex == 0)];
#endif
	}
}

#pragma mark -

#if ENABLE(FILE_TRANSFERS)
- (void) imagePickerController:(UIImagePickerController *) picker didFinishPickingImage:(UIImage *) image editingInfo:(NSDictionary *) editingInfo {
	NSString *behavior = [[CQSettingsController settingsController] stringForKey:@"CQImageFileTransferBehavior"];
	if ([behavior isEqualToString:@"Ask"]) {
		UIActionSheet *sheet = [[UIActionSheet alloc] init];
		sheet.delegate = self;
		sheet.tag = FileTypeActionSheetTag;
		[sheet associateObject:image forKey:@"image"];
		[sheet addButtonWithTitle:NSLocalizedString(@"PNG", @"PNG button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"JPG", @"JPG button title")];
		[[CQColloquyApplication sharedApplication] showActionSheet:sheet];
		[sheet release];
	} else {
		[self _sendImage:image asPNG:[behavior isEqualToString:@"PNG"]];
	}

    [[CQColloquyApplication sharedApplication] dismissModalViewControllerAnimated:YES];
}

- (void) imagePickerControllerDidCancel:(UIImagePickerController *) picker {
    [[CQColloquyApplication sharedApplication] dismissModalViewControllerAnimated:YES];
    [_fileUser release];
}
#endif

#pragma mark -

@synthesize visibleChatController = _visibleChatController;
@synthesize chatNavigationController = _chatNavigationController;
@synthesize chatPresentationController = _chatPresentationController;
@synthesize totalImportantUnreadCount = _totalImportantUnreadCount;

- (void) setTotalImportantUnreadCount:(NSInteger) count {
	if (count < 0)
		count = 0;

	_totalImportantUnreadCount = count;

	if ([CQColloquyApplication sharedApplication].areNotificationBadgesAllowed)
		[UIApplication sharedApplication].applicationIconBadgeNumber = count;

	[[NSNotificationCenter defaultCenter] postNotificationName:CQChatControllerChangedTotalImportantUnreadCountNotification object:self];
}

#pragma mark -

- (NSDictionary *) persistentStateForConnection:(MVChatConnection *) connection {
	NSArray *controllers = [[CQChatOrderingController defaultController] chatViewControllersForConnection:connection];
	if (!controllers.count)
		return nil;

	NSMutableDictionary *state = [[NSMutableDictionary alloc] init];
	NSMutableArray *controllerStates = [[NSMutableArray alloc] init];

	for (id <CQChatViewController> controller in controllers) {
		if (![controller respondsToSelector:@selector(persistentState)])
			continue;

		NSDictionary *controllerState = controller.persistentState;
		if (!controllerState.count || ![controllerState objectForKey:@"class"])
			continue;

		[controllerStates addObject:controllerState];
	}

	if (controllerStates.count)
		[state setObject:controllerStates forKey:@"chatControllers"];

	[controllerStates release];

	return [state autorelease];
}

- (void) restorePersistentState:(NSDictionary *) state forConnection:(MVChatConnection *) connection {
	for (NSDictionary *controllerState in [state objectForKey:@"chatControllers"]) {
		NSString *className = [controllerState objectForKey:@"class"];
		Class class = NSClassFromString(className);
		if (!class)
			continue;

		id <CQChatViewController> controller = [[class alloc] initWithPersistentState:controllerState usingConnection:connection];
		if (!controller)
			continue;

		[[CQChatOrderingController defaultController] addViewController:controller];
		[controller release];

		if ([[controllerState objectForKey:@"active"] boolValue]) {
			id old = _nextController;
			_nextController = [controller retain];
			[old release];
		}
	}
}

#pragma mark -

- (void) showNewChatActionSheet:(id) sender {
	UIActionSheet *sheet = [[UIActionSheet alloc] init];
	sheet.delegate = self;

	[sheet associateObject:sender forKey:@"userInfo"];

	if ([CQConnectionsController defaultController].connections.count) {
		sheet.tag = NewChatActionSheetTag;

		[sheet addButtonWithTitle:NSLocalizedString(@"Join a Chat Room", @"Join a Chat Room button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"Message a User", @"Message a User button title")];
	} else {
		sheet.tag = NewConnectionActionSheetTag;

		[sheet addButtonWithTitle:NSLocalizedString(@"Add New Connection", @"Add New Connection button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"Join Support Room", @"Join Support Room button title")];
	}

	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet forSender:sender animated:YES];

	[sheet release];
}

#pragma mark -

- (void) showChatControllerWhenAvailableForRoomNamed:(NSString *) roomName andConnection:(MVChatConnection *) connection {
	NSParameterAssert(connection != nil);

	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	MVChatRoom *room = (roomName.length ? [connection chatRoomWithName:roomName] : nil);
	if (room) {
		CQChatRoomController *controller = [[CQChatOrderingController defaultController] chatViewControllerForRoom:room ifExists:YES];
		if (controller) {
			[self showChatController:controller animated:[UIView areAnimationsEnabled]];
			return;
		}
	}

	_nextRoomConnection = [connection retain];
}

- (void) showChatControllerForUserNicknamed:(NSString *) nickname andConnection:(MVChatConnection *) connection {
	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	MVChatUser *user = (nickname.length ? [[connection chatUsersWithNickname:nickname] anyObject] : nil);
	if (!user)
		return;

	CQDirectChatController *controller = [[CQChatOrderingController defaultController] chatViewControllerForUser:user ifExists:NO];
	if (!controller)
		return;

	[self showChatController:controller animated:[UIView areAnimationsEnabled]];
}

- (void) showChatController:(id <CQChatViewController>) controller animated:(BOOL) animated {
	if (![UIDevice currentDevice].isPadModel) {
		[[CQColloquyApplication sharedApplication] showColloquies:nil hidingTopViewController:NO];
		if ([controller respondsToSelector:@selector(setHidesBottomBarWhenPushed:)])
			((UIViewController *)controller).hidesBottomBarWhenPushed = YES;
	}

	if (_visibleChatController == controller)
		return;

	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	id old = _visibleChatController;
	_visibleChatController = [controller retain];
	[old release];

	if ([[UIDevice currentDevice] isPadModel]) {
		_chatPresentationController.topChatViewController = controller;
		[_chatNavigationController selectChatViewController:controller animatedSelection:animated animatedScroll:animated];
	} else {
		if (_chatNavigationController.presentedViewController != nil) {
			[_chatNavigationController popToRootViewControllerAnimated:NO];
			[_chatNavigationController pushViewController:(UIViewController *)controller animated:NO];
			[_chatNavigationController dismissViewControllerAnimated:animated completion:NULL];
		} else {
			if (!_chatNavigationController.rootViewController)
				[[CQColloquyApplication sharedApplication] showColloquies:nil];

			if (animated && _chatNavigationController.topViewController != _chatNavigationController.rootViewController) {
				id old = _nextController;
				_nextController = [controller retain];
				[old release];

				[_chatNavigationController popToRootViewControllerAnimated:animated];
			} else {
				[_chatNavigationController popToRootViewControllerAnimated:NO];
				[_chatNavigationController pushViewController:(UIViewController *)controller animated:animated];

				[_nextController release];
				_nextController = nil;
			}
		}
	}
}

- (void) showPendingChatControllerAnimated:(BOOL) animated {
	if (_nextController)
		[self showChatController:_nextController animated:animated];
}

- (BOOL) hasPendingChatController {
	return !!_nextController;
}

#pragma mark -

#if ENABLE(FILE_TRANSFERS)
- (void) showFilePickerWithUser:(MVChatUser *) user {
	UIActionSheet *sheet = [[UIActionSheet alloc] init];
	sheet.delegate = self;
	sheet.tag = SendFileActionSheetTag;

	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
		[sheet addButtonWithTitle:NSLocalizedString(@"Take Photo", @"Take Photo button title")];
	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
		[sheet addButtonWithTitle:NSLocalizedString(@"Choose Existing Photo", @"Choose Existing Photo button title")];
//	[sheet addButtonWithTitle:NSLocalizedString(@"Choose Contact", @"Choose Contact button title")];

	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	_fileUser = [user retain];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet];

	[sheet release];
}
#endif

#pragma mark -

- (void) joinSupportRoom {
	MVChatConnection *connection = [[CQConnectionsController defaultController] connectionForServerAddress:@"freenode.net"];
	if (!connection) connection = [[CQConnectionsController defaultController] connectionForServerAddress:@"freenode.com"];

	if (!connection) {
		connection = [[MVChatConnection alloc] initWithType:MVChatConnectionIRCType];
		connection.displayName = @"Freenode";
		connection.server = @"irc.freenode.net";
		connection.preferredNickname = [MVChatConnection defaultNickname];
		connection.realName = [MVChatConnection defaultRealName];
		connection.username = [connection.preferredNickname lowercaseString];
		connection.encoding = [MVChatConnection defaultEncoding];
		connection.automaticallyConnect = NO;
		connection.multitaskingSupported = YES;
		connection.secure = NO;
		connection.serverPort = 6667;

		[[CQConnectionsController defaultController] addConnection:connection];

		[connection release];
	}

	[connection connectAppropriately];

	[self showChatControllerWhenAvailableForRoomNamed:@"#colloquy-mobile" andConnection:connection];

	[connection joinChatRoomNamed:@"#colloquy-mobile"];

	[[CQColloquyApplication sharedApplication] showColloquies:nil];
}

#pragma mark -

- (void) showConsoleForConnection:(MVChatConnection *) connection {
	CQConsoleController *consoleController = [[CQChatOrderingController defaultController] chatViewControllerForConnection:connection ifExists:NO userInitiated:NO];

	[self showChatController:consoleController animated:YES];
}

#pragma mark -

- (void) _showChatControllerUnanimated:(id) controller {
	[self showChatController:controller animated:NO];
}

- (void) visibleChatControllerWasHidden {
	id old = _visibleChatController;
	_visibleChatController = nil;
	[old release];
}

- (void) closeViewController:(id) controller {
	if ([controller respondsToSelector:@selector(close)])
		[controller close];

	[controller retain];

	NSUInteger controllerIndex = [[CQChatOrderingController defaultController] indexOfViewController:controller];

	[[CQChatOrderingController defaultController] removeViewController:controller];

	NSDictionary *notificationInfo = [NSDictionary dictionaryWithObject:controller forKey:@"controller"];
	[[NSNotificationCenter defaultCenter] postNotificationName:CQChatControllerRemovedChatViewControllerNotification object:self userInfo:notificationInfo];

	if ([[UIDevice currentDevice] isPadModel] && _visibleChatController == controller) {
		if ([CQChatOrderingController defaultController].chatViewControllers.count) {
			if (!controllerIndex)
				controllerIndex = 1;
			[self performSelector:@selector(_showChatControllerUnanimated:) withObject:[[CQChatOrderingController defaultController].chatViewControllers objectAtIndex:(controllerIndex - 1)] afterDelay:0.];
		} else [self showChatController:nil animated:YES];
	}

	[controller release];
}
@end

#pragma mark -

@implementation MVIRCChatRoom (CQChatControllerAdditions)
- (NSString *) displayName {
	if (![[CQSettingsController settingsController] boolForKey:@"JVShowFullRoomNames"])
		return [self.connection displayNameForChatRoomNamed:self.name];
	return self.name;
}
@end
