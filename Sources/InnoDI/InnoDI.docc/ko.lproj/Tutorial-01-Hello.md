# 튜토리얼 1 — Hello, container

컴파일되고 실행되며 `.shared` 멤버 하나를 노출하는 가장 작은 InnoDI 컨테이너를
만듭니다. 이어지는 튜토리얼은 여기에 새 개념을 하나씩 더합니다.

## 목표

factory 클로저로 만든 의존성 하나만 소유하고, 다른 구성 요소는 없는 컨테이너.

## 코드

<!-- innodi:compile -->
```swift
import InnoDI

struct Greeter {
    func hello() -> String { "Hello, world" }
}

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: { Greeter() })
    var greeter: Greeter
}

let container = AppContainer()
print(container.greeter.hello())
```

## 매크로가 하는 일

* `@DIContainer`는 `init()`, 중첩 `Overrides` builder, `withOverrides` helper
  네 개를 합성합니다. `@Input` 멤버가 없으므로 기본 initializer는 인자를 받지
  않습니다.
* `@Provide(.shared, factory:)`는 주어진 클로저로 컨테이너 인스턴스마다 한 번
  만드는 멤버를 선언합니다. 만든 인스턴스는 cache되어 읽을 때마다
  재사용됩니다.
* 선언한 property 타입이 `Greeter`이므로 생성된 storage와 override도 그
  concrete nominal 타입을 씁니다. 대신 `any Protocol` existential로 선언하면
  existential storage가 만들어집니다.

## 해 보기

* 이름이 다른 `@Provide(.shared, factory: { Greeter() })`를 하나 더 추가하고,
  두 번째 멤버가 따로 cache되는지 확인하세요.

## 다음

- <doc:Tutorial-02-Inputs>
