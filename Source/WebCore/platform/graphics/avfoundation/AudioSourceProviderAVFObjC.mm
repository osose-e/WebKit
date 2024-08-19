/*
 * Copyright (C) 2014, 2015 Apple Inc. All rights reserved.
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

#import "config.h"
#import "AudioSourceProviderAVFObjC.h"

#if ENABLE(WEB_AUDIO) && USE(MEDIATOOLBOX)

#import "AudioBus.h"
#import "AudioChannel.h"
#import "AudioSourceProviderClient.h"
#import "CAAudioStreamDescription.h"
#import "CARingBuffer.h"
#import "Logging.h"
#import <AVFoundation/AVAssetTrack.h>
#import <AVFoundation/AVAudioMix.h>
#import <AVFoundation/AVMediaFormat.h>
#import <AVFoundation/AVPlayerItem.h>

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

#if !LOG_DISABLED
#import <wtf/StringPrintStream.h>
#endif

#import <pal/cf/AudioToolboxSoftLink.h>
#import <pal/cf/CoreMediaSoftLink.h>
#import <pal/cocoa/AVFoundationSoftLink.h>
#import <pal/cocoa/MediaToolboxSoftLink.h>

#pragma mark SFSpeechRecognitionTaskDelegate
#if ENABLE(VIDEO)
@interface WebSynthesizedTextGeneratorRequestDelegate : NSObject<SFSpeechRecognitionTaskDelegate> {
    ThreadSafeWeakPtr<WebCore::AudioSourceProviderAVFObjC> _audioSourceProvider;
    NSRange _rangeOfCurrentTranscription;
    MediaTime _startTimeOfCurrentTranscriptionRange;
    MediaTime _endTimeOfCurrentTranscriptionRange;
    NSUInteger _startingSegmentIndex;
    WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask _createCompletionHandler;
    WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask _updateCompletionHandler;
    WebCore::AudioSourceProviderAVFObjC::CompletedCaptionCreationTask _finalizeCompletionHandler;
    BOOL _firstWordOfCue;
    
}
- (instancetype) initWithAudioSourceProvider:(WebCore::AudioSourceProviderAVFObjC&)audioSourceProvider cueCreateCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask&&)createCompletionHandler cueUpdateCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask&&)updateCompletionHandler andCueFinalizeCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::CompletedCaptionCreationTask&&)finalizeCompletionHandler;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult;
@end

@implementation WebSynthesizedTextGeneratorRequestDelegate
- (instancetype) initWithAudioSourceProvider:(WebCore::AudioSourceProviderAVFObjC&)audioSourceProvider cueCreateCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask&&)createCompletionHandler cueUpdateCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::PartialCaptionCreationTask&&)updateCompletionHandler andCueFinalizeCompletionHandler:(WebCore::AudioSourceProviderAVFObjC::CompletedCaptionCreationTask&&)finalizeCompletionHandler {
    self = [super init];
    if (!self)
        return nil;
    _audioSourceProvider = audioSourceProvider;
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
//        rangeEnd = transcriptionSegment.substringRange.length + transcriptionSegment.substringRange.location - baseTranscriptionSegment.substringRange.location;
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
            // NSLog(@"Finalized Text: %@ Start: %f End: %f SegTime: %f",text, _startTimeOfCurrentTranscriptionRange.toFloat(), _endTimeOfCurrentTranscriptionRange.toFloat(), timeOfSegment);
            
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
                // NSLog(@"Started Text: %@ Start: %f", transcriptionSegment.substring, _startTimeOfCurrentTranscriptionRange.toFloat());
                
            } else {
                // _rangeOfCurrentTranscription.location
                NSString *text = [transcription.formattedString substringWithRange:NSMakeRange(_rangeOfCurrentTranscription.location, transcriptionSegment.substringRange.location + transcriptionSegment.substringRange.length - _rangeOfCurrentTranscription.location)];
//                if ([transcriptionSegment.substring isEqualToString:@"."]) {
//                    _endTimeOfCurrentTranscriptionRange = _endTimeOfCurrentTranscriptionRange + MediaTime::createWithDouble(3.0);
//                    _finalizeCompletionHandler(text, _startTimeOfCurrentTranscriptionRange, _endTimeOfCurrentTranscriptionRange + MediaTime::createWithDouble(3.0));
//                    
//                    _startTimeOfCurrentTranscriptionRange = _endTimeOfCurrentTranscriptionRange;
//                    _startingSegmentIndex = i + 1;
//                    _rangeOfCurrentTranscription.location = transcriptionSegment.substringRange.location + transcriptionSegment.substringRange.length;
//                    _rangeOfCurrentTranscription.length = 0;
//                    _firstWordOfCue = YES;
//                    rangeEnd = 0;
//                } else {
                    _updateCompletionHandler(text, _startTimeOfCurrentTranscriptionRange);
               // NSLog(@"Updated Text: %@ Start: %f",text, _startTimeOfCurrentTranscriptionRange.toFloat());

//
//                }
            }
         }

    }
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult
{
    NSLog(@"CAPTIONS: %@", recognitionResult.bestTranscription.formattedString);
}
@end
#endif
// have the objective c class have ptr to the c++ class

namespace WebCore {

static const double kRingBufferDuration = 1;

class AudioSourceProviderAVFObjC::TapStorage : public ThreadSafeRefCounted<AudioSourceProviderAVFObjC::TapStorage> {
public:
    TapStorage(AudioSourceProviderAVFObjC* _this) : _this(_this) { }
    AudioSourceProviderAVFObjC* _this;
    Lock lock;
};

RefPtr<AudioSourceProviderAVFObjC> AudioSourceProviderAVFObjC::create(AVPlayerItem *item)
{
    if (!PAL::canLoad_MediaToolbox_MTAudioProcessingTapCreate())
        return nullptr;
    return adoptRef(*new AudioSourceProviderAVFObjC(item));
}

AudioSourceProviderAVFObjC::AudioSourceProviderAVFObjC(AVPlayerItem *item)
    : m_avPlayerItem(item)
    , m_configureAudioStorageCallback([](const CAAudioStreamDescription& format, size_t frameCount) {
        return InProcessCARingBuffer::allocate(format, frameCount);
    })
{
}

AudioSourceProviderAVFObjC::~AudioSourceProviderAVFObjC()
{
    // FIXME: this is not correct, as this indicates that there might be simultaneous calls
    // to the destructor and a member function. This undefined behavior will be addressed in the future
    // commits. https://bugs.webkit.org/show_bug.cgi?id=224480
    setClient(nullptr);
}

void AudioSourceProviderAVFObjC::provideInput(AudioBus* bus, size_t framesToProcess)
{
    // Protect access to m_ringBuffer by using tryLock(). If we failed
    // to aquire, a re-configure is underway, and m_ringBuffer is unsafe to access.
    // Emit silence.
    if (!m_tapStorage) {
        bus->zero();
        return;
    }

    if (!m_tapStorage->lock.tryLock()) {
        bus->zero();
        return;
    }
    Locker locker { AdoptLock, m_tapStorage->lock };

    if (!m_ringBuffer) {
        bus->zero();
        return;
    }


    uint64_t seekTo = std::exchange(m_seekTo, NoSeek);
    if (seekTo != NoSeek)
        m_readCount = seekTo;

    auto [startFrame, endFrame] = m_ringBuffer->getFetchTimeBounds();

    if (!m_readCount || m_readCount == seekTo) {
        // We have not started rendering yet. If there aren't enough frames in the buffer, then output
        // silence until there is.
        if (endFrame <= m_readCount + m_writeAheadCount + framesToProcess) {
            bus->zero();
            return;
        }
    } else {
        // We've started rendering. Don't output silence unless we really have to.
        size_t framesAvailable = static_cast<size_t>(endFrame - m_readCount);
        if (framesAvailable < framesToProcess) {
            bus->zero();
            if (!framesAvailable)
                return;
            framesToProcess = framesAvailable;
        }
    }

    ASSERT(bus->numberOfChannels() == m_ringBuffer->channelCount());

    for (unsigned i = 0; i < m_list->mNumberBuffers; ++i) {
        AudioChannel* channel = bus->channel(i);
        m_list->mBuffers[i].mNumberChannels = 1;
        m_list->mBuffers[i].mData = channel->mutableData();
        m_list->mBuffers[i].mDataByteSize = channel->length() * sizeof(float);
    }

    m_ringBuffer->fetch(m_list.get(), framesToProcess, m_readCount);
    m_readCount += framesToProcess;

    if (m_converter)
        PAL::AudioConverterConvertComplexBuffer(m_converter.get(), framesToProcess, m_list.get(), m_list.get());
}

void AudioSourceProviderAVFObjC::setClient(WeakPtr<AudioSourceProviderClient>&& client)
{
    if (m_client == client)
        return;
    destroyMixIfNeeded();
    m_client = WTFMove(client);
    createMixIfNeeded();
}

void AudioSourceProviderAVFObjC::setPlayerItem(AVPlayerItem *avPlayerItem)
{
    if (m_avPlayerItem == avPlayerItem)
        return;
    destroyMixIfNeeded();
    m_avPlayerItem = avPlayerItem;
    createMixIfNeeded();
}

void AudioSourceProviderAVFObjC::setAudioTrack(AVAssetTrack *avAssetTrack)
{
    if (m_avAssetTrack == avAssetTrack)
        return;
    destroyMixIfNeeded();
    m_avAssetTrack = avAssetTrack;
    createMixIfNeeded();
}

void AudioSourceProviderAVFObjC::recreateAudioMixIfNeeded()
{
    if (!m_avAudioMix)
        return;

    destroyMixIfNeeded();
    createMixIfNeeded();
}

#if ENABLE(VIDEO)
void AudioSourceProviderAVFObjC::beginVideoTranscription(PartialCaptionCreationTask&& createCompletionHandler, PartialCaptionCreationTask&& updateCompletionHandler, CompletedCaptionCreationTask&& finalizeCompletionHandler) {
    // make a blk ptr with lambda - no silly you deleted it 🙈
    // initialize delegate with it
    // set it and call it later 🤡
    m_transcriptionGeneratorInUse = true;
    m_generatorRecognitionTaskDelegate = adoptNS([[WebSynthesizedTextGeneratorRequestDelegate alloc] initWithAudioSourceProvider:*this cueCreateCompletionHandler:WTFMove(createCompletionHandler) cueUpdateCompletionHandler:WTFMove(updateCompletionHandler) andCueFinalizeCompletionHandler:WTFMove(finalizeCompletionHandler)]);
#if 0
    auto completionHandler = makeBlockPtr([weakThis = ThreadSafeWeakPtr { *this }, &task](NSString *text, const MediaTime start, const MediaTime end) mutable {
        if (!weakThis.get())
            return;

        task(text, start, end);
    });
    m_generatorRecognitionTaskDelegate = adoptNS([[WebSynthesizedTextGeneratorRequestDelegate alloc] initWithAudioSourceProvider:*this andCompletionHandler:completionHandler.get()]) ;
#endif
          // (void(^)(NSString *text, const MediaTime start, const MediaTime end))
    m_generator = adoptNS([PAL::allocSFSpeechRecognizerInstance() initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]]);
}
#endif

void AudioSourceProviderAVFObjC::destroyMixIfNeeded()
{
    if (!m_avAudioMix)
        return;
    ASSERT(m_tapStorage);
    {
        Locker locker { m_tapStorage->lock };
        if (m_avPlayerItem)
            [m_avPlayerItem setAudioMix:nil];
        [m_avAudioMix setInputParameters:@[ ]];
        m_avAudioMix.clear();
        m_tap.clear();
        m_tapStorage->_this = nullptr;
        // Call unprepare, since Tap cannot call it after clear.
        unprepare();
        m_weakFactory.revokeAll();
    }
    m_tapStorage = nullptr;
}

void AudioSourceProviderAVFObjC::createMixIfNeeded()
{
    // look into her
    if (!m_generator && !m_client)
        return;
    
    if (!m_transcriptionGeneratorInUse)
        return;
        
    if (!m_avPlayerItem || !m_avAssetTrack)
        return;

    ASSERT(!m_avAudioMix);
    ASSERT(!m_tapStorage);
    ASSERT(!m_tap);

    auto tapStorage = adoptRef(new TapStorage(this));
    Locker locker { tapStorage->lock };

    MTAudioProcessingTapCallbacks callbacks = {
        0,
        tapStorage.get(),
        initCallback,
        finalizeCallback,
        prepareCallback,
        unprepareCallback,
        processCallback,
    };

    MTAudioProcessingTapRef tap = nullptr;
    OSStatus status = PAL::MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, 1, &tap);
    if (status != noErr) {
        if (tap)
            CFRelease(tap);
        return;
    }
    m_tap = adoptCF(tap);
    m_tapStorage = WTFMove(tapStorage);
    m_avAudioMix = adoptNS([PAL::allocAVMutableAudioMixInstance() init]);

    RetainPtr<AVMutableAudioMixInputParameters> parameters = adoptNS([PAL::allocAVMutableAudioMixInputParametersInstance() init]);
    [parameters setAudioTapProcessor:m_tap.get()];

    CMPersistentTrackID trackID = m_avAssetTrack.get().trackID;
    [parameters setTrackID:trackID];
    
    [m_avAudioMix setInputParameters:@[parameters.get()]];
    [m_avPlayerItem setAudioMix:m_avAudioMix.get()];
    // consider changing
    m_weakFactory.initializeIfNeeded(*this);
}

void AudioSourceProviderAVFObjC::initCallback(MTAudioProcessingTapRef tap, void* clientInfo, void** tapStorageOut)
{
    ASSERT_UNUSED(tap, tap);
    TapStorage* tapStorage = static_cast<TapStorage*>(clientInfo);
    *tapStorageOut = tapStorage;
    // ref balanced by deref in finalizeCallback:
    tapStorage->ref();
}

void AudioSourceProviderAVFObjC::finalizeCallback(MTAudioProcessingTapRef tap)
{
    ASSERT(tap);
    TapStorage* tapStorage = static_cast<TapStorage*>(PAL::MTAudioProcessingTapGetStorage(tap));
    tapStorage->deref();
}

void AudioSourceProviderAVFObjC::prepareCallback(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat)
{
    ASSERT(tap);
    TapStorage* tapStorage = static_cast<TapStorage*>(PAL::MTAudioProcessingTapGetStorage(tap));

    Locker locker { tapStorage->lock };

    if (tapStorage->_this)
        tapStorage->_this->prepare(maxFrames, processingFormat);
}

void AudioSourceProviderAVFObjC::unprepareCallback(MTAudioProcessingTapRef tap)
{
    ASSERT(tap);
    TapStorage* tapStorage = static_cast<TapStorage*>(PAL::MTAudioProcessingTapGetStorage(tap));

    Locker locker { tapStorage->lock };

    if (tapStorage->_this)
        tapStorage->_this->unprepare();
}

void AudioSourceProviderAVFObjC::processCallback(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut)
{
    ASSERT(tap);
    TapStorage* tapStorage = static_cast<TapStorage*>(PAL::MTAudioProcessingTapGetStorage(tap));

    Locker locker { tapStorage->lock };

    if (tapStorage->_this)
        tapStorage->_this->process(tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut);
}

void AudioSourceProviderAVFObjC::prepare(CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat)
{
    ASSERT(maxFrames >= 0);

    m_tapDescription = makeUniqueWithoutFastMallocCheck<AudioStreamBasicDescription>(*processingFormat);
    int numberOfChannels = processingFormat->mChannelsPerFrame;
    double sampleRate = processingFormat->mSampleRate;
    ASSERT(sampleRate >= 0);

    m_outputDescription = makeUniqueWithoutFastMallocCheck<AudioStreamBasicDescription>();
    m_outputDescription->mSampleRate = sampleRate;
    m_outputDescription->mFormatID = kAudioFormatLinearPCM;
    m_outputDescription->mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    m_outputDescription->mBitsPerChannel = 8 * sizeof(Float32);
    m_outputDescription->mChannelsPerFrame = numberOfChannels;
    m_outputDescription->mFramesPerPacket = 1;
    m_outputDescription->mBytesPerPacket = sizeof(Float32);
    m_outputDescription->mBytesPerFrame = sizeof(Float32);
    m_outputDescription->mFormatFlags |= kAudioFormatFlagIsNonInterleaved;

    if (*m_tapDescription != *m_outputDescription) {
        AudioConverterRef outConverter = nullptr;
        PAL::AudioConverterNew(m_tapDescription.get(), m_outputDescription.get(), &outConverter);
        m_converter = outConverter;
    }

    // Make the ringbuffer large enough to store at least two callbacks worth of audio, or 1s, whichever is larger.
    size_t capacity = std::max(static_cast<size_t>(2 * maxFrames), static_cast<size_t>(kRingBufferDuration * sampleRate));

    m_ringBuffer = m_configureAudioStorageCallback(*processingFormat, capacity);

    // AudioBufferList is a variable-length struct, so create on the heap with a generic new() operator
    // with a custom size, and initialize the struct manually.
    size_t bufferListSize = sizeof(AudioBufferList) + (sizeof(AudioBuffer) * std::max(1, numberOfChannels - 1));
    m_list = std::unique_ptr<AudioBufferList>((AudioBufferList*) ::operator new (bufferListSize));
    memset(m_list.get(), 0, bufferListSize);
    m_list->mNumberBuffers = numberOfChannels;
    
#if ENABLE(VIDEO)
    if (m_transcriptionGeneratorInUse) {
        m_audioProcessingFormat = adoptNS([PAL::allocAVAudioFormatInstance() initWithStreamDescription:m_tapDescription.get()]);
//        m_generatorRecognitionTaskDelegate = adoptNS([[WebSynthesizedTextGeneratorRequestDelegate alloc] initWithAudioSourceProvider:*this]);
        
        auto completionHandler = makeBlockPtr([weakThis = ThreadSafeWeakPtr { *this }](SFSpeechRecognizerAuthorizationStatus authStatus) mutable {
            

            callOnMainThread([authStatus, weakThis = WTFMove(weakThis)] {
                if (RefPtr protectedThis = weakThis.get()) {
                    if (authStatus == SFSpeechRecognizerAuthorizationStatus::SFSpeechRecognizerAuthorizationStatusAuthorized) {
                        protectedThis->m_generator = adoptNS([PAL::allocSFSpeechRecognizerInstance() initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]]);
                        
                        protectedThis->m_samplesBuffer = adoptNS([PAL::allocSFSpeechAudioBufferRecognitionRequestInstance() init]);
                        protectedThis->m_samplesBuffer.get().taskHint = SFSpeechRecognitionTaskHint::SFSpeechRecognitionTaskHintDictation;
                        protectedThis->m_samplesBuffer.get().addsPunctuation = true;
                        
                        // Will using this as a delegate work?
                        // Should be recognizer -- recognizer
                        protectedThis->m_generatorRecogitionTask = [protectedThis->m_generator.get() recognitionTaskWithRequest:protectedThis->m_samplesBuffer.get() delegate:protectedThis->m_generatorRecognitionTaskDelegate.get()];
                        //                    NSLog(@"PREPARE steps");
                    } else {
                        NSLog(@"Error: No authorization for use of synthesized text generator.");
                    }
                }
            });
        });
        [PAL::getSFSpeechRecognizerClass() requestAuthorization:completionHandler.get()];
    }
#endif
    
    callOnMainThread([weakThis = ThreadSafeWeakPtr { *this }, numberOfChannels, sampleRate] {
        if (RefPtr protectedThis = weakThis.get()){
            if (protectedThis->m_client)
                protectedThis->m_client->setFormat(numberOfChannels, sampleRate);
        }
            
    });
}

void AudioSourceProviderAVFObjC::unprepare()
{
#if ENABLE(VIDEO)
    if (m_transcriptionGeneratorInUse) {
        [m_samplesBuffer.get() endAudio];
        [m_generatorRecogitionTask cancel];
        m_generatorRecognitionTaskDelegate = nil;
        
        
        // set delegate to nil !
        // cancel on the task
    }
#endif
    m_tapDescription = nullptr;
    m_outputDescription = nullptr;
    m_ringBuffer = nullptr;
    m_list = nullptr;
}

void AudioSourceProviderAVFObjC::process(MTAudioProcessingTapRef tap, CMItemCount numberOfFrames, MTAudioProcessingTapFlags flags, AudioBufferList* bufferListInOut, CMItemCount* numberFramesOut, MTAudioProcessingTapFlags* flagsOut)
{
    UNUSED_PARAM(flags);
    if (!m_ringBuffer)
        return;
    
    CMItemCount itemCount = 0;
    CMTimeRange rangeOut;
    OSStatus status = PAL::MTAudioProcessingTapGetSourceAudio(tap, numberOfFrames, bufferListInOut, flagsOut, &rangeOut, &itemCount);
    if (status != noErr || !itemCount)
        return;
    
    MediaTime rangeStart = PAL::toMediaTime(rangeOut.start);
    MediaTime rangeDuration = PAL::toMediaTime(rangeOut.duration);
    
    if (rangeStart.isInvalid())
        return;
    
    MediaTime currentTime = PAL::toMediaTime(PAL::CMTimebaseGetTime([m_avPlayerItem timebase]));
    if (currentTime.isInvalid())
        return;

    // The audio tap will generate silence when the media is paused, and will not advance the
    // tap currentTime.
    if (rangeStart == m_startTimeAtLastProcess || rangeDuration == MediaTime::zeroTime()) {
        m_paused = true;
        return;
    }

    if (m_paused) {
        // Only check the write-ahead time when playback begins.
        m_paused = false;
        MediaTime earlyBy = rangeStart - currentTime;
        m_writeAheadCount = m_tapDescription->mSampleRate * earlyBy.toDouble();
    }

    auto [startFrame, endFrame] = m_ringBuffer->getStoreTimeBounds();
        // Only check the write-ahead time when playback begins.
    // Check to see if the underlying media has seeked, which would require us to "flush"
    // our outstanding buffers.
    if (rangeStart != m_endTimeAtLastProcess)
        m_seekTo = endFrame;

    m_startTimeAtLastProcess = rangeStart;
    m_endTimeAtLastProcess = rangeStart + rangeDuration;
    // Check to see if the underlying media has seeked, which would require us to "flush"
    // StartOfStream indicates a discontinuity, such as when an AVPlayerItem is re-added
    // to an AVPlayer, so "flush" outstanding buffers.
    if (flagsOut && *flagsOut & kMTAudioProcessingTapFlag_StartOfStream)
        m_seekTo = endFrame;
    
    m_ringBuffer->store(bufferListInOut, itemCount, endFrame);

    NSLog(@"Time: %f", m_startTimeAtLastProcess.toFloat());
    
    // If a client exists, mute the default audio playback by zeroing the tap-owned buffers.
    if (m_client) {
        for (uint32_t i = 0; i < bufferListInOut->mNumberBuffers; ++i) {
            AudioBuffer& buffer = bufferListInOut->mBuffers[i];
            memset(buffer.mData, 0, buffer.mDataByteSize);
        }
        *numberFramesOut = 0;
    } else {
        if (numberFramesOut)
            *numberFramesOut = numberOfFrames;
        
        if (flagsOut)
            *flagsOut = flags;
    }
    
#if ENABLE(VIDEO)
    if (m_transcriptionGeneratorInUse) {
        RetainPtr<AVAudioPCMBuffer> pcmBuffer = adoptNS([PAL::allocAVAudioPCMBufferInstance() initWithPCMFormat:m_audioProcessingFormat.get() bufferListNoCopy:bufferListInOut deallocator:nil]);
        
        [m_samplesBuffer.get() appendAudioPCMBuffer:pcmBuffer.get()];
    }
#endif
    
    
    if (m_audioCallback)
        m_audioCallback(endFrame, itemCount);
}

void AudioSourceProviderAVFObjC::setAudioCallback(AudioCallback&& callback)
{
    ASSERT(!m_avAudioMix);
    m_audioCallback = WTFMove(callback);
}

void AudioSourceProviderAVFObjC::setConfigureAudioStorageCallback(ConfigureAudioStorageCallback&& callback)
{
    ASSERT(!m_avAudioMix);
    m_configureAudioStorageCallback = WTFMove(callback);
}

}

#endif // ENABLE(WEB_AUDIO) && USE(MEDIATOOLBOX)
