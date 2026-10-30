<#
.SYNOPSIS
    Probelauf aller MCP-Werkzeuge von AtlasServer mit Beispielargumenten und rohem Mitschnitt (#1125).

.DESCRIPTION
    Startet AtlasServer --mcp einmal (der Index entsteht nur einmal) und spricht ihn direkt über
    stdio an, ohne Claude und ohne Inspector:

      1. initialize, tools/list, resources/list, resources/templates/list
      2. Schema jedes Werkzeugs prüfen: Beschreibung vorhanden, inputSchema vom Typ object,
         jeder Pflichtparameter steht in properties, jeder Parameter hat eine Beschreibung
      3. Jedes Werkzeug mit seinem Beispiel aus Tools/Mcp/Werkzeug-Beispiele.json aufrufen:
         kein JSON-RPC-Fehler, kein isError (außer bei expectError), Inhalt nicht leer,
         erwarteter Text (contains) enthalten
      4. Jede Ressource aus resources/list lesen
      5. Jeden Prompt aus prompts/list mit seinem Beispiel (prompts) über prompts/get holen und
         jede Ressourcenvorlage aus resources/templates/list mit ihrer Beispiel-URI (templates)
         lesen (#1357): Beschreibungen vorhanden, kein Fehler, Inhalt nicht leer, erwarteter Text

    Ein Werkzeug, ein Prompt oder eine Vorlage ohne Beispiel lässt den Lauf scheitern; neue bekommen
    so zwingend einen Eintrag. Werkzeuge mit "process": true (build_project, run_tests) laufen nur mit
    -WithProcessTools, weil sie die IDE oder einen Testlauf brauchen.

    Jede Nachricht in beide Richtungen steht roh im Mitschnitt (JSON Lines, Vorgabe
    Output/Mcp/probe-<Zeit>.jsonl): {"zeit":…,"richtung":"an Server"|"vom Server","nachricht":<roh>}.

    Mit -Tool nur dieses Werkzeug; mit -Arguments eigene Argumente statt des Beispiels. Die
    Antwort steht dann vollständig auf der Konsole. Das ersetzt den Inspector für einen
    schnellen Einzelaufruf mit Listen- oder Objektargumenten.

    Exit-Code 0: alles in Ordnung, 1: mindestens ein Befund, 3: Umgebungsfehler (Server fehlt,
    startet nicht, antwortet nicht).

.PARAMETER Server
    Pfad zu AtlasServer; Vorgabe wie bei Start-McpInspector.ps1.

.PARAMETER ProjectRoot
    Arbeitsordner des Servers (--root); Vorgabe: "root" aus der Beispieldatei
    (Tests/Referenzprojekt). Die Beispiele passen nur zu diesem Ordner.

.PARAMETER Examples
    Beispieldatei; Vorgabe Tools/Mcp/Werkzeug-Beispiele.json.

.PARAMETER Tool
    Nur dieses Werkzeug aufrufen (Schemaprüfung und Abgleich laufen trotzdem für alle).

.PARAMETER Arguments
    Mit -Tool: eigene Argumente als Hashtable statt des Beispiels.

.PARAMETER WithProcessTools
    Auch Werkzeuge mit "process": true aufrufen.

.PARAMETER TimeoutSeconds
    Zeitlimit je Antwort; Vorgabe 180 (der erste Aufruf wartet auf den Index).

.PARAMETER Transcript
    Datei für den rohen Mitschnitt.

.EXAMPLE
    pwsh Tools/Test-McpTools.ps1

.EXAMPLE
    pwsh Tools/Test-McpTools.ps1 -Tool find_symbol -Arguments @{ name = 'TKundenSuche' }

.EXAMPLE
    pwsh Tools/Test-McpTools.ps1 -Tool run_tests -WithProcessTools -Arguments @{ tests = @('Ref.Tests.Kunden') }
#>
[CmdletBinding()]
param(
    [string] $Server,
    [string] $ProjectRoot,
    [string] $Examples,
    [string] $Tool,
    [hashtable] $Arguments,
    [switch] $WithProcessTools,
    [int] $TimeoutSeconds = 180,
    [string] $Transcript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Utf8 = New-Object Text.UTF8Encoding $false

function Stop-Environment([string] $Message) {
    Write-Host "Umgebungsfehler: $Message" -ForegroundColor Red
    exit 3
}

if (-not $Examples) { $Examples = Join-Path $PSScriptRoot 'Mcp/Werkzeug-Beispiele.json' }
$exampleData = [IO.File]::ReadAllText($Examples, $Utf8) | ConvertFrom-Json
if (-not $ProjectRoot) { $ProjectRoot = Join-Path $RepoRoot $exampleData.root }
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if ($Arguments -and -not $Tool) { Stop-Environment '-Arguments nur zusammen mit -Tool.' }

if (-not $Server) {
    $candidates = @(
        (Join-Path $RepoRoot 'Output/Win64/Debug/Bin/AtlasServer.exe'),
        (Join-Path $RepoRoot 'Output/Linux64/Bin/AtlasServer')
    )
    $Server = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Server) {
        $command = Get-Command 'AtlasServer.exe', 'AtlasServer' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $command) { Stop-Environment 'AtlasServer nicht gefunden; -Server angeben oder erst bauen.' }
        $Server = $command.Source
    }
}
$Server = (Resolve-Path $Server).Path

if (-not $Transcript) {
    $Transcript = Join-Path $RepoRoot ("Output/Mcp/probe-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$Transcript = [IO.Path]::GetFullPath($Transcript)
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Transcript))
$transcriptWriter = New-Object IO.StreamWriter($Transcript, $false, $Utf8)

# --- Verbindung zum Server -------------------------------------------------------------------

function ConvertTo-ProcessArgument([string] $Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Write-TranscriptLine([string] $Direction, [string] $Raw) {
    $entry = '{"zeit":"' + (Get-Date).ToString('o') + '","richtung":"' + $Direction + '","nachricht":' + $Raw + '}'
    $transcriptWriter.WriteLine($entry)
    $transcriptWriter.Flush()
}

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $Server
$startInfo.Arguments = (@('--mcp', '--root', $ProjectRoot) | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' '
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.StandardOutputEncoding = $Utf8
$startInfo.WorkingDirectory = $ProjectRoot

try {
    $process = [Diagnostics.Process]::Start($startInfo)
} catch {
    Stop-Environment "AtlasServer startet nicht: $($_.Exception.Message)"
}
$stdin = $process.StandardInput.BaseStream
$stdout = $process.StandardOutput
$script:NextId = 0
$script:PendingLine = $null

function Send-Message([string] $Raw) {
    Write-TranscriptLine 'an Server' $Raw
    $bytes = $Utf8.GetBytes($Raw + "`n")
    $stdin.Write($bytes, 0, $bytes.Length)
    $stdin.Flush()
}

function Read-Response([int] $Id) {
    # Liest bis zur Antwort mit dieser id; Benachrichtigungen des Servers stehen nur im Mitschnitt.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        if ($null -eq $script:PendingLine) { $script:PendingLine = $stdout.ReadLineAsync() }
        $remaining = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        if (-not $script:PendingLine.Wait($remaining)) {
            throw "Keine Antwort auf Anfrage $Id binnen $TimeoutSeconds s"
        }
        $line = $script:PendingLine.Result
        $script:PendingLine = $null
        if ($null -eq $line) { throw "Server hat die Verbindung beendet (Anfrage $Id)" }
        if ($line.Trim() -eq '') { continue }
        Write-TranscriptLine 'vom Server' $line
        $message = $line | ConvertFrom-Json
        if (($message.PSObject.Properties.Name -contains 'id') -and ($message.id -eq $Id)) {
            return $message
        }
    }
}

function Invoke-Rpc([string] $Method, $Params) {
    $script:NextId++
    $request = [ordered]@{ jsonrpc = '2.0'; id = $script:NextId; method = $Method }
    if ($null -ne $Params) { $request.params = $Params }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Send-Message (ConvertTo-Json -InputObject $request -Compress -Depth 20)
    $response = Read-Response $script:NextId
    $watch.Stop()
    return [pscustomobject]@{ Response = $response; Ms = $watch.ElapsedMilliseconds }
}

# --- Hilfen für Prüfung und Beispiele --------------------------------------------------------

$findings = New-Object Collections.Generic.List[string]
$rows = New-Object Collections.Generic.List[object]

function Add-Finding([string] $Text) {
    $findings.Add($Text)
}

function Get-Property($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-Hashtable($Object) {
    $table = [ordered]@{}
    if ($null -eq $Object) { return $table }
    foreach ($property in $Object.PSObject.Properties) { $table[$property.Name] = $property.Value }
    return $table
}

function Resolve-Placeholders([Collections.IDictionary] $Arguments, [string] $ToolName) {
    # {{zeile:Text}} und {{spalte:Text}} über die Datei in 'file' auflösen (siehe Beispieldatei)
    $lines = $null
    if ($Arguments.Contains('file')) {
        $path = Join-Path $ProjectRoot $Arguments['file']
        if (Test-Path -LiteralPath $path) { $lines = [IO.File]::ReadAllLines($path) }
    }
    foreach ($pass in @('zeile', 'spalte')) {
        foreach ($key in @($Arguments.Keys)) {
            $value = $Arguments[$key]
            if (-not ($value -is [string]) -or $value -notmatch "^\{\{$($pass):(.+)\}\}$") { continue }
            $needle = $Matches[1]
            if ($null -eq $lines) { throw "${ToolName}: Platzhalter $value braucht eine vorhandene Datei in 'file'" }
            if ($pass -eq 'zeile') {
                $index = 0
                while ($index -lt $lines.Length -and -not $lines[$index].Contains($needle)) { $index++ }
                if ($index -ge $lines.Length) { throw "${ToolName}: '$needle' steht nicht in $($Arguments['file'])" }
                $Arguments[$key] = $index + 1
            } else {
                if ("$($Arguments['line'])" -notmatch '^\d+$') { throw "${ToolName}: {{spalte:…}} braucht 'line'" }
                $column = $lines[[int]$Arguments['line'] - 1].IndexOf($needle)
                if ($column -lt 0) { throw "${ToolName}: '$needle' steht nicht in Zeile $($Arguments['line'])" }
                $Arguments[$key] = $column + 1
            }
        }
    }
}

function Get-ResultText($Result) {
    $parts = @()
    foreach ($block in @(Get-Property $Result 'content') + @(Get-Property $Result 'contents')) {
        if ($null -eq $block) { continue }
        $text = Get-Property $block 'text'
        if ($null -ne $text) { $parts += [string]$text }
    }
    return ($parts -join "`n")
}

function Test-ToolSchema($ToolInfo) {
    $name = $ToolInfo.name
    if (-not (Get-Property $ToolInfo 'description')) { Add-Finding "${name}: Beschreibung fehlt" }
    $schema = Get-Property $ToolInfo 'inputSchema'
    if ($null -eq $schema -or (Get-Property $schema 'type') -ne 'object') {
        Add-Finding "${name}: inputSchema fehlt oder ist nicht vom Typ object"
        return
    }
    $properties = Get-Property $schema 'properties'
    $propertyNames = @()
    if ($null -ne $properties) { $propertyNames = @($properties.PSObject.Properties.Name) }
    foreach ($required in @(Get-Property $schema 'required')) {
        if ($null -ne $required -and $propertyNames -notcontains $required) {
            Add-Finding "${name}: Pflichtparameter '$required' fehlt in properties"
        }
    }
    foreach ($propertyName in $propertyNames) {
        if (-not (Get-Property $properties.$propertyName 'description')) {
            Add-Finding "${name}: Parameter '$propertyName' ohne Beschreibung"
        }
    }
}

# --- Ablauf ----------------------------------------------------------------------------------

$exitCode = 0
try {
    try {
        $init = Invoke-Rpc 'initialize' ([ordered]@{
            protocolVersion = '2025-06-18'
            capabilities    = @{}
            clientInfo      = [ordered]@{ name = 'Test-McpTools'; version = '1' }
        })
    } catch {
        Stop-Environment "AtlasServer antwortet nicht auf initialize: $($_.Exception.Message)"
    }
    Send-Message '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    $serverInfo = Get-Property $init.Response.result 'serverInfo'
    Write-Host ("Server: {0} {1}, Protokoll {2}, Ordner {3}" -f (Get-Property $serverInfo 'name'),
        (Get-Property $serverInfo 'version'), $init.Response.result.protocolVersion, $ProjectRoot)

    $toolList = @((Invoke-Rpc 'tools/list' @{}).Response.result.tools)
    $resourceList = @()
    $templateList = @()
    $promptList = @()
    $resourcesResponse = (Invoke-Rpc 'resources/list' @{}).Response
    if ($null -ne (Get-Property $resourcesResponse 'result')) { $resourceList = @($resourcesResponse.result.resources) }
    if ($resourceList.Count -gt 0) {
        # Wer resources anbietet, wird von Clients wie dem Inspector auch nach Vorlagen gefragt.
        $templatesResponse = (Invoke-Rpc 'resources/templates/list' @{}).Response
        if ($null -ne (Get-Property $templatesResponse 'error')) {
            Add-Finding "resources/templates/list: $($templatesResponse.error.message)"
        } else {
            $templateList = @($templatesResponse.result.resourceTemplates)
        }
    }
    if ($null -ne (Get-Property (Get-Property $init.Response.result 'capabilities') 'prompts')) {
        $promptsResponse = (Invoke-Rpc 'prompts/list' @{}).Response
        if ($null -ne (Get-Property $promptsResponse 'error')) {
            Add-Finding "prompts/list: $($promptsResponse.error.message)"
        } else {
            $promptList = @($promptsResponse.result.prompts)
        }
    }
    Write-Host ("{0} Werkzeuge, {1} Ressourcen, {2} Vorlagen, {3} Prompts" -f $toolList.Count, $resourceList.Count,
        $templateList.Count, $promptList.Count)

    $exampleTools = Get-Property $exampleData 'tools'
    $exampleNames = @($exampleTools.PSObject.Properties.Name)
    foreach ($toolInfo in $toolList) {
        Test-ToolSchema $toolInfo
        if ($exampleNames -notcontains $toolInfo.name) {
            Add-Finding "$($toolInfo.name): kein Beispiel in $(Split-Path -Leaf $Examples)"
        }
    }
    foreach ($exampleName in $exampleNames) {
        if (@($toolList | Where-Object { $_.name -eq $exampleName }).Count -eq 0) {
            Write-Host "Hinweis: Beispiel für $exampleName, aber das Werkzeug fehlt in tools/list (abgeschaltet?)" -ForegroundColor Yellow
        }
    }
    if ($Tool -and @($toolList | Where-Object { $_.name -eq $Tool }).Count -eq 0) {
        Add-Finding "${Tool}: nicht in tools/list"
    }

    foreach ($toolInfo in $toolList) {
        $name = $toolInfo.name
        if ($Tool -and $name -ne $Tool) { continue }
        $example = Get-Property $exampleTools $name
        if ($null -eq $example -and -not $Arguments) { continue }
        if ((Get-Property $example 'process') -and -not $WithProcessTools) {
            $rows.Add([pscustomobject]@{ Werkzeug = $name; Ergebnis = 'übersprungen'; Ms = ''; Zeichen = '' })
            continue
        }
        if ($Arguments) {
            $callArgs = [ordered]@{}
            foreach ($key in $Arguments.Keys) { $callArgs[$key] = $Arguments[$key] }
        } else {
            $callArgs = ConvertTo-Hashtable (Get-Property $example 'arguments')
        }
        try {
            Resolve-Placeholders $callArgs $name
            $call = Invoke-Rpc 'tools/call' ([ordered]@{ name = $name; arguments = $callArgs })
        } catch {
            Add-Finding "${name}: $($_.Exception.Message)"
            $rows.Add([pscustomobject]@{ Werkzeug = $name; Ergebnis = 'Fehler'; Ms = ''; Zeichen = '' })
            if (-not $process.HasExited) { continue } else { break }
        }
        $outcome = 'ok'
        $rpcError = Get-Property $call.Response 'error'
        $result = Get-Property $call.Response 'result'
        $text = Get-ResultText $result
        if ($null -ne $rpcError) {
            Add-Finding "${name}: JSON-RPC-Fehler $($rpcError.code): $($rpcError.message)"
            $outcome = 'Fehler'
        } elseif ((Get-Property $result 'isError') -and -not (Get-Property $example 'expectError')) {
            Add-Finding "${name}: isError: $text"
            $outcome = 'isError'
        } elseif ($text.Trim() -eq '') {
            Add-Finding "${name}: leere Antwort"
            $outcome = 'leer'
        } elseif (-not $Arguments -and (Get-Property $example 'contains') -and -not $text.Contains($example.contains)) {
            Add-Finding "${name}: '$($example.contains)' fehlt in der Antwort"
            $outcome = 'Inhalt'
        }
        $rows.Add([pscustomobject]@{ Werkzeug = $name; Ergebnis = $outcome; Ms = $call.Ms; Zeichen = $text.Length })
        if ($Tool) {
            Write-Host '--- Antwort (Text) ---'
            Write-Host $text
        }
    }

    if (-not $Tool) {
        $exampleResources = Get-Property $exampleData 'resources'
        foreach ($resource in $resourceList) {
            $call = Invoke-Rpc 'resources/read' ([ordered]@{ uri = $resource.uri })
            $text = Get-ResultText (Get-Property $call.Response 'result')
            $expected = Get-Property (Get-Property $exampleResources $resource.uri) 'contains'
            $outcome = 'ok'
            if ($null -ne (Get-Property $call.Response 'error') -or $text.Trim() -eq '') {
                Add-Finding "$($resource.uri): Fehler oder leer"
                $outcome = 'Fehler'
            } elseif ($expected -and -not $text.Contains($expected)) {
                Add-Finding "$($resource.uri): '$expected' fehlt"
                $outcome = 'Inhalt'
            }
            $rows.Add([pscustomobject]@{ Werkzeug = $resource.uri; Ergebnis = $outcome; Ms = $call.Ms; Zeichen = $text.Length })
        }

        # Prompts (#1357): Beschreibung je Prompt und Argument, Beispiel über prompts/get.
        $examplePrompts = Get-Property $exampleData 'prompts'
        foreach ($prompt in $promptList) {
            $name = $prompt.name
            if (-not (Get-Property $prompt 'description')) { Add-Finding "Prompt ${name}: Beschreibung fehlt" }
            foreach ($argument in @(Get-Property $prompt 'arguments')) {
                if ($null -ne $argument -and -not (Get-Property $argument 'description')) {
                    Add-Finding "Prompt ${name}: Argument '$($argument.name)' ohne Beschreibung"
                }
            }
            $example = Get-Property $examplePrompts $name
            if ($null -eq $example) {
                Add-Finding "Prompt ${name}: kein Beispiel unter prompts in $(Split-Path -Leaf $Examples)"
                continue
            }
            $promptArgs = ConvertTo-Hashtable (Get-Property $example 'arguments')
            try {
                Resolve-Placeholders $promptArgs $name
                # prompts/get nimmt nur Text als Argumente.
                foreach ($key in @($promptArgs.Keys)) { $promptArgs[$key] = [string]$promptArgs[$key] }
                $call = Invoke-Rpc 'prompts/get' ([ordered]@{ name = $name; arguments = $promptArgs })
            } catch {
                Add-Finding "Prompt ${name}: $($_.Exception.Message)"
                continue
            }
            $text = ''
            $result = Get-Property $call.Response 'result'
            foreach ($message in @(Get-Property $result 'messages')) {
                if ($null -ne $message) { $text += [string](Get-Property (Get-Property $message 'content') 'text') }
            }
            $outcome = 'ok'
            $rpcError = Get-Property $call.Response 'error'
            if ($null -ne $rpcError) {
                Add-Finding "Prompt ${name}: JSON-RPC-Fehler $($rpcError.code): $($rpcError.message)"
                $outcome = 'Fehler'
            } elseif ($text.Trim() -eq '') {
                Add-Finding "Prompt ${name}: leere Nachricht"
                $outcome = 'leer'
            } elseif ((Get-Property $example 'contains') -and -not $text.Contains($example.contains)) {
                Add-Finding "Prompt ${name}: '$($example.contains)' fehlt in der Nachricht"
                $outcome = 'Inhalt'
            }
            $rows.Add([pscustomobject]@{ Werkzeug = "prompt $name"; Ergebnis = $outcome; Ms = $call.Ms; Zeichen = $text.Length })
        }

        # Ressourcenvorlagen (#1357): je Vorlage eine Beispiel-URI lesen.
        $exampleTemplates = Get-Property $exampleData 'templates'
        foreach ($template in $templateList) {
            $example = Get-Property $exampleTemplates $template.uriTemplate
            if ($null -eq $example) {
                Add-Finding "$($template.uriTemplate): kein Beispiel unter templates in $(Split-Path -Leaf $Examples)"
                continue
            }
            $call = Invoke-Rpc 'resources/read' ([ordered]@{ uri = $example.uri })
            $text = Get-ResultText (Get-Property $call.Response 'result')
            $outcome = 'ok'
            if ($null -ne (Get-Property $call.Response 'error') -or $text.Trim() -eq '') {
                Add-Finding "$($example.uri): Fehler oder leer"
                $outcome = 'Fehler'
            } elseif ((Get-Property $example 'contains') -and -not $text.Contains($example.contains)) {
                Add-Finding "$($example.uri): '$($example.contains)' fehlt"
                $outcome = 'Inhalt'
            }
            $rows.Add([pscustomobject]@{ Werkzeug = $example.uri; Ergebnis = $outcome; Ms = $call.Ms; Zeichen = $text.Length })
        }
    }
} finally {
    try { $stdin.Close() } catch { }
    if (-not $process.WaitForExit(10000)) { $process.Kill() }
    $transcriptWriter.Dispose()
}

$rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
foreach ($finding in $findings) { Write-Host "Befund: $finding" -ForegroundColor Red }
Write-Host "Mitschnitt: $Transcript"
if ($findings.Count -gt 0) {
    $exitCode = 1
} else {
    Write-Host 'Alle Werkzeuge in Ordnung.' -ForegroundColor Green
}
exit $exitCode
