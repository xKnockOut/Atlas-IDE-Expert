unit Atlas.Core.Tracker.Board.Tests;

// Tests des Boards (#1272) ohne Server: Kürzel, Prioritätsstufen, Filter
// „Nur meine“ und Suche, Zuordnung Zustand → Spalte, Verschieben erlaubt,
// aktueller Sprint, Zwischenspeicher; Abbildung der Board- und
// Sprint-Antworten von YouTrack und GitHub (GraphQL, REST) aus Beispieldateien
// (Tests\Data\YouTrack, Tests\Data\GitHub) und das Verschieben gegen einen
// Transport mit festen Antworten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerBoardTests = class
  public
    [Test]
    procedure InitialsFromNames;
    [Test]
    procedure PriorityLevels;
    /// <summary>Zustände ohne Groß-/Kleinschreibung, mehrere Werte je Spalte, ohne Spalte -1.</summary>
    [Test]
    procedure ColumnOfState;
    /// <summary>„Nur meine“ nach Anmeldenamen; ohne bekannten Namen filtert es nicht.</summary>
    [Test]
    procedure VisibleFiltersMineAndSearch;
    [Test]
    procedure CanMoveOnlyToOtherColumnWithValue;
    [Test]
    procedure CurrentSprintContainsNow;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure CacheSavesAndLoads;
  end;

  [TestFixture]
  TAtlasYouTrackBoardTests = class
  public
    /// <summary>Board zum Projekt des Ziels, Spalten mit deutschen Werten wie auf dem Server.</summary>
    [Test]
    procedure AgilesChooseBoardOfProject;
    [Test]
    procedure AgilesChooseBoardById;
    /// <summary>Karten: Spalte, Kürzel, Farbe, Checkliste (#1273), Schloss (#1279).</summary>
    [Test]
    procedure SprintCardsFromFixture;
    [Test]
    procedure LoadBoardAsksAgilesSprintsSprintAndMe;
    [Test]
    procedure LoadBoardWithoutBoardIsNotFound;
    /// <summary>Verschieben ist ein Befehl mit Spaltenfeld, erstem Wert der Zielspalte und Kommentar.</summary>
    [Test]
    procedure MoveSendsCommand;
    [Test]
    procedure MoveWithoutRightsFailsWithReason;
  end;

  [TestFixture]
  TAtlasGitHubBoardTests = class
  public
    [Test]
    procedure GraphQlUrlForGitHubAndEnterprise;
    [Test]
    procedure ProjectsOpenFirstWithViewer;
    /// <summary>Spalten aus „Status“, aktuelle Iteration, nur Issues, fremdes Repository mit Präfix.</summary>
    [Test]
    procedure ProjectCardsFromFixture;
    [Test]
    procedure MissingScopesAreUnauthorized;
    [Test]
    procedure LoadBoardWithProject;
    /// <summary>Ohne Projekt: Spalten Offen/Geschlossen aus /issues, ohne Pull Requests.</summary>
    [Test]
    procedure LoadBoardWithoutProjectUsesIssues;
    /// <summary>Token ohne „read:project“: Offen/Geschlossen mit ProjectsDenied statt Fehler.</summary>
    [Test]
    procedure LoadBoardWithoutProjectScopeFallsBack;
    [Test]
    procedure MoveInProjectSetsOption;
    /// <summary>Ohne Projekt: Kommentar zuerst, dann PATCH state.</summary>
    [Test]
    procedure MoveWithoutProjectClosesIssue;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Providers.YouTrackBoard,
  Atlas.Core.Tracker.Providers.GitHubBoard;

type
  /// <summary>Transport mit festen Antworten je Adressanfang (GET) bzw. Adressanfang und Textstück im Inhalt
  /// (Send); merkt sich alle Anfragen.</summary>
  TFakeBoardTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FPrefixes: TArray<string>;
    FParts: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Find(const AUrl, ABody: string; out AStatus: Integer; out AText: string): Boolean;
  public
    Calls: TArray<string>;
    Methods: TArray<string>;
    Bodies: TArray<string>;
    /// <summary>Antwort für Adressen mit APrefix; APart ('' = jeder) muss im Inhalt stehen.</summary>
    procedure Answer(const APrefix, APart: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TFakeBoardTransport.Answer(const APrefix, APart: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FParts := FParts + [APart];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeBoardTransport.Find(const AUrl, ABody: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  AStatus := 404;
  AText := '';
  for mIndex := 0 to High(FPrefixes) do
    if (Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex]) and
      ((FParts[mIndex] = '') or (Pos(FParts[mIndex], ABody) > 0)) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit(True);
    end;
  Result := False;
end;

function TFakeBoardTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Calls := Calls + [AUrl];
  Methods := Methods + ['GET'];
  Bodies := Bodies + [''];
  AError := TAtlasCiFetchError.None;
  Find(AUrl, '', AStatus, AText);
  Result := True;
end;

function TFakeBoardTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  Calls := Calls + [AUrl];
  Methods := Methods + [AMethod];
  Bodies := Bodies + [ABody];
  AError := TAtlasCiFetchError.None;
  Find(AUrl, ABody, AStatus, AText);
  Result := True;
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

/// <summary>Text des Feldes AName im JSON-Objekt AJson; '' ohne.</summary>
function JsonText(const AJson, AName: string): string;
var
  mValue, mItem: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      mItem := TJSONObject(mValue).Values[AName];
      if mItem <> nil then
        Result := mItem.Value;
    end;
  finally
    mValue.Free;
  end;
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://firma.youtrack.cloud', 'ATL', '');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function Card(const AKey, AState: string; const ALogins: TArray<string>): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.Title := 'Titel ' + AKey;
  Result.State := AState;
  Result.Logins := ALogins;
end;

function Sample: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Offen', 'Nachgefragt'), '', False),
    TAtlasBoardColumn.Create('In Arbeit', TArray<string>.Create('In Arbeit'), '', False),
    TAtlasBoardColumn.Create('Leer', nil, '', False)];
  Result.Cards := [Card('ATL-1', 'offen', TArray<string>.Create('marco')),
    Card('ATL-2', 'In Arbeit', TArray<string>.Create('anna')), Card('ATL-3', 'Verworfen', nil)];
  Result.Me := 'Marco';
end;

{ TAtlasTrackerBoardTests }

procedure TAtlasTrackerBoardTests.InitialsFromNames;
begin
  Assert.AreEqual('MB', TAtlasTrackerBoard.Initials('Marco Bähring'));
  Assert.AreEqual('AN', TAtlasTrackerBoard.Initials('anna'));
  Assert.AreEqual('MB', TAtlasTrackerBoard.Initials('marco.baehring'));
  Assert.AreEqual('MB', TAtlasTrackerBoard.Initials('Marco B. (mb)'));
  Assert.AreEqual('ÄS', TAtlasTrackerBoard.Initials('Ärzte Schmidt'));
  Assert.AreEqual('', TAtlasTrackerBoard.Initials('  '));
end;

procedure TAtlasTrackerBoardTests.PriorityLevels;
begin
  Assert.AreEqual(4, TAtlasTrackerBoard.PriorityLevel('Kritisch'));
  Assert.AreEqual(4, TAtlasTrackerBoard.PriorityLevel('Show-stopper'));
  Assert.AreEqual(3, TAtlasTrackerBoard.PriorityLevel('major'));
  Assert.AreEqual(3, TAtlasTrackerBoard.PriorityLevel('priority:high'));
  Assert.AreEqual(2, TAtlasTrackerBoard.PriorityLevel('P2'));
  Assert.AreEqual(1, TAtlasTrackerBoard.PriorityLevel('Niedrig'));
  Assert.AreEqual(0, TAtlasTrackerBoard.PriorityLevel('Irgendwas'));
end;

procedure TAtlasTrackerBoardTests.ColumnOfState;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := Sample;
  Assert.AreEqual(0, mSnapshot.ColumnOf('Nachgefragt'));
  Assert.AreEqual(0, mSnapshot.ColumnOf(' OFFEN '));
  Assert.AreEqual(1, mSnapshot.ColumnOf('In Arbeit'));
  Assert.AreEqual(-1, mSnapshot.ColumnOf('Verworfen'));
  Assert.AreEqual(-1, mSnapshot.ColumnOf(''));
  Assert.AreEqual(0, mSnapshot.CardColumn(0));
  Assert.AreEqual(-1, mSnapshot.CardColumn(2));
  Assert.AreEqual(-1, mSnapshot.CardColumn(7));
  Assert.AreEqual(1, mSnapshot.CardIndex('atl-2'));
  Assert.AreEqual(-1, mSnapshot.CardIndex('ATL-9'));
end;

procedure TAtlasTrackerBoardTests.VisibleFiltersMineAndSearch;
var
  mSnapshot: TAtlasBoardSnapshot;
  mVisible: TArray<Integer>;
begin
  mSnapshot := Sample;
  mVisible := TAtlasTrackerBoard.Visible(mSnapshot, True, '');
  Assert.AreEqual(Integer(1), Integer(Length(mVisible)));
  Assert.AreEqual(0, mVisible[0]);
  mVisible := TAtlasTrackerBoard.Visible(mSnapshot, False, '');
  Assert.AreEqual(Integer(3), Integer(Length(mVisible)));
  mVisible := TAtlasTrackerBoard.Visible(mSnapshot, False, 'titel atl-2');
  Assert.AreEqual(Integer(1), Integer(Length(mVisible)));
  Assert.AreEqual(1, mVisible[0]);
  mVisible := TAtlasTrackerBoard.Visible(mSnapshot, False, 'anna');
  Assert.AreEqual(Integer(1), Integer(Length(mVisible)), 'Suche im Anmeldenamen');
  // Ohne bekannten Anmeldenamen filtert „Nur meine“ nicht.
  mSnapshot.Me := '';
  mVisible := TAtlasTrackerBoard.Visible(mSnapshot, True, '');
  Assert.AreEqual(Integer(3), Integer(Length(mVisible)));
  mVisible := TAtlasTrackerBoard.ColumnCards(mSnapshot, mVisible, -1);
  Assert.AreEqual(Integer(1), Integer(Length(mVisible)));
  Assert.AreEqual(2, mVisible[0]);
end;

procedure TAtlasTrackerBoardTests.CanMoveOnlyToOtherColumnWithValue;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := Sample;
  Assert.IsTrue(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 1));
  Assert.IsFalse(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 0), 'gleiche Spalte');
  Assert.IsFalse(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 2), 'Spalte ohne Wert');
  Assert.IsFalse(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 3), 'keine Spalte');
  Assert.IsTrue(TAtlasTrackerBoard.CanMove(mSnapshot, 2, 0), 'aus „ohne Spalte“');
  mSnapshot.Kind := TAtlasBoardKind.Project;
  Assert.IsFalse(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 1), 'Projekt ohne Option');
  mSnapshot.Columns[1].OptionId := 'o2';
  mSnapshot.Cards[0].ItemId := 'PVTI_1';
  Assert.IsTrue(TAtlasTrackerBoard.CanMove(mSnapshot, 0, 1));
end;

procedure TAtlasTrackerBoardTests.CurrentSprintContainsNow;
var
  mSprints: TArray<TAtlasBoardSprint>;
  mNow: TDateTime;
begin
  SetLength(mSprints, 3);
  mSprints[0].Start := EncodeDate(2026, 10, 12);
  mSprints[0].Finish := EncodeDate(2026, 10, 26);
  mSprints[1].Start := EncodeDate(2026, 11, 9);
  mSprints[1].Finish := EncodeDate(2026, 11, 23);
  mSprints[2].Start := EncodeDate(2026, 10, 26);
  mSprints[2].Finish := EncodeDate(2026, 11, 9);
  mNow := EncodeDate(2026, 10, 28);
  Assert.AreEqual(2, TAtlasTrackerBoard.CurrentSprint(mSprints, mNow));
  // Zwischen zwei Sprints: der nächste.
  mSprints[2].Start := EncodeDate(2026, 10, 30);
  Assert.AreEqual(2, TAtlasTrackerBoard.CurrentSprint(mSprints, mNow));
  // Alle vorbei: der letzte.
  Assert.AreEqual(2, TAtlasTrackerBoard.CurrentSprint(mSprints, EncodeDate(2027, 1, 1)));
  Assert.AreEqual(-1, TAtlasTrackerBoard.CurrentSprint(nil, mNow));
end;

procedure TAtlasTrackerBoardTests.JsonRoundTrip;
var
  mSnapshot, mBack: TAtlasBoardSnapshot;
begin
  mSnapshot := Sample;
  mSnapshot.Kind := TAtlasBoardKind.Project;
  mSnapshot.Board := TAtlasBoardRef.Create('PVT_1', 'Roadmap');
  mSnapshot.Boards := [mSnapshot.Board];
  mSnapshot.ProjectId := 'PVT_1';
  mSnapshot.FieldId := 'F1';
  mSnapshot.Field := 'Status';
  mSnapshot.Sprint.Id := 'it2';
  mSnapshot.Sprint.Name := 'Iteration 2';
  mSnapshot.Sprint.Start := EncodeDateTime(2026, 10, 26, 0, 0, 0, 0);
  mSnapshot.Sprints := [mSnapshot.Sprint];
  mSnapshot.Cards[0].Checklist := TAtlasChecklistProgress.Create(3, 5);
  mSnapshot.Cards[0].Locked := True;
  mSnapshot.Cards[0].PriorityColor := '#e30000';
  mSnapshot.Fetched := EncodeDateTime(2026, 10, 28, 9, 30, 0, 0);
  Assert.IsTrue(TAtlasTrackerBoard.FromJson(TAtlasTrackerBoard.ToJson(mSnapshot), mBack));
  Assert.IsTrue(mBack.Kind = TAtlasBoardKind.Project);
  Assert.AreEqual('Roadmap', mBack.Board.Name);
  Assert.AreEqual(Integer(1), Integer(Length(mBack.Boards)));
  Assert.AreEqual('F1', mBack.FieldId);
  Assert.AreEqual(Integer(3), Integer(Length(mBack.Columns)));
  Assert.AreEqual('Nachgefragt', mBack.Columns[0].Values[1]);
  Assert.AreEqual('it2', mBack.Sprint.Id);
  Assert.AreEqual(Double(mSnapshot.Sprint.Start), Double(mBack.Sprint.Start), 1E-6);
  Assert.AreEqual(Integer(3), Integer(Length(mBack.Cards)));
  Assert.AreEqual('3/5', mBack.Cards[0].Checklist.Text);
  Assert.IsTrue(mBack.Cards[0].Locked);
  Assert.AreEqual('#e30000', mBack.Cards[0].PriorityColor);
  Assert.AreEqual('marco', mBack.Cards[0].Logins[0]);
  Assert.AreEqual('Marco', mBack.Me);
  Assert.AreEqual(Double(mSnapshot.Fetched), Double(mBack.Fetched), 1E-6);
  Assert.IsFalse(TAtlasTrackerBoard.FromJson('{"version": 99}', mBack), 'andere Version');
  Assert.IsFalse(TAtlasTrackerBoard.FromJson('kaputt', mBack));
end;

procedure TAtlasTrackerBoardTests.CacheSavesAndLoads;
var
  mFolder: string;
  mSnapshot, mBack: TAtlasBoardSnapshot;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-board-' + IntToStr(Random(1000000)));
  try
    Assert.IsFalse(TAtlasTrackerBoard.Load(mFolder, YouTrackTarget, mBack));
    mSnapshot := Sample;
    TAtlasTrackerBoard.Save(mFolder, YouTrackTarget, mSnapshot);
    Assert.IsTrue(TAtlasTrackerBoard.Load(mFolder, YouTrackTarget, mBack));
    Assert.AreEqual(Integer(3), Integer(Length(mBack.Cards)));
    Assert.IsFalse(TAtlasTrackerBoard.Load(mFolder, GitHubTarget, mBack), 'anderer Tracker');
    Assert.AreEqual('', TAtlasTrackerBoard.CacheFile('', YouTrackTarget));
  finally
    if TDirectory.Exists(mFolder) then
      TDirectory.Delete(mFolder, True);
  end;
end;

{ TAtlasYouTrackBoardTests }

procedure TAtlasYouTrackBoardTests.AgilesChooseBoardOfProject;
var
  mSnapshot: TAtlasBoardSnapshot;
  mCurrent: string;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '', 'ATL', mSnapshot,
    mCurrent));
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Boards)));
  Assert.AreEqual('108-2', mSnapshot.Board.Id);
  Assert.AreEqual('Zustand', mSnapshot.Field);
  Assert.AreEqual('109-42', mCurrent);
  Assert.AreEqual(Integer(4), Integer(Length(mSnapshot.Columns)));
  Assert.AreEqual('Offen, Nachgefragt', mSnapshot.Columns[0].Name);
  Assert.AreEqual('Zur Prüfung', mSnapshot.Columns[2].Values[0]);
  Assert.IsTrue(mSnapshot.Columns[3].Resolved);
  Assert.AreEqual(0, mSnapshot.ColumnOf('Nachgefragt'));
end;

procedure TAtlasYouTrackBoardTests.AgilesChooseBoardById;
var
  mSnapshot: TAtlasBoardSnapshot;
  mCurrent: string;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '108-1', 'ATL', mSnapshot,
    mCurrent));
  Assert.AreEqual('108-1', mSnapshot.Board.Id);
  Assert.AreEqual('State', mSnapshot.Field);
  // Ohne passendes Projekt: das erste Board.
  Assert.IsTrue(TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '', 'XYZ', mSnapshot, mCurrent));
  Assert.AreEqual('108-1', mSnapshot.Board.Id);
  Assert.IsFalse(TAtlasYouTrackBoards.ParseAgiles('[]', '', 'ATL', mSnapshot, mCurrent));
  Assert.IsFalse(TAtlasYouTrackBoards.ParseAgiles('kaputt', '', 'ATL', mSnapshot, mCurrent));
end;

procedure TAtlasYouTrackBoardTests.SprintCardsFromFixture;
var
  mSnapshot: TAtlasBoardSnapshot;
  mCurrent: string;
  mSprints: TArray<TAtlasBoardSprint>;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '', 'ATL', mSnapshot,
    mCurrent));
  Assert.IsTrue(TAtlasYouTrackBoards.ParseSprints(Fixture('YouTrack', 'agile-sprints.json'), mSprints));
  Assert.AreEqual(Integer(2), Integer(Length(mSprints)));
  Assert.IsTrue(mSprints[0].Archived);
  Assert.IsTrue(mSprints[1].Start > 0);
  Assert.IsTrue(TAtlasYouTrackBoards.ParseSprint(Fixture('YouTrack', 'agile-sprint.json'), YouTrackTarget,
    mSnapshot));
  Assert.AreEqual('Sprint 42', mSnapshot.Sprint.Name);
  Assert.AreEqual(Integer(3), Integer(Length(mSnapshot.Cards)));
  Assert.AreEqual('ATL-123', mSnapshot.Cards[0].Key);
  Assert.AreEqual('In Arbeit', mSnapshot.Cards[0].State);
  Assert.AreEqual(1, mSnapshot.CardColumn(0));
  Assert.AreEqual('marco', mSnapshot.Cards[0].Logins[0]);
  Assert.AreEqual('MB', TAtlasTrackerBoard.Initials(mSnapshot.Cards[0].Assignee));
  Assert.AreEqual('#e30000', mSnapshot.Cards[0].PriorityColor);
  Assert.AreEqual('2/3', mSnapshot.Cards[0].Checklist.Text);
  Assert.IsTrue(mSnapshot.Cards[0].Locked, 'ATL-100 ist offen');
  Assert.AreEqual('https://firma.youtrack.cloud/issue/ATL-123', mSnapshot.Cards[0].Page);
  Assert.AreEqual(0, mSnapshot.CardColumn(1), 'Nachgefragt liegt in „Offen“');
  Assert.IsFalse(mSnapshot.Cards[1].Locked);
  Assert.IsFalse(mSnapshot.Cards[1].Checklist.Any);
  Assert.AreEqual(-1, mSnapshot.CardColumn(2), 'Verworfen hat keine Spalte');
  Assert.AreEqual(Integer(0), Integer(Length(mSnapshot.Cards[2].Logins)));
end;

procedure TAtlasYouTrackBoardTests.LoadBoardAsksAgilesSprintsSprintAndMe;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://firma.youtrack.cloud/api/agiles?', '', 200, Fixture('YouTrack', 'agiles.json'));
  mTransport.Answer('https://firma.youtrack.cloud/api/agiles/108-2/sprints?', '', 200,
    Fixture('YouTrack', 'agile-sprints.json'));
  mTransport.Answer('https://firma.youtrack.cloud/api/agiles/108-2/sprints/109-42?', '', 200,
    Fixture('YouTrack', 'agile-sprint.json'));
  mTransport.Answer('https://firma.youtrack.cloud/api/users/me', '', 200, Fixture('YouTrack', 'users-me.json'));
  mBoards := TAtlasYouTrackBoards.Create;
  Assert.IsTrue(mBoards.LoadBoard(YouTrackTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.None);
  Assert.AreEqual(Integer(4), Integer(Length(mTransport.Calls)));
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Sprints)));
  Assert.AreEqual(Integer(3), Integer(Length(mSnapshot.Cards)));
  Assert.AreEqual('marco', mSnapshot.Me);
  Assert.AreEqual(Integer(1), Integer(Length(TAtlasTrackerBoard.Visible(mSnapshot, True, ''))));
  // Gewählter Sprint statt des aktuellen.
  mTransport.Calls := nil;
  mBoards.LoadBoard(YouTrackTarget, mKeep, '108-2', '109-41', 10000, mSnapshot, mError);
  Assert.IsTrue(Pos('/sprints/109-41?', mTransport.Calls[2]) > 0);
end;

procedure TAtlasYouTrackBoardTests.LoadBoardWithoutBoardIsNotFound;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://firma.youtrack.cloud/api/agiles?', '', 200, '[]');
  mBoards := TAtlasYouTrackBoards.Create;
  Assert.IsFalse(mBoards.LoadBoard(YouTrackTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound);
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://firma.youtrack.cloud/api/agiles', '', 401, '');
  Assert.IsFalse(mBoards.LoadBoard(YouTrackTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Unauthorized);
end;

function YouTrackSnapshot: TAtlasBoardSnapshot;
var
  mCurrent: string;
begin
  Result := TAtlasBoardSnapshot.Empty;
  TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '', 'ATL', Result, mCurrent);
  TAtlasYouTrackBoards.ParseSprint(Fixture('YouTrack', 'agile-sprint.json'), YouTrackTarget, Result);
end;

procedure TAtlasYouTrackBoardTests.MoveSendsCommand;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mResult: TAtlasTrackerWriteResult;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://firma.youtrack.cloud/api/commands', '', 200, '{}');
  mSnapshot := YouTrackSnapshot;
  mBoards := TAtlasYouTrackBoards.Create;
  mResult := mBoards.MoveCard(YouTrackTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 2, 'Bitte prüfen', 15000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual(Integer(1), Integer(Length(mTransport.Calls)));
  Assert.AreEqual('POST', mTransport.Methods[0]);
  Assert.AreEqual('Zustand {Zur Prüfung}', JsonText(mTransport.Bodies[0], 'query'));
  Assert.AreEqual('Bitte prüfen', JsonText(mTransport.Bodies[0], 'comment'));
  Assert.IsTrue(Pos('ATL-123', mTransport.Bodies[0]) > 0);
  // Spalte mit mehreren Werten: der erste.
  mBoards.MoveCard(YouTrackTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 0, '', 15000);
  Assert.AreEqual('Zustand Offen', JsonText(mTransport.Bodies[1], 'query'));
  Assert.IsFalse(mBoards.MoveCard(YouTrackTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 9, '', 15000).Succeeded);
end;

procedure TAtlasYouTrackBoardTests.MoveWithoutRightsFailsWithReason;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mResult: TAtlasTrackerWriteResult;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://firma.youtrack.cloud/api/commands', '', 403,
    '{"error": "Forbidden", "error_description": "Keine Berechtigung für das Feld Zustand"}');
  mSnapshot := YouTrackSnapshot;
  mBoards := TAtlasYouTrackBoards.Create;
  mResult := mBoards.MoveCard(YouTrackTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 2, '', 15000);
  Assert.IsFalse(mResult.Succeeded);
  Assert.IsTrue(mResult.Error = TAtlasCiFetchError.Unauthorized);
  Assert.AreEqual(403, mResult.Status);
  Assert.IsTrue(Pos('Keine Berechtigung', mResult.Message) > 0);
end;

{ TAtlasGitHubBoardTests }

procedure TAtlasGitHubBoardTests.GraphQlUrlForGitHubAndEnterprise;
begin
  Assert.AreEqual('https://api.github.com/graphql', TAtlasGitHubBoards.GraphQlUrl(GitHubTarget));
  Assert.AreEqual('https://git.firma.de/api/graphql', TAtlasGitHubBoards.GraphQlUrl(
    TAtlasTrackerTarget.Create('github', 'https://git.firma.de', 'team/kasse', '')));
  Assert.IsTrue(Pos('"owner":"beispiel"', TAtlasGitHubBoards.GraphQlBody('q', ['owner', 'beispiel'])) > 0);
end;

procedure TAtlasGitHubBoardTests.ProjectsOpenFirstWithViewer;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasGitHubBoards.ParseProjects(Fixture('GitHub', 'projects-v2.json'), mSnapshot));
  Assert.AreEqual('xKnockOut', mSnapshot.Me);
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Boards)));
  Assert.AreEqual('PVT_atlas', mSnapshot.Boards[0].Id);
  Assert.AreEqual('Altes Board', mSnapshot.Boards[1].Name);
end;

procedure TAtlasGitHubBoardTests.ProjectCardsFromFixture;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasGitHubBoards.ParseProject(Fixture('GitHub', 'project-v2.json'), GitHubTarget, '',
    EncodeDate(2026, 10, 28), mSnapshot));
  Assert.IsTrue(mSnapshot.Kind = TAtlasBoardKind.Project);
  Assert.AreEqual('Status', mSnapshot.Field);
  Assert.AreEqual('PVTSSF_status', mSnapshot.FieldId);
  Assert.AreEqual(Integer(4), Integer(Length(mSnapshot.Columns)));
  Assert.AreEqual('o3', mSnapshot.Columns[2].OptionId);
  Assert.IsTrue(mSnapshot.Columns[3].Resolved, 'Done');
  Assert.AreEqual(Integer(3), Integer(Length(mSnapshot.Sprints)));
  Assert.AreEqual('it2', mSnapshot.Sprint.Id);
  Assert.IsTrue(mSnapshot.Sprints[2].Archived);
  // Nur Issues der Iteration 2: #753 und das fremde #12; #700 gehört zu Iteration 1, der Entwurf fehlt.
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Cards)));
  Assert.AreEqual('#753', mSnapshot.Cards[0].Key);
  Assert.AreEqual('PVTI_1', mSnapshot.Cards[0].ItemId);
  Assert.AreEqual(1, mSnapshot.CardColumn(0));
  Assert.AreEqual('P0', mSnapshot.Cards[0].Priority);
  Assert.AreEqual('1/2', mSnapshot.Cards[0].Checklist.Text);
  Assert.AreEqual('MB', TAtlasTrackerBoard.Initials(mSnapshot.Cards[0].Assignee));
  Assert.AreEqual('beispiel/web#12', mSnapshot.Cards[1].Key);
  // Älterer Sprint gewählt.
  Assert.IsTrue(TAtlasGitHubBoards.ParseProject(Fixture('GitHub', 'project-v2.json'), GitHubTarget, 'it1',
    EncodeDate(2026, 10, 28), mSnapshot));
  Assert.AreEqual(Integer(1), Integer(Length(mSnapshot.Cards)));
  Assert.AreEqual('#700', mSnapshot.Cards[0].Key);
  Assert.AreEqual(3, mSnapshot.CardColumn(0));
end;

procedure TAtlasGitHubBoardTests.MissingScopesAreUnauthorized;
var
  mMessage: string;
begin
  Assert.IsTrue(TAtlasGitHubBoards.GraphQlError(Fixture('GitHub', 'graphql-scopes.json'), mMessage) =
    TAtlasCiFetchError.Unauthorized);
  Assert.IsTrue(Pos('read:project', mMessage) > 0);
  Assert.IsTrue(TAtlasGitHubBoards.GraphQlError(Fixture('GitHub', 'projects-v2.json'), mMessage) =
    TAtlasCiFetchError.None);
  Assert.IsTrue(TAtlasGitHubBoards.GraphQlError('{"errors":[{"message":"x"}]}', mMessage) =
    TAtlasCiFetchError.Invalid);
end;

procedure TAtlasGitHubBoardTests.LoadBoardWithProject;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/graphql', 'projectsV2', 200, Fixture('GitHub', 'projects-v2.json'));
  mTransport.Answer('https://api.github.com/graphql', 'PVT_atlas', 200, Fixture('GitHub', 'project-v2.json'));
  mBoards := TAtlasGitHubBoards.Create;
  Assert.IsTrue(mBoards.LoadBoard(GitHubTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.AreEqual(Integer(2), Integer(Length(mTransport.Calls)));
  Assert.IsTrue(Pos('"name":"atlas"', mTransport.Bodies[0]) > 0, mTransport.Bodies[0]);
  Assert.AreEqual('PVT_atlas', mSnapshot.Board.Id);
  Assert.AreEqual('xKnockOut', mSnapshot.Me);
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Boards)));
  Assert.IsTrue(Length(mSnapshot.Cards) > 0);
end;

procedure TAtlasGitHubBoardTests.LoadBoardWithoutProjectUsesIssues;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/graphql', '', 200, Fixture('GitHub', 'projects-v2-empty.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues?state=open', '', 200,
    Fixture('GitHub', 'repo-issues-open.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues?state=closed', '', 200,
    Fixture('GitHub', 'repo-issues-closed.json'));
  mBoards := TAtlasGitHubBoards.Create;
  Assert.IsTrue(mBoards.LoadBoard(GitHubTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.IsTrue(mSnapshot.Kind = TAtlasBoardKind.Repository);
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Columns)));
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Cards)), 'ohne Pull Request');
  Assert.AreEqual(0, mSnapshot.CardColumn(0));
  Assert.AreEqual(1, mSnapshot.CardColumn(1));
  Assert.AreEqual('xKnockOut', mSnapshot.Me, 'aus viewer, ohne /user');
  Assert.AreEqual('xKnockOut', mSnapshot.Cards[0].Logins[0]);
  Assert.IsFalse(mSnapshot.ProjectsDenied, 'Projekte gelesen, nur keines da');
end;

procedure TAtlasGitHubBoardTests.LoadBoardWithoutProjectScopeFallsBack;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/graphql', '', 200, Fixture('GitHub', 'graphql-scopes.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues?state=open', '', 200,
    Fixture('GitHub', 'repo-issues-open.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues?state=closed', '', 200,
    Fixture('GitHub', 'repo-issues-closed.json'));
  mBoards := TAtlasGitHubBoards.Create;
  Assert.IsTrue(mBoards.LoadBoard(GitHubTarget, mKeep, '', '', 10000, mSnapshot, mError));
  Assert.IsTrue(mSnapshot.Kind = TAtlasBoardKind.Repository);
  Assert.IsTrue(mSnapshot.ProjectsDenied);
  Assert.AreEqual(Integer(2), Integer(Length(mSnapshot.Cards)));
  // Nicht im Zwischenspeicher.
  Assert.IsTrue(TAtlasTrackerBoard.FromJson(TAtlasTrackerBoard.ToJson(mSnapshot), mSnapshot));
  Assert.IsFalse(mSnapshot.ProjectsDenied);
end;

procedure TAtlasGitHubBoardTests.MoveInProjectSetsOption;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mResult: TAtlasTrackerWriteResult;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  TAtlasGitHubBoards.ParseProject(Fixture('GitHub', 'project-v2.json'), GitHubTarget, '', EncodeDate(2026, 10, 28),
    mSnapshot);
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/graphql', 'updateProjectV2ItemFieldValue', 200,
    '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_1"}}}}');
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753/comments', '', 201, '{}');
  mBoards := TAtlasGitHubBoards.Create;
  mResult := mBoards.MoveCard(GitHubTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 2, 'Zur Prüfung', 15000);
  Assert.IsTrue(mResult.Succeeded, mResult.Message);
  Assert.AreEqual(Integer(2), Integer(Length(mTransport.Calls)));
  Assert.IsTrue(Pos('/comments', mTransport.Calls[0]) > 0, 'Kommentar zuerst');
  Assert.IsTrue(Pos('"option":"o3"', mTransport.Bodies[1]) > 0, mTransport.Bodies[1]);
  Assert.IsTrue(Pos('"item":"PVTI_1"', mTransport.Bodies[1]) > 0);
  // Fehler kommt als "errors" mit Status 200.
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/graphql', '', 200, Fixture('GitHub', 'graphql-scopes.json'));
  mResult := mBoards.MoveCard(GitHubTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 2, '', 15000);
  Assert.IsFalse(mResult.Succeeded);
  Assert.IsTrue(mResult.Error = TAtlasCiFetchError.Unauthorized);
  Assert.IsTrue(Pos('read:project', mResult.Message) > 0);
end;

procedure TAtlasGitHubBoardTests.MoveWithoutProjectClosesIssue;
var
  mTransport: TFakeBoardTransport;
  mKeep: IAtlasCiTransport;
  mBoards: IAtlasTrackerBoards;
  mSnapshot: TAtlasBoardSnapshot;
  mResult: TAtlasTrackerWriteResult;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  mSnapshot.Kind := TAtlasBoardKind.Repository;
  mSnapshot.Columns := [TAtlasBoardColumn.Create('open', TArray<string>.Create('open'), '', False),
    TAtlasBoardColumn.Create('closed', TArray<string>.Create('closed'), '', True)];
  mSnapshot.Cards := [Card('#753', 'open', nil)];
  mTransport := TFakeBoardTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753/comments', '', 403,
    '{"message": "Must have admin rights"}');
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753', '', 200, '{}');
  mBoards := TAtlasGitHubBoards.Create;
  mResult := mBoards.MoveCard(GitHubTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 1, 'Fertig', 15000);
  Assert.IsFalse(mResult.Succeeded, 'Kommentar abgelehnt: nichts geändert');
  Assert.AreEqual(Integer(1), Integer(Length(mTransport.Calls)));
  mResult := mBoards.MoveCard(GitHubTarget, mKeep, mSnapshot, mSnapshot.Cards[0], 1, '', 15000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual('PATCH', mTransport.Methods[1]);
  Assert.AreEqual('{"state":"closed"}', mTransport.Bodies[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasYouTrackBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasGitHubBoardTests);

end.
