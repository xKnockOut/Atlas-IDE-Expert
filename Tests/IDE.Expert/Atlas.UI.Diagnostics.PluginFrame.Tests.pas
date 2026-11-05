unit Atlas.UI.Diagnostics.PluginFrame.Tests;

// Diagnose-Fenster mit den Reitern des Plugins: Seiten wechseln, Hinweis bei
// ausgeschalteter Messung, Leiste mit Belegung und Schwelle, Filter „Nur X
// zeigen“, Abschalten und Zeile kopieren über das Kontextmenü, die Wahl folgt
// der Funktion über einen neuen Stand, Zeichnen ohne Fehler, Knöpfe der Leiste
// in einer zweiten Zeile, wenn das Fenster schmal ist.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDiagnosticsFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure StartsOnMainThreadWithBar;
    [Test]
    procedure PluginOffShowsNoteCompletionStays;
    [Test]
    procedure TabsSwitchPages;
    [Test]
    procedure BarShowsBusyThresholdAndPause;
    [Test]
    procedure OnlyFilterAndMenuActions;
    [Test]
    procedure SelectionFollowsFeature;
    [Test]
    procedure PaintsAllPages;
    [Test]
    procedure BarTwoRowsRule;
    [Test]
    procedure NarrowBarPutsButtonsBelow;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.PluginParts,
  Atlas.UI.Diagnostics.PluginFrame;

function Feature(AFeature: TAtlasFeature; ATotalMs: Double): TAtlasFeatureTiming;
begin
  Result := Default(TAtlasFeatureTiming);
  Result.Feature := AFeature;
  Result.Stat.Calls := 1;
  Result.Stat.TotalMs := ATotalMs;
  Result.Stat.MaxMs := ATotalMs;
end;

function SlowCall(AFeature: TAtlasFeature; AMs: Double): TAtlasSlowCall;
begin
  Result := Default(TAtlasSlowCall);
  Result.Feature := AFeature;
  Result.Ms := AMs;
end;

function Snapshot: TAtlasPluginSnapshot;
var
  mHang: TAtlasHangEntry;
begin
  Result := Default(TAtlasPluginSnapshot);
  Result.ThresholdMs := 16;
  Result.Busy := TArray<Double>.Create(10, 50);
  Result.Features := TArray<TAtlasFeatureTiming>.Create(Feature(TAtlasFeature.Minimap, 40),
    Feature(TAtlasFeature.Outline, 20));
  Result.Slow := TArray<TAtlasSlowCall>.Create(SlowCall(TAtlasFeature.Minimap, 40),
    SlowCall(TAtlasFeature.Outline, 20));
  mHang := Default(TAtlasHangEntry);
  mHang.DurationMs := 900;
  mHang.WithAtlas := True;
  Result.Hangs := TArray<TAtlasHangEntry>.Create(mHang);
end;

function NewFrame(AForm: TForm): TAtlasDiagnosticsFrame;
begin
  AForm.Width := 800;
  AForm.Height := 500;
  Result := TAtlasDiagnosticsFrame.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alClient;
  Result.SetColors(TAtlasColors.Dark);
end;

{ TAtlasDiagnosticsFrameTests }

procedure TAtlasDiagnosticsFrameTests.WarmUpFirstUse;
begin
  PaintsAllPages;
end;

procedure TAtlasDiagnosticsFrameTests.StartsOnMainThreadWithBar;
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := TAtlasDiagnosticsFrame.Create(nil);
  try
    Assert.AreEqual(Ord(TAtlasDiagnosticPage.MainThread), Ord(mFrame.ActivePage));
    Assert.IsTrue(mFrame.PluginTimings);
    Assert.IsTrue(mFrame.Bar.Visible);
    Assert.IsTrue(mFrame.MainThread.Visible);
    Assert.IsFalse(mFrame.OffNote.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagTabHangs),
      TAtlasDiagnosticTabs.Caption(TAtlasDiagnosticPage.Hangs));
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.PluginOffShowsNoteCompletionStays;
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := TAtlasDiagnosticsFrame.Create(nil);
  try
    mFrame.SetPluginTimings(False);
    Assert.IsFalse(mFrame.Bar.Visible);
    Assert.IsFalse(mFrame.MainThread.Visible);
    Assert.IsTrue(mFrame.OffNote.Visible, 'Hinweis statt Tabellen');
    mFrame.SelectPage(TAtlasDiagnosticPage.Completion);
    Assert.IsFalse(mFrame.OffNote.Visible);
    Assert.IsTrue(mFrame.Completion.Parent.Visible, 'Vervollständigung wie bisher');
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.TabsSwitchPages;
var
  mFrame: TAtlasDiagnosticsFrame;
begin
  mFrame := TAtlasDiagnosticsFrame.Create(nil);
  try
    mFrame.SelectPage(TAtlasDiagnosticPage.Server);
    Assert.IsTrue(mFrame.Server.Visible);
    Assert.IsFalse(mFrame.MainThread.Visible);
    mFrame.SelectPage(TAtlasDiagnosticPage.Completion);
    Assert.IsFalse(mFrame.Bar.Visible, 'die Vervollständigung hat eigene Knöpfe');
    Assert.IsFalse(mFrame.Server.Visible);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.BarShowsBusyThresholdAndPause;
var
  mFrame: TAtlasDiagnosticsFrame;
  mSnapshot: TAtlasPluginSnapshot;
  mPause: Boolean;
  mResets: Integer;
begin
  mPause := False;
  mResets := 0;
  mFrame := TAtlasDiagnosticsFrame.Create(nil);
  try
    mSnapshot := Snapshot;
    mFrame.SetSnapshot(mSnapshot, 2);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagBusy, [2, '30']), mFrame.Bar.Busy.Caption);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagThreshold, [16]), mFrame.Bar.Threshold.Caption);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagWorkers, [2]), mFrame.Background.Header.Caption);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagHangSummary, [1, 1]), mFrame.Hangs.Header.Caption);
    mFrame.Bar.OnPause :=
      procedure(APause: Boolean)
      begin
        mPause := APause;
      end;
    mFrame.Bar.OnReset :=
      procedure
      begin
        Inc(mResets);
      end;
    mFrame.Bar.PauseButton.Click;
    Assert.IsTrue(mPause, 'läuft: Knopf hält an');
    mSnapshot.Paused := True;
    mFrame.SetSnapshot(mSnapshot, 0);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagResume), mFrame.Bar.PauseButton.Caption);
    mFrame.Bar.PauseButton.Click;
    Assert.IsFalse(mPause);
    mFrame.Bar.ResetButton.Click;
    Assert.AreEqual(1, mResets);
    mFrame.FeatureDisabled(TAtlasFeature.Minimap);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagDisabled, [TAtlasGuard.FeatureName(TAtlasFeature.Minimap)]),
      mFrame.Bar.Note.Caption);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.OnlyFilterAndMenuActions;
var
  mForm: TForm;
  mFrame: TAtlasDiagnosticsFrame;
  mDisabled: TAtlasFeature;
  mCopied: string;
begin
  mDisabled := TAtlasFeature.Completion;
  mCopied := '';
  mForm := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mForm);
    mFrame.SetSnapshot(Snapshot, 0);
    Assert.AreEqual(2, Integer(Length(mFrame.MainThread.Slow.Rows)));
    mFrame.MainThread.ShowOnly(TAtlasFeature.Outline);
    Assert.AreEqual(1, Integer(Length(mFrame.MainThread.Slow.Rows)));
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagSlowOnly, [TAtlasGuard.FeatureName(TAtlasFeature.Outline)]),
      mFrame.MainThread.SlowCaption.Caption);
    mFrame.MainThread.ShowAllSlow;
    Assert.AreEqual(2, Integer(Length(mFrame.MainThread.Slow.Rows)));
    mFrame.MainThread.OnDisable :=
      procedure(AFeature: TAtlasFeature)
      begin
        mDisabled := AFeature;
      end;
    mFrame.MainThread.OnCopyText :=
      procedure(AText: string)
      begin
        mCopied := AText;
      end;
    // Erste Zeile: die meiste eigene Zeit.
    mFrame.MainThread.Features.SelectRow(0);
    mFrame.MainThread.Menu.DisableItem.Click;
    Assert.AreEqual(Ord(TAtlasFeature.Minimap), Ord(mDisabled));
    mFrame.MainThread.Menu.CopyRowItem.Click;
    Assert.Contains(mCopied, TAtlasGuard.FeatureName(TAtlasFeature.Minimap));
    mFrame.MainThread.Menu.OnlyItem.Click;
    Assert.IsTrue(mFrame.MainThread.FilterOn);
    Assert.AreEqual(Ord(TAtlasFeature.Minimap), Ord(mFrame.MainThread.Filter));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.SelectionFollowsFeature;
var
  mForm: TForm;
  mFrame: TAtlasDiagnosticsFrame;
  mSnapshot: TAtlasPluginSnapshot;
  mFeature: TAtlasFeature;
begin
  mForm := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mForm);
    mSnapshot := Snapshot;
    mFrame.SetSnapshot(mSnapshot, 0);
    mFrame.MainThread.Features.SelectRow(1);
    Assert.IsTrue(mFrame.MainThread.SelectedFeature(mFeature));
    Assert.AreEqual(Ord(TAtlasFeature.Outline), Ord(mFeature));
    // Die Gliederung überholt die Minimap: die Wahl bleibt bei der Gliederung, jetzt Zeile 0.
    mSnapshot.Features[1].Stat.TotalMs := 100;
    mFrame.SetSnapshot(mSnapshot, 0);
    Assert.AreEqual(0, mFrame.MainThread.Features.Selected);
    Assert.IsTrue(mFrame.MainThread.SelectedFeature(mFeature));
    Assert.AreEqual(Ord(TAtlasFeature.Outline), Ord(mFeature));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.PaintsAllPages;
var
  mForm: TForm;
  mFrame: TAtlasDiagnosticsFrame;
  mPage: TAtlasDiagnosticPage;
begin
  mForm := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mForm);
    mFrame.SetSnapshot(Snapshot, 1);
    mForm.Show;
    // Repaint zeichnet sofort; Nachrichten erst nach der Schleife.
    for mPage := Low(TAtlasDiagnosticPage) to High(TAtlasDiagnosticPage) do
    begin
      mFrame.SelectPage(mPage);
      mFrame.Repaint;
    end;
    Application.ProcessMessages;
    Assert.AreEqual(Ord(High(TAtlasDiagnosticPage)), Ord(mFrame.ActivePage));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDiagnosticsFrameTests.BarTwoRowsRule;
begin
  Assert.IsFalse(TAtlasDiagnosticBar.NeedsTwoRows(500, 300, 800), 'passt nebeneinander');
  Assert.IsFalse(TAtlasDiagnosticBar.NeedsTwoRows(500, 300, 900), 'Platz übrig');
  Assert.IsTrue(TAtlasDiagnosticBar.NeedsTwoRows(500, 300, 799), 'ein Punkt zu schmal');
  Assert.IsFalse(TAtlasDiagnosticBar.NeedsTwoRows(500, 300, 0), 'ohne Breite (noch nicht angeordnet)');
end;

procedure TAtlasDiagnosticsFrameTests.NarrowBarPutsButtonsBelow;
var
  mForm: TForm;
  mFrame: TAtlasDiagnosticsFrame;
  mBar: TAtlasDiagnosticBar;
  mButtons, mSpark, mThreshold: TRect;
  mRowHeight: Integer;
begin
  mForm := TForm.CreateNew(nil);
  try
    mFrame := NewFrame(mForm);
    mFrame.SetSnapshot(Snapshot, 0);
    mForm.Show;
    mForm.ClientWidth := 1400;
    Application.ProcessMessages;
    mBar := mFrame.Bar;
    mRowHeight := mBar.Height;
    Assert.AreEqual(Ord(alRight), Ord(mBar.Buttons.Align), 'breit: Knöpfe rechts');
    // Schmal wie das Fenster in seiner Startgröße: Die Knöpfe lagen über Verlauf und Schwelle.
    mForm.ClientWidth := 520;
    Application.ProcessMessages;
    Assert.AreEqual(Ord(alBottom), Ord(mBar.Buttons.Align), 'schmal: Knöpfe darunter');
    Assert.AreEqual(2 * mRowHeight, mBar.Height);
    mButtons := mBar.Buttons.BoundsRect;
    mSpark := mBar.Spark.BoundsRect;
    mThreshold := mBar.Threshold.BoundsRect;
    Assert.IsFalse(mButtons.IntersectsWith(mSpark), 'Verlauf frei');
    Assert.IsFalse(mButtons.IntersectsWith(mThreshold), 'Schwelle frei');
    Assert.IsTrue(mBar.PauseButton.Visible and (mBar.PauseButton.Width > 0));
    mForm.ClientWidth := 1400;
    Application.ProcessMessages;
    Assert.AreEqual(Ord(alRight), Ord(mBar.Buttons.Align), 'wieder breit: eine Zeile');
    Assert.AreEqual(mRowHeight, mBar.Height);
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDiagnosticsFrameTests);

end.
