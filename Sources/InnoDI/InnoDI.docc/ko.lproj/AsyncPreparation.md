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

실패 뒤에만 ``DIAsyncScope/retry()``를 호출할 수 있습니다. 재시도는 새로운
generation에서 시작하며 이전 local 결과와 섞이지 않습니다. InnoDI가 소유하는
범위는 전달된 operation으로 만든 작업뿐입니다. 서비스 내부에서 별도로 만든
작업은 해당 서비스가 관리해야 하며 취소는 협조적으로 동작합니다.

상태 보고서는 provider ID, generation, 상태, 오류의 reflected type만 기록합니다.
오류 값, 입력 값, token, 기타 애플리케이션 payload는 직렬화하지 않습니다.
