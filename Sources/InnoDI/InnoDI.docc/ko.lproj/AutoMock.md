# 자동 mock 생성

`@GenerateMock`(RFC 0001)은 protocol의 호출을 기록하는 mock peer를 합성해,
테스트가 mock 본문을 손으로 쓰지 않고 기존 `Overrides` builder에 끼워 넣을 수
있게 합니다. 이 attribute는 **experimental** opt-in으로 제공되며 InnoDI
6.0에서도 experimental로 남습니다. 생성되는 형태는 RFC 0001의 전용 GA 기준을
통과할 때까지 바뀔 수 있습니다.

## 사용법

protocol 선언에 `@GenerateMock`을 직접 붙이세요.

```swift
import InnoDI

@GenerateMock
protocol UserService {
    var prefix: String { get set }
    func fetch(id: String) async throws -> String
    func reset()
}
```

매크로는 protocol 옆에 peer mock class를 생성합니다. 생성된 class는 그
protocol을 따릅니다. 테스트는 mock을 만들고, stub을 채운 뒤, 기록된 호출을
읽습니다.

```swift
let mock = UserServiceMock()
mock.prefix = "test"
mock.fetchResult = .success("hello")
try DIStubValidation.requireAllStubbed(mock.missingStubSelectors)

let value = try await mock.fetch(id: "42")
#expect(value == "hello")
#expect(mock.fetchCalls.last?.id == "42")

mock.reset()
#expect(mock.resetCalls.count == 1)

let completed = mock.innoDIReset(.calls)
#expect(completed.generation == 0)
#expect(completed.recordedCallCounts["reset"] == 1)
```

## 생성되는 형태

지원하는 protocol 멤버마다 매크로는 다음을 생성합니다.

* **`var prop: T { get set }`** — private optional stub storage가 뒷받침하는,
  타입이 정확한 computed `var prop: T`. 읽기 전에 채우세요.
* **`func name(args)`(동기, non-throwing)** — 인자를 담는 `struct NameCall`,
  `private(set) var nameCalls: [NameCall]` 목록, optional
  `var nameReturnValue: ReturnType?` slot, 그리고 `nameCalls`에 호출을
  추가하고 stub을 꺼내는 conforming 메서드.
* **`func name(args) async`** — 동기 경우와 같지만 생성된 메서드에 `async`
  효과가 붙습니다.
* **`func name(args) throws -> T`** — optional 반환 slot을
  `var nameResult: Result<T, Error> = .failure(...)`로 바꿔, 테스트가 한 번의
  대입으로 `.success(value)`와 `.failure(error)` 중에서 고르게 합니다. 기본
  실패는 stub되지 않은 selector 이름을 출력하는 중첩 `_InnoDIMockNotStubbed`
  오류입니다.
* **`func name(args) throws`(Void 반환)** — 값이 설정되면 생성된 본문이 다시
  던지는 `var nameThrownError: Error?` hook 하나를 추가합니다. 성공 동작을
  설정했다고 표시하려면 `nil`을 명시적으로 대입하세요.
* **`func name(args) async throws -> T`** — 두 경우를 합칩니다.
* **`func name(args) throws(Failure) -> T`** — typed error를
  `Result<T, Failure>?`에 보존합니다. 매크로가 임의의 `Failure`를 만들어 낼 수
  없으므로, 동작을 실행하기 전에 `missingStubSelectors`를 검증하세요.
* **overload된 함수** — helper 이름에 selector label과 파라미터 타입 stem이
  들어가므로 `fetch(id:)`와 `fetch(page:)`가 충돌하지 않습니다.
* **제네릭 함수** — 생성된 메서드는 generic 절을 보존하고, 지워진
  `([Any]) -> Any` handler를 저장하며, 필요하면 `async` / `throws` 효과도
  맞춥니다. 테스트는 호출 경계에서 generic 반환 타입으로 cast합니다. generic
  typed-throws requirement는 handler를 지우면 선언된 실패 타입이 사라지므로
  여전히 지원하지 않습니다.
* **`mutating` requirement** — 생성된 `final class` mock으로 지원하며, 합성된
  메서드에 `mutating`을 붙일 필요가 없습니다.
* **접근 수준** — `private`와 `fileprivate` protocol의 mock은 그 좁은 접근
  수준을 물려받아 생성된 conformance가 유효하게 남습니다. internal, package,
  public protocol의 mock은 이 API가 experimental인 동안 internal로 남으므로,
  매크로를 붙여도 패키지의 public API가 넓어지지 않습니다.
* **escaping 클로저 인자** — property에 담을 수 있는 함수 타입으로 기록합니다
  (호출 기록 필드에서는 `@escaping` / `@autoclosure`를 빼고, conforming
  메서드는 원래 파라미터 표기를 유지합니다).
* **동시성** — `Sendable`을 상속하는 protocol은 `InnoDITesting` product의 lock
  기반 호출·stub storage를 받습니다. snapshot과 reset-safe 지원 타입은
  unchecked conformance를 쓰지 않습니다. 컴파일러는 여전히 `Sendable`이 아닌
  인자, 결과, stored property를 거부합니다. 일반 protocol은 단일 executor
  mock으로 남습니다.
* **Actor 격리** — protocol 수준의 `@MainActor`를 생성된 mock class에 복사해,
  변경 가능한 테스트 상태를 모두 main actor에 둡니다.
* **상호작용 검증** — 함수가 있는 생성 mock은 모두 `recordedCallCounts`를
  노출합니다. 모든 property, 값을 반환하는 함수, throwing 함수, generic
  handler는 생성된 slot에 값을 대입할 때까지 `missingStubSelectors`에
  들어갑니다. 설정 여부 flag는 optional storage와 별개이므로, 정당한 `nil`
  property나 optional 반환을 대입해도 그 stub은 설정된 것으로 표시됩니다. 동작
  전에 `DIStubValidation.requireAllStubbed`를 실행하고, 같은 selector와
  `recordedCallCounts`를 `DIInteractionValidation`에 넘겨 strict 또는
  recording-only 검증을 하세요.
* **Reset** — 비어 있지 않은 생성 mock은 모두 `innoDIReset(_:)`,
  `innoDICallHistoryGeneration`, `innoDICallHistorySnapshot`을 노출합니다.
  설정한 stub을 유지하면서 호출 기록만 지우려면 `.calls`를, 호출을 지우고 모든
  stub을 missing 상태로 되돌리려면 `.all`을 쓰세요. 호출 기록마다 generation이
  들어갑니다.

## Reset과 generation 의미

`innoDIReset(_:)`은 자신이 닫는 generation의 원자적 snapshot을 반환한 뒤
mock을 다음 generation으로 넘깁니다. 그래서 경쟁하는 호출도 결정적으로
처리됩니다. 그 호출은 반환된 이전 generation의 개수나 새 generation 중
한쪽에만 나타나고, 둘 다에 나타나지 않습니다. `innoDICallHistorySnapshot`은
현재 generation과 모든 selector 개수를 하나의 집계 연산으로 읽습니다.

`Sendable` mock에서는 호출 기록, 집계 snapshot, stub 접근, reset이
`DIConcurrentMockState` 임계 영역 하나를 공유합니다. `@MainActor` mock에서는
MainActor 직렬화가 같은 순서를 보장합니다. 일반 mock은 문서화된 단일 executor
계약을 유지하므로, 호출자는 여러 executor에서 동시에 접근하면 안 됩니다.

메서드는 호출 기록과 stub 값을 캡처하는 시점에 활성인 generation에 속합니다.
그 뒤에 하는 작업은 이미 시작된 호출의 일부로 남으며, reset은 임의의 사용자
작업을 취소하지 않습니다. `.calls`는 모든 stub과 설정 flag를 보존합니다.
`.all`은 backing 값과 설정 flag를 함께 초기화하므로, reset 뒤에
`missingStubSelectors`가 그 멤버를 다시 보고합니다. 생성된 helper 이름이
충돌하면 protocol requirement를 조용히 가리지 않고 fail closed합니다.

## 아직 지원하지 않는 것

첫 버전은 다음 requirement를 `mock.unsupported-member` 경고로 의도적으로
거부합니다. 이 중 하나라도 있으면 깨진 conformance가 생성되므로, InnoDI는 부분
mock을 합성하지 않습니다.

* `static`과 `class` requirement(RFC 0001 4단계).
* custom global-actor protocol과 개별 actor 격리 requirement. protocol 수준의
  `@MainActor`는 지원합니다.
* `mutating`이 아닌 함수 requirement modifier. `nonisolated`, `borrowing`,
  `consuming`도 포함합니다.
* `subscript` requirement(아직 안정적인 lowering이 없습니다).
* `inout` 파라미터(호출 기록 storage에 복사 정책이 필요합니다).
* `rethrows` requirement. typed `throws(ErrorType)`는 non-generic
  requirement에서 지원하며, generic typed-throws requirement는 부분
  conformance를 생성하지 않고 소스 attribute에서 실패합니다.
* opaque `some` 반환 타입.
* associated type. RFC가 pinning과 모듈 간 해석 경로를 정할 때까지 그런 mock은
  직접 작성하세요.
* `AnyObject`와 `Sendable`이 아닌 protocol 상속. attached peer 매크로는
  파일이나 모듈을 넘어 상속된 requirement를 볼 수 없으므로, InnoDI는
  conformance가 불완전할 수 있는 mock을 생성하지 않고 fail closed합니다.

protocol에 멤버가 하나도 없으면 매크로는 정보성 `mock.experimental-skeleton`
note를 내어, 도입하는 쪽이 매크로 plugin이 attribute를 봤는지 확인할 수 있게
합니다.

## 진단

| 코드 | 심각도 | 원인 |
|---|---|---|
| `mock.requires-protocol` | error | `@GenerateMock`이 protocol 선언이 아닌 곳에 붙었습니다. |
| `mock.experimental-skeleton` | note | protocol에 멤버가 없어 매크로가 빈 mock skeleton을 생성합니다. |
| `mock.unsupported-member` | warning | protocol 멤버 하나 이상이 합성을 막습니다. 해당 이름이 진단 메시지에 나옵니다. |

DiagnosticsGuide 문서는 모든 InnoDI 진단을 같은 코드로 나열하고 복구 방법으로
연결합니다.

## InnoDI mock으로 부족할 때

`@GenerateMock`은 InnoDI가 호출 위치를 모호하게 남기지 않고 합성할 수 있는
protocol 형태만 의도적으로 다룹니다. 테스트가 위에서 말한 지원하지 않는
requirement(associated type, `subscript`, `inout`, `rethrows`, opaque 반환,
`static`/`class` 멤버)를 만나면, 생성된 형태를 그 자리에서 확장하기보다 외부
mocking framework를 쓰기를 권장합니다.

InnoDI와 함께 쓰기 좋은 출발점:

* protocol에 `static` requirement, custom global actor, associated-type
  binding이 필요하면 protocol-witness나 partial-mock 패턴을 지원하는 서드파티
  라이브러리가 잘 맞습니다.
* 작은 protocol에는 손으로 쓴 conforming struct/class가 여전히 가장 가벼운
  선택입니다. 매크로는 반복되는 boilerplate를 없애려는 것이지, 일회성
  conformance를 대체하려는 것이 아닙니다.
* 아직 설계 중이라 빠르게 바뀌는 protocol에는 API가 안정될 때까지 손으로 쓴
  mock을 쓰세요. 형태가 정해지면 `@GenerateMock`으로 바꾸는 일은 기계적입니다.

InnoDI overrides builder는 conforming 인스턴스라면 무엇이든 받으므로, mock
라이브러리 선택은 컨테이너 표면과 무관합니다. 외부 mock은 test target에만 두고
버전을 `InnoDI`와 따로 고정하세요. 생성된 경로와 손으로 쓴 경로는 그래프
검증에 영향을 주지 않고 함께 쓸 수 있습니다.

## 안정성

* `@GenerateMock`은 experimental opt-in API입니다. attribute 자체는
  안정적이지만, *생성되는* 멤버 형태(storage 이름, helper struct 이름, 호출
  기록 내부)는 **아직 안정적이지 않으며** GA 전에 바뀔 수 있습니다. 합성된
  내부에 직접 접근하지 말고, 생성된 이름은 `Overrides` builder slot을 통해서만
  쓰세요.
* RFC 0001의 `bundleWithOverrides:` 파라미터는 이후 단계를 위해 예약돼
  있습니다. `Sendable` 동작은 protocol 상속에서 추론하므로, 격리가 production
  계약과 어긋날 수 없습니다.

## See Also

- [RFC 0001 — Macro-driven mock generation](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0001-macro-mock-generation.md)
- <doc:DiagnosticsGuide>
- <doc:Validation>
