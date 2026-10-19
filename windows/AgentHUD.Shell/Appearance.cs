// The appearance setting as the normal windows draw it: "light", "dark", or anything else ("system") as Windows' app
// mode says (AppsUseLightTheme). Presentation only; the setting itself is Core's.
namespace AgentHUD.Shell;

public static class Appearance
{
    public static bool IsDark(string? setting, bool systemUsesLight) =>
        setting switch { "light" => false, "dark" => true, _ => !systemUsesLight };
}
