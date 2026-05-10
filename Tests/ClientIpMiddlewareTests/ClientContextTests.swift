import Foundation
import Testing

@testable import ClientIpMiddleware

@Suite("ClientContext")
struct ClientContextTests {

    private func readClientIp() async -> String? { ClientContext.clientIp }
    private func readUserAgent() async -> String? { ClientContext.userAgent }

    @Test("clientIp default is nil")
    func clientIpDefaultIsNil() {
        #expect(ClientContext.clientIp == nil)
    }

    @Test("userAgent default is nil")
    func userAgentDefaultIsNil() {
        #expect(ClientContext.userAgent == nil)
    }

    @Test("clientIp.withValue scopes the value to the closure")
    func clientIpScopes() {
        ClientContext.$clientIp.withValue("203.0.113.7") {
            #expect(ClientContext.clientIp == "203.0.113.7")
        }
        #expect(ClientContext.clientIp == nil)
    }

    @Test("userAgent.withValue scopes the value to the closure")
    func userAgentScopes() {
        ClientContext.$userAgent.withValue("Mozilla/5.0") {
            #expect(ClientContext.userAgent == "Mozilla/5.0")
        }
        #expect(ClientContext.userAgent == nil)
    }

    @Test("clientIp propagates across an `await` boundary inside the closure")
    func clientIpPropagatesAcrossAwait() async {
        let observed = await ClientContext.$clientIp.withValue("198.51.100.42") {
            await readClientIp()
        }
        #expect(observed == "198.51.100.42")
    }

    @Test("userAgent propagates across an `await` boundary inside the closure")
    func userAgentPropagatesAcrossAwait() async {
        let observed = await ClientContext.$userAgent.withValue("curl/8.7.1") {
            await readUserAgent()
        }
        #expect(observed == "curl/8.7.1")
    }

    @Test("nested withValue layers compose without leaking on exit")
    func nestedWithValueComposes() async {
        await ClientContext.$clientIp.withValue("ip-A") {
            await ClientContext.$userAgent.withValue("ua-A") {
                #expect(ClientContext.clientIp == "ip-A")
                #expect(ClientContext.userAgent == "ua-A")
            }
            #expect(ClientContext.clientIp == "ip-A")
            #expect(ClientContext.userAgent == nil)
        }
        #expect(ClientContext.clientIp == nil)
        #expect(ClientContext.userAgent == nil)
    }
}
