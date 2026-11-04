import { MANIFEST_VERSION, NAME_MAX_LENGTH, NAME_PATTERN, RETURN_TYPES } from "./manifest.js";

export interface ValidationError {
  path: string;
  message: string;
}

export type ValidationResult = { ok: true } | { ok: false; errors: ValidationError[] };

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const SECTIONS = ["actions", "state", "views"] as const;

/** manifest 규칙 위반을 모두 수집한다. 객체 키 중복은 JS 에서 표현 불가라 레지스트리 계층 (createManifestBuilder) 이 검사한다. */
export function validateManifest(m: unknown): ValidationResult {
  const errors: ValidationError[] = [];
  const err = (path: string, message: string) => errors.push({ path, message });

  if (!isRecord(m)) {
    return { ok: false, errors: [{ path: "", message: "manifest 는 object" }] };
  }
  if (m.version !== MANIFEST_VERSION) err("version", `"${MANIFEST_VERSION}" 이어야 함`);

  for (const section of SECTIONS) {
    const entries = m[section];
    if (!isRecord(entries)) {
      err(section, "object 이어야 함");
      continue;
    }
    for (const [name, def] of Object.entries(entries)) {
      const p = `${section}.${name}`;
      if (!NAME_PATTERN.test(name) || name.length > NAME_MAX_LENGTH)
        err(p, `이름 규칙 위반: ${NAME_PATTERN} · ${NAME_MAX_LENGTH}자 이하`);
      if (!isRecord(def)) {
        err(p, "object 이어야 함");
        continue;
      }
      if (typeof def.description !== "string" || def.description.trim() === "") {
        err(`${p}.description`, "비어 있지 않은 문자열이어야 함");
      }
      if (section === "actions") {
        if (def.input !== undefined && (!isRecord(def.input) || def.input.type !== "object")) {
          err(`${p}.input`, 'JSON Schema 최상위 type 은 "object" 만 허용');
        }
        if (def.confirm !== undefined && typeof def.confirm !== "boolean") {
          err(`${p}.confirm`, "boolean 이어야 함");
        }
        if (def.returns !== undefined && !(RETURN_TYPES as readonly unknown[]).includes(def.returns)) {
          err(`${p}.returns`, `허용값: ${RETURN_TYPES.join(", ")}`);
        }
      }
      if (section === "state" && def.schema !== undefined && !isRecord(def.schema)) {
        err(`${p}.schema`, "JSON Schema object 이어야 함");
      }
    }
  }
  return errors.length === 0 ? { ok: true } : { ok: false, errors };
}
