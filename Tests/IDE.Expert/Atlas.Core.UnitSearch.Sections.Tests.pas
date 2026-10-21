unit Atlas.Core.UnitSearch.Sections.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.UnitSearch.Sections;

type
  [TestFixture]
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
  None_: TAtlasSectionChoices = (TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto, TAtlasSectionChoice.Auto,
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
  States: TAtlasSectionStates;
begin
  States := TAtlasPreviewSections.Arrange(Inputs, None_, 380, True);
  Assert.IsTrue(States[TAtlasPreviewSection.Path] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.Types] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.Uses_] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.UsedBy] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.Header] = TAtlasSectionState.Hidden);
  Assert.AreEqual(380, TAtlasPreviewSections.Height(Inputs, States));
end;

procedure TAtlasPreviewSectionsTests.LessImportantCollapseFirst;
var
  States: TAtlasSectionStates;
begin
  // 340 Platz: der Pfad (380 - 20 = 360) reicht nicht, uses dazu (320) reicht.
  States := TAtlasPreviewSections.Arrange(Inputs, None_, 340, True);
  Assert.IsTrue(States[TAtlasPreviewSection.Path] = TAtlasSectionState.AutoCollapsed);
  Assert.IsTrue(States[TAtlasPreviewSection.Uses_] = TAtlasSectionState.AutoCollapsed);
  Assert.IsTrue(States[TAtlasPreviewSection.UsedBy] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.Types] = TAtlasSectionState.Open);
end;

procedure TAtlasPreviewSectionsTests.MostImportantStaysOpen;
var
  States: TAtlasSectionStates;
begin
  States := TAtlasPreviewSections.Arrange(Inputs, None_, 50, True);
  Assert.IsTrue(States[TAtlasPreviewSection.Types] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.UsedBy] = TAtlasSectionState.AutoCollapsed);
  Assert.IsTrue(States[TAtlasPreviewSection.Uses_] = TAtlasSectionState.AutoCollapsed);
  Assert.IsTrue(States[TAtlasPreviewSection.Path] = TAtlasSectionState.AutoCollapsed);
end;

procedure TAtlasPreviewSectionsTests.HandOpenedStaysOpen;
var
  Choices: TAtlasSectionChoices;
  States: TAtlasSectionStates;
begin
  Choices := None_;
  Choices[TAtlasPreviewSection.UsedBy] := TAtlasSectionChoice.HandOpen;
  States := TAtlasPreviewSections.Arrange(Inputs, Choices, 160, True);
  Assert.IsTrue(States[TAtlasPreviewSection.UsedBy] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.Types] = TAtlasSectionState.AutoCollapsed,
    'ein von Hand geöffneter Abschnitt bleibt offen, dafür klappen die übrigen ein');
  Assert.IsTrue(States[TAtlasPreviewSection.Uses_] = TAtlasSectionState.AutoCollapsed);
end;

procedure TAtlasPreviewSectionsTests.HandClosedStaysClosed;
var
  Choices: TAtlasSectionChoices;
  States: TAtlasSectionStates;
begin
  Choices := None_;
  Choices[TAtlasPreviewSection.Types] := TAtlasSectionChoice.HandClosed;
  States := TAtlasPreviewSections.Arrange(Inputs, Choices, 1000, True);
  Assert.IsTrue(States[TAtlasPreviewSection.Types] = TAtlasSectionState.Collapsed);
  Assert.IsTrue(States[TAtlasPreviewSection.Path] = TAtlasSectionState.Open);
end;

procedure TAtlasPreviewSectionsTests.SwitchedOffNothingCollapses;
var
  States: TAtlasSectionStates;
begin
  States := TAtlasPreviewSections.Arrange(Inputs, None_, 50, False);
  Assert.IsTrue(States[TAtlasPreviewSection.Path] = TAtlasSectionState.Open);
  Assert.IsTrue(States[TAtlasPreviewSection.UsedBy] = TAtlasSectionState.Open);
end;

procedure TAtlasPreviewSectionsTests.ToggleFlipsTheState;
begin
  Assert.IsTrue(TAtlasPreviewSections.Toggled(TAtlasSectionState.Open) = TAtlasSectionChoice.HandClosed);
  Assert.IsTrue(TAtlasPreviewSections.Toggled(TAtlasSectionState.AutoCollapsed) = TAtlasSectionChoice.HandOpen);
  Assert.IsTrue(TAtlasPreviewSections.Toggled(TAtlasSectionState.Collapsed) = TAtlasSectionChoice.HandOpen);
  Assert.IsFalse(TAtlasPreviewSections.IsOpen(TAtlasSectionState.AutoCollapsed));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPreviewSectionsTests);

end.
