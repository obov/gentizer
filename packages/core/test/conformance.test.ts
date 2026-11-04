import { describe, expect, test } from "vitest";
import { InvalidManifestError, toA2uiCatalog, validateManifest, type Manifest } from "../src/index.js";
import { loadSuite, schemaErrors } from "./conformance-helpers.js";

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
