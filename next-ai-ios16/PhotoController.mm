#import "PhotoController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Photos/Photos.h>
#include "photo-engine/NextPhoto.h"

@interface PhotoController ()
- (void)progress:(int)step total:(int)total;
@end
static void photoProgress(int step,int total,void *user) {
 PhotoController *controller=(__bridge PhotoController *)user;
 dispatch_async(dispatch_get_main_queue(), ^{[controller progress:step total:total];});
}
@implementation PhotoController {
 UITextView *_prompt;UITextField *_negative;UITextField *_seed;
 UILabel *_status;UIImageView *_preview;UIButton *_generate;UISegmentedControl *_size;UISegmentedControl *_steps;UISegmentedControl *_mode;
 UIProgressView *_progress;NSString *_model;NSString *_lastImage;BOOL _busy;BOOL _turbo;
}
- (NSString *)modelKey {return _turbo?@"turboModel":@"photoModel";}
- (NSString *)documents {return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;}
- (NSString *)imagesFolder {return [[self documents] stringByAppendingPathComponent:@"Generated Images"];}
- (void)alert:(NSString *)message {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Next AI Photos" message:message preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)viewDidLoad {
 [super viewDidLoad];self.title=@"Create a photo";self.view.backgroundColor=UIColor.systemBackgroundColor;
 _turbo=[NSUserDefaults.standardUserDefaults boolForKey:@"photoTurbo"];
 _model=[NSUserDefaults.standardUserDefaults stringForKey:[self modelKey]];
 if(_model && ![NSFileManager.defaultManager fileExistsAtPath:[[self documents] stringByAppendingPathComponent:_model]])_model=nil;
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
 _mode=[[UISegmentedControl alloc] initWithItems:@[@"Standard SD 1.5",@"Fast SD-Turbo"]];_mode.selectedSegmentIndex=_turbo?1:0;[_mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:_mode];
 _status=[UILabel new];_status.font=[UIFont systemFontOfSize:13];_status.numberOfLines=0;_status.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:_status];
 UILabel *label=[UILabel new];label.text=@"Describe your image";label.font=[UIFont boldSystemFontOfSize:17];[stack addArrangedSubview:label];
 _prompt=[UITextView new];_prompt.font=[UIFont systemFontOfSize:16];_prompt.backgroundColor=UIColor.secondarySystemBackgroundColor;_prompt.layer.cornerRadius=10;
 _prompt.text=[NSUserDefaults.standardUserDefaults stringForKey:@"photoPrompt"] ?: @"A realistic photograph of a golden retriever on a beach at sunset, soft natural light, detailed fur";
 [_prompt.heightAnchor constraintEqualToConstant:100].active=YES;[stack addArrangedSubview:_prompt];
 _negative=[UITextField new];_negative.borderStyle=UITextBorderStyleRoundedRect;_negative.placeholder=@"Avoid (optional)";_negative.text=@"blurry, distorted, low quality, watermark, text";[stack addArrangedSubview:_negative];
 _size=[[UISegmentedControl alloc] initWithItems:@[@"384 × 384",@"512 × 512"]];_size.selectedSegmentIndex=0;[stack addArrangedSubview:_size];
 _steps=[[UISegmentedControl alloc] initWithItems:_turbo?@[@"1 step",@"2 steps",@"4 steps"]:@[@"12 steps",@"20 steps",@"24 steps"]];_steps.selectedSegmentIndex=1;_negative.enabled=!_turbo;[stack addArrangedSubview:_steps];
 _seed=[UITextField new];_seed.borderStyle=UITextBorderStyleRoundedRect;_seed.placeholder=@"Seed: leave blank for random";_seed.keyboardType=UIKeyboardTypeNumberPad;[stack addArrangedSubview:_seed];
 _generate=[UIButton buttonWithType:UIButtonTypeSystem];[_generate setTitle:@"Generate image" forState:UIControlStateNormal];_generate.titleLabel.font=[UIFont boldSystemFontOfSize:18];[_generate.heightAnchor constraintEqualToConstant:44].active=YES;[_generate addTarget:self action:@selector(generate) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:_generate];
 _progress=[UIProgressView new];[stack addArrangedSubview:_progress];
 _preview=[UIImageView new];_preview.contentMode=UIViewContentModeScaleAspectFit;_preview.backgroundColor=UIColor.secondarySystemBackgroundColor;_preview.layer.cornerRadius=12;_preview.clipsToBounds=YES;[_preview.heightAnchor constraintEqualToAnchor:_preview.widthAnchor].active=YES;[stack addArrangedSubview:_preview];
 UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"Share / export image" forState:UIControlStateNormal];[share addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:share];
 UIButton *save=[UIButton buttonWithType:UIButtonTypeSystem];[save setTitle:@"Save to Photos" forState:UIControlStateNormal];[save addTarget:self action:@selector(saveToPhotos) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:save];
 UILabel *hint=[UILabel new];hint.text=@"Offline • Keep Next AI open while generating. The model is released after each image. Images are also saved in Files → Next AI → Generated Images.";hint.font=[UIFont systemFontOfSize:12];hint.numberOfLines=0;hint.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:hint];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Models / Gallery" style:UIBarButtonItemStylePlain target:self action:@selector(menu)];
 NSString *last=[NSUserDefaults.standardUserDefaults stringForKey:@"lastPhoto"];
 if(last){_lastImage=[[self documents] stringByAppendingPathComponent:last];_preview.image=[UIImage imageWithContentsOfFile:_lastImage];}
 [self updateStatus];
}
- (void)modeChanged {
 if(NextAIWorking){_mode.selectedSegmentIndex=_turbo?1:0;[self alert:@"Wait for the current operation to finish before switching modes."];return;}
 _turbo=_mode.selectedSegmentIndex==1;[NSUserDefaults.standardUserDefaults setBool:_turbo forKey:@"photoTurbo"];
 _model=[NSUserDefaults.standardUserDefaults stringForKey:[self modelKey]];
 [_steps removeAllSegments];NSArray *titles=_turbo?@[@"1 step",@"2 steps",@"4 steps"]:@[@"12 steps",@"20 steps",@"24 steps"];
 for(NSUInteger i=0;i<titles.count;i++)[_steps insertSegmentWithTitle:titles[i] atIndex:i animated:NO];_steps.selectedSegmentIndex=1;
 _negative.enabled=!_turbo;_negative.alpha=_turbo?0.4:1.0;[self updateStatus];
}
- (void)updateStatus {_status.text=_model ? [@"Photo model: " stringByAppendingString:_model.lastPathComponent] : (_turbo?@"Turbo mode: select SD-Turbo Q4_0. Uses 1–4 steps; negative prompts are disabled.":@"Standard mode: select SD 1.5 Q4_0 from Models / Gallery.");}
- (void)progress:(int)step total:(int)total {
 _progress.progress=total>0?(float)step/total:0;
 _status.text=step==0?@"Loading image model… this may take a while.":[NSString stringWithFormat:@"Generating step %d of %d%@",step,total,step==total?@" • decoding image…":@""];
}
- (void)menu {
 if(NextAIWorking){[self alert:@"Wait for the current chat, import or image generation to finish."];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Photos" message:(_turbo?@"Select the complete SD-Turbo Q4_0 model for Fast mode.":@"Select the complete SD 1.5 Q4_0 model for Standard mode.") preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"Import image model from Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Use image model from Next AI folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self chooseModel];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Generated image gallery" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self gallery];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (BOOL)validate:(NSURL *)url error:(NSError **)error {
 NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:error];if(error && *error)return NO;
 if(![url.pathExtension.lowercaseString isEqual:@"gguf"] || size.unsignedLongLongValue>2200000000ULL || size.unsignedLongLongValue<1000000ULL){if(error)*error=[NSError errorWithDomain:@"NextAI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Choose the complete SD 1.5 Q4_0 or SD-Turbo Q4_0 GGUF matching your mode (up to 2.2 GB)."}];return NO;}
 NSFileHandle *h=[NSFileHandle fileHandleForReadingFromURL:url error:error];if(!h)return NO;NSData *magic=[h readDataUpToLength:4 error:error];[h closeFile];
 if(![magic isEqual:[@"GGUF" dataUsingEncoding:NSUTF8StringEncoding]]){if(error)*error=[NSError errorWithDomain:@"NextAI" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid model file. Finish the download before importing."}];return NO;}return YES;
}
- (void)chooseModel {
 NSArray *files=[NSFileManager.defaultManager subpathsOfDirectoryAtPath:[self documents] error:nil];
 UIAlertController *a=[UIAlertController alertControllerWithTitle:(_turbo?@"Select SD-Turbo image model":@"Select SD 1.5 image model") message:@"If empty, copy the image GGUF into Files → On My iPhone → Next AI. Do not choose Qwen or another chat model." preferredStyle:UIAlertControllerStyleActionSheet];
 for(NSString *file in files) if([file.pathExtension.lowercaseString isEqual:@"gguf"]) [a addAction:[UIAlertAction actionWithTitle:file.lastPathComponent style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSError *error=nil;if(![self validate:[NSURL fileURLWithPath:[[self documents] stringByAppendingPathComponent:file]] error:&error]){[self alert:error.localizedDescription];return;}self->_model=file;[NSUserDefaults.standardUserDefaults setObject:file forKey:[self modelKey]];[self updateStatus];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
 [controller dismissViewControllerAnimated:YES completion:nil];NSURL *url=urls.firstObject;if(!url)return;
 if(NextAIWorking){[self alert:@"Please wait for the current operation to finish."];return;}
 NextAIWorking=YES;_busy=YES;_generate.enabled=NO;_status.text=@"Importing image model… keep the app open.";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
 BOOL access=[url startAccessingSecurityScopedResource];__block NSError *error=nil;__block NSString *relative=nil;NSError *coordError=nil;
 NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
 [coordinator coordinateReadingItemAtURL:url options:0 error:&coordError byAccessor:^(NSURL *source){
 if(![self validate:source error:&error])return;
 NSString *folder=[[self documents] stringByAppendingPathComponent:@"PhotoModels"];
 [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];if(error)return;
 relative=[NSString stringWithFormat:@"PhotoModels/%@-%@",NSUUID.UUID.UUIDString,source.lastPathComponent];
 NSURL *dest=[NSURL fileURLWithPath:[[self documents] stringByAppendingPathComponent:relative]];
 [NSFileManager.defaultManager copyItemAtURL:source toURL:dest error:&error];
 if(error)[NSFileManager.defaultManager removeItemAtURL:dest error:nil];else [dest setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 }];if(access)[url stopAccessingSecurityScopedResource];NSError *finalError=error ?: coordError;
 dispatch_async(dispatch_get_main_queue(),^{NextAIWorking=NO;self->_busy=NO;self->_generate.enabled=YES;
 if(!finalError && relative){self->_model=relative;[NSUserDefaults.standardUserDefaults setObject:relative forKey:[self modelKey]];}[self updateStatus];if(finalError)[self alert:finalError.localizedDescription];});
 }});
}
- (void)generate {
 if(NextAIWorking){[self alert:@"Wait for the current chat, import or image to finish."];return;}
 if(!_model){[self alert:(_turbo?@"Choose the SD-Turbo model from Models / Gallery first.":@"Choose the SD 1.5 model from Models / Gallery first.")];return;}
 NSString *prompt=[_prompt.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!prompt.length || prompt.length>2000){[self alert:@"Enter an image description of 1–2,000 characters."];return;}
 NSString *modelPath=[[self documents] stringByAppendingPathComponent:_model];NSError *error=nil;
 if(![self validate:[NSURL fileURLWithPath:modelPath] error:&error]){[self alert:error.localizedDescription];return;}
 NSString *chatModel=[NSUserDefaults.standardUserDefaults stringForKey:@"model"];
 if([_model isEqual:chatModel]){[self alert:@"This is your chat model. Select the separate SD 1.5 photo model."];return;}
 BOOL turbo=_turbo;
 NSString *lower=_model.lastPathComponent.lowercaseString;
 if((turbo && ![lower containsString:@"turbo"]) || (!turbo && [lower containsString:@"turbo"])) {[self alert:@"The model name does not match this mode. Use Standard for SD 1.5 or Fast for SD-Turbo. Keep the original model filename."];return;}
 int size=_size.selectedSegmentIndex==0?384:512;int steps=turbo?(_steps.selectedSegmentIndex==0?1:(_steps.selectedSegmentIndex==1?2:4)):(_steps.selectedSegmentIndex==0?12:(_steps.selectedSegmentIndex==1?20:24));
 int64_t seed=arc4random_uniform(2147483647);
 if(_seed.text.length){NSScanner *scanner=[NSScanner scannerWithString:_seed.text];long long parsed=0;if(![scanner scanLongLong:&parsed] || !scanner.isAtEnd || parsed<0 || parsed>2147483646){[self alert:@"Use a seed from 0 to 2147483646, or leave it blank."];return;}seed=parsed;}
 NSString *negative=turbo?@"":(_negative.text ?: @"");
 [NSFileManager.defaultManager createDirectoryAtPath:[self imagesFolder] withIntermediateDirectories:YES attributes:nil error:&error];if(error){[self alert:error.localizedDescription];return;}
 NSString *filename=[NSString stringWithFormat:@"NextAI-%@.png",NSUUID.UUID.UUIDString];NSString *destination=[[self imagesFolder] stringByAppendingPathComponent:filename];
 NSMutableDictionary *metadata=[@{@"prompt":prompt,@"negative_prompt":negative,@"seed":@(seed),@"width":@(size),@"height":@(size),@"steps":@(steps),@"model":_model.lastPathComponent,@"engine":turbo?@"SD-Turbo / Euler / trailing":@"SD 1.5 / Euler A",@"cfg":turbo?@1.0:@7.0} mutableCopy];
 [NSUserDefaults.standardUserDefaults setObject:prompt forKey:@"photoPrompt"];
 [self.view endEditing:YES];NextAIWorking=YES;_busy=YES;_generate.enabled=NO;UIApplication.sharedApplication.idleTimerDisabled=YES;_progress.progress=0;_status.text=@"Loading image model…";
 NSDate *start=[NSDate date];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
 char message[2048]={0};NextPhotoTiming timing={0,0};int status=NextPhotoGenerate(modelPath.UTF8String,prompt.UTF8String,negative.UTF8String,size,steps,turbo,seed,destination.UTF8String,&timing,photoProgress,(__bridge void *)self,message,sizeof(message));
 NSString *failure=status?[NSString stringWithUTF8String:message]:nil;
 metadata[@"load_seconds"]=@(timing.loadSeconds);metadata[@"render_seconds"]=@(timing.renderSeconds);
 NSError *metadataError=nil;if(!status){NSData *json=[NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:&metadataError];if(json)[json writeToFile:[destination.stringByDeletingPathExtension stringByAppendingPathExtension:@"json"] options:NSDataWritingAtomic error:&metadataError];}
 dispatch_async(dispatch_get_main_queue(),^{NextAIWorking=NO;self->_busy=NO;self->_generate.enabled=YES;UIApplication.sharedApplication.idleTimerDisabled=NO;
 if(status){[self updateStatus];[self alert:failure ?: @"Image generation failed."];return;}
 self->_lastImage=destination;self->_preview.image=[UIImage imageWithContentsOfFile:destination];self->_progress.progress=1;
 [NSUserDefaults.standardUserDefaults setObject:[@"Generated Images" stringByAppendingPathComponent:filename] forKey:@"lastPhoto"];
 self->_status.text=[NSString stringWithFormat:@"Saved • %d × %d • %.0fs total (load %.0fs / render %.0fs) • seed %lld%@",size,size,-start.timeIntervalSinceNow,timing.loadSeconds,timing.renderSeconds,(long long)seed,metadataError?@" • prompt metadata could not be saved":@""];
 });
 }});
}
- (void)gallery {
 NSArray *files=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:[self imagesFolder] error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
 NSDictionary *aa=[NSFileManager.defaultManager attributesOfItemAtPath:[[self imagesFolder] stringByAppendingPathComponent:a] error:nil];NSDictionary *bb=[NSFileManager.defaultManager attributesOfItemAtPath:[[self imagesFolder] stringByAppendingPathComponent:b] error:nil];return [bb[NSFileModificationDate] compare:aa[NSFileModificationDate]];
 }];
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Recent images" message:@"All generated images are also available in Files → Next AI → Generated Images." preferredStyle:UIAlertControllerStyleActionSheet];
 int count=0;for(NSString *file in files){if(![file.pathExtension isEqual:@"png"])continue;if(count++>=20)break;
 NSString *path=[[self imagesFolder] stringByAppendingPathComponent:file];NSDictionary *meta=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[path.stringByDeletingPathExtension stringByAppendingPathExtension:@"json"]] ?: [NSData data] options:0 error:nil];NSString *title=meta[@"prompt"] ?: file;if(title.length>48)title=[title substringToIndex:48];
 [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self->_lastImage=path;self->_preview.image=[UIImage imageWithContentsOfFile:path];if(meta[@"prompt"])self->_prompt.text=meta[@"prompt"];if(meta[@"seed"])self->_seed.text=[meta[@"seed"] stringValue];self->_status.text=@"Saved image opened";}]];}
 [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)share {
 if(!_lastImage || !_preview.image){[self alert:@"Generate an image or open one from the gallery first."];return;}
 UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:_lastImage]] applicationActivities:nil];a.popoverPresentationController.sourceView=_preview;a.popoverPresentationController.sourceRect=_preview.bounds;[self presentViewController:a animated:YES completion:nil];
}
- (void)saveToPhotos {
 if(!_lastImage || !_preview.image){[self alert:@"Generate an image or open one from the gallery first."];return;}
 NSURL *url=[NSURL fileURLWithPath:_lastImage];
 [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){
 if(status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited){dispatch_async(dispatch_get_main_queue(),^{[self alert:@"Photos permission was not granted. You can still export through Share or find the image in Files."];});return;}
 [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];} completionHandler:^(BOOL success,NSError *error){dispatch_async(dispatch_get_main_queue(),^{[self alert:success?@"Image saved to Photos.":error.localizedDescription];});}];
 }];
}
@end

