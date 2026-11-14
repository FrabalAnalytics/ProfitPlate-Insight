$ErrorActionPreference = 'Stop'

# Run once from a normal PowerShell session. No application files are moved.
$webRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $webRoot
$webGit = Join-Path $webRoot '.git'
$parentGit = Join-Path $projectRoot '.git'

function Invoke-ProjectGit {
    & git -c "safe.directory=$projectRoot" -C $projectRoot @args
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $args" }
}

if (!(Test-Path -LiteralPath $webGit -PathType Container)) {
    throw 'The web repository is missing or cleanup has already run. No changes made.'
}
if (!(Test-Path -LiteralPath $parentGit -PathType Container)) {
    throw 'Expected a Git repository in the main project folder. No changes made.'
}
& git -c "safe.directory=$projectRoot" -C $projectRoot rev-parse --verify --quiet HEAD
if ($LASTEXITCODE -eq 0) { throw 'The parent repository has commits. Stop for review.' }
$parentEntries = @(Invoke-ProjectGit ls-files --stage)
if ($parentEntries.Count -ne 1 -or $parentEntries[0] -notmatch '^160000 [0-9a-f]+ 0\s+web$') {
    throw 'The parent index differs from the reviewed setup. Stop for review.'
}
if ((Test-Path -LiteralPath (Join-Path $projectRoot '.gitignore')) -or
    (Test-Path -LiteralPath (Join-Path $projectRoot 'mobile\.gitkeep'))) {
    throw 'A destination file already exists. Stop for review.'
}
& git -c "safe.directory=$webRoot" -C $webRoot diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw 'Commit or unstage web changes before running this script.' }
& git -c "safe.directory=$webRoot" -C $webRoot var GIT_AUTHOR_IDENT
if ($LASTEXITCODE -ne 0) { throw 'Configure your Git name and email before continuing.' }

$backupRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('ProfitPlate-git-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backupRoot | Out-Null
Copy-Item -LiteralPath $webGit -Destination (Join-Path $backupRoot 'web.git') -Recurse -Force
Copy-Item -LiteralPath $parentGit -Destination (Join-Path $backupRoot 'parent.git') -Recurse -Force
Write-Host "Git backups: $backupRoot"

# Both sources are verified absolute paths inside the project. Keep the old
# parent metadata as a backup; use the web metadata to retain its full history.
[IO.Directory]::Move($parentGit, (Join-Path $backupRoot 'original-parent.git'))
try {
    [IO.Directory]::Move($webGit, $parentGit)
} catch {
    [IO.Directory]::Move((Join-Path $backupRoot 'original-parent.git'), $parentGit)
    throw "Could not move web Git metadata. The parent repository was restored. Run from a standalone Windows PowerShell window outside Codex, after closing editors using this project. Original error: $($_.Exception.Message)"
}

# Stage the committed baseline under web/, leaving current source edits alone.
Invoke-ProjectGit read-tree --empty
Invoke-ProjectGit read-tree --prefix=web/ HEAD

$ignoreText = @'
# Dependencies
node_modules/
.pnp/
.pnp.*

# Build output and caches
.next/
out/
build/
dist/
coverage/
.expo/
.vercel/
*.tsbuildinfo

# Local environment and credentials
.env*
*.pem
*.key

# Logs and operating system files
*.log
.DS_Store
Thumbs.db
'@
[IO.File]::WriteAllText((Join-Path $projectRoot '.gitignore'), $ignoreText + "`n", (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $projectRoot 'mobile\.gitkeep'), '', (New-Object Text.UTF8Encoding($false)))
Invoke-ProjectGit add -- .gitignore mobile/.gitkeep
Invoke-ProjectGit commit -m 'Organize project into web and mobile folders'
Invoke-ProjectGit check-ignore -- web/.env.local web/node_modules web/.next
Invoke-ProjectGit status --short
Write-Host 'Cleanup complete. Current source edits remain uncommitted. Nothing was pushed.'
