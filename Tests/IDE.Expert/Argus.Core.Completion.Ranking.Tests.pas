unit Argus.Core.Completion.Ranking.Tests;

// Tests für Rangfolge (#419), Filter-Chips (#422) und lernende Gewichtung (#418).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusRankingTests = class
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
  end;

  [TestFixture]
  TArgusUsageTests = class
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
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Ranking,
  Argus.Core.Completion.Usage,
  Argus.Core.Completion.Controller,
  Argus.Core.Completion.Providers.Fixed;

type
  TRecordingView = class(TInterfacedObject, IArgusCompletionView)
  public
    Names: string;
    Selected: Integer;
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
  end;

procedure TRecordingView.ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  Index: Integer;
begin
  Names := '';
  for Index in AOrder do
  begin
    if Names <> '' then
      Names := Names + ',';
    if Index = TArgusRanking.Header then
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

procedure TRecordingView.ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
begin
end;

function Member(const AName, AContainer: string; ADepth, ARank: Integer;
  AKind: TArgusItemKind = TArgusItemKind.Method): TArgusCompletionItem;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AName;
  Result.DeclaringClass := AContainer;
  Result.Depth := ADepth;
  Result.Rank := ARank;
  Result.Kind := AKind;
end;

function Names(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
  begin
    if Result <> '' then
      Result := Result + ',';
    if Index = TArgusRanking.Header then
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

function Context(const APrefix: string): TArgusContext;
begin
  Result := Default(TArgusContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

function StringsItems: TArgusCompletionItems;
begin
  // TStringList-Instanz: eigene Member, dann TStrings, dann TPersistent.
  Result := [Member('Sort', 'TStringList', 0, 0), Member('Add', 'TStrings', 1, 1),
    Member('BeginUpdate', 'TStrings', 1, 2), Member('Assign', 'TPersistent', 2, 3)];
end;

{ TArgusRankingTests }

procedure TArgusRankingTests.GroupsInheritedMembersWithHeaders;
var
  Options: TArgusRankOptions;
  Items: TArgusCompletionItems;
begin
  Items := StringsItems;
  Options := TArgusRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', Names(Items, TArgusRanking.Order(Items, '', Options)));
  Assert.AreEqual(4, TArgusRanking.ItemCount(TArgusRanking.Order(Items, '', Options)));
  // Abgeschaltet: flache Liste in der Reihenfolge der Quelle.
  Options.GroupInherited := False;
  Assert.AreEqual('Sort,Add,BeginUpdate,Assign', Names(Items, TArgusRanking.Order(Items, '', Options)));
end;

procedure TArgusRankingTests.PrefixLiftsInheritedMatchWithoutHeaders;
var
  Options: TArgusRankOptions;
  Items: TArgusCompletionItems;
begin
  // Beispiel aus #419: "Ass" liefert Assign zuerst, obwohl es geerbt ist.
  Items := StringsItems + [Member('AssignTo', 'TStringList', 0, 4)];
  Options := TArgusRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Assign,AssignTo', Names(Items, TArgusRanking.Order(Items, 'Assign', Options)));
  // Gleiche Güte: der eigene Member vor dem geerbten.
  Assert.AreEqual('AssignTo,Assign', Names(Items, TArgusRanking.Order(Items, 'Ass', Options)));
  // Ohne eigenen Treffer: das geerbte Assign zuerst, ohne Überschrift.
  Assert.AreEqual('Assign', Names(StringsItems, TArgusRanking.Order(StringsItems, 'Ass', Options)));
end;

procedure TArgusRankingTests.BoostReordersButNeverBeatsBetterMatch;
var
  Options: TArgusRankOptions;
  Items: TArgusCompletionItems;
begin
  Items := [Member('Add', '', 0, 0), Member('AddObject', '', 0, 1), Member('BeginUpdate', '', 0, 2)];
  Options := TArgusRankOptions.Defaults;
  Options.Boost :=
    function(AIndex: Integer): Integer
    begin
      if AIndex = 0 then
        Result := 0
      else
        Result := 99;
    end;
  // Ohne Präfix gewinnt das Gelernte.
  Assert.AreEqual('AddObject,BeginUpdate,Add', Names(Items, TArgusRanking.Order(Items, '', Options)));
  // Genauer Treffer bleibt vor einem gelernten Präfix-Treffer.
  Assert.AreEqual('Add,AddObject', Names(Items, TArgusRanking.Order(Items, 'Add', Options)));
end;

procedure TArgusRankingTests.ChipsFilterAndCount;
var
  Options: TArgusRankOptions;
  Items: TArgusCompletionItems;
  Counts: TArgusChipCounts;
begin
  Items := [Member('Add', '', 0, 0), Member('Count', '', 0, 1, TArgusItemKind.Property_),
    Member('OnChange', '', 0, 2, TArgusItemKind.Event), Member('Capacity', '', 0, 3, TArgusItemKind.Property_),
    Member('Total', '', 0, 4, TArgusItemKind.Variable)];
  Counts := TArgusRanking.ChipCounts(Items, '');
  Assert.AreEqual(5, Counts[TArgusChip.All]);
  Assert.AreEqual(1, Counts[TArgusChip.Methods]);
  Assert.AreEqual(2, Counts[TArgusChip.Properties]);
  Assert.AreEqual(1, Counts[TArgusChip.Events]);
  Assert.AreEqual(0, Counts[TArgusChip.Types]);
  Options := TArgusRankOptions.Defaults;
  Options.Chip := TArgusChip.Properties;
  Assert.AreEqual('Count,Capacity', Names(Items, TArgusRanking.Order(Items, '', Options)));
  Assert.AreEqual(1, TArgusRanking.ChipCounts(Items, 'cou')[TArgusChip.Properties]);
end;

procedure TArgusRankingTests.ServerGroupHeaderAndActionLast;
var
  Options: TArgusRankOptions;
  Items: TArgusCompletionItems;
begin
  // Ereignis-Zuweisung (#444): Überschrift „Passt zu …“, die neue Methode immer zuletzt und immer sichtbar.
  Items := [Member('Neue Methode btnSaveClick …', '', 0, 0), Member('FormCreate', 'TForm1', 0, 1),
    Member('Klick', 'TBasis', 1, 2)];
  Items[0].IsAction := True;
  Items[1].Group := 'Passt zu TNotifyEvent';
  Items[2].Group := 'Passt zu TNotifyEvent';
  Options := TArgusRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('#,FormCreate,Klick,Neue Methode btnSaveClick …', Names(Items, TArgusRanking.Order(Items, '', Options)));
  Assert.AreEqual('#,Klick,Neue Methode btnSaveClick …', Names(Items, TArgusRanking.Order(Items, 'Kl', Options)));
end;
{ TArgusUsageTests }

procedure TArgusUsageTests.RecordsBoostAndMarks;
var
  Usage: TArgusUsage;
  Begin_, Add: TArgusCompletionItem;
  Round: Integer;
begin
  Usage := TArgusUsage.Create;
  try
    Begin_ := Member('BeginUpdate', 'TStrings', 1, 0);
    Add := Member('Add', 'TStrings', 1, 1);
    Assert.AreEqual(0, Usage.Boost(Begin_));
    for Round := 1 to 3 do
      Usage.Record_(Begin_);
    Assert.AreEqual(75, Usage.Boost(Begin_), '3 × 15 + 30 für zuletzt');
    Assert.IsTrue(Usage.Mark(Begin_) = TArgusUsageMark.Recent);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Add) = TArgusUsageMark.Recent);
    Assert.IsTrue(Usage.Mark(Begin_) = TArgusUsageMark.None, 'erst ab 5 Übernahmen häufig');
    Usage.Record_(Begin_);
    Usage.Record_(Begin_);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Begin_) = TArgusUsageMark.Frequent);
    Assert.AreEqual(60, Usage.Boost(Begin_), 'gedeckelt, nicht mehr zuletzt');
  finally
    Usage.Free;
  end;
end;

procedure TArgusUsageTests.SavesLoadsAndClears;
var
  Usage, Loaded: TArgusUsage;
  FileName: string;
  Item: TArgusCompletionItem;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'ArgusUsage' + IntToStr(TThread.GetTickCount64) + '.json');
  Item := Member('BeginUpdate', 'TStrings', 1, 0);
  Usage := TArgusUsage.Create;
  Loaded := TArgusUsage.Create;
  try
    Usage.Record_(Item);
    Usage.Record_(Item);
    Assert.IsTrue(Usage.Changed);
    Usage.SaveToFile(FileName);
    Assert.IsFalse(Usage.Changed);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(Usage.Boost(Item), Loaded.Boost(Item));
    Assert.IsTrue(Loaded.Mark(Item) = TArgusUsageMark.Recent);
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

procedure TArgusUsageTests.LearnedEntryRisesInController;
var
  View: TRecordingView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
  Usage: TArgusUsage;
  Round: Integer;
  Item: TArgusCompletionItem;
begin
  // Akzeptanz #418: nach dreimaliger Übernahme von BeginUpdate steht es ohne Präfix vor Add.
  View := TRecordingView.Create;
  ViewRef := View;
  Usage := TArgusUsage.Create;
  Controller := TArgusCompletionController.Create(TArgusFixedCompletionProvider.Create(
    [Member('Add', 'TStrings', 0, 0), Member('BeginUpdate', 'TStrings', 0, 1)]) as IArgusCompletionProvider, ViewRef);
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
    Assert.IsTrue(Item.Usage = TArgusUsageMark.Recent);
  finally
    Controller.Free;
    Usage.Free;
  end;
end;

procedure TArgusUsageTests.SelectionSkipsHeaders;
var
  View: TRecordingView;
  ViewRef: IArgusCompletionView;
  Controller: TArgusCompletionController;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TArgusCompletionController.Create(TArgusFixedCompletionProvider.Create(StringsItems)
    as IArgusCompletionProvider, ViewRef);
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
    Controller.HandleKey(TArgusNavigationKey.Down);
    Assert.AreEqual(2, View.Selected, 'Überschrift übersprungen');
    Controller.HandleKey(TArgusNavigationKey.Up);
    Assert.AreEqual(0, View.Selected);
    Controller.HandleKey(TArgusNavigationKey.Last);
    Assert.AreEqual(5, View.Selected);
    Controller.HandleKey(TArgusNavigationKey.Up);
    Assert.AreEqual(3, View.Selected);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusRankingTests);
  TDUnitX.RegisterTestFixture(TArgusUsageTests);

end.
