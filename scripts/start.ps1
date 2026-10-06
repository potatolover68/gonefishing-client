# Enter the venv and start the encoder in a hidden background process.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
$PidFile = Join-Path $LogDir "server.pid"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (Test-Path -LiteralPath $PidFile) {
    $old = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($old -match '^\d+$') {
        $running = Get-CimInstance Win32_Process -Filter "ProcessId=$old" -ErrorAction SilentlyContinue
        if ($running -and $running.CommandLine -like "*server.py*") {
            Write-Host "server already running (pid $old)"
            exit 0
        }
    }
}

$pythonw = Join-Path $Root ".venv\Scripts\pythonw.exe"
$python = Join-Path $Root ".venv\Scripts\python.exe"
if (Test-Path -LiteralPath $pythonw) {
    $exe = $pythonw
} elseif (Test-Path -LiteralPath $python) {
    $exe = $python
} else {
    Write-Host "venv missing; run scripts\install.ps1"
    exit 1
}

$server = Join-Path $Root "server.py"
$proc = Start-Process -FilePath $exe -ArgumentList @("-u", $server) -WorkingDirectory $Root -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $PidFile -Value $proc.Id -Encoding ascii
Write-Host "started server pid $($proc.Id)"
