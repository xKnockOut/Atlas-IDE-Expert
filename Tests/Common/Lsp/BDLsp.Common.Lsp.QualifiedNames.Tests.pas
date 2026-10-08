unit BDLsp.Common.Lsp.QualifiedNames.Tests;

// Tests für den qualifizierten Namen des Symbols unter dem Cursor (#128), je Formatfall einer.

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver;

type
  [TestFixture]
  TQualifiedNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function NameAt(const AMarker: string; AOccurrence: Integer; AWithParameters: Boolean = False): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DottedUnitNameStaysComplete;
    [Test]
    procedure NestedTypes;
    [Test]
    procedure GenericTypeWithTypeParameters;
    [Test]
    procedure OverloadWithParameterTypes;
    [Test]
    procedure LocalRoutineWithOuterRoutine;
    [Test]
    procedure LocalVariableWithRoutine;
    [Test]
    procedure UnitNameAlone;
    [Test]
    procedure NoSymbolGivesError;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.QualifiedNames;

const
  ControlsFile = 'C:\P\Vcl.Steuer.pas';
  MainFile = 'C:\P\Haupt.pas';

  UnitControls =
    'unit Vcl.Steuer;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TControl = class'#10 +
    '    procedure Paint;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TControl.Paint;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitMain =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Vcl.Steuer;'#10 +
    'type'#10 +
    '  TAussen = class'#10 +
    '  type'#10 +
    '    TInnen = class'#10 +
    '      procedure Tief;'#10 +
    '    end;'#10 +
    '  end;'#10 +
    '  TListe<T> = class'#10 +
    '    procedure Hinzu(const AWert: T);'#10 +
    '  end;'#10 +
    'procedure Rechne(A: Integer; const B: string); overload;'#10 +
    'procedure Rechne; overload;'#10 +
    'implementation'#10 +
    'procedure TAussen.TInnen.Tief;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TListe<T>.Hinzu(const AWert: T);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne(A: Integer; const B: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Aussen(C: TControl);'#10 +
    'var'#10 +
    '  Zaehler: Integer;'#10 +
    '  procedure Innen;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'begin'#10 +
    '  Innen;'#10 +
    '  Zaehler := 1;'#10 +
    '  C.Paint;'#10 +
    '  Rechne(Zaehler, ''x'');'#10 +
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

{ TQualifiedNamesTests }

procedure TQualifiedNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitControls, ControlsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TQualifiedNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TQualifiedNamesTests.NameAt(const AMarker: string; AOccurrence: Integer; AWithParameters: Boolean): string;
var
  Tree: TSyntaxTree;
  Error: string;
begin
  Tree := TPascalParser.Parse(UnitMain);
  try
    Assert.IsTrue(TQualifiedNames.At(FResolver, FIndex, Tree, MainFile, PositionOf(UnitMain, AMarker, AOccurrence),
      AWithParameters, Result, Error), Error);
  finally
    Tree.Free;
  end;
end;

procedure TQualifiedNamesTests.DottedUnitNameStaysComplete;
begin
  Assert.AreEqual('Vcl.Steuer.TControl.Paint', NameAt('Paint;', 1));
  Assert.AreEqual('Vcl.Steuer.TControl', NameAt('TControl)', 1));
end;

procedure TQualifiedNamesTests.NestedTypes;
begin
  Assert.AreEqual('Haupt.TAussen.TInnen.Tief', NameAt('Tief;', 1));
end;

procedure TQualifiedNamesTests.GenericTypeWithTypeParameters;
begin
  Assert.AreEqual('Haupt.TListe<T>.Hinzu', NameAt('Hinzu(', 1));
  Assert.AreEqual('Haupt.TListe<T>', NameAt('TListe<T> =', 1));
end;

procedure TQualifiedNamesTests.OverloadWithParameterTypes;
begin
  Assert.AreEqual('Haupt.Rechne', NameAt('Rechne(A', 1));
  Assert.AreEqual('Haupt.Rechne(Integer, string)', NameAt('Rechne(A', 1, True));
  Assert.AreEqual('Haupt.Rechne()', NameAt('Rechne; overload', 1, True));
end;

procedure TQualifiedNamesTests.LocalRoutineWithOuterRoutine;
begin
  Assert.AreEqual('Haupt.Aussen.Innen', NameAt('Innen;'#10'  Zaehler', 1));
  Assert.AreEqual('Haupt.Aussen', NameAt('Aussen(C', 1));
end;

procedure TQualifiedNamesTests.LocalVariableWithRoutine;
begin
  Assert.AreEqual('Haupt.Aussen.Zaehler', NameAt('Zaehler := 1', 1));
end;

procedure TQualifiedNamesTests.UnitNameAlone;
begin
  Assert.AreEqual('Vcl.Steuer', NameAt('Vcl.Steuer;'#10'type', 1));
end;

procedure TQualifiedNamesTests.NoSymbolGivesError;
var
  Tree: TSyntaxTree;
  Name, Error: string;
begin
  Tree := TPascalParser.Parse(UnitMain);
  try
    Assert.IsFalse(TQualifiedNames.At(FResolver, FIndex, Tree, MainFile, TTextPosition.Create(17, 0), False, Name,
      Error));
    Assert.AreEqual('', Name);
    Assert.AreEqual('An Zeile 18, Spalte 1 steht kein bekanntes Symbol', Error);
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TQualifiedNamesTests);

end.
