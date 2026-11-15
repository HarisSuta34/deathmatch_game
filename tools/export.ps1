# Exports the web client to build\web and the Linux dedicated server to build\server.
$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64.exe" }
New-Item -ItemType Directory -Force build\web, build\server | Out-Null
Set-Content build\.gdignore ""   # keeps Godot from importing the build output
foreach ($job in @(@('Web', 'build/web/index.html'), @('Server', 'build/server/server.x86_64'))) {
    $p = Start-Process $godot -ArgumentList @('--headless', '--path', '.', '--export-release', $job[0], $job[1]) -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\bdm_export.txt" -RedirectStandardError "$env:TEMP\bdm_export_err.txt"
    Get-Content "$env:TEMP\bdm_export_err.txt" | Select-String "ERROR"
    "$($job[0]) export: exit code $($p.ExitCode)"
}
Get-ChildItem build\web\index.html, build\web\index.wasm, build\web\index.pck, build\server\* | Select-Object Name, Length
