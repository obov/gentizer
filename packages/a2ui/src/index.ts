import { toA2uiCatalog, type A2uiCatalog, type AgentRuntime } from "@gentizer/core";
import {
  Catalog,
  RpcHandler,
  type CallRendererFunctionMessage,
  type FunctionImplementation,
  type RendererFunctionResponseMessage,
} from "@a2ui/web_core/v1_0";

export interface A2uiBridge {
  /** 현재 등록된 액션의 A2UI v1.0 catalog. 에이전트에 보낼 정의 */
  catalog(): A2uiCatalog;
  /** callRendererFunction → rendererFunctionResponse. reject 없음 */
  handle(message: CallRendererFunctionMessage): Promise<RendererFunctionResponseMessage>;
  dispose(): void;
}

export function createA2uiBridge(runtime: AgentRuntime, options: { catalogId: string }): A2uiBridge {
  const { catalogId } = options;
  // 등록 변경 시 버리고, 다음 handle 에서 다시 만든다 (D1: lazy)
  let handler: RpcHandler | null = null;
  const unsubscribe = runtime.subscribe(() => {
    handler?.dispose();
    handler = null;
  });

  const catalog = () => toA2uiCatalog(runtime.manifest(), { catalogId });

  function build(): RpcHandler {
    const parsed = Catalog.fromJson(catalog() as unknown as Record<string, unknown>);
    const impls = [...parsed.functions.values()].map(
      (f): FunctionImplementation => ({
        ...f,
        execute: async (args) => {
          const r = await runtime.invoke(f.name, args);
          if (!r.ok) throw new Error(`${r.error.code}: ${r.error.message}`);
          return r.value;
        },
      }),
    );
    return new RpcHandler({ catalogs: [new Catalog(catalogId, "1.0", [], impls)] });
  }

  return {
    catalog,
    async handle(message) {
      handler ??= build();
      const callFunction = message.callRendererFunction.callFunction;
      const filled: CallRendererFunctionMessage =
        callFunction.catalogId === undefined
          ? {
              ...message,
              callRendererFunction: { ...message.callRendererFunction, callFunction: { ...callFunction, catalogId } },
            }
          : message;
      return handler.handleCallRendererFunction(filled);
    },
    dispose() {
      unsubscribe();
      handler?.dispose();
      handler = null;
    },
  };
}
export * from "./surface-host.js";
