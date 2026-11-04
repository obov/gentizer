import { afterEach, describe, expect, test } from "vitest";
import { act, cleanup, render, waitFor } from "@testing-library/react";
import { useState } from "react";
import { createAgentRuntime, type AgentRuntime } from "@gentizer/core";
import { GentizerProvider, useAgentState } from "@gentizer/react";
import { basicCatalog } from "@a2ui/web_core/v1_0";
import { A2uiSurfaceView, useA2uiSurfaceHost, useA2uiSurfaceIds, type A2uiSurfaceHost, type RendererMessage } from "../src/index.js";

afterEach(cleanup);

const create = (surfaceId: string, sendDataModel = false) => ({
  version: "1.0",
  createSurface: { surfaceId, catalogId: basicCatalog.id, sendDataModel },
});
const components = (surfaceId: string) => ({
  version: "1.0",
  updateComponents: {
    surfaceId,
    components: [
      { id: "root", component: "Column", children: ["t", "b"] },
      { id: "t", component: "Text", text: "안녕하세요" },
      { id: "b", component: "Button", child: "bt", action: { event: { name: "buy", context: { id: 2 } } } },
      { id: "bt", component: "Text", text: "구매" },
    ],
  },
});

function harness(rt: AgentRuntime, sent: RendererMessage[], out: { host?: A2uiSurfaceHost | null; renders?: number }) {
  return function App({ label }: { label: string }) {
    useAgentState("label", { description: "라벨" }, label);
    const host = useA2uiSurfaceHost({ catalogId: "cat", send: (m) => sent.push(m) });
    const ids = useA2uiSurfaceIds(host);
    out.host = host;
    out.renders = (out.renders ?? 0) + 1;
    return (
      <div>
        <span data-testid="ids">{ids.join(",")}</span>
        {ids.map((id) => (
          <A2uiSurfaceView key={id} host={host} surfaceId={id} />
        ))}
        <A2uiSurfaceView host={host} surfaceId="missing" fallback={<i>없음</i>} />
      </div>
    );
  };
}

describe("@gentizer/react-a2ui", () => {
  test("host 생성 · surface 렌더 · 버튼 action send · 상태 동기화 · 언마운트 dispose", async () => {
    const rt = createAgentRuntime();
    const sent: RendererMessage[] = [];
    const out: { host?: A2uiSurfaceHost | null } = {};
    const App = harness(rt, sent, out);
    const r = render(
      <GentizerProvider runtime={rt}>
        <App label="a" />
      </GentizerProvider>,
    );
    await waitFor(() => expect(out.host).toBeTruthy());
    const host = out.host!;
    await act(async () => {
      await host.process(create("s1", true));
      await host.process(components("s1"));
    });
    expect(r.getByTestId("ids").textContent).toBe("s1");
    await waitFor(() => expect(r.container.textContent).toContain("안녕하세요"));
    expect(r.container.textContent).toContain("없음");

    const button = r.container.querySelector("a2ui-basic-button button") as HTMLButtonElement;
    await act(async () => {
      button.click();
      await new Promise((res) => setTimeout(res, 10));
    });
    expect(sent.at(-1)).toMatchObject({ version: "1.0", action: { name: "buy", surfaceId: "s1", context: { id: 2 } } });

    expect(host.dataModel().surfaces).toEqual({ s1: { gentizer: { state: { label: "a" }, views: {} } } });
    r.rerender(
      <GentizerProvider runtime={rt}>
        <App label="b" />
      </GentizerProvider>,
    );
    expect(host.dataModel().surfaces).toEqual({ s1: { gentizer: { state: { label: "b" }, views: {} } } });

    const pending = host.callAgentFunction("s1", { call: "lookup" });
    r.unmount();
    await expect(pending).rejects.toThrow();
  });

  test("send 는 최신 렌더 함수", async () => {
    const rt = createAgentRuntime();
    const got: string[] = [];
    let hostRef: A2uiSurfaceHost | null = null;
    function App() {
      const [tag, setTag] = useState("first");
      hostRef = useA2uiSurfaceHost({ catalogId: "cat", send: () => got.push(tag) });
      return <button onClick={() => setTag("second")}>x</button>;
    }
    const r = render(
      <GentizerProvider runtime={rt}>
        <App />
      </GentizerProvider>,
    );
    await waitFor(() => expect(hostRef).toBeTruthy());
    act(() => rt.trigger("a"));
    act(() => r.getByText("x").click());
    act(() => rt.trigger("b"));
    expect(got).toEqual(["first", "second"]);
  });
});
