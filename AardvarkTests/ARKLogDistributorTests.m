//
//  ARKLogDistributorTests.m
//  Aardvark
//
//  Created by Dan Federman on 10/5/14.
//  Copyright 2014 Square, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <XCTest/XCTest.h>

#import "ARKLogDistributor.h"
#import "ARKLogDistributor_Protected.h"
#import "ARKLogDistributor_Testing.h"

#import "ARKDataArchive.h"
#import "ARKDataArchive_Testing.h"
#import "ARKLogMessage.h"
#import "ARKLogObserver.h"
#import "ARKLogStore.h"
#import "ARKLogStore_Testing.h"


@interface ARKLogDistributorTests : XCTestCase

@property (nonatomic, weak) ARKLogStore *logStore;

@end


typedef void (^LogHandlingBlock)(ARKLogMessage *logMessage);


@interface ARKTestLogObserver : NSObject <ARKLogObserver>

@property (nonatomic, copy) NSMutableArray *observedLogs;

@end


@implementation ARKTestLogObserver

@synthesize logDistributor;

- (instancetype)init;
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _observedLogs = [NSMutableArray new];
    
    return self;
}

- (void)observeLogMessage:(ARKLogMessage *)logMessage;
{
    [self.observedLogs addObject:logMessage];
}

@end


@interface ARKLogMessageTestSubclass : ARKLogMessage
@end

@implementation ARKLogMessageTestSubclass
@end


@implementation ARKLogDistributorTests

#pragma mark - Setup

- (void)setUp;
{
    [super setUp];
    
    ARKLogStore *logStore = [[ARKLogStore alloc] initWithPersistedLogFileName:NSStringFromClass([self class])];
    [logStore clearLogsWithCompletionHandler:NULL];
    [logStore.dataArchive waitUntilAllOperationsAreFinished];
    
    [ARKLogDistributor defaultDistributor].defaultLogStore = logStore;
    
    self.logStore = logStore;
}

- (void)tearDown;
{
    [[ARKLogDistributor defaultDistributor] waitUntilAllPendingLogsHaveBeenDistributed];
    
    [ARKLogDistributor defaultDistributor].defaultLogStore = nil;
    [ARKLogDistributor defaultDistributor].logMessageClass = [ARKLogMessage class];
    
    [super tearDown];
}

#pragma mark - Behavior Tests

- (void)test_logMessageClass_defaultsToARKLogMessage;
{
    [[ARKLogDistributor defaultDistributor] logWithFormat:@"This log should be an ARKLogMessage"];
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [self.logStore retrieveAllLogMessagesWithCompletionHandler:^(NSArray *logMessages) {
        XCTAssertEqual(logMessages.count, 1);
        XCTAssertEqual([logMessages.firstObject class], [ARKLogMessage class]);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setLogMessageClass_appendedLogsAreCorrectClass;
{
    [ARKLogDistributor defaultDistributor].logMessageClass = [ARKLogMessageTestSubclass class];
    [[ARKLogDistributor defaultDistributor] logWithFormat:@"This log should be an ARKLogMessageTestSubclass"];
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [self.logStore retrieveAllLogMessagesWithCompletionHandler:^(NSArray *logMessages) {
        XCTAssertEqual(logMessages.count, 1);
        XCTAssertEqual([logMessages.firstObject class], [ARKLogMessageTestSubclass class]);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_defaultLogStore_lazilyInitializesOnFirstAccess;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    XCTAssertNotNil(logDistributor.defaultLogStore);
    
    logDistributor.defaultLogStore = nil;
    XCTAssertNil(logDistributor.defaultLogStore, @"Default log store should not initialize itself lazily twice.");
}

- (void)test_addLogObserver_notifiesLogObserverOnARKLog;
{
    ARKTestLogObserver *testLogObserver = [ARKTestLogObserver new];
    [[ARKLogDistributor defaultDistributor] addLogObserver:testLogObserver];
    
    XCTAssertEqual(testLogObserver.observedLogs.count, 0);
    
    for (NSUInteger i  = 0; i < self.logStore.maximumLogMessageCount; i++) {
        ARKLog(@"Log %@", @(i));
    }
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [self.logStore retrieveAllLogMessagesWithCompletionHandler:^(NSArray *logMessages) {
        XCTAssertEqual(logMessages.count, self.logStore.maximumLogMessageCount);
        [logMessages enumerateObjectsUsingBlock:^(ARKLogMessage *logMessage, NSUInteger idx, BOOL *stop) {
            XCTAssertEqualObjects(logMessage, testLogObserver.observedLogs[idx]);
        }];
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    [[ARKLogDistributor defaultDistributor] removeLogObserver:testLogObserver];
}

- (void)test_addLogObserver_notifiesLogObserverOnLogWithFormat;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    
    ARKTestLogObserver *testLogObserver = [ARKTestLogObserver new];
    [logDistributor addLogObserver:testLogObserver];
    
    [logDistributor logWithFormat:@"Log"];
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [logDistributor distributeAllPendingLogsWithCompletionHandler:^{
        XCTAssertEqual(testLogObserver.observedLogs.count, 1);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_removeLogObserver_removesLogObserver;
{
    ARKLogDistributor *logDistributor = [ARKLogDistributor new];
    ARKTestLogObserver *testLogObserver = [ARKTestLogObserver new];
    
    [logDistributor addLogObserver:testLogObserver];
    
    XCTAssertEqual(logDistributor.logObservers.count, 1);
    
    [logDistributor removeLogObserver:testLogObserver];
    
    XCTAssertEqual(logDistributor.logObservers.count, 0);
    
    for (NSUInteger i  = 0; i < 100; i++) {
        [logDistributor logWithFormat:@"Log %@", @(i)];
    }
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [logDistributor distributeAllPendingLogsWithCompletionHandler:^{
        XCTAssertEqual(testLogObserver.observedLogs.count, 0);
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_distributeAllPendingLogsWithCompletionHandler_informsLogObserversOfAllPendingLogs;
{
    NSMutableSet *numbers = [NSMutableSet new];
    for (NSUInteger i  = 0; i < 100; i++) {
        [numbers addObject:[NSString stringWithFormat:@"%@", @(i)]];
    }
    
    [numbers enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString *text, BOOL *stop) {
        // Log to ARKLog, which will cause the default log distributor to queue up observeLogMessage: calls on its log observers on its background queue.
        ARKLog(@"%@", text);
    }];
    
    XCTestExpectation *expectation = [self expectationWithDescription:NSStringFromSelector(_cmd)];
    [[ARKLogDistributor defaultDistributor] distributeAllPendingLogsWithCompletionHandler:^{
        // Internal log queue should now be empty.
        XCTAssertEqual([ARKLogDistributor defaultDistributor].internalQueueOperationCount, 0);
        
        [self.logStore retrieveAllLogMessagesWithCompletionHandler:^(NSArray *logMessages) {
            NSMutableSet *allLogText = [NSMutableSet new];
            for (ARKLogMessage *logMessage in logMessages) {
                [allLogText addObject:logMessage.text];
            }
            
            // allLogText should contain the same content as the original log set.
            XCTAssertEqualObjects(allLogText, numbers);
            
            [expectation fulfill];
        }];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#pragma mark - Performance Tests

- (void)test_logDistribution_performance;
{
    NSMutableArray *numbers = [NSMutableArray new];
    for (NSUInteger i  = 0; i < 3 * self.logStore.maximumLogMessageCount; i++) {
        [numbers addObject:[NSString stringWithFormat:@"%@", @(i)]];
    }
    
    [self measureBlock:^{
        // Concurrently add all of the logs.
        [numbers enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSString *text, NSUInteger idx, BOOL *stop) {
            [[ARKLogDistributor defaultDistributor] logWithFormat:@"%@", text];
        }];
    }];
}

@end
