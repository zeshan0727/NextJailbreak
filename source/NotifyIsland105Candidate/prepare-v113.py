#!/usr/bin/env python3
"""1.0.13: align icon to app-name header; make the real reply draft visible."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.13 missing anchor: "+a[:140])
    s=s.replace(a,b,1)

# Use a single header center line for icon, application name and timestamp.
# This occurs before the shared dock offset, so all shapes stay aligned.
rep('    CGFloat icon = NANExpanded ? 38 : 34;\n    self.iconView.frame = CGRectMake(pad, (contentHeight - icon) / 2.0, icon, icon);',r'''    CGFloat icon = NANExpanded ? 26.0 : 24.0;
    CGFloat iconHeaderY = NANExpanded ? 12.0 : 9.0;
    CGFloat iconY = iconHeaderY + (18.0 - icon) * .5;
    self.iconView.frame = CGRectIntegral(CGRectMake(pad, iconY, icon, icon));
    self.iconView.layer.cornerRadius = icon * .24;''')

# UIKit's native keyboard and submitted text buffer already work. Do not
# alter the request or dispatcher. Use an explicitly contrasting local palette
# and an independent live preview of the actual field's buffer, so text is
# readable even when SpringBoard's private text rendering is affected.
rep('@property(nonatomic,strong) UILabel *contextLabel;\n- (void)focusField;',r'''@property(nonatomic,strong) UILabel *contextLabel;
@property(nonatomic,strong) UILabel *liveDraftLabel;
- (void)focusField;
- (void)updateLiveDraft;''')
rep('    UIView *root=[UIView new];\n    root.backgroundColor=[UIColor colorWithWhite:0 alpha:.18];',r'''    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIView *root=[UIView new];
    root.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    root.backgroundColor=[UIColor colorWithWhite:0 alpha:.18];''')
rep('    panel.backgroundColor=UIColor.secondarySystemBackgroundColor;', '    panel.backgroundColor=[UIColor colorWithWhite:.095 alpha:1.0];')
rep('    self.heading.textColor=UIColor.labelColor;','    self.heading.textColor=UIColor.whiteColor;')
rep('    self.contextLabel.textColor=UIColor.secondaryLabelColor;','    self.contextLabel.textColor=[UIColor colorWithWhite:.74 alpha:1.0];')
rep('    self.field.font=[UIFont systemFontOfSize:16];\n    self.field.borderStyle=UITextBorderStyleRoundedRect;\n    self.field.backgroundColor=UIColor.tertiarySystemBackgroundColor;\n    self.field.textColor=UIColor.labelColor;\n    self.field.placeholder=@"Type your reply";',r'''    self.field.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIFont *inputFont=[UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.field.font=inputFont;
    self.field.borderStyle=UITextBorderStyleNone;
    self.field.backgroundColor=[UIColor colorWithWhite:.19 alpha:1.0];
    self.field.textColor=UIColor.whiteColor;
    self.field.tintColor=[UIColor colorWithRed:.36 green:.70 blue:1 alpha:1];
    self.field.defaultTextAttributes=@{NSFontAttributeName:inputFont,NSForegroundColorAttributeName:UIColor.whiteColor};
    self.field.attributedPlaceholder=[[NSAttributedString alloc] initWithString:@"Type your reply" attributes:@{NSFontAttributeName:inputFont,NSForegroundColorAttributeName:[UIColor colorWithWhite:.65 alpha:1.0]}];
    self.field.layer.cornerRadius=14;
    self.field.layer.cornerCurve=kCACornerCurveContinuous;
    self.field.clipsToBounds=YES;
    self.field.leftView=[[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    self.field.leftViewMode=UITextFieldViewModeAlways;
    self.field.rightView=[[UIView alloc] initWithFrame:CGRectMake(0,0,8,1)];
    self.field.rightViewMode=UITextFieldViewModeAlways;
    self.field.keyboardAppearance=UIKeyboardAppearanceDark;
    self.field.secureTextEntry=NO;
    self.field.adjustsFontSizeToFitWidth=NO;
    [self.field setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.field setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.field addTarget:self action:@selector(updateLiveDraft) forControlEvents:UIControlEventEditingChanged];
    self.liveDraftLabel=[UILabel new];
    self.liveDraftLabel.font=[UIFont systemFontOfSize:15];
    self.liveDraftLabel.textColor=UIColor.whiteColor;
    self.liveDraftLabel.numberOfLines=4;
    self.liveDraftLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    self.liveDraftLabel.hidden=YES;
    self.liveDraftLabel.isAccessibilityElement=NO;''')
rep('UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.contextLabel,input]];', 'UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.contextLabel,self.liveDraftLabel,input]];')
rep('- (void)focusField {\n    if (self.view.window && !self.view.window.hidden) {',r'''- (void)updateLiveDraft {
    // Read the same real field that submitReply uses; never synthesize or
    // independently send a message. Do not write to disk or logs.
    NSString *draft=self.field.text ?: @"";
    self.liveDraftLabel.text=draft;
    self.liveDraftLabel.hidden=(draft.length==0);
    self.field.textColor=UIColor.whiteColor;
    self.field.tintColor=[UIColor colorWithRed:.36 green:.70 blue:1 alpha:1];
    [self.liveDraftLabel setNeedsDisplay];
}
- (void)focusField {
    if (self.view.window && !self.view.window.hidden) {''')
rep('        [self.field becomeFirstResponder];\n    }\n}\n@end',r'''        [self.field becomeFirstResponder];
        [self updateLiveDraft];
    }
}
@end''')
rep('    self.replyHost.field.text=@"";\n    self.replyHost.contextLabel.text=@"";',r'''    self.replyHost.field.text=@"";
    self.replyHost.liveDraftLabel.text=@"";
    self.replyHost.liveDraftLabel.hidden=YES;
    self.replyHost.contextLabel.text=@"";''')
rep('1.0.12 Full Cover Plus loaded','1.0.13 Reply Visibility loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.13 Reply Visibility.")
