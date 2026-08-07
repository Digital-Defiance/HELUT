import Foundation
import HELUTCLI
import HELUTToolKit

/// Umbrella dispatcher — prefers domain binaries' entry points in-process.
let args = CommandLine.arguments

if HelutE256CLI.handles(args) {
    HelutE256CLI.run()
}

if HelutBenchCLI.handles(args) {
    HelutBenchCLI.run()
}

if HelutCompileCLI.handles(args) {
    HelutCompileCLI.run()
}

if HelutBombeCLI.handles(args) {
    HelutBombeCLI.run()
}

fputs(
    """
    helut — HELUT umbrella CLI (shim)

      helut-bench      FHE SING / micro / noisy-BK / hardness
      helut-e256       Enigma256 SoftBus tools
      helut-bombe      Welchman / hybrid / campaign / Metal demo
      helut-compile    Netlist validate / compile helpers

    Pass the same flags as before to `helut`; domain tools are preferred going forward.
    See directives/packaging-roadmap.md.

    """,
    stderr
)
exit(2)
