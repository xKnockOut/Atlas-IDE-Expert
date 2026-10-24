unit Atlas.Core.Settings.VisualizerKinds.Tests;

// Tests für die Einstellungen der Visualisierer (#835): Arten lesen und in
// fester Reihenfolge schreiben, Auswertungsstufe, Namensfelder, Grenzen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVisualizerSettingsTests = class
  public
    [Test]
    procedure KindsNormalizeInFixedOrder;
    [Test]
    procedure KindsTextOfAllKinds;
    [Test]
    procedure EvaluationFallsBackToProperties;
    [Test]
    procedure NameFieldsWithoutEmptyDuplicatesAndInvalid;
    [Test]
    procedure DefaultsLieWithinLimits;
  end;

implementation

uses
  Atlas.Core.Settings.VisualizerKinds;

{ TAtlasVisualizerSettingsTests }

procedure TAtlasVisualizerSettingsTests.KindsNormalizeInFixedOrder;
begin
  Assert.AreEqual('lists,json,colors', TAtlasVisualizerSettings.NormalizeKinds(' Colors, lists ;JSON, unbekannt'));
  Assert.AreEqual('', TAtlasVisualizerSettings.NormalizeKinds(''));
  Assert.IsTrue(TAtlasVisualizerSettings.ParseKinds('GUID') = [TAtlasVisualizerKind.Guid]);
end;

procedure TAtlasVisualizerSettingsTests.KindsTextOfAllKinds;
begin
  Assert.AreEqual('lists,dictionaries,dataSets,bytes,json,colors,guid,geometry,graphics',
    TAtlasVisualizerSettings.KindsText(TAtlasVisualizerSettings.AllKinds));
  Assert.AreEqual('', TAtlasVisualizerSettings.KindsText([]));
end;

procedure TAtlasVisualizerSettingsTests.EvaluationFallsBackToProperties;
begin
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Ord(TAtlasVisualizerSettings.ParseEvaluation('CALLS')));
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Fields), Ord(TAtlasVisualizerSettings.ParseEvaluation(' fields ')));
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties),
    Ord(TAtlasVisualizerSettings.ParseEvaluation('quatsch')));
  Assert.AreEqual('properties', TAtlasVisualizerSettings.EvaluationNames[TAtlasVisualizerEvaluation.Properties]);
end;

procedure TAtlasVisualizerSettingsTests.NameFieldsWithoutEmptyDuplicatesAndInvalid;
var
  mFields: TArray<string>;
begin
  mFields := TAtlasVisualizerSettings.ParseNameFields(' Name, caption,, NAME, 1x, Text');
  Assert.AreEqual(3, Integer(Length(mFields)));
  Assert.AreEqual('caption', mFields[1]);
  Assert.AreEqual('Name,caption,Text',
    TAtlasVisualizerSettings.NormalizeNameFields(' Name, caption,, NAME, 1x, Text'));
  Assert.AreEqual('Name,Caption,Text', TAtlasVisualizerSettings.NormalizeNameFields(
    TAtlasVisualizerSettings.DefaultNameFields));
end;

procedure TAtlasVisualizerSettingsTests.DefaultsLieWithinLimits;
begin
  Assert.IsTrue((TAtlasVisualizerSettings.DefaultMaxLength >= TAtlasVisualizerSettings.MinMaxLength) and
    (TAtlasVisualizerSettings.DefaultMaxLength <= TAtlasVisualizerSettings.MaxMaxLength));
  Assert.IsTrue((TAtlasVisualizerSettings.DefaultTimeoutMs >= TAtlasVisualizerSettings.MinTimeoutMs) and
    (TAtlasVisualizerSettings.DefaultTimeoutMs <= TAtlasVisualizerSettings.MaxTimeoutMs));
  Assert.IsTrue((TAtlasVisualizerSettings.DefaultMaxImagePixels >= TAtlasVisualizerSettings.MinMaxImagePixels) and
    (TAtlasVisualizerSettings.DefaultMaxImagePixels <= TAtlasVisualizerSettings.MaxMaxImagePixels));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVisualizerSettingsTests);

end.
