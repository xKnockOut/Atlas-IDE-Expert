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
  Move: Boolean;
begin
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Popup(Opened, Opened));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, Opened, 120, Move));
  Assert.IsFalse(Move);
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, Opened, False, False));
end;

procedure TAtlasCloseRulesTests.InactiveIdeClosesAll;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  // Wechsel zu einer anderen Anwendung: kein Atlas-Fenster bleibt sichtbar, auch angeheftet nicht.
  Now := Opened;
  Now.AppActive := False;
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Popup(Opened, Now));
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Hint(Opened, Now, 120, Move));
  Same(TAtlasCloseReason.Inactive, TAtlasCloseRules.Tooltip(Opened, Now, True, True));
end;

procedure TAtlasCloseRulesTests.FocusElsewhereClosesAll;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  // Objektinspektor oder Projektverwaltung im Fokus.
  Now := Opened;
  Now.Focus := 7;
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Popup(Opened, Now));
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Hint(Opened, Now, 120, Move));
  Same(TAtlasCloseReason.FocusLost, TAtlasCloseRules.Tooltip(Opened, Now, False, False));
end;

procedure TAtlasCloseRulesTests.ResizeClosesAll;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  Now := Opened;
  Now.Size := Point(700, 600);
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Popup(Opened, Now));
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Hint(Opened, Now, 120, Move));
  Same(TAtlasCloseReason.Resized, TAtlasCloseRules.Tooltip(Opened, Now, False, False));
end;

procedure TAtlasCloseRulesTests.TabSwitchClosesAll;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  Now := Opened;
  Now.FileName := 'C:\P\Unit2.pas';
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Popup(Opened, Now));
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Hint(Opened, Now, 120, Move));
  Same(TAtlasCloseReason.OtherFile, TAtlasCloseRules.Tooltip(Opened, Now, False, False));
end;

procedure TAtlasCloseRulesTests.ScrollClosesPopupAndTooltip;
var
  Now: TAtlasEditorWindowState;
begin
  Now := Opened;
  Now.TopRow := 103;
  Same(TAtlasCloseReason.Scrolled, TAtlasCloseRules.Popup(Opened, Now));
  Same(TAtlasCloseReason.Scrolled, TAtlasCloseRules.Tooltip(Opened, Now, False, False));
end;

procedure TAtlasCloseRulesTests.ScrollMovesHintWhileAnchorVisible;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  Now := Opened;
  Now.TopRow := 110;
  // Sichtbar sind die Zeilen 110 bis 149.
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, Now, 110, Move));
  Assert.IsTrue(Move);
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Hint(Opened, Now, 149, Move));
  Assert.IsTrue(Move);
end;

procedure TAtlasCloseRulesTests.ScrollClosesHintWhenAnchorOutOfView;
var
  Now: TAtlasEditorWindowState;
  Move: Boolean;
begin
  // Mehrzeiliger Aufruf: Der Caret steht noch im Bild, die Klammer mit dem Hint nicht mehr.
  Now := Opened;
  Now.TopRow := 110;
  Same(TAtlasCloseReason.OutOfView, TAtlasCloseRules.Hint(Opened, Now, 109, Move));
  Assert.IsFalse(Move);
  Same(TAtlasCloseReason.OutOfView, TAtlasCloseRules.Hint(Opened, Now, 150, Move));
end;

procedure TAtlasCloseRulesTests.PinnedOrHoveredTooltipStaysOnFocusChange;
var
  Now: TAtlasEditorWindowState;
begin
  Now := Opened;
  Now.Focus := 7;
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, Now, True, False));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, Now, False, True));
  Now := Opened;
  Now.FileName := 'C:\P\Unit2.pas';
  Same(TAtlasCloseReason.None, TAtlasCloseRules.Tooltip(Opened, Now, True, False));
end;

procedure TAtlasCloseRulesTests.LeavingTheWordClosesPopup;
var
  Index: Integer;
begin
  // "  Liste.Ad|": Wortanfang hinter dem Punkt (8), Cursor bei 10.
  Same(TAtlasCloseReason.OtherLine, TAtlasCloseRules.PopupWord(False, '', 8, 0, Index));
  Same(TAtlasCloseReason.BeforeWord, TAtlasCloseRules.PopupWord(True, '  Liste.Ad', 8, 7, Index));
  Same(TAtlasCloseReason.NonIdentifier, TAtlasCloseRules.PopupWord(True, '  Liste.Ad ', 8, 11, Index));
  Assert.AreEqual(11, Index);
  Same(TAtlasCloseReason.NonIdentifier, TAtlasCloseRules.PopupWord(True, '  Liste.Ad(', 8, 11, Index));
end;

procedure TAtlasCloseRulesTests.TypingIdentifierKeepsPopup;
var
  Index: Integer;
begin
  Same(TAtlasCloseReason.None, TAtlasCloseRules.PopupWord(True, '  Liste.Add_2', 8, 13, Index));
  Same(TAtlasCloseReason.None, TAtlasCloseRules.PopupWord(True, '  Liste.', 8, 8, Index));
end;

procedure TAtlasCloseRulesTests.TooltipHidesAfter300Ms;
begin
  Assert.AreEqual(300, TAtlasCloseRules.TooltipHideDelayMs);
end;

procedure TAtlasCloseRulesTests.DelayedOpenOnlyWhileTypingIdentifier;
var
  Now_: TAtlasEditorWindowState;
begin
  // ARG-046: "List." ausgelöst an Zeichen 5, danach "Co" getippt: öffnen.
  Assert.IsTrue(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List.Co', 5, 7));
  Assert.IsTrue(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List.', 5, 5));
  // Leerzeichen, ";" oder Rücktaste vor die Auslösestelle: nicht mehr öffnen.
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List. ', 5, 6));
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, True, 'List', 5, 4));
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Opened, False, 'List.', 5, 5));
  // Fenster gewechselt oder gescrollt.
  Now_ := Opened;
  Now_.TopRow := 120;
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Now_, True, 'List.', 5, 5));
  Now_ := Opened;
  Now_.Focus := 7;
  Assert.IsFalse(TAtlasCloseRules.DelayedOpen(Opened, Now_, True, 'List.', 5, 5));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCloseRulesTests);

end.
