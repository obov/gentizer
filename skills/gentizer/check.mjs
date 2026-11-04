// skills/gentizer 검사 (specs/skill.md '검사'). npm run build 뒤 실행: node skills/gentizer/check.mjs
// 1 frontmatter  2 references 링크  3 코드 블록의 API 이름이 실제로 있는지 (TS = dist export, Swift = swift/Sources public)
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = fileURLToPath(new URL("../../", import.meta.url));
const errors = [];
const fail = (m) => errors.push(m);

// 1 frontmatter
const skill = readFileSync(`${here}SKILL.md`, "utf8");
const fm = skill.match(/^---\n([\s\S]*?)\n---\n/);
if (!fm) fail("SKILL.md frontmatter 없음");
else {
  const name = fm[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
  const description = fm[1].match(/^description:\s*(.+)$/m)?.[1]?.trim() ?? "";
  if (name !== "gentizer") fail(`frontmatter name = ${name} (gentizer 여야 함)`);
  if (!description) fail("frontmatter description 없음");
  if (description.length > 1024) fail(`description ${description.length}자 (1024 이하)`);
}

// 2 references 링크
const refs = readdirSync(`${here}references`).filter((f) => f.endsWith(".md"));
for (const [, target] of skill.matchAll(/\]\((references\/[^)]+)\)/g)) {
  if (!refs.includes(target.replace("references/", ""))) fail(`SKILL.md 링크 대상 없음: ${target}`);
}

// 3 API 이름
const docs = [["SKILL.md", skill], ...refs.map((f) => [`references/${f}`, readFileSync(`${here}references/${f}`, "utf8")])];
const blocks = (text, langs) =>
  [...text.matchAll(/```(\w+)\n([\s\S]*?)```/g)].filter(([, lang]) => langs.includes(lang)).map(([, , code]) => code);
const inline = (text) => [...text.matchAll(/`([^`\n]+)`/g)].map(([, c]) => c);

// TS: import { a, b } from "@gentizer/<pkg>" 의 이름 → packages/<pkg>/dist export
const exportsOf = new Map();
async function tsExports(pkg) {
  if (!exportsOf.has(pkg)) {
    const url = pathToFileURL(`${root}packages/${pkg}/dist/index.js`).href;
    exportsOf.set(pkg, await import(url).then((m) => new Set(Object.keys(m)), () => null));
  }
  return exportsOf.get(pkg);
}
for (const [file, text] of docs) {
  for (const code of blocks(text, ["js", "ts", "tsx", "jsx"])) {
    for (const [, names, pkg] of code.matchAll(/import\s*\{([^}]+)\}\s*from\s*"@gentizer\/([\w-]+)"/g)) {
      const exported = await tsExports(pkg);
      if (!exported) {
        fail(`${file}: @gentizer/${pkg} dist 없음 (npm run build 먼저)`);
        continue;
      }
      for (const raw of names.split(",")) {
        const name = raw.trim().replace(/^type\s+/, "").split(/\s+as\s+/)[0];
        // 런타임 export 또는 d.ts 선언 (type · interface)
        if (name && !exported.has(name) && !typeNames(pkg).has(name)) fail(`${file}: @gentizer/${pkg} 에 ${name} 없음`);
      }
    }
  }
}

// TS 타입 · 컴포넌트 이름 (런타임 export 가 아닌 것) 은 d.ts 에서
function typeNames(pkg) {
  try {
    const dts = readFileSync(`${root}packages/${pkg}/dist/index.d.ts`, "utf8");
    return new Set([...dts.matchAll(/export (?:declare )?(?:function|const|class|interface|type) (\w+)/g)].map(([, n]) => n));
  } catch {
    return new Set();
  }
}

// Swift: gentizer 접두 · 알려진 이름의 public 선언
const swiftSources = [];
(function walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) walk(`${dir}/${e.name}`);
    else if (e.name.endsWith(".swift")) swiftSources.push(readFileSync(`${dir}/${e.name}`, "utf8"));
  }
})(`${root}swift/Sources`);
const swift = swiftSources.join("\n");
const FUNCS = ["runWithFrontendTools", "connectTriggers", "validateManifest", "toAGUITools", "toAGUIContext", "toA2uiCatalog"];
const swiftNames = new Set();
for (const [, text] of docs) {
  for (const code of [...blocks(text, ["swift"]), ...inline(text)]) {
    for (const [, n] of code.matchAll(/\.(agent[A-Z]\w*)\(/g)) swiftNames.add(`func:${n}`);
    for (const [, n] of code.matchAll(/\b((?:A2UI|AGUI|Agent)[A-Z]\w*|ActionDef|StateDef|ViewDef|AgentRuntime)\b/g)) swiftNames.add(`type:${n}`);
    for (const n of FUNCS) if (new RegExp(`\\b${n}\\(`).test(code) && blocks(text, ["swift"]).includes(code)) swiftNames.add(`func:${n}`);
  }
}
for (const key of swiftNames) {
  const [kind, name] = key.split(":");
  const re =
    kind === "func"
      ? new RegExp(`public (?:static )?func ${name}\\b`)
      : new RegExp(`public (?:final )?(?:class|struct|enum|protocol|typealias|actor) ${name}\\b|public let ${name}\\b`);
  if (!re.test(swift)) fail(`Swift public ${kind === "func" ? "func" : "type"} ${name} 없음`);
}

if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  process.exit(1);
}
console.log(`skills/gentizer 검사 통과: references ${refs.length} · Swift 이름 ${swiftNames.size}`);
