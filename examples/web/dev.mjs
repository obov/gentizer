// mock agent 2개 + vite 를 함께 실행. Ctrl+C 로 모두 종료
import { spawn } from "node:child_process";

const procs = [
  ["node", ["mock/agent-server.mjs"]],
  ["node", ["mock/a2ui-server.mjs"]],
  ["npx", ["vite"]],
].map(([cmd, args]) => spawn(cmd, args, { stdio: "inherit" }));

const stop = () => {
  for (const p of procs) p.kill();
  process.exit();
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
for (const p of procs) p.on("exit", (code) => code && stop());
