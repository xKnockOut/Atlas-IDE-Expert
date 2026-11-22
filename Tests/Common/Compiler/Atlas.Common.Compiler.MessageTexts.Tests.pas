unit Atlas.Common.Compiler.MessageTexts.Tests;

// Tests für TCompilerMessageTexts: Namen in Hochkommas aus deutschen und englischen Meldungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerMessageTextsTests = class
  public
    [Test]
    procedure QuotedNamesFromMessages;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Compiler.MessageTexts;

{ TCompilerMessageTextsTests }

procedure TCompilerMessageTextsTests.QuotedNamesFromMessages;
begin
  Assert.AreEqual('Add|System.Generics.Collections', string.Join('|', TCompilerMessageTexts.QuotedNames(
    'Inline function ''Add'' has not been expanded because unit ''System.Generics.Collections'' is not ' +
    'specified in USES list')));
  Assert.AreEqual('AnsiString|string', string.Join('|', TCompilerMessageTexts.QuotedNames(
    'Implizite String-Umwandlung von ''AnsiString'' zu ''string''')));
  Assert.AreEqual('', string.Join('|', TCompilerMessageTexts.QuotedNames('ohne Namen ''offen')));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerMessageTextsTests);

end.
