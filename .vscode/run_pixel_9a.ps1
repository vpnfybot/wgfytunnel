param(
    [switch]$LaunchOnly
)

$ErrorActionPreference = 'Stop'

$sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$flutter = Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat'
$emulator = Join-Path $sdkRoot 'emulator-36.1.9\emulator\emulator.exe'
$adb = Join-Path $sdkRoot 'platform-tools\adb.exe'
$playStoreImagePath = Join-Path $sdkRoot 'system-images\android-36\google_apis_playstore\x86_64'
$avd = 'Pixel_9a_API_36'
$avdConfigPath = Join-Path $env:USERPROFILE ".android\avd\$avd.avd\config.ini"
$serial = 'emulator-5554'
$emulatorArgs = @(
    '-avd', $avd,
    '-port', '5554',
    '-no-snapshot-load',
    '-gpu', 'swiftshader_indirect',
    '-skin', '1080x2424'
)

$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot

function Invoke-Adb {
    param(
        [string[]]$Arguments
    )

    try {
        $output = & $adb @Arguments 2>$null
        return [pscustomobject]@{
            Output = ($output | Out-String).Trim()
            ExitCode = $LASTEXITCODE
        }
    } catch {
        return [pscustomobject]@{
            Output = ''
            ExitCode = 1
        }
    }
}

function Stop-EmulatorProcesses {
    Get-Process emulator, qemu-system-x86_64, qemu-system-x86_64-headless -ErrorAction SilentlyContinue |
        Stop-Process -Force
}

function Test-TargetEmulatorRunning {
    $result = Invoke-Adb -Arguments @('-s', $serial, 'emu', 'avd', 'name')
    return $result.ExitCode -eq 0 -and $result.Output -eq $avd
}

function Set-AvdConfigValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]](Get-Content $Path))

    $updated = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -like "$Key=*") {
            if ($lines[$index] -ne "$Key=$Value") {
                $lines[$index] = "$Key=$Value"
                $updated = $true
            }

            break
        }
    }

    if (-not ($lines -like "$Key=*")) {
        $lines.Add("$Key=$Value")
        $updated = $true
    }

    if ($updated) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($Path, [string[]]$lines, $utf8NoBom)
    }
}

function Ensure-CompatibleAvdConfig {
    Set-AvdConfigValue -Path $avdConfigPath -Key 'showDeviceFrame' -Value 'no'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'PlayStore.enabled' -Value 'true'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'fastboot.forceColdBoot' -Value 'yes'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'fastboot.forceFastBoot' -Value 'no'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'hw.device.hash2' -Value 'MD5:5478e3411cc0e0441240e736eb14c07a'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'hw.device.name' -Value 'pixel_9'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'hw.gpu.enabled' -Value 'yes'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'hw.gpu.mode' -Value 'swiftshader'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'image.sysdir.1' -Value 'system-images\android-36\google_apis_playstore\x86_64\'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'tag.display' -Value 'Google Play'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'tag.displaynames' -Value 'Google Play'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'tag.id' -Value 'google_apis_playstore'
    Set-AvdConfigValue -Path $avdConfigPath -Key 'tag.ids' -Value 'google_apis_playstore'
}

function Wait-ForDevice {
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $state = (Invoke-Adb -Arguments @('-s', $serial, 'get-state')).Output
        if ($state -eq 'device') {
            return $true
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

function Wait-ForBootComplete {
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $bootCompleted = (Invoke-Adb -Arguments @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed')).Output
        if ($bootCompleted -eq '1') {
            return $true
        }

        Start-Sleep -Seconds 2
    }

    return $false
}

if (-not (Test-Path $emulator)) {
    throw "Android emulator 36.1.9 not found at $emulator"
}

if (-not (Test-Path $adb)) {
    throw "adb not found at $adb"
}

if (-not (Test-Path $playStoreImagePath)) {
    throw "Android 16 Google Play x86_64 image not found at $playStoreImagePath"
}

if (-not $LaunchOnly -and -not (Test-Path $flutter)) {
    throw "Flutter SDK not found at $flutter"
}

Ensure-CompatibleAvdConfig

$null = & $adb start-server

if (-not (Test-TargetEmulatorRunning)) {
    Stop-EmulatorProcesses
    Start-Process -FilePath $emulator -ArgumentList $emulatorArgs
}

if (-not (Wait-ForDevice) -or -not (Wait-ForBootComplete)) {
    throw 'Pixel 9a emulator did not become ready.'
}

if ($LaunchOnly) {
    return
}

& $flutter run -d $serial