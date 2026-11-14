unit Atlas.Common.Lsp.Completion.Proposals.Tests;

// Tests der Vervollständigung für Vorschläge, die Code erzeugen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Vorschläge, die Code erzeugen: Überschreiben, Ereignisse, case-Zweige, Felder, Deklarationen,
  /// Formularkomponenten.</summary>
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
    procedure OffersTryFinallyAfterConstructor;
    [Test]
    procedure OffersGenericInterfaceMethods;
    [Test]
    procedure GroupsByExpectedType;
    /// <summary>Collect mit vom Aufrufer gepinntem Baum liefert dasselbe.</summary>
    [Test]
    procedure CollectWithOuterPinSameItems;
    /// <summary>Jede Vorfahren-Unit wird einmal gelesen, nicht je Kandidat.</summary>
    [Test]
    procedure OverrideItemsReadsEachFileOnce;
    /// <summary>Eingebaute Typen werden nicht im Index gesucht (kein gleichnamiger Fremdtyp).</summary>
    [Test]
    procedure BuiltinTypeNotShadowedByIndexEnum;
    /// <summary>#456: Helper aus nicht eingebundenen Units nach den eigenen Mitgliedern, mit Kennzeichen und
    /// uses-Eintrag; eingebunden ohne uses-Eintrag.</summary>
    [Test]
    procedure HelpersFromOtherUnitsBringTheirUses;
  end;

implementation

uses
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.AssignFields,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Context,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Completion.Details;

procedure TLspCompletionProposalTests.WarmUpFirstUse;
begin
  Setup;
  try
    OffersOverridesWithDeclarationAndBody;
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
  cUnitHilfen = 'unit Hilfen;'#10'interface'#10'uses Werkzeug;'#10'type'#10 +
    '  TBasisHelper = class helper for TBasis'#10'  public'#10'    procedure Hilfe;'#10'  end;'#10 +
    '  TTextHelper = record helper for string'#10'  public'#10'    function Laenge: Integer;'#10 +
    '  private'#10'    procedure Intern;'#10'  end;'#10'implementation'#10'end.';
var
  mText: string;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mFound: Boolean;
  mDetails: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHilfen, 'C:\P\Hilfen.pas', nil));
  // Detailpanel: „TTextHelper · Hilfen“ (Zeile 10: function Laenge).
  mDetails := TCompletionDetails.Details(FIndex, 'C:\P\Hilfen.pas', cUnitHilfen, TTextPosition.Create(10, 13));
  try
    Assert.AreEqual('TTextHelper', mDetails.GetValue<string>('container'));
    // TJSONBool.Create(True) ist kein TJSONTrue; erst der Parser erzeugt diese Klasse.
    Assert.IsTrue((mDetails.GetValue('helper') is TJSONBool) and TJSONBool(mDetails.GetValue('helper')).AsBoolean,
      mDetails.ToJSON);
  finally
    mDetails.Free;
  end;
  mText := WithCode('  Wert.');
  mItems := ItemsAt(mText, 'Wert.');
  // Eigene und geerbte Mitglieder zuerst, der Helper des Vorfahren dahinter.
  Assert.AreEqual('Name Bar Zaehler Melde Hilfe', Names(mItems));
  mFound := False;
  for mItem in mItems.Items do
  begin
    if mItem.Name = 'Hilfe' then
    begin
      mFound := True;
      Assert.IsTrue(mItem.IsHelper);
      Assert.AreEqual(1, mItem.Depth);
      Assert.AreEqual('Hilfen (uses ergänzen)', mItem.Detail);
      Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
      // Verwendung im implementation-Teil: dort ein neuer uses-Abschnitt.
      Assert.IsTrue(mItem.AdditionalEdits[0].NewText.Contains('Hilfen'), mItem.AdditionalEdits[0].NewText);
    end;
  end;
  Assert.IsTrue(mFound);
  // Eingebauter Typ: nur die öffentlichen Helper-Mitglieder.
  Assert.AreEqual('Laenge', Names(ItemsAt(WithCode('  Wert.Name.'), 'Wert.Name.')));
  // Eingebunden: aktiver Helper ohne uses-Eintrag.
  mText := StringReplace(WithCode('  Wert.'), 'uses Werkzeug;', 'uses Werkzeug, Hilfen;', []);
  for mItem in ItemsAt(mText, 'Wert.').Items do
  begin
    if mItem.Name = 'Hilfe' then
    begin
      Assert.IsTrue(mItem.IsHelper);
      Assert.AreEqual(0, Integer(Length(mItem.AdditionalEdits)));
    end;
  end;
end;
procedure TLspCompletionProposalTests.OffersOverridesWithDeclarationAndBody;
const
  cUnitBasis =
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
  cText =
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TCompletionItems;
  mBody: string;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, 'C:\P\Basis.pas', nil));
  mTree := TPascalParser.Parse(cText);
  mResolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(OverrideAt(LookupOf(mResolver, nil, mTree, cText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end),
      PositionOf(cText, '    procedure '), mItems));
    // Nur virtuelle Prozeduren; Count ist eine Funktion, Fest nicht virtuell.
    Assert.AreEqual('Changed Pruefe', Names(mItems));
    Assert.AreEqual('Changed; override;', mItems.Items[0].InsertText);
    Assert.AreEqual('TBasisListe', mItems.Items[0].Container);
    Assert.AreEqual(1, Integer(Length(mItems.Items[0].AdditionalEdits)));
    mBody := mItems.Items[0].AdditionalEdits[0].NewText;
    Assert.IsTrue(mBody.Contains('procedure TLogList.Changed;'#13#10'begin'#13#10'  inherited;'#13#10'end;'), mBody);
    // Abstrakt: ohne inherited; Standardwert nur in der Deklaration.
    Assert.AreEqual('Pruefe(A: Integer; const B: string = ''''); override;', mItems.Items[1].InsertText);
    mBody := mItems.Items[1].AdditionalEdits[0].NewText;
    Assert.IsTrue(mBody.Contains('procedure TLogList.Pruefe(A: Integer; const B: string);'), mBody);
    Assert.IsFalse(mBody.Contains('inherited'), mBody);
    // Außerhalb einer Klassendeklaration kein Override-Kontext.
    Assert.IsFalse(OverrideAt(LookupOf(mResolver, nil, mTree, cText, nil),
      PositionOf(cText, 'uses Ba'), mItems));
  finally
    mResolver.Free;
    mTree.Free;
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mHandlers, mEdits: string;
  mEdit: TRuleEdit;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cEventsUnitBasis, 'C:\P\Basis.pas', nil));
  mTree := TPascalParser.Parse(cEventsText);
  mResolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(EventsAt(LookupOf(mResolver, nil, mTree, cEventsText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cEventsUnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end),
      PositionOf(cEventsText, 'btnSave.OnClick := '), mItems));
    // Nur Methoden mit (Sender: TObject); Fertig hat zwei Parameter.
    mHandlers := '';
    for mItem in mItems.Items do
    begin
      if mItem.Action = '' then
      begin
        mHandlers := mHandlers + ' ' + mItem.Name;
        Assert.AreEqual('TNotifyEvent', mItem.Expected);
        Assert.IsTrue(mItem.Fits);
      end;
    end;
    Assert.AreEqual(' FormCreate btnSaveClick', mHandlers);
    // Zuletzt die neue Methode; btnSaveClick ist vergeben.
    mItem := mItems.Items[High(mItems.Items)];
    Assert.AreEqual('create', mItem.Action);
    Assert.AreEqual('Neue Methode btnSaveClick2 …', mItem.Name);
    Assert.AreEqual('btnSaveClick2', mItem.InsertText);
    mEdits := '';
    for mEdit in mItem.AdditionalEdits do
    begin
      mEdits := mEdits + mEdit.NewText + '|';
    end;
    Assert.AreEqual(2, Integer(Length(mItem.AdditionalEdits)), mEdits);
    Assert.IsTrue(mEdits.Contains('private'#13#10'    procedure btnSaveClick2(Sender: TObject);'), mEdits);
    Assert.IsTrue(mEdits.Contains('procedure TForm1.btnSaveClick2(Sender: TObject);'#13#10'begin'#13#10#13#10'end;'),
      mEdits);
    // Keine Ereignis-Zuweisung: normale Vervollständigung.
    Assert.IsFalse(EventsAt(LookupOf(mResolver, nil, mTree, cEventsText, nil),
      PositionOf(cEventsText, 'uses Ba'), mItems));
  finally
    mResolver.Free;
    mTree.Free;
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mList: TCompletionItems;
  mEdits, mMerged: TArray<TRuleEdit>;
  mItem: TCompletionItem;
  mBatch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cGenericUnitListen, 'C:\P\Listen.pas', nil));
  mTree := TPascalParser.Parse(cGenericText);
  mResolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(InterfaceAt(LookupOf(mResolver, nil, mTree, cGenericText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cGenericUnitListen;
        Result := SameText(AFileName, 'C:\P\Listen.pas');
      end),
      TTextPosition.Create(8, 4), TCompletionInterfaceSection.Public, mItems, mBatch));
    mList.Items := mItems;
    Assert.AreEqual('Add Items', Names(mList));
    Assert.AreEqual('IListe<TKunde>', mItems[0].Container);
    Assert.Contains(mItems[0].Detail, 'procedure Add(const AItem: TKunde)');
    Assert.Contains(mItems[1].Detail, 'function Items: TArray<TKunde>');
    mEdits := nil;
    for mItem in mItems do
    begin
      mEdits := mEdits + mItem.AdditionalEdits;
    end;
    mMerged := TInterfaceStubs.Merge(mEdits);
    Assert.IsTrue(mMerged[0].NewText.Contains('{ IListe<TKunde> }'), mMerged[0].NewText);
    Assert.IsTrue(mMerged[1].NewText.Contains('procedure TKundenListe.Add(const AItem: TKunde);'), mMerged[1].NewText);
    Assert.IsTrue(mMerged[1].NewText.Contains('Result := Default(TArray<TKunde>);'), mMerged[1].NewText);
  finally
    mResolver.Free;
    mTree.Free;
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
  Assert.IsTrue(InterfaceAt(LookupOf(AResolver, nil, ATree, cMissingTyped,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cMissingUnitBasis;
      Result := True;
    end),
    TTextPosition.Create(7, 6), TCompletionInterfaceSection.Public, mItems, mBatch));
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mList: TCompletionItems;
  mBatch: Boolean;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cMissingUnitBasis, 'C:\P\Basis.pas', nil));
  mTree := TPascalParser.Parse(cMissingText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // Strg+Leer auf der leeren Zeile: Liste mit Kontrollkästchen. SetName erbt die Klasse von TBasis.
    Assert.IsTrue(InterfaceAt(LookupOf(mResolver, nil, mTree, cMissingText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cMissingUnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end),
      TTextPosition.Create(7, 4), TCompletionInterfaceSection.Public, mItems, mBatch));
    Assert.IsTrue(mBatch);
    mList.Items := mItems;
    Assert.AreEqual('Export GetName Flush', Names(mList));
    Assert.AreEqual('IExporter', mItems[0].Container);
    Assert.AreEqual('IFlush', mItems[2].Container);
    Assert.AreEqual('IExporter, IFlush', mItems[0].SetOf);
    Assert.IsTrue(mItems[0].Batch and mItems[0].SetChecked);
    Assert.AreEqual(3, mItems[2].Ordinal);
    Assert.AreEqual(7, mItems[0].SetRange.StartPos.Line);
    AssertMergedInterfaceStubs(mItems);
    // Abschnitt nach Einstellung: private steht schon als letzter da, also kein neuer.
    Assert.IsTrue(InterfaceAt(LookupOf(mResolver, nil, mTree, cMissingText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cMissingUnitBasis;
        Result := True;
      end),
      TTextPosition.Create(7, 4), TCompletionInterfaceSection.Private, mItems, mBatch));
    Assert.AreEqual('    { IExporter }'#13#10, mItems[0].AdditionalEdits[0].NewText);
    // Außerhalb der Klasse nichts.
    Assert.IsFalse(InterfaceAt(LookupOf(mResolver, nil, mTree, cMissingText, nil),
      TTextPosition.Create(2, 0), TCompletionInterfaceSection.Public, mItems, mBatch));
  finally
    mTree.Free;
  end;
  // Angefangenes Wort: je Interface ein Hinweis, der seine Methoden anlegt und das Wort entfernt.
  mTree := TPascalParser.Parse(cMissingTyped);
  try
    AssertTypedInterfaceHints(mResolver, mTree);
  finally
    mResolver.Free;
    mTree.Free;
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mKnown: TArray<TCompletionItem>;

  function Named(const AName: string): TCompletionItem;
  var
    mItem: TCompletionItem;
  begin
    for mItem in mItems do
    begin
      if mItem.Name = AName then
      begin
        Exit(mItem);
      end;
    end;
    raise Exception.CreateFmt('Eintrag "%s" fehlt', [AName]);
  end;

var
  mItem: TCompletionItem;
begin
  mTree := TPascalParser.Parse(cUnknownText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // Ziel einer Zuweisung: Typ aus der rechten Seite.
    Assert.IsTrue(DeclareAt(LookupOf(mResolver, FIndex, mTree, cUnknownText, nil),
      PositionOf(cUnknownText, '  TotalCount'), True, nil, mItems));
    mItem := Named('Lokale Variable anlegen');
    Assert.AreEqual('TotalCount: Integer', mItem.Detail);
    Assert.AreEqual('declare', mItem.Action);
    Assert.AreEqual('TotalCount', mItem.Unknown);
    // Die Verwendung bleibt, der Cursor auch; var vor begin.
    Assert.AreEqual('TotalCount$0', mItem.TextEdit.NewText);
    Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
    Assert.AreEqual('var'#13#10'  TotalCount: Integer;'#13#10, mItem.AdditionalEdits[0].NewText);
    Assert.AreEqual(17, mItem.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual('var TotalCount$0', Named('Inline-Variable anlegen').TextEdit.NewText);
    // Feld mit F-Konvention: im private-Abschnitt, die Verwendung heißt danach FTotalCount.
    mItem := Named('Feld FTotalCount anlegen');
    Assert.AreEqual('FTotalCount$0', mItem.TextEdit.NewText);
    Assert.AreEqual(7, mItem.AdditionalEdits[0].Range.StartPos.Line);
    Assert.AreEqual(#13#10'    FTotalCount: Integer;', mItem.AdditionalEdits[0].NewText);
    // Keine Konstante als Ziel einer Zuweisung.
    for mItem in mItems do
    begin
      Assert.AreNotEqual('Konstante anlegen', mItem.Name);
    end;
    // Als Argument: Typ des Parameters, auch als Konstante in der implementation.
    Assert.IsTrue(DeclareAt(LookupOf(mResolver, FIndex, mTree, cUnknownText, nil),
      PositionOf(cUnknownText, 'Zeige(Anzahl'), False, nil, mItems));
    Assert.AreEqual('Anzahl: Integer', Named('Lokale Variable anlegen').Detail);
    mItem := Named('Konstante anlegen');
    Assert.AreEqual('Anzahl = 0;', mItem.Detail);
    Assert.AreEqual(12, mItem.AdditionalEdits[0].Range.StartPos.Line);
    // Bekannte Namen und genaue Treffer: nichts.
    Assert.IsFalse(DeclareAt(LookupOf(mResolver, FIndex, mTree, cUnknownText, nil),
      PositionOf(cUnknownText, 'Zeige(Anzahl);'#13#10'  FLines'), True, nil, mItems));
    // Eigene Variable für die bekannten Einträge: Ein out-Parameter leert sein Ziel vor dem Aufruf.
    SetLength(mKnown, 1);
    mKnown[0] := Default(TCompletionItem);
    mKnown[0].Name := 'Anzahl';
    Assert.IsFalse(DeclareAt(LookupOf(mResolver, FIndex, mTree, cUnknownText, nil),
      PositionOf(cUnknownText, 'Zeige(Anzahl'), True, mKnown, mItems));
  finally
    mResolver.Free;
    mTree.Free;
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
  mPosition: TTextPosition;
begin
  mTree := TPascalParser.Parse(cCaseText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // Ohne Zweige: „Alle Werte einfügen“ zuerst, mit Anzahl; alle vier Zweige und das fehlende end.
    mPosition := PositionOf(cCaseText, 'case S.Kind of'#13#10'    ');
    Assert.IsTrue(EnumAt(LookupOf(mResolver, FIndex, mTree, cCaseText, nil),
      mPosition, mItems, mSetMode));
    Assert.AreEqual('Alle Werte einfügen', mItems[0].Name);
    Assert.IsTrue(mItems[0].Pinned);
    Assert.AreEqual(4, Integer(mItems[0].Count));
    Assert.IsTrue(mItems[0].HasTextEdit);
    Assert.AreEqual(#13#10'    skCircle: $0;'#13#10'    skLine: ;'#13#10'    skRect: ;'#13#10'    skTriangle: ;' +
      #13#10'  end;', mItems[0].TextEdit.NewText);
    // Ersetzt wird ab dem "of" bis zum Cursor (der Leerraum der Zeile).
    Assert.AreEqual(24, mItems[0].TextEdit.Range.StartPos.Line);
    Assert.AreEqual(16, mItems[0].TextEdit.Range.StartPos.Character);
    Assert.AreEqual(mPosition.Line, mItems[0].TextEdit.Range.EndPos.Line);
    Assert.AreEqual(mPosition.Character, mItems[0].TextEdit.Range.EndPos.Character);
    Assert.AreEqual('skCircle', mItems[1].Name, 'darunter die einzelnen Werte');
    // Mit Zweig skCircle: nur die drei übrigen, end ist vorhanden.
    Assert.IsTrue(EnumAt(LookupOf(mResolver, FIndex, mTree, cCaseText, nil),
      PositionOf(cCaseText, 'skCircle: Zeichne;'#13#10'    sk'), mItems, mSetMode));
    Assert.AreEqual('Fehlende Werte ergänzen (3)', mItems[0].Name);
    Assert.AreEqual(0, Integer(mItems[0].Count));
    Assert.AreEqual(#13#10'    skLine: $0;'#13#10'    skRect: ;'#13#10'    skTriangle: ;', mItems[0].TextEdit.NewText);
    // Bereiche und Listen zählen als vorhanden: nichts mehr zu ergänzen.
    Assert.IsTrue(EnumAt(LookupOf(mResolver, FIndex, mTree, cCaseText, nil),
      PositionOf(cCaseText, 'skTriangle: ;'#13#10'    '), mItems, mSetMode));
    Assert.AreEqual('skCircle', mItems[0].Name);
    Assert.IsFalse(mItems[0].Pinned);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

const
  cAssignText =
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
  mItem: TCompletionItem;
  mText: string;
begin
  // Abnahme: drei Felder mit Platzhaltern; steht Opts.Header schon in der nächsten Zeile, nur zwei.
  mText := StringReplace(cAssignText, '  Opts.Header := ''x'';'#13#10, '', []);
  Assert.IsTrue(AssignItem(mText, #10'  Opts.', True, True, mItem));
  Assert.AreEqual('Alle Felder zuweisen (3)', mItem.Name);
  Assert.IsTrue(mItem.Pinned);
  Assert.IsTrue(mItem.Snippet);
  Assert.AreEqual('Opts.Header := ${1:''''};'#10'Opts.Count := ${2:0};'#10'Opts.Kind := ${3:kA};',
    mItem.TextEdit.NewText);
  Assert.AreEqual(2, mItem.TextEdit.Range.StartPos.Character, 'ab dem Anfang des Ausdrucks');
  Assert.AreEqual(7, mItem.TextEdit.Range.EndPos.Character);
  Assert.IsTrue(AssignItem(cAssignText, #10'  Opts.', True, True, mItem));
  Assert.AreEqual('Alle Felder zuweisen (2)', mItem.Name);
  Assert.AreEqual('Opts.Count := ${1:0};'#10'Opts.Kind := ${2:kA};', mItem.TextEdit.NewText);
  // Ohne Platzhalter: Klartext mit der Einrückung der Zeile.
  Assert.IsTrue(AssignItem(cAssignText, #10'  Opts.', False, True, mItem));
  Assert.IsFalse(mItem.Snippet);
  Assert.AreEqual('Opts.Count := 0;'#13#10'  Opts.Kind := kA;', mItem.TextEdit.NewText);
  // Klasse: Vorfahren zuerst; geschützte Property, die der Nachfahr öffentlich macht, ja; nur lesbare und
  // private nicht.
  Assert.IsTrue(AssignItem(cAssignText, #10'    C.', False, True, mItem));
  Assert.AreEqual('C.Hidden := '''';'#13#10'    C.Tag := 0;'#13#10'    C.Name := '''';'#13#10 +
    '    C.Owner := nil;'#13#10'    C.Flags := [];', mItem.TextEdit.NewText);
  // Nicht am Anweisungsanfang, nach einem Typ und abgeschaltet: nichts.
  Assert.IsFalse(AssignItem(cAssignText, 'X := Opts.', True, True, mItem), 'Zuweisung');
  Assert.IsFalse(AssignItem(cAssignText, '  TOpts.', True, True, mItem), 'Typ');
  Assert.IsFalse(AssignItem(cAssignText, #10'  Opts.', True, False, mItem), 'abgeschaltet');
  mItem := Default(TCompletionItem);
end;
procedure TLspCompletionProposalTests.AssignsManyFieldsThroughList;
var
  mItem: TCompletionItem;
  mText, mFields: string;
  mIndex: Integer;
  mJson: TJSONArray;
  mData, mLine: TJSONObject;
begin
  // Mehr als 15 Felder: erst die Liste mit Kontrollkästchen, je Zeile samt Umbruch für die nächste.
  mFields := '';
  for mIndex := 0 to TAssignFields.cListThreshold do
  begin
    mFields := mFields + '    F' + IntToStr(mIndex) + ': Integer;'#13#10;
  end;
  mText := StringReplace(cAssignText, '    Header: string;'#13#10, mFields, []);
  mText := StringReplace(mText, '  Opts.Header := ''x'';'#13#10, '', []);
  Assert.IsTrue(AssignItem(mText, #10'  Opts.', True, True, mItem));
  Assert.AreEqual('Alle Felder zuweisen (18)', mItem.Name);
  Assert.IsFalse(mItem.Snippet);
  Assert.AreEqual('Opts.', mItem.TextEdit.NewText, 'Text bleibt bis zur Auswahl');
  Assert.AreEqual(18, Integer(Length(mItem.Assignments)));
  Assert.AreEqual('F0', mItem.Assignments[0].Name);
  Assert.AreEqual('Integer', mItem.Assignments[0].Detail);
  Assert.AreEqual('Opts.F0 := 0;'#13#10'  ', mItem.Assignments[0].Text);
  Assert.AreEqual('Opts.Kind := kA;'#13#10'  ', mItem.Assignments[17].Text);
  // Im JSON unter data.assign.
  mJson := TLspCompletion.ToJson([mItem], 0);
  try
    mData := TJSONObject(mJson.Items[0]).GetValue('data') as TJSONObject;
    Assert.AreEqual('assign', mData.GetValue<string>('action'));
    mLine := (mData.GetValue('assign') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('F0', mLine.GetValue<string>('name'));
    Assert.AreEqual('Integer', mLine.GetValue<string>('detail'));
    Assert.AreEqual('Opts.F0 := 0;'#13#10'  ', mLine.GetValue<string>('text'));
  finally
    mJson.Free;
  end;
  mItem := Default(TCompletionItem);
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
procedure AssertScopedEnumAndCase(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AReader: TCompletionReadText);
var
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
begin
  // Vergleich mit Scoped Enum: Typpräfix beim Einfügen, gefiltert nach dem Getippten.
  Assert.IsTrue(EnumAt(LookupOf(AResolver, AIndex, ATree, cEnumText, AReader),
    PositionOf(cEnumText, 'C.Kind = sk'), mItems, mSetMode));
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.AreEqual('TShapeKind.skCircle', mItems[0].InsertText);
  // case-Zweig.
  Assert.IsTrue(EnumAt(LookupOf(AResolver, AIndex, ATree, cEnumText, AReader),
    PositionOf(cEnumText, 'skCircle: ;'#13#10'    '), mItems, mSetMode));
  Assert.AreEqual('Fehlende Werte ergänzen (3) skCircle skRect skLine skTriangle', JoinedItemNames(mItems));
  Assert.AreEqual(#13#10'    TShapeKind.skRect: $0;'#13#10'    TShapeKind.skLine: ;'#13#10'    TShapeKind.skTriangle: ;',
    mItems[0].TextEdit.NewText, 'Scoped Enum mit Typpräfix (#449)');
end;
/// <summary>Menge: alle Werte des Elementtyps, akLeft angehakt; bei in der Elementtyp aus der linken Seite.</summary>
procedure AssertEnumSetItems(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AReader: TCompletionReadText);
var
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
begin
  // Menge: alle Werte des Elementtyps, akLeft angehakt, Enter ersetzt die ganze Klammer.
  Assert.IsTrue(EnumAt(LookupOf(AResolver, AIndex, ATree, cEnumText, AReader),
    PositionOf(cEnumText, 'C.Anchors := [akLeft, '), mItems, mSetMode));
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
  Assert.IsTrue(EnumAt(LookupOf(AResolver, AIndex, ATree, cEnumText, AReader),
    PositionOf(cEnumText, 'C.Kind in ['), mItems, mSetMode));
  Assert.IsTrue(mSetMode);
  Assert.AreEqual('set of TShapeKind', mItems[0].Expected);
  Assert.AreEqual('TShapeKind.skCircle', mItems[0].InsertText);
end;
procedure TLspCompletionProposalTests.OffersEnumValuesAndSetValues;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
  mReader: TCompletionReadText;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cEnumUnitTypen, cEnumTypenFile, nil));
  mReader := TypenReader();
  mTree := TPascalParser.Parse(cEnumText);
  mResolver := TNameResolver.Create(FIndex);
  try
    // Zuweisung: Werte in Deklarationsreihenfolge, auch über mehrere Zeilen.
    Assert.IsTrue(EnumAt(LookupOf(mResolver, FIndex, mTree, cEnumText, mReader),
      PositionOf(cEnumText, 'C.Align := '), mItems, mSetMode));
    Assert.IsFalse(mSetMode);
    Assert.AreEqual('alNone alTop alClient', JoinedItemNames(mItems));
    Assert.AreEqual(3, mItems[2].Ordinal);
    Assert.AreEqual('TAlign', mItems[0].Expected);
    Assert.IsTrue(mItems[0].Fits);
    Assert.AreEqual('', mItems[0].InsertText);
    Assert.AreEqual(cEnumTypenFile, mItems[0].SourceFile, 'Position für completionItem/resolve');
    AssertScopedEnumAndCase(mResolver, FIndex, mTree, mReader);
    AssertEnumSetItems(mResolver, FIndex, mTree, mReader);
    // Index statt Menge.
    Assert.IsFalse(EnumAt(LookupOf(mResolver, FIndex, mTree, cEnumText, mReader),
      PositionOf(cEnumText, ':= List['), mItems, mSetMode));
    Assert.IsFalse(mSetMode);
  finally
    mResolver.Free;
    mTree.Free;
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
    mText, mFits: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
    mItems: TCompletionItems;
    mItem: TCompletionItem;
    mPosition: TTextPosition;
    mFitting: Boolean;
  begin
    mText := MakeText(ALine);
    mPosition := PositionOf(mText, ALine);
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(FIndex);
    try
      Result := TCompletionContexts.ExpectedType(mResolver, mTree, cHauptFile, mPosition);
      mItems := TCompletionLists.Collect(mResolver, FIndex, mTree, cHauptFile, mPosition);
      // Passende zuerst, danach keine passenden mehr.
      mFits := '';
      mFitting := True;
      for mItem in mItems.Items do
      begin
        Assert.AreEqual(AExpected, mItem.Expected, ALine + ': ' + mItem.Name);
        if mItem.Fits then
        begin
          Assert.IsTrue(mFitting, ALine + ': ' + mItem.Name + ' steht hinter nicht passenden');
          mFits := mFits + ' ' + mItem.Name;
        end
        else
        begin
          mFitting := False;
        end;
      end;
      Assert.AreEqual(AFits, Trim(mFits), ALine);
    finally
      mResolver.Free;
      mTree.Free;
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
procedure TLspCompletionProposalTests.OffersTryFinallyAfterConstructor;
const
  cUnitTeile =
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
    mText: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
  begin
    mText := 'unit Haupt;'#13#10'interface'#13#10'implementation'#13#10'uses Teile;'#13#10 +
      'procedure Laden;'#13#10'var'#13#10'  ' + AVar + #13#10'begin'#13#10'  ' + AStatement + #13#10 + ARest +
      'end;'#13#10'end.';
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(FIndex);
    try
      Result := GuardAt(LookupOf(mResolver, nil, mTree, mText, nil),
        TTextPosition.Create(8,
        2 + Length(AStatement)), AStyle, False, AItems);
    finally
      mResolver.Free;
      mTree.Free;
    end;
  end;

  /// <summary>Wie Guards, aber nach Enter am Zeilenende: Zeile 9 enthält ALine, der Cursor steht dort.</summary>
  function GuardsAfterEnter(const AStatement, ALine: string; out AItems: TCompletionItems): Boolean;
  var
    mText: string;
    mTree: TSyntaxTree;
    mResolver: TNameResolver;
  begin
    mText := 'unit Haupt;'#13#10'interface'#13#10'implementation'#13#10'uses Teile;'#13#10 +
      'procedure Laden;'#13#10'var'#13#10'  List: TStringList;'#13#10'begin'#13#10'  ' + AStatement + #13#10 +
      ALine + #13#10'end;'#13#10'end.';
    mTree := TPascalParser.Parse(mText);
    mResolver := TNameResolver.Create(FIndex);
    try
      Result := GuardAt(LookupOf(mResolver, nil, mTree, mText, nil),
        TTextPosition.Create(9, Length(ALine)), TCompletionFreeStyle.Free, True, AItems);
    finally
      mResolver.Free;
      mTree.Free;
    end;
  end;

var
  mItems: TCompletionItems;
  mJson: TJSONObject;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitTeile, 'C:\P\Teile.pas', nil));
  // Neue Zeile: ein Eintrag mit Cursor im try.
  Assert.IsTrue(Guards('List: TStringList;', 'List := TStringList.Create;', '', TCompletionFreeStyle.Free, mItems));
  Assert.AreEqual(1, Integer(Length(mItems.Items)));
  Assert.AreEqual('Mit try…finally absichern', mItems.Items[0].Name);
  Assert.AreEqual('List.Free', mItems.Items[0].Detail);
  Assert.AreEqual('newLine', mItems.Items[0].Guard);
  Assert.IsTrue(mItems.Items[0].TextEdit.NewText.Contains('try'#13#10'    $0'));
  mJson := TLspCompletion.ToJson(mItems);
  try
    Assert.IsTrue(mJson.ToJSON.Contains('"guard":"newLine"'));
  finally
    mJson.Free;
  end;
  // Folgende Zeilen: zweiter Eintrag bis zum Routinenende; FreeAndNil nach Einstellung.
  Assert.IsTrue(Guards('List: TStringList;', 'List := TStringList.Create;', '  List.Add(''a'');'#13#10,
    TCompletionFreeStyle.FreeAndNil, mItems));
  Assert.AreEqual(2, Integer(Length(mItems.Items)));
  Assert.AreEqual('routineEnd', mItems.Items[1].Guard);
  Assert.AreEqual('FreeAndNil(List)', mItems.Items[1].Detail);
  // Komponente mit Owner und Record: nichts; Komponente ohne Owner: angeboten.
  Assert.IsFalse(Guards('Timer: TTimer;', 'Timer := TTimer.Create(pnlOben);', '', TCompletionFreeStyle.Free, mItems));
  Assert.IsTrue(Guards('Timer: TTimer;', 'Timer := TTimer.Create(nil);', '', TCompletionFreeStyle.Free, mItems));
  Assert.IsFalse(Guards('P: TPunkt;', 'P := TPunkt.Create;', '', TCompletionFreeStyle.Free, mItems));
  // Enter am Zeilenende ohne ";": Das ";" kommt dazu, die leere Zeile wird ersetzt.
  Assert.IsTrue(GuardsAfterEnter('List := TStringList.Create', '  ', mItems));
  Assert.AreEqual(1, Integer(Length(mItems.Items)));
  Assert.IsTrue(mItems.Items[0].TextEdit.NewText.StartsWith(';'#13#10'  try'), mItems.Items[0].TextEdit.NewText);
  Assert.AreEqual(8, mItems.Items[0].TextEdit.Range.StartPos.Line);
  Assert.AreEqual(9, mItems.Items[0].TextEdit.Range.EndPos.Line);
  // Mit ";" ebenso; Inhalt in der Zeile des Cursors: nichts.
  Assert.IsTrue(GuardsAfterEnter('List := TStringList.Create;', '', mItems));
  Assert.IsFalse(GuardsAfterEnter('List := TStringList.Create', '  List', mItems));
end;
procedure TLspCompletionProposalTests.CollectWithOuterPinSameItems;
var
  mText, mPlain: string;
  mTree: TSyntaxTree;
begin
  mText := WithCode('  ');
  mPlain := Names(ItemsAt(mText, #10'begin'#10'  '));
  mTree := TPascalParser.Parse(mText);
  try
    FResolver.PinTree(mTree, cHauptFile);
    try
      Assert.AreEqual(mPlain, Names(TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile,
        PositionOf(mText, #10'begin'#10'  '), TCompletionMatching.Prefix)));
      // Ein zweiter Aufruf im selben Pin (wie Handle mit mehreren Stufen).
      Assert.AreEqual(mPlain, Names(TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile,
        PositionOf(mText, #10'begin'#10'  '), TCompletionMatching.Prefix)));
    finally
      FResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
  Assert.AreEqual('Wert Anzahl Self Name Bar Zaehler Melde TFoo TBasis Rechne', mPlain);
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TCompletionItems;
  mReads: TDictionary<string, Integer>;
  mCount: Integer;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOverrideUnitBasis, cOverrideBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOverrideUnitMitte, cOverrideMitteFile, nil));
  mReads := TDictionary<string, Integer>.Create;
  mTree := TPascalParser.Parse(cOverrideText);
  mResolver := TNameResolver.Create(FIndex);
  try
    Assert.IsTrue(OverrideAt(LookupOf(mResolver, nil, mTree, cOverrideText,
      function(const AFileName: string; out AText: string): Boolean
      var
        Seen: Integer;
      begin
        if not mReads.TryGetValue(UpperCase(AFileName), Seen) then
        begin
          Seen := 0;
        end;
        mReads.AddOrSetValue(UpperCase(AFileName), Seen + 1);
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
      end),
      PositionOf(cOverrideText,
      '    procedure '), mItems));
    Assert.AreEqual('Moved Renamed Changed Cleared Sorted', Names(mItems));
    // Vorher je Kandidat einmal (3 bzw. 2), jetzt je Datei einmal.
    Assert.AreEqual(2, Integer(mReads.Count));
    Assert.IsTrue(mReads.TryGetValue(UpperCase(cOverrideBasisFile), mCount));
    Assert.AreEqual(1, mCount);
    Assert.IsTrue(mReads.TryGetValue(UpperCase(cOverrideMitteFile), mCount));
    Assert.AreEqual(1, mCount);
  finally
    mResolver.Free;
    mTree.Free;
    mReads.Free;
  end;
end;

procedure TLspCompletionProposalTests.BuiltinTypeNotShadowedByIndexEnum;
const
  cUnitFremd =
    'unit Fremd;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  Integer = (Eins, Zwei);'#13#10 +
    'implementation'#13#10 +
    'end.';
  cText =
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mItems: TArray<TCompletionItem>;
  mSetMode: Boolean;
  mItem: TCompletionItem;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitFremd, 'C:\P\Fremd.pas', nil));
  mTree := TPascalParser.Parse(cText);
  mResolver := TNameResolver.Create(FIndex);
  try
    if EnumAt(LookupOf(mResolver, FIndex, mTree, cText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitFremd;
        Result := SameText(AFileName, 'C:\P\Fremd.pas');
      end), PositionOf(cText, '  I := '), mItems, mSetMode) then
    begin
      for mItem in mItems do
      begin
        Assert.AreNotEqual('Eins', mItem.Name);
      end;
    end;
    Assert.IsFalse(mSetMode);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionProposalTests);

end.
