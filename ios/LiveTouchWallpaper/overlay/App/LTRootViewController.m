#import "LTRootViewController.h"
#import "LTSpawnRoot.h"

@interface LTRootViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *cleanupButton;
@property (nonatomic, strong) UIButton *respringButton;
@end

@implementation LTRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"LiveTouch Cleanup";

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Remove LiveTouch Completely";
    title.font = [UIFont boldSystemFontOfSize:28.0];
    title.numberOfLines = 0;
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *body = [UILabel new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.text = @"This final cleanup build removes the LiveTouch SpringBoard engine from RootHide/ElleKit and legacy tweak paths, deletes the saved wallpaper video, preferences, and engine log. After cleanup, respring once and then delete LiveTouch from TrollStore.";
    body.font = [UIFont systemFontOfSize:16.0];
    body.textColor = UIColor.secondaryLabelColor;
    body.numberOfLines = 0;
    body.textAlignment = NSTextAlignmentCenter;

    UIButton *cleanup = [UIButton buttonWithType:UIButtonTypeSystem];
    cleanup.translatesAutoresizingMaskIntoConstraints = NO;
    [cleanup setTitle:@"Uninstall LiveTouch Files" forState:UIControlStateNormal];
    cleanup.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [cleanup setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    cleanup.backgroundColor = UIColor.systemRedColor;
    cleanup.layer.cornerRadius = 14.0;
    cleanup.contentEdgeInsets = UIEdgeInsetsMake(15, 18, 15, 18);
    [cleanup addTarget:self action:@selector(cleanupTapped) forControlEvents:UIControlEventTouchUpInside];
    self.cleanupButton = cleanup;

    UIButton *respring = [UIButton buttonWithType:UIButtonTypeSystem];
    respring.translatesAutoresizingMaskIntoConstraints = NO;
    [respring setTitle:@"Respring to Finish Cleanup" forState:UIControlStateNormal];
    respring.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    respring.contentEdgeInsets = UIEdgeInsetsMake(13, 16, 13, 16);
    [respring addTarget:self action:@selector(respringTapped) forControlEvents:UIControlEventTouchUpInside];
    self.respringButton = respring;

    UITextView *log = [UITextView new];
    log.translatesAutoresizingMaskIntoConstraints = NO;
    log.editable = NO;
    log.selectable = YES;
    log.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    log.backgroundColor = UIColor.secondarySystemBackgroundColor;
    log.layer.cornerRadius = 12.0;
    log.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    log.text = @"Ready. Tap Uninstall LiveTouch Files.";
    self.logView = log;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, body, cleanup, respring, log]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    [self.view addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-20],
        [cleanup.heightAnchor constraintGreaterThanOrEqualToConstant:56],
        [respring.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        [log.heightAnchor constraintGreaterThanOrEqualToConstant:220]
    ]];
}

- (void)setBusy:(BOOL)busy {
    self.cleanupButton.enabled = !busy;
    self.respringButton.enabled = !busy;
    self.cleanupButton.alpha = busy ? 0.5 : 1.0;
    self.respringButton.alpha = busy ? 0.5 : 1.0;
}

- (void)cleanupTapped {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Remove LiveTouch?"
                                                                     message:@"This deletes the installed LiveTouch engine, saved wallpaper video, preferences, and logs. The app itself remains until you delete it from TrollStore."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [weakSelf performCleanup];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performCleanup {
    [self setBusy:YES];
    self.logView.text = @"Removing LiveTouch files...";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *output = nil;
        int rc = LTRunRootHelper(@[@"uninstall"], &output);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) selfRef = weakSelf;
            if (!selfRef) return;
            [selfRef setBusy:NO];
            selfRef.logView.text = output.length ? output : [NSString stringWithFormat:@"Cleanup exit code: %d", rc];
            NSString *title = rc == 0 ? @"Cleanup Complete" : @"Cleanup Finished With Warning";
            NSString *message = rc == 0 ? @"LiveTouch installed files were removed. Tap Respring to Finish Cleanup, then delete LiveTouch from TrollStore." : @"Some files could not be removed. Review the log below before deleting the app.";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [selfRef presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)respringTapped {
    [self setBusy:YES];
    self.logView.text = @"Requesting RootHide respring...";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *output = nil;
        int rc = LTRunRootHelper(@[@"respring"], &output);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) selfRef = weakSelf;
            if (!selfRef) return;
            [selfRef setBusy:NO];
            selfRef.logView.text = output.length ? output : [NSString stringWithFormat:@"Respring exit code: %d", rc];
            if (rc != 0) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Manual Respring Required" message:@"LiveTouch files are already removed. Respring once from your RootHide/Dopamine environment, then delete LiveTouch from TrollStore." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [selfRef presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

@end
