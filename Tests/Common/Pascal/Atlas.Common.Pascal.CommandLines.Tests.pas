unit Atlas.Common.Pascal.CommandLines.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalCommandLinesTests = class
  public
    [Test]
    procedure SplitsCommandLines;
    /// <summary>Befehlszeilen in Kommentar, String über mehrere Zeilen oder asm zählen nicht.</summary>
    [Test]
    procedure CodeLinesSkipCommentsAndAsm;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.CommandLines;

{ TPascalCommandLinesTests }

procedure TPascalCommandLinesTests.SplitsCommandLines;
var
  mName, mArguments: string;
begin
  Assert.IsTrue(TPascalCommandLines.Split('  /uses A, B', mName, mArguments));
  Assert.AreEqual('uses', mName);
  Assert.AreEqual('A, B', mArguments);
  Assert.IsTrue(TPascalCommandLines.Split('/const! X = 1', mName, mArguments));
  Assert.AreEqual('const!', mName);
  Assert.IsTrue(TPascalCommandLines.Split('/guid', mName, mArguments));
  Assert.AreEqual('', mArguments);
  Assert.IsFalse(TPascalCommandLines.Split('// Kommentar', mName, mArguments));
  Assert.IsFalse(TPascalCommandLines.Split('A / B', mName, mArguments));
  Assert.IsFalse(TPascalCommandLines.Split('/ 2', mName, mArguments));
end;

procedure TPascalCommandLinesTests.CodeLinesSkipCommentsAndAsm;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('begin'#10'/a'#10'{'#10'/b'#10'}'#10'asm'#10'/c'#10'end;'#10'/d');
  Assert.IsTrue(TPascalCommandLines.IsCodeLine(mTokens, 1));
  Assert.IsFalse(TPascalCommandLines.IsCodeLine(mTokens, 3));
  Assert.IsFalse(TPascalCommandLines.IsCodeLine(mTokens, 6));
  Assert.IsTrue(TPascalCommandLines.IsCodeLine(mTokens, 8));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalCommandLinesTests);

end.
