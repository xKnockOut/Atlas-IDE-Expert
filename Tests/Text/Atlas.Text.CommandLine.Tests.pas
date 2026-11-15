unit Atlas.Text.CommandLine.Tests;

// Tests für TTextCommandLine: Anführungszeichen nach CommandLineToArgvW und
// für Delphi-Programme (ParamStr).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextCommandLineTests = class
  public
    [Test]
    procedure PlainArgumentsStayUnchanged;
    [Test]
    procedure EmptyAndBlankArgumentsAreQuoted;
    [Test]
    procedure QuotesAndBackslashesFollowCommandLineToArgv;
    [Test]
    procedure JoinQuotesProgramAndArguments;
    [Test]
    procedure JoinArgumentsWithoutProgram;
    [Test]
    procedure ParamStrQuotingDropsQuotes;
  end;

implementation

uses
  Atlas.Text.CommandLine;

procedure TTextCommandLineTests.PlainArgumentsStayUnchanged;
begin
  Assert.AreEqual('-Q', TTextCommandLine.Quote('-Q'));
  Assert.AreEqual('abc', TTextCommandLine.Quote('abc'));
  Assert.AreEqual('C:\a\b', TTextCommandLine.Quote('C:\a\b'), 'Backslashes ohne Anführungszeichen');
end;

procedure TTextCommandLineTests.EmptyAndBlankArgumentsAreQuoted;
begin
  Assert.AreEqual('""', TTextCommandLine.Quote(''));
  Assert.AreEqual('"a b"', TTextCommandLine.Quote('a b'));
  Assert.AreEqual('"a'#9'b"', TTextCommandLine.Quote('a'#9'b'));
  Assert.AreEqual('"C:\Program Files\x.dpr"', TTextCommandLine.Quote('C:\Program Files\x.dpr'));
end;

procedure TTextCommandLineTests.QuotesAndBackslashesFollowCommandLineToArgv;
begin
  Assert.AreEqual('"a\"b"', TTextCommandLine.Quote('a"b'));
  Assert.AreEqual('"a\\\"b c"', TTextCommandLine.Quote('a\"b c'), 'Backslash vor Anführungszeichen verdoppelt');
  Assert.AreEqual('"C:\Program Files\\"', TTextCommandLine.Quote('C:\Program Files\'),
    'Backslash vor dem schließenden Anführungszeichen verdoppelt');
  Assert.AreEqual('"-UC:\a b\\"', TTextCommandLine.Quote('-UC:\a b\'));
  Assert.AreEqual('"a\b c"', TTextCommandLine.Quote('a\b c'), 'Backslash in der Mitte bleibt einfach');
end;

procedure TTextCommandLineTests.JoinQuotesProgramAndArguments;
begin
  Assert.AreEqual('C:\Tools\pwsh.exe -File "Tools\Check Delphi12.ps1"',
    TTextCommandLine.Join('C:\Tools\pwsh.exe', TArray<string>.Create('-File', 'Tools\Check Delphi12.ps1')));
  Assert.AreEqual('"C:\Program Files\Git\git.exe"', TTextCommandLine.Join('C:\Program Files\Git\git.exe', nil),
    'ohne Argumente kein Leerzeichen am Ende');
  Assert.AreEqual('git.exe "" x', TTextCommandLine.Join('git.exe', TArray<string>.Create('', 'x')),
    'leeres Argument bleibt erhalten');
end;

procedure TTextCommandLineTests.JoinArgumentsWithoutProgram;
begin
  Assert.AreEqual('', TTextCommandLine.JoinArguments(nil));
  Assert.AreEqual('prepare "C:\a b\\"', TTextCommandLine.JoinArguments(TArray<string>.Create('prepare', 'C:\a b\')));
end;

procedure TTextCommandLineTests.ParamStrQuotingDropsQuotes;
begin
  Assert.AreEqual('"--xmlfile:C:\Mit Leer\r.xml"', TTextCommandLine.QuoteForParamStr('--xmlfile:C:\Mit Leer\r.xml'));
  Assert.AreEqual('--run:A.B', TTextCommandLine.QuoteForParamStr('--run:A.B'));
  Assert.AreEqual('"a bc"', TTextCommandLine.QuoteForParamStr('a "b"c'), 'Anführungszeichen fallen weg');
  Assert.AreEqual('"C:\x y\"', TTextCommandLine.QuoteForParamStr('C:\x y\'), 'Backslash ohne Sonderrolle');
end;

initialization
  TDUnitX.RegisterTestFixture(TTextCommandLineTests);

end.
