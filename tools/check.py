"""Run the campaign oracle and actual Godot tests. Pass --visual for rendered QA."""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--visual", action="store_true")
args = parser.parse_args()
godot = shutil.which("godot") or shutil.which("godot4")
if not godot:
    raise SystemExit("Godot 4.6 is required.")


def run(command, marker=None):
    result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=120)
    output = result.stdout
    if marker or result.returncode or "ERROR:" in output:
        print(output.strip())
    if result.returncode or "ERROR:" in output or (marker and marker not in output):
        raise SystemExit(1)


run([sys.executable, "tools/verify_levels.py"], "X04 Switchyard")
run([godot, "--headless", "--editor", "--import", "--path", "."])
run([godot, "--headless", "--path", ".", "--script", "tests/test_rules.gd"], "0 failures.")
ui_args = ([godot] if args.visual else [godot, "--headless"]) + [
    "--path", ".", "--script", "tests/test_ui.gd"]
if args.visual:
    ui_args += ["--", "--capture"]
run(ui_args, "0 failures.")
run([godot, "--headless", "--path", ".", "--script", "tests/test_guides.gd"], "0 failures.")
run([godot, "--headless", "--path", ".", "--script", "tests/test_chapters.gd"], "0 failures.")
print("All ECHO checks passed.")
