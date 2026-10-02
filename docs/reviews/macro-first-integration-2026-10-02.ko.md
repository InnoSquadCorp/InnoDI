# InnoDI 최신 main 통합과 동일 workload 재측정

2026-10-02 UTC

## 결론

채택된 macro-first 기능을 최신 main `dba4530494b148b24f6dfa382d70439bd1a8d513`에 충돌 없이 통합했다. 이전 base 이후 변경은 CI·정책·테스트 17파일이며, 통합 제품 Sources 208파일은 앞서 검증한 기능 상태와 전부 동일하다. 성능 후보 세 개는 계속 미채택이다.

새 Linux 측정에서 InnoDI는 이 20-node 동기 on-demand 그래프의 세 시간 지표 모두 Factory, Swinject, Dependencies graph adapter보다 낮았고, Needle의 수동 등록 runtime 경로와 단일-thread lazy control보다 높았다. 기능 범위·동시성·생성 도구·context 의미가 다르므로 라이브러리의 보편적인 순위로 해석하지 않는다.

동일 가중 rubric은 **종합 7.8 / CS 8.0 / DX 7.5**로 유지한다. 실제 값 7.775 / 8.0454545 / 7.5를 반올림한 것이다. 성능 개선을 새로 채택하지 않았고 Apple 전체 검증도 아직 없으므로 점수를 올리지 않는다.

## 통합 상태와 회귀 검증

- 브랜치: `local/macro-first-integration-2026-10-02`
- 기능 patch 적용 직후 tree: `694e7fee6b91df1f328058477e8d7f91fb771c77`
- 아래 보고서 추가 후 최종 tree는 체크포인트의 `integration-final-state.json`에 기록한다
- 직접 typed storage, typed forwarding, explicit `makeOwned` lifecycle을 유지한다. 일반 sync DI 초기화는 기존 가벼운 경계를 유지한다
- production 최적화 delta 없음. 이전 checkpoint와 거절 후보의 원자료를 보존했다
- commit, push, PR, workflow dispatch, merge 또는 Mac/Codex 작업은 수행하지 않았다

| 검증 | 통합 입력의 결과 | 범위 |
|---|---:|---|
| Portable macro/core | 616 tests / 47 suites 통과 | Swift 6.4 Linux, 별도 source-built harness |
| Portable runtime | 73 tests / 11 suites 통과 | strict concurrency / warnings-as-errors |
| 실제 plugin consumer | positive, deferred, public library/client 통과 | 21 negative는 의도한 진단까지 확인 |
| 재진입 canary | debug/release 6개 통과 | factory, factory release, trace callback; timeout 없음 |
| 실제 20-node plugin 재구성 | 85 role 소비, -O plugin/expanded oracle 통과 | 명시적 공통 module name Consumer |
| Portable 공개 API | 591 symbols / 669 relationships 동일 | location/doc comment 제외; Apple 전체 API gate 대체 불가 |
| 최신 main 정책 | 120 tests 통과 | Ready/reuse 정책 및 CI validation/action pin/public operations |
| 로컬 문서 링크 | 305 links / 113 Markdown 통과 | 통합 보고서 추가 전 수치 |
| 새 Apple consumer 제안 | Linux 실제 plugin 교차 모듈 실행 통과 | Apple 실행 결과 아님 |
| 별도 effect/context 시나리오 | Dependencies와 InnoDI 모두 통과 | captured context, inherited task, parallel isolation; 시간 비교 아님 |

새 harness에서 기존 build cache를 복사한 첫 시도는 SwiftShims의 절대 module-cache 경로 때문에 실패했다. 해당 로그를 invalid로 보존하고, 별도 새 build에서 616개를 다시 실행했다. Apple consumer smoke 첫 시도는 기존 동명 `OwnedPublicLibrary`를 먼저 import한 검증 경로 오류였다. import/link 경로 순서를 바로잡은 새 시도는 통과했으며 원래 로그도 보존했다. 제품 소스를 바꿔 회피하지 않았다.

전체 문서 코드 블록 검사는 첫 실행에서 toolchain 환경을 불러오지 않아 종료했다. 이를 제품 실패나 통과로 집계하지 않는다. 해당 검사는 InnoDISwiftUI를 포함하는 전체 package build이므로 Apple 계획에 남긴다. checked-in 공개 API baseline은 갱신하지 않았다.

## 비교 프로토콜과 결과

- Debian 13 x86_64, 공식 Swift 6.4.0, release consumer, native SwiftPM build, CPU8 동일 affinity
- 여섯 lane × 12 chronological blocks = 72개 측정 process. 각 process는 동일 3 warmup + 10 batched samples
- 각 lane이 각 순서 위치에 두 번 나타나는 순환/역순 배치. 실패·outlier 제거·유리한 재실행 없음
- 전후 및 debug-stripped oracle 18개 추가, 총 90 process 성공. source/binary/tool/runtime/lockfile/command hash와 stat 불변 확인
- 표는 각 process의 batched mean 중앙값을 구한 뒤 그 중앙값이다. 개별 호출의 p50/p95가 아니다
- cold는 oracle/process warmup 후 fresh root 생성 + 첫 resolve + 해제 경계다. 프로세스 시작 또는 cold filesystem cache 측정이 아니다
- first는 미리 만든 root의 첫 resolve이며, root를 timing 종료 뒤까지 유지했다. warm은 이미 준비된 root의 leaf 반복 접근이다

| Lane | Fresh-root lifecycle µs | First resolve µs | Warm resolve ns |
|---|---:|---:|---:|
| InnoDI | 18.828 | 8.804 | 220.139 |
| Factory | 72.713 | 113.686 | 1209.362 |
| Swinject | 56.147 | 29.333 | 1619.983 |
| Dependencies | 94.108 | 46.651 | 617.209 |
| Needle-runtime | 14.469 | 6.539 | 153.300 |
| Control | 4.397 | 1.592 | 25.510 |

아래 값은 **InnoDI / 비교 lane**의 paired geometric mean ratio와 95% whole-block bootstrap 구간이다. 12개 block 전체를 resampling 단위로 사용한다. 작을수록 이 workload에서 InnoDI 시간이 짧다는 뜻이며, 위 중앙값끼리의 단순 나눗셈과 다른 추정량이다. 각 비교의 기술적 구간이며 다중비교 보정된 보편적 우위 검정은 아니다.

| 비교 lane | Lifecycle ratio [95% 구간] | First ratio [95% 구간] | Warm ratio [95% 구간] |
|---|---:|---:|---:|
| Factory | 0.267 [0.242, 0.294] | 0.081 [0.069, 0.095] | 0.179 [0.164, 0.189] |
| Swinject | 0.343 [0.325, 0.373] | 0.303 [0.289, 0.317] | 0.138 [0.131, 0.145] |
| Dependencies | 0.210 [0.196, 0.226] | 0.187 [0.178, 0.194] | 0.361 [0.349, 0.375] |
| Needle-runtime | 1.282 [1.176, 1.370] | 1.370 [1.318, 1.424] | 1.430 [1.290, 1.535] |
| Control | 4.320 [3.964, 4.794] | 5.501 [5.264, 5.754] | 8.813 [8.417, 9.344] |

Factory의 first 값이 lifecycle보다 큰 결과도 그대로 보존했다. first는 100개 root를 미리 만들어 유지하고 lifecycle은 root별 생성·해제를 반복하므로 두 값은 더하거나 빼서 setup 비용을 계산할 수 있는 구성 요소가 아니다. 이번 차이의 구체적 원인은 확정하지 않았다.

## 해석 경계

- Factory는 각 ManagedContainer의 retained cached scope, Swinject는 container scope와 synchronized resolver다
- Needle은 BootstrapComponent/shared와 **수동 provider 등록**이다. 공식 Generator의 Linux 결과와 generated DX는 측정하지 않았다. 앞선 upstream Objective-C Foundation bridge 실패를 고쳐서 성공한 것처럼 처리하지 않았다
- Dependencies는 root별 독립 객체 수명을 맞추려고 fresh public DependencyValues를 쓰는 graph adapter다. 일반적인 effect dependency 사용에서 매번 context를 재생성한다는 뜻이 아니다. native context/effect correctness는 별도 검증했다
- Control은 직렬 Swift lazy property다. 동시 접근 안전한 cache 제품의 대체 구현이 아니다
- 이 graph는 동기 resolve이며 `makeOwned` prepare/cancel/retry/close의 경쟁 비교가 아니다
- InnoDI 비교 build는 새 실제 plugin expansion과 DITracing/OnDemandSharedCell/정확한 RuntimeSupport 선언의 선택적 runtime 경계다. 전체 제품/매크로 package build 비용이 아니다
- SwiftPM description의 계획만 믿지 않고 실제 verbose compiler/link 실행, source/object/module hash, link object 목록을 교차 검증했다. FactoryTesting, NeedleFoundationTest, Dependencies macros/test support 및 SwiftSyntax는 계획에 존재해도 실제 linked consumer build에는 포함되지 않았다
- Dependencies는 이번에 새로 resolve한 lockfile을 고정했다. 선택된 manifest는 tools 6.4의 Package.swift, default traits 유지. combine-schedulers 1.2.2, swift-clocks 1.1.1, concurrency-extras 1.4.1, issue-reporting 2.1.1, OpenCombine 0.14.0, SwiftSyntax 604.0.0이다. 과거 transitive revision을 정확히 재현한 비교가 아니다
- `-j 1`은 SwiftPM 작업 수다. 실제 release compiler의 `-num-threads 9`도 기록했다. 한 번의 setup build wall time은 build 성능 순위나 cold/incremental 비교로 사용하지 않는다
- 작은 C launcher의 wait4로 process peak RSS를 수집했다. oracle, runtime, root batches를 포함한 process resident high-water이며 retained live heap 또는 allocation 수가 아니다

| Lane | Process peak RSS 범위 KiB | Debug-stripped ELF bytes |
|---|---:|---:|
| InnoDI | 21888–22636 | 233760 |
| Factory | 35576–37916 | 313344 |
| Swinject | 21868–22612 | 297328 |
| Dependencies | 28196–28544 | 3821408 |
| Needle-runtime | 21516–22264 | 136920 |
| Control | 20864–21584 | 60952 |

## Apple 검증 경계와 준비된 제안

[Apple 실행 계획](../plans/macro-first-apple-validation.md)에 exact Xcode/Swift 확인, strict/full suite, 공개 API delta 검토, deployment floor, SwiftUI/InnoDITesting, sanitizer와 evidence 기준을 기록했다. CI 제안은 체크포인트 `integration/apple-plan/apple-ci-and-consumer-proposal.patch`에 별도 보관하며 live workflow에 적용하지 않았다.

- Swift 6.2 job에 runtime/unit package suite 실행을 추가하고 기존 strict/external consumer는 그대로 실행한다
- owned override와 typed Lazy/Provider를 실제 plugin 교차 모듈 consumer discovery에 추가한다. Int 기반 fixture는 API/override 값 확인이며 cache identity/fresh construction의 독립 증명으로 부르지 않는다
- 새 minimum-toolchain step을 Ready와 main exact-tree reuse의 **production proof predicate 두 곳 모두** 필수로 지정한다. missing/skipped/failed/cancelled/duplicate 증거를 거절하는 테스트를 포함한다
- 제안의 정책 테스트 122개와 추가 static contract 3개, YAML/action pin/opt-out/applicability 검사가 통과했고 독립 검토를 받았다
- Swift 6.2/6.3 Apple 실행, actionlint, 실제 최소 OS 실행, intentional API baseline review는 아직 미실행이다
- 9개 Mutex 기반 trace 추가 테스트는 macOS15/iOS18 등에서만 실행 가능하다. macOS14/iOS17 제품 floor 검증으로 대신하지 않는다

현재 로컬 통합·동일 workload 재측정 단계는 완료됐다. 다음 실제 실행 경계는 검토된 CI 제안 적용과 공개 API 의도 변경 검토 뒤, 승인된 Apple 환경 또는 원격 PR/full CI에서 같은 최종 tree를 검증하는 것이다. 이 보고서는 원격 발행이나 사용자 Mac 작업의 승인으로 해석하지 않는다.

## 원자료

체크포인트의 `integration/`에는 source/lock manifest, 정확한 명령과 실패 기록, native compile/link audit, 실제 plugin role dump/expanded source, 모든 측정 stdout/resource row, 최종 hash 검증, Apple patch/plan이 포함된다. 이전 성능 후보의 protocol/result/rejection과 historical driver scope 정정은 기존 checkpoint 항목에 그대로 남아 있다. 이전 “whole-macro/composite-v2”는 root/member-attribute in-process driver이며 전체 compiler expansion 증거가 아니다.
