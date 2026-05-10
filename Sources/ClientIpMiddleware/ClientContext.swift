import Foundation

/// Task-local channel for per-request client metadata captured by ``ClientIpMiddleware``.
///
/// ## Overview
///
/// OpenAPI-generated handlers do not see Vapor's `Request` directly — they only
/// receive the typed `Operations.<X>.Input`. They therefore cannot read
/// `request.headers` or `request.remoteAddress`. ``ClientIpMiddleware`` stashes the
/// extracted client IP and User-Agent here so generated handlers can still log,
/// rate-limit, or audit on a per-client basis.
///
/// Read either value from a handler:
///
///     guard let ip = ClientContext.clientIp else { ... }
///     let ua = ClientContext.userAgent ?? "unknown"
///
/// Conventional Vapor handlers can read these task-locals or fall back to inspecting
/// `request` directly.
///
/// - Note: The task-locals are set inside ``ClientIpMiddleware/respond(to:chainingTo:)``
///   via nested `withValue { ... }` closures, so the values are visible to every
///   async handler executed during the request and are automatically cleared when
///   the closure returns.
///
/// ## Topics
///
/// ### Reading per-request metadata
/// - ``clientIp``
/// - ``userAgent``
public enum ClientContext {

    /// Best-effort client IP for the currently handled request.
    ///
    /// Sourced from `X-Forwarded-For` (first hop) when present, otherwise from the
    /// connection's `remoteAddress`. `nil` outside the middleware's scope, or when
    /// neither source yielded a value.
    @TaskLocal public static var clientIp: String?

    /// `User-Agent` header captured for the currently handled request.
    ///
    /// Verbatim from the inbound `User-Agent` header. `nil` when no header was
    /// sent, or outside the middleware's scope.
    @TaskLocal public static var userAgent: String?
}
