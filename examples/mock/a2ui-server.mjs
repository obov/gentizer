// mock A2UI v1.0 agent. 브라우저 ↔ 서버
//   POST /a2ui/catalog   앱이 등록한 액션의 catalog (toA2uiCatalog 결과)
//   GET  /a2ui/events    SSE. 서버 → 브라우저 callRendererFunction 메시지
//   POST /a2ui/chat      { text } → 판단해서 callRendererFunction 전송
//   POST /a2ui/response  렌더러 → 에이전트 메시지 (rendererFunctionResponse · action · error 등, 로그만)
import { createServer } from "node:http";
import { decide, HELP } from "./intent.mjs";

const PORT = Number(process.env.A2UI_PORT ?? 8781);
const clients = new Set();
let catalog = null;
let seq = 0;

const send = (msg) => {
  for (const res of clients) res.write(`data: ${JSON.stringify(msg)}\n\n`);
};
const json = (res, status, body) => res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body));

async function readJson(req) {
  let body = "";
  for await (const chunk of req) body += chunk;
  return JSON.parse(body || "{}");
}

createServer(async (req, res) => {
  const url = req.url ?? "";
  if (req.method === "GET" && url === "/a2ui/events") {
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
    res.write(": connected\n\n");
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }
  if (req.method === "POST" && url === "/a2ui/catalog") {
    catalog = await readJson(req);
    console.log(`[a2ui] catalog ${catalog.catalogId} · functions ${Object.keys(catalog.functions).join(",")}`);
    return json(res, 200, { ok: true });
  }
  if (req.method === "POST" && url === "/a2ui/chat") {
    const { text = "" } = await readJson(req);
    if (!catalog) return json(res, 409, { reply: "catalog 미수신" });
    const call = decide(text, Object.keys(catalog.functions));
    if (!call) return json(res, 200, { reply: `이해하지 못함. ${HELP}` });
    const message = {
      version: "1.0",
      callRendererFunction: {
        functionCallId: `fc-${++seq}`,
        callFunction: { "@call": call.name, catalogId: catalog.catalogId, args: call.args },
      },
    };
    send(message);
    console.log(`[a2ui] → ${JSON.stringify(message)}`);
    return json(res, 200, { reply: `${call.name} 호출 전송`, sent: message });
  }
  if (req.method === "POST" && url === "/a2ui/response") {
    console.log(`[a2ui] ← ${JSON.stringify(await readJson(req))}`);
    return json(res, 200, { ok: true });
  }
  res.writeHead(404).end();
}).listen(PORT, () => console.log(`[a2ui] mock A2UI agent http://localhost:${PORT}/a2ui`));
