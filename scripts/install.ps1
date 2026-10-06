# Create .venv, download luar_mud.onnx, and install numpy, tokenizers, waitress,
# and one ONNX Runtime build.
# NVIDIA (nvidia-smi) -> onnxruntime-gpu. AMD/Radeon -> onnxruntime-migraphx.
# Anything else, or a MIGraphX wheel this platform cannot install, -> CPU onnxruntime.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

function Open-PythonHome {
    Write-Host "Python 3.11 or newer was not found. Opening https://www.python.org/downloads/"
    Start-Process "https://www.python.org/downloads/"
    exit 1
}

function Test-PythonVersion {
    param(
        [string]$Exe,
        [string[]]$Extra
    )
    & $Exe @Extra -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)"
    return $LASTEXITCODE -eq 0
}

function Find-Python {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py -and $py.Source -notlike "*\WindowsApps\*") {
        if (Test-PythonVersion -Exe $py.Source -Extra @("-3")) {
            return @{ Exe = $py.Source; Extra = @("-3") }
        }
    }
    $dirs = @($env:PATH -split ";" | Where-Object { $_ -and $_ -notlike "*\WindowsApps*" })
    foreach ($name in @("python3", "python")) {
        foreach ($dir in $dirs) {
            foreach ($file in @("$name.exe", $name)) {
                $candidate = Join-Path $dir $file
                if (-not (Test-Path -LiteralPath $candidate)) { continue }
                if (Test-PythonVersion -Exe $candidate -Extra @()) {
                    return @{ Exe = $candidate; Extra = @() }
                }
            }
        }
    }
    return $null
}

function Test-Nvidia {
    $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    & $cmd.Source -L 1>$null 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-Amd {
    $rows = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $text = "$($row.Name) $($row.AdapterCompatibility)"
        if ($text -match "AMD|Radeon|Advanced Micro Devices") { return $true }
    }
    return $false
}

$python = Find-Python
if (-not $python) { Open-PythonHome }

$venvPy = Join-Path $Root ".venv\Scripts\python.exe"
& $python.Exe @($python.Extra) -m venv (Join-Path $Root ".venv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Test-Path -LiteralPath $venvPy)) {
    Write-Host "venv was not created at $venvPy"
    exit 1
}

& $venvPy -m pip install -U pip
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $venvPy -m pip install "numpy==2.5.3" "tokenizers==0.23.2" "waitress==3.0.2"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Nvidia) {
    $ort = "onnxruntime-gpu==1.30.0"
    Write-Host "NVIDIA GPU detected; installing $ort"
} elseif (Test-Amd) {
    $ort = "onnxruntime-migraphx==1.27.1"
    Write-Host "AMD GPU detected; installing $ort"
} else {
    $ort = "onnxruntime==1.30.0"
    Write-Host "No compatible GPU detected; installing $ort"
}

& $venvPy -m pip install $ort
if ($LASTEXITCODE -ne 0) {
    if ($ort -like "onnxruntime-migraphx*") {
        Write-Host "onnxruntime-migraphx is not available for this platform; installing CPU onnxruntime."
        & $venvPy -m pip install "onnxruntime==1.30.0"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } else {
        exit $LASTEXITCODE
    }
}

$ModelUrl = "http://tools-static.wmflabs.org/gonefishing/luar_mud.onnx"
$Model = Join-Path $Root "luar_mud.onnx"
if (-not (Test-Path -LiteralPath $Model) -or (Get-Item -LiteralPath $Model).Length -eq 0) {
    Write-Host "Downloading luar_mud.onnx"
    $partial = "$Model.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    & curl.exe -fL --retry 3 -o $partial $ModelUrl
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        exit $LASTEXITCODE
    }
    Move-Item -LiteralPath $partial -Destination $Model -Force
}

Write-Host "Installed into $Root\.venv"
