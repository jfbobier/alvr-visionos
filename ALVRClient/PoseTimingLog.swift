//
//  PoseTimingLog.swift
//
// Opt-in diagnostics for pose / timestamp handling (Settings > "Log pose timing").
//
// For every displayed frame it relates three poses: the one the client measured when it sent
// the tracking sample (and how far Apple's anchor query had to be walked back to get it), the
// one the host rendered for (the client core extrapolates the sent pose by the pipeline latency),
// and the one the display will actually have. The difference between the last two is what the
// reprojection in the shader has to hide: its rotation part is corrected, its translation part is not.
//
// One summary line per second goes to the host's log through alvr_log, so it ends up next to the
// host's own logs with no Mac needed to read it. Full per-frame rows go to Documents/pose_timing.csv
// (visible in the Files app).
//

import Foundation
import os
import simd

final class PoseTimingLog {
    static let shared = PoseTimingLog()

    /// What we knew when a tracking sample was sent.
    private struct Sent {
        var walkBackMs: Double
        var anchorMinusUsedMs: Double
        var usedFallback: Bool
        var pose: simd_float4x4
    }

    private struct Row {
        var presentTimeS: Double
        var timestampNs: UInt64
        var ageMs: Double
        var repeated: Bool
        var hadSendRecord: Bool
        var walkBackMs: Double
        var anchorMinusUsedMs: Double
        var usedFallback: Bool
        var extrapDeg: Double
        var extrapMm: Double
        var compDeg: Double
        var compMm: Double
        var dCompMm: Double
        var dCompDeg: Double
    }

    private let lock = OSAllocatedUnfairLock()
    private var sent: [UInt64: Sent] = [:]
    private var sentOrder: [UInt64] = []
    private var rows: [Row] = []
    private var lastSummaryTime = 0.0
    private var lastCompMm = 0.0
    private var lastCompDeg = 0.0
    private var lastTimestampNs: UInt64 = 0
    private var accessoryLastTimestamp: [Bool: Double] = [:]
    private var accessoryDeltasMs: [Bool: [Double]] = [:]
    private var csv: FileHandle?
    private var pendingCsv = ""

    private init() {}

    /// Called from sendTracking once the pose for `reportedNs` is known.
    func recordSend(reportedNs: UInt64, requestedTime: Double, usedTime: Double, anchorTime: Double, usedFallback: Bool, pose: simd_float4x4) {
        lock.withLock {
            sent[reportedNs] = Sent(walkBackMs: (requestedTime - usedTime) * 1000.0,
                                    anchorMinusUsedMs: (anchorTime - usedTime) * 1000.0,
                                    usedFallback: usedFallback,
                                    pose: pose)
            sentOrder.append(reportedNs)
            if sentOrder.count > 512 {
                sent.removeValue(forKey: sentOrder.removeFirst())
            }
        }
    }

    /// Called for every accessory (controller) anchor update. `anchorTimestamp` is the anchor's own timestamp in seconds.
    func recordAccessoryUpdate(isLeft: Bool, anchorTimestamp: Double) {
        lock.withLock {
            if let last = accessoryLastTimestamp[isLeft] {
                accessoryDeltasMs[isLeft, default: []].append((anchorTimestamp - last) * 1000.0)
            }
            accessoryLastTimestamp[isLeft] = anchorTimestamp
        }
    }

    /// Called once per displayed frame. `framePose` is the pose the host rendered for (from the client core),
    /// `anchorPose` the pose the display will use.
    func recordDisplay(timestampNs: UInt64, presentTimeS: Double, framePose: simd_float4x4, anchorPose: simd_float4x4) {
        // The client core stamps timestamps from the display clock (seconds); compare in the same unit.
        let ageMs = presentTimeS * 1000.0 - Double(timestampNs) / 1_000_000.0
        let comp = Self.delta(framePose, anchorPose)
        lock.withLock {
            let info = sent[timestampNs]
            let extrap = info.map { Self.delta($0.pose, framePose) } ?? (deg: 0.0, mm: 0.0)
            let repeated = timestampNs == lastTimestampNs
            // Frame-to-frame change of the uncorrected residual: this is what reads as tremble.
            let dMm = abs(comp.mm - lastCompMm)
            let dDeg = abs(comp.deg - lastCompDeg)
            lastCompMm = comp.mm
            lastCompDeg = comp.deg
            lastTimestampNs = timestampNs

            let row = Row(presentTimeS: presentTimeS, timestampNs: timestampNs, ageMs: ageMs, repeated: repeated,
                          hadSendRecord: info != nil, walkBackMs: info?.walkBackMs ?? 0, anchorMinusUsedMs: info?.anchorMinusUsedMs ?? 0,
                          usedFallback: info?.usedFallback ?? false, extrapDeg: extrap.deg, extrapMm: extrap.mm,
                          compDeg: comp.deg, compMm: comp.mm, dCompMm: dMm, dCompDeg: dDeg)
            rows.append(row)
            appendCsv(row)

            if presentTimeS - lastSummaryTime >= 1.0 {
                if lastSummaryTime > 0 {
                    summarize()
                }
                lastSummaryTime = presentTimeS
                rows.removeAll(keepingCapacity: true)
            }
        }
    }

    // MARK: - Helpers

    /// Rotation angle (degrees) and translation distance (millimetres) between two poses.
    private static func delta(_ a: simd_float4x4, _ b: simd_float4x4) -> (deg: Double, mm: Double) {
        let qa = simd_quatf(a), qb = simd_quatf(b)
        let d = min(1.0, abs(Double(simd_dot(qa.vector, qb.vector))))
        let deg = 2.0 * acos(d) * 180.0 / Double.pi
        let dp = a.columns.3 - b.columns.3
        let mm = Double(simd_length(simd_float3(dp.x, dp.y, dp.z))) * 1000.0
        return (deg.isFinite ? deg : 0.0, mm.isFinite ? mm : 0.0)
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        if values.isEmpty { return 0 }
        let s = values.sorted()
        return s[Int(p * Double(s.count - 1))]
    }

    private func summarize() {
        let n = rows.count
        if n == 0 { return }
        let repeats = rows.filter { $0.repeated }.count
        let noRecord = rows.filter { !$0.hadSendRecord }.count
        let walked = rows.filter { $0.walkBackMs > 0.5 }.count
        let fallback = rows.filter { $0.usedFallback }.count
        let age = rows.map { $0.ageMs }
        let walk = rows.map { $0.walkBackMs }
        let extrapDeg = rows.map { $0.extrapDeg }
        let extrapMm = rows.map { $0.extrapMm }
        let compDeg = rows.map { $0.compDeg }
        let compMm = rows.map { $0.compMm }
        let dMm = rows.map { $0.dCompMm }
        let dDeg = rows.map { $0.dCompDeg }
        let line = String(format: "[pose-timing] frames=%d repeat=%d nosend=%d walkback=%d(max %.1fms) fallback=%d age_ms p50/p95=%.1f/%.1f extrap deg p50/p95=%.2f/%.2f mm p50/p95=%.1f/%.1f comp deg p50/p95=%.2f/%.2f mm p50/p95=%.1f/%.1f dcomp deg p95=%.2f mm p95=%.1f",
                          n, repeats, noRecord, walked, walk.max() ?? 0, fallback,
                          percentile(age, 0.5), percentile(age, 0.95),
                          percentile(extrapDeg, 0.5), percentile(extrapDeg, 0.95), percentile(extrapMm, 0.5), percentile(extrapMm, 0.95),
                          percentile(compDeg, 0.5), percentile(compDeg, 0.95), percentile(compMm, 0.5), percentile(compMm, 0.95),
                          percentile(dDeg, 0.95), percentile(dMm, 0.95))
        var accessoryText = ""
        for (isLeft, name) in [(true, "L"), (false, "R")] {
            if let d = accessoryDeltasMs[isLeft], d.count > 3 {
                let mean = d.reduce(0, +) / Double(d.count)
                accessoryText += String(format: " ctrl%@ n=%d hz=%.1f dt_ms p50/p95/max=%.1f/%.1f/%.1f", name, d.count, 1000.0 / max(mean, 0.001),
                                        percentile(d, 0.5), percentile(d, 0.95), d.max() ?? 0)
            }
            accessoryDeltasMs[isLeft] = []
        }
        let fullLine = line + accessoryText
        fullLine.withCString { alvr_log(UInt8(ALVR_LOG_LEVEL_INFO.rawValue), $0) }
        flushCsv()
    }

    private func appendCsv(_ r: Row) {
        if csv == nil {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pose_timing.csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                pendingCsv += "present_s,timestamp_ns,age_ms,repeated,had_send,walkback_ms,anchor_minus_used_ms,fallback,extrap_deg,extrap_mm,comp_deg,comp_mm,dcomp_deg,dcomp_mm\n"
            }
            csv = try? FileHandle(forWritingTo: url)
            _ = try? csv?.seekToEnd()
        }
        pendingCsv += String(format: "%.6f,%llu,%.3f,%d,%d,%.3f,%.3f,%d,%.4f,%.3f,%.4f,%.3f,%.4f,%.3f\n",
                             r.presentTimeS, r.timestampNs, r.ageMs, r.repeated ? 1 : 0, r.hadSendRecord ? 1 : 0, r.walkBackMs,
                             r.anchorMinusUsedMs, r.usedFallback ? 1 : 0, r.extrapDeg, r.extrapMm, r.compDeg, r.compMm, r.dCompDeg, r.dCompMm)
    }

    private func flushCsv() {
        if let data = pendingCsv.data(using: .utf8), !data.isEmpty {
            try? csv?.write(contentsOf: data)
        }
        pendingCsv = ""
    }
}
