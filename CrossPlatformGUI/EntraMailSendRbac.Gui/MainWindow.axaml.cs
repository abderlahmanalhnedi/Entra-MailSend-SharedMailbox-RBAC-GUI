using System.Text.Json;
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
            AddStatus(T("Sprache auf Deutsch geändert.", "Language changed to English."));
        };

        RetryRuntimeButton.Click += async (_, _) => await InitializeRuntimeAsync();
        ConnectButton.Click += async (_, _) => await ConnectAsync();
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
            "Mail.Send – Shared Mailbox RBAC",
            "Mail.Send – Shared Mailbox RBAC");

        TitleText.Text = Title;
        SubtitleText.Text = T(
            "Microsoft Entra + Exchange Online · sicher auf eine Shared Mailbox begrenzen",
            "Microsoft Entra + Exchange Online · securely restrict access to one Shared Mailbox");

        LanguageLabel.Text = T("Sprache", "Language");
        RuntimeLabel.Text = T("System:", "System:");
        RetryRuntimeButton.Content = T("Erneut prüfen", "Check again");

        Step1TitleText.Text = T("Mit Microsoft anmelden", "Sign in with Microsoft");
        Step1BodyText.Text = T(
            "Die Anmeldung läuft direkt über Microsoft. MFA, Passkeys und Conditional Access bleiben vollständig erhalten.",
            "Sign-in is handled directly by Microsoft. MFA, passkeys and Conditional Access remain fully supported.");
        AdminLabel.Text = T("Admin-Konto", "Admin account");
        ConnectButton.Content = T("Mit Microsoft anmelden", "Sign in with Microsoft");

        Step2TitleText.Text = T("App und Shared Mailbox", "App and Shared Mailbox");
        Step2BodyText.Text = T(
            "Trage die Entra-App und die Shared Mailbox ein, die Mail.Send erhalten soll.",
            "Enter the Entra app and the Shared Mailbox that should receive Mail.Send access.");
        AppIdLabel.Text = "Application (Client) ID";
        ObjectIdLabel.Text = "Enterprise App Object ID";
        ObjectIdHintText.Text = T(
            "Object ID aus Entra ID → Enterprise applications verwenden, nicht aus App registrations.",
            "Use the Object ID from Entra ID → Enterprise applications, not from App registrations.");
        MailboxLabel.Text = "Shared Mailbox";

        SecurityHeadingText.Text = T("Sicherheitsprüfung", "Security check");
        SecurityBodyText.Text = T(
            "Damit die Begrenzung wirklich gilt, darf diese App nicht zusätzlich tenantweit Microsoft Graph → Mail.Send (Application) besitzen.",
            "For the restriction to be effective, this app must not also have tenant-wide Microsoft Graph → Mail.Send (Application).");
        TenantMailSendCheckBox.Content = T(
            "Ich bestätige, dass tenantweites Mail.Send (Application) entfernt bzw. nicht erteilt ist.",
            "I confirm that tenant-wide Mail.Send (Application) has been removed or is not granted.");

        Step3TitleText.Text = T("Zugriff einrichten und prüfen", "Configure and verify access");
        Step3BodyText.Text = T(
            "Die App erstellt den Exchange-RBAC-Scope und führt danach automatisch einen Sicherheitstest aus.",
            "The app creates the Exchange RBAC scope and then automatically performs a security test.");
        ConfigureButton.Content = T("Zugriff einrichten", "Configure access");
        TestButton.Content = T("Zugriff testen", "Test access");
        DisconnectButton.Content = T("Abmelden", "Sign out");
        StatusLabel.Text = T("Details anzeigen", "Show details");

        if (_runtimeReady && !string.IsNullOrWhiteSpace(_runtimeSummary))
            RuntimeStatusText.Text = _runtimeSummary;
        else if (!_runtimeReady)
            RuntimeStatusText.Text = T("PowerShell-Backend wird geprüft …", "Checking PowerShell backend …");

        var admin = AdminTextBox.Text?.Trim() ?? string.Empty;
        ConnectionStatusText.Text = _connected
            ? T($"Verbunden als {admin}", $"Connected as {admin}")
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
            "Starte PowerShell-Backend …",
            "Starting PowerShell backend …"));

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
            AddStatus(T("[OK] System ist bereit.", "[OK] System is ready."));
        }
        catch (Exception ex)
        {
            _runtimeReady = false;
            RuntimeStatusText.Text = T("Systemprüfung fehlgeschlagen", "System check failed");
            RetryRuntimeButton.IsVisible = true;
            AddStatus($"[ERROR] {ex.Message}");
        }
        finally
        {
            SetBusy(false);
            SetActionButtons();
        }
    }

    private async Task ConnectAsync()
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
        AddStatus(T(
            $"Öffne Microsoft-Anmeldung für {admin} …",
            $"Opening Microsoft sign-in for {admin} …"));

        try
        {
            var response = await _worker.SendAsync(
                "connect",
                new { adminUpn = admin, mode = "browser", language = _language },
                TimeSpan.FromMinutes(10));

            if (!response.Success)
                throw new InvalidOperationException(response.Message);

            _connected = true;
            ConnectionStatusText.Text = T($"Verbunden als {admin}", $"Connected as {admin}");
            ConnectionStatusText.Foreground = new SolidColorBrush(Color.Parse("#138A5B"));
            AddStatus(T(
                "[OK] Anmeldung bei Exchange Online erfolgreich.",
                "[OK] Signed in to Exchange Online successfully."));
        }
        catch (Exception ex)
        {
            _connected = false;
            ConnectionStatusText.Text = T("Nicht verbunden", "Not connected");
            ConnectionStatusText.Foreground = new SolidColorBrush(Color.Parse("#C9372C"));
            AddStatus($"[ERROR] {ex.Message}");
            AddStatus(T(
                "Die Microsoft-Anmeldung konnte nicht abgeschlossen werden. Bitte erneut versuchen.",
                "Microsoft sign-in could not be completed. Please try again."));
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
                "[ERROR] Bitte zuerst die Sicherheitsbestätigung aktivieren.",
                "[ERROR] Please confirm the security requirement first."));
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
            $"Teste Mail.Send für {config.Mailbox} …",
            $"Testing Mail.Send for {config.Mailbox} …"));

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
                $"[OK] GRANTED: Mail.Send ist für {config.Mailbox} im erwarteten Scope.",
                $"[OK] GRANTED: Mail.Send is in the expected scope for {config.Mailbox}."));
            AddStatus(T(
                "Hinweis: Tenantweite Entra API Permissions müssen separat ausgeschlossen sein.",
                "Note: Tenant-wide Entra API permissions must be ruled out separately."));
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
            ConnectionStatusText.Foreground = new SolidColorBrush(Color.Parse("#C9372C"));
            AddStatus(T(
                "[OK] Von Exchange Online abgemeldet.",
                "[OK] Signed out from Exchange Online."));
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
        ConfigureButton.IsEnabled = !busy && _runtimeReady && _connected;
        TestButton.IsEnabled = !busy && _runtimeReady && _connected;
        DisconnectButton.IsEnabled = !busy && _runtimeReady && _connected;
    }

    private void SetActionButtons()
    {
        ConnectButton.IsEnabled = _runtimeReady;
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

        if (message.Contains("[ERROR]", StringComparison.OrdinalIgnoreCase))
            LogExpander.IsExpanded = true;
    }

    private static string? ReadString(JsonElement data, string propertyName)
    {
        if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty(propertyName, out var property))
            return property.ValueKind == JsonValueKind.String ? property.GetString() : property.ToString();
        return null;
    }

    private sealed record AppConfiguration(string AppId, string ObjectId, string Mailbox);
}
