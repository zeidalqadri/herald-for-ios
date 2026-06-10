//
//  MeshKitSurface.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

// NWPathMonitor is Apple-only. On Linux the monitor is a no-op — call flush() manually.
#if canImport(Network)
import Network
#endif

/// Callback interface for surface flush delivery results.
public protocol MeshKitSurfaceDelegate: AnyObject {
    func meshKitSurface(didDeliver envelope: MeshKitEnvelope)
    func meshKitSurface(didFailDelivery envelope: MeshKitEnvelope, error: Error)
}

/// Error types for surface delivery failures.
public enum MeshKitSurfaceError: Error {
    case httpError(Int)
}

/// Injectable HTTP client — override in tests to avoid real network calls.
public protocol MeshKitHTTPClient {
    /// POST `body` to `url`. Returns HTTP status code.
    func post(url: URL, body: Data, completion: @escaping (Result<Int, Error>) -> Void)
}

/// Default implementation using URLSession (Apple platforms only).
#if !os(Linux)
final class URLSessionHTTPClient: MeshKitHTTPClient {
    func post(url: URL, body: Data, completion: @escaping (Result<Int, Error>) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let http = response as? HTTPURLResponse {
                completion(.success(http.statusCode))
            } else {
                completion(.failure(MeshKitSurfaceError.httpError(-1)))
            }
        }.resume()
    }
}
#endif

/// Drains the MeshKit envelope queue to a remote relay endpoint when
/// internet connectivity is available.
///
/// Usage:
/// ```swift
/// let surface = MeshKitSurface(queue: queue, endpointURL: URL(string: "https://relay.example.com/meshkit/envelopes")!)
/// surface.start() // starts NWPathMonitor; auto-flushes on connectivity change
/// surface.flush() // manual flush
/// ```
public final class MeshKitSurface {

    public let endpointURL: URL
    private let queue: MeshKitQueue
    private let httpClient: MeshKitHTTPClient
    private let deliveryQueue = DispatchQueue(label: "io.meshkit.surface.delivery")

    public weak var delegate: MeshKitSurfaceDelegate?

#if canImport(Network)
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "io.meshkit.surface.monitor")
#endif

    public init(queue: MeshKitQueue, endpointURL: URL, httpClient: MeshKitHTTPClient? = nil) {
        self.queue = queue
        self.endpointURL = endpointURL
        #if os(Linux)
        precondition(httpClient != nil, "On Linux, httpClient must be provided explicitly")
        self.httpClient = httpClient!
        #else
        self.httpClient = httpClient ?? URLSessionHTTPClient()
        #endif
    }

#if canImport(Network)
    /// Start network monitoring. Automatically flushes the queue when internet comes back.
    public func start() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.flush()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stop network monitoring.
    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
#endif

    /// Drain all queued envelopes and deliver them to the remote endpoint.
    /// Safe to call from any thread. Non-blocking.
    public func flush() {
        let envelopes = queue.drain()
        guard !envelopes.isEmpty else { return }
        deliveryQueue.async { [weak self] in
            guard let self = self else { return }
            for envelope in envelopes {
                self.deliver(envelope)
            }
        }
    }

    // MARK:- Private

    private func deliver(_ envelope: MeshKitEnvelope) {
        httpClient.post(url: endpointURL, body: envelope.serialize()) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let status) where status == 200:
                self.delegate?.meshKitSurface(didDeliver: envelope)
            case .success(let status):
                self.delegate?.meshKitSurface(
                    didFailDelivery: envelope,
                    error: MeshKitSurfaceError.httpError(status)
                )
                self.queue.enqueue(envelope) // re-enqueue for next surface
            case .failure(let error):
                self.delegate?.meshKitSurface(didFailDelivery: envelope, error: error)
                self.queue.enqueue(envelope)
            }
        }
    }
}
