# ADR-002: Windows UI technology — WPF on .NET 10

- Status: accepted (M0, 2026-10-16)
- Deciders: port owner (unattended run; decision principles of TASK.md §7)

## Context

The macOS interface (AgentHUDDesktop, ~30k lines of SwiftUI/AppKit) cannot be reused on Windows; a native shell has to
be written in `windows/`. It needs, in order of importance:

1. A top-centre "island" and edge docks: borderless, topmost, **non-activating**, per-pixel transparent windows that
   let clicks through while collapsed (`WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TRANSPARENT`),
   one per monitor.
2. A notification-area (tray) icon with a self-drawn pop-up menu.
3. Mica/Acrylic backdrops on Windows 11 for the settings and statistics windows, solid fallback on Windows 10.
4. Per-Monitor-V2 DPI, several monitors, monitor hot-plug.
5. A build that runs from the command line on a clean CI image (`windows-latest`) without Visual Studio workloads,
   MSIX tooling or interactive steps, and a small portable zip.
6. As few third-party packages as possible (project rule: no dependencies; TASK.md §6 G6).

Candidates: **WPF** (.NET, in-box `Microsoft.WindowsDesktop.App`), **WinUI 3** (Windows App SDK), and for
completeness Swift + swift-winrt (option B of TASK.md §2, rejected in ADR-001).

## Scoring (0–3, higher is better)

| Criterion | WPF (.NET 10) | WinUI 3 (WinAppSDK 1.x) | Notes |
| --- | --- | --- | --- |
| Per-pixel transparent topmost no-activate window | 3 | 1 | WPF: `AllowsTransparency=True` layered window + `SetWindowLongPtr(GWL_EXSTYLE)`. WinUI 3 has no supported per-pixel transparent top-level window; needs `SetWindowSubclass`/DComp hacks. |
| Click-through while collapsed (`WS_EX_TRANSPARENT`) | 3 | 2 | Both via Win32 interop; trivial on WPF's HWND. |
| Tray icon | 2 | 1 | Neither has a tray API; WPF can use `System.Windows.Forms.NotifyIcon` (in-box WindowsDesktop runtime) or `Shell_NotifyIcon` P/Invoke. WinUI 3 needs P/Invoke and its own message window. |
| Mica / Acrylic | 2 | 3 | WinUI 3 has `MicaBackdrop`/`DesktopAcrylicBackdrop`. WPF: `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)` + extended frame works on Win11 22H2+; .NET 9+ `ThemeMode` adds Fluent styling. |
| Per-Monitor-V2 DPI, multi-monitor, hot-plug | 2 | 3 | WPF supports PMv2 through the app manifest (`dpiAwareness PerMonitorV2`) and `DpiChanged`; monitor enumeration via `EnumDisplayMonitors`. |
| CLI/CI build without workloads | 3 | 1 | `dotnet build` with the plain SDK builds WPF. WinUI 3 needs the Windows App SDK NuGet packages, the MRT/PRI toolchain and either MSIX or the bootstrapper for unpackaged apps. |
| Third-party packages | 3 | 1 | WPF: none for the app. WinUI 3: `Microsoft.WindowsAppSDK` (+ `Microsoft.Windows.SDK.BuildTools`). |
| Portable package size | 2 | 1 | WPF framework-dependent build is a few MB (needs the .NET 10 Desktop Runtime); self-contained ~70 MB trimmed-free. WinUI 3 self-contained adds the WinAppSDK runtime (~30–40 MB) on top. |
| Windows 10 22H2 support | 3 | 2 | WinUI 3 runs on 1809+, but Mica is Win11 only on both. |
| Offscreen rendering for `--snapshot` (G5) | 3 | 1 | WPF: `RenderTargetBitmap` renders any visual tree without a window. WinUI 3: `RenderTargetBitmap` needs the element in a live XAML island. |
| **Total** | **26** | **16** | |

## Decision

Use **WPF on .NET 10** (`net10.0-windows`, `UseWPF`, `UseWindowsForms` only for `NotifyIcon`).

- **.NET 10 instead of the brief's ".NET 8"**: .NET 8 reaches end of support on 2026-11-10, less than a month after this
  decision; .NET 10 is the current LTS (supported to 2028-11). The machine and `windows-latest` carry the .NET 10 SDK.
  This is a deviation from the brief and is recorded in DECISIONS.md.
- No NuGet package in the shipped application. Interop with `user32`, `dwmapi`, `shell32` through `DllImport`
  declarations written in the project.
- Test project only: `Microsoft.NET.Test.Sdk`, `MSTest.TestAdapter`, `MSTest.TestFramework` (MIT, Microsoft), never
  shipped; recorded in DECISIONS.md and THIRD_PARTY_NOTICES.txt.

## Consequences

- The island's glass is approximated: WPF cannot host a DWM backdrop inside a per-pixel transparent layered window, so
  the island and panel draw a solid/translucent fill (the "solid" look of macOS with its transparency slider), and Mica
  is used only for normal windows (settings, statistics). `docs/windows.md` states the difference.
- WPF's rendering of text and shapes differs from SwiftUI; visual fidelity is a lower priority than behaviour (TASK.md
  §7.1).
- A framework-dependent zip needs the .NET 10 Desktop Runtime; the build script can also produce a self-contained
  variant (`-SelfContained`).
