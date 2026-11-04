import { describe, expect, test } from "vitest";
import type { CallRendererFunctionMessage } from "@a2ui/web_core/v1_0";
import { createA2uiBridge } from "../src/index.js";
import { loadSuite, makeRuntime, registerDecls, type ActionDecl, type ConfirmMode } from "../../core/test/conformance-helpers.js";

const SKIP: Record<string, string> = {};
const run = (id: string) => (SKIP[id] ? test.skip : test);

interface A2uiCase {
  name: string;
  actions: ActionDecl[];
  confirm?: ConfirmMode;
  catalogId: string;
  message: CallRendererFunctionMessage;
  expect: { value: unknown } | { errorCode: string; messagePrefix?: string };
}

describe("conformance a2ui", () => {
  for (const { id, c } of loadSuite<A2uiCase>("a2ui")) {
    run(id)(id, async () => {
      const { runtime } = makeRuntime(c.confirm);
      registerDecls(runtime, c.actions);
      const r = (await createA2uiBridge(runtime, { catalogId: c.catalogId }).handle(c.message)).rendererFunctionResponse;
      expect(r.functionCallId).toBe(c.message.callRendererFunction.functionCallId);
      if ("value" in c.expect) {
        expect(r.error).toBeUndefined();
        expect(r.value).toEqual(c.expect.value);
      } else {
        expect(r.error?.code).toBe(c.expect.errorCode);
        if (c.expect.messagePrefix) expect(r.error?.message.startsWith(c.expect.messagePrefix)).toBe(true);
      }
    });
  }
});
