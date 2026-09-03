import Foundation
import HELUTRadio

/// Thin CLI for the radio C ABI — works without GNU Radio installed.
@main
enum HelutRadioMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("-h") || args.contains("--help") || args.isEmpty {
            printUsage()
            exit(args.isEmpty ? 2 : 0)
        }

        if args.first == "--selftest" {
            let netlist = args.dropFirst().first ?? defaultRegexNetlist()
            let mode = flagValue("--mode", in: args) ?? "clear"
            runSelftest(netlist: netlist, mode: mode)
            return
        }

        if args.first == "--feed" {
            let netlist = flagValue("--netlist", in: args) ?? defaultRegexNetlist()
            let mode = flagValue("--mode", in: args) ?? "clear"
            let text = flagValue("--text", in: args) ?? "ABCDEFxyzDEF!!"
            runFeed(netlist: netlist, mode: mode, text: text)
            return
        }

        fputs("helut-radio: unknown command\n", stderr)
        printUsage()
        exit(2)
    }

    static func printUsage() {
        print(
            """
            helut-radio — HELUT netlist C ABI smoke tool (GNU Radio optional)

              helut-radio --selftest [regex_netlist.json] [--mode clear|encrypted-demo]
              helut-radio --feed --netlist PATH [--mode clear] [--text STRING]

            Builds libHELUTRadio.dylib for Apps/gr-helut. Install GNU Radio separately,
            then see Apps/gr-helut/README.md.
            """
        )
    }

    static func defaultRegexNetlist() -> String {
        let name = "regex_netlist.json"
        let cwd = FileManager.default.currentDirectoryPath
        for relative in [name, "../\(name)", "../../\(name)"] {
            let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        fatalError("\(name) not found; pass an explicit path")
    }

    static func flagValue(_ name: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        let value = args[idx + 1]
        return value.hasPrefix("--") ? nil : value
    }

    static func runSelftest(netlist: String, mode: String) {
        var err = [CChar](repeating: 0, count: 512)
        guard let raw = helut_open(netlist, mode, &err, err.count) else {
            let msg = String(cString: err)
            fputs("helut_open failed: \(msg)\n", stderr)
            exit(1)
        }
        defer { helut_close(raw) }

        let module = String(cString: helut_module_name(raw)!)
        let modeName = String(cString: helut_mode(raw)!)
        print("HELUT radio selftest")
        print("  netlist: \(netlist)")
        print("  module:  \(module)")
        print("  mode:    \(modeName)")
        print("  inputs:  \(helut_input_port_count(raw)) ports / \(helut_input_bit_count(raw)) bits")
        print("  outputs: \(helut_output_port_count(raw)) ports / \(helut_output_bit_count(raw)) bits")

        let probe = "XXDEFYYDEFZZ"
        var hits: [Int] = []
        for (i, byte) in probe.utf8.enumerated() {
            var match: UInt8 = 0
            let rc = helut_regex_feed(raw, byte, &match)
            if rc != 0 {
                fputs("helut_regex_feed failed rc=\(rc) at i=\(i)\n", stderr)
                exit(1)
            }
            if match != 0 { hits.append(i) }
        }
        // "DEF" completes at indices 4 and 9 in "XXDEFYYDEFZZ"
        let expected = [4, 9]
        if hits != expected {
            fputs("FAIL: hits=\(hits) expected=\(expected)\n", stderr)
            exit(1)
        }
        print("  feed \"\(probe)\" → hits at \(hits)  PASS")
        print("OK")
    }

    static func runFeed(netlist: String, mode: String, text: String) {
        var err = [CChar](repeating: 0, count: 512)
        guard let raw = helut_open(netlist, mode, &err, err.count) else {
            fputs("helut_open failed: \(String(cString: err))\n", stderr)
            exit(1)
        }
        defer { helut_close(raw) }

        for (i, byte) in text.utf8.enumerated() {
            var match: UInt8 = 0
            let rc = helut_regex_feed(raw, byte, &match)
            if rc != 0 {
                fputs("tick failed rc=\(rc)\n", stderr)
                exit(1)
            }
            let mark = match != 0 ? " ★ MATCH" : ""
            let ch = byte >= 32 && byte < 127 ? String(UnicodeScalar(byte)) : String(format: "\\x%02x", byte)
            print(String(format: "%4d  '%@'%@", i, ch, mark))
        }
    }
}
