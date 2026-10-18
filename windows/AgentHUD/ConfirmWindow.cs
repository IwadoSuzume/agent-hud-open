// A question with two answers in the engine's words (a system message box would name its buttons in Windows' own
// language, not the HUD's): Cancel, the default and Escape's, and the action, which closes it with true.
using System.Windows;
using System.Windows.Controls;

namespace AgentHUD;

sealed class ConfirmWindow : Window
{
    public ConfirmWindow(string title, string message, string cancel, string action)
    {
        Title = title;
        Width = 420;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        var actionButton = new Button { Content = action, MinWidth = 88, Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0) };
        actionButton.Click += (_, _) => DialogResult = true;
        var cancelButton = new Button { Content = cancel, MinWidth = 88, Padding = new Thickness(12, 4, 12, 4), IsCancel = true, IsDefault = true };
        Content = new StackPanel
        {
            Margin = new Thickness(20),
            Children =
            {
                new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 14 },
                new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 16) },
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right,
                                 Children = { cancelButton, actionButton } },
            },
        };
    }
}
