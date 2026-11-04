// conformance/ 케이스를 읽는 TS 실행기 공통 도구 (specs/conformance.md '실행기')
// core · ag-ui · a2ui 테스트가 상대 경로로 import 한다
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Ajv2020 } from "ajv/dist/2020.js";
import { createAgentRuntime, type ActionDef, type AgentRuntime, type StateDef } from "../src/index.js";

export const CONFORMANCE_DIR = fileURLToPath(new URL("../../../conformance/", import.meta.url));

const schema = JSON.parse(readFileSync(`${CONFORMANCE_DIR}schema.json`, "utf8"));
const validateFile = new Ajv2020({ allErrors: true, strict: false }).compile(schema);

/** 케이스 파일이 schema.json 을 위반하면 사유 문자열, 통과하면 null */
export function schemaErrors(file: unknown): string | null {
  return validateFile(file) ? null : JSON.stringify(validateFile.errors);
}

export interface LoadedCase<C> {
  id: string;
  c: C;
}

/** conformance/<suite>/*.json 전부. 파일 없음 · schema 위반 · suite 불일치 · 이름 중복은 throw */
export function loadSuite<C extends { name: string }>(suite: string): LoadedCase<C>[] {
  const dir = `${CONFORMANCE_DIR}${suite}/`;
  const files = readdirSync(dir).filter((f) => f.endsWith(".json")).sort();
  if (files.length === 0) throw new Error(`conformance/${suite} 케이스 파일 없음`);
  const out: LoadedCase<C>[] = [];
  const seen = new Set<string>();
  for (const f of files) {
    const data = JSON.parse(readFileSync(dir + f, "utf8"));
    const err = schemaErrors(data);
    if (err) throw new Error(`conformance/${suite}/${f} schema 위반: ${err}`);
    if (data.suite !== suite) throw new Error(`conformance/${suite}/${f} suite 불일치: ${data.suite}`);
    for (const c of data.cases as C[]) {
      const id = `${suite}/${f.replace(/\.json$/, "")}#${c.name}`;
      if (seen.has(id)) throw new Error(`케이스 id 중복: ${id}`);
      seen.add(id);
      out.push({ id, c });
    }
  }
  return out;
}

export type ConfirmMode = "approve" | "deny" | "throw" | "absent";
export type Behavior = { returns: unknown } | { throws: string } | { echoArgs: true };
export interface ActionDecl {
  name: string;
  def: ActionDef;
  behavior: Behavior;
}
export interface StateDecl {
  name: string;
  def: StateDef;
  value?: unknown;
}

export interface ConfirmCall {
  name: string;
  description: string;
  args: Record<string, unknown>;
}

/** confirm 모드대로 runtime 생성. 호출된 confirm 인자는 calls 에 쌓인다 */
export function makeRuntime(mode: ConfirmMode = "absent") {
  const calls: ConfirmCall[] = [];
  const confirm =
    mode === "absent"
      ? undefined
      : (req: ConfirmCall) => {
          calls.push(req);
          if (mode === "throw") throw new Error("confirm 실패");
          return mode === "approve";
        };
  const runtime = createAgentRuntime(confirm ? { confirm } : {});
  return { runtime, calls };
}

export function behaviorRun(b: Behavior) {
  return (args: Record<string, unknown>) => {
    if ("throws" in b) throw new Error(b.throws);
    if ("echoArgs" in b) return args;
    return structuredClone(b.returns);
  };
}

export function registerDecls(rt: AgentRuntime, actions: ActionDecl[] = [], states: StateDecl[] = []) {
  for (const a of actions) rt.action(a.name, a.def, behaviorRun(a.behavior));
  for (const s of states) rt.state(s.name, s.def, () => structuredClone(s.value));
}
