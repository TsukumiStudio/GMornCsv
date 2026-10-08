#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

addon = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="gmorn-csv-") as temporary:
    project = Path(temporary) / "project"
    target = project / "addons" / "csv_test_install"
    target.mkdir(parents=True)
    for pattern in ("*.gd", "*.uid", "*.tscn", "plugin.cfg"):
        for source in addon.glob(pattern):
            shutil.copy2(source, target / source.name)
    (project / "project.godot").write_text('config_version=5\n[editor_plugins]\nenabled=PackedStringArray("res://addons/csv_test_install/plugin.cfg")\n')
    env = dict(os.environ, HOME=temporary, XDG_DATA_HOME=temporary)
    godot = os.environ.get("GODOT_BIN", "godot")
    for arguments in (["--editor", "--quit"], ["--script", "res://addons/csv_test_install/verify.gd"]):
        result = subprocess.run([godot, "--headless", "--path", str(project), *arguments], env=env, capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output)
        if result.returncode or any(marker in output for marker in ("ERROR:", "WARNING:", "Assertion failed")):
            raise SystemExit(1)
        if "--script" in arguments and "PASS" not in output:
            raise SystemExit(1)
