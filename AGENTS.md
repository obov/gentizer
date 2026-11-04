<!-- gnam:begin -->
<!-- gnam sync 가 생성. 이 블록 안은 직접 고치지 않는다 -->

## gnam (Git-Native Agent Memory)

파일에는 현재 상태, 커밋에는 상태가 변한 이유. 규약 원본 `.agents/skills/gnam/references/index.md`

```sh
git status
npx gnam status    # 설치 · 문제 · 인계 메모 · 요청 · plan 진행 · Blocking · 미결 (경로 · --json 으로 데이터)
```

```text
커밋 형식   제목 Conventional Commits + 메시지 끝 trailer 단락 (gnam.json format 2)
커밋 종류   docs(<topic>) + Gnam: spec.<topic>.plan · feat|fix(<topic>) + Gnam: spec.<topic>.impl · docs(<topic>) + Gnam: spec.<topic>.chore
            Gnam 없음 = spec 무관 (fix · chore · build · ci · docs · test …) · refactor:  (<topic> = specs/<topic>.md, feat 는 impl 만)
            format 1 저장소는 제목 접두 spec.<topic>.<kind>: (.agents/skills/gnam/references/commits/kinds.md 'format 1 대응')
작업 순서   spec 확인 → plan 커밋 (trailer Summary: 사람용 한 줄) → 한 단위 구현 → 검증 → impl 커밋 (trailer Plan: <plan hash> <단계>)
금지        공동 작성자 줄 · squash · plan.md 같은 별도 계획 파일
강제        commit-msg hook (.githooks) · CI 는 npx gnam verify
업그레이드  npx gnam outdated → 업그레이드 명령 실행 → 출력된 이전 항목 수행 (gnam link 도 업그레이드 직후 한 번 출력)
```

### 자율 진행 (사용자 확인 없음)

```text
진행        커밋 (plan · impl · chore · refactor) · 다음 plan 착수는 확인 없이 바로. 이 규칙이 상시 커밋 요청
            "커밋할까요" · "다음 plan 착수할까요" 로 턴을 끝내지 않는다. 다음 행동이 기록 · 다음 단계면 실행
보고        요구사항 진행 상태 (된 것 · 남은 것 · 필요한 판단). git 방법 · 커밋 목록은 요청 시만
질문        요구사항 판단 (미결: · Blocking) · git 예외만 (.agents/skills/gnam/references/agent-protocol.md '사용자 소통')
```

### lore (작업 노하우)

```text
시작      cat lore/README.md 후 적용 조건이 맞는 파일만 읽는다
형식      lore/<주제>.md 의 ## 항목마다 When: · Basis: 실측|경험칙 · Evidence:  (npx gnam verify 가 검사)
규약      .agents/skills/gnam-lore/references/lore.md
```

### release (버전 · 태그)

```text
release:    버전 변경 커밋. 'Package: <name> <version>' 절 = GitHub Release 본문. 대상 = gnam.json release.targets
            수준은 직전 release 이후 커밋 근거에서 계산, 호환성 깨짐은 plan · impl 본문 Breaking:
명령        npx gnam run release status | bump | publish <before> <sha> (CI)
규약        .agents/skills/gnam-release/references/release.md
판          format 1 전용 (format 2 + release plugin = 설정 오류). format 2 는 release-please (specs/commit-format.md)
```

### recall (과거 기록 검색)

```text
언제      단어가 기억나지 않는 결정 · 계획 · 노하우를 찾을 때. git log --grep 으로 안 걸리면 먼저
명령      npx gnam run recall search <query…> [--limit N]   커밋 · specs/ 절 · lore/ 항목, BM25 (한글 bigram)
결과      ref 만. 원문은 git show <hash> · <경로>:<줄>. superseded by <hash> = 대체된 plan → 대체한 plan 을 읽는다
```

### layout (폴더 구조)

```text
구조      .gnam/layout.json. 새 파일 · 폴더 전 npx gnam run layout where <경로>
경고      GNAM/layout/* 가 나오면 같은 작업 안에서 처리: 이동 (refactor:) 또는 구조 변경 (layout 커밋, 본문 Goal:)
변경      .gnam/layout.json 은 layout 커밋 (chore: … + Gnam: layout, format 1 제목 layout:) 에서만. 현재 트리 초안 = npx gnam run layout capture <폴더>
규약      .agents/skills/gnam-layout/references/layout.md
```

<!-- gnam:end -->
