#requires -Version 7.4
<#
.SYNOPSIS
    Cross-platform CLI assistant for limiting an Entra application to Application Mail.Send
    for exactly one Shared Mailbox using Exchange Online RBAC for Applications.

.DESCRIPTION
    Works with PowerShell 7.4+ on Windows, macOS and Linux.
    The script never asks for or stores an admin password. Authentication is handled by
    Connect-ExchangeOnline using Microsoft modern authentication / MFA / Conditional Access.

.SECURITY
    For the Exchange RBAC scope to be effective, the same app must NOT also have tenant-wide
    Microsoft Graph -> Mail.Send (Application) permission in Microsoft Entra ID.
    Entra permissions and Exchange Application RBAC permissions are additive.

.REQUIREMENTS
    - PowerShell 7.4 or newer
    - ExchangeOnlineManagement module
    - Exchange Administrator in Microsoft Entra ID
    - Permission to assign Exchange Application RBAC roles (for example Organization Management)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExchangeConnected = $false
$script:Config = [ordered]@{
    AdminUPN = ''
    AppId = ''
    ObjectId = ''
    Mailbox = ''
}

function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' Entra Mail.Send - Shared Mailbox RBAC CLI' -ForegroundColor Cyan
    Write-Host ' Windows | macOS | Linux' -ForegroundColor DarkCyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'SICHERHEIT:' -ForegroundColor Yellow
    Write-Host "- Kein Passwortfeld und keine Speicherung von Kennwoertern/Tokens." -ForegroundColor DarkYellow
    Write-Host "- Anmeldung erfolgt ueber Microsoft Modern Authentication / MFA." -ForegroundColor DarkYellow
    Write-Host "- Tenantweites Graph 'Mail.Send (Application)' darf fuer diese App nicht parallel bestehen." -ForegroundColor DarkYellow
    Write-Host ''
}

function Write-Status {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO'
    )

    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }

    $stamp = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$stamp] [$Level] $Message" -ForegroundColor $color
}

function Pause-Menu {
    [void](Read-Host "`nEnter druecken, um fortzufahren")
}

function Test-GuidText {
    param([string]$Value)
    $parsed = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$parsed)
}

function Test-MailAddress {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Get-PlatformName {
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'macOS' }
    if ($IsLinux)   { return 'Linux' }
    return 'Unbekannt'
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
    if ($name.Length -gt 64) { $name = $name.Substring(0, 64) }
    return $name
}

function Get-CompatibleExchangeModuleTarget {
    $psVersion = $PSVersionTable.PSVersion

    if ($psVersion -ge [version]'7.6.0') {
        return [pscustomobject]@{ Mode = 'Latest'; Version = $null }
    }

    if ($psVersion -ge [version]'7.4.0') {
        return [pscustomobject]@{ Mode = 'Pinned'; Version = [version]'3.9.2' }
    }

    throw 'Dieses CLI-Skript benoetigt PowerShell 7.4 oder neuer.'
}

function Ensure-ExchangeOnlineModule {
    $installed = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)
    $target = Get-CompatibleExchangeModuleTarget

    $usable = $null
    if ($target.Mode -eq 'Latest') {
        $usable = $installed | Select-Object -First 1
    }
    else {
        $usable = $installed | Where-Object { $_.Version -le $target.Version -and $_.Version -ge [version]'3.5.0' } | Select-Object -First 1
    }

    if (-not $usable) {
        Write-Status 'ExchangeOnlineManagement ist nicht in einer kompatiblen Version installiert.' 'WARN'

        if ($target.Mode -eq 'Pinned') {
            Write-Host "Fuer PowerShell $($PSVersionTable.PSVersion) wird ExchangeOnlineManagement $($target.Version) verwendet." -ForegroundColor Yellow
        }

        $answer = (Read-Host 'Modul jetzt fuer den aktuellen Benutzer installieren? [J/n]').Trim()
        if ($answer -match '^(n|nein|no)$') {
            throw 'Installation wurde vom Benutzer abgebrochen.'
        }

        Write-Status 'Installiere ExchangeOnlineManagement ...' 'INFO'
        if ($target.Mode -eq 'Pinned') {
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -RequiredVersion $target.Version -Force -AllowClobber
        }
        else {
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
        }

        $installed = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)
        if ($target.Mode -eq 'Pinned') {
            $usable = $installed | Where-Object { $_.Version -eq $target.Version } | Select-Object -First 1
        }
        else {
            $usable = $installed | Select-Object -First 1
        }

        if (-not $usable) {
            throw 'ExchangeOnlineManagement wurde installiert, konnte aber nicht gefunden werden.'
        }
    }

    Import-Module ExchangeOnlineManagement -RequiredVersion $usable.Version -Force
    Write-Status "ExchangeOnlineManagement $($usable.Version) geladen." 'OK'
}

function Ensure-Connected {
    if (-not $script:ExchangeConnected) {
        throw 'Bitte zuerst mit Exchange Online verbinden.'
    }
}

function Read-AdminUPN {
    if ([string]::IsNullOrWhiteSpace($script:Config.AdminUPN)) {
        $script:Config.AdminUPN = (Read-Host 'Admin-Konto (z. B. admin@contoso.com)').Trim()
    }

    if (-not (Test-MailAddress $script:Config.AdminUPN)) {
        throw 'Bitte ein gueltiges Admin-Konto im UPN-/E-Mail-Format eingeben.'
    }

    return $script:Config.AdminUPN
}

function Read-AppData {
    Write-Host ''
    Write-Host 'App- und Mailbox-Daten' -ForegroundColor Cyan
    Write-Host '----------------------' -ForegroundColor DarkCyan

    $appId = (Read-Host "Application (Client) ID [$($script:Config.AppId)]").Trim()
    if (-not [string]::IsNullOrWhiteSpace($appId)) { $script:Config.AppId = $appId }

    $objectId = (Read-Host "Enterprise App Object ID [$($script:Config.ObjectId)]").Trim()
    if (-not [string]::IsNullOrWhiteSpace($objectId)) { $script:Config.ObjectId = $objectId }

    $mailbox = (Read-Host "Shared Mailbox [$($script:Config.Mailbox)]").Trim()
    if (-not [string]::IsNullOrWhiteSpace($mailbox)) { $script:Config.Mailbox = $mailbox }

    Test-Config
    Write-Status 'Eingaben sind syntaktisch gueltig.' 'OK'
}

function Test-Config {
    if (-not (Test-GuidText $script:Config.AppId)) {
        throw 'Application (Client) ID fehlt oder ist keine gueltige GUID.'
    }
    if (-not (Test-GuidText $script:Config.ObjectId)) {
        throw 'Enterprise App Object ID fehlt oder ist keine gueltige GUID.'
    }
    if (-not (Test-MailAddress $script:Config.Mailbox)) {
        throw 'Shared Mailbox fehlt oder ist keine gueltige E-Mail-Adresse.'
    }
}

function Connect-ExchangeSafely {
    $admin = Read-AdminUPN
    Ensure-ExchangeOnlineModule

    Write-Status "Oeffne Microsoft-Anmeldung fuer $admin ..." 'INFO'
    Write-Status 'Kennwort/MFA werden ausschliesslich von Microsoft verarbeitet.' 'INFO'

    try {
        Connect-ExchangeOnline -UserPrincipalName $admin -ShowBanner:$false -ErrorAction Stop
        $script:ExchangeConnected = $true
        Write-Status 'Verbindung zu Exchange Online erfolgreich.' 'OK'
    }
    catch {
        $script:ExchangeConnected = $false
        Write-Status "Standard-Anmeldung fehlgeschlagen: $($_.Exception.Message)" 'ERROR'

        $fallback = (Read-Host 'Mit Device-Code-Anmeldung erneut versuchen? [j/N]').Trim()
        if ($fallback -match '^(j|ja|y|yes)$') {
            Write-Status 'Starte Microsoft Device-Code-Anmeldung ...' 'INFO'
            Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
            $script:ExchangeConnected = $true
            Write-Status 'Verbindung zu Exchange Online erfolgreich.' 'OK'
        }
        else {
            throw
        }
    }
}

function Confirm-SecurityRequirement {
    Write-Host ''
    Write-Host 'WICHTIGE SICHERHEITSBESTAETIGUNG' -ForegroundColor Yellow
    Write-Host "Fuer diese App darf in Entra kein tenantweites 'Microsoft Graph -> Mail.Send (Application)' aktiv sein." -ForegroundColor Yellow
    Write-Host 'Exchange RBAC und Entra API Permissions wirken additiv.' -ForegroundColor Yellow
    Write-Host ''

    $answer = (Read-Host "Zum Fortfahren 'JA' eingeben").Trim()
    if ($answer -notmatch '^(JA|YES)$') {
        throw 'Sicherheitsbestaetigung wurde nicht erteilt.'
    }
}

function Get-ValidatedMailbox {
    Test-Config
    Write-Status "Pruefe Shared Mailbox $($script:Config.Mailbox) ..." 'INFO'

    $mbx = Get-Mailbox -Identity $script:Config.Mailbox -ErrorAction Stop
    if ($mbx.RecipientTypeDetails -ne 'SharedMailbox') {
        throw "'$($script:Config.Mailbox)' ist keine Shared Mailbox (gefunden: $($mbx.RecipientTypeDetails))."
    }
    if ([string]::IsNullOrWhiteSpace([string]$mbx.ExternalDirectoryObjectId)) {
        throw 'ExternalDirectoryObjectId der Shared Mailbox konnte nicht ermittelt werden.'
    }

    Write-Status "Shared Mailbox gefunden: $($mbx.DisplayName)" 'OK'
    return $mbx
}

function Ensure-ExchangeServicePrincipal {
    param([Parameter(Mandatory)]$Mailbox)

    Write-Status "Pruefe Exchange-Service-Principal fuer App $($script:Config.AppId) ..." 'INFO'
    $exoSp = @(Get-ServicePrincipal -Identity $script:Config.AppId -ErrorAction SilentlyContinue) |
        Where-Object { [string]$_.AppId -eq $script:Config.AppId } |
        Select-Object -First 1

    if ($exoSp) {
        if ([string]$exoSp.ObjectId -ne $script:Config.ObjectId) {
            throw "In Exchange existiert fuer diese App bereits ein Service Principal mit einer anderen Object ID. Exchange: $($exoSp.ObjectId) | Eingabe: $($script:Config.ObjectId)"
        }
        Write-Status 'Exchange-Service-Principal existiert bereits.' 'OK'
        return $exoSp
    }

    $displayName = "Mail.Send scoped - $($Mailbox.PrimarySmtpAddress)"
    Write-Status 'Erstelle Exchange-Verweis auf den Entra Service Principal ...' 'INFO'
    $exoSp = New-ServicePrincipal -AppId $script:Config.AppId -ObjectId $script:Config.ObjectId -DisplayName $displayName -ErrorAction Stop
    Write-Status 'Exchange-Service-Principal wurde erstellt.' 'OK'
    return $exoSp
}

function Ensure-ManagementScope {
    param([Parameter(Mandatory)]$Mailbox)

    $scopeName = Get-SafeName -AppId $script:Config.AppId -Alias $Mailbox.Alias -Type Scope
    $externalId = [string]$Mailbox.ExternalDirectoryObjectId
    $recipientFilter = "ExternalDirectoryObjectId -eq '$externalId'"

    Write-Status "Pruefe Management Scope '$scopeName' ..." 'INFO'
    $existingScope = Get-ManagementScope -ErrorAction Stop |
        Where-Object { $_.Name -eq $scopeName } |
        Select-Object -First 1

    if ($existingScope) {
        if ([string]$existingScope.RecipientFilter -ne $recipientFilter) {
            throw "Der Management Scope '$scopeName' existiert bereits mit einem anderen Filter. Aus Sicherheitsgruenden wird er nicht automatisch veraendert."
        }
        Write-Status 'Management Scope existiert bereits und ist korrekt.' 'OK'
    }
    else {
        New-ManagementScope -Name $scopeName -RecipientRestrictionFilter $recipientFilter -ErrorAction Stop | Out-Null
        Write-Status 'Management Scope fuer genau diese Shared Mailbox wurde erstellt.' 'OK'
    }

    return $scopeName
}

function Ensure-MailSendAssignment {
    param(
        [Parameter(Mandatory)][string]$ScopeName,
        [Parameter(Mandatory)]$Mailbox
    )

    $assignmentName = Get-SafeName -AppId $script:Config.AppId -Alias $Mailbox.Alias -Type Assignment
    Write-Status "Pruefe Rollen-Zuweisung '$assignmentName' ..." 'INFO'

    $existingAssignment = Get-ManagementRoleAssignment -Role 'Application Mail.Send' -ErrorAction Stop |
        Where-Object { $_.Name -eq $assignmentName } |
        Select-Object -First 1

    if ($existingAssignment) {
        Write-Status 'Rollen-Zuweisung existiert bereits.' 'OK'
    }
    else {
        New-ManagementRoleAssignment `
            -Name $assignmentName `
            -App $script:Config.ObjectId `
            -Role 'Application Mail.Send' `
            -CustomResourceScope $ScopeName `
            -ErrorAction Stop | Out-Null

        Write-Status 'Application Mail.Send wurde mit dem Mailbox-Scope zugewiesen.' 'OK'
    }

    return $assignmentName
}

function Configure-MailSendScope {
    Ensure-Connected
    Test-Config
    Confirm-SecurityRequirement

    $mbx = Get-ValidatedMailbox
    [void](Ensure-ExchangeServicePrincipal -Mailbox $mbx)
    $scopeName = Ensure-ManagementScope -Mailbox $mbx
    $assignmentName = Ensure-MailSendAssignment -ScopeName $scopeName -Mailbox $mbx

    Write-Host ''
    Write-Status 'Konfiguration erfolgreich abgeschlossen.' 'OK'
    Write-Host "  App ID:          $($script:Config.AppId)" -ForegroundColor Gray
    Write-Host "  Shared Mailbox:  $($mbx.PrimarySmtpAddress)" -ForegroundColor Gray
    Write-Host "  Rolle:           Application Mail.Send" -ForegroundColor Gray
    Write-Host "  Scope:           $scopeName" -ForegroundColor Gray
    Write-Host "  Assignment:      $assignmentName" -ForegroundColor Gray
    Write-Host ''

    Test-MailSendScope
}

function Test-MailSendScope {
    Ensure-Connected
    Test-Config

    Write-Status "Teste Exchange-RBAC-Autorisierung fuer $($script:Config.Mailbox) ..." 'INFO'
    $result = Test-ServicePrincipalAuthorization -Identity $script:Config.ObjectId -Resource $script:Config.Mailbox -ErrorAction Stop

    $mailSend = @($result | Where-Object {
        $_.RoleName -eq 'Application Mail.Send' -or
        ([string]$_.GrantedPermissions -match '(^|,|\s)Mail\.Send($|,|\s)')
    })

    if ($mailSend.Count -eq 0) {
        throw 'Keine Exchange-RBAC-Zuweisung fuer Application Mail.Send gefunden.'
    }

    $inScope = @($mailSend | Where-Object { $_.InScope -eq $true -or [string]$_.InScope -eq 'True' })
    if ($inScope.Count -eq 0) {
        throw "Application Mail.Send ist vorhanden, aber '$($script:Config.Mailbox)' ist nicht im Scope."
    }

    $mbx = Get-Mailbox -Identity $script:Config.Mailbox -ErrorAction Stop
    $expectedScopeName = Get-SafeName -AppId $script:Config.AppId -Alias $mbx.Alias -Type Scope

    $allAuth = Test-ServicePrincipalAuthorization -Identity $script:Config.ObjectId -ErrorAction Stop
    $allMailSend = @($allAuth | Where-Object {
        $_.RoleName -eq 'Application Mail.Send' -or
        $_.RoleName -eq 'Application Mail Full Access' -or
        $_.RoleName -eq 'Application Exchange Full Access' -or
        ([string]$_.GrantedPermissions -match 'Mail\.Send')
    })

    $unexpected = @($allMailSend | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.AllowedResourceScope) -or
        [string]$_.AllowedResourceScope -ne $expectedScopeName
    })

    if ($unexpected.Count -gt 0) {
        Write-Status 'GRANTED fuer die gewuenschte Shared Mailbox, ABER weitere Exchange-RBAC-Mail.Send-Zuweisungen wurden gefunden.' 'WARN'
        foreach ($item in $unexpected) {
            $scopeText = if ([string]::IsNullOrWhiteSpace([string]$item.AllowedResourceScope)) { '<kein Scope / unscoped>' } else { [string]$item.AllowedResourceScope }
            Write-Host "  - $($item.RoleName): $scopeText" -ForegroundColor Yellow
        }
        throw 'Bitte die zusaetzlichen Exchange-RBAC-Zuweisungen pruefen, da sie den Zugriff erweitern koennen.'
    }

    Write-Status "GRANTED: Application Mail.Send ist fuer $($script:Config.Mailbox) im erwarteten Scope." 'OK'
    Write-Host "Hinweis: Dieser Test prueft nur Exchange Application RBAC. Tenantweite Entra API Permissions muessen separat ausgeschlossen sein." -ForegroundColor DarkYellow
}

function Show-CurrentConfig {
    Write-Host ''
    Write-Host 'Aktuelle Eingaben' -ForegroundColor Cyan
    Write-Host '------------------' -ForegroundColor DarkCyan
    Write-Host "Admin-Konto:              $($script:Config.AdminUPN)"
    Write-Host "Application (Client) ID:  $($script:Config.AppId)"
    Write-Host "Enterprise App Object ID: $($script:Config.ObjectId)"
    Write-Host "Shared Mailbox:            $($script:Config.Mailbox)"
    Write-Host "Exchange verbunden:        $($script:ExchangeConnected)"
    Write-Host "Plattform:                  $(Get-PlatformName)"
    Write-Host "PowerShell:                 $($PSVersionTable.PSVersion)"
}

function Disconnect-ExchangeSafely {
    if ($script:ExchangeConnected) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        $script:ExchangeConnected = $false
        Write-Status 'Exchange-Online-Verbindung getrennt.' 'OK'
    }
    else {
        Write-Status 'Keine aktive Exchange-Online-Verbindung vorhanden.' 'INFO'
    }
}

function Invoke-MenuAction {
    param([string]$Choice)

    switch ($Choice) {
        '1' { Connect-ExchangeSafely }
        '2' { Read-AppData }
        '3' { Configure-MailSendScope }
        '4' { Test-MailSendScope }
        '5' { Show-CurrentConfig }
        '6' { Disconnect-ExchangeSafely }
        '0' {
            if ($script:ExchangeConnected) { Disconnect-ExchangeSafely }
            return $false
        }
        default { Write-Status 'Ungueltige Auswahl.' 'WARN' }
    }

    return $true
}

try {
    do {
        Write-Banner
        Write-Host "Plattform: $(Get-PlatformName) | PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
        Write-Host "Exchange:  $(if ($script:ExchangeConnected) { 'Verbunden' } else { 'Nicht verbunden' })" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '[1] Mit Exchange Online verbinden'
        Write-Host '[2] App- und Mailbox-Daten eingeben'
        Write-Host '[3] Zugriff einrichten'
        Write-Host '[4] Zugriff testen'
        Write-Host '[5] Aktuelle Eingaben anzeigen'
        Write-Host '[6] Verbindung trennen'
        Write-Host '[0] Beenden'
        Write-Host ''

        $choice = (Read-Host 'Auswahl').Trim()

        try {
            $continue = Invoke-MenuAction -Choice $choice
        }
        catch {
            Write-Host ''
            Write-Status $_.Exception.Message 'ERROR'
            $continue = $true
        }

        if ($continue) { Pause-Menu }
    } while ($continue)
}
finally {
    if ($script:ExchangeConnected) {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    }
}
