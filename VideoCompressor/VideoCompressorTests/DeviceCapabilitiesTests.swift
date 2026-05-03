//
//  DeviceCapabilitiesTests.swift
//  VideoCompressorTests
//
//  Phase 3 Commit 8: Tests for DeviceCapabilities model-ID classification
//  and thermal-aware concurrency logic.
//

import Testing
@testable import VideoCompressor_iOS

struct DeviceCapabilitiesTests {

    // MARK: - deviceClass(for:)

    @Test func proIdentifiers_returnProClass() {
        let proIDs = [
            "iPhone14,2", "iPhone14,3",   // 13 Pro / 13 Pro Max
            "iPhone15,2", "iPhone15,3",   // 14 Pro / 14 Pro Max
            "iPhone16,1", "iPhone16,2",   // 15 Pro / 15 Pro Max
            "iPhone17,1", "iPhone17,2",   // 16 Pro / 16 Pro Max
            "iPhone18,1", "iPhone18,2",   // 17 Pro / 17 Pro Max
        ]
        for id in proIDs {
            #expect(
                DeviceCapabilities.deviceClass(for: id) == .pro,
                "Expected .pro for \(id)"
            )
        }
    }

    @Test func standardIdentifiers_returnStandardClass() {
        let standardIDs = [
            "iPhone14,4",   // 13 mini
            "iPhone14,5",   // 13
            "iPhone15,4",   // 14
            "iPhone15,5",   // 14 Plus
            "iPhone17,3",   // 16
            "iPhone17,4",   // 16 Plus / Plus variant
        ]
        for id in standardIDs {
            #expect(
                DeviceCapabilities.deviceClass(for: id) == .standard,
                "Expected .standard for \(id)"
            )
        }
    }

    @Test func nonIPhoneIdentifier_returnsUnknown() {
        // Simulator hw.machine returns arm64 or similar, not an iPhone ID.
        #expect(DeviceCapabilities.deviceClass(for: "arm64") == .unknown)
        #expect(DeviceCapabilities.deviceClass(for: "x86_64") == .unknown)
        #expect(DeviceCapabilities.deviceClass(for: "iPad14,6") == .unknown)
        #expect(DeviceCapabilities.deviceClass(for: "") == .unknown)
    }

    // MARK: - safeConcurrency(deviceClass:thermalState:)

    @Test func proConcurrency_nominalThermal_returns2() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .pro, thermalState: .nominal) == 2)
    }

    @Test func proConcurrency_fairThermal_returns2() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .pro, thermalState: .fair) == 2)
    }

    @Test func proConcurrency_seriousThermal_returns1() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .pro, thermalState: .serious) == 1)
    }

    @Test func proConcurrency_criticalThermal_returns1() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .pro, thermalState: .critical) == 1)
    }

    @Test func standardConcurrency_nominalThermal_returns1() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .standard, thermalState: .nominal) == 1)
    }

    @Test func unknownConcurrency_nominalThermal_returns1() {
        #expect(DeviceCapabilities.safeConcurrency(deviceClass: .unknown, thermalState: .nominal) == 1)
    }

    // MARK: - recommendedEncodeConcurrency

    @Test func recommendedConcurrency_isConsistentWithDeviceClass() {
        // On simulator hw.machine will NOT be a Pro identifier, so
        // recommendedEncodeConcurrency must be 1.
        let cls = DeviceCapabilities.deviceClass
        let expected = cls == .pro ? 2 : 1
        #expect(DeviceCapabilities.recommendedEncodeConcurrency == expected)
    }
}
