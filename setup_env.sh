#!/bin/bash
# ==============================================================================
# Setup Virtual Environment (.venv) for Linux / Ubuntu
# FRA362 - Acoustic Wave Analysis & Machine Learning System
# ==============================================================================

set -e

echo "=== [1/5] Checking Python 3 Installation ==="
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python 3 is not installed. Please install it with:"
    echo "  sudo apt update && sudo apt install -y python3 python3-pip python3-venv"
    exit 1
fi

PYTHON_VERSION=$(python3 --version)
echo "Found: $PYTHON_VERSION"

echo ""
echo "=== [2/5] Creating Virtual Environment (.venv) ==="
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
    echo "Created virtual environment in .venv/"
else
    echo "Virtual environment .venv/ already exists."
fi

echo ""
echo "=== [3/5] Activating Virtual Environment ==="
# shellcheck disable=SC1091
source .venv/bin/activate

echo ""
echo "=== [4/5] Upgrading pip & Installing Dependencies ==="
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "=== [5/5] Registering Jupyter Kernel ==="
python -m ipykernel install --user --name=acoustic-ml --display-name="Python 3 (.venv)"

echo ""
echo "=============================================================================="
echo " Setup Complete! To activate your environment in terminal, run:"
echo "   source .venv/bin/activate"
echo ""
echo " To launch the Jupyter Notebook:"
echo "   jupyter notebook acoustic_blockage_ml_pipeline.ipynb"
echo "=============================================================================="
