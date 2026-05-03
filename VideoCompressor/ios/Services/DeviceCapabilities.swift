//
//  DeviceCapabilities.swift
//  VideoCompressor
//
//  Phase 3 Commit 8: Detects whether the running device is a Pro-tier iPhone
//  with multiple dedicated video encoder engines. Used by VideoLibrary to
//  drive TaskGroup concurrency in compressAll().
//
//  iPhone 13 Pro through 17 Pro each have 2 dedicated video encoder engines
//  on their A-series Pro SoCs. Using both roughly halves wall-clock time on
//  batches of 5+ clips. Non-Pro devices get concurrency = 1 (unchanged from
//  previous serial behavior). Concurrency drops back to 1 under thermal stress.
//

import Foundation
import UIKit

/// Detects whether the running device is a Pro-tier iPhone with multiple
/// dedicated video encoder engines (2× on A15 Pro / A16 Pro / A17 Pro / A18 Pro).
/// Returns the recommended encode concurrency.
struct DeviceCapabilities {

    // MARK: - Public API

    /// Returns 1 for non-Pro devices, 2 for Pro devices, 1 if uncertain.
    /// Conservative default — over-parallelizing on a base iPhone causes
    /// thermal throttle within 2–3 minutes of continuous encoding.
    static var recommendedEncodeConcurrency: Int {
        switch deviceClass {
        case .pro: return 2
        case .standard, .unknown: return 1
        }
    }

    enum DeviceClass {
        case pro
        case standard
        case unknown
    }

    /// Classifies the running device using its hw.machine identifier.
    static var deviceClass: DeviceClass {
        deviceClass(for: modelIdentifier())
    }

    /// Pure-function overload for testing — accepts an explicit identifier
    /// string instead of reading from the running hardware.
    static func deviceClass(for identifier: String) -> DeviceClass {
        // Known Pro identifiers:
        //   iPhone14,2 / iPhone14,3  — 13 Pro / 13 Pro Max  (A15 Bionic Pro)
        //   iPhone15,2 / iPhone15,3  — 14 Pro / 14 Pro Max  (A16 Bionic)
        //   iPhone16,1 / iPhone16,2  — 15 Pro / 15 Pro Max  (A17 Pro)
        //   iPhone17,1 / iPhone17,2  — 16 Pro / 16 Pro Max  (A18 Pro)
        //   iPhone18,1 / iPhone18,2  — 17 Pro / 17 Pro Max  (A19 Pro)
        let proIdentifiers: Set<String> = [
            "iPhone14,2", "iPhone14,3",   // 13 Pro / 13 Pro Max
            "iPhone15,2", "iPhone15,3",   // 14 Pro / 14 Pro Max
            "iPhone16,1", "iPhone16,2",   // 15 Pro / 15 Pro Max
            "iPhone17,1", "iPhone17,2",   // 16 Pro / 16 Pro Max
            "iPhone18,1", "iPhone18,2",   // 17 Pro / 17 Pro Max
        ]
        if proIdentifiers.contains(identifier) { return .pro }
        if identifier.hasPrefix("iPhone") { return .standard }
        return .unknown
    }

    /// Adjusts concurrency down when the device is thermally pressured.
    /// Falls back to 1 under .serious or .critical thermal state to prevent
    /// the device from throttling mid-encode (which causes stalls, not crashes,
    /// but produces degraded encode throughput and causes the batch to take
    /// longer than serial would have).
    static func currentSafeConcurrency() -> Int {
        safeConcurrency(
            deviceClass: deviceClass,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    /// Pure-function overload for testing.
    static func safeConcurrency(
        deviceClass: DeviceClass,
        thermalState: ProcessInfo.ThermalState
    ) -> Int {
        let baseline: Int = {
            switch deviceClass {
            case .pro: return 2
            case .standard, .unknown: return 1
            }
        }()
        switch thermalState {
        case .nominal, .fair: return baseline
        case .serious, .critical: return 1
        @unknown default: return 1
        }
    }

    // MARK: - Helpers

    /// Reads the hw.machine sysctl, e.g. "iPhone17,1".
    /// On the simulator this returns the Mac's identifier (e.g. "arm64") which
    /// won't match any iPhone prefix, so `deviceClass` will return `.unknown`
    /// and concurrency will safely default to 1.
    static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
