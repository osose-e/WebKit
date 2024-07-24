/*
 * Copyright (C) 2011, Google Inc. All rights reserved.
 * Copyright (C) 2020, Apple Inc. All rights reserved.
 * Copyright (C) 2024  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1.  Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma once

#if ENABLE(WEB_AUDIO) && ENABLE(VIDEO) && HAVE(SPEECHRECOGNIZER)
// TODO: make sure all my additions of HAVE(SPEECHRECOGNIZER) include video and web audio

#include "AudioNode.h"
#include "AudioSourceProviderClient.h"
#include "HTMLMediaElement.h"
#include "MultiChannelResampler.h"
// #include "MediaElementAudioSourceNode.h"
#include <memory>
#include <wtf/Lock.h>

namespace WebCore {

class AudioContext;


// debating whether this should inhert from AudioNode and AudioSourceProviderClient or MediaElementSourceNode
class SynthesizedTextGenerator final : public AudioNode, public AudioSourceProviderClient {
    WTF_MAKE_ISO_ALLOCATED(SynthesizedTextGenerator);
public:
    virtual ~SynthesizedTextGenerator();

    using AudioNode::weakPtrFactory;
    using AudioNode::WeakValueType;
    using AudioNode::WeakPtrImplType;

    HTMLMediaElement& mediaElement() { return m_mediaElement; }

    // AudioNode
    void process(size_t framesToProcess) override;
    
    // AudioSourceProviderClient
    void setFormat(size_t numberOfChannels, float sampleRate) override;

    // Lock& processLock() WTF_RETURNS_LOCK(m_processLock) { return m_processLock; }

private:
    SynthesizedTextGenerator(BaseAudioContext&, Ref<HTMLMediaElement>&&);
    void provideInput(AudioBus*, size_t framesToProcess);

    double tailTime() const override { return 0; }
    double latencyTime() const override { return 0; }
    bool requiresTailProcessing() const final { return false; }

    // As an audio source, we will never propagate silence.
    bool propagatesSilence() const override { return false; }

    bool wouldTaintOrigin();

    Ref<HTMLMediaElement> m_mediaElement;
    Lock m_processLock;

    unsigned m_sourceNumberOfChannels WTF_GUARDED_BY_LOCK(m_processLock) { 0 };
    double m_sourceSampleRate WTF_GUARDED_BY_LOCK(m_processLock) { 0 };
    UniqueRef<AudioStreamBasicDescription> m_asbd WTF_GUARDED_BY_LOCK(m_processLock) { 0 };
    bool m_muted WTF_GUARDED_BY_LOCK(m_processLock) { false };

    std::unique_ptr<MultiChannelResampler> m_multiChannelResampler WTF_GUARDED_BY_LOCK(m_processLock);
    // questions
    
    // Q: why use uniqueref over unique_ptr / vice versa? // is the scope different
    // Q: why do we use Ref vs the ptr
    // Q: difference between ref and retain ptr
    // Q: difference betweeen makeuniqueref and makeunique
    // Q: I think these are all defined in WTF is there somewhere to read on use cases of each- I want to be sure I am using best pointer based on my intent. If not I will ask for code review via github draft early + often 
    
    // Q: strategy
    // 1. make a child class of audionode or MediaElementAudioSourceNode
    //
    // use the same node, just different providers
    // 2. and then add the speech synthesis functions onto the mediasourceelement, seperation can come later
};

} // namespace WebCore

#endif // ENABLE(WEB_AUDIO) && ENABLE(VIDEO) && HAVE(SPEECHRECOGNIZER)
