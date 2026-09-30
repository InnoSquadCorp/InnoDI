# 튜토리얼 2 — 외부 input

컨테이너가 소유하지 않는 설정 값을 추가합니다. `@Input` 멤버는 초기화할 때
전달되고, 그 뒤로는 읽기 전용입니다.

## 목표

런타임 설정 값을 받아, 그 값에 맞춰 메시지를 바꾸는 greeter를 만드는 컨테이너.

## 코드

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let audience: String
}

struct Greeter {
    let audience: String
    func hello() -> String { "Hello, \(audience)" }
}

@DIContainer
struct AppContainer {
    @Input
    var config: AppConfig

    @Provide(.shared, factory: { (config: AppConfig) in
        Greeter(audience: config.audience)
    })
    var greeter: Greeter
}

let container = AppContainer(config: AppConfig(audience: "world"))
print(container.greeter.hello())
```

## 달라진 점

* `@Input`은 합성된 initializer에 `config: AppConfig`를 추가합니다. 매크로는
  property 타입에서 파라미터를 추론해 `init(config: AppConfig)`를 생성합니다.
* 이제 factory 클로저가 `config`를 파라미터로 받습니다. 매크로는 클로저
  파라미터 목록을 읽고, `config`를 같은 이름의 컨테이너 멤버에 맞춰 자동으로
  연결합니다.
* `container.greeter`를 읽으면 cache된 `.shared` slot을 거칩니다. property를
  여러 번 읽어도 factory는 최대 한 번만 실행됩니다.

## 해 보기

* factory 파라미터 이름을 `config`에서 `cfg`로 바꾸고
  `provide.unresolved-factory-parameter` 진단을 확인하세요. 이름 해석은
  의도적으로 엄격합니다.
* `@Input`을 하나 더 추가하고, 합성된 initializer가 두 인자를 모두 받는지
  확인하세요.

## 다음

- <doc:Tutorial-03-Wiring>
