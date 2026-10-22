unit Atlas.Common.Lsp.Baseline.Tests;

// Tests für den Befehl atlas.updateBaseline (#97): schreibt die Baseline und
// antwortet mit den Zählern; Einträge ohne Datei, ältere Datei, keine leere
// Baseline ohne Projektdateien. Dateien und Prüfung sind ersetzt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspBaselineTests = class
  public
    /// <summary>Globale Testdaten leeren: Der Leckmonitor zählte sie sonst dem Test an.</summary>
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: atlas.updateBaseline schreibt die Baseline und antwortet mit den Zählern.</summary>
    [Test]
    procedure WritesBaselineAndAnswersCounters;
    [Test]
    procedure SecondRunCountsAgainstPreviousBaseline;
    [Test]
    procedure ReportsOrphanedEntries;
    [Test]
    procedure ReadsLegacyFileNameAndWritesNewName;
    [Test]
    procedure RefusesWithoutProjectFiles;
    [Test]
    procedure RefusesWithoutWorkspace;
    /// <summary>Bericht N3: Eine unbrauchbare bisherige Baseline wird nicht still ersetzt, sondern als .defekt
    /// beiseitegelegt und in "setAside" genannt.</summary>
    [Test]
    procedure InvalidPreviousBaselineIsSetAside;
    /// <summary>Lässt sie sich nicht beiseitelegen, wird sie trotzdem neu geschrieben (der Befehl soll sie neu
    /// schreiben); "setAside" fehlt dann.</summary>
    [Test]
    procedure InvalidPreviousBaselineIsReplacedWhenSetAsideFails;
    [Test]
    procedure UnreadableFileIsSkipped;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline;

const
  Root = 'C:\Projekt';
  UnitA =
    'unit A;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    'procedure TFoo.Bar;' + #10 +
    'begin' + #10 +
    '  X.Free;' + #10 +
    'end;' + #10 +
    'end.';

var
  /// <summary>Unechte Platte: voller Pfad → Inhalt.</summary>
  Disk: TDictionary<string, string>;
  /// <summary>Unechte Prüfung: voller Pfad → Zeilen mit einem Treffer der Regel "a".</summary>
  Hits: TDictionary<string, TArray<Integer>>;
  Written: string;
  /// <summary>Unechte Sperre: SetAside scheitert.</summary>
  Locked: Boolean;

function FullPath(const ARelative: string): string;
begin
  Result := Root + PathDelim + ARelative;
end;

function Files: TLspBaselineFiles;
begin
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := Disk.ContainsKey(AFileName);
    end;
  Result.Read :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Disk.TryGetValue(AFileName, AText);
    end;
  Result.Write :=
    procedure(const AFileName, AText: string)
    begin
      Disk.AddOrSetValue(AFileName, AText);
    end;
  Result.SetAside :=
    function(const AFileName: string; out ATarget: string): Boolean
    var
      Text: string;
    begin
      ATarget := AFileName + '.defekt';
      Result := not Locked and Disk.TryGetValue(AFileName, Text);
      if not Result then
        Exit;
      Disk.AddOrSetValue(ATarget, Text);
      Disk.Remove(AFileName);
    end;
end;

function CheckFile(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;
var
  Lines: TArray<Integer>;
  Line: Integer;
  Finding: TRuleFinding;
begin
  ACheck := Default(TLspBaselineCheck);
  Result := Disk.TryGetValue(AFileName, ACheck.Text);
  if not Result then
    Exit;
  ACheck.RelativePath := Copy(AFileName, Length(Root) + 2, MaxInt);
  if Hits.TryGetValue(AFileName, Lines) then
    for Line in Lines do
    begin
      Finding := Default(TRuleFinding);
      Finding.RuleId := 'a';
      Finding.Range := TTextRange.Create(TTextPosition.Create(Line, 2), TTextPosition.Create(Line, 8));
      ACheck.Findings := ACheck.Findings + [Finding];
    end;
end;

function MakeCommand(const AFiles: TArray<string>): TLspBaseline;
var
  ProjectFiles: TArray<string>;
begin
  ProjectFiles := AFiles;
  Result := TLspBaseline.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TServerSettings.Default;
      ASource.Root := Root;
      ASource.Files := ProjectFiles;
      Result := AProject;
    end,
    function(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean
    begin
      Result := CheckFile(AFileName, ACheck);
    end, Files);
  Result.OnWritten :=
    procedure(AFileName: string)
    begin
      Written := AFileName;
    end;
end;

function Run(ACommand: TLspBaseline): TJSONObject;
var
  Arguments: TJSONArray;
  Value: TJSONValue;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add('file:///C:/Projekt/Projekt.dproj');
    Value := ACommand.Execute(Arguments);
  finally
    Arguments.Free;
  end;
  Assert.IsTrue(Value is TJSONObject);
  Result := TJSONObject(Value);
end;

function NumberAt(AObject: TJSONObject; const APath: string): Integer;
var
  Value: TJSONValue;
begin
  Value := AObject.FindValue(APath);
  Assert.IsTrue(Value is TJSONNumber, APath);
  Result := TJSONNumber(Value).AsInt;
end;

function TextAt(AObject: TJSONObject; const APath: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.FindValue(APath);
  Assert.IsTrue(Value is TJSONString, APath);
  Result := TJSONString(Value).Value;
end;

/// <summary>Erster Eintrag von orphaned.entries.</summary>
function FirstOrphan(AAnswer: TJSONObject): TJSONObject;
var
  Entries: TJSONValue;
begin
  Entries := AAnswer.FindValue('orphaned.entries');
  Assert.IsTrue((Entries is TJSONArray) and (TJSONArray(Entries).Count > 0));
  Assert.IsTrue(TJSONArray(Entries).Items[0] is TJSONObject);
  Result := TJSONObject(TJSONArray(Entries).Items[0]);
end;

{ TLspBaselineTests }

/// <summary>Frischer Stand je Test: A.pas und B.pas mit je einem Treffer.</summary>
procedure Reset;
begin
  Disk.Clear;
  Hits.Clear;
  Written := '';
  Locked := False;
  Disk.Add(FullPath('A.pas'), UnitA);
  Disk.Add(FullPath('B.pas'), UnitA);
  Hits.Add(FullPath('A.pas'), [5]);
  Hits.Add(FullPath('B.pas'), [5]);
end;

procedure TLspBaselineTests.TearDown;
begin
  Disk.Clear;
  Hits.Clear;
  Written := '';
end;

procedure TLspBaselineTests.WritesBaselineAndAnswersCounters;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
  Baseline: IRuleBaseline;
begin
  Reset;
  Command := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual(TLspBaseline.Format, NumberAt(Answer, 'format'));
      Assert.AreEqual(FullPath(BaselineFileName), TextAt(Answer, 'file'));
      Assert.AreEqual('none', TextAt(Answer, 'previous'));
      Assert.AreEqual(2, NumberAt(Answer, 'total'));
      Assert.AreEqual(2, NumberAt(Answer, 'files'));
      Assert.AreEqual(2, NumberAt(Answer, 'added'));
      Assert.AreEqual(0, NumberAt(Answer, 'removed'));
      Assert.AreEqual(0, NumberAt(Answer, 'unchanged'));
      Assert.AreEqual(0, NumberAt(Answer, 'orphaned.count'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
  Assert.AreEqual(FullPath(BaselineFileName), Written);
  Baseline := TRuleBaseline.FromJson(Disk[FullPath(BaselineFileName)]);
  Assert.AreEqual(2, Integer(Baseline.Count));
  Assert.AreEqual(0, Baseline.LegacyCount);
end;

procedure TLspBaselineTests.SecondRunCountsAgainstPreviousBaseline;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
begin
  Reset;
  Command := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    Run(Command).Free;
    // B.pas ist bereinigt, A.pas hat einen Treffer mehr.
    Disk[FullPath('A.pas')] := StringReplace(UnitA, '  X.Free;', '  X.Free;' + #10 + '  Y.Free;', []);
    Hits[FullPath('A.pas')] := [5, 6];
    Hits[FullPath('B.pas')] := nil;
    Answer := Run(Command);
    try
      Assert.AreEqual('valid', TextAt(Answer, 'previous'));
      Assert.AreEqual(2, NumberAt(Answer, 'total'));
      Assert.AreEqual(1, NumberAt(Answer, 'added'));
      Assert.AreEqual(1, NumberAt(Answer, 'removed'));
      Assert.AreEqual(1, NumberAt(Answer, 'unchanged'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
end;

procedure TLspBaselineTests.ReportsOrphanedEntries;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
begin
  Reset;
  Command := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    Run(Command).Free;
  finally
    Command.Free;
  end;
  // B.pas umbenannt in C.pas.
  Disk.Remove(FullPath('B.pas'));
  Disk.Add(FullPath('C.pas'), UnitA);
  Hits.Add(FullPath('C.pas'), [5]);
  Command := MakeCommand([FullPath('A.pas'), FullPath('C.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual(1, NumberAt(Answer, 'orphaned.count'));
      Assert.AreEqual('B.pas', TextAt(FirstOrphan(Answer), 'path'));
      Assert.AreEqual(1, NumberAt(FirstOrphan(Answer), 'count'));
      Assert.AreEqual(1, NumberAt(Answer, 'removed'));
      Assert.AreEqual(1, NumberAt(Answer, 'added'));
      Assert.AreEqual(1, NumberAt(Answer, 'unchanged'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
end;

procedure TLspBaselineTests.ReadsLegacyFileNameAndWritesNewName;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
  Check: TLspBaselineCheck;
begin
  Reset;
  CheckFile(FullPath('A.pas'), Check);
  // Alte Datei unter dem früheren Namen und ohne Routine.
  Disk.Add(FullPath(LegacyBaselineFileName), '{"version": 1, "findings": [{"path": "A.pas", "rule": "a", ' +
    '"fingerprint": "' + TRuleBaseline.Fingerprint(UnitA, Check.Findings[0]) + '", "count": 1}]}');
  Command := MakeCommand([FullPath('A.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual('valid', TextAt(Answer, 'previous'));
      Assert.AreEqual(1, NumberAt(Answer, 'unchanged'));
      Assert.AreEqual(1, NumberAt(Answer, 'completed'));
      Assert.AreEqual(FullPath(BaselineFileName), TextAt(Answer, 'file'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
  Assert.IsTrue(Pos('"routine": "TFoo.Bar"', Disk[FullPath(BaselineFileName)]) > 0);
end;

procedure TLspBaselineTests.RefusesWithoutProjectFiles;
var
  Command: TLspBaseline;
  Raised: Boolean;
begin
  Reset;
  Disk.Add(FullPath(BaselineFileName), '{"version": 1, "findings": []}');
  Command := MakeCommand(nil);
  try
    Raised := False;
    try
      Run(Command).Free;
    except
      on EJsonRpcError do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
  finally
    Command.Free;
  end;
  Assert.AreEqual('', Written);
  Assert.AreEqual('{"version": 1, "findings": []}', Disk[FullPath(BaselineFileName)]);
end;

procedure TLspBaselineTests.RefusesWithoutWorkspace;
var
  Command: TLspBaseline;
  Raised: Boolean;
begin
  Reset;
  Command := TLspBaseline.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      Result := False;
    end,
    function(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean
    begin
      ACheck := Default(TLspBaselineCheck);
      Result := False;
    end, Files);
  try
    Raised := False;
    try
      Run(Command).Free;
    except
      on EJsonRpcError do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
  finally
    Command.Free;
  end;
end;

procedure TLspBaselineTests.InvalidPreviousBaselineIsSetAside;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
begin
  Reset;
  Disk.Add(FullPath(BaselineFileName), '{"version": 7}');
  Command := MakeCommand([FullPath('A.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual('invalid', TextAt(Answer, 'previous'));
      Assert.AreEqual(FullPath(BaselineFileName) + '.defekt', TextAt(Answer, 'setAside'));
      Assert.AreEqual(1, NumberAt(Answer, 'added'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
  Assert.AreEqual('{"version": 7}', Disk[FullPath(BaselineFileName) + '.defekt'], 'alter Inhalt bleibt erhalten');
  Assert.AreEqual(1, Integer(TRuleBaseline.FromJson(Disk[FullPath(BaselineFileName)]).Count));
end;

procedure TLspBaselineTests.InvalidPreviousBaselineIsReplacedWhenSetAsideFails;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
begin
  Reset;
  Locked := True;
  Disk.Add(FullPath(BaselineFileName), '{"version": 7}');
  Command := MakeCommand([FullPath('A.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual('invalid', TextAt(Answer, 'previous'));
      Assert.IsNull(Answer.FindValue('setAside'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
  Assert.IsFalse(Disk.ContainsKey(FullPath(BaselineFileName) + '.defekt'));
  Assert.AreEqual(1, Integer(TRuleBaseline.FromJson(Disk[FullPath(BaselineFileName)]).Count));
end;

procedure TLspBaselineTests.UnreadableFileIsSkipped;
var
  Command: TLspBaseline;
  Answer: TJSONObject;
begin
  Reset;
  Command := MakeCommand([FullPath('A.pas'), FullPath('Fehlt.pas')]);
  try
    Answer := Run(Command);
    try
      Assert.AreEqual(1, NumberAt(Answer, 'skipped'));
      Assert.AreEqual(1, NumberAt(Answer, 'files'));
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
end;

initialization
  // Mit Vorrat: Ein Test, der die Tabelle wachsen ließe, zählte sonst als Leck.
  Disk := TDictionary<string, string>.Create(64);
  Hits := TDictionary<string, TArray<Integer>>.Create(64);
  TDUnitX.RegisterTestFixture(TLspBaselineTests);

finalization
  Hits.Free;
  Disk.Free;

end.
