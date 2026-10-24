<#
.SYNOPSIS
    Startet den MCP Inspector gegen AtlasServer, um MCP-Werkzeuge ohne Claude zu prüfen (#1125).

.DESCRIPTION
    Der MCP Inspector (https://modelcontextprotocol.io/docs/tools/inspector) zeigt alle
    Werkzeuge, Ressourcen und Eingabeschemas des Servers, ruft sie mit eigenen Argumenten
    auf und zeigt die rohen JSON-RPC-Nachrichten. Gedacht für die Entwicklung neuer
    Atlas-Werkzeuge (docs/MCP.md, Abschnitt „Werkzeuge entwickeln und prüfen“).

    Drei Arten:
      - ohne -Method und -Tui: Oberfläche im Browser (Verlauf mit rohem JSON je Aufruf)
      - -Tui: Oberfläche im Terminal, z. B. über SSH oder in einer Cloud-Sitzung
      - -Method: Kommandozeile, ein Aufruf, Ergebnis als JSON (für Skripte oder Claude)

    Der Server startet über eine erzeugte Sitzungskonfiguration (--config/--server). So landen
    Schalter wie --mcp oder --restricted sicher beim Server und nicht beim Inspector.

    Alle Werkzeuge auf einmal mit Beispielargumenten prüft Tools/Test-McpTools.ps1.

    Braucht Node.js ab 22.19 (npx). Der Inspector wird beim ersten Aufruf in der festen Version
    InspectorVersion geladen.

.PARAMETER Server
    Pfad zu AtlasServer; Vorgabe: Debug-Ausgabe der Win64-Gruppe, unter Linux
    Output/Linux64/Bin/AtlasServer, sonst AtlasServer.exe bzw. AtlasServer aus dem PATH.

.PARAMETER ProjectRoot
    Arbeitsordner des MCP-Servers (--root); Vorgabe: Wurzel dieses Repositorys. Für stabile
    Proben eignet sich Tests/Referenzprojekt.

.PARAMETER Tui
    Oberfläche im Terminal statt im Browser.

.PARAMETER Method
    tools/list, tools/call, resources/list, resources/read, prompts/list (Kommandozeile).

.PARAMETER Tool
    Werkzeug bei tools/call, z. B. get_diagnostics.

.PARAMETER Arguments
    Argumente bei tools/call als Hashtable, z. B. @{ file = 'Application/AtlasServer.dpr' }.
    Der Inspector wandelt die Werte nach dem Eingabeschema (integer, boolean). Listen und
    Objekte gehen als JSON; unter Windows mit Anführungszeichen im Wert besser
    Tools/Test-McpTools.ps1 -Tool … -Arguments … nehmen.

.PARAMETER Uri
    Ressource bei resources/read, z. B. delphi://conventions.

.PARAMETER Strict
    Bei tools/list die Schema-Prüfung des Inspectors ausführlich auf stderr ausgeben
    (Pfad, Problem, Vorschlag); Exit-Code 6 bei einem Fehler. Ohne den Schalter steht nur
    die Anzahl der Probleme da.

.PARAMETER Restricted
    Server mit --restricted starten: nur lesende Werkzeuge.

.PARAMETER Log
    Logdatei des Servers (--log).

.PARAMETER Output
    Ergebnis der Kommandozeile in diese Datei statt auf die Konsole.

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1 -ProjectRoot Tests/Referenzprojekt -Method tools/list -Strict

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1 -Method tools/call -Tool hook_check -Arguments @{ file = 'Application/Source/Shell/Shell.Mcp.pas' }

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1 -Method resources/read -Uri delphi://conventions
#>
[CmdletBinding()]
param(
    [string] $Server,
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch] $Tui,
    [ValidateSet('', 'tools/list', 'tools/call', 'resources/list', 'resources/read', 'prompts/list')]
    [string] $Method = '',
    [string] $Tool,
    [hashtable] $Arguments = @{},
    [string] $Uri,
    [switch] $Strict,
    [switch] $Restricted,
    [string] $Log,
    [string] $Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InspectorVersion = '2.12.0'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ($Tui -and $Method) {
    throw '-Tui und -Method schließen sich aus.'
}
if (-not $Server) {
    $candidates = @(
        (Join-Path $RepoRoot 'Output/Win64/Debug/Bin/AtlasServer.exe'),
        (Join-Path $RepoRoot 'Output/Linux64/Bin/AtlasServer')
    )
    $Server = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Server) {
        $command = Get-Command 'AtlasServer.exe', 'AtlasServer' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $command) { throw 'AtlasServer nicht gefunden; -Server angeben oder erst bauen.' }
        $Server = $command.Source
    }
}
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'npx fehlt: Node.js ab 22.19 installieren (https://nodejs.org).'
}

$serverArgs = @('--mcp', '--root', (Resolve-Path $ProjectRoot).Path)
if ($Restricted) { $serverArgs += '--restricted' }
if ($Log) { $serverArgs += @('--log', [IO.Path]::GetFullPath($Log)) }

# Sitzungskonfiguration des Inspectors (nur gelesen, nie geschrieben)
$config = [ordered]@{
    mcpServers = [ordered]@{
        atlas = [ordered]@{
            command = (Resolve-Path $Server).Path
            args    = $serverArgs
        }
    }
}
$configFile = Join-Path ([IO.Path]::GetTempPath()) "atlas-mcp-inspector-$PID.json"
[IO.File]::WriteAllText($configFile, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))

$inspectorArgs = @('-y', "@modelcontextprotocol/inspector@$InspectorVersion")
if ($Method) {
    $inspectorArgs += '--cli'
} elseif ($Tui) {
    $inspectorArgs += '--tui'
} else {
    $inspectorArgs += '--web'
}
# Nur die Kommandozeile kennt --server; Web und TUI zeigen alle Server der Datei (hier nur atlas).
$inspectorArgs += @('--config', $configFile)
if ($Method) { $inspectorArgs += @('--server', 'atlas') }
if ($Method) {
    $inspectorArgs += @('--method', $Method)
    switch ($Method) {
        'tools/call' {
            if (-not $Tool) { throw '-Tool fehlt für tools/call.' }
            $inspectorArgs += @('--tool-name', $Tool)
            foreach ($key in $Arguments.Keys) {
                $value = $Arguments[$key]
                if ($value -is [bool]) {
                    $value = "$value".ToLowerInvariant()
                } elseif ($value -is [array] -or $value -is [hashtable]) {
                    $value = ConvertTo-Json -InputObject $value -Compress -Depth 10
                }
                $inspectorArgs += @('--tool-arg', "$key=$value")
            }
        }
        'resources/read' {
            if (-not $Uri) { throw '-Uri fehlt für resources/read.' }
            $inspectorArgs += @('--uri', $Uri)
        }
        'tools/list' {
            if ($Strict) { $inspectorArgs += '--strict' }
        }
    }
    if ($Output) { $inspectorArgs += @('--output', [IO.Path]::GetFullPath($Output)) }
}

# Atlas braucht keine Geheimnisse (OAuth); ohne Schlüsselbund meldet der Inspector sonst bei jedem Start
# den Rückfall auf eine unverschlüsselte Datei.
if (-not $env:MCP_INSPECTOR_SECRET_STORE) { $env:MCP_INSPECTOR_SECRET_STORE = 'memory' }

try {
    Write-Verbose "Server: $($config.mcpServers.atlas.command) $($serverArgs -join ' ')"
    Write-Verbose "npx $($inspectorArgs -join ' ')"
    & npx @inspectorArgs
    $exitCode = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue
}
exit $exitCode
