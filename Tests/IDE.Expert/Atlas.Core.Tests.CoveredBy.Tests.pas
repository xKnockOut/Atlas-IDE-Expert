unit Atlas.Core.Tests.CoveredBy.Tests;

// Tests der Marke „getestet von“ (#1778) ohne IDE: Parameter der Anfrage, Antwort lesen, Namen der Tests zerlegen,
// Stand der Marke über mehrere Tests und die Namen für --run.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasCoveredByTests = class
  public
    [Test]
    procedure ParamsCarryTextDepthAndPrivate;
    [Test]
    procedure ReadsMethodsAndTests;
    [Test]
    procedure NoObjectIsNoResult;
    [Test]
    procedure SplitsUnitWithDots;
    [Test]
    procedure TallyNeedsEveryTest;
    [Test]
    procedure TallyFailedWins;
    [Test]
    procedure RunNamesWithoutDuplicates;
    [Test]
    procedure WantedNeedsTestRunAndSwitch;
    [Test]
    procedure TestUnitHasFixtures;
    [Test]
    procedure StaleKeysReadEachFileOnce;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.CoveredBy;

const
  cAnswer =
    '{"unit":"Basis","depth":1,"testUnit":false,"hasTestUnit":true,"tested":1,"total":2,"limits":["time"],' +
    '"methods":[{"name":"TBaseline.Match","line":20,"character":19,"visibility":"public","public":true,' +
    '"tests":[{"name":"Basis.Tests.TBaselineTests.MatchFindet","run":["Basis.Tests.TBaselineTests.MatchFindet"],' +
    '"uri":"file:///C:/P/Basis.Tests.pas","line":14,"level":1,"inferred":false}]},' +
    '{"name":"Pruefe","line":30,"character":10,"visibility":"public","public":true,"tests":[]}]}';

function UriAsPath(AUri: string): string;
begin
  Result := StringReplace(AUri, 'file:///', '', []);
end;

function Covered(const AName: string): TAtlasCoveredTest;
begin
  Result := Default(TAtlasCoveredTest);
  Result.Name := AName;
  Result.RunNames := TArray<string>.Create(AName);
end;

function Tally(ARan, APassed, AFailed: Integer): TAtlasTestTally;
begin
  Result := Default(TAtlasTestTally);
  Result.Total := 1;
  Result.Ran := ARan;
  Result.Passed := APassed;
  Result.Failed := AFailed;
end;

/// <summary>Stand je Methode: Eins bestanden, Zwei fehlgeschlagen, sonst ohne Ergebnis.</summary>
function Results(const AUnitName, AFixture, AMethod: string): TAtlasTestTally;
begin
  if AMethod = 'Eins' then
  begin
    Result := Tally(1, 1, 0);
  end
  else if AMethod = 'Zwei' then
  begin
    Result := Tally(1, 0, 1);
  end
  else
  begin
    Result := Tally(0, 0, 0);
  end;
end;

procedure TAtlasCoveredByTests.ParamsCarryTextDepthAndPrivate;
var
  mValue: TJSONValue;
  mParams: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasCoveredBy.Params('file:///C:/P/Basis.pas', 'unit Basis;', 2, True));
  try
    mParams := mValue as TJSONObject;
    Assert.AreEqual('file:///C:/P/Basis.pas', mParams.GetValue<string>('textDocument.uri'));
    Assert.AreEqual('unit Basis;', mParams.GetValue<string>('text'));
    Assert.AreEqual(2, mParams.GetValue<Integer>('depth'));
    Assert.IsTrue(mParams.GetValue<Boolean>('includePrivate'));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasCoveredByTests.ReadsMethodsAndTests;
var
  mUnit: TAtlasCoveredUnit;
begin
  Assert.IsTrue(TAtlasCoveredBy.FromJson(cAnswer, UriAsPath, mUnit));
  Assert.AreEqual('Basis', mUnit.UnitName);
  Assert.IsTrue(mUnit.HasTestUnit);
  Assert.IsFalse(mUnit.IsTestUnit);
  Assert.IsTrue(mUnit.Incomplete, 'Grenze erreicht');
  Assert.AreEqual(2, Integer(Length(mUnit.Methods)));
  Assert.AreEqual(1, mUnit.Tested);
  Assert.AreEqual(0, mUnit.MethodAt(20));
  Assert.AreEqual(1, mUnit.MethodAt(30));
  Assert.AreEqual(-1, mUnit.MethodAt(21));
  Assert.AreEqual('TBaseline.Match', mUnit.Methods[0].Name);
  Assert.AreEqual(19, mUnit.Methods[0].Character);
  Assert.AreEqual(1, Integer(Length(mUnit.Methods[0].Tests)));
  Assert.AreEqual('C:/P/Basis.Tests.pas', mUnit.Methods[0].Tests[0].FileName);
  Assert.AreEqual(14, mUnit.Methods[0].Tests[0].Line);
  Assert.AreEqual(0, Integer(Length(mUnit.Methods[1].Tests)));
end;

procedure TAtlasCoveredByTests.NoObjectIsNoResult;
var
  mUnit: TAtlasCoveredUnit;
begin
  Assert.IsFalse(TAtlasCoveredBy.FromJson('', UriAsPath, mUnit));
  Assert.IsFalse(TAtlasCoveredBy.FromJson('[1]', UriAsPath, mUnit));
  Assert.AreEqual(0, Integer(Length(mUnit.Methods)));
end;

procedure TAtlasCoveredByTests.SplitsUnitWithDots;
var
  mUnitName, mFixture, mMethod: string;
begin
  Assert.IsTrue(TAtlasCoveredBy.SplitName('Basis.Tests.TBaselineTests.MatchFindet', mUnitName, mFixture, mMethod));
  Assert.AreEqual('Basis.Tests', mUnitName);
  Assert.AreEqual('TBaselineTests', mFixture);
  Assert.AreEqual('MatchFindet', mMethod);
  Assert.IsFalse(TAtlasCoveredBy.SplitName('TBaselineTests.MatchFindet', mUnitName, mFixture, mMethod));
end;

procedure TAtlasCoveredByTests.TallyNeedsEveryTest;
var
  mTally: TAtlasTestTally;
begin
  // Eins bestand, Drei lief noch nicht: Teilstand, nicht grün.
  mTally := TAtlasCoveredBy.TallyOf(TArray<TAtlasCoveredTest>.Create(Covered('U.F.Eins'), Covered('U.F.Drei')), Results);
  Assert.AreEqual(2, mTally.Total);
  Assert.AreEqual(1, mTally.Ran);
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Partial, mTally.Shown);
  mTally := TAtlasCoveredBy.TallyOf(TArray<TAtlasCoveredTest>.Create(Covered('U.F.Eins')), Results);
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Passed, mTally.Shown);
  mTally := TAtlasCoveredBy.TallyOf(TArray<TAtlasCoveredTest>.Create(Covered('U.F.Drei')), Results);
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Unknown, mTally.Shown);
end;

procedure TAtlasCoveredByTests.TallyFailedWins;
var
  mTally: TAtlasTestTally;
begin
  mTally := TAtlasCoveredBy.TallyOf(TArray<TAtlasCoveredTest>.Create(Covered('U.F.Eins'), Covered('U.F.Zwei')), Results);
  Assert.AreEqual(1, mTally.Failed);
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Failed, mTally.Shown);
end;

procedure TAtlasCoveredByTests.RunNamesWithoutDuplicates;
var
  mNames: TArray<string>;
begin
  mNames := TAtlasCoveredBy.RunNames(TArray<TAtlasCoveredTest>.Create(Covered('U.F.Eins'), Covered('U.F.Zwei'),
    Covered('U.F.Eins')));
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('U.F.Eins', mNames[0]);
  Assert.AreEqual('U.F.Zwei', mNames[1]);
end;

procedure TAtlasCoveredByTests.WantedNeedsTestRunAndSwitch;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasCoveredBy.Wanted(mSettings));
  mSettings.CodeLensCoveredBy := False;
  Assert.IsFalse(TAtlasCoveredBy.Wanted(mSettings));
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.TestRun := False;
  Assert.IsFalse(TAtlasCoveredBy.Wanted(mSettings));
end;

procedure TAtlasCoveredByTests.TestUnitHasFixtures;
const
  cTestUnit =
    'unit Basis.Tests;'#13#10'interface'#13#10'uses DUnitX.TestFramework;'#13#10'type'#13#10 +
    '  [TestFixture]'#13#10'  TBasisTests = class'#13#10'  public'#13#10'    [Test]'#13#10'    procedure Eins;'#13#10 +
    '  end;'#13#10'implementation'#13#10'procedure TBasisTests.Eins;'#13#10'begin'#13#10'end;'#13#10'end.';
begin
  Assert.IsTrue(TAtlasCoveredBy.IsTestUnit(cTestUnit));
  Assert.IsFalse(TAtlasCoveredBy.IsTestUnit('unit Basis;'#13#10'interface'#13#10'implementation'#13#10'end.'));
end;

procedure TAtlasCoveredByTests.StaleKeysReadEachFileOnce;
var
  mTests: TArray<TAtlasCoveredTest>;
  mKeys: TArray<string>;
  mReads: Integer;
begin
  mTests := TArray<TAtlasCoveredTest>.Create(Covered('U.F.Eins'), Covered('U.F.Zwei'), Covered('V.G.Drei'));
  mTests[0].FileName := 'U.pas';
  mTests[1].FileName := 'U.pas';
  mTests[2].FileName := 'V.pas';
  mReads := 0;
  mKeys := TAtlasCoveredBy.StaleKeysOf(mTests,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Inc(mReads);
      ALines := TArray<string>.Create(AFileName);
      Result := True;
    end,
    function(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<string>
    begin
      Result := TArray<string>.Create('stale:' + ALines[0]);
    end);
  Assert.AreEqual(2, mReads, 'jede Testunit einmal');
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual('stale:U.pas', mKeys[0]);
  Assert.AreEqual('stale:V.pas', mKeys[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasCoveredBy.StaleKeysOf(mTests, nil, nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCoveredByTests);

end.
