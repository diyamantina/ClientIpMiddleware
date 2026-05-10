import Foundation
import Testing
import Vapor
import VaporTesting

@testable import ClientIpMiddleware

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

    private func makeApp() async throws -> (Application, Recorder) {
        let app = try await Application.make(.testing)
        let recorder = Recorder()
        app.middleware.use(ClientIpMiddleware())
        app.get("probe") { _ -> String in
            await recorder.record(
                ip: ClientContext.clientIp,
                ua: ClientContext.userAgent
            )
            return "ok"
        }
        return (app, recorder)
    }

    // MARK: - X-Forwarded-For

    @Test("captures single-IP X-Forwarded-For header")
    func xffSingleIP() async throws {
        let (app, recorder) = try await makeApp()
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

    @Test("multi-hop X-Forwarded-For: picks first (leftmost) hop, ignores proxies")
    func xffMultiHopPicksFirst() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "203.0.113.7, 198.51.100.10, 192.0.2.99"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("X-Forwarded-For with whitespace around the first IP is trimmed")
    func xffTrimsWhitespace() async throws {
        let (app, recorder) = try await makeApp()
        try await app.testing().test(
            .GET, "probe",
            beforeRequest: { req in
                req.headers.replaceOrAdd(
                    name: .xForwardedFor,
                    value: "   203.0.113.7   , 198.51.100.10"
                )
            }
        ) { res async in
            #expect(res.status == .ok)
        }
        await #expect(recorder.ip == "203.0.113.7")
        try await app.asyncShutdown()
    }

    @Test("IPv6 X-Forwarded-For is captured verbatim")
    func xffIPv6() async throws {
        let (app, recorder) = try await makeApp()
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

    // MARK: - User-Agent

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

    @Test("captures both IP and User-Agent in the same request")
    func capturesBoth() async throws {
        let (app, recorder) = try await makeApp()
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
        // app.testing() doesn't simulate a socket-level remoteAddress, so both
        // sources are absent.
        await #expect(recorder.ip == nil)
        await #expect(recorder.ua == nil)
        try await app.asyncShutdown()
    }

    // MARK: - Cross-request isolation

    @Test("task-locals do not leak across sibling requests")
    func noLeakAcrossRequests() async throws {
        let (app, recorder) = try await makeApp()

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

    /// Calls the middleware with a hand-constructed `Request` so we can assert
    /// behaviour without depending on `app.testing()`. This also lets us verify
    /// task-local propagation through to the handler in isolation.
    @Test("direct call: X-Forwarded-For wins over remoteAddress")
    func directCallXFFWins() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        let req = Request(
            application: app,
            method: .GET,
            url: URI(path: "/probe"),
            on: app.eventLoopGroup.next()
        )
        req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7, 198.51.100.10")
        req.headers.replaceOrAdd(name: .userAgent, value: "test-ua")

        struct Recorded: AsyncResponder {
            let recorder: Recorder
            func respond(to request: Request) async throws -> Response {
                await recorder.record(
                    ip: ClientContext.clientIp,
                    ua: ClientContext.userAgent
                )
                return Response(status: .ok)
            }
        }

        let recorder = Recorder()
        let response = try await ClientIpMiddleware().respond(
            to: req,
            chainingTo: Recorded(recorder: recorder)
        )
        #expect(response.status == .ok)
        await #expect(recorder.ip == "203.0.113.7")
        await #expect(recorder.ua == "test-ua")
    }
}
