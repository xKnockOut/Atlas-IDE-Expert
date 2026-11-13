unit Atlas.IDE.Tests.Series;

// Tests mehrfach oder in zufälliger Reihenfolge ausführen (#1782) in der IDE:
// - Befehle „Test am Cursor N-mal ausführen …“ (Anzahl vorbelegt mit
//   tests.repeat.count), „Tests der Klasse in zufälliger Reihenfolge
//   ausführen“, „Mit dieser Reihenfolge erneut ausführen“ und „Testserie
//   abbrechen“ (Kontextmenü einer Testunit, Palette); dieselben Einträge im
//   Kontextmenü des Fensters „Atlas-Tests“ (Atlas.IDE.Tests.Explorer).
// - Ablauf: Testprojekt wie beim Ausführen (ResolveProject, fragt bei
//   mehreren einmal), dann die Starts der Serie (Atlas.Core.Tests.Series)
//   nacheinander als Läufe im Hintergrund (TAtlasIdeTests.RunQuiet): Der
//   erste baut wie mit „Vor den Tests bauen“, die übrigen nehmen die
//   vorhandene EXE. Jeder Lauf meldet sich wie sonst (Probleme, Code Lens,
//   Fenster, Verlauf über OnReported); sein Ende kommt über SendNextEndTo der
//   Ausgabe.
// - Abbrechen: TAtlasIdeTestStop, den der Prozessläufer der Composition
//   abfragt; der laufende Prozess endet sofort.
// - Ergebnis: Zeilen in der Meldungsansicht (Gruppe Atlas) mit den Zahlen,
//   bei zufälliger Reihenfolge mit Startwert und Reihenfolge, je Test mit
//   Fehlschlag Anzahl und letzte Meldung; an der Marke der Serie (Haken
//   Series der Lens) bis zum nächsten Lauf.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Series,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Output;

type
  /// <summary>Abbruchwunsch einer Serie; gesetzt im Hauptthread, gelesen vom Prozessläufer im Thread des Laufs.
  /// </summary>
  TAtlasIdeTestStop = class(TInterfacedObject)
  private
    FRequested: Boolean;
  public
    property Requested: Boolean read FRequested write FRequested;
  end;

  TAtlasIdeTestSeries = class
  private type
    /// <summary>Lebt, solange die Serie lebt; die Wahl des Testprojekts in der Palette prüft es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private
    FAlive: TAlive;
    FAliveRef: IInterface;
    FTests: TAtlasIdeTests;
    FOutput: TAtlasIdeTestsOutput;
    FStop: TAtlasIdeTestStop;
    FStopRef: IInterface;
    FSeries: TAtlasTestSeries;
    FRunning: Boolean;
    /// <summary>Ergebnis der letzten Serie gilt an der Marke, solange sich der Stand der Läufe nicht geändert hat.
    /// </summary>
    FShown: Boolean;
    FShownVersion: Integer;
    /// <summary>Letzte Serie in zufälliger Reihenfolge, für „Mit dieser Reihenfolge erneut“.</summary>
    FLastShuffle: TAtlasTestSeries;
    FHasShuffle: Boolean;
    procedure Launch(const AFileName: string; const ASeries: TAtlasTestSeries);
    procedure Step;
    procedure Ended(const AEnd: TAtlasTestsQuietEnd);
    procedure Finish;
    procedure Report;
    /// <summary>Datei, Test am Cursor und gelesene Unit; False mit Meldung.</summary>
    function AtCursor(out AFileName: string; out ASelection: TAtlasTestSelection; out AUnit: TDUnitXUnit): Boolean;
  public
    /// <summary>ATests, AOutput und AStop gehören dem Aufrufer; ATests und AOutput leben länger.</summary>
    constructor Create(ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput; AStop: TAtlasIdeTestStop);
    destructor Destroy; override;
    /// <summary>Befehl: Test (Fixture, Fall) am Cursor N-mal ausführen; fragt nach N.</summary>
    procedure RepeatAtCursor;
    /// <summary>Befehl: Tests der Fixture am Cursor einzeln in zufälliger Reihenfolge.</summary>
    procedure ShuffleAtCursor;
    /// <summary>Befehl: letzte Serie in zufälliger Reihenfolge mit demselben Startwert wiederholen.</summary>
    procedure ShuffleAgain;
    /// <summary>Befehl: laufende Serie abbrechen.</summary>
    procedure Cancel;
    /// <summary>ANames (Testunit AFileName) N-mal ausführen; fragt nach N (Fenster „Atlas-Tests“).</summary>
    procedure RepeatNames(const AFileName: string; const ASubject: TAtlasTestSeriesSubject;
      const ANames: TArray<string>);
    /// <summary>ANames (je ein Test bzw. Fall) einzeln in zufälliger Reihenfolge ausführen.</summary>
    procedure ShuffleNames(const AFileName: string; const ASubject: TAtlasTestSeriesSubject;
      const ANames: TArray<string>);
    /// <summary>Haken Series der Lens: Ergebnis der Serie an der Marke ASelection.</summary>
    function MarkOf(const ASelection: TAtlasTestSelection; out AMark: TAtlasTestSeriesMark): Boolean;
    function Running: Boolean;
    function CanShuffleAgain: Boolean;
  end;

implementation

uses
  System.Math,
  ToolsAPI,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.UI.Tests.Strings,
  Atlas.UI.Tests.SeriesMenu;

const
  /// <summary>Höchstens so viele Namen in der Zeile „Reihenfolge: …“.</summary>
  cOrderNames = 40;

function SubjectOf(const ASelection: TAtlasTestSelection): TAtlasTestSeriesSubject;
begin
  Result := TAtlasTestSeriesSubject.Make(ASelection.UnitName, ASelection.Fixture, ASelection.Method,
    ASelection.CaseName);
end;

/// <summary>Kurzer Name für die Reihenfolge: ohne Unit und Fixture des Gegenstands.</summary>
function ShortName(const AName: string; const ASubject: TAtlasTestSeriesSubject): string;
var
  mPrefix: string;
begin
  Result := AName;
  mPrefix := ASubject.UnitName + '.' + ASubject.Fixture + '.';
  if (ASubject.Fixture <> '') and SameText(Copy(AName, 1, Length(mPrefix)), mPrefix) then
  begin
    Result := Copy(AName, Length(mPrefix) + 1, MaxInt);
  end;
end;

function OrderText(const ASeries: TAtlasTestSeries): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to Min(High(ASeries.Steps), cOrderNames - 1) do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ShortName(ASeries.Steps[mIndex][0], ASeries.Subject);
  end;
  if Length(ASeries.Steps) > cOrderNames then
  begin
    Result := Result + ', …';
  end;
end;

function SeriesTexts: TAtlasTestSeriesTexts;
begin
  Result := Default(TAtlasTestSeriesTexts);
  Result.Repeated := TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesLensRepeated);
  Result.Shuffled := TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesLensShuffled);
  Result.Running := TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesLensRunning);
end;

{ TAtlasIdeTestSeries }

constructor TAtlasIdeTestSeries.Create(ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput;
  AStop: TAtlasIdeTestStop);
begin
  inherited Create;
  FTests := ATests;
  FOutput := AOutput;
  FStop := AStop;
  FStopRef := AStop;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
end;

destructor TAtlasIdeTestSeries.Destroy;
begin
  FAlive.Alive := False;
  if FRunning then
  begin
    // Das Ende des laufenden Laufs darf dieses Objekt nicht mehr erreichen; der Prozess endet mit dem Läufer.
    FOutput.SendNextEndTo(nil);
    FStop.Requested := True;
  end;
  FStopRef := nil;
  FAliveRef := nil;
  inherited Destroy;
end;

function TAtlasIdeTestSeries.Running: Boolean;
begin
  Result := FRunning;
end;

function TAtlasIdeTestSeries.CanShuffleAgain: Boolean;
begin
  Result := FHasShuffle;
end;

function TAtlasIdeTestSeries.AtCursor(out AFileName: string; out ASelection: TAtlasTestSelection;
  out AUnit: TDUnitXUnit): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  AFileName := '';
  ASelection := Default(TAtlasTestSelection);
  AUnit := Default(TDUnitXUnit);
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(ExtractFileExt(mView.Buffer.FileName), '.pas');
  if Result then
  begin
    AFileName := mView.Buffer.FileName;
    AUnit := TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer)));
    Result := TAtlasTestDebug.SelectAt(AUnit, mView.CursorPos.Line - 1, ASelection) and
      (Length(ASelection.Names) > 0);
  end;
  if not Result then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoTestAtCursor));
  end;
end;

procedure TAtlasIdeTestSeries.RepeatAtCursor;
var
  mFileName: string;
  mSelection: TAtlasTestSelection;
  mUnit: TDUnitXUnit;
begin
  if AtCursor(mFileName, mSelection, mUnit) then
  begin
    RepeatNames(mFileName, SubjectOf(mSelection), mSelection.Names);
  end;
end;

procedure TAtlasIdeTestSeries.ShuffleAtCursor;
var
  mFileName: string;
  mSelection: TAtlasTestSelection;
  mUnit: TDUnitXUnit;
  mFixture, mTest: Integer;
begin
  if not AtCursor(mFileName, mSelection, mUnit) then
  begin
    Exit;
  end;
  // Immer die ganze Fixture am Cursor, auch wenn er in einem ihrer Tests steht.
  if mUnit.Find(mSelection.Fixture, '', mFixture, mTest) then
  begin
    ShuffleNames(mFileName, TAtlasTestSeriesSubject.Make(mSelection.UnitName, mSelection.Fixture, '', ''),
      TAtlasTestShuffle.SingleNames(mUnit, mFixture, -1, -1));
  end;
end;

procedure TAtlasIdeTestSeries.ShuffleAgain;
begin
  if not FHasShuffle then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesNoOrder));
    Exit;
  end;
  Launch(FLastShuffle.Project, TAtlasTestSeries.Shuffling(FLastShuffle.Subject, FLastShuffle.Names,
    FLastShuffle.Seed));
end;

procedure TAtlasIdeTestSeries.Cancel;
begin
  if FRunning then
  begin
    FStop.Requested := True;
  end
  else
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.SeriesNotRunning));
  end;
end;

procedure TAtlasIdeTestSeries.RepeatNames(const AFileName: string; const ASubject: TAtlasTestSeriesSubject;
  const ANames: TArray<string>);
var
  mText: string;
  mCount: Integer;
begin
  if Length(ANames) = 0 then
  begin
    Exit;
  end;
  if not TAtlasTestsSeriesMenu.AskCount(TAtlasIdeSettings.Current.TestsRepeatCount,
    TAtlasPluginSettings.cMinTestsRepeatCount, TAtlasPluginSettings.cMaxTestsRepeatCount, mText) then
  begin
    Exit;
  end;
  if not TAtlasTestShuffle.CountOf(mText, TAtlasPluginSettings.cMinTestsRepeatCount,
    TAtlasPluginSettings.cMaxTestsRepeatCount, mCount) then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesBadCount, [mText,
      TAtlasPluginSettings.cMinTestsRepeatCount, TAtlasPluginSettings.cMaxTestsRepeatCount]));
    Exit;
  end;
  Launch(AFileName, TAtlasTestSeries.Repeating(ASubject, ANames, mCount));
end;

procedure TAtlasIdeTestSeries.ShuffleNames(const AFileName: string; const ASubject: TAtlasTestSeriesSubject;
  const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoTestAtCursor));
    Exit;
  end;
  Launch(AFileName, TAtlasTestSeries.Shuffling(ASubject, ANames, TAtlasTestShuffle.SeedOf(TAtlasTicks.Now)));
end;

procedure TAtlasIdeTestSeries.Launch(const AFileName: string; const ASeries: TAtlasTestSeries);
var
  mSeries: TAtlasTestSeries;
  mAlive: TAlive;
  mKeep: IInterface;
begin
  if not TAtlasTestDebug.RunWanted(TAtlasIdeSettings.Current) then
  begin
    FTests.Say(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
    Exit;
  end;
  if FRunning or FTests.Busy then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
    Exit;
  end;
  mSeries := ASeries;
  mAlive := FAlive;
  mKeep := FAliveRef;
  FTests.ResolveProject(AFileName,
    procedure(const AProject: IOTAProject)
    begin
      // Keep hält den Merker am Leben, auch wenn die Serie schon frei ist (Wahl in der Palette).
      if (mKeep = nil) or not mAlive.Alive then
      begin
        Exit;
      end;
      if FRunning or FTests.Busy then
      begin
        FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
        Exit;
      end;
      FSeries := mSeries;
      FSeries.Project := AProject.FileName;
      FRunning := True;
      FShown := False;
      FStop.Requested := False;
      if FSeries.Kind = TAtlasTestSeriesKind.Shuffled then
      begin
        FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesStartedShuffle, [FSeries.Total,
          FSeries.Subject.Caption, FSeries.Seed]));
      end
      else
      begin
        FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesStartedRepeat, [FSeries.Subject.Caption,
          FSeries.Total]));
      end;
      Step;
    end);
end;

procedure TAtlasIdeTestSeries.Step;
var
  mReason: string;
begin
  FOutput.SendNextEndTo(Ended);
  // Nur der erste Start baut; die übrigen nehmen dieselbe EXE.
  if not FTests.RunQuiet(FSeries.Project, FSeries.NextNames, mReason, FSeries.Done = 0) then
  begin
    FOutput.SendNextEndTo(nil);
    FSeries.Stopped := mReason;
    Finish;
  end;
end;

procedure TAtlasIdeTestSeries.Ended(const AEnd: TAtlasTestsQuietEnd);
begin
  if not FRunning then
  begin
    Exit;
  end;
  if AEnd.Reported then
  begin
    FSeries.Add(AEnd.Run);
  end
  else if not FStop.Requested then
  begin
    // Ohne Bericht (Build abgelehnt, EXE fehlt, Zeitlimit): Die übrigen Starts endeten genauso.
    FSeries.Stopped := AEnd.Text;
    if FSeries.Stopped = '' then
    begin
      FSeries.Stopped := '?';
    end;
  end;
  FSeries.Cancelled := FStop.Requested;
  if FSeries.Finished then
  begin
    Finish;
  end
  else
  begin
    Step;
  end;
end;

procedure TAtlasIdeTestSeries.Finish;
begin
  FRunning := False;
  FStop.Requested := False;
  FShown := FSeries.Done > 0;
  FShownVersion := FTests.Version;
  if FSeries.Kind = TAtlasTestSeriesKind.Shuffled then
  begin
    FLastShuffle := FSeries;
    FHasShuffle := True;
  end;
  Report;
end;

procedure TAtlasIdeTestSeries.Report;
var
  mTally: TAtlasTestSeriesTally;
begin
  if FSeries.Cancelled then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesCancelled, [FSeries.Done, FSeries.Total]));
  end
  else if FSeries.Stopped <> '' then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesStopped, [FSeries.Done, FSeries.Total,
      FSeries.Stopped]));
  end;
  if FSeries.Kind = TAtlasTestSeriesKind.Shuffled then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesFinishedShuffle, [FSeries.Subject.Caption,
      FSeries.Seed, FSeries.PassedSteps, FSeries.FailedSteps]));
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesOrder, [OrderText(FSeries)]));
  end
  else
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesFinishedRepeat, [FSeries.Subject.Caption,
      FSeries.Done, FSeries.PassedSteps, FSeries.FailedSteps]));
  end;
  for mTally in FSeries.Failing do
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.SeriesFailingTest, [ShortName(mTally.FullName,
      FSeries.Subject), mTally.Failed, mTally.Failed + mTally.Passed, mTally.Message]));
  end;
  FOutput.ShowView;
end;

function TAtlasIdeTestSeries.MarkOf(const ASelection: TAtlasTestSelection; out AMark: TAtlasTestSeriesMark): Boolean;
begin
  AMark := Default(TAtlasTestSeriesMark);
  // Nach der Serie gilt ihr Ergebnis bis zum nächsten Lauf (der Läufer zählt Version weiter).
  Result := (FRunning or (FShown and (FTests.Version = FShownVersion))) and
    FSeries.Subject.Matches(SubjectOf(ASelection));
  if Result then
  begin
    AMark.Caption := FSeries.Caption(SeriesTexts, FRunning);
    AMark.Running := FRunning;
    AMark.AnyPassed := FSeries.PassedSteps > 0;
    AMark.AnyFailed := FSeries.FailedSteps > 0;
  end;
end;

end.
