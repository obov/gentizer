import { describe, expect, test, vi } from "vitest";
import { renderToString } from "react-dom/server";
import { createAgentRuntime } from "@gentizer/core";
import { GentizerProvider } from "@gentizer/react";
import { A2uiSurfaceView, useA2uiSurfaceHost } from "../src/index.js";

const loaded = vi.hoisted(() => ({ count: 0 }));
vi.mock("@a2ui/react/v0_9", () => {
  loaded.count++;
  return { A2uiSurface: () => null };
});

describe("서버 렌더", () => {
  test("fallback 만 내고 @a2ui/react 를 불러오지 않는다, host 는 null", () => {
    let seen: unknown = "unset";
    function App() {
      const host = useA2uiSurfaceHost({ catalogId: "cat", send: () => {} });
      seen = host;
      return <A2uiSurfaceView host={host} surfaceId="s1" fallback={<p>불러오는 중</p>} />;
    }
    const html = renderToString(
      <GentizerProvider runtime={createAgentRuntime()}>
        <App />
      </GentizerProvider>,
    );
    expect(html).toBe("<p>불러오는 중</p>");
    expect(seen).toBeNull();
    expect(loaded.count).toBe(0);
  });
});
