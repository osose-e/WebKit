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
#pragma once
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
OBJC_CLASS AutomaticTranscriptionGeneratorRequestDelegate;

typedef struct AudioBufferList AudioBufferList;
typedef struct AudioStreamBasicDescription AudioStreamBasicDescription;

namespace WebKit {

class AutomaticTranscriptionGenerator : public ThreadSafeRefCountedAndCanMakeThreadSafeWeakPtr<AutomaticTranscriptionGenerator> {
    WTF_MAKE_FAST_ALLOCATED
public:
    using CompletedCaptionCreationTask = Function<void(NSString *, const WTF::MediaTime start, const WTF::MediaTime end)>;
    using PartialCaptionCreationTask = Function<void(NSString *, const WTF::MediaTime)>;
    
    static Ref<AutomaticTranscriptionGenerator> create();
    ~AutomaticTranscriptionGenerator();
    void setFormat(AudioStreamBasicDescription* asbd);
    void process(AudioBufferList* samples);
    void prepare(PartialCaptionCreationTask&& createCallback, PartialCaptionCreationTask&& updateCallback, CompletedCaptionCreationTask&&);
    void unprepare();
    void receivedNewAudioSamples(const AudioBufferList&, const AudioStreamDescription&, size_t);
     
private:
    AutomaticTranscriptionGenerator();
    RetainPtr<SFSpeechRecognitionRequest> m_generator;
    RetainPtr<SFSpeechAudioBufferRecognitionRequest> m_samplesBuffer;
    RetainPtr<SFSpeechRecognitionTask> m_generatorRecogitionTask;
    RetainPtr<AVAudioFormat> m_audioProcessingFormat;
    RetainPtr<AutomaticTranscriptionGeneratorRequestDelegate> m_genratorRecognitionTaskDelegate;
    std::unique_ptr<WebAudioBufferList> m_audioBufferList;
};

}
#endif // ENABLE(AUTOMATIC_LIVE_CAPTIONING)

/* AutomaticTranscriptionGenerator_h */

