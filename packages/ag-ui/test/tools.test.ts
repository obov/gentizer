import { describe, expect, test, vi } from "vitest";
import type { Message } from "@ag-ui/client";
import { createAgentRuntime } from "@gentizer/core";
import { runFrontendTools, toAgUiContext, toAgUiTools } from "../src/index.js";

const filterInput = { type: "object" as const, properties: { category: { type: "string" } }, required: ["category"] };

const assistant = (calls: [id: string, name: string, args: string][]): Message => ({
  id: `a-${calls.map((c) => c[0]).join("-")}`,
  role: "assistant",
  toolCalls: calls.map(([id, name, args]) => ({ id, type: "function", function: { name, arguments: args } })),
});

describe("toAgUiTools · toAgUiContext", () => {
  test("액션 → tool, input 생략 시 빈 object", () => {
    const rt = createAgentRuntime();
    rt.action("cart_add", { description: "담기" }, () => {});
    rt.action("filter_set", { description: "필터", input: filterInput }, () => {});
    expect(toAgUiTools(rt.manifest())).toEqual([
      { name: "cart_add", description: "담기", parameters: { type: "object", properties: {} } },
      { name: "filter_set", description: "필터", parameters: filterInput },
    ]);
  });

  test("상태 → context, 값 JSON · 미정의 null", () => {
    const rt = createAgentRuntime();
    rt.state("cart", { description: "장바구니" }, () => [{ id: 1 }]);
    rt.state("empty", { description: "없음" }, () => undefined);
    expect(toAgUiContext(rt)).toEqual([
      { description: "cart: 장바구니", value: '[{"id":1}]' },
      { description: "empty: 없음", value: "null" },
    ]);
  });
});

describe("runFrontendTools", () => {
  test("응답 있는 call · 미등록 이름 무시", async () => {
    const rt = createAgentRuntime();
    const run = vi.fn(() => "ok");
    rt.action("cart_add", { description: "담기" }, run);
    const messages: Message[] = [
      assistant([["t1", "cart_add", "{}"], ["t2", "backend_search", "{}"], ["t3", "cart_add", "{}"]]),
      { id: "r1", role: "tool", toolCallId: "t1", content: "done" },
    ];
    const out = await runFrontendTools(rt, messages);
    expect(out.map((m) => m.toolCallId)).toEqual(["t3"]);
    expect(run).toHaveBeenCalledTimes(1);
  });

  test("성공 content · 실패 content 와 error", async () => {
    const rt = createAgentRuntime();
    rt.action("filter_set", { description: "필터", input: filterInput, returns: "string" }, (a) => `set ${a.category}`);
    const out = await runFrontendTools(rt, [
      assistant([["t1", "filter_set", '{"category":"shoes"}'], ["t2", "filter_set", "{}"]]),
    ]);
    expect(out[0]).toEqual({ id: "gentizer-t1", role: "tool", toolCallId: "t1", content: '"set shoes"' });
    expect(out[1]).toMatchObject({ toolCallId: "t2", error: expect.stringMatching(/^INVALID_ARGS: /) });
    expect(JSON.parse(out[1]!.content as string)).toMatchObject({ error: { code: "INVALID_ARGS" } });
  });

  test("arguments 파싱 실패 · object 아님은 실행 없이 INVALID_ARGS, 빈 문자열은 {}", async () => {
    const rt = createAgentRuntime();
    const run = vi.fn();
    rt.action("cart_add", { description: "담기" }, run);
    const out = await runFrontendTools(rt, [assistant([["t1", "cart_add", "{oops"], ["t2", "cart_add", "[1]"], ["t3", "cart_add", ""]])]);
    expect(out.map((m) => m.error?.split(":")[0])).toEqual(["INVALID_ARGS", "INVALID_ARGS", undefined]);
    expect(run).toHaveBeenCalledTimes(1);
    expect(run).toHaveBeenCalledWith({});
  });

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
