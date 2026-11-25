unit Atlas.Common.Rules.InstructionFiles.Tests;

// Tests für die Anweisungsdateien für KI-Assistenten (#2615): neue Datei als UTF-8 mit LF, vorhandene Datei behält
// BOM, Zeilenenden und Text außerhalb des Abschnitts, nur prüfen schreibt nichts, zweiter Lauf ist aktuell, Antwort
// des Befehls und seine Argumente.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleInstructionFilesTests = class
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CreatesMissingFileWithLf;
    [Test]
    procedure KeepsBomAndLineBreaksOutside;
    [Test]
    procedure CheckOnlyWritesNothing;
    [Test]
    procedure SecondRunIsCurrent;
    [Test]
    procedure ArgumentsAndAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Instructions,
  Atlas.Common.Rules.InstructionFiles;

var
  Files: TDictionary<string, TBytes>;

function ReadFile(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  Result := Files.TryGetValue(AFileName, ABytes);
end;

function WriteFile(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
begin
  AError := '';
  Files.AddOrSetValue(AFileName, ABytes);
  Result := True;
end;

function Run(AWrite: Boolean): TArray<TInstructionsFile>;
var
  mInstructions: TRuleInstructionFiles;
  mIssues: TArray<TConfigurationIssue>;
begin
  mInstructions := TRuleInstructionFiles.Create(ReadFile, WriteFile);
  try
    Result := mInstructions.Run('/p', TConfigurationParser.Parse('{"assistants": {"instructions": {"file": ' +
      '["AGENTS.md"]}}}', mIssues), BuiltinRules, AWrite);
  finally
    mInstructions.Free;
  end;
end;

function Stored: TBytes;
begin
  Assert.IsTrue(Files.TryGetValue('/p' + PathDelim + 'AGENTS.md', Result), 'Datei geschrieben');
end;

function Utf8(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

{ TRuleInstructionFilesTests }

procedure TRuleInstructionFilesTests.SetUp;
begin
  Files := TDictionary<string, TBytes>.Create;
end;

procedure TRuleInstructionFilesTests.TearDown;
begin
  FreeAndNil(Files);
end;

procedure TRuleInstructionFilesTests.CreatesMissingFileWithLf;
var
  mFiles: TArray<TInstructionsFile>;
  mText: string;
begin
  mFiles := Run(True);
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.AreEqual(Ord(TInstructionsState.Missing), Ord(mFiles[0].State));
  Assert.IsTrue(mFiles[0].Written);
  Assert.AreEqual('', mFiles[0].OldSection);
  mText := TEncoding.UTF8.GetString(Stored);
  Assert.StartsWith(TRuleInstructions.cBeginMarker, mText, 'ohne BOM');
  Assert.AreEqual(0, Pos(#13, mText), 'LF');
  Assert.EndsWith(TRuleInstructions.cEndMarker + #10, mText);
  mFiles := nil;
end;

procedure TRuleInstructionFilesTests.KeepsBomAndLineBreaksOutside;
const
  cHead = '# Projekt'#13#10'Größe: frei  '#13#10;
var
  mBytes: TBytes;
  mText: string;
begin
  Files.Add('/p' + PathDelim + 'AGENTS.md', TBytes.Create($EF, $BB, $BF) + Utf8(cHead));
  Run(True);
  mBytes := Stored;
  Assert.AreEqual($EF, Integer(mBytes[0]), 'BOM bleibt');
  mText := TEncoding.UTF8.GetString(Copy(mBytes, 3, MaxInt));
  Assert.StartsWith(cHead + #13#10 + TRuleInstructions.cBeginMarker, mText);
  Assert.AreEqual(0, Pos(#10, StringReplace(mText, #13#10, '', [rfReplaceAll])), 'nur CRLF');
  mBytes := nil;
end;

procedure TRuleInstructionFilesTests.CheckOnlyWritesNothing;
var
  mFiles: TArray<TInstructionsFile>;
begin
  mFiles := Run(False);
  Assert.AreEqual(0, Integer(Files.Count));
  Assert.IsFalse(mFiles[0].Written);
  Assert.AreEqual(1, TRuleInstructionFiles.StaleCount(mFiles));
  mFiles := nil;
end;

procedure TRuleInstructionFilesTests.SecondRunIsCurrent;
var
  mFiles: TArray<TInstructionsFile>;
  mFirst: TBytes;
begin
  Run(True);
  mFirst := Stored;
  mFiles := Run(True);
  Assert.AreEqual(Ord(TInstructionsState.Current), Ord(mFiles[0].State));
  Assert.IsFalse(mFiles[0].Written, 'aktueller Abschnitt wird nicht neu geschrieben');
  Assert.AreEqual(0, TRuleInstructionFiles.StaleCount(mFiles));
  Assert.AreEqual(mFiles[0].NewSection, mFiles[0].OldSection);
  Assert.AreEqual(Integer(Length(mFirst)), Integer(Length(Stored)), 'unverändert');
  mFiles := nil;
  mFirst := nil;
end;

procedure TRuleInstructionFilesTests.ArgumentsAndAnswer;
var
  mArguments: TJSONArray;
  mAnswer: TJSONObject;
  mItem: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue('[{"uri": "file:///p/U.pas", "write": true}]') as TJSONArray;
  try
    Assert.IsTrue(TRuleInstructionFiles.WriteRequested(mArguments));
    Assert.AreEqual('file:///p/U.pas', TRuleInstructionFiles.UriOf(mArguments));
  finally
    mArguments.Free;
  end;
  Assert.IsFalse(TRuleInstructionFiles.WriteRequested(nil));
  mAnswer := TRuleInstructionFiles.ToJson(Run(False));
  try
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('stale'));
    mItem := mAnswer.GetValue<TJSONArray>('files').Items[0] as TJSONObject;
    Assert.AreEqual('AGENTS.md', mItem.GetValue<string>('file'));
    Assert.AreEqual('missing', mItem.GetValue<string>('state'));
    Assert.StartsWith(TRuleInstructions.cBeginMarker, mItem.GetValue<string>('new'));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleInstructionFilesTests);

end.
