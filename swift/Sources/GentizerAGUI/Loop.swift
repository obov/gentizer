import Gentizer

public struct AGUIRunResult: Equatable, Sendable {
    public var rounds: Int
    public var toolMessages: [AGUIMessage]
}

/// runAgent → frontend tool 실행 → 결과를 메시지로 추가 → 다시 runAgent. 실행할 tool call 이 없으면 종료
@MainActor
public func runWithFrontendTools(_ agent: AGUIAgent, _ runtime: AgentRuntime,
                                 _ params: AGUIRunParameters = AGUIRunParameters(),
                                 maxRounds: Int = 5) async throws -> AGUIRunResult {
    var result = AGUIRunResult(rounds: 0, toolMessages: [])
    while result.rounds < maxRounds {
        result.rounds += 1
        var p = params
        p.tools = toAGUITools(runtime.manifest()) + params.tools
        p.context = toAGUIContext(runtime) + params.context
        try await agent.runAgent(p)
        let out = await runFrontendTools(runtime, agent.messages)
        if out.isEmpty { break }
        agent.addMessages(out)
        result.toolMessages += out
    }
    return result
}

/// trigger 마다 메시지 추가 → runWithFrontendTools. 한 번에 하나씩 순서대로. 반환 함수로 해제 (대기 중 trigger 버림)
@MainActor
public func connectTriggers(_ agent: AGUIAgent, _ runtime: AgentRuntime,
                            _ params: AGUIRunParameters = AGUIRunParameters(), maxRounds: Int = 5,
                            onError: (@MainActor (Error, TriggerEvent) -> Void)? = nil) -> @MainActor () -> Void {
    let queue = TriggerQueue { event in
        agent.addMessages([toAGUITriggerMessage(event)])
        do {
            _ = try await runWithFrontendTools(agent, runtime, params, maxRounds: maxRounds)
        } catch {
            onError?(error, event)
        }
    }
    let off = runtime.onTrigger { queue.push($0) }
    return {
        queue.close()
        off()
    }
}

/// 직렬 실행 큐. drain Task 하나가 순서대로 처리
@MainActor
private final class TriggerQueue {
    private var pending: [TriggerEvent] = []
    private var running = false
    private var connected = true
    private let handle: @MainActor (TriggerEvent) async -> Void

    init(_ handle: @escaping @MainActor (TriggerEvent) async -> Void) { self.handle = handle }

    func push(_ event: TriggerEvent) {
        guard connected else { return }
        pending.append(event)
        guard !running else { return }
        running = true
        Task { await self.drain() }
    }

    func close() {
        connected = false
        pending.removeAll()
    }

    private func drain() async {
        while connected, !pending.isEmpty {
            await handle(pending.removeFirst())
        }
        running = false
    }
}
