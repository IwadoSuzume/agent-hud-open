// What the portable package (scripts/build-windows.ps1, D-055) puts beside the shell, and what an engine's status says
// about the machine it ran on. Presentation and packaging facts only; no Core rule.
namespace AgentHUD.Shell;

public static class Package
{
    /// <summary>The file build-windows.ps1 writes beside AgentHUD.exe. Only a copy that has it is an installed one
    /// (launch at login registers nothing else: a developer's build output never lands in the user's Run key).</summary>
    public const string MarkerFileName = "agenthud-package.json";

    public static bool IsPackaged(string folder) => File.Exists(Path.Combine(folder, MarkerFileName));

    /// <summary>Windows' STATUS_DLL_NOT_FOUND: the engine could not load a library it needs. The package carries the
    /// Swift runtime; the Microsoft Visual C++ runtime is the machine's own (D-055), so this is the likely one missing.</summary>
    public const int DllNotFound = unchecked((int)0xC0000135);

    public static bool IsMissingLibrary(int? status) => status == DllNotFound;

    /// <summary>Microsoft's page for the supported Visual C++ Redistributable downloads.</summary>
    public const string VisualCppRedistributablePage = "https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist";
}
