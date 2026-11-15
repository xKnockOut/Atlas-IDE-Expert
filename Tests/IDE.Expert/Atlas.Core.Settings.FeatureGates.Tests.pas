unit Atlas.Core.Settings.FeatureGates.Tests;

// Tests für die zusammengesetzten Schalter des Plugins (#1967): Inline-Diagnosen hängen an Hauptschalter und
// Problemen, der Befundzähler der IDE weicht der eigenen Statusleiste mit Befunden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFeatureGatesTests = class
  public
    [Test]
    procedure InlineDiagnosticsFollowsSetting;
    [Test]
    procedure InlineDiagnosticsOffWithoutProblemsOrMainSwitch;
    [Test]
    procedure StatusCounterOnByItsSwitches;
    [Test]
    procedure StatusCounterYieldsToEditorStatusBarFindings;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Settings.FeatureGates;

function CounterSettings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.Enabled := True;
  Result.Problems := True;
  Result.ProblemsStatusCounter := True;
  Result.EditorStatusBar := False;
end;

{ TAtlasFeatureGatesTests }

procedure TAtlasFeatureGatesTests.InlineDiagnosticsFollowsSetting;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.InlineDiagnostics := 'all';
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.All), Ord(TAtlasFeatureGates.InlineDiagnostics(mSettings)));
  mSettings.InlineDiagnostics := 'off';
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasFeatureGates.InlineDiagnostics(mSettings)));
end;

procedure TAtlasFeatureGatesTests.InlineDiagnosticsOffWithoutProblemsOrMainSwitch;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.InlineDiagnostics := 'all';
  mSettings.Problems := False;
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasFeatureGates.InlineDiagnostics(mSettings)));
  mSettings.Problems := True;
  mSettings.Enabled := False;
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasFeatureGates.InlineDiagnostics(mSettings)));
end;

procedure TAtlasFeatureGatesTests.StatusCounterOnByItsSwitches;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  Assert.IsTrue(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
  mSettings.ProblemsStatusCounter := False;
  Assert.IsFalse(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
  mSettings := CounterSettings;
  mSettings.Problems := False;
  Assert.IsFalse(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
  mSettings := CounterSettings;
  mSettings.Enabled := False;
  Assert.IsFalse(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
end;

procedure TAtlasFeatureGatesTests.StatusCounterYieldsToEditorStatusBarFindings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.EditorStatusBarItems := 'status,findings';
  // Eigene Statusleiste aus: Zähler bleibt.
  Assert.IsTrue(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
  mSettings.EditorStatusBar := True;
  Assert.IsFalse(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
  // Eigene Statusleiste ohne Befunde: Zähler bleibt.
  mSettings.EditorStatusBarItems := 'status';
  Assert.IsTrue(TAtlasFeatureGates.ProblemsStatusCounter(mSettings));
end;

end.
