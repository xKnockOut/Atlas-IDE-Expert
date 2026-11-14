unit Atlas.Core.Completion.Favorites.Tests;

// Tests für angeheftete Favoriten der Vervollständigung (#458): Anheften und Lösen, höchstens fünf je Typ,
// Ablage als JSON, Rangfolge (vor allen Gruppen, nur passend zum Präfix) und Ablauf im Controller.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFavoritesTests = class
  public
    [Test]
    procedure TogglesPerTypeAndMember;
    [Test]
    procedure AtMostFivePerType;
    [Test]
    procedure RejectsActionsAndHints;
    [Test]
    procedure JsonKeepsOrderAndFields;
    [Test]
    procedure ParseDropsInvalidEntries;
    [Test]
    procedure SurvivesRestartViaFile;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
  end;

  [TestFixture]
  TAtlasFavoritesRankingTests = class
  public
    [Test]
    procedure MatchingFavoritesComeFirst;
    [Test]
    procedure FavoritesBeatLearningAndBetterMatch;
    [Test]
    procedure FavoritesPrecedeAllGroups;
  end;

  [TestFixture]
  TAtlasFavoritesControllerTests = class
  public
    [Test]
    procedure PinnedEntriesStayOnTopForEveryQuery;
    [Test]
    procedure SixthFavoriteChangesNothing;
    [Test]
    procedure SelectionFollowsTheToggledEntry;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Completion.Providers.Fixed;

type
  TFavoritesView = class(TInterfacedObject, IAtlasCompletionView)
  public
    Names: string;
    Selected: Integer;
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
  end;

function OrderNames(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    if TAtlasRanking.IsHeader(mIndex) then
    begin
      Result := Result + '#';
    end
    else
    begin
      Result := Result + AItems[mIndex].Name;
    end;
  end;
end;

procedure TFavoritesView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  Names := OrderNames(AItems, AOrder);
  Selected := ASelected;
end;

procedure TFavoritesView.HideList;
begin
  Names := '';
end;

procedure TFavoritesView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Names := '';
end;

function TFavoritesView.PageSize: Integer;
begin
  Result := 9;
end;

procedure TFavoritesView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

function Member(const AName, AContainer: string; ADepth, ARank: Integer): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.DeclaringClass := AContainer;
  Result.DeclaringUnit := 'FireDAC.Comp.Client';
  Result.Depth := ADepth;
  Result.Rank := ARank;
  Result.Kind := TAtlasItemKind.Method;
end;

/// <summary>Member einer TFDQuery: eigene, dann geerbte von TDataSet.</summary>
function QueryItems: TAtlasCompletionItems;
begin
  Result := [Member('ExecSQL', 'TFDQuery', 0, 0), Member('ParamByName', 'TFDQuery', 0, 1),
    Member('Active', 'TDataSet', 1, 2), Member('Close', 'TDataSet', 1, 3), Member('FieldByName', 'TDataSet', 1, 4),
    Member('Open', 'TDataSet', 1, 5)];
  Result[5].DeclaringUnit := 'Data.DB';
  Result[5].Signature := 'procedure Open';
end;

function Context(const APrefix: string): TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

function Wait(const ACondition: TFunc<Boolean>): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > 3000;
  Result := False;
end;

function TempFile: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasFavorites' + IntToStr(TThread.GetTickCount64) + '.json');
end;

function Ordered(const AItems: TAtlasCompletionItems; AFavorites: TAtlasFavorites; const APattern: string;
  const AOptions: TAtlasRankOptions): string;
var
  mItems: TAtlasCompletionItems;
  mIndex: Integer;
begin
  mItems := Copy(AItems);
  for mIndex := 0 to High(mItems) do
  begin
    mItems[mIndex].Favorite := AFavorites.IsFavorite(mItems[mIndex]);
  end;
  Result := OrderNames(mItems, TAtlasRanking.Order(mItems, APattern, AOptions));
end;

/// <summary>Position des Eintrags AName in der aktuellen Anzeige des Controllers; -1 ohne.</summary>
function PositionOf(AController: TAtlasCompletionController; const AName: string): Integer;
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(AController.Order) do
  begin
    if not TAtlasRanking.IsHeader(AController.Order[mPosition]) and
      (AController.Items[AController.Order[mPosition]].Name = AName) then
    begin
      Exit(mPosition);
    end;
  end;
  Result := -1;
end;

procedure StartAndWait(AController: TAtlasCompletionController; const APrefix: string);
begin
  AController.Start(Context(APrefix));
  Assert.IsTrue(Wait(
    function: Boolean
    begin
      Result := not AController.Loading;
    end));
end;

{ TAtlasFavoritesTests }

procedure TAtlasFavoritesTests.TogglesPerTypeAndMember;
var
  mFavorites: TAtlasFavorites;
  mOpen, mOtherCase, mOtherType: TAtlasCompletionItem;
  mItems: TArray<TAtlasFavorite>;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    mOpen := Member('Open', 'TDataSet', 1, 0);
    Assert.IsFalse(mFavorites.IsFavorite(mOpen));
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added, mFavorites.Toggle(mOpen));
    Assert.IsTrue(mFavorites.Changed);
    // Schlüssel wie #418: Paar (Typ, Member), Groß-/Kleinschreibung egal.
    mOtherCase := Member('OPEN', 'tdataset', 0, 0);
    Assert.IsTrue(mFavorites.IsFavorite(mOtherCase));
    Assert.IsTrue(mFavorites.Contains('TDataSet|Open'));
    mOtherType := Member('Open', 'TStream', 0, 0);
    Assert.IsFalse(mFavorites.IsFavorite(mOtherType), 'anderer Typ, anderer Favorit');
    // Auf Unit-Ebene zählt die Unit als Typ.
    mOtherType := Member('ShowMessage', '', 0, 0);
    mOtherType.DeclaringUnit := 'Vcl.Dialogs';
    Assert.AreEqual('Vcl.Dialogs', TAtlasFavorites.TypeNameOf(mOtherType));
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added, mFavorites.Toggle(mOtherType));
    Assert.AreEqual(1, mFavorites.CountOf('VCL.DIALOGS'));
    mItems := mFavorites.Items;
    Assert.AreEqual('Vcl.Dialogs.ShowMessage', mItems[1].DisplayName);
    // Erneut: lösen.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Removed, mFavorites.Toggle(mOtherCase));
    Assert.IsFalse(mFavorites.IsFavorite(mOpen));
    Assert.AreEqual(1, Integer(mFavorites.Count));
    Assert.IsTrue(mFavorites.Remove('vcl.dialogs|showmessage'));
    Assert.IsFalse(mFavorites.Remove('vcl.dialogs|showmessage'), 'schon gelöst');
    Assert.AreEqual(0, Integer(mFavorites.Count));
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.AtMostFivePerType;
var
  mFavorites: TAtlasFavorites;
  mIndex: Integer;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    for mIndex := 1 to TAtlasFavorites.cMaxPerType do
    begin
      Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added,
        mFavorites.Toggle(Member('M' + IntToStr(mIndex), 'TDataSet', 0, 0)));
    end;
    // Ein sechster ersetzt nichts.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Full, mFavorites.Toggle(Member('M6', 'TDataSet', 0, 0)));
    Assert.AreEqual(5, mFavorites.CountOf('TDataSet'));
    Assert.IsFalse(mFavorites.IsFavorite(Member('M6', 'TDataSet', 0, 0)));
    Assert.IsTrue(mFavorites.IsFavorite(Member('M1', 'TDataSet', 0, 0)), 'der erste bleibt');
    // Andere Typen haben ihr eigenes Kontingent.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added, mFavorites.Toggle(Member('M6', 'TFDQuery', 0, 0)));
    // Nach dem Lösen ist wieder Platz.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Removed,
      mFavorites.Toggle(Member('M3', 'TDataSet', 0, 0)));
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added, mFavorites.Toggle(Member('M6', 'TDataSet', 0, 0)));
    Assert.AreEqual(6, Integer(mFavorites.Count));
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.RejectsActionsAndHints;
var
  mFavorites: TAtlasFavorites;
  mItem: TAtlasCompletionItem;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    mItem := Member('Neue Methode btnSaveClick …', '', 0, 0);
    mItem.IsAction := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(mItem));
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.NotAllowed, mFavorites.Toggle(mItem));
    mItem := Member('3 Methoden von IExporter fehlen', '', 0, 0);
    mItem.Hint := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(mItem));
    mItem := Member('Alle Werte einfügen', '', 0, 0);
    mItem.Pinned := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(mItem));
    mItem := Member('TotalCount deklarieren', '', 0, 0);
    mItem.Unknown := 'TotalCount';
    Assert.IsFalse(TAtlasFavorites.CanPin(mItem));
    mItem := Member('Mit try…finally absichern', '', 0, 0);
    mItem.Guard := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(mItem));
    Assert.IsFalse(TAtlasFavorites.CanPin(Member('  ', 'TDataSet', 0, 0)));
    Assert.IsTrue(TAtlasFavorites.CanPin(Member('Open', 'TDataSet', 0, 0)));
    Assert.AreEqual(0, Integer(mFavorites.Count));
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.JsonKeepsOrderAndFields;
var
  mFavorites, mLoaded: TAtlasFavorites;
  mItems: TArray<TAtlasFavorite>;
  mQuery: TAtlasCompletionItems;
  mStamp: TDateTime;
begin
  mFavorites := TAtlasFavorites.Create;
  mLoaded := TAtlasFavorites.Create;
  try
    mStamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 5, 0);
    mQuery := QueryItems;
    mFavorites.Toggle(mQuery[5], mStamp);
    mFavorites.Toggle(mQuery[1], mStamp + 1);
    mLoaded.Parse(mFavorites.ToJson);
    Assert.IsFalse(mLoaded.Changed);
    mItems := mLoaded.Items;
    Assert.AreEqual(2, Integer(Length(mItems)));
    Assert.AreEqual('TDataSet', mItems[0].TypeName, 'Reihenfolge des Anheftens');
    Assert.AreEqual('Open', mItems[0].Member);
    Assert.AreEqual<TAtlasItemKind>(TAtlasItemKind.Method, mItems[0].Kind);
    Assert.AreEqual('Data.DB', mItems[0].UnitName);
    Assert.AreEqual('procedure Open', mItems[0].Signature);
    Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', mStamp), FormatDateTime('yyyy-mm-dd hh:nn:ss', mItems[0].Added));
    Assert.AreEqual('TFDQuery', mItems[1].TypeName);
    Assert.AreEqual('ParamByName', mItems[1].Member);
    Assert.AreEqual('tfdquery|parambyname', mItems[1].Key);
    // Format der Ablage, das auch die Willkommensseite (#755) liest.
    Assert.IsTrue(Pos('"version":1', mFavorites.ToJson) > 0);
    Assert.IsTrue(Pos('"added":"2026-10-15T09:30:05"', mFavorites.ToJson) > 0);
    Assert.IsTrue(Pos('"kind":"method"', mFavorites.ToJson) > 0);
    Assert.AreEqual<TAtlasItemKind>(TAtlasItemKind.EnumMember, TAtlasFavorites.KindFromName('enumMember'));
    Assert.AreEqual<TAtlasItemKind>(TAtlasItemKind.Unknown, TAtlasFavorites.KindFromName('unbekannt'));
  finally
    mLoaded.Free;
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.ParseDropsInvalidEntries;
var
  mFavorites: TAtlasFavorites;
  mJson: string;
  mIndex: Integer;
  mItems: TArray<TAtlasFavorite>;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    mFavorites.Parse('{kaputt');
    Assert.AreEqual(0, Integer(mFavorites.Count));
    mFavorites.Parse('[1, 2]');
    Assert.AreEqual(0, Integer(mFavorites.Count));
    mJson := '{"version":1,"favorites":[{"type":"TDataSet","member":"Open"},{"type":"tdataset","member":"OPEN"},' +
      '{"type":"TDataSet","member":""},7,{"member":"ohneTyp","added":"gestern"}';
    for mIndex := 1 to 6 do
    begin
      mJson := mJson + ',{"type":"TStrings","member":"S' + IntToStr(mIndex) + '"}';
    end;
    mFavorites.Parse(mJson + ']}');
    Assert.AreEqual(1, mFavorites.CountOf('TDataSet'), 'doppelt und leer fallen weg');
    Assert.AreEqual(5, mFavorites.CountOf('TStrings'), 'höchstens fünf je Typ');
    Assert.IsTrue(mFavorites.Contains('|ohnetyp'));
    mItems := mFavorites.Items;
    Assert.AreEqual('ohneTyp', mItems[1].Member);
    Assert.AreEqual<TDateTime>(0, mItems[1].Added, 'unlesbares Datum: 0');
    Assert.AreEqual(7, Integer(mFavorites.Count));
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.SurvivesRestartViaFile;
var
  mFavorites, mLoaded: TAtlasFavorites;
  mFileName: string;
begin
  // Akzeptanz #458: Favoriten bleiben nach einem Neustart erhalten.
  mFileName := TPath.Combine(TPath.Combine(TempFile + '.d', 'Atlas'), 'favorites.json');
  mFavorites := TAtlasFavorites.Create;
  mLoaded := TAtlasFavorites.Create;
  try
    mFavorites.Toggle(Member('Open', 'TDataSet', 1, 0));
    mFavorites.Toggle(Member('ParamByName', 'TFDQuery', 0, 0));
    mFavorites.SaveToFile(mFileName);
    Assert.IsFalse(mFavorites.Changed);
    mLoaded.LoadFromFile(mFileName);
    Assert.AreEqual(2, Integer(mLoaded.Count));
    Assert.IsTrue(mLoaded.IsFavorite(Member('Open', 'TDataSet', 1, 0)));
    Assert.IsTrue(mLoaded.IsFavorite(Member('ParamByName', 'TFDQuery', 0, 0)));
    // Fehlende Datei: leer, kein Fehler.
    mLoaded.LoadFromFile(mFileName + '.fehlt');
    Assert.AreEqual(0, Integer(mLoaded.Count));
    mLoaded.Toggle(Member('Close', 'TDataSet', 1, 0));
    mLoaded.Clear;
    Assert.IsTrue(mLoaded.Changed);
  finally
    mLoaded.Free;
    mFavorites.Free;
    if TFile.Exists(mFileName) then
    begin
      TFile.Delete(mFileName);
    end;
  end;
end;

{ TAtlasFavoritesRankingTests }

procedure TAtlasFavoritesRankingTests.MatchingFavoritesComeFirst;
var
  mFavorites: TAtlasFavorites;
  mOptions: TAtlasRankOptions;
  mQuery: TAtlasCompletionItems;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    mQuery := QueryItems;
    mFavorites.Toggle(mQuery[5]);
    mFavorites.Toggle(mQuery[1]);
    mOptions := TAtlasRankOptions.Defaults;
    Assert.AreEqual('ParamByName,Open,ExecSQL,Active,Close,FieldByName', Ordered(QueryItems, mFavorites, '', mOptions));
    Assert.AreEqual('Open', Ordered(QueryItems, mFavorites, 'Op', mOptions));
    Assert.AreEqual('ParamByName,FieldByName', Ordered(QueryItems, mFavorites, 'ByName', mOptions),
      'Favorit vor dem gleich guten Treffer');
    // Passt ein Favorit nicht zum Präfix, steht er nicht in der Liste.
    Assert.AreEqual('Close', Ordered(QueryItems, mFavorites, 'Clo', mOptions));
    // Gruppen geerbter Member (#419): Favoriten ohne Überschrift davor, die Gruppen danach wie gewohnt.
    mOptions.GroupInherited := True;
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', Ordered(QueryItems, mFavorites, '',
      mOptions));
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesRankingTests.FavoritesBeatLearningAndBetterMatch;
var
  mFavorites: TAtlasFavorites;
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    mItems := [Member('O', 'TFDQuery', 0, 0), Member('OnError', 'TFDQuery', 0, 1), Member('Open', 'TDataSet', 1, 2)];
    mFavorites.Toggle(mItems[2]);
    mOptions := TAtlasRankOptions.Defaults;
    // Lernzuschlag für die anderen Einträge: Der Favorit bleibt trotzdem oben.
    mOptions.Boost :=
      function(AIndex: Integer): Integer
      begin
        if AIndex = 2 then
        begin
          Result := 0;
        end
        else
        begin
          Result := 99;
        end;
      end;
    Assert.AreEqual('Open,O,OnError', Ordered(mItems, mFavorites, 'O', mOptions), 'vor dem genauen Treffer "O"');
    Assert.AreEqual('Open,O,OnError', Ordered(mItems, mFavorites, '', mOptions), 'auch ohne Präfix');
  finally
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesRankingTests.FavoritesPrecedeAllGroups;
var
  mFavorites: TAtlasFavorites;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
begin
  mFavorites := TAtlasFavorites.Create;
  try
    // Formularkomponenten (#455) und erwarteter Typ (#417) bilden Gruppen mit Überschrift; der Favorit steht
    // davor und ohne eigene Überschrift.
    mItems := [Member('btnSave', 'TForm1', 0, 0), Member('Caption', 'TForm1', 0, 1), Member('Color', 'TForm1', 0, 2),
      Member('Close', 'TForm1', 0, 3)];
    mItems[0].Form := 'frmMain';
    mItems[1].ExpectedType := 'string';
    mItems[1].Fits := True;
    mItems[2].ExpectedType := 'string';
    mItems[3].ExpectedType := 'string';
    mFavorites.Toggle(mItems[3]);
    mOptions := TAtlasRankOptions.Defaults;
    Assert.AreEqual('Close,#,btnSave,#,Caption,#,Color', Ordered(mItems, mFavorites, '', mOptions));
    // Hinweis „n Methoden fehlen“ (#466) steht sonst ganz oben – der Favorit davor.
    mItems := [Member('2 Methoden von IExporter fehlen', '', 0, 0), Member('Open', 'TDataSet', 0, 1)];
    mItems[0].Hint := True;
    mFavorites.Toggle(mItems[1]);
    Assert.AreEqual('Open,2 Methoden von IExporter fehlen', Ordered(mItems, mFavorites, 'Op', mOptions));
  finally
    mFavorites.Free;
  end;
end;

{ TAtlasFavoritesControllerTests }

procedure TAtlasFavoritesControllerTests.PinnedEntriesStayOnTopForEveryQuery;
var
  mView: TFavoritesView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mFavorites, mRestarted: TAtlasFavorites;
  mItem: TAtlasCompletionItem;
  mFileName: string;
begin
  // Akzeptanz #458: Nach Anheften von Open und ParamByName stehen beide bei jeder Query oben, auch nach einem
  // Neustart (neu geladen aus der Ablage).
  mView := TFavoritesView.Create;
  mViewRef := mView;
  mFileName := TempFile;
  mFavorites := TAtlasFavorites.Create;
  mRestarted := TAtlasFavorites.Create;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.Favorites := mFavorites;
    mController.GroupInherited := True;
    StartAndWait(mController, '');
    Assert.AreEqual('ExecSQL,ParamByName,#,Active,Close,FieldByName,Open', mView.Names);
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added,
      mController.ToggleFavorite(PositionOf(mController, 'Open'), mItem));
    Assert.AreEqual('Open', mItem.Name);
    Assert.IsTrue(mItem.Favorite);
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added,
      mController.ToggleFavorite(PositionOf(mController, 'ParamByName'), mItem));
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', mView.Names, 'sofort neu sortiert');
    Assert.IsTrue(mController.Items[mController.Order[0]].Favorite);
    // Nächste Abfrage (andere Query, dieselben Typen): beide oben.
    StartAndWait(mController, '');
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', mView.Names);
    mController.UpdatePrefix('e');
    Assert.AreEqual('ParamByName,Open', Copy(mView.Names, 1, Length('ParamByName,Open')));
    mFavorites.SaveToFile(mFileName);
    // „Neustart“: neue Instanz aus der Datei.
    mRestarted.LoadFromFile(mFileName);
    mController.Favorites := mRestarted;
    StartAndWait(mController, '');
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', mView.Names);
    // Abgeschaltet (Favorites = nil): keine Sonderstellung.
    mController.Favorites := nil;
    StartAndWait(mController, '');
    Assert.AreEqual('ExecSQL,ParamByName,#,Active,Close,FieldByName,Open', mView.Names);
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.NotAllowed, mController.ToggleSelectedFavorite(mItem));
  finally
    mController.Free;
    mRestarted.Free;
    mFavorites.Free;
    if TFile.Exists(mFileName) then
    begin
      TFile.Delete(mFileName);
    end;
  end;
end;

procedure TAtlasFavoritesControllerTests.SixthFavoriteChangesNothing;
var
  mView: TFavoritesView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mFavorites: TAtlasFavorites;
  mItem: TAtlasCompletionItem;
  mIndex: Integer;
  mBefore: string;
begin
  mView := TFavoritesView.Create;
  mViewRef := mView;
  mFavorites := TAtlasFavorites.Create;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, mViewRef);
  try
    for mIndex := 1 to TAtlasFavorites.cMaxPerType do
    begin
      mFavorites.Toggle(Member('Weitere' + IntToStr(mIndex), 'TDataSet', 1, 0));
    end;
    mController.Favorites := mFavorites;
    StartAndWait(mController, '');
    mBefore := mView.Names;
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Full,
      mController.ToggleFavorite(PositionOf(mController, 'Open'), mItem));
    Assert.AreEqual('TDataSet', TAtlasFavorites.TypeNameOf(mItem), 'für den Hinweis in der Fußzeile');
    Assert.AreEqual(mBefore, mView.Names, 'nichts geändert');
    Assert.IsFalse(mFavorites.IsFavorite(mItem));
    // Überschriften lassen sich nicht anheften.
    mController.GroupInherited := True;
    StartAndWait(mController, '');
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.NotAllowed,
      mController.ToggleFavorite(2, mItem), 'Überschrift');
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.NotAllowed, mController.ToggleFavorite(99, mItem));
  finally
    mController.Free;
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesControllerTests.SelectionFollowsTheToggledEntry;
var
  mView: TFavoritesView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mFavorites: TAtlasFavorites;
  mItem: TAtlasCompletionItem;
begin
  mView := TFavoritesView.Create;
  mViewRef := mView;
  mFavorites := TAtlasFavorites.Create;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.Favorites := mFavorites;
    StartAndWait(mController, '');
    Assert.AreEqual('ExecSQL,ParamByName,Active,Close,FieldByName,Open', mView.Names);
    mController.HandleKey(TAtlasNavigationKey.Last);
    // Strg+D: der gewählte Eintrag wandert nach oben, die Auswahl geht mit.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added, mController.ToggleSelectedFavorite(mItem));
    Assert.AreEqual('Open,ExecSQL,ParamByName,Active,Close,FieldByName', mView.Names);
    Assert.AreEqual(0, mView.Selected);
    Assert.IsTrue(mController.SelectedItem(mItem));
    Assert.AreEqual('Open', mItem.Name);
    // Stern einer anderen Zeile: Die Auswahl bleibt auf Open.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Added,
      mController.ToggleFavorite(PositionOf(mController, 'Close'), mItem));
    Assert.AreEqual('Close,Open,ExecSQL,ParamByName,Active,FieldByName', mView.Names);
    Assert.AreEqual(1, mView.Selected);
    // Lösen: zurück an den gewohnten Platz.
    Assert.AreEqual<TAtlasFavoriteToggle>(TAtlasFavoriteToggle.Removed, mController.ToggleSelectedFavorite(mItem));
    Assert.IsFalse(mItem.Favorite);
    Assert.AreEqual('Close,ExecSQL,ParamByName,Active,FieldByName,Open', mView.Names);
    Assert.AreEqual(5, mView.Selected);
  finally
    mController.Free;
    mFavorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.BrokenFileSetAsideLockedFileKept;
var
  mFavorites: TAtlasFavorites;
  mFolder, mFileName: string;
  mLock: TFileStream;
begin
  mFolder := TempFile + '.d';
  mFileName := TPath.Combine(mFolder, 'favorites.json');
  TDirectory.CreateDirectory(mFolder);
  mFavorites := TAtlasFavorites.Create;
  try
    TFile.WriteAllText(mFileName, '{kaputt');
    Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Renewed, mFavorites.LoadFromFile(mFileName));
    Assert.AreEqual('{kaputt', TFile.ReadAllText(mFileName + TAtlasDataFile.cDefectExtension, TEncoding.UTF8));
    mFavorites.Toggle(Member('Open', 'TDataSet', 1, 0));
    Assert.IsTrue(mFavorites.SaveToFile(mFileName));
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept, mFavorites.LoadFromFile(mFileName));
    finally
      mLock.Free;
    end;
    Assert.AreEqual(0, Integer(mFavorites.Count));
    mFavorites.Toggle(Member('Close', 'TDataSet', 1, 0));
    Assert.IsFalse(mFavorites.SaveToFile(mFileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), '"Open"');
    Assert.DoesNotContain(TFile.ReadAllText(mFileName, TEncoding.UTF8), '"Close"');
  finally
    mFavorites.Free;
    TDirectory.Delete(mFolder, True);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFavoritesTests);
  TDUnitX.RegisterTestFixture(TAtlasFavoritesRankingTests);
  TDUnitX.RegisterTestFixture(TAtlasFavoritesControllerTests);

end.
