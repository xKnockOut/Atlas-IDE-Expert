unit Atlas.Core.BuildPipeline.Plan.Tests;

// Tests für die Entscheidungen der Build-Pipeline in der IDE (#528, #533):
// Ablehnung eines Auftrags, Quelltextdateien, Regel-IDs und Konfiguration
// für „Release prüfen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
  TAtlasBuildPipelinePlanTests = class
  public
    /// <summary>Ablehnung in fester Reihenfolge; nur Make, Build und Check werden gebaut.</summary>
    [Test]
    procedure RefusalInOrder;
    /// <summary>Quelltext sind .pas, .dpr und .dpk.</summary>
    [Test]
    procedure PascalFiles;
    /// <summary>Regel-IDs ohne Doppelte in der Reihenfolge des ersten Auftretens.</summary>
    [Test]
    procedure RulesUnique;
    /// <summary>Aktive Release-Konfiguration, sonst „Release“, sonst die erste Release-Konfiguration.</summary>
    [Test]
    procedure ConfigurationForCheck;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.BuildPipeline.Plan;

function IsFinal(AName: string): Boolean;
begin
  Result := SameText(AName, 'Final') or SameText(AName, 'Release');
end;

{ TAtlasBuildPipelinePlanTests }

procedure TAtlasBuildPipelinePlanTests.RefusalInOrder;
begin
  Assert.AreEqual(Ord(TAtlasBuildRefusal.None),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, False, False, TAtlasCompileKind.Build)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.Busy),
    Ord(TAtlasBuildPipelinePlan.Refusal(True, True, True, TAtlasCompileKind.Clean)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.ForeignBuild),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, True, True, TAtlasCompileKind.Clean)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.Debugging),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, False, True, TAtlasCompileKind.Clean)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.Kind),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, False, False, TAtlasCompileKind.Clean)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.None),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, False, False, TAtlasCompileKind.Check)));
  Assert.AreEqual(Ord(TAtlasBuildRefusal.None),
    Ord(TAtlasBuildPipelinePlan.Refusal(False, False, False, TAtlasCompileKind.Make)));
end;

procedure TAtlasBuildPipelinePlanTests.PascalFiles;
begin
  Assert.IsTrue(TAtlasBuildPipelinePlan.IsPascalFile('C:\P\A.PAS'));
  Assert.IsTrue(TAtlasBuildPipelinePlan.IsPascalFile('C:\P\App.dpr'));
  Assert.IsTrue(TAtlasBuildPipelinePlan.IsPascalFile('C:\P\Pkg.dpk'));
  Assert.IsFalse(TAtlasBuildPipelinePlan.IsPascalFile('C:\P\Main.dfm'));
end;

procedure TAtlasBuildPipelinePlanTests.RulesUnique;
var
  mRules: TArray<string>;
begin
  mRules := TAtlasBuildPipelinePlan.UniqueRules(TArray<string>.Create('b', 'a', 'b', 'c', 'a'));
  Assert.AreEqual('b,a,c', string.Join(',', mRules));
  Assert.AreEqual(0, Integer(Length(TAtlasBuildPipelinePlan.UniqueRules(nil))));
  mRules := nil;
end;

procedure TAtlasBuildPipelinePlanTests.ConfigurationForCheck;
var
  mConfigurations: TArray<string>;
begin
  mConfigurations := TArray<string>.Create('Debug', 'Final', 'Release');
  Assert.AreEqual('Final', TAtlasBuildPipelinePlan.CheckConfiguration('Final', mConfigurations, 'Release', IsFinal),
    'aktive ist Release');
  Assert.AreEqual('Release', TAtlasBuildPipelinePlan.CheckConfiguration('Debug', mConfigurations, 'Release',
    IsFinal), '„Release“ vor anderen');
  mConfigurations := TArray<string>.Create('Debug', 'Final');
  Assert.AreEqual('Final', TAtlasBuildPipelinePlan.CheckConfiguration('Debug', mConfigurations, 'Release', IsFinal));
  mConfigurations := TArray<string>.Create('Debug');
  Assert.AreEqual('', TAtlasBuildPipelinePlan.CheckConfiguration('Debug', mConfigurations, 'Release', IsFinal));
  mConfigurations := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildPipelinePlanTests);

end.
