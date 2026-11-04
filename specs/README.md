# specs — 현재 상태

이 디렉터리는 **합의된 요구사항**만 설명한다. 미구현은 `미구현:`, 합의 전은 `미결:` 로 표기한다.
왜 이렇게 됐는지는 git history 가 답한다 (`.agents/skills/gnam/references/index.md`).

```text
<파일명>.md  <한 줄 설명>
core.md      L2 manifest 스키마 · 검증 · A2UI v1.0 catalog 변환 · 런타임
react.md     React · Next.js 바인딩 (hooks)
dom.md       HTML data-agent-* 속성 바인딩
a2ui.md      A2UI v1.0 callRendererFunction → 런타임 브리지 (웹)
ag-ui.md     AG-UI 전송 어댑터 (frontend tool · context)
conformance.md  언어 공통 JSON 케이스 · 저장소 배치
swift.md     Swift 패키지 배치 · gentizer-swift 배포 · conformance 실행기 · core API
swiftui.md   SwiftUI 바인딩 (environment · 수정자 · manifest 모델 · 승인 UI)
skill.md     L4 코딩 에이전트 skill (대상 프로젝트에 표시 추가)
```

## 커밋

제목 접두 `spec.<topic>.<kind>:` 의 `<topic>` = 이 디렉터리의 파일 이름 (확장자 제외).

```text
spec.<topic>.plan:    spec 파일 하나 변경 (없으면 --allow-empty) + 본문 Goal · Plan · Blocking (· Scope · Decisions expected · Risks · Open)
spec.<topic>.impl:    본문 첫 줄 Plan: <plan 커밋 hash> <단계>
spec.<topic>.chore:   계획 없는 spec 정리. 본문 Goal · Scope
chore:                spec 과 무관한 변경 (의존성 · 설정 · 도구)
refactor:             동작 유지 · 구조만 변경. 본문 Goal · Scope · Invariant. specs/ 변경 금지
```

상세: `.agents/skills/gnam/references/commits/`
