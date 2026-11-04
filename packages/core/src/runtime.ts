import { DuplicateNameError } from "./builder.js";
import { MANIFEST_VERSION, NAME_MAX_LENGTH, NAME_PATTERN, type ActionDef, type Manifest, type StateDef, type ViewDef } from "./manifest.js";

export type InvokeErrorCode = "NOT_FOUND" | "INVALID_ARGS" | "DENIED" | "EXECUTION_ERROR";

export type InvokeResult =
  | { ok: true; value: unknown }
  | { ok: false; error: { code: InvokeErrorCode; message: string } };

export interface ConfirmRequest {
  name: string;
  description: string;
  args: Record<string, unknown>;
}

export interface AgentRuntimeOptions {
  /** confirm: true 액션 실행 전 호출. 없으면 confirm 액션은 항상 DENIED */
  confirm?: (req: ConfirmRequest) => boolean | Promise<boolean>;
}

export type ActionRun = (args: Record<string, unknown>) => unknown;

/** P2 이벤트형: 앱 → 에이전트 알림 */
export interface TriggerEvent {
  name: string;
  payload: Record<string, unknown>;
}
export type TriggerListener = (event: TriggerEvent) => void;

export class InvalidTriggerError extends Error {
  readonly code = "INVALID_TRIGGER";
  constructor(message: string) {
    super(message);
    this.name = "InvalidTriggerError";
  }
}

interface Entry<D, X = undefined> {
  def: D;
  extra: X;
  token: symbol;
}

export interface AgentRuntime {
  action(name: string, def: ActionDef, run: ActionRun): () => void;
  state(name: string, def: StateDef, read: () => unknown): () => void;
  view(name: string, def: ViewDef): () => void;
  manifest(): Manifest;
  readState(name: string): unknown;
  subscribe(listener: () => void): () => void;
  invoke(name: string, args?: unknown): Promise<InvokeResult>;
  /** 이름 위반 · payload 가 object 아님은 InvalidTriggerError */
  trigger(name: string, payload?: unknown): void;
  onTrigger(listener: TriggerListener): () => void;
}

/** 표시와 실행 함수를 함께 보관하는 레지스트리. 바인딩이 마운트 · 언마운트에 맞춰 등록 · 해제 */
export function createAgentRuntime(options: AgentRuntimeOptions = {}): AgentRuntime {
  const actions = new Map<string, Entry<ActionDef, ActionRun>>();
  const states = new Map<string, Entry<StateDef, () => unknown>>();
  const views = new Map<string, Entry<ViewDef>>();
  const listeners = new Set<() => void>();
  // 같은 함수를 두 번 등록해도 각각 호출 · 각각 해제
  const triggerListeners = new Map<symbol, TriggerListener>();
  const notify = () => {
    for (const l of [...listeners]) l();
  };

  function register<D, X>(section: string, map: Map<string, Entry<D, X>>, name: string, def: D, extra: X) {
    if (map.has(name)) throw new DuplicateNameError(section, name);
    const token = Symbol(name);
    map.set(name, { def: structuredClone(def), extra, token });
    notify();
    // 자기 등록만 지운다: 이미 해제됐거나 같은 이름이 재등록된 경우 무시
    return () => {
      if (map.get(name)?.token !== token) return;
      map.delete(name);
      notify();
    };
  }

  const fail = (code: InvokeErrorCode, message: string): InvokeResult => ({ ok: false, error: { code, message } });
  const defs = <D>(map: Map<string, Entry<D, unknown>>) =>
    Object.fromEntries([...map].map(([k, e]) => [k, structuredClone(e.def)]));

  return {
    action: (name, def, run) => register("actions", actions, name, def, run),
    state: (name, def, read) => register("state", states, name, def, read),
    view: (name, def) => register("views", views, name, def, undefined),
    manifest: () => ({ version: MANIFEST_VERSION, actions: defs(actions), state: defs(states), views: defs(views) }),
    readState: (name) => states.get(name)?.extra(),
    subscribe(listener) {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
    trigger(name, payload = {}) {
      if (typeof name !== "string" || !NAME_PATTERN.test(name) || name.length > NAME_MAX_LENGTH)
        throw new InvalidTriggerError(`trigger 이름 규칙 위반: ${String(name)}`);
      if (typeof payload !== "object" || payload === null || Array.isArray(payload))
        throw new InvalidTriggerError("trigger payload 는 object");
      for (const l of [...triggerListeners.values()]) {
        try {
          l({ name, payload: structuredClone(payload as Record<string, unknown>) });
        } catch {
          // 한 수신기 실패가 다른 수신기를 막지 않는다
        }
      }
    },
    onTrigger(listener) {
      const key = Symbol("trigger");
      triggerListeners.set(key, listener);
      return () => void triggerListeners.delete(key);
    },
    async invoke(name, rawArgs = {}) {
      const entry = actions.get(name);
      if (!entry) return fail("NOT_FOUND", `등록되지 않은 액션: ${name}`);
      if (typeof rawArgs !== "object" || rawArgs === null || Array.isArray(rawArgs))
        return fail("INVALID_ARGS", "args 는 object");
      const args = rawArgs as Record<string, unknown>;
      const required = entry.def.input?.required;
      if (Array.isArray(required)) {
        const missing = required.filter((k) => typeof k === "string" && !Object.hasOwn(args, k));
        if (missing.length) return fail("INVALID_ARGS", `필수 인자 누락: ${missing.join(", ")}`);
      }
      if (entry.def.confirm) {
        let approved = false;
        try {
          approved = options.confirm ? (await options.confirm({ name, description: entry.def.description, args })) === true : false;
        } catch {
          approved = false;
        }
        if (!approved) return fail("DENIED", `사용자 승인 없음: ${name}`);
      }
      try {
        const value = await entry.extra(args);
        return { ok: true, value: value === undefined ? null : value };
      } catch (err) {
        return fail("EXECUTION_ERROR", err instanceof Error ? err.message : String(err));
      }
    },
  };
}
