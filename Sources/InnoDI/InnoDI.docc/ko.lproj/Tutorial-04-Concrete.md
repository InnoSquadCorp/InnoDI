# 튜토리얼 4 — concrete storage와 protocol storage

`@Provide`는 생성된 storage와 override의 기준으로 선언한 property 타입을
씁니다. concrete nominal 타입은 concrete storage를, `any Protocol`은
existential storage를 만듭니다.

## 목표

같은 의존성을 protocol existential과 concrete struct 두 방식으로 표현해
비교하고, 그 선언이 호출자 API를 어떻게 바꾸는지 봅니다.

## 코드

<!-- innodi:compile -->
```swift
import InnoDI

protocol GreeterProtocol {
    func hello() -> String
}

struct LoudGreeter: GreeterProtocol {
    let audience: String
    func hello() -> String { "HELLO, \(audience.uppercased())" }
}

@DIContainer
struct AppContainer {
    @Input
    var audience: String

    // The declared type selects existential `any GreeterProtocol` storage.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    })
    var greeter: any GreeterProtocol

    // Concrete storage of the struct keeps the static type for callers
    // that need methods or stored properties not part of the protocol.
    @Provide(.shared, factory: { (audience: String) in
        LoudGreeter(audience: audience)
    })
    var loudGreeter: LoudGreeter
}

let container = AppContainer(audience: "world")
print(container.greeter.hello())
print(container.loudGreeter.audience)
```

## 선언 타입이 기준인 이유

storage 형태는 코드 생성보다 더 많은 것에 영향을 줍니다. 호출자에게 보이는
API가 달라집니다.

* protocol storage는 구현 타입을 숨깁니다. 테스트와 preview는 둘러싼
  컨테이너를 다시 만들지 않고 `Overrides`로 다른 conforming 타입을 끼워 넣을
  수 있습니다.
* concrete storage는 구현에만 있는 property와 메서드 시그니처를 드러냅니다.
  호출자는 `LoudGreeter.audience`에 바로 접근할 수 있지만, 다른 구현으로
  바꾸려면 override 경로가 더 넓어져야 합니다.

property 선언은 이미 code review에서 그 trade-off를 드러냅니다. InnoDI는
attribute flag나 매크로 heuristic으로 storage를 고르지 않습니다. factory가
existential property에 concrete 값을 반환할 수는 있지만, 생성되는 storage와
override slot은 여전히 선언한 property 타입이 정합니다.

## 해 보기

* 테스트에서 `greeter`를 다른 `GreeterProtocol` conformer로 override해
  보세요(`overrides.greeter = QuietGreeter()`). slot 타입이 protocol이라
  override가 컴파일되는지 확인하세요.
* 같은 방법을 `loudGreeter`에 써 보세요. override slot이 concrete
  `LoudGreeter`이므로 다른 conformer로 바꾸면 컴파일 오류가 납니다.
* `loudGreeter`의 선언 타입을 `any GreeterProtocol`로 바꿔 보세요. 이제
  override slot이 어떤 conformer든 받고, 호출자는 existential API로
  `audience`에 접근할 수 없게 되는지 확인하세요.

## 다음

- <doc:Tutorial-05-SubContainer>
