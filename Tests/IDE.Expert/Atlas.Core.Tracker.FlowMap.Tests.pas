unit Atlas.Core.Tracker.FlowMap.Tests;

// Tests der Ablauf-Karte (#2125) ohne Server: Lesen der Seiten von
// /api/activitiesPage und der offenen Issues (Zustandsfeld per Name, Typ
// oder üblichem Namen), Abruf über mehrere Seiten mit festem Transport,
// Auswertung (Übergänge, Rückwege, Verweildauer, Liegezeit, eigene Issues,
// Anordnung des Hauptwegs), Nachladen ab dem letzten Stand, Zusammenführen
// ohne doppelte Wechsel und Zwischenspeicher. Grundlage sind die gespeicherten
// Antworten Tests/Data/YouTrack/flow-*.json; „jetzt“ ist der 31.03.2026, 12 Uhr
// UTC, der Zeitraum 90 Tage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerFlowMapTests = class
  public
    /// <summary>Nur Wechsel des Zustandsfeldes, mit Kennung, Titel, Anlage, Werten und Cursor.</summary>
    [Test]
    procedure ParsePageKeepsStateChanges;
    /// <summary>Zustandsfeld per Name, sonst am Typ "state[…]", ohne Typ an den üblichen Namen.</summary>
    [Test]
    procedure StateFieldDetection;
    /// <summary>Offene Issues: Zustand aus State- bzw. StateMachine-Feld, Zuständig, Anlage.</summary>
    [Test]
    procedure ParseOpenIssues;
    /// <summary>Adressen: Projekt, Beginn in Millisekunden, Cursor; ohne Projekt keine.</summary>
    [Test]
    procedure Urls;
    /// <summary>Zwei Seiten Wechsel, offene und meine Issues über den Transport.</summary>
    [Test]
    procedure LoadFlowFollowsCursor;
    /// <summary>Ohne Antwort auf die erste Abfrage keine Daten, der Fehler aus dem Status.</summary>
    [Test]
    procedure LoadFlowFailsWithoutAccess;
    /// <summary>Übergänge mit Anzahl, Rückweg im Hauptweg, Anordnung.</summary>
    [Test]
    procedure BuildTransitions;
    /// <summary>Mittlere Verweildauer aus abgeschlossenen Aufenthalten; erster nur bei Anlage im Zeitraum.</summary>
    [Test]
    procedure BuildDwellTimes;
    /// <summary>Liegt lange: seit dem letzten Wechsel, der Anlage bzw. dem Beginn des Zeitraums; erledigte nicht.
    /// </summary>
    [Test]
    procedure BuildStuckIssues;
    /// <summary>Offene, eigene und liegen gebliebene Issues je Zustand, Summen.</summary>
    [Test]
    procedure BuildCounts;
    /// <summary>Ohne Wechsel stehen alle Zustände in der ersten Zeile.</summary>
    [Test]
    procedure BuildWithoutChanges;
    /// <summary>Nachladen ab dem letzten Stand nur bei passendem, vollständigem Stand.</summary>
    [Test]
    procedure SinceUsesMatchingCache;
    /// <summary>Doppelte Wechsel nur einmal, ältere als der Zeitraum fallen weg.</summary>
    [Test]
    procedure MergeDropsDuplicatesAndOldChanges;
    [Test]
    procedure JsonRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Adapters.LocalFiles,
  Atlas.Core.Tracker.FlowMap,
  Atlas.Core.Tracker.YouTrackFlow;

const
  cDelta = 0.001;
  cServer = 'https://firma.youtrack.cloud';

type
  /// <summary>Transport mit festen Antworten je Adressteil; merkt sich alle Anfragen.</summary>
  TFakeFlowTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FParts: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
  public
    Calls: TArray<string>;
    /// <summary>Antwort für Adressen, die APart enthalten (erste passende gilt).</summary>
    procedure Answer(const APart: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TFakeFlowTransport.Answer(const APart: string; AStatus: Integer; const AText: string);
begin
  FParts := FParts + [APart];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeFlowTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AError := TAtlasCiFetchError.None;
  AStatus := 404;
  AText := '';
  for mIndex := 0 to High(FParts) do
  begin
    if Pos(FParts[mIndex], AUrl) > 0 then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Break;
    end;
  end;
  Result := True;
end;

/// <summary>Datei aus Tests\Data\YouTrack, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('YouTrack', AName))));
    if TFile.Exists(mFileName) then
    begin
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise EFileNotFoundException.Create('Tests\Data\YouTrack\' + AName + ' nicht gefunden');
end;

function Day(AMonth, ADay: Word): TDateTime;
begin
  Result := EncodeDateTime(2026, AMonth, ADay, 12, 0, 0, 0);
end;

function NowUtc: TDateTime;
begin
  Result := Day(3, 31);
end;

function Target: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack, cServer, 'ATL', '');
end;

/// <summary>Daten aus den gespeicherten Antworten wie nach LoadFlow.</summary>
function FixtureData: TAtlasFlowData;
var
  mPage: TAtlasYouTrackFlowPage;
  mKeys: TArray<string>;
  mIndex: Integer;
begin
  Result := TAtlasFlowData.Empty;
  Result.Days := 90;
  Result.Fetched := NowUtc;
  Assert.IsTrue(TAtlasYouTrackFlow.ParsePage(Fixture('flow-activities-1.json'), '', mPage));
  Result.Changes := mPage.Changes;
  Result.Resolved := mPage.Resolved;
  Assert.IsTrue(TAtlasYouTrackFlow.ParsePage(Fixture('flow-activities-2.json'), '', mPage));
  Result.Changes := Result.Changes + mPage.Changes;
  Assert.IsTrue(TAtlasYouTrackFlow.ParseOpen(Fixture('flow-open.json'), '', Result.Open));
  Assert.IsTrue(TAtlasYouTrackFlow.ParseKeys(Fixture('flow-mine.json'), mKeys));
  for mIndex := 0 to High(Result.Open) do
  begin
    Result.Open[mIndex].Mine := Result.Open[mIndex].Key = mKeys[0];
  end;
end;

function FixtureMap: TAtlasFlowMap;
begin
  Result := TAtlasFlowMap.Build(FixtureData, NowUtc, 5);
end;

function TransitionCount(const AMap: TAtlasFlowMap; const AFrom, ATo: string; out ABack: Boolean): Integer;
var
  mTransition: TAtlasFlowTransition;
begin
  Result := 0;
  ABack := False;
  for mTransition in AMap.Transitions do
  begin
    if SameText(AMap.States[mTransition.FromIndex].Name, AFrom) and SameText(AMap.States[mTransition.ToIndex].Name,
      ATo) then
    begin
      ABack := mTransition.Back;
      Exit(mTransition.Count);
    end;
  end;
end;

function StateOf(const AMap: TAtlasFlowMap; const AName: string): TAtlasFlowState;
var
  mIndex: Integer;
begin
  mIndex := AMap.IndexOf(AName);
  Assert.IsTrue(mIndex >= 0, AName + ' fehlt');
  Result := AMap.States[mIndex];
end;

{ TAtlasTrackerFlowMapTests }

procedure TAtlasTrackerFlowMapTests.ParsePageKeepsStateChanges;
var
  mPage: TAtlasYouTrackFlowPage;
begin
  Assert.IsTrue(TAtlasYouTrackFlow.ParsePage(Fixture('flow-activities-1.json'), '', mPage));
  // Zuständig und Priorität fallen weg.
  Assert.AreEqual(Integer(5), Integer(Length(mPage.Changes)));
  Assert.AreEqual('1-1', mPage.Changes[0].Id);
  Assert.AreEqual('ATL-1', mPage.Changes[0].Key);
  Assert.AreEqual('Hover zeigt Signatur doppelt', mPage.Changes[0].Title);
  Assert.AreEqual('Offen', mPage.Changes[0].FromState);
  Assert.AreEqual('In Bearbeitung', mPage.Changes[0].ToState);
  Assert.AreEqual(Day(3, 3), mPage.Changes[0].Time, cDelta);
  Assert.AreEqual(Day(3, 1), mPage.Changes[0].Created, cDelta);
  Assert.IsTrue(mPage.HasMore);
  Assert.AreEqual('AI.2-1', mPage.Cursor);
  Assert.AreEqual(Integer(1), Integer(Length(mPage.Resolved)));
  Assert.AreEqual('Behoben', mPage.Resolved[0]);
  Assert.IsTrue(TAtlasYouTrackFlow.ParsePage(Fixture('flow-activities-2.json'), '', mPage));
  Assert.IsFalse(mPage.HasMore);
  Assert.IsFalse(TAtlasYouTrackFlow.ParsePage('[]', '', mPage));
end;

function FieldJson(const AText: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AText) as TJSONObject;
end;

procedure TAtlasTrackerFlowMapTests.StateFieldDetection;
var
  mField: TJSONObject;
begin
  mField := FieldJson('{"name": "Phase", "customField": {"fieldType": {"id": "state[1]"}}}');
  try
    Assert.IsTrue(TAtlasYouTrackFlow.IsStateField(mField, ''), 'am Typ');
    Assert.IsTrue(TAtlasYouTrackFlow.IsStateField(mField, 'phase'), 'per Name');
    Assert.IsTrue(TAtlasYouTrackFlow.IsStateField(mField, 'State'), 'Vorgabe passt nicht: Typ entscheidet');
  finally
    mField.Free;
  end;
  mField := FieldJson('{"name": "Status", "customField": {"fieldType": {"id": "enum[1]"}}}');
  try
    Assert.IsFalse(TAtlasYouTrackFlow.IsStateField(mField, ''), 'Typ verrät ein anderes Feld');
  finally
    mField.Free;
  end;
  mField := FieldJson('{"name": "Zustand"}');
  try
    Assert.IsTrue(TAtlasYouTrackFlow.IsStateField(mField, ''), 'üblicher Name ohne Typ');
  finally
    mField.Free;
  end;
  Assert.IsFalse(TAtlasYouTrackFlow.IsStateField(nil, ''));
end;

procedure TAtlasTrackerFlowMapTests.ParseOpenIssues;
var
  mIssues: TArray<TAtlasFlowIssue>;
begin
  Assert.IsTrue(TAtlasYouTrackFlow.ParseOpen(Fixture('flow-open.json'), '', mIssues));
  Assert.AreEqual(Integer(4), Integer(Length(mIssues)));
  Assert.AreEqual('ATL-2', mIssues[0].Key);
  Assert.AreEqual('Zur Prüfung', mIssues[0].State);
  Assert.AreEqual('Marco B.', mIssues[0].Assignee);
  Assert.AreEqual(EncodeDateTime(2025, 11, 1, 12, 0, 0, 0), mIssues[0].Created, cDelta);
  Assert.AreEqual('', mIssues[1].Assignee);
  // StateMachineIssueCustomField zählt als Zustandsfeld.
  Assert.AreEqual('Zurückgestellt', mIssues[2].State);
  // Der Name aus der Einstellung geht vor; passt er zu keinem Feld, entscheidet der Typ.
  Assert.IsTrue(TAtlasYouTrackFlow.ParseOpen(Fixture('flow-open.json'), 'Priority', mIssues));
  Assert.AreEqual('Normal', mIssues[0].State);
  Assert.IsTrue(TAtlasYouTrackFlow.ParseOpen(Fixture('flow-open.json'), 'State', mIssues));
  Assert.AreEqual(Integer(4), Integer(Length(mIssues)));
  Assert.AreEqual('Zur Prüfung', mIssues[0].State);
end;

procedure TAtlasTrackerFlowMapTests.Urls;
var
  mUrl: string;
  mTarget: TAtlasTrackerTarget;
begin
  mUrl := TAtlasYouTrackFlow.ActivitiesUrl(Target, EncodeDateTime(2026, 1, 1, 0, 0, 0, 0), '');
  Assert.IsTrue(mUrl.StartsWith(cServer + '/api/activitiesPage?categories=CustomFieldCategory&issueQuery=project'),
    mUrl);
  Assert.IsTrue(Pos('ATL', mUrl) > 0, mUrl);
  Assert.IsTrue(Pos('&start=1767225600000', mUrl) > 0, mUrl);
  Assert.IsTrue(Pos('&$top=400', mUrl) > 0, mUrl);
  Assert.AreEqual(0, Pos('cursor=', mUrl), mUrl);
  mUrl := TAtlasYouTrackFlow.ActivitiesUrl(Target, 0, 'AI.2-1');
  Assert.IsTrue(Pos('&cursor=AI.2-1', mUrl) > 0, mUrl);
  mUrl := TAtlasYouTrackFlow.OpenUrl(Target, 500, False);
  Assert.IsTrue(mUrl.StartsWith(cServer + '/api/issues?query='), mUrl);
  Assert.IsTrue(Pos('Unresolved', mUrl) > 0, mUrl);
  Assert.IsTrue(Pos('&$skip=500', mUrl) > 0, mUrl);
  Assert.IsTrue(Pos('for%3A%20me', TAtlasYouTrackFlow.OpenUrl(Target, 0, True)) > 0);
  Assert.AreEqual('project: {Mein Projekt}', TAtlasYouTrackFlow.ProjectQuery(TAtlasTrackerTarget.Create(
    TAtlasTrackerTarget.cYouTrack, cServer, 'Mein Projekt', '')));
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack, cServer, '', '');
  Assert.AreEqual('', TAtlasYouTrackFlow.ActivitiesUrl(mTarget, 0, ''));
  Assert.AreEqual('', TAtlasYouTrackFlow.OpenUrl(mTarget, 0, False));
end;

procedure TAtlasTrackerFlowMapTests.LoadFlowFollowsCursor;
var
  mTransport: TFakeFlowTransport;
  mKeep: IAtlasCiTransport;
  mFlow: IAtlasTrackerFlow;
  mData: TAtlasFlowData;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeFlowTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('cursor=AI.2-1', 200, Fixture('flow-activities-2.json'));
  mTransport.Answer('/api/activitiesPage', 200, Fixture('flow-activities-1.json'));
  mTransport.Answer('for%3A%20me', 200, Fixture('flow-mine.json'));
  mTransport.Answer('/api/issues?', 200, Fixture('flow-open.json'));
  mFlow := TAtlasYouTrackFlow.Create;
  Assert.IsTrue(mFlow.LoadFlow(TAtlasFlowRequest.Create(Target, mKeep, '', Day(1, 1), 10000), mData, mError));
  Assert.AreEqual(Integer(8), Integer(Length(mData.Changes)));
  Assert.AreEqual(Integer(4), Integer(Length(mData.Open)));
  Assert.IsTrue(mData.Open[3].Mine, 'ATL-5 ist meins');
  Assert.IsFalse(mData.Open[0].Mine);
  Assert.IsFalse(mData.Truncated);
  // Offene Issues, meine, zwei Seiten Wechsel.
  Assert.AreEqual(Integer(4), Integer(Length(mTransport.Calls)));
end;

procedure TAtlasTrackerFlowMapTests.LoadFlowFailsWithoutAccess;
var
  mTransport: TFakeFlowTransport;
  mKeep: IAtlasCiTransport;
  mFlow: IAtlasTrackerFlow;
  mData: TAtlasFlowData;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeFlowTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('/api/', 401, '{"error": "Unauthorized"}');
  mFlow := TAtlasYouTrackFlow.Create;
  Assert.IsFalse(mFlow.LoadFlow(TAtlasFlowRequest.Create(Target, mKeep, '', Day(1, 1), 10000), mData, mError));
  Assert.AreEqual(Ord(TAtlasCiFetchError.Unauthorized), Ord(mError));
  Assert.AreEqual(Integer(1), Integer(Length(mTransport.Calls)));
  Assert.IsFalse(mFlow.LoadFlow(TAtlasFlowRequest.Create(Target, nil, '', Day(1, 1), 10000), mData, mError));
  Assert.AreEqual(Ord(TAtlasCiFetchError.NotConfigured), Ord(mError));
end;

procedure TAtlasTrackerFlowMapTests.BuildTransitions;
var
  mMap: TAtlasFlowMap;
  mBack: Boolean;
  mRow: TArray<Integer>;
begin
  mMap := FixtureMap;
  Assert.AreEqual(3, TransitionCount(mMap, 'Offen', 'In Bearbeitung', mBack));
  Assert.IsFalse(mBack);
  Assert.AreEqual(3, TransitionCount(mMap, 'In Bearbeitung', 'Zur Prüfung', mBack));
  Assert.AreEqual(1, TransitionCount(mMap, 'Zur Prüfung', 'Behoben', mBack));
  Assert.AreEqual(1, TransitionCount(mMap, 'Zur Prüfung', 'In Bearbeitung', mBack));
  Assert.IsTrue(mBack, 'zurück nach links');
  Assert.AreEqual(Integer(4), Integer(Length(mMap.Transitions)));
  Assert.AreEqual(3, mMap.MaxCount);
  // Hauptweg von links nach rechts, der Rest darunter.
  mRow := mMap.RowStates(0);
  Assert.AreEqual(Integer(4), Integer(Length(mRow)));
  Assert.AreEqual('Offen', mMap.States[mRow[0]].Name);
  Assert.AreEqual('In Bearbeitung', mMap.States[mRow[1]].Name);
  Assert.AreEqual('Zur Prüfung', mMap.States[mRow[2]].Name);
  Assert.AreEqual('Behoben', mMap.States[mRow[3]].Name);
  mRow := mMap.RowStates(1);
  Assert.AreEqual(Integer(1), Integer(Length(mRow)));
  Assert.AreEqual('Zurückgestellt', mMap.States[mRow[0]].Name);
  Assert.IsTrue(StateOf(mMap, 'Behoben').Resolved);
  Assert.IsFalse(StateOf(mMap, 'Offen').Resolved);
end;

procedure TAtlasTrackerFlowMapTests.BuildDwellTimes;
var
  mMap: TAtlasFlowMap;
begin
  mMap := FixtureMap;
  // Offen: ATL-1 zwei Tage, ATL-5 drei Tage; ATL-2 wurde vor dem Zeitraum angelegt.
  Assert.AreEqual(2, StateOf(mMap, 'Offen').Stays);
  Assert.AreEqual(2.5, StateOf(mMap, 'Offen').AverageDays, cDelta);
  // In Bearbeitung: 2 + 2 + 1 Tage (Rückweg von ATL-2 eingeschlossen).
  Assert.AreEqual(3, StateOf(mMap, 'In Bearbeitung').Stays);
  Assert.AreEqual(5 / 3, StateOf(mMap, 'In Bearbeitung').AverageDays, cDelta);
  Assert.AreEqual(3.0, StateOf(mMap, 'Zur Prüfung').AverageDays, cDelta);
  Assert.AreEqual(-1.0, StateOf(mMap, 'Behoben').AverageDays, cDelta);
end;

procedure TAtlasTrackerFlowMapTests.BuildStuckIssues;
var
  mMap: TAtlasFlowMap;
  mStuck: TArray<TAtlasFlowStuck>;
begin
  mMap := FixtureMap;
  Assert.AreEqual(Integer(3), Integer(Length(mMap.Stuck)));
  // Längste zuerst: ATL-4 vor dem Zeitraum, ATL-2 seit dem letzten Wechsel, ATL-3 seit der Anlage.
  Assert.AreEqual('ATL-4', mMap.Stuck[0].Key);
  Assert.IsTrue(mMap.Stuck[0].Before);
  Assert.AreEqual(90, mMap.Stuck[0].Days);
  Assert.AreEqual('ATL-2', mMap.Stuck[1].Key);
  Assert.AreEqual('Zur Prüfung', mMap.Stuck[1].State);
  Assert.AreEqual(16, mMap.Stuck[1].Days);
  Assert.AreEqual(Day(3, 15), mMap.Stuck[1].Since, cDelta);
  Assert.AreEqual('Marco B.', mMap.Stuck[1].Assignee);
  Assert.IsFalse(mMap.Stuck[1].Before);
  Assert.AreEqual('ATL-3', mMap.Stuck[2].Key);
  Assert.AreEqual(11, mMap.Stuck[2].Days);
  // ATL-5 steht erst drei Tage: nicht dabei; mit einem Tag Grenze schon.
  Assert.AreEqual(Integer(4), Integer(Length(TAtlasFlowMap.Build(FixtureData, NowUtc, 1).Stuck)));
  mStuck := mMap.StuckIn('zur prüfung');
  Assert.AreEqual(Integer(1), Integer(Length(mStuck)));
  Assert.AreEqual('ATL-2', mStuck[0].Key);
  Assert.AreEqual(Integer(3), Integer(Length(mMap.StuckIn(''))));
end;

procedure TAtlasTrackerFlowMapTests.BuildCounts;
var
  mMap: TAtlasFlowMap;
begin
  mMap := FixtureMap;
  Assert.AreEqual(5, mMap.IssueCount);
  Assert.AreEqual(8, mMap.ChangeCount);
  Assert.AreEqual(90, mMap.Days);
  Assert.AreEqual(1, StateOf(mMap, 'In Bearbeitung').OpenCount);
  Assert.AreEqual(1, StateOf(mMap, 'In Bearbeitung').MineCount);
  Assert.AreEqual(0, StateOf(mMap, 'In Bearbeitung').StuckCount);
  Assert.AreEqual(1, StateOf(mMap, 'Zur Prüfung').StuckCount);
  Assert.AreEqual(0, StateOf(mMap, 'Zur Prüfung').MineCount);
  Assert.AreEqual(1, StateOf(mMap, 'Zurückgestellt').StuckCount);
  Assert.AreEqual(0, StateOf(mMap, 'Behoben').OpenCount);
end;

procedure TAtlasTrackerFlowMapTests.BuildWithoutChanges;
var
  mData: TAtlasFlowData;
  mMap: TAtlasFlowMap;
  mRow: TArray<Integer>;
begin
  mData := FixtureData;
  mData.Changes := nil;
  mMap := TAtlasFlowMap.Build(mData, NowUtc, 5);
  Assert.AreEqual(Integer(0), Integer(Length(mMap.Transitions)));
  mRow := mMap.RowStates(0);
  Assert.AreEqual(Integer(4), Integer(Length(mRow)));
  Assert.AreEqual(Integer(0), Integer(Length(mMap.RowStates(1))));
  Assert.AreEqual(4, mMap.IssueCount);
  // Ohne Wechsel im Zeitraum: seit der Anlage bzw. dem Beginn des Zeitraums. ATL-5 liegt ohne seinen
  // Wechsel seit der Anlage vor sechs Tagen.
  Assert.AreEqual(Integer(4), Integer(Length(mMap.Stuck)));
end;

procedure TAtlasTrackerFlowMapTests.SinceUsesMatchingCache;
var
  mCached: TAtlasFlowData;
  mWindow: TDateTime;
begin
  mWindow := TAtlasTrackerFlow.WindowStart(NowUtc, 90);
  Assert.AreEqual(NowUtc - 90, mWindow, cDelta);
  mCached := TAtlasFlowData.Empty;
  mCached.Days := 90;
  mCached.Fetched := Day(3, 30);
  Assert.AreEqual(Day(3, 30) - 10 / MinsPerDay, TAtlasTrackerFlow.SinceOf(mCached, True, NowUtc, 90, ''), cDelta);
  Assert.AreEqual(mWindow, TAtlasTrackerFlow.SinceOf(mCached, False, NowUtc, 90, ''), cDelta, 'ohne Stand');
  Assert.AreEqual(NowUtc - 30, TAtlasTrackerFlow.SinceOf(mCached, True, NowUtc, 30, ''), cDelta, 'anderer Zeitraum');
  Assert.AreEqual(mWindow, TAtlasTrackerFlow.SinceOf(mCached, True, NowUtc, 90, 'Phase'), cDelta, 'anderes Feld');
  mCached.Truncated := True;
  Assert.AreEqual(mWindow, TAtlasTrackerFlow.SinceOf(mCached, True, NowUtc, 90, ''), cDelta, 'unvollständig');
  mCached.Truncated := False;
  mCached.Fetched := NowUtc - 100;
  Assert.AreEqual(mWindow, TAtlasTrackerFlow.SinceOf(mCached, True, NowUtc, 90, ''), cDelta, 'zu alt');
end;

procedure TAtlasTrackerFlowMapTests.MergeDropsDuplicatesAndOldChanges;
var
  mOld, mNew, mMerged: TAtlasFlowData;
begin
  mOld := TAtlasFlowData.Empty;
  mOld.Days := 90;
  mOld.Changes := [TAtlasFlowChange.Create('a', 'ATL-1', NowUtc - 100, 'Offen', 'Fertig'),
    TAtlasFlowChange.Create('b', 'ATL-1', Day(3, 1), 'Offen', 'In Bearbeitung'),
    TAtlasFlowChange.Create('c', 'ATL-2', Day(3, 2), 'Offen', 'In Bearbeitung')];
  mOld.Open := [TAtlasFlowIssue.Create('ATL-9', 'alt', 'Offen')];
  mNew := TAtlasFlowData.Empty;
  mNew.Days := 90;
  mNew.Changes := [TAtlasFlowChange.Create('c', 'ATL-2', Day(3, 2), 'Offen', 'In Bearbeitung'),
    TAtlasFlowChange.Create('d', 'ATL-2', Day(3, 30), 'In Bearbeitung', 'Fertig')];
  mNew.Open := [TAtlasFlowIssue.Create('ATL-3', 'neu', 'Offen')];
  mMerged := TAtlasTrackerFlow.Merge(mOld, mNew, True, NowUtc);
  Assert.AreEqual(Integer(3), Integer(Length(mMerged.Changes)), 'a zu alt, c nur einmal');
  Assert.AreEqual('b', mMerged.Changes[0].Id);
  Assert.AreEqual('d', mMerged.Changes[2].Id);
  Assert.AreEqual(Integer(1), Integer(Length(mMerged.Open)));
  Assert.AreEqual('ATL-3', mMerged.Open[0].Key);
  mMerged := TAtlasTrackerFlow.Merge(mOld, mNew, False, NowUtc);
  Assert.AreEqual(Integer(2), Integer(Length(mMerged.Changes)), 'ohne alten Stand');
end;

procedure TAtlasTrackerFlowMapTests.JsonRoundTrip;
var
  mData, mLoaded: TAtlasFlowData;
  mFolder: string;
begin
  mData := FixtureData;
  mData.StateField := 'Zustand';
  mData.Truncated := True;
  Assert.IsTrue(TAtlasTrackerFlow.FromJson(TAtlasTrackerFlow.ToJson(mData), mLoaded), 'lesen');
  Assert.AreEqual(Integer(Length(mData.Changes)), Integer(Length(mLoaded.Changes)));
  Assert.AreEqual(Integer(Length(mData.Open)), Integer(Length(mLoaded.Open)));
  Assert.AreEqual(mData.Changes[0].Id, mLoaded.Changes[0].Id);
  Assert.AreEqual(mData.Changes[0].Title, mLoaded.Changes[0].Title);
  Assert.AreEqual(mData.Changes[0].Time, mLoaded.Changes[0].Time, cDelta);
  Assert.AreEqual(mData.Changes[0].Created, mLoaded.Changes[0].Created, cDelta);
  Assert.AreEqual(mData.Open[3].Mine, mLoaded.Open[3].Mine);
  Assert.AreEqual(mData.Open[0].Assignee, mLoaded.Open[0].Assignee);
  Assert.AreEqual('Behoben', mLoaded.Resolved[0]);
  Assert.AreEqual('Zustand', mLoaded.StateField);
  Assert.AreEqual(90, mLoaded.Days);
  Assert.IsTrue(mLoaded.Truncated, 'unvollständig');
  Assert.IsFalse(TAtlasTrackerFlow.FromJson('{"version": 0}', mLoaded), 'andere Version');
  Assert.IsFalse(TAtlasTrackerFlow.FromJson('kaputt', mLoaded));
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasFlowTests' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  // Dateizugriff wie im Modul (Composition): ohne Adapter schreibt und liest der Zwischenspeicher nichts.
  TAtlasTrackerFiles.Install(TAtlasTrackerLocalFiles.Create, nil);
  try
    TAtlasTrackerFlow.Save(mFolder, Target, mData);
    Assert.IsTrue(TAtlasTrackerFlow.Load(mFolder, Target, mLoaded), 'laden');
    Assert.AreEqual(Integer(Length(mData.Changes)), Integer(Length(mLoaded.Changes)));
  finally
    TAtlasTrackerFiles.Uninstall;
    TDirectory.Delete(mFolder, True);
  end;
end;

end.
