# T4: the target compiler, given the include dir the activation hands to
# setuptools, emits ARM64 objects. Compile only: linking needs the target
# python's import library, which the win-64 test env does not have.
# usage: python check_compiler.py <source.c>
import configparser
import os
import struct
import subprocess
import sys
import tempfile

IMAGE_FILE_MACHINE_ARM64 = 0xAA64

cfg = configparser.ConfigParser()
assert cfg.read(os.environ["DIST_EXTRA_CONFIG"]), os.environ["DIST_EXTRA_CONFIG"]
include_dir = cfg["build_ext"]["include_dirs"]

with tempfile.TemporaryDirectory() as tmp:
    obj = os.path.join(tmp, "smoke.obj")
    subprocess.run(
        ["cl", "/nologo", "/c", f"/I{include_dir}", sys.argv[1], f"/Fo{obj}"],
        check=True,
    )
    with open(obj, "rb") as f:
        head = f.read(8)

sig1, sig2 = struct.unpack_from("<HH", head)
if sig1 == 0 and sig2 == 0xFFFF:
    # anonymous (/bigobj) object header: Machine follows the Version field
    (machine,) = struct.unpack_from("<H", head, 6)
else:
    machine = sig1
print(f"{sys.argv[1]}: machine 0x{machine:04X}")
assert machine == IMAGE_FILE_MACHINE_ARM64, "not an ARM64 object"
