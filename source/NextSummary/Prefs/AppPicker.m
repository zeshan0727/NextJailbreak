#import "AppPicker.h"
#import "../Shared.h"
#import <objc/message.h>

static id NSUCall(id target, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id,SEL))objc_msgSend)(target,sel); }
    @catch (__unused NSException *e) { return nil; }
}
static NSString *NSUString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

@interface NSUAppPicker ()
@property(nonatomic,copy) NSArray<NSDictionary *> *apps;
@property(nonatomic,copy) NSArray<NSDictionary *> *visibleApps;
@property(nonatomic,strong) NSMutableSet<NSString *> *selected;
@property(nonatomic,strong) UISearchController *search;
@end

@implementation NSUAppPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Installed apps";
    self.definesPresentationContext=YES;
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater=self;
    self.search.obscuresBackgroundDuringPresentation=NO;
    self.search.searchBar.placeholder=@"Search apps or bundle IDs";
    self.navigationItem.searchController=self.search;
    self.navigationItem.hidesSearchBarWhenScrolling=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addBundleID)];
    self.tableView.rowHeight=58;
    [self refreshApps];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshApps];
}
- (void)refreshApps {
    id stored=NSUConfig()[@"apps"];
    self.selected=[NSMutableSet setWithArray:[stored isKindOfClass:NSArray.class]?stored:@[]];
    NSMutableDictionary<NSString *,NSString *> *names=[@{
        @"com.facebook.Messenger":@"Messenger",@"net.whatsapp.WhatsApp":@"WhatsApp",
        @"com.apple.MobileSMS":@"Messages",@"ph.telegra.Telegraph":@"Telegram",
        @"com.apple.mobilemail":@"Mail",@"org.whispersystems.signal":@"Signal"
    } mutableCopy];
    id ws=NSUCall(NSClassFromString(@"LSApplicationWorkspace"),@"defaultWorkspace");
    id apps=NSUCall(ws,@"allApplications");
    if ([apps conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id app in apps) {
            NSString *identifier=NSUString(NSUCall(app,@"applicationIdentifier"));
            if (!identifier.length) identifier=NSUString(NSUCall(app,@"bundleIdentifier"));
            if (!identifier.length || [identifier isEqualToString:@"com.apple.springboard"] || [identifier isEqualToString:@"com.apple.Preferences"]) continue;
            NSString *type=NSUString(NSUCall(app,@"applicationType"));
            if (type.length && ![@[@"User",@"System"] containsObject:type]) continue;
            NSString *name=NSUString(NSUCall(app,@"localizedName"));
            if (!name.length) name=NSUString(NSUCall(app,@"localizedShortName"));
            names[identifier]=name.length?name:(names[identifier]?:identifier);
        }
    }
    id manual=NSUConfig()[@"manualApps"];
    for (id item in ([manual isKindOfClass:NSArray.class]?manual:@[])) if ([item isKindOfClass:NSString.class] && !names[item]) names[item]=item;
    for (id item in self.selected) if ([item isKindOfClass:NSString.class] && !names[item]) names[item]=item;
    NSMutableArray *rows=[NSMutableArray array];
    for (NSString *identifier in names) [rows addObject:@{@"id":identifier,@"name":names[identifier]}];
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSComparisonResult r=[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        return r==NSOrderedSame?[a[@"id"] compare:b[@"id"]]:r;
    }];
    self.apps=rows;
    [self updateSearchResultsForSearchController:self.search];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q=[searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!q.length) self.visibleApps=self.apps;
    else self.visibleApps=[self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,NSDictionary *bindings){
        return [row[@"name"] localizedCaseInsensitiveContainsString:q] || [row[@"id"] localizedCaseInsensitiveContainsString:q];
    }]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApps.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [NSString stringWithFormat:@"%lu selected · %lu shown",(unsigned long)self.selected.count,(unsigned long)self.visibleApps.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Tap an app to enable or disable AI summaries. Only selected apps send notification previews to OpenAI. Use + to add a missing bundle ID. System notifications without an app identifier cannot be selected automatically.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"NSUApp"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NSUApp"];
    NSDictionary *row=self.visibleApps[indexPath.row];
    cell.textLabel.text=row[@"name"];
    cell.detailTextLabel.text=row[@"id"];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.accessoryType=[self.selected containsObject:row[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    cell.accessibilityTraits=UIAccessibilityTraitButton|([self.selected containsObject:row[@"id"]]?UIAccessibilityTraitSelected:0);
    return cell;
}
- (void)error:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Next Summary" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *identifier=self.visibleApps[indexPath.row][@"id"];
    NSMutableDictionary *config=[NSUConfig() mutableCopy];
    id stored=config[@"apps"];
    NSMutableSet *next=[NSMutableSet setWithArray:[stored isKindOfClass:NSArray.class]?stored:@[]];
    if ([next containsObject:identifier]) [next removeObject:identifier]; else [next addObject:identifier];
    config[@"apps"]=[[next allObjects] sortedArrayUsingSelector:@selector(compare:)];
    if (!NSUSave(config)) { [self error:@"Could not save app selection."]; return; }
    self.selected=next;
    [self.tableView reloadData];
}
- (void)addBundleID {
    self.search.active=NO;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Add application" message:@"Enter the exact bundle identifier. Adding it does not enable AI summaries until you select it." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"com.example.app"; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.autocorrectionType=UITextAutocorrectionTypeNo; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        typeof(self) selfRef=weakSelf; if(!selfRef)return;
        NSString *identifier=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSPredicate *valid=[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+"];
        if(identifier.length>255 || ![valid evaluateWithObject:identifier]) { dispatch_async(dispatch_get_main_queue(), ^{[selfRef error:@"Enter a valid application bundle ID."];}); return; }
        NSMutableDictionary *config=[NSUConfig() mutableCopy];
        id old=config[@"manualApps"];
        NSMutableSet *manual=[NSMutableSet setWithArray:[old isKindOfClass:NSArray.class]?old:@[]];
        [manual addObject:identifier]; config[@"manualApps"]=[[manual allObjects] sortedArrayUsingSelector:@selector(compare:)];
        if(!NSUSave(config)) { dispatch_async(dispatch_get_main_queue(), ^{[selfRef error:@"Could not save the application."];}); return; }
        [selfRef refreshApps];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
