# WireMenu

![WireMenu 앱 아이콘](docs/assets/app-icon.png)

현재 네트워크 연결과 전송량을 macOS 메뉴바에 표시하는 개인용 앱입니다. SwiftUI와 AppKit으로 만들었으며 외부 패키지 의존성은 없습니다.

## 기능

- 유선: 메뉴 막대와 패널에서 같은 macOS `display` 심볼
- Wi‑Fi: macOS Wi‑Fi 심볼
- 개인용 핫스팟: macOS 핫스팟 심볼
- 오프라인: 연결 끊김 심볼
- 글래스 패널에서 Wi-Fi 켜기/끄기
- 현재·저장된·주변 Wi-Fi 검색 및 연결
- 보안 네트워크 암호 입력과 저장된 Keychain 암호 사용
- 유선 링크 속도와 IP 주소 표시
- 현재 인터넷 경로의 다운로드·업로드 그래프: 메뉴가 열린 동안 최근 최대 60개 샘플 표시

그래프는 **실제로 주고받는 데이터량**입니다. 인터넷 요금제의 최대 속도를 측정하는 속도 테스트가 아니며, 유선 링크 속도 역시 회선 최대 속도와 다릅니다.

## 빌드

Swift 6 도구와 macOS SDK 26 이상이 필요합니다. 언어 모드는 프로젝트 설정에 따릅니다. 배포 대상은 macOS 13 이상이지만 실제 UI 검증은 macOS 26에서 진행했습니다. 이전 버전 호환성은 추가 검증 대상입니다.

```sh
swift test
./build-app.sh
codesign --verify --deep --strict dist/WireMenu.app
```

결과는 `dist/WireMenu.app`이며 현재 Mac 아키텍처용으로 생성됩니다. 앱 아이콘은 빌드 때 생성하고 앱은 ad-hoc 서명합니다. 처음 복제한 프로젝트에서 시험 실행할 때:

```sh
open dist/WireMenu.app
```

이미 설치한 앱을 업데이트할 때는 로컬 `OPERATIONS.md`의 설치 경로와 백업 절차를 따르세요. 이 파일은 머신별 기록이라 저장소에는 포함하지 않습니다. 로그인 자동 실행을 사용할 앱은 먼저 최종 설치 위치를 정한 뒤 그 위치에서 실행하세요.

## 개발과 UI 확인

- [AI 작업 진입점](AGENTS.md): 수정·설치·검증 시 읽을 문서
- [코드 구조와 회귀 검사](docs/ARCHITECTURE.md): 데이터 흐름, 파일 역할, 유지할 동작, 알려진 한계

`swift test`는 연결 분류, 속도 계산, 신호 강도, 키보드 순서와 다중 모니터 배치를 확인합니다.
실행 중인 앱은 `osascript Tests/check-panel.applescript`로 상단·하단 배치와 Esc 닫기를 확인할 수 있습니다. 접근성 권한이 필요하며 네트워크 연결은 변경하지 않습니다. `Expanded list: false`이면 펼치기/접기는 미검증입니다.

## 권한과 한계

macOS 26 이상에서는 시스템 `NSGlassEffectView`, 이전 버전에서는 메뉴용 `NSVisualEffectView`를 사용합니다. 글자색은 시스템 색을 따릅니다. 기본 메뉴의 내부 렌더링이나 Instant Hotspot 기기 검색을 복제한 것은 아니며, 핫스팟 버튼은 시스템 설정을 엽니다.

신호 칸수는 RSSI 추정값이므로 기본앱과 항상 일치하지 않습니다. 핫스팟 판별 역시 경로 속성에 기반한 추정으로, 모든 핫스팟을 구별하지는 못합니다.

처음 패널을 열면 주변 Wi-Fi 이름을 읽기 위한 위치 권한을 요청합니다. Wi-Fi 전원이나 연결 정책에 관리자 인증이 설정된 Mac에서는 macOS가 인증을 요청할 수 있습니다.

장기 무누수 검증은 완료하지 않았습니다. 발견된 누수 의심과 미검증 항목은 개발 문서에 기록했습니다.

## 아이콘과 배포

현재 앱·메뉴바는 Apple SF Symbols를 사용합니다. 이전 시안 리소스 `ethernet-windows-connected.png`는 [Easy Ethernet Icon](https://github.com/felixblome/easy-ethernet-icon)에서 가져온 Icons8 이미지이며 프로젝트에 보관되어 있습니다. 해당 이미지와 SF Symbols의 권리는 각각의 권리자에게 있으며, 공개 배포 전에 각 사용 조건을 별도로 확인해야 합니다.

현재 개인용 프로젝트이며, 공증된 설치 프로그램이나 공개 릴리스는 제공하지 않습니다.
