# Tests the browser version locally: exports the web build, starts a dev game server
# and a small web server, then opens http://localhost:8060 in your browser.
# Open the same address in more tabs/windows to add players. Ctrl+C here stops the web server;
# close the Godot console window to stop the game server.
& "$PSScriptRoot\export.ps1"
$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64.exe" }
Start-Process $godot -ArgumentList @('--headless', '--path', '.', '++', '--server', '--dev')
Start-Process "http://localhost:8060"
python -m http.server 8060 --directory build\web
