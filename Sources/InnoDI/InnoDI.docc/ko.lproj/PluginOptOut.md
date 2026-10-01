# Build plugin 끄기

target에 `InnoDIDAGValidationPlugin`을 붙이면 plugin이 그 target의 validation
coordinator를 실행하고, SwiftPM의 plugin work directory 아래에 graph
artifact를 직렬화합니다. target이 InnoDI 컨테이너를 선언했다고 SwiftPM이
plugin을 자동으로 붙이지는 않습니다. consumer가 target manifest에 plugin을
나열해 opt-in합니다. coordinator는 incremental하고 cache를 쓰지만, plugin은
여전히 target마다 빌드 단계 하나와 swift-syntax 호출 하나를 더합니다. 끄는
것이 정당한 경우는 좁은 세 가지 상황입니다.

## 꺼도 되는 경우

- **버리는 PoC와 scratchpad**: InnoDI를 import하지만 배포하지 않습니다.
  작성자에게는 빌드 시점 gate가 아니라 매크로 전개와 Swift 컴파일러 진단이
  필요합니다.
- **리팩터링 중의 빠른 내부 반복**: workspace를 일부러 알려진 잘못된 상태로
  두는 동안입니다. 변경이 들어가기 전에 gate를 다시 켜세요.
- **이미 다른 곳에서 gate를 돌리는 build farm**: gate를 별도 CI job으로
  돌린다면 target별 plugin hook을 건너뛰어 같은 validator를 두 번 돌리지 않을
  수 있습니다.

## 끄면 안 되는 경우

- **Production 릴리스 브랜치**: plugin은 downstream 도구가 쓰는 validation
  metrics artifact를 만드는 gate입니다. 우회하면 audit trail이 사라집니다.
- **공유 인프라의 CI**에서 어디에서도
  `swift run InnoDI-DependencyGraph --validate-dag`를 돌리지 않는 경우: 대체
  수단이 없으면 global DAG gate가 사라집니다.
- **사용자에게 닿는 모든 것**: plugin의 역할은 깨진 그래프가 consumer에게 가지
  않게 막는 것입니다. 배포되는 경로에서 끄는 것은 계약을 없애는 것과 같습니다.

## 끄는 방법

빌드를 실행할 때 환경 변수를 설정하세요.

```sh
INNODI_DISABLE_BUILD_VALIDATION=1 swift build
```

받는 값은 `1`, `true`, `yes`이며, 앞뒤 공백을 자르고 소문자로 바꾼 뒤
비교합니다. 그 밖의 값이거나 변수가 없으면 plugin은 켜진 채로 남습니다. 변수는
plugin이 명령을 예약할 때 실행마다 한 번 읽힙니다. 빌드 사이에 유지되지
않으며, Xcode의 Build Settings sheet는 프로세스가 다시 시작될 때 이 값을
초기화합니다.

`INNODI_DISABLE_BUILD_VALIDATION=1`은 `INNODI_ALLOW_UNSAFE_LOCK=1`과
독립적입니다. 후자는 validator를 그대로 실행하되 안전하지 않은 파일시스템
위에서 돌리고, 전자는 validator를 아예 건너뜁니다. 한 빌드에서 둘을 함께 켜면
안 됩니다. 그 조합은 검증도 audit trail도 없는 빌드를 조용히 내보냅니다.

## See Also

- <doc:DAGValidation>
- <doc:lock-safety>
