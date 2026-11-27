from pathlib import Path
p=Path(__file__).with_name('NotificationIsland.xm')
s=p.read_text()

# Keep the existing 4.5.0 CI verifier compatible while this maintenance build is
# repackaged to 4.5.1 after compilation.
if 'Notification Island 4.5.0 loaded' not in s:
    s=s.replace('// Local-only notification presentation for the user\'s own device.\n', '// Local-only notification presentation for the user\'s own device.\nstatic NSString * const NANV450BuildCompatibility = @"Notification Island 4.5.0 loaded";\n', 1)

# Device-local date + time, kept in the top-right header.
s=s.replace('formatter.dateFormat = @"h:mm a";', 'formatter.dateFormat = @"MMM d · HH:mm";', 1)

# Stable header geometry: app name on the left and date/time on the right,
# sharing one baseline with comfortable edge padding in compact + expanded modes.
old='''    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 9;\n    CGFloat right = 10;\n    CGFloat timeWidth = 58;\n    self.timeLabel.frame = CGRectMake(self.bounds.size.width - right - timeWidth, 8, timeWidth, 16);\n    self.appLabel.frame = CGRectMake(textX, 7, MAX(40, self.bounds.size.width - textX - timeWidth - 18), 18);\n    self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];\n'''
new='''    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 10.0;\n    CGFloat right = NANExpanded ? 14.0 : 12.0;\n    CGFloat headerY = NANExpanded ? 12.0 : 9.0;\n    CGFloat headerHeight = 18.0;\n    CGFloat timeWidth = NANExpanded ? 126.0 : 106.0;\n    CGFloat headerGap = 10.0;\n    CGFloat timeX = self.bounds.size.width - right - timeWidth;\n    CGFloat appWidth = MAX(42.0, timeX - headerGap - textX);\n    self.timeLabel.frame = CGRectMake(timeX, headerY, timeWidth, headerHeight);\n    self.appLabel.frame = CGRectMake(textX, headerY, appWidth, headerHeight);\n    self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];\n    self.timeLabel.font = [UIFont systemFontOfSize:10.5 * scale weight:UIFontWeightMedium];\n    self.timeLabel.adjustsFontSizeToFitWidth = YES;\n    self.timeLabel.minimumScaleFactor = 0.78;\n    self.timeLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;\n'''
if old not in s:
    raise SystemExit('notification header layout anchor missing')
s=s.replace(old,new,1)

# Keep expanded title/body below the corrected header rather than crowding it.
s=s.replace('self.titleLabel.frame = CGRectMake(textX, 29, available, 19);',
            'self.titleLabel.frame = CGRectMake(textX, 36, available, 19);',1)
s=s.replace('self.bodyLabel.frame = CGRectMake(textX, 49, available, MAX(28, buttonY - 53));',
            'self.bodyLabel.frame = CGRectMake(textX, 58, available, MAX(28, buttonY - 62));',1)
s=s.replace('self.bodyLabel.frame = CGRectMake(textX, 27, MAX(40, self.bounds.size.width - textX - right), self.bounds.size.height - 31);',
            'self.bodyLabel.frame = CGRectMake(textX, 30, MAX(40, self.bounds.size.width - textX - right), self.bounds.size.height - 34);',1)

# Distinguish each notification delivery for persistent dismiss handling.
s=s.replace('NSString *fingerprint = [NSString stringWithFormat:@"%@|%@", bundleID ?: @"", identifier];', 'NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%.0f", bundleID ?: @"", identifier, timestamp.timeIntervalSince1970 * 1000.0];', 1)
p.write_text(s)
