# Builds the web client and publishes it to the `gh-pages` branch on origin (GitHub Pages).
# The branch only ever holds the latest build (it is force-replaced each time).
&"$PSScriptRoot\export.ps1"
$origin = git remote get-url origin
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "bdm_pages"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory $tmp | Out-Null
Copy-Item build\web\* $tmp -Exclude *.import
Set-Content "$tmp\.nojekyll" ""
Push-Location $tmp
git init -q -b gh-pages
git config core.autocrlf false
git add -A
git commit -q -m "Publish web build"
git push -q -f $origin gh-pages
$ok = $LASTEXITCODE -eq 0
Pop-Location
Remove-Item $tmp -Recurse -Force
if ($ok) { "Published to the gh-pages branch." } else { "Push failed - see the git message above." }
