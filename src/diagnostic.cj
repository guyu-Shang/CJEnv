package cjenv

import std.env.{getVariable, getWorkingDirectory}
import std.fs.{Path, FileInfo, exists}
import std.process.{executeWithOutput, ProcessException, ProcessRedirect}

// This is deliberately limited to executables found through this process's PATH.
func pathEntry(part: String): ?Path {
    let folder = part.trimAscii().removePrefix("\"").removeSuffix("\"").trimAscii()
    if (folder.isEmpty()) {
        return None
    }
    try {
        let parsed = Path(folder)
        return Some(if (parsed.isAbsolute()) {
            parsed.normalize()
        } else {
            getWorkingDirectory().join(parsed).normalize()
        })
    } catch (_: Exception) {
        return None
    }
}

func firstOnPath(name: String, search: String): ?Path {
    for (part in search.split(";")) {
        match (pathEntry(part)) {
            case Some(directory) =>
                try {
                    let candidate = directory.join(name).normalize()
                    if (exists(candidate) && FileInfo(candidate).isRegular()) {
                        return Some(candidate)
                    }
                } catch (_: Exception) {
                    // An inaccessible PATH entry does not hide later entries.
                }
            case None => ()
        }
    }
    return None
}

func runtimeOnPath(runtime: Path, search: String): Bool {
    let target = runtime.normalize().toString().toAsciiLower()
    for (part in search.split(";")) {
        match (pathEntry(part)) {
            case Some(directory) =>
                if (directory.toString().toAsciiLower() == target) {
                    return true
                }
            case None => ()
        }
    }
    return false
}

func checkPathResolution(name: String, executable: String, target: Path, search: String): CheckResult {
    return match (firstOnPath(executable, search)) {
        case None => CheckResult(CheckLevel.ERROR, "PATH ${name}", "not found in current PATH")
        case Some(found) =>
            if (found.normalize().toString().toAsciiLower() == target.normalize().toString().toAsciiLower()) {
                CheckResult(CheckLevel.OK, "PATH ${name}", "resolved to ${found}")
            } else {
                CheckResult(CheckLevel.WARN, "PATH ${name}",
                    "resolves to ${found}; target SDK executable is ${target}")
            }
    }
}

func firstOutputLine(bytes: Array<Byte>): String {
    try {
        for (line in String.fromUtf8(bytes).split("\n")) {
            let clean = line.trimAscii()
            if (!clean.isEmpty()) {
                return clean
            }
        }
    } catch (_: Exception) {
        return ""
    }
    return ""
}

func checkStartup(name: String, target: Path, argument: String): (CheckResult, ?Int64) {
    try {
        let (code, stdout, stderr) = executeWithOutput(target.toString(), [argument],
            stdIn: ProcessRedirect.Discard)
        let outLine = firstOutputLine(stdout)
        let errLine = firstOutputLine(stderr)
        if (code == 0) {
            let version = if (!outLine.isEmpty()) { outLine } else { errLine }
            let detail = if (version.isEmpty()) { "" } else { "; ${version}" }
            return (CheckResult(CheckLevel.OK, name, "${name.toAsciiLower()} started successfully${detail}"), Some(code))
        }
        // Windows 0xC0000135 / STATUS_DLL_NOT_FOUND is observed as Int64 3221225781 here.
        if (name == "CJPM" && code == 3221225781) {
            return (CheckResult(CheckLevel.ERROR, name,
                "cjpm failed to start with STATUS_DLL_NOT_FOUND (0xC0000135; exit code ${code})"), Some(code))
        }
        let detail = if (!errLine.isEmpty()) { errLine } else { outLine }
        let suffix = if (detail.isEmpty()) { "" } else { "; ${detail}" }
        return (CheckResult(CheckLevel.ERROR, name, "${name.toAsciiLower()} exited with code ${code}${suffix}"), Some(code))
    } catch (e: ProcessException) {
        return (CheckResult(CheckLevel.ERROR, name, "unable to start ${name.toAsciiLower()}: ${e.message}"), None)
    } catch (e: Exception) {
        return (CheckResult(CheckLevel.ERROR, name, "startup check failed for ${name.toAsciiLower()}: ${e.message}"), None)
    }
}

func checkFile(name: String, path: Path): CheckResult {
    try {
        if (!exists(path)) {
            return CheckResult(CheckLevel.ERROR, name, "not found: ${path}")
        }
        if (!FileInfo(path).isRegular()) {
            return CheckResult(CheckLevel.ERROR, name, "not a regular file: ${path}")
        }
        return CheckResult(CheckLevel.OK, name, "found: ${path}")
    } catch (e: Exception) {
        return CheckResult(CheckLevel.ERROR, name, "could not inspect ${path}: ${e.message}")
    }
}

func inspectSdk(raw: String): Int64 {
    let parsed = Path(raw)
    let root = if (parsed.isAbsolute()) {
        parsed.normalize()
    } else {
        getWorkingDirectory().join(parsed).normalize()
    }

    var hasError = false
    let rootExists = exists(root) && FileInfo(root).isDirectory()
    let rootResult = if (rootExists) {
        CheckResult(CheckLevel.OK, "SDK", "directory exists: ${root}")
    } else {
        CheckResult(CheckLevel.ERROR, "SDK", "directory not found: ${root}")
    }
    showCheck(rootResult)
    if (!rootExists) {
        hasError = true
    }

    let runtime = root.join("runtime").join("lib").join("windows_x86_64_cjnative")
    let checks = [
        checkFile("CJC", root.join("bin").join("cjc.exe")),
        checkFile("CJPM", root.join("tools").join("bin").join("cjpm.exe")),
        checkFile("Runtime", runtime.join("libcangjie-runtime.dll")),
        checkFile("Runtime", runtime.join("libboundscheck.dll"))
    ]
    for (result in checks) {
        showCheck(result)
        if (isError(result.level)) {
            hasError = true
        }
    }

    let cjc = root.join("bin").join("cjc.exe")
    let cjpm = root.join("tools").join("bin").join("cjpm.exe")
    let search = match (getVariable("PATH")) {
        case Some(value) => value
        case None => ""
    }
    let cjcPathResult = checkPathResolution("CJC", "cjc.exe", cjc, search)
    let cjpmPathResult = checkPathResolution("CJPM", "cjpm.exe", cjpm, search)
    for (result in [cjcPathResult, cjpmPathResult]) {
        showCheck(result)
        if (isError(result.level)) {
            hasError = true
        }
    }
    let runtimeInPath = runtimeOnPath(runtime, search)
    let runtimePathResult = if (runtimeInPath) {
        CheckResult(CheckLevel.OK, "Runtime", "target Runtime directory is present in current PATH: ${runtime}")
    } else {
        CheckResult(CheckLevel.WARN, "Runtime", "target Runtime directory is not present in current PATH: ${runtime}")
    }
    showCheck(runtimePathResult)

    var cjcStartup = checks[0]
    if (!isError(checks[0].level)) {
        let (result, _) = checkStartup("CJC", cjc, "-v")
        cjcStartup = result
        showCheck(cjcStartup)
        if (isError(cjcStartup.level)) {
            hasError = true
        }
    }
    var cjpmStartup = checks[1]
    var cjpmExit: ?Int64 = None
    if (!isError(checks[1].level)) {
        let (result, code) = checkStartup("CJPM", cjpm, "--version")
        cjpmStartup = result
        cjpmExit = code
        showCheck(cjpmStartup)
        if (isError(cjpmStartup.level)) {
            hasError = true
        }
    }
    if (isError(cjpmStartup.level)) {
        if (cjpmExit == Some(3221225781) &&
            !isError(checks[2].level) && !isError(checks[3].level) && !runtimeInPath) {
            showCheck(CheckResult(CheckLevel.WARN, "Diagnosis",
                "CJPM failure is consistent with a Runtime DLL search-path problem; the missing DLL is not identified"))
        } else if (runtimeInPath && !isError(checks[1].level) &&
            !isError(checks[2].level) && !isError(checks[3].level)) {
            showCheck(CheckResult(CheckLevel.WARN, "Diagnosis",
                "current checks do not explain the CJPM startup failure"))
        }
    }
    if (rootExists && isError(checks[0].level) && isError(checks[1].level)) {
        showCheck(CheckResult(CheckLevel.ERROR, "SDK", "path does not appear to be a Cangjie SDK root"))
    }
    let sdkLevel = worseLevel(worseLevel(worseLevel(rootResult.level, checks[0].level), checks[1].level),
        worseLevel(checks[2].level, checks[3].level))
    let pathLevel = worseLevel(cjcPathResult.level, cjpmPathResult.level)
    let runtimeLevel = worseLevel(worseLevel(checks[2].level, checks[3].level), runtimePathResult.level)
    showSummary(sdkLevel, pathLevel, cjcStartup.level, cjpmStartup.level, runtimeLevel)
    return if (hasError) { 1 } else { 0 }
}

func missingSdk(): Int64 {
    showCheck(CheckResult(CheckLevel.ERROR, "SDK", "cannot determine SDK; use cjenv doctor --sdk \"<SDK directory>\""))
    return 1
}

func sdkFromCjc(executable: Path): ?Path {
    let bin = executable.parent
    if (executable.fileName.toAsciiLower() == "cjc.exe" && bin.fileName.toAsciiLower() == "bin") {
        return Some(bin.parent.normalize())
    }
    return None
}

func sdkFromCjpm(executable: Path): ?Path {
    let bin = executable.parent
    let tools = bin.parent
    if (executable.fileName.toAsciiLower() == "cjpm.exe" && bin.fileName.toAsciiLower() == "bin" &&
        tools.fileName.toAsciiLower() == "tools") {
        return Some(tools.parent.normalize())
    }
    return None
}

func pathSdkCandidate(executable: ?Path, isCjc: Bool): ?Path {
    return match (executable) {
        case Some(found) => if (isCjc) { sdkFromCjc(found) } else { sdkFromCjpm(found) }
        case None => None
    }
}

func usePathSdk(root: Path, source: String, both: Bool): Int64 {
    if (both) {
        showCheck(CheckResult(CheckLevel.OK, "SDK", "source: PATH (CJC/CJPM); inferred ${root}"))
    } else {
        showCheck(CheckResult(CheckLevel.WARN, "SDK",
            "inferred from ${source} in PATH: ${root}; the other tool did not provide a matching SDK candidate"))
    }
    return inspectSdk(root.toString())
}

func inferSdkFromPath(): Int64 {
    let search = match (getVariable("PATH")) {
        case Some(value) => value
        case None => ""
    }
    let cjc = pathSdkCandidate(firstOnPath("cjc.exe", search), true)
    let cjpm = pathSdkCandidate(firstOnPath("cjpm.exe", search), false)
    return match (cjc) {
        case Some(cjcRoot) =>
            match (cjpm) {
                case Some(cjpmRoot) =>
                    if (cjcRoot.toString().toAsciiLower() == cjpmRoot.toString().toAsciiLower()) {
                        usePathSdk(cjcRoot, "CJC/CJPM", true)
                    } else {
                        showCheck(CheckResult(CheckLevel.ERROR, "SDK",
                            "CJC and CJPM in PATH point to different SDK candidates: ${cjcRoot} and ${cjpmRoot}"))
                        println("Use cjenv doctor --sdk \"<SDK directory>\" to select one explicitly.")
                        1
                    }
                case None => usePathSdk(cjcRoot, "CJC", false)
            }
        case None =>
            match (cjpm) {
                case Some(cjpmRoot) => usePathSdk(cjpmRoot, "CJPM", false)
                case None => missingSdk()
            }
    }
}

func inspectOrMissing(raw: String): Int64 {
    return if (raw.isEmpty()) { missingSdk() } else { inspectSdk(raw) }
}

func runDoctor(sdkOverride: ?String): Int64 {
    try {
        return match (sdkOverride) {
            case Some(value) => inspectOrMissing(value)
            case None =>
                match (getVariable("CANGJIE_HOME")) {
                    case Some(value) => if (value.isEmpty()) { inferSdkFromPath() } else { inspectSdk(value) }
                    case None => inferSdkFromPath()
                }
        }
    } catch (e: Exception) {
        println("Error: diagnosis could not complete: ${e.message}")
        return 2
    }
}


