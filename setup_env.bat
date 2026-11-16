@echo off
REM ==============================================================================
REM Setup Virtual Environment (.venv) for Windows (Command Prompt)
REM FRA362 - Acoustic Wave Analysis & Machine Learning System
REM ==============================================================================

echo === [1/5] Checking Python Installation ===
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not found in PATH.
    echo Please install Python 3 from https://www.python.org/ and check "Add Python to PATH".
    pause
    exit /b 1
)

python --version

echo.
echo === [2/5] Creating Virtual Environment (.venv) ===
if not exist ".venv" (
    python -m venv .venv
    echo Created virtual environment in .venv\
) else (
    echo Virtual environment .venv\ already exists.
)

echo.
echo === [3/5] Activating Virtual Environment ===
call .venv\Scripts\activate.bat

echo.
echo === [4/5] Upgrading pip and Installing Dependencies ===
python -m pip install --upgrade pip
pip install -r requirements.txt

echo.
echo === [5/5] Registering Jupyter Kernel ===
python -m ipykernel install --user --name=acoustic-ml --display-name="Python 3 (.venv)"

echo.
echo ==============================================================================
echo  Setup Complete! To activate your environment in cmd, run:
echo    .venv\Scripts\activate.bat
echo.
echo  To launch the Jupyter Notebook:
echo    jupyter notebook acoustic_blockage_ml_pipeline.ipynb
echo ==============================================================================
pause
