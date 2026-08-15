param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ReportPath = (Join-Path $ProjectPath "test-results\godot-tests.json")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "project.godot") -PathType Leaf)) {
    throw "Godot project not found: $ProjectPath"
}

$tests = Get-ChildItem -LiteralPath (Join-Path $ProjectPath "tests") -Filter "test_*.gd" |
    Sort-Object Name
$results = @()
$failed = 0
$started = Get-Date

foreach ($test in $tests) {
    Write-Output ("::RUN::" + $test.Name)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = @(& $GodotPath --headless --path $ProjectPath --script $test.FullName 2>&1)
    $exitCode = $LASTEXITCODE
    $watch.Stop()
    $output = $lines -join "`n"
    $hasPassMarker = $output -match "(?i)tests? passed"
    $hasScriptError = $output -match "(?i)SCRIPT ERROR|Parse Error"
    $passed = $exitCode -eq 0 -and $hasPassMarker -and -not $hasScriptError
    if (-not $passed) {
        $failed += 1
        $lines | ForEach-Object { Write-Output $_ }
    }
    $statusPrefix = if ($passed) { "::PASS::" } else { "::FAIL::" }
    Write-Output ($statusPrefix + $test.Name)
    $results += [ordered]@{
        test = $test.Name
        passed = $passed
        exit_code = $exitCode
        duration_ms = [Math]::Round($watch.Elapsed.TotalMilliseconds, 3)
        output = if ($passed) { "" } else { $output }
    }
}

$reportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$report = [ordered]@{
    format = "worldir-godot-test-report-v1"
    godot_path = $GodotPath
    project_path = $ProjectPath
    started_at = $started.ToString("o")
    duration_ms = [Math]::Round(((Get-Date) - $started).TotalMilliseconds, 3)
    total = $tests.Count
    failed = $failed
    results = $results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output ("::SUMMARY::TOTAL=" + $tests.Count + ";FAILED=" + $failed + ";REPORT=" + $ReportPath)
if ($failed -gt 0) {
    exit 1
}
