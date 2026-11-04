import Combine
import Foundation
import Gentizer
import SwiftUI

/// confirm: true 액션 승인 요청 큐 (specs/swiftui.md '승인'). AgentRuntime(confirm: confirmation.confirm) 로 연결
@MainActor
public final class AgentConfirmation: ObservableObject {
    /// 지금 묻는 요청. 없으면 nil
    @Published public private(set) var request: ConfirmRequest?

    private struct Pending {
        let id: Int
        let request: ConfirmRequest
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var queue: [Pending] = []
    private var nextId = 0

    public init() {}

    /// 사용자 답을 기다린다. 기다리는 Task 가 취소되면 false
    public func confirm(_ request: ConfirmRequest) async -> Bool {
        nextId += 1
        let id = nextId
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                queue.append(Pending(id: id, request: request, continuation: continuation))
                publish()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id: id, answer: false) }
        }
    }

    /// 지금 요청 승인
    public func approve() { answerCurrent(true) }

    /// 지금 요청 거절
    public func deny() { answerCurrent(false) }

    private func answerCurrent(_ answer: Bool) {
        guard let first = queue.first else { return }
        finish(id: first.id, answer: answer)
    }

    private func finish(id: Int, answer: Bool) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        let pending = queue.remove(at: i)
        pending.continuation.resume(returning: answer)
        publish()
    }

    private func publish() {
        request = queue.first?.request
    }
}

extension ConfirmRequest {
    /// alert 메시지: description + args JSON (키 정렬)
    var alertMessage: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let args = (try? String(decoding: encoder.encode(JSONValue.object(self.args)), as: UTF8.self)) ?? "{}"
        return "\(description)\n\(args)"
    }
}

private struct ConfirmationModifier: ViewModifier {
    @ObservedObject var confirmation: AgentConfirmation
    /// 버튼으로 답한 직후의 isPresented = false 는 다음 요청을 거절하지 않게 건너뛴다
    @State private var answered = false

    func body(content: Content) -> some View {
        content.alert(
            "에이전트 실행 승인",
            isPresented: Binding(
                get: { confirmation.request != nil },
                // 승인 · 거절 버튼 외의 방법으로 닫히면 거절
                set: { shown in
                    guard !shown else { return }
                    if answered { answered = false } else { confirmation.deny() }
                }
            ),
            presenting: confirmation.request
        ) { _ in
            Button("승인") {
                answered = true
                confirmation.approve()
            }
            Button("거절", role: .cancel) {
                answered = true
                confirmation.deny()
            }
        } message: { request in
            Text(request.alertMessage)
        }
    }
}

extension View {
    /// confirmation.request 가 있는 동안 승인 alert
    public func agentConfirmation(_ confirmation: AgentConfirmation) -> some View {
        modifier(ConfirmationModifier(confirmation: confirmation))
    }
}
