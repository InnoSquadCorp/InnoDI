# InnoDI macro first 성능 개선 단계 최종 검증

2026-10-02 UTC · 기준 commit `8177f8d7c3b74822b181b1616d67fe1e2e6482a7`

## 결론

이번 단계에서 검토한 **추가 성능 후보 3개는 모두 미채택**했다. 마지막 후보는 반복
접근을 빠르게 만들었지만 첫 접근 비용을 높였다. 세 후보의 코드 변경을 모두 되돌렸고,
기존에 구현한 macro-first 기능 체크포인트를 유지한다. 신규 정확성 테스트 2개와
이번 측정의 근거 및 한계 설명을 추가했다. commit, push, PR 생성, merge는 하지 않았다.

같은 12항목 rubric 평가는 **7.8 / CS 8.0 / DX 7.5로 유지**한다. 원본 평가는
7.5 / 7.7 / 7.3, 1차 체크포인트는 7.7 / 8.0 / 7.4였다. 이 점수는 설계와 사용성에
대한 판단이며, 보편적인 성능 우위나 출시 적합성을 수치로 증명한 것이 아니다.

## 유지한 구현과 복구 상태

두 원본 ZIP의 SHA256을 확인하고 checkpoint 2의 모든 patch를 순서대로 적용했다.
각 중간 tree와 최종 `d3b0b040097fb847f3329ea1ee50c24fb98786f6`가 일치했다.
과거에 gate를 통과하지 못한 선택적 guard-order patch 03은 제외했다.
실제 비교 기준 tree는 `1573ae35738446fd1bff6d768f32471b52fa71ab`이다.

- 정적 availability index, 선택적 dependency-order 초기화, typed prewarm 유지
- `makeOwned`의 명시적 prepare/cancel/retry/close 경계와 일반 initializer 유지
- override seed pruning, borrowed child, 별도 `makeOwnedWithOverrides` 유지
- 동기 Lazy/Provider의 typed forwarding 유지
- 새 registry, service locator, 전역 service cache, reflection 경로 또는
  unchecked Sendable 우회는 추가하지 않음

최종 `Sources/`의 208개 파일, 그중 Swift 141개는 비교 기준의 파일과 바이트 단위로
일치한다. 추가 성능 구현이 남아 있지 않다는 뜻이며, 전체 worktree가 원격 main과
같다는 뜻은 아니다. 이전 기능 체크포인트와 신규 테스트 및 문서의 의도된 차이는 남아 있다.

## 측정 기반의 범위 정정

과거 보고서의 `whole-macro`, `composite-v2`, `whole-driver` 수치는 단일 pass
`MacroAssertions`의 **root/member-attribute in-process driver**로 해석해야 한다.
생성된 `_InnoDIProvideAccessor` 역할이 남는 출력은 전체 compiler macro expansion이나
소비자 typecheck 완료를 의미하지 않는다. 그 수치만으로 전체 빌드 개선을 주장하지 않는다.

이번에는 실제 compiler plugin을 빌드하고 input, eager, on-demand, transient diamond,
owned mixed의 5개 fixture에서 **217개 macro role 출력**을 모두 소비했다. 선언 위치에
accessor/peer/member 출력을 재구성한 소스를 plugin 없이 typecheck, compile, 실행해
결과를 확인했다. 별도의 동일 20-node 소비자에서도 실제 plugin의 85개 role과
재구성 소스 양쪽이 lifetime/override oracle을 통과했다. 이는 제한된 fixture 검증이며
일반적인 Swift 소스 변환기나 전체 Apple package 검증이 아니다.

## 후보별 결과와 채택 판단

아래 ratio는 candidate/baseline이다. 1보다 작으면 시간이 짧다. 구간은 사전 정의한
paired chronological block bootstrap의 95% 구간이며, VM에서의 관측을 기술한다.
서로 다른 설정의 절대 시간을 직접 이어 붙이지 않았다. Runtime 시간은 process별 batch-mean
sample의 median을 구한 뒤 paired ratio의 geometric mean으로 요약한다. 개별 호출의
percentile이 아니다. Cold는 process/oracle warmup 이후 새 root의 생성·첫 resolve·해제이며,
cold process startup을 의미하지 않는다.

### Optional type을 typed AST로 구성

기존 lexical grouping 조건을 유지하면서 반복적인 type 문자열 재파싱을 줄였다.
40개 type spelling oracle, 실제 compiler dump와 확장 소스의 동일성을 확인했다.

| 실제 소비자 지표 | Ratio | 95% 구간 |
|---|---:|---:|
| 단일 파일 typecheck | 0.9772 | 0.9498–1.0014 |
| 단일 파일 compile 및 link | 1.0002 | 0.9798–1.0252 |
| SwiftPM leaf source 수정 후 소비자 module 재빌드 | 1.0147 | 0.9600–1.0723 |

**소비자 빌드 이득을 입증하지 못해 미채택**했다. SwiftPM 수정은 실제로 소비자 파일
3개를 재컴파일했다. 한 파일만 컴파일한 결과로 표현하지 않는다. No-op control은
production module을 재컴파일하지 않았다.

단일 파일 lane은 사전 빌드된 debug plugin/runtime과 warmed module cache를 사용했다.
소비자 `-O`가 plugin의 release 빌드를 의미하지 않는다. SwiftPM lane도 준비된 의존성을
사용한 debug incremental 측정이다. Cold full-package build, release plugin의 결과는 아니다.

### Trace owner handle 축소

immutable context/generation/container ID를 기존 enabled State로 옮겼다. 이 Linux
x86_64 빌드에서 handle은 88→8 bytes였고, 20-node on-demand root는 168 bytes로 같았다.

5,000개 root를 유지한 whole-process 경계에서 private-dirty resident memory의
**paired mean 감소량**은 아래와 같았다. Enabled State와 공유 bounded sink/buffer도
경계 안에 있다.

| Tracing | Root 상태 | 감소량 KiB | 감소량 MiB |
|---|---|---:|---:|
| Off | Unresolved | 7,813.3 | 7.630 |
| Off | Resolved | 7,812.7 | 7.629 |
| On | Unresolved | 7,426.0 | 7.252 |
| On | Resolved | 7,423.3 | 7.249 |

이는 process-resident 측정이다. 정확한 live allocated heap이나 allocation 횟수는
측정하지 않았으며, 작은 handle 크기만으로 전체 메모리 이득을 추론하지 않았다.

| Tracing off 지표 | Ratio | 95% 구간 |
|---|---:|---:|
| Cold root 생성과 첫 resolve 및 해제 | 0.9547 | 0.8732–1.0420 |
| 첫 resolve | 1.1358 | 0.9986–1.4099 |
| 반복 resolve | 0.9820 | 0.8880–1.0781 |

시간 구간이 넓어 필요한 이득과 비열화 조건을 입증하지 못했다. 첫 resolve의 13.6%
point estimate를 확정된 회귀로 표현하지 않는다. **메모리 결과가 latency gate를
대신할 수 없어 미채택**했고 코드를 되돌렸다.

### 완료된 untraced ready read의 bookkeeping 생략

동일 lock 안에서 tracing off, active caller 없음, ready 상태를 모두 만족할 때만
값을 반환했다. 새 cache나 stored field는 없다. Factory, waiter, unwind와 tracing
경로는 기존 caller guard를 유지했다. 짧은 gprofng 진단에서 관련 value/defer, Set,
Thread.current, ARC 경로가 관측됐지만 33개 PC 관측뿐이므로 비중이나 개선 예측에 쓰지 않았다.

양쪽을 동일 CPU 8에 배치한 새 설정에서 16 paired timing blocks와 process당 30개
sample을 사용했다. 공유 VM을 전용 성능 장비로 간주하지 않았다.

| 지표 | Ratio | 95% 구간 | 판단 |
|---|---:|---:|---|
| Tracing off cold lifecycle | 1.0455 | 1.0346–1.0566 | 95% 구간 상한이 +5% 초과 |
| Tracing off 첫 resolve | 1.1005 | 1.0763–1.1228 | 회귀 확인 |
| Tracing off 반복 resolve | 0.6330 | 0.6232–0.6467 | 개선 확인 |
| Tracing on cold lifecycle | 1.0111 | 0.9955–1.0302 | 비열화 gate 통과 |
| Tracing on 첫 resolve | 1.0046 | 0.9946–1.0139 | 비열화 gate 통과 |
| Tracing on 반복 resolve | 1.0077 | 0.9980–1.0205 | 비열화 gate 통과 |
| 변경 없는 sink record control | 0.9987 | 0.9852–1.0170 | drift gate 통과 |

반복 접근 시간은 약 36.7% 감소했지만 첫 접근 시간은 약 10.0%, cold lifecycle 시간은
약 4.5% 증가했다. 메모리-neutral 조건과 tracing 조건을 통과해도 첫 접근 회귀를 상쇄하지 않는다.
**미채택 후 원복**했고 이번 단계의 후보 탐색을 종료했다.

## 정확성 및 API 검증

- 복구 baseline macro/core focused tests: 615 tests / 46 suites 통과
- 미채택 typed-wrapper와 추가 40-case oracle: 616 tests / 47 suites 통과
- 최종 유지 runtime과 각 runtime 후보: 73 tests / 11 suites 통과
- Factory, factory-capture release/deinit, trace 재진입: debug/release 6개 subprocess가
  지정된 진단으로 종료하고 timeout 없이 통과
- Actual-plugin positive/owned-deferred/public-client 실행과 21개 지정된 negative 진단 통과
- Portable Linux module의 public symbol/signature 591개 동일성 확인
- 새 trace identity 테스트는 copied-owner, generation/mapped ID, 명시적 old span,
  sink lifetime, same-owner reentry, concurrent copy와 failure/cancel/wait 순서를 확인

Mutex 기반 추가 테스트는 최신 Apple OS availability를 각 test 함수에 지정했다.
이 추가 범위를 macOS 14/iOS 17 deployment-floor 검증으로 계산하지 않는다.
Swift Testing의 suite 자체에는 availability를 붙일 수 없어 각 함수에 지정했다.
[Swift Testing의 suite availability 규칙](https://docs.swift.org/latest/documentation/testing/organizingtests/)

## 같은 rubric 재평가

이전의 12개 항목, 가중치와 0.5 단위 판단을 유지한다. 채택된 기능이 추가로 바뀌지
않았으므로 각 항목을 올리지 않는다. 총점 7.775, CS 8.045…, DX 7.5이며 표시값은
**7.8 / CS 8.0 / DX 7.5**다. 런타임 자원 항목 7.5, 빌드 반복 DX 5.5도 유지한다.
기능/DX 개선이 보편적인 performance win이라는 해석은 이번 근거에서 더 좁혔다.

Factory 3.4.1, Swinject 2.10.0, Needle v0.25.1, swift-dependencies 1.17.1의 정확한
기존 revision과 같은 workload source는 복구했다. **이번 단계에서 경쟁 제품의 새
head-to-head 실행은 하지 않았다.** 이전 숫자는 역사적 자료로만 남긴다. Needle은
여전히 handwritten runtime lane과 공식 generator 검증을 구분해야 한다.
모든 경쟁 제품보다 빠르거나 DX가 우수하다는 결론은 없다.

## 남은 실제 경계

1. 승인된 Apple 환경/CI에서 Swift 6.2와 6.3 full package build/test, strict concurrency,
   SwiftUI와 InnoDITesting, deployment-floor 및 API baseline 재생성/review 필요
2. 소스 API 동일성과 prebuilt binary의 drop-in 호환성은 별개다. 이번에는 후자를 주장하지 않음
3. 실제 앱의 mixed/large/async graph와 cold full-package/release-plugin 비용은 별도 검증 필요
4. 현재 공개 저장소에 publish한 변경은 없음. 원격 게시/PR/merge는 별도 승인 경계

## 근거와 재현

Checkpoint 3 ZIP은 source patch, 두 신규 테스트, 프로토콜, raw rows, source/binary
fingerprint, 재구성 소스, 검증 로그와 실패한 setup 시도도 보존한다. 대형 toolchain,
의존성 checkout 및 build cache는 제외한다. Swift 6.4 Debian13와 SwiftSyntax 604.0.0
revision `050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf`를 사용했다.

- `compiler-measurements-v2`: 420 rows, optimized 결과 10개 실행 확인
- `native-measurements-v2`: 56 rows, production/manifest compilation을 구분한 audit
- `runtime-compact-owner-v1/measurements-v1`: 96 processes
- `runtime-ready-guard-v1/measurements-v1`: 96 processes, CPU8 확인
- Runtime의 작은 C launcher는 자체 exec 이후 Swift child를 fork해 Python의 inherited
  RSS high-water floor를 피한다. Compiler/native의 기존 RSS 수치는 메모리 비교에서 제외
- 모든 결과를 유지했고 유리한 결과를 고르기 위한 재실행은 하지 않음. 초기 실패는
  driver invocation, manifest audit, public-module 준비 등 setup 오류로 분리 보존
