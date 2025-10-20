#import "WifiWizard2.h"
#include <ifaddrs.h>
#import <net/if.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>
#import <CoreLocation/CoreLocation.h>

@implementation WifiWizard2

- (void)fetchSSIDInfo:(void (^)(NSDictionary *networkInfo))completion {
    if (@available(iOS 15.0, *)) {
        NSLog(@"Using NEHotspotNetwork API for iOS 15+");
        [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
            if (currentNetwork) {
                NSLog(@"Current network SSID: %@", currentNetwork.SSID);
                NSLog(@"Current network BSSID: %@", currentNetwork.BSSID);
                
                NSDictionary *networkInfo = @{
                    (id)kCNNetworkInfoKeySSID: currentNetwork.SSID ?: @"",
                    (id)kCNNetworkInfoKeyBSSID: currentNetwork.BSSID ?: @""
                };
                completion(networkInfo);
            } else {
                NSLog(@"No current network found");
                completion(nil);
            }
        }];
    } else {
        NSLog(@"Using legacy CNCopyCurrentNetworkInfo for iOS < 15");
        NSArray *ifs = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
        NSLog(@"Supported interfaces: %@", ifs);
        
        for (NSString *ifnam in ifs) {
            NSDictionary *info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
            NSLog(@"%@ => %@", ifnam, info);
            if (info && [info count]) {
                completion(info);
                return;
            }
        }
        completion(nil);
    }
}

- (BOOL) isWiFiEnabled {
    // see http://www.enigmaticape.com/blog/determine-wifi-enabled-ios-one-weird-trick
    NSCountedSet * cset = [NSCountedSet new];

    struct ifaddrs *interfaces = NULL;
    // retrieve the current interfaces - returns 0 on success
    int success = getifaddrs(&interfaces);
    if(success == 0){
        for( struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
            if ( (interface->ifa_flags & IFF_UP) == IFF_UP ) {
                [cset addObject:[NSString stringWithUTF8String:interface->ifa_name]];
            }
        }
    }

    return [cset countForObject:@"awdl0"] > 1 ? YES : NO;
}

- (void)iOSConnectNetwork:(CDVInvokedUrlCommand*)command {
    __block CDVPluginResult *pluginResult = nil;
    
    NSDictionary* options = [command argumentAtIndex:0];
    NSString *ssidString = [options objectForKey:@"Ssid"];
    NSString *passwordString = [options objectForKey:@"Password"];
    
    if (@available(iOS 11.0, *)) {
        if (ssidString && [ssidString length]) {
            NEHotspotConfiguration *configuration = [[NEHotspotConfiguration alloc]
                                                      initWithSSID:ssidString
                                                      passphrase:passwordString
                                                      isWEP:NO];
            
            configuration.joinOnce = NO;
            
            [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration
                                                            completionHandler:^(NSError * _Nullable error) {
                
                if (error) {
                    NSLog(@"NEHotspotConfiguration error: %@", error);
                    NSLog(@"Error code: %ld", (long)error.code);
                    NSLog(@"Error domain: %@", error.domain);
                    
                    if (error.code == NEHotspotConfigurationErrorAlreadyAssociated) {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:ssidString];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                    else if (error.code == NEHotspotConfigurationErrorUserDenied) {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"failed to get user's approval."];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                    else {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:error.localizedDescription];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                } else {
                    [self fetchSSIDInfo:^(NSDictionary *networkInfo) {
                        NSString *currentSSID = [networkInfo objectForKey:(id)kCNNetworkInfoKeySSID];
                        NSLog(@"Current SSID after connection: %@", currentSSID ? currentSSID : @"nil");
                        
                        if ([currentSSID isEqualToString:ssidString]) {
                            NSLog(@"Successfully connected to SSID: %@", currentSSID);
                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsString:currentSSID];
                        } else {
                            NSLog(@"Current SSID doesn't match target");
                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:@"Failed to connect to specified network"];
                        }
                        
                        [self.commandDelegate sendPluginResult:pluginResult
                                                    callbackId:command.callbackId];
                    }];
                }
            }];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                          messageAsString:@"SSID Not provided"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                      messageAsString:@"iOS 11+ not available"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)iOSConnectOpenNetwork:(CDVInvokedUrlCommand*)command {
    __block CDVPluginResult *pluginResult = nil;
    
    NSDictionary* options = [command argumentAtIndex:0];
    NSString *ssidString = [options objectForKey:@"Ssid"];
    
    if (@available(iOS 11.0, *)) {
        if (ssidString && [ssidString length]) {
            NEHotspotConfiguration *configuration = [[NEHotspotConfiguration alloc] initWithSSID:ssidString];
            
            configuration.joinOnce = NO;
            
            [[NEHotspotConfigurationManager sharedManager] applyConfiguration:configuration
                                                            completionHandler:^(NSError * _Nullable error) {
                
                if (error) {
                    NSLog(@"NEHotspotConfiguration error (open network): %@", error);
                    NSLog(@"Error code: %ld", (long)error.code);
                    NSLog(@"Error domain: %@", error.domain);
                    
                    if (error.code == NEHotspotConfigurationErrorAlreadyAssociated) {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:ssidString];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                    else if (error.code == NEHotspotConfigurationErrorUserDenied) {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"failed to get user's approval."];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                    else {
                        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:error.localizedDescription];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                } else {
                    [self fetchSSIDInfo:^(NSDictionary *networkInfo) {
                        NSString *currentSSID = [networkInfo objectForKey:(id)kCNNetworkInfoKeySSID];
                        NSLog(@"Current SSID after open network connection: %@", currentSSID ? currentSSID : @"nil");
                        
                        if ([currentSSID isEqualToString:ssidString]) {
                            NSLog(@"Successfully connected to open network SSID: %@", currentSSID);
                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsString:currentSSID];
                        } else {
                            NSLog(@"Current SSID doesn't match target");
                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:@"Failed to connect to specified network"];
                        }
                        
                        [self.commandDelegate sendPluginResult:pluginResult
                                                    callbackId:command.callbackId];
                    }];
                }
            }];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                          messageAsString:@"SSID Not provided"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                      messageAsString:@"iOS 11+ not available"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)iOSDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    NSString * ssidString;
    NSDictionary* options = [[NSDictionary alloc]init];

    options = [command argumentAtIndex:0];
    ssidString = [options objectForKey:@"Ssid"];

    if (@available(iOS 11.0, *)) {
        if (ssidString && [ssidString length]) {
            [[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:ssidString];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssidString];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not provided"];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"iOS 11+ not available"];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getConnectedSSID:(CDVInvokedUrlCommand*)command {
    NSLog(@"=== getConnectedSSID called ===");
    
    if (@available(iOS 14.0, *)) {
        CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        NSLog(@"Location authorization status: %d", (int)status);
        
        switch(status) {
            case kCLAuthorizationStatusNotDetermined:
                NSLog(@"Location status: Not Determined");
                break;
            case kCLAuthorizationStatusRestricted:
                NSLog(@"Location status: Restricted");
                break;
            case kCLAuthorizationStatusDenied:
                NSLog(@"Location status: Denied");
                break;
            case kCLAuthorizationStatusAuthorizedAlways:
                NSLog(@"Location status: Authorized Always");
                break;
            case kCLAuthorizationStatusAuthorizedWhenInUse:
                NSLog(@"Location status: Authorized When In Use");
                break;
            default:
                NSLog(@"Location status: Unknown");
                break;
        }
    }
    
    [self fetchSSIDInfo:^(NSDictionary *networkInfo) {
        CDVPluginResult *pluginResult = nil;
        
        NSString *ssid = [networkInfo objectForKey:(id)kCNNetworkInfoKeySSID];
        NSLog(@"SSID extracted: %@", ssid ? ssid : @"nil");
        
        if (ssid && [ssid length]) {
            NSLog(@"SSID length: %lu", (unsigned long)[ssid length]);
            NSLog(@"Returning success with SSID: %@", ssid);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ssid];
        } else {
            NSLog(@"Returning error - SSID not available");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SSID Not available"];
        }
        
        NSLog(@"Sending plugin result...");
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }];
}

- (void)getConnectedBSSID:(CDVInvokedUrlCommand*)command {
    [self fetchSSIDInfo:^(NSDictionary *networkInfo) {
        CDVPluginResult *pluginResult = nil;
        
        NSString *bssid = [networkInfo objectForKey:(id)kCNNetworkInfoKeyBSSID];
        NSLog(@"BSSID extracted: %@", bssid ? bssid : @"nil");
        
        if (bssid && [bssid length]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:bssid];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"BSSID Not available"];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }];
}

- (void)isWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    NSString *isWifiOn = [self isWiFiEnabled] ? @"1" : @"0";

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:isWifiOn];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)setWifiEnabled:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

// Android functions

- (void)addNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)removeNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidConnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)androidDisconnectNetwork:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)listNetworks:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getScanResults:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)startScan:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)disconnect:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)isConnectedToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToInternet:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canPingWifiRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)canConnectToRouter:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not supported"];
    
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}


@end
