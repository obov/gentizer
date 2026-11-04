# dom — HTML `data-agent-*` 속성 바인딩

HTML 요소에 속성만 붙여 core 런타임 (`specs/core.md` '런타임') 에 액션 · 상태 · 화면을 등록한다 (README D1 의 HTML 속성 쪽).
패키지 `@gentizer/dom` (`packages/dom`). 의존성 `@gentizer/core`. 프레임워크 무관 (plain HTML · React · Vue).

## API

```text
bindAgentAttributes(runtime, root?, options?) → () => void
  root       기본 document.body. root 와 그 하위 요소를 대상
  options    onError?(error, element)  등록 실패 (이름 규칙 위반 · 중복 · description 없음) 통지. 기본 console.warn
  반환       해제 함수. 관찰 중지 + 이 바인딩이 한 등록 전부 해제
```

## 속성

| 속성 | 대상 | 등록 |
|---|---|---|
| `data-agent-action="<name>"` | 모든 요소 | 액션 `<name>`, 인자 없음 |
| `data-agent-field="<name>"` | `input` · `textarea` · `select` | 상태 `<name>` + 액션 `<name>_set` |
| `data-agent-view="<name>"` | 모든 요소 | 화면 `<name>` |
| `data-agent-desc="<설명>"` | 위 세 속성과 함께 | description. 없으면 등록하지 않고 onError |
| `data-agent-confirm` | `data-agent-action` · `data-agent-field` 요소 | 값과 무관하게 있으면 `confirm: true` |

액션 실행 (`data-agent-action`):

```text
form          form.requestSubmit()
그 외         element.click() (실제 click 이벤트. React · Vue 핸들러가 그대로 반응)
disabled      element.disabled 또는 aria-disabled="true" → throw "disabled: <name>" (EXECUTION_ERROR)
분리된 요소   실행 시점에 root 안에 없으면 throw "detached: <name>"
반환값        null
```

필드 (`data-agent-field`):

```text
상태          readState = 현재 값. checkbox · radio = checked (boolean), select multiple = 선택 값 배열, 그 외 = value 문자열
<name>_set    input { value }, required ["value"]. 스키마 type:
              checkbox · radio → boolean, select multiple → string 배열 (enum = option 값),
              select → string (enum = option 값), number · range → number, 그 외 → string
실행          값 설정은 요소 prototype 의 native setter (React 제어 input 도 반영) → input · change 이벤트 (bubbles) 발생
              select 의 enum 밖 값 → throw "invalid option: <value>"
반환값        설정 후 readState 값
```

## 관찰

- 시작 시 root 하위를 한 번 훑고, `MutationObserver` (childList · subtree · attributes: `data-agent-*`) 로 추가 · 제거 · 속성 변경을 반영
- 같은 요소의 이름 · 설명 · confirm 이 바뀌면 이전 등록 해제 후 재등록
- 이름 중복 (다른 요소 · 다른 바인딩 · 코드 API 등록) 은 먼저 등록한 것 유지, 나중 것은 onError
- 등록 순서 = 문서 순서 (최초 훑기). 이후 추가는 관찰 순서
- select 의 option 이 바뀌면 `<name>_set` 스키마 갱신 (재등록)
