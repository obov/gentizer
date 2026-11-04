import { describe, expect, test } from "vitest";
import { Catalog, type FunctionImplementation } from "@a2ui/web_core";
import { FunctionDefinitionSchema, RpcHandler } from "@a2ui/web_core/v1_0";
import { createManifestBuilder, toA2uiCatalog } from "../src/index.js";

const manifest = createManifestBuilder()
  .action("cart_add", { description: "장바구니 담기" })
  .action("filter_set", {
    description: "목록 필터 변경",
    input: { type: "object", properties: { category: { type: "string" } }, required: ["category"] },
    confirm: true,
    returns: "boolean",
  })
  .state("cart", { description: "장바구니" })
  .view("cart", { description: "장바구니 영역" })
  .build();

const catalog = toA2uiCatalog(manifest, { catalogId: "https://example.com/shop/catalog.json" });

// 변환 규칙은 conformance/catalog (conformance.test.ts). 여기는 TS 고유 (객체 복사 · web_core 파싱 · 실행)
describe("toA2uiCatalog TS 고유", () => {
  test("input 을 복사 (manifest 변경이 catalog 에 번지지 않음)", () => {
    expect(catalog.functions["filter_set"]!.properties.args).not.toBe(manifest.actions["filter_set"]!.input);
  });

  test.each(Object.keys(catalog.functions))("@a2ui/web_core v1_0 FunctionDefinitionSchema 통과: %s", (name) => {
    const parsed = FunctionDefinitionSchema.safeParse(catalog.functions[name]);
    expect(parsed.error).toBeUndefined();
    expect(parsed.data).toMatchObject({ allowedCallers: "agentOnly" });
  });
});

describe("web_core 실행", () => {
  const catalogId = "https://example.com/shop/catalog.json";
  // Catalog.fromJson 이 생성 catalog 을 파싱하고, 실행 함수만 붙여 RpcHandler 로 호출
  const parsed = Catalog.fromJson(catalog as unknown as Record<string, unknown>);
  const impls = [...parsed.functions.values()].map(
    (f) => ({ ...f, execute: (args: Record<string, unknown>) => `${f.name}:${JSON.stringify(args)}` }) as FunctionImplementation,
  );
  const handler = new RpcHandler({ catalogs: [new Catalog(catalogId, "1.0", [], impls)] });
  const call = (name: string, args: Record<string, unknown>) =>
    handler.handleCallRendererFunction({
      version: "1.0",
      callRendererFunction: { functionCallId: "c1", callFunction: { "@call": name, catalogId, args } },
    });

  test("allowedCallers agentOnly 로 파싱", () => {
    expect([...parsed.functions.values()].map((f) => [f.name, f.allowedCallers])).toEqual([
      ["cart_add", "agentOnly"],
      ["filter_set", "agentOnly"],
    ]);
  });

  test("callRendererFunction 실행 결과", async () => {
    const r = await call("filter_set", { category: "shoes" });
    expect(r.rendererFunctionResponse).toEqual({ functionCallId: "c1", value: 'filter_set:{"category":"shoes"}' });
  });

  test("input.required 누락은 INVALID_FUNCTION_CALL", async () => {
    const r = await call("filter_set", {});
    expect(r.rendererFunctionResponse).toMatchObject({ error: { code: "INVALID_FUNCTION_CALL" } });
  });
});
