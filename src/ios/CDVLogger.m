#import "CDVLogger.h"

@implementation CDVLogger

static NSMutableArray<NSString *> *_logs = nil;
static NSUInteger const kMaxLogEntries = 100;

+ (void)initialize {
    if (self == [CDVLogger class]) {
        _logs = [NSMutableArray arrayWithCapacity:kMaxLogEntries];
    }
}

+ (void)log:(NSString *)message {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss.SSS"];
    NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    NSLog(@"CDVAUTO: %@", logEntry);
    
    @synchronized (_logs) {
        [_logs addObject:logEntry];
        
        // Trim logs if they exceed max count
        if (_logs.count > kMaxLogEntries) {
            [_logs removeObjectAtIndex:0];
        }
    }
    
    // Post notification so UI can update if showing logs
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVLoggerUpdated" object:nil];
}

+ (NSArray<NSString *> *)getLogs {
    @synchronized (_logs) {
        return [_logs copy];
    }
}

+ (void)clearLogs {
    @synchronized (_logs) {
        [_logs removeAllObjects];
    }
    
    // Post notification so UI can update if showing logs
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDVLoggerUpdated" object:nil];
}

@end
