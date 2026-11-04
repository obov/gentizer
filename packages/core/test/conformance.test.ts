import { describe, expect, test } from "vitest";
import {
  DuplicateNameError,
  InvalidManifestError,
  InvalidTriggerError,
  toA2uiCatalog,
  validateManifest,
  type ActionDef,
  type Manifest,
} from "../src/index.js";
import { behaviorRun, loadSuite, makeRuntime, schemaErrors, type Behavior, type ConfirmMode } from "./conformance-helpers.js";

/** 케이스 id → 사유. 미구현 skip 용 */
const SKIP: Record<string, string> = {};
const run = (id: string) => (SKIP[id] ? test.skip : test);

interface ValidateCase {
  name: string;
  manifest: unknown;
  expect: { ok: true } | { ok: false; errorPaths: string[] };
}

interface CatalogCase {
  name: string;
  manifest: Manifest;
  catalogId: string;
  catalog?: unknown;
  error?: "INVALID_MANIFEST";
}

describe("conformance 형식", () => {
  test("schema 위반 파일은 거부", () => {
    expect(schemaErrors({ suite: "validate", cases: [{ name: "x", manifest: {} }] })).not.toBeNull();
    expect(schemaErrors({ suite: "nope", cases: [] })).not.toBeNull();
  });
});

describe("conformance validate", () => {
  for (const { id, c } of loadSuite<ValidateCase>("validate")) {
    run(id)(id, () => {
      const r = validateManifest(c.manifest);
      if (c.expect.ok) {
        expect(r).toEqual({ ok: true });
      } else {
        expect(r.ok).toBe(false);
        const paths = r.ok ? [] : r.errors.map((e) => e.path);
        expect([...paths].sort()).toEqual([...c.expect.errorPaths].sort());
      }
    });
  }
});

describe("conformance catalog", () => {
  for (const { id, c } of loadSuite<CatalogCase>("catalog")) {
    run(id)(id, () => {
      if (c.error) {
        expect(() => toA2uiCatalog(c.manifest, { catalogId: c.catalogId })).toThrow(InvalidManifestError);
      } else {
        expect(toA2uiCatalog(c.manifest, { catalogId: c.catalogId })).toEqual(c.catalog);
      }
    });
  }
});

type Step =
  | { op: "register"; kind: "action" | "state" | "view"; name: string; def: ActionDef; behavior?: Behavior; value?: unknown; handle?: string; expectError?: "DUPLICATE_NAME" }
  | { op: "unregister"; handle: string }
  | { op: "invoke"; name: string; args?: unknown; expect: { ok: true; value: unknown } | { ok: false; code: string }; expectConfirm?: unknown }
  | { op: "manifest"; expect: Manifest; expectOrder?: Partial<Record<"actions" | "state" | "views", string[]>> }
  | { op: "readState"; name: string; expect: unknown }
  | { op: "listen"; listener: string; throws?: true; handle?: string }
  | { op: "trigger"; name: string; payload?: unknown; expectEvents?: { listener: string; name: string; payload: unknown }[]; expectError?: "INVALID_TRIGGER" };

interface RuntimeCase {
  name: string;
  confirm?: ConfirmMode;
  steps: Step[];
}

describe("conformance runtime", () => {
  for (const { id, c } of loadSuite<RuntimeCase>("runtime")) {
    run(id)(id, async () => {
      const { runtime: rt, calls } = makeRuntime(c.confirm);
      const handles = new Map<string, () => void>();
      const events: { listener: string; name: string; payload: unknown }[] = [];
      for (const [i, step] of c.steps.entries()) {
        const at = `step ${i} ${step.op}`;
        switch (step.op) {
          case "register": {
            const doRegister = () => {
              if (step.kind === "action") return rt.action(step.name, step.def, behaviorRun(step.behavior ?? { returns: null }));
              if (step.kind === "state") return rt.state(step.name, step.def, () => structuredClone(step.value));
              return rt.view(step.name, step.def);
            };
            if (step.expectError) {
              expect(doRegister, at).toThrow(DuplicateNameError);
            } else {
              const off = doRegister();
              if (step.handle) handles.set(step.handle, off);
            }
            break;
          }
          case "unregister":
            handles.get(step.handle)!();
            break;
          case "invoke": {
            const before = calls.length;
            const r = "args" in step ? await rt.invoke(step.name, step.args) : await rt.invoke(step.name);
            if (step.expect.ok) expect(r, at).toEqual({ ok: true, value: step.expect.value });
            else expect(r.ok ? null : r.error.code, at).toBe(step.expect.code);
            if ("expectConfirm" in step) {
              const made = calls.slice(before);
              expect(made, at).toEqual(step.expectConfirm === null ? [] : [step.expectConfirm]);
            }
            break;
          }
          case "manifest": {
            const m = rt.manifest();
            expect(m, at).toEqual(step.expect);
            for (const [section, order] of Object.entries(step.expectOrder ?? {})) {
              expect(Object.keys(m[section as keyof typeof step.expectOrder]), at).toEqual(order);
            }
            break;
          }
          case "readState":
            expect(rt.readState(step.name) ?? null, at).toEqual(step.expect);
            break;
          case "listen": {
            const { listener, throws } = step;
            const off = rt.onTrigger((e) => {
              events.push({ listener, ...e });
              if (throws) throw new Error("수신기 실패");
            });
            if (step.handle) handles.set(step.handle, off);
            break;
          }
          case "trigger": {
            events.length = 0;
            const fire = () => ("payload" in step ? rt.trigger(step.name, step.payload) : rt.trigger(step.name));
            if (step.expectError) {
              expect(fire, at).toThrow(InvalidTriggerError);
              expect(events, at).toEqual([]);
            } else {
              fire();
              expect(events, at).toEqual(step.expectEvents);
            }
            break;
          }
        }
      }
    });
  }
});
