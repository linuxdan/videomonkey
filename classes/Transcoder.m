//
//  Transcoder.m
//  VideoMonkey
//
//  Created by Chris Marrin on 11/26/08.
//  Copyright 2008 Apple. All rights reserved.
//

#import <ScriptingBridge/ScriptingBridge.h>
#import "iTunes.h"

#import "Transcoder.h"
#import "AppController.h"
#import "Command.h"
#import "DeviceController.h"

FrameSize makeFrameSize(int width, int height) { return ((uint32_t) width << 16) | ((uint32_t) height & 0xffff); }
int widthFromFrameSize(FrameSize f) { return f >> 16; }
int heightFromFrameSize(FrameSize f) { return f & 0xffff; }

@implementation TranscoderFileInfo

// General
@synthesize filename;
@synthesize format;
@synthesize duration;
@synthesize bitrate;
@synthesize isQuicktime;
@synthesize fileSize;

// Video
@synthesize videaStreamKind;
@synthesize videoTrack;
@synthesize videoLanguage;
@synthesize videoCodec;
@synthesize videoProfile;
@synthesize videoInterlaced;
@synthesize videoFrameSize;
@synthesize pixelAspectRatio;
@synthesize displayAspectRatio;
@synthesize videoFrameRate;
@synthesize videoBitrate;

// Audio
@synthesize audioStreamKind;
@synthesize audioTrack;
@synthesize audioLanguage;
@synthesize audioCodec;
@synthesize audioSampleRate;
@synthesize audioChannels;
@synthesize audioBitrate;

@end

@implementation Transcoder

-(TranscoderFileInfo*) inputFileInfo
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0]) : nil;
}

-(TranscoderFileInfo*) outputFileInfo
{
    return ([m_outputFiles count] > 0) ? ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0]) : nil;
}

// Properties
@synthesize progress = m_progress;
@synthesize enabled = m_enabled;

// Input properties
-(NSString*) inputFileName { return [self inputFileInfo].filename; }
-(NSString*) inputFormat { return [self inputFileInfo].format; }
-(double) inputDuration { return [self inputFileInfo].duration; }
-(double) inputFileSize { return [self inputFileInfo].fileSize; }
-(double) inputBitrate { return [self inputFileInfo].bitrate; }

-(NSString*) inputVideoCodec { return [self inputFileInfo].videoCodec; }
-(NSString*) inputVideoProfile { return [self inputFileInfo].videoProfile; }
-(BOOL) inputVideoInterlaced { return [self inputFileInfo].videoInterlaced; }
-(FrameSize) inputVideoFrameSize { return [self inputFileInfo].videoFrameSize; }
-(double) inputVideoAspectRatio { return [self inputFileInfo].displayAspectRatio; }
-(double) inputVideoFramerate { return [self inputFileInfo].videoFrameRate; }
-(double) inputVideoBitrate { return [self inputFileInfo].videoBitrate; }

-(NSString*) inputAudioCodec { return [self inputFileInfo].audioCodec; }
-(double) inputAudioSampleRate { return [self inputFileInfo].audioSampleRate; }
-(int) inputAudioChannels { return [self inputFileInfo].audioChannels; }
-(double) inputAudioBitrate { return [self inputFileInfo].audioBitrate; }

// Output properties
-(NSString*) outputFileName { return [self outputFileInfo].filename; }
-(void) setOutputFileName:(NSString*) filename { [self outputFileInfo].filename = filename; }
-(NSString*) outputFormat { return [self outputFileInfo].format; }
-(void) setOutputFormat:(NSString*) format { [self outputFileInfo].format = format; }
-(double) outputDuration { return [self outputFileInfo].duration; }
-(void) setOutputDuration:(double) duration { [self outputFileInfo].duration = duration; }
-(double) outputFileSize { return [self outputFileInfo].fileSize; }
-(void) setOutputFileSize:(double) fileSize { [self outputFileInfo].fileSize = fileSize; }
-(double) outputBitrate { return [self outputFileInfo].bitrate; }
-(void) setOutputBitrate:(double) bitrate { [self outputFileInfo].bitrate = bitrate; }
-(NSString*) outputVideoCodec { return [self outputFileInfo].videoCodec; }
-(void) setOutputVideoCodec:(NSString*) codec { [self outputFileInfo].videoCodec = codec; }
-(NSString*) outputVideoProfile { return [self outputFileInfo].videoProfile; }
-(void) setOutputVideoProfile:(NSString*) profile { [self outputFileInfo].videoProfile = profile; }
-(BOOL) outputVideoInterlaced { return [self outputFileInfo].videoInterlaced; }
-(void) setOutputVideoInterlaced:(BOOL) interlaced { [self outputFileInfo].videoInterlaced = interlaced; }
-(FrameSize) outputVideoFrameSize { return [self outputFileInfo].videoFrameSize; }
-(void) setOutputVideoFrameSize:(FrameSize) frameSize { [self outputFileInfo].videoFrameSize = frameSize; }
-(double) outputVideoAspectRatio { return [self outputFileInfo].displayAspectRatio; }
-(void) setOutputVideoAspectRatio:(double) aspectRatio { [self outputFileInfo].displayAspectRatio = aspectRatio; }
-(double) outputVideoFramerate { return [self outputFileInfo].videoFrameRate; }
-(void) setOutputVideoFramerate:(double) framerate { [self outputFileInfo].videoFrameRate = framerate; }
-(double) outputVideoBitrate { return [self outputFileInfo].videoBitrate; }
-(void) setOutputVideoBitrate:(double) bitrate { [self outputFileInfo].videoBitrate = bitrate; }

-(NSString*) outputAudioCodec { return [self outputFileInfo].audioCodec; }
-(void) setOutputAudioCodec:(NSString*) codec { [self outputFileInfo].audioCodec = codec; }
-(double) outputAudioSampleRate { return [self outputFileInfo].audioSampleRate; }
-(void) setOutputAudioSampleRate:(double) sampleRate { [self outputFileInfo].audioSampleRate = sampleRate; }
-(int) outputAudioChannels { return [self outputFileInfo].audioChannels; }
-(void) setOutputAudioChannels:(int) channels { [self outputFileInfo].audioChannels = channels; }
-(double) outputAudioBitrate { return [self outputFileInfo].audioBitrate; }
-(void) setOutputAudioBitrate:(double) bitrate { [self outputFileInfo].audioBitrate = bitrate; }



/*
- (void) setBitrate: (float) rate
{
    if ([m_outputFiles count] == 0)
        return;
    
    ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_bitrate = rate;
}

- (double) bitrate;
{
    double inputRate =  ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_bitrate : 100000;
    double outputRate =  ([m_outputFiles count] > 0) ? ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_bitrate : 0;
    return (outputRate > 0) ? outputRate : inputRate;
}
*/





-(BOOL) _validateInputFile: (TranscoderFileInfo*) info
{
    NSMutableString* mediainfoPath = [NSMutableString stringWithString: [[NSBundle mainBundle] resourcePath]];
    [mediainfoPath appendString:@"/bin/mediainfo"];
    
    NSMutableString* mediainfoInformPath = [NSMutableString stringWithString: @"--Inform=file://"];
    [mediainfoInformPath appendString: [[NSBundle mainBundle] resourcePath]];
    [mediainfoInformPath appendString:@"/mediainfo-inform.csv"];
    
    NSTask* task = [[NSTask alloc] init];
    NSMutableArray* args = [NSMutableArray arrayWithObjects: mediainfoInformPath, [info filename], nil];
    [task setArguments: args];
    [task setLaunchPath: mediainfoPath];
    
    NSPipe* pipe = [NSPipe pipe];
    [task setStandardOutput:[pipe fileHandleForWriting]];
    
    [task launch];
    
    [task waitUntilExit];
    
    NSString* data = [[NSString alloc] initWithData: [[pipe fileHandleForReading] availableData] encoding: NSASCIIStringEncoding];
    
    // The first line must start with "-General-" or the file is not valid
    if (![data hasPrefix: @"-General-"])
        return NO;
    
    NSArray* components = [data componentsSeparatedByString:@"\r\n"];
    
    // We always have a General line.
    NSArray* general = [[components objectAtIndex:0] componentsSeparatedByString:@","];
    if ([general count] != 6)
        return NO;
        
    [info setFormat: [general objectAtIndex:1]];
    info.isQuicktime = [[general objectAtIndex:2] isEqualToString:@"QuickTime"];
    info.duration = [[general objectAtIndex:3] doubleValue] / 1000;
    //info.bitrate = [[general objectAtIndex:4] doubleValue];
    info.fileSize = [[general objectAtIndex:5] doubleValue];

    if ([info.format length] == 0)
        return NO;
        
    // Do video if it's there
    int offset = 1;
    if ([components count] > offset && [[components objectAtIndex:offset] hasPrefix: @"-Video-"]) {
        NSArray* video = [[components objectAtIndex:offset] componentsSeparatedByString:@","];
        offset = 2;
        
        // -Video-,%StreamKindID%,%ID%,%Language%,%Format%,%Codec_Profile%,%ScanType%,%ScanOrder%,%Width%,%Height%,%PixelAspectRatio%,%DisplayAspectRatio%,%FrameRate%.%Bitrate%

        if ([video count] != 14)
            return NO;
            
        info.videaStreamKind = [[video objectAtIndex:1] intValue];
        info.videoTrack = [[video objectAtIndex:2] intValue];
        info.videoLanguage = [[video objectAtIndex:3] retain];
        info.videoCodec = [[video objectAtIndex:4] retain];
        info.videoProfile = [[video objectAtIndex:5] retain];
        info.videoInterlaced = [[video objectAtIndex:6] isEqualToString:@"Interlace"];
        FrameSize frameSize = makeFrameSize([[video objectAtIndex:8] intValue], [[video objectAtIndex:9] intValue]);
        info.videoFrameSize = frameSize;
        info.pixelAspectRatio = [[video objectAtIndex:10] doubleValue];
        info.displayAspectRatio = [[video objectAtIndex:11] doubleValue];
        info.videoFrameRate = [[video objectAtIndex:12] doubleValue];
        info.videoBitrate = [[video objectAtIndex:13] doubleValue];
        
        // standardize video codec name
        NSString* f = VC_H264;
        if ([info.videoCodec caseInsensitiveCompare:@"vc-1"] == NSOrderedSame || [info.videoCodec caseInsensitiveCompare:@"wmv3"] == NSOrderedSame)
            f = VC_WMV3;
        else if ([info.videoCodec caseInsensitiveCompare:@"avc"] == NSOrderedSame || [info.videoCodec caseInsensitiveCompare:@"avc1"] == NSOrderedSame)
            f = VC_H264;
    
        info.videoCodec = f;
    }
    
    // Do audio if it's there
    if ([components count] > offset && [[components objectAtIndex:offset] hasPrefix: @"-Audio-"]) {
        NSArray* audio = [[components objectAtIndex:offset] componentsSeparatedByString:@","];

        // -Audio-,%StreamKindID%,%ID%,%Language%,%Format%,%SamplingRate%,%Channels%,%BitRate%
        if ([audio count] != 8)
            return NO;
            
        info.audioStreamKind = [[audio objectAtIndex:1] intValue];
        info.audioTrack = [[audio objectAtIndex:2] intValue];
        info.audioLanguage = [[audio objectAtIndex:3] retain];
        info.audioCodec = [[audio objectAtIndex:4] retain];
        info.audioSampleRate = [[audio objectAtIndex:5] doubleValue];
        info.audioChannels = [[audio objectAtIndex:6] intValue];
        info.audioBitrate = [[audio objectAtIndex:7] doubleValue];
    }

    return YES;
}

static NSImage* getFileStatusImage(FileStatus status)
{
    NSString* name = nil;
    switch(status)
    {
        case FS_INVALID:    name = @"invalid";     break;
        case FS_VALID:      name = @"ready";       break;
        case FS_ENCODING:   name = @"converting";  break;
        case FS_FAILED:     name = @"error";       break;
        case FS_SUCCEEDED:  name = @"ok";          break;
    }
    
    if (!name)
        return nil;
        
    NSString* path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    return [[NSImage alloc] initWithContentsOfFile:path]; 
}

- (Transcoder*) initWithController: (AppController*) controller
{
    self = [super init];
    m_appController = controller;
    m_inputFiles = [[NSMutableArray alloc] init];
    m_outputFiles = [[NSMutableArray alloc] init];
    m_fileStatus = FS_INVALID;
    m_enabled = YES;
    m_tempAudioFileName = [[NSString stringWithFormat:@"/tmp/%p-tmpaudio.wav", self] retain];
    m_passLogFileName = [[NSString stringWithFormat:@"/tmp/%p-tmppass.log", self] retain];
    
    // init the progress indicator
    m_progressIndicator = [[NSProgressIndicator alloc] init];
    [m_progressIndicator setMinValue:0];
    [m_progressIndicator setMaxValue:1];
    [m_progressIndicator setIndeterminate: NO];
    [m_progressIndicator setBezeled: NO];
    
    // init the status image view
    m_statusImageView = [[NSImageView alloc] init];
    [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];

    return self;
}

-(void) dealloc
{
    [m_progressIndicator removeFromSuperview];
    [m_statusImageView removeFromSuperview];
    [m_progressIndicator release];
    [m_statusImageView release];
    
    [super dealloc];
}
    
- (int) addInputFile: (NSString*) filename
{
    TranscoderFileInfo* file = [[TranscoderFileInfo alloc] init];
    [file setFilename: filename];
    
    if (![self _validateInputFile: file ]) {
        [file release];
        m_fileStatus = FS_INVALID;
        m_enabled = false;
        [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
        return -1;
    }

    [m_inputFiles addObject: file];
    [file release];
    m_fileStatus = FS_VALID;
    [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
    return [m_inputFiles count] - 1;    
}

- (int) addOutputFile: (NSString*) filename
{
    TranscoderFileInfo* file = [[TranscoderFileInfo alloc] init];
    [m_outputFiles addObject: file];
    [file release];
    [file setFilename: filename];
    return [m_outputFiles count] - 1;    
}

-(void) changeOutputFileName: (NSString*) filename
{
    if ([m_outputFiles count] > 0)
        [[m_outputFiles objectAtIndex: 0] setFilename: filename];
}

-(NSValue*) progressCell
{
    return [NSValue valueWithPointer:self];
}

-(void) resetStatus
{
    // If we're enabled, set the status to FS_VALID, even if we were M_FAILED or M_INVALID.
    // This gives the encoder a chance to run, just in case we were wrong about it.
    if (m_enabled) {
        m_fileStatus = FS_VALID;
        [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
    }
}

-(NSProgressIndicator*) progressIndicator
{
    return m_progressIndicator;
}

-(NSImageView*) statusImageView
{
    return m_statusImageView;
}

-(FileStatus) inputFileStatus
{
    return m_fileStatus;
}

-(BOOL) isInputQuicktime
{
    return [[self inputFileInfo] isQuicktime];
}

-(BOOL) hasInputAudio
{
    return [[self inputFileInfo] audioSampleRate] != 0;
}

-(NSString*) tempAudioFileName
{
    return m_tempAudioFileName;
}

-(NSString*) passLogFileName
{
    return m_passLogFileName;
}

-(NSString*) audioQuality
{
    return m_audioQuality;
}

-(void) setParams
{
    if ([m_outputFiles count] == 0)
        return;
        
    // build the environment
    NSMutableDictionary* env = [[NSMutableDictionary alloc] init];

    // fill in the environment
    NSString* cmdPath = [NSString stringWithString: [[NSBundle mainBundle] resourcePath]];
    [env setValue: [cmdPath stringByAppendingPathComponent: @"bin/ffmpeg"] forKey: @"ffmpeg"];
    [env setValue: [cmdPath stringByAppendingPathComponent: @"bin/qt_export"] forKey: @"qt_export"];
    [env setValue: [cmdPath stringByAppendingPathComponent: @"bin/movtoy4m"] forKey: @"movtoy4m"];
    [env setValue: [cmdPath stringByAppendingPathComponent: @"bin/yuvadjust"] forKey: @"yuvadjust"];
    [env setValue: [cmdPath stringByAppendingPathComponent: @"bin/yuvcorrect"] forKey: @"yuvcorrect"];

    // fill in the filenames
    [env setValue: [self inputFileName] forKey: @"input_file"];
    [env setValue: [self outputFileName] forKey: @"output_file"];
    [env setValue: [self tempAudioFileName] forKey: @"tmp_audio_file"];
    [env setValue: [self passLogFileName] forKey: @"pass_log_file"];
    
    // fill in params
    FrameSize frameSize = [self inputVideoFrameSize];
    [env setValue: [[NSNumber numberWithInt: widthFromFrameSize(frameSize)] stringValue] forKey: @"input_video_width"];
    [env setValue: [[NSNumber numberWithInt: heightFromFrameSize(frameSize)] stringValue] forKey: @"input_video_height"];
    [env setValue: [[NSNumber numberWithDouble: [self inputVideoFramerate]] stringValue] forKey: @"input_frame_rate"];
    [env setValue: [[NSNumber numberWithInt: [self inputVideoBitrate]] stringValue] forKey: @"input_video_bitrate"];
    
    [env setValue: ([self isInputQuicktime] ? @"true" : @"false") forKey: @"is_quicktime"];
    [env setValue: ([self hasInputAudio] ? @"true" : @"false") forKey: @"has_audio"];
    [env setValue: (([m_appController paramLimit] == PL_LIMIT) ? @"true" : @"false") forKey: @"limit_output_params"];

    [env setValue: [self inputVideoCodec] forKey: @"input_video_codec"];

    // set the params
    [[m_appController deviceController] setCurrentParamsWithEnvironment:env];
    
    // save some of the values
    int width = [[[m_appController deviceController] paramForKey:@"output_video_width"] intValue];
    int height = [[[m_appController deviceController] paramForKey:@"output_video_height"] intValue];
    if (width > 32767)
        width = 32767;
    if (height > 32767)
        height = 32767;
        
    frameSize = makeFrameSize(width, height);
    self.outputVideoFrameSize = frameSize;
    self.outputVideoAspectRatio = (double) width / (double) height;
    
    self.outputFormat = [[m_appController deviceController] paramForKey:@"output_format"];

    
    self.outputVideoCodec = [[m_appController deviceController] paramForKey:@"output_video_codec"];
    NSString* profile = [[m_appController deviceController] paramForKey:@"output_video_profile"];
    int level = [[[m_appController deviceController] paramForKey:@"output_video_level"] intValue];
    self.outputVideoProfile = [NSString stringWithFormat:@"%@@%d.%d", profile, level/10, level%10];
    self.outputVideoFramerate = [[[m_appController deviceController] paramForKey:@"output_video_frame_rate"] floatValue];
    self.outputVideoBitrate = [[[m_appController deviceController] paramForKey:@"output_video_bitrate"] floatValue];
    
    m_audioQuality = [[m_appController deviceController] paramForKey:@"audio_quality"];

    self.outputAudioCodec = [[m_appController deviceController] paramForKey:@"output_audio_codec"];
    self.outputAudioBitrate = [[[m_appController deviceController] paramForKey:@"output_audio_bitrate"] floatValue];
    self.outputAudioSampleRate = [[[m_appController deviceController] paramForKey:@"output_audio_sample_rate"] floatValue];
    self.outputAudioChannels = [[[m_appController deviceController] paramForKey:@"output_audio_channels"] intValue];

    self.outputBitrate = self.outputVideoBitrate + self.outputAudioBitrate;
    self.outputFileSize = self.outputDuration * self.outputBitrate / 8;
}

-(void) finish: (int) status
{
    BOOL deleteOutputFile = NO;
    m_fileStatus = (status == 0) ? FS_SUCCEEDED : (status == 255) ? FS_VALID : FS_FAILED;
    
    if (status == 0) {
        [m_appController log: @"Transcode succeeded!\n"];
        
        if ([m_appController addToMediaLibrary]) {
            if (![self addToMediaLibrary: [self outputFileName]]) {
                m_fileStatus = FS_FAILED;
            }
            else if ([m_appController deleteFromDestination])
                deleteOutputFile = YES;
        }
    }
    else {
        deleteOutputFile = YES;
        [m_appController log: @"Transcode FAILED with error code: %d\n", status];
    }
        
    [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
    if (m_fileStatus != FS_VALID)
        m_enabled = false;
    m_progress = (status == 0) ? 1 : 0;
    [m_progressIndicator setDoubleValue: m_progress];
    [m_appController encodeFinished:self withStatus:status];
    [m_logFile closeFile];
    [m_logFile release];
    m_logFile = nil;
    
    // toss output file is not successful
    if (deleteOutputFile)
        [[NSFileManager defaultManager] removeFileAtPath:[self outputFileName] handler:nil];
}

- (BOOL) startEncode
{
    if ([m_outputFiles count] == 0 || !m_enabled)
        return NO;
    
    // Make sure the output file doesn't exist
    if ([[NSFileManager defaultManager] fileExistsAtPath: [self outputFileName]]) {
        NSRunAlertPanel(@"Internal Error", 
                        [NSString stringWithFormat:@"The output file '%@' exists. Video Monkey should never write to an existing file.", [self outputFileName]], 
                        nil, nil, nil);
        return NO;
    }

    // initialize progress values
    m_progress = 0;
    [m_progressIndicator setDoubleValue: m_progress];
    
    // open the log file
    if (m_logFile) {
        [m_logFile closeFile];
        [m_logFile release];
    }
    
    [m_appController log: @"============================================================================\n"];
    [m_appController log: @"Begin transcode: %@ --> %@\n", [[self inputFileName] lastPathComponent], [[self outputFileName] lastPathComponent]];
    
    // Make sure path exists
    NSString* logFilePath = [LOG_FILE_PATH stringByStandardizingPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath: logFilePath])
        [[NSFileManager defaultManager] createDirectoryAtPath:logFilePath withIntermediateDirectories:YES attributes:nil error: nil];
        
    NSString* logFileName = [NSString stringWithFormat:@"%@/%@-%@.log",
                                logFilePath, [[self outputFileName] lastPathComponent], [[NSDate date] description]];
    [[NSFileManager defaultManager] removeFileAtPath:logFileName handler:nil];
    [[NSFileManager defaultManager] createFileAtPath:logFileName contents:nil attributes:nil];
                                
    m_logFile = [[NSFileHandle fileHandleForWritingAtPath:logFileName] retain];
    
    // make sure the tmp tmp files do not exist
    [[NSFileManager defaultManager] removeFileAtPath:m_tempAudioFileName handler:nil];
    [[NSFileManager defaultManager] removeFileAtPath:m_passLogFileName handler:nil];
    
    [self setParams];

    // get recipe
    NSString* recipe = [[m_appController deviceController] recipe];

    if ([recipe length] == 0) {
        [m_appController log:@"*** ERROR: No recipe returned, probably due to a previous JavaScript error\n"];
        [self finish: -1];
        return NO;
    }
    
    // split out each command separately
    NSArray* elements = [recipe componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@";&|"]];
    
    m_commands = [[NSMutableArray alloc] init];
    NSEnumerator* enumerator = [elements objectEnumerator];
    NSString* s;
    int commandId = 0;
    int index = 0;
    
    while (s = (NSString*) [enumerator nextObject]) {
        CommandOutputType type = OT_NONE;
        
        // in splitting the commands, we've lost it's separator, so we have to reconstruct it from the original string
        index += [s length];
        unichar sep = (index < [recipe length]) ? [recipe characterAtIndex:index] : '&';
        index++;
        
        switch(sep)
        {
            case ';': type = OT_WAIT; break;
            case '|': type = OT_PIPE; break;
            case '&': type = OT_CONTINUE; break;
        }
        
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![s length])
            continue;

        // make a Command object for this command
        [m_commands addObject:[[Command alloc] initWithTranscoder:self command:s 
                            outputType:type identifier:[[NSNumber numberWithInt:commandId] stringValue]]];
    }
    
    // execute each command in turn
    enumerator = [m_commands objectEnumerator];
    Command* command = [enumerator nextObject];
    m_isLastCommandRunning = NO;
    int i = 0;
    
    while(command) {
        Command* nextCommand = [enumerator nextObject];
        
        if (++i >= [m_commands count])
            m_isLastCommandRunning = YES;
        [command execute: nextCommand];
        command = nextCommand;
    }

    m_fileStatus = FS_ENCODING;
    [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
    return YES;
}

- (BOOL) pauseEncode
{
    NSEnumerator* enumerator = [m_commands objectEnumerator];
    Command* command;
    
    while(command = [enumerator nextObject])
        [command suspend];
        
    m_fileStatus = FS_PAUSED;
    return YES;
}

-(BOOL) resumeEncode
{
    NSEnumerator* enumerator = [m_commands objectEnumerator];
    Command* command;
    
    while(command = [enumerator nextObject])
        [command resume];
        
    m_fileStatus = FS_ENCODING;
    return YES;
}

-(BOOL) stopEncode
{
    NSEnumerator* enumerator = [m_commands objectEnumerator];
    Command* command;
    
    while(command = [enumerator nextObject])
        [command terminate];
        
    [self finish: 255];
    return YES;
}

-(BOOL) addToMediaLibrary:(NSString*) filename
{
    iTunesApplication* iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
    NSURL *file = [NSURL fileURLWithPath: filename];
    iTunesTrack* track;
    NSString* errorString = nil;
    
    @try {
        track = [iTunes add: [NSArray arrayWithObject:file] to: nil];
        if (!track)
            errorString = @"File could not be added to iTunes (probably an invalid type)";
    }
    @catch (NSException* e) {
        NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:[[[e userInfo] valueForKey:@"ErrorNumber"] intValue] userInfo:[e userInfo]];
        errorString = [error localizedDescription];
    }
    
    if (!errorString) {
        [m_appController log: @"Copy to iTunes succeeded!\n"];
        return YES;
    }
    
    // Error
    [m_appController log: @"Copy to iTunes FAILED with error: %@\n", errorString];
    return NO;
}

-(void) setProgressForCommand: (Command*) command to: (double) value
{
    // TODO: need to give each command a percentage of the progress
    m_progress = value;
    [m_progressIndicator setDoubleValue: m_progress];
    [m_appController setProgressFor: self to: m_progress];
}

-(void) commandFinished: (Command*) command status: (int) status
{
    if (m_isLastCommandRunning)
        [self finish: status];
}

-(void) logToFile: (NSString*) string
{
    // Output to log file
    if (m_logFile)
        [m_logFile writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

-(void) logCommand: (NSString*) commandId withFormat: (NSString*) format, ...
{
    va_list args;
    va_start(args, format);
    NSString* string = [[NSString alloc] initWithFormat:format arguments:args];
    [m_appController log: @"    [Command %@] %@\n", commandId, string];
}

@end
