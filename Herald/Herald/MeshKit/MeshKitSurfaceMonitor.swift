//
//  MeshKitSurfaceMonitor.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

#if canImport(Network)
import Network

/// Called when internet connectivity returns after being offline.
/// The app layer should POST these envelopes to the backend sync endpoint.
public protocol MeshKitSurfaceMonitorDelegate: AnyObject {
    func meshKit(didSurface envelopes: [MeshKitEnvelope])
}

/// Monitors network path status and drains the MeshKit queue when
/// connectivity transitions from unsatisfied to satisfied.
public final class MeshKitSurfaceMonitor {

    public weak var delegate: MeshKitSurfaceMonitorDelegate?
    private let queue: MeshKitQueue
    private let monitorQueue: DispatchQueue
    private var monitor: NWPathMonitor?
    private var wasUnsatisfied: Bool = false
    private var isRunning: Bool = false

    public init(queue: MeshKitQueue) {
        self.queue = queue
        self.monitorQueue = DispatchQueue(label: "io.meshkit.surfacemonitor")
    }

    /// Start monitoring. Safe to call multiple times.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        wasUnsatisfied = false
        let m = NWPathMonitor()
        monitor = m
        m.pathUpdateHandler = { [weak self] path in
            self?.handlePath(path)
        }
        m.start(queue: monitorQueue)
    }

    /// Stop monitoring. Safe to call multiple times.
    public func stop() {
        guard isRunning else { return }
        monitor?.cancel()
        monitor = nil
        isRunning = false
    }

    /// Current connectivity status.
    public var isConnected: Bool {
        monitor?.currentPath.status == .satisfied
    }

    deinit { stop() }

    // MARK:- Internal

    private func handlePath(_ path: NWPath) {
        if path.status == .satisfied {
            if wasUnsatisfied {
                surface()
            }
            wasUnsatisfied = false
        } else {
            wasUnsatisfied = true
        }
    }

    /// Internal: for testing. Simulates a connectivity transition.
    internal func simulateSurface() {
        let envelopes = queue.drain()
        if !envelopes.isEmpty {
            delegate?.meshKit(didSurface: envelopes)
        }
    }

    private func surface() {
        let envelopes = queue.drain()
        if !envelopes.isEmpty {
            delegate?.meshKit(didSurface: envelopes)
        }
    }
}

#endif // canImport(Network)
