//
//  AudioBackgroundKeeper.swift
//  VideoCompressor
//
//  Keeps the app alive in the background indefinitely (vs UIBackgroundTask's
//  ~30 sec ceiling) by activating the AVAudioSession and playing a silent
//  looped audio buffer. Used during long encodes (Compress + Stitch) when
//  the user has opted in via Settings.
//
//  Only active when `UserDefaults.standard.bool(forKey: "allowBackgroundEncoding")`
//  is true. Default OFF — the toggle is in the Settings tab.
//

import Foundation
import AVFoundation
import UIKit

@MainActor
final class AudioBackgroundKeeper {
    static let shared = AudioBackgroundKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var refCount = 0

    private init() {}

    /// Enable for the duration of an encode. Idempotent — multiple
    /// concurrent encodes share the same audio session via refcount.
    func begin() {
        guard UserDefaults.standard.bool(forKey: "allowBackgroundEncoding") else {
            return
        }
        refCount += 1
        if refCount == 1 {
            startAudio()
        }
    }

    /// Decrement the refcount; when it hits zero, deactivate the audio
    /// session so we're not silently playing forever.
    func end() {
        guard refCount > 0 else { return }
        refCount -= 1
        if refCount == 0 {
            stopAudio()
        }
    }

    private func startAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            // Generate a 1-second silent PCM buffer file in tmp once.
            let url = silentTrackURL()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1   // infinite loop
            audioPlayer?.volume = 0.0
            audioPlayer?.play()
        } catch {
            // Fail-soft. If audio session activation fails, fall back to
            // the existing UIBackgroundTask grace window.
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Lazily generates a 1-second silent .m4a in tmp.
    private func silentTrackURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("silent.m4a")
        if FileManager.default.fileExists(atPath: tmp.path) {
            return tmp
        }
        // Write a 1-second silent AAC buffer via AVAudioFile.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frameCapacity = AVAudioFrameCount(44100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
        buffer.frameLength = frameCapacity
        // Buffer is zero-initialized → silent.

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            let file = try AVAudioFile(forWriting: tmp, settings: settings)
            try file.write(from: buffer)
        } catch {
            // If we can't generate, return a path that doesn't exist —
            // AVAudioPlayer init will fail in startAudio, fail-soft kicks in.
        }
        return tmp
    }
}
