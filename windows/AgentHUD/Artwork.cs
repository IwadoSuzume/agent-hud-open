// The vendors' marks, as the macOS Desktop draws them (Sources/AgentHUDDesktop/Components/AgentLogo.swift,
// AgentArtwork): the same files, single-colour marks drawn in the HUD's ink (white on the dark HUD), ChatGPT's in
// OpenAI's green. A vendor without artwork gets its initial instead. Presentation only.
using System;
using System.Collections.Generic;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AgentHUD;

static class Artwork
{
    static readonly Dictionary<string, string> FileNames = new()
    {
        ["Claude"] = "claude", ["ChatGPT"] = "chatgpt", ["Antigravity"] = "antigravity", ["DeepSeek"] = "deepseek",
        ["Grok"] = "grok", ["Grok Bot"] = "grok-bot", ["Cursor"] = "cursor", ["OpenCode"] = "opencode",
        ["Kimi"] = "kimi", ["GLM"] = "glm", ["Pi"] = "pi", ["GitHub Copilot"] = "copilot", ["OpenClaw"] = "openclaw",
        ["Hermes"] = "hermes", ["ZCode"] = "zcode", ["CodeBuddy"] = "codebuddy", ["WorkBuddy"] = "workbuddy",
        ["Qwen"] = "qwen", ["Qoder"] = "qoder",
    };

    /// <summary>Marks drawn in one colour, the ink's (AgentArtwork's template images).</summary>
    static readonly HashSet<string> SingleColour = ["Grok", "Cursor", "Kimi", "Pi", "GitHub Copilot", "Hermes", "ZCode"];

    // The dark HUD shows OpenCode's and Qoder's marks for a dark ground.
    static readonly Dictionary<string, string> OnDark = new() { ["OpenCode"] = "opencode-dark", ["Qoder"] = "qoder-dark" };

    static readonly Dictionary<string, ImageSource?> Cache = [];

    /// <summary>The mark <paramref name="vendor"/> (Core's mark key: vendors that share artwork share it) for the dark
    /// HUD, or null when it has no artwork.</summary>
    public static ImageSource? Mark(string vendor)
    {
        if (Cache.TryGetValue(vendor, out var known)) return known;
        ImageSource? made = null;
        if (OnDark.TryGetValue(vendor, out var name) || FileNames.TryGetValue(vendor, out name))
        {
            try
            {
                var file = new BitmapImage();
                file.BeginInit();
                file.UriSource = new Uri($"pack://application:,,,/Artwork/{name}.png");
                file.DecodePixelWidth = 64;
                file.CacheOption = BitmapCacheOption.OnLoad;
                file.EndInit();
                file.Freeze();
                made = vendor == "ChatGPT" ? Tinted(file, Color.FromRgb(16, 163, 127))
                     : SingleColour.Contains(vendor) ? Tinted(file, Colors.White) : file;
            }
            catch (System.IO.IOException) { made = null; }
        }
        Cache[vendor] = made;
        return made;
    }

    /// <summary>The image in one colour, each pixel keeping its alpha (`sourceAtop` fill on macOS).</summary>
    static ImageSource Tinted(BitmapSource source, Color colour)
    {
        var bgra = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        int width = bgra.PixelWidth, height = bgra.PixelHeight, stride = width * 4;
        var pixels = new byte[stride * height];
        bgra.CopyPixels(pixels, stride, 0);
        for (var i = 0; i < pixels.Length; i += 4)
        {
            var alpha = pixels[i + 3];
            // Premultiplied as Bgra32 is drawn: the colour scaled by the pixel's alpha.
            pixels[i] = (byte)(colour.B * alpha / 255);
            pixels[i + 1] = (byte)(colour.G * alpha / 255);
            pixels[i + 2] = (byte)(colour.R * alpha / 255);
        }
        var tinted = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
        tinted.Freeze();
        return tinted;
    }
}
