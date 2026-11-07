unit Atlas.Common.Rules.Builtin.Performance.StringResets.Tests;

// Tests von TStringResets: Neusetzen im selben Durchlauf, auch über beide Zweige eines if.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStringResetsTests = class
  public
    [Test]
    procedure ResetInBothBranches;
    [Test]
    procedure ResetOnlyInThenOrWithOldValue;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Performance.StringResets;

/// <summary>Setzt eine Anweisung vor der letzten Zuweisung "S := S + …" in ABody den String S sicher neu?</summary>
function ResetBeforeAppend(const ABody: string): Boolean;
var
  mSource: string;
  mTree: TSyntaxTree;
begin
  mSource := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  S: string;'#10 +
    '  I: Integer;'#10'begin'#10'  for I := 1 to 3 do'#10'  begin'#10 + ABody + #10'    S := S + ''x'';'#10 +
    '  end;'#10'end;'#10'end.';
  mTree := TPascalParser.Parse(mSource);
  try
    Result := TStringResets.EarlierInPass(mTree, mSource.LastIndexOf('S := S'), 'S');
  finally
    mTree.Free;
  end;
end;

{ TStringResetsTests }

procedure TStringResetsTests.ResetInBothBranches;
begin
  Assert.IsTrue(ResetBeforeAppend('    S := '''';'));
  Assert.IsTrue(ResetBeforeAppend('    if I = 2 then'#10'      S := ''>'''#10'    else'#10'    begin'#10 +
    '      S := '' '';'#10'    end;'));
end;

procedure TStringResetsTests.ResetOnlyInThenOrWithOldValue;
begin
  Assert.IsFalse(ResetBeforeAppend('    if I = 2 then'#10'      S := ''>'';'));
  Assert.IsFalse(ResetBeforeAppend('    S := Trim(S);'));
  Assert.IsFalse(ResetBeforeAppend('    I := I;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TStringResetsTests);

end.
