unit Atlas.Common.Editing.BoundaryCases.Tests;

// Grenzfälle aus den Bedingungen einer Routine (#2173): je Vergleichsart, Typ und die Regel „je Fall weicht ein
// Parameter ab“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBoundaryCasesTests = class
  public
    [Test]
    procedure PlatformCheckGivesSixCases;
    [Test]
    procedure NumberGivesBelowOnAbove;
    [Test]
    procedure CaseGivesLabelsAndOneMore;
    [Test]
    procedure FieldsAndCallsGiveNothing;
    [Test]
    procedure LocalCopyCounts;
    [Test]
    procedure TextFunctionsAndLength;
    [Test]
    procedure FloatSetAndBoolean;
    [Test]
    procedure OtherParametersStayNeutral;
    [Test]
    procedure MaxCasesTruncates;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.BoundaryCases;

const
  cUnit =
    'unit U;' + sLineBreak +
    'interface' + sLineBreak +
    'type' + sLineBreak +
    '  TArt = (Rot, Gruen, Blau, Gelb, Weiss);' + sLineBreak +
    'implementation' + sLineBreak +
    'const cGrenze = 7;' + sLineBreak +
    'function CanRun(const APlatform: string): Boolean;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := (APlatform = '''') or SameText(APlatform, ''Win32'') or' + sLineBreak +
    '    SameText(APlatform, ''Win64'') or SameText(APlatform, ''Win64x'');' + sLineBreak +
    'end;' + sLineBreak +
    'function Rabatt(AMenge: Integer): Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  if AMenge >= 100 then Result := 5 else Result := 0;' + sLineBreak +
    'end;' + sLineBreak +
    'function Name(AArt: TArt): string;' + sLineBreak +
    'begin' + sLineBreak +
    '  case AArt of' + sLineBreak +
    '    Rot: Result := ''r'';' + sLineBreak +
    '    Gruen, Blau: Result := ''gb'';' + sLineBreak +
    '  else Result := '''';' + sLineBreak +
    '  end;' + sLineBreak +
    'end;' + sLineBreak +
    'function Fremd(A: Integer): Boolean;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := (FGrenze = 3) or (Berechne(A) > 4) or (A = FMax);' + sLineBreak +
    'end;' + sLineBreak +
    'function Kopie(const AText: string): Boolean;' + sLineBreak +
    'var m: string;' + sLineBreak +
    'begin' + sLineBreak +
    '  m := AText;' + sLineBreak +
    '  Result := m = ''abc'';' + sLineBreak +
    'end;' + sLineBreak +
    'function Texte(const A: string): Boolean;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := StartsText(''pre'', A) or (Length(A) > 3) or (Pos(''@'', A) > 0);' + sLineBreak +
    'end;' + sLineBreak +
    'function Mix(AWert: Double; AZahl: Integer; AFlag: Boolean): Boolean;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := (AWert > 0.5) and (AZahl in [1, 3..5]) and not AFlag and (AZahl <> cGrenze);' + sLineBreak +
    'end;' + sLineBreak +
    'end.';

function RoutineOf(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  mImpl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mImpl := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  for mIndex := 0 to mImpl.ChildCount - 1 do
  begin
    if (mImpl[mIndex].Kind = TSyntaxKind.RoutineDecl) and SameText(mImpl[mIndex].Name, AName) then
    begin
      Exit(mImpl[mIndex]);
    end;
  end;
end;

function CasesOf(const AName: string; AMax: Integer): TBoundaryResult; overload;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cUnit);
  try
    Result := TBoundaryCases.Find(mTree, RoutineOf(mTree, AName), AMax);
  finally
    mTree.Free;
  end;
end;

function CasesOf(const AName: string): TBoundaryResult; overload;
begin
  Result := CasesOf(AName, TBoundaryCases.cDefaultMax);
end;

/// <summary>Werte des Parameters AParam, mit | getrennt.</summary>
function ValuesOf(const AResult: TBoundaryResult; AParam: Integer): string;
var
  mCase: TBoundaryCase;
begin
  Result := '';
  for mCase in AResult.Cases do
  begin
    if mCase.Parameter = AParam then
    begin
      Result := Result + mCase.Value + '|';
    end;
  end;
end;

{ TBoundaryCasesTests }

procedure TBoundaryCasesTests.PlatformCheckGivesSixCases;
var
  mResult: TBoundaryResult;
begin
  mResult := CasesOf('CanRun');
  Assert.AreEqual(1, Integer(Length(mResult.Parameters)));
  Assert.AreEqual('|Win32|win64|Win64x|Win64 |x|', ValuesOf(mResult, 0));
  Assert.Contains(mResult.Cases[0].Reason, 'APlatform = ''''');
  Assert.Contains(mResult.Cases[2].Reason, 'Win64');
end;

procedure TBoundaryCasesTests.NumberGivesBelowOnAbove;
var
  mResult: TBoundaryResult;
begin
  mResult := CasesOf('Rabatt');
  Assert.AreEqual('99|100|101|', ValuesOf(mResult, 0));
  Assert.AreEqual(13, mResult.Cases[1].Line);
end;

procedure TBoundaryCasesTests.CaseGivesLabelsAndOneMore;
var
  mResult: TBoundaryResult;
begin
  mResult := CasesOf('Name');
  Assert.AreEqual('Rot|Gruen|Blau|Gelb|', ValuesOf(mResult, 0));
  Assert.AreEqual('Rot', mResult.Parameters[0].Neutral);
end;

procedure TBoundaryCasesTests.FieldsAndCallsGiveNothing;
begin
  Assert.AreEqual(0, Integer(Length(CasesOf('Fremd').Cases)));
end;

procedure TBoundaryCasesTests.LocalCopyCounts;
begin
  Assert.AreEqual('abc|ABC|abc |x|', ValuesOf(CasesOf('Kopie'), 0));
end;

procedure TBoundaryCasesTests.TextFunctionsAndLength;
begin
  Assert.AreEqual('prex|pr|aa|aaa|aaaa|x@x|', ValuesOf(CasesOf('Texte'), 0));
end;

procedure TBoundaryCasesTests.FloatSetAndBoolean;
var
  mResult: TBoundaryResult;
begin
  mResult := CasesOf('Mix');
  Assert.AreEqual('0.4|0.5|0.6|', ValuesOf(mResult, 0));
  Assert.AreEqual('1|3|5|6|7|8|', ValuesOf(mResult, 1));
  Assert.AreEqual('True|False|', ValuesOf(mResult, 2));
end;

procedure TBoundaryCasesTests.OtherParametersStayNeutral;
var
  mResult: TBoundaryResult;
  mValues: TArray<string>;
begin
  mResult := CasesOf('Mix');
  mValues := mResult.Values(0);
  Assert.AreEqual(3, Integer(Length(mValues)));
  Assert.AreEqual('0.4', mValues[0]);
  Assert.AreEqual('0', mValues[1]);
  Assert.AreEqual('False', mValues[2]);
end;

procedure TBoundaryCasesTests.MaxCasesTruncates;
var
  mResult: TBoundaryResult;
begin
  mResult := CasesOf('Mix', 2);
  Assert.AreEqual(2, Integer(Length(mResult.Cases)));
  Assert.IsTrue(mResult.Truncated);
  Assert.IsFalse(CasesOf('Rabatt').Truncated);
end;

end.
