#import <Foundation/Foundation.h>

@interface CDVLogger : NSObject

+ (void)log:(NSString *)message;
+ (NSArray<NSString *> *)getLogs;
+ (void)clearLogs;

@end
