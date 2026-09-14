# Entra Mail.Send – Shared Mailbox RBAC Tool

**Language / Sprache:** 🇬🇧 English · [🇩🇪 Deutsch](README.md)

A cross-platform admin GUI for assigning **Application Mail.Send** to one specific **Shared Mailbox** through Exchange Online RBAC for Applications.

> [!IMPORTANT]
> The same app must not also have tenant-wide **Microsoft Graph → Mail.Send (Application)** permission, otherwise the mailbox restriction is not effective.

## Cross-Platform GUI

The Avalonia GUI runs on **Windows, macOS and Linux** and includes a built-in **Deutsch / English** language selector.

The current interface uses a simple three-step workflow:

1. Sign in with Microsoft
2. Enter the Entra app and Shared Mailbox
3. Configure and verify access

Technical details are collapsed by default and only need to be opened for troubleshooting.

## Microsoft sign-in

Enter the administrator account and select **Sign in with Microsoft**. The standard Microsoft authentication flow opens directly and continues to support MFA, passkeys and Conditional Access.

The normal GUI no longer shows a Device Code button.

## Requirements

- Windows, macOS or Linux
- .NET 10 SDK
- PowerShell 7.4 or newer
- ExchangeOnlineManagement
- Exchange Administrator permissions
- an existing Entra Enterprise Application
- an existing Shared Mailbox

## Start on Windows

```powershell
pwsh .\CrossPlatformGUI\scripts\run-source.ps1
```

## Start on macOS

```powershell
pwsh ./CrossPlatformGUI/scripts/run-source.ps1
```

## How to use it

1. Select **English** in the upper-right corner.
2. Enter the admin account.
3. Select **Sign in with Microsoft**.
4. Enter the **Application (Client) ID**.
5. Enter the **Enterprise App Object ID**.
6. Enter the **Shared Mailbox**.
7. Confirm that tenant-wide `Mail.Send (Application)` is not granted to the app.
8. Select **Configure access**.
9. The tool automatically performs an Exchange RBAC access test.

## Which Object ID do I need?

Use the Object ID from:

**Entra ID → Enterprise applications → your application**

Do not use the Object ID from **App registrations**.

## What the tool configures

```text
Microsoft Entra Enterprise Application
                 │
                 ▼
       Exchange Service Principal
                 │
                 ▼
        Application Mail.Send
                 │
                 ▼
          Management Scope
                 │
                 ▼
        one Shared Mailbox
```

The tool creates or validates the required Exchange service principal, mailbox scope and role assignment, then verifies the result using `Test-ServicePrincipalAuthorization`.

## Screenshots

The repository screenshots currently show the previous interface. The new GUI has been redesigned as a cleaner three-step workflow.

## Microsoft documentation

- [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline)
- [Test-ServicePrincipalAuthorization](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization)

## Disclaimer

This project is not an official Microsoft product. Test permission changes before using them in production.
