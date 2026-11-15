unit Atlas.Core.Problems.Plan.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemsPlanTests = class
  public
    [Test]
    procedure ActiveWithProblemsOrDimming;
    [Test]
    procedure ShownNeedsEnabledAndProblems;
    [Test]
    procedure CompilerMergeUnlessBoth;
    [Test]
    procedure IsSourceByExtension;
    [Test]
    procedure CountsDueOnVisibilityOrVersion;
    [Test]
    procedure SwitchRemembersWaitsAndSyncs;
    [Test]
    procedure UsesHintByState;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Plan;

function Base: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.Enabled := True;
  Result.Problems := False;
  Result.InactiveDim := False;
  Result.DimUnusedUses := False;
end;

{ TAtlasProblemsPlanTests }

procedure TAtlasProblemsPlanTests.ActiveWithProblemsOrDimming;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Base;
  Assert.IsFalse(TAtlasProblemsPlan.Active(mSettings));
  mSettings.DimUnusedUses := True;
  Assert.IsTrue(TAtlasProblemsPlan.Active(mSettings));
  mSettings := Base;
  mSettings.InactiveDim := True;
  Assert.IsTrue(TAtlasProblemsPlan.Active(mSettings));
  Assert.IsTrue(TAtlasProblemsPlan.InactiveShown(mSettings));
  mSettings.Enabled := False;
  Assert.IsFalse(TAtlasProblemsPlan.Active(mSettings));
  Assert.IsFalse(TAtlasProblemsPlan.InactiveShown(mSettings));
end;

procedure TAtlasProblemsPlanTests.ShownNeedsEnabledAndProblems;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Base;
  mSettings.InactiveDim := True;
  Assert.IsFalse(TAtlasProblemsPlan.Shown(mSettings));
  mSettings.Problems := True;
  Assert.IsTrue(TAtlasProblemsPlan.Shown(mSettings));
  mSettings.Enabled := False;
  Assert.IsFalse(TAtlasProblemsPlan.Shown(mSettings));
end;

procedure TAtlasProblemsPlanTests.CompilerMergeUnlessBoth;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Base;
  mSettings.ProblemsCompilerMerge := 'Both';
  Assert.IsFalse(TAtlasProblemsPlan.CompilerMerge(mSettings));
  mSettings.ProblemsCompilerMerge := 'atlas';
  Assert.IsTrue(TAtlasProblemsPlan.CompilerMerge(mSettings));
end;

procedure TAtlasProblemsPlanTests.IsSourceByExtension;
begin
  Assert.IsTrue(TAtlasProblemsPlan.IsSource('C:\Src\Main.PAS'));
  Assert.IsTrue(TAtlasProblemsPlan.IsSource('App.dpr'));
  Assert.IsTrue(TAtlasProblemsPlan.IsSource('Pkg.dpk'));
  Assert.IsTrue(TAtlasProblemsPlan.IsSource('Defs.inc'));
  Assert.IsTrue(TAtlasProblemsPlan.IsSource('Tool.lpr'));
  Assert.IsFalse(TAtlasProblemsPlan.IsSource('Main.dfm'));
  Assert.IsFalse(TAtlasProblemsPlan.IsSource('pas'));
end;

procedure TAtlasProblemsPlanTests.CountsDueOnVisibilityOrVersion;
begin
  Assert.IsTrue(TAtlasProblemsPlan.CountsDue(True, False, 3, 3));
  Assert.IsTrue(TAtlasProblemsPlan.CountsDue(False, True, 3, 3));
  Assert.IsTrue(TAtlasProblemsPlan.CountsDue(True, True, 4, 3));
  Assert.IsFalse(TAtlasProblemsPlan.CountsDue(True, True, 3, 3));
  // Ausgeblendet zählt der Stand nicht.
  Assert.IsFalse(TAtlasProblemsPlan.CountsDue(False, False, 4, 3));
end;

procedure TAtlasProblemsPlanTests.SwitchRemembersWaitsAndSyncs;
begin
  Assert.AreEqual<TAtlasProblemsSwitch>(TAtlasProblemsSwitch.Remember, TAtlasProblemsPlan.Switch('', 'A.pas', False));
  Assert.AreEqual<TAtlasProblemsSwitch>(TAtlasProblemsSwitch.Remember,
    TAtlasProblemsPlan.Switch('a.PAS', 'A.pas', True));
  Assert.AreEqual<TAtlasProblemsSwitch>(TAtlasProblemsSwitch.Wait, TAtlasProblemsPlan.Switch('B.pas', 'A.pas', False));
  Assert.AreEqual<TAtlasProblemsSwitch>(TAtlasProblemsSwitch.SyncPrevious,
    TAtlasProblemsPlan.Switch('B.pas', 'A.pas', True));
end;

procedure TAtlasProblemsPlanTests.UsesHintByState;
begin
  Assert.AreEqual<TAtlasProblemsUsesHint>(TAtlasProblemsUsesHint.Initialization_,
    TAtlasProblemsPlan.UsesHint(TAtlasProblem.cUsesInitialization));
  Assert.AreEqual<TAtlasProblemsUsesHint>(TAtlasProblemsUsesHint.Allowlist,
    TAtlasProblemsPlan.UsesHint(TAtlasProblem.cUsesAllowlist));
  Assert.AreEqual<TAtlasProblemsUsesHint>(TAtlasProblemsUsesHint.Implementation_,
    TAtlasProblemsPlan.UsesHint(TAtlasProblem.cUsesImplementation));
  Assert.AreEqual<TAtlasProblemsUsesHint>(TAtlasProblemsUsesHint.Unused, TAtlasProblemsPlan.UsesHint(''));
  Assert.AreEqual<TAtlasProblemsUsesHint>(TAtlasProblemsUsesHint.Unused, TAtlasProblemsPlan.UsesHint('unused'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsPlanTests);

end.
