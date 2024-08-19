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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "InbandSynthesizedTextTrackPrivateObjC.h"

#import "Logging.h"

#import <wtf/text/AtomString.h>
#import <wtf/text/WTFString.h>

#if ENABLE(VIDEO) && ENABLE(WEB_AUDIO)

namespace WebCore {

static const AtomString& languageAtomString()
{
    static MainThreadNeverDestroyed<const AtomString> language("en_US"_s);
    return language;
}

static const AtomString& labelAtomString()
{
    static MainThreadNeverDestroyed<const AtomString> label("Auto-generated Subtitles (English)"_s);
    return label;
}

InbandSynthesizedTextTrackPrivateObjC::InbandSynthesizedTextTrackPrivateObjC(Mode mode, InbandTextTrackPrivate::CueFormat format)
: InbandTextTrackPrivate(format)
, m_currentCue(InbandGenericCue::create())
{
    setMode(mode);
    setLabel(labelAtomString());
    setLanguage(languageAtomString());

}

void InbandSynthesizedTextTrackPrivateObjC::createPartialCueForText(const String& text, const MediaTime start) {
    ASSERT(isMainThread());
    
    auto cueData = InbandGenericCue::create();
    cueData->setAlign(GenericCueData::Alignment::Start);
    
    cueData->setStartTime(start);
    cueData->setContent(text);
    cueData->setEndTime(MediaTime::positiveInfiniteTime());
    
    cueData->setStatus(GenericCueData::Status::Partial);
    
    m_currentCue = cueData;
    
    notifyMainThreadClient([&](auto& client) {
        downcast<InbandTextTrackPrivateClient>(client).addGenericCue(cueData);
    });
}

void InbandSynthesizedTextTrackPrivateObjC::updatePartialCueForText(const String& text, const MediaTime start) {
    ASSERT(isMainThread());
    
    if (start != m_currentCue->startTime())
        return;
    
    m_currentCue->setContent(text);
    
    notifyMainThreadClient([&](auto& client) {
        downcast<InbandTextTrackPrivateClient>(client).updateGenericCue(m_currentCue);
    });
}

void InbandSynthesizedTextTrackPrivateObjC::finalizeCueForText(const String& text, const MediaTime start, const MediaTime end) {
    ASSERT(isMainThread());
    
    // Create Cue
    
    // create a new cue if not already existing (as an ivar), and each time a new word is gotten ad d to exist ing string and updaate the cue data and the final message should update one last time or finalize and clear the ivar
    if (start != m_currentCue->startTime())
        return;
    
    m_currentCue->setContent(text);
    m_currentCue->setEndTime(end);

    m_currentCue->setStatus(GenericCueData::Status::Complete);
    
    
    // add partial cues
        // 1. potentially make a new method (like one word at a time) to display a cue (updateGenericCue)and keep update the one on screen and then use create cue for text to finalize the cue
        // PROBLEM:
    
    notifyMainThreadClient([&](auto& client) {
        downcast<InbandTextTrackPrivateClient>(client).updateGenericCue(m_currentCue);
    });
    
}



}
#endif

