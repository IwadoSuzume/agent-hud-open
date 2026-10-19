using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

/// <summary>Settings → General (the macOS Desktop's GeneralPane): appearance and language, launch at login, client hooks
/// (switching them off asks first) and how long a request waits. Its words are the engine's (`settings.*`), its values
/// Core's settings from the last state; a change is sent as a patch, and the window shows what the engine then says.
/// It follows the `appearance` setting, light or dark, on Mica where Windows 11 has it.</summary>
public partial class SettingsWindow : Window
{
    readonly ShellModel model;
    readonly Action<string> send;
    bool updating;

    internal SettingsWindow(ShellModel model, Action<string> send)
    {
        InitializeComponent();
        this.model = model;
        this.send = send;
        model.Changed += Refresh;
        model.SourcesChanged += ShowSources;
        // Light or dark as the application draws it (App.FollowAppearance: the setting, or Windows' app mode).
        var app = (App)Application.Current;
        app.AppearanceChanged += Theme;
        Closed += (_, _) =>
        {
            model.Changed -= Refresh;
            model.SourcesChanged -= ShowSources;
            app.AppearanceChanged -= Theme;
        };
        Refresh();
        ShowSources();
        // The clients are looked for when the window opens (1.5): the engine probes their folders once, not with each state.
        if (model.Hello is not null) send(ShellMessage.Sources());
    }

    void Refresh()
    {
        updating = true;
        try
        {
            Title = model.Text("settings.title");
            AppearanceLanguageTitle.Text = model.Text("settings.appearanceLanguage");
            AppearanceLabel.Text = model.Text("settings.appearance");
            AppearanceSystem.Content = model.Text("settings.system");
            AppearanceLight.Content = model.Text("settings.light");
            AppearanceDark.Content = model.Text("settings.dark");
            LanguageLabel.Text = model.Text("settings.language");
            StartupTitle.Text = model.Text("settings.startup");
            LaunchLabel.Text = model.Text("settings.launchAtLogin");
            ClientsTitle.Text = model.Text("settings.clients");
            HooksLabel.Text = model.Text("settings.clientHooks");
            HooksNote.Text = model.Text("settings.clientHooksNote");
            WaitLabel.Text = model.Text("settings.wait");
            WaitNote.Text = model.Text("settings.waitNote");

            var appearance = Setting("appearance") ?? "system";
            AppearanceSystem.IsChecked = appearance == "system";
            AppearanceLight.IsChecked = appearance == "light";
            AppearanceDark.IsChecked = appearance == "dark";

            // GeneralPane's choices: the system's language, then each in its own words.
            var languages = new[] { ("system", model.Text("settings.system")), ("zh-Hans", "中文"), ("en", "English") };
            LanguageChoice.ItemsSource = languages.Select(l => new ComboBoxItem { Content = l.Item2, Tag = l.Item1 }).ToList();
            LanguageChoice.SelectedItem = ((System.Collections.Generic.List<ComboBoxItem>)LanguageChoice.ItemsSource)
                .FirstOrDefault(i => (string)i.Tag == (Setting("language") ?? "system"));

            LaunchAtLogin.IsChecked = Flag("launchAtLogin");
            ClientHooks.IsChecked = Flag("clientHooks");

            // The wait's choices are the engine's (`settings.wait.<minutes>`, Core's `Settings.approvalWaitChoices`).
            var waits = (model.Hello?.Strings ?? new System.Collections.Generic.Dictionary<string, string>())
                .Where(s => s.Key.StartsWith("settings.wait.", StringComparison.Ordinal)
                            && int.TryParse(s.Key["settings.wait.".Length..], out _))
                .Select(s => new ComboBoxItem { Content = s.Value, Tag = int.Parse(s.Key["settings.wait.".Length..]) })
                .OrderBy(i => (int)i.Tag).ToList();
            WaitChoice.ItemsSource = waits;
            WaitChoice.SelectedItem = waits.FirstOrDefault(i => (int)i.Tag == model.IntSetting("approvalWaitMinutes", -1));
            WaitChoice.IsEnabled = Flag("clientHooks");

            Theme();
        }
        finally { updating = false; }
    }


    void ShowSources()
    {
        SourcesTitle.Text = model.Sources?.Title ?? "";
        SourcesList.ItemsSource = (model.Sources?.Items ?? []).Select(item => new SourceRow(item, Artwork.Mark(item.Mark))).ToList();
    }

    /// <summary>A client's row: dimmed when it was not found or this build does not read it, as the Desktop dims one it
    /// did not detect.</summary>
    sealed record SourceRow(SourceItem Item, ImageSource? Image)
    {
        public double Opacity => Item.Supported && Item.Detected ? 1 : 0.55;
    }

    string? Setting(string name) =>
        model.State?.Settings[name] is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    bool Flag(string name) => model.BoolSetting(name, false);

    void Patch(string name, JsonNode value)
    {
        if (updating) return;
        send(ShellMessage.UpdateSettings(new JsonObject { [name] = value }));
    }

    void OnAppearance(object sender, RoutedEventArgs e)
    {
        if ((sender as RadioButton)?.Tag is string value) Patch("appearance", value);
    }

    void OnLanguage(object sender, SelectionChangedEventArgs e)
    {
        if (LanguageChoice.SelectedItem is ComboBoxItem { Tag: string value }) Patch("language", value);
    }

    void OnLaunchAtLogin(object sender, RoutedEventArgs e) => Patch("launchAtLogin", LaunchAtLogin.IsChecked == true);

    void OnWait(object sender, SelectionChangedEventArgs e)
    {
        if (WaitChoice.SelectedItem is ComboBoxItem { Tag: int minutes }) Patch("approvalWaitMinutes", minutes);
    }

    /// <summary>Switching the hooks off asks first; switching them on does not.</summary>
    void OnClientHooks(object sender, RoutedEventArgs e)
    {
        if (ClientHooks.IsChecked == true) { Patch("clientHooks", true); return; }
        ClientHooks.IsChecked = true;
        var confirm = new ConfirmWindow(model.Text("settings.removeHooks"), model.Text("settings.clientHooksNote"),
                                        model.Text("settings.cancel"), model.Text("settings.remove")) { Owner = this };
        if (confirm.ShowDialog() == true) Patch("clientHooks", false);
    }

    // Look: light or dark as the application draws it, in WPF's Fluent theme, which draws the controls as Windows 11
    // does and a Mica backdrop where Windows 11 has one (a solid ground on Windows 10).
    bool? dark;

    void Theme()
    {
        var isDark = ((App)Application.Current).IsDark;
        if (dark == isDark) return;
        dark = isDark;
        Brush Solid(uint argb) => new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        Resources["Ground"] = Mica ? Brushes.Transparent : Solid(isDark ? 0xFF202020u : 0xFFF3F3F3u);
        Resources["Card"] = Solid(isDark ? 0x0DFFFFFFu : 0xB3FFFFFFu);
        Resources["Ink"] = Solid(isDark ? 0xFFFFFFFFu : 0xFF1B1B1Bu);
        Resources["Secondary"] = Solid(isDark ? 0xFF9A9AA0u : 0xFF5F5F66u);
        Resources["Hairline"] = Solid(isDark ? 0x1FFFFFFFu : 0x14000000u);
    }

    /// <summary>Windows 11 22H2 and later, where the Fluent theme draws Mica behind the window.</summary>
    static bool Mica => Environment.OSVersion.Version.Build >= 22621;
}
