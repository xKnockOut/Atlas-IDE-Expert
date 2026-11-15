unit Atlas.Core.Problems.Switches.Tests;

// Tests für die zusammengesetzten Schalter des Plugins (#1967): Inline-Diagnosen hängen an Hauptschalter und
// Problemen, der Befundzähler der IDE weicht der eigenen Statusleiste mit Befunden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemSwitchesTests = class
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
  Atlas.Core.Problems.Switches;

function CounterSettings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.Enabled := True;
  Result.Problems := True;
  Result.ProblemsStatusCounter := True;
  Result.EditorStatusBar := False;
end;

{ TAtlasProblemSwitchesTests }

procedure TAtlasProblemSwitchesTests.InlineDiagnosticsFollowsSetting;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.InlineDiagnostics := 'all';
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.All), Ord(TAtlasProblemSwitches.InlineDiagnostics(mSettings)));
  mSettings.InlineDiagnostics := 'off';
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasProblemSwitches.InlineDiagnostics(mSettings)));
end;

procedure TAtlasProblemSwitchesTests.InlineDiagnosticsOffWithoutProblemsOrMainSwitch;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.InlineDiagnostics := 'all';
  mSettings.Problems := False;
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasProblemSwitches.InlineDiagnostics(mSettings)));
  mSettings.Problems := True;
  mSettings.Enabled := False;
  Assert.AreEqual(Ord(TAtlasInlineDiagnosticsMode.Off), Ord(TAtlasProblemSwitches.InlineDiagnostics(mSettings)));
end;

procedure TAtlasProblemSwitchesTests.StatusCounterOnByItsSwitches;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  Assert.IsTrue(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
  mSettings.ProblemsStatusCounter := False;
  Assert.IsFalse(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
  mSettings := CounterSettings;
  mSettings.Problems := False;
  Assert.IsFalse(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
  mSettings := CounterSettings;
  mSettings.Enabled := False;
  Assert.IsFalse(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
end;

procedure TAtlasProblemSwitchesTests.StatusCounterYieldsToEditorStatusBarFindings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := CounterSettings;
  mSettings.EditorStatusBarItems := 'status,findings';
  // Eigene Statusleiste aus: Zähler bleibt.
  Assert.IsTrue(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
  mSettings.EditorStatusBar := True;
  Assert.IsFalse(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
  // Eigene Statusleiste ohne Befunde: Zähler bleibt.
  mSettings.EditorStatusBarItems := 'status';
  Assert.IsTrue(TAtlasProblemSwitches.ProblemsStatusCounter(mSettings));
end;

end.
