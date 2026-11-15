unit Atlas.Core.Debug.VisualizerFlow.Tests;

// Tests für die Entscheidungen der Debug-Visualisierer außerhalb von Erkennung und Text (#835, #1967):
// Ansichtsfenster, Optionen, neue Anmeldung, Art und Text; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasVisualizerFlowTests = class
  public
    [Test]
    procedure ViewerOnlyForViewKinds;
    [Test]
    procedure OptionsFromSettings;
    [Test]
    procedure ReregisterOnSwitchOrKinds;
    [Test]
    procedure WantsAndShown;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Debug.VisualizerFlow;

{ TAtlasVisualizerFlowTests }

procedure TAtlasVisualizerFlowTests.ViewerOnlyForViewKinds;
begin
  Assert.IsTrue(TAtlasVisualizerFlow.HasViewer(TAtlasVisualizerKind.Lists));
  Assert.IsTrue(TAtlasVisualizerFlow.HasViewer(TAtlasVisualizerKind.Graphics));
  Assert.IsFalse(TAtlasVisualizerFlow.HasViewer(TAtlasVisualizerKind.Guid));
  Assert.IsFalse(TAtlasVisualizerFlow.HasViewer(TAtlasVisualizerKind.Geometry));
  Assert.IsTrue(TAtlasVisualizerFlow.ValidType(0, 2));
  Assert.IsFalse(TAtlasVisualizerFlow.ValidType(2, 2));
  Assert.IsFalse(TAtlasVisualizerFlow.ValidType(-1, 2));
end;

procedure TAtlasVisualizerFlowTests.OptionsFromSettings;
var
  mSettings: TAtlasPluginSettings;
  mOptions: TAtlasVisualizerOptions;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.DebugVisualizerTypes := 'lists,json';
  mSettings.DebugVisualizerMaxLength := 77;
  mSettings.DebugVisualizerMaxImagePixels := 1234;
  mOptions := TAtlasVisualizerFlow.OptionsOf(mSettings);
  Assert.AreEqual(TAtlasVisualizerSettings.KindsText([TAtlasVisualizerKind.Lists, TAtlasVisualizerKind.Json]),
    TAtlasVisualizerSettings.KindsText(mOptions.Kinds));
  Assert.AreEqual(77, mOptions.MaxLength);
  Assert.AreEqual(1234, mOptions.MaxImagePixels);
  mOptions.NameFields := nil;
end;

procedure TAtlasVisualizerFlowTests.ReregisterOnSwitchOrKinds;
var
  mSettings: TAtlasPluginSettings;
  mOld: string;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mOld := TAtlasVisualizerFlow.Signature(mSettings);
  mSettings.DebugVisualizerMaxLength := mSettings.DebugVisualizerMaxLength + 1;
  Assert.AreEqual(mOld, TAtlasVisualizerFlow.Signature(mSettings));
  mSettings.DebugVisualizerTypes := 'json';
  Assert.AreNotEqual(mOld, TAtlasVisualizerFlow.Signature(mSettings));
  Assert.IsTrue(TAtlasVisualizerFlow.NeedsReregister(True, mOld, TAtlasVisualizerFlow.Signature(mSettings)));
  Assert.IsFalse(TAtlasVisualizerFlow.NeedsReregister(False, mOld, TAtlasVisualizerFlow.Signature(mSettings)));
  Assert.IsFalse(TAtlasVisualizerFlow.NeedsReregister(True, mOld, mOld));
end;

procedure TAtlasVisualizerFlowTests.WantsAndShown;
begin
  Assert.IsTrue(TAtlasVisualizerFlow.Wants(True, TAtlasVisualizerKind.Json, [TAtlasVisualizerKind.Json]));
  Assert.IsFalse(TAtlasVisualizerFlow.Wants(False, TAtlasVisualizerKind.Json, [TAtlasVisualizerKind.Json]));
  Assert.IsFalse(TAtlasVisualizerFlow.Wants(True, TAtlasVisualizerKind.Json, [TAtlasVisualizerKind.Lists]));
  Assert.AreEqual('3 Einträge', TAtlasVisualizerFlow.Shown('3 Einträge', '($1234)'));
  Assert.AreEqual('($1234)', TAtlasVisualizerFlow.Shown('', '($1234)'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVisualizerFlowTests);

end.
