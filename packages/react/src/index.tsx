"use client";

import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import type { ActionDef, ActionRun, AgentRuntime, Manifest, StateDef, ViewDef } from "@gentizer/core";

const RuntimeContext = createContext<AgentRuntime | null>(null);

export function GentizerProvider({ runtime, children }: { runtime: AgentRuntime; children?: ReactNode }) {
  return <RuntimeContext.Provider value={runtime}>{children}</RuntimeContext.Provider>;
}

export function useAgentRuntime(): AgentRuntime {
  const rt = useContext(RuntimeContext);
  if (!rt) throw new Error("GentizerProvider 밖에서 gentizer hook 사용");
  return rt;
}

/** def 는 내용 비교: 매 렌더 새 object 여도 내용이 같으면 재등록하지 않는다 */
function useRegistration(name: string, def: unknown, register: () => () => void) {
  const rt = useAgentRuntime();
  const key = JSON.stringify(def);
  // register 는 최신 렌더의 클로저지만 재등록 조건은 rt · name · key 만
  const registerRef = useRef(register);
  registerRef.current = register;
  useEffect(() => registerRef.current(), [rt, name, key]);
}

export function useAgentAction(name: string, def: ActionDef, run: ActionRun): void {
  const rt = useAgentRuntime();
  const runRef = useRef(run);
  runRef.current = run;
  useRegistration(name, def, () => rt.action(name, def, (args) => runRef.current(args)));
}

export function useAgentState(name: string, def: StateDef, value: unknown): void {
  const rt = useAgentRuntime();
  const valueRef = useRef(value);
  valueRef.current = value;
  useRegistration(name, def, () => rt.state(name, def, () => valueRef.current));
}

export function useAgentView(name: string, def: ViewDef): void {
  const rt = useAgentRuntime();
  useRegistration(name, def, () => rt.view(name, def));
}

// runtime 당 manifest 캐시 하나. 내부 구독이 컴포넌트 구독보다 먼저 등록되어 변경 알림 전에 갱신된다
const stores = new WeakMap<AgentRuntime, { manifest: Manifest }>();
function manifestStore(rt: AgentRuntime) {
  let s = stores.get(rt);
  if (!s) {
    const created = { manifest: rt.manifest() };
    rt.subscribe(() => {
      created.manifest = rt.manifest();
    });
    stores.set(rt, created);
    s = created;
  }
  return s;
}

/** 등록 · 해제 때만 새 object. 변경이 없으면 같은 object */
export function useAgentManifest(): Manifest {
  const rt = useAgentRuntime();
  const getSnapshot = () => manifestStore(rt).manifest;
  return useSyncExternalStore(rt.subscribe, getSnapshot, getSnapshot);
}
