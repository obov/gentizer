import { describe, expect, test } from "vitest";
import type { Message } from "@ag-ui/client";
import { toAgUiContext, toAgUiTools, toAgUiTriggerMessage, runFrontendTools } from "../src/index.js";
import {
  loadSuite,
  makeRuntime,
  registerDecls,
  type ActionDecl,
  type ConfirmMode,
  type StateDecl,
} from "../../core/test/conformance-helpers.js";

const SKIP: Record<string, string> = {};
const run = (id: string) => (SKIP[id] ? test.skip : test);

interface AgUiCase {
  name: string;
  actions: ActionDecl[];
  states?: StateDecl[];
  views?: { name: string; def: { description: string } }[];
  confirm?: ConfirmMode;
  op: "tools" | "context" | "runFrontendTools" | "triggerMessage";
  messages?: Message[];
  event?: { name: string; payload: Record<string, unknown> };
  expect: unknown[];
}

describe("conformance ag-ui", () => {
  for (const { id, c } of loadSuite<AgUiCase>("ag-ui")) {
    run(id)(id, async () => {
      const { runtime } = makeRuntime(c.confirm);
      registerDecls(runtime, c.actions, c.states);
      for (const v of c.views ?? []) runtime.view(v.name, v.def);
      if (c.op === "triggerMessage") {
        const m = toAgUiTriggerMessage(c.event!);
        expect(m.id.startsWith("gentizer-trigger-")).toBe(true);
        expect([{ role: m.role, content: JSON.parse(m.content as string) }]).toEqual(c.expect);
      } else if (c.op === "tools") {
        expect(toAgUiTools(runtime.manifest())).toEqual(c.expect);
      } else if (c.op === "context") {
        expect(toAgUiContext(runtime).map((x) => ({ ...x, value: JSON.parse(x.value) }))).toEqual(c.expect);
      } else {
        const out = await runFrontendTools(runtime, c.messages ?? []);
        const actual = out.map((m) => {
          expect(m.id).toBe(`gentizer-${m.toolCallId}`);
          expect(m.role).toBe("tool");
          const content = JSON.parse(m.content as string);
          if (m.error === undefined) return { toolCallId: m.toolCallId, content };
          const code = content.error.code as string;
          expect(m.error.startsWith(`${code}: `)).toBe(true);
          return { toolCallId: m.toolCallId, content: { error: { code } }, errorCode: code };
        });
        expect(actual).toEqual(c.expect);
      }
    });
  }
});
