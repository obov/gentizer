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

// 메시지 처리 규칙은 conformance/a2ui (conformance.test.ts). 여기는 TS 고유 (등록 변경 추적 · dispose)
describe("createA2uiBridge TS 고유", () => {
  test("catalog() 은 toA2uiCatalog 결과", () => {
    const { rt, bridge } = setup();
    expect(bridge.catalog()).toEqual(toA2uiCatalog(rt.manifest(), { catalogId }));
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
