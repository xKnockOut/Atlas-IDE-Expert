unit Atlas.Core.Tests.Untested.Tests;

// Tests der ungetesteten Methoden (#1783) ohne IDE: Zeile des unit-Kopfs, wann die Marke steht und gelb ist,
// Parameter der Anfrage, Antwort lesen und die Reihenfolge der Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasUntestedTests = class
  public
    [Test]
    procedure UnitLineSkipsComments;
    [Test]
    procedure UnitLineOnlyForUnits;
    [Test]
    procedure ShownNeedsTestUnitAndMethods;
    [Test]
    procedure WarnBelowPercent;
    [Test]
    procedure WantedNeedsTestRunAndSwitch;
    [Test]
    procedure ParamsCarryDepthAndPrivate;
    [Test]
    procedure ReadsUnitsMostUntestedFirst;
    [Test]
    procedure NoObjectIsNoResult;
    [Test]
    procedure SortedDropsFullyTestedAndBreaksTies;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tests.Untested;

const
  cAnswer =
    '{"units":[' +
    '{"uri":"file:///C:/P/Basis.pas","unit":"Basis","hasTestUnit":true,"tested":2,"total":4,' +
    '"untested":[{"name":"TBaseline.Count","line":40,"character":19}]},' +
    '{"uri":"file:///C:/P/Andere.pas","unit":"Andere","hasTestUnit":false,"tested":0,"total":2,' +
    '"untested":[{"name":"Leer","line":4,"character":10},{"name":"Voll","line":8,"character":10}]},' +
    '{"uri":"file:///C:/P/Fertig.pas","unit":"Fertig","hasTestUnit":true,"tested":1,"total":1,"untested":[]}],' +
    '"skipped":3,"limits":["time"]}';

function UriAsPath(AUri: string): string;
begin
  Result := StringReplace(AUri, 'file:///', '', []);
end;

function UnitNamed(const AName: string; AUntested: Integer): TAtlasUntestedUnit;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasUntestedUnit);
  Result.UnitName := AName;
  Result.FileName := AName + '.pas';
  SetLength(Result.Untested, AUntested);
  for mIndex := 0 to AUntested - 1 do
  begin
    Result.Untested[mIndex] := Default(TAtlasUntestedMethod);
    Result.Untested[mIndex].Name := Format('M%d', [mIndex]);
  end;
end;

procedure TAtlasUntestedTests.UnitLineSkipsComments;
begin
  Assert.AreEqual(0, TAtlasUntested.UnitLine('unit Basis;'#13#10'interface'));
  Assert.AreEqual(0, TAtlasUntested.UnitLine(#$FEFF'unit Basis;'));
  Assert.AreEqual(3, TAtlasUntested.UnitLine('// Kopf'#10'{ Block'#10'  unit nicht hier }'#10'unit Basis;'));
  Assert.AreEqual(2, TAtlasUntested.UnitLine('(* alt'#10'*)'#10'  UNIT'#10'  Basis;'));
  Assert.AreEqual(1, TAtlasUntested.UnitLine('{$I Atlas.inc}'#10'unit Basis;'));
end;

procedure TAtlasUntestedTests.UnitLineOnlyForUnits;
begin
  Assert.AreEqual(-1, TAtlasUntested.UnitLine('program Tests;'#10'unit Basis;'));
  Assert.AreEqual(-1, TAtlasUntested.UnitLine('units := 1;'));
  Assert.AreEqual(-1, TAtlasUntested.UnitLine(''));
end;

procedure TAtlasUntestedTests.ShownNeedsTestUnitAndMethods;
begin
  Assert.IsTrue(TAtlasUntested.Shown(True, 3));
  Assert.IsFalse(TAtlasUntested.Shown(False, 3), 'ohne Testunit keine Marke');
  Assert.IsFalse(TAtlasUntested.Shown(True, 0), 'ohne Methoden keine Marke');
end;

procedure TAtlasUntestedTests.WarnBelowPercent;
begin
  Assert.IsTrue(TAtlasUntested.Warn(5, 12, 50), '5 von 12 liegt unter 50 %');
  Assert.IsFalse(TAtlasUntested.Warn(6, 12, 50), '6 von 12 sind genau 50 %');
  Assert.IsFalse(TAtlasUntested.Warn(0, 12, 0), '0 % = nie gelb');
  Assert.IsTrue(TAtlasUntested.Warn(11, 12, 100), 'unter 100 %');
  Assert.IsFalse(TAtlasUntested.Warn(0, 0, 50), 'ohne Methoden nie gelb');
end;

procedure TAtlasUntestedTests.WantedNeedsTestRunAndSwitch;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasUntested.Wanted(mSettings));
  mSettings.CodeLensUntested := False;
  Assert.IsFalse(TAtlasUntested.Wanted(mSettings));
  mSettings.CodeLensUntested := True;
  mSettings.TestRun := False;
  Assert.IsFalse(TAtlasUntested.Wanted(mSettings));
end;

procedure TAtlasUntestedTests.ParamsCarryDepthAndPrivate;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasUntested.ProjectParams('file:///C:/P/Basis.pas', 2, True)) as TJSONObject;
  try
    Assert.AreEqual('file:///C:/P/Basis.pas', mJson.GetValue<string>('textDocument.uri'));
    Assert.AreEqual(2, mJson.GetValue<Integer>('depth'));
    Assert.IsTrue(mJson.GetValue<Boolean>('includePrivate'));
    Assert.IsNull(mJson.GetValue('text'), 'ohne Text: der Server liest die Dateien');
  finally
    mJson.Free;
  end;
end;

procedure TAtlasUntestedTests.ReadsUnitsMostUntestedFirst;
var
  mProject: TAtlasUntestedProject;
begin
  Assert.IsTrue(TAtlasUntested.FromJson(cAnswer, UriAsPath, mProject));
  Assert.AreEqual(2, Integer(Length(mProject.Units)), 'Fertig hat keine ungetesteten Methoden');
  Assert.AreEqual('Andere', mProject.Units[0].UnitName);
  Assert.IsFalse(mProject.Units[0].HasTestUnit);
  Assert.AreEqual('C:/P/Andere.pas', mProject.Units[0].FileName);
  Assert.AreEqual('Voll', mProject.Units[0].Untested[1].Name);
  Assert.AreEqual(8, mProject.Units[0].Untested[1].Line);
  Assert.AreEqual('Basis', mProject.Units[1].UnitName);
  Assert.AreEqual(2, mProject.Units[1].Tested);
  Assert.AreEqual(4, mProject.Units[1].Total);
  Assert.AreEqual(19, mProject.Units[1].Untested[0].Character);
  Assert.AreEqual(3, mProject.Skipped);
  Assert.IsTrue(mProject.Incomplete);
  Assert.AreEqual(3, mProject.UntestedCount);
end;

procedure TAtlasUntestedTests.NoObjectIsNoResult;
var
  mProject: TAtlasUntestedProject;
begin
  Assert.IsFalse(TAtlasUntested.FromJson('[]', nil, mProject));
  Assert.IsFalse(TAtlasUntested.FromJson('', nil, mProject));
  Assert.AreEqual(0, Integer(Length(mProject.Units)));
end;

procedure TAtlasUntestedTests.SortedDropsFullyTestedAndBreaksTies;
var
  mSorted: TArray<TAtlasUntestedUnit>;
begin
  mSorted := TAtlasUntested.Sorted(TArray<TAtlasUntestedUnit>.Create(UnitNamed('Zeta', 2), UnitNamed('Leer', 0),
    UnitNamed('Alpha', 2), UnitNamed('Mitte', 5)));
  Assert.AreEqual(3, Integer(Length(mSorted)));
  Assert.AreEqual('Mitte', mSorted[0].UnitName);
  Assert.AreEqual('Alpha', mSorted[1].UnitName);
  Assert.AreEqual('Zeta', mSorted[2].UnitName);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUntestedTests);

end.
