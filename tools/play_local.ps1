# Local multiplayer test: starts a dev server plus N game windows on this PC.
# Usage: tools\play_local.ps1 [windows=2]
# The dev server lets the host start with any number of players (the real 4-20 even rule
# is only skipped because of --dev). Close the server console window to stop the server.
param([int]$Windows = 2)
$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64.exe" }
Start-Process $godot -ArgumentList @('--headless', '--path', '.', '++', '--server', '--dev')
Start-Sleep -Seconds 1
foreach ($i in 0..($Windows - 1)) {
    $x = 40 + ($i % 2) * 920
    $y = 40 + [math]::Floor($i / 2) * 480
    Start-Process $godot -ArgumentList @('--path', '.', '--resolution', '900x506', '--position', "$x,$y")
}
