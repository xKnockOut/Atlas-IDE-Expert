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
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest;

const
  HauptFile = 'C:\P\Haupt.pas';
  BasisFile = 'C:\P\Basis.pas';

  UnitBasis =
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

  UnitHaupt =
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

function InMethod(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Methode }', ACode, []);
end;

function InRoutine(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Frei }', ACode, []);
end;

{ TLspCompletionContextTests }

procedure TLspCompletionContextTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionContextTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspCompletionContextTests.ItemsAt(const AText, AMarker: string): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(AText, AMarker),
      TCompletionMatching.Prefix);
  finally
    Tree.Free;
  end;
end;

function TLspCompletionContextTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := Result.Trim;
end;

function TLspCompletionContextTests.Has(const AItems: TCompletionItems; const AName: string): Boolean;
var
  Item: TCompletionItem;
begin
  Result := False;
  for Item in AItems.Items do
    if SameText(Item.Name, AName) then
      Exit(True);
end;

procedure TLspCompletionContextTests.PrivateFieldOfOtherUnitIsHidden;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(InRoutine('  Fremd.'), 'Fremd.');
  Assert.IsTrue(Has(Items, 'Oeffentlich'), Names(Items));
  Assert.IsTrue(Has(Items, 'Zaehler'), Names(Items));
  // private aus einer anderen Unit nie, protected außerhalb von Nachfahren nicht.
  Assert.IsFalse(Has(Items, 'FGeheim'), Names(Items));
  Assert.IsFalse(Has(Items, 'Geschuetzt'), Names(Items));
end;

procedure TLspCompletionContextTests.ProtectedOnlyInDescendants;
var
  Items: TCompletionItems;
begin
  // In einer Methode des Nachfahren ist protected sichtbar, private weiterhin nicht.
  Items := ItemsAt(InMethod('  Self.'), 'Self.');
  Assert.IsTrue(Has(Items, 'Geschuetzt'), Names(Items));
  Assert.IsFalse(Has(Items, 'FGeheim'), Names(Items));
end;

procedure TLspCompletionContextTests.InheritedOffersAncestorMethodsOnly;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(InMethod('  inherited '), 'inherited ');
  Assert.AreEqual('Geschuetzt Oeffentlich Anzahl', Names(Items));
  Assert.AreEqual(1, Items.Items[0].Depth);
  // Weder lokale Variablen, Felder noch Routinen der Unit; außerhalb einer Methode nichts.
  Assert.IsFalse(Has(Items, 'Wert'), Names(Items));
  Assert.IsFalse(Has(Items, 'Zaehler'), Names(Items));
  Assert.IsFalse(Has(Items, 'Rechne'), Names(Items));
  Assert.AreEqual('', Names(ItemsAt(InRoutine('  inherited '), 'inherited ')));
end;

procedure TLspCompletionContextTests.ClassAncestorListOffersTypesOnly;
var
  Text: string;
  Items: TCompletionItems;
begin
  Text := StringReplace(UnitHaupt, '  TFoo = class(TBasis)', '  TNeu = class('#10'  end;'#10 +
    '  TFoo = class(TBasis)', []);
  Items := ItemsAt(Text, 'TNeu = class(');
  Assert.IsTrue(Has(Items, 'TBasis'), Names(Items));
  Assert.IsTrue(Has(Items, 'TFoo'), Names(Items));
  Assert.IsFalse(Has(Items, 'Rechne'), Names(Items));
  Assert.IsFalse(Has(Items, 'Frei'), Names(Items));
  // Ohne "class(" im Gültigkeitsbereich auch Routinen.
  Items := ItemsAt(InMethod('  Re'), '  Re');
  Assert.IsTrue(Has(Items, 'Rechne'), Names(Items));
end;

procedure TLspCompletionContextTests.ColonInDeclarationOffersTypes;
var
  Text: string;
  Items: TCompletionItems;
begin
  Text := StringReplace(UnitHaupt, '  Wert: TBasis;', '  Wert: ', []);
  Items := ItemsAt(Text, '  Wert: ');
  Assert.IsTrue(Has(Items, 'TBasis'), Names(Items));
  Assert.IsFalse(Has(Items, 'Rechne'), Names(Items));
  Assert.IsFalse(Has(Items, 'Name'), Names(Items));
  // Typ-Schlüsselwörter nur nach ":".
  Text := StringReplace(UnitHaupt, '  Wert: TBasis;', '  Wert: str', []);
  Assert.IsTrue(Has(ItemsAt(Text, 'Wert: str'), 'string'));
  // Inline-Variable in einer Anweisung ebenfalls; case-Marke dagegen nicht.
  Items := ItemsAt(InMethod('  var X: '), 'var X: ');
  Assert.IsTrue(Has(Items, 'TBasis'), Names(Items));
  Assert.IsFalse(Has(Items, 'Wert'), Names(Items));
  Items := ItemsAt(InMethod('  case 1 of 1: '), 'of 1: ');
  Assert.IsTrue(Has(Items, 'Wert'), Names(Items));
end;

procedure TLspCompletionContextTests.IsNotAndNotInBehave;
var
  Items: TCompletionItems;
begin
  // Delphi 13: "is not" erwartet einen Typ.
  Items := ItemsAt(InMethod('  if Wert is not '), 'is not ');
  Assert.IsTrue(Has(Items, 'TFoo'), Names(Items));
  Assert.IsFalse(Has(Items, 'Wert'), Names(Items));
  Items := ItemsAt(InMethod('  if Wert is '), 'is ');
  Assert.IsTrue(Has(Items, 'TBasis'), Names(Items));
  Assert.IsFalse(Has(Items, 'Rechne'), Names(Items));
  // "not in" erwartet eine Menge: keine Einschränkung auf Typen.
  Items := ItemsAt(InMethod('  if 1 not in '), 'not in ');
  Assert.IsTrue(Has(Items, 'Wert'), Names(Items));
end;

procedure TLspCompletionContextTests.NothingInMultiLineString;
var
  Text: string;
begin
  // Mehrzeiliger String (ab Delphi 12): mitten darin nichts anbieten, dahinter wieder.
  Text := InMethod('  Name := '''''''#10'    We'#10'    ''''''; We');
  Assert.AreEqual('', Names(ItemsAt(Text, '    We')));
  Assert.AreEqual('Wert', Names(ItemsAt(Text, '; We')));
end;

procedure TLspCompletionContextTests.PropertyReadOffersMatchingGetters;
const
  Text =
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
  Tree: TSyntaxTree;
  Items: TCompletionItems;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TLspCompletion.PropertyItems(FResolver, Tree, Text, HauptFile,
      PositionOf(Text, 'Wert: Integer read '), TCompletionMatching.Prefix, Items));
    // Felder und Funktionen vom Typ Integer, auch geerbte (Zaehler, Anzahl); kein string, kein Setter.
    Assert.AreEqual('FWert GetWert Zaehler Anzahl', Names(Items));
    Assert.IsTrue(TLspCompletion.PropertyItems(FResolver, Tree, Text, HauptFile,
      PositionOf(Text, 'string read '), TCompletionMatching.Prefix, Items));
    // Dazu „GetItems anlegen“ (#467) oben; ein Feld gibt es zu Indexeigenschaften nicht.
    Assert.AreEqual('GetItems anlegen GetItem', Names(Items));
    // Außerhalb einer property-Zeile kein Kontext.
    Assert.IsFalse(TLspCompletion.PropertyItems(FResolver, Tree, Text, HauptFile,
      PositionOf(Text, 'FWert: '), TCompletionMatching.Prefix, Items));
  finally
    Tree.Free;
  end;
end;

procedure TLspCompletionContextTests.PropertyWriteOffersMatchingSetters;
const
  Text =
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
  Tree: TSyntaxTree;
  Items: TCompletionItems;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TLspCompletion.PropertyItems(FResolver, Tree, Text, HauptFile, PositionOf(Text, 'write Se'),
      TCompletionMatching.Prefix, Items));
    Assert.AreEqual('SetWert', Names(Items));
  finally
    Tree.Free;
  end;
end;

const
  UnitEigenschaft =
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
  Request: TCompletionRequest;
  Tree: TSyntaxTree;
  Lines: TArray<string>;
  Line: Integer;
  Position: TTextPosition;
begin
  Lines := string(UnitEigenschaft).Split([#10]);
  Position := TTextPosition.Create(0, 0);
  for Line := 0 to High(Lines) do
    if Pos(AMarker, Lines[Line]) > 0 then
      Position := TTextPosition.Create(Line, Pos(AMarker, Lines[Line]) - 1 + Length(AMarker));
  Tree := TPascalParser.Parse(UnitEigenschaft);
  Request := TCompletionRequest.Create(UnitEigenschaft, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := AResolver;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Assert.IsTrue(TLspCompletion.PropertyItems(Request, Result));
  finally
    Request.Free;
    Tree.Free;
  end;
end;

procedure TLspCompletionContextTests.PropertyOffersAccessorCreation;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Edit: TTextEdit;
  Inserted: string;
begin
  // #467: Nach "read Ca" stehen „Feld FCaption anlegen“ und „GetCaption anlegen“ oben.
  Items := AccessorItemsAt(FResolver, 'read Ca', TCompletionSettings.Default);
  Assert.AreEqual('Feld FCaption anlegen GetCaption anlegen', Names(Items));
  Item := Items.Items[0];
  Assert.AreEqual('create', Item.Action);
  Assert.IsTrue(Item.Pinned);
  Assert.AreEqual('FCaption: string;', Item.Detail);
  // "Ca" wird zu "FCaption"; das Feld kommt hinter FName.
  Assert.IsTrue(Item.HasTextEdit);
  Assert.AreEqual('FCaption', Item.TextEdit.NewText);
  Assert.AreEqual(Integer(7), Item.TextEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(34), Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(Integer(36), Item.TextEdit.Range.EndPos.Character);
  Assert.AreEqual(Integer(1), Integer(Length(Item.AdditionalEdits)));
  Assert.AreEqual(#10'    FCaption: string;', Item.AdditionalEdits[0].NewText);
  // Der Getter hat Deklaration und Rumpf.
  Inserted := '';
  for Edit in Items.Items[1].AdditionalEdits do
    Inserted := Inserted + Edit.NewText;
  Assert.Contains(Inserted, 'function GetCaption: string;');
  Assert.Contains(Inserted, 'function TFoo.GetCaption: string;');
  // Nach "write " ohne Feld FTitel: „Feld FTitel anlegen“, „SetTitel anlegen“ legt das Feld mit an; danach das
  // vorhandene Feld FName.
  Items := AccessorItemsAt(FResolver, 'FName write ', TCompletionSettings.Default);
  Assert.AreEqual('Feld FTitel anlegen SetTitel anlegen FName', Names(Items));
  Assert.AreEqual('procedure SetTitel(const Value: string); + FTitel: string;', Items.Items[1].Detail);
end;

procedure TLspCompletionContextTests.AccessorCreationFollowsSettings;
var
  Settings: TCompletionSettings;
  Items: TCompletionItems;
  Edit: TTextEdit;
  Inserted: string;
begin
  Settings := TCompletionSettings.Default;
  Settings.AccessorSection := TCompletionAccessorSection.Protected;
  Items := AccessorItemsAt(FResolver, 'read Ca', Settings);
  Inserted := '';
  for Edit in Items.Items[1].AdditionalEdits do
    Inserted := Inserted + Edit.NewText;
  // Kein protected vor der Eigenschaft: eigener Abschnitt, danach weiter public.
  Assert.Contains(Inserted, '  protected'#10'    function GetCaption: string;'#10'  public'#10);
  // Abgeschaltet: nur vorhandene Mitglieder.
  Settings.CreateAccessors := False;
  Items := AccessorItemsAt(FResolver, 'read Ca', Settings);
  Assert.AreEqual('', Names(Items));
end;

procedure TLspCompletionContextTests.OverrideKeywordOffersVirtualMethods;
const
  Text =
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
  Tree: TSyntaxTree;
  Items: TCompletionItems;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TLspCompletion.OverrideItems(FResolver, Tree, Text, HauptFile, PositionOf(Text, '    override '),
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, BasisFile);
      end, Items));
    Assert.AreEqual('Geschuetzt Oeffentlich', Names(Items));
    Assert.IsTrue(Items.Items[1].HasTextEdit);
    Assert.AreEqual('procedure Oeffentlich; override;', Items.Items[1].TextEdit.NewText);
    Assert.AreEqual(4, Items.Items[1].TextEdit.Range.StartPos.Character);
    Assert.AreEqual('override Oeffentlich', Items.Items[1].FilterText);
    // In einem Routinenrumpf kein Override-Kontext.
    Assert.IsFalse(TLspCompletion.OverrideItems(FResolver, Tree, Text, HauptFile, PositionOf(Text,
      'begin'#10'  override '), nil, Items));
  finally
    Tree.Free;
  end;
end;

procedure TLspCompletionContextTests.KeywordsFitThePlace;
var
  Text: string;
begin
  // Anweisung.
  Assert.IsTrue(Has(ItemsAt(InMethod('  beg'), '  beg'), 'begin'));
  Assert.IsTrue(Has(ItemsAt(InMethod('  tr'), '  tr'), 'try'));
  Assert.IsFalse(Has(ItemsAt(InMethod('  prop'), '  prop'), 'property'));
  // Klassenrumpf.
  Text := StringReplace(UnitHaupt, '    Name: string;', '    prop', []);
  Assert.IsTrue(Has(ItemsAt(Text, '    prop'), 'property'));
  Text := StringReplace(UnitHaupt, '    Name: string;', '    tr', []);
  Assert.IsFalse(Has(ItemsAt(Text, '    tr'), 'try'));
  // Deklarationsteil.
  Text := StringReplace(UnitHaupt, 'procedure Frei;', 'proc'#10'procedure Frei;', []);
  Assert.IsTrue(Has(ItemsAt(Text, #10'proc'), 'procedure'));
  Text := StringReplace(UnitHaupt, 'procedure Frei;', 'tr'#10'procedure Frei;', []);
  Assert.IsFalse(Has(ItemsAt(Text, #10'tr'), 'try'));
  // Ohne Eingabe keine Schlüsselwörter.
  Assert.IsFalse(Has(ItemsAt(InMethod('  '), #10'begin'#10'  '), 'begin'));
end;

procedure TLspCompletionContextTests.DocumentationFollowsClientFormat;
var
  Params, Details: TJSONObject;
  Documentation: TJSONValue;
begin
  Params := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{"completion":{"completionItem":' +
    '{"documentationFormat":["plaintext"]}}}}}') as TJSONObject;
  try
    Assert.IsFalse(TLspCompletion.ClientPrefersMarkdown(Params), 'plaintext');
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"capabilities":{"textDocument":{"completion":{"completionItem":' +
    '{"documentationFormat":["markdown","plaintext"]}}}}}') as TJSONObject;
  try
    Assert.IsTrue(TLspCompletion.ClientPrefersMarkdown(Params), 'markdown');
  finally
    Params.Free;
  end;
  Assert.IsFalse(TLspCompletion.ClientPrefersMarkdown(nil));
  Details := TJSONObject.Create;
  try
    Details.AddPair('summary', 'Kurz');
    Details.AddPair('documentationText', 'Kurz'#10'Mehr Text');
    Details.AddPair('documentationMarkdown', '**Kurz**');
    // Klartext: ganzer Text als String.
    Documentation := TLspCompletion.ResolveDocumentation(Details, False);
    try
      Assert.IsTrue(Documentation is TJSONString, 'Klartext als String');
      Assert.AreEqual('Kurz'#10'Mehr Text', Documentation.Value);
    finally
      Documentation.Free;
    end;
    // Markdown: MarkupContent.
    Documentation := TLspCompletion.ResolveDocumentation(Details, True);
    try
      Assert.AreEqual('markdown', (Documentation as TJSONObject).GetValue<string>('kind'));
      Assert.AreEqual('**Kurz**', (Documentation as TJSONObject).GetValue<string>('value'));
    finally
      Documentation.Free;
    end;
  finally
    Details.Free;
  end;
  Assert.IsNull(TLspCompletion.ResolveDocumentation(nil, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionContextTests);

end.
