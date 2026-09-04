# Cross-Platform GUI (Avalonia)

**Language / Sprache:** 🇬🇧 English · [🇩🇪 Deutsch](README.md)

This variant provides the same Exchange Online RBAC functionality as the PowerShell tools through a real desktop interface on **Windows, macOS and Linux**.

## Language

Use the selector in the upper-right corner to switch between **Deutsch** and **English**. The selected language also applies to status and error messages returned by the Exchange backend.

## Architecture

```text
Avalonia GUI (.NET 10)
        ↓
persistent PowerShell 7 worker
        ↓
ExchangeOnlineManagement
        ↓
Exchange Online RBAC for Applications
        ↓
Application Mail.Send → exactly one Shared Mailbox
```

The application does **not** request or store the admin password. Authentication is handled by `Connect-ExchangeOnline` using Microsoft Modern Authentication / MFA / Conditional Access.

## Requirements

- .NET 10 SDK
- PowerShell 7.4 or newer (`pwsh` must be available in `PATH`)
- internet access to Microsoft 365 and PowerShell Gallery
- Exchange Administrator
- permission to assign Exchange Application RBAC roles

`ExchangeOnlineManagement` is checked at startup and installed for the current user if required.

## Start from source on macOS

```powershell
pwsh ./CrossPlatformGUI/scripts/run-source.ps1
```

Alternatively:

```bash
dotnet run --project CrossPlatformGUI/EntraMailSendRbac.Gui/EntraMailSendRbac.Gui.csproj
```

## Build a macOS `.app`

```bash
chmod +x ./CrossPlatformGUI/scripts/build-macos-app.sh
./CrossPlatformGUI/scripts/build-macos-app.sh
```

Output:

```text
CrossPlatformGUI/dist/Entra MailSend RBAC.app
```

The local build is not codesigned or notarized.

## Windows

Start from source:

```powershell
pwsh .\CrossPlatformGUI\scripts\run-source.ps1
```

Build:

```powershell
pwsh .\CrossPlatformGUI\scripts\build-windows.ps1
```

Output:

```text
CrossPlatformGUI/dist/windows-x64/
```

## Usage

1. Select **English** or **Deutsch**.
2. Enter the admin account.
3. Select **Microsoft Login**. Use **Device Code** if browser sign-in does not work.
4. Enter the Application (Client) ID.
5. Enter the Object ID of the **Enterprise Application**.
6. Enter the Shared Mailbox.
7. Confirm that tenant-wide Microsoft Graph `Mail.Send (Application)` is removed or not granted.
8. Select **Configure access**.
9. The app performs an RBAC test automatically.

## Security note

For the restriction to be effective, the same app must not also have tenant-wide:

```text
Microsoft Graph → Mail.Send (Application)
```

Entra application permissions and Exchange Application RBAC are additive.
