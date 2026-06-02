# ClientIpMiddleware

[![Linux](https://github.com/mihaelamj/ClientIpMiddleware/actions/workflows/linux.yml/badge.svg)](https://github.com/mihaelamj/ClientIpMiddleware/actions/workflows/linux.yml)
[![macOS](https://github.com/mihaelamj/ClientIpMiddleware/actions/workflows/macos.yml/badge.svg)](https://github.com/mihaelamj/ClientIpMiddleware/actions/workflows/macos.yml)
![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20%7C%20Linux-blue.svg)

A small Vapor `AsyncMiddleware` that captures the client IP and `User-Agent` of
each inbound request into task-locals, so OpenAPI-generated handlers (which do
not see Vapor's `Request`) can read them.

## Installation

```swift
.package(url: "https://github.com/mihaelamj/ClientIpMiddleware", from: "1.0.0"),
```

```swift
.target(
    name: "ApiServer",
    dependencies: [
        .product(name: "ClientIpMiddleware", package: "ClientIpMiddleware"),
    ]
),
```

## Quick start

```swift
import ClientIpMiddleware
import Vapor

let app = try await Application.make(.detect())

// Direct deployment (no proxy in front) — secure default:
app.middleware.use(ClientIpMiddleware())

// Behind one trusted reverse proxy (nginx, Caddy, ALB, Cloudflare, ...):
app.middleware.use(ClientIpMiddleware(trustedProxyHops: 1))
```

Read either value from any async handler executed during the request:

```swift
import ClientIpMiddleware

func someOperation(...) async throws -> ... {
    let ip = ClientContext.clientIp ?? "unknown"
    let ua = ClientContext.userAgent ?? "unknown"
    // ...
}
```

OpenAPI-generated handlers (which never see Vapor's `Request`) read the
task-locals the same way conventional Vapor handlers do.

## What it captures

- **Client IP** — selected per `trustedProxyHops`:
  - `0` (default): ignore `X-Forwarded-For` entirely; use the connection's
    `remoteAddress?.ipAddress`. Anything in `X-Forwarded-For` is
    client-controllable when there's no proxy stripping it, so the safe
    default is to not trust it.
  - `n >= 1`: peel `n` hops off the right of `X-Forwarded-For`. The entry at
    `count - n` is what the n-th trusted proxy received the connection from
    (the real client when `n` matches the proxy depth). Falls back to
    `remoteAddress` when the header is absent or has fewer than `n` entries.
- **User-Agent** — verbatim from the inbound `User-Agent` header.

> Match `trustedProxyHops` to your actual deployment. Setting it too high lets
> a client spoof the IP by stuffing extra entries into `X-Forwarded-For`;
> setting it too low surfaces the proxy IP instead of the client.

Both values land in task-locals on `ClientContext`:

```swift
public enum ClientContext {
    @TaskLocal public static var clientIp: String?
    @TaskLocal public static var userAgent: String?
}
```

## Why task-locals

OpenAPI-generated handlers see only the typed `Operations.<X>.Input` and cannot
reach Vapor's `Request`. Task-locals propagate through `await` boundaries so
handlers that run inside the middleware's `withValue` block see the captured
values. Conventional Vapor handlers can also read these task-locals or fall back
to reading the request headers directly.

## Companion packages

- [`mihaelamj/BearerTokenAuthMiddleware`](https://github.com/mihaelamj/BearerTokenAuthMiddleware)
  for client-side bearer-token stamping plus a server-side enforcement
  middleware with `AuthMode` + validation strategies.
- [`mihaelamj/OpenAPILoggingMiddleware`](https://github.com/mihaelamj/OpenAPILoggingMiddleware)
  for request/response logging on both client and server sides.
- [`mihaelamj/swift-server-middleware-petshop`](https://github.com/mihaelamj/swift-server-middleware-petshop)
  end-to-end integration tests for all three middlewares composed inside
  a real Vapor + OpenAPI 3.1 app, with macOS + Linux CI.

## Platform support

| Platform | How CI proves it |
|---|---|
| macOS 13+ | full `swift build` + `swift test` (33 tests) |
| Linux (Swift 6.0 container) | full `swift build` + `swift test` (33 tests) |
| iOS / tvOS / watchOS | **not supported** — Vapor itself does not ship for these platforms |

## Documentation

DocC is enabled. Generate the archive locally with:

```bash
swift package --allow-writing-to-directory ./docs generate-documentation \
    --target ClientIpMiddleware \
    --output-path ./docs/ClientIpMiddleware.doccarchive
```

## Testing

The package ships with **33 tests across 3 suites**:

| Area | Tests |
|---|---|
| `ClientContext` (task-local semantics) | 8 |
| `ClientIpMiddleware` (Vapor integration, trusted-proxy-hops) | 16 |
| `ClientIpMiddleware: adversarial / malformed inputs` (XFF edge cases, 100-fold concurrent burst) | 9 |

Coverage includes the secure-by-default `hops=0` path (XFF ignored), `hops=1`
single-proxy resolution including client-spoof resistance, `hops=2`
multi-proxy resolution, fallback to `remoteAddress` when XFF is absent or
under-length, IPv6, whitespace trimming, missing-header fallback,
cross-request isolation, propagation across `await`, and negative-hops
clamping. Run with `swift test`.

CI runs the suite on macOS and on Linux (Swift 6.0 container).

## License

Apache 2.0 — see [LICENSE](LICENSE).
