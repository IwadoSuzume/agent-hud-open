// The engine as the shell's child (PROTOCOL.md "Transport"): `agenthud-engine --serve` with its standard input and
// output as the protocol's pipes. Lines are read on a thread of their own and handed on as parsed messages; a line the
// shell does not take is reported and skipped (D-022).
using System.Diagnostics;
using System.Text;
using AgentHUD.Protocol;

namespace AgentHUD.Shell;

/// <summary>Where the lines come from: the engine's process, or in tests any pair of streams.</summary>
public sealed class EngineConnection : IDisposable
{
    readonly TextWriter input;
    readonly TextReader output;
    readonly Process? process;
    readonly object writing = new();
    Thread? reader;
    int exited;

    /// <summary>Raised on the reader thread for each message the engine sends, in order.</summary>
    public event Action<object>? Received;
    /// <summary>Raised on the reader thread for a line the shell does not take, with the reason.</summary>
    public event Action<string>? Rejected;
    /// <summary>Raised once when the engine's output ends: the engine exited (its status, or null when unknown).</summary>
    public event Action<int?>? Ended;
    /// <summary>Raised on a thread of its own for each line the engine writes to standard error (its complaints,
    /// never protocol), for the shell's log.</summary>
    public event Action<string>? Complained;

    public EngineConnection(TextWriter input, TextReader output, Process? process = null)
    {
        this.input = input;
        this.output = output;
        this.process = process;
    }

    /// <summary>The engine built beside the shell (`agenthud-engine.exe` in the shell's own folder).</summary>
    public static string DefaultEnginePath => Path.Combine(AppContext.BaseDirectory, "agenthud-engine.exe");

    /// <summary>Starts `engine --serve` with <paramref name="arguments"/> (`--demo`, `--language`), without a console
    /// window, its arguments passed as a list and never as one command string (G7).</summary>
    public static EngineConnection Launch(string engine, IEnumerable<string> arguments)
    {
        var utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        var start = new ProcessStartInfo(engine)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = utf8,
            StandardOutputEncoding = utf8,
            StandardErrorEncoding = utf8,
        };
        start.ArgumentList.Add("--serve");
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        var process = Process.Start(start) ?? throw new InvalidOperationException($"{engine} did not start");
        return new EngineConnection(process.StandardInput, process.StandardOutput, process);
    }

    /// <summary>Starts reading, then says hello (PROTOCOL.md "The exchange" 1).</summary>
    public void Start(string shellVersion)
    {
        reader = new Thread(Read) { IsBackground = true, Name = "AgentHUD engine output" };
        reader.Start();
        if (process is not null)
        {
            // Read to its end, or a full pipe would stop the engine at its next complaint.
            new Thread(() =>
            {
                try { while (process.StandardError.ReadLine() is { } line) Complained?.Invoke(line); }
                catch (IOException) { }
                catch (ObjectDisposedException) { }
            }) { IsBackground = true, Name = "AgentHUD engine errors" }.Start();
        }
        Send(ShellMessage.Hello(shellVersion));
    }

    /// <summary>Writes one of <see cref="ShellMessage"/>'s lines; a gone engine takes nothing, and its end is
    /// reported by <see cref="Ended"/>.</summary>
    public void Send(string line)
    {
        lock (writing)
        {
            try
            {
                input.Write(line);
                input.Flush();
            }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
        }
    }

    void Read()
    {
        try
        {
            while (output.ReadLine() is { } line)
            {
                object message;
                try { message = EngineMessage.Parse(line); }
                catch (ProtocolRejectedException error)
                {
                    Rejected?.Invoke(error.Message);
                    continue;
                }
                Received?.Invoke(message);
            }
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        End();
    }

    void End()
    {
        if (Interlocked.Exchange(ref exited, 1) != 0) return;
        int? status = null;
        if (process is not null && process.WaitForExit(5000)) status = process.ExitCode;
        Ended?.Invoke(status);
    }

    /// <summary>Asks the engine to quit and waits for it a little (it lets waiting approvals go back to their
    /// clients first); a process that does not end is stopped.</summary>
    public void Quit(TimeSpan wait)
    {
        Send(ShellMessage.Quit());
        if (process is null) return;
        if (!process.WaitForExit((int)wait.TotalMilliseconds))
        {
            try { process.Kill(); } catch (InvalidOperationException) { }
        }
    }

    public void Dispose()
    {
        lock (writing)
        {
            // Closing flushes what is buffered; an engine that already exited has closed its end of the pipe.
            try { input.Dispose(); }
            catch (IOException) { }
        }
        process?.Dispose();
    }
}
