#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>
#import <dlfcn.h>

static CFStringRef const NQRDatabaseChangedNotification = CFSTR("com.nextsolution.nextreminder.database.changed");
static id NQRMissedPersistentTimer = nil;
static id NQRMissedSchedulerTarget = nil;

static NSString *NQRAppContainerPathForMissed(void) {
    @try {
        Class c = NSClassFromString(@"LSApplicationProxy");
        SEL s = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!c || ![c respondsToSelector:s]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(c, s, @"com.nextsolution.nextreminder");
        SEL d = NSSelectorFromString(@"dataContainerURL");
        if (!proxy || ![proxy respondsToSelector:d]) return nil;
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(proxy, d);
        return [url isKindOfClass:NSURL.class] ? url.path : nil;
    } @catch (__unused NSException *e) { return nil; }
}

static NSArray<NSDictionary *> *NQRReminderRows(void) {
    NSString *container = NQRAppContainerPathForMissed();
    if (!container.length) return @[];
    NSString *path = [container stringByAppendingPathComponent:@"Library/Application Support/NextReminder/NextReminderDatabase.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) return @[];
    id rows = ((NSDictionary *)root)[@"reminders"];
    return [rows isKindOfClass:NSArray.class] ? rows : @[];
}

static NSDate *NQRDateFromJSON(id raw) {
    if (![raw isKindOfClass:NSString.class]) return nil;
    NSString *value = (NSString *)raw;
    if (!value.length) return nil;
    NSISO8601DateFormatter *fractional = [NSISO8601DateFormatter new];
    fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [fractional dateFromString:value];
    if (date) return date;
    NSISO8601DateFormatter *standard = [NSISO8601DateFormatter new];
    standard.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [standard dateFromString:value];
}

static BOOL NQRReminderCompleted(NSDictionary *row) {
    id value = row[@"completedAt"];
    return value && value != NSNull.null;
}

static BOOL NQRReminderNotificationsEnabled(NSDictionary *row) {
    id value = row[@"notificationsEnabled"];
    return !value || ![value respondsToSelector:@selector(boolValue)] ? YES : [value boolValue];
}

static NSString *NQRMissedRequestID(NSString *reminderID) {
    return [NSString stringWithFormat:@"%@-missed-daily", reminderID ?: @""];
}

static UNUserNotificationCenter *NQRNextReminderNotificationCenter(void) {
    Class cls = NSClassFromString(@"UNUserNotificationCenter");
    SEL sel = NSSelectorFromString(@"initWithBundleIdentifier:");
    if (cls && [cls instancesRespondToSelector:sel]) {
        id obj = [cls alloc];
        id center = ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, @"com.nextsolution.nextreminder");
        if ([center isKindOfClass:UNUserNotificationCenter.class]) return center;
    }
    return nil;
}

static void NQRRemoveMissedRequest(UNUserNotificationCenter *center, NSString *reminderID) {
    if (!center || !reminderID.length) return;
    NSString *identifier = NQRMissedRequestID(reminderID);
    [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
    [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
}

static void NQRSyncMissedReminderNotifications(void) {
    NSArray<NSDictionary *> *rows = NQRReminderRows();
    UNUserNotificationCenter *center = NQRNextReminderNotificationCenter();
    if (!center) {
        NSLog(@"[NextQuickReminder] ERROR unable to open Next Reminder notification center");
        return;
    }

    NSDate *now = NSDate.date;
    NSMutableSet<NSString *> *validIDs = [NSMutableSet set];

    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSString *reminderID = [row[@"id"] isKindOfClass:NSString.class] ? row[@"id"] : nil;
        if (!reminderID.length) continue;
        [validIDs addObject:NQRMissedRequestID(reminderID)];

        if (NQRReminderCompleted(row) || !NQRReminderNotificationsEnabled(row)) {
            NQRRemoveMissedRequest(center, reminderID);
            continue;
        }

        NSDate *due = NQRDateFromJSON(row[@"dueDate"]);
        if (!due || [due compare:now] == NSOrderedDescending) {
            NQRRemoveMissedRequest(center, reminderID);
            continue;
        }

        NSString *title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"Reminder";
        NSString *notes = [row[@"notes"] isKindOfClass:NSString.class] ? row[@"notes"] : @"";

        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = title.length ? title : @"Reminder";
        content.subtitle = @"Missed reminder • repeats daily";
        content.body = notes.length ? notes : @"This reminder is still incomplete. Mark it Completed to stop daily alerts.";
        content.sound = UNNotificationSound.defaultSound;
        content.badge = @1;
        content.categoryIdentifier = @"NEXT_REMINDER_CATEGORY";
        content.threadIdentifier = @"Missed Reminders";
        content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
        content.userInfo = @{@"reminderID": reminderID, @"missedDaily": @YES};

        NSCalendar *calendar = NSCalendar.currentCalendar;
        NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:due];
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:YES];
        NSString *identifier = NQRMissedRequestID(reminderID);
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            if (error) NSLog(@"[NextQuickReminder] missed daily schedule failed %@: %@", reminderID, error);
            else NSLog(@"[NextQuickReminder] missed daily active %@ at %02ld:%02ld", reminderID, (long)components.hour, (long)components.minute);
        }];
    }

    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
        NSMutableArray<NSString *> *stale = [NSMutableArray array];
        for (UNNotificationRequest *request in requests) {
            if ([request.identifier hasSuffix:@"-missed-daily"] && ![validIDs containsObject:request.identifier]) {
                [stale addObject:request.identifier];
            }
        }
        if (stale.count) [center removePendingNotificationRequestsWithIdentifiers:stale];
    }];
}

static NSDate *NQRNextFutureDueDate(void) {
    NSDate *now = NSDate.date;
    NSDate *best = nil;
    for (NSDictionary *row in NQRReminderRows()) {
        if (![row isKindOfClass:NSDictionary.class] || NQRReminderCompleted(row) || !NQRReminderNotificationsEnabled(row)) continue;
        NSDate *due = NQRDateFromJSON(row[@"dueDate"]);
        if (!due || [due compare:now] != NSOrderedDescending) continue;
        if (!best || [due compare:best] == NSOrderedAscending) best = due;
    }
    return best;
}

static void NQRInvalidateMissedTimer(void) {
    if (NQRMissedPersistentTimer && [NQRMissedPersistentTimer respondsToSelector:NSSelectorFromString(@"invalidate")]) {
        ((void (*)(id, SEL))objc_msgSend)(NQRMissedPersistentTimer, NSSelectorFromString(@"invalidate"));
    }
    NQRMissedPersistentTimer = nil;
}

@class NQRMissedScheduleTarget;
static void NQRScheduleNextMissedWake(void);

@interface NQRMissedScheduleTarget : NSObject
- (void)nqrMissedTimerFired:(id)timer;
@end

@implementation NQRMissedScheduleTarget
- (void)nqrMissedTimerFired:(id)timer {
    NSLog(@"[NextQuickReminder] missed-reminder persistent wake fired");
    NQRInvalidateMissedTimer();
    NQRSyncMissedReminderNotifications();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NQRScheduleNextMissedWake();
    });
}
@end

static void NQRScheduleNextMissedWake(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRInvalidateMissedTimer();
        NSDate *due = NQRNextFutureDueDate();
        if (!due) {
            NSLog(@"[NextQuickReminder] no future reminder due date needs a missed-reminder wake");
            return;
        }

        NSDate *fireDate = [due dateByAddingTimeInterval:2.0];
        if (!NSClassFromString(@"PCPersistentTimer")) {
            dlopen("/System/Library/PrivateFrameworks/PersistentConnection.framework/PersistentConnection", RTLD_LAZY | RTLD_LOCAL);
        }
        Class timerClass = NSClassFromString(@"PCPersistentTimer");
        if (!timerClass) {
            NSLog(@"[NextQuickReminder] ERROR PCPersistentTimer unavailable for missed reminders");
            return;
        }
        if (!NQRMissedSchedulerTarget) NQRMissedSchedulerTarget = [NQRMissedScheduleTarget new];

        SEL initSel = NSSelectorFromString(@"initWithFireDate:serviceIdentifier:target:selector:userInfo:");
        id obj = [timerClass alloc];
        if (![obj respondsToSelector:initSel]) return;
        obj = ((id (*)(id, SEL, id, id, id, SEL, id))objc_msgSend)(
            obj, initSel, fireDate,
            @"com.nextsolution.nextquickreminder.missedreminders",
            NQRMissedSchedulerTarget,
            @selector(nqrMissedTimerFired:),
            nil
        );
        if (!obj) return;

        SEL wakeSel = NSSelectorFromString(@"setDisableSystemWaking:");
        if ([obj respondsToSelector:wakeSel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, wakeSel, NO);
        SEL scheduleSel = NSSelectorFromString(@"scheduleInRunLoop:");
        if ([obj respondsToSelector:scheduleSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(obj, scheduleSel, NSRunLoop.mainRunLoop);
            NQRMissedPersistentTimer = obj;
            NSLog(@"[NextQuickReminder] next missed-reminder wake scheduled %@", fireDate);
        }
    });
}

static void NQRDatabaseChangedForMissed(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NQRSyncMissedReminderNotifications();
        NQRScheduleNextMissedWake();
    });
}

void NQRStartMissedReminderScheduler(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NQRDatabaseChangedForMissed,
            NQRDatabaseChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[NextQuickReminder] starting missed-reminder daily scheduler");
        NQRSyncMissedReminderNotifications();
        NQRScheduleNextMissedWake();
    });
}
