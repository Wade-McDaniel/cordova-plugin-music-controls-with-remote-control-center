//
//  MusicControls.m
//
//
//  Created by Juan Gonzalez on 12/16/16.
//
//

@import AVFoundation;
@import Foundation;

#import "MusicControls.h"
#import "MusicControlsInfo.h"

@implementation MusicControls

NSMutableDictionary * currentNowPlayingInfo;
NSString * ___currentCoverUrl = @"";
MPMediaItemArtwork * ___currentCover;
BOOL _currentlyUpdatingMPNowPlayingInfoCenter = NO;
BOOL musicControlsEventListenerAlreadyRegistered = NO;
BOOL audioInterrupted = NO;
BOOL audioInterruptedBecauseADeviceWasDisconnected = NO;
BOOL audioInterruptedForPhoneCall = NO;
BOOL audioInterruptedForSiri = NO;
BOOL _isPlaying = NO;

- (void) pluginInitialize {
    [super pluginInitialize];
    NSLog(@"[MCF] Initializing Music Controls plugin.");
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    rcc.togglePlayPauseCommand.enabled = YES;
    rcc.previousTrackCommand.enabled = YES;
    rcc.nextTrackCommand.enabled = YES;
    rcc.changeShuffleModeCommand.enabled = YES;
    rcc.changeRepeatModeCommand.enabled = YES;

    [rcc.togglePlayPauseCommand addTarget:self action:@selector(handleCommand:)];
    [rcc.previousTrackCommand addTarget:self action:@selector(handleCommand:)];
    [rcc.nextTrackCommand addTarget:self action:@selector(handleCommand:)];
    [rcc.changeShuffleModeCommand addTarget:self action:@selector(handleCommand:)];
    [rcc.changeRepeatModeCommand addTarget:self action:@selector(handleCommand:)];

    
}

- (void) create: (CDVInvokedUrlCommand *) command {
//    NSLog(@"[MCF] Creating NowPlayingInfoCenter object.");
    if (_currentlyUpdatingMPNowPlayingInfoCenter) {
        NSLog(@"[MCF] attempted create while another was running");
        return;
    } else {
        _currentlyUpdatingMPNowPlayingInfoCenter = YES;
    }
    
    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];
    
    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }
    
    [self.commandDelegate runInBackground:^{
        MPNowPlayingInfoCenter * nowPlayingInfoCenter =  [MPNowPlayingInfoCenter defaultCenter];
        NSDictionary * nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo;
        NSMutableDictionary * updatedNowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingInfo];
        
        BOOL setIsPlaying = [musicControlsInfo isPlaying];
       
        NSNumber * duration = [NSNumber numberWithInt:[musicControlsInfo duration]];
        NSNumber * elapsed = [NSNumber numberWithFloat:[musicControlsInfo elapsed]];
        NSNumber * _queueIndex = [NSNumber numberWithInt:[musicControlsInfo playbackQueueIndex]];
        NSNumber * _queueCount = [NSNumber numberWithInt:[musicControlsInfo playbackQueueCount]];

        double playbackRate = [[NSNumber numberWithInt:(setIsPlaying ? 1 : 0)] doubleValue];
        
        if ([elapsed floatValue] < 0) {
            elapsed = [NSNumber numberWithFloat:0.0f];
        }
        
        [updatedNowPlayingInfo setObject:[musicControlsInfo artist] forKey:MPMediaItemPropertyArtist];
        [updatedNowPlayingInfo setObject:[musicControlsInfo track] forKey:MPMediaItemPropertyTitle];
        [updatedNowPlayingInfo setObject:[musicControlsInfo album] forKey:MPMediaItemPropertyAlbumTitle];
        [updatedNowPlayingInfo setObject:duration forKey:MPMediaItemPropertyPlaybackDuration];
        [updatedNowPlayingInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [updatedNowPlayingInfo setObject:@(playbackRate) forKey:MPNowPlayingInfoPropertyPlaybackRate];
        [updatedNowPlayingInfo setObject:_queueIndex forKey:MPNowPlayingInfoPropertyPlaybackQueueIndex];
        [updatedNowPlayingInfo setObject:_queueCount forKey:MPNowPlayingInfoPropertyPlaybackQueueCount];
        
//        NSLog(@"[MCF] MPNowPlayingInfoCenter.create:\n %@", updatedNowPlayingInfo);
        
        _isPlaying = [[NSNumber numberWithDouble:playbackRate] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            nowPlayingInfoCenter.nowPlayingInfo = updatedNowPlayingInfo;
            currentNowPlayingInfo = updatedNowPlayingInfo;
            _currentlyUpdatingMPNowPlayingInfoCenter = NO;
        });
        
//        NSLog(@"QUEUE POSITION: %d/%d",[queueIndex intValue], [queueCount intValue]);
        
        [self updateRemotePreviousTrack:musicControlsInfo.hasPrev];
        [self updateRemoteNextTrack:musicControlsInfo.hasNext];

        if (![___currentCoverUrl isEqualToString:[musicControlsInfo cover]]) {
            [self createCoverArtwork:[musicControlsInfo cover] onComplete:^(MPMediaItemArtwork* mediaItemArtwork) {
                [self updateArtwork:mediaItemArtwork];
            }];
        } else {
            [self updateArtwork:___currentCover];
        }

    }];
}
- (NSDictionary*) getNowPlayingInfo {
    MPNowPlayingInfoCenter * nowPlayingInfoCenter =  [MPNowPlayingInfoCenter defaultCenter];
    NSDictionary * nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo;
    return nowPlayingInfo;
}
- (void) getNowPlaying:(CDVInvokedUrlCommand *) command {
    [self.commandDelegate runInBackground:^{
        NSDictionary * nowPlayingInfo = [self getNowPlayingInfo];
        NSMutableDictionary * customNowPlayingInfo = [[NSMutableDictionary alloc] init];
        [customNowPlayingInfo removeObjectForKey:MPMediaItemPropertyArtwork];
        
        [customNowPlayingInfo setValue:[nowPlayingInfo valueForKey:@"albumTitle"] forKey:@"album"];
        [customNowPlayingInfo setValue:[nowPlayingInfo valueForKey:@"artist"] forKey:@"artist"];
        [customNowPlayingInfo setValue:[nowPlayingInfo valueForKey:@"albumTitle"] forKey:@"album"];
        [customNowPlayingInfo setValue:[nowPlayingInfo valueForKey:@"playbackDuration"] forKey:@"duration"];
        [customNowPlayingInfo setValue:[nowPlayingInfo valueForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime] forKey:@"elapsed"];
        
        double playbackRate = [[nowPlayingInfo valueForKey:MPNowPlayingInfoPropertyPlaybackRate] doubleValue];
        BOOL playing = playbackRate == 1;
        
        [customNowPlayingInfo setValue:@(playing) forKey:@"isPlaying"];

        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:customNowPlayingInfo];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];

}

-(void) updateArtwork:(MPMediaItemArtwork*)artwork {
    if (artwork == nil) {
        NSLog(@"[MCF] Artwork is nil!!");
        ___currentCover = nil;
        ___currentCoverUrl = nil;
        return;
    }
//    [self.commandDelegate runInBackground:^{
        MPNowPlayingInfoCenter * nowPlayingInfoCenter =  [MPNowPlayingInfoCenter defaultCenter];
        NSMutableDictionary * nowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingInfoCenter.nowPlayingInfo];
//        NSMutableDictionary *nowPlayingInfo = [[NSMutableDictionary alloc] init];
    
        [nowPlayingInfo setObject:artwork forKey:MPMediaItemPropertyArtwork];
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo;
//    }];
    
}

- (void) updateRemotePreviousTrack: (bool)enabled {
//    NSLog (@">>>>>>>>>>>Setting previous track control to %@",enabled ? @"ENABLED" : @"DISABLED");
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    rcc.previousTrackCommand.enabled = enabled;
}

- (void) updateRemoteNextTrack: (bool)enabled {
//    NSLog (@">>>>>>>>>>>Setting next track control to %@",enabled ? @"ENABLED" : @"DISABLED");
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    rcc.nextTrackCommand.enabled = enabled;
}

- (MPRemoteCommandHandlerStatus) handleCommand: (MPRemoteCommandEvent*) event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (void) updateIsPlaying: (CDVInvokedUrlCommand *) command {
    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];
    NSNumber * playbackRate = [NSNumber numberWithBool:[musicControlsInfo isPlaying]];
    
    _isPlaying = [playbackRate boolValue];
    
    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }
    
    MPNowPlayingInfoCenter * nowPlayingCenter = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary * updatedNowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingCenter.nowPlayingInfo];
    
    [updatedNowPlayingInfo setObject:playbackRate forKey:MPNowPlayingInfoPropertyPlaybackRate];
    nowPlayingCenter.nowPlayingInfo = updatedNowPlayingInfo;
}

- (void) destroy: (CDVInvokedUrlCommand *) command {
    [self deregisterMusicControlsEventListener];
}

- (void) watch: (CDVInvokedUrlCommand *) command {
    [self setLatestEventCallbackId:command.callbackId];
    [self registerMusicControlsEventListener];
}

- (MPMediaItemArtwork *) createCoverArtwork: (NSString *) coverUri {
    UIImage * coverImage = nil;
    
    if (coverUri == nil) {
        return nil;
    }
    
    if ([coverUri hasPrefix:@"http://"] || [coverUri hasPrefix:@"https://"]) {
        NSURL * coverImageUrl = [NSURL URLWithString:coverUri];
        NSData * coverImageData = [NSData dataWithContentsOfURL: coverImageUrl];
        
        coverImage = [UIImage imageWithData: coverImageData];
    }
    else if ([coverUri hasPrefix:@"file://"]) {
        NSString * fullCoverImagePath = [coverUri stringByReplacingOccurrencesOfString:@"file://" withString:@""];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath: fullCoverImagePath]) {
            coverImage = [[UIImage alloc] initWithContentsOfFile: fullCoverImagePath];
        }
    }
    else if (![coverUri isEqual:@""]) {
        NSString * baseCoverImagePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString * fullCoverImagePath = [NSString stringWithFormat:@"%@%@", baseCoverImagePath, coverUri];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullCoverImagePath]) {
            coverImage = [UIImage imageNamed:fullCoverImagePath];
        }
    }
    else {
        coverImage = [UIImage imageNamed:@"none"];
    }
    
    MPMediaItemArtwork* mediaItemCoverImage = [[MPMediaItemArtwork alloc] initWithImage:coverImage];
    ___currentCoverUrl = coverUri;
    ___currentCover = mediaItemCoverImage;

    return [self isCoverImageValid:coverImage] ? mediaItemCoverImage : nil;
}

- (bool) isCoverImageValid: (UIImage *) coverImage {
    return coverImage != nil && ([coverImage CIImage] != nil || [coverImage CGImage] != nil);
}
- (void) createCoverArtwork: (NSString *) coverUri onComplete:(void(^)(MPMediaItemArtwork*))handler {
    ___currentCoverUrl = coverUri;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MPMediaItemArtwork * item = [self createCoverArtwork:coverUri];
        
        ___currentCover = item;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) {
                handler(item);
            }
        });
    });
}

- (void) handleMusicControlsNotification: (NSNotification *) notification {
    UIEvent * receivedEvent = notification.object;
    
    if ([self latestEventCallbackId] == nil) {
        return;
    }
    NSString * action;
    
    if (notification.name == AVAudioSessionInterruptionNotification) {
        NSLog(@"[MCF] Handling a session interruption notification");
        action = [self handleSessionInterruption:notification];
    } else if (notification.name == AVAudioSessionRouteChangeNotification) {
        NSLog(@"[MCF] Handling a route change notification");
        action = [self handleRouteChange:notification];
    } else if (notification.name == AVAudioSessionSilenceSecondaryAudioHintNotification) {
        NSLog(@"[MCF] Handling a silence secondary audio hint notification");
        action = [self handleSecondaryAudio:notification];
    } else if (notification.name == AVAudioSessionMediaServicesWereResetNotification) {
        NSLog(@"[MCF] Handling a media services reset notification");
    } else if ([notification.name  isEqual: @"CDVSoundObjectAudioReadyToPlay"]) {
        action = @"cdv-sound-object-audio-ready-to-play";
    } else if (receivedEvent.type == UIEventTypeRemoteControl) {
        NSLog(@"[MCF] Handling a Remote Control notification");

        audioInterrupted = NO;
        audioInterruptedBecauseADeviceWasDisconnected = NO;
        audioInterruptedForPhoneCall = NO;
        audioInterruptedForSiri = NO;

        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                action = @"music-controls-toggle-play-pause";
                break;
                
            case UIEventSubtypeRemoteControlPlay:
                action = @"music-controls-play";
                break;
                
            case UIEventSubtypeRemoteControlPause:
                action = @"music-controls-pause";
                break;
                
            case UIEventSubtypeRemoteControlPreviousTrack:
                action = @"music-controls-previous";
                break;
                
            case UIEventSubtypeRemoteControlNextTrack:
                action = @"music-controls-next";
                break;
                
            case UIEventSubtypeRemoteControlStop:
                action = @"music-controls-destroy";
                break;
                
            default:
                break;
      }
    }
    
    if (![action isEqualToString:@""] && action != nil) {
//        NSLog(@"[MCF] %@",action);
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:action];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    }

}

- (NSString*) handleSessionInterruption: (NSNotification *) notification{
    NSString * returnValue;
//    NSDictionary *nowPlayingInfo = [self getNowPlayingInfo];
//    NSNumber *playbackRate = [nowPlayingInfo valueForKey:MPNowPlayingInfoPropertyPlaybackRate];
    
//    BOOL isPlaying = [playbackRate intValue];
//    NSLog(@"Playback rate = %f or %g or %d", [playbackRate floatValue], [playbackRate doubleValue], [playbackRate intValue]);
//    NSLog(@"isPlaying is listed as %s while _isPlaying is listed as %s",
//          isPlaying ? "YES" : "NO", _isPlaying ? "YES" : "NO");
// Since, for some reason, the explicitly set _isPlaying is a better indicator of the music playing than the MPNowPlayingInfoCentre itself, we'll just use that to determine if the music is still playing.

    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        NSNumber* reason = [notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey];
        NSLog(@"[MCF] Interruption notification - %@", reason);
        if ([reason isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
            if (_isPlaying) audioInterrupted = YES;
            if (audioInterrupted == YES) {
                NSLog(@"[MCF] Interruption has begun so I guess I should pause the music.");
                [self sendEventToApp:@"mcfinterruptpause"];
                returnValue = @"music-controls-pause";
            } else {
                returnValue = @"";
            }
        } else if ([reason isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded]]) {
            NSNumber* options = [notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey];
            NSLog(@"[MCF]  AVAudioSessionInterruptionOptionKey says %d",[options intValue]);
            if ([options isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionOptionShouldResume]]) {
                [self sendEventToApp:@"mcfinterruptionoptionshouldresume"];
            }
            if (audioInterrupted && (audioInterruptedForPhoneCall || audioInterruptedBecauseADeviceWasDisconnected)) {
                audioInterrupted = audioInterruptedForPhoneCall = audioInterruptedBecauseADeviceWasDisconnected = NO;
                NSLog(@"[MCF] Interruption ended so I guess I should restart the song...");
                [self sendEventToApp:@"mcfinterruptplay"];
                returnValue = @"music-controls-play";
            } else {
                returnValue = @"";
            }
        }
    }
    
    if (returnValue == nil)
        NSLog(@"[MCF] I got to the end without anything to return?!");
    return returnValue;
}
- (NSString*) handleRouteChange:(NSNotification*) notification {
    NSString* returnValue;

    NSDictionary *nowPlayingInfo = [self getNowPlayingInfo];
    BOOL isPlaying = [[nowPlayingInfo valueForKey:MPNowPlayingInfoPropertyPlaybackRate] intValue] > 0;

    if ([notification.name isEqualToString:AVAudioSessionRouteChangeNotification]) {
        NSNumber* reason = [notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey];
        NSLog(@"[MCF] Route change notification - %@", reason);
        if ([reason isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionRouteChangeReasonCategoryChange]]) {
            if (audioInterruptedForPhoneCall) {
//                audioInterruptedForPhoneCall = NO;
//                NSLog(@"[MCF] Category change route change after audioInterruptedForPhoneCall");
//                returnValue = @"";
            } else {
                audioInterruptedForPhoneCall = isPlaying || audioInterrupted;
                if (audioInterruptedForPhoneCall) {
                    NSLog(@"[MCF] I should be stopping sound because a phone call has started.");
                    [self sendEventToApp:@"mcfroutepausephone"];
                }
//                returnValue = @"";
            }
        } else if ([reason isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionRouteChangeReasonRouteConfigurationChange]]) {
            if (audioInterruptedForSiri) {
//                audioInterruptedForSiri = NO;
//                NSLog(@"[MCF] Category change route change after audioInterruptedForSiri.");
//                returnValue = @"";
            } else {
                audioInterruptedForSiri = isPlaying || audioInterrupted;
                if (audioInterruptedForSiri) {
                    NSLog(@"[MCF] I should be stopping sound because Siri has been activated.");
                }
//                returnValue = @"";
            }
        } else if ([reason intValue] == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
            audioInterruptedBecauseADeviceWasDisconnected = isPlaying;
//            if (audioInterruptedBecauseADeviceWasDisconnected) {
                NSLog(@"[MCF] I should be stopping sound because a device was disconnected.");
                returnValue = @"music-controls-pause";
             [self sendEventToApp:@"mcfroutepausedevice"];
//            }
        } else if ([reason intValue] == AVAudioSessionRouteChangeReasonNewDeviceAvailable) {
            if (audioInterruptedBecauseADeviceWasDisconnected) {
                audioInterruptedBecauseADeviceWasDisconnected = NO;
                NSLog(@"[MCF] I guess I should restart the music since a new device was connected?");
                returnValue = @"music-controls-play";
                 [self sendEventToApp:@"mcfrouteplaydevice"];
            }
        }
    }
    
    [self.commandDelegate evalJs:[NSString stringWithFormat:@"window.ev = new Event('mcfroutechange%d');document.dispatchEvent(ev);",[[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue]]];

    return returnValue;

}

- (NSString*) handleSecondaryAudio:(NSNotification*) notification {
    #pragma mark This only happens when this app steals the audio from another app
    NSDictionary * userInfo = notification.userInfo;
    NSLog(@"%@",userInfo);
    [self sendEventToApp:@"mcfsecondaryaudio"];
    return @"";
}

- (void) sendConsoleLogToApp:(NSString*)message {
    NSString *js = [NSString stringWithFormat:@"console.log('%@')",message];
    [self.commandDelegate evalJs:js];
}
- (void) sendEventToApp:(NSString*)message {
    // [self.commandDelegate evalJs:[NSString stringWithFormat:@"setTimeout(function(){window.ev = new Event('%@');document.dispatchEvent(ev);},0);",message]];
}

- (void) registerMusicControlsEventListener {
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    NSNotificationCenter * notesMagotes = [NSNotificationCenter defaultCenter];
    if (!musicControlsEventListenerAlreadyRegistered) {
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:@"musicControlsEventNotification"
                           object:nil];
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:AVAudioSessionInterruptionNotification
                           object:nil];
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:AVAudioSessionRouteChangeNotification
                           object:nil];
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:AVAudioSessionSilenceSecondaryAudioHintNotification
                           object:nil];
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:AVAudioSessionMediaServicesWereResetNotification
                           object:nil];
        [notesMagotes addObserver:self
                         selector:@selector(handleMusicControlsNotification:)
                             name:@"CDVSoundObjectAudioReadyToPlay"
                           object:nil];

        NSLog(@"[MCF] Registered music controls listener.");
        musicControlsEventListenerAlreadyRegistered = YES;
    } else {
//        NSLog(@"[MCF] Already registered music controls listener.");
    }
}

- (void) deregisterMusicControlsEventListener {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
    [self setLatestEventCallbackId:nil];
    NSLog(@"[MCF] De-registered music controls listener.");
    musicControlsEventListenerAlreadyRegistered = NO;
}

- (void) dealloc {
    [self deregisterMusicControlsEventListener];
}


@end
