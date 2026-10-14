unit Atlas.Core.Completion.Ranking.Tests;

// Tests für Rangfolge (#419), Filter-Chips (#422) und lernende Gewichtung (#418).

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Usage,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Providers.Fixed;

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

end.
