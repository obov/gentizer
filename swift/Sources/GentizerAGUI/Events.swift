import Foundation
import Gentizer

/// SSE 바이트 → 이벤트 data 문자열. 줄 끝 \n · \r\n, data: 줄을 \n 으로 이어 빈 줄에서 하나
struct SSEParser {
    private var line: [UInt8] = []
    private var data: [String] = []

    /// 바이트 하나를 넣고, 이벤트가 끝났으면 data 를 돌려준다
    mutating func feed(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            line.append(byte)
            return nil
        }
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        return endLine(String(decoding: line, as: UTF8.self))
    }

    /// 스트림 끝. 빈 줄 없이 끝난 마지막 이벤트
    mutating func finish() -> String? {
        if !line.isEmpty {
            let pending = String(decoding: line, as: UTF8.self)
            line.removeAll()
            _ = endLine(pending)
        }
        return endLine("")
    }

    private mutating func endLine(_ s: String) -> String? {
        if s.isEmpty {
            guard !data.isEmpty else { return nil }
            defer { data.removeAll() }
            return data.joined(separator: "\n")
        }
        guard s.hasPrefix("data:") else { return nil }
        var value = s.dropFirst(5)
        if value.first == " " { value = value.dropFirst() }
        data.append(String(value))
        return nil
    }
}

/// 이벤트 반영 결과. 메시지 · state 와 RUN_ERROR
struct AGUIEventState {
    var messages: [AGUIMessage]
    var state: JSONValue
    var runError: AGUIError?
    private var chunkMessageId: String?
    private var chunkToolCallId: String?
    private var chunkReasoningId: String?

    init(messages: [AGUIMessage], state: JSONValue) {
        self.messages = messages
        self.state = state
    }

    /// data 문자열 하나. 디코딩 실패 · 모르는 type 은 무시
    mutating func apply(data: String) {
        guard let event = try? JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)) else { return }
        apply(event)
    }

    mutating func apply(_ e: JSONValue) {
        guard runError == nil, let type = e["type"]?.stringValue else { return }
        switch type {
        case "TEXT_MESSAGE_START":
            if let id = e["messageId"]?.stringValue { textStart(id, role: e["role"]?.stringValue) }
        case "TEXT_MESSAGE_CONTENT":
            if let id = e["messageId"]?.stringValue { textContent(id, e["delta"]?.stringValue ?? "") }
        case "TEXT_MESSAGE_CHUNK":
            guard let id = e["messageId"]?.stringValue ?? chunkMessageId else { return }
            chunkMessageId = id
            textStart(id, role: e["role"]?.stringValue)
            if let delta = e["delta"]?.stringValue { textContent(id, delta) }
        case "TOOL_CALL_START":
            if let id = e["toolCallId"]?.stringValue, let name = e["toolCallName"]?.stringValue {
                toolStart(id, name: name, parent: e["parentMessageId"]?.stringValue)
            }
        case "TOOL_CALL_ARGS":
            if let id = e["toolCallId"]?.stringValue { toolArgs(id, e["delta"]?.stringValue ?? "") }
        case "TOOL_CALL_CHUNK":
            guard let id = e["toolCallId"]?.stringValue ?? chunkToolCallId else { return }
            if id != chunkToolCallId, let name = e["toolCallName"]?.stringValue {
                toolStart(id, name: name, parent: e["parentMessageId"]?.stringValue)
            }
            chunkToolCallId = id
            if let delta = e["delta"]?.stringValue { toolArgs(id, delta) }
        case "TOOL_CALL_RESULT":
            if let id = e["messageId"]?.stringValue, let callId = e["toolCallId"]?.stringValue {
                toolResult(AGUIMessage(id: id, role: e["role"]?.stringValue ?? "tool",
                                       content: e["content"]?.stringValue, toolCallId: callId))
            }
        case "MESSAGES_SNAPSHOT":
            if let snapshot = try? e["messages"]?.decode(as: [AGUIMessage].self) { messagesSnapshot(snapshot) }
        case "STATE_SNAPSHOT":
            state = e["snapshot"] ?? .null
        case "STATE_DELTA":
            if let next = applyJSONPatch(state, e["delta"] ?? .null) { state = next }
        case "REASONING_MESSAGE_START":
            if let id = e["messageId"]?.stringValue { reasoningStart(id) }
        case "REASONING_MESSAGE_CONTENT":
            if let id = e["messageId"]?.stringValue { reasoningContent(id, e["delta"]?.stringValue ?? "") }
        case "REASONING_MESSAGE_CHUNK":
            guard let id = e["messageId"]?.stringValue ?? chunkReasoningId else { return }
            if id != chunkReasoningId { reasoningStart(id) }
            chunkReasoningId = id
            if let delta = e["delta"]?.stringValue { reasoningContent(id, delta) }
        case "REASONING_ENCRYPTED_VALUE":
            if let entity = e["entityId"]?.stringValue, let value = e["encryptedValue"]?.stringValue {
                encrypted(entity, value, toolCall: e["subtype"]?.stringValue == "tool-call")
            }
        case "ACTIVITY_SNAPSHOT":
            if let id = e["messageId"]?.stringValue, let type = e["activityType"]?.stringValue {
                activitySnapshot(id, type: type, content: e["content"] ?? [:], replace: e["replace"]?.boolValue ?? true)
            }
        case "ACTIVITY_DELTA":
            if let id = e["messageId"]?.stringValue,
               let i = messages.firstIndex(where: { $0.id == id }), messages[i].role == "activity",
               let next = applyJSONPatch(messages[i].structuredContent ?? [:], e["patch"] ?? []) {
                messages[i].structuredContent = next
                if let type = e["activityType"]?.stringValue { messages[i].activityType = type }
            }
        case "RUN_ERROR":
            runError = .run(message: e["message"]?.stringValue ?? "", code: e["code"]?.stringValue)
        default:
            break
        }
    }

    private mutating func reasoningStart(_ id: String) {
        guard !messages.contains(where: { $0.id == id }) else { return }
        messages.append(AGUIMessage(id: id, role: "reasoning", content: ""))
    }

    private mutating func reasoningContent(_ id: String, _ delta: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].role != "activity" else { return }
        messages[i].content = (messages[i].content ?? "") + delta
    }

    private mutating func encrypted(_ entity: String, _ value: String, toolCall: Bool) {
        if toolCall {
            if let (i, j) = toolIndex(entity), messages[i].role == "assistant" { messages[i].toolCalls![j].encryptedValue = value }
        } else if let i = messages.firstIndex(where: { $0.id == entity }), messages[i].role != "activity" {
            messages[i].encryptedValue = value
        }
    }

    private mutating func activitySnapshot(_ id: String, type: String, content: JSONValue, replace: Bool) {
        let fresh = AGUIMessage(id: id, role: "activity", activityType: type, structuredContent: content)
        guard let i = messages.firstIndex(where: { $0.id == id }) else {
            messages.append(fresh)
            return
        }
        guard replace else { return }
        if messages[i].role == "activity" {
            messages[i].activityType = type
            messages[i].structuredContent = content
        } else {
            messages[i] = fresh
        }
    }

    private mutating func textStart(_ id: String, role: String?) {
        guard !messages.contains(where: { $0.id == id }) else { return }
        messages.append(AGUIMessage(id: id, role: role ?? "assistant", content: ""))
    }

    private mutating func textContent(_ id: String, _ delta: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].content = (messages[i].content ?? "") + delta
    }

    private func toolIndex(_ id: String) -> (Int, Int)? {
        for (i, m) in messages.enumerated() {
            if let j = m.toolCalls?.firstIndex(where: { $0.id == id }) { return (i, j) }
        }
        return nil
    }

    private mutating func toolStart(_ id: String, name: String, parent: String?) {
        if let (i, j) = toolIndex(id) {
            messages[i].toolCalls![j].function.name = name
            return
        }
        let call = AGUIToolCall(id: id, function: .init(name: name, arguments: ""))
        let i: Int
        if let parent, let found = messages.firstIndex(where: { $0.id == parent }) {
            if messages[found].role == "assistant" {
                i = found
            } else {
                messages.append(AGUIMessage(id: id, role: "assistant", toolCalls: []))
                i = messages.count - 1
            }
        } else {
            messages.append(AGUIMessage(id: parent ?? id, role: "assistant", toolCalls: []))
            i = messages.count - 1
        }
        messages[i].toolCalls = (messages[i].toolCalls ?? []) + [call]
    }

    private mutating func toolArgs(_ id: String, _ delta: String) {
        guard let (i, j) = toolIndex(id) else { return }
        messages[i].toolCalls![j].function.arguments += delta
    }

    private mutating func toolResult(_ m: AGUIMessage) {
        if let i = messages.firstIndex(where: { $0.id == m.id && $0.role == "tool" && $0.toolCallId == m.toolCallId }) {
            messages[i] = m
        } else if let (i, _) = toolIndex(m.toolCallId!), messages[i].role == "assistant" {
            var k = i + 1
            while k < messages.count, messages[k].role == "tool" { k += 1 }
            messages.insert(m, at: k)
        } else {
            messages.append(m)
        }
    }

    /// snapshot 에 activity · reasoning 이 하나도 없으면 기존 activity · reasoning 은 유지
    private mutating func messagesSnapshot(_ snapshot: [AGUIMessage]) {
        let byId = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let keepActivity = !snapshot.contains { $0.role == "activity" }
        let keepReasoning = !snapshot.contains { $0.role == "reasoning" }
        messages = messages.compactMap { m in
            if let s = byId[m.id] { return s }
            if (m.role == "activity" && keepActivity) || (m.role == "reasoning" && keepReasoning) { return m }
            return nil
        }
        let kept = Set(messages.map(\.id))
        messages += snapshot.filter { !kept.contains($0.id) }
    }
}

public enum AGUIError: Error, Equatable, Sendable {
    /// 응답 상태가 2xx 아님
    case http(status: Int)
    /// RUN_ERROR 이벤트
    case run(message: String, code: String?)
}
