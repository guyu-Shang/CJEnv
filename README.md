# CJEnv

CJEnv 0.1.0 is a read-only Windows CLI written in Cangjie to explain the current Cangjie development environment.

## What is CJEnv?

CJEnv checks the selected Cangjie SDK, the PATH inherited by the current terminal, CJC and CJPM startup, and Runtime files and search-path evidence. It helps explain cases where SDK files exist but commands are not found, or commands are found but cannot start. The official SDK already provides environment setup scripts; CJEnv does not replace them.

CJEnv does not modify PATH or environment variables, run `envsetup` automatically, repair the SDK, or install or switch SDKs.

## Supported environment

- CJEnv: 0.1.0
- Windows x64
- Cangjie SDK 1.0.5 and CJPM 1.0.5

Other platforms and SDK versions have not been validated.

## Build from source

Install Cangjie SDK 1.0.5, then load its official environment in the terminal used to build CJEnv:

```cmd
call "C:\path\to\cangjie\envsetup.bat"
cjpm build -o cjenv
```

In PowerShell, load the PowerShell script instead:

```powershell
. "C:\path\to\cangjie\envsetup.ps1"
cjpm build -o cjenv
```

The build produces `target\release\bin\cjenv.exe`. The runnable release directory includes that EXE, `libcangjie-runtime.dll`, and `libboundscheck.dll` together; see the bundled third-party notices and license texts.

## Run the Windows package

Extract the versioned directory and keep both DLLs beside `cjenv.exe`. In CMD opened in that directory, run `cjenv.exe` or `cjenv.exe doctor`. In PowerShell, use `.\cjenv.exe` or `.\cjenv.exe doctor`. The bundled EXE starts without loading the SDK environment first; doctor then reports the state of the terminal in which you ran it.

## Usage

```text
cjenv
cjenv doctor
cjenv doctor --sdk "C:\path\to\cangjie"
cjenv --help
cjenv --version
```

`cjenv` is equivalent to `cjenv doctor`. When no `--sdk` is supplied, CJEnv uses `CANGJIE_HOME`, then infers an SDK from the first CJC and CJPM executables in its current PATH. If those executables imply different SDK roots, specify one with `--sdk`.

Doctor checks the SDK location and critical files, CJC/CJPM PATH resolution and startup, Runtime DLL files, and whether the selected Runtime directory is in PATH. `OK` means a check passed. `WARN` marks a configuration difference or incomplete evidence and does not necessarily mean the environment is unusable. `ERROR` means a check actually failed.

For example, with CJC and CJPM on PATH but the SDK Runtime directory absent, an observed result included:

```text
OK    PATH CJC    resolved to <SDK>\bin\cjc.exe
OK    PATH CJPM    resolved to <SDK>\tools\bin\cjpm.exe
WARN    Runtime    target Runtime directory is not present in current PATH: <SDK>\runtime\lib\windows_x86_64_cjnative
OK    CJC    cjc started successfully; Cangjie Compiler: 1.0.5 (cjnative)
ERROR    CJPM    cjpm failed to start with STATUS_DLL_NOT_FOUND (0xC0000135; exit code 3221225781)
```

The paths above are abbreviated; the actual output shows full paths. The status identifies a DLL loading failure but does not identify which DLL Windows could not load.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Checks completed without an `ERROR` |
| 1 | Checks completed with at least one `ERROR` |
| 2 | Invalid arguments or CJEnv could not complete diagnosis |

## Known limitations

CJEnv 0.1.0 is validated only on Windows with Cangjie SDK 1.0.5. CJC/CJPM startup probes do not enforce a timeout. Doctor does not verify compilation, linking, or generated program execution. DLL diagnosis uses observed files, PATH, and process status; it does not trace the Windows loader.

## Development verification

Run the seven core checks with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Sdk "C:\path\to\cangjie"
```

## License

CJEnv is licensed under Apache License 2.0; see `LICENSE`. The Cangjie Runtime DLLs in the Windows package are third-party components with separate materials in `THIRD_PARTY_NOTICES.txt` and `licenses/`.
