#import <ChatCore/MVAvailability.h>
#import <ChatCore/MVChatString.h>

typedef enum {
	MVChatRoomNoModes = 0,
	MVChatRoomPrivateMode = 1 << 0,
	MVChatRoomSecretMode = 1 << 1,
	MVChatRoomInviteOnlyMode = 1 << 2,
	MVChatRoomNormalUsersSilencedMode = 1 << 3,
	MVChatRoomOperatorsSilencedMode = 1 << 4,
	MVChatRoomOperatorsOnlySetTopicMode = 1 << 5,
	MVChatRoomNoOutsideMessagesMode = 1 << 6,
	MVChatRoomPassphraseToJoinMode = 1 << 7,
	MVChatRoomLimitNumberOfMembersMode = 1 << 8
} MVChatRoomMode;

typedef enum {
	MVChatRoomMemberNoModes = 0,
	MVChatRoomMemberVoicedMode = 1 << 0,
	MVChatRoomMemberHalfOperatorMode = 1 << 1,
	MVChatRoomMemberOperatorMode = 1 << 2,
	MVChatRoomMemberAdministratorMode = 1 << 3,
	MVChatRoomMemberFounderMode = 1 << 4
} MVChatRoomMemberMode;

typedef enum {
	MVChatRoomMemberNoDisciplineModes = 0,
	MVChatRoomMemberDisciplineQuietedMode = 1 << 0
} MVChatRoomMemberDisciplineMode;

extern NSString *MVChatRoomMemberQuietedFeature;
extern NSString *MVChatRoomMemberVoicedFeature;
extern NSString *MVChatRoomMemberHalfOperatorFeature;
extern NSString *MVChatRoomMemberOperatorFeature;
extern NSString *MVChatRoomMemberAdministratorFeature;
extern NSString *MVChatRoomMemberFounderFeature;

extern NSString *MVChatRoomJoinedNotification;
extern NSString *MVChatRoomPartedNotification;
extern NSString *MVChatRoomKickedNotification;
extern NSString *MVChatRoomInvitedNotification;

extern NSString *MVChatRoomMemberUsersSyncedNotification;
extern NSString *MVChatRoomBannedUsersSyncedNotification;

extern NSString *MVChatRoomUserJoinedNotification;
extern NSString *MVChatRoomUserPartedNotification;
extern NSString *MVChatRoomUserKickedNotification;
extern NSString *MVChatRoomUserBannedNotification;
extern NSString *MVChatRoomUserBanRemovedNotification;
extern NSString *MVChatRoomUserModeChangedNotification;
extern NSString *MVChatRoomUserBrickedNotification;

extern NSString *MVChatRoomGotMessageNotification;
extern NSString *MVChatRoomTopicChangedNotification;
extern NSString *MVChatRoomModesChangedNotification;
extern NSString *MVChatRoomAttributeUpdatedNotification;

@class MVChatConnection;
@class MVChatUser;

@interface MVChatRoom : NSObject {
@protected
	MVChatConnection *_connection;
	id _uniqueIdentifier;
	NSString *_name;
	NSDate *_dateJoined;
	NSDate *_dateParted;
	NSData *_topic;
	MVChatUser *_topicAuthor;
	NSDate *_dateTopicChanged;
	NSMutableDictionary *_attributes;
	NSMutableSet *_memberUsers;
	NSMutableSet *_bannedUsers;
	NSMutableDictionary *_modeAttributes;
	NSMutableDictionary *_memberModes;
	NSMutableDictionary *_disciplineMemberModes;
	NSStringEncoding _encoding;
	NSUInteger _modes;
	NSUInteger _hash;
	BOOL _releasing;
}
@property(readonly) MVChatConnection *connection;

@property(readonly) NSURL *url;
@property(readonly) NSString *name;
@property(readonly) NSString *displayName;
@property(readonly) id uniqueIdentifier;

@property(readonly, getter=isJoined) BOOL joined;
@property(readonly) NSDate *dateJoined;
@property(readonly) NSDate *dateParted;

@property NSStringEncoding encoding;

@property(readonly) NSData *topic;
@property(readonly) MVChatUser *topicAuthor;
@property(readonly) NSDate *dateTopicChanged;

@property(readonly) NSSet *supportedAttributes;
@property(readonly) NSDictionary *attributes;

@property(readonly) NSUInteger supportedModes;
@property(readonly) NSUInteger supportedMemberUserModes;
@property(readonly) NSUInteger supportedMemberDisciplineModes;
@property(readonly) NSUInteger modes;

@property(readonly) MVChatUser *localMemberUser;
@property(readonly) NSSet *memberUsers;
@property(readonly) NSSet *bannedUsers;

- (BOOL) isEqual:(id) object;
- (BOOL) isEqualToChatRoom:(MVChatRoom *) anotherUser;

- (NSComparisonResult) compare:(MVChatRoom *) otherRoom;
- (NSComparisonResult) compareByUserCount:(MVChatRoom *) otherRoom;

- (void) join;
- (void) part;

- (void) partWithReason:(MVChatString *) reason;

- (void) changeTopic:(MVChatString *) topic;

- (void) sendMessage:(MVChatString *) message asAction:(BOOL) action;
- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action;
- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) encoding withAttributes:(NSDictionary *) attributes;

- (void) sendCommand:(NSString *) command withArguments:(MVChatString *) arguments;
- (void) sendCommand:(NSString *) command withArguments:(MVChatString *) arguments withEncoding:(NSStringEncoding) encoding;

- (void) sendSubcodeRequest:(NSString *) command withArguments:(id) arguments;
- (void) sendSubcodeReply:(NSString *) command withArguments:(id) arguments;

- (void) refreshAttributes;
- (void) refreshAttributeForKey:(NSString *) key;

- (BOOL) hasAttributeForKey:(NSString *) key;
- (id) attributeForKey:(NSString *) key;
- (void) setAttribute:(id) attribute forKey:(id) key;

- (id) attributeForMode:(MVChatRoomMode) mode;

- (void) setModes:(NSUInteger) modes;
- (void) setMode:(MVChatRoomMode) mode;
- (void) setMode:(MVChatRoomMode) mode withAttribute:(id) attribute;
- (void) removeMode:(MVChatRoomMode) mode;

- (NSSet *) memberUsersWithModes:(NSUInteger) modes;
- (NSSet *) memberUsersWithNickname:(NSString *) nickname;
- (NSSet *) memberUsersWithFingerprint:(NSString *) fingerprint;
- (MVChatUser *) memberUserWithUniqueIdentifier:(id) identifier;
- (BOOL) hasUser:(MVChatUser *) user;

- (void) kickOutMemberUser:(MVChatUser *) user forReason:(MVChatString *) reason;

- (void) addBanForUser:(MVChatUser *) user;
- (void) removeBanForUser:(MVChatUser *) user;

- (NSUInteger) modesForMemberUser:(MVChatUser *) user;
- (NSUInteger) disciplineModesForMemberUser:(MVChatUser *) user;

- (void) setModes:(NSUInteger) modes forMemberUser:(MVChatUser *) user;
- (void) setMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user;
- (void) removeMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user;

- (void) setDisciplineMode:(MVChatRoomMemberDisciplineMode) mode forMemberUser:(MVChatUser *) user;
- (void) removeDisciplineMode:(MVChatRoomMemberDisciplineMode) mode forMemberUser:(MVChatUser *) user;
@end

#pragma mark -

#if ENABLE(SCRIPTING)
@interface MVChatRoom (MVChatRoomScripting)
@property(readonly) NSString *scriptUniqueIdentifier;
@property(readonly) NSScriptObjectSpecifier *objectSpecifier;
@end
#endif
