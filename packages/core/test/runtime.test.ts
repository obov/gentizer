import { describe, expect, test, vi } from "vitest";
import { createAgentRuntime, DuplicateNameError } from "../src/index.js";

const filterDef = {
  description: "목록 필터 변경",
  input: { type: "object" as const, properties: { category: { type: "string" } }, required: ["category"] },
};

describe("등록", () => {
  test("등록 · 해제 · 재등록", () => {
    const rt = createAgentRuntime();
    const off = rt.action("cart_add", { description: "담기" }, () => {});
    expect(Object.keys(rt.manifest().actions)).toEqual(["cart_add"]);
    off();
    expect(rt.manifest().actions).toEqual({});
    rt.action("cart_add", { description: "담기" }, () => {});
    expect(Object.keys(rt.manifest().actions)).toEqual(["cart_add"]);
  });

  test("등록 중 같은 이름은 DuplicateNameError", () => {
    const rt = createAgentRuntime();
    rt.state("cart", { description: "장바구니" }, () => []);
    expect(() => rt.state("cart", { description: "x" }, () => [])).toThrow(DuplicateNameError);
  });

  test("이전 해제 함수는 재등록을 지우지 않음 (D4)", () => {
    const rt = createAgentRuntime();
    const off1 = rt.view("cart", { description: "a" });
    off1();
    rt.view("cart", { description: "b" });
    off1();
    expect(rt.manifest().views).toEqual({ cart: { description: "b" } });
  });

  test("manifest 등록 순서 · 구역 분리", () => {
    const rt = createAgentRuntime();
    rt.action("b", { description: "b" }, () => {});
    rt.action("a", { description: "a" }, () => {});
    rt.state("a", { description: "s" }, () => 1);
    const m = rt.manifest();
    expect(m.version).toBe("gentizer/0.1");
    expect(Object.keys(m.actions)).toEqual(["b", "a"]);
    expect(Object.keys(m.state)).toEqual(["a"]);
  });

  test("readState 현재 값 · 미등록 undefined", () => {
    const rt = createAgentRuntime();
    let n = 1;
    rt.state("count", { description: "개수" }, () => n);
    n = 2;
    expect(rt.readState("count")).toBe(2);
    expect(rt.readState("none")).toBeUndefined();
  });

  test("subscribe 는 등록 · 해제마다 호출, 해제 후 미호출", () => {
    const rt = createAgentRuntime();
    const l = vi.fn();
    const unsub = rt.subscribe(l);
    const off = rt.action("a", { description: "a" }, () => {});
    off();
    expect(l).toHaveBeenCalledTimes(2);
    unsub();
    rt.action("a", { description: "a" }, () => {});
    expect(l).toHaveBeenCalledTimes(2);
  });
});

describe("invoke", () => {
  test("NOT_FOUND", async () => {
    const r = await createAgentRuntime().invoke("nope");
    expect(r).toMatchObject({ ok: false, error: { code: "NOT_FOUND" } });
  });

  test("INVALID_ARGS: object 아님 · required 누락", async () => {
    const rt = createAgentRuntime();
    const run = vi.fn();
    rt.action("filter_set", filterDef, run);
    expect(await rt.invoke("filter_set", [])).toMatchObject({ ok: false, error: { code: "INVALID_ARGS" } });
    expect(await rt.invoke("filter_set", {})).toMatchObject({ ok: false, error: { code: "INVALID_ARGS" } });
    expect(run).not.toHaveBeenCalled();
  });

  test("실행 결과 전달 · args 생략 시 {} · undefined → null", async () => {
    const rt = createAgentRuntime();
    rt.action("filter_set", filterDef, (a) => `set ${a.category}`);
    const run = vi.fn();
    rt.action("cart_clear", { description: "비우기" }, run);
    expect(await rt.invoke("filter_set", { category: "shoes" })).toEqual({ ok: true, value: "set shoes" });
    expect(await rt.invoke("cart_clear")).toEqual({ ok: true, value: null });
    expect(run).toHaveBeenCalledWith({});
  });

  test("DENIED: confirm 콜백 없음 · false · throw", async () => {
    const run = vi.fn();
    const def = { description: "결제", confirm: true };
    for (const confirm of [undefined, () => false, async () => false, () => { throw new Error("x"); }]) {
      const rt = createAgentRuntime(confirm ? { confirm } : {});
      rt.action("pay", def, run);
      expect(await rt.invoke("pay")).toMatchObject({ ok: false, error: { code: "DENIED" } });
    }
    expect(run).not.toHaveBeenCalled();
  });

  test("승인 후 실행 · 콜백 인자", async () => {
    const confirm = vi.fn(async () => true);
    const rt = createAgentRuntime({ confirm });
    rt.action("pay", { description: "결제", confirm: true }, () => 42);
    expect(await rt.invoke("pay", { amount: 1 })).toEqual({ ok: true, value: 42 });
    expect(confirm).toHaveBeenCalledWith({ name: "pay", description: "결제", args: { amount: 1 } });
  });

  test("EXECUTION_ERROR: throw · reject", async () => {
    const rt = createAgentRuntime();
    rt.action("a", { description: "a" }, () => { throw new Error("boom"); });
    rt.action("b", { description: "b" }, async () => Promise.reject(new Error("later")));
    expect(await rt.invoke("a")).toEqual({ ok: false, error: { code: "EXECUTION_ERROR", message: "boom" } });
    expect(await rt.invoke("b")).toEqual({ ok: false, error: { code: "EXECUTION_ERROR", message: "later" } });
  });
});
