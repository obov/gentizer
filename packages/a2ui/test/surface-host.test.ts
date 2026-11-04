import { describe, expect, test } from "vitest";
import { createAgentRuntime } from "@gentizer/core";
import { basicCatalog } from "@a2ui/web_core/v1_0";
import { createA2uiSurfaceHost, type RendererMessage } from "../src/index.js";

const catalogId = "https://example.com/shop/catalog.json";

function setup(options: { stateSync?: boolean; triggerSurfaceId?: string } = {}) {
  const rt = createAgentRuntime();
  const sent: RendererMessage[] = [];
  const host = createA2uiSurfaceHost(rt, { catalogId, send: (m) => sent.push(m), ...options });
  return { rt, host, sent };
}

const create = (surfaceId: string, sendDataModel = false) => ({
  version: "1.0",
  createSurface: { surfaceId, catalogId: basicCatalog.id, sendDataModel },
});
const components = (surfaceId: string) => ({
  version: "1.0",
  updateComponents: {
    surfaceId,
    components: [
      { id: "root", component: "Button", child: "t", action: { event: { name: "buy", context: { id: 2 } } } },
      { id: "t", component: "Text", text: "담기" },
    ],
  },
});

describe("createA2uiSurfaceHost", () => {
  test("callRendererFunction 응답은 send", async () => {
    const { rt, host, sent } = setup();
    rt.action("ping", { description: "핑" }, () => "pong");
    await host.process({ version: "1.0", callRendererFunction: { functionCallId: "c1", callFunction: { "@call": "ping" } } });
    expect(sent).toEqual([{ version: "1.0", rendererFunctionResponse: { functionCallId: "c1", value: "pong" } }]);
  });

  test("surface 생성 · 삭제 · subscribe", async () => {
    const { host } = setup();
    let n = 0;
    const off = host.subscribe(() => n++);
    await host.process(create("b"));
    await host.process(create("a"));
    expect(host.surfaceIds()).toEqual(["a", "b"]);
    await host.process({ version: "1.0", deleteSurface: { surfaceId: "a" } });
    expect(host.surfaceIds()).toEqual(["b"]);
    expect(n).toBe(3);
    off();
    await host.process({ version: "1.0", deleteSurface: { surfaceId: "b" } });
    expect(n).toBe(3);
  });

  test("잘못된 메시지 → error send, reject 없음", async () => {
    const { host, sent } = setup();
    await host.process("garbage");
    await host.process({ version: "1.0", createSurface: { surfaceId: "x", catalogId: "nope" } });
    expect(sent.map((m) => (m.error as { code: string }).code)).toEqual(["VALIDATION_FAILED", "CATALOG_NOT_FOUND"]);
  });

  test("surface 컴포넌트 action → action send", async () => {
    const { host, sent } = setup();
    await host.process(create("s1"));
    await host.process(components("s1"));
    await host.surface("s1")!.dispatchAction({ event: { name: "buy", context: { id: 2 } } }, "root");
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ version: "1.0", action: { name: "buy", surfaceId: "s1", sourceComponentId: "root", context: { id: 2 } } });
  });

  test("trigger → action (triggerSurfaceId · sourceComponentId gentizer · context = payload)", () => {
    const { rt, sent } = setup({ triggerSurfaceId: "app" });
    rt.trigger("form_saved", { id: 7 });
    expect(sent).toHaveLength(1);
    const action = sent[0]!.action as Record<string, unknown>;
    expect(action).toMatchObject({ name: "form_saved", surfaceId: "app", sourceComponentId: "gentizer", context: { id: 7 } });
    expect(new Date(action.timestamp as string).toISOString()).toBe(action.timestamp);
  });

  test("callAgentFunction: send → agentFunctionResponse value 로 resolve, error 면 reject", async () => {
    const { host, sent } = setup();
    await host.process(create("s1"));
    const ok = host.callAgentFunction("s1", { call: "lookup", args: { q: 1 } });
    const call = sent[0]!.callAgentFunction as { functionCallId: string; surfaceId: string; callFunction: unknown };
    expect(call).toMatchObject({ surfaceId: "s1", callFunction: { "@call": "lookup", args: { q: 1 } } });
    await host.process({ version: "1.0", agentFunctionResponse: { functionCallId: call.functionCallId, value: 42 } });
    await expect(ok).resolves.toBe(42);

    const bad = host.callAgentFunction("s1", { call: "lookup" });
    const id = (sent[1]!.callAgentFunction as { functionCallId: string }).functionCallId;
    await host.process({ version: "1.0", agentFunctionResponse: { functionCallId: id, error: { code: "X", message: "실패" } } });
    await expect(bad).rejects.toThrow();
  });

  test("dispose 는 대기 중 callAgentFunction reject", async () => {
    const { host } = setup();
    await host.process(create("s1"));
    const p = host.callAgentFunction("s1", { call: "lookup" });
    host.dispose();
    await expect(p).rejects.toThrow();
  });

  test("상태 · 화면 → /gentizer, 해제된 상태 키 삭제, dataModel() 형식", async () => {
    const { rt, host } = setup();
    let cart = [1];
    const offCart = rt.state("cart", { description: "장바구니" }, () => cart);
    rt.state("empty", { description: "없음" }, () => undefined);
    rt.view("list", { description: "상품 목록" });
    await host.process(create("s1", true));
    expect(host.dataModel()).toEqual({
      version: "1.0",
      surfaces: { s1: { gentizer: { state: { cart: [1] }, views: { list: "상품 목록" } } } },
    });
    cart = [1, 2];
    host.syncState();
    expect(host.surface("s1")!.dataModel.get("/gentizer/state/cart")).toEqual([1, 2]);
    offCart();
    expect(host.surface("s1")!.dataModel.get("/gentizer/state")).toEqual({});
  });

  test("stateSync false 면 /gentizer 없음", async () => {
    const { rt, host } = setup({ stateSync: false });
    rt.state("cart", { description: "장바구니" }, () => [1]);
    await host.process(create("s1", true));
    expect(host.dataModel()).toEqual({ version: "1.0", surfaces: { s1: {} } });
  });
});
