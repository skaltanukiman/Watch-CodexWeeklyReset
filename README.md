# Watch Codex Weekly Reset

Codex CLIから使用制限情報を取得し、週次使用枠のリセットを検知したときにWindowsのToast通知を表示するPowerShellスクリプトです。

前回取得したリセット予定時刻をローカルのJSONファイルへ保存し、次回実行時の値と比較して週次枠の切り替わりを判定します。

Windowsタスクスケジューラから実行する場合は、VBSランチャーを経由することでPowerShellのウィンドウを表示せずに実行できます。

## 主な機能

- Codex App Serverから現在の使用制限情報を取得
- 6日以上の制限枠を週次枠の候補として判定
- 複数の候補がある場合は、制限期間が最も長い枠を選択
- 使用済み割合、残り割合、次回リセット日時を表示
- 前回実行時の状態をJSONファイルへ保存
- 週次枠のリセットを検知した場合にWindowsのToast通知を表示
- Windows通知センターと連携する通知を使用
- `-TestNotification`による通知単体テスト
- VBS経由によるPowerShellウィンドウの非表示実行
- 任意の通知サムネイル画像に対応
- 通知画像が存在しない場合はBurntToastの標準画像を使用

## 動作環境

- Windows
- Windows PowerShell 5.1以降
- Codex CLI
- Codex CLIへログイン済みであること
- PowerShellモジュール `BurntToast`

## Codex CLIの確認

Codex CLIが利用できることを、次のコマンドで確認してください。

```powershell
codex --version
codex login status
```

`codex`コマンドが見つからない場合は、Codex CLIをインストールしてPATHを設定してください。

## BurntToastのインストール

WindowsのToast通知を表示するため、初回のみBurntToastモジュールをインストールします。

```powershell
Install-Module `
    -Name BurntToast `
    -Scope CurrentUser
```

インストール確認は次のコマンドで行えます。

```powershell
Get-Module `
    -ListAvailable `
    -Name BurntToast
```

タスクスケジューラは、BurntToastをインストールしたWindowsユーザーで実行してください。

## ファイル構成

```text
Watch-CodexWeeklyReset/
├─ assets/
│  └─ codex-monitor.png
├─ Watch-CodexWeeklyReset.ps1
├─ Run-Watch-CodexWeeklyReset.vbs
└─ README.md
```

`Watch-CodexWeeklyReset.ps1`と`Run-Watch-CodexWeeklyReset.vbs`は、同じフォルダへ配置してください。

VBSランチャーは、自身が置かれているフォルダを基準にPowerShellスクリプトを探します。そのため、VBS内へ個人環境の絶対パスを記述する必要はありません。

`assets\codex-monitor.png`は任意です。画像が存在しない場合でもスクリプトは動作し、BurntToastの標準画像が使用されます。

## PowerShellスクリプトの使用方法

### 通知テスト

Windows通知が正しく表示されるか確認します。

```powershell
.\Watch-CodexWeeklyReset.ps1 -TestNotification
```

実行ポリシーの影響で起動できない場合は、次のように実行します。

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\Watch-CodexWeeklyReset.ps1" `
    -TestNotification
```

通知が表示されたら、`Windowsキー + N`で通知センターを開いて確認できます。

### 通常実行

Codexの週次使用状況を取得します。

```powershell
.\Watch-CodexWeeklyReset.ps1
```

実行ポリシーを一時的に回避して起動する場合は、次のように実行します。

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\Watch-CodexWeeklyReset.ps1"
```

動作確認のため、実行後もPowerShellウィンドウを閉じたくない場合は`-NoExit`を追加します。

```powershell
powershell.exe `
    -NoExit `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\Watch-CodexWeeklyReset.ps1"
```

タスクスケジューラで実行する場合は、`-NoExit`を付けないでください。PowerShellプロセスが終了せず、タスクが実行中のまま残る可能性があります。

## 通知サムネイル画像の変更

通知に表示するサムネイル画像は、次のファイルを差し替えることで変更できます。

```text
assets\codex-monitor.png
```

ファイル名は `codex-monitor.png` のままにしてください。

推奨形式は次のとおりです。

```text
形式:
PNG

サイズ:
512 × 512 px

形状:
正方形
```

Windows側で小さく縮小表示されるため、細かすぎる文字や装飾は見えにくくなる場合があります。

画像ファイルが存在する場合は、その画像を通知サムネイルとして使用します。

```text
assets\codex-monitor.png が存在する
→ 指定画像を表示
```

画像ファイルが存在しない場合は、エラーにはせずBurntToastの標準画像を使用します。

```text
assets\codex-monitor.png が存在しない
→ BurntToastの標準画像を表示
```

## VBSランチャー

`Run-Watch-CodexWeeklyReset.vbs`は、PowerShellウィンドウを表示せずに監視スクリプトを実行するためのランチャーです。

Windowsタスクスケジューラから実行する場合は、VBSランチャーを経由することでPowerShellのウィンドウを表示せずに実行できます。

### VBSランチャーの引数

```vbscript
shell.Run command, 0, False
```

それぞれの意味は次のとおりです。

| 値 | 説明 |
|---|---|
| `command` | 実行するPowerShellコマンドです。 |
| `0` | PowerShellウィンドウを非表示にします。 |
| `False` | PowerShellの終了を待たずにVBSを終了します。 |

### VBS経由で通知テストする場合

一時的にVBSから通知テストを実行する場合は、コマンド生成部分を次のように変更します。

```vbscript
command = _
    "powershell.exe " & _
    "-NoProfile " & _
    "-ExecutionPolicy Bypass " & _
    "-File """ & powerShellScript & """ " & _
    "-TestNotification"
```

`-TestNotification`はPowerShell本体のオプションではなく、`Watch-CodexWeeklyReset.ps1`へ渡す引数です。そのため、`-File`でスクリプトを指定した後ろに記述します。

テスト終了後は、通常実行用のコマンドへ戻してください。

## 実行結果の例

```text
Codex週次使用状況
------------------------------
使用済み : 42.5%
残り     : 57.5%
次回     : 2026-07-24 18:30:00 +09:00
状態保存 : C:\Users\<ユーザー名>\AppData\Local\CodexUsageMonitor\weekly-state.json
```

初回実行時は比較対象となる前回データがないため、状態ファイルの保存だけを行い、リセット通知は表示しません。

## リセット判定

スクリプトは、Codex App Serverから取得した次回リセット時刻 `resetsAt` を前回保存した値と比較します。

現在の `resetsAt` が前回値より未来へ進んでいた場合、新しい週次使用枠へ切り替わったと判断します。

```text
前回のresetsAt < 今回のresetsAt
                 ↓
          週次枠のリセットを検知
```

リセットを検知すると、次の内容をWindows通知で表示します。

- 週次使用枠がリセットされたこと
- 現在の残り使用率
- 次回リセット予定日時

## 週次枠の選択方法

Codex App Serverから取得した使用制限情報のうち、次の条件に該当する枠を週次枠の候補として扱います。

- `rateLimitsByLimitId` 内の各制限バケット、または後方互換用の `rateLimits`
- `primary` または `secondary` に存在する
- `windowDurationMins` が6日以上である
- 必須プロパティと値が存在する
  - `usedPercent`
  - `windowDurationMins`
  - `resetsAt`

候補が複数ある場合は、`windowDurationMins` が最も長い枠を使用します。

6日間は次の値として定義されています。

```powershell
$WeeklyMinimumMinutes = 6 * 24 * 60
```

通常の週次枠は7日間ですが、Codex側の仕様差や時間表現のずれを考慮し、少し余裕を持たせています。

## 状態ファイル

既定では、前回の使用状況を次の場所へ保存します。

```text
%LOCALAPPDATA%\CodexUsageMonitor\weekly-state.json
```

保存内容の例です。

```json
{
  "checkedAt": "2026-07-19T19:30:00.0000000+09:00",
  "usedPercent": 42.5,
  "remainingPercent": 57.5,
  "resetsAt": 1784885400,
  "windowDurationMins": 10080
}
```

書き込み途中で状態ファイルが破損しにくいよう、一時ファイルへ保存してから正式な状態ファイルへ移動します。

状態ファイルが存在しない場合は初回実行として扱います。内容が不正な場合も警告を表示し、初回実行として処理を継続します。

## 保存先の変更

`-StateFile`を指定すると、状態ファイルの保存先を変更できます。

```powershell
.\Watch-CodexWeeklyReset.ps1 `
    -StateFile "C:\CodexMonitor\weekly-state.json"
```

指定先の親ディレクトリが存在しない場合は、自動的に作成されます。

## Windowsタスクスケジューラで定期実行する

PowerShellウィンドウを表示せずに定期実行する場合は、VBSランチャーをタスクスケジューラへ登録します。

### 1. タスクを作成する

タスクスケジューラを開き、右側のメニューから「タスクの作成」を選択します。

「基本タスクの作成」ではなく「タスクの作成」を使用すると、繰り返し間隔や重複起動防止などを細かく設定できます。

### 2. 全般

設定例です。

```text
名前:
Codex週次枠リセット監視
```

```text
セキュリティオプション:
ユーザーがログオンしているときのみ実行する
```

Windows通知を表示するため、「ユーザーがログオンしているときのみ実行する」を選択してください。

「最上位の特権で実行する」は、通常は不要です。

### 3. トリガー

1時間ごとに確認する場合の設定例です。

```text
タスクの開始:
スケジュールに従う

設定:
毎日

間隔:
1日

開始:
任意の時刻

繰り返し間隔:
1時間

継続時間:
1日

有効:
オン
```

上側の「間隔」は、何日ごとにトリガーを開始するかを表します。

下側の「繰り返し間隔」は、トリガー開始後に何時間おきにスクリプトを実行するかを表します。

例えば、開始時刻を23:00、繰り返し間隔を1時間、継続時間を1日にした場合、23:00から翌日の22:00まで1時間ごとに実行されます。

### 4. 操作

次のように設定します。

#### プログラム／スクリプト

```text
wscript.exe
```

#### 引数の追加

```text
"C:\path\to\Watch-CodexWeeklyReset\Run-Watch-CodexWeeklyReset.vbs"
```

#### 開始

```text
C:\path\to\Watch-CodexWeeklyReset
```

「開始」にはVBSファイル名ではなく、VBSとPowerShellスクリプトを配置したフォルダを指定します。

### 5. 条件

必要に応じて次を設定します。

```text
コンピューターをAC電源で使用している場合のみタスクを開始する:
必要に応じてオフ
```

スリープ中のPCを起こして実行する場合は、次を有効にします。

```text
タスクを実行するためにスリープを解除する:
オン
```

完全にシャットダウンしているPCをタスクスケジューラだけで起動することはできません。

### 6. 設定

推奨設定です。

```text
タスクを要求時に実行する:
オン
```

```text
スケジュールされた時刻にタスクを開始できなかった場合、
すぐにタスクを実行する:
オン
```

```text
タスクが既に実行中の場合に適用される規則:
新しいインスタンスを開始しない
```

必要に応じて、長時間実行されたタスクを停止する設定も追加できます。

```text
タスクが次の時間より長く実行されている場合は停止する:
5分
```

### 7. 動作確認

タスクスケジューラライブラリから作成したタスクを右クリックし、「実行」を選択します。

通常実行では、週次枠のリセットを検知したときだけ通知が表示されます。初回実行時やリセットされていない場合は、通知が表示されなくても正常です。

通知機能だけを確認する場合は、PowerShellから次を実行してください。

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\Watch-CodexWeeklyReset.ps1" `
    -TestNotification
```

## パラメーター

| パラメーター | 型 | 説明 |
|---|---|---|
| `-TestNotification` | `switch` | Codexへ接続せず、Windows通知のテストだけを実行します。 |
| `-StateFile` | `string` | 前回状態を保存するJSONファイルのパスを指定します。 |

## トラブルシューティング

### BurntToastモジュールが見つからない

```text
BurntToastモジュールが見つかりません。
```

次のコマンドでインストールしてください。

```powershell
Install-Module `
    -Name BurntToast `
    -Scope CurrentUser
```

インストール済みか確認します。

```powershell
Get-Module `
    -ListAvailable `
    -Name BurntToast
```

### Codex CLIが見つからない

```text
Codex CLIが見つかりません。
```

次を確認してください。

```powershell
Get-Command codex
codex --version
codex login status
```

Codex CLIをインストールした直後は、PowerShellを開き直すとPATHが反映される場合があります。

### 使用制限情報を取得できない

```text
使用制限情報を取得できませんでした。
```

Codex CLIのログイン状態を確認してください。

```powershell
codex login status
```

また、Codex CLI自体が正常に起動するか確認してください。

```powershell
codex
```

### 週次制限枠が見つからない

Codex App Serverのレスポンス形式または制限期間が変更された可能性があります。

スクリプトは、取得したすべての制限バケットの `primary` と `secondary` を確認し、6日以上の枠を週次枠として判定します。

取得された `windowDurationMins` が条件を満たさない場合はエラーになります。

### タスクは成功しているが通知が表示されない

次を確認してください。

- タスクの「全般」が「ユーザーがログオンしているときのみ実行する」になっているか
- タスクを実行するユーザーにBurntToastがインストールされているか
- Windowsの通知設定が有効になっているか
- 集中モードで通知が抑制されていないか
- `-TestNotification`を付けた通知テストでは表示されるか
- VBS内の `-TestNotification` が `-File` より後ろに指定されているか

### 通知画像が標準画像になる

次の画像ファイルが存在するか確認してください。

```text
assets\codex-monitor.png
```

次も確認してください。

- ファイル名が `codex-monitor.png` になっている
- `assets`フォルダがPowerShellスクリプトと同じフォルダ内にある
- 画像ファイルを開ける
- PNG形式になっている

画像が存在しない場合は、仕様どおりBurntToastの標準画像が使用されます。

### VBS経由ではエラー内容を確認できない

VBSはPowerShellウィンドウを非表示にするため、PowerShell側でエラーが発生しても画面には表示されません。

デバッグ時は、一時的に次のように変更します。

```vbscript
shell.Run command, 1, True
```

| 値 | 説明 |
|---|---|
| `1` | PowerShellウィンドウを表示します。 |
| `True` | PowerShellが終了するまでVBS側も待機します。 |

原因を確認した後は、通常設定へ戻してください。

```vbscript
shell.Run command, 0, False
```

## 注意事項

- Codex App Serverのレスポンス形式が変更された場合、スクリプトの修正が必要になる可能性があります。
- 週次枠の判定は、制限期間が6日以上であることを基準にしています。
- 通知の表示時間や表示方法は、Windows側の設定にも依存します。
- 通知履歴の表示状態は、Windowsの通知設定や集中モードの影響を受けます。
- タスクスケジューラの実行時刻にPCがシャットダウンしている場合、その時刻には実行されません。
- 「スケジュールされた時刻にタスクを開始できなかった場合、すぐにタスクを実行する」を有効にすると、PC起動後に未実行分を補えます。
- このスクリプトはCodexの使用制限を変更するものではなく、現在の状態を取得して通知するだけです。