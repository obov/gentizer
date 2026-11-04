---
name: gentizer
description: 기존 웹 (HTML · React · Next.js) 또는 SwiftUI 앱에 gentizer 표시를 추가해 에이전트가 앱의 버튼 · 입력 · 상태를 다루게 한다. "에이전트가 앱을 조작하게 해줘", "gentizer 붙여줘", "AI 가 이 버튼 누르게", "앱 액션을 tool 로 노출", "A2UI · AG-UI 연결" 같은 요청에 쓴다.
---

# gentizer — 앱에 에이전트 조작 표시 추가

에이전트가 조작해도 되는 부분만 표시한다. 표시한 것이 에이전트의 도구 (액션) · 상태 · 화면 맥락이 되고, 표시하지 않은 것은 에이전트가 건드릴 수 없다.

## 절차

1. 플랫폼 감지
   - `package.json` 에 `next` → Next.js (React 규칙 + 서버 컴포넌트 주의), `react` → React
   - `package.json` 없이 HTML · 바닐라 JS → HTML
   - `Package.swift` 또는 `*.xcodeproj` + `import SwiftUI` → SwiftUI
2. 설치
   - 웹: `npm install @gentizer/core` + 필요한 것 (`@gentizer/react` · `@gentizer/dom` · `@gentizer/ag-ui` · `@gentizer/a2ui` · `@gentizer/react-a2ui`)
   - Swift: `.package(url: "https://github.com/obov/gentizer-swift.git", from: "0.1.0")`, product `Gentizer` · `GentizerSwiftUI` (+ `GentizerAGUI` · `GentizerA2UISwiftUI`)
3. 후보 찾기: 사용자 조작 (onClick · onSubmit · Button action · 폼 제출 · 화면 이동), 화면 상태 (useState · store · @State), 화면 영역 (목록 · 장바구니 · 상세)
4. 아래 '기준' 으로 표시할 것 고르기
5. 플랫폼 문서대로 코드 추가
   - HTML: [references/html.md](references/html.md)
   - React · Next.js: [references/react.md](references/react.md)
   - SwiftUI: [references/swiftui.md](references/swiftui.md)
6. 전송 연결: 사용자에게 묻는다. AG-UI 에이전트 (`runWithFrontendTools`) · A2UI 에이전트 (surface host) · 없음 (표시만, 나중에 연결)
7. 검증
   - 웹: 앱에서 `validateManifest(runtime.manifest())` 가 `{ ok: true }` (개발 중 한 번 console 출력)
   - Swift: `validateManifest(runtime.manifest().json) == .ok`
   - 프로젝트의 빌드 · 테스트 명령 통과
8. 보고: 표 (이름 · 종류 · confirm · 파일:줄) 와 일부러 표시하지 않은 것 (이유 한 줄)

## 기준

- 액션은 사용자가 화면에서 이미 할 수 있는 조작만. 화면에 없는 API 호출을 새 액션으로 만들지 않는다
- 삭제 · 결제 · 외부 전송 · 되돌릴 수 없는 변경은 `confirm: true` (실행 전 사용자 승인)
- 상태는 에이전트 판단에 필요한 읽기 값만. 비밀 · 토큰 · 개인정보 (이메일 · 전화 · 주소 · 결제 정보) 는 표시하지 않는다
- 이름 `^[a-z][a-z0-9_]*$` 64자 이하, `<대상>_<동사>` (`cart_add` · `filter_set`). `.` · `-` 불가
- description 은 에이전트가 읽는 한 줄: 무엇을 하는지 · 반환값 ("상품을 장바구니에 담기. 반환: 장바구니 개수")
- 간단한 버튼 · 입력은 HTML 속성, 인자 · 반환값이 필요한 동작은 코드 API
- 같은 이름을 두 번 등록하지 않는다 (목록 행마다 액션을 만들지 말고 id 인자를 받는 액션 하나)

## 하지 않는 것

- 기존 핸들러 동작을 바꾸지 않는다. 표시는 기존 함수를 그대로 부른다
- 표시를 위해 상태 관리 구조를 바꾸지 않는다
- 에이전트 서버 · LLM 설정은 범위 밖 (전송 연결 코드까지만)
