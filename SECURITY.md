# Security Policy

## Reporting a vulnerability

If you believe you have found a security issue in ClientIpMiddleware, please
report it privately. Do not open a public issue for security problems.

Email **mihaelamj@gmail.com** with:

- A description of the issue and its impact.
- Steps to reproduce, or a proof of concept.
- The affected version or commit.

You can expect an acknowledgement within a few days. Once the issue is confirmed,
a fix will be prepared and a release cut, after which the issue can be disclosed
publicly with credit to the reporter if desired.

## Supported versions

Security fixes are applied to the latest `1.x` release and to the `main` branch.
Older versions are not maintained; upgrade to the latest release to receive
fixes.

## Scope

ClientIpMiddleware selects the client IP from the connection's `remoteAddress`
and, when configured, from the `X-Forwarded-For` header. The most security
relevant behavior is `trustedProxyHops`: it controls how many right-most
`X-Forwarded-For` entries are peeled as trusted proxies. In scope:

- Client IP spoofing through crafted `X-Forwarded-For` headers under a given
  `trustedProxyHops` value.
- Incorrect hop resolution that surfaces a proxy IP as the client, or a
  client-controlled value as trusted.
- Any way the middleware leaks one request's captured values into another
  request's task-locals.

Out of scope: misconfiguration where `trustedProxyHops` does not match the
actual proxy depth of your deployment. Match the value to your topology; see the
README for the trade-off.
