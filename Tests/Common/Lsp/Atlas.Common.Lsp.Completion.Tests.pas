unit Atlas.Common.Lsp.Completion.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
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
  Atlas.Common.Semantics.NameResolver,
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
  mSource, mText: string;
  mIndex: Integer;
  mItems: TCompletionItems;
begin
  // Rückmeldung 15.10.2026: Bei einem Vorfahren mit mehr als MaxItems kurzen Mitgliedern fielen eigene
  // Methoden mit längerem Namen beim Kürzen heraus.
  mSource := 'unit Gross;'#10'interface'#10'type'#10'  TGross = class'#10'  public'#10;
  for mIndex := 0 to TLspCompletion.cMaxItems + 199 do
  begin
    mSource := mSource + '    procedure R' + IntToStr(mIndex) + ';'#10;
  end;
  mSource := mSource + '  end;'#10'implementation'#10'end.';
  FIndex.AddUnit(TIndexExtractor.ExtractText(mSource, 'C:\P\Gross.pas', nil));
  mText := StringReplace(StringReplace(WithCode('  R'), 'uses Werkzeug;', 'uses Werkzeug, Gross;', []),
    'class(TBasis)', 'class(TGross)', []);
  mText := StringReplace(mText, '    procedure Bar(Anzahl: Integer);',
    '    procedure Bar(Anzahl: Integer);'#10'    procedure RechneSehrLangerName;', []);
  mItems := ItemsAt(mText, #10'  R', TCompletionMatching.Fuzzy);
  Assert.IsTrue(mItems.Incomplete);
  Assert.AreEqual<NativeInt>(TLspCompletion.cMaxItems, Length(mItems.Items));
  Assert.IsTrue(Pos(' RechneSehrLangerName ', ' ' + Names(mItems) + ' ') > 0, 'eigene Methode fehlt');
end;
procedure TLspCompletionTests.ScopeFiltersByPrefix;
begin
  Assert.AreEqual('Wert', Names(ItemsAt(WithCode('  We'), '  We')));
  Assert.AreEqual('TFoo', Names(ItemsAt(WithCode('  tf'), '  tf')));
end;
procedure TLspCompletionTests.MembersAfterDotIncludeInherited;
var
  mText: string;
begin
  mText := WithCode('  Wert.');
  Assert.AreEqual('Name Bar Zaehler Melde', Names(ItemsAt(mText, 'Wert.')));
  mText := WithCode('  Self.Za');
  Assert.AreEqual('Zaehler', Names(ItemsAt(mText, 'Self.Za')));
end;
procedure TLspCompletionTests.MembersOfUnitAreInterfaceSymbols;
var
  mText: string;
begin
  mText := WithCode('  Werkzeug.');
  Assert.AreEqual('TBasis Rechne', Names(ItemsAt(mText, 'Werkzeug.')));
end;
procedure TLspCompletionTests.UsesClauseListsUnits;
var
  mText: string;
  mItems: TCompletionItems;
begin
  mText := StringReplace(cUnitHaupt, 'uses Werkzeug;', 'uses Werk', []);
  mItems := ItemsAt(mText, 'uses Werk');
  Assert.AreEqual('Werkzeug', Names(mItems));
  Assert.AreEqual(9, mItems.Items[0].Kind);
end;
procedure TLspCompletionTests.NothingInCommentsAndStrings;
begin
  Assert.AreEqual('', Names(ItemsAt(cUnitHaupt, '{ Kommentar W')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  Name := ''We'';'), '''We')));
  Assert.AreEqual('', Names(ItemsAt(WithCode('  // We'), '// We')));
end;
procedure TLspCompletionTests.WritesCompletionList;
var
  mItems: TCompletionItems;
  mJson: TJSONObject;
begin
  SetLength(mItems.Items, 1);
  mItems.Items[0].Name := 'Wert';
  mItems.Items[0].Detail := 'TFoo';
  mItems.Items[0].Kind := 6;
  mItems.Incomplete := False;
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":6,"detail":"TFoo","sortText":"00000"}]}',
      mJson.ToJSON);
  finally
    mJson.Free;
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
  mItems: TCompletionItems;
  mJson: TJSONObject;
begin
  mItems := Default(TCompletionItems);
  SetLength(mItems.Items, 1);
  mItems.Items[0] := FullDataItem;
  mItems.Incomplete := True;
  mJson := TLspCompletion.ToJson(mItems);
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
      mJson.ToJSON);
  finally
    mJson.Free;
  end;
  // textEdit hat Vorrang vor insertText.
  mItems.Items[0] := Default(TCompletionItem);
  mItems.Items[0].Name := 'for';
  mItems.Items[0].Kind := 15;
  mItems.Items[0].InsertText := 'nie';
  mItems.Items[0].HasTextEdit := True;
  mItems.Items[0].TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(1, 2),
    TTextPosition.Create(1, 6)), 'for X');
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.AreEqual('{"isIncomplete":true,"items":[{"label":"for","kind":15,"textEdit":{"range":{"start":' +
      '{"line":1,"character":2},"end":{"line":1,"character":6}},"newText":"for X"},"sortText":"00000"}]}',
      mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;
procedure TLspCompletionTests.ToJsonOmitsDataBelowGate;
var
  mItems: TCompletionItems;
  mJson: TJSONObject;
begin
  mItems := Default(TCompletionItems);
  SetLength(mItems.Items, 1);
  mItems.Items[0] := Default(TCompletionItem);
  mItems.Items[0].Name := 'Wert';
  mItems.Items[0].Kind := 5;
  mItems.Items[0].Container := 'TFoo';
  mItems.Items[0].Depth := 1;
  mItems.Items[0].IsHelper := True;
  mItems.Items[0].HasParameters := True;
  mItems.Items[0].UnitName := 'U';
  mItems.Items[0].Count := 2;
  mItems.Items[0].Unknown := 'X';
  mItems.Items[0].Batch := True;
  mItems.Items[0].ByType := True;
  mItems.Items[0].Unavailable := True;
  mItems.Items[0].SetOf := 'TKind';
  mItems.Items[0].Hides := ['Feld TKunde.Wert'];
  mItems.Items[0].Overloads := [TTextPosition.Create(7, 2)];
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.AreEqual('{"isIncomplete":false,"items":[{"label":"Wert","kind":5,"sortText":"00000"}]}', mJson.ToJSON);
  finally
    mJson.Free;
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
  mItems: TCompletionItems;
begin
  // Präfix-Treffer vor Teilfolgen; "me" passt als Präfix auf Melde, als Teilwort nicht weiter.
  mItems := ItemsAt(WithCode('  me'), '  me', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Melde', mItems.Items[0].Name, Names(mItems));
  // Ohne Eingabe bleibt die Reihenfolge der Gültigkeitsbereiche.
  Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo TBasis Rechne',
    Names(ItemsAt(WithCode('  '), #10'begin'#10'  ', TCompletionMatching.Fuzzy)));
end;
procedure TLspCompletionTests.FuzzySetsFilterTextAndIsIncomplete;
var
  mItems: TCompletionItems;
  mJson: TJSONObject;
begin
  // Vollständig (#616): Der Editor filtert beim Weitertippen selbst, statt bei jedem Zeichen neu zu fragen.
  mItems := ItemsAt(WithCode('  ehl'), '  ehl', TCompletionMatching.Fuzzy);
  Assert.IsFalse(mItems.Incomplete);
  Assert.AreEqual('ehl', mItems.Items[0].FilterText);
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.AreEqual('ehl', mJson.GetValue<string>('items[0].filterText'));
    Assert.IsTrue(mJson.GetValue('isIncomplete') is TJSONFalse);
  finally
    mJson.Free;
  end;
  // Präfix-Treffer brauchen keinen filterText.
  mItems := ItemsAt(WithCode('  We'), '  We', TCompletionMatching.Fuzzy);
  Assert.AreEqual('Wert', mItems.Items[0].Name);
  Assert.AreEqual('', mItems.Items[0].FilterText);
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
  mLib: TUnitIndex;
  mIndex: Integer;
  mItems: TCompletionItems;
begin
  // Mehr passende Importe als MaxImportItems: Beim Weitertippen können andere drankommen (#616).
  for mIndex := 1 to TLspCompletion.cMaxImportItems + 5 do
  begin
    mLib := TIndexExtractor.ExtractText(Format('unit Lib%d;'#10'interface'#10'type TTestLib%d = class end;'#10 +
      'implementation'#10'end.', [mIndex, mIndex]), Format('C:\Lib\Lib%d.pas', [mIndex]), nil);
    mLib.Library_ := True;
    FIndex.AddUnit(mLib);
  end;
  mItems := ItemsAt(WithCode('  TTest'), '  TTest', TCompletionMatching.Fuzzy);
  Assert.AreEqual(Integer(TLspCompletion.cMaxImportItems), Integer(Length(mItems.Items)));
  Assert.IsTrue(mItems.Incomplete);
end;
procedure TLspCompletionTests.NameFilterSkipsIndexSymbols;
var
  mTree: TSyntaxTree;
  mText, mFound: string;
  mSymbol: TResolvedSymbol;
begin
  // Der Filter gilt für Symbole aus dem Index (eigene Unit, uses, Mitglieder), nicht für lokale Namen (#616).
  mText := WithCode('  ');
  mTree := TPascalParser.Parse(mText);
  try
    FResolver.Candidates.NameFilter :=
      function(const AName: string): Boolean
      begin
        Result := AName.StartsWith('R', True) or AName.StartsWith('M', True);
      end;
    try
      mFound := '';
      for mSymbol in FResolver.Candidates.ScopeCandidates(mTree, cHauptFile,
        TCompletionContexts.Analyze(mTree, PositionOf(mText, #10'begin'#10'  ')).Offset) do
      begin
        mFound := mFound + mSymbol.Name + ' ';
      end;
    finally
      FResolver.Candidates.NameFilter := nil;
    end;
    Assert.AreEqual('Wert Anzahl Self Melde Rechne', mFound.Trim);
  finally
    mTree.Free;
  end;
end;
procedure TLspCompletionTests.StagedDeliversOwnScopeThenUsedUnits;
var
  mText: string;
  mTree: TSyntaxTree;
  mStages: TList<string>;
  mItems: TCompletionItems;
  mPostfix: TPostfixOptions;
  mPartial: TCompletionPartialProc;
begin
  mText := WithCode('  ');
  mTree := TPascalParser.Parse(mText);
  mStages := TList<string>.Create;
  try
    mPostfix := TPostfixOptions.Default;
    mPostfix.Enabled := False;
    mPartial :=
      procedure(const AItems: TArray<TCompletionItem>)
      var
        Part: TCompletionItems;
      begin
        Part.Items := AItems;
        mStages.Add(Names(Part));
      end;
    mItems := CollectAt(LookupOf(FResolver, FIndex, mTree, mText, nil), PositionOf(mText, #10'begin'#10'  '), mPostfix,
      mPartial);
    // Erst lokal, Self und eigene Unit, dann die Units aus uses; die Antwort bringt den (leeren) Rest.
    Assert.AreEqual(2, Integer(mStages.Count));
    Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo', mStages[0]);
    Assert.AreEqual('TBasis Rechne', mStages[1]);
    Assert.AreEqual('', Names(mItems));
    Assert.IsTrue(mItems.Incomplete, 'ohne Eingabe fehlen noch die Importe');
  finally
    mStages.Free;
    mTree.Free;
  end;
end;
procedure TLspCompletionTests.StagedKeepsImportsAfterUsedNames;
var
  mText: string;
  mTree: TSyntaxTree;
  mSent: string;
  mItems: TCompletionItems;
  mPostfix: TPostfixOptions;
  mPartial: TCompletionPartialProc;
begin
  // Gleichnamiges aus nicht eingebundenen Units kommt nicht doppelt als Import, auch wenn der eingebundene Name
  // schon in einem Teilergebnis stand; es steht einmal als Variante direkt hinter dem eingebundenen (#475).
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Rechne;'#10 +
    'procedure Rechenweg;'#10'implementation'#10'procedure Rechne; begin end;'#10 +
    'procedure Rechenweg; begin end;'#10'end.', 'C:\P\Extra.pas', nil));
  mText := WithCode('  Rech');
  mTree := TPascalParser.Parse(mText);
  try
    mPostfix := TPostfixOptions.Default;
    mPostfix.Enabled := False;
    mSent := '';
    mPartial :=
      procedure(const AItems: TArray<TCompletionItem>)
      var
        Part: TCompletionItems;
      begin
        Part.Items := AItems;
        mSent := mSent + Names(Part) + '|';
      end;
    mItems := CollectAt(LookupOf(FResolver, FIndex, mTree, mText, nil), PositionOf(mText, '  Rech'), mPostfix, mPartial);
    Assert.AreEqual('Rechne Rechne|', mSent);
    Assert.AreEqual('Rechenweg', Names(mItems));
    Assert.AreEqual('Extra (uses ergänzen)', mItems.Items[0].Detail);
  finally
    mTree.Free;
  end;
end;
procedure TLspCompletionTests.PartialJsonContinuesSortText;
var
  mItems: TArray<TCompletionItem>;
  mJson: TJSONArray;
begin
  SetLength(mItems, 1);
  mItems[0].Name := 'Wert';
  mItems[0].Kind := 6;
  mJson := TLspCompletion.ToJson(mItems, 12);
  try
    Assert.AreEqual('[{"label":"Wert","kind":6,"sortText":"00012"}]', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;
procedure TLspCompletionTests.PrefixModeKeepsStrictSelection;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt(WithCode('  zlr'), '  zlr', TCompletionMatching.Prefix);
  Assert.AreEqual('', Names(mItems));
  Assert.IsFalse(mItems.Incomplete);
end;
procedure TLspCompletionTests.OffersSymbolsOfUnusedUnitsWithUsesEdit;
var
  mBibliothek: TUnitIndex;
  mItems: TCompletionItems;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\P\Extra.pas', nil));
  mBibliothek := TIndexExtractor.ExtractText('unit Bib.Mathe;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'procedure Berechne; begin end;'#10'end.', 'C:\Bib\Bib.Mathe.pas', nil);
  mBibliothek.Library_ := True;
  FIndex.AddUnit(mBibliothek);
  mItems := ItemsAt(WithCode('  Ber'), '  Ber', TCompletionMatching.Fuzzy);
  // Projekt-Unit vor Bibliothek; eingetragen wird im implementation-Teil, der noch kein uses hat.
  Assert.AreEqual('Berechne Berechne', Names(mItems));
  Assert.AreEqual('Extra (uses ergänzen)', mItems.Items[0].Detail);
  Assert.AreEqual('Bib.Mathe (uses ergänzen)', mItems.Items[1].Detail);
  Assert.AreEqual(1, Integer(Length(mItems.Items[0].AdditionalEdits)));
  Assert.AreEqual(#13#10#13#10'uses'#13#10'  Extra;', mItems.Items[0].AdditionalEdits[0].NewText);
  Assert.AreEqual(8, mItems.Items[0].AdditionalEdits[0].Range.StartPos.Line);
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
  mLib: TUnitIndex;
  mIndex: Integer;
  mItems: TCompletionItems;
  mFound: Boolean;
  mItem: TCompletionItem;
begin
  // Mehr passende Bibliotheks-Symbole als die Höchstzahl: die eigene Unit fehlte sonst (#492).
  for mIndex := 1 to 250 do
  begin
    mLib := TIndexExtractor.ExtractText(Format('unit Lib%d;'#10'interface'#10'type TTestLib%d = class end;'#10 +
      'implementation'#10'end.', [mIndex, mIndex]), Format('C:\Lib\Lib%d.pas', [mIndex]), nil);
    mLib.Library_ := True;
    FIndex.AddUnit(mLib);
  end;
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Eigene;'#10'interface'#10'type TTestHier = class end;'#10 +
    'implementation'#10'end.', 'C:\P\Eigene.pas', nil));
  mItems := ItemsAt(WithCode('  TTest'), '  TTest', TCompletionMatching.Prefix);
  mFound := False;
  for mItem in mItems.Items do
  begin
    if mItem.Name = 'TTestHier' then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, 'Klasse aus dem Projekt trotz vieler Bibliotheks-Treffer');
end;
procedure TLspCompletionTests.ImportsKnowParameters;
var
  mItems: TCompletionItems;
begin
  // Import mit uses-Ergänzung: Parameter aus dem Index, damit das Plugin Klammern setzt.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Zeige(const S: string);'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  mItems := ItemsAt(WithCode('  Zeig'), '  Zeig', TCompletionMatching.Prefix);
  Assert.AreEqual('Zeige', mItems.Items[0].Name);
  Assert.AreEqual(1, Integer(Length(mItems.Items[0].AdditionalEdits)));
  Assert.IsTrue(mItems.Items[0].HasParameters);
  Assert.AreEqual('C:\P\Extra.pas', mItems.Items[0].SourceFile);
end;
procedure TLspCompletionTests.ItemsCarryTheirScope;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mScopes: string;
begin
  // #488: lokal 1, Parameter 2, Mitglied von Self 3, eigene Unit 4, andere Unit 5.
  mItems := ItemsAt(WithCode('  Ziel := '), 'Ziel := ', TCompletionMatching.Prefix);
  mScopes := '';
  for mItem in mItems.Items do
  begin
    if (mItem.Name = 'Wert') or (mItem.Name = 'Anzahl') or (mItem.Name = 'Name') or (mItem.Name = 'TFoo') or
      (mItem.Name = 'Rechne') then
    begin
      mScopes := mScopes + mItem.Name + '=' + IntToStr(mItem.Scope) + ';';
    end;
  end;
  Assert.Contains(mScopes, 'Wert=1;');
  Assert.Contains(mScopes, 'Anzahl=2;');
  Assert.Contains(mScopes, 'Name=3;');
  Assert.Contains(mScopes, 'TFoo=4;');
  Assert.Contains(mScopes, 'Rechne=5;');
end;
function FindItem(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(AItems.Items) do
  begin
    if SameText(AItems.Items[mIndex].Name, AName) then
    begin
      if Result = 0 then
      begin
        AItem := AItems.Items[mIndex];
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
  cText =
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
  mItems: TCompletionItems;
  mTotalAt, mCustomerAt, mDiscountAt: Integer;
begin
  // #488, Abnahme: ohne Präfix lokal vor Parameter vor Feld.
  mItems := ItemsAt(cText, 'Total := ');
  mTotalAt := IndexOfItem(mItems, 'Total');
  mCustomerAt := IndexOfItem(mItems, 'ACustomer');
  mDiscountAt := IndexOfItem(mItems, 'FDiscount');
  Assert.IsTrue(mTotalAt >= 0, Names(mItems));
  Assert.IsTrue(mTotalAt < mCustomerAt, Names(mItems));
  Assert.IsTrue(mCustomerAt < mDiscountAt, Names(mItems));
end;
procedure TLspCompletionTests.InlineVarBelowCaretIsNotOffered;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mText: string;
begin
  // #488: Inline-Variablen oberhalb des Carets ja, unterhalb nicht.
  mText := WithCode('  var Oben := 1;'#10'  Ziel := '#10'  var Unten := 2;');
  mItems := ItemsAt(mText, 'Ziel := ');
  Assert.AreEqual(1, FindItem(mItems, 'Oben', mItem), Names(mItems));
  Assert.AreEqual(1, mItem.Scope);
  Assert.AreEqual(0, FindItem(mItems, 'Unten', mItem), Names(mItems));
end;
procedure TLspCompletionTests.HiddenNamesAppearOnceWithHint;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mText: string;
  mJson: TJSONObject;
begin
  // #488, Abnahme: Ein lokaler Name verdeckt das Feld Name und die Routine Rechne aus Werkzeug; beide
  // erscheinen einmal als „lokal“, das Detailpanel nennt die verdeckte Deklaration.
  mText := StringReplace(WithCode('  Ziel := '), '  Wert: TFoo;', '  Wert: TFoo;'#10'  Name: string;'#10 +
    '  Rechne: Integer;', []);
  mItems := ItemsAt(mText, 'Ziel := ');
  Assert.AreEqual(1, FindItem(mItems, 'Name', mItem), Names(mItems));
  Assert.AreEqual(1, mItem.Scope);
  Assert.AreEqual<NativeInt>(1, Length(mItem.Hides));
  Assert.AreEqual('Feld TFoo.Name', mItem.Hides[0]);
  Assert.AreEqual(1, FindItem(mItems, 'Rechne', mItem), Names(mItems));
  Assert.AreEqual(1, mItem.Scope);
  Assert.AreEqual<NativeInt>(1, Length(mItem.Hides));
  Assert.AreEqual('Werkzeug.Rechne', mItem.Hides[0]);
  // Nicht verdeckt: keine Angabe; aus einer anderen Unit: deren Name für das Tag.
  Assert.AreEqual(1, FindItem(mItems, 'TBasis', mItem), Names(mItems));
  Assert.AreEqual<NativeInt>(0, Length(mItem.Hides));
  Assert.AreEqual(5, mItem.Scope);
  Assert.AreEqual('Werkzeug', mItem.UnitName);
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.Contains(mJson.ToJSON, '"hides":["Feld TFoo.Name"]');
    Assert.Contains(mJson.ToJSON, '"unit":"Werkzeug"');
  finally
    mJson.Free;
  end;
end;
procedure TLspCompletionTests.PlainItemsHaveNoTextEdit;
var
  mItems: TCompletionItems;
  mIndex: Integer;
begin
  // Regression: Add verwendete Scored wieder, ohne es zu leeren; HasTextEdit blieb mit
  // leerem Bereich stehen und das Plugin löschte alles vom Dateianfang bis zum Wort.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit Extra;'#10'interface'#10'procedure Berechne;'#10 +
    'implementation'#10'end.', 'C:\P\Extra.pas', nil));
  mItems := ItemsAt(WithCode('  B'), '  B', TCompletionMatching.Fuzzy);
  Assert.IsTrue(Length(mItems.Items) > 1);
  for mIndex := 0 to High(mItems.Items) do
  begin
    Assert.IsFalse(mItems.Items[mIndex].HasTextEdit, mItems.Items[mIndex].Name);
  end;
end;
procedure TLspCompletionTests.MembersCarryContainerDepthAndOverloads;
const
  cUnitUeber =
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
  cText =
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
  mItems: TCompletionItems;
  mJson: TJSONObject;
  mData: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitUeber, 'C:\P\Ueber.pas', nil));
  mItems := ItemsAt(cText, '  A.');
  Assert.AreEqual('Eigen Schreibe', Names(mItems));
  // Eigene Klasse: Tiefe 0; geerbt: Tiefe 1 mit deklarierender Klasse (#419).
  Assert.AreEqual('TAbleitung', mItems.Items[0].Container);
  Assert.AreEqual(0, mItems.Items[0].Depth);
  Assert.AreEqual('TGrund', mItems.Items[1].Container);
  Assert.AreEqual(1, mItems.Items[1].Depth);
  // Drei Überladungen: ein Eintrag mit zwei weiteren Positionen; Rümpfe zählen nicht (#425).
  Assert.AreEqual(2, Integer(Length(mItems.Items[1].Overloads)));
  Assert.AreEqual(0, Integer(Length(mItems.Items[0].Overloads)));
  // Klammern beim Übernehmen (#430): Eigen hat keine Parameter, Schreibe in zwei Überladungen.
  Assert.IsFalse(mItems.Items[0].HasParameters);
  Assert.IsTrue(mItems.Items[1].HasParameters);
  mJson := TLspCompletion.ToJson(mItems);
  try
    mData := ((mJson.GetValue('items') as TJSONArray).Items[1] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('TGrund', mData.GetValue<string>('container'));
    Assert.AreEqual(1, mData.GetValue<Integer>('depth'));
    Assert.IsTrue(mData.GetValue('parameters') is TJSONTrue);
    Assert.AreEqual(2, (mData.GetValue('overloads') as TJSONArray).Count);
    Assert.AreEqual(5, (mData.GetValue('overloads') as TJSONArray).Items[0].GetValue<Integer>('line'));
  finally
    mJson.Free;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TLspCompletionTests);

end.
