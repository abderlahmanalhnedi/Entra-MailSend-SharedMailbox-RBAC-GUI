#requires -Version 5.1
<#
.SYNOPSIS
    GUI-Assistent zum Beschraenken einer Entra-Anwendung auf Mail.Send fuer genau eine Shared Mailbox
    mit Exchange Online RBAC for Applications.

.SECURITY
    - Es gibt bewusst KEIN Passwortfeld.
    - Die Anmeldung erfolgt ueber Connect-ExchangeOnline (Modern Authentication / MFA / Conditional Access).
    - Das Skript speichert keine Kennwoerter, Tokens oder Client Secrets.
    - Fuer eine wirksame RBAC-Begrenzung darf Mail.Send (Application) NICHT zusaetzlich tenantweit
      als Microsoft-Entra-API-Berechtigung erteilt sein. Entra- und Exchange-RBAC-Berechtigungen sind additiv.

.REQUIREMENTS
    - Windows PowerShell 5.1 oder PowerShell 7 unter Windows
    - Internetzugriff auf Microsoft 365 / PowerShell Gallery
    - Exchange Administrator in Entra ID
    - Fuer das Zuweisen der Application-RBAC-Rolle: Mitglied der Exchange-Rollengruppe Organization Management
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Dieses GUI-Skript ist fuer Windows vorgesehen.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ExchangeConnected = $false
$script:LastScopeName = $null
$script:LastMailbox = $null
$script:LastServicePrincipalObjectId = $null

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Information','Warning','Error')][string]$Type = 'Information',
        [string]$Title = 'Entra Mail.Send Assistent'
    )

    $icon = switch ($Type) {
        'Warning' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'   { [System.Windows.Forms.MessageBoxIcon]::Error }
        default   { [System.Windows.Forms.MessageBoxIcon]::Information }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = 'Bestaetigung'
    )

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Add-Status {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO'
    )

    $stamp = (Get-Date).ToString('HH:mm:ss')
    $statusBox.AppendText("[$stamp] [$Level] $Message`r`n")
    $statusBox.SelectionStart = $statusBox.TextLength
    $statusBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy {
    param([bool]$Busy)

    $form.UseWaitCursor = $Busy
    $btnConnect.Enabled = -not $Busy
    $btnConfigure.Enabled = -not $Busy
    $btnTest.Enabled = -not $Busy
    $btnDisconnect.Enabled = -not $Busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Test-GuidText {
    param([string]$Value)
    $parsed = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$parsed)
}

function Get-SafeName {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Alias,
        [ValidateSet('Scope','Assignment')][string]$Type
    )

    $shortApp = $AppId.Substring(0, 8)
    $safeAlias = ($Alias -replace '[^A-Za-z0-9_-]', '_')
    $prefix = if ($Type -eq 'Scope') { 'AppMailSend-Scope' } else { 'AppMailSend-Role' }
    $name = "$prefix-$shortApp-$safeAlias"
    if ($name.Length -gt 64) {
        $name = $name.Substring(0, 64)
    }
    return $name
}

function Ensure-ExchangeOnlineModule {
    $module = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $module) {
        Add-Status 'ExchangeOnlineManagement ist nicht installiert.' 'WARN'

        $ok = Confirm-Action -Text (
            "Das PowerShell-Modul 'ExchangeOnlineManagement' fehlt.`r`n`r`n" +
            "Soll es jetzt fuer den aktuellen Benutzer aus der PowerShell Gallery installiert werden?"
        ) -Title 'Modul installieren'

        if (-not $ok) {
            throw 'Installation wurde abgebrochen.'
        }

        Add-Status 'Installiere ExchangeOnlineManagement fuer CurrentUser ...' 'INFO'
        try {
            if ($PSVersionTable.PSVersion.Major -le 5) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            }
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
        catch {
            throw "ExchangeOnlineManagement konnte nicht installiert werden: $($_.Exception.Message)"
        }

        Add-Status 'ExchangeOnlineManagement wurde installiert.' 'OK'
    }
    else {
        Add-Status "ExchangeOnlineManagement $($module.Version) gefunden." 'OK'
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop
}

function Ensure-Connected {
    if (-not $script:ExchangeConnected) {
        throw 'Bitte zuerst mit Exchange Online verbinden.'
    }
}

function Get-ValidatedInput {
    $admin = $txtAdmin.Text.Trim()
    $appId = $txtAppId.Text.Trim()
    $objectId = $txtObjectId.Text.Trim()
    $mailbox = $txtMailbox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($admin)) {
        throw 'Bitte das Admin-Konto eintragen.'
    }
    if ([string]::IsNullOrWhiteSpace($appId) -or -not (Test-GuidText $appId)) {
        throw 'Bitte eine gueltige Application (Client) ID eintragen.'
    }
    if ([string]::IsNullOrWhiteSpace($objectId) -or -not (Test-GuidText $objectId)) {
        throw 'Bitte eine gueltige Object ID der Enterprise Application eintragen.'
    }
    if ([string]::IsNullOrWhiteSpace($mailbox) -or $mailbox -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw 'Bitte eine gueltige E-Mail-Adresse der Shared Mailbox eintragen.'
    }

    return [pscustomobject]@{
        AdminUPN = $admin
        AppId = $appId
        ObjectId = $objectId
        Mailbox = $mailbox
    }
}

function Connect-ExchangeSafely {
    Set-Busy $true
    try {
        $admin = $txtAdmin.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($admin)) {
            throw 'Bitte zuerst das Admin-Konto eintragen.'
        }

        Ensure-ExchangeOnlineModule
        Add-Status "Oeffne Microsoft-Anmeldung fuer $admin ..." 'INFO'
        Add-Status 'Kennwort/MFA werden ausschliesslich von Microsoft abgefragt, nicht von diesem Skript.' 'INFO'

        Connect-ExchangeOnline -UserPrincipalName $admin -ShowBanner:$false -ErrorAction Stop
        $script:ExchangeConnected = $true
        $lblConnection.Text = "Verbunden: $admin"
        $lblConnection.ForeColor = [System.Drawing.Color]::DarkGreen
        Add-Status 'Verbindung zu Exchange Online erfolgreich.' 'OK'
    }
    catch {
        $script:ExchangeConnected = $false
        $lblConnection.Text = 'Nicht verbunden'
        $lblConnection.ForeColor = [System.Drawing.Color]::DarkRed
        Add-Status $_.Exception.Message 'ERROR'
        Show-Message -Text $_.Exception.Message -Type Error
    }
    finally {
        Set-Busy $false
    }
}

function Configure-MailSendScope {
    Set-Busy $true
    try {
        Ensure-Connected
        $data = Get-ValidatedInput

        if (-not $chkNoTenantMailSend.Checked) {
            throw (
                "Sicherheitspruefung nicht bestaetigt.`r`n`r`n" +
                "Bei Exchange RBAC for Applications darf 'Mail.Send (Application)' nicht zusaetzlich tenantweit " +
                "in Microsoft Entra erteilt sein. Sonst waere die effektive Berechtigung nicht auf diese Mailbox beschraenkt."
            )
        }

        Add-Status "Pruefe Shared Mailbox $($data.Mailbox) ..." 'INFO'
        $mbx = Get-Mailbox -Identity $data.Mailbox -ErrorAction Stop

        if ($mbx.RecipientTypeDetails -ne 'SharedMailbox') {
            throw "'$($data.Mailbox)' ist keine Shared Mailbox (gefunden: $($mbx.RecipientTypeDetails))."
        }
        if ([string]::IsNullOrWhiteSpace([string]$mbx.ExternalDirectoryObjectId)) {
            throw 'ExternalDirectoryObjectId der Shared Mailbox konnte nicht ermittelt werden.'
        }
        Add-Status "Shared Mailbox gefunden: $($mbx.DisplayName)" 'OK'

        $scopeName = Get-SafeName -AppId $data.AppId -Alias $mbx.Alias -Type Scope
        $assignmentName = Get-SafeName -AppId $data.AppId -Alias $mbx.Alias -Type Assignment
        $externalId = [string]$mbx.ExternalDirectoryObjectId
        $recipientFilter = "ExternalDirectoryObjectId -eq '$externalId'"

        Add-Status "Pruefe Exchange-Service-Principal fuer App $($data.AppId) ..." 'INFO'
        $exoSp = @(Get-ServicePrincipal -Identity $data.AppId -ErrorAction SilentlyContinue) |
            Where-Object { [string]$_.AppId -eq $data.AppId } |
            Select-Object -First 1

        if ($exoSp) {
            if ([string]$exoSp.ObjectId -ne $data.ObjectId) {
                throw (
                    "In Exchange existiert fuer diese App bereits ein Service Principal, aber mit einer anderen Object ID.`r`n" +
                    "Exchange: $($exoSp.ObjectId)`r`nEingabe:  $($data.ObjectId)`r`n`r`n" +
                    "Bitte die Object ID unter Entra ID > Enterprise applications pruefen."
                )
            }
            Add-Status 'Exchange-Service-Principal existiert bereits.' 'OK'
        }
        else {
            Add-Status 'Erstelle Exchange-Verweis auf den Entra Service Principal ...' 'INFO'
            $displayName = "Mail.Send scoped - $($mbx.PrimarySmtpAddress)"
            $exoSp = New-ServicePrincipal -AppId $data.AppId -ObjectId $data.ObjectId -DisplayName $displayName -ErrorAction Stop
            Add-Status 'Exchange-Service-Principal wurde erstellt.' 'OK'
        }

        Add-Status "Pruefe Management Scope '$scopeName' ..." 'INFO'
        $existingScope = Get-ManagementScope -ErrorAction Stop |
            Where-Object { $_.Name -eq $scopeName } |
            Select-Object -First 1
        if ($existingScope) {
            if ([string]$existingScope.RecipientFilter -ne $recipientFilter) {
                throw (
                    "Der Management Scope '$scopeName' existiert bereits, zeigt aber auf einen anderen Filter.`r`n" +
                    "Aus Sicherheitsgruenden wird er nicht automatisch veraendert."
                )
            }
            Add-Status 'Management Scope existiert bereits und ist korrekt.' 'OK'
        }
        else {
            New-ManagementScope -Name $scopeName -RecipientRestrictionFilter $recipientFilter -ErrorAction Stop | Out-Null
            Add-Status "Management Scope fuer genau diese Shared Mailbox wurde erstellt." 'OK'
        }

        Add-Status "Pruefe Rollen-Zuweisung '$assignmentName' ..." 'INFO'
        $existingAssignment = Get-ManagementRoleAssignment -Role 'Application Mail.Send' -ErrorAction Stop |
            Where-Object { $_.Name -eq $assignmentName } |
            Select-Object -First 1
        if ($existingAssignment) {
            Add-Status 'Rollen-Zuweisung existiert bereits.' 'OK'
        }
        else {
            New-ManagementRoleAssignment `
                -Name $assignmentName `
                -App $data.ObjectId `
                -Role 'Application Mail.Send' `
                -CustomResourceScope $scopeName `
                -ErrorAction Stop | Out-Null
            Add-Status 'Application Mail.Send wurde mit dem Mailbox-Scope zugewiesen.' 'OK'
        }

        $script:LastScopeName = $scopeName
        $script:LastMailbox = [string]$mbx.PrimarySmtpAddress
        $script:LastServicePrincipalObjectId = $data.ObjectId

        Add-Status 'Konfiguration abgeschlossen. Starte Sicherheits-Test ...' 'INFO'
        Test-MailSendScope -Quiet

        Show-Message -Text (
            "Die Exchange-RBAC-Konfiguration wurde erfolgreich eingerichtet.`r`n`r`n" +
            "App: $($data.AppId)`r`n" +
            "Shared Mailbox: $($mbx.PrimarySmtpAddress)`r`n" +
            "Rolle: Application Mail.Send`r`n" +
            "Scope: $scopeName`r`n`r`n" +
            "WICHTIG: Tenantweites 'Mail.Send (Application)' in Entra darf nicht parallel erteilt sein."
        ) -Type Information -Title 'Erfolgreich'
    }
    catch {
        Add-Status $_.Exception.Message 'ERROR'
        Show-Message -Text $_.Exception.Message -Type Error
    }
    finally {
        Set-Busy $false
    }
}

function Test-MailSendScope {
    param([switch]$Quiet)

    if (-not $Quiet) { Set-Busy $true }
    try {
        Ensure-Connected
        $data = Get-ValidatedInput

        Add-Status "Teste Exchange-RBAC-Autorisierung fuer $($data.Mailbox) ..." 'INFO'
        $result = Test-ServicePrincipalAuthorization -Identity $data.ObjectId -Resource $data.Mailbox -ErrorAction Stop

        $mailSend = $result | Where-Object {
            $_.RoleName -eq 'Application Mail.Send' -or
            ([string]$_.GrantedPermissions -match '(^|,|\s)Mail\.Send($|,|\s)')
        }

        if (-not $mailSend) {
            throw 'Keine Exchange-RBAC-Zuweisung fuer Application Mail.Send gefunden.'
        }

        $inScope = @($mailSend | Where-Object { $_.InScope -eq $true -or [string]$_.InScope -eq 'True' })
        if ($inScope.Count -gt 0) {
            Add-Status "GRANTED: Application Mail.Send ist fuer $($data.Mailbox) im Scope." 'OK'

            # Zusaetzliche Exchange-RBAC-Mail.Send-Zuweisungen erkennen.
            # Hinweis: Microsoft-Entra-API-Permissions werden von diesem Test bewusst nicht erfasst.
            $allAuth = Test-ServicePrincipalAuthorization -Identity $data.ObjectId -ErrorAction Stop
            $allMailSend = @($allAuth | Where-Object {
                $_.RoleName -eq 'Application Mail.Send' -or
                $_.RoleName -eq 'Application Mail Full Access' -or
                $_.RoleName -eq 'Application Exchange Full Access' -or
                ([string]$_.GrantedPermissions -match 'Mail\.Send')
            })

            $testMailbox = Get-Mailbox -Identity $data.Mailbox -ErrorAction Stop
            $expectedScopeName = Get-SafeName -AppId $data.AppId -Alias $testMailbox.Alias -Type Scope

            $unexpected = @($allMailSend | Where-Object {
                [string]::IsNullOrWhiteSpace([string]$_.AllowedResourceScope) -or
                [string]$_.AllowedResourceScope -ne $expectedScopeName
            })
            if ($unexpected.Count -gt 0) {
                $otherScopes = ($unexpected | ForEach-Object {
                    $scopeText = if ([string]::IsNullOrWhiteSpace([string]$_.AllowedResourceScope)) { '<kein Scope / unscoped>' } else { [string]$_.AllowedResourceScope }
                    "$($_.RoleName): $scopeText"
                }) -join "`r`n"
                throw (
                    "Es wurden weitere Exchange-RBAC-Berechtigungen mit Mail.Send gefunden.`r`n`r`n" +
                    "$otherScopes`r`n`r`n" +
                    "Damit koennte die App Zugriff ausserhalb der vorgesehenen Shared Mailbox haben. Bitte diese Zuweisungen pruefen."
                )
            }

            if (-not $Quiet) {
                Show-Message -Text (
                    "Test erfolgreich.`r`n`r`n" +
                    "Application Mail.Send ist fuer die Shared Mailbox '$($data.Mailbox)' im Exchange-RBAC-Scope.`r`n`r`n" +
                    "Hinweis: Test-ServicePrincipalAuthorization prueft die Exchange-RBAC-Zuweisung. " +
                    "Tenantweite Entra-Berechtigungen muessen separat ausgeschlossen sein."
                ) -Type Information -Title 'Zugriff: GRANTED'
            }
        }
        else {
            throw "Application Mail.Send ist vorhanden, aber '$($data.Mailbox)' ist laut Test nicht im Scope."
        }
    }
    catch {
        Add-Status $_.Exception.Message 'ERROR'
        if (-not $Quiet) {
            Show-Message -Text $_.Exception.Message -Type Error -Title 'Test fehlgeschlagen'
        }
        else {
            throw
        }
    }
    finally {
        if (-not $Quiet) { Set-Busy $false }
    }
}

function Disconnect-ExchangeSafely {
    Set-Busy $true
    try {
        if ($script:ExchangeConnected) {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        }
        $script:ExchangeConnected = $false
        $lblConnection.Text = 'Nicht verbunden'
        $lblConnection.ForeColor = [System.Drawing.Color]::DarkRed
        Add-Status 'Exchange-Online-Verbindung getrennt.' 'INFO'
    }
    finally {
        Set-Busy $false
    }
}

# ----------------------------- GUI -----------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Entra App - Mail.Send auf eine Shared Mailbox beschraenken'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(820, 720)
$form.MinimumSize = New-Object System.Drawing.Size(820, 720)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Entra App - Mail.Send auf eine Shared Mailbox beschraenken'
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.Size = New-Object System.Drawing.Size(750, 32)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Exchange Online RBAC for Applications | Kein Passwort wird vom Skript abgefragt oder gespeichert.'
$subtitle.Location = New-Object System.Drawing.Point(26, 53)
$subtitle.Size = New-Object System.Drawing.Size(750, 24)
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($subtitle)

$securityPanel = New-Object System.Windows.Forms.Panel
$securityPanel.Location = New-Object System.Drawing.Point(24, 84)
$securityPanel.Size = New-Object System.Drawing.Size(755, 72)
$securityPanel.BorderStyle = 'FixedSingle'
$securityPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 225)
$form.Controls.Add($securityPanel)

$securityText = New-Object System.Windows.Forms.Label
$securityText.Location = New-Object System.Drawing.Point(12, 9)
$securityText.Size = New-Object System.Drawing.Size(725, 52)
$securityText.Text = "SICHERHEIT: Fuer die neue RBAC-Methode darf 'Mail.Send (Application)' nicht parallel tenantweit in Entra erteilt sein. Die Anmeldung erfolgt ueber Microsoft (Modern Auth/MFA); es gibt bewusst kein Passwortfeld."
$securityText.ForeColor = [System.Drawing.Color]::FromArgb(110, 70, 0)
$securityPanel.Controls.Add($securityText)

# Admin
$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.Text = '1. Admin-Konto:'
$lblAdmin.Location = New-Object System.Drawing.Point(24, 176)
$lblAdmin.Size = New-Object System.Drawing.Size(170, 22)
$form.Controls.Add($lblAdmin)

$txtAdmin = New-Object System.Windows.Forms.TextBox
$txtAdmin.Location = New-Object System.Drawing.Point(205, 173)
$txtAdmin.Size = New-Object System.Drawing.Size(360, 25)
$form.Controls.Add($txtAdmin)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = 'Mit Exchange Online verbinden'
$btnConnect.Location = New-Object System.Drawing.Point(580, 170)
$btnConnect.Size = New-Object System.Drawing.Size(198, 31)
$form.Controls.Add($btnConnect)

$lblConnection = New-Object System.Windows.Forms.Label
$lblConnection.Text = 'Nicht verbunden'
$lblConnection.Location = New-Object System.Drawing.Point(205, 204)
$lblConnection.Size = New-Object System.Drawing.Size(570, 22)
$lblConnection.ForeColor = [System.Drawing.Color]::DarkRed
$form.Controls.Add($lblConnection)

# App ID
$lblAppId = New-Object System.Windows.Forms.Label
$lblAppId.Text = '2. Application (Client) ID:'
$lblAppId.Location = New-Object System.Drawing.Point(24, 244)
$lblAppId.Size = New-Object System.Drawing.Size(170, 22)
$form.Controls.Add($lblAppId)

$txtAppId = New-Object System.Windows.Forms.TextBox
$txtAppId.Location = New-Object System.Drawing.Point(205, 241)
$txtAppId.Size = New-Object System.Drawing.Size(573, 25)
$form.Controls.Add($txtAppId)

# Object ID
$lblObjectId = New-Object System.Windows.Forms.Label
$lblObjectId.Text = '3. Enterprise App Object ID:'
$lblObjectId.Location = New-Object System.Drawing.Point(24, 283)
$lblObjectId.Size = New-Object System.Drawing.Size(180, 22)
$form.Controls.Add($lblObjectId)

$txtObjectId = New-Object System.Windows.Forms.TextBox
$txtObjectId.Location = New-Object System.Drawing.Point(205, 280)
$txtObjectId.Size = New-Object System.Drawing.Size(573, 25)
$form.Controls.Add($txtObjectId)

$lblObjectHint = New-Object System.Windows.Forms.Label
$lblObjectHint.Text = 'Wichtig: Object ID der Enterprise Application, nicht die Object ID aus App registrations verwenden.'
$lblObjectHint.Location = New-Object System.Drawing.Point(205, 308)
$lblObjectHint.Size = New-Object System.Drawing.Size(573, 20)
$lblObjectHint.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblObjectHint)

# Mailbox
$lblMailbox = New-Object System.Windows.Forms.Label
$lblMailbox.Text = '4. Shared Mailbox:'
$lblMailbox.Location = New-Object System.Drawing.Point(24, 346)
$lblMailbox.Size = New-Object System.Drawing.Size(170, 22)
$form.Controls.Add($lblMailbox)

$txtMailbox = New-Object System.Windows.Forms.TextBox
$txtMailbox.Location = New-Object System.Drawing.Point(205, 343)
$txtMailbox.Size = New-Object System.Drawing.Size(573, 25)
$form.Controls.Add($txtMailbox)

$chkNoTenantMailSend = New-Object System.Windows.Forms.CheckBox
$chkNoTenantMailSend.Location = New-Object System.Drawing.Point(205, 382)
$chkNoTenantMailSend.Size = New-Object System.Drawing.Size(573, 44)
$chkNoTenantMailSend.Text = "Ich bestaetige: Tenantweites 'Microsoft Graph > Mail.Send (Application)' ist in Entra fuer diese App entfernt bzw. nicht erteilt."
$form.Controls.Add($chkNoTenantMailSend)

$btnConfigure = New-Object System.Windows.Forms.Button
$btnConfigure.Text = 'Zugriff einrichten'
$btnConfigure.Location = New-Object System.Drawing.Point(205, 438)
$btnConfigure.Size = New-Object System.Drawing.Size(180, 38)
$btnConfigure.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$form.Controls.Add($btnConfigure)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = 'Zugriff testen'
$btnTest.Location = New-Object System.Drawing.Point(395, 438)
$btnTest.Size = New-Object System.Drawing.Size(180, 38)
$form.Controls.Add($btnTest)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = 'Verbindung trennen'
$btnDisconnect.Location = New-Object System.Drawing.Point(585, 438)
$btnDisconnect.Size = New-Object System.Drawing.Size(193, 38)
$form.Controls.Add($btnDisconnect)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Status:'
$lblStatus.Location = New-Object System.Drawing.Point(24, 498)
$lblStatus.Size = New-Object System.Drawing.Size(100, 22)
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$form.Controls.Add($lblStatus)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Location = New-Object System.Drawing.Point(24, 522)
$statusBox.Size = New-Object System.Drawing.Size(754, 118)
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = 'Vertical'
$statusBox.BackColor = [System.Drawing.Color]::White
$statusBox.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($statusBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Erforderlich: Exchange Administrator + Berechtigung zum Zuweisen der Application-RBAC-Rolle (Organization Management).'
$footer.Location = New-Object System.Drawing.Point(24, 650)
$footer.Size = New-Object System.Drawing.Size(754, 22)
$footer.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($footer)

$btnConnect.Add_Click({ Connect-ExchangeSafely })
$btnConfigure.Add_Click({ Configure-MailSendScope })
$btnTest.Add_Click({ Test-MailSendScope })
$btnDisconnect.Add_Click({ Disconnect-ExchangeSafely })

$form.Add_FormClosing({
    if ($script:ExchangeConnected) {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    }
})

Add-Status 'Bereit. Schritt 1: Admin-Konto eintragen und mit Exchange Online verbinden.' 'INFO'
Add-Status 'Das Skript fragt niemals nach dem Admin-Kennwort.' 'INFO'

[void]$form.ShowDialog()
