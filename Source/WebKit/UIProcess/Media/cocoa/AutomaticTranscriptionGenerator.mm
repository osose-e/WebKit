/*
 * Copyright (C) 2024 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
#import "config.h"
#import "AutomaticTranscriptionGenerator.h"

#import "CAAudioStreamDescription.h"
#import "CARingBuffer.h"

#if ENABLE(VIDEO)
#import <AVFoundation/AVAudioFormat.h>
#import <AVFoundation/AVAudioBuffer.h>
#import <pal/cocoa/SpeechSoftLink.h>
#endif

#import <objc/runtime.h>
#import <pal/avfoundation/MediaTimeAVFoundation.h>

#import <wtf/BlockPtr.h>
#import <wtf/Lock.h>
#import <wtf/MainThread.h>
#import <wtf/MediaTime.h>
#import <wtf/RetainPtr.h>

#import <pal/cf/AudioToolboxSoftLink.h>
#import <pal/cf/CoreMediaSoftLink.h>
#import <pal/cocoa/AVFoundationSoftLink.h>
#import <pal/cocoa/MediaToolboxSoftLink.h>

#if ENABLE(VIDEO) && HAVE(SPEECHRECOGNIZER)
#pragma mark SFSpeechRecognitionTaskDelegate
@interface AutomaticTranscriptionGeneratorRequestDelegate : NSObject<SFSpeechRecognitionTaskDelegate> {
    ThreadSafeWeakPtr<AutomaticTranscriptionGenerator> _automaticTranscriptionGenerator;
    NSRange _rangeOfCurrentTranscription;
    MediaTime _startTimeOfCurrentTranscriptionRange;
    MediaTime _endTimeOfCurrentTranscriptionRange;
    NSUInteger _startingSegmentIndex;
    WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask _createCompletionHandler;
    WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask _updateCompletionHandler;
    WebKit::AutomaticTranscriptionGenerator::CompletedCaptionCreationTask _finalizeCompletionHandler;
    // TODO: Rename functions to be callbacks instead of completion handlers.
    BOOL _firstWordOfCue;
    
}
- (instancetype) initWithAutomaticTranscriptionGenerator:(WebKit::AutomaticTranscriptionGenerator&)automaticTranscriptionGenerator cueCreateCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask&&)createCompletionHandler cueUpdateCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask&&)updateCompletionHandler andCueFinalizeCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::CompletedCaptionCreationTask&&)finalizeCompletionHandler;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription;
@end

@implementation AutomaticTranscriptionGeneratorRequestDelegate
- (instancetype) initWithAutomaticTranscriptionGenerator:(WebKit::AutomaticTranscriptionGenerator&)automaticTranscriptionGenerator cueCreateCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask&&)createCompletionHandler cueUpdateCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::PartialCaptionCreationTask&&)updateCompletionHandler andCueFinalizeCompletionHandler:(WebKit::AutomaticTranscriptionGenerator::CompletedCaptionCreationTask&&)finalizeCompletionHandler; {
    self = [super init];
    if (!self)
        return nil;
    _automaticTranscriptionGenerator = automaticTranscriptionGenerator;
    _rangeOfCurrentTranscription = NSMakeRange(0, 0);
    _startTimeOfCurrentTranscriptionRange = MediaTime();
    _endTimeOfCurrentTranscriptionRange = MediaTime();
    _startingSegmentIndex = 0;
    _createCompletionHandler = WTFMove(createCompletionHandler);
    _updateCompletionHandler = WTFMove(updateCompletionHandler);
    _finalizeCompletionHandler = WTFMove(finalizeCompletionHandler);
    _firstWordOfCue = YES;
    return self;
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription
{
    NSUInteger i;
    NSUInteger rangeEnd = 0;
    
    for (i = _startingSegmentIndex ; i < [transcription.segments count]; i++) {
        SFTranscriptionSegment *transcriptionSegment = [transcription.segments objectAtIndex:i];
        SFTranscriptionSegment *baseTranscriptionSegment = [transcription.segments objectAtIndex:_startingSegmentIndex];
        _rangeOfCurrentTranscription.location = baseTranscriptionSegment.substringRange.location;
        double timeOfSegment = (transcriptionSegment.timestamp / 0.033);
        if ([transcriptionSegment.substring isEqualToString:@"."] || [transcriptionSegment.substring isEqualToString:@","]) {
            if (i == _startingSegmentIndex)
                _startingSegmentIndex += 1;
            continue;
        }
        
        if ((timeOfSegment == floor(timeOfSegment)) && floor(timeOfSegment) != 0 && (int)timeOfSegment % 3 == 0) {
            _rangeOfCurrentTranscription.length = transcriptionSegment.substringRange.location + transcriptionSegment.substringRange.length - _rangeOfCurrentTranscription.location + 1;
            if (_rangeOfCurrentTranscription.location + _rangeOfCurrentTranscription.length > transcription.formattedString.length)
                _rangeOfCurrentTranscription.length -= 1;
            NSString *text = [transcription.formattedString substringWithRange:_rangeOfCurrentTranscription];
            _endTimeOfCurrentTranscriptionRange = _endTimeOfCurrentTranscriptionRange + MediaTime::createWithDouble(2.5);
            _finalizeCompletionHandler(text, _startTimeOfCurrentTranscriptionRange, _endTimeOfCurrentTranscriptionRange + MediaTime::createWithDouble(2.7));
            
            _startTimeOfCurrentTranscriptionRange = _endTimeOfCurrentTranscriptionRange;
            _startingSegmentIndex = i + 1;
            _rangeOfCurrentTranscription.location = transcriptionSegment.substringRange.location + transcriptionSegment.substringRange.length;
            _rangeOfCurrentTranscription.length = 0;
            _firstWordOfCue = YES;
            rangeEnd = 0;
            break;
        } else {
            if (_firstWordOfCue) {
                _rangeOfCurrentTranscription.location = transcriptionSegment.substringRange.location;
                _createCompletionHandler(transcriptionSegment.substring, _startTimeOfCurrentTranscriptionRange);
                _firstWordOfCue = NO;
                
            } else {
                NSString *text = [transcription.formattedString substringWithRange:NSMakeRange(_rangeOfCurrentTranscription.location, transcriptionSegment.substringRange.location + transcriptionSegment.substringRange.length - _rangeOfCurrentTranscription.location)];
                _updateCompletionHandler(text, _startTimeOfCurrentTranscriptionRange);
            }
        }
        
    }
}

namespace WebKit {
 
Ref<AutomaticTranscriptionGenerator> AutomaticTranscriptionGenerator::create()
{
    return adoptRef(*new AutomaticTranscriptionGenerator())
}
    
AutomaticTranscriptionGenerator::AutomaticTranscriptionGenerator()
{
}

AutomaticTranscriptionGenerator::~AutomaticTranscriptionGenerator()
{
}

void AutomaticTranscriptionGenerator::process(AudioBufferList* samples)
{
    RetainPtr<AVAudioPCMBuffer> pcmBuffer = adoptNS([PAL::allocAVAudioPCMBufferInstance() initWithPCMFormat:m_audioProcessingFormat.get() bufferListNoCopy:bufferListInOut deallocator:nil]);
    
    [m_samplesBuffer.get() appendAudioPCMBuffer:pcmBuffer.get()];

}

void AutomaticTranscriptionGenerator::setFormat(AudioStreamBasicDescription* asbd) 
{
    m_audioProcessingFormat = adoptNS([PAL::allocAVAudioFormatInstance() initWithStreamDescription:m_tapDescription.get()]);
}

void AutomaticTranscriptionGenerator::prepare(PartialCaptionCreationTask&& createCompletionHandler, PartialCaptionCreationTask&& updateCompletionHandler, CompletedCaptionCreationTask&& finalizeCompletionHandler)
{
    // TODO: Accept different languages and locales.
    
    m_generatorRecognitionTaskDelegate = adoptNS([[AutomaticTranscriptionGeneratorRequestDelegate alloc] initWithAutomaticTranscriptionGenerator:*this cueCreateCompletionHandler:WTFMove(createCompletionHandler) cueUpdateCompletionHandler:WTFMove(updateCompletionHandler) andCueFinalizeCompletionHandler:WTFMove(finalizeCompletionHandler)]);
    
    m_generator = adoptNS([PAL::allocSFSpeechRecognizerInstance() initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]]);
    
    auto completionHandler = makeBlockPtr([weakThis = ThreadSafeWeakPtr { *this }](SFSpeechRecognizerAuthorizationStatus authStatus) mutable {
        

        callOnMainThread([authStatus, weakThis = WTFMove(weakThis)] {
            if (RefPtr protectedThis = weakThis.get()) {
                if (authStatus == SFSpeechRecognizerAuthorizationStatus::SFSpeechRecognizerAuthorizationStatusAuthorized) {
                    protectedThis->m_generator = adoptNS([PAL::allocSFSpeechRecognizerInstance() initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]]);
                    
                    protectedThis->m_samplesBuffer = adoptNS([PAL::allocSFSpeechAudioBufferRecognitionRequestInstance() init]);
                    protectedThis->m_samplesBuffer.get().taskHint = SFSpeechRecognitionTaskHint::SFSpeechRecognitionTaskHintDictation;
                    protectedThis->m_samplesBuffer.get().addsPunctuation = true;
                    
                    protectedThis->m_generatorRecogitionTask = [protectedThis->m_generator.get() recognitionTaskWithRequest:protectedThis->m_samplesBuffer.get() delegate:protectedThis->m_generatorRecognitionTaskDelegate.get()];
                } else {
                    NSLog(@"Error: No authorization for use of synthesized text generator.");
                }
            }
        });
    });
    [PAL::getSFSpeechRecognizerClass() requestAuthorization:completionHandler.get()];
    
}

void AutomaticTranscriptionGenerator::unprepare()
{
    // Marking the end of audio to be processed by the synthesized text generator.
    [m_samplesBuffer.get() endAudio];
    [m_generatorRecogitionTask cancel];
    m_generatorRecognitionTaskDelegate = nil;
}

void AutomaticTranscriptionGenerator::receivedNewAudioSamples(const AudioBufferList& data, const AudioStreamDescription& description, size_t frameCount)
{
    auto& basicDescription = *std::get<const AudioStreamBasicDescription*>(description.platformDescription().description);
    if (!m_audioProcessingFormat)
        setFormat(basicDescription);
    
    // TODO: use write count and sample rate to create a media time for the most recent sample.
    // ex. MediaTime(writeCount, sampleRate)
    process(data);
}
    
}
#endif // ENABLE(VIDEO) && HAVE(SPEECHRECOGNIZER)
