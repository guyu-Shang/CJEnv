param(
    [Parameter(Mandatory = $true)]
    [string] $Sdk
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$passed = 0
$failed = 0
$workspace = $null

function Invoke-Child {
    param(
        [string] $FileName,
        [string] $Arguments,
        [string] $PathValue,
        [string[]] $InputLines = @()
    )
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FileName
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PATH'] = $PathValue
    $start.EnvironmentVariables.Remove('CANGJIE_HOME')
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        foreach ($line in $InputLines) { $process.StandardInput.WriteLine($line) }
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Test process exceeded 30 seconds.'
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}

function Run-Cmd {
    param([string[]] $Lines, [string] $PathValue)
    return Invoke-Child -FileName (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments '/d /q' -PathValue $PathValue -InputLines ($Lines + @('exit'))
}

function Test-Case {
    param([string] $Name, [scriptblock] $Action, [scriptblock] $Check)
    try {
        $result = & $Action
        if (& $Check $result) {
            $script:passed++
            Write-Output "[PASS] $Name"
            return
        }
        $script:failed++
        Write-Output "[FAIL] $Name (exit $($result.ExitCode))"
        if ($result.StdOut) { Write-Output $result.StdOut.TrimEnd() }
        if ($result.StdErr) { Write-Output "stderr: $($result.StdErr.TrimEnd())" }
    } catch {
        $script:failed++
        Write-Output "[FAIL] $Name : $_"
    }
}

try {
    $sdkRoot = (Resolve-Path -LiteralPath $Sdk).Path
    $required = @(
        'envsetup.ps1', 'envsetup.bat', 'bin\cjc.exe', 'tools\bin\cjpm.exe',
        'runtime\lib\windows_x86_64_cjnative\libcangjie-runtime.dll',
        'runtime\lib\windows_x86_64_cjnative\libboundscheck.dll'
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot $relative) -PathType Leaf)) {
            throw "SDK file not found: $relative"
        }
    }

    # Dot-sourcing changes this short-lived verification process only.
    . (Join-Path $sdkRoot 'envsetup.ps1')
    $cjpm = Join-Path $sdkRoot 'tools\bin\cjpm.exe'
    Push-Location $projectRoot
    try {
        & $cjpm clean
        if ($LASTEXITCODE -ne 0) { throw "cjpm clean failed: $LASTEXITCODE" }
        & $cjpm build -o cjenv
        if ($LASTEXITCODE -ne 0) { throw "cjpm build -o cjenv failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    $builtExe = Join-Path $projectRoot 'target\release\bin\cjenv.exe'
    if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
        throw "Built EXE not found: $builtExe"
    }
    $workspace = Join-Path (Join-Path $projectRoot 'verify-temp') ([guid]::NewGuid().ToString('N'))
    $portable = New-Item -ItemType Directory -Path (Join-Path $workspace 'portable') -Force
    $portableExe = Join-Path $portable.FullName 'cjenv.exe'
    Copy-Item -LiteralPath $builtExe -Destination $portableExe
    $runtime = Join-Path $sdkRoot 'runtime\lib\windows_x86_64_cjnative'
    foreach ($dll in @('libcangjie-runtime.dll', 'libboundscheck.dll')) {
        Copy-Item -LiteralPath (Join-Path $runtime $dll) -Destination (Join-Path $portable.FullName $dll)
    }

    $windowsPath = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
    $toolsPath = "$sdkRoot\bin;$sdkRoot\tools\bin;$windowsPath"
    $doctor = '"' + $portableExe + '" doctor --sdk "' + $sdkRoot + '"'
    $inferDoctor = '"' + $portableExe + '" doctor'
    $setup = 'call "' + (Join-Path $sdkRoot 'envsetup.bat') + '"'

    Test-Case 'version' {
        Invoke-Child -FileName $portableExe -Arguments '--version' -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 0 -and $r.StdOut.Contains('CJEnv 0.1.0') }

    Test-Case 'help' {
        Invoke-Child -FileName $portableExe -Arguments '--help' -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 0 -and $r.StdOut.Contains('Usage:') -and
        $r.StdOut.Contains('doctor') -and $r.StdOut.Contains('--sdk') }

    Test-Case 'invalid arguments' {
        Invoke-Child -FileName $portableExe -Arguments 'invalid-command' -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 2 -and $r.StdOut.Contains("Try 'cjenv --help'") }

    Test-Case 'unconfigured PATH with explicit SDK' {
        Run-Cmd -Lines @($doctor) -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 1 -and $r.StdOut -match 'OK\s+SDK\s+directory exists' -and
        $r.StdOut -match 'ERROR\s+PATH CJC\s+not found' -and
        $r.StdOut -match 'ERROR\s+PATH CJPM\s+not found' -and
        $r.StdOut -match 'WARN\s+Runtime\s+target Runtime directory is not present' }

    Test-Case 'tool PATH without Runtime' {
        Run-Cmd -Lines @($doctor) -PathValue $toolsPath
    } { param($r) $r.ExitCode -eq 1 -and $r.StdOut -match 'OK\s+PATH CJC\s+resolved' -and
        $r.StdOut -match 'OK\s+PATH CJPM\s+resolved' -and
        $r.StdOut -match 'WARN\s+Runtime\s+target Runtime directory is not present' -and
        $r.StdOut.Contains('STATUS_DLL_NOT_FOUND') }

    Test-Case 'official complete environment' {
        Run-Cmd -Lines @($setup, $doctor) -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 0 -and $r.StdOut -match 'Summary:' -and
        $r.StdOut -match '(?m)^\s+SDK:\s+OK\b' -and
        $r.StdOut -match '(?m)^\s+PATH:\s+OK\b' -and
        $r.StdOut -match '(?m)^\s+CJC:\s+OK\b' -and
        $r.StdOut -match '(?m)^\s+CJPM:\s+OK\b' -and
        $r.StdOut -match '(?m)^\s+Runtime:\s+OK\b' }

    Test-Case 'SDK inference from PATH' {
        Run-Cmd -Lines @($setup, 'set CANGJIE_HOME=', $inferDoctor) -PathValue $windowsPath
    } { param($r) $r.ExitCode -eq 0 -and $r.StdOut.Contains('source: PATH (CJC/CJPM)') -and
        $r.StdOut -match '(?m)^\s+SDK:\s+OK\b' }
} catch {
    $failed++
    Write-Output "[FAIL] verification setup: $_"
} finally {
    Write-Output "CJEnv validation: $passed passed, $failed failed"
    if ($failed -eq 0 -and $workspace -and (Test-Path -LiteralPath $workspace)) {
        $projectFull = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
        $workFull = [System.IO.Path]::GetFullPath($workspace)
        if (-not $workFull.StartsWith($projectFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean an unexpected path: $workFull"
        }
        Remove-Item -LiteralPath $workFull -Recurse -Force
        $tempParent = Split-Path -Parent $workFull
        if (-not (Get-ChildItem -LiteralPath $tempParent -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $tempParent -Force
        }
    } elseif ($workspace -and (Test-Path -LiteralPath $workspace)) {
        Write-Output "Failed test workspace retained: $workspace"
    }
}

if ($failed -eq 0) { exit 0 }
exit 1
