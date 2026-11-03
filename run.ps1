param(
    [ValidateSet('run','debug','release','analyze','doctor')]
    [string]$Task = 'run',
    [string]$Device = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExecutable = if ($flutterCommand) { $flutterCommand.Source } else { $null }
if (!$flutterExecutable -and $env:FLUTTER_ROOT) {
    $candidate = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
    if (Test-Path -LiteralPath $candidate) { $flutterExecutable = $candidate }
}
if (!$flutterExecutable -and (Test-Path -LiteralPath 'D:\develop\flutter\bin\flutter.bat')) {
    $flutterExecutable = 'D:\develop\flutter\bin\flutter.bat'
}
if (!$flutterExecutable) { throw 'Install the stable Flutter SDK and add flutter/bin to PATH, or set FLUTTER_ROOT.' }
Push-Location -LiteralPath $projectRoot
try {
    & $flutterExecutable pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    switch ($Task) {
        'run' { if ($Device) { & $flutterExecutable run -d $Device } else { & $flutterExecutable run } }
        'debug' { & $flutterExecutable build apk --debug }
        'release' { & $flutterExecutable build apk --release --split-per-abi }
        'analyze' { & $flutterExecutable analyze }
        'doctor' { & $flutterExecutable doctor -v }
    }
    $resultCode = $LASTEXITCODE
} finally { Pop-Location }
exit $resultCode
