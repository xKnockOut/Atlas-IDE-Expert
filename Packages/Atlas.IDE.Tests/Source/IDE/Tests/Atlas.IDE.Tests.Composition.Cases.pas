unit Atlas.IDE.Tests.Composition.Cases;

// Testfälle bearbeiten und anlegen, aus Atlas.IDE.Tests.Composition gelöst; die Composition startet und stoppt
// sie mit dem Läufer:
// - TestCase-Tabelle (#1879): Befehl „TestCase-Tabelle bearbeiten …“ und Marke „Tabelle“ der Testlinse;
// - Grenzfälle als Testfälle (#2173): Befehl „Grenzfälle vorschlagen …“; sein Haken Remember steht vorn in
//   OnReported des Läufers und reicht jeden Lauf an den bisherigen Haken weiter;
// - Ungetestete Methoden des Projekts (#1783) und Test aus dem Debug-Halt (#1873).

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.CoveredBy;

/// <summary>Tabelle, Grenzfälle und ungetestete Methoden anlegen; nach dem Setzen der übrigen Haken von
/// OnReported rufen. AOutput lebt länger.</summary>
procedure StartCases(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
  AOutput: TAtlasIdeTestsOutput; const AScopeOf: TAtlasCoveredByScopeFunc);
/// <summary>Freigeben; nimmt den Haken OnReported von ATests (nil erlaubt) zurück.</summary>
procedure StopCases(ATests: TAtlasIdeTests);
/// <summary>TestCase-Tabelle der Testmethode an ALine der Datei AFileName (Marke der Testlinse).</summary>
procedure OpenCaseTable(const AFileName: string; ALine: Integer);
/// <summary>Befehl „TestCase-Tabelle bearbeiten …“ sichtbar (ohne tests.run-Prüfung des Läufers).</summary>
function CaseTableWanted: Boolean;
procedure EditCaseTable;
/// <summary>Befehl „Grenzfälle vorschlagen …“ sichtbar.</summary>
function BoundaryCasesWanted: Boolean;
procedure SuggestBoundaryCases;
/// <summary>Befehl „Ungetestete Methoden des Projekts“ (#1783).</summary>
procedure ListUntested;
/// <summary>Kennung, Sichtbarkeit und Aktion von „Test aus dem Debug-Halt anlegen …“ (#1873).</summary>
function TestFromDebugCommand: string;
function TestFromDebugVisible: Boolean;
procedure RunTestFromDebug(const AScope: IAtlasModuleScope);

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Tests.CaseTable,
  Atlas.IDE.Tests.BoundaryCases,
  Atlas.IDE.Tests.UntestedProject,
  Atlas.IDE.Tests.FromDebugStop;

var
  GCaseTable: TAtlasIdeTestCaseTable;
  GBoundary: TAtlasIdeBoundaryCases;
  GUntested: TAtlasIdeUntestedProject;

procedure StartCases(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
  AOutput: TAtlasIdeTestsOutput; const AScopeOf: TAtlasCoveredByScopeFunc);
begin
  GUntested := TAtlasIdeUntestedProject.Create(AOutput, AScopeOf);
  GCaseTable := TAtlasIdeTestCaseTable.Create(AScope, ATests, ADebugger);
  GBoundary := TAtlasIdeBoundaryCases.Create(AScope, ATests, ATests.OnReported);
  ATests.OnReported := GBoundary.Remember;
end;

procedure StopCases(ATests: TAtlasIdeTests);
begin
  if ATests <> nil then
  begin
    ATests.OnReported := nil;
  end;
  FreeAndNil(GBoundary);
  FreeAndNil(GCaseTable);
  FreeAndNil(GUntested);
end;

procedure OpenCaseTable(const AFileName: string; ALine: Integer);
begin
  if GCaseTable <> nil then
  begin
    GCaseTable.OpenAt(AFileName, ALine);
  end;
end;

function CaseTableWanted: Boolean;
begin
  Result := TAtlasIdeTestCaseTable.Wanted and (GCaseTable <> nil);
end;

procedure EditCaseTable;
begin
  if GCaseTable <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GCaseTable.OpenAtCursor);
  end;
end;

function BoundaryCasesWanted: Boolean;
begin
  Result := TAtlasIdeBoundaryCases.Wanted and (GBoundary <> nil);
end;

procedure SuggestBoundaryCases;
begin
  if GBoundary <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GBoundary.OpenAtCursor);
  end;
end;


procedure ListUntested;
begin
  if GUntested <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GUntested.Run);
  end;
end;

function TestFromDebugCommand: string;
begin
  Result := TAtlasIdeTestFromDebug.cCommand;
end;

function TestFromDebugVisible: Boolean;
begin
  Result := TAtlasIdeTestFromDebug.Visible;
end;

procedure RunTestFromDebug(const AScope: IAtlasModuleScope);
begin
  TAtlasIdeTestFromDebug.Run(AScope);
end;

end.
