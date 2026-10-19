// Presentation only: how a level the engine gave is coloured (the dark HUD's status colours, the Desktop's
// StatusPalette), how a share fills a bar, what is hidden when absent.
using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using AgentHUD.Protocol;

namespace AgentHUD;

sealed class LevelBrush : IValueConverter
{
    // The Desktop's StatusPalette on the dark HUD (DesktopColours, held to its source by a test).
    public static readonly SolidColorBrush Ok = Frozen(AgentHUD.Shell.DesktopColours.Ok);
    public static readonly SolidColorBrush Warning = Frozen(AgentHUD.Shell.DesktopColours.Warning);
    public static readonly SolidColorBrush Critical = Frozen(AgentHUD.Shell.DesktopColours.Critical);
    public static readonly SolidColorBrush None = Frozen(AgentHUD.Shell.DesktopColours.Idle);

    public static SolidColorBrush Frozen(uint rgb)
    {
        var brush = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
        brush.Freeze();
        return brush;
    }

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value switch
    {
        StatusLevel.Ok => Ok,
        StatusLevel.Warning => Warning,
        StatusLevel.Critical => Critical,
        _ => None,
    };

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>A share (0–1) of the width given as the parameter, in DIPs.</summary>
sealed class FractionWidth : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        (value is double share ? share : 0) * double.Parse((string)parameter!, CultureInfo.InvariantCulture);

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

/// <summary>Collapsed when the value is null, false or empty text; with the parameter "invert", the other way round.</summary>
sealed class Shown : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var present = value switch { null => false, bool flag => flag, string text => text.Length > 0, _ => true };
        if ((string?)parameter == "invert") present = !present;
        return present ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}
