unit Atlas.UI.Diagnostics.SafeModeNotice.Tests;

// Hinweis des abgesicherten Starts (#722): Knöpfe je Variante, Aktionen nach
// dem Schließen, Details mit Export und Fehlerbericht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSafeModeNoticeTests = class
  public
    /// <summary>Erste Benutzung (VCL, Codepages, RTTI) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure AskOffersSafeNormalDetails;
    [Test]
    procedure SafeOffersContinueTogglesRestore;
    [Test]
    procedure DetailsShowLinesAndBugReport;
    /// <summary>Alle Knöpfe liegen nach dem Zeigen im Fenster, auch in umgebrochenen Reihen.</summary>
    [Test]
    procedure ButtonsFitAfterShow;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.UI.Diagnostics.Strings,
  Atlas.UI.Diagnostics.SafeModeNotice;

procedure TAtlasSafeModeNoticeTests.WarmUpFirstUse;
begin
  AskOffersSafeNormalDetails;
end;

procedure TAtlasSafeModeNoticeTests.AskOffersSafeNormalDetails;
var
  mNotice: TAtlasSafeModeNotice;
  mSafe, mNormal: Integer;
begin
  mSafe := 0;
  mNormal := 0;
  mNotice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Ask,
    TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeAskText), '', 'Zurücksetzen', ['Atlas 1.0.0']);
  mNotice.OnSafe :=
    procedure
    begin
      Inc(mSafe);
    end;
  mNotice.OnNormal :=
    procedure
    begin
      Inc(mNormal);
    end;
  Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeAskSafe), mNotice.PrimaryButton.Caption);
  Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeAskNormal),
    mNotice.SecondaryButton.Caption);
  Assert.IsTrue(mNotice.DetailsButton.Visible, 'Details');
  Assert.IsFalse(mNotice.RestoreButton.Visible, 'Zurücksetzen nur abgesichert');
  Assert.IsFalse(mNotice.SuggestionLabel.Visible, 'ohne Vorschlag keine Zeile');
  // Nur die erste Aktion zählt; ausgeführt nach dem Schließen (das Fenster gibt sich selbst frei).
  mNotice.PrimaryButton.Click;
  mNotice.SecondaryButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, mSafe);
  Assert.AreEqual(0, mNormal);
end;

procedure TAtlasSafeModeNoticeTests.SafeOffersContinueTogglesRestore;
var
  mNotice: TAtlasSafeModeNotice;
  mRestored: Integer;
begin
  mRestored := 0;
  mNotice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Safe,
    TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeActiveText),
    TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.SafeSuggest, ['Klammerfarben']),
    TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.SafeRestore, ['14.10.2026 12:00']), nil);
  mNotice.OnRestore :=
    procedure
    begin
      Inc(mRestored);
    end;
  Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeContinueNormal),
    mNotice.PrimaryButton.Caption);
  Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeOpenToggles),
    mNotice.SecondaryButton.Caption);
  Assert.IsTrue(mNotice.RestoreButton.Visible);
  Assert.IsTrue(mNotice.SuggestionLabel.Visible);
  Assert.IsTrue(Pos('Klammerfarben', mNotice.SuggestionLabel.Caption) > 0);
  Assert.IsFalse(mNotice.DetailsButton.Visible, 'ohne Details kein Knopf');
  mNotice.RestoreButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, mRestored);
end;

procedure TAtlasSafeModeNoticeTests.DetailsShowLinesAndBugReport;
var
  mNotice: TAtlasSafeModeNotice;
  mHeight1, mExported, mReported: Integer;
begin
  mExported := 0;
  mReported := 0;
  mNotice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Safe, 'Text', '', '',
    ['Atlas 1.0.0', 'Fehler Pairs: 2']);
  try
    mNotice.OnExportLog :=
      procedure
      begin
        Inc(mExported);
      end;
    mHeight1 := mNotice.ClientHeight;
    Assert.IsFalse(mNotice.DetailsVisible);
    mNotice.DetailsButton.Click;
    Assert.IsTrue(mNotice.DetailsVisible);
    Assert.IsTrue(mNotice.ClientHeight > mHeight1, 'Details machen das Fenster höher');
    Assert.AreEqual(2, Integer(mNotice.Details.Lines.Count));
    Assert.AreEqual('Fehler Pairs: 2', mNotice.Details.Lines[1]);
    Assert.IsTrue(mNotice.ExportButton.Visible);
    Assert.IsFalse(mNotice.BugButton.Visible, 'ohne Fehlerbericht kein Knopf');
    mNotice.ExportButton.Click;
    Assert.AreEqual(1, mExported);
    // Mit Fehlerbericht (#108) erscheint der Knopf beim nächsten Aufklappen.
    mNotice.OnBugReport :=
      procedure
      begin
        Inc(mReported);
      end;
    mNotice.ToggleDetails;
    mNotice.ToggleDetails;
    Assert.IsTrue(mNotice.BugButton.Visible);
    mNotice.BugButton.Click;
    Assert.AreEqual(1, mReported);
  finally
    mNotice.Free;
  end;
end;

procedure TAtlasSafeModeNoticeTests.ButtonsFitAfterShow;
var
  mNotice: TAtlasSafeModeNotice;
  mButton: TButton;
begin
  mNotice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Safe,
    TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeActiveText),
    TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.SafeSuggest, ['Diagnosemodus']),
    TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.SafeRestore, ['15.10.2026 23:02:10']), ['Zeile']);
  try
    mNotice.ShowIn(Rect(0, 0, 1600, 900));
    for mButton in [mNotice.PrimaryButton, mNotice.SecondaryButton, mNotice.RestoreButton, mNotice.DetailsButton] do
    begin
      Assert.IsTrue(mButton.Visible, mButton.Caption);
      Assert.IsTrue(mNotice.ScreenToClient(mButton.ClientToScreen(Point(0, mButton.Height))).Y <= mNotice.ClientHeight,
        mButton.Caption + ' abgeschnitten');
    end;
  finally
    mNotice.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSafeModeNoticeTests);

end.
