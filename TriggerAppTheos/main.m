#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString * const NJTOwner = @"zeshan0727";
static NSString * const NJTRepo = @"NextJailbreak";
static NSString * const NJTBranch = @"main";
static NSString * const NJTService = @"com.nextjailbreak.trigger";
static NSString * const NJTAccount = @"github-token";

@interface NJTRootViewController : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) UITextField *tokenField;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSMutableArray<UIButton *> *actionButtons;
@end

@interface NJTAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end

@implementation NJTRootViewController

- (NSArray<NSDictionary *> *)workflows {
    return @[
        @{ @"title": @"Verified Tweak Post", @"file": @"tweak-draft-generator.yml" },
        @{ @"title": @"Original-Source News", @"file": @"ios-repo-original-source-news.yml" },
        @{ @"title": @"Dopamine 3 Post", @"file": @"dopamine3-cluster-publisher.yml" }
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Next Jailbreak Trigger";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.actionButtons = [NSMutableArray array];
    [self buildUI];
    self.tokenField.text = [self loadToken];
    [self setStatus:@"Ready. Save your GitHub token, then tap Post Now."];
}

- (UILabel *)label:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style];
    return label;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 12;
    button.backgroundColor = self.view.tintColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:52].active = YES;
    return button;
}

- (void)buildUI {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 13;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28]
    ]];

    UILabel *intro = [self label:@"Manual control for the Next Jailbreak article publishers. Your GitHub token stays on this iPhone in Keychain and is never written to the public repository." style:UIFontTextStyleBody];
    [stack addArrangedSubview:intro];

    self.tokenField = [UITextField new];
    self.tokenField.placeholder = @"GitHub fine-grained token";
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.tokenField.borderStyle = UITextBorderStyleRoundedRect;
    self.tokenField.delegate = self;
    [self.tokenField.heightAnchor constraintEqualToConstant:48].active = YES;
    [stack addArrangedSubview:self.tokenField];

    UIStackView *tokenRow = [UIStackView new];
    tokenRow.axis = UILayoutConstraintAxisHorizontal;
    tokenRow.distribution = UIStackViewDistributionFillEqually;
    tokenRow.spacing = 10;
    UIButton *save = [self button:@"Save Token" action:@selector(saveTokenTapped)];
    UIButton *test = [self button:@"Test Token" action:@selector(testTokenTapped)];
    [tokenRow addArrangedSubview:save];
    [tokenRow addArrangedSubview:test];
    [stack addArrangedSubview:tokenRow];

    UIView *line = [UIView new];
    line.backgroundColor = UIColor.separatorColor;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    [stack addArrangedSubview:line];

    UILabel *heading = [self label:@"Publish now" style:UIFontTextStyleHeadline];
    [stack addArrangedSubview:heading];

    NSArray *workflows = [self workflows];
    for (NSInteger i = 0; i < workflows.count; i++) {
        NSDictionary *item = workflows[i];
        NSString *title = (i == 0) ? @"POST NOW — Verified Tweak" : [NSString stringWithFormat:@"Run — %@", item[@"title"]];
        UIButton *button = [self button:title action:@selector(workflowTapped:)];
        button.tag = i;
        if (i > 0) button.backgroundColor = UIColor.systemIndigoColor;
        [self.actionButtons addObject:button];
        [stack addArrangedSubview:button];
    }

    UIButton *refresh = [self button:@"Refresh Latest Run Status" action:@selector(refreshTapped)];
    refresh.backgroundColor = UIColor.systemGrayColor;
    [stack addArrangedSubview:refresh];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.spinner];

    self.statusLabel = [self label:@"" style:UIFontTextStyleFootnote];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.statusLabel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.statusLabel.layer.cornerRadius = 10;
    self.statusLabel.layer.masksToBounds = YES;
    [self.statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    [stack addArrangedSubview:self.statusLabel];

    UILabel *note = [self label:@"The manual trigger starts the same GitHub automation used by the site. Quality checks, duplicate protection, source verification, daily limits and publication-gap rules remain active, so a successful trigger may still safely produce a no-op when no eligible article is available." style:UIFontTextStyleFootnote];
    note.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:note];
}

- (NSDictionary *)keychainQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: NJTService,
        (__bridge id)kSecAttrAccount: NJTAccount
    };
}

- (BOOL)saveToken:(NSString *)token {
    NSDictionary *base = [self keychainQuery];
    SecItemDelete((__bridge CFDictionaryRef)base);
    NSMutableDictionary *item = [base mutableCopy];
    item[(__bridge id)kSecValueData] = [token dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

- (NSString *)loadToken {
    NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) return @"";
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSString *)currentToken {
    return [self.tokenField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (BOOL)requireToken {
    if ([self currentToken].length == 0) {
        [self setStatus:@"Enter a GitHub token first. The token needs Actions: Read and write access to NextJailbreak."];
        return NO;
    }
    return YES;
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path method:(NSString *)method {
    if (![self requireToken]) return nil;
    NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/%@", path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = method;
    request.timeoutInterval = 30;
    [request setValue:[NSString stringWithFormat:@"Bearer %@", [self currentToken]] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:@"NextJailbreakTrigger/1.0" forHTTPHeaderField:@"User-Agent"];
    return request;
}

- (void)setBusy:(BOOL)busy message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIButton *button in self.actionButtons) button.enabled = !busy;
        if (busy) [self.spinner startAnimating]; else [self.spinner stopAnimating];
        if (message) [self setStatus:message];
    });
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = [NSString stringWithFormat:@"  %@  ", [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\n  "]];
}

- (void)saveTokenTapped {
    [self.view endEditing:YES];
    NSString *token = [self currentToken];
    if (token.length == 0) {
        [self setStatus:@"Token is empty."];
        return;
    }
    [self setStatus:[self saveToken:token] ? @"Token saved securely in iOS Keychain." : @"Could not save token to Keychain."];
}

- (void)testTokenTapped {
    NSMutableURLRequest *request = [self requestForPath:[NSString stringWithFormat:@"repos/%@/%@", NJTOwner, NJTRepo] method:@"GET"];
    if (!request) return;
    [self setBusy:YES message:@"Testing repository access…"];
    [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO message:nil];
            if (error) [self setStatus:[NSString stringWithFormat:@"Token test failed: %@", error.localizedDescription]];
            else if (code == 200) [self setStatus:@"Token works. NextJailbreak repository access confirmed."];
            else [self setStatus:[NSString stringWithFormat:@"Token test returned HTTP %ld. Check repository access and token permissions.", (long)code]];
        });
    }] resume];
}

- (void)workflowTapped:(UIButton *)sender {
    NSArray *workflows = [self workflows];
    if (sender.tag < 0 || sender.tag >= workflows.count || ![self requireToken]) return;
    NSDictionary *item = workflows[sender.tag];
    [self dispatchWorkflow:item];
}

- (void)dispatchWorkflow:(NSDictionary *)item {
    NSString *title = item[@"title"];
    NSString *file = item[@"file"];
    NSString *path = [NSString stringWithFormat:@"repos/%@/%@/actions/workflows/%@/dispatches", NJTOwner, NJTRepo, file];
    NSMutableURLRequest *request = [self requestForPath:path method:@"POST"];
    if (!request) return;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"ref": NJTBranch } options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [self setBusy:YES message:[NSString stringWithFormat:@"Triggering %@…", title]];
    [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO message:nil];
            if (error) {
                [self setStatus:[NSString stringWithFormat:@"%@ failed: %@", title, error.localizedDescription]];
            } else if (code == 204) {
                [self setStatus:[NSString stringWithFormat:@"%@ TRIGGERED. Wait about 1–3 minutes, then tap Refresh Latest Run Status.", title]];
            } else {
                NSString *body = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                [self setStatus:[NSString stringWithFormat:@"%@ returned HTTP %ld. %@", title, (long)code, body ?: @""]];
            }
        });
    }] resume];
}

- (void)refreshTapped {
    if (![self requireToken]) return;
    [self setBusy:YES message:@"Loading latest workflow runs…"];
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    for (NSDictionary *item in [self workflows]) {
        dispatch_group_enter(group);
        NSString *path = [NSString stringWithFormat:@"repos/%@/%@/actions/workflows/%@/runs?per_page=1", NJTOwner, NJTRepo, item[@"file"]];
        NSMutableURLRequest *request = [self requestForPath:path method:@"GET"];
        if (!request) { dispatch_group_leave(group); continue; }
        [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSString *line = nil;
            NSInteger code = [(NSHTTPURLResponse *)response statusCode];
            if (!error && code == 200 && data.length) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSDictionary *run = [json[@"workflow_runs"] firstObject];
                if (run) {
                    line = [NSString stringWithFormat:@"%@: #%@ %@ / %@", item[@"title"], run[@"run_number"] ?: @"?", run[@"status"] ?: @"unknown", run[@"conclusion"] ?: @"—"];
                }
            }
            if (!line) line = [NSString stringWithFormat:@"%@: %@", item[@"title"], error ? error.localizedDescription : [NSString stringWithFormat:@"HTTP %ld", (long)code]];
            @synchronized(lines) { [lines addObject:line]; }
            dispatch_group_leave(group);
        }] resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self setBusy:NO message:nil];
        NSArray *sorted = [lines sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        [self setStatus:[sorted componentsJoinedByString:@"\n"]];
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

@implementation NJTAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    NJTRootViewController *root = [NJTRootViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(NJTAppDelegate.class));
    }
}
