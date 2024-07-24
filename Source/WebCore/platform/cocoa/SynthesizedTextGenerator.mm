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
#import <Speech/Speech.h>
#import "SynthesizedTextGenerator.h"
#import "SynthesizedTextGeneratorRequestDelegate.h"
#import <wtf/BlockPtr.h>
#import <wtf/RetainPtr.h>

#if ENABLE(AUTOMATIC_LIVE_CAPTIONING)

// Add the delegate here ---

SynthesizedTextGenerator::SynthesizedTextGenerator()
{
}

SynthesizedTextGenerator::~SynthesizedTextGenerator()
{
}

void SynthesizedTextGenerator::process(AudioBufferList* samples)
{
    RetainPtr<AVAudioPCMBuffer> pcmBuffer = adoptNS([[AVAudioPCMBuffer alloc] initWithPCMFormat:m_audioProcessingFormat.get() bufferListNoCopy:samples deallocator:nil]);
    

    [m_samplesBuffer.get() appendAudioPCMBuffer:pcmBuffer.get()];
    
}

void SynthesizedTextGenerator::addFormat(AudioStreamBasicDescription* asbd) {
    m_audioProcessingFormat = adoptNS([[AVAudioFormat alloc] initWithStreamDescription:asbd]);
}

void SynthesizedTextGenerator::start()
{
    // prepare generator
    
    auto completionHandler = makeBlockPtr([[this, weakThis = WeakPtr { *this }](SFSpeechRecognizerAuthorizationStatus authStatus) {
        
        if (!weakThis)
            return;
        
        auto checkedThis = CheckedPtr { *this }; // should this be CanMakeCheckedPtr
        
        if (authStatus == SFSpeechRecognizerAuthorizationStatus::SFSpeechRecognizerAuthorizationStatusAuthorized) {
            checkedThis->m_generator = adoptNS([[SFSpeechRecognizer alloc] initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]]);
            
            checkedThis->m_samplesBuffer = adoptNS([[SFSpeechAudioBufferRecognitionRequest alloc] init]);
            checkedThis->m_samplesBuffer.get().taskHint = SFSpeechRecognitionTaskHint::SFSpeechRecognitionTaskHintDictation;
            
            checkedThis->m_generatorRecogitionTask = [checkedThis->m_generator recognitionTaskWithRequest:checkedThis->m_samplesBuffer delegate:checkedThis->m_genratorRecognitionTaskDelegate];
        } else {
            NSLog(@"Error: No authorization for use of synthesized text generator.");
        }
    });
    
    [SFSpeechRecognizer requestAuthorization:completionHandler.get()];

}

void SynthesizedTextGenerator::stop()
{
    // Marking the end of audio to be processed by the synthesized text generator.
    [m_samplesBuffer.get() endAudio];
    
}

#endif // ENABLE(AUTOMATIC_LIVE_CAPTIONING)

