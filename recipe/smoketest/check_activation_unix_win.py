# Unix build machine, Windows target: run by the build python.
# usage: python check_activation_unix_win.py activated|deactivated
import os
import pathlib
import struct
import subprocess
import sys
import sysconfig
import tempfile

IMAGE_FILE_MACHINE_AMD64 = 0x8664
PROBE_C = "#include <windows.h>\nint probe(void) { return (int)sizeof(UINT_PTR); }\n"
OWN_VARS = (
    "CROSS_PYTHON_PLATFORM",
    "CROSS_PYTHON_EXT_SUFFIX",
    "SETUPTOOLS_EXT_SUFFIX",
    "DIST_EXTRA_CONFIG",
    "PIP_PREFIX",
    "PYO3_CROSS_LIB_DIR",
    "PYO3_CROSS_PYTHON_VERSION",
    "PYO3_CROSS_PYTHON_IMPLEMENTATION",
)


def check(name, got, want):
    print(f"{name}: {got!r}")
    assert got == want, f"{name}: expected {want!r}"


def check_deactivated():
    left = [v for v in OWN_VARS if v in os.environ]
    assert not left, f"still set after deactivation: {left}"
    assert "-fuse-ld=lld" not in os.environ.get("LDFLAGS", ""), os.environ.get("LDFLAGS")
    assert "cross-python" not in os.environ.get("PYTHONPATH", ""), os.environ.get("PYTHONPATH")
    print("deactivation OK")


def check_activated():
    thread = "t" if sysconfig.get_config_var("Py_GIL_DISABLED") else ""
    ext_suffix = f".cp{sys.version_info[0]}{sys.version_info[1]}{thread}-win_amd64.pyd"
    prefix = os.environ["PREFIX"]

    check("PYTHON", os.environ["PYTHON"], os.path.join(os.environ["BUILD_PREFIX"], "bin", "python"))
    check("PIP_PREFIX", os.environ["PIP_PREFIX"], prefix)
    check("PYO3_CROSS_LIB_DIR", os.environ["PYO3_CROSS_LIB_DIR"], os.path.join(prefix, "libs"))
    check("SETUPTOOLS_EXT_SUFFIX", os.environ["SETUPTOOLS_EXT_SUFFIX"], ext_suffix)
    assert "-fuse-ld=lld" in os.environ["LDFLAGS"], os.environ["LDFLAGS"]

    # the VFS overlay (created by activate-winsdk.sh) must reach CFLAGS
    winsdk = os.environ.get("CONDA_BUILD_WINSDK")
    if winsdk:
        act = pathlib.Path(os.environ["BUILD_PREFIX"], "etc", "conda", "activate.d", "activate-winsdk.sh")
        version = next(line.split("=", 1)[1].strip() for line in act.read_text().splitlines() if line.startswith("WINSDK_VERSION="))
        if pathlib.Path(winsdk, f"winsdk-{version}", "winsdk_vfs_overlay.yaml").is_file():
            assert "-ivfsoverlay" in os.environ["CFLAGS"], os.environ["CFLAGS"]

    check("sysconfig.get_platform", sysconfig.get_platform(), "win-amd64")
    assert sysconfig.get_config_var("EXT_SUFFIX").endswith("win_amd64.pyd"), sysconfig.get_config_var("EXT_SUFFIX")
    check("EXT_SUFFIX", sysconfig.get_config_var("EXT_SUFFIX"), ext_suffix)
    check("CCSHARED", sysconfig.get_config_var("CCSHARED"), "")
    check("include", sysconfig.get_path("include"), os.path.join(prefix, "include"))
    check("platinclude", sysconfig.get_paths()["platinclude"], os.path.join(prefix, "include"))

    check("preferred prefix scheme", sysconfig.get_preferred_scheme("prefix"), "nt")
    purelib = sysconfig.get_path("purelib", "nt", vars={"base": prefix})
    assert purelib == os.path.join(prefix, "Lib", "site-packages"), purelib

    from packaging import tags

    first = next(iter(tags.sys_tags()))
    print(f"packaging first tag: {first}")
    check("packaging platform", first.platform, "win_amd64")

    # the clang_win-64 compiler emits x86-64 COFF objects; windows.h also
    # needs the SDK headers to be complete (shared/basetsd.h)
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp, "probe.c")
        obj = pathlib.Path(tmp, "probe.obj")
        src.write_text(PROBE_C)
        # CFLAGS carries -fms-runtime-lib=dll and the SDK VFS overlay
        cmd = [*os.environ["CC"].split(), *os.environ.get("CFLAGS", "").split(), "-c", str(src), "-o", str(obj)]
        subprocess.run(cmd, check=True)
        (machine,) = struct.unpack_from("<H", obj.read_bytes(), 0)
    print(f"probe.obj: machine 0x{machine:04X}")
    assert machine == IMAGE_FILE_MACHINE_AMD64, "not an x86-64 object"
    print("activation OK")


{"activated": check_activated, "deactivated": check_deactivated}[sys.argv[1]]()
