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
  cRoot = 'C:\Projekt';
  cUnitA =
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
  Result.SetAside := nil;
end;

function MakeCommand: TLspCompilerBaseline;
begin
  Result := TLspCompilerBaseline.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TServerSettings.Default;
      ASource.Root := cRoot;
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
  Result.Root := cRoot;
end;

function Classified(ACommand: TLspCompilerBaseline; const AMessages: TArray<TLspCompilerMessage>): TArray<Boolean>;
var
  mPrevious: string;
begin
  Result := ACommand.Classify(Source, AMessages, mPrevious);
end;

{ TLspCompilerBaselineTests }

procedure TLspCompilerBaselineTests.Setup;
begin
  Disk.Clear;
  Disk.Add(FullPath('A.pas'), cUnitA);
end;

procedure TLspCompilerBaselineTests.TearDown;
begin
  Disk.Clear;
end;

procedure TLspCompilerBaselineTests.AddedMessageIsBaselinedNewOneIsNot;
var
  mCommand: TLspCompilerBaseline;
  mArguments, mItems: TJSONArray;
  mItem: TJSONObject;
  mAnswer: TJSONValue;
  mBaselined: TArray<Boolean>;
begin
  mCommand := MakeCommand;
  try
    // Zeile 6 (1-basiert): "  X: Integer;" – H2164 Variable X wird nicht verwendet.
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('file:///C:/Projekt/Projekt.dproj');
      mItem := TJSONObject.Create;
      mItem.AddPair('file', FullPath('A.pas'));
      mItem.AddPair('line', TJSONNumber.Create(6));
      mItem.AddPair('code', 'h2164');
      mItems := TJSONArray.Create;
      mItems.AddElement(mItem);
      mArguments.AddElement(mItems);
      mAnswer := mCommand.ExecuteAdd(mArguments);
    finally
      mArguments.Free;
    end;
    try
      Assert.IsTrue(mAnswer is TJSONObject);
      Assert.AreEqual(1, TJSONObject(mAnswer).GetValue<Integer>('total', -1));
      Assert.AreEqual(1, TJSONObject(mAnswer).GetValue<Integer>('added', -1));
      Assert.AreEqual('none', TJSONObject(mAnswer).GetValue<string>('previous', ''));
    finally
      mAnswer.Free;
    end;
    Assert.IsTrue(Disk.ContainsKey(IncludeTrailingPathDelimiter(cRoot) + cBaselineFileName));
    mBaselined := Classified(mCommand, [Msg(FullPath('A.pas'), 6, 'H2164'), Msg(FullPath('A.pas'), 4,
      'W1035')]);
    Assert.IsTrue(mBaselined[0], 'dieselbe Meldung zählt nicht mehr');
    Assert.IsFalse(mBaselined[1], 'eine neue Meldung zählt');
  finally
    mCommand.Free;
  end;
end;

procedure TLspCompilerBaselineTests.SurvivesShiftedLines;
var
  mCommand: TLspCompilerBaseline;
begin
  mCommand := MakeCommand;
  try
    mCommand.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
    // Zwei Zeilen oberhalb eingefügt: Zuordnung über Zeile und Routine, nicht über die Nummer.
    Disk[FullPath('A.pas')] := StringReplace(cUnitA, 'implementation' + #10, 'implementation' + #10 + 'uses' + #10 +
      '  B;' + #10, []);
    Assert.IsTrue(Classified(mCommand, [Msg(FullPath('A.pas'), 8, 'H2164')])[0]);
  finally
    mCommand.Free;
  end;
end;

procedure TLspCompilerBaselineTests.KeepsRuleEntries;
var
  mCommand: TLspCompilerBaseline;
  mBaseline: IRuleBaseline;
begin
  Disk.Add(IncludeTrailingPathDelimiter(cRoot) + cBaselineFileName,
    '{"version": 1, "findings": [{"path": "A.pas", "rule": "empty-except", "fingerprint": "00000000", ' +
    '"count": 2}]}');
  mCommand := MakeCommand;
  try
    mCommand.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
  finally
    mCommand.Free;
  end;
  mBaseline := TRuleBaseline.FromJson(Disk[IncludeTrailingPathDelimiter(cRoot) + cBaselineFileName]);
  Assert.AreEqual(3, mBaseline.Count, 'zwei Regeltreffer und eine Compilermeldung');
end;

procedure TLspCompilerBaselineTests.SkipsErrorsAndForeignFiles;
var
  mCommand: TLspCompilerBaseline;
  mAnswer: string;
  mValue: TJSONValue;
begin
  mCommand := MakeCommand;
  try
    mAnswer := mCommand.Add(Source, [Msg(FullPath('A.pas'), 6, 'E2003'), Msg('D:\Fremd\X.pas', 1, 'W1035'),
      Msg(FullPath('Fehlt.pas'), 1, 'H2164'), Msg(FullPath('A.pas'), 6, 'H2164')]);
  finally
    mCommand.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(mAnswer);
  try
    Assert.AreEqual(1, TJSONObject(mValue).GetValue<Integer>('total', -1), 'Fehler kommen nicht in die Baseline');
    Assert.AreEqual(2, TJSONObject(mValue).GetValue<Integer>('skipped', -1), 'fremde und fehlende Datei');
  finally
    mValue.Free;
  end;
end;

procedure TLspCompilerBaselineTests.ClassifyWithoutBaseline;
var
  mCommand: TLspCompilerBaseline;
  mAnswer: TJSONValue;
  mArguments: TJSONArray;
begin
  mCommand := MakeCommand;
  try
    mArguments := TJSONObject.ParseJSONValue('[null, [{"file": "x", "line": 1, "code": "H2164"}]]') as TJSONArray;
    try
      mAnswer := mCommand.ExecuteClassify(mArguments);
    finally
      mArguments.Free;
    end;
    try
      Assert.AreEqual('none', TJSONObject(mAnswer).GetValue<string>('baseline', ''));
      Assert.AreEqual(0, TJSONArray(TJSONObject(mAnswer).GetValue('baselined')).Count);
    finally
      mAnswer.Free;
    end;
  finally
    mCommand.Free;
  end;
end;

procedure TLspCompilerBaselineTests.RefusesInvalidBaseline;
var
  mCommand: TLspCompilerBaseline;
  mRaised: Boolean;
begin
  Disk.Add(IncludeTrailingPathDelimiter(cRoot) + cBaselineFileName, '{kaputt');
  mCommand := MakeCommand;
  try
    mRaised := False;
    try
      mCommand.Add(Source, [Msg(FullPath('A.pas'), 6, 'H2164')]);
    except
      on EJsonRpcError do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised, 'eine unlesbare Baseline wird nicht still ersetzt');
    Assert.AreEqual('{kaputt', Disk[IncludeTrailingPathDelimiter(cRoot) + cBaselineFileName]);
  finally
    mCommand.Free;
  end;
end;

initialization
  // Mit Vorrat: Ein Test, der die Tabelle wachsen ließe, zählte sonst als Leck.
  Disk := TDictionary<string, string>.Create(64);
  TDUnitX.RegisterTestFixture(TLspCompilerBaselineTests);

finalization
  Disk.Free;

end.
