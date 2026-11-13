unit Atlas.IDE.Debug.MethodBreakpoints;

// Haltepunkte auf Methoden nach Name oder Muster (#855) im Debugger der IDE:
// - Befehl „Haltepunkt auf Methoden …“ (Atlas.MethodBreakpoints): Dialog mit Muster und Vorschau; „Setzen“ legt
//   an der Zeile des ersten ausführbaren Befehls jeder gewählten Methode einen Quelltext-Haltepunkt an, in der
//   Haltepunktgruppe mit dem Muster als Namen, mit Bedingung und, wenn gewählt, „nur protokollieren“. Wo der
//   Benutzer schon einen Haltepunkt hat, bleibt der.
// - Befehl „Haltepunktgruppen der Methoden …“ (Atlas.MethodBreakpointGroups): Gruppen des aktiven Projekts mit
//   Zahl der Haltepunkte; ein- und ausschalten oder entfernen (Haltepunkte und Gruppe).
// - Mitwachsen: Vor dem Start einer Debug-Sitzung (BeforeProgramLaunch über IAtlasIdeDebugLaunchCheck) fragt Atlas
//   für jede Gruppe des gestarteten Projekts mit „Mitwachsen“ den Server erneut und ergänzt Haltepunkte für
//   Methoden, die die Gruppe noch nicht kennt; eine Zeile in den Meldungen nennt sie. Antwortet der Server nicht
//   rechtzeitig (3 s), startet die IDE wie bisher.
// - Die Gruppen liegen persönlich in %LOCALAPPDATA%\Atlas\debug-method-breakpoints.json, je Projektdatei.
// Ein Teil der Feature-Tabelle (debug.methodBreakpoints): aus = kein Zuhörer, keine Befehle. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.MethodBreakpoints,
  Atlas.UI.Debug.MethodBreakpoints,
  Atlas.IDE.Debug.Session;

type
  TAtlasMethodBreakpointSessionFunc = reference to function: TLspSession;

  TAtlasIdeMethodBreakpoints = class
  private const
    cLaunchTimeoutMs = 3000;
    cSearchTimeoutMs = 15000;
    cFileName = 'debug-method-breakpoints.json';
    cStoreWhat = 'Methodenhaltepunkte';
  private type
    TListener = class(TAtlasIdeDebugListener, IAtlasIdeDebugLaunchCheck)
    public
      function AllowLaunch(const AProject: IOTAProject): Boolean;
    end;
  private class var
    FSession: TAtlasMethodBreakpointSessionFunc;
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FStore: TAtlasMethodGroupStore;
    FStoreKept: Boolean;
    FLastGroup: TAtlasMethodGroup;
    class procedure Report(const AText: string); static;
    class function StoreFile: string; static;
    class procedure LoadStore; static;
    class procedure SaveStore; static;
    class function ActiveProject: string; static;
    /// <summary>Server fragen; False ohne Server oder bei Fehler (AError).</summary>
    class function Search(const AQuery: TAtlasMethodQuery; ATimeoutMs: Cardinal; out AAnswer: TAtlasMethodAnswer;
      out AError: string): Boolean; static;
    /// <summary>Haltepunkte für AHits in der Gruppe anlegen; Zahl der neuen.</summary>
    class function Place(const AGroup: TAtlasMethodGroup; const AHits: TAtlasMethodHits): Integer; static;
    /// <summary>Quelltext-Haltepunkte der Gruppe APattern.</summary>
    class function GroupBreakpoints(const APattern: string): TArray<IOTABreakpoint>; static;
    class procedure Grow(const AProject: string); static;
    class procedure ToggleGroup(const AGroup: TAtlasMethodGroup); static;
    /// <summary>Gruppen des aktiven Projekts mit Zahl ihrer Haltepunkte.</summary>
    class function States: TAtlasMethodGroupStates; static;
    class procedure RemoveGroup(const AGroup: TAtlasMethodGroup); static;
  public
    /// <summary>Teil starten: Zuhörer bei der Debug-Sitzung anmelden, Gruppen laden. ASession liefert die laufende
    /// Sitzung (nil ohne), AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Start(const ASession: TAtlasMethodBreakpointSessionFunc; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.MethodBreakpoints: Dialog zeigen und Haltepunkte setzen.</summary>
    class procedure Run; static;
    /// <summary>Befehl Atlas.MethodBreakpointGroups: Gruppen des aktiven Projekts verwalten.</summary>
    class procedure RunGroups; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Files.DataFile,
  Atlas.UI.Debug.Strings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Debug.Breakpoints;

{ TAtlasIdeMethodBreakpoints.TListener }

function TAtlasIdeMethodBreakpoints.TListener.AllowLaunch(const AProject: IOTAProject): Boolean;
begin
  // Mitwachsen hält den Start nie auf.
  Result := True;
  if AProject <> nil then
  begin
    TAtlasIdeMethodBreakpoints.Grow(AProject.FileName);
  end;
end;

{ TAtlasIdeMethodBreakpoints }

class procedure TAtlasIdeMethodBreakpoints.Start(const ASession: TAtlasMethodBreakpointSessionFunc;
  const AMessage: TProc<string>);
begin
  FSession := ASession;
  FMessage := AMessage;
  if FStore = nil then
  begin
    FStore := TAtlasMethodGroupStore.Create;
    LoadStore;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
  end;
end;

class procedure TAtlasIdeMethodBreakpoints.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FSession := nil;
  FMessage := nil;
  FreeAndNil(FStore);
  FLastGroup := Default(TAtlasMethodGroup);
end;

class function TAtlasIdeMethodBreakpoints.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeMethodBreakpoints.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeMethodBreakpoints.StoreFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cFileName);
end;

class procedure TAtlasIdeMethodBreakpoints.LoadStore;
begin
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert ohne Pfad.
  FStoreKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile, cStoreWhat,
    function(const AText: string): Boolean
    begin
      Result := FStore.Parse(AText);
    end));
end;

class procedure TAtlasIdeMethodBreakpoints.SaveStore;
begin
  if (FStore = nil) or FStoreKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(StoreFile, FStore.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cStoreWhat, E);
  end;
end;

class function TAtlasIdeMethodBreakpoints.ActiveProject: string;
var
  mProject: IOTAProject;
begin
  Result := '';
  mProject := TAtlasIdeFiles.GroupProject(TAtlasIdeFiles.ActiveProjectFile);
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

/// <summary>URI der Antwort in einen Pfad; eigene Routine, damit die Methodenreferenz nichts weiter festhält.
/// </summary>
function UriToPathFunc: TAtlasUriToPath;
begin
  Result :=
    function(const AUri: string): string
    begin
      Result := TLspSession.UriToPath(AUri);
    end;
end;

class function TAtlasIdeMethodBreakpoints.Search(const AQuery: TAtlasMethodQuery; ATimeoutMs: Cardinal;
  out AAnswer: TAtlasMethodAnswer; out AError: string): Boolean;
var
  mSession: TLspSession;
  mAnswer: TJSONValue;
begin
  AAnswer := Default(TAtlasMethodAnswer);
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
    mAnswer := mSession.RunCommand(TAtlasMethodBreakpoints.cCommand, TAtlasMethodBreakpoints.Arguments(AQuery),
      ATimeoutMs);
    try
      Result := TAtlasMethodBreakpoints.ReadAnswer(mAnswer, UriToPathFunc(), AAnswer);
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
end;

class function TAtlasIdeMethodBreakpoints.Place(const AGroup: TAtlasMethodGroup;
  const AHits: TAtlasMethodHits): Integer;
var
  mHit: TAtlasMethodHit;
  mBreakpoint: IOTABreakpoint;
begin
  Result := 0;
  for mHit in AHits do
  begin
    if not mHit.HasSource then
    begin
      Continue;
    end;
    // Steht dort schon ein Haltepunkt des Benutzers, bleibt er, wie er ist (Add liefert nil).
    mBreakpoint := TAtlasIdeBreakpoints.Add(mHit.FileName, mHit.Line,
      TAtlasMethodBreakpoints.GroupName(AGroup.Pattern));
    if mBreakpoint = nil then
    begin
      Continue;
    end;
    try
      if AGroup.Condition <> '' then
      begin
        mBreakpoint.Expression := AGroup.Condition;
      end;
      if AGroup.LogOnly then
      begin
        mBreakpoint.DoBreak := False;
        mBreakpoint.LogMessage := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MethodBreakpointsLog,
          [mHit.QualifiedName]);
      end;
    except
      // Ohne Bedingung oder Aktion hält der Haltepunkt trotzdem.
      on Exception do
        ;
    end;
    Inc(Result);
  end;
end;

/// <summary>Zeile für die Meldungen: die ersten Namen, danach „…“.</summary>
function HitNames(const AHits: TAtlasMethodHits): string;
const
  cShown = 5;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AHits) do
  begin
    if mIndex = cShown then
    begin
      Result := Result + ', …';
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + AHits[mIndex].DisplayName;
  end;
end;

class procedure TAtlasIdeMethodBreakpoints.Grow(const AProject: string);
var
  mGroups: TAtlasMethodGroups;
  mGroup: TAtlasMethodGroup;
  mAnswer: TAtlasMethodAnswer;
  mError: string;
  mNew: TAtlasMethodHits;
  mChanged: Boolean;
  mIndex: Integer;
begin
  if FStore = nil then
  begin
    Exit;
  end;
  mChanged := False;
  mGroups := FStore.Groups(AProject);
  for mIndex := 0 to High(mGroups) do
  begin
    mGroup := mGroups[mIndex];
    // Ohne Server oder bei einem Fehler startet die IDE wie bisher.
    if not mGroup.Grow or not Search(mGroup.Query, cLaunchTimeoutMs, mAnswer, mError) or (mAnswer.Error <> '') then
    begin
      Continue;
    end;
    mNew := TAtlasMethodBreakpoints.NewHits(mGroup, mAnswer.Hits);
    if mNew = nil then
    begin
      Continue;
    end;
    Place(mGroup, mNew);
    mGroup.Learn(mNew);
    FStore.Put(AProject, mGroup);
    mChanged := True;
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MethodBreakpointsGrown, [Length(mNew), mGroup.Pattern,
      HitNames(mNew)]));
  end;
  if mChanged then
  begin
    SaveStore;
  end;
end;

/// <summary>Suche für den Dialog; eigene Routine, damit die Methodenreferenz nichts weiter festhält.</summary>
function SearchFunc: TAtlasMethodSearch;
begin
  Result :=
    function(const AQuery: TAtlasMethodQuery; out AAnswer: TAtlasMethodAnswer; out AError: string): Boolean
    begin
      Result := TAtlasIdeMethodBreakpoints.Search(AQuery, TAtlasIdeMethodBreakpoints.cSearchTimeoutMs, AAnswer,
        AError);
    end;
end;

class procedure TAtlasIdeMethodBreakpoints.Run;
var
  mGroup, mKnown: TAtlasMethodGroup;
  mSelected: TAtlasMethodHits;
  mProject, mKey: string;
begin
  if not Started then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.MethodBreakpointsOff));
    Exit;
  end;
  mGroup := FLastGroup;
  if mGroup.Pattern = '' then
  begin
    mGroup.Overrides := True;
    mGroup.Overloads := True;
  end;
  // Gesehen ist, was diese Gruppe schon kannte; der Dialog nimmt die neuen Treffer dazu.
  mGroup.Known := nil;
  if not TAtlasMethodBreakpointsDialog.Execute(mGroup, SearchFunc(), mSelected) then
  begin
    Exit;
  end;
  mProject := ActiveProject;
  // Schon gesehene Treffer einer gleichnamigen Gruppe bleiben gesehen.
  if FStore.Find(mProject, mGroup.Pattern, mKnown) then
  begin
    for mKey in mKnown.Known do
    begin
      if not mGroup.Knows(mKey) then
      begin
        mGroup.Known := mGroup.Known + [mKey];
      end;
    end;
  end;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MethodBreakpointsCreated, [Place(mGroup, mSelected),
    TAtlasMethodBreakpoints.GroupName(mGroup.Pattern)]));
  FLastGroup := mGroup;
  FLastGroup.Known := nil;
  if mProject <> '' then
  begin
    FStore.Put(mProject, mGroup);
    SaveStore;
  end;
end;

class function TAtlasIdeMethodBreakpoints.GroupBreakpoints(const APattern: string): TArray<IOTABreakpoint>;
var
  mServices: IOTADebuggerServices;
  mIndex, mCount: Integer;
  mBreakpoint: IOTASourceBreakpoint;
  mName: string;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mName := TAtlasMethodBreakpoints.GroupName(APattern);
  // Höchstens alle Haltepunkte; am Ende auf die gefundenen kürzen.
  SetLength(Result, mServices.SourceBkptCount);
  mCount := 0;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and (mCount < Length(Result)) and SameText(mBreakpoint.GroupName, mName) then
    begin
      Result[mCount] := mBreakpoint;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class procedure TAtlasIdeMethodBreakpoints.ToggleGroup(const AGroup: TAtlasMethodGroup);
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mBreakpoint: IOTABreakpoint;
  mAllEnabled: Boolean;
begin
  mBreakpoints := GroupBreakpoints(AGroup.Pattern);
  mAllEnabled := True;
  for mBreakpoint in mBreakpoints do
  begin
    mAllEnabled := mAllEnabled and mBreakpoint.Enabled;
  end;
  // Alle an: alle aus; sonst alle an.
  for mBreakpoint in mBreakpoints do
  begin
    mBreakpoint.Enabled := not mAllEnabled;
  end;
end;

class procedure TAtlasIdeMethodBreakpoints.RemoveGroup(const AGroup: TAtlasMethodGroup);
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mCount: Integer;
  mProject: string;
begin
  mBreakpoints := GroupBreakpoints(AGroup.Pattern);
  mCount := Length(mBreakpoints);
  TAtlasIdeBreakpoints.RemoveAll(mBreakpoints);
  mProject := ActiveProject;
  if (FStore <> nil) and FStore.Remove(mProject, AGroup.Pattern) then
  begin
    SaveStore;
  end;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MethodGroupsRemoved, [AGroup.Pattern, mCount]));
end;

class function TAtlasIdeMethodBreakpoints.States: TAtlasMethodGroupStates;
var
  mGroup: TAtlasMethodGroup;
  mState: TAtlasMethodGroupState;
  mBreakpoint: IOTABreakpoint;
begin
  Result := nil;
  if FStore = nil then
  begin
    Exit;
  end;
  for mGroup in FStore.Groups(ActiveProject) do
  begin
    mState := Default(TAtlasMethodGroupState);
    mState.Group := mGroup;
    for mBreakpoint in GroupBreakpoints(mGroup.Pattern) do
    begin
      Inc(mState.Breakpoints);
      if mBreakpoint.Enabled then
      begin
        Inc(mState.Enabled);
      end;
    end;
    Result := Result + [mState];
  end;
end;

/// <summary>Gruppen des aktiven Projekts mit ihren Haltepunkten; eigene Routine für die Methodenreferenz.
/// </summary>
function StatesFunc: TAtlasMethodGroupStatesFunc;
begin
  Result :=
    function: TAtlasMethodGroupStates
    begin
      Result := TAtlasIdeMethodBreakpoints.States;
    end;
end;

function ToggleFunc: TAtlasMethodGroupAction;
begin
  Result :=
    procedure(const AGroup: TAtlasMethodGroup)
    begin
      TAtlasIdeMethodBreakpoints.ToggleGroup(AGroup);
    end;
end;

function RemoveFunc: TAtlasMethodGroupAction;
begin
  Result :=
    procedure(const AGroup: TAtlasMethodGroup)
    begin
      TAtlasIdeMethodBreakpoints.RemoveGroup(AGroup);
    end;
end;

class procedure TAtlasIdeMethodBreakpoints.RunGroups;
begin
  if not Started then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.MethodBreakpointsOff));
    Exit;
  end;
  TAtlasMethodGroupsDialog.Execute(StatesFunc(), ToggleFunc(), RemoveFunc());
end;

end.
