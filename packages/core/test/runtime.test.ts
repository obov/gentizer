import { describe, expect, test, vi } from "vitest";
import { createAgentRuntime } from "../src/index.js";

// 등록 · invoke · confirm 규칙은 conformance/runtime (conformance.test.ts). 여기는 TS 고유 (구독 · 클로저 · Promise)

describe("runtime TS 고유", () => {
  test("subscribe 는 등록 · 해제마다 호출, 구독 해제 후 미호출", () => {
    const rt = createAgentRuntime();
    const l = vi.fn();
    const unsub = rt.subscribe(l);
    const off = rt.action("a", { description: "a" }, () => {});
    off();
    off();
    expect(l).toHaveBeenCalledTimes(2);
    unsub();
    rt.action("a", { description: "a" }, () => {});
    expect(l).toHaveBeenCalledTimes(2);
  });

  test("readState 는 호출 시점 값", () => {
    const rt = createAgentRuntime();
    let n = 1;
    rt.state("count", { description: "개수" }, () => n);
    n = 2;
    expect(rt.readState("count")).toBe(2);
  });

  test("run 이 undefined 반환 시 value null", async () => {
    const rt = createAgentRuntime();
    rt.action("a", { description: "a" }, () => undefined);
    expect(await rt.invoke("a")).toEqual({ ok: true, value: null });
  });

  test("async run · async confirm · reject 는 EXECUTION_ERROR", async () => {
    const rt = createAgentRuntime({ confirm: async () => true });
    rt.action("pay", { description: "결제", confirm: true }, async () => 42);
    rt.action("late", { description: "b" }, async () => Promise.reject(new Error("later")));
    expect(await rt.invoke("pay")).toEqual({ ok: true, value: 42 });
    expect(await rt.invoke("late")).toEqual({ ok: false, error: { code: "EXECUTION_ERROR", message: "later" } });
  });

  test("등록 후 def 변경이 manifest 에 번지지 않음", () => {
    const rt = createAgentRuntime();
    const def = { description: "a" };
    rt.action("a", def, () => {});
    def.description = "changed";
    expect(rt.manifest().actions["a"]).toEqual({ description: "a" });
  });
});
