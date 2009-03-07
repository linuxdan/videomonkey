//
//  Transcoder.m
//  VideoMonkey
//
//  Created by Chris Marrin on 11/26/08.
//  Copyright 2008 Apple. All rights reserved.
//

#import "Transcoder.h"
#import "AppController.h"
#import "Command.h"
#import "DeviceController.h"

@implementation TranscoderFileInfo

-(void) setFormat: (NSString*) format
{
    [format retain];
    [m_format release];
    m_format = format;
}

-(void) setVideoLanguage: (NSString*) lang
{
    [lang retain];
    [m_videoLanguage release];
    m_videoLanguage = lang;
}

-(void) setVideoCodec: (NSString*) codec
{
    [codec retain];
    [m_videoCodec release];
    m_videoCodec = codec;
}

-(void) setVideoProfile: (NSString*) profile
{
    [profile retain];
    [m_videoProfile release];
    m_videoProfile = profile;
}

-(void) setAudioLanguage: (NSString*) lang
{
    [lang retain];
    [m_audioLanguage release];
    m_audioLanguage = lang;
}

-(void) setAudioCodec: (NSString*) codec
{
    [codec retain];
    [m_audioCodec release];
    m_audioCodec = codec;
}

-(void) setFilename: (NSString*) filename
{
    [filename retain];
    [m_filename release];
    m_filename = filename;
}

@end

@implementation Transcoder

-(BOOL) _validateInputFile: (TranscoderFileInfo*) info
{
    NSMutableString* mediainfoPath = [NSMutableString stringWithString: [[NSBundle mainBundle] resourcePath]];
    [mediainfoPath appendString:@"/bin/mediainfo"];
    
    NSMutableString* mediainfoInformPath = [NSMutableString stringWithString: @"--Inform=file://"];
    [mediainfoInformPath appendString: [[NSBundle mainBundle] resourcePath]];
    [mediainfoInformPath appendString:@"/mediainfo-inform.csv"];
    
    NSTask* task = [[NSTask alloc] init];
    NSMutableArray* args = [NSMutableArray arrayWithObjects: mediainfoInformPath, info->m_filename, nil];
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
    if ([general count] != 5)
        return NO;
        
    [info setFormat: [general objectAtIndex:1]];
    info->m_isQuicktime = [[general objectAtIndex:2] isEqualToString:@"QuickTime"];
    info->m_duration = [[general objectAtIndex:3] doubleValue] / 1000;
    info->m_bitrate = [[general objectAtIndex:4] doubleValue];

    if ([info->m_format length] == 0)
        return NO;
        
    // Do video if it's there
    int offset = 1;
    if ([components count] > offset && [[components objectAtIndex:offset] hasPrefix: @"-Video-"]) {
        NSArray* video = [[components objectAtIndex:offset] componentsSeparatedByString:@","];
        offset = 2;
        
        // -Video-,%StreamKindID%,%ID%,%Language%,%Format%,%Codec_Profile%,%ScanType%,%ScanOrder%,%Width%,%Height%,%PixelAspectRatio%,%DisplayAspectRatio%,%FrameRate%

        if ([video count] != 13)
            return NO;
        info->m_videaStreamKind = [[video objectAtIndex:1] intValue];
        info->m_videoTrack = [[video objectAtIndex:2] intValue];
        info->m_videoLanguage = [[video objectAtIndex:3] retain];
        info->m_videoCodec = [[video objectAtIndex:4] retain];
        info->m_videoProfile = [[video objectAtIndex:5] retain];
        info->m_videoInterlaced = [[video objectAtIndex:6] isEqualToString:@"Interlace"];
        info->m_width = [[video objectAtIndex:8] intValue];
        info->m_height = [[video objectAtIndex:9] intValue];
        info->m_pixelAspectRatio = [[video objectAtIndex:10] doubleValue];
        info->m_displayAspectRatio = [[video objectAtIndex:11] doubleValue];
        info->m_frameRate = [[video objectAtIndex:12] doubleValue];
        
        // standardize video codec name
        NSString* f = VC_H264;
        if ([info->m_videoCodec caseInsensitiveCompare:@"vc-1"] == NSOrderedSame || [info->m_videoCodec caseInsensitiveCompare:@"wmv3"] == NSOrderedSame)
            f = VC_WMV3;
        else if ([info->m_videoCodec caseInsensitiveCompare:@"avc"] == NSOrderedSame || [info->m_videoCodec caseInsensitiveCompare:@"avc1"] == NSOrderedSame)
            f = VC_H264;
    
        info->m_videoCodec = f;
    }
    
    // Do audio if it's there
    if ([components count] > offset && [[components objectAtIndex:offset] hasPrefix: @"-Audio-"]) {
        NSArray* audio = [[components objectAtIndex:offset] componentsSeparatedByString:@","];

        // -Audio-,%StreamKindID%,%ID%,%Language%,%Format%,%SamplingRate%,%Channels%,%BitRate%
        if ([audio count] != 8)
            return NO;
            
        info->m_audioStreamKind = [[audio objectAtIndex:1] intValue];
        info->m_audioTrack = [[audio objectAtIndex:2] intValue];
        info->m_audioLanguage = [[audio objectAtIndex:3] retain];
        info->m_audioCodec = [[audio objectAtIndex:4] retain];
        info->m_audioSamplingRate = [[audio objectAtIndex:5] doubleValue];
        info->m_channels = [[audio objectAtIndex:6] intValue];
        info->m_audioBitrate = [[audio objectAtIndex:7] doubleValue];
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

-(void) setVideoFormat: (NSString*) format
{
    if ([m_outputFiles count] == 0)
        return;
        
    ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_videoCodec = format;
}

-(NSString*) videoFormat
{
    return ([m_outputFiles count] == 0) ? VC_H264 : ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_videoCodec;
}

-(double) duration
{
    if ([m_inputFiles count] > 0)
        return ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_duration;
    return -1;
}

-(double) progress
{
    return m_progress;
}

-(NSValue*) progressCell
{
    return [NSValue valueWithPointer:self];
}

-(BOOL) enabled
{
    return m_enabled;
}

-(void) setEnabled: (BOOL) b
{
    m_enabled = b;
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

-(NSString*) inputFileName
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_filename : nil;
}

-(BOOL) isInputQuicktime
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_isQuicktime : NO;
}

-(BOOL) hasInputAudio
{
    return ([m_inputFiles count] > 0) ? (((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_audioSamplingRate != 0) : NO;
}

-(NSString*) inputVideoFormat
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_videoCodec : nil;
}

-(NSString*) outputFileName
{
    return ([m_outputFiles count] > 0) ? ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_filename : nil;
}

-(int) inputVideoWidth
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_width : 0;
}

-(int) inputVideoHeight
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_height : 0;
}

-(int) inputVideoWidthDiv2
{
    if ([m_inputFiles count] == 0)
        return 100;
        
    int w = ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_width;
    return (w & 1) ? w+1 : w;
}

-(int) inputVideoHeightDiv2
{
    if ([m_inputFiles count] == 0)
        return 100;
        
    int h = ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_height;
    return (h & 1) ? h+1 : h;
}

-(int) inputVideoWidthDiv16
{
    if ([m_inputFiles count] == 0)
        return 100;
        
    int w = ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_width;
    return (w+15) & (~(16-1));
}

-(int) inputVideoHeightDiv16
{
    if ([m_inputFiles count] == 0)
        return 100;
        
    int h = ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_height;
    return (h+15) & (~(16-1));
}

-(double) inputVideoFrameRate
{
    return ([m_inputFiles count] > 0) ? ((TranscoderFileInfo*) [m_inputFiles objectAtIndex: 0])->m_frameRate : 30;
}

-(NSString*) ffmpeg_vcodec
{
    if ([[self videoFormat] isEqualToString:VC_H264])
        return @"libx264";
    else if ([[self videoFormat] isEqualToString:VC_WMV3])
        return @"wmv3";
    else 
        return @"libx264";
}

-(int) outputFileSize
{
    double duration = [self duration];
    double bitrate = [self bitrate];
    return (int) (duration * bitrate / 8);
}

-(NSString*) tempAudioFileName
{
    return m_tempAudioFileName;
}

-(NSString*) passLogFileName
{
    return m_passLogFileName;
}

-(int) frameSize
{
    // This is a composite (upper 16 bits width, lower 16 bits height)
    int width = ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_width;
    int height = ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_height;
    return (width << 16) | height;
}

-(NSString*) audioQuality
{
    return m_audioQuality;
}

-(void) setParams
{
    if ([m_outputFiles count] == 0 || !m_enabled)
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
    [env setValue: [[NSNumber numberWithInt: [self inputVideoWidth]] stringValue] forKey: @"input_video_width"];
    [env setValue: [[NSNumber numberWithInt: [self inputVideoHeight]] stringValue] forKey: @"input_video_height"];
    [env setValue: [[NSNumber numberWithInt: [self inputVideoWidthDiv16]] stringValue] forKey: @"output_video_width"];
    [env setValue: [[NSNumber numberWithInt: [self inputVideoHeightDiv16]] stringValue] forKey: @"output_video_height"];
    [env setValue: [[NSNumber numberWithInt: [self bitrate]] stringValue] forKey: @"bitrate"];
    [env setValue: [[NSNumber numberWithInt: [self inputVideoFrameRate]] stringValue] forKey: @"input_frame_rate"];
    
    [env setValue: ([self isInputQuicktime] ? @"true" : @"false") forKey: @"is_quicktime"];
    [env setValue: ([self hasInputAudio] ? @"true" : @"false") forKey: @"has_audio"];

    [env setValue: [self inputVideoFormat] forKey: @"input_video_codec"];

    [env setValue: [self ffmpeg_vcodec] forKey: @"ffmpeg_vcodec"];
    
    // set the params
    [[m_appController deviceController] setCurrentParamsWithEnvironment:env];
    
    // save some of the values
    if ([m_outputFiles count] > 0) {
        int width = [[[m_appController deviceController] paramForKey:@"output_video_width"] intValue];
        int height = [[[m_appController deviceController] paramForKey:@"output_video_height"] intValue];
        if (width > 32767)
            width = 32767;
        if (height > 32767)
            height = 32767;
        ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_width = width;
        ((TranscoderFileInfo*) [m_outputFiles objectAtIndex: 0])->m_height = height;
    }
    
    m_audioQuality = [[m_appController deviceController] paramForKey:@"audio_quality_string"];
}

-(void) finish: (int) status
{
    if (status == 0)
        [m_appController log: @"Transcode succeeded!\n"];
    else
        [m_appController log: @"Transcode FAILED with error code: %d\n", status];
        
    m_fileStatus = (status == 0) ? FS_SUCCEEDED : (status == 255) ? FS_VALID : FS_FAILED;
    [m_statusImageView setImage: getFileStatusImage(m_fileStatus)];
    m_progress = (status == 0) ? 1 : 0;
    [m_progressIndicator setDoubleValue: m_progress];
    [m_appController encodeFinished:self];
    [m_logFile closeFile];
    [m_logFile release];
    m_logFile = nil;
    
    // toss output file is not successful
    if (m_fileStatus != FS_SUCCEEDED)
        [[NSFileManager defaultManager] removeFileAtPath:[self outputFileName] handler:nil];
}

- (BOOL) startEncode
{
    if ([m_outputFiles count] == 0 || !m_enabled)
        return NO;
        
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
