// mock 에이전트 2개 (examples/mock) + vite 를 함께 실행. Ctrl+C 로 모두 종료
import { spawn } from "node:child_process";
import { startMocks } from "../mock/start.mjs";

const procs = [...startMocks(), spawn("npx", ["vite"], { stdio: "inherit" })];

const stop = () => {
  for (const p of procs) p.kill();
  process.exit();
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
for (const p of procs) p.on("exit", (code) => code && stop());
