unit Atlas.Core.Welcome.State.Tests;

// Tests für die Zustandskachel „Atlas“ (#754): Zeilen aus dem Atlas-Statusfeld
// (#591) mit derselben Ampel, Zusammenfassung zu Ampelzuständen,
// welcomePage.statusTile und .onlyProblems, Knöpfe, Fingerabdruck; die neuen
// Angaben der Zeilen Server (seit, abgestürzt, beendet), Index (vollständig
// indiziert, „Stand vom …“) und Version (Update bereit); der gespeicherte
// Index-Stand und das gemerkte Update (#495).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
    procedure LineKeepsBriefAndDetail;
  end;

  [TestFixture]
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
  TAtlasStateUpdateTests = class
  public
    [Test]
    procedure RememberKeepsNewVersionAndForgetsAfterCurrent;
    [Test]
    procedure PendingOnlyWhenNewerThanInstalled;
    [Test]
    procedure StateKeepsAvailableVersion;
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
  Item: TAtlasStatusLine;
begin
  Item := TAtlasStatusLine.Create(ARegistry, AId, 0);
  Result := Item;
  Item.Update(AText, AState, '', ABrief, ADetail);
  ARegistry.Add(Result);
end;

/// <summary>Alle fünf Zeilen grün bzw. neutral wie bei laufendem Server und vollständiger Einrichtung.</summary>
function HealthyRegistry: IAtlasStatusRegistry;
begin
  Result := TAtlasStatusRegistry.Create;
  Line(Result, TAtlasStatusLines.ServerId, 'Server: läuft seit 19:02', TAtlasStatusState.Green, 'Server läuft',
    'seit 19:02');
  Line(Result, TAtlasStatusLines.VersionId, 'Version: Atlas 1.0.0 (aktuell)', TAtlasStatusState.Green, 'Atlas 1.0.0',
    'aktuell');
  Line(Result, TAtlasStatusLines.IndexId, 'Index: 1284 Units', TAtlasStatusState.Green, 'Index: 1284 Units',
    'indiziert 18:40');
  Line(Result, TAtlasStatusLines.SetupId, 'Einrichtung: vollständig (6 von 6)', TAtlasStatusState.Green, '', '');
  // Die Datei-Zeile gehört nicht zur Kachel.
  Line(Result, TAtlasStatusLines.FileId, 'Datei: keine aktiv', TAtlasStatusState.Neutral, '', '');
end;

function Today(AHour, AMinute: Word): TDateTime;
begin
  Result := Trunc(EncodeDate(2026, 10, 15)) + EncodeTime(AHour, AMinute, 0, 0);
end;

{ TAtlasWelcomeStateTests }

procedure TAtlasWelcomeStateTests.RowsComeFromStatusFieldInFixedOrder;
var
  Rows: TAtlasStateRows;
begin
  Rows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.AreEqual(5, Integer(Length(Rows)));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Server), Ord(Rows[0].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Version), Ord(Rows[1].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Index), Ord(Rows[2].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Setup), Ord(Rows[3].Kind));
  Assert.AreEqual(Ord(TAtlasStateRowKind.Diagnostic), Ord(Rows[4].Kind));
  Assert.AreEqual('atlas.server', Rows[0].Id);
  Assert.AreEqual('atlas.version', Rows[1].Id);
  Assert.AreEqual('atlas.index', Rows[2].Id);
  Assert.AreEqual('atlas.setup', Rows[3].Id);
  Assert.AreEqual('atlas.diagnosticMode', Rows[4].Id);
end;

procedure TAtlasWelcomeStateTests.RowsShowSameStateAsStatusField;
var
  Registry: IAtlasStatusRegistry;
  State: TAtlasStatusState;
  Row: TAtlasStateRow;
  Item: IAtlasStatusItem;
begin
  // In jedem Zustand dieselbe Ampel wie die Zeile im Statusfeld.
  for State := Low(TAtlasStatusState) to High(TAtlasStatusState) do
  begin
    Registry := HealthyRegistry;
    Line(Registry, TAtlasStatusLines.ServerId, 'Server', State, '', '');
    Line(Registry, TAtlasStatusLines.IndexId, 'Index', State, '', '');
    Line(Registry, TAtlasStatusLines.DiagnosticModeId, 'Diagnosemodus: an', State, '', '');
    for Row in TAtlasWelcomeState.Rows(Registry.Items) do
    begin
      Item := Registry.Find(Row.Id);
      Assert.IsTrue(Item <> nil, Row.Id);
      Assert.AreEqual(Ord(Item.State), Ord(Row.State), Row.Id);
      Assert.AreEqual(Ord(Item.HasAction), Ord(Row.HasAction), Row.Id);
    end;
    Assert.AreEqual(Ord(TAtlasStatusSummary.Overall(Registry.Items)),
      Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(Registry.Items))), 'Gesamtampel');
  end;
end;

procedure TAtlasWelcomeStateTests.MissingLinesAreNeutralFallbacks;
var
  Rows: TAtlasStateRows;
  Row: TAtlasStateRow;
begin
  Rows := TAtlasWelcomeState.Rows(nil);
  Assert.AreEqual(5, Integer(Length(Rows)));
  for Row in Rows do
  begin
    Assert.IsFalse(Row.Present, Row.Id);
    Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(Row.State), Row.Id);
    Assert.AreEqual('', Row.Text, Row.Id);
    Assert.IsFalse(Row.HasAction, Row.Id);
  end;
  // Diagnosemodus aus: keine Zeile im Statusfeld, in der Kachel neutral.
  Rows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.IsFalse(Rows[4].Present);
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(Rows[4].State));
end;

procedure TAtlasWelcomeStateTests.BriefAndDetailFromLine;
var
  Rows: TAtlasStateRows;
begin
  Rows := TAtlasWelcomeState.Rows(HealthyRegistry.Items);
  Assert.AreEqual('Server läuft', Rows[0].Text);
  Assert.AreEqual('seit 19:02', Rows[0].Detail);
  Assert.AreEqual('Server: läuft seit 19:02', Rows[0].Hint, 'Tooltip mit dem vollen Text');
  // Ohne Kurzform: Text der Zeile, kein Zusatz.
  Assert.AreEqual('Einrichtung: vollständig (6 von 6)', Rows[3].Text);
  Assert.AreEqual('', Rows[3].Detail);
end;

procedure TAtlasWelcomeStateTests.ForeignLineWithoutBriefShowsText;
var
  Registry: IAtlasStatusRegistry;
  Rows: TAtlasStateRows;
begin
  Registry := TAtlasStatusRegistry.Create;
  Registry.Add(TPlainItem.Create('ATLAS.SETUP', 'Einrichtung: 5 von 6 erledigt', TAtlasStatusState.Yellow));
  Rows := TAtlasWelcomeState.Rows(Registry.Items);
  Assert.IsTrue(Rows[3].Present, 'Kennung ohne Groß-/Kleinschreibung');
  Assert.AreEqual('Einrichtung: 5 von 6 erledigt', Rows[3].Text);
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(Rows[3].State));
end;

procedure TAtlasWelcomeStateTests.OverallIsWorstRow;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := HealthyRegistry;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    Registry.Items))));
  Line(Registry, TAtlasStatusLines.SetupId, 'Einrichtung: 5 von 6 erledigt', TAtlasStatusState.Yellow, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    Registry.Items))));
  Line(Registry, TAtlasStatusLines.ServerId, 'Server: abgestürzt um 14:32', TAtlasStatusState.Red, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    Registry.Items))));
  // Eine rote Datei-Zeile gehört nicht zur Kachel.
  Registry := HealthyRegistry;
  Line(Registry, TAtlasStatusLines.FileId, 'Datei: gemischt', TAtlasStatusState.Red, '', '');
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasWelcomeState.Overall(TAtlasWelcomeState.Rows(
    Registry.Items))));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasWelcomeState.Overall(nil)), 'ohne Zeilen');
end;

procedure TAtlasWelcomeStateTests.AllGreenOrNeutralIsNoProblem;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := HealthyRegistry;
  Assert.IsFalse(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(Registry.Items)));
  Line(Registry, TAtlasStatusLines.ServerId, 'Server: beendet', TAtlasStatusState.Neutral, '', '');
  Assert.IsFalse(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(Registry.Items)), 'neutral');
  Line(Registry, TAtlasStatusLines.DiagnosticModeId, 'Diagnosemodus: an', TAtlasStatusState.Yellow, '', '');
  Assert.IsTrue(TAtlasWelcomeState.HasProblem(TAtlasWelcomeState.Rows(Registry.Items)), 'gelb');
end;

procedure TAtlasWelcomeStateTests.OnlyProblemsHidesTileWhenAllGreen;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := HealthyRegistry;
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, False, TAtlasWelcomeState.Rows(Registry.Items)),
    'ohne onlyProblems immer');
  Assert.IsFalse(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(Registry.Items)),
    'alles grün: unsichtbar');
  Line(Registry, TAtlasStatusLines.VersionId, 'Version: Update 1.0.1', TAtlasStatusState.Yellow, '', '');
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(Registry.Items)), 'gelb: sichtbar');
  Line(Registry, TAtlasStatusLines.VersionId, 'Version', TAtlasStatusState.Green, '', '');
  Line(Registry, TAtlasStatusLines.ServerId, 'Server: abgestürzt', TAtlasStatusState.Red, '', '');
  Assert.IsTrue(TAtlasWelcomeState.Visible(True, True, TAtlasWelcomeState.Rows(Registry.Items)), 'rot: sichtbar');
end;

procedure TAtlasWelcomeStateTests.StatusTileOffHidesTile;
var
  Registry: IAtlasStatusRegistry;
begin
  Registry := HealthyRegistry;
  Line(Registry, TAtlasStatusLines.ServerId, 'Server: abgestürzt', TAtlasStatusState.Red, '', '');
  Assert.IsFalse(TAtlasWelcomeState.Visible(False, False, TAtlasWelcomeState.Rows(Registry.Items)));
  Assert.IsFalse(TAtlasWelcomeState.Visible(False, True, TAtlasWelcomeState.Rows(Registry.Items)));
end;

procedure TAtlasWelcomeStateTests.UpdateButtonOnlyWithUpdate;
var
  Registry: IAtlasStatusRegistry;
  Buttons: TArray<TAtlasStateButton>;
begin
  Registry := HealthyRegistry;
  Buttons := TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(Registry.Items));
  Assert.AreEqual(3, Integer(Length(Buttons)));
  Assert.AreEqual(Ord(TAtlasStateButton.Restart), Ord(Buttons[0]));
  Assert.AreEqual(Ord(TAtlasStateButton.Settings), Ord(Buttons[1]));
  Assert.AreEqual(Ord(TAtlasStateButton.LogFolder), Ord(Buttons[2]));
  Assert.IsFalse(TAtlasWelcomeState.UpdateReady(TAtlasWelcomeState.Rows(Registry.Items)));
  Line(Registry, TAtlasStatusLines.VersionId, 'Version: Atlas 1.0.0, Update 1.0.1 bereit', TAtlasStatusState.Yellow,
    'Update 1.0.1 bereit', 'installiert 1.0.0');
  Buttons := TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(Registry.Items));
  Assert.AreEqual(4, Integer(Length(Buttons)));
  Assert.AreEqual(Ord(TAtlasStateButton.Update), Ord(Buttons[3]));
  // Eine gelbe Zeile anderswo ist kein Update.
  Registry := HealthyRegistry;
  Line(Registry, TAtlasStatusLines.SetupId, 'Einrichtung', TAtlasStatusState.Yellow, '', '');
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeState.Buttons(TAtlasWelcomeState.Rows(Registry.Items)))));
end;

procedure TAtlasWelcomeStateTests.SignatureChangesOnlyWithVisibleChange;
var
  Registry: IAtlasStatusRegistry;
  Before: string;
begin
  Registry := HealthyRegistry;
  Before := TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(Registry.Items));
  // Die Datei-Zeile ändert die Kachel nicht.
  Line(Registry, TAtlasStatusLines.FileId, 'Datei Main.pas: UTF-8', TAtlasStatusState.Green, '', '');
  Assert.AreEqual(Before, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(Registry.Items)));
  Line(Registry, TAtlasStatusLines.IndexId, 'Index: 1284 Units', TAtlasStatusState.Green, 'Index: 1284 Units',
    'indiziert 18:41');
  Assert.AreNotEqual(Before, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(Registry.Items)), 'Zusatz');
  Registry := HealthyRegistry;
  Line(Registry, TAtlasStatusLines.ServerId, 'Server: läuft seit 19:02', TAtlasStatusState.Yellow, 'Server läuft',
    'seit 19:02');
  Assert.AreNotEqual(Before, TAtlasWelcomeState.Signature(TAtlasWelcomeState.Rows(Registry.Items)), 'Ampel');
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
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Running;
  Info.Version := '1.0.0';
  Info.Since := Today(19, 2);
  Assert.AreEqual('Server: läuft seit 19:02, Version 1.0.0', TAtlasStatusLines.ServerText(Info, Today(20, 0)));
  Assert.AreEqual('Server läuft', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual('seit 19:02', TAtlasStatusLines.ServerDetail(Info, Today(20, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.ServerState(Info)));
  Info.Samples := 3;
  Info.AverageMs := TAtlasStatusLines.SlowMs;
  Assert.AreEqual('Server läuft langsam', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.ServerState(Info)));
end;

procedure TAtlasStateLinesTests.CrashedServerIsRedWithTime;
var
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Stopped;
  Info.Since := Today(14, 32);
  Assert.AreEqual('Server: abgestürzt um 14:32', TAtlasStatusLines.ServerText(Info, Today(15, 0)));
  Assert.AreEqual('Server abgestürzt', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual('um 14:32', TAtlasStatusLines.ServerDetail(Info, Today(15, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(Info)));
  Assert.AreEqual('Server abgestürzt', TAtlasStatusLines.ServerSummary(Info));
  // Ursache aus dem Exit-Code (Bericht H5).
  Info.Error := 'Stapelüberlauf (0xC00000FD)';
  Assert.AreEqual('Server: abgestürzt um 14:32 (Stapelüberlauf (0xC00000FD))',
    TAtlasStatusLines.ServerText(Info, Today(15, 0)));
  Assert.AreEqual('um 14:32, Stapelüberlauf (0xC00000FD)', TAtlasStatusLines.ServerDetail(Info, Today(15, 0)));
  // Von Atlas beendet: keine Ursache, auch wenn noch eine gesetzt ist.
  Info.Ended := True;
  Assert.AreEqual('Server: beendet um 14:32', TAtlasStatusLines.ServerText(Info, Today(15, 0)));
end;

procedure TAtlasStateLinesTests.EndedServerIsNeutral;
var
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Stopped;
  Info.Ended := True;
  Info.Since := Today(8, 5);
  Assert.AreEqual('Server: beendet um 08:05', TAtlasStatusLines.ServerText(Info, Today(9, 0)));
  Assert.AreEqual('Server beendet', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.ServerState(Info)));
  Assert.AreEqual('', TAtlasStatusLines.ServerSummary(Info));
end;

procedure TAtlasStateLinesTests.FailedServerShowsError;
var
  Info: TAtlasServerInfo;
begin
  Info := Default(TAtlasServerInfo);
  Info.Phase := TAtlasServerPhase.Failed;
  Info.Error := 'AtlasServer.exe nicht gefunden';
  Assert.AreEqual('Server-Start fehlgeschlagen', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual('AtlasServer.exe nicht gefunden', TAtlasStatusLines.ServerDetail(Info, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasStatusLines.ServerState(Info)));
  Info := Default(TAtlasServerInfo);
  Assert.AreEqual('Server nicht gestartet', TAtlasStatusLines.ServerBrief(Info));
  Assert.AreEqual('', TAtlasStatusLines.ServerDetail(Info, Today(9, 0)));
end;

procedure TAtlasStateLinesTests.IndexShowsLastFullIndexing;
var
  Info: TAtlasIndexInfo;
begin
  Info := Default(TAtlasIndexInfo);
  Info.Units := 1284;
  Info.Percent := -1;
  Info.FullAt := Today(18, 40);
  Assert.AreEqual('Index: 1284 Units, vollständig indiziert 18:40', TAtlasStatusLines.IndexText(Info, Today(19, 0)));
  Assert.AreEqual('Index: 1284 Units', TAtlasStatusLines.IndexBrief(Info));
  Assert.AreEqual('indiziert 18:40', TAtlasStatusLines.IndexDetail(Info, Today(19, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.IndexState(Info)));
end;

procedure TAtlasStateLinesTests.IndexWhileBuildingShowsPercent;
var
  Info: TAtlasIndexInfo;
begin
  Info := Default(TAtlasIndexInfo);
  Info.Units := -1;
  Info.Indexing := True;
  Info.Percent := 45;
  Info.FullAt := Today(18, 40);
  Assert.AreEqual('Index wird aufgebaut', TAtlasStatusLines.IndexBrief(Info));
  Assert.AreEqual('45 %', TAtlasStatusLines.IndexDetail(Info, Today(19, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.IndexState(Info)));
  Info.Percent := -1;
  Assert.AreEqual('', TAtlasStatusLines.IndexDetail(Info, Today(19, 0)));
end;

procedure TAtlasStateLinesTests.OfflineIndexShowsStoredValues;
var
  Info: TAtlasIndexInfo;
begin
  Info := Default(TAtlasIndexInfo);
  Info.Offline := True;
  Info.Units := 1284;
  Info.Percent := -1;
  Info.StoredAt := Today(17, 45) - 1;
  Assert.AreEqual('Index: 1284 Units, Stand vom 14.10. 17:45 (Server läuft nicht)',
    TAtlasStatusLines.IndexText(Info, Today(9, 0)));
  Assert.AreEqual('Index: 1284 Units', TAtlasStatusLines.IndexBrief(Info));
  Assert.AreEqual('Stand vom 14.10. 17:45', TAtlasStatusLines.IndexDetail(Info, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(Info)));
  Assert.AreEqual('', TAtlasStatusLines.IndexSummary(Info));
end;

procedure TAtlasStateLinesTests.OfflineIndexWithoutStoredValues;
var
  Info: TAtlasIndexInfo;
begin
  Info := Default(TAtlasIndexInfo);
  Info.Offline := True;
  Info.Units := -1;
  Assert.AreEqual('Index: Server läuft nicht', TAtlasStatusLines.IndexText(Info, Today(9, 0)));
  Assert.AreEqual('Index unbekannt', TAtlasStatusLines.IndexBrief(Info));
  Assert.AreEqual('Server läuft nicht', TAtlasStatusLines.IndexDetail(Info, Today(9, 0)));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.IndexState(Info)));
end;

procedure TAtlasStateLinesTests.VersionWithUpdateIsYellow;
var
  Info: TAtlasVersionInfo;
begin
  Info := Default(TAtlasVersionInfo);
  Info.Installed := '1.0.0';
  Info.Available := '1.0.1';
  Info.CheckEnabled := True;
  Info.Checked := True;
  Assert.IsTrue(TAtlasStatusLines.UpdateAvailable(Info));
  Assert.AreEqual(Ord(TAtlasStatusState.Yellow), Ord(TAtlasStatusLines.VersionState(Info)));
  Assert.AreEqual('Version: Atlas 1.0.0, Update 1.0.1 bereit', TAtlasStatusLines.VersionText(Info));
  Assert.AreEqual('Update 1.0.1 bereit', TAtlasStatusLines.VersionBrief(Info));
  Assert.AreEqual('installiert 1.0.0', TAtlasStatusLines.VersionDetail(Info));
  Assert.AreEqual('Update 1.0.1', TAtlasStatusLines.VersionSummary(Info));
end;

procedure TAtlasStateLinesTests.VersionWithoutUpdate;
var
  Info: TAtlasVersionInfo;
begin
  Info := Default(TAtlasVersionInfo);
  Info.Installed := '1.0.0';
  Info.CheckEnabled := True;
  Info.Checked := True;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasStatusLines.VersionState(Info)));
  Assert.AreEqual('Atlas 1.0.0', TAtlasStatusLines.VersionBrief(Info));
  Assert.AreEqual('aktuell', TAtlasStatusLines.VersionDetail(Info));
  Assert.AreEqual('', TAtlasStatusLines.VersionSummary(Info));
  Info.Checked := False;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.VersionState(Info)));
  Assert.AreEqual('noch nicht geprüft', TAtlasStatusLines.VersionDetail(Info));
  Info.CheckEnabled := False;
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasStatusLines.VersionState(Info)));
  Assert.AreEqual('Version: Atlas 1.0.0 (Update-Prüfung aus)', TAtlasStatusLines.VersionText(Info));
  Assert.AreEqual('Update-Prüfung aus', TAtlasStatusLines.VersionDetail(Info));
end;

procedure TAtlasStateLinesTests.LineKeepsBriefAndDetail;
var
  Registry: IAtlasStatusRegistry;
  Item: TAtlasStatusLine;
  Ref: IAtlasStatusItem;
  Brief: IAtlasStatusBrief;
  Before: Integer;
begin
  Registry := TAtlasStatusRegistry.Create;
  Item := TAtlasStatusLine.Create(Registry, 'atlas.server', 0);
  Ref := Item;
  Registry.Add(Ref);
  Item.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:02');
  Assert.IsTrue(Supports(Ref, IAtlasStatusBrief, Brief));
  Assert.AreEqual('Server läuft', Brief.Brief);
  Assert.AreEqual('seit 19:02', Brief.Detail);
  Before := Registry.Version;
  Item.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:02');
  Assert.AreEqual(Before, Registry.Version, 'nichts geändert');
  Item.Update('Server: läuft', TAtlasStatusState.Green, '', 'Server läuft', 'seit 19:03');
  Assert.AreEqual(Before + 1, Registry.Version, 'Zusatz geändert');
  // Ohne Kurzform sind beide leer.
  Item.Update('Server: läuft', TAtlasStatusState.Green);
  Assert.AreEqual('', Brief.Brief);
  Assert.AreEqual('', Brief.Detail);
  Item.Detach;
end;

{ TAtlasIndexStoreTests }

procedure TAtlasIndexStoreTests.SnapshotRoundTrip;
var
  Snapshot, Back: TAtlasIndexSnapshot;
begin
  Snapshot := TAtlasIndexSnapshot.Empty;
  Assert.IsFalse(Snapshot.Known);
  Snapshot.Units := 1284;
  Snapshot.FullAt := Today(18, 40);
  Snapshot.At := Today(19, 5);
  Assert.IsTrue(Snapshot.Known);
  Back := TAtlasIndexSnapshot.FromJson(Snapshot.ToJson);
  Assert.AreEqual(1284, Back.Units);
  Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', Snapshot.FullAt), FormatDateTime('yyyy-mm-dd hh:nn:ss',
    Back.FullAt));
  Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', Snapshot.At), FormatDateTime('yyyy-mm-dd hh:nn:ss', Back.At));
  Assert.IsTrue(Back.Known);
  // Keine Pfade und Namen in der Datei.
  Assert.IsFalse(Snapshot.ToJson.Contains('\'));
end;

procedure TAtlasIndexStoreTests.InvalidJsonIsEmpty;
var
  Back: TAtlasIndexSnapshot;
begin
  Back := TAtlasIndexSnapshot.FromJson('kein JSON');
  Assert.AreEqual(-1, Back.Units);
  Assert.IsFalse(Back.Known);
  Back := TAtlasIndexSnapshot.FromJson('{"format": 2, "units": 5, "at": "2026-10-15T10:00:00Z"}');
  Assert.AreEqual(-1, Back.Units, 'anderes Format');
  Back := TAtlasIndexSnapshot.FromJson('{"format": 1, "units": -3, "at": "Unsinn"}');
  Assert.AreEqual(-1, Back.Units);
  Assert.IsTrue(Back.At = 0);
end;

procedure TAtlasIndexStoreTests.TrackerRecordsEndOfIndexing;
var
  Tracker: TAtlasIndexTracker;
begin
  Tracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Assert.IsFalse(Tracker.Observe(True, True, -1, Today(18, 30)), 'Indizierung läuft');
    Assert.IsTrue(Tracker.Snapshot.FullAt = 0);
    Assert.IsTrue(Tracker.Observe(True, False, 1284, Today(18, 40)), 'Ende der Indizierung');
    Assert.IsTrue(Tracker.Snapshot.FullAt = Today(18, 40));
    Assert.AreEqual(1284, Tracker.Snapshot.Units);
    Assert.IsTrue(Tracker.Snapshot.At = Today(18, 40));
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerIgnoresUnitsWhileIndexing;
var
  Tracker: TAtlasIndexTracker;
begin
  Tracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Tracker.Observe(True, True, 80, Today(18, 30));
    Assert.AreEqual(-1, Tracker.Snapshot.Units, 'Zwischenstand zählt nicht');
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerSavesWhenServerStops;
var
  Tracker: TAtlasIndexTracker;
begin
  Tracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Assert.IsFalse(Tracker.Observe(False, False, -1, Today(9, 0)), 'lief nie: nichts zu sichern');
    Tracker.Observe(True, False, 1284, Today(9, 1));
    Tracker.Observe(True, False, 1284, Today(9, 30));
    Assert.IsTrue(Tracker.Observe(False, False, -1, Today(9, 31)), 'Server hört auf');
    Assert.IsTrue(Tracker.Snapshot.At = Today(9, 30), 'zuletzt bestätigt');
    Assert.IsFalse(Tracker.Observe(False, False, -1, Today(9, 32)), 'nur einmal');
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.TrackerSavesOnlyOnChange;
var
  Stored: TAtlasIndexSnapshot;
  Tracker: TAtlasIndexTracker;
begin
  Stored := TAtlasIndexSnapshot.Empty;
  Stored.Units := 1200;
  Stored.FullAt := Today(8, 0);
  Stored.At := Today(8, 30);
  Tracker := TAtlasIndexTracker.Create(Stored);
  try
    Assert.IsFalse(Tracker.Observe(True, False, -1, Today(9, 0)), 'Units noch unbekannt');
    Assert.IsFalse(Tracker.Observe(True, False, 1200, Today(9, 1)), 'unverändert');
    Assert.IsTrue(Tracker.Snapshot.At = Today(9, 1), 'Stand im Speicher nachgeführt');
    Assert.IsTrue(Tracker.Observe(True, False, 1210, Today(9, 2)), 'Units geändert');
    Assert.IsTrue(Tracker.Snapshot.FullAt = Today(8, 0), 'keine neue Indizierung');
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.InfoUsesStoredValuesOffline;
var
  Stored: TAtlasIndexSnapshot;
  Tracker: TAtlasIndexTracker;
  Info: TAtlasIndexInfo;
begin
  Stored := TAtlasIndexSnapshot.Empty;
  Stored.Units := 1284;
  Stored.FullAt := Today(8, 0);
  Stored.At := Today(8, 30);
  Tracker := TAtlasIndexTracker.Create(Stored);
  try
    Info := Tracker.Info(False, False, -1, -1);
    Assert.IsTrue(Info.Offline);
    Assert.AreEqual(1284, Info.Units);
    Assert.IsTrue(Info.StoredAt = Today(8, 30));
    Assert.AreEqual('Stand vom 08:30', TAtlasStatusLines.IndexDetail(Info, Today(9, 0)));
    Info := Tracker.Info(True, True, 45, 300);
    Assert.IsFalse(Info.Offline);
    Assert.IsTrue(Info.Indexing);
    Assert.AreEqual(45, Info.Percent);
    Assert.AreEqual(300, Info.Units);
    Assert.IsTrue(Info.FullAt = Today(8, 0), 'letzte vollständige Indizierung');
  finally
    Tracker.Free;
  end;
  Tracker := TAtlasIndexTracker.Create(TAtlasIndexSnapshot.Empty);
  try
    Info := Tracker.Info(False, False, -1, -1);
    Assert.AreEqual(-1, Info.Units, 'nichts gespeichert');
    Assert.AreEqual('Index: Server läuft nicht', TAtlasStatusLines.IndexText(Info, Today(9, 0)));
  finally
    Tracker.Free;
  end;
end;

procedure TAtlasIndexStoreTests.FileRoundTrip;
var
  Folder, FileName: string;
  Snapshot, Back: TAtlasIndexSnapshot;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-index-store-' + IntToStr(Random(MaxInt)));
  FileName := TPath.Combine(TPath.Combine(Folder, 'Atlas'), TAtlasIndexStore.FileName);
  try
    Back := TAtlasIndexStore.Load(FileName);
    Assert.AreEqual(-1, Back.Units, 'fehlende Datei');
    Snapshot := TAtlasIndexSnapshot.Empty;
    Snapshot.Units := 77;
    Snapshot.At := Today(10, 0);
    Assert.IsTrue(TAtlasIndexStore.Save(FileName, Snapshot), 'legt den Ordner an');
    Back := TAtlasIndexStore.Load(FileName);
    Assert.AreEqual(77, Back.Units);
    Assert.IsTrue(Back.Known);
  finally
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

{ TAtlasStateUpdateTests }

procedure TAtlasStateUpdateTests.RememberKeepsNewVersionAndForgetsAfterCurrent;
var
  State: TAtlasUpdateState;
  Outcome: TAtlasUpdateResult;
begin
  State := Default(TAtlasUpdateState);
  Outcome := Default(TAtlasUpdateResult);
  Outcome.Outcome := TAtlasUpdateOutcome.NewVersion;
  Outcome.Release.Version := '1.0.1';
  Outcome.Release.ChangesUrl := 'https://example.org/changes';
  TAtlasUpdates.Remember(State, Outcome);
  Assert.AreEqual('1.0.1', State.Available);
  Assert.AreEqual('https://example.org/changes', State.ChangesUrl);
  Outcome := Default(TAtlasUpdateResult);
  Outcome.Outcome := TAtlasUpdateOutcome.Failed;
  TAtlasUpdates.Remember(State, Outcome);
  Assert.AreEqual('1.0.1', State.Available, 'Fehlschlag ändert nichts');
  Outcome.Outcome := TAtlasUpdateOutcome.NotDue;
  TAtlasUpdates.Remember(State, Outcome);
  Assert.AreEqual('1.0.1', State.Available, 'nicht fällig ändert nichts');
  Outcome.Outcome := TAtlasUpdateOutcome.Current;
  TAtlasUpdates.Remember(State, Outcome);
  Assert.AreEqual('', State.Available, 'aktuell');
  Assert.AreEqual('', State.ChangesUrl);
end;

procedure TAtlasStateUpdateTests.PendingOnlyWhenNewerThanInstalled;
var
  State: TAtlasUpdateState;
  Release: TAtlasRelease;
begin
  State := Default(TAtlasUpdateState);
  Assert.IsFalse(TAtlasUpdates.Pending(State, '1.0.0', Release));
  State.Available := '1.0.1';
  State.ChangesUrl := 'https://example.org/changes';
  Assert.IsTrue(TAtlasUpdates.Pending(State, '1.0.0', Release));
  Assert.AreEqual('1.0.1', Release.Version);
  Assert.AreEqual('https://example.org/changes', Release.ChangesUrl);
  // Nach der Installation gilt das Update nicht mehr.
  Assert.IsFalse(TAtlasUpdates.Pending(State, '1.0.1', Release));
  Assert.AreEqual('', Release.Version);
  Assert.IsFalse(TAtlasUpdates.Pending(State, '1.1.0', Release));
  // Keine https-Adresse: Release-Seite der Version.
  State.ChangesUrl := 'file:///C:/x';
  Assert.IsTrue(TAtlasUpdates.Pending(State, '1.0.0', Release));
  Assert.AreEqual(TAtlasUpdates.ReleasesUrl + '/tag/v1.0.1', Release.ChangesUrl);
end;

procedure TAtlasStateUpdateTests.StateKeepsAvailableVersion;
var
  State, Back: TAtlasUpdateState;
begin
  State := Default(TAtlasUpdateState);
  State.Asked := True;
  State.Available := '1.0.1';
  State.ChangesUrl := 'https://example.org/changes';
  Back := TAtlasUpdateState.FromJson(State.ToJson);
  Assert.IsTrue(Back.Asked);
  Assert.AreEqual('1.0.1', Back.Available);
  Assert.AreEqual('https://example.org/changes', Back.ChangesUrl);
  // Ungültige Version gilt nicht; fremde Adresse wird zur Release-Seite.
  Back := TAtlasUpdateState.FromJson('{"asked": true, "available": "neu", "changes": "https://x"}');
  Assert.AreEqual('', Back.Available);
  Back := TAtlasUpdateState.FromJson('{"available": "1.2.0", "changes": "http://x"}');
  Assert.AreEqual('1.2.0', Back.Available);
  Assert.AreEqual(TAtlasUpdates.ReleasesUrl + '/tag/v1.2.0', Back.ChangesUrl);
  // Ohne gefundene Version kein Feld in der Datei.
  State.Available := '';
  Assert.IsFalse(State.ToJson.Contains('available'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateTests);
  TDUnitX.RegisterTestFixture(TAtlasStateLinesTests);
  TDUnitX.RegisterTestFixture(TAtlasIndexStoreTests);
  TDUnitX.RegisterTestFixture(TAtlasStateUpdateTests);

end.
