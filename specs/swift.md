# swift — Swift 패키지 배치 · 배포 · conformance 실행기

Swift 구현은 이 저장소 `swift/` 에서 개발하고, 배포 전용 저장소 `gentizer-swift` 로 내보낸다 (gnam export plugin).
사용자는 배포 저장소 URL 하나로 설치한다.

```swift
.package(url: "https://github.com/obov/gentizer-swift.git", from: "0.1.0")
```

## 배치

```text
swift/Package.swift                    SwiftPM 진입점 (배포 저장소의 루트가 된다)
swift/VERSION                          배포 버전 한 줄 (MAJOR.MINOR.PATCH)
swift/Sources/Gentizer/                core (manifest · 검증 · catalog · 런타임)
swift/Tests/GentizerTests/             Swift 고유 단위 테스트
swift/Tests/GentizerConformanceTests/  conformance 실행기
```

- swift-tools-version 6.0, 플랫폼 iOS 17 · macOS 14 이상 (A2UI Swift 하한, specs/a2ui.md 'Swift 의존성')
- 라이브러리 product `Gentizer` 하나. SwiftUI 바인딩 · AG-UI 어댑터는 별도 target (이후 plan)
- 빌드 산출물 `swift/.build/` 은 git 무시

## 예시 앱

`examples/swift/` — macOS SwiftUI 실행 파일 (SwiftPM 패키지 `examples/swift/ShopExample`, `swift/` 를 path 의존. 폴더 이름 `swift` 가 의존 패키지 identity 와 겹치지 않게 한 단계 아래). 웹 예시와 같은 미니 상점 + mock 에이전트 (`examples/mock`).

```text
실행        npm start -w @gentizer/example-mock (mock 두 개) · npm run dev -w @gentizer/example-swift
확인        npm run smoke -w @gentizer/example-swift: mock 과 정해진 대화 (AG-UI 담기 · A2UI 필터 · 추천 surface · trigger) 결과 출력 후 종료
표시        .agentAction (filter_set · cart_add · cart_clear confirm) · .agentState (cart · filter) · .agentView
승인        AgentConfirmation + .agentConfirmation
AG-UI       AGUIHTTPAgent (:8782) + runWithFrontendTools, 저장 버튼 trigger → connectTriggers
A2UI        A2UISurfaceHost (:8781 SSE) + 앱 컴포넌트 ProductCard, A2UISurfaceView 로 에이전트 surface 표시
```

- mock A2UI 에이전트는 "추천" 입력에 ProductCard surface 를 보낸다. mock AG-UI 에이전트는 trigger 메시지에 "앱 이벤트 수신: <name>" 으로 답한다
- 예시는 배포 저장소에 포함하지 않는다 (export path 밖)

## 배포

gnam.json `export.targets.swift`:

```text
path      swift
repo      https://github.com/obov/gentizer-swift.git
include   conformance → Tests/Conformance
tag       {version}   (v 없는 MAJOR.MINOR.PATCH, SwiftPM 규칙)
version   swift/VERSION
```

- 배포 저장소에 직접 커밋 금지. 이슈 · PR 은 이 저장소로
- 버전 변경은 `release: export:swift <version>` 커밋에서만 (gnam release 연동)
- 미구현: 배포 저장소 생성 · CI push (첫 배포 시점)

## conformance 실행기

- `swift test` 에 포함. 케이스 위치는 두 곳 중 먼저 있는 곳:
  1. 저장소 루트 `conformance/` (개발 저장소, `swift/` 의 부모)
  2. 패키지 `Tests/Conformance/` (배포 저장소, include 복사본)
- 케이스 파일 읽기 규칙은 `specs/conformance.md` '실행기' 와 같다 (suite 불일치 · id 중복 · 케이스 없음 = 실패). schema.json 검사는 TS 실행기만
- skip 은 suite 단위 사유 또는 케이스 id 단위. 현재 skip 없음

## core API

TS core (`specs/core.md`) 와 같은 규칙 · 같은 오류 code. 차이는 언어 표현만.

```text
JSONValue          null · bool · number(Double) · string · array · object. Codable · 리터럴 초기화
                   JSONValue(encoding: Encodable) · decode(as:) 로 앱 타입과 변환
ActionDef          description · input: JSONValue? (object schema) · confirm: Bool? · returns: ReturnType?
StateDef · ViewDef description (· schema: JSONValue?)
Manifest           version · actions · state · views. 구역은 등록 순서를 유지하는 이름 → 정의 목록
                   Manifest(json:) 는 검증 실패 시 InvalidManifestError. json 속성 = JSON 표현
validateManifest   (JSONValue) -> ValidationResult. 오류 path 는 TS 와 같은 문자열
toA2uiCatalog      (Manifest, catalogId:) throws -> JSONValue (A2UI v1.0 catalog)
AgentRuntime       @MainActor class. action · state · view 등록은 해제 함수 반환 (자기 등록만 해제),
                   같은 구역 같은 이름은 DuplicateNameError. manifest() · readState · subscribe · invoke
invoke             (name, args: JSONValue = {}) async -> InvokeResult. 검사 순서 TS 와 같음
                   NOT_FOUND → INVALID_ARGS → DENIED → EXECUTION_ERROR. run 이 throw = EXECUTION_ERROR
confirm            init(confirm:) 콜백 async throws -> Bool. 없음 · false · throw = DENIED
```

- `AgentRuntime` 이 `@MainActor` 인 이유: 액션 실행 함수 대부분이 SwiftUI 상태를 바꾼다
- 정적 manifest builder (TS `createManifestBuilder`) 대응 없음. Swift 는 런타임 등록만
