// main.swift - Oracle OS v2 CLI entry point
//
// Thin CLI:
//   oracle mcp      Start the MCP server (used by Claude Code)
//   oracle setup    Interactive setup wizard
//   oracle doctor   Diagnose issues and suggest fixes
//   oracle status   Quick health check
//   oracle version  Print version

import AppKit
import ApplicationServices
import Foundation
import OracleOS

// Force CoreGraphics server connection initialization.
// ScreenCaptureKit requires a CG connection to the window server.
_ = CGMainDisplayID()

@MainActor
func main() async {
    let args = CommandLine.arguments.dropFirst()
    let command = args.first ?? "help"

    switch command {
    case "mcp":
        let server = MCPServer()
        await server.run()

    case "setup":
        guard let runtime = try? await RuntimeBootstrap.makeBootstrappedRuntime() else {
            print("Failed to initialize runtime")
            return
        }
        let wizard = SetupWizard(executor: runtime.container.executor)
        await wizard.run()

    case "doctor":
        guard let runtime = try? await RuntimeBootstrap.makeBootstrappedRuntime() else {
            print("Failed to initialize runtime")
            return
        }
        var doctor = Doctor(executor: runtime.container.executor)
        await doctor.run()

    case "dashboard":
        let dash = Dashboard()
        dash.run()

    case "status":
        printStatus()

    case "version", "--version", "-v":
        print("Oracle OS v\(OracleOS.version)")

    case "help", "--help", "-h":
        printUsage()

    default:
        fputs("Unknown command: \(command)\n", stderr)
        printUsage()
        exit(1)
    }
}

await main()

// MARK: - Status

@MainActor
func printStatus() {
    print("Oracle OS v\(OracleOS.version)")
    print("")

    let hasAX = AXIsProcessTrusted()
    print("Accessibility: \(hasAX ? "granted" : "NOT GRANTED")")
    if !hasAX {
        print("  Run: oracle setup")
    }

    let hasScreenRecording = ScreenCapture.hasPermission()
    print("Screen Recording: \(hasScreenRecording ? "granted" : "not granted")")

    let recipes = RecipeStore.listRecipes()
    print("Recipes: \(recipes.count) installed")

    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    print("Running apps: \(apps.count)")

    print("")
    print(hasAX ? "Status: Ready" : "Status: Run `oracle setup` first")
}

// MARK: - Usage

func printUsage() {
    print("""
    Oracle OS v\(OracleOS.version) - Accessibility-tree MCP server for AI agents

    Usage: oracle <command>

    Commands:
      mcp         Start the MCP server (used by Claude Code)
      setup       Interactive setup wizard (first-time configuration)
      doctor      Diagnose issues and suggest fixes
      dashboard   Live terminal dashboard (agent state, policy, metrics)
      status      Quick health check
      version     Print version

    Get started:
      oracle setup    Configure permissions and MCP
      oracle doctor   Check if everything is working

    Oracle OS gives AI agents eyes and hands on macOS.
    """)
}
