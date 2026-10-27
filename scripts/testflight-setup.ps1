<#
.SYNOPSIS
  AirFrameXR: sets up TestFlight publishing on GitHub for you (fork, secrets, first build).

.DESCRIPTION
  Run this after Part 1 of docs/TESTFLIGHT.md (the Apple part), when you have the five values.
  It checks the GitHub command line tool (gh), signs you in, makes your own copy (fork) of the project,
  turns on its builds, asks for the values (checking each one), stores them as secrets and variables,
  and offers to run the test build and the real upload. It never prints your key.

  Start it:   powershell -ExecutionPolicy Bypass -File .\testflight-setup.ps1
  Nothing is changed on GitHub until you confirm the summary. Use -DryRun to see what it would do.
#>
[CmdletBinding()]
param(
    [string]$Upstream = 'jfbobier/alvr-visionos',
    [string]$BundleId,
    [string]$TeamId,
    [string]$KeyId,
    [string]$IssuerId,
    [string]$P8Path,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$DefaultBranch = 'airframexr-client'
$Workflow = 'testflight.yml'

function Step($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   OK  $m" -ForegroundColor Green }
function Info($m) { Write-Host "       $m" }
function Warn($m) { Write-Host "   !   $m" -ForegroundColor Yellow }
function Stop-Here($m) { Write-Host ''; Write-Host "   STOP  $m" -ForegroundColor Red; exit 1 }

# Runs gh. Mutating calls are only printed in a dry run. Returns the output text; stops on failure unless -AllowFail.
function Invoke-Gh {
    param([string[]]$ArgList, [switch]$Mutating, [switch]$AllowFail, [string]$StdIn)
    if ($DryRun -and $Mutating) {
        Info ('[dry run] gh ' + ($ArgList -join ' '))
        return ''
    }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # native stderr must not become an exception in Windows PowerShell 5.1
    try {
        if ($PSBoundParameters.ContainsKey('StdIn')) {
            $out = $StdIn | & gh @ArgList 2>&1 | Out-String
        } else {
            $out = & gh @ArgList 2>&1 | Out-String
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
    if ($code -ne 0 -and -not $AllowFail) {
        Stop-Here ("gh " + ($ArgList -join ' ') + " failed:`n" + $out.Trim())
    }
    $script:LastGhCode = $code
    return $out
}

# Read-Host that never returns $null (it does when the input is closed)
function Read-Line($prompt) {
    $r = Read-Host $prompt
    if ($null -eq $r) { return '' }
    return $r.Trim()
}

function Ask-Yes($question, $defaultYes = $true) {
    $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = (Read-Line "$question $hint").ToLower()
        if ($a -eq '') { return $defaultYes }
        if ($a -in @('y', 'yes')) { return $true }
        if ($a -in @('n', 'no')) { return $false }
    }
}

# Asks until the value matches the pattern. Shows what a good value looks like.
function Ask-Value($name, $pattern, $example, $where, $default = '', $upper = $false) {
    while ($true) {
        Write-Host ''
        Write-Host "   $name" -ForegroundColor White
        Info "Where: $where"
        Info "Looks like: $example"
        $prompt = if ($default) { "   Paste it (Enter = $default)" } else { '   Paste it' }
        $v = (Read-Line $prompt).Trim('"').Trim()
        if ($v -eq '' -and $default) { $v = $default }
        if ($upper) { $v = $v.ToUpper() }
        if ($v -match $pattern) { return $v }
        Warn "That does not look right ($name). Copy it again from your worksheet."
    }
}

Write-Host ''
Write-Host 'AirFrameXR - TestFlight setup' -ForegroundColor White
if ($DryRun) { Warn 'DRY RUN: nothing is changed on GitHub.' }

# 1. gh installed ---------------------------------------------------------------------------------
Step '1/7  GitHub command line tool (gh)'
function Test-Gh { return [bool](Get-Command gh -ErrorAction SilentlyContinue) }
if (-not (Test-Gh)) {
    Warn 'gh is not installed.'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Here 'winget is missing. Install "App Installer" from the Microsoft Store, or get gh from https://cli.github.com , then run this script again.'
    }
    if (Ask-Yes 'Install it now with winget?') {
        & winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not (Test-Gh)) {
            Stop-Here 'gh is installed, but this window does not see it yet. CLOSE this window, open a new PowerShell, and run the script again.'
        }
    } else {
        Stop-Here 'Install it with:  winget install --id GitHub.cli -e   then close this window, open a new one and run the script again.'
    }
}
Ok ((Invoke-Gh @('--version')).Split("`n")[0].Trim())

# 2. signed in ------------------------------------------------------------------------------------
Step '2/7  Your GitHub account'
$null = Invoke-Gh @('auth', 'status') -AllowFail
if ($script:LastGhCode -ne 0) {
    Info 'You are not signed in. A browser window will open: sign in to GitHub and confirm the code shown here.'
    & gh auth login --hostname github.com --git-protocol https --web
    $null = Invoke-Gh @('auth', 'status') -AllowFail
    if ($script:LastGhCode -ne 0) { Stop-Here 'Sign-in did not complete. Run the script again.' }
}
$login = (Invoke-Gh @('api', 'user', '--jq', '.login')).Trim()
if (-not $login) { Stop-Here 'Could not read your GitHub user name.' }
Ok "Signed in as $login"
$repoName = $Upstream.Split('/')[1]
$repo = "$login/$repoName"
if ($login -eq $Upstream.Split('/')[0]) { Stop-Here 'You are signed in as the owner of the original project. Sign in as the Apple account holder (gh auth logout, then run again).' }

# 3. fork -----------------------------------------------------------------------------------------
Step "3/7  Your copy of the project ($repo)"
$info = Invoke-Gh @('api', "repos/$repo") -AllowFail
if ($script:LastGhCode -eq 0) {
    $j = $info | ConvertFrom-Json
    if (-not $j.fork -or $j.parent.full_name -ne $Upstream) {
        Stop-Here "$repo already exists but is not a copy of $Upstream. Rename or delete it on GitHub, or use another account."
    }
    Ok 'You already have a copy.'
} else {
    Info 'Making your copy (a fork)...'
    $null = Invoke-Gh @('repo', 'fork', $Upstream, '--clone=false') -Mutating
    if (-not $DryRun) {
        $found = $false
        for ($i = 0; $i -lt 20 -and -not $found; $i++) {
            Start-Sleep -Seconds 3
            $null = Invoke-Gh @('api', "repos/$repo") -AllowFail
            $found = ($script:LastGhCode -eq 0)
        }
        if (-not $found) { Stop-Here 'The copy did not appear after a minute. Reload https://github.com and run the script again.' }
    }
    Ok 'Your copy is ready.'
}

# 4. builds on ------------------------------------------------------------------------------------
Step '4/7  Turn on the automatic builds in your copy'
$null = Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/actions/permissions", '-F', 'enabled=true', '-f', 'allowed_actions=all') -Mutating -AllowFail
$null = Invoke-Gh @('workflow', 'enable', $Workflow, '-R', $repo) -Mutating -AllowFail
if (-not $DryRun) {
    $listed = $false
    for ($i = 0; $i -lt 15 -and -not $listed; $i++) {
        $wl = Invoke-Gh @('workflow', 'list', '-R', $repo) -AllowFail
        $listed = ($wl -match 'TestFlight')
        if (-not $listed) { Start-Sleep -Seconds 4 }
    }
    if (-not $listed) {
        Warn 'The TestFlight workflow is not listed yet. If a later step fails, open the Actions tab of your copy and click "I understand my workflows, go ahead and enable them", then run this script again.'
    } else {
        $db = (Invoke-Gh @('api', "repos/$repo", '--jq', '.default_branch')).Trim()
        if ($db -ne $DefaultBranch) {
            Warn "Your copy's main branch is '$db', not '$DefaultBranch'. Switching it."
            $null = Invoke-Gh @('api', '-X', 'PATCH', "repos/$repo", '-f', "default_branch=$DefaultBranch") -AllowFail
        }
        Ok 'The TestFlight workflow is available.'
    }
} else { Info '[dry run] would check that the TestFlight workflow is listed' }

# 5. values ---------------------------------------------------------------------------------------
Step '5/7  The values from the Apple part'
Info 'Have your worksheet and the .p8 file at hand (Part 1 of docs/TESTFLIGHT.md).'

# the .p8 first: its file name holds the Key ID
$p8Text = $null
while (-not $p8Text) {
    if (-not $P8Path) {
        Write-Host ''
        Write-Host '   The .p8 key file' -ForegroundColor White
        Info 'Where: the AuthKey_XXXXXXXXXX.p8 file you downloaded in App Store Connect (Part 1, step 3).'
        Info 'Tip: drag the file into this window and press Enter, or type its full path.'
        $P8Path = (Read-Line '   Path').Trim('"').Trim()
    }
    if (-not (Test-Path -LiteralPath $P8Path -PathType Leaf)) {
        Warn "No file at '$P8Path'."; $P8Path = $null; continue
    }
    $t = Get-Content -LiteralPath $P8Path -Raw
    if ($t -notmatch '-----BEGIN PRIVATE KEY-----' -or $t -notmatch '-----END PRIVATE KEY-----') {
        Warn 'That file is not an App Store Connect key (no BEGIN/END PRIVATE KEY lines). Pick the AuthKey_...p8 file.'
        $P8Path = $null; continue
    }
    $p8Text = $t
}
Ok ("Key file read ({0} characters, not shown)" -f $p8Text.Length)
$keyFromName = ''
if ((Split-Path $P8Path -Leaf) -match '^AuthKey_([A-Za-z0-9]{10})\.p8$') { $keyFromName = $Matches[1].ToUpper() }

if ($KeyId) { $KeyId = $KeyId.ToUpper() } else {
    $KeyId = Ask-Value 'Key ID' '^[A-Z0-9]{10}$' 'ABC123DEFG (10 letters and digits)' 'the characters after AuthKey_ in the file name, or the key table in App Store Connect' $keyFromName $true
}
if (-not $IssuerId) {
    $IssuerId = Ask-Value 'Issuer ID' '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' '69a6de80-1234-47e3-e053-5b8c7c11a4d1 (a long code with dashes)' 'top of the App Store Connect API page (Part 1, step 3)'
}
if (-not $TeamId) {
    $TeamId = Ask-Value 'Team ID' '^[A-Z0-9]{10}$' 'Z9Y8X7W6V5 (10 letters and digits)' 'developer.apple.com/account > Membership details (Part 1, step 4)' '' $true
}
if (-not $BundleId) {
    $BundleId = Ask-Value 'Bundle ID' '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' 'io.github.airframexr.client' 'the one you registered at Apple (Part 1, step 1)' 'io.github.airframexr.client'
}

Write-Host ''
Write-Host '   Summary' -ForegroundColor White
Info "GitHub copy : $repo"
Info "Bundle ID   : $BundleId"
Info "Team ID     : $TeamId"
Info "Key ID      : $KeyId"
Info "Issuer ID   : $IssuerId"
Info "Key file    : $P8Path (content will be stored as a secret, never shown)"
Warn 'The Bundle ID must be EXACTLY the one registered at Apple and used for the app in App Store Connect.'
if (-not (Ask-Yes 'Store these in your copy now?')) { Stop-Here 'Nothing was changed. Run the script again when ready.' }

# 6. store ----------------------------------------------------------------------------------------
Step '6/7  Storing the secrets and variables in your copy'
$null = Invoke-Gh @('secret', 'set', 'ASC_KEY_ID', '-R', $repo, '--body', $KeyId) -Mutating
$null = Invoke-Gh @('secret', 'set', 'ASC_ISSUER_ID', '-R', $repo, '--body', $IssuerId) -Mutating
if ($DryRun) { Info ('[dry run] gh secret set ASC_KEY_P8 -R ' + $repo + '   (key file content from stdin, hidden)') }
else { $null = Invoke-Gh @('secret', 'set', 'ASC_KEY_P8', '-R', $repo) -StdIn $p8Text }
$null = Invoke-Gh @('variable', 'set', 'APPLE_TEAM_ID', '-R', $repo, '--body', $TeamId) -Mutating
$null = Invoke-Gh @('variable', 'set', 'BUNDLE_ID', '-R', $repo, '--body', $BundleId) -Mutating
if (-not $DryRun) {
    $sec = Invoke-Gh @('secret', 'list', '-R', $repo)
    $var = Invoke-Gh @('variable', 'list', '-R', $repo)
    $missing = @()
    foreach ($n in 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8') { if ($sec -notmatch $n) { $missing += $n } }
    foreach ($n in 'APPLE_TEAM_ID', 'BUNDLE_ID') { if ($var -notmatch $n) { $missing += $n } }
    if ($missing.Count -gt 0) { Stop-Here ('Not stored: ' + ($missing -join ', ')) }
    Ok 'All five values are stored (3 secrets, 2 variables).'
}

# 7. run ------------------------------------------------------------------------------------------
function Start-Build($label, $extra) {
    $started = (Get-Date).ToUniversalTime().AddSeconds(-5)
    $args1 = @('workflow', 'run', $Workflow, '-R', $repo, '--ref', $DefaultBranch) + $extra
    $null = Invoke-Gh $args1 -Mutating
    if ($DryRun) { return }
    $id = $null
    for ($i = 0; $i -lt 20 -and -not $id; $i++) {
        Start-Sleep -Seconds 4
        $r = Invoke-Gh @('run', 'list', '-R', $repo, '--workflow', $Workflow, '--limit', '3', '--json', 'databaseId,createdAt') -AllowFail
        try {
            foreach ($x in ($r | ConvertFrom-Json)) {
                if ([datetime]$x.createdAt -ge $started) { $id = $x.databaseId; break }
            }
        } catch { }
    }
    if (-not $id) { Stop-Here "The run did not start. Open https://github.com/$repo/actions and check." }
    $url = "https://github.com/$repo/actions/runs/$id"
    Info "$label started: $url"
    Info 'Waiting (this takes 10 to 30 minutes; you can close the window and follow it at the link).'
    & gh run watch $id -R $repo --interval 30 --exit-status *> $null
    if ($LASTEXITCODE -eq 0) { Ok "$label finished: green tick." }
    else {
        Warn "$label failed (red cross). Open $url , download the 'testflight-logs' file at the bottom, and send it with the link to whoever helps you."
        Stop-Here 'See the table "If something goes wrong" in docs/TESTFLIGHT.md.'
    }
}

Step '7/7  Build'
if (Ask-Yes 'Run the TEST build now (no Apple involved, about 15 minutes, recommended)?') {
    Start-Build 'The test build' @('-f', 'unsigned_check=true')
}
if (Ask-Yes 'Upload to TestFlight now?') {
    $ver = Read-Line '   Version number (Enter = 0.1.0)'
    if (-not $ver) { $ver = '0.1.0' }
    $ll = if (Ask-Yes 'Include the low-latency-streaming entitlement? (say no if signing complains about it)') { 'true' } else { 'false' }
    Start-Build 'The upload' @('-f', "marketing_version=$ver", '-f', "low_latency_streaming=$ll", '-f', 'unsigned_check=false')
    if (-not $DryRun) {
        Write-Host ''
        Ok 'The build reached Apple. In 10 to 20 minutes you get an email "has completed processing".'
        Info 'Next: https://appstoreconnect.apple.com/apps > AirFrameXR > TestFlight (Part 3 of docs/TESTFLIGHT.md).'
    }
}

Write-Host ''
Write-Host 'Done. To build again later: ' -NoNewline
Write-Host "https://github.com/$repo/actions/workflows/$Workflow" -ForegroundColor Cyan
