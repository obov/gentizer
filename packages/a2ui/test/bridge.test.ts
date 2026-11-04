import { describe, expect, test, vi } from "vitest";
import { createAgentRuntime, toA2uiCatalog } from "@gentizer/core";
import { createA2uiBridge } from "../src/index.js";

const catalogId = "https://example.com/shop/catalog.json";
const filterDef = {
  description: "목록 필터 변경",
  input: { type: "object" as const, properties: { category: { type: "string" } }, required: ["category"] },
  returns: "string" as const,
};

let seq = 0;
const msg = (name: string, args?: Record<string, unknown>, id: string | undefined = catalogId) => ({
  version: "1.0" as const,
  callRendererFunction: {
    functionCallId: `c${++seq}`,
    callFunction: { "@call": name, ...(id === undefined ? {} : { catalogId: id }), ...(args ? { args } : {}) },
  },
});

function setup(confirm?: () => boolean) {
  const rt = createAgentRuntime(confirm ? { confirm } : {});
  rt.action("filter_set", filterDef, (a) => `set ${a.category}`);
  return { rt, bridge: createA2uiBridge(rt, { catalogId }) };
}

describe("createA2uiBridge", () => {
  test("catalog() 은 toA2uiCatalog 결과", () => {
    const { rt, bridge } = setup();
    expect(bridge.catalog()).toEqual(toA2uiCatalog(rt.manifest(), { catalogId }));
  });

  test("성공 value", async () => {
    const { bridge } = setup();
    const r = await bridge.handle(msg("filter_set", { category: "shoes" }));
    expect(r.rendererFunctionResponse).toMatchObject({ value: "set shoes" });
  });

  test("catalogId 생략 시 채움 · 다른 catalogId 오류", async () => {
    const { bridge } = setup();
    expect((await bridge.handle(msg("filter_set", { category: "a" }, undefined))).rendererFunctionResponse).toMatchObject({
      value: "set a",
    });
    expect((await bridge.handle(msg("filter_set", { category: "a" }, "https://other"))).rendererFunctionResponse).toMatchObject({
      error: { code: "INVALID_FUNCTION_CALL" },
    });
  });

  test("required 누락은 INVALID_FUNCTION_CALL, 실행 안 함", async () => {
    const rt = createAgentRuntime();
    const run = vi.fn();
    rt.action("filter_set", filterDef, run);
    const bridge = createA2uiBridge(rt, { catalogId });
    expect((await bridge.handle(msg("filter_set", {}))).rendererFunctionResponse).toMatchObject({
      error: { code: "INVALID_FUNCTION_CALL" },
    });
    expect(run).not.toHaveBeenCalled();
  });

  test("해제된 액션 INVALID_FUNCTION_CALL · 추가된 액션 실행", async () => {
    const rt = createAgentRuntime();
    const off = rt.action("cart_add", { description: "담기" }, () => "added");
    const bridge = createA2uiBridge(rt, { catalogId });
    expect((await bridge.handle(msg("cart_add"))).rendererFunctionResponse).toMatchObject({ value: "added" });
    off();
    expect((await bridge.handle(msg("cart_add"))).rendererFunctionResponse).toMatchObject({
      error: { code: "INVALID_FUNCTION_CALL" },
    });
    rt.action("cart_clear", { description: "비우기" }, () => "cleared");
    expect((await bridge.handle(msg("cart_clear"))).rendererFunctionResponse).toMatchObject({ value: "cleared" });
  });

  test("confirm 거부는 EXECUTION_ERROR 'DENIED:'", async () => {
    const rt = createAgentRuntime({ confirm: () => false });
    const run = vi.fn();
    rt.action("pay", { description: "결제", confirm: true }, run);
    const r = await createA2uiBridge(rt, { catalogId }).handle(msg("pay"));
    expect(r.rendererFunctionResponse.error?.code).toBe("EXECUTION_ERROR");
    expect(r.rendererFunctionResponse.error?.message).toMatch(/^DENIED: /);
    expect(run).not.toHaveBeenCalled();
  });

  test("dispose 후 runtime 구독 해제", () => {
    const rt = createAgentRuntime();
    const unsub = vi.fn();
    const original = rt.subscribe;
    rt.subscribe = (l) => {
      const off = original(l);
      return () => {
        unsub();
        off();
      };
    };
    const bridge = createA2uiBridge(rt, { catalogId });
    expect(unsub).not.toHaveBeenCalled();
    bridge.dispose();
    expect(unsub).toHaveBeenCalledTimes(1);
  });
});
