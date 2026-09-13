#import <UIKit/UIKit.h>
// Accessed only on the main queue: serialize chat, image generation and imports.
extern BOOL NextAIWorking;
@interface PhotoController : UIViewController <UIDocumentPickerDelegate>
@end
