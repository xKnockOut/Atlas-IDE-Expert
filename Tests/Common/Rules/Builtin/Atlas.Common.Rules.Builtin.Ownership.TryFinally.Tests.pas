unit Atlas.Common.Rules.Builtin.Ownership.TryFinally.Tests;

// Tests der gemeinsamen Korrektur der Besitzregeln: Anweisung vor try, folgende Anweisungen eingerückt, Freigabe
// im finally; abgelehnt, wenn die Anweisung oder die letzte folgende Anweisung ihre Zeile nicht allein hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTryFinallyWrapTests = class
  public
    [Test]
    procedure WrapsFollowingStatements;
    [Test]
    procedure KeepsEmptyLines;
    [Test]
    procedure RefusesSharedLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Ownership.TryFinally;

function Source(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

/// <summary>Erste Anweisung im Rumpf von P.</summary>
function FirstStatement(ATree: TSyntaxTree): TSyntaxNode;
var
  mBlock: TSyntaxNode;
begin
  mBlock := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.Block then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Assert.IsNotNull(mBlock);
  Result := mBlock[0];
end;

/// <summary>Wendet AEdit auf ein Wrap über den ersten Rumpf an; False, wenn Wrap ablehnt.</summary>
function Wrapped(const ABody: string; out AText: string): Boolean;
var
  mTree: TSyntaxTree;
  mEdit: TTextEdit;
  mLines: TArray<string>;
  mLine: Integer;
begin
  mTree := TPascalParser.Parse(Source(ABody));
  try
    mLines := TTextLines.SplitLines(Source(ABody));
    Result := TTryFinallyWrap.Create(mLines, #10, TFormatStyle.Default).Wrap(FirstStatement(mTree), 'L := ',
      'L.Free;', mEdit);
    AText := '';
    if Result then
    begin
      for mLine := 0 to mEdit.Range.StartPos.Line - 1 do
      begin
        AText := AText + mLines[mLine] + #10;
      end;
      AText := AText + mEdit.NewText;
      for mLine := mEdit.Range.EndPos.Line to High(mLines) do
      begin
        AText := AText + mLines[mLine] + #10;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

{ TTryFinallyWrapTests }

procedure TTryFinallyWrapTests.WrapsFollowingStatements;
var
  mText: string;
begin
  Assert.IsTrue(Wrapped('  TStringList.Create;'#10'  A;'#10'  B;'#10, mText));
  Assert.AreEqual(Source('  L := TStringList.Create;'#10'  try'#10'    A;'#10'    B;'#10'  finally'#10 +
    '    L.Free;'#10'  end;'#10) + #10, mText);
end;

procedure TTryFinallyWrapTests.KeepsEmptyLines;
var
  mText: string;
begin
  Assert.IsTrue(Wrapped('  TStringList.Create;'#10#10'  A;'#10, mText));
  Assert.AreEqual(Source('  L := TStringList.Create;'#10'  try'#10#10'    A;'#10'  finally'#10'    L.Free;'#10 +
    '  end;'#10) + #10, mText);
end;

procedure TTryFinallyWrapTests.RefusesSharedLine;
var
  mText: string;
begin
  Assert.IsFalse(Wrapped('  TStringList.Create; A;'#10, mText));
  Assert.IsFalse(Wrapped('  TStringList.Create;'#10'  A; // Ende'#10, mText));
  Assert.AreEqual('', mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TTryFinallyWrapTests);

end.
