unit BDLsp.Common.Compiler.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Compiler.Contract;

type
  [TestFixture]
  TCompilerOutputParserTests = class
  public
    [Test]
    procedure ReadsDccLines;
    [Test]
    procedure ReadsColumns;
    [Test]
    procedure ReadsMsBuildLinesInAnyLanguage;
    [Test]
    procedure ReadsMessagesWithoutFile;
    [Test]
    procedure SkipsProgressLines;
    [Test]
    procedure RemovesDuplicates;
  end;

  [TestFixture]
  TCompilerCommandLineTests = class
  public
    [Test]
    procedure PicksCompilerByPlatform;
    [Test]
    procedure BuildsArguments;
    [Test]
    procedure ReadsBdsRoot;
  end;

  [TestFixture]
  TCompilerResultsTests = class
  public
    [Test]
    procedure GroupsByFile;
    [Test]
    procedure ReplaceReportsOldAndNewFiles;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Compiler.OutputParser,
  BDLsp.Common.Compiler.CommandLine,
  BDLsp.Common.Compiler.Results;

function Parsed(const ALine: string): TCompilerMessage;
begin
  if not TCompilerOutputParser.ParseLine(ALine, 'C:\P', Result) then
    raise Exception.Create('Keine Meldung: ' + ALine);
end;

function MessageAt(const AFileName: string; ALine: Integer; const ACode: string): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := -1;
  Result.Code := ACode;
end;

{ TCompilerOutputParserTests }

procedure TCompilerOutputParserTests.ReadsDccLines;
var
  Item: TCompilerMessage;
begin
  Item := Parsed('C:\P\Unit1.pas(12) Error: E2003 Undeclared identifier: ''X''');
  Assert.AreEqual('C:\P\Unit1.pas', Item.FileName);
  Assert.AreEqual(11, Item.Line);
  Assert.AreEqual(-1, Item.Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Item.Severity));
  Assert.AreEqual('E2003', Item.Code);
  Assert.AreEqual('Undeclared identifier: ''X''', Item.Text);
  // Relativer Pfad, Hinweis.
  Item := Parsed('Sub\Unit2.pas(30) Hint: H2164 Variable ''Y'' is declared but never used in ''Foo''');
  Assert.AreEqual('C:\P\Sub\Unit2.pas', Item.FileName);
  Assert.AreEqual(Ord(TCompilerSeverity.Hint), Ord(Item.Severity));
  Assert.AreEqual(Ord(TCompilerSeverity.Warning),
    Ord(Parsed('Unit1.pas(5) Warning: W1036 Variable ''Z'' might not have been initialized').Severity));
end;

procedure TCompilerOutputParserTests.ReadsColumns;
var
  Item: TCompilerMessage;
begin
  Item := Parsed('C:\P\Unit1.pas(12,5) Error: E2003 Undeclared identifier: ''X''');
  Assert.AreEqual(11, Item.Line);
  Assert.AreEqual(4, Item.Column);
end;

procedure TCompilerOutputParserTests.ReadsMsBuildLinesInAnyLanguage;
var
  Item: TCompilerMessage;
begin
  Item := Parsed('[dcc32 Fehler] Unit1.pas(12): E2003 Undeklarierter Bezeichner: ''X''');
  Assert.AreEqual('C:\P\Unit1.pas', Item.FileName);
  Assert.AreEqual(11, Item.Line);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Item.Severity));
  Assert.AreEqual('Undeklarierter Bezeichner: ''X''', Item.Text);
  Item := Parsed('[dcc64 Fatal Error] Projekt.dpr(5): F2613 Unit ''Foo'' not found.');
  Assert.AreEqual(Ord(TCompilerSeverity.Fatal), Ord(Item.Severity));
  Assert.AreEqual('C:\P\Projekt.dpr', Item.FileName);
end;

procedure TCompilerOutputParserTests.ReadsMessagesWithoutFile;
var
  Item: TCompilerMessage;
begin
  Item := Parsed('Fatal: F1026 File not found: ''Neu(1).dpr''');
  Assert.AreEqual('', Item.FileName);
  Assert.AreEqual(-1, Item.Line);
  Assert.AreEqual('F1026', Item.Code);
  Assert.AreEqual('File not found: ''Neu(1).dpr''', Item.Text);
end;

procedure TCompilerOutputParserTests.SkipsProgressLines;
var
  Item: TCompilerMessage;
begin
  Assert.IsFalse(TCompilerOutputParser.ParseLine('Embarcadero Delphi for Win64 compiler version 36.0', 'C:\P', Item));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('Unit1.pas(120)', 'C:\P', Item));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('1234 lines, 0.50 seconds, 100 bytes code.', 'C:\P', Item));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('', 'C:\P', Item));
end;

procedure TCompilerOutputParserTests.RemovesDuplicates;
var
  Found: TArray<TCompilerMessage>;
begin
  Found := TCompilerOutputParser.Parse([
    'Unit1.pas(1) Error: E2003 X',
    'Fortschritt',
    'Unit1.pas(1) Error: E2003 X',
    'Unit1.pas(2) Error: E2003 X'], 'C:\P');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(1, Found[1].Line);
end;

{ TCompilerCommandLineTests }

procedure TCompilerCommandLineTests.PicksCompilerByPlatform;
begin
  Assert.AreEqual('C:\Delphi\bin\dcc32.exe', TCompilerCommandLine.ExecutableFor('C:\Delphi', 'Win32'));
  Assert.AreEqual('C:\Delphi\bin\dcc64.exe', TCompilerCommandLine.ExecutableFor('C:\Delphi', 'win64'));
  Assert.WillRaise(
    procedure
    begin
      TCompilerCommandLine.ExecutableFor('C:\Delphi', 'Android64');
    end, ECompilerError);
end;

procedure TCompilerCommandLineTests.BuildsArguments;
var
  Project: TProjectInfo;
  Request: TCompilerRequest;
  Joined: string;
begin
  Project := Default(TProjectInfo);
  Project.FileName := 'C:\P\Demo.dproj';
  Project.MainSource := 'C:\P\Demo.dpr';
  Project.Platform := 'Win64';
  Project.Defines := ['DEBUG', 'FOO'];
  Project.SearchPaths := ['C:\P\Lib'];
  Project.Namespaces := ['System', 'Vcl'];
  Request := TCompilerCommandLine.Build(Project, ['C:\Delphi\lib\win64\release'], 'C:\Delphi', 'C:\Temp\Out');
  Assert.AreEqual('C:\Delphi\bin\dcc64.exe', Request.Executable);
  Assert.AreEqual('C:\P', Request.WorkingDir);
  Joined := string.Join(' ', Request.Arguments);
  Assert.Contains(Joined, '-NUC:\Temp\Out -EC:\Temp\Out');
  Assert.Contains(Joined, '-UC:\P\Lib;C:\Delphi\lib\win64\release');
  Assert.Contains(Joined, '-DDEBUG;FOO');
  Assert.Contains(Joined, '-NSSystem;Vcl');
  Assert.AreEqual('C:\P\Demo.dpr', Request.Arguments[High(Request.Arguments)]);
  Project.MainSource := '';
  Assert.WillRaise(
    procedure
    begin
      TCompilerCommandLine.Build(Project, nil, 'C:\Delphi', 'C:\Temp\Out');
    end, ECompilerError);
end;

procedure TCompilerCommandLineTests.ReadsBdsRoot;
begin
  Assert.AreEqual('C:\Delphi', TCompilerCommandLine.BdsRoot([
    TPair<string, string>.Create('BDSLIB', 'C:\Delphi\lib'),
    TPair<string, string>.Create('BDS', 'C:\Delphi')]));
  Assert.AreEqual('', TCompilerCommandLine.BdsRoot(nil));
end;

{ TCompilerResultsTests }

procedure TCompilerResultsTests.GroupsByFile;
var
  Results: TCompilerResults;
  General: TCompilerMessage;
begin
  Results := TCompilerResults.Create;
  try
    General := MessageAt('', -1, 'F1026');
    Results.Replace([MessageAt('C:\P\A.pas', 1, 'E2003'), MessageAt('C:\P\B.pas', 2, 'W1036'),
      MessageAt('C:\P\A.pas', 5, 'H2164'), General]);
    Assert.AreEqual(2, Integer(Length(Results.MessagesFor('c:\p\a.pas'))));
    Assert.AreEqual(1, Integer(Length(Results.MessagesFor('C:\P\B.pas'))));
    Assert.AreEqual(0, Integer(Length(Results.MessagesFor('C:\P\C.pas'))));
    Assert.AreEqual(1, Integer(Length(Results.General)));
  finally
    Results.Free;
  end;
end;

procedure TCompilerResultsTests.ReplaceReportsOldAndNewFiles;
var
  Results: TCompilerResults;
  Files: TArray<string>;
begin
  Results := TCompilerResults.Create;
  try
    Results.Replace([MessageAt('C:\P\A.pas', 1, 'E2003')]);
    Files := Results.Replace([MessageAt('C:\P\B.pas', 1, 'E2003')]);
    // A.pas muss geleert werden, B.pas bekommt die neue Meldung.
    Assert.AreEqual(2, Integer(Length(Files)));
    Assert.AreEqual(0, Integer(Length(Results.MessagesFor('C:\P\A.pas'))));
  finally
    Results.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerOutputParserTests);
  TDUnitX.RegisterTestFixture(TCompilerCommandLineTests);
  TDUnitX.RegisterTestFixture(TCompilerResultsTests);

end.
