#import <UIKit/UIKit.h>
#include "NextPhoto.h"
#include "stable-diffusion.h"
#include <memory>
#include <string>
#include <stdexcept>
#include <cstdio>
#include <cstdlib>
struct ProgressState { NextPhotoProgress callback; void *user; std::string error; };
static void progressBridge(int step,int total,float seconds,void *user) {
 auto *s=static_cast<ProgressState *>(user);if(s->callback)s->callback(step,total,s->user);
}
static void logBridge(sd_log_level_t level,const char *text,void *user) {
 if(level==SD_LOG_ERROR && text) static_cast<ProgressState *>(user)->error=text;
}
struct CallbackCleanup { ~CallbackCleanup(){sd_set_progress_callback(nullptr,nullptr);sd_set_log_callback(nullptr,nullptr);} };
struct ImagesCleanup { sd_image_t *images=nullptr; ~ImagesCleanup(){if(images){free(images[0].data);free(images);}} };
extern "C" __attribute__((visibility("default")))
int NextPhotoGenerate(const char *model,const char *prompt,const char *negative,int size,int steps,int turbo,int64_t seed,const char *destination,NextPhotoTiming *timing,NextPhotoProgress progress,void *user,char *error,int errorCapacity) {
 @autoreleasepool {
 try {
 if((size!=384 && size!=512) || (turbo ? (steps!=1 && steps!=2 && steps!=4) : (steps<12 || steps>24)))throw std::runtime_error("Unsupported image settings.");
 CFAbsoluteTime loadStart=CFAbsoluteTimeGetCurrent();if(timing)*timing={0,0};
 ProgressState state{progress,user,{}};CallbackCleanup cleanup;
 sd_set_log_callback(logBridge,&state);sd_set_progress_callback(progressBridge,&state);
 if(progress)progress(0,steps,user);
 std::unique_ptr<sd_ctx_t,decltype(&free_sd_ctx)> ctx(new_sd_ctx(model,"","","","","","","","","","",true,true,true,4,SD_TYPE_COUNT,STD_DEFAULT_RNG,turbo?NEXTAI_TURBO:DEFAULT,true,true,true,false),free_sd_ctx);
 if(!ctx)throw std::runtime_error(state.error.empty()?"Could not load the image model. Select the complete model matching the selected Standard or Turbo mode.":state.error);
 if(timing)timing->loadSeconds=CFAbsoluteTimeGetCurrent()-loadStart;
 CFAbsoluteTime renderStart=CFAbsoluteTimeGetCurrent();
 ImagesCleanup result;
 result.images=txt2img(ctx.get(),prompt,turbo?"":negative,-1,turbo?1.0f:7.0f,3.5f,size,size,turbo?EULER:EULER_A,steps,seed,1,nullptr,0.0f,0.0f,false,"",nullptr,0,0.0f,0.0f,0.0f);
 if(!result.images || !result.images[0].data)throw std::runtime_error(state.error.empty()?"No image was generated. Try 384 × 384 or restart the app to free memory.":state.error);
 if(timing)timing->renderSeconds=CFAbsoluteTimeGetCurrent()-renderStart;
 const sd_image_t &im=result.images[0];
 if(im.channel!=3 || im.width!=size || im.height!=size)throw std::runtime_error("Image engine returned an unexpected pixel format.");
 NSData *pixels=[NSData dataWithBytes:im.data length:(NSUInteger)im.width*im.height*3];
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 CGImageRef cg=CGImageCreate(im.width,im.height,8,24,im.width*3,space,kCGBitmapByteOrderDefault,provider,nullptr,false,kCGRenderingIntentDefault);
 CGColorSpaceRelease(space);CGDataProviderRelease(provider);
 if(!cg)throw std::runtime_error("Could not create image preview.");
 UIImage *image=[UIImage imageWithCGImage:cg];CGImageRelease(cg);
 NSData *png=UIImagePNGRepresentation(image);NSError *saveError=nil;
 if(!png || ![png writeToFile:[NSString stringWithUTF8String:destination] options:NSDataWritingAtomic error:&saveError])throw std::runtime_error(saveError?saveError.localizedDescription.UTF8String:"Could not save generated image.");
 return 0;
 }catch(const std::exception &e){if(error && errorCapacity>0)snprintf(error,errorCapacity,"%s",e.what());return 1;}
 }
}

