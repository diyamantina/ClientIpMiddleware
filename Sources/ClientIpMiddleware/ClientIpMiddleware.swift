import Vapor

/// Vapor `AsyncMiddleware` that captures the client IP and `User-Agent` of each
/// inbound request into ``ClientContext`` task-locals.
///
/// ## Overview
///
/// OpenAPI-generated handlers do not see Vapor's `Request` directly, so the
/// middleware stashes the values it captures into task-locals where downstream
/// handlers (including the generated ones) can read them.
///
/// Install once at boot, before any other middleware that needs to log or
/// audit on a per-client basis:
///
///     app.middleware.use(ClientIpMiddleware())
///
/// Then any async handler executed during the request can read:
///
///     import ClientIpMiddleware
///
///     func someOperation(...) async throws -> ... {
///         let ip = ClientContext.clientIp ?? "unknown"
///         let ua = ClientContext.userAgent ?? "unknown"
///         // ...
///     }
///
/// ## Source order for client IP
///
/// 1. The first comma-separated value of the `X-Forwarded-For` header, trimmed.
/// 2. Otherwise, `request.remoteAddress?.ipAddress`.
/// 3. Otherwise, `nil`.
///
/// - Important: Behind a reverse proxy, the connection's `remoteAddress` is the
///   proxy. Configure the proxy to set `X-Forwarded-For: <client>[, <proxy1>...]`
///   so the real client (not the proxy) is recorded. This middleware picks the
///   leftmost value, which by `X-Forwarded-For` convention is the original client.
///
/// ## Topics
///
/// ### Configuring the middleware
/// - ``init()``
///
/// ### Companion type
/// - ``ClientContext``
public struct ClientIpMiddleware: AsyncMiddleware {

    /// Creates the middleware. No configuration; install once at boot.
    public init() {}

    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let ip = request.headers.first(name: .xForwardedFor)?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            ?? request.remoteAddress?.ipAddress

        let userAgent = request.headers.first(name: .userAgent)

        return try await ClientContext.$clientIp.withValue(ip) {
            try await ClientContext.$userAgent.withValue(userAgent) {
                try await next.respond(to: request)
            }
        }
    }
}
