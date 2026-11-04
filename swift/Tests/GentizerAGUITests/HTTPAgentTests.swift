import Foundation
import Gentizer
import Testing
@testable import GentizerAGUI

// specs/ag-ui.md 'AGUIHTTPAgent 전송'. URLProtocol 가짜 서버

final class FakeServer: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: String
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var requests: [String: URLRequest] = [:]
    nonisolated(unsafe) static var bodies: [String: Data] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url!.path
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.requests[key] = request
        Self.bodies[key] = body
        let reply = Self.replies[key] ?? Reply(status: 404, body: "")
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // 이벤트 경계와 무관하게 쪼개 보냄
        let data = Data(reply.body.utf8)
        stride(from: 0, to: data.count, by: 7).forEach {
            client?.urlProtocol(self, didLoad: data.subdata(in: $0..<min($0 + 7, data.count)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func serve(_ path: String, status: Int = 200, events: [String]) {
        lock.lock()
        replies[path] = Reply(status: status, body: events.map { "data: \($0)\n\n" }.joined())
        lock.unlock()
    }

    static func sent(_ path: String) -> (URLRequest?, JSONValue?) {
        lock.lock()
        defer { lock.unlock() }
        return (requests[path], bodies[path].flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) })
    }
}

@MainActor
struct HTTPAgentTests {
    private func agent(_ path: String, messages: [AGUIMessage] = []) -> AGUIHTTPAgent {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServer.self]
        return AGUIHTTPAgent(url: URL(string: "https://agent.test\(path)")!, headers: ["Authorization": "Bearer k"],
                             threadId: "th1", messages: messages, session: URLSession(configuration: config))
    }

    @Test func requestAndEvents() async throws {
        FakeServer.serve("/ok", events: [
            #"{"type":"RUN_STARTED","threadId":"th1","runId":"r1"}"#,
            #"{"type":"TEXT_MESSAGE_START","messageId":"m1","role":"assistant"}"#,
            #"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"안녕"}"#,
            #"{"type":"STATE_SNAPSHOT","snapshot":{"n":1}}"#,
            #"{"type":"RUN_FINISHED","threadId":"th1","runId":"r1"}"#,
        ])
        let a = agent("/ok", messages: [AGUIMessage(id: "u1", role: "user", content: "hi")])
        try await a.runAgent(AGUIRunParameters(runId: "r1", tools: [AGUITool(name: "t", description: "d", parameters: [:])],
                                               context: [AGUIContext(description: "c", value: "1")]))
        #expect(a.messages.map(\.id) == ["u1", "m1"])
        #expect(a.messages[1].content == "안녕")
        #expect(a.state == ["n": 1])

        let (req, body) = FakeServer.sent("/ok")
        #expect(req?.httpMethod == "POST")
        #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(body?.objectValue.map { Set($0.keys) } ==
            ["threadId", "runId", "state", "messages", "tools", "context", "forwardedProps"])
        #expect(body?["threadId"] == "th1")
        #expect(body?["runId"] == "r1")
        #expect(body?["messages"] == [["id": "u1", "role": "user", "content": "hi"]])
        #expect(body?["tools"] == [["name": "t", "description": "d", "parameters": [:]]])
        #expect(body?["context"] == [["description": "c", "value": "1"]])
    }

    @Test func newRunIdWhenOmitted() async throws {
        FakeServer.serve("/runid", events: [])
        let a = agent("/runid")
        try await a.runAgent(AGUIRunParameters())
        let id = FakeServer.sent("/runid").1?["runId"]?.stringValue
        #expect(id.flatMap(UUID.init(uuidString:)) != nil)
    }

    @Test func httpError() async {
        FakeServer.serve("/fail", status: 500, events: [])
        await #expect(throws: AGUIError.http(status: 500)) { try await agent("/fail").runAgent(AGUIRunParameters()) }
    }

    @Test func runErrorKeepsAppliedMessages() async {
        FakeServer.serve("/err", events: [
            #"{"type":"TEXT_MESSAGE_START","messageId":"m1"}"#,
            #"{"type":"RUN_ERROR","message":"boom","code":"E1"}"#,
            #"{"type":"TEXT_MESSAGE_START","messageId":"m2"}"#,
        ])
        let a = agent("/err")
        await #expect(throws: AGUIError.run(message: "boom", code: "E1")) { try await a.runAgent(AGUIRunParameters()) }
        #expect(a.messages.map(\.id) == ["m1"])
    }

    @Test func addMessagesAppends() {
        let a = agent("/add")
        a.addMessages([AGUIMessage(id: "x", role: "tool", content: "1", toolCallId: "t")])
        #expect(a.messages.map(\.id) == ["x"])
    }
}
