import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@gentizer/core": fileURLToPath(new URL("../core/src/index.ts", import.meta.url)),
      "@gentizer/dom": fileURLToPath(new URL("../dom/src/index.ts", import.meta.url)),
    },
  },
  test: { environment: "jsdom" },
});
