param(
  [Parameter(Mandatory = $true)]
  [string]$Message,
  [switch]$SkipEnter,
  [int]$InputOffsetBottom = 70,
  [int]$InputXPercent = 50
)

$ErrorActionPreference = "Stop"

& "$PSScriptRoot\focus-viber.ps1" -InputOffsetBottom $InputOffsetBottom -InputXPercent $InputXPercent

Set-Clipboard -Value $Message
Start-Sleep -Milliseconds 100

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("^v")

if (-not $SkipEnter) {
  Start-Sleep -Milliseconds 140
  [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}
