unit Atlas.IDE.Debug.StepFilter;

// Schrittfilter beim Hineinspringen (#850) im Debugger der IDE. Welche Routine
// an einer Zeile beginnt und zu welchen Arten sie gehört (Getter, Setter,
// trivial, Operator, leerer Konstruktor), rechnet der Server
// (atlas.server.stepFilter); Urteil, Ablauf und Zwischenspeicher stehen in
// Atlas.Core.Debug.StepFilter, das Fenster in Atlas.UI.Debug.StepFilterFrame.
// Hier bleiben Debugger, Editor und Einstellungen:
// - F7 des Benutzers (TAtlasIdeDebugTrace): Stapeltiefe merken. Hält der
//   Schritt tiefer (neue Routine) an einer Zeile mit Quelltext ohne
//   Haltepunkt des Benutzers, fragt Atlas die Routine (je Datei und Zeile
//   einmal je Debug-Sitzung). Ist sie gefiltert, setzt Atlas „Bis zur
//   Rückkehr“ fort (ormRunUntilReturn) und springt danach auf derselben Tiefe
//   erneut hinein, höchstens TAtlasStepFilter.MaxSkips-mal je F7. Hält das
//   Programm dabei tiefer oder flacher (Haltepunkt, Exception, Ende der
//   Ausgangsroutine), bleibt es dort stehen.
// - Umschalt+F7 (Bis zur nächsten Quelltextzeile) und der Befehl „Trotzdem
//   hineinspringen“ springen einmal ohne Filter hinein.
// - Kontextmenü: Routine an der Schreibmarke als Muster aufnehmen bzw.
//   entfernen (debug.stepFilters.patterns).
// - Fenster „Schrittfilter“: Schalter, Arten und Muster mit Treffern im Index
//   (atlas.server.stepFilterCounts im Hintergrund) und die übersprungenen
//   Routinen der Sitzung.
// Install/Uninstall gelten für Fenster und Befehle, Start/Release für den
// Ablauf (nur mit debug.stepFilters). Gesichert über TAtlasFeature.Debugger.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.StepFilter,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.StepFilter,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Trace,
  Atlas.UI.Debug.StepFilterFrame;

type
  TAtlasStepFilterSessionFunc = reference to function: TLspSession;

  TAtlasIdeDebugStepFilter = class
  public const
    /// <summary>Name des Empfängers bei TAtlasIdeDebugTrace.</summary>
    TraceHandler = 'StepFilter';
    /// <summary>Zeitlimit je Routine: Der Debugger steht so lange.</summary>
    TimeoutMs = 3000;
    /// <summary>Zeitlimit für die Treffer im Index (im Hintergrund).</summary>
    CountsTimeoutMs = 10000;
    IntervalMs = 100;
    StackRetries = 10;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
    TStepState = record
      /// <summary>StopCount beim Auslösen des Schritts; der nächste Halt (+1) gehört dazu.</summary>
      Stop: Integer;
      Retries: Integer;
      /// <summary>Der nächste Schritt aus Atlas geht ohne Filter hinein („Trotzdem hineinspringen“).</summary>
      Bypass: Boolean;
    end;
    TSkipStats = record
      Count: Integer;
      LastName: string;
      LastReason: string;
    end;
    TCountsState = record
      Thread: TThread;
      Again: Boolean;
      Request: Integer;
      Patterns: string;
    end;
  private class var
    FSession: TAtlasStepFilterSessionFunc;
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FCache: TAtlasStepRoutineCache;
    FRun: TAtlasStepFilterRun;
    FStep: TStepState;
    // Übersprungen in dieser Debug-Sitzung.
    FSkips: TSkipStats;
    // Treffer im Index.
    FCounts: TCountsState;
    class procedure Traced(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin); static;
    class procedure Stopped; static;
    class procedure Check; static;
    class function Judge(const AThread: IOTAThread; out ARoutine: TAtlasStepRoutine): TAtlasStepVerdict; static;
    class function HasBreakpoint(const AFileName, AResolved: string; ALine: Integer): Boolean; static;
    class function Lookup(const AFileName: string; ALine: Integer; out ARoutine: TAtlasStepRoutine): Boolean;
      static;
    class function RoutineAtCursor(out ARoutine: TAtlasStepRoutine): Boolean; static;
    class procedure Remember(const ARoutine: TAtlasStepRoutine; const AVerdict: TAtlasStepVerdict); static;
    class procedure Report(const AText: string); static;
    class procedure SaveOptions(AEnabled: Boolean; AKinds: TStepFilterKinds; const APatterns: TArray<string>);
      static;
    class function Frame: TAtlasDebugStepFilterFrame; static;
    class procedure WireFrame(AFrame: TAtlasDebugStepFilterFrame); static;
    class procedure FillFrame(AFrame: TAtlasDebugStepFilterFrame); static;
    class procedure UpdateSession; static;
    class procedure Recount; static;
    class procedure CountsDone(ARequest: Integer; AOk: Boolean; const ACounts: TAtlasStepCounts); static;
    class procedure WaitCounts; static;
  public
    /// <summary>Fenster und Befehle: ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile
    /// in die Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasStepFilterSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Ablauf anmelden: Zuhörer der Debug-Sitzung, Empfänger der Schritte.</summary>
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Filter aus den aktuellen Einstellungen.</summary>
    class function Options: TAtlasStepFilterOptions; static;
    /// <summary>Befehl Atlas.StepIntoAnyway: einmal ohne Filter hineinspringen.</summary>
    class procedure StepIntoAnyway; static;
    /// <summary>Kontextmenü: Routine an der Schreibmarke als Muster aufnehmen.</summary>
    class procedure SkipAtCursor; static;
    /// <summary>Kontextmenü: Muster der Routine an der Schreibmarke entfernen.</summary>
    class procedure UnskipAtCursor; static;
    /// <summary>Befehl Atlas.StepFilters: Fenster zeigen.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Übersprungen in dieser Debug-Sitzung (Fenster, Studie).</summary>
    class function SkippedCount: Integer; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.StepFilterWindow;

/// <summary>Stapeltiefe von AThread; False ohne: im Takt neu versuchen oder (nach StackRetries) abbrechen.</summary>
function ReadDepth(const AThread: IOTAThread; out ADepth: Integer): Boolean;
begin
  Result := False;
  case TAtlasIdeDebugSession.StackDepth(AThread, ADepth) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(TAtlasIdeDebugStepFilter.FStep.Retries);
        if TAtlasIdeDebugStepFilter.FStep.Retries <= TAtlasIdeDebugStepFilter.StackRetries then
        begin
          TAtlasIdeDebugStepFilter.FTimer.Enabled := True;
        end
        else
        begin
          TAtlasIdeDebugStepFilter.FRun.Cancel;
        end;
      end;
    TAtlasDebugStackRead.None:
      TAtlasIdeDebugStepFilter.FRun.Cancel;
  else
    Result := True;
  end;
end;

/// <summary>Nächsten Schritt des Filters auslösen; ohne Aktion der IDE abbrechen.</summary>
procedure ApplyAction(AAction: TAtlasStepFilterAction);
begin
  case AAction of
    TAtlasStepFilterAction.Return:
      begin
        TAtlasIdeDebugStepFilter.FStep.Stop := TAtlasIdeDebugSession.StopCount;
        if not TAtlasIdeDebugSession.RunMode(ormRunUntilReturn) then
        begin
          TAtlasIdeDebugStepFilter.FRun.Cancel;
        end;
      end;
    TAtlasStepFilterAction.StepInto:
      // Der Empfänger (Origin Atlas) setzt FStep.Stop.
      if not TAtlasIdeDebugTrace.StepInto then
      begin
        TAtlasIdeDebugStepFilter.FRun.Cancel;
      end;
    TAtlasStepFilterAction.Keep: ;
  end;
end;

/// <summary>Datei, Zeile (0-basiert) und gefundene Quelle am Halt von AThread; False ohne Quelltext.</summary>
function SourceAt(const AThread: IOTAThread; out AFileName: string; out ALine: Integer;
  out AResolved: string): Boolean;
begin
  AFileName := '';
  ALine := -1;
  AResolved := '';
  if AThread <> nil then
  begin
    AFileName := AThread.CurrentFile;
    ALine := Integer(AThread.CurrentLine) - 1;
  end;
  if (AFileName <> '') and (ALine >= 0) then
  begin
    AResolved := TAtlasIdeDebugSources.Resolve(AFileName);
  end;
  Result := AResolved <> '';
end;

/// <summary>Im Hintergrund-Thread: Treffer der Muster im Index; False, wenn der Server nicht antwortet.</summary>
function FetchCounts(ASession: TLspSession; const APatterns: TArray<string>; out ACounts: TAtlasStepCounts): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  ACounts := Default(TAtlasStepCounts);
  try
    mAnswer := ASession.RunCommand(TAtlasStepFilter.CountsCommand, TAtlasStepFilter.CountsArguments(APatterns),
      TAtlasIdeDebugStepFilter.CountsTimeoutMs);
    try
      Result := TAtlasStepFilter.ReadCounts(mAnswer, Length(APatterns), ACounts);
    finally
      mAnswer.Free;
    end;
  except
    // Server langsam oder weg: keine Treffer, das Fenster sagt es.
    on Exception do
      Result := False;
  end;
end;

{ TAtlasIdeDebugStepFilter.TTicker }

procedure TAtlasIdeDebugStepFilter.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugStepFilter.Check);
end;

{ TAtlasIdeDebugStepFilter.TListener }

procedure TAtlasIdeDebugStepFilter.TListener.DebugStarted;
begin
  FRun.Cancel;
  FTimer.Enabled := False;
  FCache.Clear;
  FSkips.Count := 0;
  FSkips.LastName := '';
  FSkips.LastReason := '';
  UpdateSession;
end;

procedure TAtlasIdeDebugStepFilter.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if AStop = TAtlasDebugStop.Paused then
  begin
    Stopped;
  end
  else
  begin
    // Exception oder Fehler: Der Benutzer soll sehen, wo es gekracht hat.
    FRun.Cancel;
  end;
end;

procedure TAtlasIdeDebugStepFilter.TListener.DebugEnded;
begin
  FRun.Cancel;
  FTimer.Enabled := False;
  // Quelltexte können sich bis zur nächsten Sitzung ändern.
  FCache.Clear;
end;

{ TAtlasIdeDebugStepFilter }

class procedure TAtlasIdeDebugStepFilter.Install(const ASession: TAtlasStepFilterSessionFunc;
  const AMessage: TProc<string>);
begin
  FSession := ASession;
  FMessage := AMessage;
  TAtlasIdeDebugStepFilterWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugStepFilterFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugStepFilterWindow.Prepare;
end;

class procedure TAtlasIdeDebugStepFilter.Uninstall;
begin
  Release;
  WaitCounts;
  TAtlasIdeDebugStepFilterWindow.Release;
  FSession := nil;
  FMessage := nil;
end;

class procedure TAtlasIdeDebugStepFilter.Start;
begin
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := IntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FCache = nil then
  begin
    FCache := TAtlasStepRoutineCache.Create;
  end;
  FRun.Cancel;
  FStep.Bypass := False;
  TAtlasIdeDebugTrace.AddHandler(TraceHandler,
    procedure(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin)
    begin
      Traced(AKind, AOrigin);
    end);
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
  UpdateSession;
end;

class procedure TAtlasIdeDebugStepFilter.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  TAtlasIdeDebugTrace.RemoveHandler(TraceHandler);
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FCache);
  FRun.Cancel;
  FStep.Bypass := False;
  UpdateSession;
end;

class function TAtlasIdeDebugStepFilter.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugStepFilter.SkippedCount: Integer;
begin
  Result := FSkips.Count;
end;

class function TAtlasIdeDebugStepFilter.Options: TAtlasStepFilterOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasStepFilterOptions.Create(mSettings.Enabled and mSettings.DebugStepFilters,
    mSettings.DebugStepFilterKinds, mSettings.DebugStepFilterPatterns);
end;

class procedure TAtlasIdeDebugStepFilter.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class procedure TAtlasIdeDebugStepFilter.Traced(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
var
  mDepth: Integer;
begin
  if (AKind = TAtlasTraceKind.TraceToSource) or FStep.Bypass then
  begin
    // Umschalt+F7 bzw. „Trotzdem hineinspringen“: einmal ohne Filter.
    FStep.Bypass := False;
    FRun.Cancel;
    Exit;
  end;
  if AOrigin = TAtlasTraceOrigin.Atlas then
  begin
    // Atlas springt nach „Bis zur Rückkehr“ selbst wieder hinein: derselbe Lauf, der nächste Halt gehört dazu.
    if FRun.Phase <> TAtlasStepFilterPhase.Idle then
    begin
      FStep.Stop := TAtlasIdeDebugSession.StopCount;
    end;
    Exit;
  end;
  FRun.Cancel;
  if not Options.Enabled then
  begin
    Exit;
  end;
  // Unter LLDB kann der Stapel noch fehlen; dann filtert Atlas diesen Schritt nicht.
  if TAtlasIdeDebugSession.StackDepth(TAtlasIdeDebugSession.StoppedThread, mDepth) <> TAtlasDebugStackRead.Ready then
  begin
    Exit;
  end;
  FRun.Start(mDepth);
  FStep.Stop := TAtlasIdeDebugSession.StopCount;
end;

class procedure TAtlasIdeDebugStepFilter.Stopped;
begin
  if FRun.Phase = TAtlasStepFilterPhase.Idle then
  begin
    Exit;
  end;
  // Nur der Halt direkt nach dem Schritt bzw. nach „Bis zur Rückkehr“ gehört dazu.
  if TAtlasIdeDebugSession.StopCount <> FStep.Stop + 1 then
  begin
    FRun.Cancel;
    Exit;
  end;
  FStep.Retries := 0;
  Check;
end;

class procedure TAtlasIdeDebugStepFilter.Check;
var
  mThread: IOTAThread;
  mDepth: Integer;
  mRoutine: TAtlasStepRoutine;
  mVerdict: TAtlasStepVerdict;
  mAction: TAtlasStepFilterAction;
begin
  FTimer.Enabled := False;
  if FRun.Phase = TAtlasStepFilterPhase.Idle then
  begin
    Exit;
  end;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if not ReadDepth(mThread, mDepth) then
  begin
    Exit;
  end;
  if FRun.Phase = TAtlasStepFilterPhase.Returning then
  begin
    mAction := FRun.AfterReturn(mDepth);
  end
  else
  begin
    mVerdict := Default(TAtlasStepVerdict);
    mRoutine := Default(TAtlasStepRoutine);
    if FRun.Entered(mDepth) then
    begin
      mVerdict := Judge(mThread, mRoutine);
    end;
    mAction := FRun.AfterStep(mDepth, mVerdict.Filtered);
    if mAction = TAtlasStepFilterAction.Return then
    begin
      Remember(mRoutine, mVerdict);
    end;
  end;
  ApplyAction(mAction);
end;

class function TAtlasIdeDebugStepFilter.Judge(const AThread: IOTAThread;
  out ARoutine: TAtlasStepRoutine): TAtlasStepVerdict;
var
  mFileName, mResolved: string;
  mLine: Integer;
begin
  Result := Default(TAtlasStepVerdict);
  ARoutine := Default(TAtlasStepRoutine);
  // Ohne Quelltext entscheidet „Nur eigener Code“ (#578), nicht der Schrittfilter. Ein Haltepunkt des Benutzers
  // in der neuen Routine geht vor.
  if not SourceAt(AThread, mFileName, mLine, mResolved) or HasBreakpoint(mFileName, mResolved, mLine) then
  begin
    Exit;
  end;
  if FCache.TryGet(mResolved, mLine, ARoutine) then
  begin
    Result := TAtlasStepFilter.Verdict(Options, ARoutine);
  end
  else if Lookup(mResolved, mLine, ARoutine) then
  begin
    FCache.Add(mResolved, mLine, ARoutine);
    Result := TAtlasStepFilter.Verdict(Options, ARoutine);
  end;
end;

class function TAtlasIdeDebugStepFilter.HasBreakpoint(const AFileName, AResolved: string; ALine: Integer): Boolean;
var
  mServices: IOTADebuggerServices;
  mBreakpoint: IOTASourceBreakpoint;
  mIndex: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and mBreakpoint.Enabled and (mBreakpoint.LineNumber = ALine + 1) and
      (SameText(mBreakpoint.FileName, AFileName) or SameText(mBreakpoint.FileName, AResolved)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeDebugStepFilter.Lookup(const AFileName: string; ALine: Integer;
  out ARoutine: TAtlasStepRoutine): Boolean;
var
  mSession: TLspSession;
  mBuffer: IOTAEditBuffer;
  mAnswer: TJSONValue;
begin
  Result := False;
  ARoutine := Default(TAtlasStepRoutine);
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Ohne Server und bei Fehlern bleibt der Halt stehen: wie F7 ohne Schrittfilter.
  if mSession = nil then
  begin
    Exit;
  end;
  try
    // Offene Dateien mit dem Stand im Editor; alle anderen liest der Server selbst.
    mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
    if mBuffer <> nil then
    begin
      mSession.Sync(AFileName, TAtlasEditorBuffer.Text(mBuffer));
    end;
    mAnswer := mSession.RunCommand(TAtlasStepFilter.Command,
      TAtlasStepFilter.Arguments(TLspSession.PathToUri(AFileName), ALine), TimeoutMs);
    try
      Result := TAtlasStepFilter.ReadRoutine(mAnswer, ARoutine);
    finally
      mAnswer.Free;
    end;
  except
    on ELspClientError do
      Result := False;
  end;
end;

class procedure TAtlasIdeDebugStepFilter.Remember(const ARoutine: TAtlasStepRoutine;
  const AVerdict: TAtlasStepVerdict);
begin
  Inc(FSkips.Count);
  FSkips.LastName := ARoutine.Name;
  FSkips.LastReason := TAtlasStepFilterTexts.VerdictText(AVerdict);
  UpdateSession;
end;

class procedure TAtlasIdeDebugStepFilter.StepIntoAnyway;
begin
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterNotStopped));
    Exit;
  end;
  // Ohne Ablauf (debug.stepFilters aus) ist es ein gewöhnliches F7.
  FStep.Bypass := Started;
  if not TAtlasIdeDebugTrace.StepInto then
  begin
    FStep.Bypass := False;
  end;
end;

class function TAtlasIdeDebugStepFilter.RoutineAtCursor(out ARoutine: TAtlasStepRoutine): Boolean;
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mFileName: string;
  mAnswer: TJSONValue;
begin
  Result := False;
  ARoutine := Default(TAtlasStepRoutine);
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterNoRoutine));
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mFileName := mView.Buffer.FileName;
  try
    mSession.Sync(mFileName, TAtlasEditorBuffer.Text(mView.Buffer));
    mAnswer := mSession.RunCommand(TAtlasStepFilter.Command,
      TAtlasStepFilter.Arguments(TLspSession.PathToUri(mFileName), mView.CursorPos.Line - 1), TimeoutMs);
    try
      Result := TAtlasStepFilter.ReadRoutine(mAnswer, ARoutine) and ARoutine.Found;
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterFailed, [E.Message]));
      Exit;
    end;
  end;
  if not Result then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterNoRoutine));
  end;
end;

class procedure TAtlasIdeDebugStepFilter.SaveOptions(AEnabled: Boolean; AKinds: TStepFilterKinds;
  const APatterns: TArray<string>);
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  mNext.DebugStepFilters := AEnabled;
  mNext.DebugStepFilterKinds := TStepFilterNames.KindsText(AKinds);
  mNext.DebugStepFilterPatterns := TStepFilterNames.PatternsText(APatterns);
  TAtlasIdeSettings.Update(mNext);
end;

class procedure TAtlasIdeDebugStepFilter.SkipAtCursor;
var
  mRoutine: TAtlasStepRoutine;
  mOptions: TAtlasStepFilterOptions;
  mVerdict: TAtlasStepVerdict;
  mStored: TAtlasPluginSettings;
begin
  if not RoutineAtCursor(mRoutine) then
  begin
    Exit;
  end;
  mStored := TAtlasIdeSettings.Stored;
  mOptions := TAtlasStepFilterOptions.Create(True, mStored.DebugStepFilterKinds, mStored.DebugStepFilterPatterns);
  mVerdict := TAtlasStepFilter.Verdict(mOptions, mRoutine);
  if mVerdict.Filtered then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterAlready,
      [mRoutine.Name, TAtlasStepFilterTexts.VerdictText(mVerdict)]));
  end
  else
  begin
    SaveOptions(mStored.DebugStepFilters, mOptions.Kinds, TStepFilterNames.WithPattern(mOptions.Patterns,
      mRoutine.Name));
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterAdded, [mRoutine.Name]));
  end;
  if not mStored.DebugStepFilters then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterOff));
  end;
end;

class procedure TAtlasIdeDebugStepFilter.UnskipAtCursor;
var
  mRoutine: TAtlasStepRoutine;
  mOptions: TAtlasStepFilterOptions;
  mVerdict: TAtlasStepVerdict;
  mStored: TAtlasPluginSettings;
  mRemoved: Boolean;
begin
  if not RoutineAtCursor(mRoutine) then
  begin
    Exit;
  end;
  mStored := TAtlasIdeSettings.Stored;
  mOptions := TAtlasStepFilterOptions.Create(True, mStored.DebugStepFilterKinds, mStored.DebugStepFilterPatterns);
  mRemoved := TStepFilterNames.IndexOfPattern(mOptions.Patterns, mRoutine.Name) >= 0;
  if mRemoved then
  begin
    mOptions.Patterns := TStepFilterNames.WithoutPattern(mOptions.Patterns, mRoutine.Name);
    SaveOptions(mStored.DebugStepFilters, mOptions.Kinds, mOptions.Patterns);
  end;
  // Weitere Muster oder Arten bleiben, wie sie sind: Der Benutzer erfährt, was noch filtert.
  mVerdict := TAtlasStepFilter.Verdict(mOptions, mRoutine);
  case mVerdict.Kind of
    TAtlasStepVerdictKind.Pattern:
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterStillByPattern, [mRoutine.Name, mVerdict.Pattern]));
    TAtlasStepVerdictKind.Kind:
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterStillByKind,
        [mRoutine.Name, TAtlasStepFilterTexts.VerdictText(mVerdict)]));
  else
    if mRemoved then
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterRemoved, [mRoutine.Name]));
    end
    else
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterNotSkipped, [mRoutine.Name]));
    end;
  end;
end;

class function TAtlasIdeDebugStepFilter.Frame: TAtlasDebugStepFilterFrame;
begin
  Result := TAtlasIdeDebugStepFilterWindow.ExistingFrame;
end;

class procedure TAtlasIdeDebugStepFilter.WireFrame(AFrame: TAtlasDebugStepFilterFrame);
begin
  AFrame.OnChange :=
    procedure(AEnabled: Boolean; AKinds: TStepFilterKinds; const APatterns: TArray<string>)
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          SaveOptions(AEnabled, AKinds, APatterns);
        end);
    end;
  AFrame.OnRefresh :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, Recount);
    end;
  FillFrame(AFrame);
  Recount;
end;

class procedure TAtlasIdeDebugStepFilter.FillFrame(AFrame: TAtlasDebugStepFilterFrame);
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  AFrame.SetOptions(mSettings.DebugStepFilters, TStepFilterNames.ParseKinds(mSettings.DebugStepFilterKinds),
    TStepFilterNames.ParsePatterns(mSettings.DebugStepFilterPatterns));
  AFrame.SetSession(Started, FSkips.Count, FSkips.LastName, FSkips.LastReason);
end;

class procedure TAtlasIdeDebugStepFilter.UpdateSession;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetSession(Started, FSkips.Count, FSkips.LastName, FSkips.LastReason);
  end;
end;

class procedure TAtlasIdeDebugStepFilter.ShowWindow;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := TAtlasIdeDebugStepFilterWindow.Show;
  if mFrame <> nil then
  begin
    FillFrame(mFrame);
  end;
end;

class procedure TAtlasIdeDebugStepFilter.ApplySettings;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  FillFrame(mFrame);
  // Neue Muster: Treffer neu zählen; die Arten zählt der Server ohnehin alle.
  if TAtlasIdeSettings.Current.DebugStepFilterPatterns <> FCounts.Patterns then
  begin
    Recount;
  end;
end;

class procedure TAtlasIdeDebugStepFilter.ThemeChanged;
begin
  TAtlasIdeDebugStepFilterWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugStepFilter.Recount;
var
  mFrame: TAtlasDebugStepFilterFrame;
  mSession: TLspSession;
  mPatterns: TArray<string>;
  mRequest: Integer;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if FCounts.Thread <> nil then
  begin
    // Läuft noch: danach mit den dann gültigen Mustern.
    FCounts.Again := True;
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  FCounts.Patterns := TAtlasIdeSettings.Current.DebugStepFilterPatterns;
  if mSession = nil then
  begin
    mFrame.SetNoCounts;
    Exit;
  end;
  mPatterns := TStepFilterNames.ParsePatterns(FCounts.Patterns);
  Inc(FCounts.Request);
  mRequest := FCounts.Request;
  mFrame.SetCounting;
  FCounts.Thread := TThread.CreateAnonymousThread(
    procedure
    var
      mCounts: TAtlasStepCounts;
      mOk: Boolean;
    begin
      mOk := FetchCounts(mSession, mPatterns, mCounts);
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          CountsDone(mRequest, mOk, mCounts);
        end);
    end);
  FCounts.Thread.FreeOnTerminate := False;
  FCounts.Thread.Start;
end;

class procedure TAtlasIdeDebugStepFilter.CountsDone(ARequest: Integer; AOk: Boolean; const ACounts: TAtlasStepCounts);
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  WaitCounts;
  mFrame := Frame;
  if (mFrame <> nil) and (ARequest = FCounts.Request) then
  begin
    if AOk then
    begin
      mFrame.SetCounts(ACounts);
    end
    else
    begin
      mFrame.SetNoCounts;
    end;
  end;
  if FCounts.Again then
  begin
    FCounts.Again := False;
    Recount;
  end;
end;

class procedure TAtlasIdeDebugStepFilter.WaitCounts;
begin
  // Der Faden endet spätestens nach CountsTimeoutMs; beim Entladen darf er nicht weiterlaufen.
  if FCounts.Thread = nil then
  begin
    Exit;
  end;
  FCounts.Thread.WaitFor;
  FreeAndNil(FCounts.Thread);
end;

end.
