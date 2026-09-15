# ClientIpMiddleware

[![Linux](https://github.com/diyamantina/ClientIpMiddleware/actions/workflows/linux.yml/badge.svg)](https://github.com/diyamantina/ClientIpMiddleware/actions/workflows/linux.yml)
[![macOS](https://github.com/diyamantina/ClientIpMiddleware/actions/workflows/macos.yml/badge.svg)](https://github.com/diyamantina/ClientIpMiddleware/actions/workflows/macos.yml)
![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20%7C%20Linux-blue.svg)

Vapor middleware for carrying client identity into OpenAPI-generated handlers.

`ClientIpMiddleware` captures a best-effort client IP and the inbound
`User-Agent`, then stores both in task-locals. That gives generated Swift
OpenAPI handlers, which normally receive typed operation input but not Vapor's
`Request`, a clean way to log, audit, rate-limit, or enrich request handling.

Use it when you need:

- Client IP and user-agent access from generated OpenAPI handlers.
- A secure default for direct deployments where `X-Forwarded-For` is untrusted.
- Explicit reverse-proxy handling through `trustedProxyHops`.
- Per-request values that propagate across `await` boundaries and clear
  automatically after the request finishes.

## Installation

```swift
.package(url: "https://github.com/diyamantina/ClientIpMiddleware", from: "1.0.0"),
```

```swift
.target(
    name: "ApiServer",
    dependencies: [
        .product(name: "ClientIpMiddleware", package: "ClientIpMiddleware"),
    ]
),
```

## Quick Start

Install the middleware once during Vapor boot:

```swift
import ClientIpMiddleware
import Vapor

let app = try await Application.make(.detect())

// Direct deployment, local development, or no trusted proxy in front.
app.middleware.use(ClientIpMiddleware())

// Behind one trusted reverse proxy, such as nginx, Caddy, ALB, or Cloudflare.
app.middleware.use(ClientIpMiddleware(trustedProxyHops: 1))

// Behind two trusted hops, such as CDN -> reverse proxy -> app.
app.middleware.use(ClientIpMiddleware(trustedProxyHops: 2))
```

Read the values from any async handler executed during the request:

```swift
import ClientIpMiddleware

func someOperation(...) async throws -> ... {
    let ip = ClientContext.clientIp ?? "unknown"
    let userAgent = ClientContext.userAgent ?? "unknown"

    // Log, audit, rate-limit, or pass the values to your domain layer.
}
```

The same access pattern works in generated OpenAPI handlers and conventional
Vapor route handlers.

## Client IP Resolution

`trustedProxyHops` controls whether `X-Forwarded-For` is trusted.

| Setting | Source |
|---|---|
| `0` | Ignore `X-Forwarded-For`; use the connection `remoteAddress?.ipAddress`. This is the secure default for direct deployments. |
| `1` | Trust one proxy in front of the app and use the rightmost usable `X-Forwarded-For` entry. |
| `n >= 2` | Trust `n` proxy hops and select the entry at `count - n`, falling back to `remoteAddress` when the header is absent or too short. |

Match `trustedProxyHops` to your actual deployment. Setting it too high lets a
client spoof an address by adding extra `X-Forwarded-For` entries; setting it
too low reports a proxy address instead of the client.

## Task-Local Context

Captured values are exposed through `ClientContext`:

```swift
public enum ClientContext {
    @TaskLocal public static var clientIp: String?
    @TaskLocal public static var userAgent: String?
}
```

The middleware sets these inside nested `withValue` scopes around the downstream
responder. Values are visible through async calls made during the request and
are cleared when the request leaves the middleware chain.

## Companion Packages

- [`BearerTokenAuthMiddleware`](https://github.com/diyamantina/BearerTokenAuthMiddleware)
  stamps bearer tokens on generated OpenAPI clients and enforces bearer tokens
  in Vapor servers.
- [`OpenAPILoggingMiddleware`](https://github.com/diyamantina/OpenAPILoggingMiddleware)
  logs OpenAPI requests and responses on both client and server paths, with
  default credential-header redaction.

## Platform Support

| Platform | CI coverage |
|---|---|
| macOS 13+ | `swift build` and `swift test` |
| Linux, Swift 6.0 container | `swift build` and `swift test` |
| iOS / tvOS / watchOS | Not supported because Vapor does not ship for these platforms |

## Documentation

DocC is enabled:

```bash
swift package --allow-writing-to-directory ./docs generate-documentation \
    --target ClientIpMiddleware \
    --output-path ./docs/ClientIpMiddleware.doccarchive
```

## Testing

The package ships with **33 tests across 3 suites** covering:

- `ClientContext` task-local semantics.
- Vapor middleware integration.
- `trustedProxyHops` behavior for direct, single-proxy, and multi-proxy setups.
- Spoof resistance for malformed or adversarial `X-Forwarded-For` values.
- Cross-request isolation and propagation across `await`.

Run them with:

```bash
swift test
```

## Contributing

Contributions are welcome. Before opening a PR, read
[CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
[SECURITY.md](SECURITY.md), and [SUPPORT.md](SUPPORT.md).

Notable changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

Apache 2.0. See [LICENSE](LICENSE).
