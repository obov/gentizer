import type { AgentRuntime, TriggerEvent } from "@gentizer/core";
import {
  MessageProcessor,
  basicCatalog,
  type ActionPayload,
  type Catalog,
  type CallRendererFunctionMessage,
  type SurfaceModel,
} from "@a2ui/web_core/v1_0";
import { createA2uiBridge, type A2uiBridge } from "./index.js";

/** 렌더러 → 에이전트 메시지 하나 (A2UI v1.0 JSON) */
export type RendererMessage = { version: "1.0" } & Record<string, unknown>;

export interface A2uiSurfaceHostOptions {
  catalogId: string;
  send: (message: RendererMessage) => void;
  /** basic catalog 앞에 둘 component catalog (같은 id 면 앞 것 우선) */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  catalogs?: Catalog<any>[];
  /** 기본 true. false 면 /gentizer 를 쓰지 않는다 */
  stateSync?: boolean;
  /** trigger action 의 surfaceId. 기본 "gentizer" */
  triggerSurfaceId?: string;
}

export interface A2uiSurfaceHost {
  readonly bridge: A2uiBridge;
  readonly processor: MessageProcessor;
  catalog(): ReturnType<A2uiBridge["catalog"]>;
  /** 에이전트 → 렌더러 메시지 하나. reject 없음 */
  process(message: unknown): Promise<void>;
  surfaceIds(): string[];
  surface(id: string): SurfaceModel | undefined;
  /** surface 생성 · 삭제마다. 해제 함수 반환 */
  subscribe(listener: () => void): () => void;
  callAgentFunction(surfaceId: string, call: { call: string; args?: Record<string, unknown> }, options?: { timeoutMs?: number }): Promise<unknown>;
  dataModel(): { version: "1.0"; surfaces: Record<string, unknown> };
  syncState(): void;
  dispose(): void;
}

export const TRIGGER_SOURCE_COMPONENT_ID = "gentizer";
const ROOT = "/gentizer";

export function createA2uiSurfaceHost(runtime: AgentRuntime, options: A2uiSurfaceHostOptions): A2uiSurfaceHost {
  const { catalogId, send, stateSync = true, triggerSurfaceId = "gentizer" } = options;
  const bridge = createA2uiBridge(runtime, { catalogId });
  const listeners = new Set<() => void>();
  const notify = () => {
    for (const l of [...listeners]) l();
  };

  const processor = new MessageProcessor(
    [...(options.catalogs ?? []), basicCatalog],
    (action: ActionPayload) => send({ version: "1.0", action: { ...action } }),
    {
      version: "v1.0",
      outboundListener: (m) => send(m as unknown as RendererMessage),
      errorHandler: (e) => send(e as unknown as RendererMessage),
      reportErrorsOnly: true,
    },
  );

  // 지난 쓰기에서 surface 별로 쓴 상태 이름. 해제된 이름을 지우는 데 쓴다
  const written = new Map<string, Set<string>>();

  function writeSurface(surface: SurfaceModel) {
    if (!stateSync) return;
    const manifest = runtime.manifest();
    const names = new Set(Object.keys(manifest.state));
    for (const old of written.get(surface.id) ?? []) {
      if (!names.has(old)) surface.dataModel.delete(`${ROOT}/state/${escape(old)}`);
    }
    for (const name of names) {
      const path = `${ROOT}/state/${escape(name)}`;
      const value = runtime.readState(name);
      // v1.0 data model 은 null 을 저장하지 않는다 (A2UI Swift 와 같은 결과)
      if (value === undefined || value === null) surface.dataModel.delete(path);
      else surface.dataModel.set(path, structuredClone(value));
    }
    written.set(surface.id, names);
    surface.dataModel.set(
      `${ROOT}/views`,
      Object.fromEntries(Object.entries(manifest.views).map(([name, def]) => [name, def.description])),
    );
  }

  function syncState() {
    for (const s of processor.model.surfacesMap.values()) writeSurface(s);
  }

  const subs = [
    processor.onSurfaceCreated((s) => {
      writeSurface(s);
      notify();
    }),
    processor.onSurfaceDeleted((id) => {
      written.delete(id);
      notify();
    }),
  ];
  const offRuntime = runtime.subscribe(syncState);
  const offTrigger = runtime.onTrigger((e: TriggerEvent) =>
    send({
      version: "1.0",
      action: {
        name: e.name,
        surfaceId: triggerSurfaceId,
        sourceComponentId: TRIGGER_SOURCE_COMPONENT_ID,
        timestamp: new Date().toISOString(),
        context: e.payload,
      },
    }),
  );

  return {
    bridge,
    processor,
    catalog: () => bridge.catalog(),
    async process(message) {
      try {
        if (isObject(message) && "callRendererFunction" in message) {
          send((await bridge.handle(message as unknown as CallRendererFunctionMessage)) as unknown as RendererMessage);
          return;
        }
        processor.processMessages(message as never);
      } catch (err) {
        send({ version: "1.0", error: { code: "INVALID_MESSAGE", message: err instanceof Error ? err.message : String(err), surfaceId: "" } });
      }
      syncState();
    },
    surfaceIds: () => [...processor.model.surfacesMap.keys()].sort(),
    surface: (id) => processor.model.surfacesMap.get(id),
    subscribe(listener) {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
    callAgentFunction: (surfaceId, call, opts) =>
      processor.callAgentFunction(surfaceId, call as never, opts?.timeoutMs === undefined ? undefined : { timeoutMs: opts.timeoutMs }),
    dataModel() {
      const dm = processor.getRendererDataModel("v1.0") as { surfaces?: Record<string, unknown> } | undefined;
      return { version: "1.0", surfaces: dm?.surfaces ?? {} };
    },
    syncState,
    dispose() {
      offTrigger();
      offRuntime();
      for (const s of subs) s.unsubscribe();
      listeners.clear();
      processor.dispose();
      bridge.dispose();
    },
  };
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
/** JSON Pointer 토큰 이스케이프 */
const escape = (s: string) => s.replace(/~/g, "~0").replace(/\//g, "~1");
