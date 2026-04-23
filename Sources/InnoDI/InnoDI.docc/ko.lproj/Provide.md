# Provide

`@Provide`는 컨테이너 멤버와 그 생성 전략을 선언합니다.

## 선언

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

## 생성 방식

- `factory`: 동기 생성식 또는 클로저
- `asyncFactory`: 비동기 생성 클로저
- `Type.self` + `with:`: 명시적 autowiring

## 규칙

- `factory`와 `asyncFactory`는 동시에 사용할 수 없습니다.
- `.input`은 `factory`, `asyncFactory`를 허용하지 않습니다.
- `.shared`와 `.transient`는 생성 전략이 필요합니다.
- `asyncFactory`는 `async` 클로저여야 합니다.
- concrete `.shared` / `.transient` 저장은 `concrete: true`가 필요합니다.
- factory 파라미터와 `with:` 의존성은 멤버 이름 기준으로 엄격하게 해석됩니다.

## See Also

- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- <doc:Validation>
