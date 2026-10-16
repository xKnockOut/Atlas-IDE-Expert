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
    TickMs = 250;
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
    /// <summary>Bauen bzw. starten; False mit Grund, wenn es nicht geht (beschäftigt, Plattform, Build abgelehnt).
    /// </summary>
    function Prepare(const AProject: IOTAProject; out AReason: string): Boolean;
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
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.StartProfiles.Service,
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
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeTestDebugger.Destroy;
var
  Changed: Boolean;
begin
  FAlive.Alive := False;
  FTimer.Free;
  // Beim Entladen mitten in einer Sitzung: Haltepunkt weg, Startparameter zurück (sonst beim nächsten Mal über
  // den Eintrag in der lokalen Datei der Startprofile).
  if FPhase in [TPhase.Starting, TPhase.Running] then
  begin
    RemoveBreakpoint;
    if not Debugging then
      TAtlasIdeStartProfiles.EndTemporary(FTarget.Project, Changed);
  end;
  if FPhase <> TPhase.Idle then
    FTests.Debugging := False;
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
    Result := nil;
end;

class function TAtlasIdeTestDebugger.Debugging: Boolean;
var
  Services: IOTADebuggerServices;
begin
  Services := Debugger;
  Result := (Services <> nil) and (Services.ProcessCount > 0);
end;

class function TAtlasIdeTestDebugger.ProjectOf(const AFileName: string): IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Supports(Services.FindModule(AFileName), IOTAProject, Result);
end;

class function TAtlasIdeTestDebugger.ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text: string;
begin
  ALines := nil;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
    Text := TAtlasEditorBuffer.Text(Buffer)
  else
  begin
    if not FileExists(AFileName) then
      Exit(False);
    try
      Text := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(Text);
  Result := True;
end;

function TAtlasIdeTestDebugger.Busy: Boolean;
begin
  Result := FPhase <> TPhase.Idle;
end;

function TAtlasIdeTestDebugger.AtCursor(out AFileName: string; out ASelection: TAtlasTestSelection): Boolean;
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
begin
  AFileName := '';
  ASelection := Default(TAtlasTestSelection);
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(ExtractFileExt(View.Buffer.FileName), '.pas') then
    Exit(Say(TAtlasStrings.Text(TAtlasTextId.TestsNoTestAtCursor)));
  AFileName := View.Buffer.FileName;
  Result := TAtlasTestDebug.SelectAt(TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasEditorBuffer.Text(View.Buffer))),
    View.CursorPos.Line - 1, ASelection) and (Length(ASelection.Names) > 0);
  if not Result then
    Say(TAtlasStrings.Text(TAtlasTextId.TestsNoTestAtCursor));
end;

procedure TAtlasIdeTestDebugger.RunAtCursor;
var
  FileName: string;
  Selection: TAtlasTestSelection;
begin
  if not TAtlasTestDebug.RunWanted(TAtlasIdeSettings.Current) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
    Exit;
  end;
  if AtCursor(FileName, Selection) then
    Run(FileName, Selection);
end;

procedure TAtlasIdeTestDebugger.DebugAtCursor;
var
  FileName: string;
  Selection: TAtlasTestSelection;
begin
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsDebugOff));
    Exit;
  end;
  if AtCursor(FileName, Selection) then
    Debug(FileName, Selection);
end;

procedure TAtlasIdeTestDebugger.Run(const AFileName: string; const ASelection: TAtlasTestSelection);
begin
  if not TAtlasTestDebug.RunWanted(TAtlasIdeSettings.Current) or (Length(ASelection.Names) = 0) then
    Exit;
  FTests.RunTests(AFileName, ASelection.Names);
end;

procedure TAtlasIdeTestDebugger.Debug(const AFileName: string; const ASelection: TAtlasTestSelection);
var
  Alive: TAlive;
  Keep: IInterface;
begin
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) or (Length(ASelection.Names) = 0) then
    Exit;
  if Busy then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsDebugBusy));
    Exit;
  end;
  if FTests.Busy then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsBusy));
    Exit;
  end;
  if Debugging then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsDebugRunning));
    Exit;
  end;
  FSelection := ASelection;
  FUnitFile := AFileName;
  Alive := FAlive;
  Keep := FAliveRef;
  FTests.ResolveProject(AFileName,
    procedure(const AProject: IOTAProject)
    var
      Reason: string;
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      if not Prepare(AProject, Reason) then
        Say(Reason);
    end);
end;

function TAtlasIdeTestDebugger.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
var
  Project: IOTAProject;
  Name, UnitName, FileName: string;
  Index: Integer;
  Lines: TArray<string>;
  Selection: TAtlasTestSelection;
begin
  AReason := '';
  Result := False;
  if not TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsDebugOff);
    Exit;
  end;
  Project := ProjectOf(AProject);
  if Project = nil then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.StartProfilesNotOpen, [ExtractFileName(AProject)]);
    Exit;
  end;
  // Der Unitname kann Punkte enthalten: jede Teilung von hinten versuchen (Unit.Fixture.Methode[.Fall]).
  Name := Trim(AFullName);
  for Index := Length(Name) downto 1 do
  begin
    if Name[Index] <> '.' then
      Continue;
    UnitName := Copy(Name, 1, Index - 1);
    FileName := TAtlasIdeTests.UnitFileOf(Project.FileName, UnitName);
    if (FileName = '') or not ReadLines(FileName, Lines) then
      Continue;
    if TAtlasTestDebug.SelectByName(TDUnitXSource.Scan(Lines), Name, Selection) and
      (Length(Selection.Names) > 0) then
    begin
      if Busy or FTests.Busy or Debugging then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.TestsDebugBusy);
        Exit;
      end;
      FSelection := Selection;
      FUnitFile := FileName;
      Exit(Prepare(Project, AReason));
    end;
  end;
  AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoTestAtCursor);
end;

class function TAtlasIdeTestDebugger.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
var
  Name, UnitName, FileName: string;
  Index, Line: Integer;
  Lines: TArray<string>;
  Found: TDUnitXUnit;
  Selection: TAtlasTestSelection;
begin
  AFileName := '';
  ALine := 0;
  Result := False;
  Name := Trim(AFullName);
  // Wie DebugByName: jede Teilung von hinten als Unitname versuchen.
  for Index := Length(Name) downto 1 do
  begin
    if Name[Index] <> '.' then
      Continue;
    UnitName := Copy(Name, 1, Index - 1);
    FileName := TAtlasIdeTests.UnitFileOf(AProject, UnitName);
    if (FileName = '') or not ReadLines(FileName, Lines) then
      Continue;
    Found := TDUnitXSource.Scan(Lines);
    if not TAtlasTestDebug.SelectByName(Found, Name, Selection) then
      Continue;
    Line := Found.LineOf(Selection.Fixture, Selection.Method);
    AFileName := FileName;
    if Line >= 0 then
      ALine := Line + 1;
    Exit(True);
  end;
end;

function TAtlasIdeTestDebugger.Prepare(const AProject: IOTAProject; out AReason: string): Boolean;
var
  Alive: TAlive;
  Keep: IInterface;
  Reason: string;
begin
  AReason := '';
  Result := False;
  if Busy or FTests.Busy or Debugging then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsDebugBusy);
    Exit;
  end;
  FTarget := TAtlasIdeTests.TargetOf(AProject, FSelection.Names);
  if not TAtlasTestRun.CanRun(FTarget.Platform) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.TestsPlatform, [ProjectName(FTarget.Project), FTarget.Platform]);
    Exit;
  end;
  Result := True;
  FPreviousProject := '';
  if GetActiveProject <> nil then
    FPreviousProject := GetActiveProject.FileName;
  FPhase := TPhase.Building;
  FTests.Debugging := True;
  // Ohne Build-Dienst baut „Start“ der IDE selbst.
  if not FTests.CanBuild then
  begin
    Launch('');
    Exit;
  end;
  Alive := FAlive;
  Keep := FAliveRef;
  if not FTests.BuildProject(FTarget.Project,
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      if (Keep = nil) or not Alive.Alive or (FPhase <> TPhase.Building) then
        Exit;
      if AError <> '' then
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.TestsBuildRefused, [ProjectName(FTarget.Project), AError]));
        Finish(False);
      end
      else if not ASucceeded then
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.TestsBuildFailed, [ProjectName(FTarget.Project)]));
        Finish(False);
      end
      else
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            Launch(AOutputFile);
          end);
    end, Reason) then
  begin
    AReason := TAtlasStrings.Fmt(TAtlasTextId.TestsBuildRefused, [ProjectName(FTarget.Project), Reason]);
    FPhase := TPhase.Idle;
    FTests.Debugging := False;
    Result := False;
  end;
end;

procedure TAtlasIdeTestDebugger.Launch(const AExecutable: string);
var
  Names: TArray<string>;
  XmlFile, Reason: string;
begin
  if AExecutable <> '' then
    FTarget.Executable := AExecutable;
  if Debugging then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsDebugRunning));
    Finish(False);
    Exit;
  end;
  Names := FSelection.Names;
  XmlFile := TPath.Combine(TPath.GetTempPath, 'atlas-debug-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
  FXmlFile := XmlFile;
  if TAtlasTestDebug.BreakWanted(TAtlasIdeSettings.Current, FSelection) then
    SetBreakpoint;
  Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugStarted, [ProjectName(FTarget.Project), FSelection.Caption,
    FTarget.Configuration, FTarget.Platform]));
  FPhase := TPhase.Starting;
  FStartedAt := GetTickCount;
  if not TAtlasIdeStartProfiles.RunTemporary(FTarget.Project,
    function(AExisting: string): string
    begin
      Result := TAtlasTestDebug.Parameters(AExisting, Names, XmlFile);
    end, True, Reason) then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugFailed, [ProjectName(FTarget.Project), Reason]));
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
  Services: IOTADebuggerServices;
  Index, Line: Integer;
  Existing: IOTASourceBreakpoint;
begin
  FBreakpoint := nil;
  Services := Debugger;
  if (Services = nil) or (FUnitFile = '') or (FSelection.BreakLine < 0) then
    Exit;
  Line := FSelection.BreakLine + 1;
  // Ein Haltepunkt des Benutzers an derselben Stelle bleibt, wie er ist.
  for Index := 0 to Services.SourceBkptCount - 1 do
  begin
    Existing := Services.SourceBkpts[Index];
    if (Existing <> nil) and SameText(Existing.FileName, FUnitFile) and (Existing.LineNumber = Line) then
      Exit;
  end;
  try
    FBreakpoint := Services.NewSourceBreakpoint(FUnitFile, Line, nil);
    if FBreakpoint <> nil then
      Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugBreak, [Line]));
  except
    on Exception do
      FBreakpoint := nil;
  end;
end;

procedure TAtlasIdeTestDebugger.RemoveBreakpoint;
var
  Services: IOTADebuggerServices;
begin
  if FBreakpoint = nil then
    Exit;
  Services := Debugger;
  try
    if Services <> nil then
      Services.RemoveBreakpoint(FBreakpoint);
  finally
    FBreakpoint := nil;
  end;
end;

procedure TAtlasIdeTestDebugger.RestoreActiveProject;
var
  Services: IOTAModuleServices;
  Previous: IOTAProject;
begin
  if FPreviousProject = '' then
    Exit;
  Previous := ProjectOf(FPreviousProject);
  if (Previous <> nil) and Supports(BorlandIDEServices, IOTAModuleServices, Services) and
    (Services.MainProjectGroup <> nil) and (Services.MainProjectGroup.ActiveProject <> Previous) then
    Services.MainProjectGroup.ActiveProject := Previous;
end;

procedure TAtlasIdeTestDebugger.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    var
      Services: IOTADebuggerServices;
      Process: IOTAProcess;
    begin
      Services := Debugger;
      case FPhase of
        TPhase.Starting:
          if (Services <> nil) and (Services.ProcessCount > 0) then
            FPhase := TPhase.Running
          // Schneller als ein Takt gelaufen: der Bericht ist schon da.
          else if (FXmlFile <> '') and FileExists(FXmlFile) then
            Finish(True)
          else if GetTickCount - FStartedAt > TAtlasTestDebug.StartTimeoutMs then
            Finish(False);
        TPhase.Running:
          begin
            if (Services = nil) or (Services.ProcessCount = 0) then
            begin
              Finish(True);
              Exit;
            end;
            // Einmaliger Haltepunkt: nach dem ersten Halt entfernen.
            Process := Services.CurrentProcess;
            if (FBreakpoint <> nil) and (Process <> nil) and
              (Process.ProcessState in [psStopped, psFault, psException]) then
              RemoveBreakpoint;
          end;
      end;
    end);
end;

procedure TAtlasIdeTestDebugger.Finish(AStarted: Boolean);
var
  Changed: Boolean;
  Xml, Project: string;
begin
  FTimer.Enabled := False;
  RemoveBreakpoint;
  Project := FTarget.Project;
  // Nur nach „Start“ gibt es vorübergehende Parameter (Building: nichts gesetzt).
  if FPhase in [TPhase.Starting, TPhase.Running] then
  begin
    if TAtlasIdeStartProfiles.EndTemporary(Project, Changed) and Changed then
      Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugKeptParameters, [ProjectName(Project)]));
    RestoreActiveProject;
    if AStarted then
      Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugFinished, [ProjectName(Project)]))
    else
      Say(TAtlasStrings.Fmt(TAtlasTextId.TestsDebugNoProcess, [ProjectName(Project)]));
  end;
  FPhase := TPhase.Idle;
  FTests.Debugging := False;
  Xml := '';
  if FXmlFile <> '' then
  begin
    try
      if FileExists(FXmlFile) then
      begin
        Xml := TFile.ReadAllText(FXmlFile, TEncoding.UTF8);
        TFile.Delete(FXmlFile);
      end;
    except
      on Exception do
        Xml := '';
    end;
    FXmlFile := '';
  end;
  // Ergebnis wie nach „Tests ausführen“: Code Lens, Probleme, Meldungen, Projekt-Zusammenfassung.
  if AStarted and (Xml <> '') then
    FTests.ReportRun(FTarget, Xml);
end;

end.
