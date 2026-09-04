#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ProtocolPrefix = '@@RBACGUI@@'
$script:ExchangeConnected = $false
$script:LoadedModuleVersion = $null
$script:Language = 'de'

function L {
    param(
        [Parameter(Mandatory)][string]$De,
        [Parameter(Mandatory)][string]$En
    )
    if ($script:Language -eq 'en') { return $En }
    return $De
}

function Send-Protocol {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][bool]$Success,
        [string]$Message = '',
        [object]$Data = $null
    )

    $payload = [ordered]@{
        type      = $Type
        requestId = $RequestId
        success   = $Success
        message   = $Message
        data      = $Data
    }

    $json = $payload | ConvertTo-Json -Compress -Depth 10
    [Console]::Out.WriteLine($ProtocolPrefix + $json)
    [Console]::Out.Flush()
}

function Send-Progress {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO'
    )

    Send-Protocol -Type 'progress' -RequestId $RequestId -Success $true -Message $Message -Data @{ level = $Level }
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
    return (L 'Unbekannt' 'Unknown')
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

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-CompatibleExchangeModule {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [bool]$InstallIfMissing = $true
    )

    if ($PSVersionTable.PSVersion -lt [version]'7.4.0') {
        throw (L 'PowerShell 7.4 oder neuer ist erforderlich.' 'PowerShell 7.4 or newer is required.')
    }

    $installed = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)

    if ($PSVersionTable.PSVersion -ge [version]'7.6.0') {
        $usable = $installed | Where-Object { $_.Version -ge [version]'3.10.0' } | Select-Object -First 1
        if (-not $usable) {
            # Older 3.5-3.9.2 modules still work with newer PowerShell in many environments,
            # but current Microsoft guidance pairs 3.10+ with PowerShell 7.6+.
            $usable = $installed | Where-Object { $_.Version -ge [version]'3.5.0' } | Select-Object -First 1
        }

        if (-not $usable -and $InstallIfMissing) {
            Send-Progress -RequestId $RequestId -Message (L 'ExchangeOnlineManagement fehlt. Installiere aktuelle Version für CurrentUser …' 'ExchangeOnlineManagement is missing. Installing the current version for CurrentUser …') -Level WARN
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            $installed = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending)
            $usable = $installed | Select-Object -First 1
        }
    }
    else {
        $usable = $installed |
            Where-Object { $_.Version -ge [version]'3.5.0' -and $_.Version -le [version]'3.9.2' } |
            Select-Object -First 1

        if (-not $usable -and $InstallIfMissing) {
            Send-Progress -RequestId $RequestId -Message (L 'Installiere ExchangeOnlineManagement 3.9.2 für PowerShell 7.4/7.5 …' 'Installing ExchangeOnlineManagement 3.9.2 for PowerShell 7.4/7.5 …') -Level WARN
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -RequiredVersion 3.9.2 -Force -AllowClobber -ErrorAction Stop
            $usable = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
                Where-Object { $_.Version -eq [version]'3.9.2' } |
                Select-Object -First 1
        }
    }

    if (-not $usable) {
        throw (L "Keine kompatible Version von ExchangeOnlineManagement gefunden. PowerShell: $($PSVersionTable.PSVersion)." "No compatible version of ExchangeOnlineManagement was found. PowerShell: $($PSVersionTable.PSVersion).")
    }

    Import-Module ExchangeOnlineManagement -RequiredVersion $usable.Version -Force -ErrorAction Stop
    $script:LoadedModuleVersion = [string]$usable.Version
    Send-Progress -RequestId $RequestId -Message (L "ExchangeOnlineManagement $($usable.Version) geladen." "ExchangeOnlineManagement $($usable.Version) loaded.") -Level OK
    return $usable
}

function Ensure-Connected {
    if (-not $script:ExchangeConnected) {
        throw (L 'Bitte zuerst mit Exchange Online verbinden.' 'Please connect to Exchange Online first.')
    }
}

function Validate-AppData {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$Mailbox
    )

    if (-not (Test-GuidText $AppId)) {
        throw (L 'Application (Client) ID fehlt oder ist keine gültige GUID.' 'Application (Client) ID is missing or is not a valid GUID.')
    }
    if (-not (Test-GuidText $ObjectId)) {
        throw (L 'Enterprise App Object ID fehlt oder ist keine gültige GUID.' 'Enterprise App Object ID is missing or is not a valid GUID.')
    }
    if (-not (Test-MailAddress $Mailbox)) {
        throw (L 'Shared Mailbox fehlt oder ist keine gültige E-Mail-Adresse.' 'Shared Mailbox is missing or is not a valid email address.')
    }
}

function Get-ValidatedMailbox {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$Mailbox
    )

    Send-Progress -RequestId $RequestId -Message (L "Prüfe Shared Mailbox $Mailbox …" "Checking Shared Mailbox $Mailbox …")
    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop

    if ($mbx.RecipientTypeDetails -ne 'SharedMailbox') {
        throw (L "'$Mailbox' ist keine Shared Mailbox (gefunden: $($mbx.RecipientTypeDetails))." "'$Mailbox' is not a Shared Mailbox (found: $($mbx.RecipientTypeDetails)).")
    }
    if ([string]::IsNullOrWhiteSpace([string]$mbx.ExternalDirectoryObjectId)) {
        throw (L 'ExternalDirectoryObjectId der Shared Mailbox konnte nicht ermittelt werden.' 'Could not determine the Shared Mailbox ExternalDirectoryObjectId.')
    }

    Send-Progress -RequestId $RequestId -Message (L "Shared Mailbox gefunden: $($mbx.DisplayName)" "Shared Mailbox found: $($mbx.DisplayName)") -Level OK
    return $mbx
}

function Ensure-ExchangeServicePrincipal {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)]$Mailbox
    )

    Send-Progress -RequestId $RequestId -Message (L "Prüfe Exchange-Service-Principal für App $AppId …" "Checking Exchange service principal for app $AppId …")

    $exoSp = @(Get-ServicePrincipal -Identity $AppId -ErrorAction SilentlyContinue) |
        Where-Object { [string]$_.AppId -eq $AppId } |
        Select-Object -First 1

    if ($exoSp) {
        if ([string]$exoSp.ObjectId -ne $ObjectId) {
            throw (L "Für diese App existiert in Exchange bereits ein Service Principal mit anderer Object ID. Exchange: $($exoSp.ObjectId) | Eingabe: $ObjectId" "A service principal already exists in Exchange for this app with a different Object ID. Exchange: $($exoSp.ObjectId) | Input: $ObjectId")
        }
        Send-Progress -RequestId $RequestId -Message (L 'Exchange-Service-Principal existiert bereits.' 'Exchange service principal already exists.') -Level OK
        return $exoSp
    }

    $displayName = "Mail.Send scoped - $($Mailbox.PrimarySmtpAddress)"
    Send-Progress -RequestId $RequestId -Message (L 'Erstelle Exchange-Verweis auf den Entra Service Principal …' 'Creating Exchange reference to the Entra service principal …')
    $exoSp = New-ServicePrincipal -AppId $AppId -ObjectId $ObjectId -DisplayName $displayName -ErrorAction Stop
    Send-Progress -RequestId $RequestId -Message (L 'Exchange-Service-Principal wurde erstellt.' 'Exchange service principal was created.') -Level OK
    return $exoSp
}

function Ensure-ManagementScope {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)]$Mailbox
    )

    $scopeName = Get-SafeName -AppId $AppId -Alias $Mailbox.Alias -Type Scope
    $externalId = [string]$Mailbox.ExternalDirectoryObjectId
    $recipientFilter = "ExternalDirectoryObjectId -eq '$externalId'"

    Send-Progress -RequestId $RequestId -Message (L "Prüfe Management Scope '$scopeName' …" "Checking management scope '$scopeName' …")
    $existingScope = Get-ManagementScope -ErrorAction Stop |
        Where-Object { $_.Name -eq $scopeName } |
        Select-Object -First 1

    if ($existingScope) {
        if ([string]$existingScope.RecipientFilter -ne $recipientFilter) {
            throw (L "Der Management Scope '$scopeName' existiert bereits mit einem anderen Filter. Er wird aus Sicherheitsgründen nicht automatisch verändert." "The management scope '$scopeName' already exists with a different filter. It will not be changed automatically for security reasons.")
        }
        Send-Progress -RequestId $RequestId -Message (L 'Management Scope existiert bereits und ist korrekt.' 'Management scope already exists and is correct.') -Level OK
    }
    else {
        New-ManagementScope -Name $scopeName -RecipientRestrictionFilter $recipientFilter -ErrorAction Stop | Out-Null
        Send-Progress -RequestId $RequestId -Message (L 'Management Scope für genau diese Shared Mailbox wurde erstellt.' 'Management scope for exactly this Shared Mailbox was created.') -Level OK
    }

    return $scopeName
}

function Ensure-MailSendAssignment {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$ScopeName,
        [Parameter(Mandatory)]$Mailbox
    )

    $assignmentName = Get-SafeName -AppId $AppId -Alias $Mailbox.Alias -Type Assignment
    Send-Progress -RequestId $RequestId -Message (L "Prüfe Rollen-Zuweisung '$assignmentName' …" "Checking role assignment '$assignmentName' …")

    $existingAssignment = Get-ManagementRoleAssignment -Role 'Application Mail.Send' -ErrorAction Stop |
        Where-Object { $_.Name -eq $assignmentName } |
        Select-Object -First 1

    if ($existingAssignment) {
        if (-not [string]::IsNullOrWhiteSpace([string]$existingAssignment.CustomResourceScope) -and
            [string]$existingAssignment.CustomResourceScope -ne $ScopeName) {
            throw (L "Die Rollen-Zuweisung '$assignmentName' existiert, verweist aber auf einen anderen Scope." "The role assignment '$assignmentName' exists but points to a different scope.")
        }
        Send-Progress -RequestId $RequestId -Message (L 'Rollen-Zuweisung existiert bereits.' 'Role assignment already exists.') -Level OK
    }
    else {
        New-ManagementRoleAssignment `
            -Name $assignmentName `
            -App $ObjectId `
            -Role 'Application Mail.Send' `
            -CustomResourceScope $ScopeName `
            -ErrorAction Stop | Out-Null

        Send-Progress -RequestId $RequestId -Message (L 'Application Mail.Send wurde mit dem Mailbox-Scope zugewiesen.' 'Application Mail.Send was assigned with the mailbox scope.') -Level OK
    }

    return $assignmentName
}

function Invoke-MailSendTest {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$Mailbox
    )

    Validate-AppData -AppId $AppId -ObjectId $ObjectId -Mailbox $Mailbox
    Ensure-Connected

    Send-Progress -RequestId $RequestId -Message (L "Teste Exchange-RBAC-Autorisierung für $Mailbox …" "Testing Exchange RBAC authorization for $Mailbox …")
    $result = Test-ServicePrincipalAuthorization -Identity $ObjectId -Resource $Mailbox -ErrorAction Stop

    $mailSend = @($result | Where-Object {
        $_.RoleName -eq 'Application Mail.Send' -or
        ([string]$_.GrantedPermissions -match '(^|,|\s)Mail\.Send($|,|\s)')
    })

    if ($mailSend.Count -eq 0) {
        throw (L 'Keine Exchange-RBAC-Zuweisung für Application Mail.Send gefunden.' 'No Exchange RBAC assignment for Application Mail.Send was found.')
    }

    $inScope = @($mailSend | Where-Object { $_.InScope -eq $true -or [string]$_.InScope -eq 'True' })
    if ($inScope.Count -eq 0) {
        throw (L "Application Mail.Send ist vorhanden, aber '$Mailbox' ist nicht im Scope." "Application Mail.Send exists, but '$Mailbox' is not in scope.")
    }

    $mbx = Get-Mailbox -Identity $Mailbox -ErrorAction Stop
    $expectedScopeName = Get-SafeName -AppId $AppId -Alias $mbx.Alias -Type Scope

    $allAuth = Test-ServicePrincipalAuthorization -Identity $ObjectId -ErrorAction Stop
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
        $details = @($unexpected | ForEach-Object {
            $scopeText = if ([string]::IsNullOrWhiteSpace([string]$_.AllowedResourceScope)) { (L '<kein Scope / unscoped>' '<no scope / unscoped>') } else { [string]$_.AllowedResourceScope }
            "$($_.RoleName): $scopeText"
        })
        throw (L "Weitere Exchange-RBAC-Berechtigungen mit Mail.Send wurden gefunden: $($details -join '; ')" "Additional Exchange RBAC permissions containing Mail.Send were found: $($details -join '; ')")
    }

    Send-Progress -RequestId $RequestId -Message (L "GRANTED: Application Mail.Send ist für $Mailbox im erwarteten Scope." "GRANTED: Application Mail.Send is in the expected scope for $Mailbox.") -Level OK
    return [ordered]@{
        granted   = $true
        scopeName = $expectedScopeName
        mailbox   = [string]$mbx.PrimarySmtpAddress
    }
}

function Invoke-Request {
    param([Parameter(Mandatory)]$Request)

    $requestId = [string](Get-PropertyValue -Object $Request -Name 'id' -Default '')
    $command = [string](Get-PropertyValue -Object $Request -Name 'command' -Default '')
    $data = Get-PropertyValue -Object $Request -Name 'data' -Default ([pscustomobject]@{})
    $requestedLanguage = [string](Get-PropertyValue -Object $data -Name 'language' -Default $script:Language)
    $script:Language = if ($requestedLanguage -eq 'en') { 'en' } else { 'de' }

    if ([string]::IsNullOrWhiteSpace($requestId)) {
        throw (L 'Request ID fehlt.' 'Request ID is missing.')
    }

    switch ($command) {
        'init' {
            $install = [bool](Get-PropertyValue -Object $data -Name 'installIfMissing' -Default $true)
            $module = Get-CompatibleExchangeModule -RequestId $requestId -InstallIfMissing:$install
            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Laufzeit ist bereit.' 'Runtime is ready.') -Data ([ordered]@{
                platform          = Get-PlatformName
                powerShellVersion = [string]$PSVersionTable.PSVersion
                moduleVersion     = [string]$module.Version
            })
        }

        'connect' {
            $adminUpn = [string](Get-PropertyValue -Object $data -Name 'adminUpn' -Default '')
            $mode = [string](Get-PropertyValue -Object $data -Name 'mode' -Default 'browser')

            if (-not (Test-MailAddress $adminUpn)) {
                throw (L 'Bitte ein gültiges Admin-Konto im UPN-/E-Mail-Format eingeben.' 'Please enter a valid admin account in UPN/email format.')
            }

            if (-not $script:LoadedModuleVersion) {
                [void](Get-CompatibleExchangeModule -RequestId $requestId -InstallIfMissing:$true)
            }

            if ($script:ExchangeConnected) {
                try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                $script:ExchangeConnected = $false
            }

            if ($mode -eq 'device') {
                Send-Progress -RequestId $requestId -Message (L 'Device-Code-Anmeldung wird gestartet. Den von Microsoft angezeigten Code im Statusbereich beachten.' 'Device-code sign-in is starting. Follow the code shown by Microsoft in the status area.')
                Connect-ExchangeOnline -Device -ShowBanner:$false -ShowProgress:$false -ErrorAction Stop
            }
            else {
                Send-Progress -RequestId $requestId -Message (L "Microsoft Browser-Anmeldung für $adminUpn wird geöffnet …" "Opening Microsoft browser sign-in for $adminUpn …")
                Connect-ExchangeOnline -UserPrincipalName $adminUpn -ShowBanner:$false -ShowProgress:$false -ErrorAction Stop
            }

            $script:ExchangeConnected = $true
            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Mit Exchange Online verbunden.' 'Connected to Exchange Online.') -Data @{ adminUpn = $adminUpn }
        }

        'configure' {
            Ensure-Connected
            $appId = [string](Get-PropertyValue -Object $data -Name 'appId' -Default '')
            $objectId = [string](Get-PropertyValue -Object $data -Name 'objectId' -Default '')
            $mailbox = [string](Get-PropertyValue -Object $data -Name 'mailbox' -Default '')
            $confirmed = [bool](Get-PropertyValue -Object $data -Name 'tenantWideMailSendRemoved' -Default $false)

            Validate-AppData -AppId $appId -ObjectId $objectId -Mailbox $mailbox
            if (-not $confirmed) {
                throw (L "Sicherheitsbestätigung fehlt: Tenantweites Microsoft Graph -> Mail.Send (Application) muss für diese App entfernt bzw. nicht erteilt sein." "Security confirmation is missing: Tenant-wide Microsoft Graph -> Mail.Send (Application) must be removed or not granted for this app.")
            }

            $mbx = Get-ValidatedMailbox -RequestId $requestId -Mailbox $mailbox
            [void](Ensure-ExchangeServicePrincipal -RequestId $requestId -AppId $appId -ObjectId $objectId -Mailbox $mbx)
            $scopeName = Ensure-ManagementScope -RequestId $requestId -AppId $appId -Mailbox $mbx
            $assignmentName = Ensure-MailSendAssignment -RequestId $requestId -AppId $appId -ObjectId $objectId -ScopeName $scopeName -Mailbox $mbx

            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Exchange-RBAC-Konfiguration abgeschlossen.' 'Exchange RBAC configuration completed.') -Data ([ordered]@{
                appId          = $appId
                mailbox        = [string]$mbx.PrimarySmtpAddress
                scopeName      = $scopeName
                assignmentName = $assignmentName
            })
        }

        'test' {
            $appId = [string](Get-PropertyValue -Object $data -Name 'appId' -Default '')
            $objectId = [string](Get-PropertyValue -Object $data -Name 'objectId' -Default '')
            $mailbox = [string](Get-PropertyValue -Object $data -Name 'mailbox' -Default '')
            $testResult = Invoke-MailSendTest -RequestId $requestId -AppId $appId -ObjectId $objectId -Mailbox $mailbox
            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Zugriffstest erfolgreich.' 'Access test completed successfully.') -Data $testResult
        }

        'disconnect' {
            if ($script:ExchangeConnected) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                $script:ExchangeConnected = $false
            }
            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Exchange-Online-Verbindung getrennt.' 'Disconnected from Exchange Online.') -Data @{}
        }

        'shutdown' {
            if ($script:ExchangeConnected) {
                try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                $script:ExchangeConnected = $false
            }
            Send-Protocol -Type 'response' -RequestId $requestId -Success $true -Message (L 'Worker wird beendet.' 'Worker is shutting down.') -Data @{}
            return $false
        }

        default {
            throw (L "Unbekannter Worker-Befehl: '$command'." "Unknown worker command: '$command'.")
        }
    }

    return $true
}

$continue = $true
while ($continue -and ($line = [Console]::In.ReadLine()) -ne $null) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $requestId = ''
    try {
        $request = $line | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        $requestId = [string](Get-PropertyValue -Object $request -Name 'id' -Default '')
        $continue = Invoke-Request -Request $request
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($requestId)) { $requestId = 'unknown' }
        Send-Protocol -Type 'response' -RequestId $requestId -Success $false -Message $_.Exception.Message -Data @{}
    }
}

if ($script:ExchangeConnected) {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
}
