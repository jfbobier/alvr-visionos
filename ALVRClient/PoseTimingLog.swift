//
//  PoseTimingLog.swift
//
// Telemetry for pose / timestamp handling. Compiled only with the ALVR_TELEMETRY condition
// (the "telemetry" builds); the normal build contains none of this.
//
// For every displayed frame it relates three poses: the one the client measured when it sent the
// tracking sample (and how far Apple's anchor query had to be walked back to get it), the one the
// host rendered for (the client core extrapolates the sent pose by the pipeline latency), and the
// one the display will actually have. The difference between the last two is what the reprojection
// has to hide: its rotation part is corrected, its translation part is not.
//
// It also runs a fixed A/B schedule so a single play session covers every condition: after a
// warm-up, 20 segments of 45 s change the reprojection focal depth and the frame-pick policy on the
// client; the streamer changes its own re-stamp mode on the same numbering (it starts its clock when
// it sees the `[pt] start` line). Everything is reported through the client log channel as lines
// starting with `[pt] `:
//
//   [pt] start n=.. ver=1 build=.. renderer=rk|metal telemetry=1
//   [pt] cond n=.. seg=.. focal=0|2.5 pick=oldest|newest t=..
//   [pt] sum  n=.. seg=.. frames=.. repeat=.. nosend=.. walkback=.. ... (once per second)
//   [pt] rows n=.. seg=.. cols=a,b,c | v;v;v ; v;v;v ...                (~12 frames per line)
//   [pt] end  n=..
//
// The log channel only forwards ERROR level by default (extra.logging.client_log_report_level), so
// the lines are sent at that level; consecutive identical lines are merged by the logging backend,
// hence the unique n=.. counter. A copy of the per-frame rows is also written to Documents/pose_timing.csv.
//

#if ALVR_TELEMETRY

import Foundation
import simd

/// Conditions the schedule changes at run time; read by the renderers.
enum TelemetryConditions {
    /// Focal depth (meters) of the reprojection plane; nil = use the user's setting.
    static var focalDepth: Float? = nil
    /// Take the newest decoded frame instead of the oldest when two are waiting.
    static var pickNewest = false
}

final class Telemetry {
    static let shared = Telemetry()

    // MARK: - Schedule

    private static let warmupS = 120.0
    private static let segmentS = 45.0
    // Per segment (1...20): reprojection focal depth in meters (0 = default) and pick policy.
    // Tier A (1-12): focal depth crossed with the streamer's re-stamp mode; Tier B (13-20): pick policy crossed with it.
    private static let focalBySegment: [Float] = [0, 0, 0, 2.5, 2.5, 2.5,  2.5, 2.5, 2.5, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0]
    private static let newestBySegment: [Bool] = [false, false, false, false, false, false,  false, false, false, false, false, false,
                                                  false, true, false, true,  true, false, true, false]
    private static let columns = "present_s,timestamp_ns,age_ms,repeated,had_send,walkback_ms,anchor_minus_used_ms,fallback,extrap_deg,extrap_mm,comp_deg,comp_mm,dcomp_deg,dcomp_mm,head_deg_s,gpu_ms,decode_ms,queue_ms"

    // MARK: - State (all on `q`)

    private let q = DispatchQueue(label: "alvr.telemetry", qos: .utility)

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
        var hadSend: Bool
        var walkBackMs: Double
        var anchorMinusUsedMs: Double
        var usedFallback: Bool
        var extrapDeg: Double
        var extrapMm: Double
        var compDeg: Double
        var compMm: Double
        var dCompDeg: Double
        var dCompMm: Double
        var headDegS: Double
        var decodeMs: Double?
        var queueMs: Double?
    }

    private var sent: [UInt64: Sent] = [:]
    private var sentOrder: [UInt64] = []
    private var recvNs: [UInt64: UInt64] = [:]
    private var decodedNs: [UInt64: UInt64] = [:]
    private var timingOrder: [UInt64] = []

    private var rows: [Row] = []          // rows of the current second (for the summary)
    private var pendingRows: [Row] = []   // rows not yet sent
    private var gpuMs: [Double] = []
    private var accessoryLast: [Bool: Double] = [:]
    private var accessoryDt: [Bool: [Double]] = [:]
    private var lastSummary = 0.0
    private var lastComp = (deg: 0.0, mm: 0.0)
    private var lastTimestampNs: UInt64 = 0
    private var lastAnchor: simd_float4x4? = nil
    private var lastPresent = 0.0
    private var lastDisplayCall = 0.0

    private var active = false
    private var finished = false
    private var t0 = 0.0
    private var segment = -1
    private var seq = 0
    private var csv: FileHandle?

    private init() {}

    // MARK: - Recording (callable from any thread; cheap)

    func recordReceive(timestampNs: UInt64) {
        let now = PerfClock.nowNs()
        q.async {
            self.recvNs[timestampNs] = now
            self.timingOrder.append(timestampNs)
            if self.timingOrder.count > 512 {
                let old = self.timingOrder.removeFirst()
                self.recvNs.removeValue(forKey: old)
                self.decodedNs.removeValue(forKey: old)
            }
        }
    }

    func recordDecoded(timestampNs: UInt64) {
        let now = PerfClock.nowNs()
        q.async { self.decodedNs[timestampNs] = now }
    }

    func recordGpu(ms: Double) {
        if ms > 0 { q.async { self.gpuMs.append(ms) } }
    }

    /// Called from sendTracking once the pose for `reportedNs` is known.
    func recordSend(reportedNs: UInt64, requestedTime: Double, usedTime: Double, anchorTime: Double, usedFallback: Bool, pose: simd_float4x4) {
        q.async {
            self.sent[reportedNs] = Sent(walkBackMs: (requestedTime - usedTime) * 1000.0,
                                         anchorMinusUsedMs: (anchorTime - usedTime) * 1000.0,
                                         usedFallback: usedFallback, pose: pose)
            self.sentOrder.append(reportedNs)
            if self.sentOrder.count > 512 {
                self.sent.removeValue(forKey: self.sentOrder.removeFirst())
            }
        }
    }

    /// Called for every accessory (controller) anchor update. `anchorTimestamp` is the anchor's own timestamp in seconds.
    func recordAccessoryUpdate(isLeft: Bool, anchorTimestamp: Double) {
        q.async {
            if let last = self.accessoryLast[isLeft] {
                self.accessoryDt[isLeft, default: []].append((anchorTimestamp - last) * 1000.0)
            }
            self.accessoryLast[isLeft] = anchorTimestamp
        }
    }

    /// Called once per displayed frame. `framePose` is the pose the host rendered for (from the client core),
    /// `anchorPose` the pose the display will use.
    func recordDisplay(timestampNs: UInt64, presentTimeS: Double, framePose: simd_float4x4, anchorPose: simd_float4x4, renderer: String) {
        let now = PerfClock.nowNs()
        q.async {
            self.display(timestampNs: timestampNs, presentTimeS: presentTimeS, framePose: framePose, anchorPose: anchorPose, renderer: renderer, nowNs: now)
        }
    }

    // MARK: - On the queue

    private func display(timestampNs: UInt64, presentTimeS: Double, framePose: simd_float4x4, anchorPose: simd_float4x4, renderer: String, nowNs: UInt64) {
        let wall = Double(nowNs) / 1e9
        // A long gap means the stream restarted: begin a new run of the schedule.
        if active && wall - lastDisplayCall > 15.0 {
            finishRun()
            finished = false
        }
        lastDisplayCall = wall
        if finished { return }
        if !active { startRun(wall: wall, renderer: renderer) }

        advanceSchedule(wall: wall)
        if finished { return }

        // Head speed from consecutive display anchors.
        var headDegS = 0.0
        if let prev = lastAnchor {
            let dt = presentTimeS - lastPresent
            if dt > 0.004 && dt < 0.05 {
                headDegS = Self.delta(prev, anchorPose).deg / dt
            }
        }
        lastAnchor = anchorPose
        lastPresent = presentTimeS

        let ageMs = presentTimeS * 1000.0 - Double(timestampNs) / 1_000_000.0
        let comp = Self.delta(framePose, anchorPose)
        let info = sent[timestampNs]
        let extrap = info.map { Self.delta($0.pose, framePose) } ?? (deg: 0.0, mm: 0.0)
        let repeated = timestampNs == lastTimestampNs
        lastTimestampNs = timestampNs
        let dMm = abs(comp.mm - lastComp.mm)
        let dDeg = abs(comp.deg - lastComp.deg)
        lastComp = comp

        var decodeMs: Double? = nil
        var queueMs: Double? = nil
        if let r = recvNs[timestampNs], let d = decodedNs[timestampNs], d >= r {
            decodeMs = Double(d - r) / 1e6
            if nowNs >= d { queueMs = Double(nowNs - d) / 1e6 }
        }

        let row = Row(presentTimeS: presentTimeS, timestampNs: timestampNs, ageMs: ageMs, repeated: repeated,
                      hadSend: info != nil, walkBackMs: info?.walkBackMs ?? 0, anchorMinusUsedMs: info?.anchorMinusUsedMs ?? 0,
                      usedFallback: info?.usedFallback ?? false, extrapDeg: extrap.deg, extrapMm: extrap.mm,
                      compDeg: comp.deg, compMm: comp.mm, dCompDeg: dDeg, dCompMm: dMm, headDegS: headDegS,
                      decodeMs: decodeMs, queueMs: queueMs)
        rows.append(row)
        pendingRows.append(row)
        if pendingRows.count >= 12 { flushRows() }

        if wall - lastSummary >= 1.0 {
            if lastSummary > 0 { summarize() }
            lastSummary = wall
            rows.removeAll(keepingCapacity: true)
        }
    }

    private func startRun(wall: Double, renderer: String) {
        active = true
        t0 = wall
        segment = -1
        lastSummary = 0
        rows.removeAll()
        pendingRows.removeAll()
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        emit("start ver=1 build=\(build) renderer=\(renderer) telemetry=1")
    }

    private func advanceSchedule(wall: Double) {
        let elapsed = wall - t0
        let total = Self.warmupS + Double(Self.focalBySegment.count) * Self.segmentS
        if elapsed >= total {
            finishRun()
            return
        }
        let seg = elapsed < Self.warmupS ? 0 : 1 + Int((elapsed - Self.warmupS) / Self.segmentS)
        if seg != segment {
            flushRows()
            segment = seg
            let focal: Float = seg == 0 ? 0 : Self.focalBySegment[seg - 1]
            let newest = seg == 0 ? false : Self.newestBySegment[seg - 1]
            TelemetryConditions.focalDepth = focal > 0 ? focal : nil
            TelemetryConditions.pickNewest = newest
            emit(String(format: "cond seg=%d focal=%@ pick=%@ t=%.3f", seg, focal > 0 ? "2.5" : "0", newest ? "newest" : "oldest", wall))
        }
    }

    private func finishRun() {
        flushRows()
        TelemetryConditions.focalDepth = nil
        TelemetryConditions.pickNewest = false
        if active { emit("end") }
        active = false
        finished = true
        segment = -1
    }

    // MARK: - Output

    private func emit(_ body: String) {
        seq += 1
        // Format: "[pt] <verb> n=<seq> <rest>"
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let verb = parts.first.map(String.init) ?? body
        let rest = parts.count > 1 ? " " + String(parts[1]) : ""
        let line = "[pt] \(verb) n=\(seq)\(rest)"
        // ERROR level: the default client_log_report_level only forwards errors.
        line.withCString { alvr_log(UInt8(ALVR_LOG_LEVEL_ERROR.rawValue), $0) }
    }

    private func f(_ v: Double, _ digits: Int = 4) -> String {
        return String(format: "%.\(digits)f", v)
    }

    private func flushRows() {
        if pendingRows.isEmpty { return }
        var csvText = ""
        var cells: [String] = []
        for r in pendingRows {
            let cols = [String(format: "%.5f", r.presentTimeS), String(r.timestampNs), f(r.ageMs, 3), r.repeated ? "1" : "0", r.hadSend ? "1" : "0",
                        f(r.walkBackMs, 3), f(r.anchorMinusUsedMs, 3), r.usedFallback ? "1" : "0", f(r.extrapDeg), f(r.extrapMm, 3),
                        f(r.compDeg), f(r.compMm, 3), f(r.dCompDeg), f(r.dCompMm, 3), f(r.headDegS, 2), "",
                        r.decodeMs.map { f($0, 3) } ?? "", r.queueMs.map { f($0, 3) } ?? ""]
            cells.append(cols.joined(separator: ","))
            csvText += "\(max(segment, 0))," + cols.joined(separator: ",") + "\n"
        }
        emit("rows seg=\(segment) cols=\(Self.columns) | " + cells.joined(separator: ";"))
        writeCsv(csvText)
        pendingRows.removeAll(keepingCapacity: true)
    }

    private func writeCsv(_ text: String) {
        if csv == nil {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pose_timing.csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: "seg,\(Self.columns)\n".data(using: .utf8))
            }
            csv = try? FileHandle(forWritingTo: url)
            _ = try? csv?.seekToEnd()
        }
        if let data = text.data(using: .utf8) { try? csv?.write(contentsOf: data) }
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        if values.isEmpty { return 0 }
        let s = values.sorted()
        return s[Int(p * Double(s.count - 1))]
    }

    private func summarize() {
        let n = rows.count
        if n == 0 { return }
        func col(_ k: (Row) -> Double?) -> [Double] { rows.compactMap(k) }
        let pc = { (v: [Double], p: Double) in self.percentile(v, p) }
        var parts = ["seg=\(segment)", "frames=\(n)",
                     "repeat=\(rows.filter { $0.repeated }.count)",
                     "nosend=\(rows.filter { !$0.hadSend }.count)",
                     "walkback=\(rows.filter { $0.walkBackMs > 0.5 }.count)",
                     "walkback_max=" + f(rows.map { $0.walkBackMs }.max() ?? 0, 1),
                     "fallback=\(rows.filter { $0.usedFallback }.count)"]
        let age = col { $0.ageMs }, ed = col { $0.extrapDeg }, em = col { $0.extrapMm }
        let cd = col { $0.compDeg }, cm = col { $0.compMm }, dd = col { $0.dCompDeg }, dm = col { $0.dCompMm }
        parts += ["age_p50=" + f(pc(age, 0.5), 2), "age_p95=" + f(pc(age, 0.95), 2),
                  "extrap_deg_p50=" + f(pc(ed, 0.5)), "extrap_deg_p95=" + f(pc(ed, 0.95)),
                  "extrap_mm_p50=" + f(pc(em, 0.5), 3), "extrap_mm_p95=" + f(pc(em, 0.95), 3),
                  "comp_deg_p50=" + f(pc(cd, 0.5)), "comp_deg_p95=" + f(pc(cd, 0.95)),
                  "comp_mm_p50=" + f(pc(cm, 0.5), 3), "comp_mm_p95=" + f(pc(cm, 0.95), 3),
                  "dcomp_deg_p95=" + f(pc(dd, 0.95)), "dcomp_mm_p95=" + f(pc(dm, 0.95), 3)]
        for (isLeft, name) in [(true, "L"), (false, "R")] {
            if let d = accessoryDt[isLeft], d.count > 3 {
                let mean = d.reduce(0, +) / Double(d.count)
                parts.append("ctrl\(name)_hz=" + f(1000.0 / max(mean, 0.001), 1))
                parts.append("ctrl\(name)_dt_p95=" + f(pc(d, 0.95), 2))
            }
            accessoryDt[isLeft] = []
        }
        parts.append("thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
        if !gpuMs.isEmpty { parts.append("gpu_ms_p95=" + f(pc(gpuMs, 0.95), 2)) }
        gpuMs.removeAll(keepingCapacity: true)
        let dec = col { $0.decodeMs }, qu = col { $0.queueMs }
        if !dec.isEmpty { parts.append("decode_ms_p95=" + f(pc(dec, 0.95), 2)) }
        if !qu.isEmpty { parts.append("queue_ms_p95=" + f(pc(qu, 0.95), 2)) }
        emit("sum " + parts.joined(separator: " "))
    }

    /// Rotation angle (degrees) and translation distance (millimetres) between two poses.
    private static func delta(_ a: simd_float4x4, _ b: simd_float4x4) -> (deg: Double, mm: Double) {
        let qa = simd_quatf(a), qb = simd_quatf(b)
        let d = min(1.0, abs(Double(simd_dot(qa.vector, qb.vector))))
        let deg = 2.0 * acos(d) * 180.0 / Double.pi
        let dp = a.columns.3 - b.columns.3
        let mm = Double(simd_length(simd_float3(dp.x, dp.y, dp.z))) * 1000.0
        return (deg.isFinite ? deg : 0.0, mm.isFinite ? mm : 0.0)
    }
}

#endif
