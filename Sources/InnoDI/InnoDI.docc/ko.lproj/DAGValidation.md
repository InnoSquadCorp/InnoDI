# DAG 검증

`@DIContainer(validateDAG:)`는 컨테이너가 global dependency graph gate에
참여할지 정합니다. 이 flag는 의도적으로 범위가 좁지만, 그 뒤에 있는
trade-off는 잘못 쓰기 쉽습니다. 이 가이드는 flag가 실제로 무엇을 건너뛰는지,
언제 꺼도 되는지, 끈 상태가 production 릴리스로 새지 않게 하는 방법을
설명합니다.

## `validateDAG: false`가 끄는 것

`validateDAG: false`는 정확히 두 층만 끕니다.

1. 매크로의 graph-derived 가용성 진단(소유권 순환은 제외).
2. global DAG 검증에 대한 컨테이너의 기여
   (`swift run InnoDI-DependencyGraph --root . --validate-dag`).

다음은 **끄지 않습니다**.

- `Lazy<T>`와 `Provider<T>` edge를 포함한 로컬 소유권 순환 검출.
- 구조적 매크로 진단(scope 규칙, missing factory, declaration-order 가용성,
  async factory 유효성).
- `@Provide`의 직접적이고 평범한 stored instance `var` 선언 계약.
- 명시적 sibling edge의 효과 호환성.
- component와 root `@DIContainerRole` 선언에 대한 빌드 시점 계층 검증.
- 파일을 넘나드는 custom `init` 검증.
- <doc:Validation>에 문서화된 artifact 계약.

명시적 sibling edge는 root `factory:`/`asyncFactory:` 클로저 리터럴의 이름
있는 파라미터, 또는 `Type.self`와 literal `with:` key path에서만 만들어집니다.
이 edge의 sync/async/throwing 호환성은 `validateDAG: false`에서도 필수입니다.
클로저가 아닌 factory와 property initializer는 opaque한 zero-edge source이며
sibling 컨테이너 멤버를 참조하면 안 됩니다.

`validateDAG: false`를 쓴 consumer는 로컬 소유권 순환, 선언, 효과 안전성은
유지하지만, 컨테이너를 넘나드는 global graph 검사는 잃습니다.

## 꺼도 되는 경우

좁은 경우에는 이 flag가 합리적입니다.

- wiring을 잠시 쓸 수 없는 staging build나 feature-flag fixture. 로컬 순환은
  여전히 오류이며, 이 flag로 허용할 수 없습니다.
- 테스트 하나, 또는 저장소와 함께 배포되지만 제품과는 함께 배포되지 않는
  scratchpad 실행 파일 안에서만 쓰는 임시 재현용 컨테이너.
- 컨테이너를 더 작은 그래프로 쪼개는 마이그레이션 기간에, 진행 중인 중간
  그래프가 global 검증에 실패한다는 것을 알고 있는 경우.

모두 *일시적인* 상태입니다. `validateDAG: false`가 그것을 정당화한 작업보다
오래 남으면, 검증 공백이 원래의 제약보다 오래 남아 조용히 넓어집니다.

## 끄면 위험한 경우

다음에는 `validateDAG: false`가 맞는 도구가 아닙니다.

- Production 릴리스 브랜치.
- "CI를 빠르게 하고 싶을 뿐입니다." (먼저 synthetic-consumer benchmark로 실제
  비용을 재 보세요. global DAG validator는 build plugin을 통해 분석을
  cache하므로 병목이 되는 일은 드뭅니다.)
- 실제 순환을 드러내는 진단을 피하려는 경우. 그래프를 재구성하거나 공유 상태를
  독립 의존성으로 분리하세요. `Lazy<T>`와 `Provider<T>`는 해석을 미루지만
  소유권 순환을 면제하지 않습니다.

"경고를 없애려고" `validateDAG: false`를 꺼냈다면 변경을 되돌리고 진단을
기준으로 삼으세요.

## 설정에 따라 강제하기

매크로의 Boolean 옵션은 literal `true` 또는 `false`여야 합니다. production
컨테이너는 검증을 켠 채로 유지하세요.

<!-- innodi:compile -->
```swift
import InnoDI

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: 42)
    var value: Int
}
```

일시적으로 검증을 끄려면 별도로 선택하는 scratch 또는 test target에 전용
컨테이너 선언을 두세요. 해당 target은 production 애플리케이션에 포함하면
안 됩니다.

<!-- innodi:compile -->
```swift
import InnoDI

@DIContainer(validateDAG: false)
struct MigrationFixtureContainer {
    @Provide(.shared, factory: 42)
    var value: Int
}
```

`#if FAST_BUILD` / `#else` / `#endif`로 부착 매크로 attribute와 선언을
나누지 마세요. 각 분기에 완전한 선언을 반복해도 소스 기반 그래프 검증에는
충분하지 않습니다. 검증기는 컴파일러의 활성 조건을 전달받지 않으므로
분기를 선택하거나 합칠 수 없습니다. 조건부 선언의 identity가 반복되면
모든 선언 위치와 함께 `graph.conditional-identity-unresolved`를 진단합니다.
빌드 target의 소스 파일 선택으로 정의를 하나만 포함하거나, 컨테이너 선언은
하나로 유지하고 factory 내부의 구현만 조건부로 작성하세요.

모든 debug 설정에 `FAST_BUILD`를 정의하면 debug CI 빌드에도 적용됩니다.
빌드 flag만으로는 로컬 전용 검증 정책이 만들어지지 않습니다.

## Reviewer 체크리스트

diff에 `validateDAG: false`가 보이면 flag 하나를 바꾼 것으로 넘기지 말고, 검증
범위를 바꾸는 변경으로 다루세요. reviewer가 물을 질문:

1. 어느 컨테이너가 끄고 있고, 그것을 정당화하는 일시적 조건은 무엇인가?
2. tracking issue와 예상 제거 날짜가 있는가?
3. production target은 검증을 유지하고, 검증을 끈 scratch 또는 test
   target은 제품에서 제외하는가?
4. 해당 컨테이너에 validator가 잡았을 순환을 잡아낼 로컬 테스트가 있는가?

저장소 수준 규칙(CODEOWNERS 승인, PR template checkbox, custom lint rule)이
있으면 review할 때 답이 드러납니다. 함께 제공되는 `Tools/InnoDILintRules/`
패키지는 그 정책 검사용 `innodi_validate_dag_in_production` rule을 제공합니다.

## See Also

- <doc:Validation>
- <doc:PolicyBoundaries>
- ``DIContainer(validateDAG:)``
