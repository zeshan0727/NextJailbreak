#import <UIKit/UIKit.h>
#import "PhotoController.h"
BOOL NextAIWorking=NO;
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "llama.h"
#include <atomic>
#include <vector>
#include <string>
#include <memory>
#include <stdexcept>

@interface ChatController : UIViewController <UIDocumentPickerDelegate>
@end
@implementation ChatController {
 UITextView *_output; UITextField *_input; UILabel *_status; UIButton *_send;
 NSMutableArray *_messages; NSMutableArray *_archive; NSString *_chatID; NSString *_model;
 BOOL _busy; std::atomic_bool _cancel;
}
- (NSString *)documents { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject; }
- (NSString *)historyPath { return [[self documents] stringByAppendingPathComponent:@"chats.json"]; }
- (void)viewDidLoad {
 [super viewDidLoad]; self.title=@"Next AI · 0.3.0"; self.view.backgroundColor=UIColor.systemBackgroundColor;
 _cancel=false; _messages=[NSMutableArray new]; _archive=[NSMutableArray new]; _chatID=NSUUID.UUID.UUIDString;
 NSData *data=[NSData dataWithContentsOfFile:[self historyPath]];
 id saved=data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
 if ([saved isKindOfClass:NSArray.class]) for(id c in saved) if([c isKindOfClass:NSDictionary.class] && [c[@"messages"] isKindOfClass:NSArray.class]) [_archive addObject:c];
 _model=[NSUserDefaults.standardUserDefaults stringForKey:@"model"];
 if (_model && ![NSFileManager.defaultManager fileExistsAtPath:[[self documents] stringByAppendingPathComponent:_model]]) _model=nil;
 _status=[UILabel new]; _status.font=[UIFont systemFontOfSize:12]; _status.numberOfLines=2; _status.textColor=UIColor.secondaryLabelColor;
 _output=[UITextView new]; _output.editable=NO; _output.font=[UIFont systemFontOfSize:17]; _output.backgroundColor=UIColor.secondarySystemBackgroundColor; _output.layer.cornerRadius=14;
 _input=[UITextField new]; _input.placeholder=@"Message your offline AI"; _input.borderStyle=UITextBorderStyleRoundedRect;
 _send=[UIButton buttonWithType:UIButtonTypeSystem]; [_send setTitle:@"Send" forState:UIControlStateNormal]; [_send addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
 UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[_input,_send]]; row.spacing=10;
 [_send.widthAnchor constraintEqualToConstant:60].active=YES;
 UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[_status,_output,row]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],[stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12],[row.heightAnchor constraintEqualToConstant:44]]];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Menu" style:UIBarButtonItemStylePlain target:self action:@selector(menu)];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
 [self refresh];
}
- (void)background { _cancel=true; [self save]; }
- (void)refresh {
 _status.text=_model ? [@"Offline • " stringByAppendingString:_model.lastPathComponent] : @"Import Qwen2.5 1.5B Instruct Q4_K_M to begin. No internet needed after import.";
 NSMutableString *text=[NSMutableString new];
 for(NSDictionary *m in _messages) [text appendFormat:@"%@\n%@\n\n",[m[@"role"] isEqual:@"user"]?@"You":@"Next AI",m[@"content"]];
 BOOL follow=_output.contentSize.height<=_output.bounds.size.height || _output.contentOffset.y+_output.bounds.size.height>=_output.contentSize.height-100;
 _output.text=text.length?text:@"Welcome to Next AI\n\nYour model and conversations stay on this iPhone.\n\nMenu → Import model to get started.\n\n0.3.0: short text conversations, 2,048-token context and up to 384 reply tokens. Long chats will ask you to start a new conversation.";
 if(text.length && follow) [_output scrollRangeToVisible:NSMakeRange(_output.text.length-1,1)];
}
- (void)alert:(NSString *)message { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Next AI" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)save {
 if(!_messages.count) return;
 NSUInteger index=[_archive indexOfObjectPassingTest:^BOOL(id c,NSUInteger i,BOOL *stop){return [c[@"id"] isEqual:self->_chatID];}];
 NSDictionary *chat=@{@"id":_chatID,@"messages":[_messages copy]}; if(index==NSNotFound) [_archive addObject:chat]; else _archive[index]=chat;
 NSError *e=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:_archive options:0 error:&e];
 if(data && ![data writeToFile:[self historyPath] options:NSDataWritingAtomic error:&e]) _status.text=[@"Could not save chat: " stringByAppendingString:e.localizedDescription];
}
- (void)menu {
 if(NextAIWorking) { [self alert:@"Wait for the current operation or tap Stop in chat before opening the menu."]; return; }
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Next AI" message:@"All processing takes place on your iPhone." preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"Import model (.gguf)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES]; p.delegate=self; [self presentViewController:p animated:YES completion:nil]; }]];
 [a addAction:[UIAlertAction actionWithTitle:@"Use model from Next AI folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self chooseLocalModel];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"New chat" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self save]; self->_chatID=NSUUID.UUID.UUIDString; self->_messages=[NSMutableArray new]; [self refresh];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Saved chats" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self showChats];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Copy last answer" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){for(NSDictionary *m in [self->_messages reverseObjectEnumerator])if([m[@"role"] isEqual:@"assistant"]){UIPasteboard.generalPasteboard.string=m[@"content"];return;}[self alert:@"No answer to copy yet."];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Copy conversation" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){UIPasteboard.generalPasteboard.string=self->_output.text;}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Delete current chat" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[self confirmDelete];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem; [self presentViewController:a animated:YES completion:nil];
}
- (void)chooseLocalModel {
 NSString *root=[self documents];
 NSArray *files=[NSFileManager.defaultManager subpathsOfDirectoryAtPath:root error:nil];
 NSMutableArray<NSString *> *models=[NSMutableArray new];
 for(NSString *file in files) if([file.pathExtension.lowercaseString isEqual:@"gguf"]) [models addObject:file];
 if(!models.count){[self alert:@"In Files, copy your downloaded .gguf into On My iPhone → Next AI. Then return here and tap Use model from Next AI folder. You can also copy it into this app's Documents folder with Filza."];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Choose local model" message:@"Models already inside Next AI do not need to be imported again." preferredStyle:UIAlertControllerStyleActionSheet];
 for(NSString *file in models) [a addAction:[UIAlertAction actionWithTitle:file.lastPathComponent style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
 NSURL *url=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:file]];
 NSError *error=nil; NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
 if(error || size.unsignedLongLongValue>2200000000ULL){[self alert:error.localizedDescription ?: @"For this test, choose a model smaller than 2.2 GB."];return;}
 NSFileHandle *h=[NSFileHandle fileHandleForReadingFromURL:url error:&error];
 NSData *magic=h ? [h readDataUpToLength:4 error:&error] : nil;[h closeFile];
 if(error || ![magic isEqual:[@"GGUF" dataUsingEncoding:NSUTF8StringEncoding]]){[self alert:error.localizedDescription ?: @"Not a complete GGUF model. Please finish downloading the file first."];return;}
 self->_model=file;[NSUserDefaults.standardUserDefaults setObject:file forKey:@"model"];[self refresh];
 }]];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
 [self presentViewController:a animated:YES completion:nil];
}
- (void)confirmDelete {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Delete this chat?" message:@"This removes its saved messages." preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
 NSIndexSet *indexes=[self->_archive indexesOfObjectsPassingTest:^BOOL(id c,NSUInteger i,BOOL *stop){return [c[@"id"] isEqual:self->_chatID];}];
 NSMutableArray *updated=[self->_archive mutableCopy]; [updated removeObjectsAtIndexes:indexes]; NSError *e=nil;
 NSData *d=[NSJSONSerialization dataWithJSONObject:updated options:0 error:&e];
 if(!d || ![d writeToFile:[self historyPath] options:NSDataWritingAtomic error:&e]) {[self alert:e.localizedDescription ?: @"Could not delete chat."];return;}
 self->_archive=updated; self->_messages=[NSMutableArray new]; self->_chatID=NSUUID.UUID.UUIDString; [self refresh];
 }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)showChats {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Saved chats" message:_archive.count?nil:@"No saved chats yet." preferredStyle:UIAlertControllerStyleActionSheet];
 for(NSDictionary *c in [_archive reverseObjectEnumerator]) { NSString *title=[c[@"messages"] firstObject][@"content"] ?: @"Chat"; if(title.length>45) title=[title substringToIndex:45];
 [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self->_chatID=c[@"id"]; self->_messages=[c[@"messages"] mutableCopy]; [self refresh];}]]; }
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem; [self presentViewController:a animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
 [controller dismissViewControllerAnimated:YES completion:nil];
 NSURL *url=urls.firstObject; if(!url) return;
 if(![url.pathExtension.lowercaseString isEqual:@"gguf"]) {[self alert:@"Select the downloaded .gguf model file."]; return;}
 NextAIWorking=YES; _busy=YES; _send.enabled=NO; _status.text=@"Copying model… keep the app open.";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ @autoreleasepool {
 BOOL scoped=[url startAccessingSecurityScopedResource]; __block NSError *error=nil; __block NSString *relative=nil;
 NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil]; NSError *coordError=nil;
 [coordinator coordinateReadingItemAtURL:url options:0 error:&coordError byAccessor:^(NSURL *source){
 NSNumber *size=nil; [source getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
 if(error) return;
 if(size.unsignedLongLongValue>2200000000ULL) {error=[NSError errorWithDomain:@"NextAI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"For 0.3.0, choose a model smaller than 2.2 GB. Use the recommended Qwen Q4_K_M."}];return;}
 NSFileHandle *h=[NSFileHandle fileHandleForReadingFromURL:source error:&error]; if(!h)return; NSData *magic=[h readDataUpToLength:4 error:&error]; [h closeFile];
 if(error || ![magic isEqual:[@"GGUF" dataUsingEncoding:NSUTF8StringEncoding]]) {error=[NSError errorWithDomain:@"NextAI" code:2 userInfo:@{NSLocalizedDescriptionKey:@"This is not a valid GGUF file. Check that the download finished."}];return;}
 relative=[NSString stringWithFormat:@"Models/%@-%@",NSUUID.UUID.UUIDString,source.lastPathComponent];
 NSString *dir=[[self documents] stringByAppendingPathComponent:@"Models"]; [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]; if(error)return;
 NSURL *dest=[NSURL fileURLWithPath:[[self documents] stringByAppendingPathComponent:relative]];
 [NSFileManager.defaultManager copyItemAtURL:source toURL:dest error:&error];
 if(error) [NSFileManager.defaultManager removeItemAtURL:dest error:nil]; else [dest setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 }];
 if(scoped) [url stopAccessingSecurityScopedResource]; NSError *finalError=error ?: coordError;
 dispatch_async(dispatch_get_main_queue(), ^{NextAIWorking=NO;self->_busy=NO;self->_send.enabled=YES;
 if(!finalError && relative) {self->_model=relative;[NSUserDefaults.standardUserDefaults setObject:relative forKey:@"model"];} [self refresh]; if(finalError)[self alert:finalError.localizedDescription];
 });
 }});
}
- (void)send {
 if(_busy){_cancel=true;_status.text=@"Stopping…";return;}
 if(NextAIWorking){[self alert:@"Wait for image generation or model import to finish first."];return;}
 NSString *input=[_input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!input.length)return;
 if(!_model){[self alert:@"Import a model from Menu first."];return;}
 if(input.length>6000){[self alert:@"Please shorten the message for this first test."];return;}
 [_messages addObject:@{@"role":@"user",@"content":input}]; _input.text=@""; [self save];
 NSArray *history=[_messages copy]; [_messages addObject:@{@"role":@"assistant",@"content":@""}];
 NextAIWorking=YES;_busy=YES;_cancel=false;UIApplication.sharedApplication.idleTimerDisabled=YES;_input.enabled=NO;[_send setTitle:@"Stop" forState:UIControlStateNormal];[self refresh];_status.text=@"Loading model on device…";
 NSString *path=[[self documents] stringByAppendingPathComponent:_model];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ @autoreleasepool {
 NSString *failure=nil; BOOL limit=NO;
 try {
 static dispatch_once_t once;dispatch_once(&once, ^{llama_backend_init();});
 auto mp=llama_model_default_params();mp.n_gpu_layers=99;
 std::unique_ptr<llama_model,decltype(&llama_model_free)> model(llama_model_load_from_file(path.UTF8String,mp),llama_model_free);
 if(!model)throw std::runtime_error("Model could not load. Use the recommended Qwen2.5 1.5B Q4_K_M GGUF and check the download.");
 if(self->_cancel)throw std::runtime_error("Stopped.");
 auto cp=llama_context_default_params();cp.n_ctx=2048;cp.n_batch=128;cp.n_ubatch=128;cp.n_threads=4;cp.n_threads_batch=4;
 std::unique_ptr<llama_context,decltype(&llama_free)> ctx(llama_init_from_model(model.get(),cp),llama_free);
 if(!ctx)throw std::runtime_error("Not enough memory to create the AI context. Close other apps and try again.");
 std::vector<std::string> roles,contents;
 roles.push_back("system");contents.push_back("You are Next AI, a helpful offline assistant. Be clear and concise. Answer in the user's language.");
 for(NSDictionary *m in history){roles.emplace_back([m[@"role"] UTF8String]);contents.emplace_back([m[@"content"] UTF8String]);}
 std::vector<llama_chat_message> chat;for(size_t i=0;i<roles.size();i++)chat.push_back({roles[i].c_str(),contents[i].c_str()});
 const char *tmpl=llama_model_chat_template(model.get(),nullptr);if(!tmpl)throw std::runtime_error("Model has no chat template. Import the recommended Qwen Instruct model.");
 int n=llama_chat_apply_template(tmpl,chat.data(),chat.size(),true,nullptr,0);if(n<=0)throw std::runtime_error("This model's chat template is not supported by 0.3.0.");
 std::vector<char> prompt(n+1);llama_chat_apply_template(tmpl,chat.data(),chat.size(),true,prompt.data(),(int)prompt.size());
 const llama_vocab *vocab=llama_model_get_vocab(model.get());int needed=llama_tokenize(vocab,prompt.data(),n,nullptr,0,true,true);needed=needed<0?-needed:needed;
 if(needed<1 || needed>1664)throw std::runtime_error("Conversation exceeds the test model context. Start a New chat from Menu or shorten the message.");
 std::vector<llama_token> tokens(needed);int count=llama_tokenize(vocab,prompt.data(),n,tokens.data(),needed,true,true);if(count<1)throw std::runtime_error("Could not tokenize message.");
 dispatch_async(dispatch_get_main_queue(), ^{self->_status.text=@"Reading your message…";});
 for(int offset=0;offset<count && !self->_cancel;offset+=128){int batchCount=std::min(128,count-offset);if(llama_decode(ctx.get(),llama_batch_get_one(tokens.data()+offset,batchCount)))throw std::runtime_error("Model evaluation failed. Try a smaller model.");}
 std::unique_ptr<llama_sampler,decltype(&llama_sampler_free)> sampler(llama_sampler_chain_init(llama_sampler_chain_default_params()),llama_sampler_free);
 llama_sampler_chain_add(sampler.get(),llama_sampler_init_top_k(40));llama_sampler_chain_add(sampler.get(),llama_sampler_init_top_p(0.9f,1));llama_sampler_chain_add(sampler.get(),llama_sampler_init_temp(0.7f));llama_sampler_chain_add(sampler.get(),llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
 std::string result;int generated=0;CFAbsoluteTime lastUpdate=0;NSString *latestText=@"";
 for(;generated<384 && !self->_cancel;generated++){
 llama_token token=llama_sampler_sample(sampler.get(),ctx.get(),-1);if(llama_vocab_is_eog(vocab,token))break;
 std::vector<char> piece(256);int bytes=llama_token_to_piece(vocab,token,piece.data(),(int)piece.size(),0,false);if(bytes<0){piece.resize(-bytes);bytes=llama_token_to_piece(vocab,token,piece.data(),(int)piece.size(),0,false);}if(bytes>0)result.append(piece.data(),bytes);
 NSString *text=[[NSString alloc] initWithBytes:result.data() length:result.size() encoding:NSUTF8StringEncoding];
 if(text)latestText=text;
 if(text && (CFAbsoluteTimeGetCurrent()-lastUpdate>0.10)){lastUpdate=CFAbsoluteTimeGetCurrent();dispatch_async(dispatch_get_main_queue(), ^{self->_messages[self->_messages.count-1]=@{@"role":@"assistant",@"content":text};[self refresh];self->_status.text=@"Writing offline…";});}
 if(llama_decode(ctx.get(),llama_batch_get_one(&token,1)))throw std::runtime_error("Generation stopped because model evaluation failed.");
 }limit=generated==384;
 if(latestText.length)dispatch_async(dispatch_get_main_queue(), ^{self->_messages[self->_messages.count-1]=@{@"role":@"assistant",@"content":latestText};[self refresh];});
 }catch(const std::exception &e){failure=[NSString stringWithUTF8String:e.what()];}
 dispatch_async(dispatch_get_main_queue(), ^{
 NextAIWorking=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;self->_busy=NO;self->_input.enabled=YES;[self->_send setTitle:@"Send" forState:UIControlStateNormal];
 if(![self->_messages.lastObject[@"content"] length]) [self->_messages removeLastObject];
 [self refresh];[self save]; if(failure)[self alert:failure];else if(self->_cancel)self->_status.text=@"Stopped • chat saved";else if(limit)self->_status.text=@"Reply reached the 0.3.0 limit • chat saved";
 });
 }});
}
@end
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
 self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];UINavigationController *chat=[[UINavigationController alloc] initWithRootViewController:[ChatController new]];chat.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Chat" image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right"] tag:0];UINavigationController *photos=[[UINavigationController alloc] initWithRootViewController:[PhotoController new]];photos.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Photos" image:[UIImage systemImageNamed:@"photo"] tag:1];UITabBarController *tabs=[UITabBarController new];tabs.viewControllers=@[chat,photos];self.window.rootViewController=tabs;[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}


