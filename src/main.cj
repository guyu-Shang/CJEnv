package cjenv

let CJENV_VERSION: String = "0.1.0"

func showHelp(): Unit {
    println("CJEnv ${CJENV_VERSION}")
    println("Usage:")
    println("  cjenv")
    println("  cjenv doctor")
    println("  cjenv doctor --sdk <path>")
    println("  cjenv --help")
    println("  cjenv --version")
    println("Description:")
    println("  Diagnose the current Cangjie SDK and toolchain environment.")
    println("Options:")
    println("  --sdk <path>     Check the specified Cangjie SDK")
    println("  -h, --help       Show help")
    println("  -v, --version    Show version")
    println("Scope: Windows / Cangjie 1.0.5")
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return runDoctor(None)
    }
    if (args.size == 1) {
        if (args[0] == "doctor") {
            return runDoctor(None)
        }
        if (args[0] == "--help" || args[0] == "-h") {
            showHelp()
            return 0
        }
        if (args[0] == "--version" || args[0] == "-v") {
            println("CJEnv ${CJENV_VERSION}")
            return 0
        }
    }
    if (args.size == 3 && args[0] == "doctor" && args[1] == "--sdk" && !args[2].isEmpty()) {
        return runDoctor(Some(args[2]))
    }
    println("Error: invalid arguments. Try 'cjenv --help' for usage.")
    return 2
}
