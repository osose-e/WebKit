/*
 * Copyright (C) 2014 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#pragma once

#if ENABLE(WEB_AUDIO) && USE(MEDIATOOLBOX)

#include "AudioSourceProvider.h"
#include <wtf/MediaTime.h>
#include <wtf/RetainPtr.h>

#include <wtf/ThreadSafeRefCounted.h>
#include <wtf/TypeCasts.h>
#include <wtf/UniqueRef.h>
#include <wtf/WeakPtr.h>

OBJC_CLASS AVAssetTrack;
OBJC_CLASS AVPlayerItem;
OBJC_CLASS AVMutableAudioMix;
OBJC_CLASS AVAudioFormat;
OBJC_CLASS AVAudioPCMBuffer;
OBJC_CLASS SFSpeechAudioBufferRecognitionRequest;
OBJC_CLASS SFSpeechRecognizer;
OBJC_CLASS SFSpeechRecognitionTask;
OBJC_CLASS WebSynthesizedTextGeneratorRequestDelegate;


typedef const struct opaqueMTAudioProcessingTap *MTAudioProcessingTapRef;
typedef struct AudioBufferList AudioBufferList;
typedef struct AudioStreamBasicDescription AudioStreamBasicDescription;
typedef struct OpaqueAudioConverter* AudioConverterRef;
typedef uint32_t MTAudioProcessingTapFlags;
typedef signed long CMItemCount;

namespace WebCore {

class AudioStreamDescription;
class CAAudioStreamDescription;
class CARingBuffer;
class PlatformAudioData;

class AudioSourceProviderAVFObjC : public ThreadSafeRefCountedAndCanMakeThreadSafeWeakPtr<AudioSourceProviderAVFObjC>, public AudioSourceProvider {
public:
    using WeakValueType = AudioSourceProviderAVFObjC;
    static RefPtr<AudioSourceProviderAVFObjC> create(AVPlayerItem*);
    virtual ~AudioSourceProviderAVFObjC();

    void setPlayerItem(AVPlayerItem *);
    void setAudioTrack(AVAssetTrack *);

    using AudioCallback = Function<void(uint64_t startFrame, uint64_t numberOfFrames)>;
    WEBCORE_EXPORT void setAudioCallback(AudioCallback&&);
    using ConfigureAudioStorageCallback = Function<std::unique_ptr<CARingBuffer>(const CAAudioStreamDescription&, size_t frameCount)>;
    WEBCORE_EXPORT void setConfigureAudioStorageCallback(ConfigureAudioStorageCallback&&);

    void recreateAudioMixIfNeeded();

#if ENABLE(VIDEO)
    using CaptionCreationTask = Function<void(NSString *, const MediaTime start, const MediaTime end)>;
    void beginVideoTranscription(PartialCaptionCreationTask&& createCompletionHandler, PartialCaptionCreationTask&& updateCompletionHandler, CompletedCaptionCreationTask&&) override;
//    CaptionCreationTask m_task;
//    CaptionCreationTask captionCreationTask() const { return m_task; }
//    void endVideoTranscription();
#endif

private:
    AudioSourceProviderAVFObjC(AVPlayerItem *);

    void destroyMixIfNeeded();
    void createMixIfNeeded();

    // AudioSourceProvider
    void provideInput(AudioBus*, size_t framesToProcess) override;
    void setClient(WeakPtr<AudioSourceProviderClient>&&) override;
    bool isHandlingAVPlayer() const final { return true; }

    static void initCallback(MTAudioProcessingTapRef, void*, void**);
    static void finalizeCallback(MTAudioProcessingTapRef);
    static void prepareCallback(MTAudioProcessingTapRef, CMItemCount, const AudioStreamBasicDescription*);
    static void unprepareCallback(MTAudioProcessingTapRef);
    static void processCallback(MTAudioProcessingTapRef, CMItemCount, MTAudioProcessingTapFlags, AudioBufferList*, CMItemCount*, MTAudioProcessingTapFlags*);

    void prepare(CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat);
    void unprepare();
    void process(MTAudioProcessingTapRef, CMItemCount numberFrames, MTAudioProcessingTapFlags flagsIn, AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut);

    RetainPtr<AVPlayerItem> m_avPlayerItem;
    RetainPtr<AVAssetTrack> m_avAssetTrack;
    RetainPtr<AVMutableAudioMix> m_avAudioMix;
    RetainPtr<MTAudioProcessingTapRef> m_tap;
    RetainPtr<AudioConverterRef> m_converter;
    std::unique_ptr<AudioBufferList> m_list;
    std::unique_ptr<AudioStreamBasicDescription> m_tapDescription;
    std::unique_ptr<AudioStreamBasicDescription> m_outputDescription;
    std::unique_ptr<CARingBuffer> m_ringBuffer;
    
#if ENABLE(VIDEO)
    RetainPtr<SFSpeechRecognizer> m_generator;
    RetainPtr<AVAudioFormat> m_audioProcessingFormat;
    
    RetainPtr<SFSpeechAudioBufferRecognitionRequest> m_samplesBuffer;
    RetainPtr<SFSpeechRecognitionTask> m_generatorRecogitionTask;
    RetainPtr<WebSynthesizedTextGeneratorRequestDelegate> m_generatorRecognitionTaskDelegate;
    MediaTime m_startTimeForTranscriptionTask;
    
    
    bool m_transcriptionGeneratorInUse;
//    CaptionCreationTask m_task;

    RetainPtr<SFSpeechAudioBufferRecognitionRequest> m_previousSamplesBuffer;
    RetainPtr<SFSpeechRecognitionTask> m_previousGeneratorRecogitionTask;
    RetainPtr<WebSynthesizedTextGeneratorRequestDelegate> m_previousGeneratorRecognitionTaskDelegate;
    MediaTime m_startTimeForFirstUtterance;

    
//
//    
//    void flushVideoTransciptionBuffer();
//    void prepareVideoTranscriptionTask();
//    void beginVideoTranscription();
    
    
        // make generator, set to generator in use, set lambda
    
    // do I use this? it should probably be an atomString
    // store finishingbuffer &  finishingbufferstarttime
    // store currentbuffer & currentbufferstarttime
    // duration will be 4 secs
    // currentbuffer
    // when we get final transcription for a buffer
    // if we fill a curr 5 sec buffer, call end audio, add to a finishing transcription buffer + finishing start time and add all new samples to a fresh curr buffer
    // when we get a final transcription for a buffer
        // pass text and finsihing start time to texttrack
        // set finsihing buffer to nil / keep finishing start time unchanged

    // save time as buffer start time
    // what does seeking do (maybe if time is not within 4 sec flush the buffer and start a new one
        // if we seeked, cancel finsihing buffer, set to nil, and cancel current buffer, create a fresh current
#endif

    MediaTime m_startTimeAtLastProcess;
    MediaTime m_endTimeAtLastProcess;
    uint64_t m_writeAheadCount { 0 };
    uint64_t m_readCount { 0 };
    enum { NoSeek = std::numeric_limits<uint64_t>::max() };
    uint64_t m_seekTo { NoSeek };
    bool m_paused { true };
    WeakPtr<AudioSourceProviderClient> m_client;
    WeakPtrFactory<AudioSourceProviderAVFObjC> m_weakFactory;

    class TapStorage;
    RefPtr<TapStorage> m_tapStorage;
    AudioCallback m_audioCallback;
    ConfigureAudioStorageCallback m_configureAudioStorageCallback;
};

}

SPECIALIZE_TYPE_TRAITS_BEGIN(WebCore::AudioSourceProviderAVFObjC)
    static bool isType(const WebCore::AudioSourceProvider& provider) { return provider.isHandlingAVPlayer(); }
SPECIALIZE_TYPE_TRAITS_END()

#endif // ENABLE(WEB_AUDIO) && USE(MEDIATOOLBOX)
