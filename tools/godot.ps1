# Runs Godot with the given arguments and prints its output.
# (The *_console.exe wrapper fails on this machine because of the non-ASCII user path.)
# Usage: tools\godot.ps1 --headless --path . --quit-after 120
$godot = if ($env:GODOT) { $env:GODOT } else { "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64.exe" }
$out = [System.IO.Path]::GetTempFileName()
$err = [System.IO.Path]::GetTempFileName()
$p = Start-Process -FilePath $godot -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
Get-Content $out
Get-Content $err
Remove-Item $out, $err
"exit code: $($p.ExitCode)"
