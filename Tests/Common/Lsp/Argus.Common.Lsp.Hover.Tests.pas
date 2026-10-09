unit Argus.Common.Lsp.Hover.Tests;

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.Hover;

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
    procedure WritesMarkdown;
    [Test]
    procedure WritesPlainText;
    [Test]
    procedure WritesPlainTextWithValueAndDeprecation;
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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Lsp.DocWiki;

const
  WerkzeugFile = 'C:\P\Werkzeug.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '    /// <summary>Addiert zwei Zahlen.</summary>'#10 +
    '    /// <param name="A">Erster Wert</param>'#10 +
    '    function Summe(A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen, Blau);'#10 +
    'const'#10 +
    '  Grenze = $10;'#10 +
    'procedure Alt; deprecated ''Neu verwenden'';'#10 +
    'implementation'#10 +
    'procedure Alt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TRechner.Summe(A, B: Integer): Integer;'#10 +
    'begin'#10 +
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
    'begin'#10 +
    '  Zaehler := R.Summe(1, 2);'#10 +
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
begin
  Assert.AreEqual('Kurz. Lang.'#10#10'*X*: Wert',
    TLspHover.DocumentationAbove(['  /// <summary>Kurz.', '  /// Lang.</summary>', '/// <param name="X">Wert</param>',
      'procedure P(X: Integer);'], 3));
  Assert.AreEqual('', TLspHover.DocumentationAbove(['// kein Doku-Kommentar', 'procedure P;'], 1));
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

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTests);

end.
