# End-to-end network test: starts a local server and 4 headless bot clients that
# create/join a room, play a 30-second match (shooting each other) and return to the lobby.
# Usage: tools\test_net.ps1      (prints each bot's log; look for kill events and "back in lobby")
#        tools\test_net.ps1 -port 9393 -External   (test a server that is already running)
param([int]$port = 9191, [switch]$External, [string]$Url = "")   # -Url wss://...: test a deployed server
$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64.exe" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "bdm_nettest"
New-Item -ItemType Directory -Force $tmp | Out-Null
$common = @('--headless', '--path', '.', '++')
if (-not $External -and $Url -eq "") { $server = Start-Process $godot -ArgumentList ($common + @('--server', "--port=$port", '--match-seconds=30')) -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\server.txt" -RedirectStandardError "$tmp\server_err.txt" }
Start-Sleep -Seconds 2
$bots = @()
$bots += Start-Process $godot -ArgumentList ($common + @('--bot=create', "--port=$port", "--url=$Url")) -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\bot0.txt" -RedirectStandardError "$tmp\bot0_err.txt"
Start-Sleep -Seconds $(if ($Url) { 10 } else { 3 })
foreach ($i in 1..3) {
    $bots += Start-Process $godot -ArgumentList ($common + @('--bot=join', "--port=$port", "--url=$Url")) -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\bot$i.txt" -RedirectStandardError "$tmp\bot${i}_err.txt"
}
$bots | Wait-Process -Timeout 900 -ErrorAction SilentlyContinue
$bots | Where-Object { -not $_.HasExited } | Stop-Process -Force
if ($server) { Stop-Process -Id $server.Id -Force }
if ($server) { "=== server ==="; Get-Content "$tmp\server.txt", "$tmp\server_err.txt" }
foreach ($i in 0..3) { "=== bot $i ==="; Get-Content "$tmp\bot$i.txt", "$tmp\bot${i}_err.txt" | Select-Object -Last 14 }
