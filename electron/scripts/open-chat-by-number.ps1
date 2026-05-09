param(
  [Parameter(Mandatory = $true)]
  [string]$PhoneNumber
)

$ErrorActionPreference = "Stop"

$digits = ($PhoneNumber -replace "[^\d]", "")
if (-not $digits) {
  throw "Phone number is empty after normalization."
}

$wshell = New-Object -ComObject WScript.Shell
if (-not $wshell.AppActivate("Viber")) {
  throw "Could not activate Viber window."
}

Start-Sleep -Milliseconds 250

Add-Type -AssemblyName System.Windows.Forms

# Open search in Viber, type number, and confirm selection.
[System.Windows.Forms.SendKeys]::SendWait("^{f}")
Start-Sleep -Milliseconds 220
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 80
[System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE}")
Start-Sleep -Milliseconds 80
[System.Windows.Forms.SendKeys]::SendWait($digits)
Start-Sleep -Milliseconds 350
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 220
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
