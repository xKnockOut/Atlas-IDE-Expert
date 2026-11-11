unit Atlas.Common.Lsp.Completion.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionTests = class(TLspCompletionTestCase)
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScopeListsLocalsMembersAndUsedUnits;
    [Test]
    procedure OwnMethodsSurviveTruncation;
    [Test]
    procedure PlainItemsHaveNoTextEdit;
    [Test]
    procedure ItemsCarryTheirScope;
    [Test]
    procedure NearestScopeComesFirstWithoutPrefix;
    [Test]
    procedure InlineVarBelowCaretIsNotOffered;
    [Test]
    procedure HiddenNamesAppearOnceWithHint;
    [Test]
    procedure ImportsKnowParameters;
    [Test]
    procedure ProjectImportsComeBeforeLibraryLimit;
    [Test]
    procedure ScopeFiltersByPrefix;
    [Test]
    procedure MembersAfterDotIncludeInherited;
    [Test]
    procedure MembersOfUnitAreInterfaceSymbols;
    [Test]
    procedure UsesClauseListsUnits;
    [Test]
    procedure NothingInCommentsAndStrings;
    [Test]
    procedure WritesCompletionList;
    /// <summary>Golden-Test: alle Felder von data in der heutigen Reihenfolge.</summary>
    [Test]
    procedure ToJsonWritesAllDataFields;
    /// <summary>Felder außerhalb des Gates (container, depth …) allein ergeben kein data.</summary>
    [Test]
    procedure ToJsonOmitsDataBelowGate;
    [Test]
    procedure FuzzyFindsSubsequencesAndAbbreviations;
    [Test]
    procedure FuzzySortsByScoreThenScope;
    [Test]
    procedure FuzzySetsFilterTextAndIsIncomplete;
    [Test]
    procedure IncompleteOnlyWhenMoreCanCome;
    [Test]
    procedure ImportLimitMarksIncomplete;
    [Test]
    procedure NameFilterSkipsIndexSymbols;
    [Test]
    procedure StagedDeliversOwnScopeThenUsedUnits;
    [Test]
    procedure StagedKeepsImportsAfterUsedNames;
    [Test]
    procedure PartialJsonContinuesSortText;
    [Test]
    procedure PrefixModeKeepsStrictSelection;
    [Test]
    procedure OffersSymbolsOfUnusedUnitsWithUsesEdit;
    [Test]
    procedure ImportsNeedTwoCharactersAndSkipUsedUnits;
    /// <summary>Typen der IDE (atlas/ideTypes): aus nicht eingebundener Unit mit uses-Eintrag, aus eingebundener
    /// ohne; nicht bei einem Zeichen.</summary>
    [Test]
    procedure OffersIdeTypesWithUsesEdit;
    [Test]
    procedure MembersCarryContainerDepthAndOverloads;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.Completion.Lists,
  Atlas.Common.Lsp.Completion.Values,
  Atlas.Common.Lsp.IdeTypes;

procedure TLspCompletionTests.Setup;
begin
  Prepare;
end;
procedure TLspCompletionTests.TearDown;
begin
  Release;
end;
procedure TLspCompletionTests.WarmUpFirstUse;
begin
  Setup;
  try
    ScopeListsLocalsMembersAndUsedUnits;
  finally
    TearDown;
  end;
end;
procedure TLspCompletionTests.ScopeListsLocalsMembersAndUsedUnits;
begin
  // Nächster Gültigkeitsbereich zuerst; Versteckt steht nur in implementation von Werkzeug.
  Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ')));
end;
procedure TLspCompletionTests.OwnMethodsSurviveTruncation;
var
  Source, Text: string;
  Index: Integer;
  Items: TCompletionItems;
begin
  // Rückmeldung 15.10.2026: Bei einem Vorfahren mit mehr als MaxItems kurzen Mitgliedern fielen eigene
  // Methoden mit längerem Namen beim Kürzen heraus.
  Source := 'unit Gross;'#10'interface'#10'type'#10'  TGross = class'#10'  public'#10;
  for Index := 0 to TLspCompletion.cMaxItems + 199 do
  begin
    Source := Source + '    procedure R' + IntToStr(Index) + ';'#10;
  end;
  Source := Source + '  end;'#10'implementation'#10'end.';
  FIndex.AddUnit(TIndexExtractor.ExtractText(Source, 'C:\P\Gross.pas', nil));
  Text := StringReplace(StringReplace(WithCode('  R'), 'uses Werkzeug;', 'uses Werkzeug, Gross;', []),
    'class(TBasis)', 'class(TGross)', []);
  Text := StringReplace(Text, '    procedure Bar(Anzahl: Integer);',
    '    procedure Bar(Anzahl: Integer);'#10'    procedure RechneSehrLangerName;', []);
  Items := ItemsAt(Text, #10'  R', TCompletionMatching.Fuzzy);
  Assert.IsTrue(Items.Incomplete);
  Assert.AreEqual<NativeInt>(TLspCompletion.cMaxItems, Length(Items.Items));
  Assert.IsTrue(Pos(' RechneSehrLangerName ', ' ' + Names(Items) + ' ') > 0, 'eigene Methode fehlt');
end;
procedure TLspCompletionTests.ScopeFiltersByPrefix;
begin
  Assert.AreEqual('Wert', Names(ItemsAt(WithCode('  We'), '  We')));
  Assert.AreEqual('TFoo', Names(ItemsAt(WithCode('  tf'), '  tf')));
end;
procedure TLspCompletionTests.MembersAfterDotIncludeInherited;
var
  Text: string;
begin
  Text := WithCode('  Wert.');
  Assert.AreEqual('Name Bar Zaehler Melde', Names(ItemsAt(Text, 'Wert.')));
  Text := WithCode('  Self.Za');
  Assert.AreEqual('Zaehler', Names(ItemsAt(Text, 'Self.Za')));
end;
procedure TLspCompletionTests.MembersOfUnitAreInterfaceSymbols;
var
  Text: string;
begin
  Text := WithCode('  Werkzeug.');
  Assert.AreEqual('TBasis Rechne', Names(ItemsAt(Text, 'Werkzeug.')));
end;
procedure TLspCompletionTests.UsesClauseListsUnits;
var
  Text: string;
  Items: TCompletionItems;
begin
  Text := StringReplace(UnitHaupt, 'uses Werkzeug;', 'uses Werk', []);
  Items := ItemsAt(Text, 'uses Werk');
  Assert.AreEqual('Werkzeug', Names(Items));
  Assert.AreEqual(9, Items.Items[0].Kind);
end;
procedure TLspCompletionTests.NothingInCommentsAndStrings;
begin
  Assert.AreEqual('', Names(ItemsAt(UnitHaupt, '{ Kommentar W')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  Name := ''We'';'), '''We')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  // We'), '// We')));
end;
procedure TLspCompletionTests.WritesCompletionList;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  SetLength(Items.Items, 1);
  Items.Items[0].Name := 'Wert';
  Items.Items[0].Detail := 'TFoo';
  Items.Items[0].Kind := 6;
  Items.Incomplete := False;
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":6,"detail":"TFoo","sortText":"00000"}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;
/// <summary>Eintrag, der jedes Datenfeld belegt.</summary>
function FullDataItem: TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := 'Wert';
  Result.Kind := 6;
  Result.Detail := 'TFoo';
  Result.FilterText := 'We';
  Result.InsertText := 'Wert()';
  Result.Snippet := True;
  Result.AdditionalEdits := [TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(2, 0),
    TTextPosition.Create(2, 1)), 'uses X;')];
  Result.SourceFile := 'C:\P\U.pas';
  Result.SourcePosition := TTextPosition.Create(3, 4);
  Result.Expected := 'Integer';
  Result.Fits := True;
  Result.Action := 'declare';
  Result.Container := 'TFoo';
  Result.Depth := 2;
  Result.IsHelper := True;
  Result.HasParameters := True;
  Result.Condition := 'WIN64';
  Result.Unavailable := True;
  Result.Scope := 5;
  Result.Ordinal := 1;
  Result.SetOf := 'TKind';
  Result.SetChecked := True;
  Result.SetRange := TTextRange.Create(TTextPosition.Create(5, 1), TTextPosition.Create(5, 9));
  Result.Pinned := True;
  Result.Count := 3;
  Result.Unknown := 'Wert';
  Result.Batch := True;
  Result.Hint := True;
  Result.Form := 'frmMain';
  Result.ByType := True;
  Result.Sender := 'TButton';
  Result.SenderOf := 'btnSave';
  Result.DataSet := 'qry';
  Result.DataSource := 'select';
  Result.Guard := 'newLine';
  Result.UnitName := 'U';
  Result.Hides := ['Feld TKunde.Wert'];
  Result.Overloads := [TTextPosition.Create(7, 2)];
end;
procedure TLspCompletionTests.ToJsonWritesAllDataFields;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  Items := Default(TCompletionItems);
  SetLength(Items.Items, 1);
  Items.Items[0] := FullDataItem;
  Items.Incomplete := True;
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual(
      '{"isIncomplete":true,"items":[{"label":"Wert","kind":6,"detail":"TFoo","filterText":"We",' +
      '"insertText":"Wert()","insertTextFormat":2,"additionalTextEdits":[{"range":{"start":{"line":2,' +
      '"character":0},"end":{"line":2,"character":1}},"newText":"uses X;"}],"sortText":"00000",' +
      '"data":{"file":"C:\\P\\U.pas","line":3,"character":4,"expected":"Integer","fits":true,' +
      '"action":"declare","container":"TFoo","depth":2,"helper":true,"parameters":true,"condition":"WIN64",' +
      '"unavailable":true,"scope":5,"ordinal":1,"setOf":"TKind","checked":true,"setRange":{"start":' +
      '{"line":5,"character":1},"end":{"line":5,"character":9}},"pinned":true,"count":3,"unknown":"Wert",' +
      '"batch":true,"hint":true,"form":"frmMain","byType":true,"sender":"TButton","senderOf":"btnSave",' +
      '"dataSet":"qry","dataSource":"select","guard":"newLine","unit":"U","hides":["Feld TKunde.Wert"],' +
      '"overloads":[{"line":7,"character":2}]}}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
  // textEdit hat Vorrang vor insertText.
  Items.Items[0] := Default(TCompletionItem);
  Items.Items[0].Name := 'for';
  Items.Items[0].Kind := 15;
  Items.Items[0].InsertText := 'nie';
  Items.Items[0].HasTextEdit := True;
  Items.Items[0].TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(1, 2),
    TTextPosition.Create(1, 6)), 'for X');
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('{"isIncomplete":true,"items":[{"label":"for","kind":15,"textEdit":{"range":{"start":' +
      '{"line":1,"character":2},"end":{"line":1,"character":6}},"newText":"for X"},"sortText":"00000"}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;
procedure TLspCompletionTests.ToJsonOmitsDataBelowGate;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  Items := Default(TCompletionItems);
  SetLength(Items.Items, 1);
  Items.Items[0] := Default(TCompletionItem);
  Items.Items[0].Name := 'Wert';
  Items.Items[0].Kind := 5;
  Items.Items[0].Container := 'TFoo';
  Items.Items[0].Depth := 1;
  Items.Items[0].IsHelper := True;
  Items.Items[0].HasParameters := True;
  Items.Items[0].UnitName := 'U';
  Items.Items[0].Count := 2;
  Items.Items[0].Unknown := 'X';
  Items.Items[0].Batch := True;
  Items.Items[0].ByType := True;
  Items.Items[0].Unavailable := True;
  Items.Items[0].SetOf := 'TKind';
  Items.Items[0].Hides := ['Feld TKunde.Wert'];
  Items.Items[0].Overloads := [TTextPosition.Create(7, 2)];
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":5,"sortText":"00000"}]}', Json.ToJSON);
  finally
    Json.Free;
  end;
end;
procedure TLspCompletionTests.FuzzyFindsSubsequencesAndAbbreviations;
begin
  // "ehl" ist Teilwort von Zaehler, "TB" Kürzel von TBasis. Verstreute Teilfolgen wie "zlr" filtert
  // das Plugin beim Weitertippen weg; der Server liefert sie deshalb auch nicht.
  Assert.AreEqual('Zaehler', Names(ItemsAt(WithCode('  ehl'), '  ehl', TCompletionMatching.Fuzzy)));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Fuzzy)));
  Assert.AreEqual('TBasis', Names(ItemsAt(WithCode('  TBa'), '  TBa', TCompletionMatching.Fuzzy)));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  xyz'), '  xyz', TCompletionMatching.Fuzzy)));
end;
procedure TLspCompletionTests.FuzzySortsByScoreThenScope;
var
  Items: TCompletionItems;
begin
  // Präfix-Treffer vor Teilfolgen; "me" passt als Präfix auf Melde, als Teilwort nicht weiter.
  Items := ItemsAt(WithCode('  me'), '  me', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Melde', Items.Items[0].Name, Names(Items));
  // Ohne Eingabe bleibt die Reihenfolge der Gültigkeitsbereiche.
  Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ', TCompletionMatching.Fuzzy)));
end;
procedure TLspCompletionTests.FuzzySetsFilterTextAndIsIncomplete;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  // Vollständig (#616): Der Editor filtert beim Weitertippen selbst, statt bei jedem Zeichen neu zu fragen.
  Items := ItemsAt(WithCode('  ehl'), '  ehl', TCompletionMatching.Fuzzy);
  Assert.IsFalse(Items.Incomplete);
  Assert.AreEqual('ehl', Items.Items[0].FilterText);
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('ehl', Json.GetValue<string>('items[0].filterText'));
    Assert.IsTrue(Json.GetValue('isIncomplete') is TJSONFalse);
  finally
    Json.Free;
  end;
  // Präfix-Treffer brauchen keinen filterText.
  Items := ItemsAt(WithCode('  We'), '  We', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Wert', Items.Items[0].Name);
  Assert.AreEqual('', Items.Items[0].FilterText);
end;
procedure TLspCompletionTests.IncompleteOnlyWhenMoreCanCome;
begin
  // Unter MinImportPrefix fehlen die Importe noch: neu fragen, sobald genug getippt ist (#616).
  Assert.IsTrue(ItemsAt(WithCode('  W'), '  W', TCompletionMatching.Fuzzy).Incomplete, 'ein Zeichen');
  Assert.IsTrue(ItemsAt(WithCode('  '), #10'begin'#10'  ', TCompletionMatching.Fuzzy).Incomplete, 'ohne Eingabe');
  Assert.IsFalse(ItemsAt(WithCode('  We'), '  We', TCompletionMatching.Fuzzy).Incomplete, 'zwei Zeichen');
  // Nach dem Punkt gibt es keine Importe: vollständig, auch ohne Eingabe.
  Assert.IsFalse(ItemsAt(WithCode('  Wert.'), 'Wert.', TCompletionMatching.Fuzzy).Incomplete, 'Mitglieder');
end;
procedure TLspCompletionTests.ImportLimitMarksIncomplete;
var
  Lib: TUnitIndex;
  Index: Integer;
  Items: TCompletionItems;
begin
  // Mehr passende Importe als MaxImportItems: Beim Weitertippen können andere drankommen (#616).
  for Index := 1 to TLspCompletion.cMaxImportItems + 5 do
  begin
    Lib := TIndexExtractor.ExtractText(Format('unit Lib%d;'#10'interface'#10'type TTestLib%d = class end;'#10 +
      'implementation'#10'end.', [Index, Index]), Format('C:\Lib\Lib%d.pas', [Index]), nil);
    Lib.Library_ := True;
    FIndex.AddUnit(Lib);
  end;
  Items := ItemsAt(WithCode('  TTest'), '  TTest', TCompletionMatching.Fuzzy);
  Assert.AreEqual(Integer(TLspCompletion.cMaxImportItems), Integer(Length(Items.Items)));
  Assert.IsTrue(Items.Incomplete);
end;
procedure TLspCompletionTests.NameFilterSkipsIndexSymbols;
var
  Tree: TSyntaxTree;
  Text, Found: string;
  Symbol: TResolvedSymbol;
begin
  // Der Filter gilt für Symbole aus dem Index (eigene Unit, uses, Mitglieder), nicht für lokale Namen (#616).
  Text := WithCode('  ');
  Tree := TPascalParser.Parse(Text);
  try
    FResolver.Candidates.NameFilter :=
      function(const AName: string): Boolean
      begin
        Result := AName.StartsWith('R', True) or AName.StartsWith('M', True);
      end;
    try
      Found := '';
      for Symbol in FResolver.Candidates.ScopeCandidates(Tree, HauptFile,
        TCompletionContexts.Analyze(Tree, PositionOf(Text, #10'begin'#10'  ')).Offset) do
      begin
        Found := Found + Symbol.Name + ' ';
      end;
    finally
      FResolver.Candidates.NameFilter := nil;
    end;
    Assert.AreEqual('Wert Anzahl Self Melde Rechne', Found.Trim);
  finally
    Tree.Free;
  end;
end;
procedure TLspCompletionTests.StagedDeliversOwnScopeThenUsedUnits;
var
  Text: string;
  Tree: TSyntaxTree;
  Stages: TList<string>;
  Items: TCompletionItems;
  Postfix: TPostfixOptions;
  Partial: TCompletionPartialProc;
begin
  Text := WithCode('  ');
  Tree := TPascalParser.Parse(Text);
  Stages := TList<string>.Create;
  try
    Postfix := TPostfixOptions.Default;
    Postfix.Enabled := False;
    Partial :=
      procedure(const AItems: TArray<TCompletionItem>)
      var
        Part: TCompletionItems;
      begin
        Part.Items := AItems;
        Stages.Add(Names(Part));
      end;
    Items := CollectAt(LookupOf(FResolver, FIndex, Tree, Text, nil), PositionOf(Text, #10'begin'#10'  '), Postfix,
      Partial);
    // Erst lokal, Self und eigene Unit, dann die Units aus uses; die Antwort bringt den (leeren) Rest.
    Assert.AreEqual(2, Integer(Stages.Count));
    Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo', Stages[0]);
    Assert.AreEqual('TBasis Rechne', Stages[1]);
    Assert.AreEqual('', Names(Items));
    Assert.IsTrue(Items.Incomplete, 'ohne Eingabe fehlen noch die Importe');
  finally
    Stages.Free;
    Tree.Free;
  end;
end;
procedure TLspCompletionTests.StagedKeepsImportsAfterUsedNames;
var
  Text: string;
  Tree: TSyntaxTree;
  Sent: string;
  Items: TCompletionItems;
  Postfix: TPostfixOptions;
  Partial: TCompletionPartialProc;
begin
  // Gleichnamiges aus nicht eingebundenen Units kommt nicht doppelt als Import, auch wenn der eingebundene Name
  // schon in einem Teilergebnis stand; es steht einmal als Variante direkt hinter dem eingebundenen (#475).
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Rechne;'#10 +
    'procedure Rechenweg;'#10'implementation'#10'procedure Rechne; begin end;'#10 +
    'procedure Rechenweg; begin end;'#10'end.', 'C:\P\Extra.pas', nil));
  Text := WithCode('  Rech');
  Tree := TPascalParser.Parse(Text);
  try
    Postfix := TPostfixOptions.Default;
    Postfix.Enabled := False;
    Sent := '';
    Partial :=
      procedure(const AItems: TArray<TCompletionItem>)
      var
        Part: TCompletionItems;
      begin
        Part.Items := AItems;
        Sent := Sent + Names(Part) + '|';
      end;
    Items := CollectAt(LookupOf(FResolver, FIndex, Tree, Text, nil), PositionOf(Text, '  Rech'), Postfix, Partial);
    Assert.AreEqual('Rechne Rechne|', Sent);
    Assert.AreEqual('Rechenweg', Names(Items));
    Assert.AreEqual('Extra (uses ergänzen)', Items.Items[0].Detail);
  finally
    Tree.Free;
  end;
end;
procedure TLspCompletionTests.PartialJsonContinuesSortText;
var
  Items: TArray<TCompletionItem>;
  Json: TJSONArray;
begin
  SetLength(Items, 1);
  Items[0].Name := 'Wert';
  Items[0].Kind := 6;
  Json := TLspCompletion.ToJson(Items, 12);
  try
    Assert.AreEqual('[{"label":"Wert","kind":6,"sortText":"00012"}]', Json.ToJSON);
  finally
    Json.Free;
  end;
end;
procedure TLspCompletionTests.PrefixModeKeepsStrictSelection;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Prefix);
  Assert.AreEqual('', Names(Items));
  Assert.IsFalse(Items.Incomplete);
end;
procedure TLspCompletionTests.OffersSymbolsOfUnusedUnitsWithUsesEdit;
var
  Bibliothek: TUnitIndex;
  Items: TCompletionItems;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\P\Extra.pas', nil));
  Bibliothek := TIndexExtractor.ExtractText('unit Bib.Mathe;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\Bib\Bib.Mathe.pas', nil);
  Bibliothek.Library_ := True;
  FIndex.AddUnit(Bibliothek);
  Items := ItemsAt(WithCode('  Ber'), '  Ber', TCompletionMatching.Fuzzy);
  // Projekt-Unit vor Bibliothek; eingetragen wird im implementation-Teil, der noch kein uses hat.
  Assert.AreEqual('Berechne Berechne', Names(Items));
  Assert.AreEqual('Extra (uses ergänzen)', Items.Items[0].Detail);
  Assert.AreEqual('Bib.Mathe (uses ergänzen)', Items.Items[1].Detail);
  Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)));
  Assert.AreEqual(#13#10#13#10'uses'#13#10'  Extra;', Items.Items[0].AdditionalEdits[0].NewText);
  Assert.AreEqual(8, Items.Items[0].AdditionalEdits[0].Range.StartPos.Line);
end;
/// <summary>Vervollständigung an AMarker mit den Typen ATypes aus der IDE.</summary>
function IdeItemsAt(const ALookup: TEnumLookup; const AText, AMarker: string;
  const ATypes: TArray<TIdeTypeEntry>): TCompletionItems;
var
  mRequest: TCompletionRequest;
  mPostfix: TPostfixOptions;
begin
  mPostfix := TPostfixOptions.Default;
  mPostfix.Enabled := False;
  mRequest := RequestOf(ALookup, PositionOf(AText, AMarker));
  try
    mRequest.IdeTypes := ATypes;
    Result := TCompletionLists.Collect(mRequest, mPostfix, nil);
  finally
    mRequest.Free;
  end;
end;

/// <summary>Eintrag namens AName in AItems oder ein leerer.</summary>
function ItemNamed(const AItems: TCompletionItems; const AName: string): TCompletionItem;
var
  mItem: TCompletionItem;
begin
  Result := Default(TCompletionItem);
  for mItem in AItems.Items do
  begin
    if mItem.Name = AName then
    begin
      Exit(mItem);
    end;
  end;
end;

procedure TLspCompletionTests.OffersIdeTypesWithUsesEdit;
var
  mTypes: TArray<TIdeTypeEntry>;
  mText: string;
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
  mGrid: TCompletionItem;
  mColumn: TCompletionItem;
begin
  SetLength(mTypes, 2);
  mTypes[0].Name := 'TVendorGrid';
  mTypes[0].UnitName := 'Vendor.Grid';
  mTypes[1].Name := 'TVendorColumn';
  mTypes[1].UnitName := 'Werkzeug';
  mText := WithCode('  TVen');
  mTree := TPascalParser.Parse(mText);
  try
    mItems := IdeItemsAt(LookupOf(FResolver, FIndex, mTree, mText, nil), mText, '  TVen', mTypes);
    mGrid := ItemNamed(mItems, 'TVendorGrid');
    mColumn := ItemNamed(mItems, 'TVendorColumn');
    Assert.AreEqual('Vendor.Grid (uses ergänzen)', mGrid.Detail);
    Assert.AreEqual(1, Integer(Length(mGrid.AdditionalEdits)));
    Assert.AreEqual('Werkzeug', mColumn.Detail);
    Assert.AreEqual(0, Integer(Length(mColumn.AdditionalEdits)));
  finally
    mTree.Free;
  end;
  mText := WithCode('  T');
  mTree := TPascalParser.Parse(mText);
  try
    mItems := IdeItemsAt(LookupOf(FResolver, FIndex, mTree, mText, nil), mText, '  T', mTypes);
    Assert.AreEqual('', ItemNamed(mItems, 'TVendorGrid').Name);
  finally
    mTree.Free;
  end;
  mTypes := nil;
end;

procedure TLspCompletionTests.ImportsNeedTwoCharactersAndSkipUsedUnits;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  Assert.AreEqual('Bar', Names(ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Prefix)).Split([' '])[0]);
  Assert.IsFalse(Names(ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Prefix)).Contains('Berechne'));
  // Rechne kommt aus dem eingebundenen Werkzeug und erscheint nur einmal, ohne uses-Eintrag.
  Assert.AreEqual('Rechne', Names(ItemsAt(WithCode('  Rech'), '  Rech', TCompletionMatching.Prefix)));
  Assert.AreEqual(0, Integer(Length(ItemsAt(WithCode('  Rech'), '  Rech', TCompletionMatching.Prefix).Items[0].AdditionalEdits)));
end;
procedure TLspCompletionTests.ProjectImportsComeBeforeLibraryLimit;
var
  Lib: TUnitIndex;
  Index: Integer;
  Items: TCompletionItems;
  Found: Boolean;
  Item: TCompletionItem;
begin
  // Mehr passende Bibliotheks-Symbole als die Höchstzahl: die eigene Unit fehlte sonst (#492).
  for Index := 1 to 250 do
  begin
    Lib := TIndexExtractor.ExtractText(Format('unit Lib%d;'#10'interface'#10'type TTestLib%d = class end;'#10 +
      'implementation'#10'end.', [Index, Index]), Format('C:\Lib\Lib%d.pas', [Index]), nil);
    Lib.Library_ := True;
    FIndex.AddUnit(Lib);
  end;
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Eigene;'#10'interface'#10'type TTestHier = class end;'#10 +
    'implementation'#10'end.', 'C:\P\Eigene.pas', nil));
  Items := ItemsAt(WithCode('  TTest'), '  TTest', TCompletionMatching.Prefix);
  Found := False;
  for Item in Items.Items do
  begin
    if Item.Name = 'TTestHier' then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found, 'Klasse aus dem Projekt trotz vieler Bibliotheks-Treffer');
end;
procedure TLspCompletionTests.ImportsKnowParameters;
var
  Items: TCompletionItems;
begin
  // Import mit uses-Ergänzung: Parameter aus dem Index, damit das Plugin Klammern setzt.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Zeige(const S: string);'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  Items := ItemsAt(WithCode('  Zeig'), '  Zeig', TCompletionMatching.Prefix);
  Assert.AreEqual('Zeige', Items.Items[0].Name);
  Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)));
  Assert.IsTrue(Items.Items[0].HasParameters);
  Assert.AreEqual('C:\P\Extra.pas', Items.Items[0].SourceFile);
end;
procedure TLspCompletionTests.ItemsCarryTheirScope;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Scopes: string;
begin
  // #488: lokal 1, Parameter 2, Mitglied von Self 3, eigene Unit 4, andere Unit 5.
  Items := ItemsAt(WithCode('  Ziel := '), 'Ziel := ', TCompletionMatching.Prefix);
  Scopes := '';
  for Item in Items.Items do
  begin
    if (Item.Name = 'Wert') or (Item.Name = 'Anzahl') or (Item.Name = 'Name') or (Item.Name = 'TFoo') or
      (Item.Name = 'Rechne') then
    begin
      Scopes := Scopes + Item.Name + '=' + IntToStr(Item.Scope) + ';';
    end;
  end;
  Assert.Contains(Scopes, 'Wert=1;');
  Assert.Contains(Scopes, 'Anzahl=2;');
  Assert.Contains(Scopes, 'Name=3;');
  Assert.Contains(Scopes, 'TFoo=4;');
  Assert.Contains(Scopes, 'Rechne=5;');
end;
function FindItem(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to High(AItems.Items) do
  begin
    if SameText(AItems.Items[Index].Name, AName) then
    begin
      if Result = 0 then
      begin
        AItem := AItems.Items[Index];
      end;
      Inc(Result);
    end;
  end;
end;
function IndexOfItem(const AItems: TCompletionItems; const AName: string): Integer;
begin
  for Result := 0 to High(AItems.Items) do
  begin
    if SameText(AItems.Items[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;
procedure TLspCompletionTests.NearestScopeComesFirstWithoutPrefix;
const
  Text =
    'unit Kasse;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKasse = class'#10 +
    '    FDiscount: Integer;'#10 +
    '    function Calc(ACustomer: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TKasse.Calc(ACustomer: Integer): Integer;'#10 +
    'var'#10 +
    '  Total: Integer;'#10 +
    'begin'#10 +
    '  Total := '#10 +
    'end;'#10 +
    'end.';
var
  Items: TCompletionItems;
  TotalAt, CustomerAt, DiscountAt: Integer;
begin
  // #488, Abnahme: ohne Präfix lokal vor Parameter vor Feld.
  Items := ItemsAt(Text, 'Total := ');
  TotalAt := IndexOfItem(Items, 'Total');
  CustomerAt := IndexOfItem(Items, 'ACustomer');
  DiscountAt := IndexOfItem(Items, 'FDiscount');
  Assert.IsTrue(TotalAt >= 0, Names(Items));
  Assert.IsTrue(TotalAt < CustomerAt, Names(Items));
  Assert.IsTrue(CustomerAt < DiscountAt, Names(Items));
end;
procedure TLspCompletionTests.InlineVarBelowCaretIsNotOffered;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Text: string;
begin
  // #488: Inline-Variablen oberhalb des Carets ja, unterhalb nicht.
  Text := WithCode('  var Oben := 1;'#10'  Ziel := '#10'  var Unten := 2;');
  Items := ItemsAt(Text, 'Ziel := ');
  Assert.AreEqual(1, FindItem(Items, 'Oben', Item), Names(Items));
  Assert.AreEqual(1, Item.Scope);
  Assert.AreEqual(0, FindItem(Items, 'Unten', Item), Names(Items));
end;
procedure TLspCompletionTests.HiddenNamesAppearOnceWithHint;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Text: string;
  Json: TJSONObject;
begin
  // #488, Abnahme: Ein lokaler Name verdeckt das Feld Name und die Routine Rechne aus Werkzeug; beide
  // erscheinen einmal als „lokal“, das Detailpanel nennt die verdeckte Deklaration.
  Text := StringReplace(WithCode('  Ziel := '), '  Wert: TFoo;', '  Wert: TFoo;'#10'  Name: string;'#10 +
    '  Rechne: Integer;', []);
  Items := ItemsAt(Text, 'Ziel := ');
  Assert.AreEqual(1, FindItem(Items, 'Name', Item), Names(Items));
  Assert.AreEqual(1, Item.Scope);
  Assert.AreEqual<NativeInt>(1, Length(Item.Hides));
  Assert.AreEqual('Feld TFoo.Name', Item.Hides[0]);
  Assert.AreEqual(1, FindItem(Items, 'Rechne', Item), Names(Items));
  Assert.AreEqual(1, Item.Scope);
  Assert.AreEqual<NativeInt>(1, Length(Item.Hides));
  Assert.AreEqual('Werkzeug.Rechne', Item.Hides[0]);
  // Nicht verdeckt: keine Angabe; aus einer anderen Unit: deren Name für das Tag.
  Assert.AreEqual(1, FindItem(Items, 'TBasis', Item), Names(Items));
  Assert.AreEqual<NativeInt>(0, Length(Item.Hides));
  Assert.AreEqual(5, Item.Scope);
  Assert.AreEqual('Werkzeug', Item.UnitName);
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.Contains(Json.ToJSON, '"hides":["Feld TFoo.Name"]');
    Assert.Contains(Json.ToJSON, '"unit":"Werkzeug"');
  finally
    Json.Free;
  end;
end;
procedure TLspCompletionTests.PlainItemsHaveNoTextEdit;
var
  Items: TCompletionItems;
  Index: Integer;
begin
  // Regression: Add verwendete Scored wieder, ohne es zu leeren; HasTextEdit blieb mit
  // leerem Bereich stehen und das Plugin löschte alles vom Dateianfang bis zum Wort.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  Items := ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Fuzzy);
  Assert.IsTrue(Length(Items.Items) > 1);
  for Index := 0 to High(Items.Items) do
  begin
    Assert.IsFalse(Items.Items[Index].HasTextEdit, Items.Items[Index].Name);
  end;
end;
procedure TLspCompletionTests.MembersCarryContainerDepthAndOverloads;
const
  UnitUeber =
    'unit Ueber;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TGrund = class'#10 +
    '    procedure Schreibe; overload;'#10 +
    '    procedure Schreibe(const Text: string); overload;'#10 +
    '    procedure Schreibe(Wert: Integer); overload;'#10 +
    '  end;'#10 +
    '  TAbleitung = class(TGrund)'#10 +
    '    procedure Eigen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TGrund.Schreibe; begin end;'#10 +
    'procedure TGrund.Schreibe(const Text: string); begin end;'#10 +
    'procedure TGrund.Schreibe(Wert: Integer); begin end;'#10 +
    'procedure TAbleitung.Eigen; begin end;'#10 +
    'end.';
  Text =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Ueber;'#10 +
    'implementation'#10 +
    'procedure Test;'#10 +
    'var'#10 +
    '  A: TAbleitung;'#10 +
    'begin'#10 +
    '  A.'#10 +
    'end;'#10 +
    'end.';
var
  Items: TCompletionItems;
  Json: TJSONObject;
  Data: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitUeber, 'C:\P\Ueber.pas', nil));
  Items := ItemsAt(Text, '  A.');
  Assert.AreEqual('Eigen Schreibe', Names(Items));
  // Eigene Klasse: Tiefe 0; geerbt: Tiefe 1 mit deklarierender Klasse (#419).
  Assert.AreEqual('TAbleitung', Items.Items[0].Container);
  Assert.AreEqual(0, Items.Items[0].Depth);
  Assert.AreEqual('TGrund', Items.Items[1].Container);
  Assert.AreEqual(1, Items.Items[1].Depth);
  // Drei Überladungen: ein Eintrag mit zwei weiteren Positionen; Rümpfe zählen nicht (#425).
  Assert.AreEqual(2, Integer(Length(Items.Items[1].Overloads)));
  Assert.AreEqual(0, Integer(Length(Items.Items[0].Overloads)));
  // Klammern beim Übernehmen (#430): Eigen hat keine Parameter, Schreibe in zwei Überladungen.
  Assert.IsFalse(Items.Items[0].HasParameters);
  Assert.IsTrue(Items.Items[1].HasParameters);
  Json := TLspCompletion.ToJson(Items);
  try
    Data := ((Json.GetValue('items') as TJSONArray).Items[1] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('TGrund', Data.GetValue<string>('container'));
    Assert.AreEqual(1, Data.GetValue<Integer>('depth'));
    Assert.IsTrue(Data.GetValue('parameters') is TJSONTrue);
    Assert.AreEqual(2, (Data.GetValue('overloads') as TJSONArray).Count);
    Assert.AreEqual(5, (Data.GetValue('overloads') as TJSONArray).Items[0].GetValue<Integer>('line'));
  finally
    Json.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TLspCompletionTests);

end.
