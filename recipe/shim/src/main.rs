// Copyright 2022 conda-forge contributors
// Licensed under the BSD 3-clause license

use std::{
    env::args_os,
    ffi::OsStr,
    os::unix::{ffi::OsStrExt, process::CommandExt},
    path::PathBuf,
    process::{exit, Command},
};

// This file contains the prefix at the time that the cross-python package is
// built, with a NUL terminating byte. We need to include it this way (rather
// than just using `env!`) in order to get the binary prefix rewriting to work
// on macOS.
//
// Note that this package should be installed into $BUILD_PREFIX when helping to
// build other packages, so that's what this variable will work out to at
// runtime.
const PREFIX_BINARY: &'static [u8] = include_bytes!("prefix.bin");

fn main() {
    // We have to figure out how long PREFIX_BINARY "really" is at runtime,
    // since the length might change with the prefix-rewriting and MacOS gets
    // mad about NUL bytes in our path if we overshoot. My brain must be melting
    // but I can't a nice terse way to find the index of the first matching byte
    // in a &[u8] slice? So let's find it clumsily.

    let mut end = 0;

    for b in PREFIX_BINARY {
        if *b == 0 {
            break;
        }

        end += 1;
    }

    let p: PathBuf = OsStr::from_bytes(&PREFIX_BINARY[..end]).into();

    // The interpreter path for the wrapper script is nominally
    // `$PREFIX/venv/build/bin/python`, which is set up as as symlink to the
    // $PREFIX Python binary. The activation script will ensure that that path
    // continues to work even as it replaces `$PREFIX/bin/python` with this program.
    let exe = {
        let mut p = p.clone();
        p.push("venv");
        p.push("build");
        p.push("bin");
        p.push("python");
        p
    };

    // In the default crossenv output, the Python wrapper script is placed in
    // `venv/cross/bin/python`. However, the conda-forge activation script
    // deletes the whole `venv/cross` tree. We have it copy the script to
    // `$PREFIX/bin/_cross_python_wrapper.py`.
    let script = {
        let mut p = p.clone();
        p.push("bin");
        p.push("_cross_python_wrapper.py");
        p
    };

    let mut args = args_os();
    let argv0 = args.next().unwrap().to_string_lossy().into_owned();

    // If the script doesn't exist, Python will flag an error, but it doesn't
    // know anything about the crossenv context, so we can give a more helpful
    // error message here.
    if !script.exists() {
        eprintln!(
            "{}: fatal cross-python shim error: delegate script `{}` not found",
            argv0,
            script.display()
        );
        exit(1);
    }

    let mut cmd = Command::new(&exe);
    cmd.arg("-I"); // this flag is in the wrapper shebang line
    cmd.arg(&script);
    cmd.args(args);

    // If the program continues from this point, there was an error exec'ing.
    let err = cmd.exec();

    eprintln!(
        "{}: fatal cross-python shim error: failed to exec cross-python script: {}",
        argv0, err
    );
    eprint!(
        "{}: the command was: '{}' '-I' '{}'",
        argv0,
        exe.display(),
        script.display()
    );

    let mut args = args_os();
    args.next();

    for arg in args {
        eprint!(" '{}'", arg.to_string_lossy());
    }

    eprintln!();
    exit(1);
}
