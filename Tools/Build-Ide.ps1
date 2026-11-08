<#
.SYNOPSIS
    Baut Delphi-Projekte über eine eigene RAD-Studio-Instanz mit dem Atlas-Plugin (#1904), auch ohne
    Kommandozeilen-Compiler (Community und Starter Edition).

.DESCRIPTION
    Startet bds.exe im eigenen Registry-Profil (Standard „AtlasBuild“, bds -r) mit einer festen Kopie des
    Atlas-Plugins und schickt die Aufträge an den Build-Eingang des Plugins (Modul KI-Assistenten, dasselbe
    Protokoll wie das MCP-Werkzeug build_project):
      %LOCALAPPDATA%\Atlas\ide-builds\<pid>\<id>.json        Auftrag
      <id>.taken                                             vom Plugin übernommen
      <id>.result.json                                       {"ok": …, "build": {…, "messages": […]}}
    Die IDE des Benutzers wird nie angesprochen: Die Instanz läuft im eigenen Profil, sie lädt das Plugin aus
    -PluginFolder (nicht aus dem Ausgabeordner, der gerade gebaut wird) und endet nach dem letzten Auftrag.

    Einmal einrichten (oder nach einem Plugin-Update):
      pwsh Tools/Build-Ide.ps1 -Setup C:\Projekte\Atlas-IDE-Expert\main\Output\Win32\Debug\Bpl
    Bauen:
      pwsh Tools/Build-Ide.ps1 -Project Atlas.groupproj -Platform Win64 -Json

    Eine Projektgruppe baut das Skript Projekt für Projekt in der Reihenfolge der .groupproj; die Gruppe
    öffnet der Build-Eingang des Plugins selbst (Feld „group“ im Auftrag), sobald das erste Projekt nicht
    offen ist. Dialoge der Instanz (Hinweis der Community Edition u. ä.) bestätigt
    das Skript mit OK.

.PARAMETER Project
    .dproj oder .groupproj.
.PARAMETER Platform
    Win32 oder Win64; '' = wie in der IDE.
.PARAMETER Configuration
    Debug, Release …; '' = wie in der IDE.
.PARAMETER Mode
    build (alles neu), make (nur Geändertes) oder check.
.PARAMETER Setup
    Ordner mit den Plugin-BPLs (Atlas.IDE.*370.bpl samt Atlas.Common, Atlas.Windows, Atlas.Text), die nach
    -PluginFolder kopiert und im Profil eingetragen werden. Ohne -Project endet das Skript danach.
.PARAMETER PluginFolder
    Feste Kopie des Plugins; Vorgabe %LOCALAPPDATA%\Atlas\BuildIde\Bpl.
.PARAMETER Profile
    Registry-Profil der Bau-IDE (bds -r); Vorgabe AtlasBuild.
.PARAMETER Version
    BDS-Version, Vorgabe 37.0 (Delphi 13).
.PARAMETER TimeoutMinutes
    Höchstdauer je Projekt.
.PARAMETER ContinueOnError
    Nach einem gescheiterten Projekt der Gruppe die übrigen trotzdem bauen (Vorgabe: abbrechen).
.PARAMETER Json
    Ergebnis als JSON auf stdout: {"ok", "summary": {fatals, errors, warnings, hints}, "steps": [...]}.
#>
param(
    [string] $Project = '',
    [string] $Platform = '',
    [string] $Configuration = '',
    [ValidateSet('build', 'make', 'check')] [string] $Mode = 'build',
    [string] $Setup = '',
    [string] $PluginFolder = '',
    [string] $Profile = 'AtlasBuild',
    [string] $Version = '37.0',
    [int] $TimeoutMinutes = 30,
    [switch] $Json,
    [switch] $ContinueOnError
)

$ErrorActionPreference = 'Stop'
if ($PluginFolder -eq '') { $PluginFolder = Join-Path $env:LOCALAPPDATA 'Atlas\BuildIde\Bpl' }
$atlasData = Join-Path $env:LOCALAPPDATA 'Atlas'
$profileKey = "HKCU:\Software\Embarcadero\$Profile\$Version"
$knownKey = "$profileKey\Known Packages"
$disabledKey = "$profileKey\Disabled Packages"

function Write-Note([string] $Text) {
    if (-not $Json) { Write-Host $Text }
}

function Install-Plugin([string] $Source) {
    if (-not (Test-Path $Source)) { throw "Ordner fehlt: $Source" }
    New-Item -ItemType Directory -Force $PluginFolder | Out-Null
    Get-ChildItem $PluginFolder -Filter '*.bpl' | Remove-Item -Force
    $files = @(Get-ChildItem $Source -Filter '*.bpl' | Where-Object { $_.Name -like 'Atlas.*' -and $_.Name -notlike 'Atlas.IDE.Expert*' })
    foreach ($file in $files) { Copy-Item $file.FullName $PluginFolder -Force }
    Write-Note "Plugin kopiert: $($files.Count) BPLs nach $PluginFolder"
}

function Register-Plugin {
    # Profil anlegen bzw. Atlas-Einträge auf die feste Kopie setzen; andere Pakete des Profils bleiben.
    if (-not (Test-Path $knownKey)) { New-Item -Force $knownKey | Out-Null }
    $existing = (Get-ItemProperty $knownKey).PSObject.Properties | Where-Object { $_.Name -like '*Atlas.IDE.*' }
    foreach ($entry in $existing) { Remove-ItemProperty $knownKey -Name $entry.Name }
    if (Test-Path $disabledKey) {
        $off = (Get-ItemProperty $disabledKey).PSObject.Properties | Where-Object { $_.Name -like '*Atlas.IDE.*' }
        foreach ($entry in $off) { Remove-ItemProperty $disabledKey -Name $entry.Name }
    }
    $bpls = @(Get-ChildItem $PluginFolder -Filter 'Atlas.IDE.*.bpl')
    if ($bpls.Count -eq 0) { throw "Kein Plugin in $PluginFolder; zuerst -Setup <Bpl-Ordner>." }
    # Die IDE lädt die Einträge in beliebiger Reihenfolge und sucht abhängige Packages (Base, Common, Windows,
    # Text) über PATH: den Plugin-Ordner dort vorn eintragen.
    $environment = "$profileKey\Environment Variables"
    if (-not (Test-Path $environment)) { New-Item -Force $environment | Out-Null }
    New-ItemProperty $environment -Name 'PATH' -Value "$PluginFolder;`$(PATH)" -PropertyType String -Force | Out-Null
    foreach ($bpl in $bpls) {
        $name = $bpl.BaseName -replace '^Atlas\.IDE\.', '' -replace '\d+$', ''
        New-ItemProperty $knownKey -Name $bpl.FullName -Value "Atlas $name" -PropertyType String -Force | Out-Null
    }
}

function Get-BdsExe {
    $root = (Get-ItemProperty "HKCU:\Software\Embarcadero\BDS\$Version" -Name RootDir -ErrorAction SilentlyContinue).RootDir
    if (-not $root) {
        $root = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Embarcadero\BDS\$Version" -Name RootDir).RootDir
    }
    $exe = Join-Path $root 'bin\bds.exe'
    if (-not (Test-Path $exe)) { throw "bds.exe fehlt: $exe" }
    return $exe
}

function Get-GroupProjects([string] $Group) {
    # Reihenfolge der Projekte wie im Ziel Build der Gruppe (dort stehen die Abhängigkeiten aufgelöst).
    [xml] $xml = Get-Content -Raw -Encoding UTF8 $Group
    $ns = @{ m = 'http://schemas.microsoft.com/developer/msbuild/2003' }
    $folder = Split-Path -Parent $Group
    $byTarget = @{}
    foreach ($node in (Select-Xml -Xml $xml -Namespace $ns -XPath '//m:Target[m:MSBuild]')) {
        $target = $node.Node
        if ($target.Name -match '[:]') { continue }
        $byTarget[$target.Name] = [IO.Path]::GetFullPath((Join-Path $folder $target.MSBuild.Projects))
    }
    $build = (Select-Xml -Xml $xml -Namespace $ns -XPath "//m:Target[@Name='Build']/m:CallTarget").Node
    $result = @()
    if ($build) {
        foreach ($name in ($build.Targets -split ';')) {
            if ($byTarget.ContainsKey($name)) { $result += $byTarget[$name] }
        }
    }
    if ($result.Count -eq 0) {
        foreach ($node in (Select-Xml -Xml $xml -Namespace $ns -XPath '//m:Projects')) {
            $result += [IO.Path]::GetFullPath((Join-Path $folder $node.Node.Include))
        }
    }
    return $result
}

Add-Type -Namespace AtlasBuild -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);
public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
'@

function Confirm-Dialogs([int] $ProcessId) {
    # Sichtbare Dialoge der eigenen Instanz mit OK bestätigen (z. B. Hinweis der Community Edition).
    $script:dialogs = @()
    $callback = [AtlasBuild.Win+EnumProc] {
        param($hwnd, $l)
        $owner = [uint32] 0
        [void] [AtlasBuild.Win]::GetWindowThreadProcessId($hwnd, [ref] $owner)
        if ($owner -eq $ProcessId -and [AtlasBuild.Win]::IsWindowVisible($hwnd)) {
            $cls = New-Object System.Text.StringBuilder 256
            [void] [AtlasBuild.Win]::GetClassName($hwnd, $cls, 256)
            if ($cls.ToString() -match 'Dialog|#32770|TMessageForm') { $script:dialogs += $hwnd }
        }
        return $true
    }
    [void] [AtlasBuild.Win]::EnumWindows($callback, [IntPtr]::Zero)
    foreach ($dialog in $script:dialogs) {
        $script:okButton = [IntPtr]::Zero
        $childCallback = [AtlasBuild.Win+EnumProc] {
            param($child, $l)
            $text = New-Object System.Text.StringBuilder 64
            [void] [AtlasBuild.Win]::GetWindowText($child, $text, 64)
            if ($text.ToString() -match '^&?(OK|Ok|Schließen|Close)$') { $script:okButton = $child; return $false }
            return $true
        }
        [void] [AtlasBuild.Win]::EnumChildWindows($dialog, $childCallback, [IntPtr]::Zero)
        if ($script:okButton -ne [IntPtr]::Zero) {
            # BM_CLICK
            [void] [AtlasBuild.Win]::SendMessage($script:okButton, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
        }
    }
}

function Wait-Ready([System.Diagnostics.Process] $Ide, [string[]] $Projects, [int] $Seconds) {
    # Bereit, sobald das Plugin geladen ist (editor-dirty-<pid>.json).
    $file = Join-Path $atlasData "editor-dirty-$($Ide.Id).json"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $Seconds) {
        if ($Ide.HasExited) { throw 'Die Bau-IDE hat sich beendet, bevor sie bereit war.' }
        Confirm-Dialogs $Ide.Id
        # Die Projekte öffnet der Build-Eingang selbst, sobald ein Auftrag kommt (#1904).
        if (Test-Path $file) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "Das Atlas-Plugin meldet sich nach $Seconds s nicht (Plugin im Profil eingetragen? -Setup ausgeführt?)."
}

function Invoke-Build([System.Diagnostics.Process] $Ide, [string] $DprojFile) {
    $inbox = Join-Path $atlasData "ide-builds\$($Ide.Id)"
    $id = [guid]::NewGuid().ToString('N')
    $group = ''
    if ($Project -like '*.groupproj') { $group = $Project }
    $request = [ordered]@{ project = $DprojFile; mode = $Mode; configuration = $Configuration; platform = $Platform;
        group = $group }
    $requestFile = Join-Path $inbox "$id.json"
    $takenFile = Join-Path $inbox "$id.taken"
    $answer = Join-Path $inbox "$id.result.json"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $written = $false
    while (-not (Test-Path $answer)) {
        if ($Ide.HasExited) { throw 'Die Bau-IDE hat sich während des Baus beendet.' }
        if ($watch.Elapsed.TotalMinutes -gt $TimeoutMinutes) { throw "Kein Ergebnis für $DprojFile nach $TimeoutMinutes min." }
        # Der Eingang räumt seinen Ordner beim Start auf; ein zu früh gestellter Auftrag ist dann weg. Fehlt er,
        # ohne übernommen zu sein, neu stellen.
        if (-not $written -or (-not (Test-Path $requestFile) -and -not (Test-Path $takenFile))) {
            New-Item -ItemType Directory -Force $inbox | Out-Null
            $temp = Join-Path $inbox "$id.tmp"
            ($request | ConvertTo-Json -Compress) | Set-Content -Encoding UTF8 -NoNewline $temp
            Move-Item -Force $temp $requestFile
            $written = $true
        }
        Confirm-Dialogs $Ide.Id
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Milliseconds 100
    $result = Get-Content -Raw -Encoding UTF8 $answer | ConvertFrom-Json
    Remove-Item $answer -Force -ErrorAction SilentlyContinue
    return $result
}

function Get-Counts($Messages) {
    $counts = [ordered]@{ fatals = 0; errors = 0; warnings = 0; hints = 0 }
    foreach ($message in @($Messages)) {
        switch -Regex ($message.severity) {
            '^fatal' { $counts.fatals++ }
            '^error' { $counts.errors++ }
            '^warning' { $counts.warnings++ }
            '^hint' { $counts.hints++ }
        }
    }
    return $counts
}

function Stop-Ide([System.Diagnostics.Process] $Ide) {
    if ($Ide.HasExited) { return }
    [void] $Ide.CloseMainWindow()
    for ($i = 0; $i -lt 60 -and -not $Ide.HasExited; $i++) {
        Confirm-Dialogs $Ide.Id
        Start-Sleep -Milliseconds 500
    }
    # Nur die eigene Instanz, nie eine andere IDE.
    if (-not $Ide.HasExited) { $Ide.Kill() }
}

# --- Ablauf
if ($Setup -ne '') {
    Install-Plugin $Setup
    Register-Plugin
    if ($Project -eq '') { return }
}
if ($Project -eq '') { throw 'Project fehlt (.dproj oder .groupproj).' }
$Project = (Resolve-Path $Project).Path
$projects = @($Project)
if ($Project -like '*.groupproj') { $projects = @(Get-GroupProjects $Project) }
Register-Plugin

$env:ATLAS_NO_SESSION_MARKER = '1'
$ide = Start-Process (Get-BdsExe) -ArgumentList @('-pDelphi', '-r', $Profile, '-ns') -PassThru
$steps = @()
$total = [ordered]@{ fatals = 0; errors = 0; warnings = 0; hints = 0 }
$ok = $true
try {
    Write-Note "Bau-IDE gestartet (pid $($ide.Id), Profil $Profile)"
    Wait-Ready $ide $projects 600
    foreach ($dproj in $projects) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $answer = Invoke-Build $ide $dproj
        $step = [ordered]@{ project = $dproj; ok = [bool] $answer.ok; seconds = [int] $watch.Elapsed.TotalSeconds }
        if ($answer.ok) {
            $counts = Get-Counts $answer.build.messages
            $step.ok = [bool] $answer.build.success
            $step.summary = $counts
            $step.messages = @($answer.build.messages)
            foreach ($key in @($counts.Keys)) { $total[$key] += $counts[$key] }
        } else {
            $step.reason = [string] $answer.reason
        }
        if (-not $step.ok) { $ok = $false }
        $steps += [pscustomobject] $step
        Write-Note ("{0} {1} ({2} s)" -f $(if ($step.ok) { 'OK  ' } else { 'FEHL' }), (Split-Path -Leaf $dproj), $step.seconds)
        if (-not $step.ok -and -not $ContinueOnError) { break }
    }
} finally {
    Stop-Ide $ide
}
$result = [ordered]@{ ok = $ok; summary = $total; steps = $steps }
if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Host ("Gesamt: {0} Fehler, {1} Warnungen, {2} Hinweise" -f ($total.fatals + $total.errors), $total.warnings, $total.hints)
    foreach ($step in $steps) {
        foreach ($message in @($step.messages)) {
            Write-Host ("  [{0}] {1}({2}): {3} {4}" -f $message.severity, (Split-Path -Leaf $message.file), $message.line, $message.code, $message.text)
        }
        if ($step.reason) { Write-Host "  $($step.project): $($step.reason)" }
    }
}
if (-not $ok) { exit 1 }
