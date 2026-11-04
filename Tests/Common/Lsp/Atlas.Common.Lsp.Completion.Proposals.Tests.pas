unit Atlas.Common.Lsp.Completion.Proposals.Tests;

// Tests der Vervollständigung für Vorschläge, die Code erzeugen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Vorschläge, die Code erzeugen: Überschreiben, Ereignisse, case-Zweige, Felder, Deklarationen, Formularkomponenten.</summary>
  [TestFixture]
  TLspCompletionProposalTests = class(TLspCompletionTestCase)
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure OffersOverridesWithDeclarationAndBody;
    [Test]
    procedure OffersMatchingHandlersAndNewMethodForEvents;
    [Test]
    procedure OffersEnumValuesAndSetValues;
    [Test]
    procedure OffersMissingCaseBranches;
    /// <summary>Alle Felder zuweisen (#491).</summary>
    [Test]
    procedure AssignsAllFields;
    [Test]
    procedure AssignsManyFieldsThroughList;
    [Test]
    procedure OffersDeclarationsForUnknownNames;
    [Test]
    procedure OffersMissingInterfaceMethods;
    [Test]
    procedure OffersFormComponentsByNameAndType;
    /// <summary>#882: Formular-Komponenten auch über Kürzel und Teilwort, mit dem getippten Wort als filterText.</summary>
    [Test]
    procedure OffersFormComponentsFuzzyWithFilterText;
    /// <summary>#882: Anfang vor Kürzel vor Teilwort auch in der Punktzahl des Servers (Kürzen auf MaxItems).</summary>
    [Test]
    procedure MatchScoreRanksAbbreviationBeforeSubstring;
    [Test]
    procedure CastsSenderToAssignedComponents;
    [Test]
    procedure OffersDataFieldNames;
    [Test]
    procedure OffersTryFinallyAfterConstructor;
    [Test]
    procedure OffersGenericInterfaceMethods;
    [Test]
    procedure GroupsByExpectedType;
    /// <summary>Code-Review P-02: Collect mit vom Aufrufer gepinntem Baum liefert dasselbe.</summary>
    [Test]
    procedure CollectWithOuterPinSameItems;
    /// <summary>Code-Review P-07: Jede Vorfahren-Unit wird einmal gelesen, nicht je Kandidat.</summary>
    [Test]
    procedure OverrideItemsReadsEachFileOnce;
    /// <summary>Code-Review P-06: Außerhalb von Routinen wird das Formular gar nicht gelesen.</summary>
    [Test]
    procedure ComponentItemsOutsideRoutineDoesNotReadForm;
    /// <summary>Code-Review P-06: Die zweite Anfrage nutzt den Auszug der Formulardatei; nach einer Änderung
    /// der Datei wird neu gelesen.</summary>
    [Test]
    procedure ComponentItemsSecondRequestUsesCache;
    /// <summary>Code-Review P-11: Kopf der Methode aus dem Baum, auch weiter oben als die Zeilensuche reichte,
    /// und nicht der einer lokalen Prozedur.</summary>
    [Test]
    procedure SenderItemsFindsHeaderFarAboveAndSkipsLocalRoutines;
    /// <summary>Code-Review P-12: Eingebaute Typen werden nicht im Index gesucht (kein gleichnamiger Fremdtyp).</summary>
    [Test]
    procedure BuiltinTypeNotShadowedByIndexEnum;
    /// <summary>#456: Helper aus nicht eingebundenen Units nach den eigenen Mitgliedern, mit Kennzeichen und
    /// uses-Eintrag; eingebunden ohne uses-Eintrag.</summary>
    [Test]
    procedure HelpersFromOtherUnitsBringTheirUses;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.AssignFields,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Lsp.CompletionCollector;

procedure TLspCompletionProposalTests.WarmUpFirstUse;
begin
  Setup;
  try
    ComponentItemsSecondRequestUsesCache;
  finally
    TearDown;
  end;
end;
procedure TLspCompletionProposalTests.Setup;
begin
  Prepare;
end;
procedure TLspCompletionProposalTests.TearDown;
begin
  Release;
end;
procedure TLspCompletionProposalTests.HelpersFromOtherUnitsBringTheirUses;
const
  UnitHilfen = 'unit Hilfen;'#10'interface'#10'uses Werkzeug;'#10'type'#10 +
    '  TBasisHelper = class helper for TBasis'#10'  public'#10'    procedure Hilfe;'#10'  end;'#10 +
    '  TTextHelper = record helper for string'#10'  public'#10'    function Laenge: Integer;'#10 +
    '  private'#10'    procedure Intern;'#10'  end;'#10'implementation'#10'end.';
var
  Text: string;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Found: Boolean;
  Details: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHilfen, 'C:\P\Hilfen.pas', nil));
  // Detailpanel: „TTextHelper · Hilfen“ (Zeile 10: function Laenge).
  Details := TLspCompletion.Details(FIndex, 'C:\P\Hilfen.pas', UnitHilfen, TTextPosition.Create(10, 13));
  try
    Assert.AreEqual('TTextHelper', Details.GetValue<string>('container'));
    // TJSONBool.Create(True) ist kein TJSONTrue; erst der Parser erzeugt diese Klasse.
    Assert.IsTrue((Details.GetValue('helper') is TJSONBool) and TJSONBool(Details.GetValue('helper')).AsBoolean,
      Details.ToJSON);
  finally
    Details.Free;
  end;
  Text := WithCode('  Wert.');
  Items := ItemsAt(Text, 'Wert.');
  // Eigene und geerbte Mitglieder zuerst, der Helper des Vorfahren dahinter.
  Assert.AreEqual('Name Bar Zaehler Melde Hilfe', Names(Items));
  Found := False;
  for Item in Items.Items do
  begin
    if Item.Name = 'Hilfe' then
    begin
      Found := True;
      Assert.IsTrue(Item.IsHelper);
      Assert.AreEqual(1, Item.Depth);
      Assert.AreEqual('Hilfen (uses ergänzen)', Item.Detail);
      Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
      // Verwendung im implementation-Teil: dort ein neuer uses-Abschnitt.
      Assert.IsTrue(Item.AdditionalEdits[0].NewText.Contains('Hilfen'), Item.AdditionalEdits[0].NewText);
    end;
  end;
  Assert.IsTrue(Found);
  // Eingebauter Typ: nur die öffentlichen Helper-Mitglieder.
  Assert.AreEqual('Laenge', Names(ItemsAt(WithCode('  Wert.Name.'), 'Wert.Name.')));
  // Eingebunden: aktiver Helper ohne uses-Eintrag.
  Text := StringReplace(WithCode('  Wert.'), 'uses Werkzeug;', 'uses Werkzeug, Hilfen;', []);
  for Item in ItemsAt(Text, 'Wert.').Items do
  begin
    if Item.Name = 'Hilfe' then
    begin
      Assert.IsTrue(Item.IsHelper);
      Assert.AreEqual(0, Integer(Length(Item.AdditionalEdits)));
    end;
  end;
end;
procedure TLspCompletionProposalTests.OffersOverridesWithDeclarationAndBody;
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

const
  cEventsUnitBasis =
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
  cEventsText =
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

procedure TLspCompletionProposalTests.OffersMatchingHandlersAndNewMethodForEvents;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Handlers, Edits: string;
  Edit: TRuleEdit;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cEventsUnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(cEventsText);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.EventItems(Resolver, Tree, cEventsText, HauptFile, PositionOf(cEventsText,
      'btnSave.OnClick := '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cEventsUnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end, Items));
    // Nur Methoden mit (Sender: TObject); Fertig hat zwei Parameter.
    Handlers := '';
    for Item in Items.Items do
    begin
      if Item.Action = '' then
      begin
        Handlers := Handlers + ' ' + Item.Name;
        Assert.AreEqual('TNotifyEvent', Item.Expected);
        Assert.IsTrue(Item.Fits);
      end;
    end;
    Assert.AreEqual(' FormCreate btnSaveClick', Handlers);
    // Zuletzt die neue Methode; btnSaveClick ist vergeben.
    Item := Items.Items[High(Items.Items)];
    Assert.AreEqual('create', Item.Action);
    Assert.AreEqual('Neue Methode btnSaveClick2 …', Item.Name);
    Assert.AreEqual('btnSaveClick2', Item.InsertText);
    Edits := '';
    for Edit in Item.AdditionalEdits do
    begin
      Edits := Edits + Edit.NewText + '|';
    end;
    Assert.AreEqual(2, Integer(Length(Item.AdditionalEdits)), Edits);
    Assert.IsTrue(Edits.Contains('private'#13#10'    procedure btnSaveClick2(Sender: TObject);'), Edits);
    Assert.IsTrue(Edits.Contains('procedure TForm1.btnSaveClick2(Sender: TObject);'#13#10'begin'#13#10#13#10'end;'),
      Edits);
    // Keine Ereignis-Zuweisung: normale Vervollständigung.
    Assert.IsFalse(TLspCompletion.EventItems(Resolver, Tree, cEventsText, HauptFile, PositionOf(cEventsText,
      'uses Ba'), nil, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

const
  cGenericUnitListen =
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
  cGenericText =
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

procedure TLspCompletionProposalTests.OffersGenericInterfaceMethods;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  List: TCompletionItems;
  Edits, Merged: TArray<TRuleEdit>;
  Item: TCompletionItem;
  Batch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cGenericUnitListen, 'C:\P\Listen.pas', nil));
  Tree := TPascalParser.Parse(cGenericText);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, cGenericText, HauptFile, TTextPosition.Create(8, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cGenericUnitListen;
        Result := SameText(AFileName, 'C:\P\Listen.pas');
      end, TCompletionInterfaceSection.Public, Items, Batch));
    List.Items := Items;
    Assert.AreEqual('Add Items', Names(List));
    Assert.AreEqual('IListe<TKunde>', Items[0].Container);
    Assert.Contains(Items[0].Detail, 'procedure Add(const AItem: TKunde)');
    Assert.Contains(Items[1].Detail, 'function Items: TArray<TKunde>');
    Edits := nil;
    for Item in Items do
    begin
      Edits := Edits + Item.AdditionalEdits;
    end;
    Merged := TInterfaceStubs.Merge(Edits);
    Assert.IsTrue(Merged[0].NewText.Contains('{ IListe<TKunde> }'), Merged[0].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains('procedure TKundenListe.Add(const AItem: TKunde);'), Merged[1].NewText);
    Assert.IsTrue(Merged[1].NewText.Contains('Result := Default(TArray<TKunde>);'), Merged[1].NewText);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

const
  cMissingUnitBasis =
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
  cMissingText =
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
  cMissingTyped =
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

/// <summary>Alle angehakt: ein neuer public-Abschnitt vor dem end, je Interface mit Kommentar; Rümpfe in die
/// implementation.</summary>
procedure AssertMergedInterfaceStubs(const AItems: TArray<TCompletionItem>);
var
  mEdits, mMerged: TArray<TRuleEdit>;
  mItem: TCompletionItem;
begin
  // Alle angehakt: ein neuer public-Abschnitt vor dem end, je Interface mit Kommentar; Rümpfe in die implementation.
  mEdits := nil;
  for mItem in AItems do
  begin
    mEdits := mEdits + mItem.AdditionalEdits;
  end;
  mMerged := TInterfaceStubs.Merge(mEdits);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.AreEqual(8, mMerged[0].Range.StartPos.Line);
  Assert.AreEqual(
    '  public'#13#10 +
    '    { IExporter }'#13#10 +
    '    procedure Export(const AFileName: string);'#13#10 +
    '    function GetName: string;'#13#10 +
    '    { IFlush }'#13#10 +
    '    procedure Flush;'#13#10, mMerged[0].NewText);
  Assert.IsTrue(mMerged[1].NewText.Contains(
    'function TJsonExporter.GetName: string;'#13#10'begin'#13#10'  Result := Default(string);'#13#10'end;'),
    mMerged[1].NewText);
  Assert.IsTrue(mMerged[1].NewText.Contains('procedure TJsonExporter.Flush;'#13#10'begin'#13#10#13#10'end;'),
    mMerged[1].NewText);
  Assert.IsFalse(mMerged[1].NewText.Contains('inherited'), mMerged[1].NewText);
end;
/// <summary>Angefangenes Wort: je Interface ein Hinweis, der seine Methoden anlegt und das Wort entfernt.</summary>
procedure AssertTypedInterfaceHints(AResolver: TNameResolver; ATree: TSyntaxTree);
var
  mItems: TArray<TCompletionItem>;
  mBatch: Boolean;
begin
  Assert.IsTrue(TLspCompletion.InterfaceItems(AResolver, ATree, cMissingTyped, HauptFile, TTextPosition.Create(7, 6),
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cMissingUnitBasis;
      Result := True;
    end, TCompletionInterfaceSection.Public, mItems, mBatch));
  Assert.IsFalse(mBatch);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('2 Methoden von IExporter fehlen', mItems[0].Name);
  Assert.AreEqual('1 Methode von IFlush fehlt', mItems[1].Name);
  Assert.IsTrue(mItems[0].Hint and mItems[0].HasTextEdit);
  Assert.AreEqual('', mItems[0].TextEdit.NewText);
  Assert.AreEqual(4, mItems[0].TextEdit.Range.StartPos.Character);
  Assert.IsTrue(mItems[0].AdditionalEdits[0].NewText.Contains('function GetName: string;'));
  Assert.IsFalse(mItems[0].AdditionalEdits[0].NewText.Contains('Flush'));
end;
procedure TLspCompletionProposalTests.OffersMissingInterfaceMethods;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  List: TCompletionItems;
  Batch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cMissingUnitBasis, 'C:\P\Basis.pas', nil));
  Tree := TPascalParser.Parse(cMissingText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Strg+Leer auf der leeren Zeile: Liste mit Kontrollkästchen. SetName erbt die Klasse von TBasis.
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, cMissingText, HauptFile, TTextPosition.Create(7, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cMissingUnitBasis;
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
    AssertMergedInterfaceStubs(Items);
    // Abschnitt nach Einstellung: private steht schon als letzter da, also kein neuer.
    Assert.IsTrue(TLspCompletion.InterfaceItems(Resolver, Tree, cMissingText, HauptFile, TTextPosition.Create(7, 4),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cMissingUnitBasis;
        Result := True;
      end, TCompletionInterfaceSection.Private, Items, Batch));
    Assert.AreEqual('    { IExporter }'#13#10, Items[0].AdditionalEdits[0].NewText);
    // Außerhalb der Klasse nichts.
    Assert.IsFalse(TLspCompletion.InterfaceItems(Resolver, Tree, cMissingText, HauptFile, TTextPosition.Create(2, 0),
      nil,
      TCompletionInterfaceSection.Public, Items, Batch));
  finally
    Tree.Free;
  end;
  // Angefangenes Wort: je Interface ein Hinweis, der seine Methoden anlegt und das Wort entfernt.
  Tree := TPascalParser.Parse(cMissingTyped);
  try
    AssertTypedInterfaceHints(Resolver, Tree);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;
procedure TLspCompletionProposalTests.OffersFormComponentsByNameAndType;
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
      begin
        Result := Result + '*';
      end;
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
procedure TLspCompletionProposalTests.OffersFormComponentsFuzzyWithFilterText;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  end;'#13#10 +
    '  TButton = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  FormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '  end'#13#10 +
    '  object SaveButton: TButton'#13#10 +
    '  end'#13#10 +
    'end';
  Source =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    SaveButton: TButton;'#13#10 +
    '    procedure FormCreate(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  %s'#13#10 +
    'end;'#13#10 +
    'end.';

  function Components(const ATyped: string): TArray<TCompletionItem>;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
  begin
    Text := Format(Source, [ATyped]);
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      TLspCompletion.ComponentItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(13, 2 + Length(ATyped)),
        function(const AFileName: string; out AText: string): Boolean
        begin
          AText := FormText;
          Result := SameText(ExtractFileExt(AFileName), '.dfm');
        end, TCompletionMatching.Fuzzy, Result);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

  function Find(const AItems: TArray<TCompletionItem>; const AName: string; out AItem: TCompletionItem): Boolean;
  var
    Item: TCompletionItem;
  begin
    for Item in AItems do
    begin
      if Item.Name = AName then
      begin
        AItem := Item;
        Exit(True);
      end;
    end;
    AItem := Default(TCompletionItem);
    Result := False;
  end;

var
  Items: TArray<TCompletionItem>;
  Item: TCompletionItem;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSteuer, 'C:\P\Steuer.pas', nil));
  // Kürzel über Wortanfänge: "SB" → SaveButton, "bs" → btnSave.
  Items := Components('SB');
  Assert.IsTrue(Find(Items, 'SaveButton', Item), 'SB → SaveButton');
  Assert.IsFalse(Item.ByType);
  Assert.AreEqual('SB', Item.FilterText);
  Items := Components('bs');
  Assert.IsTrue(Find(Items, 'btnSave', Item), 'bs → btnSave');
  Assert.AreEqual('bs', Item.FilterText);
  // Teilwort: "Button" mitten im Namen.
  Items := Components('Button');
  Assert.IsTrue(Find(Items, 'SaveButton', Item), 'Button → SaveButton');
  Assert.AreEqual('Button', Item.FilterText);
  // Passender Anfang braucht keinen filterText.
  Items := Components('btn');
  Assert.IsTrue(Find(Items, 'btnSave', Item));
  Assert.AreEqual('', Item.FilterText);
  Items := nil;
  Item := Default(TCompletionItem);
end;
procedure TLspCompletionProposalTests.MatchScoreRanksAbbreviationBeforeSubstring;
var
  Prefix, Abbreviation, Substring, WordSubstring: Integer;
begin
  Prefix := MatchScore('SbList', 'sb', TCompletionMatching.Fuzzy);
  Abbreviation := MatchScore('SaveButton', 'sb', TCompletionMatching.Fuzzy);
  Substring := MatchScore('Ausbau', 'sb', TCompletionMatching.Fuzzy);
  WordSubstring := MatchScore('lstSbox', 'sb', TCompletionMatching.Fuzzy);
  Assert.AreNotEqual(Integer(TFuzzyMatch.NoMatch), Abbreviation);
  Assert.IsTrue(Prefix > Abbreviation, Format('Anfang %d vor Kürzel %d', [Prefix, Abbreviation]));
  Assert.IsTrue(Abbreviation > Substring, Format('Kürzel %d vor Teilwort %d', [Abbreviation, Substring]));
  Assert.IsTrue(Abbreviation > WordSubstring,
    Format('Kürzel %d vor Teilwort am Wortanfang %d', [Abbreviation, WordSubstring]));
  // Mit completion.matching = prefix bleibt es beim Anfang.
  Assert.AreEqual(Integer(TFuzzyMatch.NoMatch), MatchScore('SaveButton', 'sb', TCompletionMatching.Prefix));
end;

const
  cSenderUnitSteuer =
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
  cSenderFormText =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  // Zeile 14: "  Sender.Cap" in btnAnyClick, Zeile 18: "  Sender." in Frei (keinem Ereignis zugewiesen).
  cSenderText =
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

procedure TLspCompletionProposalTests.CastsSenderToAssignedComponents;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  ReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cSenderUnitSteuer, 'C:\P\Steuer.pas', nil));
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cSenderFormText;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  Tree := TPascalParser.Parse(cSenderText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // btnSave (TButton) und btnLoad (TBitBtn): gemeinsamer Vorfahr TButton.
    Assert.IsTrue(TLspCompletion.SenderItems(Resolver, FIndex, Tree, cSenderText, HauptFile, TTextPosition.Create(14,
      12),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.AsOperator, Items));
    Assert.AreEqual('Caption', Names(Items));
    Assert.AreEqual('TButton', Items.Items[0].Sender);
    Assert.AreEqual('btnSave, btnLoad', Items.Items[0].SenderOf);
    Assert.IsTrue(Items.Items[0].HasTextEdit);
    Assert.AreEqual('(Sender as TButton).Caption', Items.Items[0].TextEdit.NewText);
    Assert.AreEqual(2, Items.Items[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(12, Items.Items[0].TextEdit.Range.EndPos.Character);
    Assert.IsTrue(TLspCompletion.SenderItems(Resolver, FIndex, Tree, cSenderText, HauptFile, TTextPosition.Create(14,
      12),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.HardCast, Items));
    Assert.AreEqual('TButton(Sender).Caption', Items.Items[0].TextEdit.NewText);
    // Ohne Zuweisung im Formular bleibt es bei den Mitgliedern von TObject.
    Assert.IsFalse(TLspCompletion.SenderItems(Resolver, FIndex, Tree, cSenderText, HauptFile, TTextPosition.Create(18,
      9),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.AsOperator, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

const
  cUnknownText =
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

procedure TLspCompletionProposalTests.OffersDeclarationsForUnknownNames;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  Known: TArray<TCompletionItem>;

  function Named(const AName: string): TCompletionItem;
  var
    Item: TCompletionItem;
  begin
    for Item in Items do
    begin
      if Item.Name = AName then
      begin
        Exit(Item);
      end;
    end;
    raise Exception.CreateFmt('Eintrag "%s" fehlt', [AName]);
  end;

var
  Item: TCompletionItem;
begin
  Tree := TPascalParser.Parse(cUnknownText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Ziel einer Zuweisung: Typ aus der rechten Seite.
    Assert.IsTrue(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, cUnknownText, HauptFile,
      PositionOf(cUnknownText, '  TotalCount'), True, nil, Items));
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
    begin
      Assert.AreNotEqual('Konstante anlegen', Item.Name);
    end;
    // Als Argument: Typ des Parameters, auch als Konstante in der implementation.
    Assert.IsTrue(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, cUnknownText, HauptFile,
      PositionOf(cUnknownText, 'Zeige(Anzahl'), False, nil, Items));
    Assert.AreEqual('Anzahl: Integer', Named('Lokale Variable anlegen').Detail);
    Item := Named('Konstante anlegen');
    Assert.AreEqual('Anzahl = 0;', Item.Detail);
    Assert.AreEqual(12, Item.AdditionalEdits[0].Range.StartPos.Line);
    // Bekannte Namen und genaue Treffer: nichts.
    Assert.IsFalse(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, cUnknownText, HauptFile,
      PositionOf(cUnknownText, 'Zeige(Anzahl);'#13#10'  FLines'), True, nil, Items));
    // Eigene Variable für die bekannten Einträge: Ein out-Parameter leert sein Ziel vor dem Aufruf.
    SetLength(Known, 1);
    Known[0] := Default(TCompletionItem);
    Known[0].Name := 'Anzahl';
    Assert.IsFalse(TLspCompletion.DeclareItems(Resolver, FIndex, Tree, cUnknownText, HauptFile,
      PositionOf(cUnknownText, 'Zeige(Anzahl'), True, Known, Items));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

const
  cCaseText =
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

procedure TLspCompletionProposalTests.OffersMissingCaseBranches;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  SetMode: Boolean;
  Position: TTextPosition;
begin
  Tree := TPascalParser.Parse(cCaseText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Ohne Zweige: „Alle Werte einfügen“ zuerst, mit Anzahl; alle vier Zweige und das fehlende end.
    Position := PositionOf(cCaseText, 'case S.Kind of'#13#10'    ');
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, cCaseText, HauptFile, Position, nil,
      TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('Alle Werte einfügen', Items[0].Name);
    Assert.IsTrue(Items[0].Pinned);
    Assert.AreEqual(4, Integer(Items[0].Count));
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
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, cCaseText, HauptFile,
      PositionOf(cCaseText, 'skCircle: Zeichne;'#13#10'    sk'), nil, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('Fehlende Werte ergänzen (3)', Items[0].Name);
    Assert.AreEqual(0, Integer(Items[0].Count));
    Assert.AreEqual(#13#10'    skLine: $0;'#13#10'    skRect: ;'#13#10'    skTriangle: ;', Items[0].TextEdit.NewText);
    // Bereiche und Listen zählen als vorhanden: nichts mehr zu ergänzen.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, cCaseText, HauptFile,
      PositionOf(cCaseText, 'skTriangle: ;'#13#10'    '), nil, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.AreEqual('skCircle', Items[0].Name);
    Assert.IsFalse(Items[0].Pinned);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

const
  AssignText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TKind = (kA, kB);'#13#10 +
    '  TKinds = set of TKind;'#13#10 +
    '  TOpts = record'#13#10 +
    '    Header: string;'#13#10 +
    '    Count: Integer;'#13#10 +
    '    Kind: TKind;'#13#10 +
    '  end;'#13#10 +
    '  TBase = class'#13#10 +
    '  private'#13#10 +
    '    FName: string;'#13#10 +
    '    function GetSize: Integer;'#13#10 +
    '  protected'#13#10 +
    '    property Hidden: string read FName write FName;'#13#10 +
    '  public'#13#10 +
    '    Tag: Integer;'#13#10 +
    '    property Name: string read FName write FName;'#13#10 +
    '    property Size: Integer read GetSize;'#13#10 +
    '  end;'#13#10 +
    '  TChild = class(TBase)'#13#10 +
    '  public'#13#10 +
    '    Owner: TBase;'#13#10 +
    '    Flags: TKinds;'#13#10 +
    '    property Hidden;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function TBase.GetSize: Integer;'#13#10 +
    'begin'#13#10 +
    '  Result := 0;'#13#10 +
    'end;'#13#10 +
    'procedure P(Opts: TOpts; C: TChild);'#13#10 +
    'var'#13#10 +
    '  X: TOpts;'#13#10 +
    'begin'#13#10 +
    '  Opts.'#13#10 +
    '  Opts.Header := ''x'';'#13#10 +
    '  if True then'#13#10 +
    '    C.'#13#10 +
    '  X := Opts.'#13#10 +
    '  TOpts.'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TLspCompletionProposalTests.AssignsAllFields;
var
  Item: TCompletionItem;
  Text: string;
begin
  // Abnahme: drei Felder mit Platzhaltern; steht Opts.Header schon in der nächsten Zeile, nur zwei.
  Text := StringReplace(AssignText, '  Opts.Header := ''x'';'#13#10, '', []);
  Assert.IsTrue(AssignItem(Text, #10'  Opts.', True, True, Item));
  Assert.AreEqual('Alle Felder zuweisen (3)', Item.Name);
  Assert.IsTrue(Item.Pinned);
  Assert.IsTrue(Item.Snippet);
  Assert.AreEqual('Opts.Header := ${1:''''};'#10'Opts.Count := ${2:0};'#10'Opts.Kind := ${3:kA};',
    Item.TextEdit.NewText);
  Assert.AreEqual(2, Item.TextEdit.Range.StartPos.Character, 'ab dem Anfang des Ausdrucks');
  Assert.AreEqual(7, Item.TextEdit.Range.EndPos.Character);
  Assert.IsTrue(AssignItem(AssignText, #10'  Opts.', True, True, Item));
  Assert.AreEqual('Alle Felder zuweisen (2)', Item.Name);
  Assert.AreEqual('Opts.Count := ${1:0};'#10'Opts.Kind := ${2:kA};', Item.TextEdit.NewText);
  // Ohne Platzhalter: Klartext mit der Einrückung der Zeile.
  Assert.IsTrue(AssignItem(AssignText, #10'  Opts.', False, True, Item));
  Assert.IsFalse(Item.Snippet);
  Assert.AreEqual('Opts.Count := 0;'#13#10'  Opts.Kind := kA;', Item.TextEdit.NewText);
  // Klasse: Vorfahren zuerst; geschützte Property, die der Nachfahr öffentlich macht, ja; nur lesbare und
  // private nicht.
  Assert.IsTrue(AssignItem(AssignText, #10'    C.', False, True, Item));
  Assert.AreEqual('C.Hidden := '''';'#13#10'    C.Tag := 0;'#13#10'    C.Name := '''';'#13#10 +
    '    C.Owner := nil;'#13#10'    C.Flags := [];', Item.TextEdit.NewText);
  // Nicht am Anweisungsanfang, nach einem Typ und abgeschaltet: nichts.
  Assert.IsFalse(AssignItem(AssignText, 'X := Opts.', True, True, Item), 'Zuweisung');
  Assert.IsFalse(AssignItem(AssignText, '  TOpts.', True, True, Item), 'Typ');
  Assert.IsFalse(AssignItem(AssignText, #10'  Opts.', True, False, Item), 'abgeschaltet');
  Item := Default(TCompletionItem);
end;
procedure TLspCompletionProposalTests.AssignsManyFieldsThroughList;
var
  Item: TCompletionItem;
  Text, Fields: string;
  Index: Integer;
  Json: TJSONArray;
  Data, Line: TJSONObject;
begin
  // Mehr als 15 Felder: erst die Liste mit Kontrollkästchen, je Zeile samt Umbruch für die nächste.
  Fields := '';
  for Index := 0 to TAssignFields.ListThreshold do
  begin
    Fields := Fields + '    F' + IntToStr(Index) + ': Integer;'#13#10;
  end;
  Text := StringReplace(AssignText, '    Header: string;'#13#10, Fields, []);
  Text := StringReplace(Text, '  Opts.Header := ''x'';'#13#10, '', []);
  Assert.IsTrue(AssignItem(Text, #10'  Opts.', True, True, Item));
  Assert.AreEqual('Alle Felder zuweisen (18)', Item.Name);
  Assert.IsFalse(Item.Snippet);
  Assert.AreEqual('Opts.', Item.TextEdit.NewText, 'Text bleibt bis zur Auswahl');
  Assert.AreEqual(18, Integer(Length(Item.Assignments)));
  Assert.AreEqual('F0', Item.Assignments[0].Name);
  Assert.AreEqual('Integer', Item.Assignments[0].Detail);
  Assert.AreEqual('Opts.F0 := 0;'#13#10'  ', Item.Assignments[0].Text);
  Assert.AreEqual('Opts.Kind := kA;'#13#10'  ', Item.Assignments[17].Text);
  // Im JSON unter data.assign.
  Json := TLspCompletion.ToJson([Item], 0);
  try
    Data := TJSONObject(Json.Items[0]).GetValue('data') as TJSONObject;
    Assert.AreEqual('assign', Data.GetValue<string>('action'));
    Line := (Data.GetValue('assign') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('F0', Line.GetValue<string>('name'));
    Assert.AreEqual('Integer', Line.GetValue<string>('detail'));
    Assert.AreEqual('Opts.F0 := 0;'#13#10'  ', Line.GetValue<string>('text'));
  finally
    Json.Free;
  end;
  Item := Default(TCompletionItem);
end;

const
  cEnumTypenFile = 'C:\P\Typen.pas';
  cEnumUnitTypen =
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
  cEnumText =
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

/// <summary>Namen der Einträge, durch Leerzeichen getrennt.</summary>
function JoinedItemNames(const AItems: TArray<TCompletionItem>): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems do
  begin
    Result := Result + ' ' + mItem.Name;
  end;
  Result := Result.Trim;
end;
/// <summary>Liest nur die Unit Typen.</summary>
function TypenReader: TCompletionReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cEnumUnitTypen;
      Result := SameText(AFileName, cEnumTypenFile);
    end;
end;
/// <summary>Scoped Enum: Typpräfix beim Einfügen; case-Zweig mit den fehlenden Werten.</summary>
procedure AssertScopedEnumAndCase(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AReader: TCompletionReadText);
var
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
begin
  // Vergleich mit Scoped Enum: Typpräfix beim Einfügen, gefiltert nach dem Getippten.
  Assert.IsTrue(TLspCompletion.EnumItems(AResolver, AIndex, ATree, cEnumText, HauptFile, PositionOf(cEnumText,
    'C.Kind = sk'),
    AReader, TCompletionMatching.Fuzzy, mItems, mSetMode));
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.AreEqual('TShapeKind.skCircle', mItems[0].InsertText);
  // case-Zweig.
  Assert.IsTrue(TLspCompletion.EnumItems(AResolver, AIndex, ATree, cEnumText, HauptFile,
    PositionOf(cEnumText, 'skCircle: ;'#13#10'    '), AReader, TCompletionMatching.Fuzzy, mItems, mSetMode));
  Assert.AreEqual('Fehlende Werte ergänzen (3) skCircle skRect skLine skTriangle', JoinedItemNames(mItems));
  Assert.AreEqual(#13#10'    TShapeKind.skRect: $0;'#13#10'    TShapeKind.skLine: ;'#13#10'    TShapeKind.skTriangle: ;',
    mItems[0].TextEdit.NewText, 'Scoped Enum mit Typpräfix (#449)');
end;
/// <summary>Menge: alle Werte des Elementtyps, akLeft angehakt; bei in der Elementtyp aus der linken Seite.</summary>
procedure AssertEnumSetItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AReader: TCompletionReadText);
var
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
begin
  // Menge: alle Werte des Elementtyps, akLeft angehakt, Enter ersetzt die ganze Klammer.
  Assert.IsTrue(TLspCompletion.EnumItems(AResolver, AIndex, ATree, cEnumText, HauptFile,
    PositionOf(cEnumText, 'C.Anchors := [akLeft, '), AReader, TCompletionMatching.Fuzzy, mItems, mSetMode));
  Assert.IsTrue(mSetMode);
  Assert.AreEqual('akLeft akTop akRight akBottom', JoinedItemNames(mItems));
  Assert.IsTrue(mItems[0].SetChecked);
  Assert.IsFalse(mItems[1].SetChecked);
  Assert.AreEqual('TAnchorKind', mItems[0].SetOf);
  Assert.AreEqual('TAnchors', mItems[0].Expected);
  Assert.AreEqual(12, mItems[0].SetRange.StartPos.Line);
  Assert.AreEqual(15, mItems[0].SetRange.StartPos.Character);
  Assert.AreEqual(25, mItems[0].SetRange.EndPos.Character);
  // "in": Elementtyp aus der linken Seite.
  Assert.IsTrue(TLspCompletion.EnumItems(AResolver, AIndex, ATree, cEnumText, HauptFile, PositionOf(cEnumText,
    'C.Kind in ['),
    AReader, TCompletionMatching.Fuzzy, mItems, mSetMode));
  Assert.IsTrue(mSetMode);
  Assert.AreEqual('set of TShapeKind', mItems[0].Expected);
  Assert.AreEqual('TShapeKind.skCircle', mItems[0].InsertText);
end;
procedure TLspCompletionProposalTests.OffersEnumValuesAndSetValues;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  SetMode: Boolean;
  Reader: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cEnumUnitTypen, cEnumTypenFile, nil));
  Reader := TypenReader();
  Tree := TPascalParser.Parse(cEnumText);
  Resolver := TNameResolver.Create(FIndex);
  try
    // Zuweisung: Werte in Deklarationsreihenfolge, auch über mehrere Zeilen.
    Assert.IsTrue(TLspCompletion.EnumItems(Resolver, FIndex, Tree, cEnumText, HauptFile, PositionOf(cEnumText,
      'C.Align := '),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsFalse(SetMode);
    Assert.AreEqual('alNone alTop alClient', JoinedItemNames(Items));
    Assert.AreEqual(3, Items[2].Ordinal);
    Assert.AreEqual('TAlign', Items[0].Expected);
    Assert.IsTrue(Items[0].Fits);
    Assert.AreEqual('', Items[0].InsertText);
    Assert.AreEqual(cEnumTypenFile, Items[0].SourceFile, 'Position für completionItem/resolve');
    AssertScopedEnumAndCase(Resolver, FIndex, Tree, Reader);
    AssertEnumSetItems(Resolver, FIndex, Tree, Reader);
    // Index statt Menge.
    Assert.IsFalse(TLspCompletion.EnumItems(Resolver, FIndex, Tree, cEnumText, HauptFile, PositionOf(cEnumText,
      ':= List['),
      Reader, TCompletionMatching.Fuzzy, Items, SetMode));
    Assert.IsFalse(SetMode);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;
procedure TLspCompletionProposalTests.GroupsByExpectedType;

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
        begin
          Fitting := False;
        end;
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
procedure TLspCompletionProposalTests.OffersDataFieldNames;
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
procedure TLspCompletionProposalTests.OffersTryFinallyAfterConstructor;
const
  UnitTeile =
    'unit Teile;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TComponent = class'#13#10 +
    '  end;'#13#10 +
    '  TTimer = class(TComponent)'#13#10 +
    '  end;'#13#10 +
    '  TPunkt = record'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  /// <summary>Anweisung in Zeile 8, ARest danach.</summary>
  function Guards(const AVar, AStatement, ARest: string; AStyle: TCompletionFreeStyle;
    out AItems: TCompletionItems): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
  begin
    Text := 'unit Haupt;'#13#10'interface'#13#10'implementation'#13#10'uses Teile;'#13#10 +
      'procedure Laden;'#13#10'var'#13#10'  ' + AVar + #13#10'begin'#13#10'  ' + AStatement + #13#10 + ARest +
      'end;'#13#10'end.';
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := TLspCompletion.GuardItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(8,
        2 + Length(AStatement)), AStyle, False, AItems);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

  /// <summary>Wie Guards, aber nach Enter am Zeilenende: Zeile 9 enthält ALine, der Cursor steht dort.</summary>
  function GuardsAfterEnter(const AStatement, ALine: string; out AItems: TCompletionItems): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
    Resolver: TNameResolver;
  begin
    Text := 'unit Haupt;'#13#10'interface'#13#10'implementation'#13#10'uses Teile;'#13#10 +
      'procedure Laden;'#13#10'var'#13#10'  List: TStringList;'#13#10'begin'#13#10'  ' + AStatement + #13#10 +
      ALine + #13#10'end;'#13#10'end.';
    Tree := TPascalParser.Parse(Text);
    Resolver := TNameResolver.Create(FIndex);
    try
      Result := TLspCompletion.GuardItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(9, Length(ALine)),
        TCompletionFreeStyle.Free, True, AItems);
    finally
      Resolver.Free;
      Tree.Free;
    end;
  end;

var
  Items: TCompletionItems;
  Json: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTeile, 'C:\P\Teile.pas', nil));
  // Neue Zeile: ein Eintrag mit Cursor im try.
  Assert.IsTrue(Guards('List: TStringList;', 'List := TStringList.Create;', '', TCompletionFreeStyle.Free, Items));
  Assert.AreEqual(1, Integer(Length(Items.Items)));
  Assert.AreEqual('Mit try…finally absichern', Items.Items[0].Name);
  Assert.AreEqual('List.Free', Items.Items[0].Detail);
  Assert.AreEqual('newLine', Items.Items[0].Guard);
  Assert.IsTrue(Items.Items[0].TextEdit.NewText.Contains('try'#13#10'    $0'));
  Json := TLspCompletion.ToJson(Items);
  try
    Assert.IsTrue(Json.ToJSON.Contains('"guard":"newLine"'));
  finally
    Json.Free;
  end;
  // Folgende Zeilen: zweiter Eintrag bis zum Routinenende; FreeAndNil nach Einstellung.
  Assert.IsTrue(Guards('List: TStringList;', 'List := TStringList.Create;', '  List.Add(''a'');'#13#10,
    TCompletionFreeStyle.FreeAndNil, Items));
  Assert.AreEqual(2, Integer(Length(Items.Items)));
  Assert.AreEqual('routineEnd', Items.Items[1].Guard);
  Assert.AreEqual('FreeAndNil(List)', Items.Items[1].Detail);
  // Komponente mit Owner und Record: nichts; Komponente ohne Owner: angeboten.
  Assert.IsFalse(Guards('Timer: TTimer;', 'Timer := TTimer.Create(pnlOben);', '', TCompletionFreeStyle.Free, Items));
  Assert.IsTrue(Guards('Timer: TTimer;', 'Timer := TTimer.Create(nil);', '', TCompletionFreeStyle.Free, Items));
  Assert.IsFalse(Guards('P: TPunkt;', 'P := TPunkt.Create;', '', TCompletionFreeStyle.Free, Items));
  // Enter am Zeilenende ohne ";": Das ";" kommt dazu, die leere Zeile wird ersetzt.
  Assert.IsTrue(GuardsAfterEnter('List := TStringList.Create', '  ', Items));
  Assert.AreEqual(1, Integer(Length(Items.Items)));
  Assert.IsTrue(Items.Items[0].TextEdit.NewText.StartsWith(';'#13#10'  try'), Items.Items[0].TextEdit.NewText);
  Assert.AreEqual(8, Items.Items[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(9, Items.Items[0].TextEdit.Range.EndPos.Line);
  // Mit ";" ebenso; Inhalt in der Zeile des Cursors: nichts.
  Assert.IsTrue(GuardsAfterEnter('List := TStringList.Create;', '', Items));
  Assert.IsFalse(GuardsAfterEnter('List := TStringList.Create', '  List', Items));
end;
procedure TLspCompletionProposalTests.CollectWithOuterPinSameItems;
var
  Text, Plain: string;
  Tree: TSyntaxTree;
begin
  Text := WithCode('  ');
  Plain := Names(ItemsAt(Text, #10'begin'#10'  '));
  Tree := TPascalParser.Parse(Text);
  try
    FResolver.PinTree(Tree, HauptFile);
    try
      Assert.AreEqual(Plain, Names(TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile,
        PositionOf(Text, #10'begin'#10'  '), TCompletionMatching.Prefix)));
      // Ein zweiter Aufruf im selben Pin (wie Handle mit mehreren Stufen).
      Assert.AreEqual(Plain, Names(TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile,
        PositionOf(Text, #10'begin'#10'  '), TCompletionMatching.Prefix)));
    finally
      FResolver.UnpinTree;
    end;
  finally
    Tree.Free;
  end;
  Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo TBasis Rechne', Plain);
end;

const
  cOverrideBasisFile = 'C:\P\Basis.pas';
  cOverrideMitteFile = 'C:\P\Mitte.pas';
  cOverrideUnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBasisListe = class'#13#10 +
    '  protected'#13#10 +
    '    procedure Changed; virtual;'#13#10 +
    '    procedure Cleared; virtual;'#13#10 +
    '    procedure Sorted; virtual;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  cOverrideUnitMitte =
    'unit Mitte;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TMitte = class(TBasisListe)'#13#10 +
    '  protected'#13#10 +
    '    procedure Moved; virtual;'#13#10 +
    '    procedure Renamed; virtual;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  cOverrideText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis, Mitte;'#13#10 +
    'type'#13#10 +
    '  TLogList = class(TMitte)'#13#10 +
    '  protected'#13#10 +
    '    procedure '#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

procedure TLspCompletionProposalTests.OverrideItemsReadsEachFileOnce;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  Reads: TDictionary<string, Integer>;
  Count: Integer;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOverrideUnitBasis, cOverrideBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOverrideUnitMitte, cOverrideMitteFile, nil));
  Reads := TDictionary<string, Integer>.Create;
  Tree := TPascalParser.Parse(cOverrideText);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.OverrideItems(Resolver, Tree, cOverrideText, HauptFile, PositionOf(cOverrideText,
      '    procedure '),
      function(const AFileName: string; out AText: string): Boolean
      var
        Seen: Integer;
      begin
        if not Reads.TryGetValue(UpperCase(AFileName), Seen) then
        begin
          Seen := 0;
        end;
        Reads.AddOrSetValue(UpperCase(AFileName), Seen + 1);
        Result := True;
        if SameText(AFileName, cOverrideBasisFile) then
        begin
          AText := cOverrideUnitBasis;
        end
        else if SameText(AFileName, cOverrideMitteFile) then
        begin
          AText := cOverrideUnitMitte;
        end
        else
        begin
          Result := False;
        end;
      end, Items));
    Assert.AreEqual('Moved Renamed Changed Cleared Sorted', Names(Items));
    // Vorher je Kandidat einmal (3 bzw. 2), jetzt je Datei einmal.
    Assert.AreEqual(2, Integer(Reads.Count));
    Assert.IsTrue(Reads.TryGetValue(UpperCase(cOverrideBasisFile), Count));
    Assert.AreEqual(1, Count);
    Assert.IsTrue(Reads.TryGetValue(UpperCase(cOverrideMitteFile), Count));
    Assert.AreEqual(1, Count);
  finally
    Resolver.Free;
    Tree.Free;
    Reads.Free;
  end;
end;

const
  FormUnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
  FormDfm =
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '    OnEnter = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';

/// <summary>Formular-Unit; ABody steht in Zeile 13 im Rumpf von TfrmMain.FormCreate, AClass in Zeile 7 im
/// Klassenrumpf.</summary>
function FormSource(const AClass, ABody: string): string;
begin
  Result :=
    'unit Haupt;'#13#10 +                                  // 0
    'interface'#13#10 +                                    // 1
    'uses Steuer;'#13#10 +                                 // 2
    'type'#13#10 +                                         // 3
    '  TfrmMain = class(TForm)'#13#10 +                    // 4
    '    btnSave: TButton;'#13#10 +                        // 5
    '    btnLoad: TBitBtn;'#13#10 +                        // 6
    '    ' + AClass + #13#10 +                             // 7
    '    procedure FormCreate(Sender: TObject);'#13#10 +   // 8
    '  end;'#13#10 +                                       // 9
    'implementation'#13#10 +                               // 10
    '{$R *.dfm}'#13#10 +                                   // 11
    'procedure TfrmMain.FormCreate(Sender: TObject);'#13#10 + // 12
    'begin'#13#10 +                                        // 13
    '  ' + ABody + #13#10 +                                // 14
    'end;'#13#10 +
    'end.';
end;
procedure TLspCompletionProposalTests.ComponentItemsOutsideRoutineDoesNotReadForm;
var
  Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  Reads: Integer;
  ReadForm: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, 'C:\P\Steuer.pas', nil));
  Reads := 0;
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(Reads);
      AText := FormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  Resolver := TNameResolver.Create(FIndex);
  try
    // Im Klassenrumpf: keine Routine, also kein Lesezugriff.
    Text := FormSource('btn', '');
    Tree := TPascalParser.Parse(Text);
    try
      Assert.IsFalse(TLspCompletion.ComponentItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(7, 7),
        ReadForm, TCompletionMatching.Fuzzy, Items));
      Assert.AreEqual(0, Reads);
    finally
      Tree.Free;
    end;
    // In der Methode: einmal gelesen, beide Komponenten.
    Text := FormSource('', 'btn');
    Tree := TPascalParser.Parse(Text);
    try
      Assert.IsTrue(TLspCompletion.ComponentItems(Resolver, Tree, Text, HauptFile, TTextPosition.Create(14, 5),
        ReadForm, TCompletionMatching.Fuzzy, Items));
      Assert.AreEqual(1, Reads);
      Assert.AreEqual(2, Integer(Length(Items)));
      Assert.AreEqual('btnSave', Items[0].Name);
      Assert.AreEqual('frmMain', Items[0].Form);
      Assert.AreEqual('TfrmMain', Items[0].Container);
    finally
      Tree.Free;
    end;
  finally
    Resolver.Free;
  end;
end;
procedure TLspCompletionProposalTests.ComponentItemsSecondRequestUsesCache;
var
  Folder, UnitFile, DfmFile, Text, Answer: string;
  Store: IDocumentStore;
  Completion: TLspCompletion;
  Dispatcher: TJsonRpcDispatcher;
  Reads, Id: Integer;

  function Ask: string;
  var
    Request, Response: TJSONObject;
  begin
    Inc(Id);
    Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(Id) +
      ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' +
      TDocumentUris.FromPath(UnitFile).Replace('\', '\\') + '"},"position":{"line":14,"character":5}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Result := Response.ToJSON;
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  end;

begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasFormCache' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  UnitFile := TPath.Combine(Folder, 'Haupt.pas');
  DfmFile := TPath.Combine(Folder, 'Haupt.dfm');
  TFile.WriteAllText(DfmFile, FormDfm);
  Text := FormSource('', 'btn');
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, TPath.Combine(Folder, 'Steuer.pas'), nil));
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(UnitFile), 'delphi', 1, Text);
  Reads := 0;
  Id := 0;
  Completion := TLspCompletion.Create(Store, FIndex);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Completion.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, DfmFile) and FileExists(AFileName);
        if Result then
        begin
          Inc(Reads);
          AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
        end;
      end;
    Completion.Attach(Dispatcher);
    Answer := Ask;
    Assert.IsTrue(Answer.Contains('"btnSave"'), Answer);
    Assert.AreEqual(1, Reads);
    // Unveränderte Datei: kein weiterer Lesezugriff.
    Answer := Ask;
    Assert.IsTrue(Answer.Contains('"btnLoad"'), Answer);
    Assert.AreEqual(1, Reads);
    // Komponente umbenannt, Datei mit neuer Zeit: neu gelesen.
    TFile.WriteAllText(DfmFile, FormDfm.Replace('btnLoad', 'btnOpen'));
    FileSetDate(DfmFile, DateTimeToFileDate(Now + 1));
    Answer := Ask;
    Assert.AreEqual(2, Reads);
    // btnLoad bleibt als Feld der Klasse in der Liste, nur nicht mehr als Komponente des Formulars.
    Assert.IsTrue(Answer.Contains('"btnOpen"'), Answer);
  finally
    Dispatcher.Free;
    Completion.Free;
    TDirectory.Delete(Folder, True);
  end;
end;
procedure TLspCompletionProposalTests.SenderItemsFindsHeaderFarAboveAndSkipsLocalRoutines;
const
  Filler = 2100;
var
  Text, Body: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TCompletionItems;
  ReadForm: TCompletionReadText;
  Index, Line: Integer;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(FormUnitSteuer, 'C:\P\Steuer.pas', nil));
  ReadForm :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := FormDfm;
      Result := SameText(ExtractFileExt(AFileName), '.dfm');
    end;
  // Lokale Prozedur zwischen Kopf und Cursor, dann mehr Zeilen, als die frühere Zeilensuche (2000) prüfte.
  Body := '';
  for Index := 1 to Filler do
  begin
    Body := Body + '  // Zeile'#13#10;
  end;
  Text :=
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    btnLoad: TBitBtn;'#13#10 +
    '    procedure btnAnyClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.btnAnyClick(Sender: TObject);'#13#10 +
    '  procedure Innen(A: Integer);'#13#10 +
    '  begin'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    Body +
    '  Sender.Cap'#13#10 +
    'end;'#13#10 +
    'end.';
  Line := 16 + Filler;
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(TLspCompletion.SenderItems(Resolver, FIndex, Tree, Text, HauptFile, TTextPosition.Create(Line, 12),
      ReadForm, TCompletionMatching.Fuzzy, TCompletionSenderCast.AsOperator, Items));
    Assert.AreEqual('Caption', Names(Items));
    Assert.AreEqual('TButton', Items.Items[0].Sender);
    // btnLoad hat zwei Ereignisse auf die Methode, zählt aber einmal.
    Assert.AreEqual('btnSave, btnLoad', Items.Items[0].SenderOf);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;
procedure TLspCompletionProposalTests.BuiltinTypeNotShadowedByIndexEnum;
const
  UnitFremd =
    'unit Fremd;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  Integer = (Eins, Zwei);'#13#10 +
    'implementation'#13#10 +
    'end.';
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Lauf;'#13#10 +
    'var'#13#10 +
    '  I: Integer;'#13#10 +
    'begin'#13#10 +
    '  I := '#13#10 +
    'end;'#13#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Items: TArray<TCompletionItem>;
  SetMode: Boolean;
  Item: TCompletionItem;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitFremd, 'C:\P\Fremd.pas', nil));
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(FIndex);
  try
    if TLspCompletion.EnumItems(Resolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, '  I := '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitFremd;
        Result := SameText(AFileName, 'C:\P\Fremd.pas');
      end, TCompletionMatching.Fuzzy, Items, SetMode) then
    begin
      for Item in Items do
      begin
        Assert.AreNotEqual('Eins', Item.Name);
      end;
    end;
    Assert.IsFalse(SetMode);
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionProposalTests);

end.
