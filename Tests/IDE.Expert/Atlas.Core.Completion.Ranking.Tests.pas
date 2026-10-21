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
    procedure ScopeOrdersAfterExpectedTypeBeforeBoost;
    [Test]
    procedure PrefixLiftsInheritedMatchWithoutHeaders;
    [Test]
    procedure BoostReordersButNeverBeatsBetterMatch;
    [Test]
    procedure ChipsFilterAndCount;
    [Test]
    procedure ServerGroupHeaderAndActionLast;
    [Test]
    procedure PostfixAfterMembers;
    [Test]
    procedure FormComponentsComeFirst;
    [Test]
    procedure SenderItemsGetHeaderAndTag;
    [Test]
    procedure ConversionStandsBeforeOriginal;
    [Test]
    procedure TypeArgumentsGetHeaderAndFooter;
    [Test]
    procedure DataNamesCarrySource;
    [Test]
    procedure UsesUnitsGroupedWithHeaders;
    [Test]
    procedure InheritedCallsFirstWithTags;
    [Test]
    procedure ListModeFilterShowsOnlyMatches;
    [Test]
    procedure ListModeAllAppendsRestWithoutHeader;
    [Test]
    procedure ListModeRestUnderHeader;
    [Test]
    procedure ListModeRestSkipsTyposAndEmptyPattern;
    [Test]
    procedure ListModeNames;
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
    [Test]
    procedure RestOnlyInMemberListsByDefault;
    [Test]
    procedure RestWithoutMatchSelectsNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
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

function RestItems: TAtlasCompletionItems;
begin
  Result := [Member('Add', 'TStrings', 0, 0), Member('Assign', 'TPersistent', 0, 1),
    Member('BeginUpdate', 'TStrings', 0, 2), Member('Clear', 'TStrings', 0, 3), Member('Sort', 'TStringList', 0, 4)];
end;

function RestOptions(AMode: TAtlasListMode): TAtlasRankOptions;
begin
  Result := TAtlasRankOptions.Defaults;
  Result.ListMode := AMode;
end;

{ TAtlasRankingTests }

procedure TAtlasRankingTests.ListModeFilterShowsOnlyMatches;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  // Heutiger Stand (#497, Variante 1): nur Treffer.
  Items := RestItems;
  Order := TAtlasRanking.Order(Items, 'As', RestOptions(TAtlasListMode.Filter), RestStart);
  Assert.AreEqual('Assign', Names(Items, Order));
  Assert.AreEqual(-1, RestStart);
end;

procedure TAtlasRankingTests.ListModeAllAppendsRestWithoutHeader;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  // Variante 2: alles sichtbar, Treffer oben, der Rest in Rangfolge ohne Überschrift.
  Items := RestItems;
  Order := TAtlasRanking.Order(Items, 'As', RestOptions(TAtlasListMode.All), RestStart);
  Assert.AreEqual('Assign,Add,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(1, RestStart);
end;

procedure TAtlasRankingTests.ListModeRestUnderHeader;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
  Options: TAtlasRankOptions;
begin
  // Variante 3: Treffer, darunter abgesetzt „Weitere Einträge“.
  Items := RestItems;
  Order := TAtlasRanking.Order(Items, 'As', RestOptions(TAtlasListMode.Rest), RestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(TAtlasRanking.RestHeader, Order[1]);
  Assert.AreEqual(2, RestStart);
  // Der Chip schränkt auch den Rest ein.
  Items := Items + [Member('Count', 'TStrings', 0, 5, TAtlasItemKind.Property_)];
  Order := TAtlasRanking.Order(Items, 'As', RestOptions(TAtlasListMode.Rest), RestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort,Count', Names(Items, Order));
  Options := RestOptions(TAtlasListMode.Rest);
  Options.Chip := TAtlasChip.Methods;
  Order := TAtlasRanking.Order(Items, 'Co', Options, RestStart);
  Assert.AreEqual('#,Add,Assign,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(1, RestStart);
  Items := nil;
  Order := nil;
end;

procedure TAtlasRankingTests.ListModeRestSkipsTyposAndEmptyPattern;
var
  Items: TAtlasCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  Items := RestItems;
  // Ohne Präfix gibt es keinen Rest: alle Einträge sind Treffer.
  Order := TAtlasRanking.Order(Items, '', RestOptions(TAtlasListMode.Rest), RestStart);
  Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(-1, RestStart);
  // Tippfehler (#485) stehen unter „Meintest du“ und nicht noch einmal im Rest.
  Order := TAtlasRanking.Order(Items, 'Cleer', RestOptions(TAtlasListMode.Rest), RestStart);
  Assert.AreEqual('#,Clear,#,Add,Assign,BeginUpdate,Sort', Names(Items, Order));
  Assert.AreEqual(TAtlasRanking.TypoHeader, Order[0]);
  Assert.AreEqual(TAtlasRanking.RestHeader, Order[2]);
  Assert.AreEqual(3, RestStart);
  Items := nil;
  Order := nil;
end;

procedure TAtlasRankingTests.ListModeNames;
begin
  Assert.IsTrue(TAtlasListModes.ModeOf('filter') = TAtlasListMode.Filter);
  Assert.IsTrue(TAtlasListModes.ModeOf(' ALL ') = TAtlasListMode.All);
  Assert.IsTrue(TAtlasListModes.ModeOf('rest') = TAtlasListMode.Rest);
  Assert.IsTrue(TAtlasListModes.ModeOf('alles') = TAtlasListMode.Filter, 'Unbekanntes wird Filter');
  Assert.IsTrue(TAtlasListModes.ScopeOf('everywhere') = TAtlasListScope.Everywhere);
  Assert.IsTrue(TAtlasListModes.ScopeOf('') = TAtlasListScope.Members);
end;

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

procedure TAtlasRankingTests.ScopeOrdersAfterExpectedTypeBeforeBoost;

  function Scoped(const AName: string; AScope: Integer): TAtlasCompletionItem;
  begin
    Result := Member(AName, '', 0, 0, TAtlasItemKind.Variable);
    Result.Scope := AScope;
  end;

var
  Options: TAtlasRankOptions;
  Items: TAtlasCompletionItems;
begin
  // #488: Präfix-Güte → erwarteter Typ → Bereich → Lerngewicht → Name.
  Items := [Scoped('FDiscount', 3), Scoped('ACustomer', 2), Scoped('Total', 1), Scoped('Format', 5),
    Scoped('TKasse', 4)];
  Options := TAtlasRankOptions.Defaults;
  Options.Boost :=
    function(AIndex: Integer): Integer
    begin
      // FDiscount ist gelernt, schlägt aber keinen näheren Bereich.
      if AIndex = 0 then
        Result := 99
      else
        Result := 0;
    end;
  Assert.AreEqual('Total,ACustomer,FDiscount,TKasse,Format', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  // Erwarteter Typ vor Bereich: Nur ACustomer passt.
  Items[1].ExpectedType := 'Integer';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'Integer';
  Assert.AreEqual('#,ACustomer,#,Total,FDiscount,TKasse,Format',
    Names(Items, TAtlasRanking.Order(Items, '', Options)));
  // Mit Präfix: bessere Güte vor Bereich, bei gleicher Güte der nähere Bereich.
  Items := [Scoped('Totalbetrag', 5), Scoped('Total', 4), Scoped('TotalLokal', 1)];
  Assert.AreEqual('Total,TotalLokal,Totalbetrag', Names(Items, TAtlasRanking.Order(Items, 'Total', Options)));
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

procedure TAtlasRankingTests.PostfixAfterMembers;
var
  Items: TAtlasCompletionItems;
begin
  // Postfix-Vorlagen (#188) stehen hinter allen echten Mitgliedern, auch wenn sie genauer passen.
  Items := [Member('tryf', '', 0, 0, TAtlasItemKind.Snippet), Member('tryfNext', '', 0, 1),
    Member('TryFoo', '', 0, 2)];
  Items[0].Postfix := True;
  Items[0].FilterText := 'tryf';
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(Items, TAtlasRanking.Order(Items, 'tryf',
    TAtlasRankOptions.Defaults)));
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(Items, TAtlasRanking.Order(Items, '', TAtlasRankOptions.Defaults)));
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

procedure TAtlasRankingTests.ConversionStandsBeforeOriginal;
const
  Answers: array[0..3] of string = (
    '{"label":"Count.ToString","kind":5,"detail":"Integer","filterText":"Count","data":{"expected":"string",' +
      '"conversion":"string","convertFrom":"Count","scope":0}}',
    '{"label":"Text","kind":5,"detail":"string","data":{"expected":"string","fits":true}}',
    '{"label":"Count","kind":5,"detail":"Integer","data":{"expected":"string"}}',
    '{"label":"Preis","kind":5,"detail":"Double","data":{"expected":"Integer","lossy":"Double"}}');
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
  Tag: TAtlasTag;
  Found: Boolean;
  Answer: string;
begin
  // Typkonvertierung (#490): „Count.ToString → string“ direkt über Count, gefiltert nach dem Namen des Originals.
  Items := nil;
  for Answer in Answers do
  begin
    Json := TJSONObject.ParseJSONValue(Answer) as TJSONObject;
    try
      Items := Items + [TAtlasServerCompletionProvider.ItemFromLsp(Json, Length(Items))];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('string', Items[0].Conversion);
  Assert.AreEqual('Count', Items[0].ConvertFrom);
  Assert.AreEqual('Count', Items[0].FilterText);
  Assert.AreEqual('Double', Items[3].Lossy);
  Items[1].Fits := True;
  Options := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,Count.ToString,Count', Names(Items, TAtlasRanking.Order(Items, 'Cou', Options)));
  Assert.AreEqual('#,Text,#,Count.ToString,Count,Preis', Names(Items, TAtlasRanking.Order(Items, '', Options)));
  // Ohne sichtbares Original auch keine Umwandlung; gezählt wird sie nicht.
  Assert.AreEqual('#,Text', Names(Items, TAtlasRanking.Order(Items, 'Tex', Options)));
  Assert.AreEqual(1, TAtlasRanking.ChipCounts(Items, 'Cou')[TAtlasChip.All]);
  Found := False;
  for Tag in TAtlasItemPresentation.Tags(Items[0]) do
    if Tag.Text = '→ string' then
      Found := True;
  Assert.IsTrue(Found);
end;

procedure TAtlasRankingTests.TypeArgumentsGetHeaderAndFooter;
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Options: TAtlasRankOptions;
begin
  // Typargumente (#450): eine Überschrift mit dem Constraint über der Liste, ausgeblendete Arten für die Fußzeile.
  Json := TJSONObject.ParseJSONValue('{"label":"TKunde","kind":7,"detail":"Listen","data":{"typeParam":"T",' +
    '"constraint":"class","constraintHint":"classes","hiddenKinds":"records,enums"}}') as TJSONObject;
  try
    Items := [TAtlasServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('T', Items[0].TypeParam);
  Assert.AreEqual('class', Items[0].Constraint);
  Assert.AreEqual('classes', Items[0].ConstraintHint);
  Assert.AreEqual('records,enums', TAtlasItemPresentation.HiddenKinds(Items));
  Options := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,TKunde', Names(Items, TAtlasRanking.Order(Items, 'TK', Options)));
  Items[0].TypeParam := '';
  Assert.AreEqual('TKunde', Names(Items, TAtlasRanking.Order(Items, 'TK', Options)));
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

procedure TAtlasRankingTests.InheritedCallsFirstWithTags;
const
  Lines: array[0..3] of string = (
    '{"label":"Free","kind":2,"data":{"container":"TObject","depth":3}}',
    '{"label":"CreateNew(AOwner, Dummy)","filterText":"CreateNew","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"other","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"Create(AOwner)","filterText":"Create","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"same","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"CreateParented(ParentWindow)","filterText":"CreateParented","kind":4,"detail":"TWinControl",' +
      '"data":{"container":"TWinControl","depth":2,"inheritedMatch":"other"}}');
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Index: Integer;
  Tags: TAtlasTags;
  Found: Boolean;
  Tag: TAtlasTag;
begin
  // Nach "inherited " (#482): der Aufruf mit gleichen Parametern zuerst, dann die übrigen Konstruktoren.
  Items := nil;
  for Index := 0 to High(Lines) do
  begin
    Json := TJSONObject.ParseJSONValue(Lines[Index]) as TJSONObject;
    try
      Items := Items + [TAtlasServerCompletionProvider.ItemFromLsp(Json, Index)];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('Create(AOwner),CreateNew(AOwner, Dummy),CreateParented(ParentWindow)',
    Names(Items, TAtlasRanking.Order(Items, 'Cre', TAtlasRankOptions.Defaults)));
  Tags := TAtlasItemPresentation.Tags(Items[2]);
  Found := False;
  for Tag in Tags do
    if Tag.Id = TAtlasTagId.SameParams then
      Found := True;
  Assert.IsTrue(Found);
  // Weitere Konstruktoren tragen die deklarierende Klasse.
  Found := False;
  for Tag in TAtlasItemPresentation.Tags(Items[3]) do
    if Tag.Text = 'TWinControl' then
      Found := True;
  Assert.IsTrue(Found);
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', TAtlasItemPresentation.InheritedAbstract(Items)));
end;

procedure TAtlasRankingTests.UsesUnitsGroupedWithHeaders;
const
  Lines: array[0..3] of string = (
    '{"label":"Spring.Collections.Generic","kind":9,"data":{"usesGroup":"library","usesFilter":"Generic"}}',
    '{"label":"System.Generics.Collections","kind":9,' +
      '"detail":"$(BDS)\\source\\rtl\\common\\System.Generics.Collections.pas","data":{"usesGroup":"rtl",' +
      '"usesFilter":"Generics.Collections","usesTypes":["TList<T>","TObjectList<T>"],"usesTypeCount":7,' +
      '"usesHidden":["System.SysUtils"]}}',
    '{"label":"System.Generics.Defaults","kind":9,"data":{"usesGroup":"rtl","usesFilter":"Generics.Defaults",' +
      '"usesElsewhere":"implementation"}}',
    '{"label":"uGeneratorBeleg","kind":9,"detail":"C:\\P\\uGeneratorBeleg.pas","data":{"usesGroup":"project",' +
      '"usesCycle":"uGeneratorBeleg → Haupt"}}');
var
  Json: TJSONObject;
  Items: TAtlasCompletionItems;
  Index: Integer;
  Tags: TAtlasTags;
  Details: TAtlasItemDetails;
begin
  // uses-Abschnitt (#469): Projekt vor RTL/VCL vor Drittanbietern, je Gruppe eine Überschrift; gefiltert wird nach
  // dem Namensteil ab dem Getippten.
  Items := nil;
  for Index := 0 to High(Lines) do
  begin
    Json := TJSONObject.ParseJSONValue(Lines[Index]) as TJSONObject;
    try
      Items := Items + [TAtlasServerCompletionProvider.ItemFromLsp(Json, Index)];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('Generics.Collections', Items[1].FilterText);
  Assert.AreEqual('#,uGeneratorBeleg,#,System.Generics.Collections,System.Generics.Defaults,#,' +
    'Spring.Collections.Generic', Names(Items, TAtlasRanking.Order(Items, 'Gener', TAtlasRankOptions.Defaults)));
  Assert.AreEqual('#,System.Generics.Defaults',
    Names(Items, TAtlasRanking.Order(Items, 'Defau', TAtlasRankOptions.Defaults)));
  // Zirkelbezug als Marke in Fehlerfarbe, anderer Abschnitt rechts, kein Dateiname.
  Tags := TAtlasItemPresentation.Tags(Items[3]);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.IsTrue(Tags[0].Kind = TAtlasTagKind.Error);
  Assert.IsTrue(Tags[0].Id = TAtlasTagId.Cycle);
  Assert.AreEqual('', TAtlasItemPresentation.Detail(Items[3]));
  Assert.AreEqual('bereits im implementation-Teil', TAtlasItemPresentation.Detail(Items[2]));
  Assert.AreEqual(1, Integer(Length(TAtlasItemPresentation.UsesHidden(Items))));
  Assert.AreEqual('System.SysUtils', TAtlasItemPresentation.UsesHidden(Items)[0]);
  // Detailpanel ohne Server: Deklaration, Pfad, Typen samt Gesamtzahl.
  Details := TAtlasItemPresentation.UsesDetails(Items[1]);
  Assert.AreEqual('unit System.Generics.Collections', Details.Declaration);
  Assert.AreEqual('$(BDS)\source\rtl\common\System.Generics.Collections.pas', Details.UnitPath);
  Assert.AreEqual(2, Integer(Length(Details.UnitTypes)));
  Assert.AreEqual(7, Details.UnitTypeCount);
  Assert.IsFalse(Details.IsEmpty);
  Assert.AreEqual('uGeneratorBeleg → Haupt', TAtlasItemPresentation.UsesDetails(Items[3]).UsesCycle);
  Assert.AreEqual('implementation', TAtlasItemPresentation.UsesDetails(Items[2]).UsesElsewhere);
  // Ohne Gruppe (Schalter aus): keine Überschriften.
  for Index := 0 to High(Items) do
    Items[Index].UsesGroup := '';
  Assert.IsFalse(Names(Items, TAtlasRanking.Order(Items, 'Gener', TAtlasRankOptions.Defaults)).Contains('#'));
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
    Assert.AreEqual(0, Integer(Loaded.Count));
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

function MemberContext(const APrefix: string): TAtlasContext;
begin
  Result := Context(APrefix);
  Result.Kind := TAtlasContextKind.MemberAccess;
end;

procedure TAtlasUsageTests.RestOnlyInMemberListsByDefault;
var
  View: TRecordingView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(RestItems) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.ListMode := TAtlasListMode.Rest;
    // Strg+Leer (alle sichtbaren Namen): nur Treffer, solange der Bereich Members ist.
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign', View.Names);
    Assert.AreEqual(-1, Controller.RestStart);
    // Nach ".": Treffer, darunter der Rest.
    Controller.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', View.Names);
    Assert.AreEqual(0, View.Selected, 'Bester Treffer gewählt');
    Assert.AreEqual(2, Controller.RestStart);
    // Bild↓/Ende überspringen die Überschrift und erreichen das Ende des Rests.
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(2, View.Selected, 'Überschrift übersprungen');
    Controller.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(5, View.Selected);
    // Überall: auch ohne ".".
    Controller.ListScope := TAtlasListScope.Everywhere;
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasUsageTests.RestWithoutMatchSelectsNothing;
var
  View: TRecordingView;
  ViewRef: IAtlasCompletionView;
  Controller: TAtlasCompletionController;
  Item: TAtlasCompletionItem;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(RestItems) as
    IAtlasCompletionProvider, ViewRef);
  try
    Controller.ListMode := TAtlasListMode.All;
    Controller.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Kein Treffer für "Zq": alles sichtbar, nichts gewählt; Enter gehört dem Editor.
    Controller.UpdatePrefix('Zq');
    Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', View.Names);
    Assert.AreEqual(0, Controller.RestStart);
    Assert.IsTrue(Controller.Passive);
    Assert.AreEqual(-1, View.Selected);
    Assert.IsFalse(Controller.CanCommitOnCharacter);
    // Eine Pfeiltaste wählt den ersten Eintrag.
    Controller.HandleKey(TAtlasNavigationKey.Down);
    Assert.IsFalse(Controller.Passive);
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Add', Item.Name);
    // Mit Treffer wieder der beste gewählt.
    Controller.UpdatePrefix('Cl');
    Assert.AreEqual('Clear,Add,Assign,BeginUpdate,Sort', View.Names);
    Assert.AreEqual(0, View.Selected);
    Assert.IsFalse(Controller.Passive);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRankingTests);
  TDUnitX.RegisterTestFixture(TAtlasUsageTests);

end.
