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
    /// <summary>Eine unbrauchbare bisherige Baseline wird nicht still ersetzt, sondern als .defekt
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
  cRoot = 'C:\Projekt';
  cUnitA =
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
  Result := cRoot + PathDelim + ARelative;
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
      begin
        Exit;
      end;
      Disk.AddOrSetValue(ATarget, Text);
      Disk.Remove(AFileName);
    end;
end;

function CheckFile(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;
var
  mLines: TArray<Integer>;
  mLine: Integer;
  mFinding: TRuleFinding;
begin
  ACheck := Default(TLspBaselineCheck);
  Result := Disk.TryGetValue(AFileName, ACheck.Text);
  if not Result then
  begin
    Exit;
  end;
  ACheck.RelativePath := Copy(AFileName, Length(cRoot) + 2, MaxInt);
  if Hits.TryGetValue(AFileName, mLines) then
  begin
    for mLine in mLines do
    begin
      mFinding := Default(TRuleFinding);
      mFinding.RuleId := 'a';
      mFinding.Range := TTextRange.Create(TTextPosition.Create(mLine, 2), TTextPosition.Create(mLine, 8));
      ACheck.Findings := ACheck.Findings + [mFinding];
    end;
  end;
end;

function MakeCommand(const AFiles: TArray<string>): TLspBaseline;
var
  mProjectFiles: TArray<string>;
begin
  mProjectFiles := AFiles;
  Result := TLspBaseline.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TServerSettings.Default;
      ASource.Root := cRoot;
      ASource.Files := mProjectFiles;
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
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('file:///C:/Projekt/Projekt.dproj');
    mValue := ACommand.Execute(mArguments);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mValue is TJSONObject);
  Result := TJSONObject(mValue);
end;

function NumberAt(AObject: TJSONObject; const APath: string): Integer;
var
  mValue: TJSONValue;
begin
  mValue := AObject.FindValue(APath);
  Assert.IsTrue(mValue is TJSONNumber, APath);
  Result := TJSONNumber(mValue).AsInt;
end;

function TextAt(AObject: TJSONObject; const APath: string): string;
var
  mValue: TJSONValue;
begin
  mValue := AObject.FindValue(APath);
  Assert.IsTrue(mValue is TJSONString, APath);
  Result := TJSONString(mValue).Value;
end;

/// <summary>Erster Eintrag von orphaned.entries.</summary>
function FirstOrphan(AAnswer: TJSONObject): TJSONObject;
var
  mEntries: TJSONValue;
begin
  mEntries := AAnswer.FindValue('orphaned.entries');
  Assert.IsTrue((mEntries is TJSONArray) and (TJSONArray(mEntries).Count > 0));
  Assert.IsTrue(TJSONArray(mEntries).Items[0] is TJSONObject);
  Result := TJSONObject(TJSONArray(mEntries).Items[0]);
end;

{ TLspBaselineTests }

/// <summary>Frischer Stand je Test: A.pas und B.pas mit je einem Treffer.</summary>
procedure Reset;
begin
  Disk.Clear;
  Hits.Clear;
  Written := '';
  Locked := False;
  Disk.Add(FullPath('A.pas'), cUnitA);
  Disk.Add(FullPath('B.pas'), cUnitA);
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
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
  mBaseline: IRuleBaseline;
begin
  Reset;
  mCommand := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual(TLspBaseline.cFormat, NumberAt(mAnswer, 'format'));
      Assert.AreEqual(FullPath(cBaselineFileName), TextAt(mAnswer, 'file'));
      Assert.AreEqual('none', TextAt(mAnswer, 'previous'));
      Assert.AreEqual(2, NumberAt(mAnswer, 'total'));
      Assert.AreEqual(2, NumberAt(mAnswer, 'files'));
      Assert.AreEqual(2, NumberAt(mAnswer, 'added'));
      Assert.AreEqual(0, NumberAt(mAnswer, 'removed'));
      Assert.AreEqual(0, NumberAt(mAnswer, 'unchanged'));
      Assert.AreEqual(0, NumberAt(mAnswer, 'orphaned.count'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
  Assert.AreEqual(FullPath(cBaselineFileName), Written);
  mBaseline := TRuleBaseline.FromJson(Disk[FullPath(cBaselineFileName)]);
  Assert.AreEqual(2, Integer(mBaseline.Count));
  Assert.AreEqual(0, mBaseline.LegacyCount);
end;

procedure TLspBaselineTests.SecondRunCountsAgainstPreviousBaseline;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
begin
  Reset;
  mCommand := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    Run(mCommand).Free;
    // B.pas ist bereinigt, A.pas hat einen Treffer mehr.
    Disk[FullPath('A.pas')] := StringReplace(cUnitA, '  X.Free;', '  X.Free;' + #10 + '  Y.Free;', []);
    Hits[FullPath('A.pas')] := [5, 6];
    Hits[FullPath('B.pas')] := nil;
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual('valid', TextAt(mAnswer, 'previous'));
      Assert.AreEqual(2, NumberAt(mAnswer, 'total'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'added'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'removed'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'unchanged'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
end;

procedure TLspBaselineTests.ReportsOrphanedEntries;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
begin
  Reset;
  mCommand := MakeCommand([FullPath('A.pas'), FullPath('B.pas')]);
  try
    Run(mCommand).Free;
  finally
    mCommand.Free;
  end;
  // B.pas umbenannt in C.pas.
  Disk.Remove(FullPath('B.pas'));
  Disk.Add(FullPath('C.pas'), cUnitA);
  Hits.Add(FullPath('C.pas'), [5]);
  mCommand := MakeCommand([FullPath('A.pas'), FullPath('C.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual(1, NumberAt(mAnswer, 'orphaned.count'));
      Assert.AreEqual('B.pas', TextAt(FirstOrphan(mAnswer), 'path'));
      Assert.AreEqual(1, NumberAt(FirstOrphan(mAnswer), 'count'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'removed'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'added'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'unchanged'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
end;

procedure TLspBaselineTests.ReadsLegacyFileNameAndWritesNewName;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
  mCheck: TLspBaselineCheck;
begin
  Reset;
  CheckFile(FullPath('A.pas'), mCheck);
  // Alte Datei unter dem früheren Namen und ohne Routine.
  Disk.Add(FullPath(cLegacyBaselineFileName), '{"version": 1, "findings": [{"path": "A.pas", "rule": "a", ' +
    '"fingerprint": "' + TRuleBaseline.Fingerprint(cUnitA, mCheck.Findings[0]) + '", "count": 1}]}');
  mCommand := MakeCommand([FullPath('A.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual('valid', TextAt(mAnswer, 'previous'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'unchanged'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'completed'));
      Assert.AreEqual(FullPath(cBaselineFileName), TextAt(mAnswer, 'file'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
  Assert.IsTrue(Pos('"routine": "TFoo.Bar"', Disk[FullPath(cBaselineFileName)]) > 0);
end;

procedure TLspBaselineTests.RefusesWithoutProjectFiles;
var
  mCommand: TLspBaseline;
  mRaised: Boolean;
begin
  Reset;
  Disk.Add(FullPath(cBaselineFileName), '{"version": 1, "findings": []}');
  mCommand := MakeCommand(nil);
  try
    mRaised := False;
    try
      Run(mCommand).Free;
    except
      on EJsonRpcError do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
  finally
    mCommand.Free;
  end;
  Assert.AreEqual('', Written);
  Assert.AreEqual('{"version": 1, "findings": []}', Disk[FullPath(cBaselineFileName)]);
end;

procedure TLspBaselineTests.RefusesWithoutWorkspace;
var
  mCommand: TLspBaseline;
  mRaised: Boolean;
begin
  Reset;
  mCommand := TLspBaseline.Create(
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
    mRaised := False;
    try
      Run(mCommand).Free;
    except
      on EJsonRpcError do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
  finally
    mCommand.Free;
  end;
end;

procedure TLspBaselineTests.InvalidPreviousBaselineIsSetAside;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
begin
  Reset;
  Disk.Add(FullPath(cBaselineFileName), '{"version": 7}');
  mCommand := MakeCommand([FullPath('A.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual('invalid', TextAt(mAnswer, 'previous'));
      Assert.AreEqual(FullPath(cBaselineFileName) + '.defekt', TextAt(mAnswer, 'setAside'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'added'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
  Assert.AreEqual('{"version": 7}', Disk[FullPath(cBaselineFileName) + '.defekt'], 'alter Inhalt bleibt erhalten');
  Assert.AreEqual(1, Integer(TRuleBaseline.FromJson(Disk[FullPath(cBaselineFileName)]).Count));
end;

procedure TLspBaselineTests.InvalidPreviousBaselineIsReplacedWhenSetAsideFails;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
begin
  Reset;
  Locked := True;
  Disk.Add(FullPath(cBaselineFileName), '{"version": 7}');
  mCommand := MakeCommand([FullPath('A.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual('invalid', TextAt(mAnswer, 'previous'));
      Assert.IsNull(mAnswer.FindValue('setAside'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
  Assert.IsFalse(Disk.ContainsKey(FullPath(cBaselineFileName) + '.defekt'));
  Assert.AreEqual(1, Integer(TRuleBaseline.FromJson(Disk[FullPath(cBaselineFileName)]).Count));
end;

procedure TLspBaselineTests.UnreadableFileIsSkipped;
var
  mCommand: TLspBaseline;
  mAnswer: TJSONObject;
begin
  Reset;
  mCommand := MakeCommand([FullPath('A.pas'), FullPath('Fehlt.pas')]);
  try
    mAnswer := Run(mCommand);
    try
      Assert.AreEqual(1, NumberAt(mAnswer, 'skipped'));
      Assert.AreEqual(1, NumberAt(mAnswer, 'files'));
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
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
