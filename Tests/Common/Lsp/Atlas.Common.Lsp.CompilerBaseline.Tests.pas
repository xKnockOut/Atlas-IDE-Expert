unit Atlas.Common.Lsp.CompilerBaseline.Tests;

// Tests für Compilermeldungen in der Baseline (#530):
// atlas.baselineCompilerMessages und atlas.classifyCompilerMessages mit
// unechter Platte. Abnahme: Nach „In die Basislinie“ zählt dieselbe Meldung
// nicht mehr, eine neue zählt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspCompilerBaselineTests = class
  public
    [Setup]
    procedure Setup;
    /// <summary>Globale Testdaten leeren: Der Leckmonitor zählte sie sonst dem Test an.</summary>
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: übernommene Meldung steht in der Baseline, eine neue nicht.</summary>
    [Test]
    procedure AddedMessageIsBaselinedNewOneIsNot;
    [Test]
    procedure SurvivesShiftedLines;
    [Test]
    procedure KeepsRuleEntries;
    [Test]
    procedure SkipsErrorsAndForeignFiles;
    [Test]
    procedure ClassifyWithoutBaseline;
    [Test]
    procedure RefusesInvalidBaseline;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.CompilerBaseline;

const
  Root = 'C:\Projekt';
  UnitA =
    'unit A;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    'function TFoo.Bar: Integer;' + #10 +
    'var' + #10 +
    '  X: Integer;' + #10 +
    'begin' + #10 +
    'end;' + #10 +
    'end.';

var
  /// <summary>Unechte Platte: voller Pfad → Inhalt.</summary>
  Disk: TDictionary<string, string>;

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
  Result.SetAside := nil;
end;

function MakeCommand: TLspCompilerBaseline;
begin
  Result := TLspCompilerBaseline.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TServerSettings.Default;
      ASource.Root := Root;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Disk.TryGetValue(AFileName, AText);
    end, Files);
end;

function Msg(const AFileName: string; ALine: Integer; const ACode: string): TLspCompilerMessage;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Code := ACode;
end;

function Source: TLspMetricsSource;
begin
  Result := Default(TLspMetricsSource);
  Result.Root := Root;
end;

function Classified(ACommand: TLspCompilerBaseline; const AMessages: TArray<TLspCompilerMessage>): TArray<Boolean>;
var
  Previous: string;
begin
  Result := ACommand.Classify(Source, AMessages, Previous);
end;

{ TLspCompilerBaselineTests }

procedure TLspCompilerBaselineTests.Setup;
begin
  Disk.Clear;
  Disk.Add(FullPath('A.pas'), UnitA);
end;

procedure TLspCompilerBaselineTests.TearDown;
begin
  Disk.Clear;
end;

procedure TLspCompilerBaselineTests.AddedMessageIsBaselinedNewOneIsNot;
var
  Command: TLspCompilerBaseline;
  Arguments, Items: TJSONArray;
  Item: TJSONObject;
  Answer: TJSONValue;
  Baselined: TArray<Boolean>;
begin
  Command := MakeCommand;
  try
    // Zeile 6 (1-basiert): "  X: Integer;" – H2164 Variable X wird nicht verwendet.
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('file:///C:/Projekt/Projekt.dproj');
      Item := TJSONObject.Create;
      Item.AddPair('file', FullPath('A.pas'));
      Item.AddPair('line', TJSONNumber.Create(6));
      Item.AddPair('code', 'h2164');
      Items := TJSONArray.Create;
      Items.AddElement(Item);
      Arguments.AddElement(Items);
      Answer := Command.ExecuteAdd(Arguments);
    finally
      Arguments.Free;
    end;
    try
      Assert.IsTrue(Answer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(Answer).GetValue<Integer>('total', -1));
      Assert.AreEqual(1, TJSONObject(Answer).GetValue<Integer>('added', -1));
      Assert.AreEqual('none', TJSONObject(Answer).GetValue<string>('previous', ''));
    finally
      Answer.Free;
    end;
    Assert.IsTrue(Disk.ContainsKey(IncludeTrailingPathDelimiter(Root) + BaselineFileName));
    Baselined := Classified(Command, [Msg(FullPath('A.pas'), 6, 'H2164'), Msg(FullPath('A.pas'), 4,
      'W1035')]);
    Assert.IsTrue(Baselined[0], 'dieselbe Meldung zählt nicht mehr');
    Assert.IsFalse(Baselined[1], 'eine neue Meldung zählt');
  finally
    Command.Free;
  end;
end;

procedure TLspCompilerBaselineTests.SurvivesShiftedLines;
var
  Command: TLspCompilerBaseline;
begin
  Command := MakeCommand;
  try
    Command.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
    // Zwei Zeilen oberhalb eingefügt: Zuordnung über Zeile und Routine, nicht über die Nummer.
    Disk[FullPath('A.pas')] := StringReplace(UnitA, 'implementation' + #10, 'implementation' + #10 + 'uses' + #10 +
      '  B;' + #10, []);
    Assert.IsTrue(Classified(Command, [Msg(FullPath('A.pas'), 8, 'H2164')])[0]);
  finally
    Command.Free;
  end;
end;

procedure TLspCompilerBaselineTests.KeepsRuleEntries;
var
  Command: TLspCompilerBaseline;
  Baseline: IRuleBaseline;
begin
  Disk.Add(IncludeTrailingPathDelimiter(Root) + BaselineFileName,
    '{"version": 1, "findings": [{"path": "A.pas", "rule": "empty-except", "fingerprint": "00000000", ' +
    '"count": 2}]}');
  Command := MakeCommand;
  try
    Command.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
  finally
    Command.Free;
  end;
  Baseline := TRuleBaseline.FromJson(Disk[IncludeTrailingPathDelimiter(Root) + BaselineFileName]);
  Assert.AreEqual(3, Baseline.Count, 'zwei Regeltreffer und eine Compilermeldung');
end;

procedure TLspCompilerBaselineTests.SkipsErrorsAndForeignFiles;
var
  Command: TLspCompilerBaseline;
  Answer: string;
  Value: TJSONValue;
begin
  Command := MakeCommand;
  try
    Answer := Command.Add(Source, [Msg(FullPath('A.pas'), 6, 'E2003'), Msg('D:\Fremd\X.pas', 1, 'W1035'),
      Msg(FullPath('Fehlt.pas'), 1, 'H2164'), Msg(FullPath('A.pas'), 6, 'H2164')]);
  finally
    Command.Free;
  end;
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Assert.AreEqual(1, TJSONObject(Value).GetValue<Integer>('total', -1), 'Fehler kommen nicht in die Baseline');
    Assert.AreEqual(2, TJSONObject(Value).GetValue<Integer>('skipped', -1), 'fremde und fehlende Datei');
  finally
    Value.Free;
  end;
end;

procedure TLspCompilerBaselineTests.ClassifyWithoutBaseline;
var
  Command: TLspCompilerBaseline;
  Answer: TJSONValue;
  Arguments: TJSONArray;
begin
  Command := MakeCommand;
  try
    Arguments := TJSONObject.ParseJSONValue('[null, [{"file": "x", "line": 1, "code": "H2164"}]]') as TJSONArray;
    try
      Answer := Command.ExecuteClassify(Arguments);
    finally
      Arguments.Free;
    end;
    try
      Assert.AreEqual('none', TJSONObject(Answer).GetValue<string>('baseline', ''));
      Assert.AreEqual(0, TJSONArray(TJSONObject(Answer).GetValue('baselined')).Count);
    finally
      Answer.Free;
    end;
  finally
    Command.Free;
  end;
end;

procedure TLspCompilerBaselineTests.RefusesInvalidBaseline;
var
  Command: TLspCompilerBaseline;
  Raised: Boolean;
begin
  Disk.Add(IncludeTrailingPathDelimiter(Root) + BaselineFileName, '{kaputt');
  Command := MakeCommand;
  try
    Raised := False;
    try
      Command.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
    except
      on EJsonRpcError do
        Raised := True;
    end;
    Assert.IsTrue(Raised, 'eine unlesbare Baseline wird nicht still ersetzt');
    Assert.AreEqual('{kaputt', Disk[IncludeTrailingPathDelimiter(Root) + BaselineFileName]);
  finally
    Command.Free;
  end;
end;

initialization
  // Mit Vorrat: Ein Test, der die Tabelle wachsen ließe, zählte sonst als Leck.
  Disk := TDictionary<string, string>.Create(64);
  TDUnitX.RegisterTestFixture(TLspCompilerBaselineTests);

finalization
  Disk.Free;

end.
