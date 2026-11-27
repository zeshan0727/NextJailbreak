#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('NotificationIsland.xm')
text = path.read_text()
anchor = '''@interface SBSystemApertureWindow : UIWindow
@end
'''
addition = anchor + '''
@interface NCNotificationShortLookViewController : UIViewController
@end
'''
if '@interface NCNotificationShortLookViewController : UIViewController' not in text:
    if anchor not in text:
        raise SystemExit('Short-look class insertion anchor not found')
    text = text.replace(anchor, addition, 1)
path.write_text(text)
print('Applied UIKit superclass declaration for notification short-look controller.')
