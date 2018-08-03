//
//  JMLog.m
//  JMLog
//
//  Created by jimmy_lem on 2018/8/3.
//  Copyright © 2018年 Jimmy. All rights reserved.
//

#import "JMLog.h"
#import <UIKit/UIKit.h>
#import <PocketSocket/PSWebSocketServer.h>
#include <mach/machine/vm_param.h>
#include <mach/mach_host.h>
#include <mach/mach_init.h>
#include <mach/task.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <SystemConfiguration/CaptiveNetwork.h>

const NSUInteger JMLOG_PORT = 9090;

const NSString* LOG_SEPERATE_COMP = @"```";

const NSString* LOG_REQUEST_DEVICEINFO = @"log.request.deviceinfo";
const NSString* LOG_REQUEST_BUNDLEINFO = @"log.request.bundleinfo";
const NSString* LOG_REQUEST_STORAGEINFO = @"log.request.storageInfo";
const NSString* LOG_REQUEST_NETWORKINFO = @"log.request.networkInfo";

void JMLog(JMLOG_TYPE type, const char* file, const char* func, int line, NSString* format){
#ifdef DEBUG
    NSString* debug = @"";
    switch (type) {
        case JMLOG_TYPE_DEBUG:
            debug = @"[Debug]";
            break;
        case JMLOG_TYPE_WARN:
            debug = @"[Warning]";
            break;
        case JMLOG_TYPE_ERROR:
            debug = @"[Error]";
            break;
        case JMLOG_TYPE_RESPONSE:
            debug = @"[Response]";
            break;
        case JMLOG_TYPE_INFO:
            debug = @"[Info]";
            break;
    }
    NSLog(@"%@ %s [Line:%d] %@%@",debug,func,line,format,LOG_SEPERATE_COMP);
#endif
}

@interface JMLogMgr :NSObject <PSWebSocketServerDelegate>

+ (instancetype)shareInstance;

@property (nonatomic, strong)  NSString* logFilePath;
@property (nonatomic, strong)  PSWebSocketServer *server;
@property (nonatomic, strong, nullable)PSWebSocket * webSocket;
@property (nonatomic, strong)  dispatch_source_t sourt_t;

@end

@implementation JMLogMgr

+ (instancetype)shareInstance {
    static JMLogMgr* mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [JMLogMgr new];
    });
    return mgr;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        [self createNewLogFile];
        self.sourt_t = [self startCapturingLogFrom:STDERR_FILENO];
    }
    return self;
}

- (BOOL)createNewLogFile{
    //    ///如果已经连接Xcode调试则不输出到文件
    //    if(isatty(STDOUT_FILENO)) {
    //        return;
    //    }
    //    ///在模拟器不保存到文件中
    //    UIDevice *device = [UIDevice currentDevice];
    //    if([[device model] hasSuffix:@"Simulator"]){
    //        return;
    //    }
    //将NSlog打印信息保存到Document目录下的Log文件夹下
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Log"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL fileExists = [fileManager fileExistsAtPath:logDirectory];
    if (!fileExists) {
        [fileManager createDirectoryAtPath:logDirectory  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"]];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"]; //每次启动后都保存一个新的日志文件中
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    NSString *logFilePath = [logDirectory stringByAppendingFormat:@"/%@.log",dateStr];
    fileExists = [fileManager fileExistsAtPath:logFilePath];
    if (!fileExists) {
        BOOL isSucess = [fileManager createFileAtPath:logFilePath contents:nil attributes:nil];
        if (isSucess){
            self.logFilePath = logFilePath;
        }else{
            jm_log_error(@"Create log file fail.");
            return NO;
        }
    }
    
    //未捕获的Objective-C异常日志
    NSSetUncaughtExceptionHandler (&UncaughtExceptionHandler);
    
    return YES;
}

///写入log信息
- (void)write:(NSString*)dataStr byPath:(NSString*)path{
    if (path.length > 0){
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        NSData *data = [[dataStr stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        [handle writeData:data];
    }
}

///删除超过时长的日志文件
- (void)deleteLogFileByLimitHours:(int)hours{
    NSString *logPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Log"];
    NSDirectoryEnumerator<NSString *> * enumerator;
    enumerator=  [[NSFileManager defaultManager] enumeratorAtPath:logPath];
    NSString* strPath = logPath;
    while (strPath = [enumerator nextObject]) {
        for (NSString * namePath in strPath.pathComponents) {
            NSString* logfilePath = [logPath stringByAppendingPathComponent:namePath];
            NSDictionary<NSFileAttributeKey, id> *attribute = [[NSFileManager defaultManager] attributesOfItemAtPath:logfilePath error:nil];
            if (attribute) {
                NSDate* createDate = [attribute valueForKey:NSFileCreationDate];
                NSTimeInterval interval = [createDate timeIntervalSinceDate:[NSDate date]];
                if (-interval/60/60 > hours) {
                    ///删除过时的log文件
                    [[NSFileManager defaultManager] removeItemAtPath:logfilePath error:nil];
                }
            }
        }
    }
}

///抓取打印日志
- (dispatch_source_t)startCapturingLogFrom:(int)fd{
    int origianlFD = fd;
    int originalStdHandle = dup(fd);//save the original for reset proporse
    int fildes[2];
    pipe(fildes);  // [0] is read end of pipe while [1] is write end
    dup2(fildes[1], fd);  // Duplicate write end of pipe "onto" fd (this closes fd)
    close(fildes[1]);  // Close original write end of pipe
    fd = fildes[0];  // We can now monitor the read end of the pipe
    
    NSMutableData* data = [[NSMutableData alloc] init];
    fcntl(fd, F_SETFL, O_NONBLOCK);// set the reading of this file descriptor without delay
    __weak typeof(self) wkSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    
    int writeEnd = fildes[1];
    dispatch_source_set_cancel_handler(source, ^{
        close(writeEnd);
        dup2(originalStdHandle, origianlFD);//reset the original file descriptor
    });
    
    dispatch_source_set_event_handler(source, ^{
        @autoreleasepool {
            char buffer[1024 * 10];
            ssize_t size = read(fd, (void*)buffer, (size_t)(sizeof(buffer)));
            [data setLength:0];
            [data appendBytes:buffer length:size];
            NSString *aString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray* subStrArray = [aString componentsSeparatedByString:[LOG_SEPERATE_COMP copy]];
            for (NSString* subStr in subStrArray){
                [wkSelf write:subStr byPath:wkSelf.logFilePath];
                printf("%s",[subStr UTF8String]); //print on STDOUT_FILENO，so that the log can still print on xcode console
                NSString* temp = [subStr copy];
                if ([temp hasPrefix:@"\n"]){
                    temp = [temp substringWithRange:NSMakeRange(1, temp.length-1)];
                }
                if (temp.length > 0){
                    [wkSelf.webSocket send:temp];
                }
            }
        }
    });
    dispatch_resume(source);
    return source;
}

///crash捕获日志写入
void UncaughtExceptionHandler(NSException* exception) {
    NSString* name = [ exception name ];
    NSString* reason = [ exception reason ];
    NSArray* symbols = [ exception callStackSymbols ]; // 异常发生时的调用栈
    NSMutableString* strSymbols = [ [ NSMutableString alloc ] init ]; //将调用栈拼成输出日志的字符串
    for ( NSString* item in symbols ) {
        [ strSymbols appendString: item ];
        [ strSymbols appendString: @"\r\n" ];
    }
    
    NSString* logFilePath = [JMLogMgr shareInstance].logFilePath;
    if (!logFilePath){
        return;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"]];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    
    NSString *crashString = [NSString  stringWithFormat:@"<- %@ ->[ Uncaught Exception ]\r\nName: %@, Reason: %@\r\n[ Fe Symbols Start ]\r\n%@[ Fe Symbols End ]\r\n\r\n", dateStr, name, reason, strSymbols];
    jm_log_error(@"%@",crashString);
    
    NSFileHandle *outFile = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    [outFile seekToEndOfFile];
    [outFile writeData:[crashString dataUsingEncoding:NSUTF8StringEncoding]];
    [outFile closeFile];
}

- (void)startServer{
    if (self.server){
        [self.server stop];
    }
    self.server = [PSWebSocketServer serverWithHost:nil port:JMLOG_PORT];
    self.server.delegate = self;
    [self.server start];
}

- (void)stopServer{
    if (self.server){
        [self.server stop];
    }
}

- (void)logDeviceInfo{
    ///设备名称
    ///电量 充电状态 系统版本 ip地址 系统语言 uuid mac地址 方向
    
    UIDevice* device = [UIDevice currentDevice];
    NSMutableString* infoStr = [NSMutableString stringWithString:@"\nDEVICE INFO\n"];
    [infoStr appendFormat:@"[name]: %@ \n",device.name];
    [infoStr appendFormat:@"[model]: %@ \n",device.model];
    [infoStr appendFormat:@"[sysName]: %@ \n",device.systemName];
    [infoStr appendFormat:@"[sysVersion]: %@ \n",device.systemVersion];
    [infoStr appendFormat:@"[uuid]: %@ \n",device.identifierForVendor.UUIDString];
    [infoStr appendFormat:@"[orientation]: %ld \n",(long)device.orientation];
    [infoStr appendFormat:@"[batteryState]: %ld \n",(long)device.batteryState];
    [infoStr appendFormat:@"[batteryLevel]: %f \n",device.batteryLevel];
    NSString* info = [infoStr copy];
    jm_log_info(@"%@",info);
}

- (void)logApplicationInfo{
    ///应用信息
    ///发布版本 编译版本 bundleid
    NSDictionary *infoDic = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDic valueForKey:@"CFBundleShortVersionString"];
    NSString *codeVersion = [infoDic valueForKey:@"CFBundleVersion"];
    NSString *bundleIdentifier = [infoDic[@"CFBundleIdentifier"] copy];
    NSMutableString* infoStr = [NSMutableString stringWithString:@"\nAPPLICATION INFO\n"];
    [infoStr appendFormat:@"[version]: %@ \n",version];
    [infoStr appendFormat:@"[codeVersion]: %@ \n",codeVersion];
    [infoStr appendFormat:@"[bundleIdentifier]: %@\n",bundleIdentifier];
    NSString* info = [infoStr copy];
    jm_log_info(@"%@",info);
}

- (void)logStorageInfo{
    /// 总大小
    float totalsize = 0.0;
    /// 剩余大小
    float freesize = 0.0;
    /// 是否登录
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    if (dictionary)
    {
        NSNumber *_free = [dictionary objectForKey:NSFileSystemFreeSize];
        freesize = [_free unsignedLongLongValue]*1.0/(1024);
        
        NSNumber *_total = [dictionary objectForKey:NSFileSystemSize];
        totalsize = [_total unsignedLongLongValue]*1.0/(1024);
    } else
    {
        jm_log_error(@"Error Obtaining System Memory Info: Domain = %@, Code = %ld", [error domain], (long)[error code]);
    }
    NSMutableString* infoStr = [NSMutableString stringWithString:@"\nROM INFO\n"];
    [infoStr appendFormat:@"totalSize: %.2f MB \n",totalsize/1024];
    [infoStr appendFormat:@"freeSize: %.2f MB \n",freesize/1024];
    jm_log_info(@"%@",infoStr);
}

// 获取当前设备可用内存(单位：MB）
- (double)availableMemory
{
    vm_statistics_data_t vmStats;
    mach_msg_type_number_t infoCount = HOST_VM_INFO_COUNT;
    kern_return_t kernReturn = host_statistics(mach_host_self(),
                                               HOST_VM_INFO,
                                               (host_info_t)&vmStats,
                                               &infoCount);
    if (kernReturn != KERN_SUCCESS) {
        return NSNotFound;
    }
    return ((vm_page_size *vmStats.free_count) / 1024.0) / 1024.0;
}

// 获取当前任务所占用的内存（单位：MB）
- (double)usedMemory
{
    task_basic_info_data_t taskInfo;
    mach_msg_type_number_t infoCount = TASK_BASIC_INFO_COUNT;
    kern_return_t kernReturn = task_info(mach_task_self(),
                                         TASK_BASIC_INFO,
                                         (task_info_t)&taskInfo,
                                         &infoCount);
    if (kernReturn != KERN_SUCCESS) {
        return NSNotFound;
    }
    return taskInfo.resident_size / 1024.0 / 1024.0;
}

- (void)logMemoryInfo{
    NSMutableString* infoStr = [NSMutableString stringWithString:@"\nRAM INFO\n"];
    [infoStr appendFormat:@"avaliableSize: %.2f MB \n",[self availableMemory]];
    [infoStr appendFormat:@"usedSize: %.2f MB \n",[self usedMemory]];
    jm_log_info(@"%@",infoStr);
}

- (nullable NSString*)getCurrentLocalIP
{
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
}

- (nullable NSString *)getCurreWiFiSsid {
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    id info = nil;
    for (NSString *ifnam in ifs) {
        info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info && [info count]) { break; }
    }
    return [(NSDictionary*)info objectForKey:@"SSID"];
}

- (void)logNetworkInfo{
    NSMutableString* infoStr = [NSMutableString stringWithString:@"\nNETWORK INFO\n"];
    NSString* localIP = [self getCurrentLocalIP];
    if (localIP){
        [infoStr appendFormat:@"wifi: %@ \n",localIP];
    }
    NSString* wifiSSID = [self getCurreWiFiSsid];
    if (wifiSSID){
        [infoStr appendFormat:@"wifiSSID: %@ \n",wifiSSID];
    }
    jm_log_info(@"%@",infoStr);
}

#pragma mark - PSWebSocketServerDelegate
- (void)serverDidStart:(PSWebSocketServer *)server{
    jm_log(@"log server did start.");
}

- (void)server:(PSWebSocketServer *)server didFailWithError:(NSError *)error{
    jm_log(@"log server did fail, error:%@",error.description);
}

- (void)serverDidStop:(PSWebSocketServer *)server{
    jm_log(@"log server did stop.");
}

- (void)server:(PSWebSocketServer *)server webSocketDidOpen:(PSWebSocket *)webSocket{
    jm_log(@"log webscoket did open.");
    self.webSocket = webSocket;
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didReceiveMessage:(id)message{
    jm_log(@"log server did receive. message:%@",message);
    if([message isEqual:LOG_REQUEST_DEVICEINFO]) {
        [self logDeviceInfo];
    }else if([message isEqual:LOG_REQUEST_BUNDLEINFO]) {
        [self logApplicationInfo];
    }else if([message isEqual:LOG_REQUEST_STORAGEINFO]){
        [self logStorageInfo];
        [self logMemoryInfo];
    }else if([message isEqual:LOG_REQUEST_NETWORKINFO]){
        [self logNetworkInfo];
    }
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didFailWithError:(NSError *)error{
    jm_log(@"log webscoket did fail, error:%@",error.description);
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean{
    jm_log(@"log websocket did close, code:%ld, reason:%@, wasClean:%d",(long)code,reason,wasClean);
}

- (BOOL)server:(PSWebSocketServer *)server acceptWebSocketWithRequest:(NSURLRequest *)request{
    jm_log(@"server accept websocket. request:%@",request.description);
    return YES;
}

- (BOOL)server:(PSWebSocketServer *)server acceptWebSocketWithRequest:(NSURLRequest *)request address:(NSData *)address trust:(SecTrustRef)trust response:(NSHTTPURLResponse *__autoreleasing *)response{
    jm_log(@"server accept websokcet. request:%@",request.description);
    return YES;
}


@end


void jm_log_init(int limitHours){
#ifdef DEBUG
    [[JMLogMgr shareInstance] deleteLogFileByLimitHours:limitHours];
#endif
}

void jm_log_startServer(void){
#ifdef DEBUG
    [[JMLogMgr shareInstance] startServer];
#endif
}

void jm_log_stopServer(void){
#ifdef DEBUG
    [[JMLogMgr shareInstance] stopServer];
#endif
}
