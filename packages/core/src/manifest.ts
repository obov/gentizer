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

/** 소문자 영문 시작, 소문자 영숫자 · _. A2UI v1.0 function 이름 (UAX #31) 과 LLM tool 이름의 공통 부분집합 */
export const NAME_PATTERN = /^[a-z][a-z0-9_]*$/;
export const NAME_MAX_LENGTH = 64;
