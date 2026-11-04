# skill — L4 코딩 에이전트 skill (대상 프로젝트에 표시 추가)

개발자의 코딩 에이전트 (Claude Code · Codex) 가 대상 프로젝트를 훑고 gentizer 표시 (액션 · 상태 · 화면) 를 추가한다.
위치 `skills/gentizer/` (`SKILL.md` + `references/<platform>.md` + `check.mjs`).

## 설치

```text
Claude Code   대상 프로젝트 .claude/skills/gentizer/ 에 복사 (또는 심볼릭 링크)
Codex         대상 프로젝트 .agents/skills/gentizer/ 에 복사
```

## SKILL.md 절차

```text
1 플랫폼 감지      package.json 의 next · react, HTML 만 (index.html), Package.swift · *.xcodeproj + SwiftUI
2 설치             npm: @gentizer/core + 플랫폼 패키지 (react · dom · ag-ui · a2ui · react-a2ui), Swift: gentizer-swift product
3 후보 찾기        사용자 조작 (onClick · onSubmit · Button action · 폼 제출 · 화면 이동), 화면 상태 (useState · store · @State), 화면 영역
4 표시 기준        아래 '기준'
5 코드 추가        references/<platform>.md 의 형태 그대로 (HTML 속성 · hook · 수정자)
6 전송 연결        사용자가 고른 것: AG-UI (runWithFrontendTools) · A2UI (surface host) · 없음 (표시만)
7 검증             manifest 를 validateManifest 로 검사 (ok), 프로젝트 빌드 · 테스트
8 보고             표 (이름 · 종류 · confirm · 파일:줄) 와 일부러 표시하지 않은 것 (이유 한 줄)
```

## 기준

- 액션은 사용자가 화면에서 이미 할 수 있는 조작만. 새 능력 (화면에 없는 API 호출) 을 만들지 않는다 (README D2)
- 삭제 · 결제 · 외부 전송 · 되돌릴 수 없는 변경은 `confirm: true`
- 상태는 에이전트 판단에 필요한 읽기 값만. 비밀 · 토큰 · 개인정보 (이메일 · 전화 · 주소 · 결제 정보) 는 표시하지 않는다
- 이름 `^[a-z][a-z0-9_]*$` 64자 이하, `<대상>_<동사>` (cart_add · filter_set)
- description 은 에이전트가 읽는 한 줄: 무엇을 하는지 · 반환값
- 간단한 버튼 · 입력은 HTML 속성 (`specs/dom.md`), 인자 · 반환값이 필요한 동작은 코드 API (README D1)

## references

```text
html.md     data-agent-* 속성 · bindAgentAttributes · 전송 연결
react.md    GentizerProvider · useAgentAction · useAgentState · useAgentView · useAgentAttributes · surface (Next.js 포함)
swiftui.md  .agentRuntime · .agentAction · .agentState · .agentView · AgentConfirmation · AG-UI · A2UI surface
```

## 검사

`npm run check:skill` (`node skills/gentizer/check.mjs`, `npm run build` 뒤):

- SKILL.md frontmatter `name: gentizer` · `description` (1024자 이하)
- SKILL.md 가 가리키는 `references/*.md` 가 모두 있음
- skill 문서의 코드 블록에 나오는 TS API 이름이 각 패키지 dist export 에 있음, Swift API 이름이 `swift/Sources` 에 public 으로 있음

미결: agent-loader 연결. agent-loader 는 클라이언트 tool (AG-UI · A2UI) 입구가 없어 gentizer 액션을 실행할 경로가 없다. agent-loader 쪽 지원 (frontend tool 채널) 이 정해지면 skill 에 연결 절차를 더한다
