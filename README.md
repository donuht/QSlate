# TakeCompare

macOS용 생성 영상 테이크 비교기. 같은 컷을 여러 번 뽑은 mp4 2~4개를 한 창에 띄워 **같은 시점으로 동기 재생**하고, 같은 시점 프레임을 한 번에 PNG로 뽑는다. QuickTime 창 여러 개를 띄워 눈으로 시점을 맞추던 걸 대신하려고 만들었다.

*A take comparer for macOS. Open 2–4 generated takes of the same shot, play them in sync on one clock, flip between them A/B, and save the same frame from every take as PNG in one keystroke. English UI included — see [English](#english) below.*

## 기능

- **열기**: 창에 mp4·mov 2~4개를 끌어다 놓거나 `⌘O`로 여러 개 고른다. 1개만 열면 안내만 하고, 5개째부터는 무시하고 상태줄에 알린다. 열려 있을 때 다시 놓으면 전부 교체한다.
- **배치**: 2개는 좌우로 나란히, 3~4개는 2×2 격자. 칸마다 위에 번호 · 파일명 · 해상도 · fps · 길이(초). 영상은 칸 안에서 비율을 지킨다.
- **동기 재생**: 모든 플레이어를 같은 host time 기준으로 출발시켜(`setRate(_:time:atHostTime:)`) 어긋나지 않게 한다. 타임라인은 In 기준 상대 시각이고 길이는 가장 긴 In~Out 구간이다. 짧은 테이크는 자기 Out(기본은 끝) 프레임에 멈춘다. 멈추면 모든 테이크를 같은 시각으로 다시 맞춘다.
- **테이크별 In/Out, ⌥화살표로 1프레임 정렬**: 칸을 골라 `I`/`O`로 그 테이크의 시작·끝을 잡으면 In끼리 맞춰 동시 재생된다. `⌥←`/`⌥→`는 선택한 테이크만 정확히 1프레임 옮겨(그 테이크의 In을 한 프레임 옮긴다) 시점을 맞춘다. 칸 위에 `In 00:00.50 · Out 00:03.20 · 오프셋 +3f`(첫 테이크 기준), 칸 아래 얇은 바에 전체 길이 대비 In~Out 구간과 현재 위치.
- **스크럽**: 아래 슬라이더 하나로 전부 같이 정확히(허용 오차 0) 이동. 시각 표시는 `t / 범위`. 한 프레임(`AVPlayerItem.step(byCount:)` — 각 테이크가 자기 프레임 하나씩)·1초 단위 이동, 처음·끝.
- **A/B 토글**: 숫자키 `1`~`4`로 그 테이크만 창 전체로 본다. 시각·재생 상태는 그대로. 같은 키나 `Esc`로 격자로 돌아온다.
- **소리**: 선택한 테이크 하나만 소리를 낸다. 칸을 클릭하면 선택(테두리 강조). `M`으로 전체 음소거.
- **프레임 저장**: `⌘S`로 지금 보이는 프레임을 모든 테이크에서 PNG로 뽑는다. 첫 번째 파일이 있는 폴더 아래 `_frames/`에 `<원본파일명>_t03.47.png`로 저장되고(시각은 In과 상관없이 그 테이크 원본 기준), 상태줄의 결과를 누르면 Finder에서 보여준다. `⇧⌘S`는 선택한 테이크 한 장만.
- **못 여는 파일**(코덱 미지원 등)은 그 칸에 사유를 띄우고 나머지로 계속 비교한다.
- 창 크기·위치 기억, 다크/라이트 모드, 한국어/영어.

## 단축키

| 키 | 동작 |
|---|---|
| `⌘O` | 열기 (여러 개 선택) |
| `스페이스` | 재생 / 정지 |
| `←` / `→` | 모든 테이크 한 프레임 뒤로 / 앞으로 (각자 자기 fps의 한 프레임) |
| `⇧←` / `⇧→` | 모든 테이크 1초 뒤로 / 앞으로 |
| `⌥←` / `⌥→` | 선택한 테이크만 한 프레임 뒤로 / 앞으로 (정렬 — 그 테이크의 In이 옮겨진다) |
| `⌥⇧←` / `⌥⇧→` | 선택한 테이크만 1초 뒤로 / 앞으로 |
| `I` | 선택한 테이크의 In = 지금 보이는 프레임 (그 프레임이 t = 0이 된다) |
| `O` | 선택한 테이크의 Out = 지금 보이는 프레임 (In보다 앞이면 무시) |
| `⌥I` / `⌥O` | 선택한 테이크의 In / Out 초기화 |
| 보기 → 인·아웃 모두 초기화 | 모든 테이크의 In/Out 초기화 |
| 보기 → 프레임 이동 자가진단 | 모든 테이크를 ±1프레임 10회 왕복해 시각 변화가 정확히 1/fps인지 확인, 상태줄에 `10/10 정확` |
| `Home` / `End` | 처음 / 끝 |
| `1` ~ `4` | 그 테이크만 창 전체로 (다시 누르면 격자) |
| `Esc` | 격자로 |
| `L` | 루프 켜고 끄기 (기본 켬) |
| `M` | 전체 음소거 |
| `⌘S` | 프레임 저장 — 모든 테이크 |
| `⇧⌘S` | 프레임 저장 — 선택한 테이크 |
| 칸 클릭 | 그 테이크 선택 (소리 · In/Out · ⌥화살표 대상). 숫자키 단독 보기도 선택이 된다 |

## 설치

- macOS 14 Sonoma 이상, Apple Silicon·Intel 둘 다.
- [Releases](../../releases)에서 `TakeCompare.zip`을 받아 풀고 `TakeCompare.app`을 응용 프로그램 폴더로 옮긴다.
- **첫 실행 때 "Apple에서 악성 소프트웨어가 없는지 확인할 수 없다"는 창이 뜬다.** 아직 Apple Developer ID로 서명·공증하지 않았기 때문이다. 한 번만 아래처럼 열어 주면 이후엔 그냥 실행된다.
  1. 앱을 더블클릭 → 경고 창에서 **완료**를 누른다 (휴지통으로 이동은 누르지 않는다).
  2. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래로 내리면 "TakeCompare이(가) 차단되었습니다" 옆에 **그래도 열기** 버튼이 있다. 누르고 암호를 넣는다.
  3. macOS 14 Sonoma 이하에서는 앱을 **우클릭 → 열기**로도 된다 (15 Sequoia부터는 이 방법이 막혔다).

  터미널이 편하면 이 한 줄로 대신할 수 있다:

```bash
xattr -dr com.apple.quarantine /Applications/TakeCompare.app
```

## 직접 빌드

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
xcodebuild -scheme TakeCompare -configuration Release -derivedDataPath build
```

결과물은 `build/Build/Products/Release/TakeCompare.app`. 외부 의존성은 없다(AVFoundation·AVKit·SwiftUI만 쓴다).

## 설계 메모

- 샌드박스 없음(의도). 열린 영상 옆 `_frames/` 폴더에 바로 써야 하기 때문이다.
- 프레임 저장은 화면을 캡처하지 않고 `AVAssetImageGenerator`로 원본에서 정확한 시각(허용 오차 0)의 프레임을 디코딩한다. 그래서 저장 PNG는 원본 해상도다.
- 한 프레임 이동은 `AVPlayerItem.step(byCount:)`를 쓴다. 단, 영상 출력이 하나도 붙지 않은 플레이어는 한 번에 0.25초씩 뛴다 — 단독 보기로 칸이 화면에서 빠져도 정확하도록 플레이어마다 `AVPlayerItemVideoOutput`을 늘 붙여 둔다.
- `CMTime(seconds:preferredTimescale:)`는 버림이라 프레임 시작 시각(예: 31/24초)을 넣으면 앞 프레임이 나온다. 초 → CMTime 변환은 마이크로초 올림으로 한다. `⌘S`는 각 플레이어의 `currentTime()`을 그대로 넘긴다.
- Out은 플레이어의 `forwardPlaybackEndTime`으로 건다 — 재생이 그 프레임에서 저절로 멈춘다.
- 없는 것: In/Out 기억(세션 저장), 드래그로 In/Out 잡기, 오디오 파형, 속도 조절, 트림·내보내기, 설정 창.

## English

TakeCompare is a small macOS app for comparing AI-generated video takes. Drop 2–4 mp4/mov files on the window (or press `⌘O`): two takes sit side by side, three or four in a 2×2 grid, each labeled with file name, resolution, fps and duration. All players start on the same host-time clock so they never drift. Each take can have its own In and Out: select a cell and press `I`/`O` to mark the frame you are looking at (`⌥I`/`⌥O` clear them, View → Clear All In/Out resets every take). Playback lines the takes up at their In points; the timeline counts from In (`t / range`, range = the longest In–Out span) and a take past its Out holds its Out frame. `⌥←`/`⌥→` nudges only the selected take by exactly one frame (it shifts that take's In, so the alignment survives playback), `⌥⇧←`/`⌥⇧→` by one second. Each cell shows `In · Out · offset ±Nf` (relative to the first take) and a thin bar with the In–Out range and playhead. One slider scrubs every take frame-accurately. `Space` plays/pauses, `←`/`→` steps every take one frame (`AVPlayerItem.step(byCount:)`, each by its own frame), `⇧←`/`⇧→` one second, `Home`/`End` jump to start/end, `L` toggles loop (on by default). View → Frame Step Self-Test steps all takes ±1 frame ten times and reports e.g. `10/10 exact`. Press `1`–`4` to view one take full-window (A/B), and the same key or `Esc` to return to the grid. Only the selected take (click a cell) plays audio; `M` mutes everything. `⌘S` saves the frame each take is showing as PNG into `_frames/` next to the first file (`<name>_t03.47.png`, time measured in the original file regardless of In); `⇧⌘S` saves only the selected take. Click the status bar result to reveal the files in Finder. Files that cannot be decoded show the reason in their cell while the rest keep working. UI is in Korean and English.

Requires macOS 14+ (Apple Silicon and Intel). Download `TakeCompare.zip` from Releases and move `TakeCompare.app` to Applications. The app is not yet notarized, so the first launch is blocked: double-click it, choose **Done** in the warning, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (On macOS 14 and earlier, right-click → Open also works.) Or run the `xattr` command above.

To build it yourself: `brew install xcodegen`, `xcodegen generate`, then `xcodebuild -scheme TakeCompare -configuration Release -derivedDataPath build`. No third-party dependencies.

## License

MIT — see [LICENSE](LICENSE).
