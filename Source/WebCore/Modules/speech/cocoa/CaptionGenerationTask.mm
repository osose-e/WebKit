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
#import "CaptionGenerationTask.h"

#if HAVE(SPEECHRECOGNIZER)

#import <wtf/BlockPtr.h>
#import <wtf/WeakObjCPtr.h>

#import <pal/cocoa/SpeechSoftLink.h>

// Set the maximum duration to be an hour; we can adjust this if needed.
static constexpr size_t maximumRecognitionDuration = 60 * 60;

NS_ASSUME_NONNULL_BEGIN
// important document where transcriptions take place
@interface CaptionGenertionTaskImpl : NSObject<SFSpeechRecognitionTaskDelegate, SFSpeechRecognizerDelegate> {
@private
    WebCore::MediaPlayerIdentifier _identifier;
     BlockPtr<void()> _delegateCallback;
    // do I need a callback ?
    RetainPtr<SFSpeechRecognizer> _recognizer;
    RetainPtr<SFSpeechAudioBufferRecognitionRequest> _request;
    WeakObjCPtr<SFSpeechRecognitionTask> _task;
    bool _hasSentSpeechStart;
    bool _hasSentSpeechEnd;
    bool _hasSentEnd;
}

- (instancetype)initWithIdentifier:(WebCore::MediaPlayerIdentifier)identifier locale:(NSString*)localeIdentifier delegateCallback:(void(^))callback;
- (void)callbackWithTranscriptions:(NSArray<SFTranscription *> *)transcriptions;
- (void)audioSamplesAvailable:(AVAudioPCMBuffer)sampleBuffer;
- (void)abort;
- (void)stop;

@end

@implementation CaptionGenertionTaskImpl

- (instancetype)initWithIdentifier:(WebCore::MediaPlayerIdentifier)identifier locale:(NSString*)localeIdentifier delegateCallback:(void(^))callback
{
    if (!(self = [super init]))
        return nil;

    _identifier = identifier;
    _delegateCallback = callback;
    _hasSentSpeechStart = false;
    _hasSentSpeechEnd = false;
    _hasSentEnd = false;

    if (![localeIdentifier length])
        _recognizer = adoptNS([PAL::allocSFSpeechRecognizerInstance() init]);
    else
        _recognizer = adoptNS([PAL::allocSFSpeechRecognizerInstance() initWithLocale:[NSLocale localeWithLocaleIdentifier:localeIdentifier]]);
    if (!_recognizer) {
        [self release];
        return nil;
    }

    if (![_recognizer isAvailable]) {
        [self release];
        return nil;
    }

    [_recognizer setDelegate:self];

    _request = adoptNS([PAL::allocSFSpeechAudioBufferRecognitionRequestInstance() init]);
    if ([_recognizer supportsOnDeviceRecognition])
        [_request setRequiresOnDeviceRecognition:YES];
    [_request setShouldReportPartialResults:YES];
    [_request setTaskHint:SFSpeechRecognitionTaskHintDictation];
    [_request setAddsPunctuation:YES];

    _task = [_recognizer recognitionTaskWithRequest:_request.get() delegate:self];
    return self;
}

- (void)callbackWithTranscriptions:(NSArray<SFTranscription *> *)transcriptions
{
    Vector<WebCore::SpeechRecognitionAlternativeData> alternatives;
    for (SFTranscription* transcription in transcriptions) {
        double maxConfidence = 0.0;
        for (SFTranscriptionSegment* segment in [transcription segments]) {
            maxConfidence = maxConfidence < confidence ? confidence : maxConfidence;
        }
        alternatives.append(WebCore::SpeechRecognitionAlternativeData { [transcription formattedString], maxConfidence });
        if (alternatives.size() == _maxAlternatives)
            break;
    }
    _delegateCallback(WebCore::SpeechRecognitionUpdate::createResult(_identifier, { WebCore::SpeechRecognitionResultData { WTFMove(alternatives), !!isFinal } }));
}

- (void)audioSamplesAvailable:(AVAudioPCMBuffer)sampleBuffer
{
    ASSERT(isMainThread());
    [_request appendAudioSampleBuffer:sampleBuffer];
}

- (void)abort
{
    if (!_task)
        return;

    [self sendSpeechEndIfNeeded];
    [_request endAudio];
    [_task cancel];
}

- (void)stop
{
    if (!_task)
        return;

    [self sendSpeechEndIfNeeded];
    [_request endAudio];
    [_task finish];
}

- (void)sendSpeechStartIfNeeded
{
    if (_hasSentSpeechStart)
        return;

    _hasSentSpeechStart = true;
    _delegateCallback();
}

- (void)sendSpeechEndIfNeeded
{
    if (!_hasSentSpeechStart || _hasSentSpeechEnd)
        return;

    _hasSentSpeechEnd = true;
    _delegateCallback();
}

- (void)sendEndIfNeeded
{
    if (_hasSentEnd)
        return;

    _hasSentEnd = true;
    _delegateCallback(WebCore::SpeechRecognitionUpdate::create(_identifier, WebCore::SpeechRecognitionUpdateType::End));
}

#pragma mark SFSpeechRecognizerDelegate

- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available
{
}

#pragma mark SFSpeechRecognitionTaskDelegate

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription
{
    ASSERT(isMainThread());

    [self sendSpeechStartIfNeeded];
    [self callbackWithTranscriptions:[NSArray arrayWithObjects:transcription, nil]];
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult
{
    ASSERT(isMainThread());

    [self callbackWithTranscriptions:recognitionResult.transcriptions];

    [self stop];
}

- (void)speechRecognitionTaskWasCancelled:(SFSpeechRecognitionTask *)task
{
    ASSERT(isMainThread());

    [self sendSpeechEndIfNeeded];
    [self sendEndIfNeeded];
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully
{
}

@end

@implementation CaptionGenerationTask

- (instancetype)initWithIdentifier:(WebCore::MediaPlayerIdentifier)identifier locale:(NSString*)localeIdentifier delegateCallback:(void(^))callback
{
    if (!(self = [super init]))
        return nil;

    _impl = adoptNS([[CaptionGenerationTaskImpl alloc] initWithIdentifier:identifier locale:localeIdentifier delegateCallback:callback]);

    if (!_impl) {
        [self release];
        return nil;
    }

    return self;
}

- (void)audioSamplesAvailable:(CMSampleBufferRef)sampleBuffer
{
    [_impl audioSamplesAvailable:sampleBuffer];
}

- (void)abort
{
    [_impl abort];
}

- (void)stop
{
    [_impl stop];
}

@end

NS_ASSUME_NONNULL_END

#endif
