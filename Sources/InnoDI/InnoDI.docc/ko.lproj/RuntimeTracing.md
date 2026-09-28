# Runtime Trace

Opt-in runtime provider 활동을 정적 schema-v6 graph와 연결합니다.

## 생성 trace 켜기

Bounded sink를 만들고 runtime module 이름을 `InnoDI-DependencyGraph`가 출력한
target ID에 매핑합니다.

```swift
let buffer = DIBoundedTraceBuffer(capacity: 4_096)
let trace = DITraceContext(
    sink: buffer,
    targetIDsByModule: ["App": "App"],
    generation: 3
)

let container = AppContainer(config: config, _innoDITrace: trace)
```

생성된 eager, on-demand, transient, async, component, sub-container, override
경로가 context를 전달합니다. Target mapping이 있으면 event ID는 graph와 같은
`target::Container.member` 형태입니다. Mapping이 없으면 reflection으로 얻은
module-qualified container path를 사용하며 exact graph 일치를 주장하지 않습니다.

## Event 해석

`ownerID`는 생성 컨테이너 인스턴스, `generation`은 application이 정한 재생성
세대입니다. 한 provider resolution의 `instanceID`가 `start`와 `success`,
`failure`, `cancel`을 연결하고 cache hit와 override는 명시적인 `origin`을
가집니다. `waitStart`와 `waitEnd`에는 기다리는 provider와 instance가 포함됩니다.

Event에는 metadata만 있습니다. Input, resolve 결과, token, 직렬화된 error,
service 설명은 없습니다. InnoDI는 생성 provider 경계만 관찰하며 service가
내부에서 시작한 task나 작업은 관찰하지 않습니다.

기본값은 ``DITraceContext/disabled``입니다. 이 경로에서 생성 owner는 state나
UUID를 할당하지 않고 event와 buffer도 만들지 않습니다. 생성 컨테이너 밖의
수동 경계에만 `DITraceContext.withResolution(providerID:_:)`을 사용하세요.
