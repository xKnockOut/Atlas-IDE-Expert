<#
.SYNOPSIS
    Startet den MCP Inspector gegen AtlasServer, um MCP-Werkzeuge ohne Claude zu prüfen.

.DESCRIPTION
    Der MCP Inspector (https://modelcontextprotocol.io/docs/tools/inspector) zeigt alle
    Werkzeuge, Ressourcen und Eingabeschemas des Servers, ruft sie mit eigenen Argumenten
    auf und zeigt die rohen JSON-RPC-Nachrichten. Gedacht für die Entwicklung neuer
    Atlas-Werkzeuge (docs/MCP.md, Abschnitt „Werkzeuge entwickeln und prüfen“).

    Ohne -Method öffnet sich die Oberfläche im Browser. Mit -Method läuft der Inspector
    als Kommandozeile und gibt das Ergebnis als JSON aus, z. B. für Skripte oder Claude.

    Braucht Node.js (npx). Der Inspector wird beim ersten Aufruf in der festen Version
    InspectorVersion geladen.

.PARAMETER Server
    Pfad zu AtlasServer.exe; Vorgabe: Debug-Ausgabe der Win64-Gruppe, unter Linux
    Output/Linux64/Bin/AtlasServer, sonst AtlasServer.exe aus dem PATH.

.PARAMETER ProjectRoot
    Arbeitsordner des MCP-Servers (--root); Vorgabe: Wurzel dieses Repositorys.

.PARAMETER Method
    tools/list, tools/call, resources/list, resources/read, prompts/list.

.PARAMETER Tool
    Werkzeug bei tools/call, z. B. get_diagnostics.

.PARAMETER Arguments
    Argumente bei tools/call als Hashtable, z. B. @{ file = 'Application/AtlasServer.dpr' }.

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1

.EXAMPLE
    pwsh Tools/Start-McpInspector.ps1 -Method tools/call -Tool hook_check -Arguments @{ file = 'Application/Source/Shell/Shell.Mcp.pas' }
#>
[CmdletBinding()]
param(
    [string] $Server,
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('', 'tools/list', 'tools/call', 'resources/list', 'resources/read', 'prompts/list')]
    [string] $Method = '',
    [string] $Tool,
    [hashtable] $Arguments = @{}
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InspectorVersion = '2.12.0'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Server) {
    $candidates = @(
        (Join-Path $RepoRoot 'Output/Win64/Debug/Bin/AtlasServer.exe'),
        (Join-Path $RepoRoot 'Output/Linux64/Bin/AtlasServer')
    )
    $Server = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Server) {
        $command = Get-Command 'AtlasServer.exe', 'AtlasServer' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) { throw 'AtlasServer nicht gefunden; -Server angeben oder erst bauen.' }
        $Server = $command.Source
    }
}
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'npx fehlt: Node.js installieren (https://nodejs.org).'
}

$inspectorArgs = @('-y', "@modelcontextprotocol/inspector@$InspectorVersion")
if ($Method) {
    $inspectorArgs += '--cli'
}
$inspectorArgs += @($Server, '--mcp', '--root', $ProjectRoot)
if ($Method) {
    $inspectorArgs += @('--method', $Method)
    if ($Method -eq 'tools/call') {
        if (-not $Tool) { throw '-Tool fehlt für tools/call.' }
        $inspectorArgs += @('--tool-name', $Tool)
        foreach ($key in $Arguments.Keys) {
            $inspectorArgs += @('--tool-arg', "$key=$($Arguments[$key])")
        }
    }
}

Write-Verbose "npx $($inspectorArgs -join ' ')"
& npx @inspectorArgs
exit $LASTEXITCODE
