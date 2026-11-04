import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const src = (p: string) => fileURLToPath(new URL(p, import.meta.url));
export default defineConfig({
  resolve: {
    alias: {
      "@gentizer/core": src("../core/src/index.ts"),
      "@gentizer/a2ui": src("../a2ui/src/index.ts"),
      "@gentizer/react": src("../react/src/index.tsx"),
    },
  },
  test: { environment: "jsdom" },
});
