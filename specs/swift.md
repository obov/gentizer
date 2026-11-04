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

- swift-tools-version 6.0, 플랫폼 iOS 16 · macOS 13 이상
- 라이브러리 product `Gentizer` 하나. SwiftUI 바인딩 · AG-UI 어댑터는 별도 target (이후 plan)
- 빌드 산출물 `swift/.build/` 은 git 무시

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
- skip 은 suite 단위 사유 또는 케이스 id 단위. 미구현: Swift core (전체 suite skip)
