unit Atlas.IDE.Debug.Variables;

// Fenster „Variablen“ (#853) in der IDE:
//   - Reiter Autos und Lokal: Bei jedem Halt liest Atlas den
//     Ausführungspunkt (oberster Rahmen mit Quelltext; LLDB liefert ihn
//     verzögert) und fragt atlas.server.debugVariables über TAtlasIdeHost im
//     Hintergrund mit der Zeile des vorigen Halts in derselben Datei (nach F8
//     die vorige Anweisung). Die Antwort kommt nur, solange das Modul
//     angemeldet ist, und gleicht die Listen ab (TAtlasEvalList.Replace):
//     Gleiche Ausdrücke behalten Knoten, Aufklappzustand und die Markierung
//     geänderter Werte. Ohne Server bleiben beide Reiter leer.
//   - Reiter Überwachung: eigene Ausdrücke je Projekt
//     (TAtlasIdeVariablesWatches), kommen mit dem Projekt wieder. Mit Bindung
//     an Klasse oder Unit (#2550) ordnet die Antwort des Servers (sonst der
//     oberste Rahmen) die Liste, bevor ausgewertet wird.
//   - Werte: TAtlasIdeVariablesLists in Zeitscheiben ohne Nebenwirkungen,
//     zuerst der gezeigte Reiter. Aufklappen holt Felder aus dem Atlas-Index
//     (TAtlasIdeDebugFieldRequests), sonst Teile des Ergebnis-Strings.
//   - Suche im gezeigten Reiter: nach Name oder Wert; mit Unterelementen
//     öffnet TAtlasVariableSearch Knoten bis debug.variablesWindow.searchDepth,
//     höchstens debug.variablesWindow.searchLimit Auswertungen. Neuer Halt
//     und anderer Reiter starten sie neu.
//   - Ausgewertet wird nur, solange das Fenster besteht; wird es bei einem
//     Halt geöffnet, holt Atlas den Halt nach.
//   - Wert ändern (F2, Kontextmenü) über TAtlasIdeDebugEditValue (#868);
//     danach wertet das Fenster im selben Halt neu aus (Reevaluate).
// Ohne debug.variablesWindow ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.UI.Debug.VariablesFrame,
  Atlas.Core.Debug.Variables,
  Atlas.IDE.Debug.StopView,
  Atlas.IDE.Debug.FieldRequests,
  Atlas.IDE.Debug.VariablesLists,
  Atlas.IDE.Debug.VariablesWatches;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasVariablesSessionFunc = reference to function: TLspSession;
  /// <summary>Serverbefehl im Hintergrund; ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler).
  /// False = nicht gestartet.</summary>
  TAtlasVariablesRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugVariables = class(TAtlasIdeDebugStopView)
  public const
    cTickMs = 10;
    cRequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel da ist (je cTickMs * cLocationTicks).</summary>
    cLocationRetries = 20;
    cLocationTicks = 5;
  private type
    /// <summary>Stand der Suche im gezeigten Reiter.</summary>
    TSearchState = record
      /// <summary>Knoten, auf dessen Felder die Suche wartet; '' ohne.</summary>
      Key: string;
      /// <summary>Die Suche ist durch (Treffer bestimmt).</summary>
      Done: Boolean;
    end;
    /// <summary>Ausführungspunkt: Datei und Zeile (0-basiert, -1 ohne), Routine des Rahmens.</summary>
    TPlace = record
      FileName: string;
      Line: Integer;
      Routine: string;
    end;
  private class var
    FInstance: TAtlasIdeDebugVariables;
  private
    FSession: TAtlasVariablesSessionFunc;
    FRun: TAtlasVariablesRunner;
    FLists: TAtlasIdeVariablesLists;
    FFields: TAtlasIdeDebugFieldRequests;
    FWatches: TAtlasIdeVariablesWatches;
    FTab: TAtlasVariablesTab;
    FSearch: TSearchState;
    FPlace: TPlace;
    FPrevious: TPlace;
    /// <summary>Text der Datei am Halt, für die Felder aus dem Index.</summary>
    FText: string;
    constructor Create(const ASession: TAtlasVariablesSessionFunc; const ARun: TAtlasVariablesRunner);
    procedure CancelWork;
    procedure Accept(ARequest: Integer; const AAnswer: string);
    procedure StartEvaluate;
    procedure SearchStep;
    procedure Expand(ATab: TAtlasVariablesTab; const AKey: string);
    procedure AcceptFields(ARequest: Integer; ATab: TAtlasVariablesTab; const AKey: string;
      const AFields: TArray<string>);
    /// <summary>Überwachung geändert: neu zeichnen und mit AEvaluate neue Zeilen auswerten.</summary>
    procedure WatchesChanged(AEvaluate: Boolean);
    /// <summary>AFrame an die Instanz hängen (nach jedem Anlegen des Fensters); einen verpassten Halt nachholen.
    /// </summary>
    procedure Attach(AFrame: TAtlasDebugVariablesFrame);
    procedure SetTab(ATab: TAtlasVariablesTab);
    /// <summary>Suche mit AText im gezeigten Reiter (neu) starten; leer: Suche aus.</summary>
    procedure Search(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean);
    procedure Refresh;
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    /// <summary>Ausführungspunkt lesen; False: später noch einmal (LLDB).</summary>
    function ReadLocation: Boolean; override;
    procedure Ask; override;
    procedure EvaluateSlice; override;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasVariablesSessionFunc; const ARun: TAtlasVariablesRunner); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.variablesWindow an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster zeigen (Befehl Atlas.DebugVariables).</summary>
    class procedure ShowWindow; static;
    /// <summary>Nach „Wert ändern“ (#868): alle Zeilen im selben Halt neu auswerten; der geänderte Wert ist
    /// danach markiert.</summary>
    class procedure Reevaluate; static;
  end;

implementation

uses
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.WatchScopes,
  Atlas.IDE.Debug.Session,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.EvaluateRows,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Debug.VariablesFlow,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.EditValue,
  Atlas.IDE.Debug.VariablesWindow,
  Atlas.UI.Debug.VariablesStrings;

/// <summary>Das Fenster, falls es schon besteht; sonst nil.</summary>
function Frame: TAtlasDebugVariablesFrame;
begin
  Result := TAtlasIdeDebugVariablesWindow.ExistingFrame;
end;

function NoPlace: TAtlasIdeDebugVariables.TPlace;
begin
  Result := Default(TAtlasIdeDebugVariables.TPlace);
  Result.Line := -1;
end;

function StillStopped: Boolean;
begin
  Result := (TAtlasIdeDebugSession.StoppedThread <> nil) and (TAtlasIdeDebugVariables.FInstance <> nil) and
    (TAtlasIdeDebugSession.StopCount = TAtlasIdeDebugVariables.FInstance.FProgress.Stop);
end;

/// <summary>Text unten im Fenster: Hinweis ohne Server, Stand der Suche bzw. Anzahl der Zeilen.</summary>
function StatusText(ALists: TAtlasIdeVariablesLists; ATab: TAtlasVariablesTab; ASearchDone,
  AHasServer: Boolean): string;
var
  mStatus: TAtlasVariablesStatus;
begin
  mStatus := TAtlasVariablesFlow.Status(ALists.Search, ATab, ALists[ATab].Count, ASearchDone, AHasServer);
  case mStatus.Kind of
    TAtlasVariablesStatusKind.NoServer:
      Result := TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesNoServer);
    TAtlasVariablesStatusKind.Count:
      Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesCount, [mStatus.Count]);
    TAtlasVariablesStatusKind.Searching:
      Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesSearching, [mStatus.Evaluations]);
    TAtlasVariablesStatusKind.Truncated:
      Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesTruncated,
        [mStatus.Hits, mStatus.Evaluations]);
  else
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesHits, [mStatus.Hits]);
  end;
end;

/// <summary>Antwort des Servers an Accept, solange das Fenster angemeldet ist.</summary>
function Answered(ARequest: Integer): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.Accept(ARequest, AAnswer);
      end;
    end;
end;

/// <summary>Felder für AKey an AcceptFields, solange das Fenster angemeldet ist.</summary>
function FieldsArrived(ARequest: Integer; ATab: TAtlasVariablesTab; const AKey: string): TAtlasDebugFieldsArrived;
var
  mKey: string;
begin
  mKey := AKey;
  Result :=
    procedure(const AFields: TArray<string>)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.AcceptFields(ARequest, ATab, mKey, AFields);
      end;
    end;
end;

/// <summary>Ein verzögerter Wert ist da: neu zeichnen.</summary>
function ValueArrived: TProc;
begin
  Result :=
    procedure
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.Refresh;
      end;
    end;
end;

/// <summary>Aufklappen nicht in der Benachrichtigung des Baums: später im Hauptthread.</summary>
procedure QueueExpand(const AKey: string);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.Expand(TAtlasIdeDebugVariables.FInstance.FTab, AKey);
      end;
    end);
end;

/// <summary>Reiter, Suche und Aufklappen.</summary>
procedure WireView(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.Hooks.Tab :=
    procedure(ATab: TAtlasVariablesTab)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.SetTab(ATab);
      end;
    end;
  AFrame.Hooks.Search :=
    procedure(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.Search(AText, AMode, ADeep);
      end;
    end;
  AFrame.Hooks.Expand :=
    procedure(ANode: TAtlasEvalNode)
    begin
      QueueExpand(ANode.Key);
    end;
end;

/// <summary>Text hinter einer gebundenen Zeile: wofür sie gilt.</summary>
function ScopeText(const AScope: TAtlasWatchScope): string;
begin
  Result := '';
  if AScope.Kind <> TAtlasWatchScopeKind.Everywhere then
  begin
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesScopeSuffix, [AScope.Name]);
  end;
end;

/// <summary>Bindung an Klasse oder Unit (#2550): Kontextmenü, Text hinter der Zeile, Ausgeblendete zeigen.
/// </summary>
procedure WireScopes(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.Hooks.CanBind :=
    function(ANode: TAtlasEvalNode; AKind: TAtlasWatchScopeKind): Boolean
    var
      mWatches: TAtlasIdeVariablesWatches;
    begin
      Result := TAtlasIdeDebugVariables.FInstance <> nil;
      if not Result then
      begin
        Exit;
      end;
      mWatches := TAtlasIdeDebugVariables.FInstance.FWatches;
      // Überall: nur für gebundene Zeilen. Klasse und Unit: nur mit Halt dort, und nicht schon so gebunden.
      if AKind = TAtlasWatchScopeKind.Everywhere then
      begin
        Result := mWatches.ScopeOf(ANode).Kind <> TAtlasWatchScopeKind.Everywhere;
      end
      else
      begin
        Result := mWatches.CanBind(AKind) and (mWatches.ScopeOf(ANode).Kind <> AKind);
      end;
    end;
  AFrame.Hooks.Binding :=
    function: Boolean
    begin
      Result := (TAtlasIdeDebugVariables.FInstance <> nil) and TAtlasIdeDebugVariables.FInstance.FWatches.Enabled;
    end;
  AFrame.Hooks.Bind :=
    procedure(ANode: TAtlasEvalNode; AKind: TAtlasWatchScopeKind)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.FWatches.Bind(ANode, AKind, StillStopped);
      end;
    end;
  AFrame.Hooks.ScopeText :=
    function(ANode: TAtlasEvalNode): string
    begin
      Result := '';
      if (TAtlasIdeDebugVariables.FInstance <> nil) and TAtlasIdeDebugVariables.FInstance.FWatches.Enabled then
      begin
        Result := ScopeText(TAtlasIdeDebugVariables.FInstance.FWatches.ScopeOf(ANode));
      end;
    end;
  AFrame.Hooks.ShowHidden :=
    procedure(AShow: Boolean)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.FWatches.SetShowHidden(AShow, StillStopped);
      end;
    end;
end;

/// <summary>Überwachung hinzufügen und entfernen.</summary>
procedure WireWatches(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.Hooks.AddWatch :=
    procedure(AExpression: string)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.FWatches.Add(AExpression, StillStopped);
      end;
    end;
  AFrame.Hooks.RemoveWatch :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.FWatches.Remove(ANode);
      end;
    end;
  WireScopes(AFrame);
end;

/// <summary>Wert ändern (#868): nur mit laufendem „Werte ändern“, im angehaltenen Programm und mit Ort.</summary>
procedure WireEdit(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.Hooks.CanEditValue :=
    function: Boolean
    begin
      Result := TAtlasIdeDebugEditValue.Started and StillStopped and
        (TAtlasIdeDebugVariables.FInstance.FPlace.Line >= 0);
    end;
  AFrame.Hooks.EditValue :=
    procedure(ANode: TAtlasEvalNode)
    var
      mPlace: TAtlasIdeDebugVariables.TPlace;
    begin
      if TAtlasIdeDebugVariables.FInstance = nil then
      begin
        Exit;
      end;
      mPlace := TAtlasIdeDebugVariables.FInstance.FPlace;
      TAtlasIdeDebugEditValue.Act(TAtlasDebugValue.Evaluated(ANode.Expression, ANode.Value), mPlace.FileName,
        mPlace.Line + 1, TAtlasIdeDebugEditValue.cEditAction);
    end;
end;

{ TAtlasIdeDebugVariables }

constructor TAtlasIdeDebugVariables.Create(const ASession: TAtlasVariablesSessionFunc;
  const ARun: TAtlasVariablesRunner);
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FPlace := NoPlace;
  FPrevious := NoPlace;
  FTab := TAtlasVariablesTab.Autos;
  FLists := TAtlasIdeVariablesLists.Create(ValueArrived());
  FFields := TAtlasIdeDebugFieldRequests.Create;
  FWatches := TAtlasIdeVariablesWatches.Create(FLists[TAtlasVariablesTab.Watch], WatchesChanged);
  CreateTimer(cTickMs);
end;

destructor TAtlasIdeDebugVariables.Destroy;
begin
  // Laufende Feldanfragen halten die Sitzung: Destroy wartet sie ab.
  FreeAndNil(FFields);
  FreeAndNil(FWatches);
  FreeAndNil(FLists);
  FText := '';
  FSearch.Key := '';
  inherited Destroy;
end;

procedure TAtlasIdeDebugVariables.CancelWork;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FLists.Cancel;
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FProgress.Request);
  FProgress.Phase := TAtlasStopPhase.Idle;
  FSearch.Key := '';
  FFields.Reap(False);
end;

procedure TAtlasIdeDebugVariables.SessionStarted;
begin
  FWatches.Sync(StillStopped);
end;

procedure TAtlasIdeDebugVariables.SessionStopped;
var
  mSearch: TAtlasVariableSearch;
begin
  CancelWork;
  FPrevious := FPlace;
  FPlace := NoPlace;
  FText := '';
  // Ohne Fenster nichts auswerten; öffnet es sich bei diesem Halt, holt Attach ihn nach.
  if not Enabled or (Frame = nil) then
  begin
    FPrevious := NoPlace;
    Exit;
  end;
  FProgress.Stop := TAtlasIdeDebugSession.StopCount;
  FProgress.Retries := 0;
  FLists.BeginStop;
  // Erst den Ort lesen; die Suche startet mit den neuen Werten neu.
  FProgress.Phase := TAtlasStopPhase.Location;
  mSearch := FLists.Search;
  Search(mSearch.Text, mSearch.Mode, mSearch.Deep);
  if ReadLocation then
  begin
    Ask;
  end;
end;

procedure TAtlasIdeDebugVariables.SessionResumed;
begin
  // Die Werte bleiben stehen bis zum nächsten Halt; nur laufende Arbeit endet.
  CancelWork;
end;

procedure TAtlasIdeDebugVariables.SessionEnded;
begin
  CancelWork;
  FWatches.Ended;
  FLists.Unavailable;
  FPlace := NoPlace;
  FPrevious := NoPlace;
  FText := '';
  Refresh;
end;

function TAtlasIdeDebugVariables.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
begin
  Result := True;
  if TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames) =
    TAtlasDebugStackRead.Wait then
  begin
    // LLDB: Stapel kommt später; nach cLocationRetries ohne Ort weiter (nur die Überwachung).
    Inc(FProgress.Retries);
    Result := FProgress.Retries > cLocationRetries;
    if not Result then
    begin
      FTimer.Interval := cTickMs * cLocationTicks;
      FTimer.Enabled := True;
    end;
    Exit;
  end;
  if (Length(mFrames) > 0) and mFrames[0].HasSource then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    FPlace.FileName := mFrames[0].FileName;
    FPlace.Line := mFrames[0].Line - 1;
    FPlace.Routine := mFrames[0].Routine;
  end;
end;

procedure TAtlasIdeDebugVariables.Ask;
var
  mSession: TLspSession;
  mPrevious: Integer;
begin
  FTimer.Enabled := False;
  Inc(FProgress.Request);
  FProgress.Phase := TAtlasStopPhase.Request;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Ohne Ort, ohne Server oder ohne lesbare Datei: Autos und Lokal leer, die Überwachung wird ausgewertet.
  if (FPlace.FileName = '') or (mSession = nil) or not Assigned(FRun) or
    not TAtlasIdeFiles.SourceText(FPlace.FileName, FText) then
  begin
    Accept(FProgress.Request, '');
    Exit;
  end;
  mPrevious := TAtlasVariablesFlow.PreviousLine(FPrevious.FileName, FPrevious.Line, FPlace.FileName);
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FPlace.FileName, FText);
  if not FRun(TAtlasVariables.cCommand, TAtlasVariables.Arguments(TLspSession.PathToUri(FPlace.FileName),
    FPlace.Line, mPrevious), cRequestTimeoutMs, Answered(FProgress.Request)) then
  begin
    Accept(FProgress.Request, '');
  end;
end;

procedure TAtlasIdeDebugVariables.Accept(ARequest: Integer; const AAnswer: string);
var
  mAnswer: TAtlasVariablesAnswer;
begin
  // Nur die jüngste Antwort, und nur, solange derselbe Halt besteht.
  if (ARequest <> FProgress.Request) or (FProgress.Phase <> TAtlasStopPhase.Request) or not StillStopped then
  begin
    Exit;
  end;
  if not TAtlasVariables.ReadAnswerText(AAnswer, mAnswer) then
  begin
    mAnswer := Default(TAtlasVariablesAnswer);
  end;
  FLists[TAtlasVariablesTab.Autos].Replace(mAnswer.Autos);
  FLists[TAtlasVariablesTab.Locals].Replace(mAnswer.Locals);
  // Ohne Server bzw. ohne Felder dazu: Klasse und Unit aus dem Rahmen, ohne Vorfahren.
  if not mAnswer.Place.Known then
  begin
    mAnswer.Place := TAtlasWatchPlace.FromFrame(FPlace.Routine, FPlace.FileName);
  end;
  FWatches.Stopped(mAnswer.Place);
  StartEvaluate;
  Refresh;
end;

procedure TAtlasIdeDebugVariables.StartEvaluate;
begin
  // StillStopped an dieser Instanz: derselbe Halt wie in FProgress, Thread angehalten.
  if StillAtStop then
  begin
    BeginEvaluate(cTickMs);
  end;
end;

procedure TAtlasIdeDebugVariables.EvaluateSlice;
var
  mChanged, mWaiting: Boolean;
begin
  if not StillStopped then
  begin
    CancelWork;
    Exit;
  end;
  // Verzögerter Wert (LLDB) oder Felder für die Suche: warten.
  if FLists.Busy or (FSearch.Key <> '') then
  begin
    Exit;
  end;
  case FLists.Slice(FTab, FPlace.FileName, FPlace.Line, mChanged) of
    TAtlasVariablesStep.Stopped:
      begin
        // Kein angehaltener Prozess mehr.
        CancelWork;
        Refresh;
        Exit;
      end;
    TAtlasVariablesStep.Done:
      SearchStep;
    TAtlasVariablesStep.More, TAtlasVariablesStep.Wait: ;
  end;
  mWaiting := FLists.Busy or (FSearch.Key <> '') or not FSearch.Done;
  if not mWaiting and not FLists.HasPending then
  begin
    FTimer.Enabled := False;
    FProgress.Phase := TAtlasStopPhase.Idle;
  end;
  if mChanged then
  begin
    Refresh;
  end;
end;

procedure TAtlasIdeDebugVariables.SearchStep;
var
  mSearch: TAtlasVariableSearch;
  mNode: TAtlasEvalNode;
begin
  if FSearch.Done then
  begin
    Exit;
  end;
  mSearch := FLists.Search;
  mNode := mSearch.NextToOpen(FLists[FTab]);
  if mNode = nil then
  begin
    // Durch oder an der Grenze: Treffer bestimmen, Pfade aufklappen, Rest ausblenden.
    mSearch.Apply(FLists[FTab]);
    FSearch.Done := True;
  end
  else
  begin
    mSearch.Opened(mNode);
    if not mNode.ChildrenLoaded then
    begin
      FSearch.Key := mNode.Key;
      Expand(FTab, mNode.Key);
    end;
  end;
  Refresh;
end;

procedure TAtlasIdeDebugVariables.Expand(ATab: TAtlasVariablesTab; const AKey: string);
var
  mNode: TAtlasEvalNode;
  mSession: TLspSession;
begin
  mNode := FLists[ATab].Find(AKey);
  if (mNode = nil) or mNode.ChildrenLoaded then
  begin
    Exit;
  end;
  mNode.Expanded := True;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Ohne Server, ohne Quelltext am Halt: Teile des Ergebnis-Strings.
  if (mSession = nil) or (FPlace.FileName = '') or (FText = '') or (mNode.Expression = '') then
  begin
    AcceptFields(FProgress.Request, ATab, AKey, nil);
    Exit;
  end;
  mSession.Sync(FPlace.FileName, FText);
  FFields.Start(mSession, FPlace.FileName, FPlace.Line, mNode.Expression + '.', False,
    FieldsArrived(FProgress.Request, ATab, AKey));
end;

procedure TAtlasIdeDebugVariables.AcceptFields(ARequest: Integer; ATab: TAtlasVariablesTab; const AKey: string;
  const AFields: TArray<string>);
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  // Antwort eines früheren Halts: verwerfen.
  if ARequest <> FProgress.Request then
  begin
    Exit;
  end;
  mList := FLists[ATab];
  mNode := mList.Find(AKey);
  // Felder des Index ersetzen Teile, die der Wert inzwischen geliefert hat.
  TAtlasEvalRows.AcceptFields(mList, mNode, AFields);
  if (ATab = FTab) and (AKey = FSearch.Key) then
  begin
    FSearch.Key := '';
    if mNode <> nil then
    begin
      FLists.Search.Loaded(mNode);
    end;
  end;
  Refresh;
  if FProgress.Phase = TAtlasStopPhase.Idle then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugVariables.WatchesChanged(AEvaluate: Boolean);
begin
  Refresh;
  if AEvaluate and (FProgress.Phase = TAtlasStopPhase.Idle) then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugVariables.Attach(AFrame: TAtlasDebugVariablesFrame);
begin
  WireView(AFrame);
  WireWatches(AFrame);
  WireEdit(AFrame);
  AFrame.SetTab(FTab);
  AFrame.SetList(FLists[FTab], FLists.Search);
  FWatches.Sync(StillStopped);
  if (TAtlasIdeDebugSession.StoppedThread <> nil) and (TAtlasIdeDebugSession.StopCount <> FProgress.Stop) then
  begin
    SessionStopped;
  end;
  Refresh;
end;

procedure TAtlasIdeDebugVariables.SetTab(ATab: TAtlasVariablesTab);
var
  mSearch: TAtlasVariableSearch;
begin
  FTab := ATab;
  if Frame <> nil then
  begin
    Frame.SetTab(ATab);
    Frame.SetList(FLists[ATab], FLists.Search);
  end;
  // Die Suche gilt für den gezeigten Reiter: dort neu.
  mSearch := FLists.Search;
  Search(mSearch.Text, mSearch.Mode, mSearch.Deep);
end;

procedure TAtlasIdeDebugVariables.Search(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean);
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  FLists.Search.Start(AText, AMode, ADeep, mSettings.DebugVariablesSearchDepth,
    mSettings.DebugVariablesSearchLimit);
  FSearch.Key := '';
  FSearch.Done := False;
  if StillStopped then
  begin
    if FProgress.Phase = TAtlasStopPhase.Idle then
    begin
      StartEvaluate;
    end;
  end
  else
  begin
    // Ohne angehaltenen Prozess öffnet die Suche nichts: nur im Vorhandenen.
    FLists.Search.Apply(FLists[FTab]);
    FSearch.Done := True;
  end;
  Refresh;
end;

procedure TAtlasIdeDebugVariables.Refresh;
var
  mFrame: TAtlasDebugVariablesFrame;
  mHasServer: Boolean;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mHasServer := Assigned(FSession) and (FSession() <> nil);
  mFrame.SetHidden(FWatches.Hidden, FWatches.ShowHidden);
  mFrame.Refresh;
  mFrame.SetStatus(StatusText(FLists, FTab, FSearch.Done, mHasServer));
end;

class procedure TAtlasIdeDebugVariables.Start(const ASession: TAtlasVariablesSessionFunc;
  const ARun: TAtlasVariablesRunner);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugVariables.Create(ASession, ARun);
    FInstance.Listen;
  end;
  TAtlasIdeDebugSession.Start;
  TAtlasIdeDebugVariablesWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugVariablesFrame)
    begin
      if FInstance <> nil then
      begin
        FInstance.Attach(AFrame);
      end;
    end;
  TAtlasIdeDebugVariablesWindow.Prepare;
  // Eingeschaltet, während der Prozess steht und das Fenster schon besteht: gleich für diesen Halt.
  if (TAtlasIdeDebugSession.StoppedThread <> nil) and (Frame <> nil) then
  begin
    FInstance.SessionStopped;
  end;
end;

class procedure TAtlasIdeDebugVariables.Release;
var
  mInstance: TAtlasIdeDebugVariables;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  // Der Frame zeigt die Listen der Instanz: erst lösen, dann Fenster und Instanz freigeben.
  if Frame <> nil then
  begin
    Frame.SetList(nil, nil);
  end;
  TAtlasIdeDebugVariablesWindow.Release;
  mInstance.Free;
end;

class function TAtlasIdeDebugVariables.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugVariables.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugVariablesWindow;
end;

class procedure TAtlasIdeDebugVariables.ApplySettings;
begin
  if (FInstance <> nil) and not Enabled then
  begin
    TAtlasIdeDebugVariablesWindow.Hide;
  end;
end;

class procedure TAtlasIdeDebugVariables.ThemeChanged;
begin
  TAtlasIdeDebugVariablesWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugVariables.ShowWindow;
var
  mShown: TAtlasDebugVariablesFrame;
begin
  if (FInstance = nil) or not Enabled then
  begin
    Exit;
  end;
  mShown := TAtlasIdeDebugVariablesWindow.Show;
  if mShown <> nil then
  begin
    FInstance.Attach(mShown);
  end;
end;

class procedure TAtlasIdeDebugVariables.Reevaluate;
var
  mSearch: TAtlasVariableSearch;
begin
  if not StillStopped or (Frame = nil) then
  begin
    Exit;
  end;
  // Wie ein neuer Halt am selben Ort: Autos und Lokal bleiben, alle Werte kommen neu.
  FInstance.CancelWork;
  FInstance.FLists.BeginStop;
  mSearch := FInstance.FLists.Search;
  FInstance.Search(mSearch.Text, mSearch.Mode, mSearch.Deep);
end;

end.
