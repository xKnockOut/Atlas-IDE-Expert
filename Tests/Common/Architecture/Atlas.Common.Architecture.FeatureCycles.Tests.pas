unit Atlas.Common.Architecture.FeatureCycles.Tests;

// Zyklen und Richtungen zwischen Features. CasesFromFile prüft gegen
// Tests/Data/Architecture/feature-cycles.json, dieselbe Fallliste wie
// Tools/Check-PackageDependencies.ps1 -SelfTest.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFeatureCyclesTests = class
  public
    [Test]
    procedure FeatureOfLongestPrefix;
    [Test]
    procedure ParsesOptions;
    [Test]
    procedure CasesFromFile;
    [Test]
    procedure DirectionWinsOverCycle;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Common.Architecture.FeatureCycles;

function CasesFile: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Architecture', 'feature-cycles.json'))));
    if TFile.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

function VerdictName(AVerdict: TFeatureVerdict): string;
begin
  case AVerdict of
    TFeatureVerdict.Cycle:
      Result := 'cycle';
    TFeatureVerdict.Direction:
      Result := 'direction';
  else
    Result := 'none';
  end;
end;

/// <summary>Kanten eines Falls; Pfade aus "paths", sonst Source/&lt;Unit&gt;.pas.</summary>
function CaseEdges(ACase: TJSONObject): TArray<TFeatureEdge>;
var
  mPaths: TJSONObject;
  mEntry: string;
  mArrow: Integer;
  mSource, mTarget: string;

  function PathOf(const AUnit: string): string;
  var
    mValue: TJSONValue;
  begin
    Result := 'Source/' + AUnit + '.pas';
    if mPaths <> nil then
    begin
      mValue := mPaths.GetValue(AUnit);
      if mValue <> nil then
      begin
        Result := mValue.Value;
      end;
    end;
  end;

begin
  Result := nil;
  mPaths := nil;
  if ACase.GetValue('paths') is TJSONObject then
  begin
    mPaths := TJSONObject(ACase.GetValue('paths'));
  end;
  for mEntry in TJsonRead.Strings(ACase, 'edges') do
  begin
    mArrow := Pos('->', mEntry);
    mSource := Trim(Copy(mEntry, 1, mArrow - 1));
    mTarget := Trim(Copy(mEntry, mArrow + 2, MaxInt));
    Result := Result + [TFeatureEdge.Create(mSource, PathOf(mSource), mTarget, PathOf(mTarget))];
  end;
end;

{ TFeatureCyclesTests }

procedure TFeatureCyclesTests.FeatureOfLongestPrefix;
var
  mPrefix, mFeature: string;
begin
  Assert.IsTrue(TFeatureCycles.FeatureOf('Atlas.Core.Lsp.Session', ['Atlas.Core', 'Atlas.Core.Lsp'], mPrefix,
    mFeature));
  Assert.AreEqual('Atlas.Core.Lsp', mPrefix);
  Assert.AreEqual('Session', mFeature);
  Assert.IsTrue(TFeatureCycles.FeatureOf('Atlas.Text.Columns', ['Atlas.Text'], mPrefix, mFeature));
  Assert.AreEqual('Columns', mFeature, 'Unit ohne Rolle: der Name nach dem Präfix');
  Assert.IsFalse(TFeatureCycles.FeatureOf('Atlas.Core', ['Atlas.Core'], mPrefix, mFeature), 'nur das Präfix');
  Assert.IsFalse(TFeatureCycles.FeatureOf('System.SysUtils', ['Atlas.Core'], mPrefix, mFeature));
  Assert.IsFalse(TFeatureCycles.FeatureOf('Atlas.CoreX.Lsp', ['Atlas.Core'], mPrefix, mFeature),
    'Präfix endet an einem Punkt');
end;

procedure TFeatureCyclesTests.ParsesOptions;
var
  mOptions: TFeatureCycleOptions;
begin
  mOptions := TFeatureCycleOptions.Parse('{"prefixes": ["Atlas.Core", " "], "exclude": ["Tests/**"], ' +
    '"known": ["Atlas.Core: A, B"], "directions": ["Atlas.Common: A < B"], "knownEdges": ["X -> Y"]}');
  Assert.AreEqual(1, Integer(Length(mOptions.Prefixes)), 'leere Einträge fallen weg');
  Assert.AreEqual('Tests/**', mOptions.Exclude[0]);
  Assert.AreEqual('Atlas.Core: A, B', mOptions.Known[0]);
  Assert.AreEqual('Atlas.Common: A < B', mOptions.Directions[0]);
  Assert.AreEqual('X -> Y', mOptions.KnownEdges[0]);
  mOptions := TFeatureCycleOptions.Parse('kein JSON');
  Assert.AreEqual(0, Integer(Length(mOptions.Prefixes)));
  mOptions := Default(TFeatureCycleOptions);
end;

procedure TFeatureCyclesTests.CasesFromFile;
var
  mFileName, mName, mDetail, mExpected: string;
  mRoot: TJSONValue;
  mItem, mVerdictItem: TJSONValue;
  mCase_, mVerdict: TJSONObject;
  mAnalysis: IFeatureCycles;
  mCount: Integer;
begin
  mFileName := CasesFile;
  Assert.AreNotEqual('', mFileName, 'Tests\Data\Architecture\feature-cycles.json nicht gefunden');
  mRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(mFileName, TEncoding.UTF8));
  try
    Assert.IsTrue(mRoot is TJSONObject);
    mCount := 0;
    for mItem in TJSONObject(mRoot).GetValue<TJSONArray>('cases') do
    begin
      mCase_ := mItem as TJSONObject;
      mName := mCase_.GetValue<string>('name');
      mAnalysis := TFeatureCycles.Analyze(TFeatureCycleOptions.Parse(mCase_.GetValue('options').ToJSON),
        CaseEdges(mCase_));
      Assert.AreEqual(string.Join(' | ', TJsonRead.Strings(mCase_, 'findings')),
        string.Join(' | ', mAnalysis.Findings), mName);
      if mCase_.GetValue('verdicts') is TJSONArray then
      begin
        for mVerdictItem in TJSONArray(mCase_.GetValue('verdicts')) do
        begin
          mVerdict := mVerdictItem as TJSONObject;
          Assert.AreEqual(mVerdict.GetValue<string>('verdict'), VerdictName(mAnalysis.Verdict(
            mVerdict.GetValue<string>('from'), mVerdict.GetValue<string>('to'), mDetail)),
            mName + ': ' + mVerdict.GetValue<string>('from'));
          if mVerdict.GetValue('detail') <> nil then
          begin
            mExpected := mVerdict.GetValue<string>('detail');
            Assert.AreEqual(mExpected, mDetail, mName + ': Detail');
          end;
        end;
      end;
      mAnalysis := nil;
      Inc(mCount);
    end;
    Assert.IsTrue(mCount >= 10, 'Fallliste unvollständig');
  finally
    mRoot.Free;
  end;
end;

procedure TFeatureCyclesTests.DirectionWinsOverCycle;
var
  mOptions: TFeatureCycleOptions;
  mAnalysis: IFeatureCycles;
  mDetail: string;
begin
  mOptions := Default(TFeatureCycleOptions);
  mOptions.Prefixes := TArray<string>.Create('Atlas.Common');
  mOptions.Directions := TArray<string>.Create('Atlas.Common: Rules < Lsp');
  mAnalysis := TFeatureCycles.Analyze(mOptions, TArray<TFeatureEdge>.Create(
    TFeatureEdge.Create('Atlas.Common.Rules.A', '', 'Atlas.Common.Lsp.B', ''),
    TFeatureEdge.Create('Atlas.Common.Lsp.B', '', 'Atlas.Common.Rules.A', '')));
  Assert.AreEqual(Ord(TFeatureVerdict.Direction), Ord(mAnalysis.Verdict('atlas.common.rules.a',
    'Atlas.Common.Lsp.B', mDetail)), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual('Atlas.Common: Rules < Lsp', mDetail);
  Assert.AreEqual(Ord(TFeatureVerdict.Cycle), Ord(mAnalysis.Verdict('Atlas.Common.Lsp.B', 'Atlas.Common.Rules.A',
    mDetail)));
  mAnalysis := nil;
  mOptions := Default(TFeatureCycleOptions);
end;

initialization
  TDUnitX.RegisterTestFixture(TFeatureCyclesTests);

end.
