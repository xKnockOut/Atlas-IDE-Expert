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
  mBounds: TRect;
begin
  mBounds := TAtlasNoticeWindow.PlaceCorner(Rect(100, 50, 1100, 850), 300, 80, 16, Rect(0, 0, 1920, 1040));
  Assert.AreEqual(784, mBounds.Left);
  Assert.AreEqual(754, mBounds.Top);
  Assert.AreEqual(300, mBounds.Width);
  Assert.AreEqual(80, mBounds.Height);
  // IDE-Fenster ragt über den Bildschirm hinaus: Der Hinweis bleibt im Arbeitsbereich.
  mBounds := TAtlasNoticeWindow.PlaceCorner(Rect(1000, 500, 2500, 1500), 300, 80, 16, Rect(0, 0, 1920, 1040));
  Assert.AreEqual(1604, mBounds.Left);
  Assert.AreEqual(944, mBounds.Top);
end;

procedure TAtlasNoticeWindowTests.ActionsReportIndexAndHide;
var
  mWindow: TAtlasNoticeWindow;
  mChosen: Integer;
begin
  mChosen := -1;
  mWindow := TAtlasNoticeWindow.Create(nil);
  try
    mWindow.Colors := TAtlasColors.Light;
    mWindow.SetScaling(96, 1, 'Segoe UI', 9);
    mWindow.OnAction :=
      procedure(AIndex: Integer)
      begin
        mChosen := AIndex;
      end;
    mWindow.ShowNotice('7 Units verwenden noch Kunden. Anpassen?', 'In der Projektgruppe: 9 Units.',
      ['Im Projekt anpassen …', 'In der Projektgruppe anpassen …'], Rect(0, 0, 1200, 900));
    try
      Assert.IsTrue(mWindow.IsShown);
      Assert.IsTrue(mWindow.Timer.Enabled, 'verschwindet von selbst');
      Assert.AreEqual(TAtlasNoticeWindow.cVisibleMs, Integer(mWindow.Timer.Interval));
      Assert.IsFalse(mWindow.ActionRect(0).IsEmpty);
      Assert.IsFalse(mWindow.ActionRect(1).IsEmpty);
      Assert.IsTrue(mWindow.ActionRect(1).Left > mWindow.ActionRect(0).Right, 'nebeneinander');
      Assert.IsTrue(mWindow.ActionRect(2).IsEmpty);
      Assert.IsFalse(mWindow.CloseRect.IsEmpty, '„×“ ist da');
      mWindow.ClickAction(5);
      Assert.AreEqual(-1, mChosen, 'unbekannte Aktion ohne Wirkung');
      mWindow.ClickAction(1);
      Assert.AreEqual(1, mChosen);
      Assert.IsFalse(mWindow.IsShown, 'Klick blendet aus');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNoticeWindowTests);

end.
