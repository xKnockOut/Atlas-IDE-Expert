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
  Lines: TArray<string>;
  Index: Integer;
  Target: TAtlasPeekTarget;
begin
  SetLength(Lines, 60);
  for Index := 0 to High(Lines) do
    Lines[Index] := Format('  X%d := ''{''; // Zeile', [Index]);
  Lines[10] := 'procedure TBar.Add(A: Integer);';
  SetLength(Result, ACount);
  for Index := 0 to ACount - 1 do
  begin
    Target.Place := TAtlasPeekPlace.Create(Format('U%d.pas', [Index]), 10, 15);
    Target.HasBody := True;
    Target.Body := TAtlasPeekPlace.Create(Format('U%d.pas', [Index]), 30, 0);
    Result[Index].Target := Target;
    Result[Index].Excerpt := TAtlasPeek.Excerpt(Lines[10]);
    Result[Index].Rows := TAtlasPeek.DefinitionRows(Target, Lines, Lines, True, 4);
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
  Window: TAtlasPeekWindow;
  Small, Large: Integer;
begin
  Window := NewWindow;
  try
    Small := Window.HeightForLines(5);
    Large := Window.HeightForLines(15);
    Assert.IsTrue(Large > Small);
    // Zehn Zeilen mehr: zehnmal dieselbe Zeilenhöhe.
    Assert.AreEqual(0, (Large - Small) mod 10);
    Window.SetScaling(192, 1, 'Consolas', 10);
    Assert.IsTrue(Window.HeightForLines(15) > Large, 'wächst mit Zoom und DPI');
  finally
    Window.Free;
  end;
end;

procedure TAtlasPeekUiTests.WindowSetsPageRowsOfView;
var
  Window: TAtlasPeekWindow;
  Y: Integer;
begin
  Window := NewWindow;
  try
    Window.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.Definition, 'Definition: Add', Entries(1)),
      Rect(100, 100, 900, 100 + Window.HeightForLines(15)));
    try
      Assert.IsTrue(Window.IsShown);
      Assert.AreEqual(15, Window.View.PageRows);
      // Ohne Liste gehört jeder Klick in den Ausschnitt.
      for Y := 0 to Window.ClientHeight - 1 do
        Assert.AreEqual(-1, Window.EntryAt(Point(10, Y)));
    finally
      Window.Dismiss;
    end;
    Assert.IsFalse(Window.IsShown);
    Assert.IsNull(Window.View, 'Zustand freigegeben');
  finally
    Window.Free;
  end;
end;

procedure TAtlasPeekUiTests.ListOnlyWithSeveralTargets;
var
  Window: TAtlasPeekWindow;
  Y, Found: Integer;
begin
  Window := NewWindow;
  try
    Window.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.Definition, 'Definition: Add', Entries(3)),
      Rect(100, 100, 900, 100 + Window.HeightForLines(15)));
    try
      Found := -1;
      for Y := 0 to Window.ClientHeight - 1 do
        if Window.EntryAt(Point(10, Y)) = 2 then
        begin
          Found := Y;
          Break;
        end;
      Assert.IsTrue(Found > 0, 'Liste links mit drei Einträgen');
      Assert.AreEqual(-1, Window.EntryAt(Point(Window.ClientWidth - 10, Found)), 'rechts der Ausschnitt');
      Window.View.Select(2);
      Window.ViewChanged;
      Assert.AreEqual(2, Window.View.Selected);
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasPeekUiTests.PaintsInLightAndDarkTheme;
var
  Window: TAtlasPeekWindow;
begin
  Window := NewWindow;
  try
    Window.ShowView(TAtlasPeekView.Create(TAtlasPeekMode.References, 'Referenzen auf Add (3)', Entries(3)),
      Rect(100, 100, 900, 100 + Window.HeightForLines(15)));
    try
      Window.Repaint;
      Window.View.PageDown;
      Window.ViewChanged;
      Window.Colors := TAtlasColors.Dark;
      Window.Repaint;
      Application.ProcessMessages;
      Assert.IsTrue(Window.View.Top > 0);
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPeekUiTests);

end.
