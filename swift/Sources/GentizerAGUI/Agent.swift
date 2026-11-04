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
    private var current: Task<Void, Error>?

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

    /// 진행 중 runAgent 의 요청 취소. runAgent 는 CancellationError 로 끝나고, 그때까지 반영한 메시지 · state 는 유지
    public func abortRun() {
        current?.cancel()
    }

    public func runAgent(_ params: AGUIRunParameters) async throws {
        let req = try request(params)
        let task = Task { @MainActor in try await self.stream(req) }
        current = task
        defer { if current == task { current = nil } }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func stream(_ req: URLRequest) async throws {
        do {
            let (bytes, response) = try await session.bytes(for: req)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw AGUIError.http(status: status)
            }
            var parser = SSEParser()
            var events = AGUIEventState(messages: messages, state: state)
            // 이벤트마다 반영해 진행 중에도 messages · state 가 보인다
            func publish(_ data: String) throws {
                events.apply(data: data)
                messages = events.messages
                state = events.state
                if let error = events.runError { throw error }
            }
            for try await byte in bytes {
                try Task.checkCancellation()
                if let data = parser.feed(byte) { try publish(data) }
            }
            try Task.checkCancellation()
            if let data = parser.finish() { try publish(data) }
        } catch {
            // URLSession 은 취소를 URLError.cancelled 로 알리기도 한다
            if Task.isCancelled, !(error is CancellationError) { throw CancellationError() }
            throw error
        }
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
