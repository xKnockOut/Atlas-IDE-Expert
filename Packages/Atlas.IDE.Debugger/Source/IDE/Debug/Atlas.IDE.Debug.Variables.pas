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
//     (TAtlasIdeVariablesStore), kommen mit dem Projekt wieder.
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
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.FieldRequests,
  Atlas.IDE.Debug.VariablesLists,
  Atlas.IDE.Debug.VariablesStore;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasVariablesSessionFunc = reference to function: TLspSession;
  /// <summary>Serverbefehl im Hintergrund; ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler).
  /// False = nicht gestartet.</summary>
  TAtlasVariablesRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugVariables = class
  public const
    cTickMs = 10;
    cRequestTimeoutMs = 3000;
    /// <summary>Versuche, bis der Aufrufstapel da ist (je cTickMs * cLocationTicks).</summary>
    cLocationRetries = 20;
    cLocationTicks = 5;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    {$SCOPEDENUMS ON}
    TPhase = (Idle, Location, Request, Evaluate);
    {$SCOPEDENUMS OFF}
    /// <summary>Ausführungspunkt: Datei und Zeile (0-basiert, -1 ohne).</summary>
    TPlace = record
      FileName: string;
      Line: Integer;
    end;
    TProgress = record
      Phase: TPhase;
      /// <summary>Halt (TAtlasIdeDebugSession.StopCount), für den die Listen gelten.</summary>
      Stop: Integer;
      /// <summary>Nummer der Anfragen; ältere Antworten verwirft Atlas.</summary>
      Request: Integer;
      Retries: Integer;
      /// <summary>Knoten, auf dessen Felder die Suche wartet; '' ohne.</summary>
      SearchKey: string;
      /// <summary>Die Suche ist durch (Treffer bestimmt).</summary>
      SearchDone: Boolean;
    end;
  private class var
    FInstance: TAtlasIdeDebugVariables;
  private
    FSession: TAtlasVariablesSessionFunc;
    FRun: TAtlasVariablesRunner;
    FLists: TAtlasIdeVariablesLists;
    FFields: TAtlasIdeDebugFieldRequests;
    FStore: TAtlasIdeVariablesStore;
    FListener: IAtlasIdeDebugListener;
    FTimer: TTimer;
    FTab: TAtlasVariablesTab;
    FProgress: TProgress;
    FPlace: TPlace;
    FPrevious: TPlace;
    /// <summary>Text der Datei am Halt, für die Felder aus dem Index.</summary>
    FText: string;
    constructor Create(const ASession: TAtlasVariablesSessionFunc; const ARun: TAtlasVariablesRunner);
    procedure CancelWork;
    procedure Stopped;
    procedure Tick(Sender: TObject);
    /// <summary>Ausführungspunkt lesen; False: später noch einmal (LLDB).</summary>
    function ReadLocation: Boolean;
    procedure Ask;
    procedure Accept(ARequest: Integer; const AAnswer: string);
    procedure StartEvaluate;
    procedure EvaluateSlice;
    procedure SearchStep;
    procedure Expand(ATab: TAtlasVariablesTab; const AKey: string);
    procedure AcceptFields(ARequest: Integer; ATab: TAtlasVariablesTab; const AKey: string;
      const AFields: TArray<string>);
    procedure AddWatch(const AExpression: string);
    procedure RemoveWatch(ANode: TAtlasEvalNode);
    procedure SyncWatches;
    procedure SetTab(ATab: TAtlasVariablesTab);
    /// <summary>Suche mit AText im gezeigten Reiter (neu) starten; leer: Suche aus.</summary>
    procedure Search(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean);
    procedure Refresh;
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
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.EditValue,
  Atlas.IDE.Debug.VariablesWindow,
  Atlas.UI.Debug.VariablesFrame,
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
  mSearch: TAtlasVariableSearch;
begin
  mSearch := ALists.Search;
  if not AHasServer and (ATab <> TAtlasVariablesTab.Watch) then
  begin
    Result := TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesNoServer);
  end
  else if not mSearch.Active then
  begin
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesCount, [ALists[ATab].Count]);
  end
  else if not ASearchDone then
  begin
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesSearching, [mSearch.Evaluations]);
  end
  else if mSearch.Truncated then
  begin
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesTruncated,
      [mSearch.HitCount, mSearch.Evaluations]);
  end
  else
  begin
    Result := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesHits, [mSearch.HitCount]);
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
  AFrame.OnTab :=
    procedure(ATab: TAtlasVariablesTab)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.SetTab(ATab);
      end;
    end;
  AFrame.OnSearch :=
    procedure(const AText: string; AMode: TAtlasVariableSearchMode; ADeep: Boolean)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.Search(AText, AMode, ADeep);
      end;
    end;
  AFrame.OnExpand :=
    procedure(ANode: TAtlasEvalNode)
    begin
      QueueExpand(ANode.Key);
    end;
end;

/// <summary>Überwachung hinzufügen und entfernen.</summary>
procedure WireWatches(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.OnAddWatch :=
    procedure(AExpression: string)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.AddWatch(AExpression);
      end;
    end;
  AFrame.OnRemoveWatch :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if TAtlasIdeDebugVariables.FInstance <> nil then
      begin
        TAtlasIdeDebugVariables.FInstance.RemoveWatch(ANode);
      end;
    end;
end;

/// <summary>Wert ändern (#868): nur mit laufendem „Werte ändern“, im angehaltenen Programm und mit Ort.</summary>
procedure WireEdit(AFrame: TAtlasDebugVariablesFrame);
begin
  AFrame.OnCanEditValue :=
    function: Boolean
    begin
      Result := TAtlasIdeDebugEditValue.Started and StillStopped and
        (TAtlasIdeDebugVariables.FInstance.FPlace.Line >= 0);
    end;
  AFrame.OnEditValue :=
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

/// <summary>AFrame an die Instanz hängen (nach jedem Anlegen des Fensters); einen verpassten Halt nachholen.
/// </summary>
procedure WireFrame(AFrame: TAtlasDebugVariablesFrame);
var
  mInstance: TAtlasIdeDebugVariables;
begin
  mInstance := TAtlasIdeDebugVariables.FInstance;
  if mInstance = nil then
  begin
    Exit;
  end;
  WireView(AFrame);
  WireWatches(AFrame);
  WireEdit(AFrame);
  AFrame.SetTab(mInstance.FTab);
  AFrame.SetList(mInstance.FLists[mInstance.FTab], mInstance.FLists.Search);
  mInstance.SyncWatches;
  if (TAtlasIdeDebugSession.StoppedThread <> nil) and
    (TAtlasIdeDebugSession.StopCount <> mInstance.FProgress.Stop) then
  begin
    mInstance.Stopped;
  end;
  mInstance.Refresh;
end;

{ TAtlasIdeDebugVariables.TListener }

procedure TAtlasIdeDebugVariables.TListener.DebugStarted;
begin
  if FInstance <> nil then
  begin
    FInstance.SyncWatches;
  end;
end;

procedure TAtlasIdeDebugVariables.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugVariables.TListener.DebugResumed;
begin
  // Die Werte bleiben stehen bis zum nächsten Halt; nur laufende Arbeit endet.
  if FInstance <> nil then
  begin
    FInstance.CancelWork;
  end;
end;

procedure TAtlasIdeDebugVariables.TListener.DebugEnded;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.CancelWork;
  FInstance.FLists.Unavailable;
  FInstance.FPlace := NoPlace;
  FInstance.FPrevious := NoPlace;
  FInstance.FText := '';
  FInstance.Refresh;
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
  FStore := TAtlasIdeVariablesStore.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeDebugVariables.Destroy;
begin
  FreeAndNil(FTimer);
  // Laufende Feldanfragen halten die Sitzung: Destroy wartet sie ab.
  FreeAndNil(FFields);
  FreeAndNil(FLists);
  FreeAndNil(FStore);
  FText := '';
  FProgress.SearchKey := '';
  inherited Destroy;
end;

class procedure TAtlasIdeDebugVariables.Start(const ASession: TAtlasVariablesSessionFunc;
  const ARun: TAtlasVariablesRunner);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugVariables.Create(ASession, ARun);
    FInstance.FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  end;
  TAtlasIdeDebugSession.Start;
  TAtlasIdeDebugVariablesWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugVariablesFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugVariablesWindow.Prepare;
  // Eingeschaltet, während der Prozess steht und das Fenster schon besteht: gleich für diesen Halt.
  if (TAtlasIdeDebugSession.StoppedThread <> nil) and (Frame <> nil) then
  begin
    FInstance.Stopped;
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
  if mInstance.FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(mInstance.FListener);
  end;
  mInstance.FListener := nil;
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
    WireFrame(mShown);
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

procedure TAtlasIdeDebugVariables.CancelWork;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FLists.Cancel;
  // Antworten noch laufender Anfragen verwerfen.
  Inc(FProgress.Request);
  FProgress.Phase := TPhase.Idle;
  FProgress.SearchKey := '';
  FFields.Reap(False);
end;

procedure TAtlasIdeDebugVariables.Stopped;
var
  mSearch: TAtlasVariableSearch;
begin
  CancelWork;
  FPrevious := FPlace;
  FPlace := NoPlace;
  FText := '';
  // Ohne Fenster nichts auswerten; öffnet es sich bei diesem Halt, holt WireFrame ihn nach.
  if not Enabled or (Frame = nil) then
  begin
    FPrevious := NoPlace;
    Exit;
  end;
  FProgress.Stop := TAtlasIdeDebugSession.StopCount;
  FProgress.Retries := 0;
  FLists.BeginStop;
  // Erst den Ort lesen; die Suche startet mit den neuen Werten neu.
  FProgress.Phase := TPhase.Location;
  mSearch := FLists.Search;
  Search(mSearch.Text, mSearch.Mode, mSearch.Deep);
  if ReadLocation then
  begin
    Ask;
  end;
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
  end;
end;

procedure TAtlasIdeDebugVariables.Ask;
var
  mSession: TLspSession;
  mPrevious: Integer;
begin
  FTimer.Enabled := False;
  Inc(FProgress.Request);
  FProgress.Phase := TPhase.Request;
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
  mPrevious := -1;
  if SameText(FPrevious.FileName, FPlace.FileName) then
  begin
    mPrevious := FPrevious.Line;
  end;
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
  if (ARequest <> FProgress.Request) or (FProgress.Phase <> TPhase.Request) or not StillStopped then
  begin
    Exit;
  end;
  if not TAtlasVariables.ReadAnswerText(AAnswer, mAnswer) then
  begin
    mAnswer := Default(TAtlasVariablesAnswer);
  end;
  FLists[TAtlasVariablesTab.Autos].Replace(mAnswer.Autos);
  FLists[TAtlasVariablesTab.Locals].Replace(mAnswer.Locals);
  StartEvaluate;
  Refresh;
end;

procedure TAtlasIdeDebugVariables.StartEvaluate;
begin
  if not StillStopped then
  begin
    Exit;
  end;
  FProgress.Phase := TPhase.Evaluate;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugVariables.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  try
    case FProgress.Phase of
      TPhase.Location:
        begin
          FTimer.Enabled := False;
          if not StillStopped then
          begin
            FProgress.Phase := TPhase.Idle;
          end
          else if ReadLocation then
          begin
            Ask;
          end;
        end;
      TPhase.Evaluate:
        EvaluateSlice;
    else
      FTimer.Enabled := False;
    end;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
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
  if FLists.Busy or (FProgress.SearchKey <> '') then
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
  mWaiting := FLists.Busy or (FProgress.SearchKey <> '') or not FProgress.SearchDone;
  if not mWaiting and not FLists.HasPending then
  begin
    FTimer.Enabled := False;
    FProgress.Phase := TPhase.Idle;
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
  if FProgress.SearchDone then
  begin
    Exit;
  end;
  mSearch := FLists.Search;
  mNode := mSearch.NextToOpen(FLists[FTab]);
  if mNode = nil then
  begin
    // Durch oder an der Grenze: Treffer bestimmen, Pfade aufklappen, Rest ausblenden.
    mSearch.Apply(FLists[FTab]);
    FProgress.SearchDone := True;
  end
  else
  begin
    mSearch.Opened(mNode);
    if not mNode.ChildrenLoaded then
    begin
      FProgress.SearchKey := mNode.Key;
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
  if (mNode <> nil) and not (mNode.ChildrenLoaded and not mNode.FromParts) then
  begin
    if Length(AFields) > 0 then
    begin
      mList.SetFields(mNode, AFields);
    end
    else if not mNode.ChildrenLoaded and not mList.SetParts(mNode) then
    begin
      // Weder Felder noch Teile: aufgeklappt mit „(keine Felder)“.
      mList.SetFields(mNode, nil);
    end;
  end;
  if (ATab = FTab) and (AKey = FProgress.SearchKey) then
  begin
    FProgress.SearchKey := '';
    if mNode <> nil then
    begin
      FLists.Search.Loaded(mNode);
    end;
  end;
  Refresh;
  if FProgress.Phase = TPhase.Idle then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugVariables.AddWatch(const AExpression: string);
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := FLists[TAtlasVariablesTab.Watch];
  if (Trim(AExpression) = '') or (mList.Find(Trim(AExpression)) <> nil) then
  begin
    Exit;
  end;
  mNode := mList.Add(AExpression);
  FStore.Add(mNode.Expression);
  if not StillStopped then
  begin
    mNode.State := TAtlasEvalState.Unavailable;
  end;
  Refresh;
  if FProgress.Phase = TPhase.Idle then
  begin
    StartEvaluate;
  end;
end;

procedure TAtlasIdeDebugVariables.RemoveWatch(ANode: TAtlasEvalNode);
var
  mList: TAtlasEvalList;
  mIndex: Integer;
begin
  mList := FLists[TAtlasVariablesTab.Watch];
  mIndex := mList.IndexOf(ANode);
  if mIndex < 0 then
  begin
    Exit;
  end;
  FStore.Remove(ANode.Expression);
  // Eine laufende Auswertung dieser Zeile findet ihren Knoten nicht mehr und verfällt.
  mList.Delete(mIndex);
  Refresh;
end;

procedure TAtlasIdeDebugVariables.SyncWatches;
var
  mProject: string;
  mList: TAtlasEvalList;
begin
  if not FStore.SwitchProject(mProject) then
  begin
    Exit;
  end;
  mList := FLists[TAtlasVariablesTab.Watch];
  mList.Replace(FStore.Items(mProject));
  if not StillStopped then
  begin
    mList.Unavailable;
  end;
  Refresh;
  if FProgress.Phase = TPhase.Idle then
  begin
    StartEvaluate;
  end;
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
  FProgress.SearchKey := '';
  FProgress.SearchDone := False;
  if StillStopped then
  begin
    if FProgress.Phase = TPhase.Idle then
    begin
      StartEvaluate;
    end;
  end
  else
  begin
    // Ohne angehaltenen Prozess öffnet die Suche nichts: nur im Vorhandenen.
    FLists.Search.Apply(FLists[FTab]);
    FProgress.SearchDone := True;
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
  mFrame.Refresh;
  mFrame.SetStatus(StatusText(FLists, FTab, FProgress.SearchDone, mHasServer));
end;

end.
