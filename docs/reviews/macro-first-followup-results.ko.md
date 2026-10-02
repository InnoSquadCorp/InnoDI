# InnoDI macro-first 후속 개선 결과

2026-10-02 범위 정정: 이 문서의 과거 whole-macro/composite-v2/whole-driver 수치는 root/member-attribute in-process driver에 한정된다. 전체 compiler expansion 또는 소비자 빌드 개선을 의미하지 않는다. [후속 실제 compiler 및 소비자 검증](macro-first-performance-track-2026-10-02.ko.md)을 함께 확인한다.

2026-10-01 UTC · 통합 기준 `8177f8d7c3b74822b181b1616d67fe1e2e6482a7` ·
로컬 branch `design/macro-first-followup`

## 결론

**두 가지 실제 사용 제한을 줄였다. 같은 rubric의 평가는 7.8 / CS 8.0 / DX 7.5다.**
1차 고정본은 7.7 / 8.0 / 7.4였고, 원본은 7.5 / 7.7 / 7.3이었다.
점수는 판단이며 속도·결함률·경쟁 우위를 측정한 수치가 아니다.

- 기존 `Overrides`를 `makeOwnedWithOverrides`에서 재사용할 수 있다
- 동기 Lazy/Provider 조합 때문에 owned 전환 전체가 막히던 제한을 완화했다
- 중복 이름 검사의 불필요한 shape 판정을 줄이는 작은 후보를 유지한다
- **Composite whole-driver 성능 gate는 실패했다. 전체 속도 개선 검증은 완료되지 않았다**

Macro-first, 기존 일반 initializer, 명시적 owner, 정적 graph/effect/cycle 검사와
compiler의 Sendable 검증을 유지했다. 런타임 registry나 값 type erasure를 추가하지 않았다.
모든 경쟁 제품보다 성능과 DX가 우수하다는 목표 달성을 선언할 근거는 아직 없다.

1차 ZIP/manifest/report는 그대로 보존한다. 이 문서는 후속 결과이며 1차의 실패 측정,
일반 getter 최적화 철회, 지원 범위와 미검증 조건을 지우지 않는다.

## 1. 사용자 API 변화

### 기존 override 묶음을 그대로 사용

```swift
// 이전: builder의 값을 각 named argument로 다시 전달
let owner = try await Services.makeOwned(seed: 1, api: preset.api, cache: preset.cache)

// 후속: 같은 Overrides 타입을 재사용
let owner = try await Services.makeOwnedWithOverrides(seed: 1) { $0 = preset }

// 직접 설정, optional nil, throwing preflight도 지원
let owner = try await Services.makeOwnedWithOverrides(seed: 1) {
    $0.api = mock
    $0.optionalValue = .some(nil)
    try checkOverrides($0)
}
await owner.close()
```

이미 취소된 Task에서는 사용자 builder closure도 실행하지 않는다. Closure가 throw하면
live factory, child, owned task를 만들지 않는다. 성공한 builder 값은 기존 direct factory
하나로 전달한다. 자동 effect 검증이나 자동 close를 추가한 것은 아니다.
기존 typed `Overrides` 값과 effect 요구사항 metadata는 실제 plugin에서 검증했다.
Apple 전용 `InnoDITesting` 전체 및 `DIOverridePreset.validated`를 포함한 전체 제품
통합 검증은 남아 있다.

처음 시도한 같은 이름의 overload는 거절했다. 동일한
`Parent.makeOwned { $0.service = 9 }`가 이전에는 child override였는데, 새 overload에서
parent override로 바뀌는 실제 실행을 발견했다. 결과가 parent/child `1/9`에서 `9/2`로
변했다. 별도 `makeOwnedWithOverrides` 이름을 사용해 기존 호출은 `1/9`를 유지하고
새 명시적 helper만 `9/2`가 되도록 회귀를 고정했다. 단순 label은 trailing closure에서
생략될 수 있어 충분하지 않았다. 새 이름의 직접 선언 충돌도 명확히 진단한다.

### 동기 지연 의존성을 같은 선언에서 유지

```swift
struct Feature { let request: InnoDI.Provider<Request> }

@DIContainer(generateOwned: true)
struct Services {
    @Input var client: Client
    @Provide(.shared, factory: { (request: InnoDI.Provider<Request>) in
        Feature(request: request)
    }) var feature: Feature
    @Provide(.transient, factory: { (client: Client) in Request(client) })
    var request: Request
}
```

1차 owned 경로는 이런 wrapper edge를 모두 거절했다. 후속은 별도 등록 DSL이나 수동
preparation graph 없이 기존 선언을 받아들인다. Lazy는 input 및 동기 shared/transient,
Provider는 동기 transient를 대상으로 삼는다. Lazy가 transient에 cache를 추가하지 않는다.

Typed local cell을 먼저 만들고 값을 저장하거나 resolver를 연결한 뒤 async 작업을
시작한다. Cell/resolver는 owner나 view 전체를 캡처하지 않는다. Forward reference,
override 우회, optional nil, 미해결/해결 후 자원 해제와 escaped handle을 실행 검증했다.
Close 이후 동기 handle은 계속 사용할 수 있으며 async owner-bound read는 닫힘을 확인한다.

Owned deferred cell은 non-Sendable이다. 일반 async factory 및 async 용도로 Sendable이어야
하는 on-demand factory가 이를 캡처하면 Swift가 거절한다. 이 경계를 unchecked conformance로
우회하지 않았다. MainActor async consumer의 적합한 조합은 실제 compiler/runtime에서 통과했다.

## 2. 최종 지원 범위

아래 실행 확인은 Swift 6.4/Linux의 실제 plugin과 portable production subset 기준이다.
Apple 전체 package 또는 최소 지원 compiler 검증으로 확대하지 않는다.

| 시나리오 | 후속 상태 | 중요한 경계 |
|---|---|---|
| Inputs, sync shared eager/on-demand, sync transient | 지원 | Sync getter는 close 후에도 사용 가능 |
| Async shared eager/on-demand | 기존 owned 계약 유지 | Read는 async throws, makeOwned는 readiness가 아니라 admission |
| Typed prepare/cancel/retry/status, shared close | 유지 | Cancel은 선택한 running scope만, 다중 선택 atomic 아님 |
| Overrides builder / throwing preflight | 새 helper 지원 | 기존 makeOwned의 child trailing closure 의미 유지 |
| Sync Lazy/Provider, forward 및 transient-only graph | 새 지원 | 소유권 cycle 및 eager 호출 금지 유지 |
| MainActor async consumer + sync deferred target | 적합한 조합 실행 통과 | Capture/result는 계속 compiler 검증 |
| Ordinary async / Sendable on-demand의 deferred cell 캡처 | 거절 | Unsafe 전송을 지원한다고 해석하면 안 됨 |
| Plain shared child | Borrowed 지원 | Parent close가 child를 adopt/close하지 않음 |
| Async transient, assisted, collection/multibinding | 미지원 | 기존 일반 container 경로는 유지 |
| Transient child, SwiftUI feature-root owned 통합 | 미지원 | 수명/host 계약 설계와 Apple 검증 필요 |
| Custom global actor, effectively generic container | 미지원 | 임의 actor 이름은 compiler 진단으로 실패할 수 있음 |
| Shared property의 Self.Value | 기존 legacy Overrides 제한 유지 | 현재는 nested Value 이름 사용 |
| Original nominal type/protocol/key-path 그대로 전달 | 자동 지원 안 함 | OwnedView는 별도 타입, consumer migration 필요 |

## 3. 성능 조사와 작은 후보

동일 driver로 원본6725, 1차 고정본, 후속을 계측했다. Model parse+validate의 비중은
이 진단에서 약 0.9–2.6%였다. 추가 계측에서 검증용 generated-source 재파싱만 약
16–17%였고, SwiftSyntax expansion 내부에도 큰 비용이 남았다. 중첩된 inclusive 시간을
합산하지 않았으며 이 driver 시간을 전체 app build 시간으로 취급하지 않는다.
따라서 큰 IR 추상화를 먼저 늘리지 않았다.

실제 source 기회는 `hasDuplicateManagedMemberName`이었다. 이름을 비교하기 전에
모든 형제의 전체 eligibility를 판정하고 있었다. 이름이 일치하는 형제에만 원래 판정을
호출하도록 조건 순서만 바꿨다. N개의 적합한 고유 이름에서는 비싼 판정이 N(N+1)회에서
2N회로 줄어든다. **단순 이름 순회는 여전히 quadratic**이며 전체 알고리즘이 linear가
되었다는 주장은 아니다. Eligibility에 진단 emit이나 이름 변경이 없음을 소스로 확인했고
원본 판정과 9,600개 비교가 일치했다.

### 비계측 paired whole-driver 결과

두 macro 구현을 같은 process의 동등한 별도 module로 두고, 변경 없는 Core/SwiftSyntax를
공유했다. 두 module의 정규화 flags, Swift 6 / Onone / strict / Werror, 정적 object link,
WMO·library evolution 비활성화를 확인했다. Product source 차이는 guard 순서 한 파일뿐이다.
각 lane 30 warmups 후 15개 ABBA/BAAB block, block당 lane별 2개 표본을 사용했다.
Output을 timing 종료 뒤까지 유지했고 전체 expansion text가 byte-identical임을 확인했다.

| Workload | Before median ms | After median ms | Ratio | Descriptive block interval | 사전 local gate |
|---|---:|---:|---:|---|---|
| Composite | 328.86 | 316.53 | 0.9625 | 0.8899–1.1253 | 상한 1.05 미통과 |
| 50-node chain | 2085.92 | 1987.64 | 0.9529 | 0.8893–1.0204 | 상한 및 point 목표 통과 |

**두 workload 모두 통과해야 하는 전체 gate는 실패했다.** Composite 초반 block의
변동이 컸지만 제외하지 않았다. 같은 process에서 block 간 상관이 남고 shared VM이므로
이 구간은 모집단 95% 보장이 아니다. 50-node의 관찰된 4.7% 차이를 전체 제품 또는 Apple
build 개선으로 일반화하지 않는다. 통과할 때까지 반복하지 않았다.

이 변경은 의미 동등성과 불필요한 연산 감소에 근거한 낮은 위험의 로컬 후보로 유지한다.
성능 승인 완료와 구분해 별도 patch로 제공하며, 향후 PR·배포 판단에도 실패 gate를 명시한다.
1차 보고서의 전체 test-image gate 실패 역시 이 실험으로 지워지지 않는다.

## 4. 같은 rubric 재평가

가중치와 0.5 단위 판단을 그대로 유지했다. 새로운 지원으로 줄어든 실제 사용 제약만
일상 DX에 반영한다. 성능 미승인 후보에 전체 속도 개선 점수를 부여하지 않는다.

| 항목 | 가중치 | 원본 | 1차 고정본 | 후속 |
|---|---:|---:|---:|---:|
| 알고리즘과 확장성 | 10 | 7.0 | 8.0 | 8.0 |
| 정적 그래프 검증 | 15 | 8.5 | 8.5 | 8.5 |
| 타입과 동시성 | 10 | 8.0 | 8.0 | 8.0 |
| 수명과 실패 모델 | 10 | 7.0 | 8.0 | 8.0 |
| 런타임 자원 설계 | 10 | 7.5 | 7.5 | 7.5 |
| 도입과 일상 사용 DX | 10 | 6.5 | 7.0 | 7.5 |
| 테스트와 override | 10 | 8.0 | 8.0 | 8.0 |
| SwiftUI 통합 | 5 | 8.5 | 8.5 | 8.5 |
| 빌드 반복 DX | 5 | 5.5 | 5.5 | 5.5 |
| 문서와 migration | 5 | 8.0 | 7.5 | 7.5 |
| 플랫폼과 유지보수 지속성 | 5 | 6.0 | 6.0 | 6.0 |
| 운영 가시성과 검증 도구 | 5 | 8.5 | 8.5 | 8.5 |

총점은 100, CS는 첫 5개 항목의 55, DX는 도입부터 문서까지의 35로 정규화한다.
후속은 총점 7.775, CS 8.045…, DX 7.5이므로 표시값은 **7.8 / 8.0 / 7.5**다.
Override 개선을 테스트 항목에도 중복 가산하지 않았다. 이는 기존 비교의 Factory 및
swift-dependencies와 비슷한 판단 범주일 뿐, 우월성이나 실사용 DX 우위를 증명하지 않는다.

## 5. 검증과 비교의 범위

- Strict focused core/macro: **616 tests / 47 suites 통과**
- 원본 duplicate predicate: **9,600 비교 일치**. 별도의 9,600 test function이 아님
- Actual plugin: 기존/owned 공존, builder, deferred runtime, public cross-module 통과
- Actual plugin negative canary: **21개 기대 진단 통과**, compiler stack dump도 실패로 처리
- Legacy async on-demand cell은 Apple `os`가 필요해 전체 legacy+owned 공존 경로가
  portable actual-plugin 검증에 포함되지는 않는다. 기존 owned-only compiler canary와 구분한다
- 1차의 runtime 64 tests 및 reentry subprocess 6개는 보존된 이전 증거다. 이번에는
  runtime source가 바뀌지 않았으며 그 숫자를 새 실행이라고 표시하지 않는다
- Source-only 독립 검토에서 확인된 추가 blocker는 없었다. 실행 증거와는 구분한다

Factory/Swinject/swift-dependencies/Needle의 고정 입력과 첫 20-node runtime 비교는
[1차 보고서](macro-first-results.ko.md)에 남아 있다. 이번 후속에서는 경쟁 runtime을 다시
측정하지 않았다. Ordinary getter/runtime도 그대로다. Needle runtime-only 수동 bridge의
cold/first 우위와 역할 차이를 유지한다. Typed-prewarm의 별도 dispatch 이득을 이번
guard 변경이나 일반 getter 이득과 섞지 않는다.

## 6. 남은 검증과 통합

- Apple 전체 package, SwiftUI, 전체 InnoDITesting 및 Swift 6.2·6.3 실행
- Intentional public API 변경의 Apple symbol-graph baseline 생성·검토
- 새 owned 조합의 supported-SDK consumer qualification과 실제 앱 migration 시간
- 안정된 runner의 whole build/compile 측정, 전체 binary 및 allocation/retained-heap 비교
- Assisted/collection/feature-root, custom actor, Self.Value 등 위 표의 미지원 범위
- 기존 F1 mock payload release-under-lock은 별도 정적 발견이며 이번에 수정했다고 하지 않음

6725→8177의 16개 변경 파일은 CI/문서였고 1차 144개 파일과 겹치지 않아 별도 worktree에
clean 적용했다. 새로운 CI와 API baseline을 통과한 것으로 해석하지 않는다. 특히 symbol-graph
baseline 갱신이 남아 있다. 기본 초기화 순서, 최소 지원 버전, product/import 이름은 유지했다.

두 DX 확장과 성능 후보는 로컬 patch 단위로 분리한다. 이전 ZIP/manifest는 불변이며
후속 raw 데이터, source/binary hash, 실패 초안, 실행 명령과 결과를 별도 evidence에 저장한다.
원격 PR·merge·release·설정 변경이나 사용자 컴퓨터 이관은 하지 않았다. 전체 B1–B6가
완성되었거나 출시 준비가 끝났다는 결론도 아니다.
