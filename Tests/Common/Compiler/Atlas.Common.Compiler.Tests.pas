unit Atlas.Common.Compiler.Tests;

interface

uses
  DUnitX.TestFramework;

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
  Atlas.Common.Compiler.Contract,
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Compiler.OutputParser,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Compiler.Results;

function Parsed(const ALine: string): TCompilerMessage;
begin
  if not TCompilerOutputParser.ParseLine(ALine, 'C:\P', Result) then
  begin
    raise Exception.Create('Keine Meldung: ' + ALine);
  end;
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
  mItem: TCompilerMessage;
begin
  mItem := Parsed('C:\P\Unit1.pas(12) Error: E2003 Undeclared identifier: ''X''');
  Assert.AreEqual('C:\P\Unit1.pas', mItem.FileName);
  Assert.AreEqual(11, mItem.Line);
  Assert.AreEqual(-1, mItem.Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(mItem.Severity));
  Assert.AreEqual('E2003', mItem.Code);
  Assert.AreEqual('Undeclared identifier: ''X''', mItem.Text);
  // Relativer Pfad, Hinweis.
  mItem := Parsed('Sub\Unit2.pas(30) Hint: H2164 Variable ''Y'' is declared but never used in ''Foo''');
  Assert.AreEqual('C:\P\Sub\Unit2.pas', mItem.FileName);
  Assert.AreEqual(Ord(TCompilerSeverity.Hint), Ord(mItem.Severity));
  Assert.AreEqual(Ord(TCompilerSeverity.Warning),
    Ord(Parsed('Unit1.pas(5) Warning: W1036 Variable ''Z'' might not have been initialized').Severity));
  // X-Codes (z. B. X1008 Integer und HRESULT vertauscht) sind Warnungen (#1040).
  mItem := Parsed('Unit1.pas(7) Warning: X1008 Integer and HRESULT interchanged');
  Assert.AreEqual('X1008', mItem.Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Warning), Ord(mItem.Severity));
  Assert.AreEqual('Integer and HRESULT interchanged', mItem.Text);
end;

procedure TCompilerOutputParserTests.ReadsColumns;
var
  mItem: TCompilerMessage;
begin
  mItem := Parsed('C:\P\Unit1.pas(12,5) Error: E2003 Undeclared identifier: ''X''');
  Assert.AreEqual(11, mItem.Line);
  Assert.AreEqual(4, mItem.Column);
end;

procedure TCompilerOutputParserTests.ReadsMsBuildLinesInAnyLanguage;
var
  mItem: TCompilerMessage;
begin
  mItem := Parsed('[dcc32 Fehler] Unit1.pas(12): E2003 Undeklarierter Bezeichner: ''X''');
  Assert.AreEqual('C:\P\Unit1.pas', mItem.FileName);
  Assert.AreEqual(11, mItem.Line);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(mItem.Severity));
  Assert.AreEqual('Undeklarierter Bezeichner: ''X''', mItem.Text);
  mItem := Parsed('[dcc64 Fatal Error] Projekt.dpr(5): F2613 Unit ''Foo'' not found.');
  Assert.AreEqual(Ord(TCompilerSeverity.Fatal), Ord(mItem.Severity));
  Assert.AreEqual('C:\P\Projekt.dpr', mItem.FileName);
end;

procedure TCompilerOutputParserTests.ReadsMessagesWithoutFile;
var
  mItem: TCompilerMessage;
begin
  mItem := Parsed('Fatal: F1026 File not found: ''Neu(1).dpr''');
  Assert.AreEqual('', mItem.FileName);
  Assert.AreEqual(-1, mItem.Line);
  Assert.AreEqual('F1026', mItem.Code);
  Assert.AreEqual('File not found: ''Neu(1).dpr''', mItem.Text);
end;

procedure TCompilerOutputParserTests.SkipsProgressLines;
var
  mItem: TCompilerMessage;
begin
  Assert.IsFalse(TCompilerOutputParser.ParseLine('Embarcadero Delphi for Win64 compiler version 36.0', 'C:\P', mItem));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('Unit1.pas(120)', 'C:\P', mItem));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('1234 lines, 0.50 seconds, 100 bytes code.', 'C:\P', mItem));
  Assert.IsFalse(TCompilerOutputParser.ParseLine('', 'C:\P', mItem));
end;

procedure TCompilerOutputParserTests.RemovesDuplicates;
var
  mFound: TArray<TCompilerMessage>;
begin
  mFound := TCompilerOutputParser.Parse([
    'Unit1.pas(1) Error: E2003 X',
    'Fortschritt',
    'Unit1.pas(1) Error: E2003 X',
    'Unit1.pas(2) Error: E2003 X'], 'C:\P');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[1].Line);
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
  mProject: TProjectInfo;
  mRequest: TCompilerRequest;
  mJoined: string;
begin
  mProject := Default(TProjectInfo);
  mProject.FileName := 'C:\P\Demo.dproj';
  mProject.MainSource := 'C:\P\Demo.dpr';
  mProject.Platform := 'Win64';
  mProject.Defines := ['DEBUG', 'FOO'];
  mProject.SearchPaths := ['C:\P\Lib'];
  mProject.Namespaces := ['System', 'Vcl'];
  mRequest := TCompilerCommandLine.Build(mProject, ['C:\Delphi\lib\win64\release'], 'C:\Delphi', 'C:\Temp\Out');
  Assert.AreEqual('C:\Delphi\bin\dcc64.exe', mRequest.Executable);
  Assert.AreEqual('C:\P', mRequest.WorkingDir);
  mJoined := string.Join(' ', mRequest.Arguments);
  Assert.Contains(mJoined, '-NUC:\Temp\Out -EC:\Temp\Out');
  // BPL und DCP eines Packages dürfen nicht in den gemeinsamen Bpl-Ordner.
  Assert.Contains(mJoined, '-LEC:\Temp\Out -LNC:\Temp\Out');
  Assert.Contains(mJoined, '-UC:\P\Lib;C:\Delphi\lib\win64\release');
  Assert.Contains(mJoined, '-DDEBUG;FOO');
  Assert.Contains(mJoined, '-NSSystem;Vcl');
  Assert.AreEqual('C:\P\Demo.dpr', mRequest.Arguments[High(mRequest.Arguments)]);
  mProject.MainSource := '';
  Assert.WillRaise(
    procedure
    begin
      TCompilerCommandLine.Build(mProject, nil, 'C:\Delphi', 'C:\Temp\Out');
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
  mResults: TCompilerResults;
  mGeneral: TCompilerMessage;
begin
  mResults := TCompilerResults.Create;
  try
    mGeneral := MessageAt('', -1, 'F1026');
    mResults.Replace([MessageAt('C:\P\A.pas', 1, 'E2003'), MessageAt('C:\P\B.pas', 2, 'W1036'),
      MessageAt('C:\P\A.pas', 5, 'H2164'), mGeneral]);
    Assert.AreEqual(2, Integer(Length(mResults.MessagesFor('c:\p\a.pas'))));
    Assert.AreEqual(1, Integer(Length(mResults.MessagesFor('C:\P\B.pas'))));
    Assert.AreEqual(0, Integer(Length(mResults.MessagesFor('C:\P\C.pas'))));
    Assert.AreEqual(1, Integer(Length(mResults.General)));
  finally
    mResults.Free;
  end;
end;

procedure TCompilerResultsTests.ReplaceReportsOldAndNewFiles;
var
  mResults: TCompilerResults;
  mFiles: TArray<string>;
begin
  mResults := TCompilerResults.Create;
  try
    mResults.Replace([MessageAt('C:\P\A.pas', 1, 'E2003')]);
    mFiles := mResults.Replace([MessageAt('C:\P\B.pas', 1, 'E2003')]);
    // A.pas muss geleert werden, B.pas bekommt die neue Meldung.
    Assert.AreEqual(2, Integer(Length(mFiles)));
    Assert.AreEqual(0, Integer(Length(mResults.MessagesFor('C:\P\A.pas'))));
  finally
    mResults.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerOutputParserTests);
  TDUnitX.RegisterTestFixture(TCompilerCommandLineTests);
  TDUnitX.RegisterTestFixture(TCompilerResultsTests);

end.
