import { afterEach, describe, expect, test } from "vitest";
import { act, useState } from "react";
import { createRoot } from "react-dom/client";
import { createAgentRuntime } from "@gentizer/core";
import { bindAgentAttributes } from "../src/index.js";

// react-dom act 경고 억제
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function setup(html: string) {
  document.body.innerHTML = html;
  const rt = createAgentRuntime();
  const off = bindAgentAttributes(rt);
  return { rt, off };
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("필드", () => {
  test("text: 상태 · 스키마 · 실행 (input · change 이벤트)", async () => {
    const { rt } = setup(`<input data-agent-field="search" data-agent-desc="검색어" value="a">`);
    const input = document.querySelector("input")!;
    const events: string[] = [];
    input.addEventListener("input", () => events.push("input"));
    input.addEventListener("change", () => events.push("change"));
    expect(rt.readState("search")).toBe("a");
    expect(rt.manifest().actions.search_set).toEqual({
      description: "검색어 값 설정",
      input: { type: "object", properties: { value: { type: "string" } }, required: ["value"] },
      returns: "any",
    });
    expect(await rt.invoke("search_set", { value: "신발" })).toEqual({ ok: true, value: "신발" });
    expect(input.value).toBe("신발");
    expect(events).toEqual(["input", "change"]);
  });

  test("number · checkbox 스키마와 값", async () => {
    const { rt } = setup(`
      <input type="number" data-agent-field="qty" data-agent-desc="수량" value="1">
      <input type="checkbox" data-agent-field="gift" data-agent-desc="선물 포장">`);
    expect(rt.manifest().actions.qty_set!.input!.properties).toEqual({ value: { type: "number" } });
    expect(rt.manifest().actions.gift_set!.input!.properties).toEqual({ value: { type: "boolean" } });
    expect(rt.readState("gift")).toBe(false);
    expect(await rt.invoke("gift_set", { value: true })).toEqual({ ok: true, value: true });
    expect(await rt.invoke("qty_set", { value: 3 })).toEqual({ ok: true, value: "3" });
  });

  test("select · multiple: enum, 밖 값은 오류", async () => {
    const { rt } = setup(`
      <select data-agent-field="category" data-agent-desc="분류"><option value="all">전체</option><option value="shoes">신발</option></select>
      <select multiple data-agent-field="tags" data-agent-desc="태그"><option value="a">a</option><option value="b">b</option></select>`);
    expect(rt.manifest().actions.category_set!.input!.properties).toEqual({ value: { type: "string", enum: ["all", "shoes"] } });
    expect(rt.manifest().actions.tags_set!.input!.properties).toEqual({
      value: { type: "array", items: { type: "string", enum: ["a", "b"] } },
    });
    expect(await rt.invoke("category_set", { value: "shoes" })).toEqual({ ok: true, value: "shoes" });
    const bad = await rt.invoke("category_set", { value: "bags" });
    expect(bad.ok ? null : bad.error.message).toBe("invalid option: bags");
    expect(await rt.invoke("tags_set", { value: ["b"] })).toEqual({ ok: true, value: ["b"] });
    expect(rt.readState("tags")).toEqual(["b"]);
  });

  test("React 제어 input 의 onChange 가 불린다", async () => {
    document.body.innerHTML = `<div id="app"></div>`;
    let seen = "";
    function App() {
      const [v, setV] = useState("");
      seen = v;
      return <input data-agent-field="name" data-agent-desc="이름" value={v} onChange={(e) => setV(e.target.value)} />;
    }
    const root = createRoot(document.getElementById("app")!);
    await act(async () => root.render(<App />));
    const rt = createAgentRuntime();
    bindAgentAttributes(rt);
    await act(async () => {
      await rt.invoke("name_set", { value: "홍길동" });
    });
    expect(seen).toBe("홍길동");
    expect(rt.readState("name")).toBe("홍길동");
    root.unmount();
  });
});

describe("관찰", () => {
  const tick = () => new Promise((r) => setTimeout(r, 0));

  test("추가 · 제거 · 이름 변경 · desc 변경 · option 변경", async () => {
    const { rt } = setup(`<div id="box"></div><select data-agent-field="size" data-agent-desc="크기"><option value="s">s</option></select>`);
    const box = document.getElementById("box")!;
    box.innerHTML = `<button data-agent-action="buy" data-agent-desc="구매"></button>`;
    await tick();
    expect(Object.keys(rt.manifest().actions)).toContain("buy");

    const button = box.querySelector("button")!;
    button.setAttribute("data-agent-action", "purchase");
    await tick();
    expect(rt.manifest().actions.buy).toBeUndefined();
    expect(rt.manifest().actions.purchase).toEqual({ description: "구매" });

    button.setAttribute("data-agent-desc", "바로 구매");
    await tick();
    expect(rt.manifest().actions.purchase).toEqual({ description: "바로 구매" });

    const select = document.querySelector("select")!;
    select.insertAdjacentHTML("beforeend", `<option value="m">m</option>`);
    await tick();
    expect(rt.manifest().actions.size_set!.input!.properties).toEqual({ value: { type: "string", enum: ["s", "m"] } });

    button.remove();
    await tick();
    expect(rt.manifest().actions.purchase).toBeUndefined();
  });
});
