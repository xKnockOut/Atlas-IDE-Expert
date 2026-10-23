unit Atlas.Core.Tasks.Commands.Tests;

// Tests für die Befehlszeile von Projektaufgaben (#900): Programmsuche über
// Arbeitsordner, PATH und PATHEXT, Umgebung, Anführungszeichen nach
// CommandLineToArgvW und der Umweg über cmd.exe für .bat/.cmd.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTaskCommandsTests = class
  public
    [Test]
    procedure ProgramIsFoundInCwdThenPathWithExtensions;
    [Test]
    procedure ProgramWithPathIsResolvedAgainstCwd;
    [Test]
    procedure MissingProgramGivesEmpty;
    [Test]
    procedure EnvironmentIsOverwrittenAndExtended;
    [Test]
    procedure ArgumentsAreQuoted;
    [Test]
    procedure BatchFilesRunThroughCmd;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Commands;

function Native(const APath: string): string;
begin
  Result := StringReplace(APath, '\', PathDelim, [rfReplaceAll]);
end;

function ExistsIn(const AFiles: TArray<string>): TAtlasTaskFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    var
      Item: string;
    begin
      for Item in AFiles do
        if SameText(Native(Item), Native(AFileName)) then
          Exit(True);
      Result := False;
    end;
end;

{ TAtlasTaskCommandsTests }

procedure TAtlasTaskCommandsTests.ProgramIsFoundInCwdThenPathWithExtensions;
var
  Exists: TAtlasTaskFileExists;
begin
  Exists := ExistsIn(TArray<string>.Create('C:\Tools\pwsh.exe', 'C:\Proj\build.cmd', 'C:\Bin\pwsh.exe'));
  Assert.AreEqual(Native('C:\Tools\pwsh.exe'), TAtlasTaskCommands.FindProgram('pwsh', 'C:\Proj',
    'C:\Tools;"C:\Bin"', '.COM;.EXE;.BAT;.CMD', Exists), 'PATH in Reihenfolge');
  Assert.AreEqual(Native('C:\Proj\build.cmd'), TAtlasTaskCommands.FindProgram('build', 'C:\Proj', 'C:\Tools',
    '.COM;.EXE;.BAT;.CMD', Exists), 'der Arbeitsordner zuerst');
  Assert.AreEqual(Native('C:\Tools\pwsh.exe'), TAtlasTaskCommands.FindProgram('pwsh.exe', '', 'C:\Tools', '',
    Exists), 'mit Endung und ohne PATHEXT');
  Assert.AreEqual(Native('C:\Bin\pwsh.exe'), TAtlasTaskCommands.FindProgram('pwsh', '', ';;C:\Bin\', '', Exists),
    'leere Einträge und Trenner am Ende');
end;

procedure TAtlasTaskCommandsTests.ProgramWithPathIsResolvedAgainstCwd;
var
  Exists: TAtlasTaskFileExists;
begin
  Exists := ExistsIn(TArray<string>.Create('C:\Proj\Tools\Check.cmd', 'D:\x\run.exe'));
  Assert.AreEqual(Native('C:\Proj\Tools\Check.cmd'), TAtlasTaskCommands.FindProgram('Tools\Check', 'C:\Proj',
    'D:\x', '.exe;.cmd', Exists), 'relativ zum Arbeitsordner, nicht in PATH');
  Assert.AreEqual(Native('D:\x\run.exe'), Native(TAtlasTaskCommands.FindProgram('D:\x\run', 'C:\Proj', '',
    '.exe', Exists)), 'mit Laufwerk');
  Assert.AreEqual('', TAtlasTaskCommands.FindProgram('x\run', 'C:\Proj', 'D:\', '.exe', Exists),
    'ein Pfadteil sucht nicht in PATH');
end;

procedure TAtlasTaskCommandsTests.MissingProgramGivesEmpty;
var
  Exists: TAtlasTaskFileExists;
begin
  Exists := ExistsIn(nil);
  Assert.AreEqual('', TAtlasTaskCommands.FindProgram('pwsh', 'C:\Proj', 'C:\Tools', '.exe', Exists));
  Assert.AreEqual('', TAtlasTaskCommands.FindProgram('  ', 'C:\Proj', 'C:\Tools', '.exe', Exists), 'leer');
end;

procedure TAtlasTaskCommandsTests.EnvironmentIsOverwrittenAndExtended;
var
  Merged: TArray<string>;
begin
  Merged := TAtlasTaskCommands.MergeEnvironment(TArray<string>.Create('=C:=C:\', 'Path=C:\Windows', 'TEMP=C:\t'),
    TArray<string>.Create('PATH', 'ATLAS_CI', ' '), TArray<string>.Create('C:\Tools', '1', 'leer'));
  Assert.AreEqual(4, Integer(Length(Merged)));
  Assert.AreEqual('=C:=C:\', Merged[0], 'Laufwerkseinträge bleiben');
  Assert.AreEqual('PATH=C:\Tools', Merged[1], 'ohne Groß-/Kleinschreibung ersetzt');
  Assert.AreEqual('TEMP=C:\t', Merged[2]);
  Assert.AreEqual('ATLAS_CI=1', Merged[3], 'neu angehängt; leere Namen entfallen');
end;

procedure TAtlasTaskCommandsTests.ArgumentsAreQuoted;
begin
  Assert.AreEqual('-File', TAtlasTaskCommands.QuoteArgument('-File'));
  Assert.AreEqual('""', TAtlasTaskCommands.QuoteArgument(''));
  Assert.AreEqual('"C:\Program Files\x"', TAtlasTaskCommands.QuoteArgument('C:\Program Files\x'));
  Assert.AreEqual('"a\"b"', TAtlasTaskCommands.QuoteArgument('a"b'));
  Assert.AreEqual('"C:\my dir\\"', TAtlasTaskCommands.QuoteArgument('C:\my dir\'),
    'Backslash vor dem schließenden Anführungszeichen verdoppelt');
  Assert.AreEqual('"a\\\"b c"', TAtlasTaskCommands.QuoteArgument('a\"b c'));
  Assert.AreEqual('C:\a\b', TAtlasTaskCommands.QuoteArgument('C:\a\b'), 'Backslashes ohne Anführungszeichen');
end;

procedure TAtlasTaskCommandsTests.BatchFilesRunThroughCmd;
begin
  Assert.AreEqual('C:\Tools\pwsh.exe -File "Tools\Check Delphi12.ps1"',
    TAtlasTaskCommands.BuildCommandLine('C:\Tools\pwsh.exe', TArray<string>.Create('-File',
    'Tools\Check Delphi12.ps1'), False));
  Assert.AreEqual('cmd.exe /d /s /c ""C:\My Proj\build.cmd" release"',
    TAtlasTaskCommands.BuildCommandLine('C:\My Proj\build.cmd', TArray<string>.Create('release'), True));
  Assert.IsTrue(TAtlasTaskCommands.IsBatch('C:\x\Build.CMD'));
  Assert.IsTrue(TAtlasTaskCommands.IsBatch('run.bat'));
  Assert.IsFalse(TAtlasTaskCommands.IsBatch('pwsh.exe'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskCommandsTests);

end.
