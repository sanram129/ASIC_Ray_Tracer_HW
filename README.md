# ASIC_Ray_Tracer_HW

The SystemVerilog files and other hardware files for our simple DDA ray tracer. Made during the 2026 IEEE U of T ASIC hackathon.

## Demo GUI (recommended)

Run a simple browser GUI (upload 1 STL, move the light, render, view output).

See: **HOW_TO_RUN_GUI.md**

For a full end-to-end guide (GUI + CLI) with only relative paths, see: **RUN_END_TO_END.md**

### Quick start (Windows)

1) Install **Icarus Verilog 12+** and confirm:

    iverilog -V

2) Create a venv + install deps:

    python -m venv venv
    .\venv\Scripts\python.exe -m pip install -r requirements.txt

3) Launch the GUI:

    .\venv\Scripts\python.exe gui_gradio.py

It will print a local URL (usually http://127.0.0.1:7860/). Open it in your browser.

## CLI flow (no GUI)

The original two-step flow is documented in **HOW_TO_RUN.md**.
