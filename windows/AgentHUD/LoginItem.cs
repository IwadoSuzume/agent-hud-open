// Launch at login on Windows (D-043: the shell is what logs in), as the macOS Desktop's LoginItem does it with
// ServiceManagement: registered once when the setting is on and the user never had it (a value Task Manager's Startup
// page turned off stays off), then set and cleared as the setting changes. The current user's `Run` key, with the
// shell's own path quoted; never in the demo.
using System;
using Microsoft.Win32;

namespace AgentHUD;

static class LoginItem
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    const string Name = "Agent HUD";

    static string? Command => Environment.ProcessPath is { } path ? $"\"{path}\"" : null;

    /// <summary>Whether this copy may register itself, as the Desktop's `LoginItem.isAvailable` lets only an installed app:
    /// never a build's own output folder (`bin\Debug`, `bin\Release`), which a developer's run would otherwise leave in
    /// the user's Run key.</summary>
    static bool IsAvailable => Environment.ProcessPath is { } path
        && !path.Contains(@"\bin\Debug\", StringComparison.OrdinalIgnoreCase)
        && !path.Contains(@"\bin\Release\", StringComparison.OrdinalIgnoreCase);

    /// <summary>Registers the shell when it never was: no value of ours, and no record that the user turned one off.</summary>
    public static void RegisterIfNeverRegistered()
    {
        if (!IsAvailable) return;
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(RunKey);
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
            if (run?.GetValue(Name) is null && approved?.GetValue(Name) is null) Set(true);
        }
        catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException or System.IO.IOException)
        {
            App.Log($"login item: {error.Message}");
        }
    }

    public static void Set(bool enabled)
    {
        if (!IsAvailable) return;
        try
        {
            using var run = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled && Command is { } command)
            {
                if (run.GetValue(Name) as string != command) run.SetValue(Name, command, RegistryValueKind.String);
                // Turned on here, it is on: a "disabled" Task Manager kept for it would leave the setting on and nothing
                // launching.
                using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey, writable: true);
                if (approved?.GetValue(Name) is not null) approved.DeleteValue(Name, throwOnMissingValue: false);
            }
            else if (!enabled && run.GetValue(Name) is not null)
            {
                run.DeleteValue(Name, throwOnMissingValue: false);
            }
        }
        catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException or System.IO.IOException)
        {
            App.Log($"login item: {error.Message}");
        }
    }
}
