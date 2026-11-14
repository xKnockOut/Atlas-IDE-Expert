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
    /// <summary>#2107: Mitglieder nach einer is-Prüfung oben mit Überschrift, die übrigen unter „Weitere“.
    /// </summary>
    [Test]
    procedure NarrowedMembersComeFirstWithHeader;
    /// <summary>#2107: Nachfahren des Typs vor is oben unter „Nachfahren von …“.</summary>
    [Test]
    procedure DescendantsComeFirstWithHeader;
    /// <summary>#2108: Nur wegen der Sichtbarkeit fehlende Mitglieder erst auf Wunsch, dann am Ende.</summary>
    [Test]
    procedure InaccessibleOnlyWhenShown;
    [Test]
    procedure ProjectUsesOrderBelowLearned;
    [Test]
    procedure VariantFieldsGetBranchTag;
    [Test]
    procedure ConversionStandsBeforeOriginal;
    [Test]
    procedure TypeArgumentsGetHeaderAndFooter;
    [Test]
    procedure AttributesGetBadge;
    [Test]
    procedure DataNamesCarrySource;
    [Test]
    procedure UsesUnitsGroupedWithHeaders;
    [Test]
    procedure InheritedCallsFirstWithTags;
    [Test]
    procedure SameNameVariantsFollowTheActive;
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
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
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
  Atlas.Core.Files.DataFile,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Style.Palette;

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
  mIndex: Integer;
begin
  Names := '';
  for mIndex in AOrder do
  begin
    if Names <> '' then
    begin
      Names := Names + ',';
    end;
    if TAtlasRanking.IsHeader(mIndex) then
    begin
      Names := Names + '#';
    end
    else
    begin
      Names := Names + AItems[mIndex].Name;
    end;
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
  AKind: TAtlasItemKind): TAtlasCompletionItem; overload;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.DeclaringClass := AContainer;
  Result.Depth := ADepth;
  Result.Rank := ARank;
  Result.Kind := AKind;
end;

function Member(const AName, AContainer: string; ADepth, ARank: Integer): TAtlasCompletionItem; overload;
begin
  Result := Member(AName, AContainer, ADepth, ARank, TAtlasItemKind.Method);
end;

function Names(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): string;
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
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mRestStart: Integer;
begin
  // Heutiger Stand (#497, Variante 1): nur Treffer.
  mItems := RestItems;
  mOrder := TAtlasRanking.Order(mItems, 'As', RestOptions(TAtlasListMode.Filter), mRestStart);
  Assert.AreEqual('Assign', Names(mItems, mOrder));
  Assert.AreEqual(-1, mRestStart);
end;

procedure TAtlasRankingTests.ListModeAllAppendsRestWithoutHeader;
var
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mRestStart: Integer;
begin
  // Variante 2: alles sichtbar, Treffer oben, der Rest in Rangfolge ohne Überschrift.
  mItems := RestItems;
  mOrder := TAtlasRanking.Order(mItems, 'As', RestOptions(TAtlasListMode.All), mRestStart);
  Assert.AreEqual('Assign,Add,BeginUpdate,Clear,Sort', Names(mItems, mOrder));
  Assert.AreEqual(1, mRestStart);
end;

procedure TAtlasRankingTests.ListModeRestUnderHeader;
var
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mRestStart: Integer;
  mOptions: TAtlasRankOptions;
begin
  // Variante 3: Treffer, darunter abgesetzt „Weitere Einträge“.
  mItems := RestItems;
  mOrder := TAtlasRanking.Order(mItems, 'As', RestOptions(TAtlasListMode.Rest), mRestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', Names(mItems, mOrder));
  Assert.AreEqual(TAtlasRanking.cRestHeader, mOrder[1]);
  Assert.AreEqual(2, mRestStart);
  // Der Chip schränkt auch den Rest ein.
  mItems := mItems + [Member('Count', 'TStrings', 0, 5, TAtlasItemKind.Property_)];
  mOrder := TAtlasRanking.Order(mItems, 'As', RestOptions(TAtlasListMode.Rest), mRestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort,Count', Names(mItems, mOrder));
  mOptions := RestOptions(TAtlasListMode.Rest);
  mOptions.Chip := TAtlasChip.Methods;
  mOrder := TAtlasRanking.Order(mItems, 'Co', mOptions, mRestStart);
  Assert.AreEqual('#,Add,Assign,BeginUpdate,Clear,Sort', Names(mItems, mOrder));
  Assert.AreEqual(1, mRestStart);
  mItems := nil;
  mOrder := nil;
end;

procedure TAtlasRankingTests.ListModeRestSkipsTyposAndEmptyPattern;
var
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mRestStart: Integer;
begin
  mItems := RestItems;
  // Ohne Präfix gibt es keinen Rest: alle Einträge sind Treffer.
  mOrder := TAtlasRanking.Order(mItems, '', RestOptions(TAtlasListMode.Rest), mRestStart);
  Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', Names(mItems, mOrder));
  Assert.AreEqual(-1, mRestStart);
  // Tippfehler (#485) stehen unter „Meintest du“ und nicht noch einmal im Rest.
  mOrder := TAtlasRanking.Order(mItems, 'Cleer', RestOptions(TAtlasListMode.Rest), mRestStart);
  Assert.AreEqual('#,Clear,#,Add,Assign,BeginUpdate,Sort', Names(mItems, mOrder));
  Assert.AreEqual(TAtlasRanking.cTypoHeader, mOrder[0]);
  Assert.AreEqual(TAtlasRanking.cRestHeader, mOrder[2]);
  Assert.AreEqual(3, mRestStart);
  mItems := nil;
  mOrder := nil;
end;

procedure TAtlasRankingTests.ListModeNames;
begin
  Assert.AreEqual<TAtlasListMode>(TAtlasListMode.Filter, TAtlasListModes.ModeOf('filter'));
  Assert.AreEqual<TAtlasListMode>(TAtlasListMode.All, TAtlasListModes.ModeOf(' ALL '));
  Assert.AreEqual<TAtlasListMode>(TAtlasListMode.Rest, TAtlasListModes.ModeOf('rest'));
  Assert.AreEqual<TAtlasListMode>(TAtlasListMode.Filter, TAtlasListModes.ModeOf('alles'), 'Unbekanntes wird Filter');
  Assert.AreEqual<TAtlasListScope>(TAtlasListScope.Everywhere, TAtlasListModes.ScopeOf('everywhere'));
  Assert.AreEqual<TAtlasListScope>(TAtlasListScope.Members, TAtlasListModes.ScopeOf(''));
end;

procedure TAtlasRankingTests.GroupsInheritedMembersWithHeaders;
var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  mItems := StringsItems;
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.GroupInherited := True;
  Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  Assert.AreEqual(4, TAtlasRanking.ItemCount(TAtlasRanking.Order(mItems, '', mOptions)));
  // Abgeschaltet: flache Liste in der Reihenfolge der Quelle.
  mOptions.GroupInherited := False;
  Assert.AreEqual('Sort,Add,BeginUpdate,Assign', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
end;

procedure TAtlasRankingTests.PrefixLiftsInheritedMatchWithoutHeaders;
var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  // Beispiel aus #419: "Ass" liefert Assign zuerst, obwohl es geerbt ist.
  mItems := StringsItems + [Member('AssignTo', 'TStringList', 0, 4)];
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.GroupInherited := True;
  Assert.AreEqual('Assign,AssignTo', Names(mItems, TAtlasRanking.Order(mItems, 'Assign', mOptions)));
  // Gleiche Güte: der eigene Member vor dem geerbten.
  Assert.AreEqual('AssignTo,Assign', Names(mItems, TAtlasRanking.Order(mItems, 'Ass', mOptions)));
  // Ohne eigenen Treffer: das geerbte Assign zuerst, ohne Überschrift.
  Assert.AreEqual('Assign', Names(StringsItems, TAtlasRanking.Order(StringsItems, 'Ass', mOptions)));
end;

procedure TAtlasRankingTests.ScopeOrdersAfterExpectedTypeBeforeBoost;

  function Scoped(const AName: string; AScope: Integer): TAtlasCompletionItem;
  begin
    Result := Member(AName, '', 0, 0, TAtlasItemKind.Variable);
    Result.Scope := AScope;
  end;

var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  // #488: Präfix-Güte → erwarteter Typ → Bereich → Lerngewicht → Name.
  mItems := [Scoped('FDiscount', 3), Scoped('ACustomer', 2), Scoped('Total', 1), Scoped('Format', 5),
    Scoped('TKasse', 4)];
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.Boost :=
    function(AIndex: Integer): Integer
    begin
      // FDiscount ist gelernt, schlägt aber keinen näheren Bereich.
      if AIndex = 0 then
      begin
        Result := 99;
      end
      else
      begin
        Result := 0;
      end;
    end;
  Assert.AreEqual('Total,ACustomer,FDiscount,TKasse,Format', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  // Erwarteter Typ vor Bereich: Nur ACustomer passt.
  mItems[1].ExpectedType := 'Integer';
  mItems[1].Fits := True;
  mItems[2].ExpectedType := 'Integer';
  Assert.AreEqual('#,ACustomer,#,Total,FDiscount,TKasse,Format',
    Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  // Mit Präfix: bessere Güte vor Bereich, bei gleicher Güte der nähere Bereich.
  mItems := [Scoped('Totalbetrag', 5), Scoped('Total', 4), Scoped('TotalLokal', 1)];
  Assert.AreEqual('Total,TotalLokal,Totalbetrag', Names(mItems, TAtlasRanking.Order(mItems, 'Total', mOptions)));
end;

procedure TAtlasRankingTests.BoostReordersButNeverBeatsBetterMatch;
var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  mItems := [Member('Add', '', 0, 0), Member('AddObject', '', 0, 1), Member('BeginUpdate', '', 0, 2)];
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.Boost :=
    function(AIndex: Integer): Integer
    begin
      if AIndex = 0 then
      begin
        Result := 0;
      end
      else
      begin
        Result := 99;
      end;
    end;
  // Ohne Präfix gewinnt das Gelernte.
  Assert.AreEqual('AddObject,BeginUpdate,Add', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  // Genauer Treffer bleibt vor einem gelernten Präfix-Treffer.
  Assert.AreEqual('Add,AddObject', Names(mItems, TAtlasRanking.Order(mItems, 'Add', mOptions)));
end;

procedure TAtlasRankingTests.ChipsFilterAndCount;
var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
  mCounts: TAtlasChipCounts;
begin
  mItems := [Member('Add', '', 0, 0), Member('Count', '', 0, 1, TAtlasItemKind.Property_),
    Member('OnChange', '', 0, 2, TAtlasItemKind.Event), Member('Capacity', '', 0, 3, TAtlasItemKind.Property_),
    Member('Total', '', 0, 4, TAtlasItemKind.Variable)];
  mCounts := TAtlasRanking.ChipCounts(mItems, '');
  Assert.AreEqual(5, mCounts[TAtlasChip.All]);
  Assert.AreEqual(1, mCounts[TAtlasChip.Methods]);
  Assert.AreEqual(2, mCounts[TAtlasChip.Properties]);
  Assert.AreEqual(1, mCounts[TAtlasChip.Events]);
  Assert.AreEqual(0, mCounts[TAtlasChip.Types]);
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.Chip := TAtlasChip.Properties;
  Assert.AreEqual('Count,Capacity', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  Assert.AreEqual(1, TAtlasRanking.ChipCounts(mItems, 'cou')[TAtlasChip.Properties]);
end;

procedure TAtlasRankingTests.PostfixAfterMembers;
var
  mItems: TAtlasCompletionItems;
begin
  // Postfix-Vorlagen (#188) stehen hinter allen echten Mitgliedern, auch wenn sie genauer passen.
  mItems := [Member('tryf', '', 0, 0, TAtlasItemKind.Snippet), Member('tryfNext', '', 0, 1),
    Member('TryFoo', '', 0, 2)];
  mItems[0].Postfix := True;
  mItems[0].FilterText := 'tryf';
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(mItems, TAtlasRanking.Order(mItems, 'tryf',
    TAtlasRankOptions.Defaults)));
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(mItems, TAtlasRanking.Order(mItems, '', TAtlasRankOptions.Defaults)));
end;

procedure TAtlasRankingTests.ServerGroupHeaderAndActionLast;
var
  mOptions: TAtlasRankOptions;
  mItems: TAtlasCompletionItems;
begin
  // Ereignis-Zuweisung (#444): Überschrift „Passt zu …“, die neue Methode immer zuletzt und immer sichtbar.
  mItems := [Member('Neue Methode btnSaveClick …', '', 0, 0), Member('FormCreate', 'TForm1', 0, 1),
    Member('Klick', 'TBasis', 1, 2)];
  mItems[0].IsAction := True;
  mItems[1].ExpectedType := 'TNotifyEvent';
  mItems[1].Fits := True;
  mItems[2].ExpectedType := 'TNotifyEvent';
  mItems[2].Fits := True;
  mOptions := TAtlasRankOptions.Defaults;
  mOptions.GroupInherited := True;
  Assert.AreEqual('#,FormCreate,Klick,Neue Methode btnSaveClick …', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  Assert.AreEqual('#,Klick,Neue Methode btnSaveClick …', Names(mItems, TAtlasRanking.Order(mItems, 'Kl', mOptions)));
  // Erwarteter Typ (#417): Passende oben, auch wenn ein übriger Eintrag besser zum Präfix passt.
  mItems := [Member('Count', '', 0, 0), Member('Capacity', '', 0, 1), Member('Clear', '', 0, 2)];
  mItems[0].ExpectedType := 'Integer';
  mItems[1].ExpectedType := 'Integer';
  mItems[1].Fits := True;
  mItems[2].ExpectedType := 'Integer';
  mItems[2].Fits := True;
  Assert.AreEqual('#,Capacity,Clear,#,Count', Names(mItems, TAtlasRanking.Order(mItems, 'C', mOptions)));
  Assert.AreEqual('#,Count', Names(mItems, TAtlasRanking.Order(mItems, 'Cou', mOptions)));
end;
procedure TAtlasRankingTests.FormComponentsComeFirst;
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
begin
  // Komponenten aus dem Formular (#455): eigene Gruppe vor allem anderen, Typtreffer hinter Namenstreffern.
  mJson := TJSONObject.ParseJSONValue('{"label":"btnSave","kind":5,"detail":"TButton","data":{"form":"frmMain",' +
    '"byType":true,"scope":3}}') as TJSONObject;
  try
    mItems := [Member('TButton', '', 0, 0, TAtlasItemKind.Class_), TAtlasServerCompletionProvider.ItemFromLsp(mJson, 1),
      Member('btnButtonLeiste', '', 0, 2)];
  finally
    mJson.Free;
  end;
  Assert.AreEqual('frmMain', mItems[1].Form);
  Assert.IsTrue(mItems[1].ByType);
  mItems[2].Form := 'frmMain';
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,btnButtonLeiste,btnSave,#,TButton', Names(mItems, TAtlasRanking.Order(mItems, 'button', mOptions)));
  // Ohne Formulareinträge keine Überschrift.
  mItems := Copy(mItems, 0, 1);
  Assert.AreEqual('TButton', Names(mItems, TAtlasRanking.Order(mItems, 'button', mOptions)));
end;

procedure TAtlasRankingTests.VariantFieldsGetBranchTag;
var
  mJson: TJSONObject;
  mItem: TAtlasCompletionItem;
  mTags: TAtlasTags;
  mTag: TAtlasTag;
  mFound: Boolean;
begin
  // Felder varianter Records (#846): data.variant wird zur Marke „Zweig 0“.
  mJson := TJSONObject.ParseJSONValue('{"label":"Left","kind":5,"detail":"Integer","data":{"variant":"0",' +
    '"container":"TRect"}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('0', mItem.VariantBranch);
  mTags := TAtlasItemPresentation.Tags(mItem);
  mFound := False;
  for mTag in mTags do
  begin
    if mTag.Id = TAtlasTagId.VariantBranch then
    begin
      mFound := True;
      Assert.AreEqual('Zweig 0', mTag.Text);
      Assert.AreEqual('0', mTag.Arg);
      Assert.AreEqual<TAtlasTagKind>(TAtlasTagKind.Neutral, mTag.Kind);
    end;
  end;
  Assert.IsTrue(mFound);
  // Ohne Zweig keine Marke.
  mItem.VariantBranch := '';
  for mTag in TAtlasItemPresentation.Tags(mItem) do
  begin
    Assert.AreNotEqual<TAtlasTagId>(TAtlasTagId.VariantBranch, mTag.Id);
  end;
end;

procedure TAtlasRankingTests.SenderItemsGetHeaderAndTag;
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mTags: TAtlasTags;
  mFound: Boolean;
  mTag: TAtlasTag;
begin
  // Sender mit Typumwandlung (#480): eine Überschrift über der Liste, Marke „als TButton“.
  mJson := TJSONObject.ParseJSONValue('{"label":"Caption","kind":10,"detail":"string","data":{"sender":"TButton",' +
    '"senderOf":"btnSave, btnLoad","scope":3}}') as TJSONObject;
  try
    mItems := [TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0)];
  finally
    mJson.Free;
  end;
  Assert.AreEqual('TButton', mItems[0].Sender);
  Assert.AreEqual('btnSave, btnLoad', mItems[0].SenderOf);
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,Caption', Names(mItems, TAtlasRanking.Order(mItems, 'Cap', mOptions)));
  mTags := TAtlasItemPresentation.Tags(mItems[0]);
  mFound := False;
  for mTag in mTags do
  begin
    if mTag.Text = 'als TButton' then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
  // Ohne Sender keine Überschrift.
  mItems[0].Sender := '';
  Assert.AreEqual('Caption', Names(mItems, TAtlasRanking.Order(mItems, 'Cap', mOptions)));
end;

procedure TAtlasRankingTests.NarrowedMembersComeFirstWithHeader;
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
  mFound: Boolean;
  mTag: TAtlasTag;
begin
  mJson := TJSONObject.ParseJSONValue('{"label":"Count","kind":10,"detail":"Integer","data":{"narrowed":' +
    '"TJSONObject","narrowedName":"mLocation","narrowedLine":147}}') as TJSONObject;
  try
    mItems := [Member('Clone', 'TJSONValue', 0, 0), TAtlasServerCompletionProvider.ItemFromLsp(mJson, 1),
      Member('AddPair', '', 0, 2)];
  finally
    mJson.Free;
  end;
  Assert.AreEqual('TJSONObject', mItems[1].Narrowed);
  Assert.AreEqual('mLocation', mItems[1].NarrowedName);
  Assert.AreEqual(147, mItems[1].NarrowedLine);
  mItems[2].Narrowed := 'TJSONObject';
  mItems[2].NarrowedName := 'mLocation';
  mItems[2].NarrowedLine := 147;
  mOrder := TAtlasRanking.Order(mItems, '', TAtlasRankOptions.Defaults);
  Assert.AreEqual('#,Count,AddPair,#,Clone', Names(mItems, mOrder));
  // Auch mit Präfix stehen sie oben.
  Assert.AreEqual('#,Count,#,Clone', Names(mItems, TAtlasRanking.Order(mItems, 'c', TAtlasRankOptions.Defaults)));
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[1]) do
  begin
    mFound := mFound or (mTag.Text = 'als TJSONObject');
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasRankingTests.InaccessibleOnlyWhenShown;
var
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mFound: Boolean;
  mTag: TAtlasTag;
begin
  mItems := [Member('FEintraege', 'TZaehler', 0, 0, TAtlasItemKind.Field), Member('FEnde', 'TZaehler', 0, 1,
    TAtlasItemKind.Field), Member('FAlt', 'TZaehler', 0, 2, TAtlasItemKind.Field)];
  mItems[0].Inaccessible := 'private';
  mItems[2].Inaccessible := 'strict private';
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('FEnde', Names(mItems, TAtlasRanking.Order(mItems, 'FE', mOptions)));
  Assert.AreEqual(1, Integer(Length(TAtlasRanking.Inaccessible(mItems, 'FE'))));
  Assert.AreEqual(0, TAtlasRanking.Inaccessible(mItems, 'FE')[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasRanking.Inaccessible(mItems, ''))));
  mOptions.ShowInaccessible := True;
  Assert.AreEqual('FEnde,#,FEintraege', Names(mItems, TAtlasRanking.Order(mItems, 'FE', mOptions)));
  // Nicht im Rest der Liste (#497) und nicht unter den Chips.
  mOptions.ShowInaccessible := False;
  mOptions.ListMode := TAtlasListMode.All;
  Assert.AreEqual('FEnde', Names(mItems, TAtlasRanking.Order(mItems, 'FE', mOptions)));
  Assert.AreEqual(1, TAtlasRanking.ChipCounts(mItems, 'FE')[TAtlasChip.All]);
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[0]) do
  begin
    mFound := mFound or (mTag.Text = 'private · TZaehler');
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasRankingTests.ProjectUsesOrderBelowLearned;
var
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mFound: Boolean;
  mTag: TAtlasTag;
begin
  // #2109: Ohne eigene Gewichtung ordnet die Zahl im Projekt; Gelerntes und bessere Treffer gehen vor.
  mItems := [Member('Add', '', 0, 0), Member('Clear', '', 0, 1), Member('Delete', '', 0, 2),
    Member('GetValue', '', 0, 3)];
  mItems[1].ProjectUses := 3;
  mItems[3].ProjectUses := 214;
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('GetValue,Clear,Add,Delete', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  mOptions.Boost :=
    function(AIndex: Integer): Integer
    begin
      // Eine einzige Übernahme von Delete (kleinster Lernzuschlag).
      Result := 0;
      if AIndex = 2 then
      begin
        Result := 15;
      end;
    end;
  Assert.AreEqual('Delete,GetValue,Clear,Add', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  mItems := [Member('Clear', '', 0, 0), Member('ClearAll', '', 0, 1)];
  mItems[1].ProjectUses := 50;
  Assert.AreEqual('Clear,ClearAll', Names(mItems, TAtlasRanking.Order(mItems, 'Clear', TAtlasRankOptions.Defaults)));
  Assert.AreEqual(0, TAtlasRanking.ProjectBoost(0));
  Assert.AreEqual(1, TAtlasRanking.ProjectBoost(1));
  Assert.AreEqual(TAtlasRanking.cMaxProjectBoost, TAtlasRanking.ProjectBoost(1000000));
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[1]) do
  begin
    mFound := mFound or mTag.Text.EndsWith(' 50×');
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasRankingTests.DescendantsComeFirstWithHeader;
var
  mItems: TAtlasCompletionItems;
  mOrder: TArray<Integer>;
begin
  mItems := [Member('TAlpha', '', 0, 0, TAtlasItemKind.Class_), Member('TJSONObject', '', 0, 1,
    TAtlasItemKind.Class_), Member('TJSONArray', '', 0, 2, TAtlasItemKind.Class_)];
  mItems[1].DescendantOf := 'TJSONValue';
  mItems[2].DescendantOf := 'TJSONValue';
  mOrder := TAtlasRanking.Order(mItems, '', TAtlasRankOptions.Defaults);
  Assert.AreEqual('#,TJSONObject,TJSONArray,#,TAlpha', Names(mItems, mOrder));
end;

procedure TAtlasRankingTests.ConversionStandsBeforeOriginal;
const
  cAnswers: array[0..3] of string = (
    '{"label":"Count.ToString","kind":5,"detail":"Integer","filterText":"Count","data":{"expected":"string",' +
      '"conversion":"string","convertFrom":"Count","scope":0}}',
    '{"label":"Text","kind":5,"detail":"string","data":{"expected":"string","fits":true}}',
    '{"label":"Count","kind":5,"detail":"Integer","data":{"expected":"string"}}',
    '{"label":"Preis","kind":5,"detail":"Double","data":{"expected":"Integer","lossy":"Double"}}');
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
  mTag: TAtlasTag;
  mFound: Boolean;
  mAnswer: string;
begin
  // Typkonvertierung (#490): „Count.ToString → string“ direkt über Count, gefiltert nach dem Namen des Originals.
  mItems := nil;
  for mAnswer in cAnswers do
  begin
    mJson := TJSONObject.ParseJSONValue(mAnswer) as TJSONObject;
    try
      mItems := mItems + [TAtlasServerCompletionProvider.ItemFromLsp(mJson, Length(mItems))];
    finally
      mJson.Free;
    end;
  end;
  Assert.AreEqual('string', mItems[0].Conversion);
  Assert.AreEqual('Count', mItems[0].ConvertFrom);
  Assert.AreEqual('Count', mItems[0].FilterText);
  Assert.AreEqual('Double', mItems[3].Lossy);
  mItems[1].Fits := True;
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,Count.ToString,Count', Names(mItems, TAtlasRanking.Order(mItems, 'Cou', mOptions)));
  Assert.AreEqual('#,Text,#,Count.ToString,Count,Preis', Names(mItems, TAtlasRanking.Order(mItems, '', mOptions)));
  // Ohne sichtbares Original auch keine Umwandlung; gezählt wird sie nicht.
  Assert.AreEqual('#,Text', Names(mItems, TAtlasRanking.Order(mItems, 'Tex', mOptions)));
  Assert.AreEqual(1, TAtlasRanking.ChipCounts(mItems, 'Cou')[TAtlasChip.All]);
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[0]) do
  begin
    if mTag.Text = '→ string' then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasRankingTests.AttributesGetBadge;
var
  mJson: TJSONObject;
  mItem: TAtlasCompletionItem;
begin
  // Attribute nach "[" (#465): Badge "at", rechts die Konstruktorparameter.
  mJson := TJSONObject.ParseJSONValue('{"label":"TestCase","kind":7,"detail":"(const AName: string)",' +
    '"insertText":"TestCase","data":{"attribute":true}}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mItem.Attribute);
  Assert.AreEqual('at', TAtlasItemPresentation.Badge(mItem).Code);
  Assert.AreEqual<TAtlasBadgeKind>(TAtlasBadgeKind.Type_, TAtlasItemPresentation.Badge(mItem).Kind);
  mJson := TJSONObject.ParseJSONValue('{"label":"TKunde","kind":7}') as TJSONObject;
  try
    mItem := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsFalse(mItem.Attribute);
  Assert.AreEqual('ty', TAtlasItemPresentation.Badge(mItem).Code);
end;

procedure TAtlasRankingTests.TypeArgumentsGetHeaderAndFooter;
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mOptions: TAtlasRankOptions;
begin
  // Typargumente (#450): eine Überschrift mit dem Constraint über der Liste, ausgeblendete Arten für die Fußzeile.
  mJson := TJSONObject.ParseJSONValue('{"label":"TKunde","kind":7,"detail":"Listen","data":{"typeParam":"T",' +
    '"constraint":"class","constraintHint":"classes","hiddenKinds":"records,enums"}}') as TJSONObject;
  try
    mItems := [TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0)];
  finally
    mJson.Free;
  end;
  Assert.AreEqual('T', mItems[0].TypeParam);
  Assert.AreEqual('class', mItems[0].Constraint);
  Assert.AreEqual('classes', mItems[0].ConstraintHint);
  Assert.AreEqual('records,enums', TAtlasItemPresentation.HiddenKinds(mItems));
  mOptions := TAtlasRankOptions.Defaults;
  Assert.AreEqual('#,TKunde', Names(mItems, TAtlasRanking.Order(mItems, 'TK', mOptions)));
  mItems[0].TypeParam := '';
  Assert.AreEqual('TKunde', Names(mItems, TAtlasRanking.Order(mItems, 'TK', mOptions)));
end;

procedure TAtlasRankingTests.DataNamesCarrySource;
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
begin
  // Feld- und Parameternamen (#461): Datenmenge und SQL-Anweisung für die Fußzeile.
  mJson := TJSONObject.ParseJSONValue('{"label":"CUSTOMER_ID","kind":5,"detail":"Integer","data":{' +
    '"dataSet":"qryOrders","dataSource":"select CUSTOMER_ID from ORDERS"}}') as TJSONObject;
  try
    mItems := [Member('Capacity', '', 0, 0), TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0)];
  finally
    mJson.Free;
  end;
  Assert.AreEqual('qryOrders', mItems[1].DataSet);
  Assert.AreEqual('select CUSTOMER_ID from ORDERS', TAtlasItemPresentation.DataSource(mItems));
  Assert.AreEqual('', TAtlasItemPresentation.DataSource(Copy(mItems, 0, 1)));
end;

procedure TAtlasRankingTests.SameNameVariantsFollowTheActive;
const
  cLines: array[0..2] of string = (
    '{"label":"TBitmap","kind":7,"data":{"scope":5,"unit":"Winapi.Windows","action":"sameName",' +
      '"sameNameOf":"Vcl.Graphics","sameNameInsert":"prefix","sameNameUnits":["Vcl.Graphics","Winapi.Windows"],' +
      '"sameNameHidden":["FMX.Graphics.TBitmap"]},"textEdit":{"range":{"start":{"line":8,"character":10},' +
      '"end":{"line":8,"character":15}},"newText":"Winapi.Windows.TBitmap"}}',
    '{"label":"TBitmap","kind":7,"data":{"scope":5,"unit":"Vcl.Graphics","sameNameActive":true,' +
      '"sameNameUnits":["Vcl.Graphics","Winapi.Windows"],"sameNameHidden":["FMX.Graphics.TBitmap"]}}',
    '{"label":"TBitmapImage","kind":7,"data":{"scope":5,"unit":"Vcl.Graphics"}}');
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mIndex: Integer;
  mOrder: TArray<Integer>;
  mFound: Boolean;
  mTag: TAtlasTag;
  mDetails: TAtlasItemDetails;
begin
  // Gleiche Namen aus verschiedenen Units (#475): die Variante direkt unter der aktiven.
  mItems := nil;
  for mIndex := 0 to High(cLines) do
  begin
    mJson := TJSONObject.ParseJSONValue(cLines[mIndex]) as TJSONObject;
    try
      mItems := mItems + [TAtlasServerCompletionProvider.ItemFromLsp(mJson, mIndex)];
    finally
      mJson.Free;
    end;
  end;
  mOrder := TAtlasRanking.Order(mItems, 'TBitm', TAtlasRankOptions.Defaults);
  Assert.AreEqual(3, Integer(Length(mOrder)));
  // Der Server schickt die Variante hier vor der aktiven; sie rückt dahinter.
  Assert.AreEqual(1, mOrder[0]);
  Assert.AreEqual(0, mOrder[1]);
  Assert.AreEqual(2, mOrder[2]);
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[1]) do
  begin
    if mTag.Id = TAtlasTagId.Active then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
  for mTag in TAtlasItemPresentation.Tags(mItems[0]) do
  begin
    Assert.AreNotEqual<TAtlasTagId>(TAtlasTagId.Active, mTag.Id);
  end;
  Assert.AreEqual('FMX.Graphics.TBitmap', string.Join(',', TAtlasItemPresentation.SameNameHidden(mItems)));
  mDetails := Default(TAtlasItemDetails);
  TAtlasItemPresentation.AddSameName(mItems[0], mDetails);
  Assert.AreEqual('Winapi.Windows', mDetails.SameNameThis);
  Assert.AreEqual('prefix', mDetails.SameNameInsert);
  Assert.AreEqual(2, Integer(Length(mDetails.SameNameUnits)));
  Assert.IsFalse(mDetails.IsEmpty);
end;

procedure TAtlasRankingTests.InheritedCallsFirstWithTags;
const
  cLines: array[0..3] of string = (
    '{"label":"Free","kind":2,"data":{"container":"TObject","depth":3}}',
    '{"label":"CreateNew(AOwner, Dummy)","filterText":"CreateNew","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"other","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"Create(AOwner)","filterText":"Create","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"same","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"CreateParented(ParentWindow)","filterText":"CreateParented","kind":4,"detail":"TWinControl",' +
      '"data":{"container":"TWinControl","depth":2,"inheritedMatch":"other"}}');
var
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mIndex: Integer;
  mTags: TAtlasTags;
  mFound: Boolean;
  mTag: TAtlasTag;
begin
  // Nach "inherited " (#482): der Aufruf mit gleichen Parametern zuerst, dann die übrigen Konstruktoren.
  mItems := nil;
  for mIndex := 0 to High(cLines) do
  begin
    mJson := TJSONObject.ParseJSONValue(cLines[mIndex]) as TJSONObject;
    try
      mItems := mItems + [TAtlasServerCompletionProvider.ItemFromLsp(mJson, mIndex)];
    finally
      mJson.Free;
    end;
  end;
  Assert.AreEqual('Create(AOwner),CreateNew(AOwner, Dummy),CreateParented(ParentWindow)',
    Names(mItems, TAtlasRanking.Order(mItems, 'Cre', TAtlasRankOptions.Defaults)));
  mTags := TAtlasItemPresentation.Tags(mItems[2]);
  mFound := False;
  for mTag in mTags do
  begin
    if mTag.Id = TAtlasTagId.SameParams then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
  // Weitere Konstruktoren tragen die deklarierende Klasse.
  mFound := False;
  for mTag in TAtlasItemPresentation.Tags(mItems[3]) do
  begin
    if mTag.Text = 'TWinControl' then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', TAtlasItemPresentation.InheritedAbstract(mItems)));
end;

procedure TAtlasRankingTests.UsesUnitsGroupedWithHeaders;
const
  cLines: array[0..3] of string = (
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
  mJson: TJSONObject;
  mItems: TAtlasCompletionItems;
  mIndex: Integer;
  mTags: TAtlasTags;
  mDetails: TAtlasItemDetails;
begin
  // uses-Abschnitt (#469): Projekt vor RTL/VCL vor Drittanbietern, je Gruppe eine Überschrift; gefiltert wird nach
  // dem Namensteil ab dem Getippten.
  mItems := nil;
  for mIndex := 0 to High(cLines) do
  begin
    mJson := TJSONObject.ParseJSONValue(cLines[mIndex]) as TJSONObject;
    try
      mItems := mItems + [TAtlasServerCompletionProvider.ItemFromLsp(mJson, mIndex)];
    finally
      mJson.Free;
    end;
  end;
  Assert.AreEqual('Generics.Collections', mItems[1].FilterText);
  Assert.AreEqual('#,uGeneratorBeleg,#,System.Generics.Collections,System.Generics.Defaults,#,' +
    'Spring.Collections.Generic', Names(mItems, TAtlasRanking.Order(mItems, 'Gener', TAtlasRankOptions.Defaults)));
  Assert.AreEqual('#,System.Generics.Defaults',
    Names(mItems, TAtlasRanking.Order(mItems, 'Defau', TAtlasRankOptions.Defaults)));
  // Zirkelbezug als Marke in Fehlerfarbe, anderer Abschnitt rechts, kein Dateiname.
  mTags := TAtlasItemPresentation.Tags(mItems[3]);
  Assert.AreEqual(1, Integer(Length(mTags)));
  Assert.AreEqual<TAtlasTagKind>(TAtlasTagKind.Error, mTags[0].Kind);
  Assert.AreEqual<TAtlasTagId>(TAtlasTagId.Cycle, mTags[0].Id);
  Assert.AreEqual('', TAtlasItemPresentation.Detail(mItems[3]));
  Assert.AreEqual('bereits im implementation-Teil', TAtlasItemPresentation.Detail(mItems[2]));
  Assert.AreEqual(1, Integer(Length(TAtlasItemPresentation.UsesHidden(mItems))));
  Assert.AreEqual('System.SysUtils', TAtlasItemPresentation.UsesHidden(mItems)[0]);
  // Detailpanel ohne Server: Deklaration, Pfad, Typen samt Gesamtzahl.
  mDetails := TAtlasItemPresentation.UsesDetails(mItems[1]);
  Assert.AreEqual('unit System.Generics.Collections', mDetails.Declaration);
  Assert.AreEqual('$(BDS)\source\rtl\common\System.Generics.Collections.pas', mDetails.UnitPath);
  Assert.AreEqual(2, Integer(Length(mDetails.UnitTypes)));
  Assert.AreEqual(7, mDetails.UnitTypeCount);
  Assert.IsFalse(mDetails.IsEmpty);
  Assert.AreEqual('uGeneratorBeleg → Haupt', TAtlasItemPresentation.UsesDetails(mItems[3]).UsesCycle);
  Assert.AreEqual('implementation', TAtlasItemPresentation.UsesDetails(mItems[2]).UsesElsewhere);
  // Ohne Gruppe (Schalter aus): keine Überschriften.
  for mIndex := 0 to High(mItems) do
  begin
    mItems[mIndex].UsesGroup := '';
  end;
  Assert.IsFalse(Names(mItems, TAtlasRanking.Order(mItems, 'Gener', TAtlasRankOptions.Defaults)).Contains('#'));
end;

{ TAtlasUsageTests }

procedure TAtlasUsageTests.RecordsBoostAndMarks;
var
  mUsage: TAtlasUsage;
  mBegin_, mAdd: TAtlasCompletionItem;
  mRound: Integer;
begin
  mUsage := TAtlasUsage.Create;
  try
    mBegin_ := Member('BeginUpdate', 'TStrings', 1, 0);
    mAdd := Member('Add', 'TStrings', 1, 1);
    Assert.AreEqual(0, mUsage.Boost(mBegin_));
    for mRound := 1 to 3 do
    begin
      mUsage.Record_(mBegin_);
    end;
    Assert.AreEqual(75, mUsage.Boost(mBegin_), '3 × 15 + 30 für zuletzt');
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.Recent, mUsage.Mark(mBegin_));
    mUsage.Record_(mAdd);
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.Recent, mUsage.Mark(mAdd));
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.None, mUsage.Mark(mBegin_), 'erst ab 5 Übernahmen häufig');
    mUsage.Record_(mBegin_);
    mUsage.Record_(mBegin_);
    mUsage.Record_(mAdd);
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.Frequent, mUsage.Mark(mBegin_));
    Assert.AreEqual(60, mUsage.Boost(mBegin_), 'gedeckelt, nicht mehr zuletzt');
  finally
    mUsage.Free;
  end;
end;

procedure TAtlasUsageTests.SavesLoadsAndClears;
var
  mUsage, mLoaded: TAtlasUsage;
  mFileName: string;
  mItem: TAtlasCompletionItem;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasUsage' + IntToStr(TThread.GetTickCount64) + '.json');
  mItem := Member('BeginUpdate', 'TStrings', 1, 0);
  mUsage := TAtlasUsage.Create;
  mLoaded := TAtlasUsage.Create;
  try
    mUsage.Record_(mItem);
    mUsage.Record_(mItem);
    Assert.IsTrue(mUsage.Changed);
    mUsage.SaveToFile(mFileName);
    Assert.IsFalse(mUsage.Changed);
    mLoaded.LoadFromFile(mFileName);
    Assert.AreEqual(mUsage.Boost(mItem), mLoaded.Boost(mItem));
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.Recent, mLoaded.Mark(mItem));
    mLoaded.Clear;
    Assert.AreEqual(0, mLoaded.Boost(mItem));
    // Fehlende Datei: leer, kein Fehler.
    mLoaded.LoadFromFile(mFileName + '.fehlt');
    Assert.AreEqual(0, Integer(mLoaded.Count));
  finally
    mLoaded.Free;
    mUsage.Free;
    TFile.Delete(mFileName);
  end;
end;

procedure TAtlasUsageTests.LearnedEntryRisesInController;
var
  mView: TRecordingView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mUsage: TAtlasUsage;
  mRound: Integer;
  mItem: TAtlasCompletionItem;
begin
  // Akzeptanz #418: nach dreimaliger Übernahme von BeginUpdate steht es ohne Präfix vor Add.
  mView := TRecordingView.Create;
  mViewRef := mView;
  mUsage := TAtlasUsage.Create;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(
    [Member('Add', 'TStrings', 0, 0), Member('BeginUpdate', 'TStrings', 0, 1)]) as IAtlasCompletionProvider, mViewRef);
  try
    mController.Usage := mUsage;
    for mRound := 1 to 3 do
    begin
      mUsage.Record_(Member('BeginUpdate', 'TStrings', 0, 1));
    end;
    mController.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('BeginUpdate,Add', mView.Names);
    Assert.IsTrue(mController.SelectedItem(mItem));
    Assert.AreEqual<TAtlasUsageMark>(TAtlasUsageMark.Recent, mItem.Usage);
  finally
    mController.Free;
    mUsage.Free;
  end;
end;

procedure TAtlasUsageTests.SelectionSkipsHeaders;
var
  mView: TRecordingView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TRecordingView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(StringsItems)
    as IAtlasCompletionProvider, mViewRef);
  try
    mController.GroupInherited := True;
    mController.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', mView.Names);
    Assert.AreEqual(0, mView.Selected);
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(2, mView.Selected, 'Überschrift übersprungen');
    mController.HandleKey(TAtlasNavigationKey.Up);
    Assert.AreEqual(0, mView.Selected);
    mController.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(5, mView.Selected);
    mController.HandleKey(TAtlasNavigationKey.Up);
    Assert.AreEqual(3, mView.Selected);
  finally
    mController.Free;
  end;
end;

procedure TAtlasUsageTests.TypingDiscardsGuardOffer;
var
  mView: TRecordingView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mJson: TJSONObject;
  mGuard: TAtlasCompletionItem;
  mItem: TAtlasCompletionItem;
begin
  // Freigabe absichern (#489): Das Angebot ist gewählt; jedes getippte Zeichen schließt die Liste.
  mJson := TJSONObject.ParseJSONValue('{"label":"Mit try…finally absichern","kind":15,"detail":"List.Free",' +
    '"data":{"guard":"newLine"}}') as TJSONObject;
  try
    mGuard := TAtlasServerCompletionProvider.ItemFromLsp(mJson, 0);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mGuard.Guard);
  Assert.IsTrue(TAtlasItemPresentation.Guarding([mGuard]));
  Assert.IsFalse(TAtlasItemPresentation.Guarding([mGuard, Member('Add', 'TStrings', 0, 0)]));
  mView := TRecordingView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create([mGuard]) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    Assert.IsTrue(mController.SelectedItem(mItem));
    Assert.AreEqual('Mit try…finally absichern', mItem.Name);
    mController.UpdatePrefix('L');
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

function MemberContext(const APrefix: string): TAtlasContext;
begin
  Result := Context(APrefix);
  Result.Kind := TAtlasContextKind.MemberAccess;
end;

procedure TAtlasUsageTests.RestOnlyInMemberListsByDefault;
var
  mView: TRecordingView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
begin
  mView := TRecordingView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(RestItems) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.ListMode := TAtlasListMode.Rest;
    // Strg+Leer (alle sichtbaren Namen): nur Treffer, solange der Bereich Members ist.
    mController.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    mController.UpdatePrefix('As');
    Assert.AreEqual('Assign', mView.Names);
    Assert.AreEqual(-1, mController.RestStart);
    // Nach ".": Treffer, darunter der Rest.
    mController.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    mController.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', mView.Names);
    Assert.AreEqual(0, mView.Selected, 'Bester Treffer gewählt');
    Assert.AreEqual(2, mController.RestStart);
    // Bild↓/Ende überspringen die Überschrift und erreichen das Ende des Rests.
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.AreEqual(2, mView.Selected, 'Überschrift übersprungen');
    mController.HandleKey(TAtlasNavigationKey.Last);
    Assert.AreEqual(5, mView.Selected);
    // Überall: auch ohne ".".
    mController.ListScope := TAtlasListScope.Everywhere;
    mController.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    mController.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', mView.Names);
  finally
    mController.Free;
  end;
end;

procedure TAtlasUsageTests.RestWithoutMatchSelectsNothing;
var
  mView: TRecordingView;
  mViewRef: IAtlasCompletionView;
  mController: TAtlasCompletionController;
  mItem: TAtlasCompletionItem;
begin
  mView := TRecordingView.Create;
  mViewRef := mView;
  mController := TAtlasCompletionController.Create(TAtlasFixedCompletionProvider.Create(RestItems) as
    IAtlasCompletionProvider, mViewRef);
  try
    mController.ListMode := TAtlasListMode.All;
    mController.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    // Kein Treffer für "Zq": alles sichtbar, nichts gewählt; Enter gehört dem Editor.
    mController.UpdatePrefix('Zq');
    Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', mView.Names);
    Assert.AreEqual(0, mController.RestStart);
    Assert.IsTrue(mController.Passive);
    Assert.AreEqual(-1, mView.Selected);
    Assert.IsFalse(mController.CanCommitOnCharacter);
    // Eine Pfeiltaste wählt den ersten Eintrag.
    mController.HandleKey(TAtlasNavigationKey.Down);
    Assert.IsFalse(mController.Passive);
    Assert.IsTrue(mController.SelectedItem(mItem));
    Assert.AreEqual('Add', mItem.Name);
    // Mit Treffer wieder der beste gewählt.
    mController.UpdatePrefix('Cl');
    Assert.AreEqual('Clear,Add,Assign,BeginUpdate,Sort', mView.Names);
    Assert.AreEqual(0, mView.Selected);
    Assert.IsFalse(mController.Passive);
  finally
    mController.Free;
  end;
end;

procedure TAtlasUsageTests.BrokenFileSetAsideLockedFileKept;
var
  mUsage: TAtlasUsage;
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'AtlasUsage' + IntToStr(Random(MaxInt)) + '.json');
  mUsage := TAtlasUsage.Create;
  try
    TFile.WriteAllText(mFileName, '{"entries": 5}');
    Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Renewed, mUsage.LoadFromFile(mFileName));
    Assert.IsTrue(TFile.Exists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
    mUsage.Record_(Member('BeginUpdate', 'TStrings', 1, 0));
    Assert.IsTrue(mUsage.SaveToFile(mFileName));
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      Assert.AreEqual<TAtlasDataLoad>(TAtlasDataLoad.Kept, mUsage.LoadFromFile(mFileName));
    finally
      mLock.Free;
    end;
    Assert.AreEqual(0, Integer(mUsage.Count));
    mUsage.Record_(Member('EndUpdate', 'TStrings', 1, 0));
    Assert.IsFalse(mUsage.SaveToFile(mFileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'beginupdate');
    Assert.DoesNotContain(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'endupdate');
  finally
    mUsage.Free;
    System.SysUtils.DeleteFile(mFileName);
    System.SysUtils.DeleteFile(mFileName + TAtlasDataFile.cDefectExtension);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRankingTests);
  TDUnitX.RegisterTestFixture(TAtlasUsageTests);

end.
