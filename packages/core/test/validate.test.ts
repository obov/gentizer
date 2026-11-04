import { describe, expect, test } from "vitest";
import { createManifestBuilder, DuplicateNameError, validateManifest } from "../src/index.js";

// validateManifest 규칙은 conformance/validate (conformance.test.ts). 여기는 TS 고유 builder 만

describe("createManifestBuilder", () => {
  test("등록 결과가 검증 통과", () => {
    const m = createManifestBuilder()
      .action("cart_add", { description: "담기" })
      .state("cart", { description: "장바구니" })
      .view("cart", { description: "장바구니 영역" })
      .build();
    expect(validateManifest(m)).toEqual({ ok: true });
  });

  test("같은 구역 중복은 오류", () => {
    const b = createManifestBuilder().action("cart_add", { description: "담기" });
    expect(() => b.action("cart_add", { description: "또" })).toThrow(DuplicateNameError);
  });

  test("다른 구역 같은 이름은 허용", () => {
    expect(() => createManifestBuilder().state("cart", { description: "a" }).view("cart", { description: "b" })).not.toThrow();
  });
});
