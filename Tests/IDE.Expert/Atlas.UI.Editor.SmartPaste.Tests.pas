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
  mChoice: TAtlasPasteChoice;
begin
  Result := Default(TAtlasPasteAnalysis);
  Result.Valid := True;
  Result.Units := ['System.JSON'];
  mChoice.Name := 'TList';
  mChoice.Units := ['System.Classes', 'System.Generics.Collections'];
  mChoice.Chosen := -1;
  Result.Choices := [mChoice];
  mChoice.Name := 'TRect';
  mChoice.Units := ['System.Types', 'Winapi.Windows'];
  Result.Choices := Result.Choices + [mChoice];
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
  mWindow: TAtlasSmartPasteWindow;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mWindow := NewWindow;
  try
    mWindow.ShowFor(Analysis, Point(100, 100));
    try
      Assert.AreEqual('Unit ergänzen: System.JSON', mWindow.Caption);
      mWindow.Choose(0, 1);
      Assert.AreEqual('2 Units ergänzen: System.JSON, System.Generics.Collections', mWindow.Caption);
      mWindow.Choose(1, 0);
      mWindow.Choose(0, 0);
      Assert.AreEqual('3 Units ergänzen: System.JSON, System.Classes, System.Types', mWindow.Caption);
      // Ungültige Wahl bleibt ohne Wirkung.
      mWindow.Choose(0, 5);
      mWindow.Choose(7, 0);
      Assert.AreEqual(0, mWindow.Analysis.Choices[0].Chosen);
      Assert.IsFalse(mWindow.OptionRect(0, -1).IsEmpty, '„keine“ ist anklickbar');
      Assert.IsFalse(mWindow.OptionRect(1, 1).IsEmpty);
      Assert.IsTrue(mWindow.OptionRect(1, 2).IsEmpty);
      Assert.IsTrue(mWindow.OptionRect(1, 0).Left > mWindow.OptionRect(1, -1).Right, 'nebeneinander');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSmartPasteWindowTests.KeysMoveRowAndChoice;
var
  mWindow: TAtlasSmartPasteWindow;
  mPlain: TAtlasPasteAnalysis;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowFor(Analysis, Point(100, 100));
    try
      Assert.AreEqual(0, mWindow.Row);
      Assert.IsTrue(mWindow.MoveChoice(1));
      Assert.AreEqual(0, mWindow.Analysis.Choices[0].Chosen);
      Assert.IsTrue(mWindow.MoveChoice(-2), 'ringsum');
      Assert.AreEqual(1, mWindow.Analysis.Choices[0].Chosen);
      Assert.IsTrue(mWindow.MoveRow(1));
      Assert.AreEqual(1, mWindow.Row);
      Assert.IsTrue(mWindow.MoveRow(1));
      Assert.AreEqual(0, mWindow.Row, 'ringsum');
    finally
      mWindow.Dismiss;
    end;
    // Nur eindeutige Units: Pfeiltasten gehören dem Editor.
    mPlain := Analysis;
    mPlain.Choices := nil;
    mWindow.ShowFor(mPlain, Point(100, 100));
    try
      Assert.AreEqual(-1, mWindow.Row);
      Assert.IsFalse(mWindow.MoveRow(1));
      Assert.IsFalse(mWindow.MoveChoice(1));
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSmartPasteWindowTests.AcceptAndCancelReportAndHide;
var
  mWindow: TAtlasSmartPasteWindow;
  mAccepted, mCancelled: Integer;
begin
  mAccepted := 0;
  mCancelled := 0;
  mWindow := NewWindow;
  try
    mWindow.OnAccept :=
      procedure
      begin
        Inc(mAccepted);
      end;
    mWindow.OnCancel :=
      procedure
      begin
        Inc(mCancelled);
      end;
    mWindow.ShowFor(Analysis, Point(100, 100));
    Assert.IsTrue(mWindow.IsShown);
    Assert.IsFalse(mWindow.AcceptRect.IsEmpty);
    mWindow.Accept;
    Assert.AreEqual(1, mAccepted);
    Assert.IsFalse(mWindow.IsShown);
    mWindow.ShowFor(Analysis, Point(100, 100));
    mWindow.Cancel;
    Assert.AreEqual(1, mCancelled);
    Assert.AreEqual(1, mAccepted);
    Assert.IsFalse(mWindow.IsShown);
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSmartPasteWindowTests);

end.
