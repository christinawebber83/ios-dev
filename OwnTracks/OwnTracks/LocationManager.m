//
//  LocationManager.m
//  OwnTracks
//
//  Created by Christoph Krey on 21.10.14.
//  Copyright (c) 2014-2015 OwnTracks. All rights reserved.
//

#import "LocationManager.h"
#import "AlertView.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>

@interface LocationManager()
@property (strong, nonatomic) CLLocationManager *manager;
@property (strong, nonatomic) CMAltimeter *altimeter;
@property (strong, nonatomic) CLLocation *lastUsedLocation;
@property (strong, nonatomic) NSTimer *activityTimer;
@property (strong, nonatomic) NSMutableSet *pendingRegionEvents;
- (void)holdDownExpired:(NSTimer *)timer;
@property (strong, nonatomic) NSMutableDictionary *insideBeaconRegions;
@property (strong, nonatomic) NSMutableDictionary *insideCircularRegions;
@property (strong, nonatomic) NSMutableArray *rangedBeacons;
@end

@interface PendingRegionEvent : NSObject
@property (strong, nonatomic) CLRegion *region;
@property (strong, nonatomic) NSTimer *holdDownTimer;

@end

@implementation PendingRegionEvent

+ (PendingRegionEvent *)holdDown:(CLRegion *)region for:(NSTimeInterval)interval to:(id)to{
    PendingRegionEvent *p = [[PendingRegionEvent alloc] init];
    p.region = region;
    p.holdDownTimer = [NSTimer timerWithTimeInterval:interval
                                              target:to
                                            selector:@selector(holdDownExpired:)
                                            userInfo:p
                                             repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:p.holdDownTimer forMode:NSRunLoopCommonModes];
    return p;
}

@end

@implementation LocationManager
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
static LocationManager *theInstance = nil;

+ (LocationManager *)sharedInstance {
    if (theInstance == nil) {
        theInstance = [[LocationManager alloc] init];
    }
    return theInstance;
}

- (id)init {
    self = [super init];

    self.manager = [[CLLocationManager alloc] init];
    self.manager.delegate = self;
    self.insideBeaconRegions = [[NSMutableDictionary alloc] init];
    self.insideCircularRegions = [[NSMutableDictionary alloc] init];
    self.rangedBeacons = [[NSMutableArray alloc] init];
    self.lastUsedLocation = [[CLLocation alloc] initWithLatitude:0 longitude:0];
    self.pendingRegionEvents = [[NSMutableSet alloc] init];
    [self authorize];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil queue:nil usingBlock:^(NSNotification *note){
                                                          DDLogVerbose(@"UIApplicationWillEnterForegroundNotification");
                                                          //
                                                      }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:nil usingBlock:^(NSNotification *note){
                                                          DDLogVerbose(@"UIApplicationDidBecomeActiveNotification");
                                                          [self wakeup];
                                                      }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                      object:nil queue:nil usingBlock:^(NSNotification *note){
                                                          DDLogVerbose(@"UIApplicationWillResignActiveNotification");
                                                          [self sleep];
                                                      }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification
                                                      object:nil queue:nil usingBlock:^(NSNotification *note){
                                                          DDLogVerbose(@"UIApplicationWillTerminateNotification");
                                                          [self stop];
                                                      }];
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
        self.altimeter = [[CMAltimeter alloc] init];
    }

    return self;
}

- (void)start {
    DDLogVerbose(@"start");
    [self authorize];
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
        if ([CMAltimeter isRelativeAltitudeAvailable]) {
            DDLogVerbose(@"startRelativeAltitudeUpdatesToQueue");
            [self.altimeter startRelativeAltitudeUpdatesToQueue:[NSOperationQueue mainQueue]
                                                    withHandler:^(CMAltitudeData *altitudeData, NSError *error) {
                                                        DDLogVerbose(@"altitudeData %@", altitudeData);
                                                        self.altitude = altitudeData;
                                                    }];
        }
    }
}

- (void)wakeup {
    DDLogVerbose(@"wakeup");
    [self authorize];
    if (self.monitoring == LocationMonitoringMove) {
        [self.activityTimer invalidate];
        self.activityTimer = [NSTimer timerWithTimeInterval:self.minTime target:self selector:@selector(activityTimer:) userInfo:Nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.activityTimer forMode:NSRunLoopCommonModes];
    }
    for (CLRegion *region in self.manager.monitoredRegions) {
        DDLogVerbose(@"requestStateForRegion %@", region.identifier);
        [self.manager requestStateForRegion:region];
    }
}

- (void)authorize {
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    DDLogVerbose(@"authorizationStatus=%d", status);
    if (status == kCLAuthorizationStatusNotDetermined) {
        DDLogVerbose(@"systemVersion=%@", [[UIDevice currentDevice] systemVersion]);
        if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
            [self.manager requestAlwaysAuthorization];
        }
    }
}

- (void)sleep {
    DDLogVerbose(@"sleep");
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending) {
        for (CLBeaconRegion *beaconRegion in self.manager.rangedRegions) {
            [self.manager stopRangingBeaconsInRegion:beaconRegion];
        }
    }
    [self.activityTimer invalidate];
}

- (void)stop {
    DDLogVerbose(@"stop");
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0"] != NSOrderedAscending) {
        if ([CMAltimeter isRelativeAltitudeAvailable]) {
            DDLogVerbose(@"stopRelativeAltitudeUpdates");
            [self.altimeter stopRelativeAltitudeUpdates];
        }
    }
}

- (void)startRegion:(CLRegion *)region {
    if (region) {
        [self.manager startMonitoringForRegion:region];
    }
}

- (void)stopRegion:(CLRegion *)region {
    if (region) {
        [self removeHoldDown:region];
        [self.manager stopMonitoringForRegion:region];
        [self.insideBeaconRegions removeObjectForKey:region.identifier];
        [self.insideCircularRegions removeObjectForKey:region.identifier];
    }
}

- (void)resetRegions {
    for (CLRegion *region in self.manager.monitoredRegions) {
        [self stopRegion:region];
    }
}

- (BOOL)insideBeaconRegion {
    return (self.insideBeaconRegions.count != 0);
}

- (BOOL)insideBeaconRegion:(NSString *)identifier {
    NSNumber *number = [self.insideBeaconRegions objectForKey:identifier];
    return (number ? [number boolValue] : false);
}

- (BOOL)insideCircularRegion {
    return (self.insideCircularRegions.count != 0);
}

- (BOOL)insideCircularRegion:(NSString *)identifier {
    NSNumber *number = [self.insideCircularRegions objectForKey:identifier];
    return (number ? [number boolValue] : false);
}

- (CLLocation *)location {
    if (self.manager.location) {
        self.lastUsedLocation = self.manager.location;
    } else {
        DDLogVerbose(@"location == nil");
        CLSLog(@"location == nil");
    }
    return self.lastUsedLocation;
}

- (void)setMinDist:(double)minDist {
    _minDist = minDist;
    self.monitoring = self.monitoring;
}

- (void)setMinTime:(double)minTime {
    _minTime = minTime;
    self.monitoring = self.monitoring;
}

- (void)setMonitoring:(LocationMonitoring)monitoring {
    DDLogVerbose(@"monitoring=%ld", (long)monitoring);
    _monitoring = monitoring;
    self.manager.pausesLocationUpdatesAutomatically = NO;
    if ([[[UIDevice currentDevice] systemVersion] compare:@"9.0"] != NSOrderedAscending) {
        self.manager.allowsBackgroundLocationUpdates = TRUE;
    }

    switch (monitoring) {
        case LocationMonitoringMove:
            self.manager.distanceFilter = self.minDist;
            self.manager.desiredAccuracy = kCLLocationAccuracyBest;
            [self.manager stopMonitoringSignificantLocationChanges];
            [self.activityTimer invalidate];
            
            [self.manager startUpdatingLocation];
            self.activityTimer = [NSTimer timerWithTimeInterval:self.minTime target:self selector:@selector(activityTimer:) userInfo:Nil repeats:YES];
            [[NSRunLoop currentRunLoop] addTimer:self.activityTimer forMode:NSRunLoopCommonModes];
            break;
        case LocationMonitoringSignificant:
            [self.activityTimer invalidate];
            [self.manager stopUpdatingLocation];
            [self.manager startMonitoringSignificantLocationChanges];
            break;
        case LocationMonitoringManual:
        case LocationMonitoringQuiet:
        default:
            [self.activityTimer invalidate];
            [self.manager stopUpdatingLocation];
            [self.manager stopMonitoringSignificantLocationChanges];
            break;
    }
}

- (void)setRanging:(BOOL)ranging
{
    DDLogVerbose(@"ranging=%d", ranging);
    _ranging = ranging;
    
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0"] != NSOrderedAscending) {
        if (!ranging) {
            for (CLBeaconRegion *beaconRegion in self.manager.rangedRegions) {
                DDLogVerbose(@"stopRangingBeaconsInRegion %@", beaconRegion.identifier);
                [self.manager stopRangingBeaconsInRegion:beaconRegion];
            }
        }
    }
    for (CLRegion *region in self.manager.monitoredRegions) {
        DDLogVerbose(@"requestStateForRegion %@", region.identifier);
        [self.manager requestStateForRegion:region];
    }
}

- (void)activityTimer:(NSTimer *)timer {
    DDLogVerbose(@"activityTimer");
    if (self.manager.location) {
        [self.delegate timerLocation:self.manager.location];
    } else {
        DDLogWarn(@"activityTimer found no location");
    }
}


/*
 *
 * Delegate
 *
 */

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    DDLogVerbose(@"didChangeAuthorizationStatus to %d", status);
    if (status != kCLAuthorizationStatusAuthorizedAlways) {
        [self showError];
    }
}
    
- (void)showError {
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways:
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            [AlertView alert:@"LocationManager" message:@"App is not allowed to use location services in background"];
            break;
        case kCLAuthorizationStatusNotDetermined:
            [AlertView alert:@"LocationManager" message:@"App is not allowed to use location services yet"];
            break;
        case kCLAuthorizationStatusDenied:
            [AlertView alert:@"LocationManager" message:@"App is not allowed to use location services"];
            break;
        case kCLAuthorizationStatusRestricted:
            [AlertView alert:@"LocationManager" message:@"App use of location services is restricted"];
            break;
        default:
            [AlertView alert:@"LocationManager" message:@"App use of location services is unclear"];
            break;
    }
    
    if (![CLLocationManager locationServicesEnabled]) {
        [AlertView alert:@"LocationManager" message:@"Location services are not enabled"];
    }
    
    if (![CLLocationManager significantLocationChangeMonitoringAvailable]) {
        [AlertView alert:@"LocationManager" message:@"Significant location change monitoring not available"];
    }
    
    if (![CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]]) {
        [AlertView alert:@"LocationManager" message:@"Circular region monitoring not available"];
    }
    
    if (![CLLocationManager isMonitoringAvailableForClass:[CLBeaconRegion class]]) {
        [AlertView alert:@"LocationManager" message:@"iBeacon region monitoring not available"];
    }
    
    if (![CLLocationManager isRangingAvailable]) {
        [AlertView alert:@"LocationManager" message:@"iBeacon ranging not available"];
    }
    
    if (![CLLocationManager deferredLocationUpdatesAvailable]) {
        // [AlertView alert:where message:@"Deferred location updates not available"];
    }

    if (![CLLocationManager headingAvailable]) {
        // [AlertView alert:where message:@"Heading not available"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    DDLogVerbose(@"didUpdateLocations");
    
    for (CLLocation *location in locations) {
        DDLogVerbose(@"Location: %@", location);
        if ([location.timestamp compare:self.lastUsedLocation.timestamp] != NSOrderedAscending ) {
            [self.delegate newLocation:location];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    DDLogError(@"didFailWithError %@ %@", error.localizedDescription, error.userInfo);
    // error
}


/*
 *
 * Regions
 *
 */
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    DDLogVerbose(@"didDetermineState %ld %@", (long)state, region);
    
    if ([region isKindOfClass:[CLBeaconRegion class]]) {
        if (state == CLRegionStateInside) {
            [self.insideBeaconRegions setObject:[NSNumber numberWithBool:TRUE] forKey:region.identifier];
            if (self.ranging) {
                if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                    CLBeaconRegion *beaconRegion = (CLBeaconRegion *)region;
                    [self.manager startRangingBeaconsInRegion:beaconRegion];
                }
            }
        } else {
            [self.insideBeaconRegions removeObjectForKey:region.identifier];
            CLBeaconRegion *beaconRegion = (CLBeaconRegion *)region;
            [self.manager stopRangingBeaconsInRegion:beaconRegion];
        }
    }
    
    if ([region isKindOfClass:[CLCircularRegion class]]) {
        CLCircularRegion *circular = (CLCircularRegion *)region;
        DDLogVerbose(@"region lat,lon,rad %f,%f,%f",
                     circular.center.latitude,
                     circular.center.longitude,
                     circular.radius);
        DDLogVerbose(@"loc lat,lon,acc %f,%f,%f @ %@",
                     manager.location.coordinate.latitude,
                     manager.location.coordinate.longitude,
                     manager.location.horizontalAccuracy,
                     manager.location.timestamp
                     );
        switch (state) {
            case CLRegionStateInside:
                if (![circular containsCoordinate:manager.location.coordinate]) {
                    DDLogVerbose(@"didDeterminState false positive!");
                    state = CLRegionStateOutside;
                }
                break;
            case CLRegionStateOutside:
                if ([circular containsCoordinate:manager.location.coordinate]) {
                    DDLogVerbose(@"didDeterminState false negative!");
                    state = CLRegionStateInside;
                }
                break;
            case CLRegionStateUnknown:
            default:
                break;
        }
        
        if (state == CLRegionStateInside) {
            [self.insideCircularRegions setObject:[NSNumber numberWithBool:TRUE] forKey:region.identifier];
        } else {
            [self.insideCircularRegions removeObjectForKey:region.identifier];
        }
    }
    [self.delegate regionState:region inside:(state == CLRegionStateInside)];
}
     
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    DDLogVerbose(@"didEnterRegion %@", region);
    
    if ([region isKindOfClass:[CLCircularRegion class]]) {
        CLCircularRegion *circular = (CLCircularRegion *)region;
        DDLogVerbose(@"region lat,lon,rad %f,%f,%f",
                     circular.center.latitude,
                     circular.center.longitude,
                     circular.radius);
        DDLogVerbose(@"loc lat,lon,acc %f,%f,%f @ %@",
                     manager.location.coordinate.latitude,
                     manager.location.coordinate.longitude,
                     manager.location.horizontalAccuracy,
                     manager.location.timestamp
                     );
        if ([self insideCircularRegion:circular.identifier] || ![circular containsCoordinate:manager.location.coordinate]) {
            DDLogVerbose(@"didEnterRegion incorrect!");
            return;
        }
    }

    if (![self removeHoldDown:region]) {
        [self.delegate regionEvent:region enter:YES];
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
    DDLogVerbose(@"didExitRegion %@", region);
    
    if ([region isKindOfClass:[CLCircularRegion class]]) {
        CLCircularRegion *circular = (CLCircularRegion *)region;
        DDLogVerbose(@"region lat,lon,rad %f,%f,%f",
                     circular.center.latitude,
                     circular.center.longitude,
                     circular.radius);
        DDLogVerbose(@"loc lat,lon,acc %f,%f,%f @ %@",
                     manager.location.coordinate.latitude,
                     manager.location.coordinate.longitude,
                     manager.location.horizontalAccuracy,
                     manager.location.timestamp
                     );
        if (![self insideCircularRegion:circular.identifier] || [circular containsCoordinate:manager.location.coordinate]) {
            DDLogVerbose(@"didExitRegion incorrect!");
            return;
        }
    }

    if ([region.identifier hasPrefix:@"-"]) {
                [self removeHoldDown:region];
        [self.pendingRegionEvents addObject:[PendingRegionEvent holdDown:region for:3.0 to:self]];
    } else {
        [self.delegate regionEvent:region enter:NO];
    }
}

- (BOOL)removeHoldDown:(CLRegion *)region {
    DDLogVerbose(@"removeHoldDown %@ [%lu]", region.identifier, (unsigned long)self.pendingRegionEvents.count);

    for (PendingRegionEvent *p in self.pendingRegionEvents) {
        if (p.region == region) {
            DDLogVerbose(@"holdDownInvalidated %@", region.identifier);
            [p.holdDownTimer invalidate];
            p.region = nil;
            [self.pendingRegionEvents removeObject:p];
            return TRUE;
        }
    }
    return FALSE;
}

- (void)holdDownExpired:(NSTimer *)timer {
    DDLogVerbose(@"holdDownExpired %@", timer.userInfo);
    if ([timer.userInfo isKindOfClass:[PendingRegionEvent class]]) {
        PendingRegionEvent *p = (PendingRegionEvent *)timer.userInfo;
        DDLogVerbose(@"holdDownExpired %@", p.region.identifier);
        [self.delegate regionEvent:p.region enter:NO];
        [self removeHoldDown:p.region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    DDLogVerbose(@"didStartMonitoringForRegion %@", region);
    [self.manager requestStateForRegion:region];
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    DDLogVerbose(@"monitoringDidFailForRegion %@ %@ %@", region, error.localizedDescription, error.userInfo);
    for (CLRegion *monitoredRegion in manager.monitoredRegions) {
        DDLogVerbose(@"monitoredRegion: %@", monitoredRegion);
    }
    
    if ((error.domain != kCLErrorDomain || error.code != 5) && [manager.monitoredRegions containsObject:region]) {
        // error
    }

}

/*
 *
 * Beacons
 *
 */
- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error {
    DDLogVerbose(@"rangingBeaconsDidFailForRegion %@ %@ %@", region, error.localizedDescription, error.userInfo);
    // error
}

- (void)locationManager:(CLLocationManager *)manager
        didRangeBeacons:(NSArray *)beacons
               inRegion:(CLBeaconRegion *)region {
    DDLogVerbose(@"didRangeBeacons %@ %@", beacons, region);
    for (CLBeacon *beacon in beacons) {
        if (beacon.proximity != CLProximityUnknown) {
            CLBeacon *foundBeacon = nil;
            for (CLBeacon *rangedBeacon in self.rangedBeacons) {
                uuid_t rangedBeaconUUID;
                uuid_t beaconUUID;
                [rangedBeacon.proximityUUID getUUIDBytes:rangedBeaconUUID];
                [beacon.proximityUUID getUUIDBytes:beaconUUID];
                
                if (uuid_compare(rangedBeaconUUID, beaconUUID) == 0 &&
                    [rangedBeacon.major intValue] == [beacon.major intValue] &&
                    [rangedBeacon.minor intValue] == [beacon.minor intValue]) {
                    foundBeacon = rangedBeacon;
                    break;
                }
            }
            if (foundBeacon == nil) {
                [self.delegate beaconInRange:beacon region:region];
                [self.rangedBeacons addObject:beacon];
            } else {
                if (foundBeacon.proximity != beacon.proximity) {
                    [self.delegate beaconInRange:beacon region:region];
                    [self.rangedBeacons removeObject:foundBeacon];
                    [self.rangedBeacons addObject:beacon];
                }
            }
        }
    }
}

/*
 *
 * Deferred Updates
 *
 */
- (void)locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {
    //
}

- (void)locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager {
    //
}

- (void)locationManagerDidResumeLocationUpdates:(CLLocationManager *)manager {
    //
}


/*
 *
 * Heading
 *
 */
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    // we don't use heading
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
    // we don't use heading
    return false;
}

/*
 *
 * Visits
 *
 */
- (void)locationManager:(CLLocationManager *)manager didVisit:(CLVisit *)visit {
    //
}

@end

