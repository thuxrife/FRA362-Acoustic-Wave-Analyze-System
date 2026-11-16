# ==============================================================================
# Setup Virtual Environment (.venv) for Windows (PowerShell)
# FRA362 - Acoustic Wave Analysis & Machine Learning System
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "=== [1/5] Checking Python Installation ===" -ForegroundColor Cyan
try {
    $pyVersion = python --version
    Write-Host "Found: $pyVersion"
} catch {
    Write-Host "[ERROR] Python was not found in PATH." -ForegroundColor Red
    Write-Host "Please install Python 3 and ensure 'Add Python to PATH' is checked."
    Exit 1
}

Write-Host "`n=== [2/5] Creating Virtual Environment (.venv) ===" -ForegroundColor Cyan
if (-not (Test-Path ".venv")) {
    python -m venv .venv
    Write-Host "Created virtual environment in .venv\"
} else {
    Write-Host "Virtual environment .venv\ already exists."
}

Write-Host "`n=== [3/5] Activating Virtual Environment ===" -ForegroundColor Cyan
& .\.venv\Scripts\Activate.ps1

Write-Host "`n=== [4/5] Upgrading pip & Installing Dependencies ===" -ForegroundColor Cyan
python -m pip install --upgrade pip
pip install -r requirements.txt

Write-Host "`n=== [5/5] Registering Jupyter Kernel ===" -ForegroundColor Cyan
python -m ipykernel install --user --name=acoustic-ml --display-name="Python 3 (.venv)"

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host " Setup Complete! To activate in PowerShell, run:" -ForegroundColor Green
Write-Host "   .\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host " To launch the Jupyter Notebook:" -ForegroundColor Green
Write-Host "   jupyter notebook acoustic_blockage_ml_pipeline.ipynb" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Green
