import { NAME_MAX_LENGTH, NAME_PATTERN, type ActionDef, type AgentRuntime } from "@gentizer/core";

export interface BindAgentAttributesOptions {
  /** 등록 실패 (이름 규칙 위반 · 중복 · description 없음). 기본 console.warn */
  onError?: (error: unknown, element: Element) => void;
}

type Field = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;

/** 요소 하나 · 종류 하나의 등록. key 가 같으면 재등록 불필요 */
interface Registration {
  key: string;
  off: Array<() => void>;
}

const KINDS = ["action", "field", "view"] as const;
type Kind = (typeof KINDS)[number];
const SELECTOR = KINDS.map((k) => `[data-agent-${k}]`).join(",");
const ATTRIBUTES = ["action", "field", "view", "desc", "confirm"].map((a) => `data-agent-${a}`);

/** data-agent-* 속성을 runtime 에 등록하고 DOM 변화를 따라간다. 반환 함수로 전부 해제 */
export function bindAgentAttributes(
  runtime: AgentRuntime,
  root: Element = document.body,
  options: BindAgentAttributesOptions = {},
): () => void {
  const onError = options.onError ?? ((error, element) => console.warn("[gentizer/dom]", error, element));
  const registrations = new Map<Element, Map<Kind, Registration>>();

  function scan() {
    const elements = [...(root.matches(SELECTOR) ? [root] : []), ...root.querySelectorAll(SELECTOR)];
    const alive = new Set(elements);
    // 사라진 요소 · 속성이 빠진 종류 해제
    for (const [el, byKind] of registrations) {
      for (const [kind, reg] of byKind) {
        if (!alive.has(el) || !el.hasAttribute(`data-agent-${kind}`)) {
          for (const off of reg.off) off();
          byKind.delete(kind);
        }
      }
      if (byKind.size === 0) registrations.delete(el);
    }
    // 문서 순서로 추가 · 변경
    for (const el of elements) {
      for (const kind of KINDS) {
        if (!el.hasAttribute(`data-agent-${kind}`)) continue;
        const key = keyOf(el, kind);
        const byKind = registrations.get(el) ?? new Map<Kind, Registration>();
        const prev = byKind.get(kind);
        if (prev?.key === key) continue;
        if (prev) for (const off of prev.off) off();
        byKind.delete(kind);
        // 실패도 key 를 기록해 같은 상태로 다시 시도 · 통지하지 않는다
        byKind.set(kind, { key, off: register(el, kind) ?? [] });
        registrations.set(el, byKind);
      }
    }
  }

  function register(el: Element, kind: Kind): Array<() => void> | null {
    const name = el.getAttribute(`data-agent-${kind}`) ?? "";
    const description = el.getAttribute("data-agent-desc");
    if (!description) {
      onError(new Error(`data-agent-desc 없음: ${kind} ${name}`), el);
      return null;
    }
    // runtime 은 등록 시 이름을 검사하지 않는다 (manifest 검증 몫). <name>_set 도 64자 안이어야 한다
    const limit = kind === "field" ? NAME_MAX_LENGTH - 4 : NAME_MAX_LENGTH;
    if (!NAME_PATTERN.test(name) || name.length > limit) {
      onError(new Error(`이름 규칙 위반: ${kind} ${name}`), el);
      return null;
    }
    const confirm = el.hasAttribute("data-agent-confirm") ? { confirm: true } : {};
    const done: Array<() => void> = [];
    try {
      if (kind === "view") {
        done.push(runtime.view(name, { description }));
      } else if (kind === "action") {
        done.push(runtime.action(name, { description, ...confirm }, () => runAction(el, name)));
      } else {
        if (!isField(el)) throw new Error(`data-agent-field 는 input · textarea · select 만: ${name}`);
        done.push(runtime.state(name, { description }, () => readField(el)));
        const def: ActionDef = {
          description: `${description} 값 설정`,
          input: { type: "object", properties: { value: valueSchema(el) }, required: ["value"] },
          returns: "any",
          ...confirm,
        };
        done.push(runtime.action(`${name}_set`, def, (args) => setField(el, name, args.value)));
      }
      return done;
    } catch (err) {
      for (const off of done) off();
      onError(err, el);
      return null;
    }
  }

  function runAction(el: Element, name: string): null {
    if (!root.contains(el)) throw new Error(`detached: ${name}`);
    if (isDisabled(el)) throw new Error(`disabled: ${name}`);
    if (el instanceof HTMLFormElement) el.requestSubmit();
    else (el as HTMLElement).click();
    return null;
  }

  function setField(el: Field, name: string, value: unknown): unknown {
    if (!root.contains(el)) throw new Error(`detached: ${name}`);
    if (isDisabled(el)) throw new Error(`disabled: ${name}`);
    if (el instanceof HTMLSelectElement) {
      const allowed = new Set([...el.options].map((o) => o.value));
      const wanted = el.multiple ? (Array.isArray(value) ? value.map(String) : [String(value)]) : [String(value)];
      for (const v of wanted) if (!allowed.has(v)) throw new Error(`invalid option: ${v}`);
      if (el.multiple) for (const o of el.options) o.selected = wanted.includes(o.value);
      else nativeSet(el, "value", wanted[0]);
    } else if (el instanceof HTMLInputElement && (el.type === "checkbox" || el.type === "radio")) {
      nativeSet(el, "checked", value === true);
    } else {
      nativeSet(el, "value", String(value ?? ""));
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return readField(el);
  }

  scan();
  let pending = false;
  const observer = new MutationObserver(() => {
    // 한 tick 의 변경을 모아 한 번만 훑는다
    if (pending) return;
    pending = true;
    queueMicrotask(() => {
      pending = false;
      scan();
    });
  });
  observer.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ATTRIBUTES, characterData: false });
  // select 의 option 변경은 childList 로 잡힌다 (위 subtree)

  return () => {
    observer.disconnect();
    for (const byKind of registrations.values()) for (const reg of byKind.values()) for (const off of reg.off) off();
    registrations.clear();
  };
}

/** 재등록 판단 키: 이름 · 설명 · confirm · (필드) 스키마 */
function keyOf(el: Element, kind: Kind): string {
  const parts = [kind, el.getAttribute(`data-agent-${kind}`), el.getAttribute("data-agent-desc"), el.hasAttribute("data-agent-confirm")];
  if (kind === "field" && isField(el)) parts.push(JSON.stringify(valueSchema(el)));
  return JSON.stringify(parts);
}

function isField(el: Element): el is Field {
  return el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement;
}

function isDisabled(el: Element): boolean {
  return (el as HTMLButtonElement).disabled === true || el.getAttribute("aria-disabled") === "true";
}

function readField(el: Field): unknown {
  if (el instanceof HTMLInputElement && (el.type === "checkbox" || el.type === "radio")) return el.checked;
  if (el instanceof HTMLSelectElement && el.multiple) return [...el.selectedOptions].map((o) => o.value);
  return el.value;
}

function valueSchema(el: Field): Record<string, unknown> {
  if (el instanceof HTMLSelectElement) {
    const values = [...el.options].map((o) => o.value);
    return el.multiple ? { type: "array", items: { type: "string", enum: values } } : { type: "string", enum: values };
  }
  if (el instanceof HTMLInputElement) {
    if (el.type === "checkbox" || el.type === "radio") return { type: "boolean" };
    if (el.type === "number" || el.type === "range") return { type: "number" };
  }
  return { type: "string" };
}

/** prototype 의 native setter. React 제어 input 의 value tracker 를 우회해 onChange 가 불린다 */
function nativeSet(el: Field, prop: "value" | "checked", value: unknown) {
  const proto = Object.getPrototypeOf(el) as object;
  const setter = Object.getOwnPropertyDescriptor(proto, prop)?.set;
  if (setter) setter.call(el, value);
  else (el as unknown as Record<string, unknown>)[prop] = value;
}
