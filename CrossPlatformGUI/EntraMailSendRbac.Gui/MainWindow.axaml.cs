using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;

namespace EntraMailSendRbac.Gui;

public partial class MainWindow : Window
{
    private readonly PowerShellWorkerService _worker = new();
    private bool _runtimeReady;
    private bool _connected;

    public MainWindow()
    {
        InitializeComponent();

        _worker.LogReceived += message => Dispatcher.UIThread.Post(() => AddStatus(message));
        _worker.ProgressReceived += progress => Dispatcher.UIThread.Post(() => AddStatus($"[{progress.Level}] {progress.Message}"));

        Opened += async (_, _) => await InitializeRuntimeAsync();
        Closing += (_, _) => _ = _worker.DisposeAsync();

        RetryRuntimeButton.Click += async (_, _) => await InitializeRuntimeAsync();
        ConnectButton.Click += async (_, _) => await ConnectAsync("browser");
        DeviceConnectButton.Click += async (_, _) => await ConnectAsync("device");
        ConfigureButton.Click += async (_, _) => await ConfigureAsync();
        TestButton.Click += async (_, _) => await TestAsync();
        DisconnectButton.Click += async (_, _) => await DisconnectAsync();

        SetActionButtons();
    }

    private async Task InitializeRuntimeAsync()
    {
        SetBusy(true);
        RuntimeStatusText.Text = "PowerShell und ExchangeOnlineManagement werden geprüft …";
        RetryRuntimeButton.IsVisible = false;
        AddStatus("Starte Cross-Platform PowerShell-Backend …");

        try
        {
            await _worker.StartAsync();
            var response = await _worker.SendAsync(
                "init",
                new { installIfMissing = true },
                TimeSpan.FromMinutes(5));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            var platform = ReadString(response.Data, "platform") ?? "unbekannt";
            var psVersion = ReadString(response.Data, "powerShellVersion") ?? "unbekannt";
            var moduleVersion = ReadString(response.Data, "moduleVersion") ?? "unbekannt";

            RuntimeStatusText.Text = $"{platform} · PowerShell {psVersion} · ExchangeOnlineManagement {moduleVersion}";
            _runtimeReady = true;
            AddStatus("[OK] Laufzeit ist bereit.");
        }
        catch (Exception ex)
        {
            _runtimeReady = false;
            RuntimeStatusText.Text = "Laufzeitprüfung fehlgeschlagen";
            RetryRuntimeButton.IsVisible = true;
            AddStatus($"[ERROR] {ex.Message}");
        }
        finally
        {
            SetBusy(false);
            SetActionButtons();
        }
    }

    private async Task ConnectAsync(string mode)
    {
        var admin = AdminTextBox.Text?.Trim() ?? string.Empty;
        if (!LooksLikeMailAddress(admin))
        {
            AddStatus("[ERROR] Bitte ein gültiges Admin-Konto eingeben.");
            return;
        }

        SetBusy(true);
        AddStatus(mode == "device"
            ? "Starte Microsoft Device-Code-Anmeldung …"
            : $"Öffne Microsoft-Anmeldung für {admin} …");

        try
        {
            var response = await _worker.SendAsync(
                "connect",
                new { adminUpn = admin, mode },
                TimeSpan.FromMinutes(10));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            _connected = true;
            ConnectionStatusText.Text = $"Verbunden: {admin}";
            ConnectionStatusText.Foreground = Brushes.Green;
            AddStatus("[OK] Verbindung zu Exchange Online erfolgreich.");
        }
        catch (Exception ex)
        {
            _connected = false;
            ConnectionStatusText.Text = "Nicht verbunden";
            ConnectionStatusText.Foreground = Brushes.DarkRed;
            AddStatus($"[ERROR] {ex.Message}");

            if (mode == "browser")
                AddStatus("Hinweis: Falls der Browser-Login auf diesem System nicht funktioniert, 'Device Code' verwenden.");
        }
        finally
        {
            SetBusy(false);
            SetActionButtons();
        }
    }

    private async Task ConfigureAsync()
    {
        if (!TryReadConfiguration(out var config, out var error))
        {
            AddStatus($"[ERROR] {error}");
            return;
        }

        if (TenantMailSendCheckBox.IsChecked != true)
        {
            AddStatus("[ERROR] Die Sicherheitsbestätigung muss vor der Konfiguration aktiviert werden.");
            return;
        }

        SetBusy(true);
        AddStatus("Richte Exchange Application RBAC ein …");

        try
        {
            var response = await _worker.SendAsync(
                "configure",
                new
                {
                    appId = config.AppId,
                    objectId = config.ObjectId,
                    mailbox = config.Mailbox,
                    tenantWideMailSendRemoved = true
                },
                TimeSpan.FromMinutes(5));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            AddStatus("[OK] Exchange-RBAC-Konfiguration wurde eingerichtet.");

            var scope = ReadString(response.Data, "scopeName");
            var assignment = ReadString(response.Data, "assignmentName");
            if (!string.IsNullOrWhiteSpace(scope)) AddStatus($"Scope: {scope}");
            if (!string.IsNullOrWhiteSpace(assignment)) AddStatus($"Role Assignment: {assignment}");

            AddStatus("Starte automatische Sicherheitsprüfung …");
            await TestAsync(skipBusyChange: true);
        }
        catch (Exception ex)
        {
            AddStatus($"[ERROR] {ex.Message}");
        }
        finally
        {
            SetBusy(false);
            SetActionButtons();
        }
    }

    private async Task TestAsync(bool skipBusyChange = false)
    {
        if (!TryReadConfiguration(out var config, out var error))
        {
            AddStatus($"[ERROR] {error}");
            return;
        }

        if (!skipBusyChange) SetBusy(true);
        AddStatus($"Teste Application Mail.Send für {config.Mailbox} …");

        try
        {
            var response = await _worker.SendAsync(
                "test",
                new
                {
                    appId = config.AppId,
                    objectId = config.ObjectId,
                    mailbox = config.Mailbox
                },
                TimeSpan.FromMinutes(3));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            AddStatus($"[OK] GRANTED: Application Mail.Send ist für {config.Mailbox} im erwarteten Scope.");
            AddStatus("Hinweis: Dieser Test prüft Exchange Application RBAC. Tenantweite Entra API Permissions müssen separat ausgeschlossen sein.");
        }
        catch (Exception ex)
        {
            AddStatus($"[ERROR] {ex.Message}");
        }
        finally
        {
            if (!skipBusyChange)
            {
                SetBusy(false);
                SetActionButtons();
            }
        }
    }

    private async Task DisconnectAsync()
    {
        SetBusy(true);
        try
        {
            var response = await _worker.SendAsync("disconnect", new { }, TimeSpan.FromMinutes(1));
            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            _connected = false;
            ConnectionStatusText.Text = "Nicht verbunden";
            ConnectionStatusText.Foreground = Brushes.DarkRed;
            AddStatus("[OK] Exchange-Online-Verbindung getrennt.");
        }
        catch (Exception ex)
        {
            AddStatus($"[ERROR] {ex.Message}");
        }
        finally
        {
            SetBusy(false);
            SetActionButtons();
        }
    }

    private bool TryReadConfiguration(out AppConfiguration configuration, out string error)
    {
        configuration = new AppConfiguration(
            AppIdTextBox.Text?.Trim() ?? string.Empty,
            ObjectIdTextBox.Text?.Trim() ?? string.Empty,
            MailboxTextBox.Text?.Trim() ?? string.Empty);

        if (!Guid.TryParse(configuration.AppId, out _))
        {
            error = "Application (Client) ID fehlt oder ist keine gültige GUID.";
            return false;
        }

        if (!Guid.TryParse(configuration.ObjectId, out _))
        {
            error = "Enterprise App Object ID fehlt oder ist keine gültige GUID.";
            return false;
        }

        if (!LooksLikeMailAddress(configuration.Mailbox))
        {
            error = "Shared Mailbox fehlt oder ist keine gültige E-Mail-Adresse.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool LooksLikeMailAddress(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return false;
        var at = value.IndexOf('@');
        return at > 0 && at < value.Length - 3 && value[(at + 1)..].Contains('.');
    }

    private void SetBusy(bool busy)
    {
        BusyProgress.IsVisible = busy;
        AdminTextBox.IsEnabled = !busy;
        AppIdTextBox.IsEnabled = !busy;
        ObjectIdTextBox.IsEnabled = !busy;
        MailboxTextBox.IsEnabled = !busy;
        TenantMailSendCheckBox.IsEnabled = !busy;
        RetryRuntimeButton.IsEnabled = !busy;
        ConnectButton.IsEnabled = !busy && _runtimeReady;
        DeviceConnectButton.IsEnabled = !busy && _runtimeReady;
        ConfigureButton.IsEnabled = !busy && _runtimeReady && _connected;
        TestButton.IsEnabled = !busy && _runtimeReady && _connected;
        DisconnectButton.IsEnabled = !busy && _runtimeReady && _connected;
    }

    private void SetActionButtons()
    {
        ConnectButton.IsEnabled = _runtimeReady;
        DeviceConnectButton.IsEnabled = _runtimeReady;
        ConfigureButton.IsEnabled = _runtimeReady && _connected;
        TestButton.IsEnabled = _runtimeReady && _connected;
        DisconnectButton.IsEnabled = _runtimeReady && _connected;
    }

    private void AddStatus(string message)
    {
        var stamp = DateTime.Now.ToString("HH:mm:ss");
        StatusTextBox.Text = string.IsNullOrEmpty(StatusTextBox.Text)
            ? $"[{stamp}] {message}"
            : $"{StatusTextBox.Text}{Environment.NewLine}[{stamp}] {message}";
        StatusTextBox.CaretIndex = StatusTextBox.Text?.Length ?? 0;
    }

    private static string? ReadString(JsonElement data, string propertyName)
    {
        if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty(propertyName, out var property))
            return property.ValueKind == JsonValueKind.String ? property.GetString() : property.ToString();
        return null;
    }

    private sealed record AppConfiguration(string AppId, string ObjectId, string Mailbox);
}
