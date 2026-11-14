unit Atlas.IDE.Tests.Composition.Explorer;

// Fenster „Atlas-Tests“ (#1776) mit Testlisten (#2167), Teststand in der Statusleiste (#1777) und dem Verlauf der
// wackelnden Tests (#1773), aus Atlas.IDE.Tests.Composition gelöst; die Composition startet und stoppt sie mit dem
// Läufer:
// - Befehle „Atlas-Tests“ und „Wackelnde Tests zeigen“ (#1773, Filter „wackelt“),
// - je Testliste ein Befehl „Testliste ausführen: <Name>“ und die Taste tests.lists.runKey für die zuletzt
//   benutzte,
// - Einstellungen, Farbschema und gespeicherte Testunits reicht die Composition herein.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Series;

/// <summary>Wackelnde Tests, Testlisten, Fenster und Teststand anlegen; das Fenster hängt sich als OnReported an
/// ATests und reicht jeden Lauf an die wackelnden Tests, die an ANext. Veraltete Tests nach AStaleKeys. ATests,
/// ADebugger und ASeries leben länger.</summary>
procedure StartExplorer(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger; ASeries: TAtlasIdeTestSeries;
  const AStaleKeys: TAtlasTestStaleKeys; const ANext: TAtlasTestsReportedProc);
/// <summary>Abfragen veralteter (AStaleKeys) und wackelnder Tests, etwa für die Testlinse.</summary>
function StateQueries(const AStaleKeys: TAtlasTestStaleKeys): TAtlasTestStateQueries;
/// <summary>Teststand, Fenster und Testlisten freigeben (in dieser Reihenfolge: Der Teststand liest aus dem
/// Fenster, das Fenster findet die Testlisten).</summary>
procedure StopExplorer;
/// <summary>Wackelnde Tests freigeben; nach Fenster und allem, was StateQueries abfragt.</summary>
procedure StopFlakyTests;
/// <summary>Befehl „Atlas-Tests“ sichtbar: tests.run, tests.window und Fenster angelegt.</summary>
function ExplorerVisible: Boolean;
procedure ShowExplorer;
/// <summary>Befehl „Wackelnde Tests zeigen“ sichtbar: zusätzlich tests.flaky.</summary>
function FlakyVisible: Boolean;
procedure ShowFlaky;
/// <summary>Je Testliste des gewählten Testprojekts ein Befehl der Palette.</summary>
function ListCommands: TArray<TAtlasModuleCommand>;
/// <summary>Taste für die zuletzt benutzte Testliste; leer ohne tests.lists oder ohne Taste.</summary>
function ListKeys: TArray<TAtlasModuleKey>;
/// <summary>tests.window, tests.lists und editor.statusBar.tests neu anwenden.</summary>
procedure ApplyExplorerSettings;
procedure ExplorerThemeChanged;
/// <summary>Gespeicherte Testunit im Fenster neu lesen.</summary>
procedure ExplorerFileSaved(const AFileName: string);

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Explorer,
  Atlas.IDE.Tests.Flaky,
  Atlas.IDE.Tests.Lists,
  Atlas.IDE.Tests.StatusField,
  Atlas.UI.Tests.Strings;

var
  GFlaky: TAtlasIdeFlakyTests;
  GExplorer: TAtlasIdeTestExplorer;
  GLists: TAtlasIdeTestLists;
  GStatusField: TAtlasIdeTestStatusField;

procedure StartExplorer(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger; ASeries: TAtlasIdeTestSeries;
  const AStaleKeys: TAtlasTestStaleKeys; const ANext: TAtlasTestsReportedProc);
begin
  // Wackelnde Tests (#1773): Verlauf je Test.
  GFlaky := TAtlasIdeFlakyTests.Create(ATests, ANext);
  // Testlisten (#2167): vor dem Fenster, das sie über TAtlasIdeTestLists.Instance findet, und nach ihm frei.
  GLists := TAtlasIdeTestLists.Create(ATests);
  GExplorer := TAtlasIdeTestExplorer.Create(ATests, ADebugger, ASeries, GFlaky.QueriesWith(AStaleKeys),
    GFlaky.Remember);
  ATests.OnReported := GExplorer.Remember;
  GStatusField := TAtlasIdeTestStatusField.Create(ATests, GExplorer);
end;

function StateQueries(const AStaleKeys: TAtlasTestStaleKeys): TAtlasTestStateQueries;
begin
  Result := GFlaky.QueriesWith(AStaleKeys);
end;

procedure StopExplorer;
begin
  FreeAndNil(GStatusField);
  FreeAndNil(GExplorer);
  FreeAndNil(GLists);
end;

procedure StopFlakyTests;
begin
  FreeAndNil(GFlaky);
end;

{ Fenster „Atlas-Tests“ (#1776) }

/// <summary>Fenster „Atlas-Tests“ mit allen Tests.</summary>
procedure ShowAll;
begin
  GExplorer.Show(False);
end;

/// <summary>Fenster „Atlas-Tests“ nur mit wackelnden Tests (#1773).</summary>
procedure ShowFlakyOnly;
begin
  GExplorer.Show(True);
end;

function ExplorerVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeTestExplorer.Wanted and (GExplorer <> nil);
end;

procedure ShowExplorer;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, ShowAll);
  end;
end;

function FlakyVisible: Boolean;
begin
  Result := ExplorerVisible and TAtlasIdeSettings.Current.TestsFlaky;
end;

procedure ShowFlaky;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, ShowFlakyOnly);
  end;
end;

{ Testlisten (#2167) }

/// <summary>Befehl „Testliste ausführen: AName“; eigene Routine, damit jeder Befehl seinen Namen fängt.</summary>
function ListCommand(const AName: string): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := 'Atlas.RunTestList:' + AName;
  Result.Caption := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsRunCommand, [AName]);
  Result.Description := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRunCommandHint);
  Result.Run :=
    procedure
    begin
      if GLists <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            GLists.RunByName(AName);
          end);
      end;
    end;
end;

function ListCommands: TArray<TAtlasModuleCommand>;
var
  mName: string;
begin
  Result := nil;
  // Die Testlisten leben mit dem Läufer; dazu tests.run.
  if (GLists = nil) or not TAtlasIdeSettings.Current.TestRun then
  begin
    Exit;
  end;
  for mName in GLists.Names do
  begin
    Result := Result + [ListCommand(mName)];
  end;
end;

/// <summary>Zuletzt benutzte Testliste ausführen; False ohne eine (die Taste geht dann an die IDE).</summary>
function RunLastList: Boolean;
begin
  Result := (GLists <> nil) and GLists.RunLast;
end;

function ListKeys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  // Zuletzt benutzte Testliste (#2167): ohne Liste geht die Taste an die IDE weiter.
  if not TAtlasIdeTestLists.Wanted or (TAtlasIdeSettings.Current.TestsListsRunKey = 0) then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.RunLastTestList';
  mKey.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRunLast);
  mKey.Key := TAtlasIdeSettings.Current.TestsListsRunKey;
  mKey.Attempt := RunLastList;
  Result := [mKey];
end;

{ Einstellungen und Ereignisse }

procedure ApplyExplorerSettings;
begin
  // tests.window aus (#1776): Fenster weg.
  if GExplorer <> nil then
  begin
    GExplorer.ApplySettings;
  end;
  // tests.lists (#2167): Reiter zeigen bzw. verbergen.
  if GLists <> nil then
  begin
    GLists.ApplySettings;
  end;
  // editor.statusBar.tests (#1777): Feld neu bzw. weg.
  if GStatusField <> nil then
  begin
    GStatusField.ApplySettings;
  end;
end;

procedure ExplorerThemeChanged;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, TAtlasIdeTestExplorer.ThemeChanged);
  end;
end;

procedure ExplorerFileSaved(const AFileName: string);
begin
  // Gespeicherte Testunit neu lesen.
  if GExplorer <> nil then
  begin
    GExplorer.FileSaved(AFileName);
  end;
end;

end.
