// Presentation only: how a level the engine gave is coloured (the dark HUD's status colours, macOS's system green,
// orange and red), how a share fills a bar, what is hidden when absent.
using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using AgentHUD.Protocol;

namespace AgentHUD;

sealed class LevelBrush : IValueConverter
{
    public static readonly SolidColorBrush Ok = Frozen(0x30, 0xD1, 0x58);
    public static readonly SolidColorBrush Warning = Frozen(0xFF, 0x9F, 0x0A);
    public static readonly SolidColorBrush Critical = Frozen(0xFF, 0x45, 0x3A);
    public static readonly SolidColorBrush None = Frozen(0x8E, 0x8E, 0x93);

    static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
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
