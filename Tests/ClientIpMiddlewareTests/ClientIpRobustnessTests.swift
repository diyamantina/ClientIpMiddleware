import Foundation
import Testing
import Vapor
import VaporTesting

@testable import ClientIpMiddleware

/// Adversarial coverage for `ClientIpMiddleware`. Each test feeds the
/// middleware something a real attacker or a misconfigured proxy might emit
/// and asserts the output is still well-defined (and, where relevant,
/// secure).
@Suite("ClientIpMiddleware: adversarial / malformed inputs")
struct ClientIpRobustnessTests {

    actor Recorder {
        private(set) var ip: String?
        func record(_ value: String?) { ip = value }
    }

    private func makeApp(trustedProxyHops: Int) async throws -> (Application, Recorder) {
        let app = try await Application.make(.testing)
        let recorder = Recorder()
        app.middleware.use(ClientIpMiddleware(trustedProxyHops: trustedProxyHops))
        app.get("probe") { _ -> String in
            await recorder.record(ClientContext.clientIp)
            return "ok"
        }
        return (app, recorder)
    }

    // MARK: - Empty / whitespace XFF entries

    @Test("hops=1: XFF made entirely of empty entries falls back to remoteAddress")
    func allEmptyEntriesFallback() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: ", , , ,")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    @Test("hops=1: XFF with a single empty leading entry resolves to the real entry on the right")
    func leadingEmptyEntrySkipped() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                // Empty entries are filtered before counting hops.
                req.headers.replaceOrAdd(name: .xForwardedFor, value: ", 203.0.113.5")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.5")
        try await app.asyncShutdown()
    }

    @Test("hops=1: pathological whitespace and tabs are trimmed")
    func pathologicalWhitespace() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "\t \t1.2.3.4 \t,    \t203.0.113.7 \t "
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    // MARK: - Header injection / control characters

    @Test("hops=1: control-character-laden XFF does not crash")
    func controlCharactersDoNotCrash() async throws {
        // Per RFC 9112 a header value cannot contain CR/LF, but a
        // misbehaving upstream may still feed garbage. The middleware
        // should not panic; it should produce *some* string or nil.
        let (app, _) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "203.0.113.7\u{1F}, evil"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        try await app.asyncShutdown()
    }

    // MARK: - Pathological hops counts

    @Test("trustedProxyHops = Int.max is clamped at parts.count → fallback to remoteAddress")
    func absurdlyLargeHopsFallback() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: Int.max)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        // Asked for more hops than entries → fallback to remoteAddress (nil
        // under app.testing()).
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    @Test("hops=1: 50-entry XFF chain resolves to rightmost without iteration explosion")
    func longChain() async throws {
        let entries = (1...50).map { "10.0.0.\($0)" }.joined(separator: ", ")
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: entries)
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "10.0.0.50")
        try await app.asyncShutdown()
    }

    // MARK: - Non-IP garbage (the middleware does NOT validate)

    @Test("hops=1: non-IP garbage is captured verbatim, middleware doesn't validate the value")
    func garbageInGarbageOut() async throws {
        // Confirm the middleware is honest about its scope: it doesn't
        // promise the captured string is a valid IP. Validation, if needed,
        // is a downstream concern.
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "definitely-not-an-ip")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "definitely-not-an-ip")
        try await app.asyncShutdown()
    }

    // MARK: - IPv6 with port

    @Test("hops=1: bracketed IPv6 with port is preserved verbatim")
    func ipv6WithPort() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "[2001:db8::1]:443"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "[2001:db8::1]:443")
        try await app.asyncShutdown()
    }

    // MARK: - Concurrent requests do not cross-contaminate task-locals

    @Test("100 concurrent requests with distinct XFF headers each see their own IP")
    func noCrossRequestContamination() async throws {
        let app = try await Application.make(.testing)
        app.middleware.use(ClientIpMiddleware(trustedProxyHops: 1))

        // Capture per-request what BackendThe middleware put in the task-local.
        actor MultiRecorder {
            private(set) var observations: [Int: String] = [:]
            func record(id: Int, ip: String?) { observations[id] = ip ?? "<nil>" }
        }
        let recorder = MultiRecorder()

        app.get("probe", ":id") { req -> String in
            let id = Int(req.parameters.get("id") ?? "-1") ?? -1
            await recorder.record(id: id, ip: ClientContext.clientIp)
            return "ok"
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let expectedIP = "10.0.0.\(i)"
                    try await app.testing().test(
                        .GET, "probe/\(i)",
                        beforeRequest: { req in
                            req.headers.replaceOrAdd(name: .xForwardedFor, value: expectedIP)
                        }
                    ) { res async in
                        #expect(res.status == .ok)
                    }
                }
            }
            try await group.waitForAll()
        }

        // Each request must see exactly its own IP.
        for i in 0..<100 {
            let observed = await recorder.observations[i]
            #expect(observed == "10.0.0.\(i)", "request \(i) saw \(observed ?? "<nothing>")")
        }
        try await app.asyncShutdown()
    }
}
