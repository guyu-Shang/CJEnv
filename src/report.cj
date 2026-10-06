package cjenv

enum CheckLevel {
    OK | WARN | ERROR
}

class CheckResult {
    let level: CheckLevel
    let checkName: String
    let message: String

    init(level: CheckLevel, checkName: String, message: String) {
        this.level = level
        this.checkName = checkName
        this.message = message
    }
}

func showCheck(result: CheckResult): Unit {
    println("${levelLabel(result.level)}    ${result.checkName}    ${result.message}")
}

func levelLabel(level: CheckLevel): String {
    return match (level) {
        case CheckLevel.OK => "OK"
        case CheckLevel.WARN => "WARN"
        case CheckLevel.ERROR => "ERROR"
    }
}

func worseLevel(left: CheckLevel, right: CheckLevel): CheckLevel {
    return match (left) {
        case CheckLevel.ERROR => CheckLevel.ERROR
        case CheckLevel.WARN =>
            match (right) {
                case CheckLevel.ERROR => CheckLevel.ERROR
                case _ => CheckLevel.WARN
            }
        case CheckLevel.OK => right
    }
}

func isWarning(level: CheckLevel): Bool {
    return match (level) {
        case CheckLevel.WARN => true
        case _ => false
    }
}

func showSummary(sdk: CheckLevel, path: CheckLevel, cjc: CheckLevel,
    cjpm: CheckLevel, runtime: CheckLevel): Unit {
    println("Summary:")
    println("  SDK:       ${levelLabel(sdk)}")
    println("  PATH:      ${levelLabel(path)}")
    println("  CJC:       ${levelLabel(cjc)}")
    println("  CJPM:      ${levelLabel(cjpm)}")
    println("  Runtime:   ${levelLabel(runtime)}")
    if (isError(sdk) || isError(path) || isError(cjc) || isError(cjpm) || isError(runtime)) {
        println("Basic environment checks found errors. See the results above.")
    } else {
        println("Basic environment checks passed. Compilation, linking, and generated program execution were not verified.")
    }
    if (isWarning(sdk) || isWarning(path) || isWarning(cjc) || isWarning(cjpm) || isWarning(runtime)) {
        println("Warnings indicate configuration differences or incomplete evidence, not necessarily a broken environment.")
    }
}

func isError(level: CheckLevel): Bool {
    return match (level) {
        case CheckLevel.ERROR => true
        case _ => false
    }
}
