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
    /// überschrieben (Bericht N3).</summary>
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
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
  begin
    if Result <> '' then
      Result := Result + ',';
    if TAtlasRanking.IsHeader(Index) then
      Result := Result + '#'
    else
      Result := Result + AItems[Index].Name;
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
  Start: UInt64;
begin
  Start := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
      Exit(True);
  until TThread.GetTickCount64 - Start > 3000;
  Result := False;
end;

function TempFile: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasFavorites' + IntToStr(TThread.GetTickCount64) + '.json');
end;

function Ordered(const AItems: TAtlasCompletionItems; AFavorites: TAtlasFavorites; const APattern: string;
  const AOptions: TAtlasRankOptions): string;
var
  Items: TAtlasCompletionItems;
  Index: Integer;
begin
  Items := Copy(AItems);
  for Index := 0 to High(Items) do
    Items[Index].Favorite := AFavorites.IsFavorite(Items[Index]);
  Result := OrderNames(Items, TAtlasRanking.Order(Items, APattern, AOptions));
end;

/// <summary>Position des Eintrags AName in der aktuellen Anzeige des Controllers; -1 ohne.</summary>
function PositionOf(AController: TAtlasCompletionController; const AName: string): Integer;
var
  Position: Integer;
begin
  for Position := 0 to High(AController.Order) do
    if not TAtlasRanking.IsHeader(AController.Order[Position]) and
      (AController.Items[AController.Order[Position]].Name = AName) then
      Exit(Position);
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
  Favorites: TAtlasFavorites;
  Open, OtherCase, OtherType: TAtlasCompletionItem;
  Items: TArray<TAtlasFavorite>;
begin
  Favorites := TAtlasFavorites.Create;
  try
    Open := Member('Open', 'TDataSet', 1, 0);
    Assert.IsFalse(Favorites.IsFavorite(Open));
    Assert.IsTrue(Favorites.Toggle(Open) = TAtlasFavoriteToggle.Added);
    Assert.IsTrue(Favorites.Changed);
    // Schlüssel wie #418: Paar (Typ, Member), Groß-/Kleinschreibung egal.
    OtherCase := Member('OPEN', 'tdataset', 0, 0);
    Assert.IsTrue(Favorites.IsFavorite(OtherCase));
    Assert.IsTrue(Favorites.Contains('TDataSet|Open'));
    OtherType := Member('Open', 'TStream', 0, 0);
    Assert.IsFalse(Favorites.IsFavorite(OtherType), 'anderer Typ, anderer Favorit');
    // Auf Unit-Ebene zählt die Unit als Typ.
    OtherType := Member('ShowMessage', '', 0, 0);
    OtherType.DeclaringUnit := 'Vcl.Dialogs';
    Assert.AreEqual('Vcl.Dialogs', TAtlasFavorites.TypeNameOf(OtherType));
    Assert.IsTrue(Favorites.Toggle(OtherType) = TAtlasFavoriteToggle.Added);
    Assert.AreEqual(1, Favorites.CountOf('VCL.DIALOGS'));
    Items := Favorites.Items;
    Assert.AreEqual('Vcl.Dialogs.ShowMessage', Items[1].DisplayName);
    // Erneut: lösen.
    Assert.IsTrue(Favorites.Toggle(OtherCase) = TAtlasFavoriteToggle.Removed);
    Assert.IsFalse(Favorites.IsFavorite(Open));
    Assert.AreEqual(1, Integer(Favorites.Count));
    Assert.IsTrue(Favorites.Remove('vcl.dialogs|showmessage'));
    Assert.IsFalse(Favorites.Remove('vcl.dialogs|showmessage'), 'schon gelöst');
    Assert.AreEqual(0, Integer(Favorites.Count));
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.AtMostFivePerType;
var
  Favorites: TAtlasFavorites;
  Index: Integer;
begin
  Favorites := TAtlasFavorites.Create;
  try
    for Index := 1 to TAtlasFavorites.MaxPerType do
      Assert.IsTrue(Favorites.Toggle(Member('M' + IntToStr(Index), 'TDataSet', 0, 0)) = TAtlasFavoriteToggle.Added);
    // Ein sechster ersetzt nichts.
    Assert.IsTrue(Favorites.Toggle(Member('M6', 'TDataSet', 0, 0)) = TAtlasFavoriteToggle.Full);
    Assert.AreEqual(5, Favorites.CountOf('TDataSet'));
    Assert.IsFalse(Favorites.IsFavorite(Member('M6', 'TDataSet', 0, 0)));
    Assert.IsTrue(Favorites.IsFavorite(Member('M1', 'TDataSet', 0, 0)), 'der erste bleibt');
    // Andere Typen haben ihr eigenes Kontingent.
    Assert.IsTrue(Favorites.Toggle(Member('M6', 'TFDQuery', 0, 0)) = TAtlasFavoriteToggle.Added);
    // Nach dem Lösen ist wieder Platz.
    Assert.IsTrue(Favorites.Toggle(Member('M3', 'TDataSet', 0, 0)) = TAtlasFavoriteToggle.Removed);
    Assert.IsTrue(Favorites.Toggle(Member('M6', 'TDataSet', 0, 0)) = TAtlasFavoriteToggle.Added);
    Assert.AreEqual(6, Integer(Favorites.Count));
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.RejectsActionsAndHints;
var
  Favorites: TAtlasFavorites;
  Item: TAtlasCompletionItem;
begin
  Favorites := TAtlasFavorites.Create;
  try
    Item := Member('Neue Methode btnSaveClick …', '', 0, 0);
    Item.IsAction := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(Item));
    Assert.IsTrue(Favorites.Toggle(Item) = TAtlasFavoriteToggle.NotAllowed);
    Item := Member('3 Methoden von IExporter fehlen', '', 0, 0);
    Item.Hint := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(Item));
    Item := Member('Alle Werte einfügen', '', 0, 0);
    Item.Pinned := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(Item));
    Item := Member('TotalCount deklarieren', '', 0, 0);
    Item.Unknown := 'TotalCount';
    Assert.IsFalse(TAtlasFavorites.CanPin(Item));
    Item := Member('Mit try…finally absichern', '', 0, 0);
    Item.Guard := True;
    Assert.IsFalse(TAtlasFavorites.CanPin(Item));
    Assert.IsFalse(TAtlasFavorites.CanPin(Member('  ', 'TDataSet', 0, 0)));
    Assert.IsTrue(TAtlasFavorites.CanPin(Member('Open', 'TDataSet', 0, 0)));
    Assert.AreEqual(0, Integer(Favorites.Count));
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.JsonKeepsOrderAndFields;
var
  Favorites, Loaded: TAtlasFavorites;
  Items: TArray<TAtlasFavorite>;
  Query: TAtlasCompletionItems;
  Stamp: TDateTime;
begin
  Favorites := TAtlasFavorites.Create;
  Loaded := TAtlasFavorites.Create;
  try
    Stamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 5, 0);
    Query := QueryItems;
    Favorites.Toggle(Query[5], Stamp);
    Favorites.Toggle(Query[1], Stamp + 1);
    Loaded.Parse(Favorites.ToJson);
    Assert.IsFalse(Loaded.Changed);
    Items := Loaded.Items;
    Assert.AreEqual(2, Integer(Length(Items)));
    Assert.AreEqual('TDataSet', Items[0].TypeName, 'Reihenfolge des Anheftens');
    Assert.AreEqual('Open', Items[0].Member);
    Assert.IsTrue(Items[0].Kind = TAtlasItemKind.Method);
    Assert.AreEqual('Data.DB', Items[0].UnitName);
    Assert.AreEqual('procedure Open', Items[0].Signature);
    Assert.AreEqual(FormatDateTime('yyyy-mm-dd hh:nn:ss', Stamp), FormatDateTime('yyyy-mm-dd hh:nn:ss', Items[0].Added));
    Assert.AreEqual('TFDQuery', Items[1].TypeName);
    Assert.AreEqual('ParamByName', Items[1].Member);
    Assert.AreEqual('tfdquery|parambyname', Items[1].Key);
    // Format der Ablage, das auch die Willkommensseite (#755) liest.
    Assert.IsTrue(Pos('"version":1', Favorites.ToJson) > 0);
    Assert.IsTrue(Pos('"added":"2026-10-15T09:30:05"', Favorites.ToJson) > 0);
    Assert.IsTrue(Pos('"kind":"method"', Favorites.ToJson) > 0);
    Assert.IsTrue(TAtlasFavorites.KindFromName('enumMember') = TAtlasItemKind.EnumMember);
    Assert.IsTrue(TAtlasFavorites.KindFromName('unbekannt') = TAtlasItemKind.Unknown);
  finally
    Loaded.Free;
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.ParseDropsInvalidEntries;
var
  Favorites: TAtlasFavorites;
  Json: string;
  Index: Integer;
  Items: TArray<TAtlasFavorite>;
begin
  Favorites := TAtlasFavorites.Create;
  try
    Favorites.Parse('{kaputt');
    Assert.AreEqual(0, Integer(Favorites.Count));
    Favorites.Parse('[1, 2]');
    Assert.AreEqual(0, Integer(Favorites.Count));
    Json := '{"version":1,"favorites":[{"type":"TDataSet","member":"Open"},{"type":"tdataset","member":"OPEN"},' +
      '{"type":"TDataSet","member":""},7,{"member":"ohneTyp","added":"gestern"}';
    for Index := 1 to 6 do
      Json := Json + ',{"type":"TStrings","member":"S' + IntToStr(Index) + '"}';
    Favorites.Parse(Json + ']}');
    Assert.AreEqual(1, Favorites.CountOf('TDataSet'), 'doppelt und leer fallen weg');
    Assert.AreEqual(5, Favorites.CountOf('TStrings'), 'höchstens fünf je Typ');
    Assert.IsTrue(Favorites.Contains('|ohnetyp'));
    Items := Favorites.Items;
    Assert.AreEqual('ohneTyp', Items[1].Member);
    Assert.IsTrue(Items[1].Added = 0, 'unlesbares Datum: 0');
    Assert.AreEqual(7, Integer(Favorites.Count));
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.SurvivesRestartViaFile;
var
  Favorites, Loaded: TAtlasFavorites;
  FileName: string;
begin
  // Akzeptanz #458: Favoriten bleiben nach einem Neustart erhalten.
  FileName := TPath.Combine(TPath.Combine(TempFile + '.d', 'Atlas'), 'favorites.json');
  Favorites := TAtlasFavorites.Create;
  Loaded := TAtlasFavorites.Create;
  try
    Favorites.Toggle(Member('Open', 'TDataSet', 1, 0));
    Favorites.Toggle(Member('ParamByName', 'TFDQuery', 0, 0));
    Favorites.SaveToFile(FileName);
    Assert.IsFalse(Favorites.Changed);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(2, Integer(Loaded.Count));
    Assert.IsTrue(Loaded.IsFavorite(Member('Open', 'TDataSet', 1, 0)));
    Assert.IsTrue(Loaded.IsFavorite(Member('ParamByName', 'TFDQuery', 0, 0)));
    // Fehlende Datei: leer, kein Fehler.
    Loaded.LoadFromFile(FileName + '.fehlt');
    Assert.AreEqual(0, Integer(Loaded.Count));
    Loaded.Toggle(Member('Close', 'TDataSet', 1, 0));
    Loaded.Clear;
    Assert.IsTrue(Loaded.Changed);
  finally
    Loaded.Free;
    Favorites.Free;
    if TFile.Exists(FileName) then
      TFile.Delete(FileName);
  end;
end;

{ TAtlasFavoritesRankingTests }

procedure TAtlasFavoritesRankingTests.MatchingFavoritesComeFirst;
var
  Favorites: TAtlasFavorites;
  Options: TAtlasRankOptions;
  Query: TAtlasCompletionItems;
begin
  Favorites := TAtlasFavorites.Create;
  try
    Query := QueryItems;
    Favorites.Toggle(Query[5]);
    Favorites.Toggle(Query[1]);
    Options := TAtlasRankOptions.Defaults;
    Assert.AreEqual('ParamByName,Open,ExecSQL,Active,Close,FieldByName', Ordered(QueryItems, Favorites, '', Options));
    Assert.AreEqual('Open', Ordered(QueryItems, Favorites, 'Op', Options));
    Assert.AreEqual('ParamByName,FieldByName', Ordered(QueryItems, Favorites, 'ByName', Options),
      'Favorit vor dem gleich guten Treffer');
    // Passt ein Favorit nicht zum Präfix, steht er nicht in der Liste.
    Assert.AreEqual('Close', Ordered(QueryItems, Favorites, 'Clo', Options));
    // Gruppen geerbter Member (#419): Favoriten ohne Überschrift davor, die Gruppen danach wie gewohnt.
    Options.GroupInherited := True;
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', Ordered(QueryItems, Favorites, '',
      Options));
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesRankingTests.FavoritesBeatLearningAndBetterMatch;
var
  Favorites: TAtlasFavorites;
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  Favorites := TAtlasFavorites.Create;
  try
    Items := [Member('O', 'TFDQuery', 0, 0), Member('OnError', 'TFDQuery', 0, 1), Member('Open', 'TDataSet', 1, 2)];
    Favorites.Toggle(Items[2]);
    Options := TAtlasRankOptions.Defaults;
    // Lernzuschlag für die anderen Einträge: Der Favorit bleibt trotzdem oben.
    Options.Boost :=
      function(AIndex: Integer): Integer
      begin
        if AIndex = 2 then
          Result := 0
        else
          Result := 99;
      end;
    Assert.AreEqual('Open,O,OnError', Ordered(Items, Favorites, 'O', Options), 'vor dem genauen Treffer "O"');
    Assert.AreEqual('Open,O,OnError', Ordered(Items, Favorites, '', Options), 'auch ohne Präfix');
  finally
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesRankingTests.FavoritesPrecedeAllGroups;
var
  Favorites: TAtlasFavorites;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
begin
  Favorites := TAtlasFavorites.Create;
  try
    // Formularkomponenten (#455) und erwarteter Typ (#417) bilden Gruppen mit Überschrift; der Favorit steht
    // davor und ohne eigene Überschrift.
    Items := [Member('btnSave', 'TForm1', 0, 0), Member('Caption', 'TForm1', 0, 1), Member('Color', 'TForm1', 0, 2),
      Member('Close', 'TForm1', 0, 3)];
    Items[0].Form := 'frmMain';
    Items[1].ExpectedType := 'string';
    Items[1].Fits := True;
    Items[2].ExpectedType := 'string';
    Items[3].ExpectedType := 'string';
    Favorites.Toggle(Items[3]);
    Options := TAtlasRankOptions.Defaults;
    Assert.AreEqual('Close,#,btnSave,#,Caption,#,Color', Ordered(Items, Favorites, '', Options));
    // Hinweis „n Methoden fehlen“ (#466) steht sonst ganz oben – der Favorit davor.
    Items := [Member('2 Methoden von IExporter fehlen', '', 0, 0), Member('Open', 'TDataSet', 0, 1)];
    Items[0].Hint := True;
    Favorites.Toggle(Items[1]);
    Assert.AreEqual('Open,2 Methoden von IExporter fehlen', Ordered(Items, Favorites, 'Op', Options));
  finally
    Favorites.Free;
  end;
end;

{ TAtlasFavoritesControllerTests }

procedure TAtlasFavoritesControllerTests.PinnedEntriesStayOnTopForEveryQuery;
var
  View: TFavoritesView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Favorites, Restarted: TAtlasFavorites;
  Item: TAtlasCompletionItem;
  FileName: string;
begin
  // Akzeptanz #458: Nach Anheften von Open und ParamByName stehen beide bei jeder Query oben, auch nach einem
  // Neustart (neu geladen aus der Ablage).
  View := TFavoritesView.Create;
  ViewRef := View;
  FileName := TempFile;
  Favorites := TAtlasFavorites.Create;
  Restarted := TAtlasFavorites.Create;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.Favorites := Favorites;
    Controller.GroupInherited := True;
    StartAndWait(Controller, '');
    Assert.AreEqual('ExecSQL,ParamByName,#,Active,Close,FieldByName,Open', View.Names);
    Assert.IsTrue(Controller.ToggleFavorite(PositionOf(Controller, 'Open'), Item) = TAtlasFavoriteToggle.Added);
    Assert.AreEqual('Open', Item.Name);
    Assert.IsTrue(Item.Favorite);
    Assert.IsTrue(Controller.ToggleFavorite(PositionOf(Controller, 'ParamByName'), Item) =
      TAtlasFavoriteToggle.Added);
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', View.Names, 'sofort neu sortiert');
    Assert.IsTrue(Controller.Items[Controller.Order[0]].Favorite);
    // Nächste Abfrage (andere Query, dieselben Typen): beide oben.
    StartAndWait(Controller, '');
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', View.Names);
    Controller.UpdatePrefix('e');
    Assert.AreEqual('ParamByName,Open', Copy(View.Names, 1, Length('ParamByName,Open')));
    Favorites.SaveToFile(FileName);
    // „Neustart“: neue Instanz aus der Datei.
    Restarted.LoadFromFile(FileName);
    Controller.Favorites := Restarted;
    StartAndWait(Controller, '');
    Assert.AreEqual('ParamByName,Open,ExecSQL,#,Active,Close,FieldByName', View.Names);
    // Abgeschaltet (Favorites = nil): keine Sonderstellung.
    Controller.Favorites := nil;
    StartAndWait(Controller, '');
    Assert.AreEqual('ExecSQL,ParamByName,#,Active,Close,FieldByName,Open', View.Names);
    Assert.IsTrue(Controller.ToggleSelectedFavorite(Item) = TAtlasFavoriteToggle.NotAllowed);
  finally
    Controller.Free;
    Restarted.Free;
    Favorites.Free;
    if TFile.Exists(FileName) then
      TFile.Delete(FileName);
  end;
end;

procedure TAtlasFavoritesControllerTests.SixthFavoriteChangesNothing;
var
  View: TFavoritesView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Favorites: TAtlasFavorites;
  Item: TAtlasCompletionItem;
  Index: Integer;
  Before: string;
begin
  View := TFavoritesView.Create;
  ViewRef := View;
  Favorites := TAtlasFavorites.Create;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, ViewRef);
  try
    for Index := 1 to TAtlasFavorites.MaxPerType do
      Favorites.Toggle(Member('Weitere' + IntToStr(Index), 'TDataSet', 1, 0));
    Controller.Favorites := Favorites;
    StartAndWait(Controller, '');
    Before := View.Names;
    Assert.IsTrue(Controller.ToggleFavorite(PositionOf(Controller, 'Open'), Item) = TAtlasFavoriteToggle.Full);
    Assert.AreEqual('TDataSet', TAtlasFavorites.TypeNameOf(Item), 'für den Hinweis in der Fußzeile');
    Assert.AreEqual(Before, View.Names, 'nichts geändert');
    Assert.IsFalse(Favorites.IsFavorite(Item));
    // Überschriften lassen sich nicht anheften.
    Controller.GroupInherited := True;
    StartAndWait(Controller, '');
    Assert.IsTrue(Controller.ToggleFavorite(2, Item) = TAtlasFavoriteToggle.NotAllowed, 'Überschrift');
    Assert.IsTrue(Controller.ToggleFavorite(99, Item) = TAtlasFavoriteToggle.NotAllowed);
  finally
    Controller.Free;
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesControllerTests.SelectionFollowsTheToggledEntry;
var
  View: TFavoritesView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Favorites: TAtlasFavorites;
  Item: TAtlasCompletionItem;
begin
  View := TFavoritesView.Create;
  ViewRef := View;
  Favorites := TAtlasFavorites.Create;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(QueryItems) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.Favorites := Favorites;
    StartAndWait(Controller, '');
    Assert.AreEqual('ExecSQL,ParamByName,Active,Close,FieldByName,Open', View.Names);
    Controller.HandleKey(TAtlasNavigationKey.Last);
    // Strg+D: der gewählte Eintrag wandert nach oben, die Auswahl geht mit.
    Assert.IsTrue(Controller.ToggleSelectedFavorite(Item) = TAtlasFavoriteToggle.Added);
    Assert.AreEqual('Open,ExecSQL,ParamByName,Active,Close,FieldByName', View.Names);
    Assert.AreEqual(0, View.Selected);
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Open', Item.Name);
    // Stern einer anderen Zeile: Die Auswahl bleibt auf Open.
    Assert.IsTrue(Controller.ToggleFavorite(PositionOf(Controller, 'Close'), Item) = TAtlasFavoriteToggle.Added);
    Assert.AreEqual('Close,Open,ExecSQL,ParamByName,Active,FieldByName', View.Names);
    Assert.AreEqual(1, View.Selected);
    // Lösen: zurück an den gewohnten Platz.
    Assert.IsTrue(Controller.ToggleSelectedFavorite(Item) = TAtlasFavoriteToggle.Removed);
    Assert.IsFalse(Item.Favorite);
    Assert.AreEqual('Close,ExecSQL,ParamByName,Active,FieldByName,Open', View.Names);
    Assert.AreEqual(5, View.Selected);
  finally
    Controller.Free;
    Favorites.Free;
  end;
end;

procedure TAtlasFavoritesTests.BrokenFileSetAsideLockedFileKept;
var
  Favorites: TAtlasFavorites;
  Folder, FileName: string;
  Lock: TFileStream;
begin
  Folder := TempFile + '.d';
  FileName := TPath.Combine(Folder, 'favorites.json');
  TDirectory.CreateDirectory(Folder);
  Favorites := TAtlasFavorites.Create;
  try
    TFile.WriteAllText(FileName, '{kaputt');
    Assert.IsTrue(Favorites.LoadFromFile(FileName) = TAtlasDataLoad.Renewed);
    Assert.AreEqual('{kaputt', TFile.ReadAllText(FileName + TAtlasDataFile.DefectExtension));
    Favorites.Toggle(Member('Open', 'TDataSet', 1, 0));
    Assert.IsTrue(Favorites.SaveToFile(FileName));
    Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(Favorites.LoadFromFile(FileName) = TAtlasDataLoad.Kept);
    finally
      Lock.Free;
    end;
    Assert.AreEqual(0, Integer(Favorites.Count));
    Favorites.Toggle(Member('Close', 'TDataSet', 1, 0));
    Assert.IsFalse(Favorites.SaveToFile(FileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(FileName), '"Open"');
    Assert.DoesNotContain(TFile.ReadAllText(FileName), '"Close"');
  finally
    Favorites.Free;
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFavoritesTests);
  TDUnitX.RegisterTestFixture(TAtlasFavoritesRankingTests);
  TDUnitX.RegisterTestFixture(TAtlasFavoritesControllerTests);

end.
