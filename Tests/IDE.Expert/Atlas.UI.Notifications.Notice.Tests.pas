unit Atlas.UI.Notifications.Notice.Tests;

// Nicht modaler Hinweis mit Aktionen (#512): Lage unten rechts im Bereich und
// ganz im Arbeitsbereich, Aktionen als Links, Klick meldet die Nummer und
// schließt, Zeitgeber zum Ausblenden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNoticeWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure SitsInLowerRightCornerInsideWorkArea;
    [Test]
    procedure ActionsReportIndexAndHide;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.UI.Notifications.Notice;

procedure TAtlasNoticeWindowTests.WarmUpFirstUse;
begin
  ActionsReportIndexAndHide;
end;

procedure TAtlasNoticeWindowTests.SitsInLowerRightCornerInsideWorkArea;
var
  Bounds: TRect;
begin
  Bounds := TAtlasNoticeWindow.PlaceCorner(Rect(100, 50, 1100, 850), 300, 80, 16, Rect(0, 0, 1920, 1040));
  Assert.AreEqual(784, Bounds.Left);
  Assert.AreEqual(754, Bounds.Top);
  Assert.AreEqual(300, Bounds.Width);
  Assert.AreEqual(80, Bounds.Height);
  // IDE-Fenster ragt über den Bildschirm hinaus: Der Hinweis bleibt im Arbeitsbereich.
  Bounds := TAtlasNoticeWindow.PlaceCorner(Rect(1000, 500, 2500, 1500), 300, 80, 16, Rect(0, 0, 1920, 1040));
  Assert.AreEqual(1604, Bounds.Left);
  Assert.AreEqual(944, Bounds.Top);
end;

procedure TAtlasNoticeWindowTests.ActionsReportIndexAndHide;
var
  Window: TAtlasNoticeWindow;
  Chosen: Integer;
begin
  Chosen := -1;
  Window := TAtlasNoticeWindow.Create(nil);
  try
    Window.Colors := TAtlasColors.Light;
    Window.SetScaling(96, 1, 'Segoe UI', 9);
    Window.OnAction :=
      procedure(AIndex: Integer)
      begin
        Chosen := AIndex;
      end;
    Window.ShowNotice('7 Units verwenden noch Kunden. Anpassen?', 'In der Projektgruppe: 9 Units.',
      ['Im Projekt anpassen …', 'In der Projektgruppe anpassen …'], Rect(0, 0, 1200, 900));
    try
      Assert.IsTrue(Window.IsShown);
      Assert.IsTrue(Window.Timer.Enabled, 'verschwindet von selbst');
      Assert.AreEqual(TAtlasNoticeWindow.VisibleMs, Integer(Window.Timer.Interval));
      Assert.IsFalse(Window.ActionRect(0).IsEmpty);
      Assert.IsFalse(Window.ActionRect(1).IsEmpty);
      Assert.IsTrue(Window.ActionRect(1).Left > Window.ActionRect(0).Right, 'nebeneinander');
      Assert.IsTrue(Window.ActionRect(2).IsEmpty);
      Assert.IsFalse(Window.CloseRect.IsEmpty, '„×“ ist da');
      Window.ClickAction(5);
      Assert.AreEqual(-1, Chosen, 'unbekannte Aktion ohne Wirkung');
      Window.ClickAction(1);
      Assert.AreEqual(1, Chosen);
      Assert.IsFalse(Window.IsShown, 'Klick blendet aus');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoticeWindowTests);

end.
