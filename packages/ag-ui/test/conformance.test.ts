import { describe, expect, test } from "vitest";
import type { Message } from "@ag-ui/client";
import { toAgUiContext, toAgUiTools, runFrontendTools } from "../src/index.js";
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
  confirm?: ConfirmMode;
  op: "tools" | "context" | "runFrontendTools";
  messages?: Message[];
  expect: unknown[];
}

describe("conformance ag-ui", () => {
  for (const { id, c } of loadSuite<AgUiCase>("ag-ui")) {
    run(id)(id, async () => {
      const { runtime } = makeRuntime(c.confirm);
      registerDecls(runtime, c.actions, c.states);
      if (c.op === "tools") {
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
