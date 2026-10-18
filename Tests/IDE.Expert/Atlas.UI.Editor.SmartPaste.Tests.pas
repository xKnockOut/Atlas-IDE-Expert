unit Atlas.UI.Editor.SmartPaste.Tests;

// Einfügen mit uses-Ergänzung (#515), Fensterteil: Überschrift zählt
// eindeutige und gewählte Units, Wahl über Tasten und Klickflächen,
// Übernehmen und Verwerfen melden sich und blenden aus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSmartPasteWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TitleCountsUniqueAndChosenUnits;
    [Test]
    procedure KeysMoveRowAndChoice;
    [Test]
    procedure AcceptAndCancelReportAndHide;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.SmartPaste,
  Atlas.UI.Strings,
  Atlas.UI.Editor.SmartPaste;

function Analysis: TAtlasPasteAnalysis;
var
  Choice: TAtlasPasteChoice;
begin
  Result := Default(TAtlasPasteAnalysis);
  Result.Valid := True;
  Result.Units := ['System.JSON'];
  Choice.Name := 'TList';
  Choice.Units := ['System.Classes', 'System.Generics.Collections'];
  Choice.Chosen := -1;
  Result.Choices := [Choice];
  Choice.Name := 'TRect';
  Choice.Units := ['System.Types', 'Winapi.Windows'];
  Result.Choices := Result.Choices + [Choice];
end;

function NewWindow: TAtlasSmartPasteWindow;
begin
  Result := TAtlasSmartPasteWindow.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Segoe UI', 9);
end;

procedure TAtlasSmartPasteWindowTests.WarmUpFirstUse;
begin
  TitleCountsUniqueAndChosenUnits;
end;

procedure TAtlasSmartPasteWindowTests.TitleCountsUniqueAndChosenUnits;
var
  Window: TAtlasSmartPasteWindow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Window := NewWindow;
  try
    Window.ShowFor(Analysis, Point(100, 100));
    try
      Assert.AreEqual('Unit ergänzen: System.JSON', Window.Caption);
      Window.Choose(0, 1);
      Assert.AreEqual('2 Units ergänzen: System.JSON, System.Generics.Collections', Window.Caption);
      Window.Choose(1, 0);
      Window.Choose(0, 0);
      Assert.AreEqual('3 Units ergänzen: System.JSON, System.Classes, System.Types', Window.Caption);
      // Ungültige Wahl bleibt ohne Wirkung.
      Window.Choose(0, 5);
      Window.Choose(7, 0);
      Assert.AreEqual(0, Window.Analysis.Choices[0].Chosen);
      Assert.IsFalse(Window.OptionRect(0, -1).IsEmpty, '„keine“ ist anklickbar');
      Assert.IsFalse(Window.OptionRect(1, 1).IsEmpty);
      Assert.IsTrue(Window.OptionRect(1, 2).IsEmpty);
      Assert.IsTrue(Window.OptionRect(1, 0).Left > Window.OptionRect(1, -1).Right, 'nebeneinander');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasSmartPasteWindowTests.KeysMoveRowAndChoice;
var
  Window: TAtlasSmartPasteWindow;
  Plain: TAtlasPasteAnalysis;
begin
  Window := NewWindow;
  try
    Window.ShowFor(Analysis, Point(100, 100));
    try
      Assert.AreEqual(0, Window.Row);
      Assert.IsTrue(Window.MoveChoice(1));
      Assert.AreEqual(0, Window.Analysis.Choices[0].Chosen);
      Assert.IsTrue(Window.MoveChoice(-2), 'ringsum');
      Assert.AreEqual(1, Window.Analysis.Choices[0].Chosen);
      Assert.IsTrue(Window.MoveRow(1));
      Assert.AreEqual(1, Window.Row);
      Assert.IsTrue(Window.MoveRow(1));
      Assert.AreEqual(0, Window.Row, 'ringsum');
    finally
      Window.Dismiss;
    end;
    // Nur eindeutige Units: Pfeiltasten gehören dem Editor.
    Plain := Analysis;
    Plain.Choices := nil;
    Window.ShowFor(Plain, Point(100, 100));
    try
      Assert.AreEqual(-1, Window.Row);
      Assert.IsFalse(Window.MoveRow(1));
      Assert.IsFalse(Window.MoveChoice(1));
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasSmartPasteWindowTests.AcceptAndCancelReportAndHide;
var
  Window: TAtlasSmartPasteWindow;
  Accepted, Cancelled: Integer;
begin
  Accepted := 0;
  Cancelled := 0;
  Window := NewWindow;
  try
    Window.OnAccept :=
      procedure
      begin
        Inc(Accepted);
      end;
    Window.OnCancel :=
      procedure
      begin
        Inc(Cancelled);
      end;
    Window.ShowFor(Analysis, Point(100, 100));
    Assert.IsTrue(Window.IsShown);
    Assert.IsFalse(Window.AcceptRect.IsEmpty);
    Window.Accept;
    Assert.AreEqual(1, Accepted);
    Assert.IsFalse(Window.IsShown);
    Window.ShowFor(Analysis, Point(100, 100));
    Window.Cancel;
    Assert.AreEqual(1, Cancelled);
    Assert.AreEqual(1, Accepted);
    Assert.IsFalse(Window.IsShown);
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSmartPasteWindowTests);

end.
