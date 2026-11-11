unit Atlas.Core.Welcome.State.Tests;

// Tests für die Zustandskachel „Atlas“ (#754): Zeilen aus dem Atlas-Statusfeld
// (#591) mit derselben Ampel, Zusammenfassung zu Ampelzuständen,
// welcomePage.statusTile und .onlyProblems, Knöpfe, Fingerabdruck; die neuen
// Angaben der Zeilen Server (seit, abgestürzt, beendet), Index (vollständig
// indiziert, „Stand vom …“) und Version (Update bereit); der gespeicherte
// Index-Stand und das gemerkte Update (#495) samt Fehlerart einer gescheiterten
// Abfrage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeStateTests = class
  public
    [Test]
    procedure RowsComeFromStatusFieldInFixedOrder;
    [Test]
    procedure RowsShowSameStateAsStatusField;
    [Test]
    procedure MissingLinesAreNeutralFallbacks;
    [Test]
    procedure BriefAndDetailFromLine;
    [Test]
    procedure ForeignLineWithoutBriefShowsText;
    [Test]
    procedure OverallIsWorstRow;
    [Test]
    procedure AllGreenOrNeutralIsNoProblem;
    [Test]
    procedure OnlyProblemsHidesTileWhenAllGreen;
    [Test]
    procedure StatusTileOffHidesTile;
    [Test]
    procedure UpdateButtonOnlyWithUpdate;
    [Test]
    procedure SignatureChangesOnlyWithVisibleChange;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasStateLinesTests = class
  public
    [Test]
    procedure WhenShowsTimeTodayAndDateOtherwise;
    [Test]
    procedure RunningServerShowsSince;
    [Test]
    procedure CrashedServerIsRedWithTime;
    [Test]
    procedure EndedServerIsNeutral;
    [Test]
    procedure FailedServerShowsError;
    [Test]
    procedure IndexShowsLastFullIndexing;
    [Test]
    procedure IndexWhileBuildingShowsPercent;
    [Test]
    procedure OfflineIndexShowsStoredValues;
    [Test]
    procedure OfflineIndexWithoutStoredValues;
    [Test]
    procedure VersionWithUpdateIsYellow;
    [Test]
    procedure VersionWithoutUpdate;
    [Test]
    procedure VersionAfterFailedCheckIsNotUpToDate;
    [Test]
    procedure LineKeepsBriefAndDetail;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasIndexStoreTests = class
  public
    [Test]
    procedure SnapshotRoundTrip;
    [Test]
    procedure InvalidJsonIsEmpty;
    [Test]
    procedure TrackerRecordsEndOfIndexing;
    [Test]
    procedure TrackerIgnoresUnitsWhileIndexing;
    [Test]
    procedure TrackerSavesWhenServerStops;
    [Test]
    procedure TrackerSavesOnlyOnChange;
    [Test]
    procedure InfoUsesStoredValuesOffline;
    [Test]
    procedure FileRoundTrip;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasStateUpdateTests = class
  public
    [Test]
    procedure RememberKeepsNewVersionAndForgetsAfterCurrent;
    [Test]
    procedure PendingOnlyWhenNewerThanInstalled;
    [Test]
    procedure StateKeepsAvailableVersion;
    [Test]
    procedure RememberKeepsFailureUntilACheckSucceeds;
    [Test]
    procedure StateKeepsLastError;
    [Test]
    procedure FailedCheckIsDueAgainAfterAnHour;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Status.IndexStore,
  Atlas.Core.Updates.Check,
  Atlas.Core.Welcome.State;

type
  /// <summary>Zeile ohne IAtlasStatusBrief (z. B. aus einem anderen Issue).</summary>
  TPlainItem = class(TInterfacedObject, IAtlasStatusItem)
  private
    FId: string;
    FText: string;
    FState: TAtlasStatusState;
  public
    constructor Create(const AId, AText: string; AState: TAtlasStatusState);
    function Id: string;
    function Text: string;
    function Summary: string;
    function State: TAtlasStatusState;
    function Order: Integer;
    function HasAction: Boolean;
    procedure Execute;
  end;

constructor TPlainItem.Create(const AId, AText: string; AState: TAtlasStatusState);
begin
  inherited Create;
  FId := AId;
  FText := AText;
  FState := AState;
end;

function TPlainItem.Id: string;
begin
  Result := FId;
end;

function TPlainItem.Text: string;
begin
  Result := FText;
end;

function TPlainItem.Summary: string;
begin
  Result := '';
end;

function TPlainItem.State: TAtlasStatusState;
begin
  Result := FState;
end;

function TPlainItem.Order: Integer;
begin
  Result := 0;
end;

function TPlainItem.HasAction: Boolean;
begin
  Result := False;
end;

procedure TPlainItem.Execute;
begin
end;

function Line(const ARegistry: IAtlasStatusRegistry; const AId, AText: string; AState: TAtlasStatusState;
  const ABrief, ADetail: string): IAtlasStatusItem;
var
  mItem: TAtlasStatusLine;
begin
  mItem := TAtlasStatusLine.Create(ARegistry, AId, 0);
  Result := mItem;
  mItem.Update(AText, AState, '', ABrief, ADetail);
  ARegistry.Add(Result);
end;

/// <summary>Alle fünf Zeilen grün bzw. neutral wie bei laufendem Server und vollständiger Einrichtung.</summary>
function HealthyRegistry: IAtlasStatusRegistry;
begin
  Result := TAtlasStatusRegistry.Create;
  Line(Result, TAtlasStatusLines.cServerId, 'Server: läuft seit 19:02', TAtlasStatusState.Green, 'Server läuft',
    'seit 19:02');
  Line(Result, TAtlasStatusLines.cVersionId, 'Version: Atlas 1.0.0 (aktuell)', TAtlasStatusState.Green, 'Atlas 1.0.0',
    'aktuell');
  Line(Result, TAtlasStatusLines.cIndexId, 'Index: 1284 Units', TAtlasStatusState.Green, 'Index: 1284 Units',
    'indiziert 18:40');
  Line(Result, TAtlasStatusLines.cSetupId, 'Einrichtung: vollständig (6 von 6)', TAtlasStatusState.Green, '', '');
  // Die Datei-Zeile gehört nicht zur Kachel.
  Line(Result, TAtlasStatusLines.cFileId, 'Datei: keine aktiv', TAtlasStatusState.Neutral, '', '');
end;

function Today(AHour, AMinute: Word): TDateTime;
begin
  Result := Trunc(EncodeDate(2026, 10, 15)) + EncodeTime(AHour, AMinute, 0, 0);
end;

{ TAtlasWelcomeStateTests }

procedure TAtlasWelcomeStateTests.RowsComeFromStatusFieldInFixedOrder;
var
  mRows: TAtlasStateRows;
begin
  mRows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.AreEqual(5, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Server), Ord(mRows[0].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Version), Ord(mRows[1].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Index), Ord(mRows[2].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Setup), Ord(mRows[3].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Diagnostic), Ord(mRows[4].Kind));
  Assert.AreEqual('atlas.server', mRows[0].Id);
  Assert.AreEqual('atlas.version', mRows[1].Id);
  Assert.AreEqual('atlas.index', mRows[2].Id);
  Assert.AreEqual('atlas.setup', mRows[3].Id);
  Assert.AreEqual('atlas.diagnosticMode', mRows[4].Id);
end;

procedure TAtlasWelcomeStateTests.RowsShowSameStateAsStatusField;
var
  mRegistry: IAtlasStatusRegistry;
  mState: TAtlasStatusState;
  mRow: TAtlasStateRow;
  mItem: IAtlasStatusItem;
begin
  // In jedem Zustand dieselbe Ampel wie die Zeile im Statusfeld.
  for mState := Low(TAtlasStatusState) to High(TAtlasStatusState) do
  begin
    mRegistry := HealthyRegistry;
    Line(mRegistry, TAtlasStatusLines.cServerId, 'Server', mState, '', '');
    Line(mRegistry, TAtlasStatusLines.cIndexId, 'Index', mState, '', '');
    Line(mRegistry, TAtlasStatusLines.cDiagnosticModeId, 'Diagnosemodus: an', mState, '', '');
    for mRow in TAtlasWelcomeState.Rows(mRegistry.Items) do
    begin
      mItem := mRegistry.Find(mRow.Id);
      Assert.IsTrue(mItem <> nil, mRow.Id);
      Assert.AreEqual(Ord(mItem.State), Ord(mRow.State), mRow.Id);
      Assert.AreEqual(Ord(mItem.HasAction), Ord(mRow.HasAction), mRow.Id);
    end;
    Assert.AreEqual(Ord(TAtlasStatusSummary.Overall(mRegistry.Items)),
      Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(mRegistry.Items))), 'Gesamtampel');
  end;
end;

procedure TAtlasWelcomeStateTests.MissingLinesAreNeutralFallbacks;
var
  mRows: TAtlasStateRows;
  mRow: TAtlasStateRow;
begin
  mRows := TAtlasWelcomeState.Rows(nil);
  Assert.AreEqual(5, Integer(Length(mRows)));
  for mRow in mRows do
  begin
    Assert.IsFalse(mRow.Present, mRow.Id);
    Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(mRow.State), mRow.Id);
    Assert.AreEqual('', mRow.Text, mRow.Id);
    Assert.IsFalse(mRow.HasAction, mRow.Id);
  end;
  // Diagnosemodus aus: keine Zeile im Statusfeld, in der Kachel neutral.
  mRows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.IsFalse(mRows[4].Present);
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(mRows[4].State));
end;

procedure TAtlasWelcomeStateTests.BriefAndDetailFromLine;
var
  mRows: TAtlasStateRows;
begin
  mRows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.AreEqual('Server läuft', mRows[0].Text);
  Assert.AreEqual('seit 19:02', mRows[0].Detail);
  Assert.AreEqual('Server: läuft seit 19:02', mRows[0].Hint, 'Tooltip mit dem vollen Text');
  // Ohne Kurzform: Text der Zeile, kein Zusatz.
  Assert.AreEqual('Einrichtung: vollständig (6 von 6)', mRows[3].Text);
  Assert.AreEqual('', mRows[3].Detail);
end;

procedure TAtlasWelcomeStateTests.ForeignLineWithoutBriefShowsText;
var
  mRegistry: IAtlasStatusRegistry;
  mRows: TAtlasStateRows;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mRegistry.Add(TPlainItem.Create('ATLAS.SETUP', 'Einrichtung: 5 von 6 erledigt', TAtlasStatusState.Yellow));
  mRows := TAtlasWelcomeState.Rows(mRegistry.Items);
  Assert.IsTrue(mRows[3].Present, 'Kennung ohne Groß-/Kleinschreibung');
  Assert.AreEqual('Einrichtung: 5 von 6 erledigt', mRows[3].Text);
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(mRows[3].State));
end;

procedure TAtlasWelcomeStateTests.OverallIsWorstRow;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := HealthyRegistry;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    mRegistry.Items))));
  Line(mRegistry, TAtlasStatusLines.cSetupId, 'Einrichtung: 5 von 6 erledigt', TAtlasStatusState.Yellow, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    mRegistry.Items))));
  Line(mRegistry, TAtlasStatusLines.cServerId, 'Server: abgestürzt um 14:32', TAtlasStatusState.Red, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    mRegistry.Items))));
  // Eine rote Datei-Zeile gehört nicht zur Kachel.
  mRegistry := HealthyRegistry;
  Line(mRegistry, TAtlasStatusLines.cFileId, 'Datei: gemischt', TAtlasStatusState.Red, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    mRegistry.Items))));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasWelcomeState.Overall(nil)), 'ohne Zeilen');
end;

procedure TAtlasWelcomeStateTests.AllGreenOrNeutralIsNoProblem;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := HealthyRegistry;
  Assert.IsFalse(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(mRegistry.Items)));
  Line(mRegistry, TAtlasStatusLines.cServerId, 'Server: beendet', TAtlasStatusState.Neutral, '', '');
  Assert.IsFalse(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(mRegistry.Items)), 'neutral');
  Line(mRegistry, TAtlasStatusLines.cDiagnosticModeId, 'Diagnosemodus: an', TAtlasStatusState.Yellow, '', '');
  Assert.IsTrue(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(mRegistry.Items)), 'gelb');
end;

procedure TAtlasWelcomeStateTests.OnlyProblemsHidesTileWhenAllGreen;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := HealthyRegistry;
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, False, TAtlasWelcomeState.Rows(mRegistry.Items)),
    'ohne onlyProblems immer');
  Assert.IsFalse(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(mRegistry.Items)),
    'alles grün: unsichtbar');
  Line(mRegistry, TAtlasStatusLines.cVersionId, 'Version: Update 1.0.1', TAtlasStatusState.Yellow, '', '');
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(mRegistry.Items)), 'gelb: sichtbar');
  Line(mRegistry, TAtlasStatusLines.cVersionId, 'Version', TAtlasStatusState.Green, '', '');
  Line(mRegistry, TAtlasStatusLines.cServerId, 'Server: abgestürzt', TAtlasStatusState.Red, '', '');
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(mRegistry.Items)), 'rot: sichtbar');
end;

procedure TAtlasWelcomeStateTests.StatusTileOffHidesTile;
var
  mRegistry: IAtlasStatusRegistry;
begin
  mRegistry := HealthyRegistry;
  Line(mRegistry, TAtlasStatusLines.cServerId, 'Server: abgestürzt', TAtlasStatusState.Red, '', '');
  Assert.IsFalse(TAtlasWelcomeState.Visible(False, False, TAtlasWelcomeState.Rows(mRegistry.Items)));
  Assert.IsFalse(TAtlasWelcomeState.Visible(False, True, TAtlasWelcomeState.Rows(mRegistry.Items)));
end;

procedure TAtlasWelcomeStateTests.UpdateButtonOnlyWithUpdate;
var
  mRegistry: IAtlasStatusRegistry;
  mButtons: TArray<TAtlasStateButton>;
begin
  mRegistry := HealthyRegistry;
  mButtons := TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(mRegistry.Items));
  Assert.AreEqual(3, Integer(Length(mButtons)));
  Assert.AreEqual(Ord(TAtlasStateButton.Restart), Ord(mButtons[0]));
  Assert.AreEqual(Ord(TAtlasStateButton.Settings), Ord(mButtons[1]));
  Assert.AreEqual(Ord(TAtlasStateButton.LogFolder), Ord(mButtons[2]));
  Assert.IsFalse(TAtlasWelcomeState.UpdateReady(TAtlasWelcomeState.Rows(mRegistry.Items)));
  Line(mRegistry, TAtlasStatusLines.cVersionId, 'Version: Atlas 1.0.0, Update 1.0.1 bereit', TAtlasStatusState.Yellow,
    'Update 1.0.1 bereit', 'installiert 1.0.0');
  mButtons := TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(mRegistry.Items));
  Assert.AreEqual(4, Integer(Length(mButtons)));
  Assert.AreEqual(Ord(TAtlasStateButton.Update), Ord(mButtons[3]));
  // Eine gelbe Zeile anderswo ist kein Update.
  mRegistry := HealthyRegistry;
  Line(mRegistry, TAtlasStatusLines.cSetupId, 'Einrichtung', TAtlasStatusState.Yellow, '', '');
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(mRegistry.Items)))));
end;

procedure TAtlasWelcomeStateTests.SignatureChangesOnlyWithVisibleChange;
var
  mRegistry: IAtlasStatusRegistry;
  mBefore: string;
begin
  mRegistry := HealthyRegistry;
  mBefore := TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(mRegistry.Items));
  // Die Datei-Zeile ändert die Kachel nicht.
  Line(mRegistry, TAtlasStatusLines.cFileId, 'Datei Main.pas: UTF-8', TAtlasStatusState.Green, '', '');
  Assert.AreEqual(mBefore, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(mRegistry.Items)));
  Line(mRegistry, TAtlasStatusLines.cIndexId, 'Index: 1284 Units', TAtlasStatusState.Green, 'Index: 1284 Units',
    'indiziert 18:41');
  Assert.AreNotEqual(mBefore, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(mRegistry.Items)), 'Zusatz');
  mRegistry := HealthyRegistry;
  Line(mRegistry, TAtlasStatusLines.cServerId, 'Server: läuft seit 19:02', TAtlasStatusState.Yellow, 'Server läuft',
    'seit 19:02');
  Assert.AreNotEqual(mBefore, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(mRegistry.Items)), 'Ampel');
end;

{ TAtlasStateLinesTests }

procedure TAtlasStateLinesTests.WhenShowsTimeTodayAndDateOtherwise;
begin
  Assert.AreEqual('19:02', TAtlasStatusLines.When(Today(19, 2), Today(20, 0)));
  Assert.AreEqual('14.10. 17:45', TAtlasStatusLines.When(Today(17, 45) - 1, Today(9, 0)));
  Assert.AreEqual('', TAtlasStatusLines.When(0, Today(9, 0)));
end;

procedure TAtlasStateLinesTests.RunningServerShowsSince;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Running;
  mInfo.Version := '1.0.0';
  mInfo.Since := Today(19, 2);
  Assert.AreEqual('Server: läuft seit 19:02, Version 1.0.0', TAtlasStatusLines.ServerText(mInfo, Today(20, 0)));
  Assert.AreEqual('Server läuft', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual('seit 19:02', TAtlasStatusLines.ServerDetail(mInfo, Today(20, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(mInfo)));
  mInfo.Samples := 3;
  mInfo.AverageMs := TAtlasStatusLines.cSlowMs;
  Assert.AreEqual('Server läuft langsam', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(mInfo)));
end;

procedure TAtlasStateLinesTests.CrashedServerIsRedWithTime;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Stopped;
  mInfo.Since := Today(14, 32);
  Assert.AreEqual('Server: abgestürzt um 14:32', TAtlasStatusLines.ServerText(mInfo, Today(15, 0)));
  Assert.AreEqual('Server abgestürzt', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual('um 14:32', TAtlasStatusLines.ServerDetail(mInfo, Today(15, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.AreEqual('Server abgestürzt', TAtlasStatusLines.ServerSummary(mInfo));
  // Ursache aus dem Exit-Code (Bericht H5).
  mInfo.Error := 'Stapelüberlauf (0xC00000FD)';
  Assert.AreEqual('Server: abgestürzt um 14:32 (Stapelüberlauf (0xC00000FD))',
    TAtlasStatusLines.ServerText(mInfo, Today(15, 0)));
  Assert.AreEqual('um 14:32, Stapelüberlauf (0xC00000FD)', TAtlasStatusLines.ServerDetail(mInfo, Today(15, 0)));
  // Von Atlas beendet: keine Ursache, auch wenn noch eine gesetzt ist.
  mInfo.Ended := True;
  Assert.AreEqual('Server: beendet um 14:32', TAtlasStatusLines.ServerText(mInfo, Today(15, 0)));
end;

procedure TAtlasStateLinesTests.EndedServerIsNeutral;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Stopped;
  mInfo.Ended := True;
  mInfo.Since := Today(8, 5);
  Assert.AreEqual('Server: beendet um 08:05', TAtlasStatusLines.ServerText(mInfo, Today(9, 0)));
  Assert.AreEqual('Server beendet', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.ServerState(mInfo)));
  Assert.AreEqual('', TAtlasStatusLines.ServerSummary(mInfo));
end;

procedure TAtlasStateLinesTests.FailedServerShowsError;
var
  mInfo: TAtlasServerInfo;
begin
  mInfo := Default(TAtlasServerInfo);
  mInfo.Phase := TAtlasServerPhase.Failed;
  mInfo.Error := 'AtlasServer.exe nicht gefunden';
  Assert.AreEqual('Server-Start fehlgeschlagen', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual('AtlasServer.exe nicht gefunden', TAtlasStatusLines.ServerDetail(mInfo, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(mInfo)));
  mInfo := Default(TAtlasServerInfo);
  Assert.AreEqual('Server nicht gestartet', TAtlasStatusLines.ServerBrief(mInfo));
  Assert.AreEqual('', TAtlasStatusLines.ServerDetail(mInfo, Today(9, 0)));
end;

procedure TAtlasStateLinesTests.IndexShowsLastFullIndexing;
var
  mInfo: TAtlasIndexInfo;
begin
  mInfo := Default(TAtlasIndexInfo);
  mInfo.Units := 1284;
  mInfo.Percent := -1;
  mInfo.FullAt := Today(18, 40);
  Assert.AreEqual('Index: 1284 Units, vollständig indiziert 18:40', TAtlasStatusLines.IndexText(mInfo, Today(19, 0)));
  Assert.AreEqual('Index: 1284 Units', TAtlasStatusLines.IndexBrief(mInfo));
  Assert.AreEqual('indiziert 18:40', TAtlasStatusLines.IndexDetail(mInfo, Today(19, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.IndexState(mInfo)));
end;

procedure TAtlasStateLinesTests.IndexWhileBuildingShowsPercent;
var
  mInfo: TAtlasIndexInfo;
begin
  mInfo := Default(TAtlasIndexInfo);
  mInfo.Units := -1;
  mInfo.Indexing := True;
  mInfo.Percent := 45;
  mInfo.FullAt := Today(18, 40);
  Assert.AreEqual('Index wird aufgebaut', TAtlasStatusLines.IndexBrief(mInfo));
  Assert.AreEqual('45 %', TAtlasStatusLines.IndexDetail(mInfo, Today(19, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.IndexState(mInfo)));
  mInfo.Percent := -1;
  Assert.AreEqual('', TAtlasStatusLines.IndexDetail(mInfo, Today(19, 0)));
end;

procedure TAtlasStateLinesTests.OfflineIndexShowsStoredValues;
var
  mInfo: TAtlasIndexInfo;
begin
  mInfo := Default(TAtlasIndexInfo);
  mInfo.Offline := True;
  mInfo.Units := 1284;
  mInfo.Percent := -1;
  mInfo.StoredAt := Today(17, 45) - 1;
  Assert.AreEqual('Index: 1284 Units, Stand vom 14.10. 17:45 (Server läuft nicht)',
    TAtlasStatusLines.IndexText(mInfo, Today(9, 0)));
  Assert.AreEqual('Index: 1284 Units', TAtlasStatusLines.IndexBrief(mInfo));
  Assert.AreEqual('Stand vom 14.10. 17:45', TAtlasStatusLines.IndexDetail(mInfo, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(mInfo)));
  Assert.AreEqual('', TAtlasStatusLines.IndexSummary(mInfo));
end;

procedure TAtlasStateLinesTests.OfflineIndexWithoutStoredValues;
var
  mInfo: TAtlasIndexInfo;
begin
  mInfo := Default(TAtlasIndexInfo);
  mInfo.Offline := True;
  mInfo.Units := -1;
  Assert.AreEqual('Index: Server läuft nicht', TAtlasStatusLines.IndexText(mInfo, Today(9, 0)));
  Assert.AreEqual('Index unbekannt', TAtlasStatusLines.IndexBrief(mInfo));
  Assert.AreEqual('Server läuft nicht', TAtlasStatusLines.IndexDetail(mInfo, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(mInfo)));
end;

procedure TAtlasStateLinesTests.VersionWithUpdateIsYellow;
var
  mInfo: TAtlasVersionInfo;
begin
  mInfo := Default(TAtlasVersionInfo);
  mInfo.Installed := '1.0.0';
  mInfo.Available := '1.0.1';
  mInfo.CheckEnabled := True;
  mInfo.Checked := True;
  Assert.IsTrue(TAtlasStatusLines.UpdateAvailable(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('Version: Atlas 1.0.0, Update 1.0.1 bereit', TAtlasStatusLines.VersionText(mInfo));
  Assert.AreEqual('Update 1.0.1 bereit', TAtlasStatusLines.VersionBrief(mInfo));
  Assert.AreEqual('installiert 1.0.0', TAtlasStatusLines.VersionDetail(mInfo));
  Assert.AreEqual('Update 1.0.1', TAtlasStatusLines.VersionSummary(mInfo));
  // Stand der Installation (#1519) in Zeile und Einzelheiten.
  mInfo.Install := 'wird beim Beenden installiert';
  Assert.AreEqual('Version: Atlas 1.0.0, Update 1.0.1 bereit (wird beim Beenden installiert)',
    TAtlasStatusLines.VersionText(mInfo));
  Assert.AreEqual('wird beim Beenden installiert', TAtlasStatusLines.VersionDetail(mInfo));
end;

procedure TAtlasStateLinesTests.VersionWithoutUpdate;
var
  mInfo: TAtlasVersionInfo;
begin
  mInfo := Default(TAtlasVersionInfo);
  mInfo.Installed := '1.0.0';
  mInfo.CheckEnabled := True;
  mInfo.Checked := True;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('Atlas 1.0.0', TAtlasStatusLines.VersionBrief(mInfo));
  Assert.AreEqual('aktuell', TAtlasStatusLines.VersionDetail(mInfo));
  Assert.AreEqual('', TAtlasStatusLines.VersionSummary(mInfo));
  mInfo.Checked := False;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('noch nicht geprüft', TAtlasStatusLines.VersionDetail(mInfo));
  mInfo.CheckEnabled := False;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('Version: Atlas 1.0.0 (Update-Prüfung aus)', TAtlasStatusLines.VersionText(mInfo));
  Assert.AreEqual('Update-Prüfung aus', TAtlasStatusLines.VersionDetail(mInfo));
end;

procedure TAtlasStateLinesTests.VersionAfterFailedCheckIsNotUpToDate;
var
  mInfo: TAtlasVersionInfo;
begin
  // Gescheiterte Abfrage (z. B. Proxy): nie „aktuell“, sondern gelb mit Fehlerart.
  mInfo := Default(TAtlasVersionInfo);
  mInfo.Installed := '2.0.0-beta.3';
  mInfo.CheckEnabled := True;
  mInfo.Checked := True;
  mInfo.Failure := 'HTTP 407';
  Assert.IsFalse(TAtlasStatusLines.UpdateAvailable(mInfo));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('Version: Atlas 2.0.0-beta.3 (Prüfung fehlgeschlagen)', TAtlasStatusLines.VersionText(mInfo));
  Assert.AreEqual('Prüfung fehlgeschlagen: HTTP 407', TAtlasStatusLines.VersionDetail(mInfo));
  Assert.AreEqual('Atlas 2.0.0-beta.3', TAtlasStatusLines.VersionBrief(mInfo));
  Assert.AreEqual('', TAtlasStatusLines.VersionSummary(mInfo));
  // Ein früher gefundenes Update bleibt vorn.
  mInfo.Available := '2.0.1';
  Assert.AreEqual('Version: Atlas 2.0.0-beta.3, Update 2.0.1 bereit', TAtlasStatusLines.VersionText(mInfo));
  // Prüfung aus: Der alte Fehler spielt keine Rolle.
  mInfo.Available := '';
  mInfo.CheckEnabled := False;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.VersionState(mInfo)));
  Assert.AreEqual('Version: Atlas 2.0.0-beta.3 (Update-Prüfung aus)', TAtlasStatusLines.VersionText(mInfo));
end;

procedure TAtlasStateLinesTests.LineKeepsBriefAndDetail;
var
  mRegistry: IAtlasStatusRegistry;
  mItem: TAtlasStatusLine;
  mRef: IAtlasStatusItem;
  mBrief: IAtlasStatusBrief;
  mBefore: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mItem := TAtlasStatusLine.Create(mRegistry, 'atlas.server', 0);
  mRef := mItem;
  mRegistry.Add(mRef);
  mItem.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:02');
  Assert.IsTrue(Supports(mRef, IAtlasStatusBrief, mBrief));
  Assert.AreEqual('Server läuft', mBrief.Brief);
  Assert.AreEqual('seit 19:02', mBrief.Detail);
  mBefore := mRegistry.Version;
  mItem.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:02');
  Assert.AreEqual(mBefore, mRegistry.Version, 'nichts geändert');
  mItem.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:03');
  Assert.AreEqual(mBefore + 1, mRegistry.Version, 'Zusatz geändert');
  // Ohne Kurzform sind beide leer.
  mItem.Update('Server: läuft', TAtlasStatusState.Green);
  Assert.AreEqual('', mBrief.Brief);
  Assert.AreEqual('', mBrief.Detail);
  mItem.Detach;
end;

{ TAtlasIndexStoreTests }

procedure TAtlasIndexStoreTests.SnapshotRoundTrip;
var
  mSnapshot, mBack: TAtlasIndexSnapshot;
begin
  mSnapshot := TAtlasIndexSnapshot.Empty;
  Assert.IsFalse(mSnapshot.Known);
  mSnapshot.Units := 1284;
  mSnapshot.FullAt := Today(18, 40);
  mSnapshot.At := Today(19, 5);
  Assert.IsTrue(mSnapshot.Known);
  mBack := TAtlasIndexSnapshot.FromJson(mSnapshot.ToJson);
  Assert.AreEqual(1284, mBack.Units);
  Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', mSnapshot.FullAt), FormatDateTime('yyyy-mm-dd hh:nn:ss',
    mBack.FullAt));
  Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', mSnapshot.At), FormatDateTime('yyyy-mm-dd hh:nn:ss', mBack.At));
  Assert.IsTrue(mBack.Known);
  // Keine Pfade und Namen in der Datei.
  Assert.IsFalse(mSnapshot.ToJson.Contains('\'));
end;

procedure TAtlasIndexStoreTests.InvalidJsonIsEmpty;
var
  mBack: TAtlasIndexSnapshot;
begin
  mBack := TAtlasIndexSnapshot.FromJson('kein JSON');
  Assert.AreEqual(-1, mBack.Units);
  Assert.IsFalse(mBack.Known);
  mBack := TAtlasIndexSnapshot.FromJson('{"format": 2, "units": 5, "at": "2026-10-15T10:00:00Z"}');
  Assert.AreEqual(-1, mBack.Units, 'anderes Format');
  mBack := TAtlasIndexSnapshot.FromJson('{"format": 1, "units": -3, "at": "Unsinn"}');
  Assert.AreEqual(-1, mBack.Units);
  Assert.IsTrue(mBack.At = 0);
end;

procedure TAtlasIndexStoreTests.TrackerRecordsEndOfIndexing;
var
  mTracker: TAtlasIndexTracker;
begin
  mTracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Assert.IsFalse(mTracker.Observe(True, True, -1, Today(18, 30)), 'Indizierung läuft');
    Assert.IsTrue(mTracker.Snapshot.FullAt = 0);
    Assert.IsTrue(mTracker.Observe(True, False, 1284, Today(18, 40)), 'Ende der Indizierung');
    Assert.IsTrue(mTracker.Snapshot.FullAt = Today(18, 40));
    Assert.AreEqual(1284, mTracker.Snapshot.Units);
    Assert.IsTrue(mTracker.Snapshot.At = Today(18, 40));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerIgnoresUnitsWhileIndexing;
var
  mTracker: TAtlasIndexTracker;
begin
  mTracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    mTracker.Observe(True, True, 80, Today(18, 30));
    Assert.AreEqual(-1, mTracker.Snapshot.Units, 'Zwischenstand zählt nicht');
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerSavesWhenServerStops;
var
  mTracker: TAtlasIndexTracker;
begin
  mTracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Assert.IsFalse(mTracker.Observe(False, False, -1, Today(9, 0)), 'lief nie: nichts zu sichern');
    mTracker.Observe(True, False, 1284, Today(9, 1));
    mTracker.Observe(True, False, 1284, Today(9, 30));
    Assert.IsTrue(mTracker.Observe(False, False, -1, Today(9, 31)), 'Server hört auf');
    Assert.IsTrue(mTracker.Snapshot.At = Today(9, 30), 'zuletzt bestätigt');
    Assert.IsFalse(mTracker.Observe(False, False, -1, Today(9, 32)), 'nur einmal');
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerSavesOnlyOnChange;
var
  mStored: TAtlasIndexSnapshot;
  mTracker: TAtlasIndexTracker;
begin
  mStored := TAtlasIndexSnapshot.Empty;
  mStored.Units := 1200;
  mStored.FullAt := Today(8, 0);
  mStored.At := Today(8, 30);
  mTracker := TAtlasIndexTracker.Create(mStored);
  try
    Assert.IsFalse(mTracker.Observe(True, False, -1, Today(9, 0)), 'Units noch unbekannt');
    Assert.IsFalse(mTracker.Observe(True, False, 1200, Today(9, 1)), 'unverändert');
    Assert.IsTrue(mTracker.Snapshot.At = Today(9, 1), 'Stand im Speicher nachgeführt');
    Assert.IsTrue(mTracker.Observe(True, False, 1210, Today(9, 2)), 'Units geändert');
    Assert.IsTrue(mTracker.Snapshot.FullAt = Today(8, 0), 'keine neue Indizierung');
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.InfoUsesStoredValuesOffline;
var
  mStored: TAtlasIndexSnapshot;
  mTracker: TAtlasIndexTracker;
  mInfo: TAtlasIndexInfo;
begin
  mStored := TAtlasIndexSnapshot.Empty;
  mStored.Units := 1284;
  mStored.FullAt := Today(8, 0);
  mStored.At := Today(8, 30);
  mTracker := TAtlasIndexTracker.Create(mStored);
  try
    mInfo := mTracker.Info(False, False, -1, -1);
    Assert.IsTrue(mInfo.Offline);
    Assert.AreEqual(1284, mInfo.Units);
    Assert.IsTrue(mInfo.StoredAt = Today(8, 30));
    Assert.AreEqual('Stand vom 08:30', TAtlasStatusLines.IndexDetail(mInfo, Today(9, 0)));
    mInfo := mTracker.Info(True, True, 45, 300);
    Assert.IsFalse(mInfo.Offline);
    Assert.IsTrue(mInfo.Indexing);
    Assert.AreEqual(45, mInfo.Percent);
    Assert.AreEqual(300, mInfo.Units);
    Assert.IsTrue(mInfo.FullAt = Today(8, 0), 'letzte vollständige Indizierung');
  finally
    mTracker.Free;
  end;
  mTracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    mInfo := mTracker.Info(False, False, -1, -1);
    Assert.AreEqual(-1, mInfo.Units, 'nichts gespeichert');
    Assert.AreEqual('Index: Server läuft nicht', TAtlasStatusLines.IndexText(mInfo, Today(9, 0)));
  finally
    mTracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.FileRoundTrip;
var
  mFolder, mFileName: string;
  mSnapshot, mBack: TAtlasIndexSnapshot;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-index-store-' + IntToStr(Random(MaxInt)));
  mFileName := TPath.Combine(TPath.Combine(mFolder, 'Atlas'), TAtlasIndexStore.cFileName);
  try
    mBack := TAtlasIndexStore.Load(mFileName);
    Assert.AreEqual(-1, mBack.Units, 'fehlende Datei');
    mSnapshot := TAtlasIndexSnapshot.Empty;
    mSnapshot.Units := 77;
    mSnapshot.At := Today(10, 0);
    Assert.IsTrue(TAtlasIndexStore.Save(mFileName, mSnapshot), 'legt den Ordner an');
    mBack := TAtlasIndexStore.Load(mFileName);
    Assert.AreEqual(77, mBack.Units);
    Assert.IsTrue(mBack.Known);
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

{ TAtlasStateUpdateTests }

procedure TAtlasStateUpdateTests.RememberKeepsNewVersionAndForgetsAfterCurrent;
var
  mState: TAtlasUpdateState;
  mOutcome: TAtlasUpdateResult;
begin
  mState := Default(TAtlasUpdateState);
  mOutcome := Default(TAtlasUpdateResult);
  mOutcome.Outcome := TAtlasUpdateOutcome.NewVersion;
  mOutcome.Release.Version := '1.0.1';
  mOutcome.Release.ChangesUrl := 'https://example.org/changes';
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('1.0.1', mState.Available);
  Assert.AreEqual('https://example.org/changes', mState.ChangesUrl);
  mOutcome := Default(TAtlasUpdateResult);
  mOutcome.Outcome := TAtlasUpdateOutcome.Failed;
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('1.0.1', mState.Available, 'Fehlschlag ändert nichts');
  mOutcome.Outcome := TAtlasUpdateOutcome.NotDue;
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('1.0.1', mState.Available, 'nicht fällig ändert nichts');
  mOutcome.Outcome := TAtlasUpdateOutcome.Current;
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('', mState.Available, 'aktuell');
  Assert.AreEqual('', mState.ChangesUrl);
end;

procedure TAtlasStateUpdateTests.RememberKeepsFailureUntilACheckSucceeds;
var
  mState: TAtlasUpdateState;
  mOutcome: TAtlasUpdateResult;
begin
  mState := Default(TAtlasUpdateState);
  mOutcome := Default(TAtlasUpdateResult);
  mOutcome.Outcome := TAtlasUpdateOutcome.Failed;
  mOutcome.Error := 'HTTP 407';
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('HTTP 407', mState.LastError);
  mOutcome.Outcome := TAtlasUpdateOutcome.NotDue;
  mOutcome.Error := '';
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('HTTP 407', mState.LastError, 'nicht fällig ändert nichts');
  // Ohne Fehlerart bleibt erkennbar, dass die Abfrage scheiterte.
  mOutcome.Outcome := TAtlasUpdateOutcome.Failed;
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('?', mState.LastError);
  mOutcome.Error := 'Zeile'#13#10'zwei';
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('Zeile  zwei', mState.LastError, 'eine Zeile');
  mOutcome.Outcome := TAtlasUpdateOutcome.NewVersion;
  mOutcome.Release.Version := '2.0.1';
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('', mState.LastError, 'neue Version');
  mOutcome.Outcome := TAtlasUpdateOutcome.Failed;
  TAtlasUpdates.Remember(mState, mOutcome);
  mOutcome.Outcome := TAtlasUpdateOutcome.Current;
  TAtlasUpdates.Remember(mState, mOutcome);
  Assert.AreEqual('', mState.LastError, 'aktuell');
end;

procedure TAtlasStateUpdateTests.StateKeepsLastError;
var
  mState, mLoaded: TAtlasUpdateState;
begin
  mState := Default(TAtlasUpdateState);
  mState.Asked := True;
  mState.LastError := 'ENetHTTPClientException';
  mLoaded := TAtlasUpdateState.FromJson(mState.ToJson);
  Assert.AreEqual('ENetHTTPClientException', mLoaded.LastError);
  mState.LastError := '';
  Assert.IsFalse(mState.ToJson.Contains('lastError'), 'ohne Fehler kein Feld');
  mLoaded := TAtlasUpdateState.FromJson('{"asked":true,"lastError":""}');
  Assert.AreEqual('?', mLoaded.LastError, 'leere Fehlerart bleibt ein Fehler');
  mLoaded := TAtlasUpdateState.FromJson('{"asked":true}');
  Assert.AreEqual('', mLoaded.LastError, 'ältere Zustandsdatei');
end;

procedure TAtlasStateUpdateTests.FailedCheckIsDueAgainAfterAnHour;
var
  mState: TAtlasUpdateState;
  mLast: TDateTime;
begin
  mLast := EncodeDateTime(2026, 11, 9, 8, 0, 0, 0);
  mState := Default(TAtlasUpdateState);
  mState.LastCheck := mLast;
  Assert.IsFalse(TAtlasUpdates.IsStateDue(mState, IncHour(mLast, 1)), 'gelungen: erst nach einem Tag');
  Assert.IsTrue(TAtlasUpdates.IsStateDue(mState, IncHour(mLast, 24)));
  // Gescheitert (z. B. HTTP 504): nach einer Stunde wieder.
  mState.LastError := 'HTTP 504';
  Assert.IsFalse(TAtlasUpdates.IsStateDue(mState, IncMinute(mLast, 59)));
  Assert.IsTrue(TAtlasUpdates.IsStateDue(mState, IncHour(mLast, 1)));
  Assert.IsTrue(TAtlasUpdates.IsStateDue(mState, IncHour(mLast, -2)), 'Uhr zurückgestellt');
end;

procedure TAtlasStateUpdateTests.PendingOnlyWhenNewerThanInstalled;
var
  mState: TAtlasUpdateState;
  mRelease: TAtlasRelease;
begin
  mState := Default(TAtlasUpdateState);
  Assert.IsFalse(TAtlasUpdates.Pending(mState, '1.0.0', mRelease));
  mState.Available := '1.0.1';
  mState.ChangesUrl := 'https://example.org/changes';
  Assert.IsTrue(TAtlasUpdates.Pending(mState, '1.0.0', mRelease));
  Assert.AreEqual('1.0.1', mRelease.Version);
  Assert.AreEqual('https://example.org/changes', mRelease.ChangesUrl);
  // Nach der Installation gilt das Update nicht mehr.
  Assert.IsFalse(TAtlasUpdates.Pending(mState, '1.0.1', mRelease));
  Assert.AreEqual('', mRelease.Version);
  Assert.IsFalse(TAtlasUpdates.Pending(mState, '1.1.0', mRelease));
  // Keine https-Adresse: Release-Seite der Version.
  mState.ChangesUrl := 'file:///C:/x';
  Assert.IsTrue(TAtlasUpdates.Pending(mState, '1.0.0', mRelease));
  Assert.AreEqual(TAtlasUpdates.cReleasesUrl + '/tag/v1.0.1', mRelease.ChangesUrl);
end;

procedure TAtlasStateUpdateTests.StateKeepsAvailableVersion;
var
  mState, mBack: TAtlasUpdateState;
begin
  mState := Default(TAtlasUpdateState);
  mState.Asked := True;
  mState.Available := '1.0.1';
  mState.ChangesUrl := 'https://example.org/changes';
  mBack := TAtlasUpdateState.FromJson(mState.ToJson);
  Assert.IsTrue(mBack.Asked);
  Assert.AreEqual('1.0.1', mBack.Available);
  Assert.AreEqual('https://example.org/changes', mBack.ChangesUrl);
  // Ungültige Version gilt nicht; fremde Adresse wird zur Release-Seite.
  mBack := TAtlasUpdateState.FromJson('{"asked": true, "available": "neu", "changes": "https://x"}');
  Assert.AreEqual('', mBack.Available);
  mBack := TAtlasUpdateState.FromJson('{"available": "1.2.0", "changes": "http://x"}');
  Assert.AreEqual('1.2.0', mBack.Available);
  Assert.AreEqual(TAtlasUpdates.cReleasesUrl + '/tag/v1.2.0', mBack.ChangesUrl);
  // Ohne gefundene Version kein Feld in der Datei.
  mState.Available := '';
  Assert.IsFalse(mState.ToJson.Contains('available'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateTests);
  TDUnitX.RegisterTestFixture(TAtlasStateLinesTests);
  TDUnitX.RegisterTestFixture(TAtlasIndexStoreTests);
  TDUnitX.RegisterTestFixture(TAtlasStateUpdateTests);

end.
