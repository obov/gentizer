import { StrictMode, useRef, useState } from "react";
import { renderToString } from "react-dom/server";
import { act, render, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup } from "@testing-library/react";
import { createAgentRuntime, type AgentRuntime } from "@gentizer/core";
import {
  GentizerProvider,
  useAgentAction,
  useAgentAttributes,
  useAgentManifest,
  useAgentRuntime,
  useAgentState,
  useAgentView,
} from "../src/index.js";

afterEach(cleanup);

const wrap = (rt: AgentRuntime) => ({ children }: { children?: React.ReactNode }) => (
  <GentizerProvider runtime={rt}>{children}</GentizerProvider>
);

function Cart({ label, onAdd }: { label: string; onAdd: (a: Record<string, unknown>) => unknown }) {
  useAgentAction("cart_add", { description: "담기" }, onAdd);
  useAgentState("cart_label", { description: "라벨" }, label);
  useAgentView("cart", { description: "장바구니 영역" });
  return null;
}

describe("등록 · 해제", () => {
  test("마운트 등록 · 언마운트 해제", () => {
    const rt = createAgentRuntime();
    const { unmount } = render(<Cart label="a" onAdd={() => {}} />, { wrapper: wrap(rt) });
    const m = rt.manifest();
    expect(Object.keys(m.actions)).toEqual(["cart_add"]);
    expect(Object.keys(m.state)).toEqual(["cart_label"]);
    expect(Object.keys(m.views)).toEqual(["cart"]);
    unmount();
    expect(rt.manifest()).toMatchObject({ actions: {}, state: {}, views: {} });
  });

  test("최신 run · value 사용, 재등록 없음", async () => {
    const rt = createAgentRuntime();
    const listener = vi.fn();
    const first = vi.fn(() => 1);
    const second = vi.fn(() => 2);
    const { rerender } = render(<Cart label="a" onAdd={first} />, { wrapper: wrap(rt) });
    rt.subscribe(listener);
    rerender(<Cart label="b" onAdd={second} />);
    expect(listener).not.toHaveBeenCalled();
    expect(rt.readState("cart_label")).toBe("b");
    expect(await rt.invoke("cart_add", { n: 1 })).toEqual({ ok: true, value: 2 });
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledWith({ n: 1 });
  });

  test("name 변경 시 재등록, def 내용 변경 시 재등록", () => {
    const rt = createAgentRuntime();
    function A({ name, desc }: { name: string; desc: string }) {
      useAgentAction(name, { description: desc }, () => {});
      return null;
    }
    const { rerender } = render(<A name="a_x" desc="1" />, { wrapper: wrap(rt) });
    rerender(<A name="a_y" desc="1" />);
    expect(Object.keys(rt.manifest().actions)).toEqual(["a_y"]);
    rerender(<A name="a_y" desc="2" />);
    expect(rt.manifest().actions).toEqual({ "a_y": { description: "2" } });
  });

  test("StrictMode 이중 마운트에서 오류 없음", () => {
    const rt = createAgentRuntime();
    expect(() =>
      render(
        <StrictMode>
          <GentizerProvider runtime={rt}>
            <Cart label="a" onAdd={() => {}} />
          </GentizerProvider>
        </StrictMode>,
      ),
    ).not.toThrow();
    expect(Object.keys(rt.manifest().actions)).toEqual(["cart_add"]);
  });

  test("Provider 밖 Error", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() => renderHook(() => useAgentRuntime())).toThrow(/GentizerProvider/);
    vi.restoreAllMocks();
  });

  test("renderToString 중 등록 없음", () => {
    const rt = createAgentRuntime();
    renderToString(
      <GentizerProvider runtime={rt}>
        <Cart label="a" onAdd={() => {}} />
      </GentizerProvider>,
    );
    expect(rt.manifest().actions).toEqual({});
  });
});

describe("useAgentManifest", () => {
  test("등록 · 해제 시 갱신, 변경 없으면 같은 object", () => {
    const rt = createAgentRuntime();
    const seen: string[][] = [];
    let setShow: (v: boolean) => void = () => {};
    function Viewer() {
      const m = useAgentManifest();
      seen.push(Object.keys(m.actions));
      return null;
    }
    function App() {
      const [show, set] = useState(false);
      setShow = set;
      return (
        <>
          <Viewer />
          {show && <Cart label="a" onAdd={() => {}} />}
        </>
      );
    }
    render(<App />, { wrapper: wrap(rt) });
    act(() => setShow(true));
    expect(seen.at(-1)).toEqual(["cart_add"]);
    act(() => setShow(false));
    expect(seen.at(-1)).toEqual([]);

    const { result, rerender } = renderHook(() => useAgentManifest(), { wrapper: wrap(rt) });
    const before = result.current;
    rerender();
    expect(result.current).toBe(before);
  });
});

describe("useAgentAttributes", () => {
  test("마운트 동안 document.body 의 속성 바인딩, 언마운트 해제", async () => {
    const rt = createAgentRuntime();
    function App() {
      useAgentAttributes();
      return <button data-agent-action="buy" data-agent-desc="구매" onClick={() => clicks++} />;
    }
    let clicks = 0;
    const r = render(<App />, { wrapper: wrap(rt) });
    expect(Object.keys(rt.manifest().actions)).toEqual(["buy"]);
    await act(async () => {
      await rt.invoke("buy");
    });
    expect(clicks).toBe(1);
    r.unmount();
    expect(rt.manifest().actions).toEqual({});
  });

  test("rootRef 범위만", () => {
    const rt = createAgentRuntime();
    function App() {
      const ref = useRef<HTMLDivElement>(null);
      useAgentAttributes(ref);
      return (
        <>
          <div ref={ref}>
            <button data-agent-action="inside" data-agent-desc="안" />
          </div>
          <button data-agent-action="outside" data-agent-desc="밖" />
        </>
      );
    }
    render(<App />, { wrapper: wrap(rt) });
    expect(Object.keys(rt.manifest().actions)).toEqual(["inside"]);
  });
});
