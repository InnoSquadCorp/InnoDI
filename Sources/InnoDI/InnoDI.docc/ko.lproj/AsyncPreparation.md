# 소유권이 있는 비동기 준비

비동기 생성에 명시적 owner, 상태 관찰, 취소, 재시도가 필요하면
``DIAsyncScope``를 사용합니다. 하나의 scope는 동시에 들어온 waiter를 하나의
작업으로 합칩니다. waiter 취소는 그 대기만 취소하고,
``DIAsyncScope/close()``는 소유 작업을 취소하며 모든 waiter를 재개한 뒤 새
작업 시작을 영구적으로 막습니다.

``DIAsyncPreparationPlan``은 명시적 provider 의존 그래프를 검증하고 선택한
provider와 전이 의존성만 준비합니다. 의존성이 실패하면 downstream node는
시작하지 않고 차단한 provider ID와 함께 `blocked`로 보고합니다. 선택하지 않은
provider는 실행하지 않습니다.

선택 준비 결과에 `failed` 또는 `cancelled`가 있으면
``DIAsyncPreparationPlan/retry(_:)``로 재시도합니다. 실패 provider와 선택된
downstream만 함께 새 generation으로 전환하고 준비된 부모 의존성은 유지합니다.
영향 범위에 실행 중이거나 닫힌 provider가 있으면 아무 generation도 바꾸기 전에
재시도를 거부합니다. 개별 ``DIAsyncScope/retry()``는 해당 scope가 실패했거나
소유 작업이 취소된 뒤에만 호출합니다.

이미 취소된 task는 factory를 시작하지 않습니다. waiter 또는 prepare 요청 하나를
취소하면 그 요청만 `cancelled`로 보고하며 owner의 공통 작업은 유지합니다. 소유
작업이 `CancellationError`를 던지면 scope도 `cancelled`가 되고 재시도할 수
있습니다. 재시도는 새로운 generation에서 시작하며 이전 child 결과와 섞이지
않습니다. InnoDI가 소유하는 범위는 전달된 operation으로 만든 작업뿐입니다.
서비스 내부에서 별도로 만든 작업은 해당 서비스가 관리해야 하며 취소는
협조적으로 동작합니다.

상태 보고서는 provider ID, generation, 상태, 오류의 reflected type만 기록합니다.
직접 waiter에는 원본 오류를 돌려주지만 보고서는 오류 값, 입력 값, token, 기타
애플리케이션 payload를 직렬화하지 않습니다. 취소 결과에는 오류 payload가
없습니다.
