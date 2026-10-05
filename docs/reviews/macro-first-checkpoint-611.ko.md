# Macro-first 개선 중간 재평가: 611-test 체크포인트

2026-10-02 범위 정정: 이 문서의 과거 whole-macro/composite-v2/whole-driver 수치는 root/member-attribute in-process driver에 한정된다. 전체 compiler expansion 또는 소비자 빌드 개선을 의미하지 않는다. [후속 실제 compiler 및 소비자 검증](macro-first-performance-track-2026-10-02.ko.md)을 함께 확인한다.

보존된 중간 결과다. 이후 V4 일반 getter 최적화는 미채택했고 현재 평가는
[최종 로컬 결과](macro-first-results.ko.md)의 7.7 / CS 8.0 / DX 7.4를 따른다.

2026-10-01 UTC. 원본 `6725e08b6da5d2ceeda61ed795adca5fadda564c` 대비 로컬
후보 평가다. 전체 breaking 개선 트랙의 완료·출시 승인·보편적인 경쟁 우위가 아니다.
다음 sync-transient 확장 이전의 결과를 보존한다.

## 요약

같은 기존 rubric에서 **종합 7.8, CS 8.1, DX 7.4**로 잠정 평가한다.
기존은 7.5 / 7.7 / 7.3이다. 판단 점수이며 속도나 결함률의 측정값이 아니다.
명시적 async owner와 typed selection은 개선됐지만 일반 앱의 shared+transient
조합을 owner 경로가 거절하는 제한 때문에 DX 목표를 달성했다고 보지 않는다.

- macro-first 선언을 그대로 사용한다. 별도 registration graph는 작성하지 않는다
- dependency-order는 opt-in이며 기존 source-order 기본값을 바꾸지 않았다
- `makeOwned`에만 준비·선택 취소·retry·close를 묶는다. 일반 initializer는 유지한다
- 별도 OwnedView 타입과 async getter의 `throws`, typed prewarm 교체는 migration 비용이다
- Apple 전체 제품, Swift 6.2/6.3, SwiftUI 성능·build·retained heap 검증은 미실행이다

## 같은 가중치의 판단 점수

0.5 단위의 세부 판단, 가중 평균 소수 첫째 자리 반올림을 유지했다. CS는 첫
5개 항목(55), DX는 도입부터 문서까지(35)를 정규화한다. 기존 경쟁 점수는
다른 버전·증거 범위의 판단이므로 새 실측 순위처럼 재사용하지 않는다.

| 항목 | 가중치 | 원본 | 후보 | 변화 근거와 남은 비용 |
|---|---:|---:|---:|---|
| 알고리즘과 확장성 | 10 | 7.0 | 8.0 | 반복 availability set 제거, oracle 동등성, 대표 macro 총비용은 대체로 유사 |
| 정적 그래프 검증 | 15 | 8.5 | 8.5 | 기존 cycle/effect 검증 보존, 지원 syntax 경계 유지 |
| 타입과 동시성 | 10 | 8.0 | 8.0 | compiler-bound Self witness와 실제 plugin 검증, 이전 compiler 미검증 |
| 수명과 실패 모델 | 10 | 7.0 | 8.0 | owner admission/close join/selected cancel/retry 통합, borrowed child·사용자 task는 제한 |
| 런타임 자원 설계 | 10 | 7.5 | 8.0 | 안전한 ready bookkeeping 생략, 비교 oracle·재진입 회귀, retained heap 미측정 |
| 도입과 일상 사용 DX | 10 | 6.5 | 7.0 | 순서 opt-in·typed 선택, transient/assisted/deferred/collection owner 제한과 별도 view 비용 |
| 테스트와 override | 10 | 8.0 | 8.0 | typed seed·factory edge pruning, owner Overrides-builder convenience 미제공 |
| SwiftUI 통합 | 5 | 8.5 | 8.5 | 이 트랙에서 개선하거나 새로 실행 검증하지 않음 |
| 빌드 반복 DX | 5 | 5.5 | 5.5 | 작은 생성량 감소, 공정한 Apple 전체 cold/warm build 미측정 |
| 문서와 migration | 5 | 8.0 | 7.5 | EN/KO 계약·migration 문서 추가, keypath 및 nominal view 수동 migration 부담 |
| 플랫폼과 유지보수 지속성 | 5 | 6.0 | 6.0 | 지원 floor/platform 변경 없음, Linux 전체 제품은 부적격 |
| 운영 가시성과 검증 도구 | 5 | 8.5 | 8.5 | trace/status 유지, 새 production 운영 데이터 없음 |

## 검증된 현재 범위

- focused core/macro 611 tests / 46 suites, strict concurrency + warnings-as-errors 통과
- 실제 portable runtime 64 tests / 10 suites 통과
- factory, capture-deinit, trace 재진입 subprocess는 debug/release 모두 기대 trap
- 실제 macro plugin을 통한 legacy+owned 공존, 별도 public library/consumer 모듈의
  owner/view/token/Self witness/prepare/cancel/close 컴파일·실행 통과
- alias 충돌, generic context, wrong token/actor, private getter, token resolver
  오용의 기대 진단 확인
- 기존 shared `Self.Value`는 legacy Overrides의 Self 바인딩 때문에 실제 plugin에서
  여전히 실패한다. owned-only 코드가 맞다는 이유로 전체 지원을 주장하지 않는다

중간 실패도 보존했다. cancellation의 전역 admission pause, 자연스러운 token
타입명의 payload shadowing, nominal name을 통한 Self 재작성, ready 경로의
capture-deinit 재진입 누락은 검토·실행으로 발견해 수정했다. 추가 overload의
17.7% 작은-container macro 비용과 두 cold 회귀 초안은 채택하지 않았다.

## 같은 workload의 좁은 런타임 비교

Swift 6.4 Linux, 20-node synchronous shared/on-demand chain. 동일 Node/counter,
identity·독립 root·override·20개 해제 oracle을 먼저 통과시켰다. 3개 프로세스
block × 10 batch mean, 각 3 warmup. 각 library와 consumer는 별도 package/module,
`-O` + WMO, CMO/library evolution off, static object linking 조건을 기록했다.
단, Needle/OpenCombine의 upstream Swift language mode는 5, consumer는 6이다.

| Lane | fresh graph+resolve+release µs | 첫 resolve µs | ready resolve ns | debug-stripped ELF bytes |
|---|---:|---:|---:|---:|
| InnoDI 원본 | 21.65 | 8.71 | 222.7 | 233,728 |
| InnoDI 후보 V4 | 19.60 | 8.77 | 155.0 | 233,880 |
| Factory 3.4.1 | 58.83 | 69.60 | 1,247.6 | 314,168 |
| Swinject 2.10.0 | 56.99 | 29.06 | 1,605.9 | 298,080 |
| swift-dependencies 1.17.1 | 92.33 | 44.75 | 642.7 | 3,821,472 |
| Needle 0.25.1 runtime-only | 14.69 | 6.14 | 154.2 | 136,888 |
| serial Swift lazy control | 4.54 | 1.57 | 26.2 | 60,912 |

이 수치는 동일 실행 내 median이다. 서로 다른 batch/setup에 의해 Factory 첫 resolve가
전체 lifecycle보다 높을 수도 있으며 차이를 구성 비용으로 빼서 해석하면 안 된다.
shared VM의 변동이 크고 3개 block뿐이다. cold는 process startup이 아니라 metadata/
oracle warmup 후 새 graph 수명이다. p95도 개별 호출 tail latency가 아닌 batch mean이다.

후보 V4는 첫 resolve block 변화가 −3.0%/+1.5%/−5.1%, cold는 +0.2%/+0.4%/−13.2%였다.
앞선 두 초안의 명확한 cold 회귀가 재현되지 않아 현재 후보로 유지하지만 일반적인
30% 속도 개선이나 회귀 부재를 보장하지 않는다. Needle은 cold/first에서 더 빠르고
ready는 비슷하다. 모든 경쟁 제품보다 우수하다는 결론은 틀리다.

범위 차이도 중요하다.
- InnoDI는 실제 생성 AST + 수정하지 않은 portable runtime subset이다. 전체 Apple
  제품의 binary/build 비용과 같지 않다
- Needle은 수동 bootstrap bridge를 사용한 runtime-only lane이다. 공식 generator는
  같은 VM에서 시도했으나 upstream ObjCBridges의 Foundation/Foundation.h 부재로
  빌드 실패했다. generator·compile-time graph DX 비교는 Apple 경로가 필요하다
- swift-dependencies는 independent-root oracle을 위해 public DependencyValues()
  fresh-cache adapter를 썼다. 대표적인 effect scoping 사용성/성능 전체를 대표하지 않는다
- control은 serial lazy이며 concurrent cache 대안이 아니다
- ru_maxrss는 전체 process peak다. retained service heap·allocation 개수는 미측정이며
  위 ELF 크기와 함께 전체 라이브러리 메모리 우열의 근거로 사용하지 않는다

## Typed prewarm만 분리한 런타임 결과

두 lane 모두 **동일한 원본 runtime dependency module**을 링크했다. V4 효과가 섞이지
않는다. 실제 원본/후보 macro AST, 20 providers, 3×10 batch mean의 median이다.

| 동작 | 원본 keypath | typed-only |
|---|---:|---:|
| 첫 leaf 준비 | 10.08 µs | 9.53 µs |
| 준비된 leaf 선택 | 1,277.7 ns | 218.2 ns |
| 준비된 20개 전체 선택 | 27.26 µs | 4.70 µs |

ready dispatch의 전체 keypath 순회 제거는 이 workload에서 뚜렷하다. 첫 준비는
factory 비용과 VM 변동이 커 개선 단정하지 않는다. unsupported selection이
runtime throw에서 compile error로 바뀌는 장점과, dynamic/generic keypath 호출의
기능적 migration 비용을 함께 본다. 소규모 생성량 감소와 전체 runtime 속도는
서로 다른 결과다.

## 다음 단계와 완료 기준

1. 기존 동기 수명을 보존하는 sync-transient owner 조합 지원 및 재평가
2. native effect/override DX 비교, migration 예시와 선언량을 별도 제시
3. 공정한 전체 cold/warm build·Apple binary/heap·supported compiler 검증
4. B5 isolation, B6 runtime product boundary는 조건부 설계이며 구현 완료가 아니다
5. 원본 F1 mock deinit-under-lock은 별도 정적 발견으로 남으며 이번 owner/ready
   재진입 회귀가 그 문제의 수정·실행 증거를 대신하지 않는다

전체 결과/방법은 [evidence ledger](macro-first-local-evidence.md), 재현 entrypoint는
`Tools/ConsumerComparison/`, `Tools/validate-owned-portable-plugin.sh`,
`Tools/validate-ready-cell-portable.sh`에 있다. 원시 sample·flags·binary/source hash는
로컬 evidence package의 `consumer-measurements-v4`, `consumer-module-boundaries-v4`,
`prewarm-method-measurements`, `checkpoint-611-source-manifest.json`에 보존했다.
