import { expect, test } from "vitest";
import * as core from "../src/index.js";

test("module loads", () => {
  expect(core).toBeTypeOf("object");
});
