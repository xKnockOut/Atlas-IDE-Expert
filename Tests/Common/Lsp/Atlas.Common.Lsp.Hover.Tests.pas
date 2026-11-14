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
    function InfoAt(const AMarker: string): THoverInfo; overload;
    function InfoAt(const AMarker: string; AOccurrence: Integer): THoverInfo; overload;
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
  cOrdersForm =
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

  cWerkzeugFile = 'C:\P\Werkzeug.pas';

  cUnitWerkzeug =
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

  cUnitHaupt =
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
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TLspHoverTests }

procedure TLspHoverTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHoverTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHoverTests.InfoAt(const AMarker: string): THoverInfo;
begin
  Result := InfoAt(AMarker, 1);
end;

function TLspHoverTests.InfoAt(const AMarker: string; AOccurrence: Integer): THoverInfo;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspHover.InfoAt(THoverSource.Create(FResolver, FIndex,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, cWerkzeugFile);
        AText := cUnitWerkzeug;
      end), mTree, cUnitHaupt, 'C:\P\Haupt.pas', PositionOf(cUnitHaupt, AMarker, AOccurrence));
  finally
    mTree.Free;
  end;
end;

procedure TLspHoverTests.ShowsDeclarationAndDocumentation;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Zaehler :=');
  Assert.AreEqual('Zaehler: Integer;', mInfo.Declaration);
  Assert.AreEqual('Zählt die Aufrufe.', mInfo.Documentation);
  Assert.AreEqual('', mInfo.UnitName);
end;

procedure TLspHoverTests.ShowsMembersFromOtherUnits;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Summe');
  Assert.AreEqual('function Summe(A, B: Integer): Integer;', mInfo.Declaration);
  Assert.AreEqual('Addiert zwei Zahlen.'#10#10'*A*: Erster Wert', mInfo.Documentation);
  Assert.AreEqual('Werkzeug', mInfo.UnitName);
  // Eigene Units haben keine DocWiki-Seite.
  Assert.AreEqual('', mInfo.DocWikiUrl);
end;

procedure TLspHoverTests.ShowsLocals;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('R.Summe');
  Assert.AreEqual('R: TRechner;', mInfo.Declaration);
end;

procedure TLspHoverTests.ShowsUnitNames;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Werkzeug;');
  Assert.AreEqual('unit Werkzeug;', mInfo.Declaration);
end;

procedure TLspHoverTests.NothingForUnknownNames;
begin
  Assert.IsFalse(InfoAt('Unbekannt').Found);
end;

procedure TLspHoverTests.FormatsParameterDocumentation;
var
  mInfo: THoverInfo;
begin
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'procedure P(X: Integer);';
  mInfo.Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(['  /// <summary>Kurz.', '  /// Lang.</summary>',
    '/// <param name="X">Wert</param>', 'procedure P(X: Integer);'], 3));
  mInfo.Documentation := mInfo.Doc.ToMarkdown;
  Assert.AreEqual('Kurz. Lang.'#10#10'*X*: Wert', mInfo.Documentation);
  Assert.AreEqual('procedure P(X: Integer);'#10#10'Kurz. Lang.'#10#10'X: Wert', mInfo.ToPlainText);
  Assert.IsTrue(TXmlDoc.Parse(TXmlDoc.CommentAbove(['// kein Doku-Kommentar', 'procedure P;'], 1)).IsEmpty);
end;

procedure TLspHoverTests.KeepsCrefNamesInDocumentation;
var
  mInfo: THoverInfo;
  mJson, mSection, mRun: TJSONObject;
begin
  // Beispiel aus #654: Der Name aus <see cref> fehlte.
  mInfo := InfoAt('Create(nil)');
  Assert.AreEqual('constructor Create(AOwner: TDBGridFilter);', mInfo.Declaration);
  Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden TDBGridFilter.', mInfo.Doc.Summary);
  Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden `TDBGridFilter`.'#10#10 +
    '*AOwner*: Der besitzende TDBGridFilter.', mInfo.Documentation);
  Assert.AreEqual(1, Integer(Length(mInfo.DocTargets)));
  Assert.AreEqual('TDBGridFilter', mInfo.DocTargets[0].Name);
  Assert.AreEqual(cWerkzeugFile, mInfo.DocTargets[0].FileName);
  Assert.AreEqual(PositionOf(cUnitWerkzeug, 'TDBGridFilter = class', 1).Line, mInfo.DocTargets[0].Line);
  // Klartext (GetHintText) mit dem Namen.
  Assert.IsTrue(Pos('besitzenden TDBGridFilter.', mInfo.ToPlainText) > 0, mInfo.ToPlainText);
  mJson := TLspHover.AtlasJson(mInfo);
  try
    Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden TDBGridFilter.'#10#10 +
      'AOwner: Der besitzende TDBGridFilter.', mJson.GetValue<string>('documentationText'));
    mSection := mJson.GetValue<TJSONArray>('documentation.sections').Items[0] as TJSONObject;
    Assert.AreEqual('summary', mSection.GetValue<string>('kind'));
    mRun := (mSection.GetValue('runs') as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('ref', mRun.GetValue<string>('kind'));
    Assert.AreEqual('TDBGridFilter', mRun.GetValue<string>('text'));
    Assert.AreEqual(cWerkzeugFile, mRun.GetValue<string>('file'));
    Assert.AreEqual(PositionOf(cUnitWerkzeug, 'TDBGridFilter = class', 1).Line, mRun.GetValue<Integer>('line'));
    mSection := mJson.GetValue<TJSONArray>('documentation.sections').Items[1] as TJSONObject;
    Assert.AreEqual('param', mSection.GetValue<string>('kind'));
    Assert.AreEqual('AOwner', mSection.GetValue<string>('name'));
  finally
    mJson.Free;
  end;
end;

procedure TLspHoverTests.InheritsDocumentationFromAncestor;
var
  mInfo: THoverInfo;
  mJson, mSection: TJSONObject;
begin
  mInfo := InfoAt('Zeichne(1)');
  Assert.AreEqual('procedure Zeichne(X: Integer); override;', mInfo.Declaration);
  Assert.AreEqual('Zeichnet X.', mInfo.Doc.Summary);
  Assert.AreEqual('Breite', mInfo.Doc.Params[0].Text);
  Assert.AreEqual('EZeichnen', mInfo.Doc.Exceptions[0].Name);
  Assert.AreEqual('Eigene Bemerkung.', mInfo.Doc.Remarks);
  Assert.IsFalse(mInfo.Doc.InheritDoc);
  mJson := TLspHover.AtlasJson(mInfo);
  try
    mSection := mJson.GetValue<TJSONArray>('documentation.sections').Items[2] as TJSONObject;
    Assert.AreEqual('exception', mSection.GetValue<string>('kind'));
    Assert.AreEqual(PositionOf(cUnitWerkzeug, 'EZeichnen = class', 1).Line, mSection.GetValue<Integer>('ref.line'));
  finally
    mJson.Free;
  end;
end;

procedure TLspHoverTests.WritesMarkdown;
var
  mInfo: THoverInfo;
begin
  mInfo.Declaration := 'procedure P;';
  mInfo.Documentation := 'Tut etwas.';
  mInfo.UnitName := 'U';
  Assert.AreEqual('```pascal'#10'procedure P;'#10'```'#10#10'Tut etwas.'#10#10'Unit `U`', mInfo.ToMarkdown);
end;

procedure TLspHoverTests.WritesPlainText;
var
  mInfo: THoverInfo;
begin
  mInfo.Declaration := 'procedure P(X: Integer);';
  mInfo.Documentation := 'Tut etwas.'#10#10'*X*: Wert';
  mInfo.UnitName := 'U';
  mInfo.DocWikiUrl := 'https://docwiki.example/P';
  Assert.AreEqual('procedure P(X: Integer);'#10#10'Tut etwas.'#10#10'X: Wert'#10#10'Unit U'#10#10 +
    'DocWiki: https://docwiki.example/P', mInfo.ToPlainText);
end;

procedure TLspHoverTests.WritesPlainTextWithValueAndDeprecation;
var
  mInfo: THoverInfo;
begin
  mInfo.Declaration := 'Max = 10;';
  mInfo.Deprecation := '**Veraltet**';
  mInfo.Value := '10';
  mInfo.Messages := '`WM_PAINT`';
  Assert.AreEqual('Max = 10;'#10#10'Veraltet'#10#10'Wert: 10'#10#10'WM_PAINT', mInfo.ToPlainText);
end;

procedure TLspHoverTests.AtlasPartsForTooltip;
var
  mInfo: THoverInfo;
  mJson, mMember: TJSONObject;
begin
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'procedure BeginUpdate;';
  mInfo.UnitName := 'System.Classes';
  mInfo.Documentation := 'Unterdrückt das **Neuzeichnen**.';
  mJson := TLspHover.AtlasJson(mInfo);
  try
    Assert.AreEqual('procedure BeginUpdate;', mJson.GetValue<string>('declaration'));
    Assert.AreEqual('System.Classes', mJson.GetValue<string>('unit'));
    Assert.AreEqual('Unterdrückt das Neuzeichnen.', mJson.GetValue<string>('documentationText'));
    Assert.IsNull(mJson.GetValue('documentation'), 'ohne XMLDoc keine Struktur');
    Assert.IsNull(mJson.GetValue('value'), 'leere Teile entfallen');
    Assert.IsNull(mJson.GetValue('published'), 'ohne Mitglieder kein published');
  finally
    mJson.Free;
  end;
  // published-Mitglieder strukturiert (#110).
  SetLength(mInfo.PublishedItems, 1);
  mInfo.PublishedItems[0].Name := 'Caption';
  mInfo.PublishedItems[0].TypeName := 'TCaption';
  mInfo.PublishedItems[0].DeclaringClass := 'TControl';
  mInfo.DefaultProperty := 'Controls[Index: Integer]: TControl';
  mJson := TLspHover.AtlasJson(mInfo);
  try
    mMember := mJson.GetValue<TJSONArray>('published.members').Items[0] as TJSONObject;
    Assert.AreEqual('Caption', mMember.GetValue<string>('name'));
    Assert.AreEqual('TControl', mMember.GetValue<string>('declaringClass'));
    Assert.AreEqual('Controls[Index: Integer]: TControl', mJson.GetValue<string>('published.defaultProperty'));
  finally
    mJson.Free;
  end;
end;

procedure TLspHoverTests.ReassignedNamesInAtlasPart;
const
  cSource =
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
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
  mJson, mPart: TJSONObject;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mInfo := Default(THoverInfo);
    mInfo.Declaration := 'Total: Integer;';
    TLspHover.AddReassigned(FResolver, mTree, 'C:\P\R.pas', cSource, TTextPosition.Create(8, 12), mInfo);
    Assert.AreEqual('locals', mInfo.ReassignedTarget);
    Assert.AreEqual(2, mInfo.ReassignedWrites);
    mJson := TLspHover.AtlasJson(mInfo);
    try
      mPart := mJson.GetValue('reassigned') as TJSONObject;
      Assert.IsNotNull(mPart);
      Assert.AreEqual('locals', mPart.GetValue('target').Value);
      Assert.AreEqual('2', mPart.GetValue('writes').Value);
      Assert.AreEqual('[7,8]', mPart.GetValue('lines').ToJSON);
    finally
      mJson.Free;
    end;
    // A wird nur gelesen: kein Eintrag.
    mInfo := Default(THoverInfo);
    TLspHover.AddReassigned(FResolver, mTree, 'C:\P\R.pas', cSource, TTextPosition.Create(8, 19), mInfo);
    Assert.AreEqual('', mInfo.ReassignedTarget);
    mJson := TLspHover.AtlasJson(mInfo);
    try
      Assert.IsNull(mJson.GetValue('reassigned'));
    finally
      mJson.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspHoverTests.PlainTextKeepsLiteralAsterisks;
var
  mInfo: THoverInfo;
begin
  // In der IDE gesehen: "(Gallery.Page.*)" kam als "(Gallery.Page.)" an.
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'TFrameClass = class of TFrame;';
  mInfo.Deprecation := '**Veraltet**: Stattdessen TNeu';
  mInfo.Documentation := 'Frame einer Seite (Gallery.Page.*), a*b.'#10#10'*AName*: Der Name';
  Assert.AreEqual('TFrameClass = class of TFrame;'#10#10'Veraltet: Stattdessen TNeu'#10#10 +
    'Frame einer Seite (Gallery.Page.*), a*b.'#10#10'AName: Der Name', mInfo.ToPlainText);
end;

procedure TLspHoverTests.DetectsMarkdownSupport;

  function Supports(const AJson: string): Boolean;
  var
    mParams: TJSONObject;
  begin
    mParams := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      Result := TLspHover.ClientSupportsMarkdown(mParams);
    finally
      mParams.Free;
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
  cLibFile = 'C:\Lib\Vcl.Werkzeug.pas';
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mLibText, mMainText: string;
  mInfo: THoverInfo;
begin
  mLibText := StringReplace(cUnitWerkzeug, 'unit Werkzeug;', 'unit Vcl.Werkzeug;', []);
  mMainText := StringReplace(cUnitHaupt, 'uses Werkzeug;', 'uses Vcl.Werkzeug;', []);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(mLibText, cLibFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(mMainText);
  try
    mInfo := TLspHover.InfoAt(THoverSource.Create(mResolver, mIndex,
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, cLibFile);
        AText := mLibText;
      end), mTree, mMainText, 'C:\P\Haupt.pas', PositionOf(mMainText, 'Summe', 1), '23.0');
    Assert.AreEqual(TDocWiki.cBaseUri + 'Athens/en/Vcl.Werkzeug.TRechner.Summe', mInfo.DocWikiUrl);
    Assert.IsTrue(Pos('[DocWiki](' + mInfo.DocWikiUrl + ')', mInfo.ToMarkdown) > 0);
    mInfo := TLspHover.InfoAt(THoverSource.Create(mResolver, mIndex, nil), mTree, mMainText, 'C:\P\Haupt.pas',
      PositionOf(mMainText, 'Vcl.Werkzeug;', 1), '');
    Assert.AreEqual(TDocWiki.cBaseUri + 'Florence/en/Vcl.Werkzeug', mInfo.DocWikiUrl);
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TLspHoverTests.ShowsNumberNotations;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('255');
  Assert.AreEqual('255', mInfo.Declaration);
  Assert.AreEqual('255 · $FF · %11111111', mInfo.Value);
  Assert.Contains(mInfo.ToMarkdown, 'Wert: `255 · $FF · %11111111`');
end;

procedure TLspHoverTests.ShowsConstantAndEnumValues;
begin
  Assert.AreEqual('16 · $10 · %10000', InfoAt('Grenze +').Value);
  Assert.AreEqual('Ord = 2', InfoAt('Blau)').Value);
end;

procedure TLspHoverTests.ShowsDeprecation;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Alt;');
  Assert.AreEqual('**Veraltet**: Neu verwenden', mInfo.Deprecation);
  Assert.Contains(mInfo.ToMarkdown, '**Veraltet**: Neu verwenden');
end;

procedure TLspHoverTests.ShowsSetsAndResourceStrings;
const
  cStilFile = 'C:\P\Stile.pas';
  cUnitStile =
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
  cMainText =
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
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mReadText: THoverReadText;

  function At(const AMarker: string): THoverInfo;
  begin
    Result := TLspHover.InfoAt(THoverSource.Create(mResolver, mIndex, mReadText), mTree, cMainText, 'C:\P\Haupt.pas',
      PositionOf(cMainText, AMarker, 1), '');
  end;

begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitStile, cStilFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cMainText);
  mReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, cStilFile);
      AText := cUnitStile;
    end;
  try
    Assert.AreEqual('[sFett, sKursiv] · 2 Elemente', At('Standard;').Value);
    Assert.AreEqual('set of TStil · 3 mögliche Elemente', At('TStile;').Value);
    Assert.AreEqual('''Hallo⏎Welt''', At('SGruss)').Value);
    Assert.Contains(At('SGruss)').ToMarkdown, 'Wert: `''Hallo⏎Welt''`');
  finally
    mReadText := nil;
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TLspHoverTests.HintsUnknownDataFieldNames;

  function Hint(const ALine: string; out AText: string): Boolean;
  begin
    Result := TLspHover.DataNameHint(nil, 'unit Orders;'#13#10'{$R *.dfm}'#13#10 + ALine + #13#10, 'C:\P\Orders.pas',
      TTextPosition.Create(2, Pos('''', ALine) + 1),
      function(const AFileName: string; out AFormText: string): Boolean
      begin
        AFormText := cOrdersForm;
        Result := SameText(ExtractFileExt(AFileName), '.dfm');
      end, AText);
  end;

var
  mText: string;
begin
  Assert.IsTrue(Hint('  qryOrders.FieldByName(''CUSTOMR_ID'').AsInteger;', mText));
  Assert.AreEqual('Feld nicht gefunden in qryOrders', mText);
  Assert.IsTrue(Hint('  qryOrders.ParamByName(''Kunde'').AsInteger := 1;', mText));
  Assert.AreEqual('Parameter nicht gefunden in qryOrders', mText);
  // Bekannte Namen, select * ohne Schema und zur Laufzeit erzeugte Datenmengen: kein Hinweis.
  Assert.IsFalse(Hint('  qryOrders.FieldByName(''currency'').AsString;', mText));
  Assert.IsFalse(Hint('  qryAll.FieldByName(''IRGENDWAS'').AsString;', mText));
  Assert.IsFalse(Hint('  qryLaufzeit.FieldByName(''IRGENDWAS'').AsString;', mText));
end;

procedure TLspHoverTests.ShowsRationaleOfDeclarationAndBody;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Summe');
  Assert.AreEqual(2, Integer(Length(mInfo.Rationale)));
  Assert.AreEqual('WHY', mInfo.Rationale[0].Marker);
  Assert.AreEqual('Ganzzahlen genuegen, siehe #312.', mInfo.Rationale[0].Text);
  Assert.AreEqual('HACK', mInfo.Rationale[1].Marker);
  Assert.AreEqual(PositionOf(cUnitWerkzeug, '// HACK', 1).Line, mInfo.Rationale[1].Line);
end;

procedure TLspHoverTests.ShowsRationaleOfUnit;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('Werkzeug;');
  Assert.AreEqual(1, Integer(Length(mInfo.Rationale)));
  Assert.AreEqual('NOTE', mInfo.Rationale[0].Marker);
end;

procedure TLspHoverTests.WritesRationale;
var
  mInfo: THoverInfo;
  mAtlas: TJSONObject;
  mSections, mRuns: TJSONArray;
begin
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'procedure P;';
  mInfo.Rationale := [TRationaleEntry.Create('WHY', 'Siehe ADR-0007 und #312.', 4)];
  mInfo.AdrFiles := ['C:\P\docs\adr\0007-ganzzahlen.md'];
  Assert.AreEqual('```pascal'#10'procedure P;'#10'```'#10#10'**Begründung**'#10#10 +
    '- **WHY:** Siehe ADR-0007 und #312.', mInfo.ToMarkdown);
  Assert.AreEqual('procedure P;'#10#10'Begründung'#10'WHY: Siehe ADR-0007 und #312.', mInfo.ToPlainText);
  mAtlas := TLspHover.AtlasJson(mInfo);
  try
    mSections := mAtlas.GetValue<TJSONArray>('documentation.sections');
    Assert.AreEqual(1, mSections.Count);
    Assert.AreEqual('rationale', mSections.Items[0].GetValue<string>('kind'));
    Assert.AreEqual('WHY', mSections.Items[0].GetValue<string>('name'));
    mRuns := mSections.Items[0].GetValue<TJSONArray>('runs');
    Assert.AreEqual(5, mRuns.Count);
    Assert.AreEqual('Siehe ', mRuns.Items[0].GetValue<string>('text'));
    Assert.AreEqual('ref', mRuns.Items[1].GetValue<string>('kind'));
    Assert.AreEqual('C:\P\docs\adr\0007-ganzzahlen.md', mRuns.Items[1].GetValue<string>('file'));
    Assert.AreEqual('link', mRuns.Items[3].GetValue<string>('kind'));
    Assert.AreEqual('issue:312', mRuns.Items[3].GetValue<string>('target'));
    Assert.AreEqual('.', mRuns.Items[4].GetValue<string>('text'));
  finally
    mAtlas.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTests);

end.
