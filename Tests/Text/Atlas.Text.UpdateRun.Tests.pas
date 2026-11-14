unit Atlas.Text.UpdateRun.Tests;

// Tests des Ablaufs zwischen Plugin und AtlasUpdate.exe (#1519): Aufruf mit
// Argumenten, state.json und result.json.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextUpdateRunTests = class
  public
    [Test]
    procedure ParsesArguments;
    [Test]
    procedure ArgumentsRoundTrip;
    [Test]
    procedure QuotesLikeCommandLineToArgv;
    [Test]
    procedure StageRoundTrip;
    [Test]
    procedure BrokenStateIsFailed;
    [Test]
    procedure OutcomeRoundTrip;
    [Test]
    procedure NamesOfPhases;
    [Test]
    procedure JoinsWindowsPaths;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.UpdateRun;

procedure TTextUpdateRunTests.ParsesArguments;
var
  mArgs: TUpdateArguments;
begin
  mArgs := TUpdateArguments.Parse(TArray<string>.Create('apply', '--version', '2.0.1', '--ide', '37.0',
    '--platform', 'Win64', '--select', 'Atlas.IDE.Base,Atlas.IDE.Debugger', '--wait-pid', '1234',
    '--new-modules', 'skip', '--unbekannt', 'x'));
  Assert.AreEqual('apply', mArgs.Command);
  Assert.AreEqual('2.0.1', mArgs.Version);
  Assert.AreEqual('Win64', mArgs.Platform);
  Assert.AreEqual(2, Integer(Length(mArgs.Select)));
  Assert.AreEqual('Atlas.IDE.Debugger', mArgs.Select[1]);
  Assert.AreEqual(Cardinal(1234), mArgs.WaitPid);
  Assert.AreEqual<TUpdateNewModules>(TUpdateNewModules.Skip, mArgs.NewModules);
end;

procedure TTextUpdateRunTests.ArgumentsRoundTrip;
var
  mArgs, mCopy: TUpdateArguments;
begin
  mArgs := Default(TUpdateArguments);
  mArgs.Command := 'prepare';
  mArgs.ManifestUrl := 'https://example.org/atlas-version.json';
  mArgs.RegistryKey := 'Software\Embarcadero\Mein Profil\37.0';
  mArgs.Target := 'C:\Program Files\Atlas\';
  mArgs.Previous := '2.0.0';
  mArgs.NewModules := TUpdateNewModules.Install;
  mCopy := TUpdateArguments.Parse(mArgs.ToArgs);
  Assert.AreEqual(mArgs.ManifestUrl, mCopy.ManifestUrl);
  Assert.AreEqual(mArgs.RegistryKey, mCopy.RegistryKey);
  Assert.AreEqual(mArgs.Target, mCopy.Target);
  Assert.AreEqual('2.0.0', mCopy.Previous);
  Assert.AreEqual<TUpdateNewModules>(TUpdateNewModules.Install, mCopy.NewModules);
  Assert.IsTrue(mArgs.CommandLine.StartsWith('prepare '));
end;

procedure TTextUpdateRunTests.QuotesLikeCommandLineToArgv;
begin
  Assert.AreEqual('abc', TUpdateNames.QuoteArgument('abc'));
  Assert.AreEqual('"a b"', TUpdateNames.QuoteArgument('a b'));
  Assert.AreEqual('""', TUpdateNames.QuoteArgument(''));
  // Schrägstriche vor dem schließenden Anführungszeichen verdoppeln.
  Assert.AreEqual('"C:\Program Files\\"', TUpdateNames.QuoteArgument('C:\Program Files\'));
  Assert.AreEqual('"a\"b"', TUpdateNames.QuoteArgument('a"b'));
end;

procedure TTextUpdateRunTests.StageRoundTrip;
var
  mStage, mCopy: TUpdateStage;
begin
  mStage := Default(TUpdateStage);
  mStage.Phase := TUpdatePhase.Ready;
  mStage.Progress := 100;
  mStage.Version := '2.0.1';
  mStage.FromSource := True;
  mStage.AskSelection := True;
  mStage.Updater := 'C:\Staging\files\AtlasUpdate.exe';
  SetLength(mStage.Candidates, 2);
  mStage.Candidates[0].Name := 'Atlas.IDE.Base';
  mStage.Candidates[0].Required := True;
  mStage.Candidates[0].Selected := True;
  mStage.Candidates[1].Name := 'Atlas.IDE.Search';
  mStage.Candidates[1].IsNew := True;
  mCopy := TUpdateStage.FromJson(mStage.ToJson);
  Assert.AreEqual<TUpdatePhase>(TUpdatePhase.Ready, mCopy.Phase);
  Assert.AreEqual(100, mCopy.Progress);
  Assert.IsTrue(mCopy.FromSource);
  Assert.IsTrue(mCopy.AskSelection);
  Assert.AreEqual(mStage.Updater, mCopy.Updater);
  Assert.AreEqual(2, Integer(Length(mCopy.Candidates)));
  Assert.IsTrue(mCopy.Candidates[1].IsNew);
  Assert.IsFalse(mCopy.Candidates[1].Selected);
  Assert.AreEqual(1, Integer(Length(mCopy.SelectedNames)));
end;

procedure TTextUpdateRunTests.BrokenStateIsFailed;
begin
  Assert.AreEqual<TUpdatePhase>(TUpdatePhase.Failed, TUpdateStage.FromJson('{kaputt').Phase);
  Assert.AreEqual<TUpdatePhase>(TUpdatePhase.Failed, TUpdateStage.FromJson('').Phase);
end;

procedure TTextUpdateRunTests.OutcomeRoundTrip;
var
  mOutcome, mCopy: TUpdateOutcome;
begin
  mOutcome := Default(TUpdateOutcome);
  mOutcome.Kind := TUpdateOutcomeKind.RolledBack;
  mOutcome.Version := '2.0.1';
  mOutcome.Previous := '2.0.0';
  mOutcome.Reason := TUpdateErrors.cLocked;
  mOutcome.Detail := 'Win32\Atlas.IDE.Base370.bpl';
  mOutcome.Added := TArray<string>.Create('Atlas.IDE.Search');
  mCopy := TUpdateOutcome.FromJson(mOutcome.ToJson);
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.RolledBack, mCopy.Kind);
  Assert.AreEqual('2.0.0', mCopy.Previous);
  Assert.AreEqual(TUpdateErrors.cLocked, mCopy.Reason);
  Assert.AreEqual(mOutcome.Detail, mCopy.Detail);
  Assert.AreEqual('Atlas.IDE.Search', mCopy.Added[0]);
  Assert.AreEqual(0, Integer(Length(mCopy.Removed)));
end;

procedure TTextUpdateRunTests.NamesOfPhases;
var
  mPhase: TUpdatePhase;
  mValue: TUpdateNewModules;
begin
  for mPhase := Low(TUpdatePhase) to High(TUpdatePhase) do
  begin
    Assert.AreEqual<TUpdatePhase>(mPhase, TUpdateNames.ParsePhase(TUpdateNames.PhaseName(mPhase)));
  end;
  for mValue := Low(TUpdateNewModules) to High(TUpdateNewModules) do
  begin
    Assert.AreEqual<TUpdateNewModules>(mValue, TUpdateNames.ParseNewModules(TUpdateNames.NewModulesName(mValue)));
  end;
  Assert.AreEqual<TUpdateNewModules>(TUpdateNewModules.Ask, TUpdateNames.ParseNewModules('quatsch'));
  Assert.AreEqual<TUpdateOutcomeKind>(TUpdateOutcomeKind.Installed, TUpdateNames.ParseOutcome('installed'));
end;

procedure TTextUpdateRunTests.JoinsWindowsPaths;
begin
  Assert.AreEqual('C:\A\b.txt', TUpdateLayout.Join('C:\A', 'b.txt'));
  Assert.AreEqual('C:\A\b.txt', TUpdateLayout.Join('C:\A\', 'b.txt'));
  Assert.AreEqual('b.txt', TUpdateLayout.Join('', 'b.txt'));
end;

end.
