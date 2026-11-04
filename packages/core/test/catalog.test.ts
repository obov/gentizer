import { describe, expect, test } from "vitest";
import { FunctionDefinitionSchema } from "@a2ui/web_core/v1_0";
import { createManifestBuilder, InvalidManifestError, toA2uiCatalog, type Manifest } from "../src/index.js";

const manifest = createManifestBuilder()
  .action("cart.add", { description: "장바구니 담기" })
  .action("filter.set", {
    description: "목록 필터 변경",
    input: { type: "object", properties: { category: { type: "string" } }, required: ["category"] },
    confirm: true,
    returns: "boolean",
  })
  .state("cart", { description: "장바구니" })
  .view("cart", { description: "장바구니 영역" })
  .build();

const catalog = toA2uiCatalog(manifest, { catalogId: "https://example.com/shop/catalog.json" });

describe("toA2uiCatalog", () => {
  test("catalog 머리", () => {
    expect(catalog.protocolVersion).toBe("1.0");
    expect(catalog.catalogId).toBe("https://example.com/shop/catalog.json");
    expect(Object.keys(catalog.functions)).toEqual(["cart.add", "filter.set"]);
  });

  test("input 생략 · returns 생략 · confirm 생략", () => {
    expect(catalog.functions["cart.add"]).toEqual({
      type: "object",
      description: "장바구니 담기",
      returnType: "void",
      allowedCallers: "agentOnly",
      properties: { "@call": { const: "cart.add" }, args: { type: "object", properties: {} } },
      required: ["@call"],
    });
  });

  test("input required → args required", () => {
    const f = catalog.functions["filter.set"]!;
    expect(f.required).toEqual(["@call", "args"]);
    expect(f.returnType).toBe("boolean");
    expect(f.properties.args).toEqual(manifest.actions["filter.set"]!.input);
  });

  test("input 을 복사 (manifest 변경이 catalog 에 번지지 않음)", () => {
    expect(catalog.functions["filter.set"]!.properties.args).not.toBe(manifest.actions["filter.set"]!.input);
  });

  test("confirm → metadata.extensions.gentizer.confirm, function 정의에는 표시 없음", () => {
    expect(catalog.metadata).toEqual({ extensions: { gentizer: { confirm: ["filter.set"] } } });
    expect(catalog.functions["filter.set"]).not.toHaveProperty("requiresUserActivation");
  });

  test("confirm 액션 없으면 metadata 생략", () => {
    const m = createManifestBuilder().action("a", { description: "x", confirm: false }).build();
    expect(toA2uiCatalog(m, { catalogId: "x" })).not.toHaveProperty("metadata");
  });

  test("extension 키가 A2UI Extensions identifier 규칙 만족", () => {
    for (const key of Object.keys(catalog.metadata!.extensions)) {
      expect(key).toMatch(/^[\p{XID_Start}_][\p{XID_Continue}]*$/u);
      expect(key.startsWith("a2ui_")).toBe(false);
    }
  });

  test("state · views 는 catalog 에 없음", () => {
    expect(catalog).not.toHaveProperty("state");
    expect(catalog).not.toHaveProperty("views");
  });

  test.each(Object.keys(catalog.functions))("@a2ui/web_core v1_0 FunctionDefinitionSchema 통과: %s", (name) => {
    const parsed = FunctionDefinitionSchema.safeParse(catalog.functions[name]);
    expect(parsed.error).toBeUndefined();
    expect(parsed.data).toMatchObject({ allowedCallers: "agentOnly" });
  });

  test("잘못된 manifest 는 InvalidManifestError", () => {
    const bad = { ...manifest, actions: { Bad: { description: "x" } } } as Manifest;
    expect(() => toA2uiCatalog(bad, { catalogId: "x" })).toThrow(InvalidManifestError);
  });
});
