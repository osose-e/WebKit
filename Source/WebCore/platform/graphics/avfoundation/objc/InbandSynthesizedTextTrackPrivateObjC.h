/*
 * Copyright (C) 2020 Apple Inc. All rights reserved.
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


#pragma once

#if ENABLE(VIDEO) & ENABLE(WEB_AUDIO)


#include "InbandTextTrackPrivate.h"
#include "InbandTextTrackPrivateClient.h"


namespace WebCore {

class InbandSynthesizedTextTrackPrivateObjC : public InbandTextTrackPrivate {
public:
    using Mode = InbandTextTrackPrivateMode;
    
    static RefPtr<InbandSynthesizedTextTrackPrivateObjC> create(Mode mode, InbandTextTrackPrivate::CueFormat format)
    {
        return adoptRef(new InbandSynthesizedTextTrackPrivateObjC(mode, format));
    }

    ~InbandSynthesizedTextTrackPrivateObjC() = default;
    
    AtomString label() const override { return m_label; }
    AtomString language() const override { return m_label; }
    void setMode(Mode mode) override { m_mode = mode; }
    Mode mode() const override { return m_mode; }
    
    void createPartialCueForText(const String& text, const MediaTime);
    void updatePartialCueForText(const String& text, const MediaTime);
    void finalizeCueForText(const String&, const MediaTime start, const MediaTime end);
    
protected:
    InbandSynthesizedTextTrackPrivateObjC(Mode, InbandTextTrackPrivate::CueFormat);
    void setLabel(const AtomString& label) { m_label = label; }
    void setLanguage(const AtomString& language) { m_language = language; }
    
private:
#if !RELEASE_LOG_DISABLED
    ASCIILiteral logClassName() const final { return "InbandSynthesizedTextTrackPrivateObjC"_s; }
#endif
    AtomString m_label;
    AtomString m_language;
    Mode m_mode;
    Ref<InbandGenericCue> m_currentCue;

};

}

#endif
