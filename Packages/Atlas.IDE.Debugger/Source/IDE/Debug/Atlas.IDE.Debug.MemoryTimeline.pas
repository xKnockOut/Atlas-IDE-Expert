unit Atlas.IDE.Debug.MemoryTimeline;

// Speicherverlauf beim Debuggen (#858) in der IDE:
//   - Zuhörer der Debug-Sitzung (TAtlasIdeDebugSession): Der Start einer
//     Sitzung leert den Verlauf und öffnet den Prozess
//     (TAtlasIdeMemoryCounters), das Ende schließt ihn; der Verlauf bleibt bis
//     zur nächsten Sitzung stehen.
//   - Ein Zeitgeber im Hauptthread misst alle debug.memoryTimeline.intervalMs
//     (Vorgabe 1 s) privaten Speicher, Arbeitssatz, Handles, GDI- und
//     USER-Objekte. Jede Messung kostet wenige Mikrosekunden; ein eigener
//     Thread lohnt nicht und bräuchte für das Fenster ohnehin den Hauptthread.
//   - Jeder Halt setzt eine Marke (Exception rot, sonst gedämpft) und misst
//     sofort, damit der Wert am Haltepunkt im Verlauf steht.
//   - Fenster „Atlas: Speicher“ (Befehl Atlas.DebugMemory): Linie je Reihe,
//     Bereich wählen zeigt den Zuwachs, „Marke setzen“, „CSV kopieren“,
//     „Leeren“.
// Ohne debug.memoryTimeline misst Atlas nichts und meldet keinen Zuhörer an.
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.MemoryTimeline,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.MemoryCounters,
  Atlas.UI.Debug.MemoryFrame;

type
  TAtlasIdeDebugMemoryTimeline = class
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
    /// <summary>Besitzer des Zeitgebers (OnTimer braucht eine Methode eines Objekts).</summary>
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
    TSessionState = record
      /// <summary>GetTickCount64 beim Start der Sitzung.</summary>
      StartTicks: UInt64;
      /// <summary>Nummer der nächsten eigenen Marke.</summary>
      NextMark: Integer;
      /// <summary>„nicht lesbar“ schon gemeldet (einmal je Sitzung).</summary>
      Reported: Boolean;
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FTimeline: TAtlasMemoryTimeline;
    FCounters: TAtlasIdeMemoryCounters;
    FSession: TSessionState;
    FMessage: TProc<string>;
    class function NowMs: Int64; static;
    /// <summary>Prozess der Sitzung öffnen, falls noch nicht offen; False, wenn es (noch) nicht geht.</summary>
    class function EnsureOpen: Boolean; static;
    /// <summary>Eine Messung aufnehmen und das Fenster auffrischen.</summary>
    class procedure Sample; static;
    class procedure AddMark(AKind: TAtlasMemoryMarkKind; const AName: string); static;
    class procedure RefreshWindow; static;
    class procedure WireFrame(AFrame: TAtlasDebugMemoryFrame); static;
    class procedure CopyCsv; static;
    class procedure ClearTimeline; static;
    class procedure SessionStarted; static;
    class procedure SessionStopped(AStop: TAtlasDebugStop); static;
    class procedure SessionEnded; static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster „Atlas: Speicher“ zeigen; ohne debug.memoryTimeline nur ein Hinweis.</summary>
    class procedure ShowWindow; static;
    /// <summary>Eigene Marke „Marke n“ jetzt (Knopf und Befehl).</summary>
    class procedure MarkNow; static;
    /// <summary>Verlauf der Sitzung (für Tests und das Fenster); nil vor Start.</summary>
    class function Timeline: TAtlasMemoryTimeline; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.MemoryWindow,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDebugMemoryTimeline.TListener }

procedure TAtlasIdeDebugMemoryTimeline.TListener.DebugStarted;
begin
  TAtlasIdeDebugMemoryTimeline.SessionStarted;
end;

procedure TAtlasIdeDebugMemoryTimeline.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasIdeDebugMemoryTimeline.SessionStopped(AStop);
end;

procedure TAtlasIdeDebugMemoryTimeline.TListener.DebugEnded;
begin
  TAtlasIdeDebugMemoryTimeline.SessionEnded;
end;

{ TAtlasIdeDebugMemoryTimeline.TTicker }

procedure TAtlasIdeDebugMemoryTimeline.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugMemoryTimeline.Sample);
end;

{ TAtlasIdeDebugMemoryTimeline }

class procedure TAtlasIdeDebugMemoryTimeline.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FTimeline = nil then
  begin
    FTimeline := TAtlasMemoryTimeline.Create;
  end;
  if FCounters = nil then
  begin
    FCounters := TAtlasIdeMemoryCounters.Create;
  end;
  if FTimer = nil then
  begin
    FTicker := TTicker.Create;
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.OnTimer := FTicker.Tick;
  end;
  FTimer.Interval := TAtlasIdeSettings.Current.DebugMemoryTimelineIntervalMs;
  TAtlasIdeDebugMemoryWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugMemoryFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugMemoryWindow.Prepare;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  // Eingeschaltet mitten in einer Sitzung: ab jetzt messen.
  if TAtlasIdeDebugSession.Active then
  begin
    SessionStarted;
  end;
end;

class procedure TAtlasIdeDebugMemoryTimeline.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  // Zuerst der Zeitgeber: Nach dem Abmelden darf keine Messung mehr kommen.
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  TAtlasIdeDebugMemoryWindow.Release;
  FreeAndNil(FCounters);
  FreeAndNil(FTimeline);
  FSession := Default(TSessionState);
  FMessage := nil;
end;

class function TAtlasIdeDebugMemoryTimeline.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class function TAtlasIdeDebugMemoryTimeline.Timeline: TAtlasMemoryTimeline;
begin
  Result := FTimeline;
end;

class procedure TAtlasIdeDebugMemoryTimeline.ApplySettings;
begin
  if FTimer <> nil then
  begin
    FTimer.Interval := TAtlasIdeSettings.Current.DebugMemoryTimelineIntervalMs;
  end;
  if not TAtlasIdeSettings.Current.DebugMemoryTimeline then
  begin
    TAtlasIdeDebugMemoryWindow.Hide;
  end;
end;

class procedure TAtlasIdeDebugMemoryTimeline.ThemeChanged;
begin
  TAtlasIdeDebugMemoryWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugMemoryTimeline.ShowWindow;
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  if not Started then
  begin
    if Assigned(FMessage) then
    begin
      FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.MemoryOff));
    end;
    Exit;
  end;
  mFrame := TAtlasIdeDebugMemoryWindow.Show;
  WireFrame(mFrame);
end;

class procedure TAtlasIdeDebugMemoryTimeline.WireFrame(AFrame: TAtlasDebugMemoryFrame);
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.OnMark := MarkNow;
  AFrame.OnCopyCsv := CopyCsv;
  AFrame.OnClear := ClearTimeline;
  AFrame.SetTimeline(FTimeline);
end;

class procedure TAtlasIdeDebugMemoryTimeline.RefreshWindow;
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  mFrame := TAtlasIdeDebugMemoryWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.Refresh;
  end;
end;

class function TAtlasIdeDebugMemoryTimeline.NowMs: Int64;
begin
  Result := Int64(GetTickCount64 - FSession.StartTicks);
end;

class function TAtlasIdeDebugMemoryTimeline.EnsureOpen: Boolean;
var
  mProcess: IOTAProcess;
begin
  Result := FCounters.IsOpen;
  if Result then
  begin
    Exit;
  end;
  mProcess := TAtlasIdeDebugSession.Process;
  if (mProcess = nil) or (mProcess.ProcessId = 0) then
  begin
    Exit;
  end;
  Result := FCounters.Open(mProcess.ProcessId);
  if (not Result) and (not FSession.Reported) and Assigned(FMessage) then
  begin
    FSession.Reported := True;
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MemoryNoAccess,
      [mProcess.ProcessId, SysErrorMessage(FCounters.LastError)]));
  end;
end;

class procedure TAtlasIdeDebugMemoryTimeline.Sample;
var
  mSample: TAtlasMemorySample;
begin
  if (FTimeline = nil) or not EnsureOpen then
  begin
    Exit;
  end;
  mSample := Default(TAtlasMemorySample);
  if not FCounters.Read(mSample.Values) then
  begin
    Exit;
  end;
  mSample.AtMs := NowMs;
  FTimeline.AddSample(mSample);
  RefreshWindow;
end;

class procedure TAtlasIdeDebugMemoryTimeline.AddMark(AKind: TAtlasMemoryMarkKind; const AName: string);
begin
  if FTimeline = nil then
  begin
    Exit;
  end;
  FTimeline.AddMark(NowMs, AKind, AName);
  // Gleich messen: Die Marke steht dann bei einem Wert, auch während das Programm angehalten ist.
  Sample;
end;

class procedure TAtlasIdeDebugMemoryTimeline.MarkNow;
begin
  if (FTimeline = nil) or (FTimeline.Count = 0) then
  begin
    Exit;
  end;
  Inc(FSession.NextMark);
  AddMark(TAtlasMemoryMarkKind.Custom, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MemoryMarkName,
    [FSession.NextMark]));
end;

class procedure TAtlasIdeDebugMemoryTimeline.CopyCsv;
begin
  if (FTimeline = nil) or (FTimeline.Count = 0) then
  begin
    Exit;
  end;
  Clipboard.AsText := FTimeline.ToCsv;
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.MemoryCopied, [FTimeline.Count]));
  end;
end;

class procedure TAtlasIdeDebugMemoryTimeline.ClearTimeline;
begin
  if FTimeline = nil then
  begin
    Exit;
  end;
  FTimeline.Clear;
  FSession.NextMark := 0;
  RefreshWindow;
end;

class procedure TAtlasIdeDebugMemoryTimeline.SessionStarted;
begin
  FCounters.Close;
  FTimeline.Clear;
  FSession := Default(TSessionState);
  FSession.StartTicks := GetTickCount64;
  FTimer.Interval := TAtlasIdeSettings.Current.DebugMemoryTimelineIntervalMs;
  FTimer.Enabled := True;
  Sample;
  RefreshWindow;
end;

class procedure TAtlasIdeDebugMemoryTimeline.SessionStopped(AStop: TAtlasDebugStop);
begin
  if AStop = TAtlasDebugStop.Paused then
  begin
    AddMark(TAtlasMemoryMarkKind.Stop, TAtlasDebugStrings.Text(TAtlasDebugTextId.MemoryMarkStop));
  end
  else
  begin
    AddMark(TAtlasMemoryMarkKind.Exception, TAtlasDebugStrings.Text(TAtlasDebugTextId.MemoryMarkException));
  end;
end;

class procedure TAtlasIdeDebugMemoryTimeline.SessionEnded;
begin
  FTimer.Enabled := False;
  FCounters.Close;
  RefreshWindow;
end;

end.
