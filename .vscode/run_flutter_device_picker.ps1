param(
  [switch]$ListOnly,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterRunArgs
)

$ErrorActionPreference = 'Stop'

$sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$flutterPath = Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat'
if (-not (Test-Path $flutterPath)) {
  $flutterPath = 'flutter'
}

$adbPath = Join-Path $sdkRoot 'platform-tools\adb.exe'
$emulatorCandidates = @(
  (Join-Path $sdkRoot 'emulator-36.1.9\emulator\emulator.exe'),
  (Join-Path $sdkRoot 'emulator\emulator.exe')
)
$emulatorPath = $emulatorCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot

function Invoke-Adb {
  param(
    [string[]]$Arguments
  )

  if (-not (Test-Path $adbPath)) {
    return [pscustomobject]@{
      Output = ''
      ExitCode = 1
    }
  }

  try {
    $output = & $adbPath @Arguments 2>$null
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

function Get-FlutterAndroidDevices {
  $rawDevices = & $flutterPath devices --machine
  if (-not $rawDevices) {
    return @()
  }

  $devices = $rawDevices | ConvertFrom-Json
  if ($null -eq $devices) {
    return @()
  }

  return @(
    $devices | Where-Object {
      $_.isSupported -and $_.targetPlatform -like 'android*'
    }
  )
}

function Get-RunningEmulatorAvdName {
  param(
    [string]$DeviceId
  )

  if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    return $null
  }

  $result = Invoke-Adb -Arguments @('-s', $DeviceId, 'emu', 'avd', 'name')
  if ($result.ExitCode -ne 0) {
    return $null
  }

  $avdName = @(
    $result.Output -split "`r?`n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -and $_ -ne 'OK' }
  ) | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($avdName)) {
    return $null
  }

  return $avdName
}

function Get-AvailableAndroidEmulators {
  $emulators = @()

  try {
    $flutterEmulatorLines = & $flutterPath emulators 2>$null
    foreach ($line in $flutterEmulatorLines) {
      if ($line -notmatch '•' -or $line -match '^\s*Id\s+•') {
        continue
      }

      $parts = @($line -split '\s*•\s*' | ForEach-Object { $_.Trim() })
      if ($parts.Count -lt 4) {
        continue
      }

      $emulators += [pscustomobject]@{
        Id = $parts[0]
        Name = $parts[1]
        Manufacturer = $parts[2]
        Platform = $parts[3]
      }
    }
  } catch {
  }

  if ($emulators.Count -gt 0) {
    return $emulators
  }

  if ($emulatorPath) {
    try {
      $avds = & $emulatorPath -list-avds 2>$null
      foreach ($avd in $avds) {
        $avdName = $avd.Trim()
        if ([string]::IsNullOrWhiteSpace($avdName)) {
          continue
        }

        $emulators += [pscustomobject]@{
          Id = $avdName
          Name = $avdName
          Manufacturer = 'Android'
          Platform = 'android'
        }
      }
    } catch {
    }
  }

  return $emulators
}

function Wait-ForEmulatorDevice {
  param(
    [string]$AvdId,
    [string[]]$KnownDeviceIds = @()
  )

  for ($attempt = 0; $attempt -lt 180; $attempt++) {
    $devices = Get-FlutterAndroidDevices
    foreach ($device in $devices | Where-Object { $_.emulator }) {
      $deviceId = [string]$device.id
      if ($KnownDeviceIds -contains $deviceId) {
        continue
      }

      $runningAvdName = Get-RunningEmulatorAvdName -DeviceId $deviceId
      if ($runningAvdName -eq $AvdId) {
        return $device
      }
    }

    Start-Sleep -Seconds 2
  }

  return $null
}

function Wait-ForBootComplete {
  param(
    [string]$DeviceId
  )

  for ($attempt = 0; $attempt -lt 180; $attempt++) {
    $bootCompleted = Invoke-Adb -Arguments @('-s', $DeviceId, 'shell', 'getprop', 'sys.boot_completed')
    if ($bootCompleted.ExitCode -eq 0 -and $bootCompleted.Output -eq '1') {
      return $true
    }

    Start-Sleep -Seconds 2
  }

  return $false
}

function Start-AndroidEmulator {
  param(
    [string]$AvdId
  )

  if (-not $emulatorPath) {
    throw 'Android emulator executable not found in the SDK.'
  }

  $emulatorArgs = @('-avd', $AvdId, '-no-snapshot-load')
  if ($AvdId -eq 'Pixel_9a_API_36') {
    $emulatorArgs += @('-gpu', 'swiftshader_indirect', '-skin', '1080x2424')
  }

  Start-Process -FilePath $emulatorPath -ArgumentList $emulatorArgs | Out-Null
}

Write-Host 'Detecting Android targets...'

$runningDevices = Get-FlutterAndroidDevices
$runningEmulatorByAvd = @{}
$targets = New-Object System.Collections.Generic.List[object]

foreach ($device in $runningDevices) {
  $deviceId = [string]$device.id
  $targetPlatform = if ($device.targetPlatform) { [string]$device.targetPlatform } else { 'android' }

  if ($device.emulator) {
    $avdName = Get-RunningEmulatorAvdName -DeviceId $deviceId
    if (-not $avdName) {
      $avdName = [string]$device.name
    }

    $runningEmulatorByAvd[$avdName] = $device
    $targets.Add([pscustomobject]@{
      Kind = 'running-emulator'
      DisplayName = [string]$device.name
      Description = 'android emulator, running'
      DeviceId = $deviceId
      AvdId = $avdName
      Platform = $targetPlatform
    })
    continue
  }

  $targets.Add([pscustomobject]@{
    Kind = 'running-device'
    DisplayName = [string]$device.name
    Description = 'android device, connected'
    DeviceId = $deviceId
    AvdId = $null
    Platform = $targetPlatform
  })
}

$availableEmulators = Get-AvailableAndroidEmulators
foreach ($emulator in $availableEmulators) {
  $emulatorId = [string]$emulator.Id
  if ($runningEmulatorByAvd.ContainsKey($emulatorId)) {
    continue
  }

  $targets.Add([pscustomobject]@{
    Kind = 'available-emulator'
    DisplayName = [string]$emulator.Name
    Description = 'android emulator, launch on selection'
    DeviceId = $null
    AvdId = $emulatorId
    Platform = [string]$emulator.Platform
  })
}

if ($targets.Count -eq 0) {
  throw 'No Android devices or emulators found. Connect/start a device and try again.'
}

Write-Host ''
Write-Host 'Available Android targets:'
for ($i = 0; $i -lt $targets.Count; $i++) {
  $target = $targets[$i]
  Write-Host ("[{0}] {1} ({2})" -f $i, $target.DisplayName, $target.Description)
  if ($target.DeviceId) {
    Write-Host ("     id: {0}" -f $target.DeviceId)
  }
  if ($target.AvdId) {
    Write-Host ("     avd: {0}" -f $target.AvdId)
  }
}

if ($ListOnly) {
  return
}

Write-Host ''
$selectedIndex = $null
while ($null -eq $selectedIndex) {
  $inputValue = Read-Host 'Enter target number'
  $parsedIndex = 0
  if (-not [int]::TryParse($inputValue, [ref]$parsedIndex)) {
    Write-Host 'Please enter a valid number.' -ForegroundColor Yellow
    continue
  }

  if ($parsedIndex -lt 0 -or $parsedIndex -ge $targets.Count) {
    Write-Host 'Number out of range.' -ForegroundColor Yellow
    continue
  }

  $selectedIndex = $parsedIndex
}

$selectedTarget = $targets[$selectedIndex]
$selectedDeviceId = $selectedTarget.DeviceId

if ($selectedTarget.Kind -eq 'available-emulator') {
  $knownDeviceIds = @($runningDevices | ForEach-Object { [string]$_.id })
  Write-Host ''
  Write-Host ("Launching emulator: {0} ({1})" -f $selectedTarget.DisplayName, $selectedTarget.AvdId)
  Start-AndroidEmulator -AvdId $selectedTarget.AvdId

  $launchedDevice = Wait-ForEmulatorDevice -AvdId $selectedTarget.AvdId -KnownDeviceIds $knownDeviceIds
  if (-not $launchedDevice) {
    throw "Timed out waiting for emulator '$($selectedTarget.AvdId)' to appear in Flutter devices."
  }

  $selectedDeviceId = [string]$launchedDevice.id
  if (-not (Wait-ForBootComplete -DeviceId $selectedDeviceId)) {
    throw "Emulator '$($selectedTarget.AvdId)' did not finish booting."
  }
}

Write-Host ''
Write-Host ("Starting app on: {0} ({1})" -f $selectedTarget.DisplayName, $selectedDeviceId)

& $flutterPath run -d $selectedDeviceId @FlutterRunArgs
exit $LASTEXITCODE