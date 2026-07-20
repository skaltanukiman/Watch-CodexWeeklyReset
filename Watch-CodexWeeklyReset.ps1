param(
    [switch]$TestNotification,

    [string]$StateFile = (
        Join-Path $env:LOCALAPPDATA `
            "CodexUsageMonitor\weekly-state.json"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 6日以上の制限期間を週次枠として判定する
# 週次枠は通常7日間だが、Codex側の仕様差や時間表現のずれを考慮し、
# 少し余裕を持たせて6日以上の制限枠を週次枠の候補として扱う。
$WeeklyMinimumMinutes = 6 * 24 * 60

$TimeoutSeconds = 20

<#
.SYNOPSIS
WindowsのToast通知を表示します。

.DESCRIPTION
BurntToastモジュールを使用して、
指定されたタイトルとメッセージをWindows通知として表示します。

スクリプトと同じフォルダ内の
assets\codex-monitor.pngが存在する場合は、
通知のアプリロゴとして使用します。

画像が存在しない場合は、
BurntToastの標準画像を使用します。

BurntToastモジュールがインストールされていない場合や、
通知の表示に失敗した場合は例外を発生させます。

.PARAMETER Title
Windows通知に表示するタイトルです。

.PARAMETER Message
Windows通知の本文として表示するメッセージです。
#>
function Show-WindowsNotification {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $burntToastModule =
        Get-Module `
            -ListAvailable `
            -Name BurntToast |
        Select-Object -First 1

    if ($null -eq $burntToastModule) {
        throw (
            "BurntToastモジュールが見つかりません。`n" +
            "次のコマンドでインストールしてください。`n" +
            "Install-Module -Name BurntToast -Scope CurrentUser"
        )
    }

    Import-Module `
        BurntToast `
        -ErrorAction Stop

    # スクリプトと同じフォルダにある
    # assets\codex-monitor.pngを通知画像の候補とする。
    $appLogoPath = Join-Path `
        $PSScriptRoot `
        "assets\codex-monitor.png"

    $notificationParameters = @{
        Text = @(
            $Title
            $Message
        )
        ErrorAction = "Stop"
    }

    # 画像が存在する場合のみ通知のアプリロゴへ設定する。
    # 存在しない場合はBurntToastの標準画像を使用する。
    if (Test-Path -LiteralPath $appLogoPath) {
        $notificationParameters.AppLogo = $appLogoPath
    }

    New-BurntToastNotification @notificationParameters
}

<#
.SYNOPSIS
Codex App ServerへJSON-RPCメッセージを送信します。

.DESCRIPTION
指定されたハッシュテーブルをJSON形式に変換し、
Codex App Serverプロセスの標準入力へ1行のJSONLとして送信します。

Codex App Serverとの初期化処理や、
使用制限情報の取得リクエストに使用します。

.PARAMETER Process
JSON-RPCメッセージの送信先となる
Codex App Serverのプロセスです。

.PARAMETER Message
Codex App Serverへ送信するJSON-RPCメッセージです。
#>
function Send-AppServerMessage {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [hashtable]$Message
    )

    $json = $Message |
        ConvertTo-Json -Compress -Depth 10

    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
}

<#
.SYNOPSIS
Codex CLIから現在の使用制限情報を取得します。

.DESCRIPTION
Codex CLIのApp Serverを標準入出力モードで起動し、
JSON-RPCを使用して現在の使用制限情報を取得します。

App Serverの初期化後、
account/rateLimits/readリクエストを送信します。

指定時間内にレスポンスを取得できなかった場合や、
Codex CLIが見つからない場合は例外を発生させます。

.OUTPUTS
Codex App Serverから返された使用制限情報のオブジェクトです。
#>
function Get-CodexRateLimits {
    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue

    if (-not $codexCommand) {
        throw (
            "Codex CLIが見つかりません。`n" +
            "Codex CLIをインストールし、codex login statusを確認してください。"
        )
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo

    # npmなどで導入されたcodex.cmdにも対応するため
    # cmd.exeを経由して起動する
    $startInfo.FileName = $env:ComSpec

    $startInfo.Arguments = '/d /s /c "codex app-server"'

    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process

    $process.StartInfo = $startInfo

    $response = $null
    $errorOutput = ""

    try {
        if (-not $process.Start()) {
            throw "Codex App Serverを起動できませんでした。"
        }

        Send-AppServerMessage `
            -Process $process `
            -Message @{
                method = "initialize"
                id = 1
                params = @{
                    clientInfo = @{
                        name = "codex_usage_monitor"
                        title = "Codex Usage Monitor"
                        version = "1.0.0"
                    }
                }
            }

        Send-AppServerMessage `
            -Process $process `
            -Message @{
                method = "initialized"
                params = @{}
            }

        Send-AppServerMessage `
            -Process $process `
            -Message @{
                method = "account/rateLimits/read"
                id = 2
            }

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

        $readTask = $process.StandardOutput.ReadLineAsync()

        while ([DateTime]::UtcNow -lt $deadline) {
            if (-not $readTask.Wait(250)) {
                continue
            }

            $line = $readTask.Result

            if ($null -eq $line) {
                break
            }

            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try {
                    $message = $line | ConvertFrom-Json

                    # 通知など、idを持たないメッセージもあるため、
                    # プロパティの存在を確認してから値を参照する。
                    $idProperty = $message.PSObject.Properties["id"]

                    if (
                        $null -ne $idProperty -and
                        $idProperty.Value -eq 2
                    ) {
                        # errorはエラー応答時にだけ存在するため、
                        # プロパティの存在を確認してから内容を参照する。
                        $errorProperty = $message.PSObject.Properties["error"]

                        if (
                            $null -ne $errorProperty -and
                            $null -ne $errorProperty.Value
                        ) {
                            $errorMessageProperty = $errorProperty.Value.PSObject.Properties["message"]

                            $errorMessage = if ($null -ne $errorMessageProperty) {
                                [string]$errorMessageProperty.Value
                            }
                            else {
                                "詳細不明のエラー"
                            }

                            throw (
                                "Codexからエラーが返されました: " +
                                $errorMessage
                            )
                        }

                        # 正常応答にはresultが必要。
                        $resultProperty = $message.PSObject.Properties["result"]

                        if ($null -eq $resultProperty) {
                            throw (
                                "Codexからの応答にresultプロパティが" +
                                "含まれていませんでした。"
                            )
                        }

                        $response = $resultProperty.Value
                        break
                    }
                }
                catch {
                    # JSON以外の標準出力は読み飛ばす。
                    # id=2のレスポンス処理中のエラーだけ再送出する。
                    if ($line -match '"id"\s*:\s*2') {
                        throw
                    }
                }
            }

            $readTask = $process.StandardOutput.ReadLineAsync()
        }
    }
    finally {
        try {
            $process.StandardInput.Close()
        }
        catch {
            # 終了処理なので無視する
        }

        if (-not $process.HasExited) {
            try {
                $process.Kill()

                # WaitForExitの戻り値が関数の出力に混入しないよう破棄する
                [void]$process.WaitForExit(3000)
            }
            catch {
                # 終了処理なので無視する
            }
        }

        try {
            $errorOutput = $process.StandardError.ReadToEnd()
        }
        catch {
            # 標準エラーを取得できなくても処理を続ける
        }

        $process.Dispose()
    }

    if (-not $response) {
        $detail = if (
            [string]::IsNullOrWhiteSpace($errorOutput)
        ) {
            "Codex CLIのログイン状態を確認してください。"
        }
        else {
            $errorOutput.Trim()
        }

        throw (
            "使用制限情報を取得できませんでした。`n" +
            $detail
        )
    }

    return $response
}

<#
.SYNOPSIS
Codexの使用制限情報から週次制限枠を取得します。

.DESCRIPTION
Codex App Serverから取得したすべての使用制限バケットを確認します。

rateLimitsByLimitIdに含まれる各バケットと、
後方互換用のrateLimitsを週次制限の検索対象とします。

各バケットのprimaryおよびsecondaryのうち、
制限期間が6日以上の枠を週次制限の候補として抽出し、
候補が複数ある場合は最も制限期間が長い枠を返します。

週次制限枠が見つからない場合や、
後続処理に必要なプロパティまたは値が存在しない場合は
例外を発生させます。

.PARAMETER RateLimits
Codex App Serverから取得した使用制限情報です。

.OUTPUTS
週次制限枠を表すオブジェクトです。
#>
function Get-WeeklyWindow {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $RateLimits
    )

    # 使用制限バケットを格納する。
    $bucketCandidates = @()

    # rateLimitsByLimitIdに含まれる全バケットを取得する。
    $rateLimitsByIdProperty = $RateLimits.PSObject.Properties["rateLimitsByLimitId"]

    if (
        $null -ne $rateLimitsByIdProperty -and
        $null -ne $rateLimitsByIdProperty.Value
    ) {
        foreach (
            $bucketProperty in
            $rateLimitsByIdProperty.Value.PSObject.Properties
        ) {
            if ($null -ne $bucketProperty.Value) {
                $bucketCandidates += $bucketProperty.Value
            }
        }
    }

    # 後方互換用のrateLimitsも検索対象に追加する。
    $rateLimitsProperty = $RateLimits.PSObject.Properties["rateLimits"]

    if (
        $null -ne $rateLimitsProperty -and
        $null -ne $rateLimitsProperty.Value
    ) {
        $bucketCandidates += $rateLimitsProperty.Value
    }

    if ($bucketCandidates.Count -eq 0) {
        $responseProperties = @($RateLimits.PSObject.Properties.Name) -join ", "

        throw (
            "Codexの使用制限バケットが見つかりませんでした。`n" +
            "取得したトップレベルプロパティ: " +
            $responseProperties
        )
    }

    # 全バケットのprimaryとsecondaryを制限枠候補として取得する。
    $windowCandidates = @()

    foreach ($bucket in $bucketCandidates) {
        foreach ($propertyName in @("primary", "secondary")) {
            $windowProperty = $bucket.PSObject.Properties[$propertyName]

            if (
                $null -ne $windowProperty -and
                $null -ne $windowProperty.Value
            ) {
                $windowCandidates += $windowProperty.Value
            }
        }
    }

    # 制限期間が6日以上の枠だけを週次枠候補として残す。
    $windows = @(
        $windowCandidates |
            Where-Object {
                $durationProperty =
                    $_.PSObject.Properties["windowDurationMins"]

                $null -ne $durationProperty -and
                $null -ne $durationProperty.Value -and
                [double]$durationProperty.Value `
                    -ge $WeeklyMinimumMinutes
            }
    )

    if ($windows.Count -eq 0) {
        $availableDurations = @(
            foreach ($window in $windowCandidates) {
                $durationProperty = $window.PSObject.Properties["windowDurationMins"]

                if (
                    $null -ne $durationProperty -and
                    $null -ne $durationProperty.Value
                ) {
                    [string]$durationProperty.Value
                }
            }
        ) -join ", "

        throw (
            "6日以上の週次制限枠が見つかりませんでした。`n" +
            "取得できた制限期間（分）: " +
            $availableDurations
        )
    }

    # 候補が複数ある場合は、最も制限期間が長い枠を選択する。
    $weeklyWindow =
        $windows |
        Sort-Object `
            -Property @{
                Expression = {
                    [double](
                        $_.PSObject.Properties[
                            "windowDurationMins"
                        ].Value
                    )
                }
            } `
            -Descending |
        Select-Object -First 1

    # 後続処理で使用する必須プロパティと値を確認する。
    foreach (
        $requiredProperty in @(
            "usedPercent",
            "windowDurationMins",
            "resetsAt"
        )
    ) {
        $property = $weeklyWindow.PSObject.Properties[$requiredProperty]

        if (
            $null -eq $property -or
            $null -eq $property.Value
        ) {
            throw (
                "週次制限枠に必須プロパティ「" +
                $requiredProperty +
                "」またはその値がありません。"
            )
        }
    }

    return $weeklyWindow
}

<#
.SYNOPSIS
前回保存したCodexの使用状況を読み込みます。

.DESCRIPTION
状態保存ファイルが存在する場合、
JSON形式で保存されている前回の使用率や
リセット予定時刻を読み込みます。

状態ファイルが存在しない場合は、
初回実行としてnullを返します。

状態ファイルの内容が不正な場合も、
警告を表示したうえで初回実行として扱います。

.OUTPUTS
前回保存された使用状況のオブジェクトです。

状態ファイルが存在しない場合や
読み込みに失敗した場合はnullを返します。
#>
function Read-PreviousState {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return $null
    }

    try {
        return Get-Content `
            -LiteralPath $StateFile `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        Write-Warning (
            "前回の状態ファイルを読み込めませんでした。" +
            "初回実行として扱います。"
        )

        return $null
    }
}

<#
.SYNOPSIS
現在のCodex使用状況を状態ファイルへ保存します。

.DESCRIPTION
現在の使用率、残り使用率、次回リセット時刻、
制限期間および確認日時をJSON形式で保存します。

書き込み途中で状態ファイルが破損しないよう、
一時ファイルへ書き込んだ後に正式な状態ファイルへ移動します。

保存された情報は、次回実行時に週次枠が
リセットされたかどうかを判定するために使用します。

.PARAMETER UsedPercent
現在の週次枠の使用済み割合です。

.PARAMETER RemainingPercent
現在の週次枠の残り使用率です。

.PARAMETER ResetsAt
次回リセット時刻を表すUnixタイムスタンプです。

.PARAMETER WindowDurationMins
制限期間を分単位で表した値です。
#>
function Save-CurrentState {
    param(
        [Parameter(Mandatory)]
        [double]$UsedPercent,

        [Parameter(Mandatory)]
        [double]$RemainingPercent,

        [Parameter(Mandatory)]
        [long]$ResetsAt,

        [Parameter(Mandatory)]
        [long]$WindowDurationMins
    )

    $directory = Split-Path -Parent $StateFile

    $temporaryFile = "$StateFile.tmp"

    New-Item `
        -ItemType Directory `
        -Path $directory `
        -Force |
        Out-Null

    [ordered]@{
        checkedAt = [DateTimeOffset]::Now.ToString("o")
        usedPercent = $UsedPercent
        remainingPercent = $RemainingPercent
        resetsAt = $ResetsAt
        windowDurationMins = $WindowDurationMins
    } |
        ConvertTo-Json |
        Set-Content `
            -LiteralPath $temporaryFile `
            -Encoding UTF8

    Move-Item `
        -LiteralPath $temporaryFile `
        -Destination $StateFile `
        -Force
}


# ============================================================
# メイン処理
# ============================================================

# 通知テストモード
# -TestNotificationが指定された場合は、通知テストだけを行って終了する。
if ($TestNotification) {
    Show-WindowsNotification `
        -Title "Codex通知テスト" `
        -Message "Windows通知は正常に動作しています。"

    Write-Host "通知テストを実行しました。"
    exit 0
}

# 通常実行
# Codexの週次使用状況を取得し、前回の状態と比較してリセットを検知する。
try {
    $rateLimits = Get-CodexRateLimits

    $weeklyWindow = Get-WeeklyWindow -RateLimits $rateLimits

    $usedPercent = [double]$weeklyWindow.usedPercent

    # 残り使用可能率を算出、100%の状態から取得した使用済みパーセントを引く
    $remainingPercent =
        [Math]::Max(
            0,
            [Math]::Round(
                100 - $usedPercent,
                1
            )
        )

    $resetsAt = [long]$weeklyWindow.resetsAt

    $windowDurationMins = [long]$weeklyWindow.windowDurationMins

    # 次回リセット時刻をUnixタイムスタンプからDateTimeOffsetに変換し、ローカルタイムに変換する
    $resetDate =
        [DateTimeOffset]::FromUnixTimeSeconds(
            $resetsAt
        ).ToLocalTime()

    $previousState = Read-PreviousState
    $resetDetected = $false

    $previousResetsAtProperty = if ($null -ne $previousState) {
        $previousState.PSObject.Properties["resetsAt"]
    }
    else {
        $null
    }

    if (
        $null -ne $previousResetsAtProperty -and
        $null -ne $previousResetsAtProperty.Value
    ) {
        # 前回情報のリセット時刻Unixタイムスタンプ
        $previousResetsAt = [long]$previousResetsAtProperty.Value

        # 次回リセット日時が前回より未来へ進んだ場合、
        # 新しい週次枠へ切り替わったと判定する
        if ($resetsAt -gt $previousResetsAt) {
            $resetDetected = $true
        }
    }

    Save-CurrentState `
        -UsedPercent $usedPercent `
        -RemainingPercent $remainingPercent `
        -ResetsAt $resetsAt `
        -WindowDurationMins $windowDurationMins

    Write-Host "Codex週次使用状況"
    Write-Host "------------------------------"
    Write-Host "使用済み : $usedPercent%"
    Write-Host "残り     : $remainingPercent%"

    Write-Host (
        "次回     : " +
        $resetDate.ToString(
            "yyyy-MM-dd HH:mm:ss zzz"
        )
    )

    Write-Host "状態保存 : $StateFile"

    if ($resetDetected) {
        $message = @(
            "週次使用枠がリセットされました。"
            "現在の残り: $remainingPercent%"
            (
                "次回リセット: " +
                $resetDate.ToString(
                    "yyyy-MM-dd HH:mm"
                )
            )
        ) -join "`n"

        Show-WindowsNotification `
            -Title "Codex週次枠リセット" `
            -Message $message

        Write-Host "Windows通知を送信しました。"
    }
}
catch {
    # 発生したエラーの詳細を出力し、異常終了コードでスクリプトを終了する。
    Write-Error `
        -ErrorRecord $_ `
        -ErrorAction Continue
        
    exit 1
}