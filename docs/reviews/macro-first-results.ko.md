# InnoDI macro-first 개선: 로컬 구현 결과와 재평가

2026-10-02 범위 정정: 이 문서의 과거 whole-macro/composite-v2/whole-driver 수치는 root/member-attribute in-process driver에 한정된다. 전체 compiler expansion 또는 소비자 빌드 개선을 의미하지 않는다. [후속 실제 compiler 및 소비자 검증](macro-first-performance-track-2026-10-02.ko.md)을 함께 확인한다.

2026-10-01 UTC · 기준 `6725e08b6da5d2ceeda61ed795adca5fadda564c` ·
로컬 branch `design/macro-first-semantic-foundation`

## 결론

**선택한 개선은 로컬 구현됐고, 원래 rubric의 현재 평가는 7.7 / CS 8.0 / DX 7.4다.**
원본은 7.5 / 7.7 / 7.3이었다. 판단 점수이며 통계적 우열이나 출시 품질 인증이 아니다.
macro-first 선언, 정적 graph/effect 검사, 명시적 ownership은 유지했다.
비교한 좁은 shared graph에서는 Factory/Swinject/swift-dependencies보다 낮은
resolution 비용을 관찰했지만, Needle runtime-only는 cold/first에서 더 빨랐다.
DX도 모든 대안보다 우수하다는 목표에 아직 도달했다고 판단하지 않는다.

이 문서는 로컬 선택안의 결과다. 전체 B1–B6가 모두 완성됐다는 뜻이 아니다.
Apple 전체 제품/Swift 6.2·6.3 검증, 실사용 migration 시간, 전체 build/heap 비교는
남아 있다. 원격 PR·merge·release나 플랫폼/지원 floor 변경은 하지 않았다.

## 개발자가 실제로 얻은 것

### 1. 기존 선언 순서를 유지하면서 선택적으로 의존성 순서로 초기화

```swift
@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
struct App {
    @Provide(.shared, factory: { (config: Config) in API(config) }) var api: API
    @Provide(.shared, factory: Config()) var config: Config
}
```

이 opt-in에서는 위 선언을 옮기지 않아도 된다. 기본값은 기존 declaration order다.
독립 node는 source index로 정렬하고 sync/async stage는 구분한다. Source parameter,
override, diagnostic, child 및 ownership edge 순서는 별도 계약을 유지한다.
Factory 부수효과 순서가 달라질 수 있으므로 자동 migration이나 기본값 변경은 없다.

### 2. 잘못된 prewarm 선택을 컴파일 시점에 수정

```swift
// 원본: 임의의 key path가 컴파일되고 잘못된 대상은 runtime throw
try container.prewarm(\.service)
// 후보: sync on-demand shared provider에만 case가 생성됨
container.prewarm(.service)
```

별도 registration은 없다. Empty call은 nonthrowing no-op이고 선택 순서/identity/
isolation을 유지한다. Dynamic/generic `PartialKeyPath` adapter는 token 또는 명시적
warming closure로 옮겨야 한다. 자동 변환기는 구현하지 않았다. 명시적 타입 표기는
`Container._InnoDIPrewarmProvider`로 길다. 짧은 일반 이름을 도입했다가 사용자 payload
타입을 가리는 실제 compiler 문제가 있어 reserved namespace를 선택했다.

### 3. 같은 선언에서 async 수명은 명시적인 owner로 제어

```swift
@DIContainer(generateOwned: true)
struct Services {
    @Provide(.shared, asyncFactory: { () async in await loadSession() })
    var session: Session
    @Provide(.shared, factory: Cache()) var cache: Cache
    @Provide(.transient, factory: { (cache: Cache) in ViewModel(cache) })
    var viewModel: ViewModel
}

let owner = try await Services.makeOwned()
let report = try await owner.prepare(.session)
let session = try await owner.container.session
let first = owner.container.viewModel
let second = owner.container.viewModel
await owner.cancel(.session)
let retry = try await owner.retry(.session)
await owner.close()
```

- 원본에 동일한 macro-managed prepare/cancel/retry/close 경로가 없었다. 수동 scope,
  provider ID, preparation node/edge 작성이 필요했던 경로를 생성한다
- makeOwned 반환은 readiness가 아니라 setup/admission이다. prepare report를 검사한다
- cancel은 선택된 running scope에만 영향을 주고 ready 값과 관련 없는 작업은 유지한다
  cancelled scope는 explicit retry가 필요하고 close와 다르다
- close는 async admission을 먼저 닫고 모든 close caller가 같은 teardown 완료를 기다린다
  취소를 무시하는 사용자 작업을 drain하거나 이미 반환된 값을 무효화하지는 않는다
- 동기 shared/transient getter는 close 뒤에도 사용 가능하다. Transient는 매 접근 factory를
  실행하며 결과를 cache하지 않는다. 직접 value override는 동일 값을 재사용한다. transient token/task는 없다
- 복사된 owner/view는 같은 scope를 공유한다. 일반 shared child는 borrowed이며 닫지 않는다
- owned async getter는 factory가 nonthrowing이어도 lifecycle 오류 때문에 async throws다

OwnedView는 기존 Services nominal type과 다르다. 기존 타입의 protocol conformance,
custom method, key path를 그대로 소비하는 코드에는 migration이 필요하다. 서비스를
직접 주입하거나 별도 view 타입을 받도록 바꿔야 한다. `makeOwned`의 builder-override
convenience는 아직 없고 직접 value/child override는 지원한다.

## 아키텍처 결정과 남은 범위

| 트랙 | 현재 결정 | 이유/제한 |
|---|---|---|
| B1 async lifetime | 명시적 makeOwned 경로 구현 | 사용자 선택. 일반 initializer 비용·수명을 바꾸지 않음 |
| B2 declaration/init order | stable opt-in 구현 | 부수효과 기본값 변경을 강제하지 않음 |
| B3 semantic foundation | immutable availability index와 공용 stable-order helper 구현 | 전체 parser/IR 통합은 하지 않음. 내부 추상화 수를 성과로 세지 않음 |
| B4 typed identity/plan | generated typed prewarm/owned selections 및 concrete scopes 구현 | 내부 lifecycle plan의 문자열 ID는 값 lookup service locator가 아님. 기존 수동 API도 남음 |
| B5 isolation | caller/MainActor 지원, custom actor 확장 미채택 | 전체 supported compiler witness가 필요. Actor 접미사 없는 attribute는 compiler diagnostic으로 실패할 수 있음 |
| B6 runtime product split | 미채택 | 현재 VM의 subset 크기만으로 전체 product/build 이득을 입증할 수 없음. 새 module/ABI/import migration을 정당화하지 못함 |

Owned 경로의 지원표:

| 선언/동작 | 상태 |
|---|---|
| input, sync shared eager/on-demand | 지원 |
| async shared eager/on-demand | 구현; Linux actual-plugin 전체 공존은 eager, Apple legacy on-demand 전체 검증은 남음 |
| sync transient 및 transient diamond | 지원; 매 접근, override short circuit, close 후 사용 회귀 통과 |
| MainActor 및 caller-nonsending | portable positive/negative compiler 검증 |
| plain shared child | borrowed; direct/closure override 지원 |
| async transient, assisted, Lazy/Provider, collection, transient/feature-root child | owner 경로 미지원; ordinary API 계약은 유지 |
| effectively generic container | 기존처럼 미지원 |
| shared property의 Self.Value | 기존 nested Overrides 제한 유지; nested Value 표기를 사용 |

## 성능: 달라진 원인과 비교 범위를 구분

자세한 7-lane 수치와 방법은 [고정 611-test checkpoint](macro-first-checkpoint-611.ko.md)에
있다. sync-transient 확장 뒤 ordinary 20-node consumer를 다시 export해 측정된 AST와
byte-for-byte 동일함을 확인했다. 측정된 V4 runtime은 추가 수명 통제 뒤 미채택했다. 최종 cell source는 원본과 동일하다.

- immutable index는 O(N) 구축 후 expected O(1) edge lookup이다. 4,681 declaration
  sequence의 기존 동등성을 확인했다. syntax-free dense N=200은 426.67→0.63ms였으나
  이것을 app speedup이나 전체 compiler speedup으로 표현하지 않는다
- whole-macro 초기 결과는 median ratio 0.984/1.002였다. 그러나 row-level bootstrap이
  block 내 상관을 무시했다. 3-block 재계산 상한은 1.1565/1.0504이므로 **기존 5% gate
  통과 주장을 철회한다**. 현재 whole-macro 회귀 없음은 미입증이다
- 미채택 V4 ready cell은 같은 lock/state machine에서 불필요한 registration만 생략한다.
  원본→후보 warm 222.7→155.0ns, first 8.71→8.77µs, cold lifecycle 21.65→19.60µs를
  관찰했으나 추가 통제 측정에서 cold/first 우려가 남아 제외했다. 최종 구현의
  일반 getter 속도 개선 수치로 사용하면 안 된다
- typed prewarm은 양쪽 모두 동일한 원본 runtime을 링크했다. ready leaf 선택
  1,277.7→218.2ns, ready 20개 선택 27.26→4.70µs였다. first 준비는 10.08→9.53µs이나
  변동이 커 개선 단정하지 않는다
- Needle runtime-only는 warm 154.2ns, cold 14.69µs, first 6.14µs였다. 수동 bootstrap
  bridge가 필요했고 generator는 ObjC Foundation header 부재로 이 VM에서 실패했다

모든 runtime lane은 동일한 20-node construction/identity/independent root/override/
release oracle을 통과했다. Runtime과 consumer는 별도 package/module, -O+WMO,
CMO/library evolution off, static object linking 조건을 기록했다. Needle/OpenCombine
upstream은 language mode 5, consumer는 6이다. InnoDI는 actual AST+portable runtime
subset이며 Apple 전체 package 비용을 비교한 것이 아니다. swift-dependencies의
fresh-root lane은 independent-root 요구에 맞춘 public fresh-cache adapter를 썼다.

ELF debug-stripped 크기와 Linux process peak RSS는 기록했지만 retained heap,
allocation count, iOS binary, process cold startup, 전체 cold/warm build는 미측정이다.
특히 전체 제품 메모리·빌드 우위를 그 수치로 주장하지 않는다.

## DX 비교: 선언량은 사용성 전체가 아니다

동일 20-node fixture의 authored wiring+adapter만 집계했다. 공통 Node/counter/측정
코드는 제외하고 InnoDI 생성 코드는 제외했다. Comments/blank를 제외한 줄 수와
원문 UTF-8 크기다. Formatting에 의존하므로 점수 공식에 넣지 않는다.

| Lane | authored lines | bytes | 해석 제한 |
|---|---:|---:|---|
| InnoDI 원본/후보 | 26 / 26 | 3,562 / 3,562 | 분석 최적화가 사용자 선언량을 줄였다는 주장 없음 |
| Factory | 33 | 2,729 | 더 짧은 전체 표현 크기, runtime registration |
| Swinject | 33 | 3,960 | container-scoped synchronized resolver와 named registrations |
| swift-dependencies | 183 | 7,292 | object-graph 역할을 강제한 fixture; 일반 effect DX 순위로 사용 금지 |
| Needle runtime-only | 43 | 2,991 | manual bridge 포함. 실제 generator UX 아님 |

그래서 별도의 native effect/override 시나리오도 실행했다.
swift-dependencies는 @Dependency와 withDependencies로 captured context, inherited Task,
parallel override isolation을 통과했다. InnoDI는 구체 dependency의 explicit capture와
독립 container override로 같은 관찰값을 통과했다. Business type+feature 선언만 보면
InnoDI 12 lines/343B, Dependencies 18 lines/493B지만, task-local 전달을 별도 인자로
적지 않아도 되는 후자의 기능과 explicit wiring이 보이는 전자의 성격은 다르다.
이 두 구현은 같은 ownership/effect semantics의 performance 비교가 아니다.

| 사용자 작업 | 원본 대비 변화 | 실제 증거/남은 비용 |
|---|---|---|
| forward shared 선언 수정 | property 이동 대신 option+명시적 정책 선택 | compiler/macro 회귀; 실제 사용자 수정 시간 미측정 |
| 잘못된 prewarm 대상 | runtime throw에서 compile-time case/type 오류 | wrong container/actor/provider negative fixtures |
| async provider rename/prepare | 직접 ID/edge 문자열 작성 제거 | generated typed token. IDE rename 실제 사용자 실험 미실행 |
| shared+transient owner graph | 초기 owner prototype의 전면 거절 제거 | 실제 plugin per-read/diamond/override/copy lifetime oracle |
| test override | 일반 API 그대로, owned async seed ready | live factory 미시작·dependency edge 제거 회귀 |
| migration | prewarm literal은 단순 변경, dynamic keypath/view nominal은 수동 | 자동 semantic migrator 없음, zero-cost migration 아님 |

Factory와 swift-dependencies가 일상 설정/효과 테스트에서 가진 편의성을 InnoDI가
모두 능가한다고 보지 않는다. invalid graph/effect 진단은 정적 macro path의 강점이며,
Needle의 compile-time generator 경로는 현재 VM에서 같은 방법으로 검증하지 못했다.

## 재평가와 검증

[고정 체크포인트](macro-first-checkpoint-611.ko.md)의 12개 항목, 같은 가중치와 0.5 단위
판단을 유지한다. sync-transient 지원으로 대표 graph의 중요한 거절은 없어졌지만
주요 미지원 형태, nominal-view migration, actor diagnostic 한계, 전체 build gate의
불확실성이 남아 대부분의 세부 점수는 유지한다. 일반 getter 최적화 미채택으로
runtime 자원 항목은 8.0에서 원래 7.5로 되돌린다.
나머지 항목은 유지하며 결과는 **7.7 / CS 8.0 / DX 7.4**다.

- focused core/macro: 613 tests / 46 suites strict 통과. Full repository suite 아님
- portable runtime: 64 tests / 10 suites strict 통과
- reentry subprocess: factory/capture-deinit/trace × debug/release 6개 기대 trap
- actual plugin: mixed/legacy+owned/public module/coexistence 및 negative canary 통과
- native effect override: 두 authoring 모델의 parallel/task capture oracle 통과
- README/DocC localized structure와 local link 검증 통과
- 최신 독립 source review는 확인된 차단 회귀를 찾지 못했다. Forward transient +
  Type.self/with: + optional nil override 보강도 실제 plugin에서 통과했다. 원본 cell
  복원 후에도 613/64 tests, actual plugin 및 6개 재진입 trap을 모두 재확인했다

중간 실패도 기록했다. 잘못된 cancellation pause, token name shadowing, Self nominal
재작성, deinit reentry bypass, 추가 overload 비용, cold-regressing 두 runtime 초안은
수정/거절했다. F1 mock payload release-under-lock은 원본의 별도 정적 발견이며 이
트랙에서 수정·실행 확인했다고 주장하지 않는다. 다른 DI48/DI49 작업은 건드리지 않았다.

재현 entrypoint는 `Tools/ConsumerComparison/`,
`Tools/validate-owned-portable-plugin.sh`, `Tools/validate-ready-cell-portable.sh`다.
설계/변경별 gate는 [plan](../plans/macro-first-next-major.md), 정정 이력과 상세 근거는
[evidence ledger](macro-first-local-evidence.md)에 있다. 원시 측정·build flags·source/binary
hash·실패 로그는 로컬 evidence package에 보존한다. 다음 단계는 남은 미지원 형태를
무조건 추가하는 것이 아니라 검토 결과와 실제 consumer의 필요에 따라 결정한다.


## 비교 입력 고정

아래 공식 repository revision의 source를 수정하지 않고 사용했다. Dependency
resolution의 하위 pin과 실제 compile/link flags는 evidence package에 함께 있다.

- [InnoDI 기준](https://github.com/InnoSquadCorp/InnoDI/tree/6725e08b6da5d2ceeda61ed795adca5fadda564c)
- [Factory 3.4.1](https://github.com/hmlongco/Factory/tree/39d340fbfc4eb79a8981e9166083cda011a6b3f8)
- [Swinject 2.10.0](https://github.com/Swinject/Swinject/tree/b685b549fe4d8ae265fc7a2f27d0789720425d69)
- [swift-dependencies 1.17.1](https://github.com/pointfreeco/swift-dependencies/tree/b476cc5761057d8d857de063fe7ac8daecf5c06b)
- [Needle 0.25.1](https://github.com/uber/needle/tree/69f7a889d2736f2621c6083ac29e0a75d158f249)


## 고정 후보 15-block whole-macro 추가 측정

613-test frozen executable을 사용해 각 버전 15개 process block × 2 measured rows,
process마다 30 warmups를 실행했다. 원본 median은 290.3885ms, 후보는 304.3915ms,
ratio는 1.04822였다. 10,000 paired whole-block resamples(seed 6725)의 descriptive
interval은 0.99669–1.10811로 **사전 정의한 상한 1.05 gate를 통과하지 못했다**.
Shared VM에서 이것을 확정적 4.82% 제품 회귀라고 단정하지 않지만, 5% 이내 회귀
없음이나 전체 macro 속도 개선이 입증되었다고도 말할 수 없다.

두 test executable은 테스트가 추가되어 85,260,696B / 89,269,672B로 다르다.
같은 benchmark 함수를 filter하더라도 static test-image 구성이 잠재 confound다.
제품 source 차이만 남기고 driver/TestSupport를 같게 둔 최소 test-target 비교를
한 번 실행했다. 아래 통제 실험의 통과는 위 full test-image 실패 결과나 실사용
회귀 우려를 지우지 않는다. 통과할 때까지 반복하지 않았다. Raw/runner hashes와
사전 protocol은 `final-macro-15-blocks`에 그대로 보존한다.


## Runtime 수명 통제와 ready-cell 최적화 미채택

첫 resolve용 root 배열을 timing 이후까지 `withExtendedLifetime`으로 유지했다.
기존 측정에 teardown이 실제 섞였다는 결함 판정이 아니라 ARC 배치의 불확실성을
제거한 통제다. 같은 3 blocks ×10 samples에서 원본은 cold 20.38µs / first 9.03µs /
warm 225.7ns, V4는 25.80µs / 10.36µs /191.2ns였다. 후보 마지막 block은 전 지표가
크게 느려 shared-VM 영향도 의심되지만, 첫 block 역시 cold/first가 약 33% 느렸다.
이 결과로 cold 회귀가 없다고 판단할 수 없다.

따라서 **일반 ready getter 최적화는 채택하지 않고 원본 cell을 복원했다**.
앞서 관찰한 223→155ns는 작업 중 V4 후보의 결과이며 최종 코드의 개선 수치가 아니다.
Warm 이득만으로 cold 우려를 덮지 않는다. 통제 실행의 7-lane raw/flags/hashes는
`consumer-measurements-lifetime` / `consumer-module-boundaries-lifetime`에 보존했고,
기존 V4 및 실패 초안들도 남긴다. Typed-prewarm만의 측정은 양쪽 동일 원본 runtime을
사용했으므로 이 제외와 무관한 별도 dispatch 결과다.


## 동일 driver 최소 macro harness: 한 번의 confound 통제

Unrelated test-image 구성을 줄이고 benchmark와 7개 TestSupport 파일을 byte-identical로
맞췄다. 두 버전 모두 같은 33-module set, 정규화된 compiler flags, source SwiftSyntax
604, native backend, prebuilts 비활성화, Debug/strict/Werror를 사용했다. 제품 source는
각 revision 그대로다. Driver hash는 `13937195e434a248bc67acc95a77d983d0d705ab2c246bda3cd6cd06a025e38f`다.

| 같은 15-block protocol | 원본 median ms | 후보 median ms | ratio | descriptive block interval | 정의된 local gate |
|---|---:|---:|---:|---|---|
| 전체 test image, 같은 함수 filter | 290.39 | 304.39 | 1.0482 | 0.9967–1.1081 | 실패 |
| 동일 minimal driver image | 317.23 | 292.78 | 0.9229 | 0.8338–0.9662 | 이 통제에서 통과 |

최소 image의 baseline block medians도 284.7–630.7ms로 크게 흔들렸다. 따라서 이것을
일반적인 7.7% 개선, binary 크기가 이전 실패의 원인이라는 증명, 전체 compile-time
회귀 우려의 해소로 해석하지 않는다. 두 실험 모두 그대로 보고한다. Apple/실사용
build 및 더 안정된 runner에서의 확인이 남는다. 원시 결과는
`final-macro-minimal-15-blocks`, 빌드·source 검증은 `controlled-macro-minimal-v2`에 있다.

## 최종 ordinary-runtime 비교 기준

최종 cell은 원본과 byte-identical하므로 아래에서는 실제 측정한 **원본 runtime lane**을
기준으로 둔다. V4를 제거한 전체 최종 consumer binary의 별도 timing을 새로 만들었다고
주장하지 않는다. 생성된 ordinary getter/constructor 경로도 그대로이고, typed prewarm의
별도 메서드 변화는 위 분리 실험으로 본다. 아래는 lifetime-control 실행의 median이다.

| Lane | cold lifecycle µs | first resolve µs | ready resolve ns |
|---|---:|---:|---:|
| InnoDI 원본 runtime 기준 | 20.38 | 9.03 | 225.7 |
| Factory | 71.19 | 105.05 | 1,245.0 |
| Swinject synchronized | 64.60 | 30.04 | 1,693.1 |
| swift-dependencies fresh-root adapter | 108.87 | 54.01 | 746.8 |
| Needle runtime-only manual bridge | 17.24 | 7.11 | 204.4 |
| serial Swift lazy control | 4.92 | 1.58 | 28.5 |

관찰된 차이는 이 구성/수명/workload에 한정된다. Factory의 첫-resolve와 lifecycle은
다른 batch/보유 root 수를 사용하므로 서로 빼서 setup 비용을 구하면 안 된다.
메모리/전체 build/async owner 경쟁 성능이나 보편적 DX 우위로 확장하지 않는다.


## 최종 source와 측정 binary의 대응

측정 이후 채택한 product-source 차이는 두 가지다.
1. 미채택 V4 cell을 원본으로 복원했다. 이후 64 runtime tests, 613 focused tests,
   real plugin 및 6개 재진입 subprocess를 다시 통과했다
2. Owned sync-transient codegen에서 computed `model.transientMembers`를 loop마다
   재계산하던 T×N scan을 한 번의 배열 projection으로 줄였다. 실제 plugin의 전체
   positive fixture expansion은 수정 전후 byte-identical이며 SHA-256은
   `939e652641a75a3ab110699e64b892b5913152b18d3de7cf72ff86bd6e758c39`다.
   수정 뒤 strict 613 tests 및 actual plugin 검증을 다시 통과했다

Whole-macro benchmark의 fixture는 generateOwned를 켜지 않아 두 번째 경로를 실행하지
않으며 runtime cell도 benchmark 모듈에 포함하지 않는다. 그래도 측정 executable이
최종 source에서 재빌드된 것이라고 표시하지 않는다. 측정은 반복하지 않았다.
최종 source/tree/patch와 측정 binary의 hash는 별도 delivery manifest에 구분한다.
