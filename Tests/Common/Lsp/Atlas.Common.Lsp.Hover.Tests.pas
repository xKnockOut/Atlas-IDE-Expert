unit Atlas.Common.Lsp.Hover.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hover;

type
  [TestFixture]
  TLspHoverTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function InfoAt(const AMarker: string; AOccurrence: Integer = 1): THoverInfo;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsDeclarationAndDocumentation;
    [Test]
    procedure ShowsMembersFromOtherUnits;
    [Test]
    procedure ShowsLocals;
    [Test]
    procedure ShowsUnitNames;
    [Test]
    procedure NothingForUnknownNames;
    [Test]
    procedure FormatsParameterDocumentation;
    [Test]
    procedure KeepsCrefNamesInDocumentation;
    [Test]
    procedure InheritsDocumentationFromAncestor;
    [Test]
    procedure WritesMarkdown;
    [Test]
    procedure WritesPlainText;
    [Test]
    procedure WritesPlainTextWithValueAndDeprecation;
    [Test]
    procedure PlainTextKeepsLiteralAsterisks;
    [Test]
    procedure AtlasPartsForTooltip;
    [Test]
    procedure DetectsMarkdownSupport;
    [Test]
    procedure LinksLibrarySymbolsToDocWiki;
    [Test]
    procedure ShowsNumberNotations;
    [Test]
    procedure ShowsConstantAndEnumValues;
    [Test]
    procedure ShowsDeprecation;
    /// <summary>#38: Elemente von Mengenkonstanten, Basistyp und Anzahl bei Mengentypen, Text von
    /// Resourcestrings auch an der Verwendungsstelle.</summary>
    [Test]
    procedure ShowsSetsAndResourceStrings;
    [Test]
    procedure HintsUnknownDataFieldNames;
    /// <summary>#1123: Begründung über der Deklaration und im Rumpf der Implementierung.</summary>
    [Test]
    procedure ShowsRationaleOfDeclarationAndBody;
    [Test]
    procedure ShowsRationaleOfUnit;
    [Test]
    procedure WritesRationale;
    /// <summary>Neu zugewiesene Namen nennen Ziel, Zahl und Zeilen der Zuweisungen (#712).</summary>
    [Test]
    procedure ReassignedNamesInAtlasPart;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Lsp.DocWiki;

const
  // Formulardatei für die Feldnamen (#461).
  OrdersForm =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select CUSTOMER_ID, CURRENCY from ORDERS where ID = :Id'')'#13#10 +
    '  end'#13#10 +
    '  object qryAll: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select * from ORDERS'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  WerkzeugFile = 'C:\P\Werkzeug.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    '// NOTE: Nur fuer die Tests.'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '    // WHY: Ganzzahlen genuegen, siehe #312.'#10 +
    '    /// <summary>Addiert zwei Zahlen.</summary>'#10 +
    '    /// <param name="A">Erster Wert</param>'#10 +
    '    function Summe(A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen, Blau);'#10 +
    '  TDBGridFilter = class'#10 +
    '  end;'#10 +
    '  TDBGridFilterColumns = class'#10 +
    '    /// <summary>'#10 +
    '    ///   Erstellt die Collection und bindet sie an den besitzenden'#10 +
    '    ///   <see cref="TDBGridFilter"/>.'#10 +
    '    /// </summary>'#10 +
    '    /// <param name="AOwner">Der besitzende TDBGridFilter.</param>'#10 +
    '    constructor Create(AOwner: TDBGridFilter);'#10 +
    '  end;'#10 +
    '  EZeichnen = class'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '    /// <summary>Zeichnet <paramref name="X"/>.</summary>'#10 +
    '    /// <param name="X">Breite</param>'#10 +
    '    /// <exception cref="EZeichnen">Bei Fehlern.</exception>'#10 +
    '    procedure Zeichne(X: Integer); virtual;'#10 +
    '  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10 +
    '    /// <inheritdoc/>'#10 +
    '    /// <remarks>Eigene Bemerkung.</remarks>'#10 +
    '    procedure Zeichne(X: Integer); override;'#10 +
    '  end;'#10 +
    'const'#10 +
    '  Grenze = $10;'#10 +
    'procedure Alt; deprecated ''Neu verwenden'';'#10 +
    'implementation'#10 +
    'procedure Alt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TRechner.Summe(A, B: Integer): Integer;'#10 +
    'begin'#10 +
    '  // HACK: Ueberlauf wird nicht geprueft.'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'implementation'#10 +
    '/// Zählt die Aufrufe.'#10 +
    'var Zaehler: Integer;'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  R: TRechner;'#10 +
    '  F: TDBGridFilterColumns;'#10 +
    '  D: TAbgeleitet;'#10 +
    'begin'#10 +
    '  Zaehler := R.Summe(1, 2);'#10 +
    '  F := TDBGridFilterColumns.Create(nil);'#10 +
    '  D.Zeichne(1);'#10 +
    '  Zaehler := Grenze + Ord(Blau) + 255;'#10 +
    '  Alt;'#10 +
    '  Unbekannt;'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := Pos(AMarker, AText, Index + 1);
    if Index = 0 then
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TLspHoverTests }

procedure TLspHoverTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHoverTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHoverTests.InfoAt(const AMarker: string; AOccurrence: Integer): THoverInfo;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspHover.InfoAt(FResolver, FIndex, Tree, UnitHaupt, 'C:\P\Haupt.pas',
      PositionOf(UnitHaupt, AMarker, AOccurrence),
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, WerkzeugFile);
        AText := UnitWerkzeug;
      end);
  finally
    Tree.Free;
  end;
end;

procedure TLspHoverTests.ShowsDeclarationAndDocumentation;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Zaehler :=');
  Assert.AreEqual('Zaehler: Integer;', Info.Declaration);
  Assert.AreEqual('Zählt die Aufrufe.', Info.Documentation);
  Assert.AreEqual('', Info.UnitName);
end;

procedure TLspHoverTests.ShowsMembersFromOtherUnits;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Summe');
  Assert.AreEqual('function Summe(A, B: Integer): Integer;', Info.Declaration);
  Assert.AreEqual('Addiert zwei Zahlen.'#10#10'*A*: Erster Wert', Info.Documentation);
  Assert.AreEqual('Werkzeug', Info.UnitName);
  // Eigene Units haben keine DocWiki-Seite.
  Assert.AreEqual('', Info.DocWikiUrl);
end;

procedure TLspHoverTests.ShowsLocals;
var
  Info: THoverInfo;
begin
  Info := InfoAt('R.Summe');
  Assert.AreEqual('R: TRechner;', Info.Declaration);
end;

procedure TLspHoverTests.ShowsUnitNames;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Werkzeug;');
  Assert.AreEqual('unit Werkzeug;', Info.Declaration);
end;

procedure TLspHoverTests.NothingForUnknownNames;
begin
  Assert.IsFalse(InfoAt('Unbekannt').Found);
end;

procedure TLspHoverTests.FormatsParameterDocumentation;
var
  Info: THoverInfo;
begin
  Info := Default(THoverInfo);
  Info.Declaration := 'procedure P(X: Integer);';
  Info.Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(['  /// <summary>Kurz.', '  /// Lang.</summary>',
    '/// <param name="X">Wert</param>', 'procedure P(X: Integer);'], 3));
  Info.Documentation := Info.Doc.ToMarkdown;
  Assert.AreEqual('Kurz. Lang.'#10#10'*X*: Wert', Info.Documentation);
  Assert.AreEqual('procedure P(X: Integer);'#10#10'Kurz. Lang.'#10#10'X: Wert', Info.ToPlainText);
  Assert.IsTrue(TXmlDoc.Parse(TXmlDoc.CommentAbove(['// kein Doku-Kommentar', 'procedure P;'], 1)).IsEmpty);
end;

procedure TLspHoverTests.KeepsCrefNamesInDocumentation;
var
  Info: THoverInfo;
  Json, Section, Run: TJSONObject;
begin
  // Beispiel aus #654: Der Name aus <see cref> fehlte.
  Info := InfoAt('Create(nil)');
  Assert.AreEqual('constructor Create(AOwner: TDBGridFilter);', Info.Declaration);
  Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden TDBGridFilter.', Info.Doc.Summary);
  Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden `TDBGridFilter`.'#10#10 +
    '*AOwner*: Der besitzende TDBGridFilter.', Info.Documentation);
  Assert.AreEqual(1, Integer(Length(Info.DocTargets)));
  Assert.AreEqual('TDBGridFilter', Info.DocTargets[0].Name);
  Assert.AreEqual(WerkzeugFile, Info.DocTargets[0].FileName);
  Assert.AreEqual(PositionOf(UnitWerkzeug, 'TDBGridFilter = class', 1).Line, Info.DocTargets[0].Line);
  // Klartext (GetHintText) mit dem Namen.
  Assert.IsTrue(Pos('besitzenden TDBGridFilter.', Info.ToPlainText) > 0, Info.ToPlainText);
  Json := TLspHover.AtlasJson(Info);
  try
    Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden TDBGridFilter.'#10#10 +
      'AOwner: Der besitzende TDBGridFilter.', Json.GetValue<string>('documentationText'));
    Section := Json.GetValue<TJSONArray>('documentation.sections').Items[0] as TJSONObject;
    Assert.AreEqual('summary', Section.GetValue<string>('kind'));
    Run := (Section.GetValue('runs') as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('ref', Run.GetValue<string>('kind'));
    Assert.AreEqual('TDBGridFilter', Run.GetValue<string>('text'));
    Assert.AreEqual(WerkzeugFile, Run.GetValue<string>('file'));
    Assert.AreEqual(PositionOf(UnitWerkzeug, 'TDBGridFilter = class', 1).Line, Run.GetValue<Integer>('line'));
    Section := Json.GetValue<TJSONArray>('documentation.sections').Items[1] as TJSONObject;
    Assert.AreEqual('param', Section.GetValue<string>('kind'));
    Assert.AreEqual('AOwner', Section.GetValue<string>('name'));
  finally
    Json.Free;
  end;
end;

procedure TLspHoverTests.InheritsDocumentationFromAncestor;
var
  Info: THoverInfo;
  Json, Section: TJSONObject;
begin
  Info := InfoAt('Zeichne(1)');
  Assert.AreEqual('procedure Zeichne(X: Integer); override;', Info.Declaration);
  Assert.AreEqual('Zeichnet X.', Info.Doc.Summary);
  Assert.AreEqual('Breite', Info.Doc.Params[0].Text);
  Assert.AreEqual('EZeichnen', Info.Doc.Exceptions[0].Name);
  Assert.AreEqual('Eigene Bemerkung.', Info.Doc.Remarks);
  Assert.IsFalse(Info.Doc.InheritDoc);
  Json := TLspHover.AtlasJson(Info);
  try
    Section := Json.GetValue<TJSONArray>('documentation.sections').Items[2] as TJSONObject;
    Assert.AreEqual('exception', Section.GetValue<string>('kind'));
    Assert.AreEqual(PositionOf(UnitWerkzeug, 'EZeichnen = class', 1).Line, Section.GetValue<Integer>('ref.line'));
  finally
    Json.Free;
  end;
end;

procedure TLspHoverTests.WritesMarkdown;
var
  Info: THoverInfo;
begin
  Info.Declaration := 'procedure P;';
  Info.Documentation := 'Tut etwas.';
  Info.UnitName := 'U';
  Assert.AreEqual('```pascal'#10'procedure P;'#10'```'#10#10'Tut etwas.'#10#10'Unit `U`', Info.ToMarkdown);
end;

procedure TLspHoverTests.WritesPlainText;
var
  Info: THoverInfo;
begin
  Info.Declaration := 'procedure P(X: Integer);';
  Info.Documentation := 'Tut etwas.'#10#10'*X*: Wert';
  Info.UnitName := 'U';
  Info.DocWikiUrl := 'https://docwiki.example/P';
  Assert.AreEqual('procedure P(X: Integer);'#10#10'Tut etwas.'#10#10'X: Wert'#10#10'Unit U'#10#10 +
    'DocWiki: https://docwiki.example/P', Info.ToPlainText);
end;

procedure TLspHoverTests.WritesPlainTextWithValueAndDeprecation;
var
  Info: THoverInfo;
begin
  Info.Declaration := 'Max = 10;';
  Info.Deprecation := '**Veraltet**';
  Info.Value := '10';
  Info.Messages := '`WM_PAINT`';
  Assert.AreEqual('Max = 10;'#10#10'Veraltet'#10#10'Wert: 10'#10#10'WM_PAINT', Info.ToPlainText);
end;

procedure TLspHoverTests.AtlasPartsForTooltip;
var
  Info: THoverInfo;
  Json, Member: TJSONObject;
begin
  Info := Default(THoverInfo);
  Info.Declaration := 'procedure BeginUpdate;';
  Info.UnitName := 'System.Classes';
  Info.Documentation := 'Unterdrückt das **Neuzeichnen**.';
  Json := TLspHover.AtlasJson(Info);
  try
    Assert.AreEqual('procedure BeginUpdate;', Json.GetValue<string>('declaration'));
    Assert.AreEqual('System.Classes', Json.GetValue<string>('unit'));
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', Json.GetValue<string>('documentationText'));
    Assert.IsNull(Json.GetValue('documentation'), 'ohne XMLDoc keine Struktur');
    Assert.IsNull(Json.GetValue('value'), 'leere Teile entfallen');
    Assert.IsNull(Json.GetValue('published'), 'ohne Mitglieder kein published');
  finally
    Json.Free;
  end;
  // published-Mitglieder strukturiert (#110).
  SetLength(Info.PublishedItems, 1);
  Info.PublishedItems[0].Name := 'Caption';
  Info.PublishedItems[0].TypeName := 'TCaption';
  Info.PublishedItems[0].DeclaringClass := 'TControl';
  Info.DefaultProperty := 'Controls[Index: Integer]: TControl';
  Json := TLspHover.AtlasJson(Info);
  try
    Member := Json.GetValue<TJSONArray>('published.members').Items[0] as TJSONObject;
    Assert.AreEqual('Caption', Member.GetValue<string>('name'));
    Assert.AreEqual('TControl', Member.GetValue<string>('declaringClass'));
    Assert.AreEqual('Controls[Index: Integer]: TControl', Json.GetValue<string>('published.defaultProperty'));
  finally
    Json.Free;
  end;
end;

procedure TLspHoverTests.ReassignedNamesInAtlasPart;
const
  Source =
    'unit R;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(A: Integer);'#10 +
    'var'#10 +
    '  Total: Integer;'#10 +
    'begin'#10 +
    '  Total := 0;'#10 +
    '  Total := Total + A;'#10 +
    'end;'#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Info: THoverInfo;
  Json, Part: TJSONObject;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Info := Default(THoverInfo);
    Info.Declaration := 'Total: Integer;';
    TLspHover.AddReassigned(FResolver, Tree, 'C:\P\R.pas', Source, TTextPosition.Create(8, 12), Info);
    Assert.AreEqual('locals', Info.ReassignedTarget);
    Assert.AreEqual(2, Info.ReassignedWrites);
    Json := TLspHover.AtlasJson(Info);
    try
      Part := Json.GetValue('reassigned') as TJSONObject;
      Assert.IsNotNull(Part);
      Assert.AreEqual('locals', Part.GetValue('target').Value);
      Assert.AreEqual('2', Part.GetValue('writes').Value);
      Assert.AreEqual('[7,8]', Part.GetValue('lines').ToJSON);
    finally
      Json.Free;
    end;
    // A wird nur gelesen: kein Eintrag.
    Info := Default(THoverInfo);
    TLspHover.AddReassigned(FResolver, Tree, 'C:\P\R.pas', Source, TTextPosition.Create(8, 19), Info);
    Assert.AreEqual('', Info.ReassignedTarget);
    Json := TLspHover.AtlasJson(Info);
    try
      Assert.IsNull(Json.GetValue('reassigned'));
    finally
      Json.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspHoverTests.PlainTextKeepsLiteralAsterisks;
var
  Info: THoverInfo;
begin
  // In der IDE gesehen: "(Gallery.Page.*)" kam als "(Gallery.Page.)" an.
  Info := Default(THoverInfo);
  Info.Declaration := 'TFrameClass = class of TFrame;';
  Info.Deprecation := '**Veraltet**: Stattdessen TNeu';
  Info.Documentation := 'Frame einer Seite (Gallery.Page.*), a*b.'#10#10'*AName*: Der Name';
  Assert.AreEqual('TFrameClass = class of TFrame;'#10#10'Veraltet: Stattdessen TNeu'#10#10 +
    'Frame einer Seite (Gallery.Page.*), a*b.'#10#10'AName: Der Name', Info.ToPlainText);
end;

procedure TLspHoverTests.DetectsMarkdownSupport;

  function Supports(const AJson: string): Boolean;
  var
    Params: TJSONObject;
  begin
    Params := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      Result := TLspHover.ClientSupportsMarkdown(Params);
    finally
      Params.Free;
    end;
  end;

begin
  // RAD Studio meldet nur Klartext.
  Assert.IsFalse(Supports('{"capabilities": {"textDocument": {"hover": {"contentFormat": ["plaintext"]}}}}'));
  Assert.IsTrue(Supports('{"capabilities": {"textDocument": {"hover": {"contentFormat": ["markdown", "plaintext"]}}}}'));
  Assert.IsTrue(Supports('{"capabilities": {}}'));
  Assert.IsTrue(TLspHover.ClientSupportsMarkdown(nil));
end;

procedure TLspHoverTests.LinksLibrarySymbolsToDocWiki;
const
  LibFile = 'C:\Lib\Vcl.Werkzeug.pas';
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  LibText, MainText: string;
  Info: THoverInfo;
begin
  LibText := StringReplace(UnitWerkzeug, 'unit Werkzeug;', 'unit Vcl.Werkzeug;', []);
  MainText := StringReplace(UnitHaupt, 'uses Werkzeug;', 'uses Vcl.Werkzeug;', []);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(LibText, LibFile, nil));
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(MainText);
  try
    Info := TLspHover.InfoAt(Resolver, Index, Tree, MainText, 'C:\P\Haupt.pas', PositionOf(MainText, 'Summe', 1),
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, LibFile);
        AText := LibText;
      end, '23.0');
    Assert.AreEqual(TDocWiki.BaseUri + 'Athens/en/Vcl.Werkzeug.TRechner.Summe', Info.DocWikiUrl);
    Assert.IsTrue(Pos('[DocWiki](' + Info.DocWikiUrl + ')', Info.ToMarkdown) > 0);
    Info := TLspHover.InfoAt(Resolver, Index, Tree, MainText, 'C:\P\Haupt.pas',
      PositionOf(MainText, 'Vcl.Werkzeug;', 1), nil, '');
    Assert.AreEqual(TDocWiki.BaseUri + 'Florence/en/Vcl.Werkzeug', Info.DocWikiUrl);
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

procedure TLspHoverTests.ShowsNumberNotations;
var
  Info: THoverInfo;
begin
  Info := InfoAt('255');
  Assert.AreEqual('255', Info.Declaration);
  Assert.AreEqual('255 · $FF · %11111111', Info.Value);
  Assert.Contains(Info.ToMarkdown, 'Wert: `255 · $FF · %11111111`');
end;

procedure TLspHoverTests.ShowsConstantAndEnumValues;
begin
  Assert.AreEqual('16 · $10 · %10000', InfoAt('Grenze +').Value);
  Assert.AreEqual('Ord = 2', InfoAt('Blau)').Value);
end;

procedure TLspHoverTests.ShowsDeprecation;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Alt;');
  Assert.AreEqual('**Veraltet**: Neu verwenden', Info.Deprecation);
  Assert.Contains(Info.ToMarkdown, '**Veraltet**: Neu verwenden');
end;

procedure TLspHoverTests.ShowsSetsAndResourceStrings;
const
  StilFile = 'C:\P\Stile.pas';
  UnitStile =
    'unit Stile;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TStil = (sFett, sKursiv, sUnter);'#10 +
    '  TStile = set of TStil;'#10 +
    'const'#10 +
    '  Standard: TStile = [sFett,'#10 +
    '    sKursiv];'#10 +
    'resourcestring'#10 +
    '  SGruss = ''Hallo'' + #13#10 +'#10 +
    '    ''Welt'';'#10 +
    'implementation'#10 +
    'end.';
  MainText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Stile;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  S: TStile;'#10 +
    'begin'#10 +
    '  S := Standard;'#10 +
    '  Writeln(SGruss);'#10 +
    'end;'#10 +
    'end.';
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  ReadText: THoverReadText;

  function At(const AMarker: string): THoverInfo;
  begin
    Result := TLspHover.InfoAt(Resolver, Index, Tree, MainText, 'C:\P\Haupt.pas', PositionOf(MainText, AMarker, 1),
      ReadText, '');
  end;

begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitStile, StilFile, nil));
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(MainText);
  ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, StilFile);
      AText := UnitStile;
    end;
  try
    Assert.AreEqual('[sFett, sKursiv] · 2 Elemente', At('Standard;').Value);
    Assert.AreEqual('set of TStil · 3 mögliche Elemente', At('TStile;').Value);
    Assert.AreEqual('''Hallo⏎Welt''', At('SGruss)').Value);
    Assert.Contains(At('SGruss)').ToMarkdown, 'Wert: `''Hallo⏎Welt''`');
  finally
    ReadText := nil;
    Tree.Free;
    Resolver.Free;
  end;
end;

procedure TLspHoverTests.HintsUnknownDataFieldNames;

  function Hint(const ALine: string; out AText: string): Boolean;
  begin
    Result := TLspHover.DataNameHint(nil, 'unit Orders;'#13#10'{$R *.dfm}'#13#10 + ALine + #13#10, 'C:\P\Orders.pas',
      TTextPosition.Create(2, Pos('''', ALine) + 1),
      function(const AFileName: string; out AFormText: string): Boolean
      begin
        AFormText := OrdersForm;
        Result := SameText(ExtractFileExt(AFileName), '.dfm');
      end, AText);
  end;

var
  Text: string;
begin
  Assert.IsTrue(Hint('  qryOrders.FieldByName(''CUSTOMR_ID'').AsInteger;', Text));
  Assert.AreEqual('Feld nicht gefunden in qryOrders', Text);
  Assert.IsTrue(Hint('  qryOrders.ParamByName(''Kunde'').AsInteger := 1;', Text));
  Assert.AreEqual('Parameter nicht gefunden in qryOrders', Text);
  // Bekannte Namen, select * ohne Schema und zur Laufzeit erzeugte Datenmengen: kein Hinweis.
  Assert.IsFalse(Hint('  qryOrders.FieldByName(''currency'').AsString;', Text));
  Assert.IsFalse(Hint('  qryAll.FieldByName(''IRGENDWAS'').AsString;', Text));
  Assert.IsFalse(Hint('  qryLaufzeit.FieldByName(''IRGENDWAS'').AsString;', Text));
end;

procedure TLspHoverTests.ShowsRationaleOfDeclarationAndBody;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Summe');
  Assert.AreEqual(2, Integer(Length(Info.Rationale)));
  Assert.AreEqual('WHY', Info.Rationale[0].Marker);
  Assert.AreEqual('Ganzzahlen genuegen, siehe #312.', Info.Rationale[0].Text);
  Assert.AreEqual('HACK', Info.Rationale[1].Marker);
  Assert.AreEqual(PositionOf(UnitWerkzeug, '// HACK', 1).Line, Info.Rationale[1].Line);
end;

procedure TLspHoverTests.ShowsRationaleOfUnit;
var
  Info: THoverInfo;
begin
  Info := InfoAt('Werkzeug;');
  Assert.AreEqual(1, Integer(Length(Info.Rationale)));
  Assert.AreEqual('NOTE', Info.Rationale[0].Marker);
end;

procedure TLspHoverTests.WritesRationale;
var
  Info: THoverInfo;
  Atlas: TJSONObject;
  Sections, Runs: TJSONArray;
begin
  Info := Default(THoverInfo);
  Info.Declaration := 'procedure P;';
  Info.Rationale := [TRationaleEntry.Create('WHY', 'Siehe ADR-0007 und #312.', 4)];
  Info.AdrFiles := ['C:\P\docs\adr\0007-ganzzahlen.md'];
  Assert.AreEqual('```pascal'#10'procedure P;'#10'```'#10#10'**Begründung**'#10#10 +
    '- **WHY:** Siehe ADR-0007 und #312.', Info.ToMarkdown);
  Assert.AreEqual('procedure P;'#10#10'Begründung'#10'WHY: Siehe ADR-0007 und #312.', Info.ToPlainText);
  Atlas := TLspHover.AtlasJson(Info);
  try
    Sections := Atlas.GetValue<TJSONArray>('documentation.sections');
    Assert.AreEqual(1, Sections.Count);
    Assert.AreEqual('rationale', Sections.Items[0].GetValue<string>('kind'));
    Assert.AreEqual('WHY', Sections.Items[0].GetValue<string>('name'));
    Runs := Sections.Items[0].GetValue<TJSONArray>('runs');
    Assert.AreEqual(5, Runs.Count);
    Assert.AreEqual('Siehe ', Runs.Items[0].GetValue<string>('text'));
    Assert.AreEqual('ref', Runs.Items[1].GetValue<string>('kind'));
    Assert.AreEqual('C:\P\docs\adr\0007-ganzzahlen.md', Runs.Items[1].GetValue<string>('file'));
    Assert.AreEqual('link', Runs.Items[3].GetValue<string>('kind'));
    Assert.AreEqual('issue:312', Runs.Items[3].GetValue<string>('target'));
    Assert.AreEqual('.', Runs.Items[4].GetValue<string>('text'));
  finally
    Atlas.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTests);

end.
