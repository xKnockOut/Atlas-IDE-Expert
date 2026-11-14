unit Atlas.Common.Lsp.QualifiedNames.Tests;

// Tests für den qualifizierten Namen des Symbols unter dem Cursor (#128), je Formatfall einer.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TQualifiedNamesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function NameAt(const AMarker: string; AOccurrence: Integer): string; overload;
    function NameAt(const AMarker: string; AOccurrence: Integer; AWithParameters: Boolean): string; overload;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.QualifiedNames;

const
  cControlsFile = 'C:\P\Vcl.Steuer.pas';
  cMainFile = 'C:\P\Haupt.pas';

  cUnitControls =
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

  cUnitMain =
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

{ TQualifiedNamesTests }

procedure TQualifiedNamesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitControls, cControlsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TQualifiedNamesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TQualifiedNamesTests.NameAt(const AMarker: string; AOccurrence: Integer): string;
begin
  Result := NameAt(AMarker, AOccurrence, False);
end;

function TQualifiedNamesTests.NameAt(const AMarker: string; AOccurrence: Integer; AWithParameters: Boolean): string;
var
  mTree: TSyntaxTree;
  mError: string;
begin
  mTree := TPascalParser.Parse(cUnitMain);
  try
    Assert.IsTrue(TQualifiedNames.At(FResolver, FIndex, mTree, TQualifiedNameRequest.Create(cMainFile,
      PositionOf(cUnitMain, AMarker, AOccurrence), AWithParameters), Result, mError), mError);
  finally
    mTree.Free;
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
  mTree: TSyntaxTree;
  mName, mError: string;
begin
  mTree := TPascalParser.Parse(cUnitMain);
  try
    Assert.IsFalse(TQualifiedNames.At(FResolver, FIndex, mTree, TQualifiedNameRequest.Create(cMainFile,
      TTextPosition.Create(17, 0), False), mName, mError));
    Assert.AreEqual('', mName);
    Assert.AreEqual('An Zeile 18, Spalte 1 steht kein bekanntes Symbol', mError);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TQualifiedNamesTests);

end.
