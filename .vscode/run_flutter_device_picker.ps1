$ErrorActionPreference = 'Stop'

$flutterPath = Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat'
if (-not (Test-Path $flutterPath)) {
  $flutterPath = 'flutter'
}

Write-Host 'Detecting Flutter devices...'
$rawDevices = & $flutterPath devices --machine

if (-not $rawDevices) {
  throw 'No output from "flutter devices --machine".'
}

$devices = $rawDevices | ConvertFrom-Json
if (-not $devices -or $devices.Count -eq 0) {
  throw 'No Flutter devices found. Connect/start a device and try again.'
}

Write-Host ''
Write-Host 'Available devices:'
for ($i = 0; $i -lt $devices.Count; $i++) {
  $device = $devices[$i]
  $platform = if ($device.targetPlatform) { $device.targetPlatform } else { 'unknown' }
  $emulatorMark = if ($device.emulator) { 'emulator' } else { 'physical' }
  Write-Host ("[{0}] {1} ({2}, {3})" -f $i, $device.name, $platform, $emulatorMark)
  Write-Host ("     id: {0}" -f $device.id)
}

Write-Host ''
$selectedIndex = $null
while ($null -eq $selectedIndex) {
  $inputValue = Read-Host 'Enter device number'
  $parsedIndex = 0
  if (-not [int]::TryParse($inputValue, [ref]$parsedIndex)) {
    Write-Host 'Please enter a valid number.' -ForegroundColor Yellow
    continue
  }

  if ($parsedIndex -lt 0 -or $parsedIndex -ge $devices.Count) {
    Write-Host 'Number out of range.' -ForegroundColor Yellow
    continue
  }

  $selectedIndex = $parsedIndex
}

$selectedDevice = $devices[$selectedIndex]
Write-Host ''
Write-Host ("Starting app on: {0} ({1})" -f $selectedDevice.name, $selectedDevice.id)

& $flutterPath run -d $selectedDevice.id
exit $LASTEXITCODE