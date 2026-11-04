"use client";

import { useEffect, useRef, useState, useSyncExternalStore, type ComponentType, type ReactNode } from "react";
import { createA2uiSurfaceHost, type A2uiSurfaceHost, type A2uiSurfaceHostOptions } from "@gentizer/a2ui";
import { useAgentRuntime } from "@gentizer/react";

export type { A2uiSurfaceHost, A2uiSurfaceHostOptions, RendererMessage } from "@gentizer/a2ui";

/** 마운트 후 생성 (서버 렌더 · 첫 렌더 null), 언마운트 시 dispose. 커밋마다 syncState */
export function useA2uiSurfaceHost(options: A2uiSurfaceHostOptions): A2uiSurfaceHost | null {
  const runtime = useAgentRuntime();
  const sendRef = useRef(options.send);
  sendRef.current = options.send;
  const catalogsRef = useRef(options.catalogs);
  catalogsRef.current = options.catalogs;
  const [host, setHost] = useState<A2uiSurfaceHost | null>(null);
  const { catalogId, stateSync, triggerSurfaceId } = options;

  useEffect(() => {
    const created = createA2uiSurfaceHost(runtime, {
      catalogId,
      send: (m) => sendRef.current(m),
      ...(catalogsRef.current ? { catalogs: catalogsRef.current } : {}),
      ...(stateSync === undefined ? {} : { stateSync }),
      ...(triggerSurfaceId === undefined ? {} : { triggerSurfaceId }),
    });
    setHost(created);
    return () => {
      created.dispose();
      setHost(null);
    };
  }, [runtime, catalogId, stateSync, triggerSurfaceId]);

  // React 상태 값 변경은 runtime 알림이 없다 → 커밋마다 반영
  useEffect(() => {
    host?.syncState();
  });
  return host;
}

const EMPTY: string[] = [];

/** 활성 surface id. 생성 · 삭제 시 다시 렌더 */
export function useA2uiSurfaceIds(host: A2uiSurfaceHost | null): string[] {
  const cache = useRef<{ host: A2uiSurfaceHost | null; ids: string[] }>({ host: null, ids: EMPTY });
  const read = () => {
    if (!host) return EMPTY;
    const ids = host.surfaceIds();
    const prev = cache.current;
    if (prev.host === host && prev.ids.length === ids.length && prev.ids.every((x, i) => x === ids[i])) return prev.ids;
    cache.current = { host, ids };
    return ids;
  };
  return useSyncExternalStore((cb) => (host ? host.subscribe(cb) : () => {}), read, () => EMPTY);
}

type SurfaceComponent = ComponentType<{ surface: never }>;
let loading: Promise<SurfaceComponent> | null = null;
/** 서버에서 평가되지 않도록 마운트 후에만 불러온다 (Next.js ssr:false 와 같은 효과) */
function loadSurface(): Promise<SurfaceComponent> {
  loading ??= import("@a2ui/react/v0_9").then((m) => m.A2uiSurface as unknown as SurfaceComponent);
  return loading;
}

export interface A2uiSurfaceViewProps {
  host: A2uiSurfaceHost | null;
  surfaceId: string;
  /** 서버 · 첫 렌더 · 로드 전 · 없는 surface. 기본 null */
  fallback?: ReactNode;
}

export function A2uiSurfaceView({ host, surfaceId, fallback = null }: A2uiSurfaceViewProps) {
  const [Surface, setSurface] = useState<SurfaceComponent | null>(null);
  useEffect(() => {
    let alive = true;
    loadSurface().then(
      (c) => alive && setSurface(() => c),
      (err) => console.error("[gentizer/react-a2ui] @a2ui/react 로드 실패", err),
    );
    return () => {
      alive = false;
    };
  }, []);
  const ids = useA2uiSurfaceIds(host);
  const surface = host && ids.includes(surfaceId) ? host.surface(surfaceId) : undefined;
  if (!Surface || !surface) return <>{fallback}</>;
  return <Surface key={surfaceId} surface={surface as never} />;
}
