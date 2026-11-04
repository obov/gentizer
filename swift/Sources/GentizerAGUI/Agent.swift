import Foundation
import Gentizer

/// runAgent 한 번의 입력. tools · context 는 runWithFrontendTools 가 gentizer 것 뒤에 붙인다
public struct AGUIRunParameters: Sendable {
    public var runId: String?
    public var tools: [AGUITool]
    public var context: [AGUIContext]
    public var forwardedProps: JSONValue

    public init(runId: String? = nil, tools: [AGUITool] = [], context: [AGUIContext] = [],
                forwardedProps: JSONValue = [:]) {
        self.runId = runId
        self.tools = tools
        self.context = context
        self.forwardedProps = forwardedProps
    }
}

/// AG-UI 에이전트. runAgent 가 끝나면 messages 에 응답이 반영돼 있다
@MainActor
public protocol AGUIAgent: AnyObject {
    var messages: [AGUIMessage] { get }
    func runAgent(_ params: AGUIRunParameters) async throws
    func addMessages(_ messages: [AGUIMessage])
}

/// AG-UI HTTP 전송. POST RunAgentInput → SSE 이벤트를 messages · state 에 반영
@MainActor
public final class AGUIHTTPAgent: AGUIAgent {
    public let url: URL
    public var headers: [String: String]
    public var threadId: String
    public private(set) var messages: [AGUIMessage]
    public private(set) var state: JSONValue
    private let session: URLSession

    public init(url: URL, headers: [String: String] = [:], threadId: String = UUID().uuidString,
                messages: [AGUIMessage] = [], state: JSONValue = [:], session: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.threadId = threadId
        self.messages = messages
        self.state = state
        self.session = session
    }

    public func addMessages(_ messages: [AGUIMessage]) {
        self.messages += messages
    }

    public func runAgent(_ params: AGUIRunParameters) async throws {
        let (bytes, response) = try await session.bytes(for: request(params))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw AGUIError.http(status: status)
        }
        var parser = SSEParser()
        var events = AGUIEventState(messages: messages, state: state)
        defer {
            messages = events.messages
            state = events.state
        }
        for try await byte in bytes {
            if let data = parser.feed(byte) { events.apply(data: data) }
            if let error = events.runError { throw error }
        }
        if let data = parser.finish() { events.apply(data: data) }
        if let error = events.runError { throw error }
    }

    func request(_ params: AGUIRunParameters) throws -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let input = RunAgentInput(threadId: threadId, runId: params.runId ?? UUID().uuidString, state: state,
                                  messages: messages, tools: params.tools, context: params.context,
                                  forwardedProps: params.forwardedProps)
        r.httpBody = try JSONEncoder().encode(input)
        return r
    }
}

struct RunAgentInput: Codable, Sendable {
    var threadId: String
    var runId: String
    var state: JSONValue
    var messages: [AGUIMessage]
    var tools: [AGUITool]
    var context: [AGUIContext]
    var forwardedProps: JSONValue
}
