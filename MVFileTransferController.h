NSString *MVPrettyFileSize( unsigned long long size );
NSString *MVReadableTime( NSTimeInterval date, BOOL longFormat );

@class MVFileTransfer;

@interface MVFileTransferController : NSWindowController {
@private
	IBOutlet NSProgressIndicator *progressBar;
	IBOutlet NSTextField *transferStatus;
	IBOutlet NSTableView *currentFiles;
	NSMutableArray *_transferStorage;
	NSMutableArray *_calculationItems;
	NSTimer *_updateTimer;
	NSSet *_safeFileExtentions;
}
+ (NSString *) userPreferredDownloadFolder;
+ (void) setUserPreferredDownloadFolder:(NSString *) path;

+ (MVFileTransferController *) defaultManager;

- (IBAction) showTransferManager:(id) sender;
- (IBAction) hideTransferManager:(id) sender;

- (void) downloadFileAtURL:(NSURL *) url toLocalFile:(NSString *) path;
- (void) addFileTransfer:(id) transfer;

- (IBAction) stopSelectedTransfer:(id) sender;
- (IBAction) clearFinishedTransfers:(id) sender;
- (IBAction) revealSelectedFile:(id) sender;
@end
