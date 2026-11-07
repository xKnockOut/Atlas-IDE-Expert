unit Atlas.IDE.Tests.Debug;

// Einzelnen DUnitX-Test im Debugger starten bzw. ohne Debugger ausführen
// (#585). Auswahl, Filter und Startparameter in Atlas.Core.Tests.Debug.
// Ablauf von „Test debuggen“ (Code Lens, Befehl „Test am Cursor debuggen“,
// Kontextmenü, Willkommensseite #763):
// 1. Testprojekt über den Läufer (#69): das Projekt der Testunit, sonst das
//    aktive bzw. das der Gruppe; bei mehreren fragt Atlas einmal und merkt
//    sich die Wahl.
// 2. Bauen (make über den Build-Dienst #261; das Ende meldet der
//    Ereignisdienst #527). Ohne Build-Dienst baut „Start“ der IDE selbst.
// 3. Aktives Projekt merken; Startparameter vorübergehend auf
//    --run:<Namen> --exitbehavior:Continue --xmlfile:<temp> setzen und „Start“
//    auslösen, beides über die Startprofile (#575, RunTemporary).
// 4. Mit debug.testBreakAtStart: einmaliger Haltepunkt an der ersten
//    Anweisung der Methode (nur wenn dort noch keiner steht); beim ersten Halt
//    entfernt Atlas ihn wieder.
// 5. Ein Zeitgeber wartet auf den Prozess und auf sein Ende; dann stellt Atlas
//    Startparameter und aktives Projekt wieder her und meldet das Ergebnis aus
//    dem XML-Bericht wie „Tests ausführen“. Startet kein Prozess innerhalb von
//    60 s, stellt Atlas ebenfalls zurück.
// „Test ausführen“ läuft ohne Debugger über den Läufer (#69).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestDebugger = class
  private type
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Building, Starting, Running);
    {$SCOPEDENUMS OFF}
    /// <summary>Lebt, solange der Debugger-Teil lebt; Rückrufe prüfen es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private const
    cTickMs = 250;
  private
    FTests: TAtlasIdeTests;
    FAlive: TAlive;
    FAliveRef: IInterface;
    FTimer: TTimer;
    FPhase: TPhase;
    FTarget: TAtlasTestTarget;
    FSelection: TAtlasTestSelection;
    FUnitFile: string;
    FPreviousProject: string;
    FXmlFile: string;
    FBreakpoint: IOTABreakpoint;
    FStartedAt: Cardinal;
    procedure Tick(Sender: TObject);
    procedure TickStarting(const AServices: IOTADebuggerServices);
    procedure TickRunning(const AServices: IOTADebuggerServices);
    /// <summary>Bauen bzw. starten; False mit Grund, wenn es nicht geht (beschäftigt, Plattform, Build abgelehnt).
    /// </summary>
    function Prepare(const AProject: IOTAProject; out AReason: string): Boolean;
    /// <summary>Build anstossen; False mit Grund, wenn der Build-Dienst ablehnt.</summary>
    function StartBuild(out AReason: string): Boolean;
    procedure BuildDone(ASucceeded: Boolean; const AOutputFile, AError: string);
    procedure Launch(const AExecutable: string);
    procedure Finish(AStarted: Boolean);
    procedure SetBreakpoint;
    procedure RemoveBreakpoint;
    procedure RestoreActiveProject;
    function Say(const AText: string): Boolean;
    class function Debugger: IOTADebuggerServices; static;
    class function Debugging: Boolean; static;
    class function ProjectOf(const AFileName: string): IOTAProject; static;
    class function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean; static;
    /// <summary>Datei und Test am Cursor der oberen Editoransicht; False mit Meldung.</summary>
    function AtCursor(out AFileName: string; out ASelection: TAtlasTestSelection): Boolean;
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger als dieses Objekt.</summary>
    constructor Create(ATests: TAtlasIdeTests);
    destructor Destroy; override;
    /// <summary>Test ASelection aus der Testunit AFileName im Debugger starten (Code Lens).</summary>
    procedure Debug(const AFileName: string; const ASelection: TAtlasTestSelection);
    /// <summary>Test ASelection aus AFileName ohne Debugger ausführen (Ergebnis wie #69).</summary>
    procedure Run(const AFileName: string; const ASelection: TAtlasTestSelection);
    /// <summary>Befehl und Kontextmenü: Test am Cursor im Debugger.</summary>
    procedure DebugAtCursor;
    /// <summary>Befehl und Kontextmenü: Test am Cursor ohne Debugger.</summary>
    procedure RunAtCursor;
    /// <summary>Für die Willkommensseite (#763, „Im Debugger“): Test AFullName (Unit.Fixture.Methode[.Fall]) des
    /// geöffneten Testprojekts AProject im Debugger starten. False mit Grund, wenn das Projekt nicht offen ist oder
    /// den Test nicht enthält.</summary>
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    /// <summary>Für die Willkommensseite (#763, Doppelklick auf einen Fehlschlag vom Build-Server): Datei und
    /// Zeile (ab 1, Methodenkopf) des Tests AFullName (Unit.Fixture.Methode[.Fall] bzw. Fixture.Methode) im
    /// Testprojekt AProject (offen oder neben der .dproj). False ohne Fundstelle.</summary>
    class function LocateByName(const AProject, AFullName: string; out AFileName: string;
      out ALine: Integer): Boolean; static;
    /// <summary>Eine Sitzung (Build, Start oder Lauf) ist im Gange.</summary>
    function Busy: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.UI.Strings,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

{ TAtlasIdeTestDebugger }

constructor TAtlasIdeTestDebugger.Create(ATests: TAtlasIdeTests);
begin
  inherited Create;
  FTests := ATests;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeTestDebugger.Destroy;
var
  mChanged: Boolean;
begin
  FAlive.Alive := False;
  FTimer.Free;
  // Beim Entladen mitten in einer Sitzung: Haltepunkt weg, Startparameter zurück (sonst beim nächsten Mal über
  // den Eintrag in der lokalen Datei der Startprofile).
  if FPhase in [TPhase.Starting, TPhase.Running] then
  begin
    RemoveBreakpoint;
    if not Debugging then
    begin
      TAtlasIdeStartOptions.EndTemporary(FTarget.Project, mChanged);
    end;
  end;
  if FPhase <> TPhase.Idle then
  begin
    FTests.Debugging := False;
  end;
  FAliveRef := nil;
  inherited Destroy;
end;

function TAtlasIdeTestDebugger.Say(const AText: string): Boolean;
begin
  FTests.Say(AText);
  Result := False;
end;

class function TAtlasIdeTestDebugger.Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeTestDebugger.Debugging: Boolean;
var
  mServices: IOTADebuggerServices;
begin
  mServices := Debugger;
  Result := (mServices <> nil) and (mServices.ProcessCount > 0);
end;

class function TAtlasIdeTestDebugger.ProjectOf(const AFileName: string): IOTAProject;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Supports(mServices.FindModule(AFileName), IOTAProject, Result);
  end;
end;

class function TAtlasIdeTestDebugger.ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  ALines := nil;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    mText := TAtlasEditorBuffer.Text(mBuffer);
  end
  else
  begin
    if not FileExists(AFileName) then
    begin
      Exit(False);
    end;
    try
      mText := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(mText);
  Result := True;
end;

function TAtlasIdeTestDebugger.Busy: Boolean;
begin
  Result := FPhase <> TPhase.Idle;
end;

function TAtlasIdeTestDebugger.AtCursor(out AFileName: string; out ASelection: TAtlasTestSelection): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  AFileName := '';
  ASelection := Default(TAtlasTestSelection);
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Exit(Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoTestAtCursor)));
  end;
  AFileName := mView.Buffer.FileName;
  Result := TAtlasTestDebug.SelectAt(TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer))),
    mView.CursorPos.Line - 1, ASelection) and (Length(ASelection.Names) > 0);
  if not Result then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoTestAtCursor));
  end;
end;

procedure TAtlasIdeTestDebugger.RunAtCursor;
var
  mFileName: string;
  mSelection: TAtlasTestSelection;
begin
  if not TAtlasTestDebug.RunWanted(TAtlasIdeSettings.Current) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
    Exit;
  end;
  if AtCursor(mFileName, mSelection) then
  begin
    Run(mFileName, mSelection);
  end;
end;

procedure TAtlasIdeTestDebugger.DebugAtCursor;
var
  mFileName: string;
  mSelection: TAtlasTestSelection;
begin
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugOff));
    Exit;
  end;
  if AtCursor(mFileName, mSelection) then
  begin
    Debug(mFileName, mSelection);
  end;
end;

procedure TAtlasIdeTestDebugger.Run(const AFileName: string; const ASelection: TAtlasTestSelection);
begin
  if not TAtlasTestDebug.RunWanted(TAtlasIdeSettings.Current) or (Length(ASelection.Names) = 0) then
  begin
    Exit;
  end;
  FTests.RunTests(AFileName, ASelection.Names);
end;

procedure TAtlasIdeTestDebugger.Debug(const AFileName: string; const ASelection: TAtlasTestSelection);
var
  mAlive: TAlive;
  mKeep: IInterface;
begin
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) or (Length(ASelection.Names) = 0) then
  begin
    Exit;
  end;
  if Busy then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugBusy));
    Exit;
  end;
  if FTests.Busy then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
    Exit;
  end;
  if Debugging then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugRunning));
    Exit;
  end;
  FSelection := ASelection;
  FUnitFile := AFileName;
  mAlive := FAlive;
  mKeep := FAliveRef;
  FTests.ResolveProject(AFileName,
    procedure(const AProject: IOTAProject)
    var
      Reason: string;
    begin
      if (mKeep = nil) or not mAlive.Alive then
      begin
        Exit;
      end;
      if not Prepare(AProject, Reason) then
      begin
        Say(Reason);
      end;
    end);
end;

function TAtlasIdeTestDebugger.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
var
  mProject: IOTAProject;
  mName, mUnitName, mFileName: string;
  mIndex: Integer;
  mLines: TArray<string>;
  mSelection: TAtlasTestSelection;
begin
  AReason := '';
  Result := False;
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugOff);
    Exit;
  end;
  mProject := ProjectOf(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // Der Unitname kann Punkte enthalten: jede Teilung von hinten versuchen (Unit.Fixture.Methode[.Fall]).
  mName := Trim(AFullName);
  for mIndex := Length(mName) downto 1 do
  begin
    if mName[mIndex] <> '.' then
    begin
      Continue;
    end;
    mUnitName := Copy(mName, 1, mIndex - 1);
    mFileName := TAtlasIdeTests.UnitFileOf(mProject.FileName, mUnitName);
    if (mFileName = '') or not ReadLines(mFileName, mLines) then
    begin
      Continue;
    end;
    if TAtlasTestDebug.SelectByName(TDUnitXSource.Scan(mLines), mName, mSelection) and
      (Length(mSelection.Names) > 0) then
    begin
      if Busy or FTests.Busy or Debugging then
      begin
        AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugBusy);
        Exit;
      end;
      FSelection := mSelection;
      FUnitFile := mFileName;
      Exit(Prepare(mProject, AReason));
    end;
  end;
  AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoTestAtCursor);
end;

class function TAtlasIdeTestDebugger.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
var
  mName, mUnitName, mFileName: string;
  mIndex, mLine: Integer;
  mLines: TArray<string>;
  mFound: TDUnitXUnit;
  mSelection: TAtlasTestSelection;
begin
  AFileName := '';
  ALine := 0;
  Result := False;
  mName := Trim(AFullName);
  // Wie DebugByName: jede Teilung von hinten als Unitname versuchen.
  for mIndex := Length(mName) downto 1 do
  begin
    if mName[mIndex] <> '.' then
    begin
      Continue;
    end;
    mUnitName := Copy(mName, 1, mIndex - 1);
    mFileName := TAtlasIdeTests.UnitFileOf(AProject, mUnitName);
    if (mFileName = '') or not ReadLines(mFileName, mLines) then
    begin
      Continue;
    end;
    mFound := TDUnitXSource.Scan(mLines);
    if not TAtlasTestDebug.SelectByName(mFound, mName, mSelection) then
    begin
      Continue;
    end;
    mLine := mFound.LineOf(mSelection.Fixture, mSelection.Method);
    AFileName := mFileName;
    if mLine >= 0 then
    begin
      ALine := mLine + 1;
    end;
    Exit(True);
  end;
end;

function TAtlasIdeTestDebugger.Prepare(const AProject: IOTAProject; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
  if Busy or FTests.Busy or Debugging then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugBusy);
    Exit;
  end;
  FTarget := TAtlasIdeTests.TargetOf(AProject, FSelection.Names);
  if not TAtlasTestRun.CanRun(FTarget.Platform) then
  begin
    AReason := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsPlatform,
      [ProjectName(FTarget.Project), FTarget.Platform]);
    Exit;
  end;
  Result := True;
  FPreviousProject := '';
  if GetActiveProject <> nil then
  begin
    FPreviousProject := GetActiveProject.FileName;
  end;
  FPhase := TPhase.Building;
  FTests.Debugging := True;
  // Ohne Build-Dienst baut „Start“ der IDE selbst.
  if not FTests.CanBuild then
  begin
    Launch('');
  end
  else if not StartBuild(AReason) then
  begin
    FPhase := TPhase.Idle;
    FTests.Debugging := False;
    Result := False;
  end;
end;

function TAtlasIdeTestDebugger.StartBuild(out AReason: string): Boolean;
var
  mAlive: TAlive;
  mKeep: IInterface;
  mReason: string;
begin
  AReason := '';
  mAlive := FAlive;
  mKeep := FAliveRef;
  Result := FTests.BuildProject(FTarget.Project,
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      if (mKeep <> nil) and mAlive.Alive and (FPhase = TPhase.Building) then
      begin
        BuildDone(ASucceeded, AOutputFile, AError);
      end;
    end, mReason);
  if not Result then
  begin
    AReason := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildRefused, [ProjectName(FTarget.Project), mReason]);
  end;
end;

procedure TAtlasIdeTestDebugger.BuildDone(ASucceeded: Boolean; const AOutputFile, AError: string);
var
  mOutputFile: string;
begin
  mOutputFile := AOutputFile;
  if AError <> '' then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildRefused, [ProjectName(FTarget.Project), AError]));
    Finish(False);
  end
  else if not ASucceeded then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildFailed, [ProjectName(FTarget.Project)]));
    Finish(False);
  end
  else
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Launch(mOutputFile);
      end);
  end;
end;

procedure TAtlasIdeTestDebugger.Launch(const AExecutable: string);
var
  mNames: TArray<string>;
  mXmlFile, mReason: string;
begin
  if AExecutable <> '' then
  begin
    FTarget.Executable := AExecutable;
  end;
  if Debugging then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsDebugRunning));
    Finish(False);
    Exit;
  end;
  mNames := FSelection.Names;
  mXmlFile := TPath.Combine(TPath.GetTempPath, 'atlas-debug-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
  FXmlFile := mXmlFile;
  if TAtlasTestDebug.BreakWanted(TAtlasIdeSettings.Current, FSelection) then
  begin
    SetBreakpoint;
  end;
  Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugStarted, [ProjectName(FTarget.Project), FSelection.Caption,
    FTarget.Configuration, FTarget.Platform]));
  FPhase := TPhase.Starting;
  FStartedAt := GetTickCount;
  if not TAtlasIdeStartOptions.RunTemporary(FTarget.Project,
    function(AExisting: string): string
    begin
      Result := TAtlasTestDebug.Parameters(AExisting, mNames, mXmlFile);
    end, True, mReason) then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugFailed, [ProjectName(FTarget.Project), mReason]));
    // RunTemporary hat die Parameter schon zurückgestellt, das aktive Projekt aber vielleicht gewechselt.
    RestoreActiveProject;
    FPhase := TPhase.Building;
    Finish(False);
    Exit;
  end;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeTestDebugger.SetBreakpoint;
var
  mServices: IOTADebuggerServices;
  mIndex, mLine: Integer;
  mExisting: IOTASourceBreakpoint;
begin
  FBreakpoint := nil;
  mServices := Debugger;
  if (mServices = nil) or (FUnitFile = '') or (FSelection.BreakLine < 0) then
  begin
    Exit;
  end;
  mLine := FSelection.BreakLine + 1;
  // Ein Haltepunkt des Benutzers an derselben Stelle bleibt, wie er ist.
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mExisting := mServices.SourceBkpts[mIndex];
    if (mExisting <> nil) and SameText(mExisting.FileName, FUnitFile) and (mExisting.LineNumber = mLine) then
    begin
      Exit;
    end;
  end;
  try
    FBreakpoint := mServices.NewSourceBreakpoint(FUnitFile, mLine, nil);
    if FBreakpoint <> nil then
    begin
      Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugBreak, [mLine]));
    end;
  except
    on Exception do
      FBreakpoint := nil;
  end;
end;

procedure TAtlasIdeTestDebugger.RemoveBreakpoint;
var
  mServices: IOTADebuggerServices;
begin
  if FBreakpoint = nil then
  begin
    Exit;
  end;
  mServices := Debugger;
  try
    if mServices <> nil then
    begin
      mServices.RemoveBreakpoint(FBreakpoint);
    end;
  finally
    FBreakpoint := nil;
  end;
end;

procedure TAtlasIdeTestDebugger.RestoreActiveProject;
var
  mServices: IOTAModuleServices;
  mPrevious: IOTAProject;
begin
  if FPreviousProject = '' then
  begin
    Exit;
  end;
  mPrevious := ProjectOf(FPreviousProject);
  if (mPrevious <> nil) and Supports(BorlandIDEServices, IOTAModuleServices, mServices) and
    (mServices.MainProjectGroup <> nil) and (mServices.MainProjectGroup.ActiveProject <> mPrevious) then
  begin
    mServices.MainProjectGroup.ActiveProject := mPrevious;
  end;
end;

procedure TAtlasIdeTestDebugger.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    var
      mServices: IOTADebuggerServices;
    begin
      mServices := Debugger;
      case FPhase of
        TPhase.Starting:
          TickStarting(mServices);
        TPhase.Running:
          TickRunning(mServices);
      end;
    end);
end;

procedure TAtlasIdeTestDebugger.TickStarting(const AServices: IOTADebuggerServices);
begin
  if (AServices <> nil) and (AServices.ProcessCount > 0) then
  begin
    FPhase := TPhase.Running;
  end
  // Schneller als ein Takt gelaufen: der Bericht ist schon da.
  else if (FXmlFile <> '') and FileExists(FXmlFile) then
  begin
    Finish(True);
  end
  else if GetTickCount - FStartedAt > TAtlasTestDebug.cStartTimeoutMs then
  begin
    Finish(False);
  end;
end;

procedure TAtlasIdeTestDebugger.TickRunning(const AServices: IOTADebuggerServices);
var
  mProcess: IOTAProcess;
begin
  if (AServices = nil) or (AServices.ProcessCount = 0) then
  begin
    Finish(True);
    Exit;
  end;
  // Einmaliger Haltepunkt: nach dem ersten Halt entfernen.
  mProcess := AServices.CurrentProcess;
  if (FBreakpoint <> nil) and (mProcess <> nil) and (mProcess.ProcessState in [psStopped, psFault, psException]) then
  begin
    RemoveBreakpoint;
  end;
end;

procedure TAtlasIdeTestDebugger.Finish(AStarted: Boolean);
var
  mChanged: Boolean;
  mXml, mProject: string;
begin
  FTimer.Enabled := False;
  RemoveBreakpoint;
  mProject := FTarget.Project;
  // Nur nach „Start“ gibt es vorübergehende Parameter (Building: nichts gesetzt).
  if FPhase in [TPhase.Starting, TPhase.Running] then
  begin
    if TAtlasIdeStartOptions.EndTemporary(mProject, mChanged) and mChanged then
    begin
      Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugKeptParameters, [ProjectName(mProject)]));
    end;
    RestoreActiveProject;
    if AStarted then
    begin
      Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugFinished, [ProjectName(mProject)]));
    end
    else
    begin
      Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsDebugNoProcess, [ProjectName(mProject)]));
    end;
  end;
  FPhase := TPhase.Idle;
  FTests.Debugging := False;
  mXml := '';
  if FXmlFile <> '' then
  begin
    try
      if FileExists(FXmlFile) then
      begin
        mXml := TFile.ReadAllText(FXmlFile, TEncoding.UTF8);
        TFile.Delete(FXmlFile);
      end;
    except
      on Exception do
        mXml := '';
    end;
    FXmlFile := '';
  end;
  // Ergebnis wie nach „Tests ausführen“: Code Lens, Probleme, Meldungen, Projekt-Zusammenfassung.
  if AStarted and (mXml <> '') then
  begin
    FTests.ReportRun(FTarget, mXml);
  end;
end;

end.
