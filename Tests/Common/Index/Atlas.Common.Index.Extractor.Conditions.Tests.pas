unit Atlas.Common.Index.Extractor.Conditions.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexConditionsTests = class
  public
    [Test]
    procedure BlankInactiveKeepsLinesAndColumns;
    [Test]
    procedure AnnotateMarksActiveAndUnavailable;
    [Test]
    procedure AnnotateFindsMembersInTypeBody;
    [Test]
    procedure InRangeExcludesEnd;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Extractor.Conditions;

function Join(const ALines: array of string): string;
begin
  Result := String.Join(#13#10, ALines);
end;

/// <summary>Eintrag zu AText mit ADefines, Bedingungen eingetragen.</summary>
function Annotated(const AText: string; const ADefines: TArray<string>): TUnitIndex;
var
  mIncludes: TArray<string>;
  mConditionals: TArray<TConditionalRange>;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(TIndexConditions.BlankInactive(AText, 'U.pas', ADefines, nil, mIncludes,
    mConditionals));
  try
    Result := TIndexExtractor.Extract(mTree, 'U.pas');
  finally
    mTree.Free;
  end;
  TIndexConditions.AnnotateConditions(Result, AText, mConditionals);
end;

function SymbolNamed(const ASymbols: TArray<TIndexSymbol>; const AName: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASymbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      Exit(mSymbol);
    end;
  end;
  Result := Default(TIndexSymbol);
end;

procedure TIndexConditionsTests.BlankInactiveKeepsLinesAndColumns;
var
  mText, mBlanked: string;
  mIncludes: TArray<string>;
  mConditionals: TArray<TConditionalRange>;
begin
  mText := Join(['unit U;', '{$IFDEF NIE}', 'weg', '{$ENDIF}', 'end.']);
  mBlanked := TIndexConditions.BlankInactive(mText, 'U.pas', nil, nil, mIncludes, mConditionals);
  Assert.AreEqual(Length(mText), Length(mBlanked));
  Assert.IsFalse(mBlanked.Contains('weg'));
  Assert.AreEqual(5, Integer(Length(mBlanked.Split([#10]))));
  Assert.AreEqual(1, Integer(Length(mConditionals)));
  Assert.IsFalse(mConditionals[0].Active);
  Assert.AreEqual(0, Integer(Length(mIncludes)));
end;

procedure TIndexConditionsTests.AnnotateMarksActiveAndUnavailable;
var
  mUnit: TUnitIndex;
begin
  mUnit := Annotated(Join(['unit U;', 'interface', '{$IFDEF NIE}', 'procedure Weg;', 'const', '  Alt = 1;',
    '{$ENDIF}', '{$IFDEF AN}', 'procedure Da;', '{$ENDIF}', 'implementation', 'end.']),
    TArray<string>.Create('AN'));
  Assert.AreEqual('AN', SymbolNamed(mUnit.Symbols, 'Da').Condition);
  Assert.AreEqual(2, Integer(Length(mUnit.Unavailable)));
  Assert.AreEqual('Weg', mUnit.Unavailable[0].Name);
  Assert.AreEqual(Ord(TIndexSymbolKind.Routine), Ord(mUnit.Unavailable[0].Kind));
  Assert.AreEqual('NIE', mUnit.Unavailable[0].Condition);
  Assert.IsTrue(mUnit.Unavailable[0].Unavailable);
  Assert.AreEqual('Alt', mUnit.Unavailable[1].Name);
  Assert.AreEqual(Ord(TIndexSymbolKind.Constant), Ord(mUnit.Unavailable[1].Kind));
end;

procedure TIndexConditionsTests.AnnotateFindsMembersInTypeBody;
var
  mUnit: TUnitIndex;
begin
  mUnit := Annotated(Join(['unit U;', 'interface', 'type', '  TKunde = class', '  {$IFDEF NIE}',
    '    FAlt, FNeu: Integer;', '    property Wert: Integer read FAlt;', '  {$ENDIF}', '  end;', 'implementation',
    'end.']), nil);
  Assert.AreEqual(3, Integer(Length(mUnit.Unavailable)));
  Assert.AreEqual('FAlt', mUnit.Unavailable[0].Name);
  Assert.AreEqual('TKunde', mUnit.Unavailable[0].Container);
  Assert.AreEqual('FNeu', mUnit.Unavailable[1].Name);
  Assert.AreEqual('Wert', mUnit.Unavailable[2].Name);
  Assert.AreEqual(Ord(TIndexSymbolKind.Property_), Ord(mUnit.Unavailable[2].Kind));
end;

procedure TIndexConditionsTests.InRangeExcludesEnd;
var
  mRange: TTextRange;
begin
  mRange := TTextRange.Create(TTextPosition.Create(1, 2), TTextPosition.Create(3, 4));
  Assert.IsTrue(TIndexConditions.InRange(TTextPosition.Create(1, 2), mRange));
  Assert.IsTrue(TIndexConditions.InRange(TTextPosition.Create(2, 0), mRange));
  Assert.IsFalse(TIndexConditions.InRange(TTextPosition.Create(3, 4), mRange));
  Assert.IsFalse(TIndexConditions.InRange(TTextPosition.Create(1, 1), mRange));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexConditionsTests);

end.
