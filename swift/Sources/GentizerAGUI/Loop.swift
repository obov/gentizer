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
