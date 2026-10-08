unit BDLsp.Common.Lsp.Hover.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.Hover;

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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor;

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
    'implementation'#10 +
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

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTests);

end.
