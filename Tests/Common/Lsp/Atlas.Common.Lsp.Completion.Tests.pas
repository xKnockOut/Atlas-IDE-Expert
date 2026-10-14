unit Atlas.Common.Lsp.Completion.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AText, AMarker: string;
      AMatching: TCompletionMatching = TCompletionMatching.Prefix): TCompletionItems;
    function Names(const AItems: TCompletionItems): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScopeListsLocalsMembersAndUsedUnits;
    [Test]
    procedure PlainItemsHaveNoTextEdit;
    [Test]
    procedure ItemsCarryTheirScope;
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
    [Test]
    procedure MembersCarryContainerDepthAndOverloads;
    [Test]
    procedure OffersOverridesWithDeclarationAndBody;
    [Test]
    procedure OffersMatchingHandlersAndNewMethodForEvents;
    [Test]
    procedure OffersEnumValuesAndSetValues;
    [Test]
    procedure OffersMissingCaseBranches;
    [Test]
    procedure OffersDeclarationsForUnknownNames;
    [Test]
    procedure OffersMissingInterfaceMethods;
    [Test]
    procedure OffersFormComponentsByNameAndType;
    [Test]
    procedure CastsSenderToAssignedComponents;
    [Test]
    procedure OffersDataFieldNames;
    [Test]
    procedure OffersGenericInterfaceMethods;
    [Test]
    procedure GroupsByExpectedType;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.InterfaceStubs;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    Zaehler: Integer;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Versteckt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Melde;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '    Name: string;'#10 +
    '    procedure Bar(Anzahl: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +
    'var'#10 +
    '  Wert: TFoo;'#10 +
    'begin'#10 +
    '  { Kommentar Wert } |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Kommentar Wert } |', ACode, []);
end;

{ TLspCompletionTests }

procedure TLspCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCompletionTests.ItemsAt(const AText, AMarker: string;
  AMatching: TCompletionMatching): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(AText, AMarker), AMatching);
  finally
    Tree.Free;
  end;
end;

function TLspCompletionTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := Result.Trim;
end;

procedure TLspCompletionTests.ScopeListsLocalsMembersAndUsedUnits;
begin
  // Nächster Gültigkeitsbereich zuerst; Versteckt steht nur in implementation von Werkzeug.
  Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ')));
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

procedure TLspCompletionTests.FuzzyFindsSubsequencesAndAbbreviations;
begin
  // "zlr" ist Teilfolge von Zaehler, "TB" Kürzel von TBasis.
  Assert.AreEqual('Zaehler', Names(ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Fuzzy)));
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
  Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ', TCompletionMatching.Fuzzy)));
end;

procedure TLspCompletionTests.FuzzySetsFilterTextAndIsIncomplete;
var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  // Vollständig (#616): Der Editor filtert beim Weitertippen selbst, statt bei jedem Zeichen neu zu fragen.
  Items := ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Fuzzy);
  Assert.IsFalse(Items.Incomplete);
  Assert.AreEqual('zlr', Items.Items[0].FilterText);
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.AreEqual('zlr', Json.GetValue<string>('items[0].filterText'));
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
  for Index := 1 to TLspCompletion.MaxImportItems + 5 do
  begin
    Lib := TIndexExtractor.ExtractText(Format('unit Lib%d;'#10'interface'#10'type TTestLib%d = class end;'#10 +
      'implementation'#10'end.', [Index, Index]), Format('C:\Lib\Lib%d.pas', [Index]), nil);
    Lib.Library_ := True;
    FIndex.AddUnit(Lib);
  end;
  Items := ItemsAt(WithCode('  TTest'), '  TTest', TCompletionMatching.Fuzzy);
  Assert.AreEqual(Integer(TLspCompletion.MaxImportItems), Integer(Length(Items.Items)));
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
    FResolver.NameFilter :=
      function(const AName: string): Boolean
      begin
        Result := AName.StartsWith('R', True) or AName.StartsWith('M', True);
      end;
    try
      Found := '';
      for Symbol in FResolver.ScopeCandidates(Tree, HauptFile,
        TLspCompletion.Analyze(Tree, PositionOf(Text, #10'begin'#10'  ')).Offset) do
        Found := Found + Symbol.Name + ' ';
    finally
      FResolver.NameFilter := nil;
    end;
    Assert.AreEqual('Anzahl Wert Self Melde Rechne', Found.Trim);
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
    Items := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, Text, PositionOf(Text, #10'begin'#10'  '),
      TCompletionMatching.Fuzzy, Postfix, Partial);
    // Erst lokal, Self und eigene Unit, dann die Units aus uses; die Antwort bringt den (leeren) Rest.
    Assert.AreEqual(2, Integer(Stages.Count));
    Assert.AreEqual('Anzahl Wert Self Name Bar Zaehler Melde TFoo', Stages[0]);
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
  // Gleichnamiges aus nicht eingebundenen Units kommt nicht doppelt, auch wenn der eingebundene Name schon
  // in einem Teilergebnis stand.
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
    Items := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, Text, PositionOf(Text, '  Rech'),
      TCompletionMatching.Fuzzy, Postfix, Partial);
    Assert.AreEqual('Rechne|', Sent);
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
    if Item.Name = 'TTestHier' then
      Found := True;
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
    if (Item.Name = 'Wert') or (Item.Name = 'Anzahl') or (Item.Name = 'Name') or (Item.Name = 'TFoo') or
      (Item.Name = 'Rechne') then
      Scopes := Scopes + Item.Name + '=' + IntToStr(Item.Scope) + ';';
  Assert.Contains(Scopes, 'Wert=1;');
  Assert.Contains(Scopes, 'Anzahl=2;');
  Assert.Contains(Scopes, 'Name=3;');
  Assert.Contains(Scopes, 'TFoo=4;');
  Assert.Contains(Scopes, 'Rechne=5;');
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
    Assert.IsFalse(Items.Items[Index].HasTextEdit, Items.Items[Index].Name);
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

procedure TLspCompletionTests.OffersOverridesWithDeclarationAndBody;
const
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBasisListe = class'#13#10 +
    '  protected'#13#10 +
    '    procedure Changed; virtual;'#13#10 +
    '    function Count: Integer; virtual;'#13#10 +
    '    procedure Fest;'#13#10 +
    '    procedure Pruefe(A: Integer; const B: string = ''''); virtual; abstract;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TLogList = class(TBasisListe)'#13#10 +
    '  protected'#13#10 +
    '    procedure '#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Body: string;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.OverrideItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, '    procedure '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, Items));
    // Nur virtuelle Prozeduren; Count ist eine Funktion, Fest nicht virtuell.
    Assert.AreEqual('Changed Pruefe', Names(Items));
    Assert.AreEqual('Changed; override;', Items.Items[0].InsertText);
    Assert.AreEqual('TBasisListe', Items.Items[0].Container);
    Assert.AreEqual(1, Integer(Length(Items.Items[0].AdditionalEdits)));
    Body := Items.Items[0].AdditionalEdits[0].NewText;
    Assert.IsTrue(Body.Contains('procedure TLogList.Changed;'#13#10'begin'#13#10'  inherited;'#13#10'end;'), Body);
    // Abstrakt: ohne inherited; Standardwert nur in der Deklaration.
    Assert.AreEqual('Pruefe(A: Integer; const B: string = ''''); override;', Items.Items[1].InsertText);
    Body := Items.Items[1].AdditionalEdits[0].NewText;
    Assert.IsTrue(Body.Contains('procedure TLogList.Pruefe(A: Integer; const B: string);'), Body);
    Assert.IsFalse(Body.Contains('inherited'), Body);
    // Außerhalb einer Klassendeklaration kein Override-Kontext.
    Assert.IsFalse(TLspCompletion.OverrideItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'uses Ba'), nil, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersMatchingHandlersAndNewMethodForEvents;
const
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TNotifyEvent = procedure(Sender: TObject) of object;'#13#10 +
    '  TButton = class'#13#10 +
    '  published'#13#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TForm1 = class'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    procedure FormCreate(Sender: TObject);'#13#10 +
    '    procedure Fertig(Sender: TObject; var Done: Boolean);'#13#10 +
    '    procedure btnSaveClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TForm1.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  btnSave.OnClick := '#13#10 +
    'end;'#13#10 +
    'procedure TForm1.Fertig(Sender: TObject; var Done: Boolean);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'procedure TForm1.btnSaveClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Handlers, Edits: string;
  Edit: TRuleEdit;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.EventItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'btnSave.OnClick := '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, Items));
    // Nur Methoden mit (Sender: TObject); Fertig hat zwei Parameter.
    Handlers := '';
    for Item in Items.Items do
      if Item.Action = '' then
      begin
        Handlers := Handlers + ' ' + Item.Name;
        Assert.AreEqual('TNotifyEvent', Item.Expected);
        Assert.IsTrue(Item.Fits);
      end;
    Assert.AreEqual(' FormCreate btnSaveClick', Handlers);
    // Zuletzt die neue Methode; btnSaveClick ist vergeben.
    Item := Items.Items[High(Items.Items)];
    Assert.AreEqual('create', Item.Action);
    Assert.AreEqual('Neue Methode btnSaveClick2 …', Item.Name);
    Assert.AreEqual('btnSaveClick2', Item.InsertText);
    Edits := '';
    for Edit in Item.AdditionalEdits do
      Edits := Edits + Edit.NewText + '|';
    Assert.AreEqual(2, Integer(Length(Item.AdditionalEdits)), Edits);
    Assert.IsTrue(Edits.Contains('private'#13#10'    procedure btnSaveClick2(Sender: TObject);'), Edits);
    Assert.IsTrue(Edits.Contains('procedure TForm1.btnSaveClick2(Sender: TObject);'#13#10'begin'#13#10#13#10'end;'),
      Edits);
    // Keine Ereignis-Zuweisung: normale Vervollständigung.
    Assert.IsFalse(TLspCompletion.EventItems(Resolver, Tree, Text, HauptFile, PositionOf(Text, 'uses Ba'), nil, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersGenericInterfaceMethods;
const
  UnitListen =
    'unit Listen;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IVergleich<T> = interface'#13#10 +
    '    function Compare(const Left, Right: T): Integer;'#13#10 +
    '  end;'#13#10 +
    '  IListe<T> = interface(IVergleich<T>)'#13#10 +
    '    procedure Add(const AItem: T);'#13#10 +
    '    function Items: TArray<T>;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  // Zeile 8: leere Zeile in der Klasse, Zeile 9: ihr end. Compare ist schon da (mit eingesetztem Typ).
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Listen;'#13#10 +
    'type'#13#10 +
    '  TKunde = class'#13#10 +
    '  end;'#13#10 +
    '  TKundenListe = class(TInterfacedObject, IListe<TKunde>)'#13#10 +
    '    function Compare(const Left, Right: TKunde): Integer;'#13#10 +
    '    '#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  List: TCompletionItems;
  Edits, Merged: TArray<TRuleEdit>;
  Item: TCompletionItem;
  Batch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitListen, 'C:\P\Listen.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(8, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitListen;
        Result := SameText(AFileName, 'C:\P\Listen.pas');
      end, TCompletionInterfaceSection.Public, Items, Batch));
    List.Items := Items;
    Assert.AreEqual('Add Items', Names(List));
    Assert.AreEqual('IListe<TKunde>', Items[0].Container);
    Assert.Contains(Items[0].Detail, 'procedure Add(const AItem: TKunde)');
    Assert.Contains(Items[1].Detail, 'function Items: TArray<TKunde>');
    Edits := nil;
    for Item in Items do
      Edits := Edits + Item.AdditionalEdits;
    Merged := TInterfaceStubs.Merge(Edits);
    Assert.IsTrue(Merged[0].NewText.Contains('{ IListe<TKunde> }'), Merged[0].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains('procedure TKundenListe.Add(const AItem: TKunde);'), Merged[1].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains('Result := Default(TArray<TKunde>);'), Merged[1].NewText);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersMissingInterfaceMethods;
const
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IFlush = interface'#13#10 +
    '    procedure Flush;'#13#10 +
    '  end;'#13#10 +
    '  IExporter = interface(IFlush)'#13#10 +
    '    procedure Export(const AFileName: string);'#13#10 +
    '    function GetName: string;'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '    property Name: string read GetName write SetName;'#13#10 +
    '  end;'#13#10 +
    '  TBasis = class(TInterfacedObject)'#13#10 +
    '  public'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  // Zeile 7: leere Zeile in der Klasse, Zeile 8: ihr end.
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TJsonExporter = class(TBasis, IExporter)'#13#10 +
    '  private'#13#10 +
    '    FText: string;'#13#10 +
    '    '#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Typed =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TJsonExporter = class(TBasis, IExporter)'#13#10 +
    '  private'#13#10 +
    '    FText: string;'#13#10 +
    '    Ex'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  List: TCompletionItems;
  Edits, Merged: TArray<TRuleEdit>;
  Item: TCompletionItem;
  Batch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Strg+Leer auf der leeren Zeile: Liste mit Kontrollkästchen. SetName erbt die Klasse von TBasis.
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(7, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, TCompletionInterfaceSection.Public, Items, Batch));
    Assert.IsTrue(Batch);
    List.Items := Items;
    Assert.AreEqual('Export GetName Flush', Names(List));
    Assert.AreEqual('IExporter', Items[0].Container);
    Assert.AreEqual('IFlush', Items[2].Container);
    Assert.AreEqual('IExporter, IFlush', Items[0].SetOf);
    Assert.IsTrue(Items[0].Batch and Items[0].SetChecked);
    Assert.AreEqual(3, Items[2].Ordinal);
    Assert.AreEqual(7, Items[0].SetRange.StartPos.Line);
    // Alle angehakt: ein neuer public-Abschnitt vor dem end, je Interface mit Kommentar; Rümpfe in die implementation.
    Edits := nil;
    for Item in Items do
      Edits := Edits + Item.AdditionalEdits;
    Merged := TInterfaceStubs.Merge(Edits);
    Assert.AreEqual(2, Integer(Length(Merged)));
    Assert.AreEqual(8, Merged[0].Range.StartPos.Line);
    Assert.AreEqual(
      '  public'#13#10 +
      '    { IExporter }'#13#10 +
      '    procedure Export(const AFileName: string);'#13#10 +
      '    function GetName: string;'#13#10 +
      '    { IFlush }'#13#10 +
      '    procedure Flush;'#13#10, Merged[0].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains(
      'function TJsonExporter.GetName: string;'#13#10'begin'#13#10'  Result := Default(string);'#13#10'end;'),
      Merged[1].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains('procedure TJsonExporter.Flush;'#13#10'begin'#13#10#13#10'end;'),
      Merged[1].NewText);
    Assert.IsFalse(Merged[1].NewText.Contains('inherited'), Merged[1].NewText);
    // Abschnitt nach Einstellung: private steht schon als letzter da, also kein neuer.
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(7, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := True;
      end, TCompletionInterfaceSection.Private, Items, Batch));
    Assert.AreEqual('    { IExporter }'#13#10, Items[0].AdditionalEdits[0].NewText);
    // Außerhalb der Klasse nichts.
    Assert.IsFalse(TLspCompletion.InterfaceItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(2, 0), nil,
      TCompletionInterfaceSection.Public, Items, Batch));
  finally
    Tree.Free;
  end;
  // Angefangenes Wort: je Interface ein Hinweis, der seine Methoden anlegt und das Wort entfernt.
  Tree := TPascalParser.Parse(Typed);
  try
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, Typed, HauptFile, TTextPosition.Create(7, 6),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := True;
      end, TCompletionInterfaceSection.Public, Items, Batch));
    Assert.IsFalse(Batch);
    Assert.AreEqual(2, Integer(Length(Items)));
    Assert.AreEqual('2 Methoden von IExporter fehlen', Items[0].Name);
    Assert.AreEqual('1 Methode von IFlush fehlt', Items[1].Name);
    Assert.IsTrue(Items[0].Hint and Items[0].HasTextEdit);
    Assert.AreEqual('', Items[0].TextEdit.NewText);
    Assert.AreEqual(4, Items[0].TextEdit.Range.StartPos.Character);
    Assert.IsTrue(Items[0].AdditionalEdits[0].NewText.Contains('function GetName: string;'));
    Assert.IsFalse(Items[0].AdditionalEdits[0].NewText.Contains('Flush'));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersFormComponentsByNameAndType;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  end;'#13#10 +
    '  TPanel = class'#13#10 +
    '  end;'#13#10 +
    '  TButtonControl = class'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TButtonControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TCheckBox = class(TButtonControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  // Formular wie aus dem Designer; der Panel-Inhalt zählt mit.
  FormText =
    'object frmMain: TfrmMain'#13#10 +
    '  Caption = ''Haupt'''#13#10 +
    '  object pnlOben: TPanel'#13#10 +
    '    object btnSave: TButton'#13#10 +
    '      Caption = ''Speichern'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '  end'#13#10 +
    '  object chkAktiv: TCheckBox'#13#10 +
    '  end'#13#10 +
    'end';

  /// <summary>Zeile 15 im Rumpf von Frei, Zeile 19 in TfrmMain.FormCreate.</summary>
  function Source(const AFrei, AForm: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Steuer;'#13#10 +
      'type'#13#10 +
      '  TfrmMain = class(TForm)'#13#10 +
      '    pnlOben: TPanel;'#13#10 +
      '    btnSave: TButton;'#13#10 +
      '    btnLoad: TBitBtn;'#13#10 +
      '    chkAktiv: TCheckBox;'#13#10 +
      '    procedure FormCreate(Sender: TObject);'#13#10 +
      '  end;'#13#10 +
      'implementation'#13#10 +
      '{$R *.dfm}'#13#10 +
      'procedure Frei;'#13#10 +
      'begin'#13#10 +
      '  ' + AFrei + #13#10 +
      'end;'#13#10 +
      'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 +
      'begin'#13#10 +
      '  ' + AForm + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  /// <summary>Komponenten mit ATyped vor dem Cursor, in der Methode des Formulars oder in Frei.</summary>
  function Components(const ATyped: string; AInForm: Boolean; out AItems: TArray<TCompletionItem>): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
    Position: TTextPosition;
  begin
    if AInForm then
    begin
      Text := Source('', ATyped);
      Position := TTextPosition.Create(19, 2 + Length(ATyped));
    end
    else
    begin
      Text := Source(ATyped, '');
      Position := TTextPosition.Create(15, 2 + Length(ATyped));
    end;
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := TLspCompletion.ComponentItems(Resolver, Tree, Text, HauptFile, Position,
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := FormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end, TCompletionMatching.Fuzzy, AItems);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

  function Joined(const AItems: TArray<TCompletionItem>): string;
  var
    Item: TCompletionItem;
  begin
    Result := '';
    for Item in AItems do
    begin
      Result := Result + Item.Name;
      if Item.ByType then
        Result := Result + '*';
      Result := Result + ' ';
    end;
    Result := Result.Trim;
  end;

var
  Items: TArray<TCompletionItem>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSteuer, 'C:\P\Steuer.pas', nil));
  // Ohne Getipptes alle Komponenten in der Reihenfolge der Formulardatei, mit Typ und Formularname.
  Assert.IsTrue(Components('', True, Items));
  Assert.AreEqual('pnlOben btnSave btnLoad chkAktiv', Joined(Items));
  Assert.AreEqual('TButton', Items[1].Detail);
  Assert.AreEqual('frmMain', Items[1].Form);
  Assert.AreEqual(3, Items[1].Scope);
  // Über den Namen.
  Assert.IsTrue(Components('btn', True, Items));
  Assert.AreEqual('btnSave btnLoad', Joined(Items));
  // Über den Typ: TButton selbst und TBitBtn als Nachfahr, nicht TCheckBox über TButtonControl.
  Assert.IsTrue(Components('button', True, Items));
  Assert.AreEqual('btnSave* btnLoad*', Joined(Items));
  // Außerhalb der Methoden des Formulars nichts.
  Assert.IsFalse(Components('', False, Items));
end;

procedure TLspCompletionTests.CastsSenderToAssignedComponents;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  public'#13#10 +
    '    procedure Click;'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TButton.Click;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';
  FormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  // Zeile 14: "  Sender.Cap" in btnAnyClick, Zeile 18: "  Sender." in Frei (keinem Ereignis zugewiesen).
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    btnLoad: TBitBtn;'#13#10 +
    '    procedure btnAnyClick(Sender: TObject);'#13#10 +
    '    procedure Frei(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.btnAnyClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.Cap'#13#10 +
    'end;'#13#10 +
    'procedure TfrmMain.Frei(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  ReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSteuer, 'C:\P\Steuer.pas', nil));
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := FormText;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    // btnSave (TButton) und btnLoad (TBitBtn): gemeinsamer Vorfahr TButton.
    Assert.IsTrue(TLspCompletion.SenderItems(Resolver, FIndex, Tree, Text, HauptFile, TTextPosition.Create(14, 12),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.AsOperator, Items));
    Assert.AreEqual('Caption', Names(Items));
    Assert.AreEqual('TButton', Items.Items[0].Sender);
    Assert.AreEqual('btnSave, btnLoad', Items.Items[0].SenderOf);
    Assert.IsTrue(Items.Items[0].HasTextEdit);
    Assert.AreEqual('(Sender as TButton).Caption', Items.Items[0].TextEdit.NewText);
    Assert.AreEqual(2, Items.Items[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(12, Items.Items[0].TextEdit.Range.EndPos.Character);
    Assert.IsTrue(TLspCompletion.SenderItems(Resolver, FIndex, Tree, Text, HauptFile, TTextPosition.Create(14, 12),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.HardCast, Items));
    Assert.AreEqual('TButton(Sender).Caption', Items.Items[0].TextEdit.NewText);
    // Ohne Zuweisung im Formular bleibt es bei den Mitgliedern von TObject.
    Assert.IsFalse(TLspCompletion.SenderItems(Resolver, FIndex, Tree, Text, HauptFile, TTextPosition.Create(18, 9),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.AsOperator, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersDeclarationsForUnknownNames;
const
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TLines = class'#13#10 +
    '    Count: Integer;'#13#10 +
    '  end;'#13#10 +
    '  TRechner = class'#13#10 +
    '  private'#13#10 +
    '    FLines: TLines;'#13#10 +
    '  public'#13#10 +
    '    procedure Summe(Extra: TLines);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Zeige(N: Integer);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'procedure TRechner.Summe(Extra: TLines);'#13#10 +
    'begin'#13#10 +
    '  TotalCount := FLines.Count + Extra.Count;'#13#10 +
    '  Zeige(Anzahl);'#13#10 +
    '  FLines := nil;'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;

  function Named(const AName: string): TCompletionItem;
  var
    Item: TCompletionItem;
  begin
    for Item in Items do
      if Item.Name = AName then
        Exit(Item);
    raise Exception.CreateFmt('Eintrag "%s" fehlt', [AName]);
  end;

var
  Item: TCompletionItem;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Ziel einer Zuweisung: Typ aus der rechten Seite.
    Assert.IsTrue(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, '  TotalCount'), True, nil, Items));
    Item := Named('Lokale Variable anlegen');
    Assert.AreEqual('TotalCount: Integer', Item.Detail);
    Assert.AreEqual('declare', Item.Action);
    Assert.AreEqual('TotalCount', Item.Unknown);
    // Die Verwendung bleibt, der Cursor auch; var vor begin.
    Assert.AreEqual('TotalCount$0', Item.TextEdit.NewText);
    Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
    Assert.AreEqual('var'#13#10'  TotalCount: Integer;'#13#10, Item.AdditionalEdits[0].NewText);
    Assert.AreEqual(17, Item.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual('var TotalCount$0', Named('Inline-Variable anlegen').TextEdit.NewText);
    // Feld mit F-Konvention: im private-Abschnitt, die Verwendung heißt danach FTotalCount.
    Item := Named('Feld FTotalCount anlegen');
    Assert.AreEqual('FTotalCount$0', Item.TextEdit.NewText);
    Assert.AreEqual(7, Item.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual(#13#10'    FTotalCount: Integer;', Item.AdditionalEdits[0].NewText);
    // Keine Konstante als Ziel einer Zuweisung.
    for Item in Items do
      Assert.AreNotEqual('Konstante anlegen', Item.Name);
    // Als Argument: Typ des Parameters, auch als Konstante in der implementation.
    Assert.IsTrue(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'Zeige(Anzahl'), False, nil, Items));
    Assert.AreEqual('Anzahl: Integer', Named('Lokale Variable anlegen').Detail);
    Item := Named('Konstante anlegen');
    Assert.AreEqual('Anzahl = 0;', Item.Detail);
    Assert.AreEqual(12, Item.AdditionalEdits[0].Range.StartPos.Line);
    // Bekannte Namen und genaue Treffer: nichts.
    Assert.IsFalse(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'Zeige(Anzahl);'#13#10'  FLines'), True, nil, Items));
    SetLength(Items, 1);
    Items[0] := Default(TCompletionItem);
    Items[0].Name := 'Anzahl';
    Assert.IsFalse(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'Zeige(Anzahl'), True, Items, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersMissingCaseBranches;
const
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TShapeKind = (skCircle, skLine, skRect, skTriangle);'#13#10 +
    '  TShape = class'#13#10 +
    '    Kind: TShapeKind;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Ergaenzen(Shape: TShape);'#13#10 +
    'begin'#13#10 +
    '  case Shape.Kind of'#13#10 +
    '    skCircle: Zeichne;'#13#10 +
    '    sk'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    'procedure Vollstaendig(Shape: TShape);'#13#10 +
    'begin'#13#10 +
    '  case Shape.Kind of'#13#10 +
    '    skCircle..skRect, skTriangle: ;'#13#10 +
    '    '#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    // Zuletzt: Ohne end der case-Anweisung liest der Parser den Rest als ihren Teil.
    'procedure Neu(S: TShape);'#13#10 +
    'begin'#13#10 +
    '  case S.Kind of'#13#10 +
    '    '#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  SetMode: Boolean;
  Position: TTextPosition;
begin
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Ohne Zweige: „Alle Werte einfügen“ zuerst, mit Anzahl; alle vier Zweige und das fehlende end.
    Position := PositionOf(Text, 'case S.Kind of'#13#10'    ');
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, Position, nil,
      TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('Alle Werte einfügen', Items[0].Name);
    Assert.IsTrue(Items[0].Pinned);
    Assert.AreEqual(4, Items[0].Count);
    Assert.IsTrue(Items[0].HasTextEdit);
    Assert.AreEqual(#13#10'    skCircle: $0;'#13#10'    skLine: ;'#13#10'    skRect: ;'#13#10'    skTriangle: ;' +
      #13#10'  end;', Items[0].TextEdit.NewText);
    // Ersetzt wird ab dem "of" bis zum Cursor (der Leerraum der Zeile).
    Assert.AreEqual(24, Items[0].TextEdit.Range.StartPos.Line);
    Assert.AreEqual(16, Items[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(Position.Line, Items[0].TextEdit.Range.EndPos.Line);
    Assert.AreEqual(Position.Character, Items[0].TextEdit.Range.EndPos.Character);
    Assert.AreEqual('skCircle', Items[1].Name, 'darunter die einzelnen Werte');
    // Mit Zweig skCircle: nur die drei übrigen, end ist vorhanden.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'skCircle: Zeichne;'#13#10'    sk'), nil, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('Fehlende Werte ergänzen (3)', Items[0].Name);
    Assert.AreEqual(0, Items[0].Count);
    Assert.AreEqual(#13#10'    skLine: $0;'#13#10'    skRect: ;'#13#10'    skTriangle: ;', Items[0].TextEdit.NewText);
    // Bereiche und Listen zählen als vorhanden: nichts mehr zu ergänzen.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'skTriangle: ;'#13#10'    '), nil, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('skCircle', Items[0].Name);
    Assert.IsFalse(Items[0].Pinned);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.OffersEnumValuesAndSetValues;
const
  TypenFile = 'C:\P\Typen.pas';
  UnitTypen =
    'unit Typen;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TAlign = (alNone, alTop,'#13#10 +
    '    alClient);'#13#10 +
    '{$SCOPEDENUMS ON}'#13#10 +
    '  TShapeKind = (skCircle, skRect, skLine, skTriangle);'#13#10 +
    '{$SCOPEDENUMS OFF}'#13#10 +
    '  TAnchorKind = (akLeft, akTop, akRight, akBottom);'#13#10 +
    '  TAnchors = set of TAnchorKind;'#13#10 +
    '  TControl = class'#13#10 +
    '    Align: TAlign;'#13#10 +
    '    Anchors: TAnchors;'#13#10 +
    '    Kind: TShapeKind;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Typen;'#13#10 +
    'implementation'#13#10 +
    'procedure Setze(C: TControl; List: TArray<Integer>);'#13#10 +
    'begin'#13#10 +
    '  C.Align := ;'#13#10 +
    '  if C.Kind = sk then;'#13#10 +
    '  case C.Kind of'#13#10 +
    '    TShapeKind.skCircle: ;'#13#10 +
    '    '#13#10 +
    '  end;'#13#10 +
    '  C.Anchors := [akLeft, ];'#13#10 +
    '  if C.Kind in [] then;'#13#10 +
    '  List[0] := List[];'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  SetMode: Boolean;
  Reader: TCompletionReadText;

  function Joined: string;
  var
    Item: TCompletionItem;
  begin
    Result := '';
    for Item in Items do
      Result := Result + ' ' + Item.Name;
    Result := Result.Trim;
  end;

begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTypen, TypenFile, nil));
  Reader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := UnitTypen;
      Result := SameText(AFileName, TypenFile);
    end;
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Zuweisung: Werte in Deklarationsreihenfolge, auch über mehrere Zeilen.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'C.Align := '),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsFalse(SetMode);
    Assert.AreEqual('alNone alTop alClient', Joined);
    Assert.AreEqual(3, Items[2].Ordinal);
    Assert.AreEqual('TAlign', Items[0].Expected);
    Assert.IsTrue(Items[0].Fits);
    Assert.AreEqual('', Items[0].InsertText);
    Assert.AreEqual(TypenFile, Items[0].SourceFile, 'Position für completionItem/resolve');
    // Vergleich mit Scoped Enum: Typpräfix beim Einfügen, gefiltert nach dem Getippten.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'C.Kind = sk'),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual(4, Integer(Length(Items)));
    Assert.AreEqual('TShapeKind.skCircle', Items[0].InsertText);
    // case-Zweig.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'skCircle: ;'#13#10'    '), Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('Fehlende Werte ergänzen (3) skCircle skRect skLine skTriangle', Joined);
    Assert.AreEqual(#13#10'    TShapeKind.skRect: $0;'#13#10'    TShapeKind.skLine: ;'#13#10'    TShapeKind.skTriangle: ;',
      Items[0].TextEdit.NewText, 'Scoped Enum mit Typpräfix (#449)');
    // Menge: alle Werte des Elementtyps, akLeft angehakt, Enter ersetzt die ganze Klammer.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile,
      PositionOf(Text, 'C.Anchors := [akLeft, '), Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsTrue(SetMode);
    Assert.AreEqual('akLeft akTop akRight akBottom', Joined);
    Assert.IsTrue(Items[0].SetChecked);
    Assert.IsFalse(Items[1].SetChecked);
    Assert.AreEqual('TAnchorKind', Items[0].SetOf);
    Assert.AreEqual('TAnchors', Items[0].Expected);
    Assert.AreEqual(12, Items[0].SetRange.StartPos.Line);
    Assert.AreEqual(15, Items[0].SetRange.StartPos.Character);
    Assert.AreEqual(25, Items[0].SetRange.EndPos.Character);
    // "in": Elementtyp aus der linken Seite.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'C.Kind in ['),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsTrue(SetMode);
    Assert.AreEqual('set of TShapeKind', Items[0].Expected);
    Assert.AreEqual('TShapeKind.skCircle', Items[0].InsertText);
    // Index statt Menge.
    Assert.IsFalse(TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, ':= List['),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsFalse(SetMode);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionTests.GroupsByExpectedType;

  function MakeText(const ALine: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'type'#13#10 +
      '  TBasis = class'#13#10 +
      '  end;'#13#10 +
      '  TKind = class(TBasis)'#13#10 +
      '  end;'#13#10 +
      '  TListe = class'#13#10 +
      '  public'#13#10 +
      '    function Count: Integer;'#13#10 +
      '    function Name: string;'#13#10 +
      '    function IndexOf(const S: string): Integer;'#13#10 +
      '    procedure Clear;'#13#10 +
      '    property Erstes: TKind read FErstes;'#13#10 +
      '  end;'#13#10 +
      'function Rechne(A: Integer; B: TBasis): Integer;'#13#10 +
      'implementation'#13#10 +
      'function Rechne(A: Integer; B: TBasis): Integer;'#13#10 +
      'var'#13#10 +
      '  L: TListe;'#13#10 +
      '  I: Integer;'#13#10 +
      '  Obj: TBasis;'#13#10 +
      'begin'#13#10 +
      '  ' + ALine + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  function Check(const ALine, AExpected, AFits: string): string;
  var
    Text, Fits: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
    Items: TCompletionItems;
    Item: TCompletionItem;
    Position: TTextPosition;
    Fitting: Boolean;
  begin
    Text := MakeText(ALine);
    Position := PositionOf(Text, ALine);
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := TLspCompletion.ExpectedType(Resolver, Tree, HauptFile, Position);
      Items := TLspCompletion.Collect(Resolver, FIndex, Tree, HauptFile, Position);
      // Passende zuerst, danach keine passenden mehr.
      Fits := '';
      Fitting := True;
      for Item in Items.Items do
      begin
        Assert.AreEqual(AExpected, Item.Expected, ALine + ': ' + Item.Name);
        if Item.Fits then
        begin
          Assert.IsTrue(Fitting, ALine + ': ' + Item.Name + ' steht hinter nicht passenden');
          Fits := Fits + ' ' + Item.Name;
        end
        else
          Fitting := False;
      end;
      Assert.AreEqual(AFits, Trim(Fits), ALine);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

begin
  // Beispiel aus #417: Integer-Zuweisung, Count und IndexOf oben.
  Assert.AreEqual('Integer', Check('I := L.', 'Integer', 'Count IndexOf'));
  // Klasse: Nachfahr passt.
  Assert.AreEqual('TBasis', Check('Obj := L.', 'TBasis', 'Erstes'));
  // Parameter im Aufruf.
  Assert.AreEqual('TBasis', Check('Rechne(1, L.', 'TBasis', 'Erstes'));
  // Rückgabetyp bei Result.
  Assert.AreEqual('Integer', Check('Result := L.', 'Integer', 'Count IndexOf'));
  // Ohne erwarteten Typ keine Gruppierung.
  Assert.AreEqual('', Check('L.', '', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionTests);

procedure TLspCompletionTests.OffersDataFieldNames;
const
  FormText =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.CUSTOMER_ID, O.CURRENCY, O.TOTAL from ORDERS O where O.ID = :OrderId'')'#13#10 +
    '    object qryOrdersCUSTOMER_ID: TIntegerField'#13#10 +
    '      FieldName = ''CUSTOMER_ID'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  function Items(const ALine: string; ACharacter: Integer; out AItems: TCompletionItems): Boolean;
  begin
    Result := TLspCompletion.DataNameItems(nil, 'unit Haupt;'#13#10'{$R *.dfm}'#13#10 + ALine + #13#10, HauptFile,
      TTextPosition.Create(2, ACharacter),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := FormText;
        Result := SameText(ExtractFileExt(AFileName), '.dfm');
      end, AItems);
  end;

var
  Found: TCompletionItems;
  Json: TJSONObject;
begin
  // qryOrders.FieldByName('cu|'): persistente Felder, dann Spalten; der ganze String-Inhalt wird ersetzt.
  Assert.IsTrue(Items('  qryOrders.FieldByName(''cu'').AsInteger;', 27, Found));
  Assert.AreEqual(3, Integer(Length(Found.Items)));
  Assert.AreEqual('CUSTOMER_ID', Found.Items[0].Name);
  Assert.AreEqual('Integer', Found.Items[0].Detail);
  Assert.AreEqual('CURRENCY', Found.Items[1].Name);
  Assert.AreEqual('TOTAL', Found.Items[2].Name);
  Assert.IsTrue(Found.Items[1].HasTextEdit);
  Assert.AreEqual(25, Found.Items[1].TextEdit.Range.StartPos.Character);
  Assert.AreEqual(27, Found.Items[1].TextEdit.Range.EndPos.Character);
  Assert.AreEqual('CURRENCY', Found.Items[1].TextEdit.NewText);
  Json := TLspCompletion.ToJson(Found);
  try
    Assert.IsTrue(Json.ToJSON.Contains('"dataSet":"qryOrders"'));
    Assert.IsTrue(Json.ToJSON.Contains('"dataSource":"select O.CUSTOMER_ID'));
  finally
    Json.Free;
  end;
  // ParamByName: die Platzhalter.
  Assert.IsTrue(Items('  qryOrders.ParamByName('''')', 25, Found));
  Assert.AreEqual(1, Integer(Length(Found.Items)));
  Assert.AreEqual('OrderId', Found.Items[0].Name);
  // Zur Laufzeit erzeugt: im String, aber ohne Vorschlag.
  Assert.IsTrue(Items('  qryNeu.FieldByName(''cu'')', 24, Found));
  Assert.AreEqual(0, Integer(Length(Found.Items)));
  // Andere Strings gehören nicht dazu.
  Assert.IsFalse(Items('  ShowMessage(''cu'');', 17, Found));
end;

end.
