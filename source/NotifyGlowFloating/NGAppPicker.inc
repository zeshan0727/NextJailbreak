// Next Jailbreak — local application selection. No network or third-party dependencies.
#import <objc/message.h>
#import <dlfcn.h>

static CFStringRef const NGAppSelectionKey=CFSTR("NotificationGlowFloatingSelectedApps");
static id NGAppValue(id obj, NSString *key) {
    @try {return [obj valueForKey:key];} @catch(__unused NSException *e){return nil;}
}
static NSString *NGAppText(id obj, NSString *key){
    id v=NGAppValue(obj,key);return [v isKindOfClass:NSString.class]?v:nil;
}
@interface NGFloatingAppsController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) NSMutableSet<NSString *> *chosen;
@property(nonatomic,strong) NSArray<NSDictionary *> *apps;
@property(nonatomic,strong) NSArray<NSDictionary *> *visible;
@property(nonatomic,strong) UISearchController *searcher;
@end
@implementation NGFloatingAppsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Floating Apps";
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue(NGAppSelectionKey,Domain));
    self.chosen=[NSMutableSet new];if([saved isKindOfClass:NSArray.class])for(id v in saved)if([v isKindOfClass:NSString.class])[self.chosen addObject:[v lowercaseString]];
    self.searcher=[[UISearchController alloc]initWithSearchResultsController:nil];
    self.searcher.searchResultsUpdater=self;self.searcher.obscuresBackgroundDuringPresentation=NO;
    self.searcher.searchBar.placeholder=@"Search installed apps";
    self.navigationItem.searchController=self.searcher;self.definesPresentationContext=YES;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addIdentifier)];
    self.tableView.rowHeight=56;
    self.tableView.tableFooterView=[UIView new];
    [self loadApps];
}
- (void)loadApps {
    Class c=NSClassFromString(@"LSApplicationWorkspace");
    if(!c){dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_LAZY|RTLD_LOCAL);c=NSClassFromString(@"LSApplicationWorkspace");}
    if(!c){dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_LAZY|RTLD_LOCAL);c=NSClassFromString(@"LSApplicationWorkspace");}
    NSMutableDictionary *found=[NSMutableDictionary new];
    @try {
        SEL shared=NSSelectorFromString(@"defaultWorkspace");
        id ws=[c respondsToSelector:shared]?((id(*)(id,SEL))objc_msgSend)(c,shared):nil;
        for(NSString *method in @[@"allApplications",@"allInstalledApplications"]){
            SEL sel=NSSelectorFromString(method);
            if(![ws respondsToSelector:sel])continue;
            id proxies=((id(*)(id,SEL))objc_msgSend)(ws,sel);
            if(![proxies conformsToProtocol:@protocol(NSFastEnumeration)])continue;
            for(id proxy in proxies){
                NSString *identifier=NGAppText(proxy,@"applicationIdentifier")?:NGAppText(proxy,@"bundleIdentifier");
                if(!identifier.length||![identifier containsString:@"."])continue;
                NSString *kind=NGAppText(proxy,@"applicationType");
                if(kind.length&&![kind isEqualToString:@"User"]&&![kind isEqualToString:@"System"])continue;
                NSString *name=NGAppText(proxy,@"localizedName")?:NGAppText(proxy,@"localizedShortName")?:identifier;
                found[identifier.lowercaseString]=@{@"id":identifier.lowercaseString,@"name":name};
            }
        }
    }@catch(__unused NSException *e){}
    // Keep manually entered or previously selected identifiers selectable too.
    for(NSString *identifier in self.chosen)if(!found[identifier])found[identifier]=@{@"id":identifier,@"name":identifier};
    self.apps=[found.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSComparisonResult r=[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        return r==NSOrderedSame?[a[@"id"] compare:b[@"id"]]:r;
    }];
    [self updateSearchResultsForSearchController:self.searcher];
}
- (void)save {
    NSArray *list=[[self.chosen allObjects] sortedArrayUsingSelector:@selector(compare:)];
    CFPreferencesSetAppValue(NGAppSelectionKey,(__bridge CFArrayRef)list,Domain);
    Sync();[self.tableView reloadData];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q=searchController.searchBar.text?:@"";
    if(!q.length)self.visible=self.apps;
    else self.visible=[self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d,__unused NSDictionary *bindings){return [d[@"name"] localizedCaseInsensitiveContainsString:q]||[d[@"id"] localizedCaseInsensitiveContainsString:q];}]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)t {return 1;}
- (NSInteger)tableView:(__unused UITableView *)t numberOfRowsInSection:(__unused NSInteger)section {return self.visible.count;}
- (NSString *)tableView:(__unused UITableView *)t titleForHeaderInSection:(__unused NSInteger)section {return [NSString stringWithFormat:@"%lu SELECTED · NEXT JAILBREAK",(unsigned long)self.chosen.count];}
- (NSString *)tableView:(__unused UITableView *)t titleForFooterInSection:(__unused NSInteger)section {
    return self.apps.count?@"Tap an app to enable or disable floating icons. The selection applies when All apps is off. Use + to add a bundle identifier.":@"Installed apps unavailable. Use + to enter an app bundle identifier manually.";
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"NGFloatingApp"];
    if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NGFloatingApp"];
    NSDictionary *d=self.visible[ip.row];cell.textLabel.text=d[@"name"];cell.detailTextLabel.text=d[@"id"];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.accessoryType=[self.chosen containsObject:d[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];NSString *key=self.visible[ip.row][@"id"];
    if([self.chosen containsObject:key])[self.chosen removeObject:key];else [self.chosen addObject:key];
    [self save];
}
- (void)addIdentifier {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Add app" message:@"Enter its bundle identifier, e.g. com.apple.MobileSMS." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"com.example.app";f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        NSString *v=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
        if(v.length>2&&v.length<256&&[v containsString:@"."]&&[v rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location==NSNotFound){[weak.chosen addObject:v];[weak save];[weak loadApps];}
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
