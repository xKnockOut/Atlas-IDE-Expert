unit Atlas.UI.Editor.Peek.Tests;

// Fenster von Definition und Referenzen einblenden (#505): Höhe nach Zeilen,
// sichtbare Zeilen an die Ansicht, Liste nur bei mehreren Zielen und Wahl per
// Klick, Freigabe des Zustands beim Schließen, Zeichnen im hellen und dunklen
// Thema ohne Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPeekUiTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure HeightGrowsWithLines;
    [Test]
    procedure WindowSetsPageRowsOfView;
    [Test]
    procedure ListOnlyWithSeveralTargets;
    [Test]
    procedure PaintsInLightAndDarkTheme;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Peek,
  Atlas.UI.Editor.Peek;

function Entries(ACount: Integer): TArray<TAtlasPeekEntry>;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mTarget: TAtlasPeekTarget;
begin
  SetLength(mLines, 60);
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := Format('  X%d := ''{''; // Zeile', [mIndex]);
  end;
  mLines[10] := 'procedure TBar.Add(A: Integer);';
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    mTarget.Place := TAtlasPeekPlace.Create(Format('U%d.pas', [mIndex]), 10, 15);
    mTarget.HasBody := True;
    mTarget.Body := TAtlasPeekPlace.Create(Format('U%d.pas', [mIndex]), 30, 0);
    Result[mIndex].Target := mTarget;
    Result[mIndex].Excerpt := TAtlasPeek.Excerpt(mLines[10]);
    Result[mIndex].Rows := TAtlasPeek.DefinitionRows(mTarget, mLines, mLines, True, 4);
  end;
end;

function NewWindow: TAtlasPeekWindow;
begin
  Result := TAtlasPeekWindow.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Consolas', 10);
end;

procedure TAtlasPeekUiTests.WarmUpFirstUse;
begin
  HeightGrowsWithLines;
end;

procedure TAtlasPeekUiTests.HeightGrowsWithLines;
var
  mWindow: TAtlasPeekWindow;
  mSmall, mLarge: Integer;
begin
  mWindow := NewWindow;
  try
    mSmall := mWindow.HeightForLines(5);
    mLarge := mWindow.HeightForLines(15);
    Assert.IsTrue(mLarge > mSmall);
    // Zehn Zeilen mehr: zehnmal dieselbe Zeilenhöhe.
    Assert.AreEqual(0, (mLarge - mSmall) mod 10);
    mWindow.SetScaling(192, 1, 'Consolas', 10);
    Assert.IsTrue(mWindow.HeightForLines(15) > mLarge, 'wächst mit Zoom und DPI');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasPeekUiTests.WindowSetsPageRowsOfView;
var
  mWindow: TAtlasPeekWindow;
  Y: Integer;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.Definition, 'Definition: Add', Entries(1)),
      Rect(100, 100, 900, 100 + mWindow.HeightForLines(15)));
    try
      Assert.IsTrue(mWindow.IsShown);
      Assert.AreEqual(15, mWindow.View.PageRows);
      // Ohne Liste gehört jeder Klick in den Ausschnitt.
      for Y := 0 to mWindow.ClientHeight - 1 do
      begin
        Assert.AreEqual(-1, mWindow.EntryAt(Point(10, Y)));
      end;
    finally
      mWindow.Dismiss;
    end;
    Assert.IsFalse(mWindow.IsShown);
    Assert.IsNull(mWindow.View, 'Zustand freigegeben');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasPeekUiTests.ListOnlyWithSeveralTargets;
var
  mWindow: TAtlasPeekWindow;
  Y, mFound: Integer;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.Definition, 'Definition: Add', Entries(3)),
      Rect(100, 100, 900, 100 + mWindow.HeightForLines(15)));
    try
      mFound := -1;
      for Y := 0 to mWindow.ClientHeight - 1 do
      begin
        if mWindow.EntryAt(Point(10, Y)) = 2 then
        begin
          mFound := Y;
          Break;
        end;
      end;
      Assert.IsTrue(mFound > 0, 'Liste links mit drei Einträgen');
      Assert.AreEqual(-1, mWindow.EntryAt(Point(mWindow.ClientWidth - 10, mFound)), 'rechts der Ausschnitt');
      mWindow.View.Select(2);
      mWindow.ViewChanged;
      Assert.AreEqual(2, mWindow.View.Selected);
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasPeekUiTests.PaintsInLightAndDarkTheme;
var
  mWindow: TAtlasPeekWindow;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.References, 'Referenzen auf Add (3)', Entries(3)),
      Rect(100, 100, 900, 100 + mWindow.HeightForLines(15)));
    try
      mWindow.Repaint;
      mWindow.View.PageDown;
      mWindow.ViewChanged;
      mWindow.Colors := TAtlasColors.Dark;
      mWindow.Repaint;
      Application.ProcessMessages;
      Assert.IsTrue(mWindow.View.Top > 0);
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPeekUiTests);

end.
