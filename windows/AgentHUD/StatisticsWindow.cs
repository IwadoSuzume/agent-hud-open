// The statistics window's Recent usage card (the macOS Desktop's UsagePeriodsCard): Today, the last seven days and the
// last thirty side by side, each with its total, cost and cache share, a bar of every model's share and the models that
// spent the most. Every figure and word is the engine's (protocol 1.3, `statistics`); the window asks for them when it
// opens and again with each new report, and draws them. The models' colours are the Desktop's AgentPalette, by Core's
// palette index.
using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

sealed class StatisticsWindow : Window
{
    readonly ShellModel model;
    readonly Action<string> send;
    DateTimeOffset? askedFor;

    internal StatisticsWindow(ShellModel model, Action<string> send)
    {
        this.model = model;
        this.send = send;
        Width = 720;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        UseLayoutRounding = true;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        FontSize = 13;
        model.Changed += AskAgain;
        model.StatisticsChanged += Draw;
        // Light or dark as the application draws it (App.FollowAppearance), redrawn when that changes.
        var app = (App)Application.Current;
        app.AppearanceChanged += Draw;
        Closed += (_, _) => { model.Changed -= AskAgain; model.StatisticsChanged -= Draw; app.AppearanceChanged -= Draw; };
        Draw();
        AskAgain();
    }

    /// <summary>The figures again for each new report (and once at the start).</summary>
    void AskAgain()
    {
        Title = model.Text("menu.statistics");
        var report = model.State?.GeneratedAt;
        if (model.Hello is null || (askedFor is not null && askedFor == report)) return;
        askedFor = report;
        send(ShellMessage.Statistics());
    }

    bool IsLight => Application.Current is App app && !app.IsDark;

    Brush Ink => IsLight ? Brushes.Black : Brushes.White;
    Brush Secondary => new SolidColorBrush(IsLight ? Color.FromRgb(0x5F, 0x5F, 0x66) : Color.FromRgb(0x9A, 0x9A, 0xA0));

    /// <summary>The Desktop's AgentPalette (DesktopColours) at Core's palette index.</summary>
    Brush Palette(int index) => LevelBrush.Frozen(DesktopColours.PaletteColour(index, IsLight));

    void Draw()
    {
        var root = new StackPanel { Margin = new Thickness(24, 20, 24, 24) };
        if (model.Statistics is not { } statistics) { Content = root; return; }
        var header = new Grid { Margin = new Thickness(0, 0, 0, 10) };
        header.Children.Add(new TextBlock { Text = statistics.Title, FontWeight = FontWeights.SemiBold, Foreground = Ink });
        header.Children.Add(new TextBlock { Text = statistics.Dimensions, FontSize = 11, Foreground = Secondary, HorizontalAlignment = HorizontalAlignment.Right });
        root.Children.Add(header);
        var columns = new Grid();
        for (var i = 0; i < statistics.Periods.Count; i++)
        {
            if (i > 0) columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(29) });
            columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            if (i > 0)
            {
                var divider = new Rectangle { Width = 1, Fill = Secondary, Opacity = 0.3, HorizontalAlignment = HorizontalAlignment.Center };
                Grid.SetColumn(divider, i * 2 - 1);
                columns.Children.Add(divider);
            }
            var column = Column(statistics.Periods[i]);
            Grid.SetColumn(column, i * 2);
            columns.Children.Add(column);
        }
        root.Children.Add(new Border
        {
            Child = columns, Padding = new Thickness(14, 12, 14, 12), CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(IsLight ? Color.FromArgb(0xB3, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)),
        });
        Content = root;
    }

    FrameworkElement Column(StatisticsPeriod period)
    {
        var column = new StackPanel();
        var head = new Grid();
        head.Children.Add(new TextBlock { Text = period.Label, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Ink });
        head.Children.Add(new TextBlock { Text = period.Total, FontSize = 15, FontWeight = FontWeights.SemiBold, Foreground = Ink,
                                          HorizontalAlignment = HorizontalAlignment.Right });
        column.Children.Add(head);
        var line = string.Join(" · ", new[] { period.Cost, period.CacheHits }.Where(t => t is not null));
        column.Children.Add(new TextBlock { Text = line, FontSize = 11, Foreground = Secondary, Margin = new Thickness(0, 6, 0, 0),
                                            TextTrimming = TextTrimming.CharacterEllipsis });
        if (period.Models.Count == 0) return column;
        // Every model's share, in the period's order, as one bar.
        var bar = new Grid { Height = 5, Margin = new Thickness(0, 6, 0, 6), ClipToBounds = true };
        foreach (var model in period.Models)
            bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(model.Share, 0.0001), GridUnitType.Star) });
        for (var i = 0; i < period.Models.Count; i++)
        {
            var piece = new Rectangle { Fill = Palette(period.Models[i].PaletteIndex) };
            Grid.SetColumn(piece, i);
            bar.Children.Add(piece);
        }
        column.Children.Add(new Border { Child = bar, CornerRadius = new CornerRadius(3), ClipToBounds = true });
        foreach (var model in period.Models.Take(period.Listed))
        {
            var row = new Grid { Margin = new Thickness(0, 0, 0, 4), ToolTip = model.DisplayName };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new Ellipse { Width = 6, Height = 6, Fill = Palette(model.PaletteIndex), Margin = new Thickness(0, 0, 5, 0) });
            var mark = new Image { Source = Artwork.Mark(model.Mark), Width = 11, Height = 11, Margin = new Thickness(0, 0, 5, 0) };
            Grid.SetColumn(mark, 1);
            row.Children.Add(mark);
            var name = new TextBlock { Text = model.Name, FontSize = 11, Foreground = Secondary, TextTrimming = TextTrimming.CharacterEllipsis };
            Grid.SetColumn(name, 2);
            row.Children.Add(name);
            var tokens = new TextBlock { Text = model.Tokens, FontSize = 11, Foreground = Secondary, Margin = new Thickness(4, 0, 0, 0) };
            Grid.SetColumn(tokens, 3);
            row.Children.Add(tokens);
            column.Children.Add(row);
        }
        if (period.RestText is { } rest)
        {
            var more = new Grid { Margin = new Thickness(11, 0, 0, 0) };
            more.Children.Add(new TextBlock { Text = rest, FontSize = 11, Foreground = Secondary });
            more.Children.Add(new TextBlock { Text = period.RestTokens, FontSize = 11, Foreground = Secondary, HorizontalAlignment = HorizontalAlignment.Right });
            column.Children.Add(more);
        }
        return column;
    }
}
