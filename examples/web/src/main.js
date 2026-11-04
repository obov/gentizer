import { createAgentRuntime } from "@gentizer/core";
import { createA2uiSurfaceHost } from "@gentizer/a2ui";
import { runWithFrontendTools } from "@gentizer/ag-ui";
import { HttpAgent } from "@ag-ui/client";

// ── 기존 앱 코드 (gentizer 와 무관) ─────────────────────────────
const PRODUCTS = [
  { id: 1, name: "러닝화", category: "shoes" },
  { id: 2, name: "가죽 구두", category: "shoes" },
  { id: 3, name: "백팩", category: "bags" },
  { id: 4, name: "토트백", category: "bags" },
];
const store = { filter: "all", cart: [] };
const $ = (id) => document.getElementById(id);

function render() {
  $("filter").value = store.filter;
  $("products").innerHTML = "";
  for (const p of PRODUCTS.filter((p) => store.filter === "all" || p.category === store.filter)) {
    const li = document.createElement("li");
    li.textContent = `${p.id}. ${p.name}`;
    const b = document.createElement("button");
    b.textContent = "담기";
    b.onclick = () => addToCart(p.id);
    li.append(b);
    $("products").append(li);
  }
  $("cart").innerHTML = store.cart.map((p) => `<li>${p.name}</li>`).join("") || "<li>비어 있음</li>";
}
function setFilter(category) { store.filter = category; render(); }
function addToCart(id) {
  const p = PRODUCTS.find((p) => p.id === id);
  if (!p) throw new Error(`상품 없음: ${id}`);
  store.cart.push(p);
  render();
  return store.cart.length;
}
function clearCart() { store.cart = []; render(); }
$("filter").onchange = (e) => setFilter(e.target.value);
$("clear").onclick = clearCart;
render();

// ── gentizer: 에이전트가 조작해도 되는 부분만 표시 ────────────────
const runtime = createAgentRuntime({
  confirm: ({ name, args }) => window.confirm(`에이전트가 ${name} 실행을 요청함\n${JSON.stringify(args)}\n승인?`),
});
runtime.action("filter_set", {
  description: "상품 목록 분류 필터 변경",
  input: { type: "object", properties: { category: { type: "string", enum: ["all", "shoes", "bags"] } }, required: ["category"] },
}, (a) => setFilter(a.category));
runtime.action("cart_add", {
  description: "상품을 장바구니에 담기. 반환: 장바구니 개수",
  input: { type: "object", properties: { id: { type: "number" } }, required: ["id"] },
  returns: "number",
}, (a) => addToCart(a.id));
runtime.action("cart_clear", { description: "장바구니 비우기", confirm: true }, () => clearCart());
runtime.state("cart", { description: "장바구니 상품 목록" }, () => store.cart);
runtime.state("filter", { description: "현재 분류 필터" }, () => store.filter);

// ── 채팅 UI ───────────────────────────────────────────────────
const log = (cls, text) => {
  const d = document.createElement("div");
  d.className = cls;
  d.textContent = text;
  $("chat").append(d);
  $("chat").scrollTop = $("chat").scrollHeight;
};

// AG-UI: HttpAgent + runWithFrontendTools (tool call → 앱 실행 → 결과를 다시 agent 로)
const agent = new HttpAgent({ url: "/agent" });
agent.subscribe({
  onTextMessageEndEvent: ({ textMessageBuffer }) => log("agent", `agent: ${textMessageBuffer}`),
  onToolCallEndEvent: ({ toolCallName, toolCallArgs }) => log("sys", `tool call ${toolCallName} ${JSON.stringify(toolCallArgs)}`),
});
async function sendAgUi(text) {
  agent.addMessage({ id: crypto.randomUUID(), role: "user", content: text });
  const { rounds, toolMessages } = await runWithFrontendTools(agent, runtime);
  for (const m of toolMessages) log("sys", `tool result ${m.content}`);
  log("sys", `rounds ${rounds}`);
}

// A2UI: 서버가 SSE 로 보낸 메시지를 host 가 처리 (callRendererFunction → 액션 실행), 렌더러 → 에이전트 메시지는 POST
const catalogId = `${location.origin}/catalog.json`;
const post = (path, body) =>
  fetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
const host = createA2uiSurfaceHost(runtime, {
  catalogId,
  send: (message) => {
    log("sys", `→ ${JSON.stringify(message)}`);
    post("/a2ui/response", message);
  },
});
post("/a2ui/catalog", host.catalog());
new EventSource("/a2ui/events").onmessage = (e) => {
  const message = JSON.parse(e.data);
  log("sys", `← ${JSON.stringify(message)}`);
  host.process(message);
};
async function sendA2ui(text) {
  const { reply } = await post("/a2ui/chat", { text });
  log("agent", `agent: ${reply}`);
}

$("form").onsubmit = async (e) => {
  e.preventDefault();
  const input = e.target.elements.text;
  const text = input.value.trim();
  if (!text) return;
  input.value = "";
  log("user", `나: ${text}`);
  try {
    await ($("mode").value === "ag-ui" ? sendAgUi(text) : sendA2ui(text));
  } catch (err) {
    log("sys", `오류: ${err.message}`);
  }
};
