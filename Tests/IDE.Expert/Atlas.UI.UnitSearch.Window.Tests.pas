unit Atlas.UI.UnitSearch.Window.Tests;

// Fenster „Units suchen“ (#777), Detail-Panel mit einklappbaren Abschnitten
// (#876): bei genug Höhe alles offen, bei kleiner Höhe nur die Typen; Klick auf
// eine Überschrift öffnet, die Wahl bleibt im Zustand der Sitzung.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasUnitSearchWindowTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AllSectionsOpenWithEnoughHeight;
    [Test]
    procedure SmallHeightCollapsesLessImportantSections;
    [Test]
    procedure ClickOnHeadingOpensAndIsRemembered;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.State,
  Atlas.Core.UnitSearch.Sections,
  Atlas.UI.UnitSearch.Window;

type
  // Zugriff auf MouseDown und ScaleValue fürs Klicken und Bemessen.
  TWindowAccess = class(TAtlasUnitSearchWindow);

function SampleEntry: TAtlasUnitEntry;
begin
  Result := Default(TAtlasUnitEntry);
  Result.Name := 'Kunde';
  Result.FileName := 'C:\Projekt\Kunde.pas';
  Result.Project := 'Projekt';
  Result.Origin := TAtlasUnitOrigin.Active;
  Result.Kind := TAtlasUnitKind.Form;
end;

function SamplePreview(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview;
var
  Index: Integer;
  Item: TAtlasUnitType;
begin
  Result := Default(TAtlasUnitPreview);
  Result.FileName := AEntry.FileName;
  Result.Lines := 120;
  Result.Header := '// Kunden verwalten.'#10'// Zweite Zeile.'#10'// Dritte Zeile.';
  for Index := 1 to 6 do
  begin
    Item.Name := 'TKunde' + IntToStr(Index);
    Item.Kind := 'class';
    Result.Types := Result.Types + [Item];
  end;
  Result.UsedBy := 2;
  Result.UsedByUnits := ['Lager', 'Rechnung'];
  Result.HasForm := True;
  Result.FormCaption := 'Kunde';
  Result.FormWidth := 400;
  Result.FormHeight := 300;
end;

function CreateWindow(AState: TAtlasUnitSearchState; AHeight: Integer): TWindowAccess;
var
  Options: TAtlasUnitSearchOptions;
begin
  Options := Default(TAtlasUnitSearchOptions);
  Options.Preview := True;
  Options.Grouping := TAtlasUnitGrouping.None;
  Options.DefaultOrigins := [Low(TAtlasUnitOrigin)..High(TAtlasUnitOrigin)];
  Result := TWindowAccess(TWindowAccess.CreateSearch(nil, Options, AState, TAtlasColors.Light));
  Result.OnPreview := SamplePreview;
  Result.SetBounds(0, 0, Result.ScaleValue(900), Result.ScaleValue(AHeight));
  Result.SetEntries([SampleEntry]);
  Result.RefreshPreview;
end;

procedure Click(AWindow: TWindowAccess; ASection: TAtlasUnitSection);
var
  Head: TRect;
begin
  Head := AWindow.SectionHeadRect(ASection);
  Assert.IsFalse(Head.IsEmpty, 'Überschrift sichtbar');
  AWindow.MouseDown(mbLeft, [], Head.Left + 4, Head.Top + Head.Height div 2);
end;

{ TAtlasUnitSearchWindowTests }

procedure TAtlasUnitSearchWindowTests.WarmUpFirstUse;
begin
  Setup;
  try
    AllSectionsOpenWithEnoughHeight;
  finally
    TearDown;
  end;
end;

procedure TAtlasUnitSearchWindowTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasUnitSearchWindowTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasUnitSearchWindowTests.AllSectionsOpenWithEnoughHeight;
var
  State: TAtlasUnitSearchState;
  Window: TWindowAccess;
  Section: TAtlasUnitSection;
begin
  State := TAtlasUnitSearchState.Create;
  try
    Window := CreateWindow(State, 900);
    try
      for Section := Low(TAtlasUnitSection) to High(TAtlasUnitSection) do
      begin
        Assert.IsTrue(Window.SectionPresent(Section), 'vorhanden');
        Assert.IsTrue(Window.SectionOpen(Section), 'offen wie bisher');
      end;
    finally
      Window.Free;
    end;
  finally
    State.Free;
  end;
end;

procedure TAtlasUnitSearchWindowTests.SmallHeightCollapsesLessImportantSections;
var
  State: TAtlasUnitSearchState;
  Window: TWindowAccess;
begin
  State := TAtlasUnitSearchState.Create;
  try
    Window := CreateWindow(State, 260);
    try
      Assert.IsTrue(Window.SectionOpen(TAtlasUnitSection.Types), 'wichtigster bleibt offen');
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.Header));
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.Form));
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.UsedBy));
      // Größer gezogen: alles wieder offen.
      Window.SetBounds(0, 0, Window.ScaleValue(900), Window.ScaleValue(900));
      Assert.IsTrue(Window.SectionOpen(TAtlasUnitSection.Header));
      Assert.IsTrue(Window.SectionOpen(TAtlasUnitSection.UsedBy));
    finally
      Window.Free;
    end;
  finally
    State.Free;
  end;
end;

procedure TAtlasUnitSearchWindowTests.ClickOnHeadingOpensAndIsRemembered;
var
  State: TAtlasUnitSearchState;
  Window: TWindowAccess;
begin
  State := TAtlasUnitSearchState.Create;
  try
    Window := CreateWindow(State, 260);
    try
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.Header));
      Click(Window, TAtlasUnitSection.Header);
      Assert.IsTrue(Window.SectionOpen(TAtlasUnitSection.Header), 'Klick öffnet');
      Assert.IsTrue(State.Sections[TAtlasUnitSection.Header] = TAtlasUnitSectionChoice.Open);
      Click(Window, TAtlasUnitSection.Types);
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.Types), 'Klick schließt auch den wichtigsten');
    finally
      Window.Free;
    end;
    // Neues Fenster in derselben Sitzung: Wahl bleibt.
    Window := CreateWindow(State, 260);
    try
      Assert.IsTrue(Window.SectionOpen(TAtlasUnitSection.Header));
      Assert.IsFalse(Window.SectionOpen(TAtlasUnitSection.Types));
    finally
      Window.Free;
    end;
  finally
    State.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitSearchWindowTests);

end.
