import { afterEach, describe, expect, test } from "vitest";
import { createAgentRuntime } from "@gentizer/core";
import { bindAgentAttributes } from "../src/index.js";

const tick = () => new Promise((r) => setTimeout(r, 0));

function setup(html: string) {
  document.body.innerHTML = html;
  const rt = createAgentRuntime({ confirm: () => true });
  const errors: string[] = [];
  const off = bindAgentAttributes(rt, document.body, { onError: (e) => errors.push(String((e as Error).message)) });
  return { rt, errors, off };
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("액션 · 화면 · confirm", () => {
  test("click 이벤트로 실행, 반환 null", async () => {
    const { rt } = setup(`<button data-agent-action="cart_add" data-agent-desc="담기">담기</button>`);
    let clicks = 0;
    document.querySelector("button")!.addEventListener("click", () => clicks++);
    expect(await rt.invoke("cart_add")).toEqual({ ok: true, value: null });
    expect(clicks).toBe(1);
    expect(rt.manifest().actions.cart_add).toEqual({ description: "담기" });
  });

  test("form 은 requestSubmit (submit 이벤트)", async () => {
    const { rt } = setup(`<form data-agent-action="search_submit" data-agent-desc="검색"><input name="q"></form>`);
    let submits = 0;
    document.querySelector("form")!.addEventListener("submit", (e) => {
      e.preventDefault();
      submits++;
    });
    expect((await rt.invoke("search_submit")).ok).toBe(true);
    expect(submits).toBe(1);
  });

  test("disabled · aria-disabled · detached 는 EXECUTION_ERROR", async () => {
    const { rt } = setup(`
      <button data-agent-action="a1" data-agent-desc="a" disabled></button>
      <div data-agent-action="a2" data-agent-desc="b" aria-disabled="true"></div>
      <div data-agent-action="a3" data-agent-desc="c"></div>`);
    const r1 = await rt.invoke("a1");
    const r2 = await rt.invoke("a2");
    expect(r1.ok ? null : r1.error).toMatchObject({ code: "EXECUTION_ERROR", message: "disabled: a1" });
    expect(r2.ok ? null : r2.error).toMatchObject({ code: "EXECUTION_ERROR", message: "disabled: a2" });
    // 제거 직후 (관찰 반영 전) 실행
    const el = document.querySelector('[data-agent-action="a3"]')!;
    el.remove();
    const r3 = await rt.invoke("a3");
    expect(r3.ok ? null : r3.error).toMatchObject({ code: "EXECUTION_ERROR", message: "detached: a3" });
  });

  test("confirm 속성 → confirm: true, 화면 등록", () => {
    const { rt } = setup(`
      <button data-agent-action="cart_clear" data-agent-desc="비우기" data-agent-confirm></button>
      <section data-agent-view="cart" data-agent-desc="장바구니"></section>`);
    expect(rt.manifest().actions.cart_clear).toEqual({ description: "비우기", confirm: true });
    expect(rt.manifest().views).toEqual({ cart: { description: "장바구니" } });
  });

  test("desc 없음 · 이름 규칙 위반 · 중복은 onError, 먼저 것 유지", () => {
    const { rt, errors } = setup(`
      <button data-agent-action="no_desc"></button>
      <button data-agent-action="Bad.Name" data-agent-desc="x"></button>
      <button id="first" data-agent-action="dup" data-agent-desc="첫째"></button>
      <button data-agent-action="dup" data-agent-desc="둘째"></button>`);
    expect(Object.keys(rt.manifest().actions)).toEqual(["dup"]);
    expect(rt.manifest().actions.dup).toEqual({ description: "첫째" });
    expect(errors).toHaveLength(3);
  });

  test("등록 순서 = 문서 순서, 해제 시 전부 해제", () => {
    const { rt, off } = setup(`
      <div data-agent-view="b_view" data-agent-desc="b"><button data-agent-action="z_act" data-agent-desc="z"></button></div>
      <button data-agent-action="a_act" data-agent-desc="a"></button>`);
    expect(Object.keys(rt.manifest().actions)).toEqual(["z_act", "a_act"]);
    off();
    expect(rt.manifest()).toMatchObject({ actions: {}, state: {}, views: {} });
  });
});
