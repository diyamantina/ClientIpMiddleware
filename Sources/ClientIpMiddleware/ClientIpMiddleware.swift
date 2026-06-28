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
///     // No proxy in front (e.g. local dev, direct deployment):
///     app.middleware.use(ClientIpMiddleware())
///
///     // Behind one trusted proxy (nginx, Caddy, ALB, Cloudflare, ...):
///     app.middleware.use(ClientIpMiddleware(trustedProxyHops: 1))
///
///     // Behind two trusted proxies (e.g. CDN → nginx → app):
///     app.middleware.use(ClientIpMiddleware(trustedProxyHops: 2))
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
/// The middleware picks the IP based on ``trustedProxyHops``:
///
/// - `0` (default, **secure for direct deployments**): ignore `X-Forwarded-For`
///   entirely and use the connection's `remoteAddress?.ipAddress`. Anything in
///   `X-Forwarded-For` is client-controllable when there is no proxy stripping
///   it, so the safe default is to not trust it.
/// - `n >= 1`: peel `n` hops off the right of `X-Forwarded-For`. The entry at
///   `count - n` is the IP the n-th trusted proxy received the connection from
///   (i.e. the real client when `n` matches the proxy depth). Falls back to
///   `remoteAddress?.ipAddress` when `X-Forwarded-For` is absent or has fewer
///   than `n` entries.
///
/// - Important: Match ``trustedProxyHops`` to the actual number of trusted
///   proxies in front of this server. Setting it too high lets a client spoof
///   the IP by stuffing extra entries into `X-Forwarded-For`. Setting it too
///   low surfaces the proxy IP instead of the client.
///
/// ## Topics
///
/// ### Configuring the middleware
/// - ``init(trustedProxyHops:)``
///
/// ### Companion type
/// - ``ClientContext``
public struct ClientIpMiddleware: AsyncMiddleware {
    /// Number of trusted proxies in front of this server.
    public let trustedProxyHops: Int

    /// Creates the middleware.
    ///
    /// - Parameter trustedProxyHops: How many trusted proxies are in front of
    ///   the server. `0` (the default) ignores `X-Forwarded-For` entirely and
    ///   uses the connection's `remoteAddress`. Set to `1` behind a single
    ///   reverse proxy (nginx, Caddy, AWS ALB, Cloudflare, ...). Set higher
    ///   only when every hop in front is genuinely trusted.
    public init(trustedProxyHops: Int = 0) {
        self.trustedProxyHops = max(0, trustedProxyHops)
    }

    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let ip = resolveClientIp(from: request)
        let userAgent = request.headers.first(name: .userAgent)

        return try await ClientContext.$clientIp.withValue(ip) {
            try await ClientContext.$userAgent.withValue(userAgent) {
                try await next.respond(to: request)
            }
        }
    }

    /// Selects the client IP per the documented source-order rules.
    ///
    /// Exposed for tests and for callers that want the same resolution outside
    /// the middleware respond chain.
    public func resolveClientIp(from request: Request) -> String? {
        guard trustedProxyHops > 0,
              let header = request.headers.first(name: .xForwardedFor)
        else {
            return request.remoteAddress?.ipAddress
        }

        let parts = header
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard parts.count >= trustedProxyHops else {
            return request.remoteAddress?.ipAddress
        }

        let index = parts.count - trustedProxyHops
        return parts[index]
    }
}
