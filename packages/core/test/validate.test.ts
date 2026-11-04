import { describe, expect, test } from "vitest";
import { createManifestBuilder, DuplicateNameError, validateManifest, type Manifest } from "../src/index.js";

const valid: Manifest = {
  version: "gentizer/0.1",
  actions: {
    "cart_add": { description: "장바구니 담기" },
    "filter_set": {
      description: "목록 필터 변경",
      input: { type: "object", properties: { category: { type: "string" } }, required: ["category"] },
      confirm: true,
      returns: "boolean",
    },
  },
  state: { cart: { description: "장바구니", schema: { type: "array" } } },
  views: { cart: { description: "장바구니 영역" } },
};

const paths = (m: unknown) => {
  const r = validateManifest(m);
  return r.ok ? [] : r.errors.map((e) => e.path);
};

describe("validateManifest", () => {
  test("정상 manifest", () => {
    expect(validateManifest(valid)).toEqual({ ok: true });
  });

  test("object 아님", () => {
    expect(paths(null)).toEqual([""]);
  });

  test("version 불일치", () => {
    expect(paths({ ...valid, version: "gentizer/9" })).toEqual(["version"]);
  });

  test("구역 누락", () => {
    const { views: _, ...rest } = valid;
    expect(paths(rest)).toEqual(["views"]);
  });

  test.each(["Cart_add", "cart.add", "cart-add", "1cart", "_cart", "cart add", "a".repeat(65)])("이름 규칙 위반: %s", (name) => {
    expect(paths({ ...valid, actions: { [name]: { description: "x" } } })).toEqual([`actions.${name}`]);
  });

  test.each(["cart", "cart_add", "list_v2", "a".repeat(64)])("이름 규칙 통과: %s", (name) => {
    expect(paths({ ...valid, actions: { [name]: { description: "x" } } })).toEqual([]);
  });

  test("description 빈 문자열", () => {
    expect(paths({ ...valid, views: { cart: { description: " " } } })).toEqual(["views.cart.description"]);
  });

  test("input 최상위 object 아님", () => {
    expect(paths({ ...valid, actions: { a: { description: "x", input: { type: "string" } } } })).toEqual([
      "actions.a.input",
    ]);
  });

  test("returns 허용값 밖", () => {
    expect(paths({ ...valid, actions: { a: { description: "x", returns: "validationResult" } } })).toEqual([
      "actions.a.returns",
    ]);
  });

  test("confirm boolean 아님", () => {
    expect(paths({ ...valid, actions: { a: { description: "x", confirm: "yes" } } })).toEqual(["actions.a.confirm"]);
  });

  test("state.schema object 아님", () => {
    expect(paths({ ...valid, state: { s: { description: "x", schema: "array" } } })).toEqual(["state.s.schema"]);
  });

  test("다중 오류 전부 수집", () => {
    expect(
      paths({
        version: "x",
        actions: { Bad: { description: "" }, ok: { description: "x", input: [], returns: 1 } },
        state: {},
        views: 3,
      }),
    ).toEqual(["version", "actions.Bad", "actions.Bad.description", "actions.ok.input", "actions.ok.returns", "views"]);
  });
});

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
