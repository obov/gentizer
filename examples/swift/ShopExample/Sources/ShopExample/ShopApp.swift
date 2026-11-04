import AppKit
import Foundation
import Gentizer
import GentizerA2UISwiftUI
import GentizerAGUI
import GentizerSwiftUI
import SwiftUI

// ── 기존 앱 코드 (gentizer 와 무관) ─────────────────────────────

struct Product: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let category: String
}

let products = [
    Product(id: 1, name: "러닝화", category: "shoes"),
    Product(id: 2, name: "가죽 구두", category: "shoes"),
    Product(id: 3, name: "백팩", category: "bags"),
    Product(id: 4, name: "토트백", category: "bags"),
]

@MainActor
final class Store: ObservableObject {
    @Published var filter = "all"
    @Published var cart: [Product] = []

    var visible: [Product] { products.filter { filter == "all" || $0.category == filter } }

    func add(_ id: Int) throws -> Int {
        guard let p = products.first(where: { $0.id == id }) else { throw ShopError.notFound(id) }
        cart.append(p)
        return cart.count
    }
}

enum ShopError: Error, CustomStringConvertible {
    case notFound(Int)
    var description: String {
        switch self {
        case .notFound(let id): "상품 없음: \(id)"
        }
    }
}

// ── gentizer 연결 ───────────────────────────────────────────────

let agentPort = ProcessInfo.processInfo.environment["AGENT_PORT"] ?? "8782"
let a2uiPort = ProcessInfo.processInfo.environment["A2UI_PORT"] ?? "8781"
let a2uiBase = URL(string: "http://localhost:\(a2uiPort)/a2ui")!

@MainActor
final class Agents: ObservableObject {
    let confirmation = AgentConfirmation()
    let runtime: AgentRuntime
    let agent: AGUIHTTPAgent
    let host: A2UISurfaceHost
    @Published var log: [String] = []
    private var offTriggers: (@MainActor () -> Void)?
    private var offCatalog: (@MainActor () -> Void)?

    init() {
        let confirmation = self.confirmation
        runtime = AgentRuntime(confirm: { await confirmation.confirm($0) })
        agent = AGUIHTTPAgent(url: URL(string: "http://localhost:\(agentPort)/agent")!)
        let card = A2UIAppComponent("ProductCard", description: "상품 카드 (이름 · 가격 · 담기 버튼)",
                                    properties: ["name": A2UIProp.string, "price": A2UIProp.number, "action": A2UIProp.action],
                                    required: ["name"]) { props in
            ProductCard(name: props.string("name") ?? "", price: props.double("price"), onAdd: props.action("action"))
        }
        var send: A2UISend = { _ in }
        // swiftlint:disable:next force_try
        host = try! A2UISurfaceHost(runtime, catalogId: "\(a2uiBase)/catalog.json", components: [card]) { send($0) }
        send = { [weak self] message in
            self?.write("→ \(compact(message))")
            Task { try? await post("response", message) }
        }
        offTriggers = connectTriggers(agent, runtime, onError: { [weak self] error, event in
            self?.write("trigger \(event.name) 실패: \(error)")
        })
        // 표시가 화면 생명주기로 바뀌므로 등록 변경마다 catalog 다시 전송 (한 번에 하나, 마지막 상태로)
        offCatalog = runtime.subscribe { [weak self] in self?.catalogChanged() }
    }

    private var postingCatalog = false
    private var catalogDirty = false

    private func catalogChanged() {
        catalogDirty = true
        guard !postingCatalog else { return }
        postingCatalog = true
        Task {
            while catalogDirty {
                catalogDirty = false
                if let catalog = try? host.catalog() { _ = try? await post("catalog", catalog) }
            }
            postingCatalog = false
        }
    }

    func write(_ line: String) {
        log.append(line)
        print(line)
    }

    /// AG-UI: tool call → 앱 실행 → 결과를 다시 에이전트로
    func sendAGUI(_ text: String) async {
        agent.addMessages([AGUIMessage(id: UUID().uuidString, role: "user", content: text)])
        do {
            let r = try await runWithFrontendTools(agent, runtime)
            for m in r.toolMessages { write("tool result \(m.content ?? "")") }
            if let last = agent.messages.last(where: { $0.role == "assistant" })?.content { write("agent: \(last)") }
        } catch {
            write("오류: \(error)")
        }
    }

    /// A2UI: 채팅은 mock 이 판단, 실행 요청 · surface 는 SSE 로 온다
    func sendA2UI(_ text: String) async {
        do {
            let reply = try await post("chat", ["text": .string(text)])
            write("agent: \(reply["reply"]?.stringValue ?? "")")
        } catch {
            write("오류: \(error)")
        }
    }

    func connectA2UI() async {
        do {
            _ = try await post("catalog", host.catalog())
            if let components = host.componentCatalog() { _ = try await post("components", components) }
            write("A2UI catalog 전송")
            let (bytes, _) = try await URLSession.shared.bytes(from: a2uiBase.appending(path: "events"))
            write("A2UI SSE 연결")
            for try await line in bytes.lines where line.hasPrefix("data:") {
                let data = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                guard let message = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                write("← \(compact(message))")
                await host.process(message: message)
            }
        } catch {
            write("A2UI 연결 실패: \(error)")
        }
    }
}

func post(_ path: String, _ body: JSONValue) async throws -> JSONValue {
    var r = URLRequest(url: a2uiBase.appending(path: path))
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try JSONEncoder().encode(body)
    let (data, _) = try await URLSession.shared.data(for: r)
    return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
}

func compact(_ v: JSONValue) -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: e.encode(v), as: UTF8.self)) ?? "?"
}

// ── 화면 ───────────────────────────────────────────────────────

struct ProductCard: View {
    let name: String
    let price: Double?
    let onAdd: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                if let price { Text("\(Int(price))원").foregroundStyle(.secondary) }
            }
            Spacer()
            if let onAdd { Button("담기", action: onAdd) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

struct ShopView: View {
    @ObservedObject var store: Store
    let runtime: AgentRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("미니 상점").font(.title)
            Picker("분류", selection: $store.filter) {
                Text("전체").tag("all")
                Text("신발").tag("shoes")
                Text("가방").tag("bags")
            }
            .agentAction("filter_set", ActionDef(description: "상품 목록 분류 필터 변경",
                                                 input: ["type": "object", "properties": ["category": ["type": "string", "enum": ["all", "shoes", "bags"]]],
                                                         "required": ["category"]])) { args in
                store.filter = args["category"]?.stringValue ?? "all"
                return .null
            }
            .agentState("filter", StateDef(description: "현재 분류 필터"), value: store.filter)

            List(store.visible) { p in
                HStack {
                    Text("\(p.id). \(p.name)")
                    Spacer()
                    Button("담기") { _ = try? store.add(p.id) }
                }
            }
            .agentAction("cart_add", ActionDef(description: "상품을 장바구니에 담기. 반환: 장바구니 개수",
                                               input: ["type": "object", "properties": ["id": ["type": "number"]], "required": ["id"]],
                                               returns: .number)) { args in
                guard case .number(let n)? = args["id"] else { throw ShopError.notFound(0) }
                return .number(Double(try store.add(Int(n))))
            }
            .agentView("product_list", ViewDef(description: "상품 목록"))

            HStack {
                Text("장바구니 \(store.cart.count)개").font(.headline)
                Button("비우기") { store.cart = [] }
                    .agentAction("cart_clear", ActionDef(description: "장바구니 비우기", confirm: true)) { _ in
                        store.cart = []
                        return .null
                    }
                Button("저장") { try? runtime.trigger("cart_saved", payload: ["count": .number(Double(store.cart.count))]) }
            }
            .agentState("cart", StateDef(description: "장바구니 상품 목록"), value: store.cart)
            .agentView("cart", ViewDef(description: "장바구니"))
            Text(store.cart.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ChatView: View {
    @ObservedObject var agents: Agents
    @ObservedObject var host: A2UISurfaceHost
    @State private var mode = "ag-ui"
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading) {
            Picker("에이전트", selection: $mode) {
                Text("AG-UI (:\(agentPort))").tag("ag-ui")
                Text("A2UI (:\(a2uiPort))").tag("a2ui")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(agents.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption).textSelection(.enabled)
                    }
                    ForEach(host.surfaceIDs, id: \.self) { id in
                        A2UISurfaceView(host: host, surfaceID: id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                TextField("신발만 보여줘 · 2번 담아줘 · 장바구니 비워줘 · 추천", text: $text)
                    .onSubmit(submit)
                Button("보내기", action: submit)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        text = ""
        agents.write("나: \(t)")
        Task { mode == "ag-ui" ? await agents.sendAGUI(t) : await agents.sendA2UI(t) }
    }
}

@main
struct ShopApp: App {
    @StateObject private var store = Store()
    @StateObject private var agents = Agents()

    init() {
        // swift run 으로 띄운 실행 파일도 일반 앱처럼 창 · Dock 표시
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("gentizer 예시") {
            HStack(spacing: 0) {
                ShopView(store: store, runtime: agents.runtime)
                Divider()
                ChatView(agents: agents, host: agents.host)
            }
            .agentRuntime(agents.runtime)
            .agentConfirmation(agents.confirmation)
            .frame(minWidth: 820, minHeight: 520)
            .task { await agents.connectA2UI() }
            .task { await smokeExit() }
        }
    }

    /// GENTIZER_EXAMPLE_SMOKE=1 이면 mock 과 정해진 대화를 하고 결과를 출력한 뒤 종료 (실행 확인용)
    private func smokeExit() async {
        guard ProcessInfo.processInfo.environment["GENTIZER_EXAMPLE_SMOKE"] == "1" else { return }
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await wait(1.5)
        await agents.sendAGUI("2번 담아줘")
        let cartAfterAGUI = store.cart.map(\.id)
        await agents.sendA2UI("신발만 보여줘")
        await wait(0.5)
        let filterAfterA2UI = store.filter
        await agents.sendA2UI("추천")
        await wait(0.5)
        let surfaces = agents.host.surfaceIDs
        try? agents.runtime.trigger("cart_saved", payload: ["count": .number(Double(store.cart.count))])
        await wait(1)
        let triggerReply = agents.agent.messages.contains { $0.content?.hasPrefix("앱 이벤트 수신") == true }
        let actions = agents.runtime.manifest().actions.names.joined(separator: ",")
        print("smoke: actions \(actions) · cart \(cartAfterAGUI) · filter \(filterAfterA2UI) · surfaces \(surfaces) · trigger \(triggerReply)")
        exit(0)
    }
}
