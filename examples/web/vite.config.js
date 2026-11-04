import { defineConfig } from "vite";

const AGENT = `http://localhost:${process.env.AGENT_PORT ?? 8782}`;
const A2UI = `http://localhost:${process.env.A2UI_PORT ?? 8781}`;

export default defineConfig({
  server: { port: 5173, proxy: { "/agent": AGENT, "/a2ui": A2UI } },
});
