//
//  JMLog.h
//  JMLog
//
//  Created by jimmy_lem on 2018/8/3.
//  Copyright © 2018年 Jimmy. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, JMLOG_TYPE) {
    JMLOG_TYPE_DEBUG,        ///正常日志
    JMLOG_TYPE_RESPONSE,     ///响应日志
    JMLOG_TYPE_WARN,         ///警告日志
    JMLOG_TYPE_ERROR,        ///错误日志
    JMLOG_TYPE_INFO,         ///信息日志
};

void JMLog(JMLOG_TYPE type, const char* file, const char* func, int line, NSString* format);

///普通日志
#define jm_log(format,...)  JMLog(JMLOG_TYPE_DEBUG,__FILE__,__func__,__LINE__,[NSString stringWithFormat:(format), ##__VA_ARGS__])

///警告日志
#define jm_log_warn(format,...)  JMLog(JMLOG_TYPE_WARN,__FILE__,__func__,__LINE__,[NSString stringWithFormat:(format), ##__VA_ARGS__])

///错误日志
#define jm_log_error(format,...)  JMLog(JMLOG_TYPE_ERROR,__FILE__,__func__,__LINE__,[NSString stringWithFormat:(format), ##__VA_ARGS__])

///响应日志
#define jm_log_response(format,...)  JMLog(JMLOG_TYPE_RESPONSE,__FILE__,__func__,__LINE__,[NSString stringWithFormat:(format), ##__VA_ARGS__])

///信息日志
#define jm_log_info(format,...) JMLog(JMLOG_TYPE_INFO,__FILE__,__func__,__LINE__,[NSString stringWithFormat:(format), ##__VA_ARGS__])


/**
 *  log初始化
 *
 * @param limitHours log文件的保留时长
 */
void jm_log_init(int limitHours);


/**
 *  开启远程log服务
 */
void jm_log_startServer(void);


/**
 *  结束远程log服务
 */
void jm_log_stopServer(void);
