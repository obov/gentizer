// mock AG-UI agent (:8782) · mock A2UI agent (:8781) 를 함께 실행. 모든 예시가 공유
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const dir = fileURLToPath(new URL(".", import.meta.url));
export function startMocks() {
  return ["agent-server.mjs", "a2ui-server.mjs"].map((f) => spawn("node", [dir + f], { stdio: "inherit" }));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const procs = startMocks();
  const stop = () => {
    for (const p of procs) p.kill();
    process.exit();
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}
