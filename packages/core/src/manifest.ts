export const MANIFEST_VERSION = "gentizer/0.1";

export const RETURN_TYPES = ["string", "number", "boolean", "array", "object", "any", "void"] as const;
export type ReturnType = (typeof RETURN_TYPES)[number];

export type JsonSchema = Record<string, unknown>;
export type ObjectSchema = JsonSchema & { type: "object" };

export interface ActionDef {
  description: string;
  input?: ObjectSchema;
  confirm?: boolean;
  returns?: ReturnType;
}

export interface StateDef {
  description: string;
  schema?: JsonSchema;
}

export interface ViewDef {
  description: string;
}

export interface Manifest {
  version: typeof MANIFEST_VERSION;
  actions: Record<string, ActionDef>;
  state: Record<string, StateDef>;
  views: Record<string, ViewDef>;
}

/** 소문자 영문으로 시작하는 segment 를 점으로 연결. segment 안에는 소문자 영숫자 · _ · - */
export const NAME_PATTERN = /^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)*$/;
