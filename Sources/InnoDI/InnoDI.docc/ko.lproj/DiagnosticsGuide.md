# 진단 가이드

InnoDI의 매크로와 build-time validator가 emit하는 진단 코드 레퍼런스입니다.

## 개요

InnoDI 매크로가 만드는 모든 error/warning/note는
`InnoDI.<category>.<id>` 형태(예:
`InnoDI.validation.container.dependency-cycle`)의 안정적인 코드를
가집니다. 이 문서는 코드를 카테고리별로 묶고, 각 코드가 언제 발생하는지
설명하고, 복구 경로를 안내합니다. 코드 ID는 grep 가능하도록 만들어졌고,
메시지 텍스트는 ID를 그대로 두면서 릴리스 사이에 다듬어질 수 있습니다.

카테고리 prefix는 진단을 발생시키는 단계를 반영합니다.

- `InnoDI.usage.*` — 매크로가 *어떻게* 부착됐는지에 대한 구조적
  오류 (잘못된 선언 종류, 타입 어노테이션 누락, 충돌하는 attribute).
- `InnoDI.validation.*` — 파싱 이후 validator가 발견하는 의미적
  오류 (factory 누락, 순환, 알 수 없는 의존성, 계층 위반).

## 자주 보이는 복구 패턴

대부분의 진단은 메시지 안에 fix를 직접 담고 있습니다. 반복적으로
보게 되는 패턴은 다음과 같습니다.

- **"`@Provide(.shared, …)` / `.transient` / `.input`을 사용하세요."** —
  선언된 프로퍼티에 대해 scope 인자가 잘못된 경우입니다.
- **"`Lazy<T>`를 직접 표기하세요."** — deferred wrapper에 대해
  `typealias`를 썼습니다. 매크로는 syntax를 읽기 때문에, alias된 형태는
  silent하게 hard edge가 됩니다.
- **"factory 파라미터 하나를 `Lazy<T>`로 감싸세요."** — 의존성 순환은
  edge 하나를 deferred로 만들면 구조 변경 없이 끊을 수 있습니다.
- **"사용자 정의 `Overrides` 타입을 제거하세요."** — 컨테이너의 nested
  타입이 합성된 overrides 빌더와 충돌합니다.
- **"root factory 클로저의 이름 있는 파라미터를 사용하세요."** — sibling DI
  edge는 클로저가 아닌 표현식, property initializer, nested 클로저, 임의
  identifier에서 추론하지 않습니다.

## Provide-scope 진단

가장 자주 만나는 코드:

- `provide.single-binding` — `@Provide`는 선언당 하나의 변수만
  지원합니다.
- `provide.duplicate-attribute` — 한 프로퍼티에 `@Provide`가 둘 이상
  붙었습니다. 정확히 하나만 남기세요. InnoDI는 모호한 선언에 peer storage와
  accessor를 생성하지 않습니다.
- `provide.escaped-identifier-unsupported` — direct provider property 또는
  root factory dependency parameter가 backtick으로 감싼 escaped identifier를
  사용합니다. Unescaped identifier로 이름을 바꾸세요. InnoDI 5.0은 unescaped
  spelling만 storage와 lookup identity로 사용하며 peer 생성 전에 실패합니다.
- `provide.named-property-required` — 바인딩에 이름이 있어야 합니다.
- `provide.explicit-type-required` — 바인딩에 타입 어노테이션이 있어야
  합니다.
- `provide.opaque-type-unsupported` — 명시적 property type이
  `some Protocol`입니다. 생성 storage와 override에는 안정적인 타입이 필요하므로
  existential `any Protocol`로 노출하세요.
- `provide.iuo-type-unsupported` — 명시적 property type이 implicitly
  unwrapped optional `T!`입니다. Storage와 sibling wiring의 optionality 계약을
  하나로 만들도록 명시적인 `T` 또는 `T?`로 바꾸세요.
- `provide.unknown-scope` — `.shared` / `.transient` / `.input`만
  받습니다.
- `provide.input-invalid-configuration` — `.input` 멤버는 factory,
  type, async factory, dependency wiring 설정을 가질 수 없습니다.
- `provide.escaping-invalid-scope` — `.input`이 아닌 scope에서
  `escaping: true`를 사용했습니다. `.shared` / `.transient`에서는 제거하세요.
  Escaping input 저장만 지원되는 용도입니다.
- `provide.escaping-nonfunction-type` — 명백한 nonfunction 또는 optional
  function type 형태에 `@Provide(.input, escaping: true)`를 사용했습니다. Alias
  뒤에 숨은 non-optional function type에만 사용하세요. 매크로는 alias를 해석할 수
  없어 identifier/member type을 보수적으로 허용하므로, 실제 alias가 non-optional
  function type이 아니면 Swift 자체 진단이 추가될 수 있습니다.
- `provide.shared-factory-required` — `.shared`는 `factory:`, `type:`,
  또는 property initializer가 필요합니다.
- `provide.transient-factory-required` — `.transient`는 `factory:`,
  `asyncFactory:`, `Type.self`, 또는 property initializer가 필요합니다.
- `provide.factory-conflict` — `factory:`와 `asyncFactory:`가 둘 다
  주어졌습니다.
- `provide.construction-source-conflict` — `factory:`, `asyncFactory:`,
  `Type.self`, property initializer 중 둘 이상을 함께 사용했습니다. 생성
  source는 정확히 하나만 남기세요.
- `provide.with-requires-type-construction` — `with:`를 factory 또는
  property initializer와 함께 사용했습니다. `with:`는 `Type.self` wiring에서만
  사용하고 factory closure의 edge는 이름 있는 파라미터로 선언하세요.
- `provide.async-factory-invalid-scope` — `asyncFactory:`는 `.shared`와
  `.transient`에서 유효하지만 `.input`에서는 사용할 수 없습니다.
- `provide.async-factory-must-be-async` — 주어진 closure가 `async`가
  아닙니다.
- `provide.factory-must-be-sync` — `factory:`에 `async` closure가
  주어졌습니다. async construction은 `asyncFactory:`로 옮기세요.
- `provide.factory-must-not-throw` — `factory:`에 throwing closure가
  주어졌습니다. 에러를 factory 내부에서 처리하거나 asynchronous throwing
  작업은 `asyncFactory:`로 옮기세요.
- `provide.bool-literal-required` — `@Provide` Bool 옵션 `escaping:`은 literal
  `true` 또는 `false`여야 합니다.
- `provide.invalid-with-dependencies` — `with:`가 정확히 `\Self.member`로
  표기한 canonical direct-member key path만 담은 literal 배열 또는 `[]`가
  아닙니다. 이름이 있는 container, module-qualified, typealias root, nested
  component, optional chaining, subscript, runtime 배열, 계산된 원소는 거부됩니다.
- `provide.requires-direct-container-member` — `@Provide`가 지원되는
  `@DIContainer` struct의 직접적이고 평범한 stored instance `var`가 아닌 곳에
  붙었거나 지원하지 않는 accessor/storage modifier를 사용했습니다. 의존성을
  해당 컨테이너 안으로 옮기고 `let`, computed/observer accessor block, `lazy`,
  `weak`, `unowned`, `static`/`class`, setter-access modifier, property wrapper,
  conditional/unknown attribute를 제거하세요. `@Provide` 외에 source에 직접 쓰는
  property-level attribute는 지원하지 않으며 `@MainActor`도 포함됩니다. Actor
  격리는 `@DIContainer(mainActor: true)`로 요청하세요. Provider 선언과 accessor에
  InnoDI가 생성한 격리 attribute는 내부 compiler support입니다.
- `provide.conditional-declaration-unsupported` — `@Provide` 선언 전체가
  `#if` 안에 있습니다. 선언은 conditional compilation 밖으로 옮기고 factory나
  주입 구현 내부에서 분기하세요. 이렇게 해야 peer/accessor macro phase가 일부
  provider만 생성하는 것을 막을 수 있습니다.
- `provide.generated-accessor-manual-attachment` — InnoDI 내부 provider
  accessor 매크로(`_InnoDIProvideAccessor`)를 수동으로 붙였습니다. 이를 제거하고
  컨테이너의 직접 멤버에 `@Provide`를 사용하세요. Accessor는 compiler-owned입니다.
  다른 property wrapper와 의도적으로 위조해 조합한 경우 Swift 자체의 structural
  diagnostic도 함께 발생할 수 있으며, 이 compiler 진단은 안정적인 InnoDI 코드와
  함께 나타나는 것이 예상된 동작입니다.
- `provide.duplicate-factory-parameter` — root factory closure에 같은
  effective parameter 이름이 둘 이상 있습니다. 일반 파라미터와 `Lazy<T>`,
  `Provider<T>` 사이의 중복도 포함됩니다. 모든 dependency parameter에 고유한
  이름을 부여하세요. InnoDI는 dependency lookup table이나 peer storage를 만들기
  전에 해당 provider를 거부합니다.
- `provide.unresolved-factory-parameter` — root factory 클로저의 이름 있는
  파라미터가 컨테이너 멤버나 `with:` key path와 매칭되지 않습니다.
- `provide.unavailable-dependency-reference` — factory가 더 늦게
  선언되어 그 construction 시점에 사용할 수 없는 멤버를 참조합니다.
- `provide.async-dependency-requires-async-consumer` — 동기 factory가 async
  provider를 명시적 sibling edge로 소비합니다. Consumer를 `asyncFactory:`로
  옮기세요. 이 검증은 `validateDAG: false`에서도 동작합니다.
- `provide.throwing-dependency-requires-throwing-consumer` — nonthrowing
  factory가 `async throws` provider를 소비합니다. Consumer의
  `asyncFactory:` 클로저를 `async throws`로 만드세요. 이 검증은
  `validateDAG: false`에서도 동작합니다.
- `provide.with-dependency-requires-synchronous-provider` — `Type.self` +
  `with:`가 async 또는 async-throwing provider를 가리킵니다. Swift key path는
  동기 프로퍼티만 지원하므로 consumer를 이름 있는 파라미터를 가진
  `asyncFactory:`로 다시 작성하세요.
- `provide.unresolved-with-dependency` — `with:` key path가 컨테이너
  멤버를 가리키지 않습니다.
- `provide.lazy-unsupported-target` — `Lazy<T>`가 `asyncFactory:`로
  생성되는 멤버를 가리킵니다. lazy resolver는 동기 방식입니다.
- `provide.lazy-eager-call` — `Lazy<T>`가 `.shared` construction 시점에
  호출되어 soft edge가 다시 eager edge가 됐습니다.
- `provide.provider-non-transient-target` — `Provider<T>`가 `.shared`
  또는 `.input`로 해소됐습니다. provider는 `.transient` target이 필요합니다.
- `provide.provider-unsupported-target` — `Provider<T>`가 async transient
  멤버를 가리킵니다. provider handle은 동기 방식입니다.
- `provide.provider-eager-call` — `Provider<T>`가 construction 시점에
  호출되어 그 의도가 무력화됐습니다.
- `provide.lazy-aliased` / `provide.provider-aliased` — `Lazy<T>` /
  `Provider<T>`에 대한 `typealias`를 썼습니다. 직접 표기로 다시
  쓰세요.
- `transient-factory.unnamed-parameters` — transient factory closure가
  shorthand나 와일드카드 파라미터를 썼습니다. InnoDI가 주입할 수 있도록
  파라미터에 이름을 붙이세요.

## 컨테이너 단위 진단

- `container.unsupported-declaration-kind` — `@DIContainer`가 class, actor,
  enum, protocol, extension 등 struct가 아닌 선언에 직접 붙었습니다.
  경계를 비제네릭 struct로 옮기고 런타임 상태는 `.input` 멤버로
  주입하세요.
- `container.private-access-unsupported` — 컨테이너가 명시적으로 `private`라서
  sibling container가 생성된 mount surface에 접근할 수 없습니다. 같은 파일에서
  mount하려면 `fileprivate`를 사용하거나, private namespace 안에 default-access
  container를 중첩하세요.
- `container.generic-unsupported` — 컨테이너가 generic parameter를
  선언했거나 generic nominal 선언 안에 중첩됐습니다. 타입별 동작은
  주입되는 의존성 뒤로 옮기세요.
- `container.unverifiable-enclosing-context` — 컨테이너가 extension 안에
  선언되어 syntax-only 매크로가 확장 대상 타입의 generic 여부를 증명할
  수 없습니다. 선언을 file scope 또는 비제네릭 nominal 안으로 옮기세요.
- `container.local-declaration-unsupported` — 컨테이너가 함수, closure,
  initializer, accessor, switch case, local block 같은 실행 스코프 안에
  선언됐습니다. file scope 또는 비제네릭 nominal 선언 안으로 옮기세요.
  generic 함수 안에 타입을 중첩하거나 local container에 `@DIComponent` 같은
  attached-extension macro를 함께 적용하는 등 Swift 언어 자체가 허용하지
  않는 위치에서는 Swift compiler 진단이 함께 나올 수 있습니다.
  현재 Swift toolchain은 computed-property body 안 타입의 attached macro
  context에서 accessor ancestry를 누락합니다. 이 형태는 build-validation
  plugin과 graph CLI의 full-source preflight가 같은 진단으로 차단합니다.
  full-source preflight가 없으면 accessor-local component에서 Swift 또는
  함께 적용한 companion macro의 추가 진단이 발생할 수 있습니다.
- `container.unknown-dependency` — 참조된 이름이 어떤 컨테이너
  멤버에도 매핑되지 않습니다.
- `container.dependency-cycle` — hard cycle이 감지됐습니다. `Lazy<T>`
  또는 `Provider<T>`로 끊거나 ownership을 재구성하세요.
- `container.custom-init-unsupported` — `@DIContainer`는 이미
  initializer를 합성합니다. 사용자가 작성한 것을 제거하세요. annotation body의
  initializer는 macro가 진단합니다. compiler-plugin macro 입력에는 sibling extension이
  없으므로, 같은 파일 또는 다른 파일 extension의 initializer는 필수
  `InnoDIDAGValidationPlugin` full-source pass가 진단합니다.
- `container.unmanaged-stored-property` — stored instance member에 `@Provide`와
  `@SubContainer`가 모두 없습니다. 빈 컨테이너까지 전체 initializer를 InnoDI 5.0이
  소유하므로 annotation을 추가하거나 computed/static property로 바꾸세요.
- `container.overrides-name-conflict` — 사용자의 nested `Overrides`
  타입이 필수 합성 빌더와 충돌합니다. InnoDI 5.0에서는 오류로 처리하므로
  사용자 선언의 이름을 바꾸세요. 진단 전용 recovery initializer가 mount된
  child container에서 무관한 Swift argument 오류가 연쇄되는 것을 막습니다.
- `container.mainactor-conflict` — `@DIContainer(mainActor: true)`가 container
  또는 dependency member의 다른 global actor와 충돌합니다. custom actor를
  제거하거나 `mainActor` 생성을 비활성화하세요.
- `container.mainactor-nonisolated-member` — `@Provide` 또는 `@SubContainer`
  member가 `nonisolated`로 격리를 해제해 container의 `mainActor: true`
  계약과 충돌합니다.
- `container.bool-literal-required` — `root:`, `validateDAG:`,
  `mainActor:`가 literal `true` 또는 `false`가 아닙니다. build
  configuration별 attribute 분기는 conditional compilation을 쓰세요.
- `container.duplicate-member-name` — `@Provide`/`@SubContainer` 조합을
  포함해 직접 선언된 managed instance member 둘이 같은 property 이름을
  사용합니다. 한 property의 이름을 바꾸세요. InnoDI는 뒤쪽 선언을 진단하고
  첫 선언 위치를 note로 표시하며 모호한 identity의 support를 억제합니다.
- `container.generated-symbol-collision` — 서로 다른 managed property
  이름이 같은 hidden storage, override 또는 child-builder symbol로
  매핑됩니다. `@Provide`나 `@SubContainer` property 하나의 이름을 바꾸세요.
  InnoDI는 source-order first-claim-wins 진단을 사용하고 모든 managed
  accessor를 recovery로 전환해 Swift의 invalid redeclaration과 잘못된
  storage type 연쇄 오류를 막습니다.
- `container.reserved-name-prefix` — direct container declaration이 매크로가
  generated storage와 support용으로 예약한 prefix (`_storage_`, `_override_`,
  `_innoDI`, `_InnoDI`)로 시작합니다. Plain variable, function, nested nominal
  type, typealias, top-level `#if` 안의 선언도 포함합니다. 선언 이름을 변경하세요.
- `container.reserved-module-name` — container 자체, enclosing nominal,
  `InnoDI`라는 direct declaration, 또는 `Swift`나 `_Concurrency`라는 direct
  nested type/typealias가 generated support의 module qualifier를 가립니다.
  선언 이름을 변경하세요. 값 namespace의 `Swift`, `_Concurrency` 멤버는 계속
  사용할 수 있습니다. Target-scoped full-source preflight는 같은 진단을 sibling
  file, enclosing member, matching extension, import한 dependency target에서
  보이는 선언까지 확장합니다.
- `generated-qualifier.inheritance-unverifiable` — generated site인 class 또는
  generated site를 lexical scope로 감싸는 class의 첫 inherited type을
  target-scoped source index가 하나로 해소할 수 없습니다. 첫 inherited 위치에는
  superclass가 올 수 있으므로 validator는 container 또는 bridge support를
  생성하기 전에 source-visible class와 typealias chain을 따라갑니다. 이 위치의
  source-visible protocol은 superclass scan을 끝내지만 SDK·binary에만 있거나,
  해소되지 않거나, 모호한 declaration은 fail closed합니다. Generated site를
  struct/enum 또는 source-visible adapter로 옮기거나 inheritance chain을 indexed
  source로 제공하세요. 이 validator는 외부 module을 type-check하지 않는 보수적인
  syntactic index입니다. Class bridge에서는 상속된 type member `Swift`와
  `SwiftUI`가 해당 reserved-module 진단을 받지만 상속된 `InnoDISwiftUI`는
  안전합니다. 다만 직접 또는 lexical scope에서 보이는 같은 이름의 declaration은
  계속 예약됩니다.

## SubContainer 진단

- `sub.single-binding`, `sub.named-property-required`,
  `sub.explicit-type-required` — `@Provide`와 같은 구조적 규칙.
- `sub.scope-required` — `@SubContainer`는 명시적
  `scope: .shared` 또는 `.transient`가 필요합니다.
- `sub.escaped-identifier-unsupported` — `@SubContainer` property가
  backtick으로 감싼 escaped identifier를 사용합니다. Child storage, override,
  SwiftUI helper identity가 canonical하도록 unescaped identifier로 바꾸세요.
- `sub.requires-direct-container-member` — `@SubContainer`가 지원되는
  `@DIContainer` struct의 직접적이고 평범한 stored instance `var`가 아닙니다.
  해당 컨테이너로 옮기고 accessor, storage modifier, wrapper, unknown
  attribute를 제거하세요.
- `sub.conditional-declaration-unsupported` — child 선언 전체가 `#if`
  안에 있습니다. Storage, accessor, parent init 매크로 단계가 일부만
  확장하지 않도록 conditional compilation 밖으로 옮기세요.
- `sub.duplicate-attribute` — 한 property에 `@SubContainer`가 두 번 이상
  선언됐습니다. Child-container attribute를 하나만 남기세요.
- `sub.generated-accessor-manual-attachment` — InnoDI의 숨은
  `_InnoDISubContainerAccessor`를 수동으로 붙였습니다. 제거하세요. 이 compiler
  support는 parent container가 소유합니다.
- `sub.unknown-scope` — `scope:` 값이 `.shared`나 `.transient`가
  아닙니다.
- `sub.conflicts-with-provide` — 한 프로퍼티에 두 attribute를 동시에
  달 수 없습니다.
- `sub.overrides-name-conflict` — 생성된 child override 헬퍼 storage가
  기존 parent 멤버 이름과 충돌합니다.
- `sub.unknown-parent-member` — `with:` key path가 parent 컨테이너
  멤버에 매핑되지 않습니다.
- `sub.unknown-child-input` — `bindings:` child key path가 child
  input에 매핑되지 않습니다.
- `sub.bindings-conflicts-with-with` — 같은 `@SubContainer`에
  `bindings:`와 `with:`가 함께 나타났습니다 (wiring 형태는 상호
  배타적).
- `sub.invalid-same-name-wiring` — `with:`가 매크로가 읽을 수 있는
  literal key-path 배열이 아닙니다 (런타임 변수와 계산된 원소는 거부).
- `sub.invalid-bindings` — `bindings:`가 literal `(child:parent:)`
  key-path tuple 배열이 아닙니다.
- `sub.auto-wiring-ambiguous` — parent에 여러 `@Provide` 후보가 있어
  implicit same-name wiring을 추론할 수 없습니다. 명시적 `with:` /
  `bindings:`를 추가하거나, child가 parent input을 받지 않는 경우
  `with: []`을 쓰세요.
- `sub.duplicate-child-binding` — 같은 child input이 두 번 바인딩됐습니다.
- `sub.shared-parent-must-not-be-transient` — `.shared`
  sub-container는 `.transient` parent를 읽을 수 없습니다.

## 그래프 단위 진단 (build plugin)

- `graph.dependency-cycle` — 글로벌 DAG (`@DIComponent` 그래프 전반)에서
  cycle이 감지됐습니다.
- `graph.ambiguous-container-reference` — 한 이름이 여러 컨테이너에
  매칭됐습니다.

## SwiftUI 진단

- `swiftui.feature-root-duplicate-default` — `@SubContainer`에 default
  feature root가 두 개 이상 선언됐습니다.
- `swiftui.feature-root-helper-name-conflict` — 생성된 헬퍼 이름이
  기존 멤버와 충돌합니다.
- `swiftui.feature-root-invalid-alias` — feature-root alias 인자가
  유효한 Swift identifier로 파싱되지 않습니다.
- `swiftui.feature-root-invalid-root` — `featureRoot:` 또는 `featureRoots:`
  항목이 `RootView.self` 같은 root view 타입 표현식을 사용하지 않았습니다.
- `swiftui.environment-bridge-unknown-member` — `@DIEnvironmentBridge`
  key path가 컨테이너 멤버로 해소되지 않습니다.
- `swiftui.environment-bridge-duplicate-member` — 같은 key path가
  두 번 나열됐습니다.
- `swiftui.environment-bridge-async-member` — `asyncFactory` 기반의
  컨테이너 멤버가 `EnvironmentValues`로 매핑됐습니다. synchronous
  값을 노출하거나, 내부에서 async 작업을 수행하는 service를
  주입하세요.
- `swiftui.environment-bridge-invalid-keypath` — `environment:`가
  `EnvironmentValues` 또는 `SwiftUI.EnvironmentValues`를 root로 하는 하나의
  direct-property key-path literal이 아닙니다. 생성 코드에서 lexical capture
  없이 key path를 보존하기 위해 alias, 다른 root, chain, subscript를 거부합니다.
- `swiftui.environment-bridge-invalid-arguments` — bridge 매크로가
  지원되는 key-path 리스트 형태 외의 인자를 받았습니다.
- `swiftui.environment-bridge-reserved-module-name` — bridge 대상이나 이를
  감싸는 nominal·generic parameter, 또는 target의 direct nested
  type/typealias에 있는 `Swift`/`SwiftUI`/`InnoDISwiftUI` 이름이 생성 modifier의
  module qualifier를 가립니다. 타입 선언이나 generic parameter 이름을
  바꾸세요. 같은 이름의 값 멤버는 계속 사용할 수 있습니다. 필수
  target-scoped full-source preflight는 attached macro가 검사할 수 없는 sibling
  file, enclosing member, matching extension, import한 dependency target에서
  보이는 선언까지 같은 진단으로 차단합니다.
- `swiftui.environment-bridge-generated-name-conflict` — bridge target이 생성
  멤버를 다시 선언했습니다. `_InnoDIEnvironmentBridgeModifier`는 direct nested
  nominal type, protocol, typealias, static/class variable·function, enum
  case와 충돌하고,
  `_innoDIEnvironmentBridgeModifier`는 direct instance variable 또는 parameter가
  없는 instance function과만 충돌합니다. Top-level `#if` branch는 재귀적으로
  검사합니다. 대문자 이름의 instance value/function, 소문자 이름의 static/class
  member와 parameter가 있는 overload, target·generic parameter 이름, 반대
  namespace의 선언, nested body 안의 선언은 계속 사용할 수 있습니다.
- `swiftui.environment-bridge-extension-context-unsupported` — bridge 대상이
  extension이거나 extension 안에 중첩되어 있습니다. Attached syntax macro는
  생성 전 다른 파일의 extension-member lookup을 검증할 수 없으므로 file 또는
  nominal scope로 옮기세요. Target-scoped full-source preflight는 source compile
  전에 두 형태에 모두 이 진단을 내며, 필수 plugin을 연결하지 않으면 direct
  extension attachment를 Swift가 먼저 거부할 수 있습니다.
- `swiftui.environment-bridge-local-declaration-unsupported` — bridge 대상이
  function, initializer, deinitializer, subscript, accessor 또는 closure 안에
  선언되어 있습니다. 생성 conformance가 안정적인 lookup path를 갖도록 file
  또는 nominal scope로 옮기세요. Attached macro가 Swift의 local-declaration
  진단보다 먼저 이 경계를 안정적으로 소유할 수 없으므로 build/CLI
  full-source pass가 내는 진단입니다.
- `swiftui.environment-bridge-unsupported-declaration-kind` — bridge 대상이
  actor, protocol 또는 다른 지원하지 않는 선언 종류입니다. Struct, class,
  enum으로 옮기세요.
- `swiftui.environment-bridge-private-nested-target` — 생성 conformance path에
  다른 타입 안에 중첩된 `private` target 또는 enclosing nominal이 있습니다.
  해당 private lookup component를 `fileprivate` 또는 default access로 바꾸세요.
  File-scope private target은 계속 지원하며 생성 protocol witness는
  `fileprivate`로 넓어집니다.
- `swiftui.environment-bridge-parameter-pack-unsupported` — bridge target이
  generic parameter pack을 선언합니다. 일반 generic parameter를 사용하거나
  bridge를 non-generic adapter type으로 옮기세요. InnoDI 5.0은 Swift의
  variadic-generics runtime에서 trap 가능한 modifier 생성을 fail closed합니다.

## Component / Hierarchy 진단

- `component.escaped-target-unsupported` — `@DIComponent` 대상이 backtick으로
  감싼 escaped identifier를 사용합니다. 생성되는 `<Container>Dependencies`
  peer가 하나의 canonical Swift 이름을 갖도록 타입을 unescaped identifier로
  바꾸세요. 이 진단은 peer macro만 소유하며 member와 extension role은 진단
  사본이나 잘못된 support 선언을 만들지 않고 fail closed합니다.
- `component.requires-container` — `@DIComponent`는
  `@DIContainer`로 표시된 타입에 부착되어야 합니다.
- `component.overrides-builder-required` — `@DIComponent`는 합성된
  overrides 빌더가 필요합니다.
- `hierarchy-root.requires-container` — `@DIHierarchyRoot`는
  `@DIContainer` 타입에 부착되어야 합니다.

## Mock generation 진단

- `mock.requires-protocol` — `@GenerateMock`가 protocol 선언이 아닌
  struct/class/enum 등에 붙었습니다. attribute를 protocol로 옮기거나
  제거하세요.
- `mock.experimental-skeleton` — protocol에 member가 없을 때 note로
  발생합니다. 매크로 plugin이 attribute를 보고 빈 mock skeleton을
  생성했음을 확인하는 신호입니다.
- `mock.unsupported-member` — static/class requirement, subscript,
  associated type, `inout` parameter, `rethrows`/typed `throws`,
  opaque `some` return type 등 때문에 mock synthesis가 불가능합니다.
  메시지에 최대 다섯 개의 member 이름이 표시되며, 해당 mock은 수동
  구현해야 합니다.

## Preview macro 진단

- `swiftui.preview-with-container-missing-container` —
  `#PreviewWithContainer`가 첫 번째 container expression 없이 호출됐습니다.
- `swiftui.preview-with-container-missing-closure` —
  `#PreviewWithContainer`가 preview body closure 없이 호출됐습니다.
- `swiftui.preview-with-container-missing-parameter` —
  `#PreviewWithContainer` body closure가 macro가 전달하는 container
  파라미터를 선언하지 않았습니다.

## 내부 진단

- `internal.codegen-invariant` — 코드 생성기가 validation이 거부했어야
  하는 케이스를 만났습니다. 메시지에 내부 설명이 포함됩니다. 전체 진단
  텍스트와 함께 버그 리포트를 부탁드립니다.
