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
    private string _language = "de";
    private string _runtimeSummary = string.Empty;

    public MainWindow()
    {
        InitializeComponent();

        _worker.LogReceived += message => Dispatcher.UIThread.Post(() => AddStatus(message));
        _worker.ProgressReceived += progress => Dispatcher.UIThread.Post(() => AddStatus($"[{progress.Level}] {progress.Message}"));

        Opened += async (_, _) => await InitializeRuntimeAsync();
        Closing += (_, _) => _ = _worker.DisposeAsync();

        LanguageComboBox.SelectionChanged += (_, _) =>
        {
            _language = LanguageComboBox.SelectedIndex == 1 ? "en" : "de";
            _worker.Language = _language;
            ApplyLanguage();
        };

        RetryRuntimeButton.Click += async (_, _) => await InitializeRuntimeAsync();
        ConnectButton.Click += async (_, _) => await ConnectAsync("browser");
        DeviceConnectButton.Click += async (_, _) => await ConnectAsync("device");
        ConfigureButton.Click += async (_, _) => await ConfigureAsync();
        TestButton.Click += async (_, _) => await TestAsync();
        DisconnectButton.Click += async (_, _) => await DisconnectAsync();

        _worker.Language = _language;
        ApplyLanguage();
        SetActionButtons();
    }

    private string T(string de, string en) => _language == "en" ? en : de;

    private void ApplyLanguage()
    {
        Title = T(
            "Entra App – Mail.Send auf eine Shared Mailbox beschränken",
            "Entra App – Restrict Mail.Send to one Shared Mailbox");

        TitleText.Text = Title;
        SubtitleText.Text = T(
            "Cross-Platform GUI · Exchange Online RBAC for Applications · Windows / macOS / Linux",
            "Cross-platform GUI · Exchange Online RBAC for Applications · Windows / macOS / Linux");

        LanguageLabel.Text = T("Sprache", "Language");
        SecurityHeadingText.Text = T("SICHERHEIT", "SECURITY");
        SecurityBodyText.Text = T(
            "Für eine wirksame Exchange-RBAC-Begrenzung darf dieselbe App nicht zusätzlich tenantweit Microsoft Graph → Mail.Send (Application) besitzen. Das Tool fragt niemals nach dem Admin-Kennwort; Anmeldung und MFA erfolgen ausschließlich über Microsoft.",
            "For the Exchange RBAC restriction to be effective, the same app must not also have tenant-wide Microsoft Graph → Mail.Send (Application). The tool never asks for the admin password; sign-in and MFA are handled exclusively by Microsoft.");

        RuntimeLabel.Text = T("Laufzeit:", "Runtime:");
        RetryRuntimeButton.Content = T("Erneut prüfen", "Check again");

        AdminLabel.Text = T("1. Admin-Konto:", "1. Admin account:");
        AppIdLabel.Text = "2. Application (Client) ID:";
        ObjectIdLabel.Text = "3. Enterprise App Object ID:";
        ObjectIdHintText.Text = T(
            "Wichtig: Object ID aus Entra ID → Enterprise applications verwenden, nicht die Object ID aus App registrations.",
            "Important: Use the Object ID from Entra ID → Enterprise applications, not the Object ID from App registrations.");
        MailboxLabel.Text = "4. Shared Mailbox:";

        TenantMailSendCheckBox.Content = T(
            "Ich bestätige: Tenantweites Microsoft Graph → Mail.Send (Application) ist für diese App entfernt bzw. nicht erteilt.",
            "I confirm: Tenant-wide Microsoft Graph → Mail.Send (Application) has been removed or is not granted for this app.");

        ConfigureButton.Content = T("Zugriff einrichten", "Configure access");
        TestButton.Content = T("Zugriff testen", "Test access");
        DisconnectButton.Content = T("Verbindung trennen", "Disconnect");
        StatusLabel.Text = T("Status / Protokoll", "Status / Log");

        if (_runtimeReady && !string.IsNullOrWhiteSpace(_runtimeSummary))
            RuntimeStatusText.Text = _runtimeSummary;
        else if (!_runtimeReady)
            RuntimeStatusText.Text = T("PowerShell-Backend wird geprüft …", "Checking PowerShell backend …");

        var admin = AdminTextBox.Text?.Trim() ?? string.Empty;
        ConnectionStatusText.Text = _connected
            ? T($"Verbunden: {admin}", $"Connected: {admin}")
            : T("Nicht verbunden", "Not connected");
    }

    private async Task InitializeRuntimeAsync()
    {
        SetBusy(true);
        RuntimeStatusText.Text = T(
            "PowerShell und ExchangeOnlineManagement werden geprüft …",
            "Checking PowerShell and ExchangeOnlineManagement …");
        RetryRuntimeButton.IsVisible = false;
        AddStatus(T(
            "Starte Cross-Platform PowerShell-Backend …",
            "Starting cross-platform PowerShell backend …"));

        try
        {
            await _worker.StartAsync();
            var response = await _worker.SendAsync(
                "init",
                new { installIfMissing = true, language = _language },
                TimeSpan.FromMinutes(5));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            var platform = ReadString(response.Data, "platform") ?? T("unbekannt", "unknown");
            var psVersion = ReadString(response.Data, "powerShellVersion") ?? T("unbekannt", "unknown");
            var moduleVersion = ReadString(response.Data, "moduleVersion") ?? T("unbekannt", "unknown");

            _runtimeSummary = $"{platform} · PowerShell {psVersion} · ExchangeOnlineManagement {moduleVersion}";
            RuntimeStatusText.Text = _runtimeSummary;
            _runtimeReady = true;
            AddStatus(T("[OK] Laufzeit ist bereit.", "[OK] Runtime is ready."));
        }
        catch (Exception ex)
        {
            _runtimeReady = false;
            RuntimeStatusText.Text = T("Laufzeitprüfung fehlgeschlagen", "Runtime check failed");
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
            AddStatus(T(
                "[ERROR] Bitte ein gültiges Admin-Konto eingeben.",
                "[ERROR] Please enter a valid admin account."));
            return;
        }

        SetBusy(true);
        AddStatus(mode == "device"
            ? T("Starte Microsoft Device-Code-Anmeldung …", "Starting Microsoft device-code sign-in …")
            : T($"Öffne Microsoft-Anmeldung für {admin} …", $"Opening Microsoft sign-in for {admin} …"));

        try
        {
            var response = await _worker.SendAsync(
                "connect",
                new { adminUpn = admin, mode, language = _language },
                TimeSpan.FromMinutes(10));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            _connected = true;
            ConnectionStatusText.Text = T($"Verbunden: {admin}", $"Connected: {admin}");
            ConnectionStatusText.Foreground = Brushes.Green;
            AddStatus(T(
                "[OK] Verbindung zu Exchange Online erfolgreich.",
                "[OK] Connected to Exchange Online successfully."));
        }
        catch (Exception ex)
        {
            _connected = false;
            ConnectionStatusText.Text = T("Nicht verbunden", "Not connected");
            ConnectionStatusText.Foreground = Brushes.DarkRed;
            AddStatus($"[ERROR] {ex.Message}");

            if (mode == "browser")
                AddStatus(T(
                    "Hinweis: Falls der Browser-Login auf diesem System nicht funktioniert, 'Device Code' verwenden.",
                    "Note: If browser sign-in does not work on this system, use 'Device Code'."));
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
            AddStatus(T(
                "[ERROR] Die Sicherheitsbestätigung muss vor der Konfiguration aktiviert werden.",
                "[ERROR] The security confirmation must be selected before configuration."));
            return;
        }

        SetBusy(true);
        AddStatus(T(
            "Richte Exchange Application RBAC ein …",
            "Configuring Exchange Application RBAC …"));

        try
        {
            var response = await _worker.SendAsync(
                "configure",
                new
                {
                    appId = config.AppId,
                    objectId = config.ObjectId,
                    mailbox = config.Mailbox,
                    tenantWideMailSendRemoved = true,
                    language = _language
                },
                TimeSpan.FromMinutes(5));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            AddStatus(T(
                "[OK] Exchange-RBAC-Konfiguration wurde eingerichtet.",
                "[OK] Exchange RBAC configuration completed."));

            var scope = ReadString(response.Data, "scopeName");
            var assignment = ReadString(response.Data, "assignmentName");
            if (!string.IsNullOrWhiteSpace(scope)) AddStatus($"Scope: {scope}");
            if (!string.IsNullOrWhiteSpace(assignment)) AddStatus($"Role Assignment: {assignment}");

            AddStatus(T(
                "Starte automatische Sicherheitsprüfung …",
                "Starting automatic security check …"));
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
        AddStatus(T(
            $"Teste Application Mail.Send für {config.Mailbox} …",
            $"Testing Application Mail.Send for {config.Mailbox} …"));

        try
        {
            var response = await _worker.SendAsync(
                "test",
                new
                {
                    appId = config.AppId,
                    objectId = config.ObjectId,
                    mailbox = config.Mailbox,
                    language = _language
                },
                TimeSpan.FromMinutes(3));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            AddStatus(T(
                $"[OK] GRANTED: Application Mail.Send ist für {config.Mailbox} im erwarteten Scope.",
                $"[OK] GRANTED: Application Mail.Send is in the expected scope for {config.Mailbox}."));
            AddStatus(T(
                "Hinweis: Dieser Test prüft Exchange Application RBAC. Tenantweite Entra API Permissions müssen separat ausgeschlossen sein.",
                "Note: This test checks Exchange Application RBAC. Tenant-wide Entra API permissions must be ruled out separately."));
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
            var response = await _worker.SendAsync(
                "disconnect",
                new { language = _language },
                TimeSpan.FromMinutes(1));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            _connected = false;
            ConnectionStatusText.Text = T("Nicht verbunden", "Not connected");
            ConnectionStatusText.Foreground = Brushes.DarkRed;
            AddStatus(T(
                "[OK] Exchange-Online-Verbindung getrennt.",
                "[OK] Disconnected from Exchange Online."));
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
            error = T(
                "Application (Client) ID fehlt oder ist keine gültige GUID.",
                "Application (Client) ID is missing or is not a valid GUID.");
            return false;
        }

        if (!Guid.TryParse(configuration.ObjectId, out _))
        {
            error = T(
                "Enterprise App Object ID fehlt oder ist keine gültige GUID.",
                "Enterprise App Object ID is missing or is not a valid GUID.");
            return false;
        }

        if (!LooksLikeMailAddress(configuration.Mailbox))
        {
            error = T(
                "Shared Mailbox fehlt oder ist keine gültige E-Mail-Adresse.",
                "Shared Mailbox is missing or is not a valid email address.");
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
        LanguageComboBox.IsEnabled = !busy;
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
