@testable import ClientIpMiddleware
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("ClientIpMiddleware")
struct ClientIpMiddlewareTests {
    /// Records what the task-locals were at handler-time, so tests can verify
    /// the middleware captured the right values.
    actor Recorder {
        private(set) var ip: String?
        private(set) var ua: String?
        func record(ip: String?, ua: String?) {
            self.ip = ip
            self.ua = ua
        }
    }

    private func makeApp(trustedProxyHops: Int = 0) async throws -> (Application, Recorder) {
        let app = try await Application.make(.testing)
        let recorder = Recorder()
        app.middleware.use(ClientIpMiddleware(trustedProxyHops: trustedProxyHops))
        app.get("probe") { _ -> String in
            await recorder.record(
                ip: ClientContext.clientIp,
                ua: ClientContext.userAgent
            )
            return "ok"
        }
        return (app, recorder)
    }

    // MARK: - Default (trustedProxyHops = 0): ignore X-Forwarded-For entirely

    @Test("default hops=0: X-Forwarded-For is ignored, falls back to remoteAddress")
    func defaultIgnoresXFF() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        // app.testing() doesn't simulate a socket-level remoteAddress, so the
        // result is nil. The point is that "203.0.113.7" is NOT picked up.
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    @Test("default hops=0: spoofed XFF is ignored")
    func defaultIgnoresSpoofedXFF() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "1.2.3.4")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    // MARK: - trustedProxyHops = 1 (single proxy in front)

    @Test("hops=1: rightmost XFF entry wins (single proxy added one hop)")
    func hops1RightmostWins() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("hops=1: client spoof + proxy append → rightmost (real client) wins")
    func hops1ResistsClientSpoof() async throws {
        // Client sends spoofed XFF; the trusted proxy appends the actual TCP
        // source it observed. With hops=1 we pick the proxy-added rightmost
        // entry, ignoring the client's lie.
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "1.2.3.4, 203.0.113.7"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("hops=1: missing XFF falls back to remoteAddress")
    func hops1FallbackToRemoteAddress() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(.GET, "probe") { res async in
            #expect(res.status == .ok)
        }
        // Vapor app.testing() doesn't supply remoteAddress.
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    @Test("hops=1: whitespace around the picked entry is trimmed")
    func hops1TrimsWhitespace() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "1.2.3.4 ,    203.0.113.7   "
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    // MARK: - trustedProxyHops = 2 (two proxies in front)

    @Test("hops=2: 2nd-from-right entry wins (real client)")
    func hops2PicksSecondFromRight() async throws {
        // CDN → nginx → app. Client connects to CDN; CDN puts client IP into
        // XFF; nginx appends CDN-IP. App receives `client, cdn`. Wait, that's
        // hops=1 because app sees one proxy (nginx). Two hops requires:
        // CDN → nginx → app, where CDN appends client to XFF, nginx appends
        // cdn-IP to XFF. App sees `client, cdn`. App's remoteAddress is nginx.
        // With hops=2 trusted (nginx + CDN both trusted), index = count-2 = 0
        // → "client".
        let (app, recorder) = try await makeApp(trustedProxyHops: 2)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "203.0.113.7, 198.51.100.10"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("hops=2 with a client-spoofed prepend → still resolves to real client")
    func hops2IgnoresSpoofedPrepend() async throws {
        // Client sends `spoof` to CDN. CDN appends client-IP. Nginx appends
        // CDN-IP. App sees `spoof, client, cdn`. Trusted hops=2 (nginx, CDN).
        // index = 3 - 2 = 1 → "client". Spoof is ignored because it's outside
        // the trusted-hops window.
        let (app, recorder) = try await makeApp(trustedProxyHops: 2)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "1.2.3.4, 203.0.113.7, 198.51.100.10"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("hops=2 but only 1 XFF entry → fallback to remoteAddress")
    func hops2InsufficientEntriesFallback() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 2)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "1.2.3.4")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == nil)
        try await app.asyncShutdown()
    }

    // MARK: - IPv6

    @Test("IPv6 client IP is captured verbatim under hops=1")
    func hops1IPv6() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "2001:db8::1"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "2001:db8::1")
        try await app.asyncShutdown()
    }

    // MARK: - User-Agent (unchanged across hops settings)

    @Test("captures User-Agent verbatim")
    func userAgentVerbatim() async throws {
        let (app, recorder) = try await makeApp()
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .userAgent, value: ua)
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ua == ua)
        try await app.asyncShutdown()
    }

    @Test("missing User-Agent header → nil in task-local")
    func userAgentMissingIsNil() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(.GET, "probe") { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ua == nil)
        try await app.asyncShutdown()
    }

    // MARK: - Combined behavior

    @Test("hops=1: captures both IP and User-Agent in the same request")
    func capturesBoth() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7")
                req.headers.replaceOrAdd(name: .userAgent, value: "curl/8.7.1")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        await #expect(recorder.ua == "curl/8.7.1")
        try await app.asyncShutdown()
    }

    @Test("missing both headers and no remoteAddress → both task-locals are nil")
    func bothMissingAreNil() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(.GET, "probe") { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == nil)
        await #expect(recorder.ua == nil)
        try await app.asyncShutdown()
    }

    // MARK: - Cross-request isolation

    @Test("task-locals do not leak across sibling requests")
    func noLeakAcrossRequests() async throws {
        let (app, recorder) = try await makeApp(trustedProxyHops: 1)

        // First request sets values.
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7")
                req.headers.replaceOrAdd(name: .userAgent, value: "agent-A")
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        await #expect(recorder.ua == "agent-A")

        // Second request without those headers must observe fresh nil values.
        try await app.testing().test(.GET, "probe") { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == nil)
        await #expect(recorder.ua == nil)

        try await app.asyncShutdown()
    }

    // MARK: - Direct middleware call (no Vapor app, hand-built Request)

    @Test("direct call hops=1: rightmost XFF entry wins")
    func directCallHops1RightmostWins() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        let req = Request(
            application: app,
            method: .GET,
            url: URI(path: "/probe"),
            on: app.eventLoopGroup.next()
        )
        req.headers.replaceOrAdd(name: .xForwardedFor, value: "1.2.3.4, 203.0.113.7")
        req.headers.replaceOrAdd(name: .userAgent, value: "test-ua")

        struct Recorded: AsyncResponder {
            let recorder: Recorder
            func respond(to _: Request) async throws -> Response {
                await recorder.record(
                    ip: ClientContext.clientIp,
                    ua: ClientContext.userAgent
                )
                return Response(status: .ok)
            }
        }

        let recorder = Recorder()
        let response = try await ClientIpMiddleware(trustedProxyHops: 1).respond(
            to: req,
            chainingTo: Recorded(recorder: recorder)
        )
        #expect(response.status == .ok)
        await #expect(recorder.ip == "203.0.113.7")
        await #expect(recorder.ua == "test-ua")
    }

    // MARK: - Negative trustedProxyHops is clamped to 0

    @Test("negative trustedProxyHops is clamped to 0")
    func negativeHopsClamped() {
        let mw = ClientIpMiddleware(trustedProxyHops: -3)
        #expect(mw.trustedProxyHops == 0)
    }
}
