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
    [Test]
    procedure AskOffersSafeNormalDetails;
    [Test]
    procedure SafeOffersContinueTogglesRestore;
    [Test]
    procedure DetailsShowLinesAndBugReport;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.SafeModeNotice;

procedure TAtlasSafeModeNoticeTests.AskOffersSafeNormalDetails;
var
  Notice: TAtlasSafeModeNotice;
  Safe, Normal: Integer;
begin
  Safe := 0;
  Normal := 0;
  Notice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Ask,
    TAtlasStrings.Text(TAtlasTextId.SafeAskText), '', 'Zurücksetzen', ['Atlas 1.0.0']);
  Notice.OnSafe :=
    procedure
    begin
      Inc(Safe);
    end;
  Notice.OnNormal :=
    procedure
    begin
      Inc(Normal);
    end;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SafeAskSafe), Notice.PrimaryButton.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SafeAskNormal), Notice.SecondaryButton.Caption);
  Assert.IsTrue(Notice.DetailsButton.Visible, 'Details');
  Assert.IsFalse(Notice.RestoreButton.Visible, 'Zurücksetzen nur abgesichert');
  Assert.IsFalse(Notice.SuggestionLabel.Visible, 'ohne Vorschlag keine Zeile');
  // Nur die erste Aktion zählt; ausgeführt nach dem Schließen (das Fenster gibt sich selbst frei).
  Notice.PrimaryButton.Click;
  Notice.SecondaryButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, Safe);
  Assert.AreEqual(0, Normal);
end;

procedure TAtlasSafeModeNoticeTests.SafeOffersContinueTogglesRestore;
var
  Notice: TAtlasSafeModeNotice;
  Restored: Integer;
begin
  Restored := 0;
  Notice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Safe,
    TAtlasStrings.Text(TAtlasTextId.SafeActiveText), TAtlasStrings.Fmt(TAtlasTextId.SafeSuggest, ['Klammerfarben']),
    TAtlasStrings.Fmt(TAtlasTextId.SafeRestore, ['14.10.2026 12:00']), nil);
  Notice.OnRestore :=
    procedure
    begin
      Inc(Restored);
    end;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SafeContinueNormal), Notice.PrimaryButton.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SafeOpenToggles), Notice.SecondaryButton.Caption);
  Assert.IsTrue(Notice.RestoreButton.Visible);
  Assert.IsTrue(Notice.SuggestionLabel.Visible);
  Assert.IsTrue(Pos('Klammerfarben', Notice.SuggestionLabel.Caption) > 0);
  Assert.IsFalse(Notice.DetailsButton.Visible, 'ohne Details kein Knopf');
  Notice.RestoreButton.Click;
  Application.ProcessMessages;
  CheckSynchronize;
  Assert.AreEqual(1, Restored);
end;

procedure TAtlasSafeModeNoticeTests.DetailsShowLinesAndBugReport;
var
  Notice: TAtlasSafeModeNotice;
  Height1, Exported, Reported: Integer;
begin
  Exported := 0;
  Reported := 0;
  Notice := TAtlasSafeModeNotice.CreateNotice(nil, TAtlasSafeNoticeKind.Safe, 'Text', '', '',
    ['Atlas 1.0.0', 'Fehler Pairs: 2']);
  try
    Notice.OnExportLog :=
      procedure
      begin
        Inc(Exported);
      end;
    Height1 := Notice.ClientHeight;
    Assert.IsFalse(Notice.DetailsVisible);
    Notice.DetailsButton.Click;
    Assert.IsTrue(Notice.DetailsVisible);
    Assert.IsTrue(Notice.ClientHeight > Height1, 'Details machen das Fenster höher');
    Assert.AreEqual(2, Notice.Details.Lines.Count);
    Assert.AreEqual('Fehler Pairs: 2', Notice.Details.Lines[1]);
    Assert.IsTrue(Notice.ExportButton.Visible);
    Assert.IsFalse(Notice.BugButton.Visible, 'ohne Fehlerbericht kein Knopf');
    Notice.ExportButton.Click;
    Assert.AreEqual(1, Exported);
    // Mit Fehlerbericht (#108) erscheint der Knopf beim nächsten Aufklappen.
    Notice.OnBugReport :=
      procedure
      begin
        Inc(Reported);
      end;
    Notice.ToggleDetails;
    Notice.ToggleDetails;
    Assert.IsTrue(Notice.BugButton.Visible);
    Notice.BugButton.Click;
    Assert.AreEqual(1, Reported);
  finally
    Notice.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSafeModeNoticeTests);

end.
