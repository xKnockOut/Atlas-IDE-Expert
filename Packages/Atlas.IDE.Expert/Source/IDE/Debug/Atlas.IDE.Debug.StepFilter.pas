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
  private class var
    FSession: TAtlasStepFilterSessionFunc;
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FCache: TAtlasStepRoutineCache;
    FRun: TAtlasStepFilterRun;
    /// <summary>StopCount beim Auslösen des Schritts; der nächste Halt (+1) gehört dazu.</summary>
    FStepStop: Integer;
    FRetries: Integer;
    /// <summary>Der nächste Schritt aus Atlas geht ohne Filter hinein („Trotzdem hineinspringen“).</summary>
    FBypass: Boolean;
    // Übersprungen in dieser Debug-Sitzung.
    FSkipped: Integer;
    FLastName: string;
    FLastReason: string;
    // Treffer im Index.
    FCountsThread: TThread;
    FCountsAgain: Boolean;
    FCountsRequest: Integer;
    FCountedPatterns: string;
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
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.StepFilterWindow;

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
  FSkipped := 0;
  FLastName := '';
  FLastReason := '';
  UpdateSession;
end;

procedure TAtlasIdeDebugStepFilter.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if AStop = TAtlasDebugStop.Paused then
    Stopped
  else
    // Exception oder Fehler: Der Benutzer soll sehen, wo es gekracht hat.
    FRun.Cancel;
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
    FTicker := TTicker.Create;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := IntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FCache = nil then
    FCache := TAtlasStepRoutineCache.Create;
  FRun.Cancel;
  FBypass := False;
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
    TAtlasIdeDebugSession.RemoveListener(FListener);
  FListener := nil;
  TAtlasIdeDebugTrace.RemoveHandler(TraceHandler);
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(FCache);
  FRun.Cancel;
  FBypass := False;
  UpdateSession;
end;

class function TAtlasIdeDebugStepFilter.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugStepFilter.SkippedCount: Integer;
begin
  Result := FSkipped;
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
    FMessage(AText);
end;

class procedure TAtlasIdeDebugStepFilter.Traced(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
var
  mDepth: Integer;
begin
  if (AKind = TAtlasTraceKind.TraceToSource) or FBypass then
  begin
    // Umschalt+F7 bzw. „Trotzdem hineinspringen“: einmal ohne Filter.
    FBypass := False;
    FRun.Cancel;
    Exit;
  end;
  if AOrigin = TAtlasTraceOrigin.Atlas then
  begin
    // Atlas springt nach „Bis zur Rückkehr“ selbst wieder hinein: derselbe Lauf, der nächste Halt gehört dazu.
    if FRun.Phase <> TAtlasStepFilterPhase.Idle then
      FStepStop := TAtlasIdeDebugSession.StopCount;
    Exit;
  end;
  FRun.Cancel;
  if not Options.Enabled then
    Exit;
  // Unter LLDB kann der Stapel noch fehlen; dann filtert Atlas diesen Schritt nicht.
  if TAtlasIdeDebugSession.StackDepth(TAtlasIdeDebugSession.StoppedThread, mDepth) <> TAtlasDebugStackRead.Ready then
    Exit;
  FRun.Start(mDepth);
  FStepStop := TAtlasIdeDebugSession.StopCount;
end;

class procedure TAtlasIdeDebugStepFilter.Stopped;
begin
  if FRun.Phase = TAtlasStepFilterPhase.Idle then
    Exit;
  // Nur der Halt direkt nach dem Schritt bzw. nach „Bis zur Rückkehr“ gehört dazu.
  if TAtlasIdeDebugSession.StopCount <> FStepStop + 1 then
  begin
    FRun.Cancel;
    Exit;
  end;
  FRetries := 0;
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
    Exit;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  case TAtlasIdeDebugSession.StackDepth(mThread, mDepth) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FRetries);
        if FRetries <= StackRetries then
          FTimer.Enabled := True
        else
          FRun.Cancel;
        Exit;
      end;
    TAtlasDebugStackRead.None:
      begin
        FRun.Cancel;
        Exit;
      end;
  end;
  if FRun.Phase = TAtlasStepFilterPhase.Returning then
    mAction := FRun.AfterReturn(mDepth)
  else
  begin
    mVerdict := Default(TAtlasStepVerdict);
    mRoutine := Default(TAtlasStepRoutine);
    if FRun.Entered(mDepth) then
      mVerdict := Judge(mThread, mRoutine);
    mAction := FRun.AfterStep(mDepth, mVerdict.Filtered);
    if mAction = TAtlasStepFilterAction.Return then
      Remember(mRoutine, mVerdict);
  end;
  case mAction of
    TAtlasStepFilterAction.Return:
      begin
        FStepStop := TAtlasIdeDebugSession.StopCount;
        if not TAtlasIdeDebugSession.RunMode(ormRunUntilReturn) then
          FRun.Cancel;
      end;
    TAtlasStepFilterAction.StepInto:
      // Der Empfänger (Origin Atlas) setzt FStepStop.
      if not TAtlasIdeDebugTrace.StepInto then
        FRun.Cancel;
    TAtlasStepFilterAction.Keep: ;
  end;
end;

class function TAtlasIdeDebugStepFilter.Judge(const AThread: IOTAThread;
  out ARoutine: TAtlasStepRoutine): TAtlasStepVerdict;
var
  mFileName, mResolved: string;
  mLine: Integer;
begin
  Result := Default(TAtlasStepVerdict);
  ARoutine := Default(TAtlasStepRoutine);
  if AThread = nil then
    Exit;
  mFileName := AThread.CurrentFile;
  mLine := Integer(AThread.CurrentLine) - 1;
  // Ohne Quelltext entscheidet „Nur eigener Code“ (#578), nicht der Schrittfilter.
  if (mFileName = '') or (mLine < 0) then
    Exit;
  mResolved := TAtlasIdeDebugSources.Resolve(mFileName);
  if mResolved = '' then
    Exit;
  // Ein Haltepunkt des Benutzers in der neuen Routine geht vor.
  if HasBreakpoint(mFileName, mResolved, mLine) then
    Exit;
  if not FCache.TryGet(mResolved, mLine, ARoutine) then
  begin
    if not Lookup(mResolved, mLine, ARoutine) then
      Exit;
    FCache.Add(mResolved, mLine, ARoutine);
  end;
  Result := TAtlasStepFilter.Verdict(Options, ARoutine);
end;

class function TAtlasIdeDebugStepFilter.HasBreakpoint(const AFileName, AResolved: string; ALine: Integer): Boolean;
var
  mServices: IOTADebuggerServices;
  mBreakpoint: IOTASourceBreakpoint;
  mIndex: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mServices) then
    Exit;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and mBreakpoint.Enabled and (mBreakpoint.LineNumber = ALine + 1) and
      (SameText(mBreakpoint.FileName, AFileName) or SameText(mBreakpoint.FileName, AResolved)) then
      Exit(True);
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
    mSession := FSession();
  // Ohne Server und bei Fehlern bleibt der Halt stehen: wie F7 ohne Schrittfilter.
  if mSession = nil then
    Exit;
  try
    // Offene Dateien mit dem Stand im Editor; alle anderen liest der Server selbst.
    mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
    if mBuffer <> nil then
      mSession.Sync(AFileName, TAtlasEditorBuffer.Text(mBuffer));
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
  Inc(FSkipped);
  FLastName := ARoutine.Name;
  FLastReason := TAtlasDebugStepFilterFrame.VerdictText(AVerdict);
  UpdateSession;
end;

class procedure TAtlasIdeDebugStepFilter.StepIntoAnyway;
begin
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.StepFilterNotStopped));
    Exit;
  end;
  // Ohne Ablauf (debug.stepFilters aus) ist es ein gewöhnliches F7.
  FBypass := Started;
  if not TAtlasIdeDebugTrace.StepInto then
    FBypass := False;
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
    Report(TAtlasStrings.Text(TAtlasTextId.StepFilterNoRoutine));
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
    mSession := FSession();
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
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterFailed, [E.Message]));
      Exit;
    end;
  end;
  if not Result then
    Report(TAtlasStrings.Text(TAtlasTextId.StepFilterNoRoutine));
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
    Exit;
  mStored := TAtlasIdeSettings.Stored;
  mOptions := TAtlasStepFilterOptions.Create(True, mStored.DebugStepFilterKinds, mStored.DebugStepFilterPatterns);
  mVerdict := TAtlasStepFilter.Verdict(mOptions, mRoutine);
  if mVerdict.Filtered then
    Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterAlready,
      [mRoutine.Name, TAtlasDebugStepFilterFrame.VerdictText(mVerdict)]))
  else
  begin
    SaveOptions(mStored.DebugStepFilters, mOptions.Kinds, TStepFilterNames.WithPattern(mOptions.Patterns,
      mRoutine.Name));
    Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterAdded, [mRoutine.Name]));
  end;
  if not mStored.DebugStepFilters then
    Report(TAtlasStrings.Text(TAtlasTextId.StepFilterOff));
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
    Exit;
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
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterStillByPattern, [mRoutine.Name, mVerdict.Pattern]));
    TAtlasStepVerdictKind.Kind:
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterStillByKind,
        [mRoutine.Name, TAtlasDebugStepFilterFrame.VerdictText(mVerdict)]));
  else
    if mRemoved then
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterRemoved, [mRoutine.Name]))
    else
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepFilterNotSkipped, [mRoutine.Name]));
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
  AFrame.SetSession(Started, FSkipped, FLastName, FLastReason);
end;

class procedure TAtlasIdeDebugStepFilter.UpdateSession;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
    mFrame.SetSession(Started, FSkipped, FLastName, FLastReason);
end;

class procedure TAtlasIdeDebugStepFilter.ShowWindow;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := TAtlasIdeDebugStepFilterWindow.Show;
  if mFrame <> nil then
    FillFrame(mFrame);
end;

class procedure TAtlasIdeDebugStepFilter.ApplySettings;
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  mFrame := Frame;
  if mFrame = nil then
    Exit;
  FillFrame(mFrame);
  // Neue Muster: Treffer neu zählen; die Arten zählt der Server ohnehin alle.
  if TAtlasIdeSettings.Current.DebugStepFilterPatterns <> FCountedPatterns then
    Recount;
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
    Exit;
  if FCountsThread <> nil then
  begin
    // Läuft noch: danach mit den dann gültigen Mustern.
    FCountsAgain := True;
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
    mSession := FSession();
  FCountedPatterns := TAtlasIdeSettings.Current.DebugStepFilterPatterns;
  if mSession = nil then
  begin
    mFrame.SetNoCounts;
    Exit;
  end;
  mPatterns := TStepFilterNames.ParsePatterns(FCountedPatterns);
  Inc(FCountsRequest);
  mRequest := FCountsRequest;
  mFrame.SetCounting;
  FCountsThread := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TJSONValue;
      mCounts: TAtlasStepCounts;
      mOk: Boolean;
    begin
      mOk := False;
      mCounts := Default(TAtlasStepCounts);
      try
        mAnswer := mSession.RunCommand(TAtlasStepFilter.CountsCommand, TAtlasStepFilter.CountsArguments(mPatterns),
          CountsTimeoutMs);
        try
          mOk := TAtlasStepFilter.ReadCounts(mAnswer, Length(mPatterns), mCounts);
        finally
          mAnswer.Free;
        end;
      except
        // Server langsam oder weg: keine Treffer, das Fenster sagt es.
        on Exception do
          mOk := False;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Debugger,
        procedure
        begin
          CountsDone(mRequest, mOk, mCounts);
        end);
    end);
  FCountsThread.FreeOnTerminate := False;
  FCountsThread.Start;
end;

class procedure TAtlasIdeDebugStepFilter.CountsDone(ARequest: Integer; AOk: Boolean; const ACounts: TAtlasStepCounts);
var
  mFrame: TAtlasDebugStepFilterFrame;
begin
  WaitCounts;
  mFrame := Frame;
  if (mFrame <> nil) and (ARequest = FCountsRequest) then
    if AOk then
      mFrame.SetCounts(ACounts)
    else
      mFrame.SetNoCounts;
  if FCountsAgain then
  begin
    FCountsAgain := False;
    Recount;
  end;
end;

class procedure TAtlasIdeDebugStepFilter.WaitCounts;
begin
  // Der Faden endet spätestens nach CountsTimeoutMs; beim Entladen darf er nicht weiterlaufen.
  if FCountsThread = nil then
    Exit;
  FCountsThread.WaitFor;
  FreeAndNil(FCountsThread);
end;

end.
