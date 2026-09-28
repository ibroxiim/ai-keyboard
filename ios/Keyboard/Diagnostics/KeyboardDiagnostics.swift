import UIKit

/// One keyboard appearance under the Diagnostika switch. Costs nothing between keystrokes — no timers, no
/// threads: a run loop observer, a notification and two process snapshots. `finish()` builds the summary.
@MainActor
final class KeyboardDiagnostics {
    var journal: TouchJournal
    private let startDate = Date()
    private let startUptime: TimeInterval
    private let startCPU = ProcessStats.cpuSeconds()
    private let startMemory = ProcessStats.memoryMB()
    private var memoryWarnings = 0
    private var thermal: [DiagnosticSession.Thermal] = []
    private var thermalObserver: NSObjectProtocol?
    private let mainThread = MainThreadMonitor()

    init(testMode: Bool) {
        let uptime = ProcessInfo.processInfo.systemUptime
        startUptime = uptime
        journal = TouchJournal(keepsDetail: testMode, start: uptime)
        thermal = [.init(state: ProcessInfo.processInfo.thermalState.name, t: 0)]
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordThermalState() }
        }
        mainThread.start()
    }

    func memoryWarning() {
        memoryWarnings += 1
    }

    func finish() -> DiagnosticSession {
        mainThread.stop()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
        let duration = ProcessInfo.processInfo.systemUptime - startUptime
        let cpuSeconds = ProcessStats.cpuSeconds() - startCPU
        return DiagnosticSession(
            start: startDate, duration: duration, testMode: journal.keepsDetail,
            touches: journal.touches, typed: journal.typed, outcomes: journal.outcomes, zones: journal.zones,
            upToInsertMs: .init(samples: journal.upToInsertMs), deliveryMs: .init(samples: journal.deliveryMs),
            mainBusy: mainThread.summary,
            cpu: .init(seconds: cpuSeconds, percent: duration > 0 ? cpuSeconds / duration * 100 : 0),
            memoryMB: .init(start: startMemory, end: ProcessStats.memoryMB(), warnings: memoryWarnings),
            thermal: thermal, detail: journal.keepsDetail ? journal.detail : nil)
    }

    private func recordThermalState() {
        thermal.append(.init(
            state: ProcessInfo.processInfo.thermalState.name,
            t: ProcessInfo.processInfo.systemUptime - startUptime))
    }
}

/// How long the main run loop stays busy between two sleeps. A stretch over 50 ms is what feels like a stuck key.
final class MainThreadMonitor {
    private var observer: CFRunLoopObserver?
    private var wokeAt: TimeInterval?
    private var over50ms = 0
    private var maxMs: Double = 0

    var summary: DiagnosticSession.MainBusy { .init(over50ms: over50ms, maxMs: maxMs) }

    func start() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { [weak self] _, activity in
            self?.handle(activity)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
    }

    private func handle(_ activity: CFRunLoopActivity) {
        let now = ProcessInfo.processInfo.systemUptime
        if activity.contains(.afterWaiting) {
            wokeAt = now
        } else if activity.contains(.beforeWaiting), let wokeAt {
            let ms = (now - wokeAt) * 1000
            if ms > 50 { over50ms += 1 }
            maxMs = max(maxMs, ms)
            self.wokeAt = nil
        }
    }
}

/// Process-wide CPU time and memory, read twice per session.
enum ProcessStats {
    /// User + system CPU time of all threads, finished ones included, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The footprint jetsam judges the extension by, in MB.
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

extension ProcessInfo.ThermalState {
    var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
