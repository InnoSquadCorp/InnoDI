# 명시적으로 소유하는 컨테이너

비동기 shared provider의 준비, 취소, 재시도, 종료를 명시적으로 관리할 때
생성되는 owner를 opt-in으로 사용합니다.

## 선언에서 Opt In

`@DIContainer`와 `@DIContainerRole` 모두 `generateOwned: true`를 지원합니다.
기존 `@Input`, `@Provide`, factory, dependency parameter를 그대로 사용합니다.

```swift
@DIContainer(generateOwned: true)
struct Services {
    @Input var seed: Int

    @Provide(.shared, asyncFactory: { (seed: Int) async in seed + 1 })
    var first: Int

    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (first: Int) async in first + 1 })
    var service: Int
}

let owner = try await Services.makeOwned(seed: 40)
do {
    let report = try await owner.prepare(.service)
    if report.isReady {
        let value: Int = try await owner.container.service
        print(value)
    }
} catch {
    await owner.close()
    throw error
}
await owner.close()
```

인자를 생략하거나 literal `false`를 쓰면 owned API를 생성하지 않습니다.
활성화해도 기존 initializer는 바뀌지 않습니다. `makeOwned`는 자체 concrete
storage를 만들며 기존 컨테이너를 생성한 뒤 task를 인수하지 않습니다.
별도의 registration DSL이나 scope 종료 시 자동 정리도 없습니다.

## 준비된 작업 한 번 실행하기

짧은 작업에는 report 검사와 성공·실패별 close 대신 생성된 `withPrepared`를 사용합니다.

```swift
try await Services.withPrepared(.service, seed: 40, overrides: { overrides in
    overrides.service = 99
}) { services in
    let value = try await services.service
    print(value)
}
```

이 helper는 `generateOwned: true`이며 async shared provider가 있는 container에만
생성됩니다. typed selection은 `prepare`와 같으며, 추가 선택은 이름 붙은 input 인자보다
앞에 놓습니다. `overrides:`는 기본적으로 아무것도 바꾸지 않고, throw할 수 있으며,
어떤 live factory·child·owned task보다 먼저 실행됩니다. operation은 nonescaping이고 결과에
Sendable 요구를 추가하지 않습니다. MainActor 격리도 유지합니다.

새 owner를 만들고 선택한 subgraph의 모든 entry가 ready일 때에만 operation에 들어갑니다.
failed·blocked·cancelled·closed entry는 준비 당시 snapshot을 담은
``DIAsyncPreparationFailure``를 던집니다. 준비 실패·operation 오류·정상 반환 모두
`close()` 완료를 기다립니다. detached cleanup task는 만들지 않습니다. 선택하지 않은
독립 eager provider도 기존 정책대로 시작하므로 선택한 부분의 성공이 전체 graph의
정상 상태를 뜻하지는 않습니다.

- 호출 시작 시 이미 취소되어 있으면 override callback과 live 작업을 막습니다.
  callback 안에서 발생한 취소는 callback 종료 뒤 live 생성 전에 확인합니다
- 준비 뒤에는 report 검사보다 caller 취소를 먼저 확인합니다
- operation이 던진 오류는 동시 취소가 있더라도 그대로 보존합니다
- operation이 성공했어도 close 뒤 caller가 취소되었으면 CancellationError를 던집니다

취소는 협력적입니다. 취소를 무시하고 반환하지 않는 operation은 helper도 계속 대기하게
합니다. close는 취소를 무시하는 factory를 drain하거나 임의 앱 task를 종료하거나 서비스의
shutdown()을 호출하지 않습니다. 생성된 async scope만 소유하며 input·동기 값·child는
빌린 값입니다. operation에서 view가 반환되거나 밖으로 capture될 수도 있습니다.
그 뒤 async read는 closed로 실패하지만 동기 값과 이미 반환된 서비스는 회수되지 않습니다.

재시도 화면처럼 owner를 오래 보관할 때에는 `try await owner.requireReady(.service)`를
사용합니다. owner를 닫지 않고 취소와 readiness를 검사합니다.
`retryAndRequireReady(.service)`는 기존 retry transaction을 정확히 한 번 실행한 뒤
검사하며 refresh나 자동 반복 재시도가 아닙니다. 기존 prepare/retry report API는
상세한 loading UI에 계속 사용할 수 있습니다. report의 동기 requireReady()는 snapshot만
검사하고 task 취소는 확인하지 않습니다. 열린 scope의 provider read는 원래 factory 오류를
던질 수 있지만 withPrepared 종료 후 escaped view에서는 closed가 우선합니다.

## 시작 허용과 준비 완료, 선택

`makeOwned`는 `async throws`입니다. 설정을 끝내고 각 eager async provider의
시작을 허용한 뒤 반환하지만, 모든 값이 준비될 때까지 기다리지는 않습니다.
On-demand async provider는 읽기 또는 준비 요청으로 시작합니다. 생성 중 취소나
설정 실패가 발생하면 할당된 owned scope를 닫은 뒤 오류를 던집니다.

`prepare(.service)`는 선택한 async dependency graph를 따라 준비하고
``DIAsyncPreparationReport``를 반환합니다. `isReady`와 각 entry로 실패하거나
막힌 provider를 확인하세요. `status(.service)`는 선택한 concrete scope의
``DIAsyncProviderStatus``를 반환합니다. 선택 token에는 async shared provider만
있으며 서비스 resolver로 사용하거나 다른 컨테이너의 token으로 대체할 수
없습니다. Async provider가 없는 owned 컨테이너에는 `close()`만 있고 선택 enum과
선택 메서드는 생성되지 않습니다.

Owned async getter는 작성한 factory가 nonthrowing이어도 모두 `async throws`입니다.
읽기에서 lifecycle 취소 또는 close를 관찰할 수 있기 때문입니다. 작성한 factory의
effect 계약은 바뀌지 않으며, dependency argument를 먼저 읽은 뒤 호출합니다.

## 취소, 재시도, 종료

- `await owner.cancel(.service)`는 각 scope의 개별 취소 시점에 실행 중인 선택
  scope만 취소합니다. Idle, ready, failed, cancelled, closed 상태는 바뀌지
  않습니다. Admission을 일시 중지하거나 의존성으로 취소를 전파하지 않으며,
  여러 선택을 하나의 원자적 transaction으로 처리하지 않습니다
- 취소된 scope는 factory를 유지합니다. `try await owner.retry(.service)`는 기존
  preparation plan의 명시적 실패/취소 subgraph 재시도와 generation 규칙을
  사용합니다. 이전 generation의 늦은 결과는 현재 값을 덮어쓸 수 없습니다.
  취소된 scope는 명시적으로 재시도하기 전까지 읽기가 계속 실패합니다
- `await owner.close()`는 공유 admission gate를 닫고 async scope를 graph의
  역순으로 닫습니다. 동시 close 호출은 진행 중인 lifecycle 정리를 포함해 같은
  완료를 기다립니다. Barrier 이전에 허용된 읽기는 scope 내부 경합에서 성공할
  수 있지만, 이후의 읽기는 cache hit도 ``DIAsyncScopeError/closed(providerID:)``로
  실패합니다
- Close는 작업을 취소하지만 취소를 무시하는 사용자 factory의 종료까지 기다리지는
  않습니다. 나중에 끝난 factory의 결과는 버립니다. 반환된 서비스의 shutdown
  메서드를 호출하거나 이미 전달한 값을 회수하지 않습니다

## Override, 복사본, 빌린 값

`makeOwned`는 기존 input과 직접 value override 인자, shared child override,
child override closure, `_innoDITrace`를 받습니다. Async value override는
factory를 실행하지 않고 ready scope를 만듭니다. 해당 preparation node에는
factory dependency edge가 없지만 선언한 전체 graph 검증은 유지됩니다.
Override된 consumer가 더 이상 필요로 하지 않더라도 다른 eager provider는
자체 정책대로 시작합니다.

`makeOwnedWithOverrides`는 기존 `Overrides` builder를 trailing closure로 받아 여러 테스트의 override
preset을 재사용할 수 있습니다:

```swift
let owner = try await Services.makeOwnedWithOverrides(seed: 40) {
    $0.service = 99
}
// 미리 만들거나 검증한 preset은 { $0 = preset }으로 대입할 수 있습니다
```

이미 취소된 task는 override closure 실행 전에 거절됩니다.
Nonescaping closure는 throw할 수 있으며 live factory, child, owned task를 만들기
전에 실행됩니다. Builder 값은 같은 직접 `makeOwned` 경로로 전달됩니다.
Optional payload는 기존 구분을 유지합니다. `.some(nil)`은 명시적인 nil override이고,
builder slot을 설정하지 않으면 live factory를 사용합니다. 이 편의 API가 side-effect
override를 자동 검증하거나 반환된 owner를 자동 종료하지는 않습니다. 기존 preset
검증과 명시적인 `close()`를 사용하세요.

별도 메서드 이름을 사용하므로 child container를 설정하는 기존 `makeOwned`
trailing closure의 의미가 유지됩니다. 두 메서드는 같은 명시적 owner 타입을 반환합니다.

Owner 복사본과 밖으로 전달한 dependency view 복사본은 같은 scope와 terminal
gate를 공유합니다. 별도 `makeOwned` 호출은 독립적입니다. Input, 동기 shared 값,
일반 shared child container는 async lifecycle에서 빌린 값입니다. Parent close가
이들을 닫지 않으며, 밖으로 전달한 view에서도 이후 동기 값을 계속 읽을 수 있습니다.

동기 `.transient` provider도 기존의 매 접근 factory 실행 계약을 유지합니다.
직접 value override를 주면 live factory나 그 의존성을 실행하지 않고 매번 같은
대체값을 돌려줍니다. 별도로 선언된 eager provider는 자신의 초기화 정책을 따릅니다.
Transient는 preparation node가 아니며 cancel/retry/status token도 없습니다.
다른 동기 getter처럼 close 이후에도 사용할 수 있습니다. 반환값의 수명은 호출자가
관리하고, `close()`가 view의 모든 서비스 객체를 dispose하거나 무효화하지는 않습니다.
Typed resolver closure는 필요한 의존성을 보관하며 owner나 coordinator를 붙잡지
않습니다. Diamond 경로도 resolver를 각각 호출하므로 transient를 cache로 바꾸지 않습니다.

## 동기 지연 의존성

Owned 생성은 기존 동기 `InnoDI.Lazy<T>`와 `InnoDI.Provider<T>` factory parameter를
지원합니다. Lazy는 input이나 동기 shared/transient provider를 대상으로 삼을 수 있고,
Provider는 동기 transient가 필요합니다. Lazy가 transient 대상에 cache를 추가하지는
않습니다. 기존 graph 검증은 소유권 cycle, 잘못된 대상, shared 생성 중 wrapper를
직접 호출하는 eager 접근을 계속 거절합니다.

Forward 대상은 async 시작 전에 연결되는 구체적인 local cell을 사용합니다.
Cell은 대상 값이나 resolver만 캡처하며 view나 owner 전체를 붙잡지 않습니다.
Wrapper 생성만으로 on-demand factory를 실행하지 않습니다. 직접 override와 builder
override 모두 identity, factory 우회, optional nil 구분을 유지합니다. 밖으로 전달한
handle은 다른 동기 getter처럼 close 이후에도 사용할 수 있습니다.

Owned deferred cell과 wrapper 값은 non-Sendable입니다. 일반 async factory나 async
사용을 위해 Sendable이어야 하는 on-demand factory는 이 cell을 캡처할 수 없습니다.
Swift가 잘못된 캡처를 진단하며 unchecked 전송을 허용하지 않습니다. MainActor에
격리된 async consumer는 Swift가 전체 capture와 결과 타입을 검증하는 경우 지원됩니다.
이 확장은 async Lazy/Provider wrapper를 추가하지 않습니다.

## 마이그레이션과 현재 경계

`owner.container`는 원래 컨테이너와 다른 생성된 dependency view입니다.
Concrete dependency getter는 있지만 기존 사용자 메서드, protocol conformance,
key path는 옮겨지지 않습니다. Consumer를 필요한 서비스 의존성이나 명시적인
view 타입으로 변경하세요. Owner/view의 타입 추론과 `.service` 같은 contextual
selection을 권장합니다.

MainActor 컨테이너는 owned factory, view, lifecycle 메서드를 같은 actor로
격리합니다. 그 외 컨테이너의 async API는 호출자의 executor를 유지하며 owner와
view에 무조건적인 `Sendable`을 추가하지 않습니다. Async factory의 capture와
payload는 컴파일러가 검사하며, 비동기 factory가 잡는 동기 on-demand cell에도
이 검사가 적용됩니다.

현재 prototype은 `validateDAG: true`가 필요합니다. Input, eager/on-demand 동기 및
비동기 shared provider, 동기 transient provider, 조건에 맞는 동기 Lazy/Provider edge,
일반 shared child를 지원합니다. Async transient provider, assisted input/factory,
collection/multibinding provider, transient child, feature-root helper, custom global actor, MainActor
컨테이너 밖의 member별 actor 격리는 지원하지 않습니다. 알 수 없는 custom-actor
attribute 이름은 InnoDI 전용 진단 대신 생성 코드의 compiler 진단으로 실패할 수
있으며, 이 prototype의 검증된 지원 범위가 아닙니다. 지원하지 않는 형태에는 기존
컨테이너 API를 사용하세요.
<doc:DiagnosticsGuide>와 <doc:AsyncPreparation>도 참고하세요.

Input 타입 안의 Self는 바깥 컨테이너에서 compiler가 바인딩한 witness를 통해
원래 컨테이너의 타입을 유지합니다. 중첩 컨테이너와 함수 타입도 같습니다.
Factory 표현식의 Self는 원래 lexical scope를 그대로 사용합니다. Shared
property의 `Self.Value` 표기는 기존 legacy `Overrides` 제한에 걸릴 수 있으므로,
이 경우에는 nested 타입의 `Value` 이름을 사용하세요. 실질적으로 generic인
컨테이너는 계속 지원하지 않습니다.
