unit Atlas.Core.UnitSearch.Sections.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.UnitSearch.Sections;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasPreviewSectionsTests = class
  private
    function Inputs: TAtlasSectionInputs;
  public
    [Test]
    procedure EverythingOpenWithEnoughRoom;
    [Test]
    procedure LessImportantCollapseFirst;
    [Test]
    procedure MostImportantStaysOpen;
    [Test]
    procedure HandOpenedStaysOpen;
    [Test]
    procedure HandClosedStaysClosed;
    [Test]
    procedure SwitchedOffNothingCollapses;
    [Test]
    procedure ToggleFlipsTheState;
  end;

implementation

const
  cNone_: TAtlasSectionChoices = (TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto,
    TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto);

function Input(AOpen: Integer): TAtlasSectionInput;
begin
  Result.Present := AOpen > 0;
  Result.OpenHeight := AOpen;
  Result.ClosedHeight := 20;
end;

function TAtlasPreviewSectionsTests.Inputs: TAtlasSectionInputs;
begin
  // Pfad 40, ohne Kopfkommentar und Formular, Typen 200, uses 60, verwendet von 80: zusammen 380.
  Result[TAtlasPreviewSection.Path] := Input(40);
  Result[TAtlasPreviewSection.Header] := Input(0);
  Result[TAtlasPreviewSection.Form] := Input(0);
  Result[TAtlasPreviewSection.Types] := Input(200);
  Result[TAtlasPreviewSection.Uses_] := Input(60);
  Result[TAtlasPreviewSection.UsedBy] := Input(80);
end;

procedure TAtlasPreviewSectionsTests.EverythingOpenWithEnoughRoom;
var
  mStates: TAtlasSectionStates;
begin
  mStates := TAtlasPreviewSections.Arrange(Inputs, cNone_, 380, True);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Path]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Types]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Uses_]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.UsedBy]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Hidden, mStates[TAtlasPreviewSection.Header]);
  Assert.AreEqual(380, TAtlasPreviewSections.Height(Inputs, mStates));
end;

procedure TAtlasPreviewSectionsTests.LessImportantCollapseFirst;
var
  mStates: TAtlasSectionStates;
begin
  // 340 Platz: der Pfad (380 - 20 = 360) reicht nicht, uses dazu (320) reicht.
  mStates := TAtlasPreviewSections.Arrange(Inputs, cNone_, 340, True);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Path]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Uses_]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.UsedBy]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Types]);
end;

procedure TAtlasPreviewSectionsTests.MostImportantStaysOpen;
var
  mStates: TAtlasSectionStates;
begin
  mStates := TAtlasPreviewSections.Arrange(Inputs, cNone_, 50, True);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Types]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.UsedBy]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Uses_]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Path]);
end;

procedure TAtlasPreviewSectionsTests.HandOpenedStaysOpen;
var
  mChoices: TAtlasSectionChoices;
  mStates: TAtlasSectionStates;
begin
  mChoices := cNone_;
  mChoices[TAtlasPreviewSection.UsedBy] := TAtlasSectionChoice.HandOpen;
  mStates := TAtlasPreviewSections.Arrange(Inputs, mChoices, 160, True);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.UsedBy]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Types],
    'ein von Hand geöffneter Abschnitt bleibt offen, dafür klappen die übrigen ein');
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.AutoCollapsed, mStates[TAtlasPreviewSection.Uses_]);
end;

procedure TAtlasPreviewSectionsTests.HandClosedStaysClosed;
var
  mChoices: TAtlasSectionChoices;
  mStates: TAtlasSectionStates;
begin
  mChoices := cNone_;
  mChoices[TAtlasPreviewSection.Types] := TAtlasSectionChoice.HandClosed;
  mStates := TAtlasPreviewSections.Arrange(Inputs, mChoices, 1000, True);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Collapsed, mStates[TAtlasPreviewSection.Types]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Path]);
end;

procedure TAtlasPreviewSectionsTests.SwitchedOffNothingCollapses;
var
  mStates: TAtlasSectionStates;
begin
  mStates := TAtlasPreviewSections.Arrange(Inputs, cNone_, 50, False);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.Path]);
  Assert.AreEqual<TAtlasSectionState>(TAtlasSectionState.Open, mStates[TAtlasPreviewSection.UsedBy]);
end;

procedure TAtlasPreviewSectionsTests.ToggleFlipsTheState;
begin
  Assert.AreEqual<TAtlasSectionChoice>(TAtlasSectionChoice.HandClosed,
    TAtlasPreviewSections.Toggled(TAtlasSectionState.Open));
  Assert.AreEqual<TAtlasSectionChoice>(TAtlasSectionChoice.HandOpen,
    TAtlasPreviewSections.Toggled(TAtlasSectionState.AutoCollapsed));
  Assert.AreEqual<TAtlasSectionChoice>(TAtlasSectionChoice.HandOpen,
    TAtlasPreviewSections.Toggled(TAtlasSectionState.Collapsed));
  Assert.IsFalse(TAtlasPreviewSections.IsOpen(TAtlasSectionState.AutoCollapsed));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPreviewSectionsTests);

end.
