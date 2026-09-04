using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

namespace EntraMailSendRbac.Gui;

public sealed class PowerShellWorkerService : IAsyncDisposable
{
    private const string ProtocolPrefix = "@@RBACGUI@@";
    private readonly ConcurrentDictionary<string, TaskCompletionSource<WorkerResponse>> _pending = new();
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private Process? _process;

    public string Language { get; set; } = "de";

    private string T(string de, string en) => Language == "en" ? en : de;

    public event Action<string>? LogReceived;
    public event Action<WorkerProgress>? ProgressReceived;

    public Task StartAsync()
    {
        if (_process is { HasExited: false }) return Task.CompletedTask;

        var workerPath = Path.Combine(AppContext.BaseDirectory, "Backend", "ExchangeWorker.ps1");
        if (!File.Exists(workerPath))
            throw new FileNotFoundException(T("Exchange PowerShell Worker wurde nicht gefunden.", "Exchange PowerShell worker was not found."), workerPath);

        var startInfo = new ProcessStartInfo
        {
            FileName = "pwsh",
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(workerPath);

        try
        {
            _process = Process.Start(startInfo)
                ?? throw new InvalidOperationException(T("PowerShell Worker konnte nicht gestartet werden.", "PowerShell worker could not be started."));
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                T("PowerShell 7 (pwsh) wurde nicht gefunden. Bitte PowerShell 7.4 oder neuer installieren und sicherstellen, dass 'pwsh' im PATH verfügbar ist.", "PowerShell 7 (pwsh) was not found. Please install PowerShell 7.4 or newer and make sure 'pwsh' is available in PATH."), ex);
        }

        _process.EnableRaisingEvents = true;
        _process.Exited += (_, _) => FailAllPending(T("Der PowerShell Worker wurde unerwartet beendet.", "The PowerShell worker exited unexpectedly."));

        _ = Task.Run(() => ReadStdOutAsync(_process));
        _ = Task.Run(() => ReadStdErrAsync(_process));

        return Task.CompletedTask;
    }

    public async Task<WorkerResponse> SendAsync(string command, object data, TimeSpan timeout)
    {
        await StartAsync();
        if (_process is null || _process.HasExited)
            throw new InvalidOperationException(T("PowerShell Worker ist nicht verfügbar.", "PowerShell worker is not available."));

        var id = Guid.NewGuid().ToString("N");
        var tcs = new TaskCompletionSource<WorkerResponse>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_pending.TryAdd(id, tcs))
            throw new InvalidOperationException(T("Interner Request konnte nicht registriert werden.", "Internal request could not be registered."));

        var payload = JsonSerializer.Serialize(new { id, command, data });

        await _writeLock.WaitAsync();
        try
        {
            await _process.StandardInput.WriteLineAsync(payload);
            await _process.StandardInput.FlushAsync();
        }
        catch
        {
            _pending.TryRemove(id, out _);
            throw;
        }
        finally
        {
            _writeLock.Release();
        }

        using var timeoutCts = new CancellationTokenSource(timeout);
        using var registration = timeoutCts.Token.Register(() =>
        {
            if (_pending.TryRemove(id, out var pending))
                pending.TrySetException(new TimeoutException(T($"Zeitüberschreitung bei '{command}'.", $"Timeout while executing '{command}'.")));
        });

        return await tcs.Task;
    }

    private async Task ReadStdOutAsync(Process process)
    {
        while (!process.HasExited)
        {
            var line = await process.StandardOutput.ReadLineAsync();
            if (line is null) break;

            if (!line.StartsWith(ProtocolPrefix, StringComparison.Ordinal))
            {
                if (!string.IsNullOrWhiteSpace(line)) LogReceived?.Invoke(line);
                continue;
            }

            try
            {
                var json = line[ProtocolPrefix.Length..];
                var envelope = JsonSerializer.Deserialize<WorkerEnvelope>(json, JsonOptions);
                if (envelope is null) continue;

                if (string.Equals(envelope.Type, "progress", StringComparison.OrdinalIgnoreCase))
                {
                    var level = "INFO";
                    if (envelope.Data.ValueKind == JsonValueKind.Object &&
                        envelope.Data.TryGetProperty("level", out var levelElement) &&
                        levelElement.ValueKind == JsonValueKind.String)
                    {
                        level = levelElement.GetString() ?? "INFO";
                    }
                    ProgressReceived?.Invoke(new WorkerProgress(level, envelope.Message ?? string.Empty));
                    continue;
                }

                if (string.Equals(envelope.Type, "response", StringComparison.OrdinalIgnoreCase) &&
                    !string.IsNullOrWhiteSpace(envelope.RequestId) &&
                    _pending.TryRemove(envelope.RequestId, out var tcs))
                {
                    tcs.TrySetResult(new WorkerResponse(
                        envelope.Success,
                        envelope.Message ?? string.Empty,
                        envelope.Data));
                }
            }
            catch (Exception ex)
            {
                LogReceived?.Invoke(T($"Worker-Protokoll konnte nicht gelesen werden: {ex.Message}", $"Worker protocol could not be read: {ex.Message}"));
            }
        }
    }

    private async Task ReadStdErrAsync(Process process)
    {
        while (!process.HasExited)
        {
            var line = await process.StandardError.ReadLineAsync();
            if (line is null) break;
            if (!string.IsNullOrWhiteSpace(line)) LogReceived?.Invoke($"[PowerShell] {line}");
        }
    }

    private void FailAllPending(string message)
    {
        foreach (var item in _pending.ToArray())
        {
            if (_pending.TryRemove(item.Key, out var tcs))
                tcs.TrySetException(new InvalidOperationException(message));
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_process is null) return;

        try
        {
            if (!_process.HasExited)
            {
                try
                {
                    await SendAsync("shutdown", new { }, TimeSpan.FromSeconds(5));
                }
                catch
                {
                    // Best effort shutdown.
                }
            }
        }
        finally
        {
            try
            {
                if (!_process.HasExited)
                    _process.Kill(entireProcessTree: true);
            }
            catch
            {
                // Ignore shutdown cleanup errors.
            }

            _process.Dispose();
            _process = null;
            _writeLock.Dispose();
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private sealed class WorkerEnvelope
    {
        public string? Type { get; set; }
        public string? RequestId { get; set; }
        public bool Success { get; set; }
        public string? Message { get; set; }
        public JsonElement Data { get; set; }
    }
}

public sealed record WorkerResponse(bool Success, string Message, JsonElement Data);
public sealed record WorkerProgress(string Level, string Message);
