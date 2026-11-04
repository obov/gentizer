import { MANIFEST_VERSION, type ActionDef, type Manifest, type StateDef, type ViewDef } from "./manifest.js";

export class DuplicateNameError extends Error {
  constructor(section: string, name: string) {
    super(`${section}.${name} 중복 등록`);
    this.name = "DuplicateNameError";
  }
}

/** 바인딩 계층이 표시를 하나씩 등록하는 레지스트리. 같은 구역 안 이름 중복은 즉시 오류 */
export function createManifestBuilder() {
  const m: Manifest = { version: MANIFEST_VERSION, actions: {}, state: {}, views: {} };
  const add = <T>(section: "actions" | "state" | "views", name: string, def: T) => {
    const target = m[section] as Record<string, T>;
    if (Object.hasOwn(target, name)) throw new DuplicateNameError(section, name);
    target[name] = def;
  };
  const builder = {
    action(name: string, def: ActionDef) {
      add("actions", name, def);
      return builder;
    },
    state(name: string, def: StateDef) {
      add("state", name, def);
      return builder;
    },
    view(name: string, def: ViewDef) {
      add("views", name, def);
      return builder;
    },
    build(): Manifest {
      return structuredClone(m);
    },
  };
  return builder;
}
