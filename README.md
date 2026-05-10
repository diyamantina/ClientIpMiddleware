# ClientIpMiddleware

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platform-macOS%2013+-blue.svg)

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
app.middleware.use(ClientIpMiddleware())
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

- **Client IP** — first comma-separated value of `X-Forwarded-For` if present
  (trimmed of whitespace), otherwise the connection's `remoteAddress`. Behind a
  reverse proxy, configure the proxy to set `X-Forwarded-For: <client>[, <proxy1>...]`
  so the real client (not the proxy) is recorded. The middleware picks the
  leftmost hop, which by convention is the original client.
- **User-Agent** — verbatim from the inbound `User-Agent` header.

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

## Documentation

DocC is enabled. Generate the archive locally with:

```bash
swift package --allow-writing-to-directory ./docs generate-documentation \
    --target ClientIpMiddleware \
    --output-path ./docs/ClientIpMiddleware.doccarchive
```

## Testing

The package ships with **17 tests across 2 suites**:

| Area | Tests |
|---|---|
| `ClientContext` (task-local semantics) | 7 |
| `ClientIpMiddleware` (Vapor integration) | 10 |

Coverage includes single + multi-hop `X-Forwarded-For`, whitespace trimming,
IPv6, missing-header fallback, cross-request isolation, and propagation across
`await`. Run with `swift test`.

## License

Apache 2.0 — see [LICENSE](LICENSE).
