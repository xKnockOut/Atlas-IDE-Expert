unit Atlas.Core.Editor.CloseRules.Tests;

// Tests der Schließlogik (#414, ARG-009): je Zeile der Tabelle aus dem Issue
// ein Fall für Popup, Parameter-Hint und Tooltip.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.CloseRules;

type
  [TestFixture]
  TAtlasCloseRulesTests = class
  private
    function Opened: TAtlasEditorWindowState;
  public
    [Test]
    procedure NothingChangedKeepsAllOpen;
    [Test]
    procedure InactiveIdeClosesAll;
    [Test]
    procedure FocusElsewhereClosesAll;
    [Test]
    procedure ResizeClosesAll;
    [Test]
    procedure TabSwitchClosesAll;
    [Test]
    procedure ScrollClosesPopupAndTooltip;
    [Test]
    procedure ScrollMovesHintWhileAnchorVisible;
    [Test]
    procedure ScrollClosesHintWhenAnchorOutOfView;
    [Test]
    procedure PinnedOrHoveredTooltipStaysOnFocusChange;
    [Test]
    procedure LeavingTheWordClosesPopup;
    [Test]
    procedure TypingIdentifierKeepsPopup;
    [Test]
    procedure TooltipHidesAfter300Ms;
    [Test]
    procedure DelayedOpenOnlyWhileTypingIdentifier;
  end;

implementation

uses
  System.Types;

procedure Same(AExpected, AActual: TAtlasCloseReason);
begin
  Assert.AreEqual(TAtlasCloseRules.Name(AExpected), TAtlasCloseRules.Name(AActual));
end;

function TAtlasCloseRulesTests.Opened: TAtlasEditorWindowState;
begin
  Result := Default(TAtlasEditorWindowState);
  Result.AppActive := True;
  Result.Focus := 42;
  Result.FileName := 'C:\P\Unit1.pas';
  Result.TopRow := 100;
  Result.Rows := 40;
  Result.Size := Point(800, 600);
end;

procedure TAtlasCloseRulesTests.NothingChangedKeepsAllOpen;
var
  mMove: Boolean;
begin
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Popup(Opened, Opened));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, Opened, 120, mMove));
  Assert.IsFalse(mMove);
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, Opened, False, False));
end;

procedure TAtlasCloseRulesTests.InactiveIdeClosesAll;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  // Wechsel zu einer anderen Anwendung: kein Atlas-Fenster bleibt sichtbar, auch angeheftet nicht.
  mNow := Opened;
  mNow.AppActive := False;
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Popup(Opened, mNow));
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Hint(Opened, mNow, 120, mMove));
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Tooltip(Opened, mNow, True, True));
end;

procedure TAtlasCloseRulesTests.FocusElsewhereClosesAll;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  // Objektinspektor oder Projektverwaltung im Fokus.
  mNow := Opened;
  mNow.Focus := 7;
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Popup(Opened, mNow));
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Hint(Opened, mNow, 120, mMove));
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Tooltip(Opened, mNow, False, False));
end;

procedure TAtlasCloseRulesTests.ResizeClosesAll;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  mNow := Opened;
  mNow.Size := Point(700, 600);
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Popup(Opened, mNow));
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Hint(Opened, mNow, 120, mMove));
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Tooltip(Opened, mNow, False, False));
end;

procedure TAtlasCloseRulesTests.TabSwitchClosesAll;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  mNow := Opened;
  mNow.FileName := 'C:\P\Unit2.pas';
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Popup(Opened, mNow));
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Hint(Opened, mNow, 120, mMove));
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Tooltip(Opened, mNow, False, False));
end;

procedure TAtlasCloseRulesTests.ScrollClosesPopupAndTooltip;
var
  mNow: TAtlasEditorWindowState;
begin
  mNow := Opened;
  mNow.TopRow := 103;
  Same(TAtlasCloseReason.Scrolled, TAtlasCloseRules.Popup(Opened, mNow));
  Same(TAtlasCloseReason.Scrolled, TAtlasCloseRules.Tooltip(Opened, mNow, False, False));
end;

procedure TAtlasCloseRulesTests.ScrollMovesHintWhileAnchorVisible;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  mNow := Opened;
  mNow.TopRow := 110;
  // Sichtbar sind die Zeilen 110 bis 149.
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, mNow, 110, mMove));
  Assert.IsTrue(mMove);
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, mNow, 149, mMove));
  Assert.IsTrue(mMove);
end;

procedure TAtlasCloseRulesTests.ScrollClosesHintWhenAnchorOutOfView;
var
  mNow: TAtlasEditorWindowState;
  mMove: Boolean;
begin
  // Mehrzeiliger Aufruf: Der Caret steht noch im Bild, die Klammer mit dem Hint nicht mehr.
  mNow := Opened;
  mNow.TopRow := 110;
  Same(TAtlasCloseReason.OutOfView, TAtlasCloseRules.Hint(Opened, mNow, 109, mMove));
  Assert.IsFalse(mMove);
  Same(TAtlasCloseReason.OutOfView, TAtlasCloseRules.Hint(Opened, mNow, 150, mMove));
end;

procedure TAtlasCloseRulesTests.PinnedOrHoveredTooltipStaysOnFocusChange;
var
  mNow: TAtlasEditorWindowState;
begin
  mNow := Opened;
  mNow.Focus := 7;
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, mNow, True, False));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, mNow, False, True));
  mNow := Opened;
  mNow.FileName := 'C:\P\Unit2.pas';
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, mNow, True, False));
end;

procedure TAtlasCloseRulesTests.LeavingTheWordClosesPopup;
var
  mIndex: Integer;
begin
  // "  Liste.Ad|": Wortanfang hinter dem Punkt (8), Cursor bei 10.
  Same(TAtlasCloseReason.OtherLine, TAtlasCloseRules.PopupWord(False, '', 8, 0, mIndex));
  Same(TAtlasCloseReason.BeforeWord, TAtlasCloseRules.PopupWord(True, '  Liste.Ad', 8, 7, mIndex));
  Same(TAtlasCloseReason.NonIdentifier, TAtlasCloseRules.PopupWord(True, '  Liste.Ad ', 8, 11, mIndex));
  Assert.AreEqual(11, mIndex);
  Same(TAtlasCloseReason.NonIdentifier, TAtlasCloseRules.PopupWord(True, '  Liste.Ad(', 8, 11, mIndex));
end;

procedure TAtlasCloseRulesTests.TypingIdentifierKeepsPopup;
var
  mIndex: Integer;
begin
  Same(TAtlasCloseReason.None, TAtlasCloseRules.PopupWord(True, '  Liste.Add_2', 8, 13, mIndex));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.PopupWord(True, '  Liste.', 8, 8, mIndex));
end;

procedure TAtlasCloseRulesTests.TooltipHidesAfter300Ms;
begin
  Assert.AreEqual(300, TAtlasCloseRules.cTooltipHideDelayMs);
end;

procedure TAtlasCloseRulesTests.DelayedOpenOnlyWhileTypingIdentifier;
var
  mNow_: TAtlasEditorWindowState;
begin
  // ARG-046: "List." ausgelöst an Zeichen 5, danach "Co" getippt: öffnen.
  Assert.IsTrue(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List.Co', 5, 7));
  Assert.IsTrue(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List.', 5, 5));
  // Leerzeichen, ";" oder Rücktaste vor die Auslösestelle: nicht mehr öffnen.
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List. ', 5, 6));
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List', 5, 4));
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, False, 'List.', 5, 5));
  // Fenster gewechselt oder gescrollt.
  mNow_ := Opened;
  mNow_.TopRow := 120;
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, mNow_, True, 'List.', 5, 5));
  mNow_ := Opened;
  mNow_.Focus := 7;
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, mNow_, True, 'List.', 5, 5));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCloseRulesTests);

end.
