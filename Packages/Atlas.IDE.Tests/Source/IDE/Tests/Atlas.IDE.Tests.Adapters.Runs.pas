unit Atlas.IDE.Tests.Adapters.Runs;

// Läufe des Moduls Tests für Base und andere Module (#69, #1120, #763, #764, #1775): TAtlasTestsRuns erfüllt
// IAtlasTestRunner (Auswirkungsanalyse von Base, Willkommensseite), IAtlasTestsSource (Atlas.IDE.Base.Foundation.Tests,
// Karte Tests und Schnellaktionen der Willkommensseite), IAtlasBuildVerdictListener (Tests nach dem Build, nach
// derselben Bewertung wie Zusammenfassung und Benachrichtigung, #530) und IAtlasFollowsSaves (Fenster „Atlas-Tests“
// #1776 und betroffene Tests beim Speichern #1775). Läufer, Debugger-Teil und Tests beim Speichern leben nur,
// solange der Teil Tests läuft; die Composition (Atlas.IDE.Tests.Composition) reicht sie als TAtlasTestsRunsHooks
// herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Plugin.Build.Contract,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.OnSave;

type
  /// <summary>Gespeicherte Datei an das Fenster „Atlas-Tests“.</summary>
  TAtlasTestsFileProc = reference to procedure(const AFileName: string);

  /// <summary>Was die Läufe aus den Teilen der Composition brauchen; Läufer, Debugger-Teil und Tests beim
  /// Speichern sind nil, solange der Teil Tests nicht läuft.</summary>
  TAtlasTestsRunsHooks = record
    Tests: TFunc<TAtlasIdeTests>;
    Debugger: TFunc<TAtlasIdeTestDebugger>;
    OnSave: TFunc<TAtlasIdeTestsOnSave>;
    MutationBusy: TFunc<Boolean>;
    WarnTestsOff: TProc;
    ExplorerFileSaved: TAtlasTestsFileProc;
  end;

  TAtlasTestsRuns = class(TInterfacedObject, IAtlasBuildVerdictListener, IAtlasTestRunner, IAtlasTestsSource,
    IAtlasFollowsSaves)
  private
    FHooks: TAtlasTestsRunsHooks;
  public
    constructor Create(const AHooks: TAtlasTestsRunsHooks);
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
    function RunProject(const ATestProject: string; out AReason: string): Boolean;
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    function LocateByName(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean;
    function Busy: Boolean;
    procedure FileSaved(const AFileName: string);
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.UI.Tests.Strings;

{ TAtlasTestsRuns }

constructor TAtlasTestsRuns.Create(const AHooks: TAtlasTestsRunsHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

procedure TAtlasTestsRuns.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
var
  mTests: TAtlasIdeTests;
begin
  // Tests nach dem Build (#69), nach derselben Bewertung wie Zusammenfassung und Benachrichtigung (#530).
  mTests := FHooks.Tests();
  if mTests <> nil then
  begin
    mTests.BuildFinished(AProject, AVerdict.Effective);
  end;
end;

procedure TAtlasTestsRuns.RunTests(const AFileName: string; const ATests: TArray<string>);
var
  mTests: TAtlasIdeTests;
begin
  mTests := FHooks.Tests();
  if mTests <> nil then
  begin
    mTests.RunTests(AFileName, ATests, False);
  end
  else
  begin
    FHooks.WarnTestsOff();
  end;
end;

function TAtlasTestsRuns.RunProject(const ATestProject: string; out AReason: string): Boolean;
var
  mTests: TAtlasIdeTests;
begin
  mTests := FHooks.Tests();
  if mTests = nil then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonTestsOff);
    Exit(False);
  end;
  Result := mTests.RunProject(ATestProject, AReason);
end;

function TAtlasTestsRuns.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
var
  mDebugger: TAtlasIdeTestDebugger;
begin
  AReason := '';
  Result := False;
  mDebugger := FHooks.Debugger();
  if mDebugger <> nil then
  begin
    Result := mDebugger.DebugByName(AProject, AFullName, AReason);
  end;
end;

function TAtlasTestsRuns.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  Result := TAtlasIdeTestDebugger.LocateByName(AProject, AFullName, AFileName, ALine);
end;

function TAtlasTestsRuns.Busy: Boolean;
var
  mTests: TAtlasIdeTests;
begin
  mTests := FHooks.Tests();
  Result := ((mTests <> nil) and mTests.Busy) or FHooks.MutationBusy();
end;

procedure TAtlasTestsRuns.FileSaved(const AFileName: string);
var
  mOnSave: TAtlasIdeTestsOnSave;
begin
  // Fenster „Atlas-Tests“ (#1776): gespeicherte Testunit neu lesen.
  FHooks.ExplorerFileSaved(AFileName);
  // Betroffene Tests beim Speichern (#1775).
  mOnSave := FHooks.OnSave();
  if mOnSave <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        mOnSave.FileSaved(AFileName);
      end);
  end;
end;

end.
