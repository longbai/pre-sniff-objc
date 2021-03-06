#import <Foundation/Foundation.h>

@class PRESTelemetryData;
@class PRESTelemetryContext;
@class PRESPersistence;

#import "PRESChannel.h"

#import "PRESNullability.h"
NS_ASSUME_NONNULL_BEGIN

@interface PRESChannel ()

/**
 * Notification that will be send on the main thread to notifiy observers that channel can't enqueue new items.
 * This is typically used to trigger sending to the server.
 */
FOUNDATION_EXPORT NSString *const PRESChannelBlockedNotification;

/**
 *  Telemetry context used by the channel to create the payload (testing).
 */
@property (nonatomic, strong) PRESTelemetryContext *telemetryContext;

/**
 *  Persistence instance for storing files after the queue gets flushed (testing).
 */
@property (nonatomic, strong) PRESPersistence *persistence;

/*
 * Threshold for sending data to the server. Default batch size for debugging is 150, for release
 * configuration, the batch size is 5.
 *
 * Default: 50
 *
 * @warning: We advice to not set the batch size below 5 events.
 */
@property (nonatomic) NSUInteger maxBatchSize;

/*
 * Interval for sending data to the server in seconds.
 *
 * Default: 15
 */
@property (nonatomic, assign) NSInteger batchInterval;

/**
 *  A timer source which is used to flush the queue after a cretain time.
 */
@property (nonatomic, strong, nullable) dispatch_source_t timerSource;

/**
 *  A queue which makes array operations thread safe.
 */
@property (nonatomic, strong) dispatch_queue_t dataItemsOperations;

/**
 *  An integer value that keeps tracks of the number of data items added to the JSON Stream string.
 */
@property (nonatomic, assign) NSUInteger dataItemCount;

/**
 *  Indicates that channel is currently in a blocked state.
 */
@property BOOL channelBlocked;

/**
 *  Manually trigger the PRESChannel to persist all items currently in its data item queue.
 */
- (void)persistDataItemQueue;

/**
 *  Adds the specified dictionary to the JSON Stream string.
 *
 *  @param dictionary the dictionary object which is to be added to the JSON Stream queue string.
 */
- (void)appendDictionaryToJsonStream:(NSDictionary *)dictionary;

/**
 *  A C function that serializes a given string to JSON and appends it to a char string
 *
 *  @param string A string which will be serialized to JSON and then appended to the string.
 *  @param jsonStream The C string which the dictionary's JSON representation will be appended to.
 */
void pres_appendStringToSafeJsonStream(NSString *string, char *__nonnull*__nonnull jsonStream);

/**
 *  Reset PRESSafeJsonEventsString so we can start appending JSON dictionaries.
 *
 *  @param jsonStream The string that will be reset.
 */
void pres_resetSafeJsonStream(char *__nonnull*__nonnull jsonStream);

/**
 *  A method which indicates whether the telemetry pipeline is busy and no new data should be enqueued.
 *  Currently, we drop telemetry data if this returns YES.
 *  This depends on defaultMaxBatchCount and defaultBatchInterval.
 *
 *  @return Returns yes if currently no new data should be enqueued on the channel.
 */
- (BOOL)isQueueBusy;

@end

NS_ASSUME_NONNULL_END
