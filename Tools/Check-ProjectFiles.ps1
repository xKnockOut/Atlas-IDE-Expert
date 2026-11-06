<#
.SYNOPSIS
    Prüft, dass MSBuild alle Projektdateien (.dproj, .groupproj) lesen kann.

.DESCRIPTION
    Die Delphi-IDE übergeht manche Fehler in Projektdateien, MSBuild nicht.
    AtlasUpdate baut das Plugin für Delphi 12 mit MSBuild aus dem Quelltext
    (#1519); 2.0.0-beta.1 scheiterte dort mit MSB4066, weil drei
    DCCReference-Zeilen mitten in einem Formular-Eintrag standen.

    Geprüft wird:
    - Jede Projektdatei ist gültiges XML.
    - DCCReference steht direkt in einer ItemGroup und hat Include.
    - Elemente innerhalb eines Eintrags (Metadaten wie Form, FormType) haben
      keine Attribute und heißen nicht DCCReference.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-ProjectFiles.ps1

.EXAMPLE
    pwsh Tools/Check-ProjectFiles.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Violations([string] $Text) {
    $Found = [System.Collections.Generic.List[string]]::new()
    $Xml = [xml]::new()
    try {
        $Xml.LoadXml($Text)
    } catch {
        $Found.Add("kein gültiges XML: $($_.Exception.Message)")
        return $Found
    }
    foreach ($Group in $Xml.GetElementsByTagName('ItemGroup')) {
        foreach ($Item in $Group.ChildNodes) {
            if ($Item.NodeType -ne [Xml.XmlNodeType]::Element) {
                continue
            }
            if ($Item.LocalName -eq 'DCCReference' -and -not $Item.HasAttribute('Include')) {
                $Found.Add('DCCReference ohne Include')
            }
            foreach ($Meta in $Item.ChildNodes) {
                if ($Meta.NodeType -ne [Xml.XmlNodeType]::Element) {
                    continue
                }
                $Name = "<$($Meta.LocalName)> in <$($Item.LocalName) Include=""$($Item.GetAttribute('Include'))"">"
                if ($Meta.LocalName -eq 'DCCReference') {
                    $Found.Add("$Name (Eintrag im Eintrag)")
                } elseif ($Meta.Attributes.Count -gt 0) {
                    $Found.Add("$Name mit Attribut (MSB4066)")
                }
            }
        }
    }
    foreach ($Reference in $Xml.GetElementsByTagName('DCCReference')) {
        if ($Reference.ParentNode.LocalName -notin 'ItemGroup', 'DCCReference') {
            $Found.Add("DCCReference außerhalb einer ItemGroup (in <$($Reference.ParentNode.LocalName)>)")
        }
    }
    $Found
}

if ($SelfTest) {
    $Head = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><ItemGroup>'
    $Tail = '</ItemGroup></Project>'
    $Cases = @(
        @{ Text = '<DCCReference Include="a.pas"/><DCCReference Include="b.pas"><Form>F</Form></DCCReference>'; Count = 0 },
        @{ Text = '<DCCReference Include="b.pas"><DCCReference Include="c.pas"/><Form>F</Form></DCCReference>'; Count = 1 },
        @{ Text = '<DCCReference Include="b.pas"><DCCReference/></DCCReference>'; Count = 1 },
        @{ Text = '<DCCReference Include="b.pas"><Form Name="x">F</Form></DCCReference>'; Count = 1 },
        @{ Text = '<DCCReference/>'; Count = 1 }
    )
    $Failed = 0
    foreach ($Case in $Cases) {
        $Got = @(Get-Violations ($Head + $Case.Text + $Tail)).Count
        if ($Got -ne $Case.Count) {
            Write-Host "FEHLER: $($Case.Text): $Got statt $($Case.Count) Verstöße"
            $Failed++
        }
    }
    if (@(Get-Violations '<Project><ItemGroup>').Count -ne 1) {
        Write-Host 'FEHLER: ungültiges XML nicht erkannt'
        $Failed++
    }
    if ($Failed -gt 0) {
        exit 1
    }
    Write-Host 'Selbsttest der Projektdatei-Prüfung bestanden.' -ForegroundColor Green
    exit 0
}

$Violations = [System.Collections.Generic.List[string]]::new()
$Files = @(Get-ChildItem -Path $Root -Recurse -File -Include '*.dproj', '*.groupproj' |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|Output|__history)[\\/]' })
foreach ($File in $Files) {
    $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName)
    foreach ($Violation in @(Get-Violations ([IO.File]::ReadAllText($File.FullName)))) {
        $Violations.Add("${Relative}: $Violation")
    }
}

if ($Violations.Count -gt 0) {
    Write-Host 'Projektdateien, an denen MSBuild scheitert:' -ForegroundColor Red
    $Violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "$($Files.Count) Projektdateien für MSBuild lesbar." -ForegroundColor Green
exit 0
