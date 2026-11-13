unit Atlas.UI.Debug.MemoryFrame.Tests;

// Fenster „Atlas: Speicher“ (#858), Oberfläche: Zeile der aktuellen Werte,
// Zuwachs im Bereich, Knöpfe erst mit Messungen, Bereich wählen und mit
// „Leeren“ aufheben, Hinweis der Linie.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugMemoryFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NowTextListsEverySeries;
    [Test]
    procedure RangeTextNeedsValidGrowth;
    [Test]
    procedure ButtonsNeedSamples;
    [Test]
    procedure SelectionShowsGrowthAndClearResets;
    [Test]
    procedure HoverTextShowsValueBefore;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.MemoryTimeline,
  Atlas.UI.Debug.MemoryFrame;

function Sample(AAtMs, APrivate, AHandles: Int64): TAtlasMemorySample;
begin
  Result := Default(TAtlasMemorySample);
  Result.AtMs := AAtMs;
  Result.Values[TAtlasMemorySeries.PrivateBytes] := APrivate;
  Result.Values[TAtlasMemorySeries.Handles] := AHandles;
end;

{ TAtlasDebugMemoryFrameTests }

procedure TAtlasDebugMemoryFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugMemoryFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugMemoryFrameTests.NowTextListsEverySeries;
var
  mValues: TAtlasMemoryValues;
  mText: string;
begin
  mValues := Default(TAtlasMemoryValues);
  mValues[TAtlasMemorySeries.Handles] := 312;
  mText := TAtlasMemoryTexts.NowText(mValues);
  Assert.StartsWith('Jetzt: Privater Speicher', mText);
  Assert.IsTrue(mText.Contains('Handles 312'), mText);
  Assert.IsTrue(mText.Contains('GDI-Objekte'), mText);
  Assert.IsTrue(mText.EndsWith('USER-Objekte 0'), mText);
end;

procedure TAtlasDebugMemoryFrameTests.RangeTextNeedsValidGrowth;
var
  mGrowth: TAtlasMemoryGrowth;
  mText: string;
begin
  mGrowth := Default(TAtlasMemoryGrowth);
  Assert.AreEqual('', TAtlasMemoryTexts.RangeText(mGrowth));
  mGrowth.Valid := True;
  mGrowth.FromMs := 4000;
  mGrowth.ToMs := 64000;
  mGrowth.Deltas[TAtlasMemorySeries.Handles] := 12;
  mText := TAtlasMemoryTexts.RangeText(mGrowth);
  Assert.StartsWith('Bereich ', mText);
  Assert.IsTrue(mText.Contains('Handles +12'), mText);
end;

procedure TAtlasDebugMemoryFrameTests.ButtonsNeedSamples;
var
  mFrame: TAtlasDebugMemoryFrame;
  mTimeline: TAtlasMemoryTimeline;
begin
  mTimeline := TAtlasMemoryTimeline.Create;
  mFrame := TAtlasDebugMemoryFrame.Create(nil);
  try
    mFrame.SetTimeline(mTimeline);
    Assert.IsFalse(mFrame.CopyCsvButton.Enabled, 'ohne Messung');
    Assert.AreEqual('', mFrame.NowLabel.Caption);
    mTimeline.AddSample(Sample(0, 1000, 10));
    mFrame.Refresh;
    Assert.IsTrue(mFrame.CopyCsvButton.Enabled);
    Assert.IsTrue(mFrame.MarkButton.Enabled);
    Assert.StartsWith('Jetzt: ', mFrame.NowLabel.Caption);
  finally
    mFrame.Free;
    mTimeline.Free;
  end;
end;

procedure TAtlasDebugMemoryFrameTests.SelectionShowsGrowthAndClearResets;
var
  mFrame: TAtlasDebugMemoryFrame;
  mTimeline: TAtlasMemoryTimeline;
  mCleared: Integer;
begin
  mCleared := 0;
  mTimeline := TAtlasMemoryTimeline.Create;
  mFrame := TAtlasDebugMemoryFrame.Create(nil);
  try
    mTimeline.AddSample(Sample(0, 1000, 10));
    mTimeline.AddSample(Sample(1000, 2000, 13));
    mTimeline.AddSample(Sample(2000, 3000, 15));
    mFrame.SetTimeline(mTimeline);
    mFrame.OnClear :=
      procedure
      begin
        Inc(mCleared);
      end;
    mFrame.Chart.SelectRange(2000, 0);
    Assert.AreEqual(Int64(0), mFrame.Chart.SelectionFromMs, 'Reihenfolge egal');
    Assert.IsTrue(mFrame.RangeLabel.Caption.Contains('Handles +5'), mFrame.RangeLabel.Caption);
    mFrame.ClearButton.Click;
    Assert.AreEqual(1, mCleared);
    Assert.IsFalse(mFrame.Chart.HasSelection);
    Assert.AreEqual('', mFrame.RangeLabel.Caption);
  finally
    mFrame.Free;
    mTimeline.Free;
  end;
end;

procedure TAtlasDebugMemoryFrameTests.HoverTextShowsValueBefore;
var
  mFrame: TAtlasDebugMemoryFrame;
  mTimeline: TAtlasMemoryTimeline;
begin
  mTimeline := TAtlasMemoryTimeline.Create;
  mFrame := TAtlasDebugMemoryFrame.Create(nil);
  try
    mFrame.SetTimeline(nil);
    Assert.AreEqual('', mFrame.Chart.HoverText(100), 'ohne Verlauf');
    mTimeline.AddSample(Sample(0, 1000, 10));
    mTimeline.AddSample(Sample(20000, 2000, 30));
    mFrame.SetTimeline(mTimeline);
    mFrame.Chart.Series := TAtlasMemorySeries.Handles;
    // Ganz links: erste Messung; ganz rechts: letzte.
    Assert.IsTrue(mFrame.Chart.HoverText(0).EndsWith(': 10'), mFrame.Chart.HoverText(0));
    Assert.IsTrue(mFrame.Chart.HoverText(mFrame.Chart.Width).EndsWith(': 30'),
      mFrame.Chart.HoverText(mFrame.Chart.Width));
  finally
    mFrame.Free;
    mTimeline.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugMemoryFrameTests);

end.
