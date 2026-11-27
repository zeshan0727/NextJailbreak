#!/usr/bin/env python3
"""1.0.16: single visible reply composer with explicit geometry and input callbacks."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.16 missing anchor: "+a[:140])
    s=s.replace(a,b,1)

# Observe only the composer-owned input, not any other keyboard or app.
rep('@interface NANReplyHostController : UIViewController',r'''@interface NANReplyInputField : UITextField
@property(nonatomic,copy) void (^draftChanged)(void);
@end
@implementation NANReplyInputField
- (void)insertText:(NSString *)text {
    [super insertText:text];
    if (self.draftChanged) self.draftChanged();
}
- (void)deleteBackward {
    [super deleteBackward];
    if (self.draftChanged) self.draftChanged();
}
- (void)setMarkedText:(NSString *)text selectedRange:(NSRange)range {
    [super setMarkedText:text selectedRange:range];
    if (self.draftChanged) self.draftChanged();
}
- (void)unmarkText {
    [super unmarkText];
    if (self.draftChanged) self.draftChanged();
}
- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    [super replaceRange:range withText:text];
    if (self.draftChanged) self.draftChanged();
}
@end

@interface NANReplyHostController : UIViewController''')
rep('@property(nonatomic,strong) UIImageView *draftSurface;',r'''@property(nonatomic,strong) UIView *replyPanel;
@property(nonatomic,strong) UILabel *draftPreview;
@property(nonatomic,strong) UILabel *draftCount;''')
rep('@property(nonatomic) CGSize lastDrawnSize;\n@property(nonatomic) NSInteger lastDrawnCaret;\n@property(nonatomic) BOOL lastDrawnFocus;','')
a=s.index('- (void)loadView {',s.index('@implementation NANReplyHostController'))
b=s.index('- (void)focusField {',a)
s=s[:a]+r'''- (void)loadView {
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIView *root=[UIView new];
    root.backgroundColor=[UIColor colorWithWhite:0 alpha:.20];
    self.view=root;
    self.replyPanel=[UIView new];
    self.replyPanel.backgroundColor=[UIColor colorWithWhite:.09 alpha:1];
    self.replyPanel.layer.cornerRadius=26;
    self.replyPanel.layer.cornerCurve=kCACornerCurveContinuous;
    self.replyPanel.layer.borderWidth=1.0/UIScreen.mainScreen.scale;
    self.replyPanel.layer.borderColor=[UIColor colorWithWhite:.30 alpha:1].CGColor;
    self.replyPanel.clipsToBounds=YES;
    [root addSubview:self.replyPanel];
    self.heading=[UILabel new];
    self.heading.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.heading.textColor=UIColor.whiteColor;
    self.heading.lineBreakMode=NSLineBreakByTruncatingTail;
    self.contextLabel=[UILabel new];
    self.contextLabel.font=[UIFont systemFontOfSize:13];
    self.contextLabel.textColor=[UIColor colorWithWhite:.72 alpha:1];
    self.contextLabel.numberOfLines=1;
    self.draftPreview=[UILabel new];
    self.draftPreview.font=[UIFont systemFontOfSize:16];
    self.draftPreview.textColor=UIColor.whiteColor;
    self.draftPreview.numberOfLines=2;
    self.draftPreview.lineBreakMode=NSLineBreakByTruncatingHead;
    self.draftPreview.accessibilityLabel=@"Live reply preview";
    self.draftCount=[UILabel new];
    self.draftCount.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.draftCount.textColor=[UIColor colorWithWhite:.65 alpha:1];
    self.draftCount.textAlignment=NSTextAlignmentRight;
    NANReplyInputField *field=[NANReplyInputField new];
    self.field=field;
    field.font=[UIFont systemFontOfSize:16];
    field.textColor=UIColor.whiteColor;
    field.tintColor=UIColor.systemBlueColor;
    field.backgroundColor=[UIColor colorWithWhite:.19 alpha:1];
    field.borderStyle=UITextBorderStyleNone;
    field.layer.cornerRadius=14;
    field.layer.cornerCurve=kCACornerCurveContinuous;
    field.clipsToBounds=YES;
    field.defaultTextAttributes=@{NSFontAttributeName:field.font,NSForegroundColorAttributeName:UIColor.whiteColor};
    field.attributedPlaceholder=[[NSAttributedString alloc] initWithString:@"Type your reply" attributes:@{NSFontAttributeName:field.font,NSForegroundColorAttributeName:[UIColor colorWithWhite:.60 alpha:1]}];
    field.leftView=[[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    field.leftViewMode=UITextFieldViewModeAlways;
    field.returnKeyType=UIReturnKeySend;
    field.keyboardAppearance=UIKeyboardAppearanceDark;
    field.accessibilityLabel=@"Notification reply";
    field.enablesReturnKeyAutomatically=YES;
    __weak typeof(self) weakSelf=self;
    field.draftChanged=^{
        [weakSelf updateLiveDraft];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf updateLiveDraft]; });
    };
    [field addTarget:self action:@selector(updateLiveDraft) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(focusField) forControlEvents:UIControlEventTouchDown];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputDidChange:) name:UITextFieldTextDidChangeNotification object:field];
    self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.sendButton.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.sendButton.backgroundColor=UIColor.systemBlueColor;
    self.sendButton.layer.cornerRadius=17;
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.cancelButton.tintColor=[UIColor colorWithWhite:.65 alpha:1];
    self.cancelButton.accessibilityLabel=@"Cancel reply";
    for (UIView *v in @[self.heading,self.contextLabel,self.draftPreview,self.draftCount,field,self.sendButton,self.cancelButton])
        [self.replyPanel addSubview:v];
    self.draftPreview.text=@"Your reply will appear here";
    self.draftCount.text=@"0 characters";
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds=self.view.bounds;
    UIEdgeInsets safe=self.view.safeAreaInsets;
    CGFloat width=MAX(1,CGRectGetWidth(bounds)-safe.left-safe.right-24);
    CGFloat top=MAX(safe.top,CGRectGetHeight(bounds)>CGRectGetWidth(bounds)?62.0:8.0)+8.0;
    CGFloat bottom=CGRectGetMaxY(self.view.keyboardLayoutGuide.layoutFrame)-CGRectGetHeight(self.view.keyboardLayoutGuide.layoutFrame);
    if (bottom<=top+120) bottom=CGRectGetHeight(bounds)-safe.bottom;
    CGFloat height=MIN(158.0,MAX(120.0,bottom-top-8.0));
    self.replyPanel.frame=CGRectIntegral(CGRectMake(safe.left+12,top,width,height));
    CGFloat inner=MAX(1,width-28);
    CGFloat inputY=height-56;
    self.heading.frame=CGRectMake(14,8,MAX(1,inner-40),22);
    self.cancelButton.frame=CGRectMake(width-48,3,44,36);
    self.contextLabel.frame=CGRectMake(14,32,inner,18);
    self.draftCount.frame=CGRectMake(14,51,inner,12);
    self.draftPreview.frame=CGRectMake(14,65,inner,MAX(1,inputY-69));
    self.field.frame=CGRectMake(14,inputY,MAX(1,inner-74),44);
    self.sendButton.frame=CGRectMake(width-80,inputY,66,44);
    [self updateLiveDraft];
}
- (void)inputDidChange:(NSNotification *)note {
    if (note.object==self.field) [self updateLiveDraft];
}
- (void)startDraftRendering {
    [self stopDraftRendering];
    __weak typeof(self) weakSelf=self;
    self.draftTimer=[NSTimer timerWithTimeInterval:.10 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf updateLiveDraft];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.draftTimer forMode:NSRunLoopCommonModes];
    [self updateLiveDraft];
}
- (void)stopDraftRendering {
    [self.draftTimer invalidate];
    self.draftTimer=nil;
    self.lastDrawnDraft=nil;
    self.draftPreview.text=nil;
    self.draftCount.text=nil;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.draftTimer invalidate];
}
- (void)updateLiveDraft {
    if (!self.view.window || self.view.window.hidden) return;
    if (NANIsUILocked()) {
        self.draftPreview.text=nil; self.draftCount.text=nil; self.lastDrawnDraft=nil;
        return;
    }
    NSString *draft=self.field.text ?: @"";
    // UIKit's document range can expose the latest composition before the
    // text property's committed value. Preview only; Send uses original buffer.
    UITextPosition *start=self.field.beginningOfDocument;
    UITextPosition *end=self.field.endOfDocument;
    if (start && end) {
        UITextRange *range=[self.field textRangeFromPosition:start toPosition:end];
        NSString *document=range?[self.field textInRange:range]:nil;
        if (document) draft=document;
    }
    if ([self.lastDrawnDraft isEqualToString:draft]) return;
    self.lastDrawnDraft=[draft copy];
    self.draftPreview.text=draft.length?draft:@"Your reply will appear here";
    self.draftPreview.textColor=draft.length?UIColor.whiteColor:[UIColor colorWithWhite:.64 alpha:1];
    self.draftCount.text=[NSString stringWithFormat:@"%lu characters",(unsigned long)draft.length];
    [self.draftPreview setNeedsDisplay];
    [self.draftCount setNeedsDisplay];
}
'''+s[b:]
# Only the dedicated host is visible during a reply. Do not globally hide
# or move Apple's aperture window, and restore our card on cancel/send.
rep('    [window makeKeyAndVisible];\n    [host.view setNeedsLayout]; [host.view layoutIfNeeded];',r'''    [window makeKeyAndVisible];
    self.hidden=YES;
    [host.view setNeedsLayout]; [host.view layoutIfNeeded];''')
rep('    self.replyHost=nil; self.replyWindow=nil; self.replyPreviousKeyWindow=nil;',r'''    self.replyHost=nil; self.replyWindow=nil; self.replyPreviousKeyWindow=nil;
    self.hidden=NO;''')
rep('    self.replyField.hidden=!replying; self.replySend.hidden=!replying; self.replyCancel.hidden=!replying;',r'''    self.replyField.hidden=YES; self.replySend.hidden=YES; self.replyCancel.hidden=YES;''')
# Keep the native action dispatch unchanged. Explicitly retain lock checks.
rep('1.0.15 Content Text loaded','1.0.16 Composer Studio loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.16 Composer Studio.")
