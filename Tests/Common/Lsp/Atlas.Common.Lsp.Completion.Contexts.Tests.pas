unit Atlas.Common.Lsp.Completion.Contexts.Tests;

// Vervollständigung ohne Typauflösung (#31): Sichtbarkeit, inherited, Typpositionen,
// property read/write, override, Schlüsselwörter, Strings und Delphi-13-Operatoren,
// Doku als Klartext. Je Kontext ein positiver und ein negativer Fall.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionContextTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AText, AMarker: string): TCompletionItems;
    function Names(const AItems: TCompletionItems): string;
    function Has(const AItems: TCompletionItems; const AName: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PrivateFieldOfOtherUnitIsHidden;
    [Test]
    procedure ProtectedOnlyInDescendants;
    [Test]
    procedure InheritedOffersAncestorMethodsOnly;
    [Test]
    procedure ClassAncestorListOffersTypesOnly;
    [Test]
    procedure ColonInDeclarationOffersTypes;
    [Test]
    procedure IsNotAndNotInBehave;
    [Test]
    procedure NothingInMultiLineString;
    [Test]
    procedure PropertyReadOffersMatchingGetters;
    [Test]
    procedure PropertyWriteOffersMatchingSetters;
    [Test]
    procedure PropertyOffersAccessorCreation;
    [Test]
    procedure AccessorCreationFollowsSettings;
    [Test]
    procedure OverrideKeywordOffersVirtualMethods;
    [Test]
    procedure KeywordsFitThePlace;
    [Test]
    procedure DocumentationFollowsClientFormat;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Lists,
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.TestSupport,
  Atlas.Common.Lsp.Completion.Declarations,
  Atlas.Common.Lsp.Completion.Details;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cBasisFile = 'C:\P\Basis.pas';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '  private'#10 +
    '    FGeheim: Integer;'#10 +
    '  protected'#10 +
    '    procedure Geschuetzt; virtual;'#10 +
    '  public'#10 +
    '    Zaehler: Integer;'#10 +
    '    procedure Oeffentlich; virtual;'#10 +
    '    function Anzahl: Integer;'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Geschuetzt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Oeffentlich;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TBasis.Anzahl: Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '    Name: string;'#10 +
    '    procedure Bar;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Frei;'#10 +
    'var'#10 +
    '  Fremd: TBasis;'#10 +
    'begin'#10 +
    '  { Frei }'#10 +
    'end;'#10 +
    'procedure TFoo.Bar;'#10 +
    'var'#10 +
    '  Wert: TBasis;'#10 +
    'begin'#10 +
    '  { Methode }'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  // Cursor hinter AMarker.
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(mIndex, Length(AMarker));
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function InMethod(const ACode: string): string;
begin
  Result := StringReplace(cUnitHaupt, '  { Methode }', ACode, []);
end;

function InRoutine(const ACode: string): string;
begin
  Result := StringReplace(cUnitHaupt, '  { Frei }', ACode, []);
end;

{ TLspCompletionContextTests }

procedure TLspCompletionContextTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionContextTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCompletionContextTests.ItemsAt(const AText, AMarker: string): TCompletionItems;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile, PositionOf(AText, AMarker),
      TCompletionMatching.Prefix);
  finally
    mTree.Free;
  end;
end;

function TLspCompletionContextTests.Names(const AItems: TCompletionItems): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems.Items do
  begin
    Result := Result + mItem.Name + ' ';
  end;
  Result := Result.Trim;
end;

function TLspCompletionContextTests.Has(const AItems: TCompletionItems; const AName: string): Boolean;
var
  mItem: TCompletionItem;
begin
  Result := False;
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TLspCompletionContextTests.PrivateFieldOfOtherUnitIsHidden;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt(InRoutine('  Fremd.'), 'Fremd.');
  Assert.IsTrue(Has(mItems, 'Oeffentlich'), Names(mItems));
  Assert.IsTrue(Has(mItems, 'Zaehler'), Names(mItems));
  // private aus einer anderen Unit nie, protected außerhalb von Nachfahren nicht.
  Assert.IsFalse(Has(mItems, 'FGeheim'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Geschuetzt'), Names(mItems));
end;

procedure TLspCompletionContextTests.ProtectedOnlyInDescendants;
var
  mItems: TCompletionItems;
begin
  // In einer Methode des Nachfahren ist protected sichtbar, private weiterhin nicht.
  mItems := ItemsAt(InMethod('  Self.'), 'Self.');
  Assert.IsTrue(Has(mItems, 'Geschuetzt'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'FGeheim'), Names(mItems));
end;

procedure TLspCompletionContextTests.InheritedOffersAncestorMethodsOnly;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt(InMethod('  inherited '), 'inherited ');
  Assert.AreEqual('Geschuetzt Oeffentlich Anzahl', Names(mItems));
  Assert.AreEqual(1, mItems.Items[0].Depth);
  // Weder lokale Variablen, Felder noch Routinen der Unit; außerhalb einer Methode nichts.
  Assert.IsFalse(Has(mItems, 'Wert'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Zaehler'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Rechne'), Names(mItems));
  Assert.AreEqual('', Names(ItemsAt(InRoutine('  inherited '), 'inherited ')));
end;

procedure TLspCompletionContextTests.ClassAncestorListOffersTypesOnly;
var
  mText: string;
  mItems: TCompletionItems;
begin
  mText := StringReplace(cUnitHaupt, '  TFoo = class(TBasis)', '  TNeu = class('#10'  end;'#10 +
    '  TFoo = class(TBasis)', []);
  mItems := ItemsAt(mText, 'TNeu = class(');
  Assert.IsTrue(Has(mItems, 'TBasis'), Names(mItems));
  Assert.IsTrue(Has(mItems, 'TFoo'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Rechne'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Frei'), Names(mItems));
  // Ohne "class(" im Gültigkeitsbereich auch Routinen.
  mItems := ItemsAt(InMethod('  Re'), '  Re');
  Assert.IsTrue(Has(mItems, 'Rechne'), Names(mItems));
end;

procedure TLspCompletionContextTests.ColonInDeclarationOffersTypes;
var
  mText: string;
  mItems: TCompletionItems;
begin
  mText := StringReplace(cUnitHaupt, '  Wert: TBasis;', '  Wert: ', []);
  mItems := ItemsAt(mText, '  Wert: ');
  Assert.IsTrue(Has(mItems, 'TBasis'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Rechne'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Name'), Names(mItems));
  // Typ-Schlüsselwörter nur nach ":".
  mText := StringReplace(cUnitHaupt, '  Wert: TBasis;', '  Wert: str', []);
  Assert.IsTrue(Has(ItemsAt(mText, 'Wert: str'), 'string'));
  // Inline-Variable in einer Anweisung ebenfalls; case-Marke dagegen nicht.
  mItems := ItemsAt(InMethod('  var X: '), 'var X: ');
  Assert.IsTrue(Has(mItems, 'TBasis'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Wert'), Names(mItems));
  mItems := ItemsAt(InMethod('  case 1 of 1: '), 'of 1: ');
  Assert.IsTrue(Has(mItems, 'Wert'), Names(mItems));
end;

procedure TLspCompletionContextTests.IsNotAndNotInBehave;
var
  mItems: TCompletionItems;
begin
  // Delphi 13: "is not" erwartet einen Typ.
  mItems := ItemsAt(InMethod('  if Wert is not '), 'is not ');
  Assert.IsTrue(Has(mItems, 'TFoo'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Wert'), Names(mItems));
  mItems := ItemsAt(InMethod('  if Wert is '), 'is ');
  Assert.IsTrue(Has(mItems, 'TBasis'), Names(mItems));
  Assert.IsFalse(Has(mItems, 'Rechne'), Names(mItems));
  // "not in" erwartet eine Menge: keine Einschränkung auf Typen.
  mItems := ItemsAt(InMethod('  if 1 not in '), 'not in ');
  Assert.IsTrue(Has(mItems, 'Wert'), Names(mItems));
end;

procedure TLspCompletionContextTests.NothingInMultiLineString;
var
  mText: string;
begin
  // Mehrzeiliger String (ab Delphi 12): mitten darin nichts anbieten, dahinter wieder.
  mText := InMethod('  Name := '''''''#10'    We'#10'    ''''''; We');
  Assert.AreEqual('', Names(ItemsAt(mText, '    We')));
  Assert.AreEqual('Wert', Names(ItemsAt(mText, '; We')));
end;

procedure TLspCompletionContextTests.PropertyReadOffersMatchingGetters;
const
  cText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '  strict private'#10 +
    '    FWert: Integer;'#10 +
    '    FName: string;'#10 +
    '    function GetWert: Integer;'#10 +
    '    function GetItem(I: Integer): string;'#10 +
    '    procedure SetWert(A: Integer);'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '    property Items[I: Integer]: string read '#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
begin
  mTree := TPascalParser.Parse(cText);
  try
    Assert.IsTrue(PropertyAt(LookupOf(FResolver, nil, mTree, cText, nil),
      PositionOf(cText, 'Wert: Integer read '), TCompletionMatching.Prefix, mItems));
    // Felder und Funktionen vom Typ Integer, auch geerbte (Zaehler, Anzahl); kein string, kein Setter.
    Assert.AreEqual('FWert GetWert Zaehler Anzahl', Names(mItems));
    Assert.IsTrue(PropertyAt(LookupOf(FResolver, nil, mTree, cText, nil),
      PositionOf(cText, 'string read '), TCompletionMatching.Prefix, mItems));
    // Dazu „GetItems anlegen“ (#467) oben; ein Feld gibt es zu Indexeigenschaften nicht.
    Assert.AreEqual('GetItems anlegen GetItem', Names(mItems));
    // Außerhalb einer property-Zeile kein Kontext.
    Assert.IsFalse(PropertyAt(LookupOf(FResolver, nil, mTree, cText, nil),
      PositionOf(cText, 'FWert: '), TCompletionMatching.Prefix, mItems));
  finally
    mTree.Free;
  end;
end;

procedure TLspCompletionContextTests.PropertyWriteOffersMatchingSetters;
const
  cText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    function GetWert: Integer;'#10 +
    '    procedure SetWert(A: Integer);'#10 +
    '    procedure SetName(const A: string);'#10 +
    '  public'#10 +
    '    property Wert: Integer read GetWert write Se'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
begin
  mTree := TPascalParser.Parse(cText);
  try
    Assert.IsTrue(PropertyAt(LookupOf(FResolver, nil, mTree, cText, nil),
      PositionOf(cText, 'write Se'), TCompletionMatching.Prefix, mItems));
    Assert.AreEqual('SetWert', Names(mItems));
  finally
    mTree.Free;
  end;
end;

const
  cUnitEigenschaft =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Caption: string read Ca'#10 +
    '    property Titel: string read FName write '#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

/// <summary>Einträge nach "read Ca" bzw. "write " in UnitEigenschaft mit ASettings.</summary>
function AccessorItemsAt(AResolver: TNameResolver; const AMarker: string;
  const ASettings: TCompletionSettings): TCompletionItems;
var
  mRequest: TCompletionRequest;
  mTree: TSyntaxTree;
  mLines: TArray<string>;
  mLine: Integer;
  mPosition: TTextPosition;
begin
  mLines := string(cUnitEigenschaft).Split([#10]);
  mPosition := TTextPosition.Create(0, 0);
  for mLine := 0 to High(mLines) do
  begin
    if Pos(AMarker, mLines[mLine]) > 0 then
    begin
      mPosition := TTextPosition.Create(mLine, Pos(AMarker, mLines[mLine]) - 1 + Length(AMarker));
    end;
  end;
  mTree := TPascalParser.Parse(cUnitEigenschaft);
  mRequest := TCompletionRequest.Create(cUnitEigenschaft, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := AResolver;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    Assert.IsTrue(TCompletionDeclarations.PropertyItems(mRequest, Result));
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

procedure TLspCompletionContextTests.PropertyOffersAccessorCreation;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mEdit: TTextEdit;
  mInserted: string;
begin
  // #467: Nach "read Ca" stehen „Feld FCaption anlegen“ und „GetCaption anlegen“ oben.
  mItems := AccessorItemsAt(FResolver, 'read Ca', TCompletionSettings.Default);
  Assert.AreEqual('Feld FCaption anlegen GetCaption anlegen', Names(mItems));
  mItem := mItems.Items[0];
  Assert.AreEqual('create', mItem.Action);
  Assert.IsTrue(mItem.Pinned);
  Assert.AreEqual('FCaption: string;', mItem.Detail);
  // "Ca" wird zu "FCaption"; das Feld kommt hinter FName.
  Assert.IsTrue(mItem.HasTextEdit);
  Assert.AreEqual('FCaption', mItem.TextEdit.NewText);
  Assert.AreEqual(Integer(7), mItem.TextEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(34), mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(Integer(36), mItem.TextEdit.Range.EndPos.Character);
  Assert.AreEqual(Integer(1), Integer(Length(mItem.AdditionalEdits)));
  Assert.AreEqual(#10'    FCaption: string;', mItem.AdditionalEdits[0].NewText);
  // Der Getter hat Deklaration und Rumpf.
  mInserted := '';
  for mEdit in mItems.Items[1].AdditionalEdits do
  begin
    mInserted := mInserted + mEdit.NewText;
  end;
  Assert.Contains(mInserted, 'function GetCaption: string;');
  Assert.Contains(mInserted, 'function TFoo.GetCaption: string;');
  // Nach "write " ohne Feld FTitel: „Feld FTitel anlegen“, „SetTitel anlegen“ legt das Feld mit an; danach das
  // vorhandene Feld FName.
  mItems := AccessorItemsAt(FResolver, 'FName write ', TCompletionSettings.Default);
  Assert.AreEqual('Feld FTitel anlegen SetTitel anlegen FName', Names(mItems));
  Assert.AreEqual('procedure SetTitel(const Value: string); + FTitel: string;', mItems.Items[1].Detail);
end;

procedure TLspCompletionContextTests.AccessorCreationFollowsSettings;
var
  mSettings: TCompletionSettings;
  mItems: TCompletionItems;
  mEdit: TTextEdit;
  mInserted: string;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.AccessorSection := TCompletionAccessorSection.Protected;
  mItems := AccessorItemsAt(FResolver, 'read Ca', mSettings);
  mInserted := '';
  for mEdit in mItems.Items[1].AdditionalEdits do
  begin
    mInserted := mInserted + mEdit.NewText;
  end;
  // Kein protected vor der Eigenschaft: eigener Abschnitt, danach weiter public.
  Assert.Contains(mInserted, '  protected'#10'    function GetCaption: string;'#10'  public'#10);
  // Abgeschaltet: nur vorhandene Mitglieder.
  mSettings.CreateAccessors := False;
  mItems := AccessorItemsAt(FResolver, 'read Ca', mSettings);
  Assert.AreEqual('', Names(mItems));
end;

procedure TLspCompletionContextTests.OverrideKeywordOffersVirtualMethods;
const
  cText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '  public'#10 +
    '    override '#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Frei;'#10 +
    'begin'#10 +
    '  override '#10 +
    'end;'#10 +
    'end.';
var
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
begin
  mTree := TPascalParser.Parse(cText);
  try
    Assert.IsTrue(OverrideAt(LookupOf(FResolver, nil, mTree, cText,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitBasis;
        Result := SameText(AFileName, cBasisFile);
      end),
      PositionOf(cText, '    override '), mItems));
    Assert.AreEqual('Geschuetzt Oeffentlich', Names(mItems));
    Assert.IsTrue(mItems.Items[1].HasTextEdit);
    Assert.AreEqual('procedure Oeffentlich; override;', mItems.Items[1].TextEdit.NewText);
    Assert.AreEqual(4, mItems.Items[1].TextEdit.Range.StartPos.Character);
    Assert.AreEqual('override Oeffentlich', mItems.Items[1].FilterText);
    // In einem Routinenrumpf kein Override-Kontext.
    Assert.IsFalse(OverrideAt(LookupOf(FResolver, nil, mTree, cText, nil),
      PositionOf(cText,
      'begin'#10'  override '), mItems));
  finally
    mTree.Free;
  end;
end;

procedure TLspCompletionContextTests.KeywordsFitThePlace;
var
  mText: string;
begin
  // Anweisung.
  Assert.IsTrue(Has(ItemsAt(InMethod('  beg'), '  beg'), 'begin'));
  Assert.IsTrue(Has(ItemsAt(InMethod('  tr'), '  tr'), 'try'));
  Assert.IsFalse(Has(ItemsAt(InMethod('  prop'), '  prop'), 'property'));
  // Klassenrumpf.
  mText := StringReplace(cUnitHaupt, '    Name: string;', '    prop', []);
  Assert.IsTrue(Has(ItemsAt(mText, '    prop'), 'property'));
  mText := StringReplace(cUnitHaupt, '    Name: string;', '    tr', []);
  Assert.IsFalse(Has(ItemsAt(mText, '    tr'), 'try'));
  // Deklarationsteil.
  mText := StringReplace(cUnitHaupt, 'procedure Frei;', 'proc'#10'procedure Frei;', []);
  Assert.IsTrue(Has(ItemsAt(mText, #10'proc'), 'procedure'));
  mText := StringReplace(cUnitHaupt, 'procedure Frei;', 'tr'#10'procedure Frei;', []);
  Assert.IsFalse(Has(ItemsAt(mText, #10'tr'), 'try'));
  // Ohne Eingabe keine Schlüsselwörter.
  Assert.IsFalse(Has(ItemsAt(InMethod('  '), #10'begin'#10'  '), 'begin'));
end;

procedure TLspCompletionContextTests.DocumentationFollowsClientFormat;
var
  mParams, mDetails: TJSONObject;
  mDocumentation: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{"completion":{"completionItem":' +
    '{"documentationFormat":["plaintext"]}}}}}') as TJSONObject;
  try
    Assert.IsFalse(TCompletionDetails.ClientPrefersMarkdown(mParams), 'plaintext');
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{"completion":{"completionItem":' +
    '{"documentationFormat":["markdown","plaintext"]}}}}}') as TJSONObject;
  try
    Assert.IsTrue(TCompletionDetails.ClientPrefersMarkdown(mParams), 'markdown');
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TCompletionDetails.ClientPrefersMarkdown(nil));
  mDetails := TJSONObject.Create;
  try
    mDetails.AddPair('summary', 'Kurz');
    mDetails.AddPair('documentationText', 'Kurz'#10'Mehr Text');
    mDetails.AddPair('documentationMarkdown', '**Kurz**');
    // Klartext: ganzer Text als String.
    mDocumentation := TCompletionDetails.ResolveDocumentation(mDetails, False);
    try
      Assert.IsTrue(mDocumentation is TJSONString, 'Klartext als String');
      Assert.AreEqual('Kurz'#10'Mehr Text', mDocumentation.Value);
    finally
      mDocumentation.Free;
    end;
    // Markdown: MarkupContent.
    mDocumentation := TCompletionDetails.ResolveDocumentation(mDetails, True);
    try
      Assert.AreEqual('markdown', (mDocumentation as TJSONObject).GetValue<string>('kind'));
      Assert.AreEqual('**Kurz**', (mDocumentation as TJSONObject).GetValue<string>('value'));
    finally
      mDocumentation.Free;
    end;
  finally
    mDetails.Free;
  end;
  Assert.IsNull(TCompletionDetails.ResolveDocumentation(nil, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionContextTests);

end.
