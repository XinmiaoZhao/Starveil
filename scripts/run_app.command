#!/bin/zsh
set -e

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PYTHONPATH="$PROJECT_DIR/src"
export PYTHONPATH

if [ -x "$PROJECT_DIR/.conda/bin/python" ]; then
  exec "$PROJECT_DIR/.conda/bin/python" -m mysequator.ui.app
fi

CONDA_EXE="${CONDA_EXE:-/opt/homebrew/bin/conda}"
if [ -x "$CONDA_EXE" ]; then
  exec "$CONDA_EXE" run -p "$PROJECT_DIR/.conda" python -m mysequator.ui.app
fi

exec /usr/bin/python3 -m mysequator.ui.app

