unit Atlas.IDE.Debug.BreakpointCheck;

// Haltepunkte, die nicht greifen werden (#577), im Debugger der IDE:
// - Vor dem Start einer Debug-Sitzung (BeforeProgramLaunch über
//   IAtlasIdeDebugLaunchCheck, nach dem Bauen) schickt Atlas die Zeilen aller
//   aktiven Quelltext-Haltepunkte an atlas.server.breakpointCheck; offene
//   Dateien vorher mit dem Stand im Editor. Antwortet der Server nicht
//   rechtzeitig (3 s) oder gibt es keinen, startet die IDE ohne Meldung.
// - Dazu Haltepunkte in Units, die zu einem anderen Projekt der Gruppe
//   gehören, nicht zum gestarteten, und nicht unter dessen Ordner liegen.
// - Gibt es Funde, zeigt der Dialog sie einmal vor dem Start: Doppelklick
//   springt zur Stelle; „Trotzdem starten“, „Auf nächste Codezeile
//   verschieben“ (verschiebt und startet) oder „Abbrechen“ (die IDE startet
//   nicht).
// - Befehl „Haltepunkte prüfen“ (Atlas.CheckBreakpoints) für das aktive
//   Projekt, mit Verschieben und Schließen; ohne Funde eine Zeile in den
//   Meldungen.
// Ein Teil der Feature-Tabelle (debug.checkBreakpoints): aus = kein Zuhörer,
// der Start bleibt, wie er ist. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.BreakpointCheck,
  Atlas.IDE.Debug.Session;

type
  TAtlasBreakpointCheckSessionFunc = reference to function: TLspSession;

  TAtlasIdeBreakpointCheck = class
  private const
    cTimeoutMs = 3000;
  private type
    TListener = class(TAtlasIdeDebugListener, IAtlasIdeDebugLaunchCheck)
    public
      function AllowLaunch(const AProject: IOTAProject): Boolean;
    end;
  private class var
    FSession: TAtlasBreakpointCheckSessionFunc;
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FLastProblems: TAtlasBreakpointProblems;
    class procedure Report(const AText: string); static;
    class function Spots: TAtlasBreakpointSpots; static;
    class procedure SyncOpenFiles(const ASession: TLspSession; const ASpots: TAtlasBreakpointSpots); static;
    class function ProjectProblems(const AProject: IOTAProject;
      const ASpots: TAtlasBreakpointSpots): TAtlasBreakpointProblems; static;
    /// <summary>Server fragen und Funde sammeln; False ohne Server oder bei Fehler (AError).</summary>
    class function Check(const AProject: IOTAProject; const ASpots: TAtlasBreakpointSpots;
      out AProblems: TAtlasBreakpointProblems; out AError: string): Boolean; static;
    class function MoveProblems(const AProblems: TAtlasBreakpointProblems): Integer; static;
    class function LaunchAllowed(const AProject: IOTAProject): Boolean; static;
  public
    /// <summary>Teil starten: Zuhörer bei der Debug-Sitzung anmelden. ASession liefert die laufende Sitzung (nil
    /// ohne), AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Start(const ASession: TAtlasBreakpointCheckSessionFunc; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.CheckBreakpoints: Haltepunkte des aktiven Projekts jetzt prüfen.</summary>
    class procedure Run; static;
    /// <summary>Funde der letzten Prüfung (vor dem Start oder per Befehl), für das Haltepunktfenster (#863); nil
    /// ohne Prüfung oder ohne Funde.</summary>
    class function LastProblems: TAtlasBreakpointProblems; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.BreakpointCheck,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Debug.Breakpoints;

{ TAtlasIdeBreakpointCheck.TListener }

function TAtlasIdeBreakpointCheck.TListener.AllowLaunch(const AProject: IOTAProject): Boolean;
begin
  Result := TAtlasIdeBreakpointCheck.LaunchAllowed(AProject);
end;

{ TAtlasIdeBreakpointCheck }

class procedure TAtlasIdeBreakpointCheck.Start(const ASession: TAtlasBreakpointCheckSessionFunc;
  const AMessage: TProc<string>);
begin
  FSession := ASession;
  FMessage := AMessage;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
  end;
end;

class procedure TAtlasIdeBreakpointCheck.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FLastProblems := nil;
  FSession := nil;
  FMessage := nil;
end;

class function TAtlasIdeBreakpointCheck.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeBreakpointCheck.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeBreakpointCheck.Spots: TAtlasBreakpointSpots;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and mBreakpoint.Enabled and (mBreakpoint.FileName <> '') and
      (mBreakpoint.LineNumber > 0) then
    begin
      Result := Result + [TAtlasBreakpointSpot.Create(mBreakpoint.FileName,
        TLspSession.PathToUri(mBreakpoint.FileName), mBreakpoint.LineNumber - 1)];
    end;
  end;
end;

class procedure TAtlasIdeBreakpointCheck.SyncOpenFiles(const ASession: TLspSession;
  const ASpots: TAtlasBreakpointSpots);
var
  mSpot: TAtlasBreakpointSpot;
  mDone: TDictionary<string, Boolean>;
  mBuffer: IOTAEditBuffer;
begin
  mDone := TDictionary<string, Boolean>.Create;
  try
    for mSpot in ASpots do
    begin
      if mDone.ContainsKey(LowerCase(mSpot.FileName)) then
      begin
        Continue;
      end;
      mDone.Add(LowerCase(mSpot.FileName), True);
      mBuffer := TAtlasIdeFiles.BufferOf(mSpot.FileName);
      if mBuffer <> nil then
      begin
        ASession.Sync(mSpot.FileName, TAtlasEditorBuffer.Text(mBuffer));
      end;
    end;
  finally
    mDone.Free;
  end;
end;

/// <summary>Ist AFileName Modul eines anderen Projekts der Gruppe als ALaunched?</summary>
function InOtherProject(const ALaunched: IOTAProject; const AFileName: string): Boolean;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
  mProject: IOTAProject;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mProject := mGroup.Projects[mIndex];
    if (mProject <> nil) and not SameFileName(mProject.FileName, ALaunched.FileName) and
      (mProject.FindModuleInfo(AFileName) <> nil) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeBreakpointCheck.ProjectProblems(const AProject: IOTAProject;
  const ASpots: TAtlasBreakpointSpots): TAtlasBreakpointProblems;
var
  mSpot: TAtlasBreakpointSpot;
  mFolder: string;
begin
  Result := nil;
  if AProject = nil then
  begin
    Exit;
  end;
  mFolder := ExtractFilePath(AProject.FileName);
  for mSpot in ASpots do
  begin
    if TAtlasBreakpointCheck.NotInProject(mSpot.FileName, mFolder, AProject.FindModuleInfo(mSpot.FileName) <> nil,
      InOtherProject(AProject, mSpot.FileName)) then
    begin
      Result := Result + [TAtlasBreakpointCheck.NotInProjectProblem(mSpot)];
    end;
  end;
end;

class function TAtlasIdeBreakpointCheck.Check(const AProject: IOTAProject; const ASpots: TAtlasBreakpointSpots;
  out AProblems: TAtlasBreakpointProblems; out AError: string): Boolean;
var
  mSession: TLspSession;
  mAnswer: TJSONValue;
  mServer: TAtlasBreakpointProblems;
begin
  AProblems := nil;
  AError := '';
  Result := False;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  try
    SyncOpenFiles(mSession, ASpots);
    mAnswer := mSession.RunCommand(TAtlasBreakpointCheck.cCommand, TAtlasBreakpointCheck.Arguments(ASpots),
      cTimeoutMs);
    try
      Result := TAtlasBreakpointCheck.ReadAnswer(mAnswer, ASpots, mServer);
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
  if Result then
  begin
    AProblems := TAtlasBreakpointCheck.Sorted(mServer + ProjectProblems(AProject, ASpots));
    FLastProblems := AProblems;
  end;
end;

class function TAtlasIdeBreakpointCheck.LastProblems: TAtlasBreakpointProblems;
begin
  Result := FLastProblems;
end;

class function TAtlasIdeBreakpointCheck.MoveProblems(const AProblems: TAtlasBreakpointProblems): Integer;
var
  mProblem: TAtlasBreakpointProblem;
  mBreakpoint: IOTABreakpoint;
begin
  Result := 0;
  for mProblem in AProblems do
  begin
    if not mProblem.CanMove then
    begin
      Continue;
    end;
    mBreakpoint := TAtlasIdeBreakpoints.Find(mProblem.FileName, mProblem.Line);
    if (mBreakpoint <> nil) and (TAtlasIdeBreakpoints.MoveTo(mBreakpoint, mProblem.NextLine) <> nil) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Sprung aus dem Dialog; eigene Routine, damit die Methodenreferenz nichts weiter festhält.</summary>
function JumpProc: TAtlasBreakpointJump;
begin
  Result :=
    procedure(const AProblem: TAtlasBreakpointProblem)
    begin
      TAtlasIdeNavigation.GoToLocation(AProblem.FileName, AProblem.Line, 0);
    end;
end;

class function TAtlasIdeBreakpointCheck.LaunchAllowed(const AProject: IOTAProject): Boolean;
var
  mSpots: TAtlasBreakpointSpots;
  mProblems: TAtlasBreakpointProblems;
  mError: string;
begin
  Result := True;
  mSpots := Spots;
  // Ohne Haltepunkte, ohne Server oder bei einem Fehler startet die IDE wie bisher.
  if (mSpots = nil) or not Check(AProject, mSpots, mProblems, mError) or (mProblems = nil) then
  begin
    Exit;
  end;
  case TAtlasBreakpointCheckDialog.Execute(mProblems, TAtlasBreakpointCheckMode.Launch, JumpProc()) of
    TAtlasBreakpointCheckChoice.Move:
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckMoved, [MoveProblems(mProblems)]));
    TAtlasBreakpointCheckChoice.Cancel:
      Result := False;
  end;
end;

class procedure TAtlasIdeBreakpointCheck.Run;
var
  mSpots: TAtlasBreakpointSpots;
  mProblems: TAtlasBreakpointProblems;
  mError: string;
  mProject: IOTAProject;
begin
  if not Started then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckOff));
    Exit;
  end;
  mSpots := Spots;
  if mSpots = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckNone));
    Exit;
  end;
  mProject := TAtlasIdeFiles.GroupProject(TAtlasIdeFiles.ActiveProjectFile);
  if not Check(mProject, mSpots, mProblems, mError) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckNoServer, [mError]));
    Exit;
  end;
  if mProblems = nil then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckAllOk, [Length(mSpots)]));
    Exit;
  end;
  if TAtlasBreakpointCheckDialog.Execute(mProblems, TAtlasBreakpointCheckMode.Command, JumpProc()) =
    TAtlasBreakpointCheckChoice.Move then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckMoved, [MoveProblems(mProblems)]));
  end;
end;

end.
