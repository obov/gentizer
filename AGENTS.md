<!-- gnam:begin -->
<!-- gnam sync 가 생성. 이 블록 안은 직접 고치지 않는다 -->

## gnam (Git-Native Agent Memory)

파일에는 현재 상태, 커밋에는 상태가 변한 이유. 규약 원본 `.agents/skills/gnam/references/index.md`

```sh
git status
npx gnam status    # 설치 · 문제 · 인계 메모 · 요청 · plan 진행 · Blocking · 미결 (경로 · --json 으로 데이터)
```

```text
커밋 종류   chore: · refactor: · spec.<topic>.plan: · spec.<topic>.impl: · spec.<topic>.chore:  (<topic> = specs/<topic>.md)
작업 순서   spec 확인 → plan 커밋 → 한 단위 구현 → 검증 → impl 커밋 (본문 첫 줄 Plan: <plan hash> <단계>)
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
```

### recall (과거 기록 검색)

```text
언제      단어가 기억나지 않는 결정 · 계획 · 노하우를 찾을 때. git log --grep 으로 안 걸리면 먼저
명령      npx gnam run recall search <query…> [--limit N]   커밋 · specs/ 절 · lore/ 항목, BM25 (한글 bigram)
결과      ref 만. 원문은 git show <hash> · <경로>:<줄>. superseded by <hash> = 대체된 plan → 대체한 plan 을 읽는다
```

<!-- gnam:end -->
