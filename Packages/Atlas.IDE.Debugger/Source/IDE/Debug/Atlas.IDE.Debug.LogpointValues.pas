unit Atlas.IDE.Debug.LogpointValues;

// Werteverlauf aus Logpunkten (#2552) in der IDE:
//   - Das Ereignisprotokoll (TAtlasIdeDebugEventLog.OnLogpoint) meldet jede
//     zusammengeführte Logpunkt-Zeile. Atlas trennt Präfix und Ort ab, sucht
//     zum Ort den Logpunkt mit „Zahl aufzeichnen“
//     (TAtlasIdeLogpoints.RecordedInput) und nimmt den Wert des einzigen
//     Platzhalters als Treffer auf (Text-Werte als Lücke).
//   - Eine Reihe je Logpunkt, höchstens debug.logpoints.recordLimit Treffer
//     (die ältesten fallen heraus); der Start einer Sitzung leert alle Reihen,
//     nach dem Ende bleiben sie bis zur nächsten Sitzung stehen.
//   - Fenster „Atlas: Logpunkt-Verlauf“ (Befehl Atlas.DebugLogpointValues):
//     neu gezeichnet höchstens alle cRefreshMs, damit schnelle Logpunkte die
//     IDE nicht ausbremsen. Klick auf einen Treffer springt zur Zeile im
//     Ereignisprotokoll; „CSV kopieren“ legt die Reihe in die Zwischenablage.
// Ohne debug.logpoints.recordValues meldet sich Atlas nicht an. Gesichert über
// TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.EventLog,
  Atlas.Core.Debug.ValueSeries,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.LogpointValuesFrame;

type
  TAtlasIdeLogpointValues = class
  public const
    /// <summary>Kürzester Abstand zwischen zwei Neuzeichnungen des Fensters.</summary>
    cRefreshMs = 500;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
    end;
    /// <summary>Besitzer des Zeitgebers (OnTimer braucht eine Methode eines Objekts).</summary>
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FSet: TAtlasValueSeriesSet;
    FMessage: TProc<string>;
    class procedure RefreshWindow; static;
    class procedure WireFrame(AFrame: TAtlasDebugLogpointValuesFrame); static;
    class procedure CopyCsv(const APlace, AThread: string); static;
    class procedure JumpTo(const APoint: TAtlasValuePoint); static;
    class procedure SessionStarted; static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Eine Zeile des Ereignisprotokolls aufnehmen, wenn ihr Logpunkt aufzeichnet.</summary>
    class procedure Collect(const AEntry: TAtlasEventEntry); static;
    /// <summary>Fenster „Atlas: Logpunkt-Verlauf“ zeigen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Reihen der Sitzung (für Tests und das Fenster); nil vor Start.</summary>
    class function Series: TAtlasValueSeriesSet; static;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.Core.Debug.Logpoint,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EventLog,
  Atlas.IDE.Debug.Logpoints,
  Atlas.IDE.Debug.LogpointValuesWindow,
  Atlas.UI.Debug.LogpointDialog,
  Atlas.UI.Debug.Logpoints.Strings;

{ TAtlasIdeLogpointValues.TListener }

procedure TAtlasIdeLogpointValues.TListener.DebugStarted;
begin
  TAtlasIdeLogpointValues.SessionStarted;
end;

{ TAtlasIdeLogpointValues.TTicker }

procedure TAtlasIdeLogpointValues.TTicker.Tick(Sender: TObject);
begin
  TAtlasIdeLogpointValues.FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeLogpointValues.RefreshWindow);
end;

{ TAtlasIdeLogpointValues }

class procedure TAtlasIdeLogpointValues.Collect(const AEntry: TAtlasEventEntry);
var
  mMessage, mPlace: string;
  mInput: TAtlasLogpointInput;
  mPoint: TAtlasValuePoint;
  mName: string;
begin
  if (FSet = nil) or not TAtlasLogpointValue.Split(AEntry.Text, TAtlasIdeSettings.Current.DebugLogpointPrefix,
    mMessage, mPlace) then
  begin
    Exit;
  end;
  if not TAtlasIdeLogpoints.RecordedInput(mPlace, mInput) then
  begin
    Exit;
  end;
  if not TAtlasValuePoint.TryOf(TAtlasLogpointTemplate.Parse(mInput.Text), mMessage, AEntry.ElapsedMs,
    AEntry.Thread, AEntry.Text, mPoint) then
  begin
    Exit;
  end;
  mName := mInput.SeriesName;
  if mName = '' then
  begin
    mName := mInput.Text;
  end;
  FSet.Ensure(mPlace, mName, TAtlasIdeSettings.Current.DebugLogpointsRecordLimit).Add(mPoint);
  // Neu zeichnen gebündelt: Der Zeitgeber läuft nur, solange etwas aussteht.
  if (FTimer <> nil) and not FTimer.Enabled then
  begin
    FTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeLogpointValues.RefreshWindow;
var
  mFrame: TAtlasDebugLogpointValuesFrame;
begin
  mFrame := TAtlasIdeLogpointValuesWindow.ExistingFrame;
  if (mFrame <> nil) and TAtlasIdeLogpointValuesWindow.Visible then
  begin
    mFrame.Refresh;
  end;
end;

class procedure TAtlasIdeLogpointValues.WireFrame(AFrame: TAtlasDebugLogpointValuesFrame);
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.OnCopyCsv :=
    procedure(const APlace, AThread: string)
    begin
      CopyCsv(APlace, AThread);
    end;
  AFrame.OnPoint :=
    procedure(const APoint: TAtlasValuePoint)
    begin
      JumpTo(APoint);
    end;
  AFrame.SetSeries(FSet);
end;

class procedure TAtlasIdeLogpointValues.CopyCsv(const APlace, AThread: string);
var
  mSeries: TAtlasValueSeries;
begin
  if FSet = nil then
  begin
    Exit;
  end;
  mSeries := FSet.Find(APlace);
  if (mSeries = nil) or (mSeries.Count = 0) then
  begin
    Exit;
  end;
  Clipboard.AsText := mSeries.ToCsv(AThread);
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesCopied));
  end;
end;

class procedure TAtlasIdeLogpointValues.JumpTo(const APoint: TAtlasValuePoint);
begin
  TAtlasIdeDebugEventLog.ShowEntry(APoint.AtMs, APoint.Line);
end;

class procedure TAtlasIdeLogpointValues.SessionStarted;
begin
  if FSet <> nil then
  begin
    FSet.Clear;
  end;
  RefreshWindow;
end;

class procedure TAtlasIdeLogpointValues.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FSet = nil then
  begin
    FSet := TAtlasValueSeriesSet.Create;
  end;
  if FTimer = nil then
  begin
    FTicker := TTicker.Create;
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cRefreshMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  TAtlasIdeLogpointValuesWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugLogpointValuesFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeLogpointValuesWindow.Prepare;
  TAtlasIdeDebugEventLog.OnLogpoint :=
    procedure(AEntry: TAtlasEventEntry)
    begin
      // Läuft im Zeitgeber des Ereignisprotokolls, der schon über TAtlasGuard gesichert ist.
      Collect(AEntry);
    end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
end;

class procedure TAtlasIdeLogpointValues.Release;
var
  mFrame: TAtlasDebugLogpointValuesFrame;
begin
  TAtlasIdeDebugEventLog.OnLogpoint := nil;
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  // Zuerst der Zeitgeber: Nach dem Abmelden darf nichts mehr neu zeichnen.
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  // Der Frame kann das Abmelden überleben (angedocktes Fenster): Ereignisse und Reihen lösen.
  mFrame := TAtlasIdeLogpointValuesWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnCopyCsv := nil;
    mFrame.OnPoint := nil;
    mFrame.SetSeries(nil);
  end;
  TAtlasIdeLogpointValuesWindow.OnFrame := nil;
  TAtlasIdeLogpointValuesWindow.Release;
  FreeAndNil(FSet);
  FMessage := nil;
end;

class function TAtlasIdeLogpointValues.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeLogpointValues.ApplySettings;
var
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DebugLogpointsRecordValues then
  begin
    TAtlasIdeLogpointValuesWindow.Hide;
  end;
  if FSet = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FSet.Count - 1 do
  begin
    FSet[mIndex].SetLimit(TAtlasIdeSettings.Current.DebugLogpointsRecordLimit);
  end;
  RefreshWindow;
end;

class procedure TAtlasIdeLogpointValues.ThemeChanged;
begin
  TAtlasIdeLogpointValuesWindow.ApplyTheme;
end;

class procedure TAtlasIdeLogpointValues.ShowWindow;
begin
  if not Started then
  begin
    Exit;
  end;
  WireFrame(TAtlasIdeLogpointValuesWindow.Show);
end;

class function TAtlasIdeLogpointValues.Series: TAtlasValueSeriesSet;
begin
  Result := FSet;
end;

end.
