# Watch Codex Weekly Reset

Codex CLIから使用制限情報を取得し、週次使用枠のリセットを検知したときにWindows通知を表示するPowerShellスクリプトです。

前回取得したリセット予定時刻をローカルのJSONファイルへ保存し、次回実行時の値と比較して週次枠の切り替わりを判定します。

## 主な機能

* Codex App Serverから現在の使用制限情報を取得
* 6日以上の制限枠を週次枠の候補として判定
* 複数の候補がある場合は、制限期間が最も長い枠を選択
* 使用済み割合、残り割合、次回リセット日時を表示
* 前回実行時の状態をJSONファイルへ保存
* 週次枠のリセットを検知した場合にWindows通知を表示
* `-TestNotification`による通知単体テスト

## 動作環境

* Windows
* Windows PowerShell 5.1以降
* Codex CLI
* Codex CLIへログイン済みであること

Codex CLIが利用できることを、次のコマンドで確認してください。

```powershell
codex --version
codex login status
```

`codex`コマンドが見つからない場合は、Codex CLIをインストールしてPATHを設定してください。

## ファイル構成

```text
Watch-CodexWeeklyReset/
├─ Watch-CodexWeeklyReset.ps1
└─ README.md
```

## 使用方法

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

スクリプトは、Codex App Serverから取得した次回リセット時刻`resetsAt`を前回保存した値と比較します。

現在の`resetsAt`が前回値より未来へ進んでいた場合、新しい週次使用枠へ切り替わったと判断します。

```text
前回のresetsAt < 今回のresetsAt
                 ↓
          週次枠のリセットを検知
```

リセットを検知すると、次の内容をWindows通知で表示します。

* 週次使用枠がリセットされたこと
* 現在の残り使用率
* 次回リセット予定日時

## 週次枠の選択方法

Codex App Serverから取得した使用制限情報のうち、次の条件に該当する枠を週次枠の候補として扱います。

* `primary`または`secondary`に存在する
* `windowDurationMins`が6日以上である
* 必須プロパティが存在する

  * `usedPercent`
  * `windowDurationMins`
  * `resetsAt`

候補が複数ある場合は、`windowDurationMins`が最も長い枠を使用します。

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

定期的にリセットを確認する場合は、Windowsタスクスケジューラへ登録します。

### プログラム

```text
powershell.exe
```

### 引数の追加

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\Watch-CodexWeeklyReset.ps1"
```

### 開始

スクリプトを配置したディレクトリを指定します。

```text
C:\path\to
```

確認頻度は1時間ごとなど、用途に合わせて設定してください。

タスクスケジューラで実行する場合、`-NoExit`は付けないでください。`-NoExit`を付けるとPowerShellプロセスが終了せず、タスクが実行中のまま残る可能性があります。

また、Windows通知を表示するには、ユーザーがログオンしている状態でタスクを実行する設定が適しています。

## パラメーター

| パラメーター              | 型        | 説明                                |
| ------------------- | -------- | --------------------------------- |
| `-TestNotification` | `switch` | Codexへ接続せず、Windows通知のテストだけを実行します。 |
| `-StateFile`        | `string` | 前回状態を保存するJSONファイルのパスを指定します。       |

## トラブルシューティング

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

スクリプトは6日以上の制限枠を週次枠として判定しているため、取得された`windowDurationMins`が条件を満たさない場合はエラーになります。

### 通知が表示されない

まず通知テストを実行してください。

```powershell
.\Watch-CodexWeeklyReset.ps1 -TestNotification
```

Windowsの通知設定、集中モード、PowerShellの実行ユーザー、タスクスケジューラのログオン設定も確認してください。

## 注意事項

* Codex App Serverのレスポンス形式が変更された場合、スクリプトの修正が必要になる可能性があります。
* 週次枠の判定は、制限期間が6日以上であることを基準にしています。
* 通知の表示時間や表示方法は、Windows側の設定にも依存します。
* このスクリプトはCodexの使用制限を変更するものではなく、現在の状態を取得して通知するだけです。
