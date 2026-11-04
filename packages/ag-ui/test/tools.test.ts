import { describe, expect, test } from "vitest";
import type { Message } from "@ag-ui/client";
import { createAgentRuntime } from "@gentizer/core";
import { runFrontendTools } from "../src/index.js";

// tools · context · runFrontendTools 규칙은 conformance/ag-ui (conformance.test.ts). 여기는 TS 고유 (비동기 순서)

const assistant = (calls: [id: string, name: string, args: string][]): Message => ({
  id: `a-${calls.map((c) => c[0]).join("-")}`,
  role: "assistant",
  toolCalls: calls.map(([id, name, args]) => ({ id, type: "function", function: { name, arguments: args } })),
});

describe("runFrontendTools TS 고유", () => {
  test("순서대로 하나씩 실행", async () => {
    const rt = createAgentRuntime();
    const log: string[] = [];
    rt.action("slow", { description: "느림" }, async () => {
      log.push("slow:start");
      await new Promise((r) => setTimeout(r, 10));
      log.push("slow:end");
    });
    rt.action("fast", { description: "빠름" }, () => void log.push("fast"));
    await runFrontendTools(rt, [assistant([["t1", "slow", "{}"], ["t2", "fast", "{}"]])]);
    expect(log).toEqual(["slow:start", "slow:end", "fast"]);
  });
});
