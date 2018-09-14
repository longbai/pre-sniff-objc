//
//  PREDPersistence.m
//  Pods
//
//  Created by 王思宇 on 14/09/2017.
//
//

#import "PREDPersistence.h"
#import "PREDError.h"
#import "PREDHelper.h"
#import "PREDLogger.h"
#import "PREDTransaction.h"

#define PREDMaxCacheFileSize 512 * 1024 // 512KB
#define PREDMillisecondPerSecond 1000

@implementation PREDPersistence {
  NSString *_appInfoDir;
  NSString *_customDir;
  NSString *_transactionsDir;
  NSFileManager *_fileManager;
  NSFileHandle *_appInfoFileHandle;
  dispatch_queue_t _appInfoQueue;
  NSFileHandle *_customFileHandle;
  dispatch_queue_t _customEventQueue;
  NSFileHandle *_transactionsFileHandle;
  dispatch_queue_t _transactionsQueue;
}

- (instancetype)init {
  if (self = [super init]) {
    _fileManager = [NSFileManager defaultManager];

    _appInfoDir = [NSString
        stringWithFormat:@"%@/%@", PREDHelper.cacheDirectory, @"appInfo"];
    _customDir = [NSString
        stringWithFormat:@"%@/%@", PREDHelper.cacheDirectory, @"custom"];
    _transactionsDir = [NSString
        stringWithFormat:@"%@/%@", PREDHelper.cacheDirectory, @"transactions"];

    _appInfoQueue =
        dispatch_queue_create("predem_app_info", DISPATCH_QUEUE_SERIAL);
    _customEventQueue =
        dispatch_queue_create("predem_custom_event", DISPATCH_QUEUE_SERIAL);
    _transactionsQueue =
        dispatch_queue_create("predem_transactions", DISPATCH_QUEUE_SERIAL);

    NSError *error;
    [_fileManager createDirectoryAtPath:_appInfoDir
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
    if (error) {
      PREDLogError(@"create dir %@ failed", _appInfoDir);
    }
   
    [_fileManager createDirectoryAtPath:_customDir
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
    if (error) {
      PREDLogError(@"create dir %@ failed", _customDir);
    }
    [_fileManager createDirectoryAtPath:_transactionsDir
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
    if (error) {
      PREDLogError(@"create dir %@ failed", _transactionsDir);
    }
    PREDLogVerbose(@"cache directory:\n%@", PREDHelper.cacheDirectory);
  }
  return self;
}

- (void)persistAppInfo:(PREDAppInfo *)appInfo {
  dispatch_async(_appInfoQueue, ^{
    NSError *error;
    NSData *toSave = [appInfo serializeForSending:&error];
    if (error) {
      PREDLogError(@"jsonize app info error: %@", error);
      return;
    }

    _appInfoFileHandle =
        [self updateFileHandle:_appInfoFileHandle dir:_appInfoDir];
    if (!_appInfoFileHandle) {
      PREDLogError(@"no file handle drop app info data");
      return;
    }
    [_appInfoFileHandle writeData:toSave];
    [_appInfoFileHandle
        writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  });
}

- (void)persistCustomEvent:(PREDCustomEvent *)event {
  dispatch_async(_customEventQueue, ^{
    NSError *error;
    NSData *toSave = [event serializeForSending:&error];
    if (error) {
      PREDLogError(@"jsonize custom events error: %@", error);
      return;
    }

    _customFileHandle =
        [self updateFileHandle:_customFileHandle dir:_customDir];
    if (!_customFileHandle) {
      PREDLogError(@"no file handle drop custom data");
      return;
    }
    [_customFileHandle writeData:toSave];
    [_customFileHandle
        writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  });
}

- (void)persistTransaction:(PREDTransaction *)transaction {
  dispatch_async(_transactionsQueue, ^{
    NSError *error;
    NSData *toSave = [transaction serializeForSending:&error];
    if (error) {
      PREDLogError(@"jsonize transaction events error: %@", error);
      return;
    }

    _transactionsFileHandle =
        [self updateFileHandle:_transactionsFileHandle dir:_transactionsDir];
    if (!_transactionsFileHandle) {
      PREDLogError(@"no file handle drop transaction data");
      return;
    }
    [_transactionsFileHandle writeData:toSave];
    [_transactionsFileHandle
        writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  });
}

// no batch

- (NSString *)nextArchivedAppInfoPath {
  NSFileHandle *fileHanle = _appInfoFileHandle;
  NSString *path = [self nextArchivedPathForDir:_appInfoDir
                                     fileHandle:&fileHanle
                                        inQueue:_appInfoQueue];
  _appInfoFileHandle = fileHanle;
  return path;
}

// do not use this method in _customEventQueue which will cause dead lock
- (NSString *)nextArchivedCustomEventsPath {
  NSFileHandle *fileHanle = _customFileHandle;
  NSString *path = [self nextArchivedPathForDir:_customDir
                                     fileHandle:&fileHanle
                                        inQueue:_customEventQueue];
  _customFileHandle = fileHanle;
  return path;
}

- (NSString *)nextArchivedTransactionsPath {
  NSFileHandle *fileHanle = _transactionsFileHandle;
  NSString *path = [self nextArchivedPathForDir:_transactionsDir
                                     fileHandle:&fileHanle
                                        inQueue:_transactionsQueue];
  _transactionsFileHandle = fileHanle;
  return path;
}

- (NSString *)nextArchivedPathForDirRun:(NSString *)dir
                             fileHandle:
                                 (NSFileHandle *__autoreleasing *)fileHandle {
  NSString *archivedPath;
  for (NSString *filePath in [_fileManager enumeratorAtPath:dir]) {
    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"SELF MATCHES %@",
                                         @"^[0-9]+\\.?[0-9]*\\.archive$"];
    if ([predicate evaluateWithObject:filePath]) {
      archivedPath = [NSString stringWithFormat:@"%@/%@", dir, filePath];
    }
  }
  // if no archived file found
  for (NSString *filePath in [_fileManager enumeratorAtPath:dir]) {
    NSPredicate *predicate = [NSPredicate
        predicateWithFormat:@"SELF MATCHES %@", @"^[0-9]+\\.?[0-9]*$"];
    if ([predicate evaluateWithObject:filePath]) {
      if (*fileHandle) {
        [*fileHandle closeFile];
        *fileHandle = nil;
      }
      NSError *error;
      archivedPath =
          [NSString stringWithFormat:@"%@/%@.archive", dir, filePath];
      [_fileManager
          moveItemAtPath:[NSString stringWithFormat:@"%@/%@", dir, filePath]
                  toPath:archivedPath
                   error:&error];
      if (error) {
        archivedPath = nil;
        NSLog(@"archive file %@ fail", filePath);
        continue;
      }
    }
  }
  return archivedPath;
}

- (NSString *)nextArchivedPathForDir:(NSString *)dir
                          fileHandle:(NSFileHandle *__autoreleasing *)fileHandle
                             inQueue:(dispatch_queue_t)queue {
  __block NSString *archivedPath;
  dispatch_sync(queue, ^{
    archivedPath = [self nextArchivedPathForDirRun:dir fileHandle:fileHandle];
  });
  return archivedPath;
}

- (void)purgeFile:(NSString *)filePath {
  NSError *error;
  [_fileManager removeItemAtPath:filePath error:&error];
  if (error) {
    PREDLogError(@"purge file %@ error %@", filePath, error);
  } else {
    PREDLogVerbose(@"purge file %@ succeeded", filePath);
  }
}

- (void)purgeAllAppInfo {
  NSError *error;
  for (NSString *fileName in [_fileManager enumeratorAtPath:_appInfoDir]) {
    NSString *filePath =
        [NSString stringWithFormat:@"%@/%@", _appInfoDir, fileName];
    [_fileManager removeItemAtPath:filePath error:&error];
    if (error) {
      PREDLogError(@"purge file %@ error %@", filePath, error);
    } else {
      PREDLogVerbose(@"purge file %@ succeeded", filePath);
    }
  }
}

- (void)purgeAllCustom {
  NSError *error;
  for (NSString *fileName in [_fileManager enumeratorAtPath:_customDir]) {
    NSString *filePath =
        [NSString stringWithFormat:@"%@/%@", _customDir, fileName];
    [_fileManager removeItemAtPath:filePath error:&error];
    if (error) {
      PREDLogError(@"purge file %@ error %@", filePath, error);
    } else {
      PREDLogVerbose(@"purge file %@ succeeded", filePath);
    }
  }
}

- (void)purgeAllTransactions {
  NSError *error;
  for (NSString *fileName in [_fileManager enumeratorAtPath:_transactionsDir]) {
    NSString *filePath =
        [NSString stringWithFormat:@"%@/%@", _transactionsDir, fileName];
    [_fileManager removeItemAtPath:filePath error:&error];
    if (error) {
      PREDLogError(@"purge file %@ error %@", filePath, error);
    } else {
      PREDLogVerbose(@"purge file %@ succeeded", filePath);
    }
  }
}

- (void)purgeAllPersistence {
  [self purgeAllAppInfo];
  [self purgeAllCustom];
  [self purgeAllTransactions];
}

- (void)purgeFiles:(NSArray<NSString *> *)filePaths {
  __block NSError *error;
  [filePaths enumerateObjectsUsingBlock:^(NSString *_Nonnull filePath,
                                          NSUInteger idx, BOOL *_Nonnull stop) {
    [_fileManager removeItemAtPath:filePath error:&error];
    if (error) {
      PREDLogError(@"purge file %@ error %@", filePath, error);
    } else {
      PREDLogVerbose(@"purge file %@ succeeded", filePath);
    }
  }];
}

- (NSFileHandle *)updateFileHandle:(NSFileHandle *)oldFileHandle
                               dir:(NSString *)dir {
  if (oldFileHandle) {
    if (oldFileHandle.offsetInFile <= PREDMaxCacheFileSize) {
      return oldFileHandle;
    } else {
      [oldFileHandle closeFile];
      oldFileHandle = nil;
    }
  }

  NSString *availableFile;
  for (NSString *filePath in [_fileManager enumeratorAtPath:dir]) {
    NSString *normalFilePattern = @"^[0-9]+\\.?[0-9]*$";
    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"SELF MATCHES %@", normalFilePattern];
    if ([predicate evaluateWithObject:filePath]) {
      availableFile = [NSString stringWithFormat:@"%@/%@", dir, filePath];
      break;
    }
  }
  if (!availableFile) {
    availableFile = [NSString
        stringWithFormat:@"%@/%f", dir, [[NSDate date] timeIntervalSince1970]];
    BOOL success = [_fileManager createFileAtPath:availableFile
                                         contents:nil
                                       attributes:nil];
    if (!success) {
      PREDLogError(@"create file failed %@", availableFile);
      return nil;
    }
  }
  oldFileHandle = [NSFileHandle fileHandleForUpdatingAtPath:availableFile];
  [oldFileHandle seekToEndOfFile];
  return oldFileHandle;
}

@end
