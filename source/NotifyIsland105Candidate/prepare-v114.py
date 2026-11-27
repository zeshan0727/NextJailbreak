#!/usr/bin/env python3
"""1.0.14: independent bitmap draft rendering and compact text scaling."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.14 missing anchor: "+a[:140])
    s=s.replace(a,b,1)

# Preserve the exact UITextField/keyboard and original-request send path that
# device testing established as working. Draw the field's *own* buffer using
# an opaque bitmap in a sibling overlay. Do not depend on textField rendering,
# label text drawing, or EditingChanged delivery alone.
rep('@property(nonatomic,strong) UILabel *liveDraftLabel;',r'''@property(nonatomic,strong) UIImageView *draftSurface;
@property(nonatomic,strong) NSTimer *draftTimer;
@property(nonatomic,copy) NSString *lastDrawnDraft;
@property(nonatomic) CGSize lastDrawnSize;
@property(nonatomic) NSInteger lastDrawnCaret;
@property(nonatomic) BOOL lastDrawnFocus;''')
rep('- (void)updateLiveDraft;\n@end',r'''- (void)updateLiveDraft;
- (void)startDraftRendering;
- (void)stopDraftRendering;
@end''')
a=s.index('    self.liveDraftLabel=[UILabel new];')
b=s.index('    self.field.returnKeyType=',a)
s=s[:a]+r'''    self.draftSurface=[UIImageView new];
    self.draftSurface.translatesAutoresizingMaskIntoConstraints=NO;
    self.draftSurface.backgroundColor=[UIColor colorWithWhite:.19 alpha:1.0];
    self.draftSurface.contentMode=UIViewContentModeScaleToFill;
    self.draftSurface.userInteractionEnabled=NO;
    self.draftSurface.isAccessibilityElement=NO;
    self.draftSurface.accessibilityElementsHidden=YES;
    self.draftSurface.clipsToBounds=YES;
    self.draftSurface.layer.zPosition=100;
'''+s[b:]
rep('    UIStackView *input=[[UIStackView alloc] initWithArrangedSubviews:@[self.field,self.sendButton]];',r'''    UIView *fieldHost=[UIView new];
    fieldHost.backgroundColor=[UIColor colorWithWhite:.19 alpha:1.0];
    fieldHost.layer.cornerRadius=14;
    fieldHost.layer.cornerCurve=kCACornerCurveContinuous;
    fieldHost.clipsToBounds=YES;
    [fieldHost setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [fieldHost setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.field.translatesAutoresizingMaskIntoConstraints=NO;
    [fieldHost addSubview:self.field];
    [fieldHost addSubview:self.draftSurface];
    [NSLayoutConstraint activateConstraints:@[
        [self.field.leadingAnchor constraintEqualToAnchor:fieldHost.leadingAnchor],
        [self.field.trailingAnchor constraintEqualToAnchor:fieldHost.trailingAnchor],
        [self.field.topAnchor constraintEqualToAnchor:fieldHost.topAnchor],
        [self.field.bottomAnchor constraintEqualToAnchor:fieldHost.bottomAnchor],
        [self.draftSurface.leadingAnchor constraintEqualToAnchor:fieldHost.leadingAnchor constant:10],
        [self.draftSurface.trailingAnchor constraintEqualToAnchor:fieldHost.trailingAnchor constant:-8],
        [self.draftSurface.topAnchor constraintEqualToAnchor:fieldHost.topAnchor constant:2],
        [self.draftSurface.bottomAnchor constraintEqualToAnchor:fieldHost.bottomAnchor constant:-2]
    ]];
    UIStackView *input=[[UIStackView alloc] initWithArrangedSubviews:@[fieldHost,self.sendButton]];''')
rep('UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.contextLabel,self.liveDraftLabel,input]];', 'UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.contextLabel,input]];')
a=s.index('- (void)updateLiveDraft {')
b=s.index('- (void)focusField {',a)
s=s[:a]+r'''- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateLiveDraft];
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
    self.lastDrawnSize=CGSizeZero;
    self.draftSurface.image=nil;
}
- (void)dealloc {
    [self.draftTimer invalidate];
}
- (void)updateLiveDraft {
    if (!self.view.window || self.view.window.hidden || NANIsUILocked()) return;
    CGSize size=self.draftSurface.bounds.size;
    if (size.width<8 || size.height<8) return;
    NSString *draft=self.field.text ?: @"";
    BOOL focused=self.field.isFirstResponder;
    NSInteger caret=(NSInteger)draft.length;
    UITextRange *selected=self.field.selectedTextRange;
    if (selected) {
        NSInteger offset=[self.field offsetFromPosition:self.field.beginningOfDocument toPosition:selected.end];
        if (offset>=0 && offset<=(NSInteger)draft.length) caret=offset;
    }
    // Skip unchanged frames. The timer only reads this user-created composer,
    // only while open. No global keyboard hook, storage, network or logging.
    if (self.draftSurface.image && [self.lastDrawnDraft isEqualToString:draft] &&
        CGSizeEqualToSize(self.lastDrawnSize,size) && self.lastDrawnCaret==caret &&
        self.lastDrawnFocus==focused) return;
    self.lastDrawnDraft=[draft copy];
    self.lastDrawnSize=size; self.lastDrawnCaret=caret; self.lastDrawnFocus=focused;
    UIFont *font=[UIFont systemFontOfSize:16];
    NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:UIColor.whiteColor};
    NSDictionary *placeholderAttrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:[UIColor colorWithWhite:.65 alpha:1.0]};
    NSString *display=draft.length?draft:@"Type your reply";
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.opaque=YES;
    format.scale=self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    self.draftSurface.image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:.19 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0,0,size.width,size.height));
        CGContextRef cg=context.CGContext;
        CGContextSaveGState(cg);
        CGContextClipToRect(cg,CGRectMake(0,0,size.width,size.height));
        CGFloat y=floor((size.height-font.lineHeight)*.5);
        CGFloat prefixWidth=0;
        if (draft.length) {
            NSUInteger safeCaret=(NSUInteger)MIN(MAX(0,caret),(NSInteger)draft.length);
            if (safeCaret>0 && safeCaret<draft.length) {
                NSRange composed=[draft rangeOfComposedCharacterSequenceAtIndex:safeCaret];
                if (composed.location<safeCaret) safeCaret=composed.location;
            }
            prefixWidth=[[draft substringToIndex:safeCaret] sizeWithAttributes:attrs].width;
        }
        CGFloat width=[display sizeWithAttributes:draft.length?attrs:placeholderAttrs].width;
        CGFloat offset=draft.length?MIN(MAX(0,prefixWidth-size.width+5),MAX(0,width-size.width+5)):0;
        [display drawAtPoint:CGPointMake(0-offset,y) withAttributes:draft.length?attrs:placeholderAttrs];
        if (focused) {
            [[UIColor colorWithRed:.36 green:.70 blue:1 alpha:1] setFill];
            CGFloat cursor=MIN(MAX(0,prefixWidth-offset),MAX(0,size.width-2));
            UIRectFill(CGRectMake(cursor,y+1,1.5,MAX(1,font.lineHeight-2)));
        }
        CGContextRestoreGState(cg);
    }];
    [self.draftSurface.superview bringSubviewToFront:self.draftSurface];
}
'''+s[b:]
rep('    [window makeKeyAndVisible];\n    [host.view setNeedsLayout]; [host.view layoutIfNeeded];',r'''    [window makeKeyAndVisible];
    [host.view setNeedsLayout]; [host.view layoutIfNeeded];
    [host startDraftRendering];''')
rep('    self.replyHost.field.text=@"";\n    self.replyHost.liveDraftLabel.text=@"";\n    self.replyHost.liveDraftLabel.hidden=YES;',r'''    [self.replyHost stopDraftRendering];
    self.replyHost.field.text=@"";''')
# Compact-only setting is independent; existing global value remains the
# expanded setting and acts as migration fallback for compact installations.
rep('    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);',r'''    CGFloat expandedScale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);
    CGFloat scale = NANExpanded ? expandedScale : NANFloat(@"NotificationIslandCompactTextScale", expandedScale, 0.75, 1.50);''')
rep('    CGFloat iconHeaderY = NANExpanded ? 12.0 : 9.0;\n    CGFloat iconY = iconHeaderY + (18.0 - icon) * .5;',r'''    CGFloat compactHeaderHeight=MAX(18.0,ceil(13.0*scale*1.22));
    CGFloat iconHeaderY = NANExpanded ? 12.0 : 9.0;
    CGFloat iconY = iconHeaderY + ((NANExpanded?18.0:compactHeaderHeight) - icon) * .5;''')
rep('    CGFloat headerHeight = 18.0;', '    CGFloat headerHeight = NANExpanded ? 18.0 : compactHeaderHeight;')
rep('        self.bodyLabel.frame = CGRectMake(textX, 30, MAX(40, self.bounds.size.width - textX - right), contentHeight - 34);',r'''        CGFloat bodyY=MAX(30.0,headerY+headerHeight+2.0);
        self.bodyLabel.frame = CGRectMake(textX, bodyY, MAX(0, self.bounds.size.width - textX - right), MAX(0,contentHeight-bodyY-4.0));''')
rep('1.0.13 Reply Visibility loaded','1.0.14 Live Draft loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.14 Live Draft.")
