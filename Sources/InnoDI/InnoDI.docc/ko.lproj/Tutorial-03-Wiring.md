# 튜토리얼 3 — Key path wiring

factory 클로저를 key path 기반 `Type.self` 형식으로 바꿉니다. 생성되는
wiring은 같지만, 선언이 한 줄로 줄고 IDE의 rename 리팩터링에도 함께
반영됩니다.

## 목표

factory 클로저를 직접 쓰지 않고 `AppConfig`로 같은 `Greeter`를 만드는
컨테이너.

## 코드

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let audience: String
}

struct Greeter {
    init(config: AppConfig) { self.audience = config.audience }
    let audience: String
    func hello() -> String { "Hello, \(audience)" }
}

@DIContainer
struct AppContainer {
    @Input
    var config: AppConfig

    @Provide(.shared, Greeter.self, with: [\Self.config])
    var greeter: Greeter
}

let container = AppContainer(config: AppConfig(audience: "world"))
print(container.greeter.hello())
```

## 달라진 점

* `@Provide`의 두 번째 위치 인자는 생성할 타입입니다. 매크로는
  `Greeter.init`을 찾아, 파라미터 label이 연결된 멤버와 맞는 overload를
  고릅니다. 생성된 storage의 기준은 여전히 선언한 property 타입입니다.
* `with: [\Self.config]`는 매크로가 initializer에 넘길 직접 sibling 멤버의 key
  path를 나열합니다. provider wiring은 정식 `\Self.member` 항목(또는 `[]`)만
  받고, 그 직접 멤버 이름(`config`)을 인자 label로 써서
  `Greeter(config: self.config)`를 생성합니다.
* `Greeter.init(config:)`는 해석된 `AppConfig`를 받아 audience를 자기
  property에 담아 둡니다. 같은 이름 wiring은 관계를 클로저 안에 숨기지 않고
  선언 위치에서 보이게 합니다.

## 클로저 형식이 나은 경우

key path wiring은 initializer 시그니처가 선언한 멤버 이름과 맞아떨어진다고
가정합니다. 다음 경우에는 클로저 형식을 쓰세요.

* 생성에 부수 효과(logging, 등록 등)가 필요할 때.
* input을 그대로 넘기지 않고 input에서 인자를 만들어 내고 싶을 때
  (`Greeter(audience: config.audience.uppercased())`).
* initializer가 throwing이거나 async일 때(`factory:`나 `asyncFactory:`를
  쓰세요).

## 해 보기

* `with:` 인자를 지워 보세요. 매크로는 이제 *암묵적* 같은 이름 wiring을
  씁니다. 컨테이너에서 `Greeter.init`의 파라미터와 타입이 맞는 `config`라는
  멤버를 찾습니다. 결과 코드는 같습니다.
* `\Self.config`를 `\AppContainer.config`로 바꾸고
  `provide.invalid-with-dependencies` 진단을 확인하세요. provider wiring은
  정식 직접 멤버 root인 `\Self`만 받습니다.

## 다음

- <doc:Tutorial-04-Concrete>
