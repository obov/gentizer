import type { Manifest, ObjectSchema, ReturnType } from "./manifest.js";
import { validateManifest, type ValidationError } from "./validate.js";

export interface A2uiFunctionDefinition {
  type: "object";
  description: string;
  returnType: ReturnType;
  allowedCallers: "agentOnly";
  properties: { "@call": { const: string }; args: ObjectSchema };
  required: ["@call"] | ["@call", "args"];
}

export interface A2uiCatalog {
  protocolVersion: "1.0";
  catalogId: string;
  functions: Record<string, A2uiFunctionDefinition>;
  metadata?: { extensions: { gentizer: GentizerCatalogExtension } };
}

/** 바인딩 런타임이 실행 전 사용자 승인을 받아야 하는 액션 이름 */
export interface GentizerCatalogExtension {
  confirm: string[];
}

export class InvalidManifestError extends Error {
  constructor(readonly errors: ValidationError[]) {
    super(`manifest 검증 실패: ${errors.map((e) => `${e.path || "(root)"} ${e.message}`).join("; ")}`);
    this.name = "InvalidManifestError";
  }
}

const EMPTY_INPUT: ObjectSchema = { type: "object", properties: {} };

/** manifest 의 actions 를 A2UI v1.0 catalog function 정의로 변환. state · views 는 포함하지 않는다 */
export function toA2uiCatalog(m: Manifest, options: { catalogId: string }): A2uiCatalog {
  const result = validateManifest(m);
  if (!result.ok) throw new InvalidManifestError(result.errors);

  const functions: Record<string, A2uiFunctionDefinition> = {};
  const confirm: string[] = [];
  for (const [name, action] of Object.entries(m.actions)) {
    const args = structuredClone(action.input ?? EMPTY_INPUT);
    const argsRequired = Array.isArray(args.required) && args.required.length > 0;
    functions[name] = {
      type: "object",
      description: action.description,
      returnType: action.returns ?? "void",
      allowedCallers: "agentOnly",
      properties: { "@call": { const: name }, args },
      required: argsRequired ? ["@call", "args"] : ["@call"],
    };
    if (action.confirm) confirm.push(name);
  }
  return {
    protocolVersion: "1.0",
    catalogId: options.catalogId,
    functions,
    ...(confirm.length > 0 ? { metadata: { extensions: { gentizer: { confirm } } } } : {}),
  };
}
