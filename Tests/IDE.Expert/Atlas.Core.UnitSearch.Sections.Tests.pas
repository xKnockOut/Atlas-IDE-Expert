unit Atlas.Core.UnitSearch.Sections.Tests;

// Einklappbare Abschnitte im Detail-Panel der Unitsuche (#876): bei genug Platz
// alles offen, sonst die unwichtigsten zu, der wichtigste bleibt offen; die Wahl
// des Benutzers gewinnt und bleibt nur für die Sitzung (nicht im JSON).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.UnitSearch.Sections;

type
  [TestFixture]
  TAtlasUnitSectionLayoutTests = class
  private
    function Sizes(AHead, ABody: Integer): TAtlasUnitSectionSizes;
    function NoChoices: TAtlasUnitSectionChoices;
  public
    [Test]
    procedure AllOpenWhenEverythingFits;
    [Test]
    procedure ClosesLeastImportantFirst;
    [Test]
    procedure MostImportantStaysOpenWithoutRoom;
    [Test]
    procedure HeaderIsMostImportantWithoutTypes;
    [Test]
    procedure AbsentSectionsAreNeverOpen;
    [Test]
    procedure UserChoiceWinsOverRoom;
    [Test]
    procedure ToggleRemembersChoice;
    [Test]
    procedure HeightCountsHeadsAndOpenBodies;
    [Test]
    procedure StateKeepsChoicesOnlyForSession;
  end;

implementation

uses
  Atlas.Core.UnitSearch.State;

function TAtlasUnitSectionLayoutTests.Sizes(AHead, ABody: Integer): TAtlasUnitSectionSizes;
var
  Section: TAtlasUnitSection;
begin
  for Section := Low(TAtlasUnitSection) to High(TAtlasUnitSection) do
  begin
    Result[Section].Present := True;
    Result[Section].Head := AHead;
    Result[Section].Body := ABody;
  end;
end;

function TAtlasUnitSectionLayoutTests.NoChoices: TAtlasUnitSectionChoices;
var
  Section: TAtlasUnitSection;
begin
  for Section := Low(TAtlasUnitSection) to High(TAtlasUnitSection) do
    Result[Section] := TAtlasUnitSectionChoice.Auto;
end;

procedure TAtlasUnitSectionLayoutTests.AllOpenWhenEverythingFits;
var
  Open: TAtlasUnitSections;
begin
  // 4 × 20 Überschrift + 4 × 50 Inhalt = 280.
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 280, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Header, TAtlasUnitSection.Form, TAtlasUnitSection.Types,
    TAtlasUnitSection.UsedBy]);
end;

procedure TAtlasUnitSectionLayoutTests.ClosesLeastImportantFirst;
var
  Open: TAtlasUnitSections;
begin
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 279, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Header, TAtlasUnitSection.Form, TAtlasUnitSection.Types],
    'zuerst „Verwendet von“');
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 229, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Header, TAtlasUnitSection.Types], 'dann die Formularskizze');
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 179, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Types], 'dann der Kopfkommentar');
end;

procedure TAtlasUnitSectionLayoutTests.MostImportantStaysOpenWithoutRoom;
var
  Open: TAtlasUnitSections;
begin
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 0, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Types]);
end;

procedure TAtlasUnitSectionLayoutTests.HeaderIsMostImportantWithoutTypes;
var
  Values: TAtlasUnitSectionSizes;
  Open: TAtlasUnitSections;
  Section: TAtlasUnitSection;
begin
  Values := Sizes(20, 50);
  Values[TAtlasUnitSection.Types].Present := False;
  Assert.IsTrue(TAtlasUnitSectionLayout.MostImportant(Values, Section));
  Assert.IsTrue(Section = TAtlasUnitSection.Header);
  Open := TAtlasUnitSectionLayout.Resolve(Values, 0, NoChoices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Header]);
end;

procedure TAtlasUnitSectionLayoutTests.AbsentSectionsAreNeverOpen;
var
  Values: TAtlasUnitSectionSizes;
  Open: TAtlasUnitSections;
  Choices: TAtlasUnitSectionChoices;
  Section: TAtlasUnitSection;
begin
  Values := Default(TAtlasUnitSectionSizes);
  Assert.IsFalse(TAtlasUnitSectionLayout.MostImportant(Values, Section));
  Choices := NoChoices;
  Choices[TAtlasUnitSection.Form] := TAtlasUnitSectionChoice.Open;
  Open := TAtlasUnitSectionLayout.Resolve(Values, 1000, Choices);
  Assert.IsTrue(Open = []);
  Assert.AreEqual(0, TAtlasUnitSectionLayout.Height(Values, Open));
end;

procedure TAtlasUnitSectionLayoutTests.UserChoiceWinsOverRoom;
var
  Choices: TAtlasUnitSectionChoices;
  Open: TAtlasUnitSections;
begin
  Choices := NoChoices;
  Choices[TAtlasUnitSection.UsedBy] := TAtlasUnitSectionChoice.Open;
  Choices[TAtlasUnitSection.Types] := TAtlasUnitSectionChoice.Closed;
  // Kein Platz: geöffnetes „Verwendet von“ bleibt, geschlossene Typen bleiben zu, Rest automatisch zu.
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 0, Choices);
  Assert.IsTrue(Open = [TAtlasUnitSection.UsedBy]);
  // Genug Platz: geschlossene Typen bleiben zu, alle anderen offen.
  Open := TAtlasUnitSectionLayout.Resolve(Sizes(20, 50), 1000, Choices);
  Assert.IsTrue(Open = [TAtlasUnitSection.Header, TAtlasUnitSection.Form, TAtlasUnitSection.UsedBy]);
end;

procedure TAtlasUnitSectionLayoutTests.ToggleRemembersChoice;
var
  Choices: TAtlasUnitSectionChoices;
begin
  Choices := NoChoices;
  TAtlasUnitSectionLayout.Toggle(Choices, TAtlasUnitSection.Form, True);
  Assert.IsTrue(Choices[TAtlasUnitSection.Form] = TAtlasUnitSectionChoice.Closed);
  TAtlasUnitSectionLayout.Toggle(Choices, TAtlasUnitSection.Form, False);
  Assert.IsTrue(Choices[TAtlasUnitSection.Form] = TAtlasUnitSectionChoice.Open);
  Assert.IsTrue(Choices[TAtlasUnitSection.Header] = TAtlasUnitSectionChoice.Auto, 'andere unberührt');
end;

procedure TAtlasUnitSectionLayoutTests.HeightCountsHeadsAndOpenBodies;
begin
  Assert.AreEqual(80, TAtlasUnitSectionLayout.Height(Sizes(20, 50), []));
  Assert.AreEqual(180, TAtlasUnitSectionLayout.Height(Sizes(20, 50), [TAtlasUnitSection.Header,
    TAtlasUnitSection.UsedBy]));
  Assert.IsTrue(TAtlasUnitSectionLayout.Rank(TAtlasUnitSection.Types) <
    TAtlasUnitSectionLayout.Rank(TAtlasUnitSection.UsedBy));
end;

procedure TAtlasUnitSectionLayoutTests.StateKeepsChoicesOnlyForSession;
var
  State, Loaded: TAtlasUnitSearchState;
begin
  State := TAtlasUnitSearchState.Create;
  Loaded := TAtlasUnitSearchState.Create;
  try
    Assert.IsTrue(State.Sections[TAtlasUnitSection.Form] = TAtlasUnitSectionChoice.Auto, 'Vorgabe automatisch');
    State.Sections[TAtlasUnitSection.Form] := TAtlasUnitSectionChoice.Closed;
    Loaded.LoadJson(State.ToJson);
    Assert.IsTrue(Loaded.Sections[TAtlasUnitSection.Form] = TAtlasUnitSectionChoice.Auto, 'nicht gespeichert');
  finally
    Loaded.Free;
    State.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitSectionLayoutTests);

end.
