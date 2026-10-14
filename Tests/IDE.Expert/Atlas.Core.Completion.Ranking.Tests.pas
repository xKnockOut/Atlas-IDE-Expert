unit Atlas.Core.Completion.Ranking.Tests;

// Tests für Rangfolge (#419), Filter-Chips (#422), lernende Gewichtung (#418) und Formular-Komponenten (#455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRankingTests = class
  public
    [Test]
    procedure GroupsInheritedMembersWithHeaders;
    [Test]
    procedure PrefixLiftsInheritedMatchWithoutHeaders;
    [Test]
    procedure BoostReordersButNeverBeatsBetterMatch;
    [Test]
    procedure ChipsFilterAndCount;
    [Test]
    procedure ServerGroupHeaderAndActionLast;
    [Test]
    procedure FormComponentsComeFirst;
    [Test]
    procedure SenderItemsGetHeaderAndTag;
    [Test]
    procedure DataNamesCarrySource;
  end;

  [TestFixture]
  TAtlasUsageTests = class
  public
    [Test]
    procedure RecordsBoostAndMarks;
    [Test]
    procedure SavesLoadsAndClears;
    [Test]
    procedure LearnedEntryRisesInController;
    [Test]
    procedure SelectionSkipsHeaders;
    [Test]
    procedure TypingDiscardsGuardOffer;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Completion.Usage,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server;

type
  TRecordingView = class(TInterfacedObject, IAtlasCompletionView)
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

procedure TRecordingView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  Index: Integer;
begin
  Names := '';
  for Index in AOrder do
  begin
    if Names <> '' then
      Names := Names + ',';
    if TAtlasRanking.IsHeader(Index) then
      Names := Names + '#'
    else
      Names := Names + AItems[Index].Name;
  end;
  Selected := ASelected;
end;

procedure TRecordingView.HideList;
begin
end;

procedure TRecordingView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
end;

function TRecordingView.PageSize: Integer;
begin
  Result := 9;
end;

procedure TRecordingView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
begin
end;

function Member(const AName, AContainer: string; ADepth, ARank: Integer;
  AKind: TAtlasItemKind = TAtlasItemKind.Method): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.DeclaringClass := AContainer;
  Result.Depth := ADepth;
  Result.Rank := ARank;
  Result.Kind := AKind;
end;

function Names(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
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

function Context(const APrefix: string): TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

function StringsItems: TAtlasCompletionItems;
begin
  // TStringList-Instanz: eigene Member, dann TStrings, dann TPersistent.
  Result := [Member('Sort', 'TStringList', 0, 0), Member('Add', 'TStrings', 1, 1),
    Member('BeginUpdate', 'TStrings', 1, 2), Member('Assign', 'TPersistent', 2, 3)];
end;

{ TAtlasRankingTests }

procedure TAtlasRankingTests.GroupsInheritedMembersWithHeaders;
var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  Items := StringsItems;
  Options := TAtlasRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  Assert.AreEqual(4, TAtlasRanking.ItemCount(TAtlasRanking.Order(Items, '', Options)));
  // Abgeschaltet: flache Liste in der Reihenfolge der Quelle.
  Options.GroupInherited := False;
  Assert.AreEqual('Sort,Add,BeginUpdate,Assign', Names(Items, TAtlasRanking.Order(Items, '', Options)));
end;

procedure TAtlasRankingTests.PrefixLiftsInheritedMatchWithoutHeaders;
var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  // Beispiel aus #419: "Ass" liefert Assign zuerst, obwohl es geerbt ist.
  Items := StringsItems + [Member('AssignTo', 'TStringList', 0, 4)];
  Options := TAtlasRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Assign,AssignTo', Names(Items, TAtlasRanking.Order(Items, 'Assign', Options)));
  // Gleiche Güte: der eigene Member vor dem geerbten.
  Assert.AreEqual('AssignTo,Assign', Names(Items, TAtlasRanking.Order(Items, 'Ass', Options)));
  // Ohne eigenen Treffer: das geerbte Assign zuerst, ohne Überschrift.
  Assert.AreEqual('Assign', Names(StringsItems, TAtlasRanking.Order(StringsItems, 'Ass', Options)));
end;

procedure TAtlasRankingTests.BoostReordersButNeverBeatsBetterMatch;
var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  Items := [Member('Add', '', 0, 0), Member('AddObject', '', 0, 1), Member('BeginUpdate', '', 0, 2)];
  Options := TAtlasRankOptions.Defaults;
  Options.Boost :=
    function(AIndex: Integer): Integer
    begin
      if AIndex = 0 then
        Result := 0
      else
        Result := 99;
    end;
  // Ohne Präfix gewinnt das Gelernte.
  Assert.AreEqual('AddObject,BeginUpdate,Add', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  // Genauer Treffer bleibt vor einem gelernten Präfix-Treffer.
  Assert.AreEqual('Add,AddObject', Names(Items, TAtlasRanking.Order(Items, 'Add', Options)));
end;

procedure TAtlasRankingTests.ChipsFilterAndCount;
var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
  Counts: TAtlasChipCounts;
begin
  Items := [Member('Add', '', 0, 0), Member('Count', '', 0, 1, TAtlasItemKind.Property_),
    Member('OnChange', '', 0, 2, TAtlasItemKind.Event), Member('Capacity', '', 0, 3, TAtlasItemKind.Property_),
    Member('Total', '', 0, 4, TAtlasItemKind.Variable)];
  Counts := TAtlasRanking.ChipCounts(Items, '');
  Assert.AreEqual(5, Counts[TAtlasChip.All]);
  Assert.AreEqual(1, Counts[TAtlasChip.Methods]);
  Assert.AreEqual(2, Counts[TAtlasChip.Properties]);
  Assert.AreEqual(1, Counts[TAtlasChip.Events]);
  Assert.AreEqual(0, Counts[TAtlasChip.Types]);
  Options := TAtlasRankOptions.Defaults;
  Options.Chip := TAtlasChip.Properties;
  Assert.AreEqual('Count,Capacity', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  Assert.AreEqual(1, TAtlasRanking.ChipCounts(Items, 'cou')[TAtlasChip.Properties]);
end;

procedure TAtlasRankingTests.ServerGroupHeaderAndActionLast;
var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  // Ereignis-Zuweisung (#444): Überschrift „Passt zu …“, die neue Methode immer zuletzt und immer sichtbar.
  Items := [Member('Neue Methode btnSaveClick …', '', 0, 0), Member('FormCreate', 'TForm1', 0, 1),
    Member('Klick', 'TBasis', 1, 2)];
  Items[0].IsAction := True;
  Items[1].ExpectedType := 'TNotifyEvent';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'TNotifyEvent';
  Items[2].Fits := True;
  Options := TAtlasRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('#,FormCreate,Klick,Neue Methode btnSaveClick …', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  Assert.AreEqual('#,Klick,Neue Methode btnSaveClick …', Names(Items, TAtlasRanking.Order(Items, 'Kl', Options)));
  // Erwarteter Typ (#417): Passende oben, auch wenn ein übriger Eintrag besser zum Präfix passt.
  Items := [Member('Count', '', 0, 0), Member('Capacity', '', 0, 1), Member('Clear', '', 0, 2)];
  Items[0].ExpectedType := 'Integer';
  Items[1].ExpectedType := 'Integer';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'Integer';
  Items[2].Fits := True;
  Assert.AreEqual('#,Capacity,Clear,#,Count', Names(Items, TAtlasRanking.Order(Items, 'C', Options)));
  Assert.AreEqual('#,Count', Names(Items, TAtlasRanking.Order(Items, 'Cou', Options)));
end;
procedure TAtlasRankingTests.FormComponentsComeFirst;
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
begin
  // Komponenten aus dem Formular (#455): eigene Gruppe vor allem anderen, Typtreffer hinter Namenstreffern.
  Json := TJSONObject.ParseJSONValue('{"label":"btnSave","kind":5,"detail":"TButton","data":{"form":"frmMain",' +
    '"byType":true,"scope":3}}') as TJSONObject;
  try
    Items := [Member('TButton', '', 0, 0, TAtlasItemKind.Class_), TAtlasServerCompletionProvider.ItemFromLsp(Json, 1),
      Member('btnButtonLeiste', '', 0, 2)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('frmMain', Items[1].Form);
  Assert.IsTrue(Items[1].ByType);
  Items[2].Form := 'frmMain';
  Options := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,btnButtonLeiste,btnSave,#,TButton', Names(Items, TAtlasRanking.Order(Items, 'button', Options)));
  // Ohne Formulareinträge keine Überschrift.
  Items := Copy(Items, 0, 1);
  Assert.AreEqual('TButton', Names(Items, TAtlasRanking.Order(Items, 'button', Options)));
end;

procedure TAtlasRankingTests.SenderItemsGetHeaderAndTag;
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
  Tags: TAtlasTags;
  Found: Boolean;
  Tag: TAtlasTag;
begin
  // Sender mit Typumwandlung (#480): eine Überschrift über der Liste, Marke „als TButton“.
  Json := TJSONObject.ParseJSONValue('{"label":"Caption","kind":10,"detail":"string","data":{"sender":"TButton",' +
    '"senderOf":"btnSave, btnLoad","scope":3}}') as TJSONObject;
  try
    Items := [TAtlasServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('TButton', Items[0].Sender);
  Assert.AreEqual('btnSave, btnLoad', Items[0].SenderOf);
  Options := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,Caption', Names(Items, TAtlasRanking.Order(Items, 'Cap', Options)));
  Tags := TAtlasItemPresentation.Tags(Items[0]);
  Found := False;
  for Tag in Tags do
    if Tag.Text = 'als TButton' then
      Found := True;
  Assert.IsTrue(Found);
  // Ohne Sender keine Überschrift.
  Items[0].Sender := '';
  Assert.AreEqual('Caption', Names(Items, TAtlasRanking.Order(Items, 'Cap', Options)));
end;

procedure TAtlasRankingTests.DataNamesCarrySource;
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
begin
  // Feld- und Parameternamen (#461): Datenmenge und SQL-Anweisung für die Fußzeile.
  Json := TJSONObject.ParseJSONValue('{"label":"CUSTOMER_ID","kind":5,"detail":"Integer","data":{' +
    '"dataSet":"qryOrders","dataSource":"select CUSTOMER_ID from ORDERS"}}') as TJSONObject;
  try
    Items := [Member('Capacity', '', 0, 0), TAtlasServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('qryOrders', Items[1].DataSet);
  Assert.AreEqual('select CUSTOMER_ID from ORDERS', TAtlasItemPresentation.DataSource(Items));
  Assert.AreEqual('', TAtlasItemPresentation.DataSource(Copy(Items, 0, 1)));
end;

{ TAtlasUsageTests }

procedure TAtlasUsageTests.RecordsBoostAndMarks;
var
  Usage: TAtlasUsage;
  Begin_, Add: TAtlasCompletionItem;
  Round: Integer;
begin
  Usage := TAtlasUsage.Create;
  try
    Begin_ := Member('BeginUpdate', 'TStrings', 1, 0);
    Add := Member('Add', 'TStrings', 1, 1);
    Assert.AreEqual(0, Usage.Boost(Begin_));
    for Round := 1 to 3 do
      Usage.Record_(Begin_);
    Assert.AreEqual(75, Usage.Boost(Begin_), '3 × 15 + 30 für zuletzt');
    Assert.IsTrue(Usage.Mark(Begin_) = TAtlasUsageMark.Recent);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Add) = TAtlasUsageMark.Recent);
    Assert.IsTrue(Usage.Mark(Begin_) = TAtlasUsageMark.None, 'erst ab 5 Übernahmen häufig');
    Usage.Record_(Begin_);
    Usage.Record_(Begin_);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Begin_) = TAtlasUsageMark.Frequent);
    Assert.AreEqual(60, Usage.Boost(Begin_), 'gedeckelt, nicht mehr zuletzt');
  finally
    Usage.Free;
  end;
end;

procedure TAtlasUsageTests.SavesLoadsAndClears;
var
  Usage, Loaded: TAtlasUsage;
  FileName: string;
  Item: TAtlasCompletionItem;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'AtlasUsage' + IntToStr(TThread.GetTickCount64) + '.json');
  Item := Member('BeginUpdate', 'TStrings', 1, 0);
  Usage := TAtlasUsage.Create;
  Loaded := TAtlasUsage.Create;
  try
    Usage.Record_(Item);
    Usage.Record_(Item);
    Assert.IsTrue(Usage.Changed);
    Usage.SaveToFile(FileName);
    Assert.IsFalse(Usage.Changed);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(Usage.Boost(Item), Loaded.Boost(Item));
    Assert.IsTrue(Loaded.Mark(Item) = TAtlasUsageMark.Recent);
    Loaded.Clear;
    Assert.AreEqual(0, Loaded.Boost(Item));
    // Fehlende Datei: leer, kein Fehler.
    Loaded.LoadFromFile(FileName + '.fehlt');
    Assert.AreEqual(0, Loaded.Count);
  finally
    Loaded.Free;
    Usage.Free;
    TFile.Delete(FileName);
  end;
end;

procedure TAtlasUsageTests.LearnedEntryRisesInController;
var
  View: TRecordingView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Usage: TAtlasUsage;
  Round: Integer;
  Item: TAtlasCompletionItem;
begin
  // Akzeptanz #418: nach dreimaliger Übernahme von BeginUpdate steht es ohne Präfix vor Add.
  View := TRecordingView.Create;
  ViewRef := View;
  Usage := TAtlasUsage.Create;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(
    [Member('Add', 'TStrings', 0, 0), Member('BeginUpdate', 'TStrings', 0, 1)]) as IAtlasCompletionProvider, ViewRef);
  try
    Controller.Usage := Usage;
    for Round := 1 to 3 do
      Usage.Record_(Member('BeginUpdate', 'TStrings', 0, 1));
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('BeginUpdate,Add', View.Names);
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.IsTrue(Item.Usage = TAtlasUsageMark.Recent);
  finally
    Controller.Free;
    Usage.Free;
  end;
end;

procedure TAtlasUsageTests.SelectionSkipsHeaders;
var
  View: TRecordingView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(StringsItems)
    as IAtlasCompletionProvider, ViewRef);
  try
    Controller.GroupInherited := True;
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', View.Names);
    Assert.AreEqual(0, View.Selected);
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(2, View.Selected, 'Überschrift übersprungen');
    Controller.HandleKey(TAtlasNavigationKey.Up);
    Assert.AreEqual(0, View.Selected);
    Controller.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(5, View.Selected);
    Controller.HandleKey(TAtlasNavigationKey.Up);
    Assert.AreEqual(3, View.Selected);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRankingTests);
  TDUnitX.RegisterTestFixture(TAtlasUsageTests);

procedure TAtlasUsageTests.TypingDiscardsGuardOffer;
var
  View: TRecordingView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Json: TJSONObject;
  Guard: TAtlasCompletionItem;
  Item: TAtlasCompletionItem;
begin
  // Freigabe absichern (#489): Das Angebot ist gewählt; jedes getippte Zeichen schließt die Liste.
  Json := TJSONObject.ParseJSONValue('{"label":"Mit try…finally absichern","kind":15,"detail":"List.Free",' +
    '"data":{"guard":"newLine"}}') as TJSONObject;
  try
    Guard := TAtlasServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Guard.Guard);
  Assert.IsTrue(TAtlasItemPresentation.Guarding([Guard]));
  Assert.IsFalse(TAtlasItemPresentation.Guarding([Guard, Member('Add', 'TStrings', 0, 0)]));
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([Guard]) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Mit try…finally absichern', Item.Name);
    Controller.UpdatePrefix('L');
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

end.
