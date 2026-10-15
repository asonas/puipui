# Launch at login

Status: planned. Let users enable or disable launch at login from puipui without a terminal command.

## Interface

Add a **Launch at Login** item to the existing ellipsis menu. Show a checkmark when `SMAppService.mainApp.status` is `.enabled`. Read the status whenever the menu opens so changes made in System Settings are reflected.

Selecting the unchecked item calls `register()`; selecting the checked item calls `unregister()`. Do not register automatically at first launch. Keep the preference in macOS rather than duplicating it in app defaults.

If macOS reports `.requiresApproval`, explain that approval is needed and offer **Open Login Items Settings** using `SMAppService.openSystemSettingsLoginItems()`. Do not display the item as enabled until macOS reports `.enabled`. Registration failures should show an error without changing the displayed state.

## Implementation and verification

Extend the native menu coordinator in `Dashboard.swift`, using the existing ServiceManagement integration. Keep the command-line registration option for maintenance, but remove it from the user-facing installation guide.

Verify from the installed, signed app in `/Applications`: enable, disable, reject or approve in System Settings, reopen the menu, and restart the app. Confirm the state matches System Settings throughout. Finally, log out and back in with launch enabled and confirm that one menu bar instance starts. That last check requires a user-coordinated session restart.
