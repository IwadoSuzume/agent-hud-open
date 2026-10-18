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

    /// <summary>Registers the shell when it never was: no value of ours, and no record that the user turned one off.</summary>
    public static void RegisterIfNeverRegistered()
    {
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
        try
        {
            using var run = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled && Command is { } command)
            {
                if (run.GetValue(Name) as string != command) run.SetValue(Name, command, RegistryValueKind.String);
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
