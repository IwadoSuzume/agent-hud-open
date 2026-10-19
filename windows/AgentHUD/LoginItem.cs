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
    /// only a copy of the portable package, which build-windows.ps1 marks (D-055), never a build's output folder or a
    /// developer's own published folder, which would otherwise be left in the user's Run key.</summary>
    static bool IsAvailable => Environment.ProcessPath is not null && AgentHUD.Shell.Package.IsPackaged(AppContext.BaseDirectory);

    /// <summary>Registers the shell when it never was: no value of ours, and no record that the user turned one off. A
    /// value of ours that names another place (the folder was moved, or a newer copy was unpacked elsewhere) is pointed
    /// at this copy; Task Manager's record of the user's choice is left as it is.</summary>
    public static void RegisterIfNeverRegistered()
    {
        if (!IsAvailable) return;
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(RunKey);
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
            if (run?.GetValue(Name) is null && approved?.GetValue(Name) is null) Set(true);
            else if (run?.GetValue(Name) is string registered && Command is { } command && registered != command)
            {
                using var writable = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
                writable?.SetValue(Name, command, RegistryValueKind.String);
            }
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
