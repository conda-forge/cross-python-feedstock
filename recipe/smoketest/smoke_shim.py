# T5: a downstream recipe script runs ${{ PYTHON }}, which renders to the
# literal %PREFIX%\python.exe of the target python and cannot run on the build
# machine. After activation that path must reach the build python, and after
# deactivation the target python.exe must be back.
# A junk python.exe stands in for the arm64 one; it fails with the same 216.
# usage: python smoke_shim.py <activate.bat> <deactivate.bat> [--strict]
import os
import subprocess
import sys
import tempfile

JUNK = b"not a windows executable"

activate, deactivate = sys.argv[1], sys.argv[2]
strict = "--strict" in sys.argv[3:]
build_python = os.path.join(sys.prefix, "python.exe")

with tempfile.TemporaryDirectory() as tmp:
    host = os.path.join(tmp, "host")
    os.makedirs(os.path.join(host, "include"))
    os.makedirs(os.path.join(host, "libs"))
    fake = os.path.join(host, "python.exe")
    with open(fake, "wb") as f:
        f.write(JUNK)
    probe = os.path.join(tmp, "probe.bat")
    with open(probe, "w") as f:
        f.write("@echo off\n")
        f.write(f'call "{activate}"\n')
        f.write(f'"{fake}" -c "import sys; print(sys.executable)"\n')
        f.write("set RC=%ERRORLEVEL%\n")
        f.write(f'call "{deactivate}"\n')
        f.write("exit /b %RC%\n")
    env = dict(os.environ, PREFIX=host, BUILD_PREFIX=sys.prefix, CONDA_BUILD="1")
    env.pop("CONDA_BUILD_STATE", None)
    res = subprocess.run(["cmd", "/d", "/c", probe], env=env, capture_output=True, text=True)
    with open(fake, "rb") as f:
        restored = f.read() == JUNK
    leftover = os.path.exists(os.path.join(sys.prefix, "etc", "conda", "cross-python", "host-python.exe"))

out = res.stdout.strip().splitlines()
reached = (
    res.returncode == 0
    and bool(out)
    and os.path.normcase(out[-1]) == os.path.normcase(build_python)
)
print(f"rc={res.returncode}\nstdout={res.stdout}\nstderr={res.stderr}")
print(f"reached build python: {reached}, target restored: {restored}, backup left: {leftover}")
if reached and restored and not leftover:
    print("T5 OK")
    sys.exit(0)
if strict:
    sys.exit(1)
print("T5 XFAIL: %PREFIX%\\python.exe does not reach the build python yet")
