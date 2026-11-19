unit Atlas.IDE.Debug.ReturnValues;

// Rückgabewerte nach dem Verlassen eigener Funktionen (#844) im Debugger der IDE. Betroffene Funktionen,
// end-Zeilen, Ablauf und Verlauf stehen ohne IDE in Atlas.Core.Debug.ReturnValues und Atlas.Core.Debug.ReturnFlow;
// Zeichnen und Klick in der Basis TAtlasIdeDebugLineNote. Hier bleiben Debugger, Server und Editor:
// - Bei jedem Halt im eigenen Code: Ort, Stapeltiefe (LLDB liefert sie verzögert, dann erneut über den Takt) und
//   die Funktion um den Ausführungspunkt (für Umschalt+F8); die Aufrufe der Zeile fragt Atlas im Hintergrund beim
//   Server (atlas.server.stepTargets) und behält die eigenen Funktionen darunter (für F8).
// - F8 bzw. Umschalt+F8 (Aktionen der IDE, auch Menü und Symbolleiste, über TAtlasIdeDebugTrace): Liegen die Daten
//   für diesen Halt vor, setzt Atlas vor dem Schritt der IDE vorübergehende Haltepunkte auf die end-Zeilen. Steht dort
//   schon ein Haltepunkt des Benutzers, legt Atlas keinen an; der des Benutzers hält wie gewohnt.
// - Halte während des Schritts gehen zuerst an den Filter der Debug-Sitzung (SetNamedStopFilter): Was der Ablauf
//   erledigt (Result auswerten, „Bis zur Rückkehr“, weiterlaufen, über die Zeile fortsetzen), erreicht die übrigen
//   Anzeigen nicht. Jeder andere Halt beendet den Ablauf: Haltepunkte weg, Ergebnisse am Ende der Aufrufzeile
//   (bei Umschalt+F8 die Zeile des Halts im Aufrufer), Klick zeigt die letzten 20.
// - Nicht auswertbares Result (etwa mit $O+) erscheint als ‹kein Zugriff›.
// Ohne debug.returnValues ist nichts angemeldet: keine Anfrage, kein Haltepunkt. Nur im Hauptthread verwenden.

interface

uses
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.ReturnValues,
  Atlas.Core.Debug.ReturnFlow,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Trace,
  Atlas.IDE.Debug.LineNote;

type
  TAtlasReturnValuesSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugReturnValues = class(TAtlasIdeDebugLineNote)
  public const
    /// <summary>Name bei TAtlasIdeDebugTrace und beim Filter der Debug-Sitzung.</summary>
    cName = 'ReturnValues';
  private const
    cTickMs = 10;
    cLocationRetries = 20;
    cLocationTicks = 5;
    cRequestTimeoutMs = 5000;
    /// <summary>Zeitlimit je Auswertung von Result.</summary>
    cEvaluateMs = 1000;
  private type
    /// <summary>Was zum Halt FStop vorbereitet ist.</summary>
    TPrepared = record
      Stop: TAtlasReturnStop;
      Calls: TArray<TAtlasReturnWatch>;
      Own: TArray<TAtlasReturnWatch>;
      Text: string;
    end;
  private class var
    FInstance: TAtlasIdeDebugReturnValues;
  private
    FSession: TAtlasReturnValuesSessionFunc;
    FRun: TAtlasHostCommandRunner;
    FValues: TAtlasReturnValues;
    FFlow: TAtlasReturnFlow;
    FBreaks: TArray<IOTABreakpoint>;
    FPrepared: TPrepared;
    /// <summary>Text der Zeile mit der Anzeige beim Halt.</summary>
    FLineText: string;
    constructor Create(const ASession: TAtlasReturnValuesSessionFunc; const ARun: TAtlasHostCommandRunner);
    procedure Drop;
    procedure ResetPrepared;
    procedure Traced(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
    procedure Arm(AMode: TAtlasReturnMode; const AWatches: TArray<TAtlasReturnWatch>);
    function Filter(AStop: TAtlasDebugStop): Boolean;
    function Apply(AAction: TAtlasReturnAction): Boolean;
    procedure Collect;
    procedure Finish(const AStop: TAtlasReturnStop);
    procedure Accept(ARequest: Integer; const AAnswer: string);
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    function ReadLocation: Boolean; override;
    procedure Ask; override;
    function NoteText(const AFileName: string; ALine: Integer; out ALineText: string): string; override;
    function NoteShown: Boolean; override;
    procedure HistoryItems(out AHint, AHeader: string; out ALines: TArray<string>); override;
  public
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), ARun schickt Serverbefehle im Hintergrund.
    /// </summary>
    class procedure Start(const ASession: TAtlasReturnValuesSessionFunc; const ARun: TAtlasHostCommandRunner);
      static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.returnValues an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Debug.StepInto,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.ReturnValues.Strings;

/// <summary>Text von AFileName aus dem Editor bzw. von der Platte; False ohne.</summary>
function SourceOf(const AFileName: string; out AText: string): Boolean;
begin
  Result := TAtlasIdeFiles.SourceText(AFileName, AText);
end;

/// <summary>Gehört AFileName zum eigenen Code (#578)?</summary>
function IsOwn(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeDebugSources.OwnCode.IsOwnFile(AFileName);
end;

/// <summary>Zeile ALine (ab 0) aus AText; '' außerhalb.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
begin
  Result := '';
  mLines := AText.Split([#13#10, #10]);
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    Result := mLines[ALine];
  end;
end;

{ TAtlasIdeDebugReturnValues }

constructor TAtlasIdeDebugReturnValues.Create(const ASession: TAtlasReturnValuesSessionFunc;
  const ARun: TAtlasHostCommandRunner);
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FValues := TAtlasReturnValues.Create;
  FFlow := TAtlasReturnFlow.Create;
  ResetPrepared;
  CreateTimer(cTickMs);
end;

destructor TAtlasIdeDebugReturnValues.Destroy;
begin
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  FreeAndNil(FFlow);
  FreeAndNil(FValues);
  FPrepared := Default(TPrepared);
  FLineText := '';
  FSession := nil;
  FRun := nil;
  inherited Destroy;
end;

procedure TAtlasIdeDebugReturnValues.Drop;
var
  mHad: Boolean;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FProgress.Discard;
  ResetPrepared;
  ForgetHit;
  mHad := NoteShown;
  FValues.Hide;
  if mHad then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugReturnValues.ResetPrepared;
begin
  FPrepared := Default(TPrepared);
  FPrepared.Stop := TAtlasReturnStop.Create('', -1, -1);
end;

procedure TAtlasIdeDebugReturnValues.SessionStarted;
begin
  FFlow.Cancel;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  Drop;
  FValues.Clear;
end;

procedure TAtlasIdeDebugReturnValues.SessionStopped;
begin
  // Ergebnisse des eben beendeten Schritts zeigen (Finish hat sie im Filter abgelegt).
  if NoteShown then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  ResetPrepared;
  if not Enabled then
  begin
    Exit;
  end;
  FProgress.Restart(TAtlasIdeDebugSession.StopCount);
  if ReadLocation then
  begin
    Ask;
  end;
end;

procedure TAtlasIdeDebugReturnValues.SessionResumed;
begin
  // Eigene Schritte des Ablaufs meldet die Sitzung nicht; ein Weiterlaufen des Benutzers nimmt die Anzeige weg.
  if not FFlow.Active then
  begin
    Drop;
  end;
end;

procedure TAtlasIdeDebugReturnValues.SessionEnded;
begin
  FFlow.Cancel;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  Drop;
end;

/// <summary>Ort (aufgelöste Datei, Zeile ab 0) und Stapeltiefe des Halts (-1 ohne); False ohne Quelltext.</summary>
function CurrentStop(out AStop: TAtlasReturnStop): Boolean;
var
  mThread: IOTAThread;
  mFileName: string;
  mLine, mDepth: Integer;
begin
  mThread := TAtlasIdeDebugSession.StoppedThread;
  mDepth := -1;
  Result := TAtlasIdeBreakpoints.Position(mThread, mFileName, mLine);
  if Result then
  begin
    mFileName := TAtlasIdeDebugSources.Resolve(mFileName);
    Result := mFileName <> '';
  end;
  if TAtlasIdeDebugSession.StackDepth(mThread, mDepth) <> TAtlasDebugStackRead.Ready then
  begin
    mDepth := -1;
  end;
  AStop := TAtlasReturnStop.Create(mFileName, mLine, mDepth);
end;

function TAtlasIdeDebugReturnValues.ReadLocation: Boolean;
var
  mStop: TAtlasReturnStop;
  mHas: Boolean;
begin
  mHas := CurrentStop(mStop);
  case FProgress.Locate(TAtlasIdeDebugSession.StoppedThread = nil, mHas and not IsOwn(mStop.FileName),
    mHas and (mStop.Depth >= 0), cLocationRetries) of
    TAtlasStopLocation.Retry:
      begin
        FTimer.Interval := cTickMs * cLocationTicks;
        FTimer.Enabled := True;
        Exit(False);
      end;
    TAtlasStopLocation.GiveUp:
      Exit(False);
  end;
  FPrepared.Stop := mStop;
  Result := SourceOf(mStop.FileName, FPrepared.Text);
end;

procedure TAtlasIdeDebugReturnValues.Ask;
var
  mOwn: TAtlasReturnWatch;
  mSession: TLspSession;
  mRequest: Integer;
begin
  FTimer.Enabled := False;
  FProgress.Phase := TAtlasStopPhase.Idle;
  // Umschalt+F8: die eigene Funktion um den Ausführungspunkt.
  if TAtlasReturnValues.FunctionAt(FPrepared.Text, FPrepared.Stop.FileName, FPrepared.Stop.Line, mOwn) then
  begin
    FPrepared.Own := [mOwn];
  end;
  // F8: Aufrufe der Zeile beim Server.
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if (mSession = nil) or not Assigned(FRun) then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FPrepared.Stop.FileName, FPrepared.Text);
  mRequest := FProgress.NextRequest;
  FRun(TAtlasStepInto.cCommand, TAtlasStepInto.Arguments(TLspSession.PathToUri(FPrepared.Stop.FileName),
    FPrepared.Stop.Line), cRequestTimeoutMs,
    procedure(AAnswer: string)
    begin
      if TAtlasIdeDebugReturnValues.FInstance <> nil then
      begin
        TAtlasIdeDebugReturnValues.FInstance.Accept(mRequest, AAnswer);
      end;
    end);
end;

procedure TAtlasIdeDebugReturnValues.Accept(ARequest: Integer; const AAnswer: string);
var
  mJson: TJSONValue;
  mAnswer: TAtlasStepAnswer;
begin
  if not FProgress.IsNewest(ARequest) or (FProgress.Stop <> TAtlasIdeDebugSession.StopCount) or (AAnswer = '') then
  begin
    Exit;
  end;
  mJson := TJSONObject.ParseJSONValue(AAnswer);
  try
    if TAtlasStepInto.ReadAnswer(mJson, mAnswer) then
    begin
      FPrepared.Calls := TAtlasReturnValues.Watches(mAnswer, SourceOf, IsOwn);
    end;
  finally
    mJson.Free;
  end;
end;

procedure TAtlasIdeDebugReturnValues.Traced(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
var
  mHad: Boolean;
begin
  if (AOrigin <> TAtlasTraceOrigin.User) or FFlow.Active or not Enabled then
  begin
    Exit;
  end;
  // Die Anzeige des vorigen Schritts verschwindet mit jedem neuen.
  mHad := NoteShown;
  FValues.BeginStep;
  if mHad then
  begin
    ForgetHit;
    TAtlasDebugLineEnd.Invalidate;
  end;
  if (FProgress.Stop <> TAtlasIdeDebugSession.StopCount) or (FPrepared.Stop.Depth < 0) then
  begin
    Exit;
  end;
  // Angemeldet nur für F8 und Umschalt+F8.
  if AKind = TAtlasTraceKind.RunUntilReturn then
  begin
    Arm(TAtlasReturnMode.RunUntilReturn, FPrepared.Own);
  end
  else
  begin
    Arm(TAtlasReturnMode.StepOver, FPrepared.Calls);
  end;
end;

procedure TAtlasIdeDebugReturnValues.Arm(AMode: TAtlasReturnMode; const AWatches: TArray<TAtlasReturnWatch>);
var
  mIndex, mCount: Integer;
  mBreak: IOTABreakpoint;
  mArmed: TArray<TAtlasReturnWatch>;
begin
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  mArmed := nil;
  SetLength(mArmed, Length(AWatches));
  SetLength(FBreaks, Length(AWatches));
  mCount := 0;
  for mIndex := 0 to High(AWatches) do
  begin
    // Steht dort schon ein Haltepunkt des Benutzers, hält er wie gewohnt (und beendet den Ablauf).
    mBreak := TAtlasIdeBreakpoints.Add(AWatches[mIndex].FileName, AWatches[mIndex].EndLine);
    if mBreak <> nil then
    begin
      FBreaks[mCount] := mBreak;
      mArmed[mCount] := AWatches[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(FBreaks, mCount);
  SetLength(mArmed, mCount);
  FFlow.Start(AMode, FPrepared.Stop, mArmed);
  if not FFlow.Active then
  begin
    TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  end;
end;

function TAtlasIdeDebugReturnValues.Filter(AStop: TAtlasDebugStop): Boolean;
var
  mStop: TAtlasReturnStop;
begin
  Result := False;
  if not FFlow.Active then
  begin
    Exit;
  end;
  mStop := TAtlasReturnStop.Create('', -1, -1);
  try
    CurrentStop(mStop);
    if AStop <> TAtlasDebugStop.Paused then
    begin
      // Exception: Der Benutzer soll sehen, wo es gekracht hat.
      FFlow.Cancel;
    end;
    Result := Apply(FFlow.Stopped(mStop));
    if not Result then
    begin
      Finish(mStop);
    end;
  except
    // Fehler im Ablauf: Haltepunkte weg, der Halt gehört dem Benutzer.
    on E: Exception do
    begin
      Finish(mStop);
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
      Result := False;
    end;
  end;
end;

function TAtlasIdeDebugReturnValues.Apply(AAction: TAtlasReturnAction): Boolean;
var
  mAction: TAtlasReturnAction;
begin
  mAction := AAction;
  if mAction = TAtlasReturnAction.Evaluate then
  begin
    Collect;
    mAction := FFlow.Returned;
  end;
  case mAction of
    TAtlasReturnAction.Return:
      Result := TAtlasIdeDebugSession.RunMode(ormRunUntilReturn);
    TAtlasReturnAction.Resume:
      Result := TAtlasIdeDebugSession.RunMode(ormRun);
    TAtlasReturnAction.StepOver:
      Result := TAtlasIdeDebugSession.RunMode(ormStmtStepOver);
  else
    Result := False;
  end;
end;

procedure TAtlasIdeDebugReturnValues.Collect;
var
  mValue: string;
  mOk: Boolean;
begin
  TAtlasIdeDebugSession.BeginInternal;
  try
    mOk := TAtlasIdeDebugEvaluator.Evaluate('Result', TAtlasVisualizerEvaluation.Fields, cEvaluateMs, mValue);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
  if not mOk or (mValue = '') then
  begin
    mValue := TAtlasReturnValuesStrings.Text(TAtlasReturnValuesTextId.ReturnUnavailable);
  end;
  FValues.Add(FFlow.Current, mValue, Now);
end;

procedure TAtlasIdeDebugReturnValues.Finish(const AStop: TAtlasReturnStop);
var
  mPlace: TAtlasReturnStop;
  mText: string;
begin
  mPlace := FFlow.Origin;
  if FFlow.Mode = TAtlasReturnMode.RunUntilReturn then
  begin
    // Bis zur Rückkehr: Die Aufrufzeile ist die des Halts im Aufrufer.
    mPlace := AStop;
  end;
  FFlow.Cancel;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  FLineText := '';
  if FValues.Show(mPlace.FileName, mPlace.Line) and SourceOf(mPlace.FileName, mText) then
  begin
    FLineText := LineOf(mText, mPlace.Line);
  end;
end;

function TAtlasIdeDebugReturnValues.NoteText(const AFileName: string; ALine: Integer; out ALineText: string): string;
begin
  ALineText := FLineText;
  Result := FValues.LineText(AFileName, ALine);
end;

function TAtlasIdeDebugReturnValues.NoteShown: Boolean;
var
  mFileName: string;
  mLine: Integer;
begin
  Result := FValues.Shown(mFileName, mLine);
end;

procedure TAtlasIdeDebugReturnValues.HistoryItems(out AHint, AHeader: string; out ALines: TArray<string>);
var
  mEntries: TArray<TAtlasReturnEntry>;
  mIndex: Integer;
begin
  AHint := TAtlasReturnValuesStrings.Text(TAtlasReturnValuesTextId.ReturnHint);
  AHeader := TAtlasReturnValuesStrings.Text(TAtlasReturnValuesTextId.ReturnHistory);
  mEntries := FValues.Entries;
  ALines := nil;
  SetLength(ALines, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    ALines[mIndex] := TAtlasReturnValues.HistoryLine(mEntries[mIndex]);
  end;
end;

class procedure TAtlasIdeDebugReturnValues.Start(const ASession: TAtlasReturnValuesSessionFunc;
  const ARun: TAtlasHostCommandRunner);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugReturnValues.Create(ASession, ARun);
    FInstance.Listen;
    TAtlasIdeDebugTrace.AddStepHandler(cName, [TAtlasTraceKind.StepOver, TAtlasTraceKind.RunUntilReturn],
      procedure(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin)
      begin
        if FInstance <> nil then
        begin
          FInstance.Traced(AKind, AOrigin);
        end;
      end);
    TAtlasIdeDebugSession.SetNamedStopFilter(cName,
      function(AStop: TAtlasDebugStop): Boolean
      begin
        Result := (FInstance <> nil) and FInstance.Filter(AStop);
      end);
  end;
  TAtlasIdeDebugSession.Start;
  if TAtlasIdeDebugSession.StoppedThread <> nil then
  begin
    FInstance.SessionStopped;
  end;
end;

class procedure TAtlasIdeDebugReturnValues.Release;
var
  mInstance: TAtlasIdeDebugReturnValues;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  TAtlasIdeDebugSession.SetNamedStopFilter(cName, nil);
  TAtlasIdeDebugTrace.RemoveHandler(cName);
  mInstance := FInstance;
  FInstance := nil;
  mInstance.Free;
  TAtlasDebugLineEnd.Invalidate;
end;

class function TAtlasIdeDebugReturnValues.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugReturnValues.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugReturnValues;
end;

end.
