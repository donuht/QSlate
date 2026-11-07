# QSlate

QSlate(큐슬레이트) — Q(검수·QC)와 Slate(테이크 번호판). 생성 영상 테이크들을 나란히 놓고 같은 시점에서 고르는 macOS 앱.

macOS용 생성 영상 테이크 비교기. 같은 컷을 여러 번 뽑은 mp4 2~4개를 한 창에 띄워 **같은 시점으로 동기 재생**하고, 같은 시점 프레임을 한 번에 PNG로 뽑는다. QuickTime 창 여러 개를 띄워 눈으로 시점을 맞추던 걸 대신하려고 만들었다.

*갈라보기 데모 — 선을 끌면 왼쪽은 테이크 A, 오른쪽은 B, 마지막은 겹치기. ([demo-split.mp4](docs/demo-split.mp4))*


*A take comparer for macOS. Open 2–4 generated takes of the same shot, play them in sync on one clock, flip between them A/B, and save the same frame from every take as PNG in one keystroke. English UI included — see [English](#english) below.*

## 기능

- **열기**: 창에 mp4·mov 2~4개를 끌어다 놓거나 `⌘O`로 여러 개 고른다. 1개만 열면 안내만 하고, 5개째부터는 무시하고 상태줄에 알린다. 열려 있을 때 다시 놓으면 전부 교체한다.
- **배치**: 2개는 좌우로 나란히, 3~4개는 2×2 격자. 칸마다 위에 번호 · 파일명 · 해상도 · fps · 길이(초). 영상은 칸 안에서 비율을 지킨다.
- **동기 재생**: 모든 플레이어를 같은 host time 기준으로 출발시켜(`setRate(_:time:atHostTime:)`) 어긋나지 않게 한다. 타임라인은 In 기준 상대 시각이고 길이는 가장 긴 In~Out 구간이다. 짧은 테이크는 자기 Out(기본은 끝) 프레임에 멈춘다. 멈추면(루프 끔으로 끝에 닿아도) 기준 테이크가 보여주던 프레임의 시작 시각으로 모든 테이크를 다시 맞춘다 — 그 뒤 `← →`·`I`/`O`는 프레임 단위로 정확하다. 파일을 읽는 중에는 재생을 받지 않는다.
- **정렬은 In에서만 나온다 — 칸 조작은 자유 탐색, 공통 조작이 줄 세움**: In/Out은 테이크마다 원본 기준 절대 시각에 찍는 표식이다. 칸 조작 줄(`◀ ▶`·`◀◀ ▶▶`·`|◀ ▶|`·바 끌기)과 `⌥←`/`⌥→`는 **그 테이크의 재생 위치만** 옮긴다 — In/Out은 그대로, 다른 테이크도 그대로라서 그 사이 테이크들은 줄이 안 맞아도 된다(탐색 중). 이때 하단 시각은 `— / 00:03.00`으로 "줄 안 맞음"을 알린다. 각 테이크에서 원하는 프레임을 찾아 `[In]`(·`[Out]`)을 찍고 **공통 조작**(재생, 공통 슬라이더, 공통 `◀ ▶`·`← →`, `⇧← ⇧→`, `Home`/`End`, 루프)을 하면 모두 `자기 In + t`로 다시 줄 선다 — 흩어진 상태였으면 t = 0, 즉 각자 In부터 같이 간다. 범위는 가장 긴 Out − In, 자기 Out을 넘은 테이크는 Out 프레임에 멈춘다.
- **각 영상 아래 조작 줄**: 칸마다 영상 바로 아래에 그 테이크 전용 조작 줄이 붙어 있다. 누른 칸이 선택된다(가운데 `▶` 빼고). 가운데(1프레임 `◀` `▶` 사이) `▶`/`❚❚` **이 테이크만 재생/정지**(다른 테이크는 그대로 서 있고 줄이 흩어진다. Out이 있으면 Out 프레임에서, 없으면 파일 끝에서 멈추고, 그 자리에서 다시 누르면 In부터. 루프가 켜져 있으면 In~Out을 그 테이크만 반복. 소리는 `🔊`가 그 칸에 있을 때만. 공통 재생 중에 누르면 공통 재생을 멈추고 그 테이크만 계속 간다. 여러 칸을 각자 돌릴 수도 있고, 그 칸의 다른 버튼·바를 만지면 그 칸 재생은 멈춘 뒤 동작한다), 그 테이크의 원본 기준 시각(지금 위치, 재생 중 실시간), `|◀` 그 테이크 In으로(없으면 처음) · 1초 `◀◀` · 1프레임 `◀` / `▶` (길게 누르면 0.4초 뒤부터 초당 8회 반복) · 1초 `▶▶` · `▶|` 그 테이크 Out으로(없으면 끝) — In/Out을 찍은 자리를 확인할 때 쓴다. `[In]`·`[Out]` 버튼(그 테이크가 지금 보여주는 프레임을 In/Out으로, 라벨에 현재 값, 없으면 `—`)과 첫 테이크 기준 In 오프셋 `+3f`, `↺` In/Out 초기화, `🔊` 이 테이크 소리(하나만), `⤢` 이 테이크만 크게. 아랫줄 바는 그 테이크 전체 길이 기준으로 In~Out 구간(강조색)과 현재 위치(세로선)를 보여 주고, **끌면 그 테이크 위치만 옮긴다**(끌기 시작하면 재생이 멈춘다). 이동은 In·Out을 넘어 원본 처음~끝 어디로나 된다. `[In]`을 Out과 같거나 뒤에 찍으면 Out을 지우고 상태줄에 알린다. `[Out]`은 In이 없으면 처음부터로 보고, In과 같거나 앞이면 무시한다(Out은 In보다 최소 1프레임 뒤). 칸 위 라벨은 `번호 · 파일명 · 해상도 · fps · 길이`.

```
[00:01.25]  |◀ ◀◀ ◀ ▶/❚❚ ▶ ▶▶ ▶|     [In 00:00.50] +3f [Out 00:03.20] ↺     🔊 ⤢
░░░░░░░░░░▐║║▌██████████|███████████▐║║▌░░░░░░░░░   ← 이 테이크 전체 길이, █ = In~Out, | = 지금 (끌어서 이 테이크 위치만 이동), ▐║║▌ = In·Out 손잡이(끌어서 표식 이동)
```

- **스크럽**: 창 아래 공통 슬라이더 하나로 전부 같이 정확히(허용 오차 0) 이동. 시각 표시는 `t / 범위`. 그 옆 `◀`/`▶`는 모든 테이크 한 프레임(허용 오차 0 seek로 프레임 시작 + ¼프레임 지점에 정확히 섬 — 각 테이크가 자기 프레임 하나씩, 길게 누르면 반복. fps가 섞이면 기준 테이크 한 프레임만큼). 키보드로 1초 단위 이동, 처음·끝. 공통 줄에는 루프·음소거·`지금 프레임 저장`(⌘S)·`인·아웃 모두 초기화` 버튼도 있다.
- **보기 모드 줄**: 창 맨 위 오른쪽에 `전체 보기`(격자) · `단독`(선택한 테이크만 크게) · `갈라보기` · `겹치기` 네 개. 왼쪽에는 열린 테이크 수와 범위. 메뉴 `보기`에도 같은 항목이 있다.
- **A/B 토글**: 숫자키 `1`~`4`로 그 테이크만 창 전체로 본다. 시각·재생 상태는 그대로. 같은 키나 `Esc`(`0`)로 격자로 돌아온다.
- **겹쳐 보기(갈라보기·겹치기)**: 두 테이크를 같은 자리에 겹쳐 재생한다. 기본은 선택한 테이크가 A(아래), 그 다음 번호(없으면 이전)가 B(위). `\`(갈라보기)는 화면에 가는 흰 세로선이 생겨 선 왼쪽은 A, 오른쪽은 B가 보인다 — 선을 끌거나 `[` `]`(2%, `⇧`는 10%)로 옮긴다. `⇧\`(겹치기)는 B를 반투명으로 올린다(투명도 슬라이더 0~100%, 기본 50%, `[` `]`도 됨). 영상 위 왼쪽·오른쪽 위 모서리에 A·B 이름이 뜬다. 위쪽 겹침 바에서 A·B를 팝업으로 바꾸고 `⇄`로 뒤집는다. 해상도가 달라도 화면 맞춤으로 같은 크기에 겹친다(비율이 다르면 가운데 정렬). 배율 `맞춤 / 100% / 200%`는 두 테이크 중 큰 해상도 기준 원본 픽셀 1:1·2:1 — 업스케일 결과와 원본을 같은 자리에서 픽셀 단위로 비교할 때 쓴다. 확대 상태에서는 영상을 끌어 이동하고 더블클릭하면 맞춤으로 돌아온다(세로선은 화면 기준이라 이동과 무관). 아래에는 A·B 두 테이크의 조작 줄이 나란히 남고 공통 조작도 그대로 쓴다. 같은 키나 `Esc`로 격자.
- **바 손잡이로 In/Out 끌기**: 칸 바의 In~Out 구간 양 끝에 세로 줄무늬 손잡이가 있다(미설정이면 바 양 끝에 흐리게). 끌면 그 표식만 프레임 단위로 옮기고, 그 테이크 화면은 끄는 손잡이의 프레임을 보여 준다(놓으면 그 자리에 머문다 — Out을 눈으로 보며 맞출 때). In과 Out은 최소 1프레임 떨어져 있고 넘으면 상대 손잡이에 붙어 멈춘다. 처음·끝까지 끌면 표식 없음으로 돌아간다. 손잡이가 아닌 곳을 끌면 기존처럼 위치 스크럽.
- **바 호버 썸네일**: 칸 조작 줄의 바 위에 마우스를 올리거나 끌면 그 지점 프레임 썸네일과 `00:01.25 · 30f`가 말풍선으로 뜬다(앞뒤 1프레임 오차 허용·테이크별 최근 200장 기억 — 정확한 프레임은 화면이 보여준다). `보기 → 바 위 썸네일 미리보기`·`T`·공통 줄 오른쪽 끝 버튼으로 켜고 끈다(기본 켬, 앱을 다시 켜도 기억). 끄면 썸네일을 아예 만들지 않는다.
- **fps가 다른 테이크**: 24fps·30fps처럼 섞이면 칸 라벨의 fps가 노란색으로 바뀌고, 공통 1프레임(`◀ ▶`·`← →`)은 기준 테이크(구간이 가장 긴 테이크)의 한 프레임만큼 시간을 옮긴다 — 나머지는 자기 In + t를 포함하는 자기 프레임에 선다. 열 때 상태줄에 기준 테이크를 알린다.
- **소리**: 선택한 테이크 하나만 소리를 낸다. 칸을 클릭하거나 칸 조작 줄의 아무 버튼(`▶` 빼고)을 누르면 선택(테두리 강조), `🔊`는 그 테이크 소리를 켜고 전체 음소거도 푼다. `M`으로 전체 음소거.
- **프레임 저장**: `⌘S`로 지금 보이는 프레임을 모든 테이크에서 PNG로 뽑는다. 첫 번째 파일이 있는 폴더 아래 `_frames/`에 `<원본파일명>_t03.47.png`로 저장되고(시각은 In과 상관없이 그 테이크 원본 기준, 다른 폴더의 같은 이름 파일이 이미 그 이름을 쓰고 있으면 `_2`, `_3`…), 상태줄의 결과를 누르면 Finder에서 보여준다. `⇧⌘S`는 선택한 테이크 한 장만.
- **못 여는 파일**(코덱 미지원 등)은 그 칸에 사유를 띄우고 나머지로 계속 비교한다.
- 창 크기·위치 기억, 다크/라이트 모드, 한국어/영어.

## 단축키

| 키 | 동작 |
|---|---|
| `⌘O` | 열기 (여러 개 선택) |
| `스페이스` | 재생 / 정지 (공통). 칸 `▶`로 도는 테이크가 있으면 먼저 전부 정지만 하고, 한 번 더 누르면 공통 재생 — 각자 In부터 줄 세워 간다 |
| `←` / `→` | 모든 테이크 한 프레임 뒤로 / 앞으로 (각자 자기 fps의 한 프레임. fps가 섞이면 기준 테이크의 한 프레임만큼 시간 이동) |
| `⇧←` / `⇧→` | 모든 테이크 1초 뒤로 / 앞으로 |
| `⌥←` / `⌥→` | 선택한 테이크 위치만 한 프레임 뒤로 / 앞으로 (칸 `◀ ▶`와 같음 — In/Out·다른 테이크는 그대로) |
| `⌥⇧←` / `⌥⇧→` | 선택한 테이크 위치만 1초 뒤로 / 앞으로 |
| `I` | 선택한 테이크의 In = 그 테이크가 지금 보여주는 프레임 (다른 것은 안 바뀐다. Out과 같거나 뒤면 Out을 지운다) |
| `O` | 선택한 테이크의 Out = 그 테이크가 지금 보여주는 프레임 (In이 없으면 처음부터, In보다 앞이면 무시) |
| `⌥I` / `⌥O` | 선택한 테이크의 In / Out 초기화 |
| 보기 → 인·아웃 모두 초기화 | 모든 테이크의 In/Out 초기화 |
| 보기 → 프레임 이동 자가진단 | 모든 테이크를 ±1프레임 10회 왕복해 시각 변화가 정확히 1/fps인지 확인, 상태줄에 `10/10 정확` |
| `Home` / `End` | 처음 / 끝 (공통 — 모두 각자 In 기준으로 다시 줄 선다) |
| `1` ~ `4` | 그 테이크만 창 전체로 (다시 누르면 격자) |
| `\` | 갈라보기 — 세로선 왼쪽 A, 오른쪽 B (다시 누르면 격자) |
| `⇧\` | 겹치기 — B 반투명 (다시 누르면 격자) |
| `[` / `]` | 겹쳐 보기에서 선(겹치기면 투명도) 2% 왼쪽·오른쪽, `⇧`와 함께 10% |
| `Esc` / `0` | 격자로 |
| `L` | 루프 켜고 끄기 (기본 켬) |
| `M` | 전체 음소거 |
| `T` | 바 위 썸네일 미리보기 켜고 끄기 (기본 켬, 기억됨) |
| `⌘S` | 프레임 저장 — 모든 테이크 |
| `⇧⌘S` | 프레임 저장 — 선택한 테이크 |
| 칸 클릭 | 그 테이크 선택 (소리 · In/Out · ⌥화살표 대상). 숫자키 단독 보기도 선택이 된다 |

`←`·`→`·`⇧←`·`⇧→`·`Home`·`End`·스페이스·공통 슬라이더는 **공통 조작**이라 칸 조작으로 흩어진 테이크를 각자 In 기준으로 다시 줄 세운다(흩어져 있었으면 t = 0부터).

## 설치

- macOS 14 Sonoma 이상, Apple Silicon·Intel 둘 다.
- [Releases](../../releases)에서 `QSlate.zip`을 받아 풀고 `QSlate.app`을 응용 프로그램 폴더로 옮긴다.
- **첫 실행 때 "Apple에서 악성 소프트웨어가 없는지 확인할 수 없다"는 창이 뜬다.** 아직 Apple Developer ID로 서명·공증하지 않았기 때문이다. 한 번만 아래처럼 열어 주면 이후엔 그냥 실행된다.
  1. 앱을 더블클릭 → 경고 창에서 **완료**를 누른다 (휴지통으로 이동은 누르지 않는다).
  2. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래로 내리면 "QSlate이(가) 차단되었습니다" 옆에 **그래도 열기** 버튼이 있다. 누르고 암호를 넣는다.
  3. macOS 14 Sonoma 이하에서는 앱을 **우클릭 → 열기**로도 된다 (15 Sequoia부터는 이 방법이 막혔다).

  터미널이 편하면 이 한 줄로 대신할 수 있다:

```bash
xattr -dr com.apple.quarantine /Applications/QSlate.app
```

## 직접 빌드

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
xcodebuild -scheme QSlate -configuration Release -derivedDataPath build
```

결과물은 `build/Build/Products/Release/QSlate.app`. 외부 의존성은 없다(AVFoundation·AVKit·SwiftUI만 쓴다).

## 설계 메모

- 샌드박스 없음(의도). 열린 영상 옆 `_frames/` 폴더에 바로 써야 하기 때문이다.
- 프레임 저장은 화면을 캡처하지 않고 `AVAssetImageGenerator`로 원본에서 정확한 시각(허용 오차 0)의 프레임을 디코딩한다. 그래서 저장 PNG는 원본 해상도다.
- 한 프레임 이동은 보통 허용 오차 0 seek(프레임 시작 + ¼프레임)로 간다. 플레이어가 정확히 프레임 시작에 서 있을 때만 `AVPlayerItem.step(byCount:)`를 쓴다(자가진단이 이 경로를 검사한다). 영상 출력이 하나도 붙지 않은 플레이어는 step이 한 번에 0.25초씩 뛴다 — 단독 보기로 칸이 화면에서 빠져도 정확하도록 플레이어마다 `AVPlayerItemVideoOutput`을 늘 붙여 둔다.
- `CMTime(seconds:preferredTimescale:)`는 버림이라 프레임 시작 시각(예: 31/24초)을 넣으면 앞 프레임이 나온다. 초 → CMTime 변환은 마이크로초 올림으로 한다. `⌘S`는 각 플레이어의 `currentTime()`을 그대로 넘긴다.
- 프레임으로 가는 seek은 프레임 시작이 아니라 **시작 + ¼프레임**을 겨눈다 — pts가 ms로 반올림된 파일(tbn 1000, 프레임 1 pts 0.042 > 1/24)에서 k/fps로 seek하면 앞 프레임이 보인다. 화면의 시각·In/Out·파일명은 프레임 시작값(k/fps)이다.
- Out은 플레이어의 `forwardPlaybackEndTime`으로 건다 — 재생이 그 프레임에서 저절로 멈춘다.
- 갈라보기는 SwiftUI `mask` 대신 `CALayer`로 자른다: A·B를 각자 `AVPlayerLayer`로 같은 자리에 겹치고, B는 `masksToBounds` 클립 레이어 안에 둔다. 클립 레이어 frame을 선 오른쪽만큼으로 줄이고 bounds.origin을 같은 만큼 옮겨 B 영상은 한 픽셀도 밀리지 않고 가려지기만 한다.
- 없는 것: In/Out 기억(세션 저장), 오디오 파형, 속도 조절, 트림·내보내기, 설정 창.

## English

QSlate is a small macOS app for comparing AI-generated video takes. Drop 2–4 mp4/mov files on the window (or press `⌘O`): two takes sit side by side, three or four in a 2×2 grid, each labeled with file name, resolution, fps and duration. All players start on the same host-time clock so they never drift. Each take can have its own In and Out: select a cell and press `I`/`O` to mark the frame you are looking at (`⌥I`/`⌥O` clear them, View → Clear All In/Out resets every take). In and Out are plain markers at absolute times in each take's own file. **Alignment comes only from In:** the per-cell controls and `⌥←`/`⌥→` (`⌥⇧←`/`⌥⇧→` for one second) move only that take's playhead — In/Out and the other takes stay put, so the takes may be out of line while you explore, and the time readout shows `— / 00:03.00`. Shared controls (play, the shared slider, shared `◀ ▶`/`← →`, `⇧← ⇧→`, `Home`/`End`, loop) line every take up again at `its In + t` — starting from t = 0, i.e. each take's In, if they were scattered. The timeline counts from In (`t / range`, range = the longest In–Out span) and a take past its Out holds its Out frame. Pausing (or reaching the end with loop off) lines every take up on the start of the frame the reference take was showing, so the next frame step and `I`/`O` are frame-exact; .

**Per-take control strip.** Under every video sits that take's own control strip, so everything can be done with the mouse alone. Its transport controls move **only that take's playhead** (never its In/Out, never the other takes), and clicking any of them selects the cell. From the left: `▶`/`❚❚` **plays or pauses only this take** (the others stay where they are and the takes fall out of line; it stops on the Out frame, or at the end of the file without an Out, and pressing it there starts again from In; with loop on it repeats this take's In–Out; you hear it only if `🔊` is on this cell; pressed during shared playback it stops the shared playback and keeps only this take going; several cells can play on their own, and touching another control of that cell stops its playback first — this button does not select the cell), the take's own time (in its original file, live while playing), `|◀` go to this take's In (or the start), −1 s `◀◀`, −1/+1 frame `◀`/`▶` (hold to repeat: after 0.4 s, 8 times a second), +1 s `▶▶`, `▶|` go to this take's Out (or the end), the `[In]` and `[Out]` buttons (mark the frame this take is showing; the label shows the current value or `—`) with the In offset from the first take (`+3f`), `↺` to clear this take's In/Out, `🔊` to hear this take (one at a time; also unmutes), and `⤢` to view it alone. The bar underneath spans the whole take: the In–Out range is highlighted, the rest dimmed, and a line marks the playhead. **Drag the bar to move only that take's playhead** (it stops playback). You can move anywhere in the file, past In or Out. Marking In at or after the Out clears the Out; marking Out with no In counts from the start, and an Out at or before the In is ignored (Out must be at least one frame after In). The label above each cell shows number, file name, resolution, fps and duration.

```
[00:01.25]  |◀ ◀◀ ◀ ▶/❚❚ ▶ ▶▶ ▶|     [In 00:00.50] +3f [Out 00:03.20] ↺     🔊 ⤢
░░░░░░░░░░▐║║▌██████████|███████████▐║║▌░░░░░░░░░   ← whole take, █ = In–Out, | = playhead (drag to move this take only), ▐║║▌ = In/Out handles
```

The shared bar at the bottom of the window has one slider that scrubs every take frame-accurately, `◀`/`▶` to step every take one frame (hold to repeat), loop, mute, **Save** (`⌘S`) and **Clear All In/Out**. `Space` plays/pauses (if any cell is playing on its own, the first press only stops everything; the next press starts shared playback from each take's In), `←`/`→` steps every take one frame (a zero-tolerance seek to the frame start + ¼ frame, each by its own frame), `⇧←`/`⇧→` one second, `Home`/`End` jump to start/end, `L` toggles loop (on by default). View → Frame Step Self-Test steps all takes ±1 frame ten times and reports e.g. `10/10 exact`. Press `1`–`4` to view one take full-window (A/B), and the same key or `Esc` (`0`) to return to the grid. The view bar at the top right switches between **All** (grid), **Single**, **Split** and **Blend** (also in the View menu). **Split** (`\`) overlays two takes in the same place with a thin white vertical line: A shows left of the line, B right of it — drag the line or nudge it with `[` `]` (2%, `⇧` for 10%). **Blend** (`⇧\`) puts B on top at adjustable opacity (default 50%, `[` `]` too). By default A is the selected take and B the next one (or the previous). The overlay bar picks A and B from pop-ups and `⇄` swaps them; takes of different resolutions are fitted to the same size (centered if the aspect differs). Zoom `Fit / 100% / 200%` shows the larger take's pixels 1:1 or 2:1 for comparing an upscale with its source; drag to pan, double-click to fit (the line stays put on screen). Both takes' control strips stay below and the shared controls work as usual. **Drag the In/Out handles** (the gripped ends of the highlighted range; dimmed at the bar ends when unset) to move just that marker frame by frame — the take shows the handle's frame while you drag and stays there when you let go, so you can set Out by eye. In and Out stay at least one frame apart (a handle stops against the other), and dragging to the very start/end clears the marker. Hovering or dragging any take bar shows a thumbnail of that point with `00:01.25 · 30f` (within ±1 frame, the last 200 cached per take); turn it off or on with View → Thumbnail Preview on Bars, `T`, or the button at the right end of the shared bar (on by default, remembered across launches; when off, no thumbnails are generated at all). When takes have different frame rates, the fps in the cell labels turns yellow and a shared frame step moves time by one frame of the reference take (the longest In–Out); the others land on their own frame containing In + t. Only the selected take (click a cell) plays audio; `M` mutes everything. `⌘S` saves the frame each take is showing as PNG into `_frames/` next to the first file (`<name>_t03.47.png`, time measured in the original file regardless of In; `_2`, `_3`… if a same-named file from another folder already took that name); `⇧⌘S` saves only the selected take. Click the status bar result to reveal the files in Finder. Files that cannot be decoded show the reason in their cell while the rest keep working. UI is in Korean and English.

Requires macOS 14+ (Apple Silicon and Intel). Download `QSlate.zip` from Releases and move `QSlate.app` to Applications. The app is not yet notarized, so the first launch is blocked: double-click it, choose **Done** in the warning, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (On macOS 14 and earlier, right-click → Open also works.) Or run the `xattr` command above.

To build it yourself: `brew install xcodegen`, `xcodegen generate`, then `xcodebuild -scheme QSlate -configuration Release -derivedDataPath build`. No third-party dependencies.

## License

MIT — see [LICENSE](LICENSE).
