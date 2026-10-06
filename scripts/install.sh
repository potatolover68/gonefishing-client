#!/usr/bin/env bash
# Create .venv, download luar_mud.onnx, and install numpy, tokenizers, waitress,
# and one ONNX Runtime build.
# NVIDIA (nvidia-smi) -> onnxruntime-gpu. AMD/Radeon -> onnxruntime-migraphx.
# Anything else, or a MIGraphX wheel this platform cannot install, -> CPU onnxruntime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

open_python() {
    echo "Python 3.11 or newer was not found. Opening https://www.python.org/downloads/" >&2
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "https://www.python.org/downloads/" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
        open "https://www.python.org/downloads/" || true
    elif command -v cmd.exe >/dev/null 2>&1; then
        cmd.exe /c start "" "https://www.python.org/downloads/" || true
    fi
    exit 1
}

python_ok() {
    "$1" "${@:2}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1
}

is_store_stub() {
    local path
    path="$(command -v "$1" 2>/dev/null || true)"
    [[ "$path" == *WindowsApps* ]]
}

# One argv array so an empty extra-arg list is never expanded under set -u.
if command -v py >/dev/null 2>&1 && ! is_store_stub py && python_ok py -3; then
    PY=(py -3)
elif command -v python3 >/dev/null 2>&1 && ! is_store_stub python3 && python_ok python3; then
    PY=(python3)
elif command -v python >/dev/null 2>&1 && ! is_store_stub python && python_ok python; then
    PY=(python)
else
    open_python
fi

has_amd() {
    if command -v rocm-smi >/dev/null 2>&1; then
        return 0
    fi
    if command -v lspci >/dev/null 2>&1 && lspci | grep -Eiq 'amd/ati|advanced micro devices|radeon'; then
        return 0
    fi
    return 1
}

"${PY[@]}" -m venv "$ROOT/.venv"
VENV_PY="$ROOT/.venv/bin/python"
if [[ ! -x "$VENV_PY" ]]; then
    VENV_PY="$ROOT/.venv/Scripts/python.exe"
fi
if [[ ! -x "$VENV_PY" && ! -f "$VENV_PY" ]]; then
    echo "venv was not created" >&2
    exit 1
fi

"$VENV_PY" -m pip install -U pip
"$VENV_PY" -m pip install "numpy==2.5.3" "tokenizers==0.23.2" "waitress==3.0.2"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    ORT="onnxruntime-gpu==1.30.0"
    echo "NVIDIA GPU detected; installing $ORT"
elif has_amd; then
    ORT="onnxruntime-migraphx==1.27.1"
    echo "AMD GPU detected; installing $ORT"
else
    ORT="onnxruntime==1.30.0"
    echo "No compatible GPU detected; installing $ORT"
fi

if ! "$VENV_PY" -m pip install "$ORT"; then
    if [[ "$ORT" == onnxruntime-migraphx* ]]; then
        echo "onnxruntime-migraphx is not available for this platform; installing CPU onnxruntime."
        "$VENV_PY" -m pip install "onnxruntime==1.30.0"
    else
        exit 1
    fi
fi

MODEL_URL="http://tools-static.wmflabs.org/gonefishing/luar_mud.onnx"
MODEL="$ROOT/luar_mud.onnx"
if [[ ! -s "$MODEL" ]]; then
    echo "Downloading luar_mud.onnx"
    partial="$MODEL.partial"
    rm -f "$partial"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$partial" "$MODEL_URL" || { rm -f "$partial"; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$partial" "$MODEL_URL" || { rm -f "$partial"; exit 1; }
    else
        echo "curl or wget is required to download luar_mud.onnx" >&2
        exit 1
    fi
    mv "$partial" "$MODEL"
fi

echo "Installed into $ROOT/.venv"
