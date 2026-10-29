unit Atlas.UI.Architecture.Frame.Tests;

// Fenster „Atlas-Architektur“ (#1118), Fensterinhalt: Tabellen und Bäume aus
// den Daten des Servers, Sortieren per Spaltenklick, Filter, Öffnen von Unit
// und uses-Eintrag, Hinweise, Umfang und Bibliotheks-Units, Treffer der
// Karte; Reiter „Vergleich“ und Änderungen auf der Karte (#1121); Regler
// „Feinheit“ mit Wert und Zahl der Teilsysteme (#1366).

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Architecture.Frame;

type
  [TestFixture]
  TAtlasArchitectureFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasArchitectureFrame;
    FOpened: string;
    FLine: Integer;
  public
    /// <summary>Einmalige VCL-Puffer (PageControl, Listen, Karte) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsTablesAndTrees;
    [Test]
    procedure SortsByColumnClick;
    [Test]
    procedure CostRankingSortsByTotal;
    [Test]
    procedure FilterNarrowsEverything;
    [Test]
    procedure OpensUnitAndUsesEntry;
    [Test]
    procedure MessageScopeAndLibrary;
    [Test]
    procedure MapSelectsUnitUnderMouse;
    [Test]
    procedure PathCyclesAndSubsystems;
    [Test]
    procedure ComparisonTabAndMapChanges;
    [Test]
    procedure WithoutComparisonShowsHint;
    [Test]
    procedure RouteFromSymbolPath;
    [Test]
    procedure ResolutionSliderReportsOnRelease;
    [Test]
    procedure ResolutionSliderCanBeHidden;
    [Test]
    procedure ComparisonNamesDifferentResolution;
    [Test]
    procedure SplitSubsystemsGroupedInMenuAndTree;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Model.Tests;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

procedure TAtlasArchitectureFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    FillsTablesAndTrees;
  finally
    TearDown;
  end;
end;

procedure TAtlasArchitectureFrameTests.SetUp;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 600;
  FFrame := TAtlasArchitectureFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.OnOpenUnit :=
    procedure(AFileName: string)
    begin
      FOpened := AFileName;
      FLine := 0;
    end;
  FFrame.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled);
  FFrame.SetModel(Model);
end;

procedure TAtlasArchitectureFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
end;

procedure TAtlasArchitectureFrameTests.FillsTablesAndTrees;
begin
  Assert.AreEqual(3, Integer(Length(FFrame.CentralText)));
  Assert.IsTrue(Length(FFrame.SubsystemText) >= 7, 'Teilsysteme und ihre sechs Units');
  // Zyklus mit Weg und seinen beiden uses-Einträgen.
  Assert.AreEqual(3, Integer(Length(FFrame.CycleText)));
  Assert.IsTrue(StartsStr(TAtlasStrings.Text(TAtlasTextId.ArchitectureCycleImplementation), FFrame.CycleText[0]));
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.CycleText)) > 0);
  Assert.IsTrue(Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureStatus, [6, Length(FFrame.Model.Subsystems), 1,
    Length(FFrame.Model.CrossLinks), Integer(FFrame.Model.Generation and $7FFFFFFF), FFrame.Model.DurationMs]),
    FFrame.StatusLabel.Caption) = 1);
  // Aktive Ausschlüsse stehen in der Statuszeile.
  Assert.IsTrue(Pos('Tests/**', FFrame.StatusLabel.Caption) > 0);
  Assert.IsTrue(FFrame.SaveButton.Enabled);
end;

procedure TAtlasArchitectureFrameTests.SortsByColumnClick;
var
  Lines: TArray<string>;
begin
  // Vorgabe: gesamt abhängig, die größten zuerst.
  Lines := FFrame.CentralText;
  Assert.IsTrue(StrToInt(Lines[0].Split([#9])[3]) >= StrToInt(Lines[1].Split([#9])[3]));
  FFrame.CentralList.OnColumnClick(FFrame.CentralList, FFrame.CentralList.Columns[0]);
  Assert.IsTrue(FFrame.SortColumn = TAtlasArchColumn.Name);
  Assert.IsFalse(FFrame.SortDescending);
  Lines := FFrame.CentralText;
  Assert.IsTrue(CompareText(Lines[0].Split([#9])[0], Lines[1].Split([#9])[0]) < 0);
  FFrame.CentralList.OnColumnClick(FFrame.CentralList, FFrame.CentralList.Columns[0]);
  Assert.IsTrue(FFrame.SortDescending);
  Lines := FFrame.CentralText;
  Assert.IsTrue(CompareText(Lines[0].Split([#9])[0], Lines[1].Split([#9])[0]) > 0);
end;

procedure TAtlasArchitectureFrameTests.CostRankingSortsByTotal;
var
  Lines: TArray<string>;
  Index: Integer;
begin
  // Teuerste Units (#554): auch nach anderer Sortierung und auf anderem Reiter wieder „gesamt abhängig“ absteigend.
  FFrame.CentralList.OnColumnClick(FFrame.CentralList, FFrame.CentralList.Columns[0]);
  FFrame.Pages.ActivePageIndex := 0;
  FFrame.ShowCostRanking;
  Assert.IsTrue(FFrame.SortColumn = TAtlasArchColumn.Total);
  Assert.IsTrue(FFrame.SortDescending);
  Assert.IsTrue(FFrame.Pages.ActivePage = FFrame.CentralList.Parent, 'Reiter „Zentrale Units“');
  Lines := FFrame.CentralText;
  for Index := 1 to High(Lines) do
    Assert.IsTrue(StrToInt(Lines[Index - 1].Split([#9])[3]) >= StrToInt(Lines[Index].Split([#9])[3]));
end;

procedure TAtlasArchitectureFrameTests.FilterNarrowsEverything;
begin
  FFrame.Filter.Text := 'cache';
  Assert.AreEqual('cache', FFrame.Map.Filter);
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.SubsystemText)) > 0);
  Assert.AreEqual(0, Pos('App.Ui.Form', Joined(FFrame.SubsystemText)));
  Assert.AreEqual(3, Integer(Length(FFrame.CycleText)), 'der Zyklus enthält App.Data.Cache');
  FFrame.Filter.Text := 'ui form';
  Assert.AreEqual(0, Integer(Length(FFrame.CycleText)));
  FFrame.Filter.Text := '';
end;

procedure TAtlasArchitectureFrameTests.OpensUnitAndUsesEntry;
var
  Unit_: Integer;
begin
  Unit_ := FFrame.Model.IndexOf('App.Data.Db');
  FFrame.OpenUnit(Unit_);
  Assert.IsTrue(EndsText('Db.pas', FOpened));
  Assert.IsTrue(StartsText('C:\Projekt', FOpened));
  Assert.AreEqual(0, FLine);
  // uses-Eintrag ohne Fundstelle (kein Quelltext im Test): die Unit, in der er steht.
  FOpened := '';
  FFrame.OpenLink(FFrame.Model.Cycles[0].Edges[0]);
  Assert.IsTrue(EndsText('.pas', FOpened));
end;

procedure TAtlasArchitectureFrameTests.MessageScopeAndLibrary;
var
  Scope: string;
  Library_: Boolean;
begin
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureLoading), True);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureLoading), FFrame.StatusLabel.Caption);
  Assert.IsTrue(FFrame.HasModel, 'bisherige Daten bleiben');
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoProject), False);
  Assert.IsFalse(FFrame.HasModel);
  Assert.AreEqual(0, Integer(Length(FFrame.CentralText)));
  Assert.IsFalse(FFrame.SaveButton.Enabled);
  Scope := '';
  FFrame.OnScopeChanged :=
    procedure(AScope: string)
    begin
      Scope := AScope;
    end;
  FFrame.ScopeValue := 'project';
  Assert.AreEqual('', Scope, 'Setzen von außen meldet nichts');
  Assert.AreEqual('project', FFrame.ScopeValue);
  Library_ := False;
  FFrame.OnLibraryChanged :=
    procedure(AValue: Boolean)
    begin
      Library_ := AValue;
    end;
  FFrame.IncludeLibrary := True;
  Assert.IsFalse(Library_, 'Setzen von außen meldet nichts');
  FFrame.LibraryCheck.Checked := False;
  Assert.IsFalse(FFrame.IncludeLibrary);
  FFrame.OnScopeChanged := nil;
  FFrame.OnLibraryChanged := nil;
end;

procedure TAtlasArchitectureFrameTests.MapSelectsUnitUnderMouse;
var
  Unit_: Integer;
  Fitted: Double;
begin
  FFrame.Map.FitView;
  Fitted := FFrame.Map.View.Scale;
  Unit_ := FFrame.Model.IndexOf('App.Main');
  Assert.AreEqual(Unit_, FFrame.Map.View.UnitAt(FFrame.Map.Model, FFrame.Map.View.ScreenX(FFrame.Model.Units[Unit_].X),
    FFrame.Map.View.ScreenY(FFrame.Model.Units[Unit_].Y)));
  FFrame.Map.SelectUnit(Unit_, True);
  Assert.AreEqual(Unit_, FFrame.Map.Selected);
  Assert.AreEqual(Double(FFrame.Map.ClientWidth / 2), FFrame.Map.View.ScreenX(FFrame.Model.Units[Unit_].X), 0.5);
  FFrame.Map.SelectUnit(99, False);
  Assert.AreEqual(-1, FFrame.Map.Selected);
  // „Namen“ blendet die Beschriftungen aus, „Einpassen“ holt die Karte zurück.
  FFrame.NamesCheck.Checked := False;
  Assert.IsFalse(FFrame.Map.ShowNames);
  FFrame.NamesCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.ShowNames);
  FFrame.Map.ZoomBy(4);
  FFrame.FitButton.Click;
  Assert.AreEqual(Fitted, FFrame.Map.View.Scale, 0.0001, 'nach dem Einpassen wieder der Maßstab vom Anfang');
end;

procedure TAtlasArchitectureFrameTests.PathCyclesAndSubsystems;
var
  Main, Cache, Db: Integer;
begin
  Main := FFrame.Model.IndexOf('App.Main');
  Cache := FFrame.Model.IndexOf('App.Data.Cache');
  Db := FFrame.Model.IndexOf('App.Data.Db');
  // Weg wie in der HTML-Karte; die Zeile unter der Karte nennt ihn.
  Assert.IsTrue(FFrame.Map.ShowPath(Main, Cache));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitecturePath, [3,
    'App.Main → App.Data → App.Data.Db → App.Data.Cache']), FFrame.InfoLabel.Caption);
  Assert.IsFalse(FFrame.Map.ShowPath(Cache, Main));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureNoPath, ['App.Data.Cache', 'App.Main']),
    FFrame.InfoLabel.Caption);
  // Ohne implementation-uses gibt es Cache → Db nicht mehr; der Weg wird neu gesucht.
  Assert.IsTrue(FFrame.Map.ShowPath(Cache, Db));
  FFrame.ImplementationCheck.Checked := False;
  Assert.IsFalse(FFrame.Map.ShowImplementation);
  Assert.IsFalse(FFrame.Map.PathFound);
  FFrame.ImplementationCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.PathFound);
  // Esc hebt den Weg auf, danach wieder der Hinweis.
  FFrame.Map.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.PathFrom);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureMapHint), FFrame.InfoLabel.Caption);
  FFrame.Map.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.PathTo, 'zweimal aufheben schadet nicht');
  // Zyklen markieren.
  Assert.IsFalse(FFrame.Map.MarkCycles);
  FFrame.MarkCyclesCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.MarkCycles);
  // Teilsysteme aus- und einblenden über das Menü.
  FFrame.FillSubsystemsMenu;
  Assert.AreEqual(Integer(Length(FFrame.Model.Subsystems)) + 2, FFrame.SubsystemsMenu.Items.Count);
  FFrame.SubsystemsMenu.Items[FFrame.Model.Units[Cache].Subsystem].Click;
  Assert.IsFalse(FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem]);
  Assert.IsFalse(FFrame.SubsystemsMenu.Items[FFrame.Model.Units[Cache].Subsystem].Checked);
  Assert.IsFalse(FFrame.Map.ShowPath(Main, Cache), 'Units ausgeblendeter Teilsysteme sind kein Ziel');
  FFrame.SubsystemsMenu.Items[FFrame.SubsystemsMenu.Items.Count - 1].Click;
  Assert.IsTrue(FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem]);
  Assert.IsTrue(FFrame.Map.PathFound, 'nach dem Einblenden wird der Weg neu gesucht');
  FFrame.Map.ClearPath;
end;

procedure TAtlasArchitectureFrameTests.ComparisonTabAndMapChanges;
var
  Model: TAtlasArchitectureModel;
  Enabled, Cleared: Boolean;
  Text: string;
  Index: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, Model, Enabled));
  FFrame.SetModel(Model);
  Text := Joined(FFrame.ComparisonText);
  Assert.IsTrue(Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureChangeNewCycles, [1]), Text) > 0, Text);
  Assert.IsTrue(Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureChangeRemovedUnits, [1]), Text) > 0, Text);
  Assert.IsTrue(Pos('App.Old', Text) > 0);
  // Leere Abschnitte stehen nicht da.
  Assert.AreEqual(0, Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureChangeRemovedCycles, [0]), Text));
  Assert.IsTrue(Pos('stand.json', FFrame.ComparisonInfo.Caption) > 0, FFrame.ComparisonInfo.Caption);
  Assert.IsTrue(Pos('newCycle', FFrame.ComparisonInfo.Caption) > 0, 'verletzte Art aus failOn');
  Assert.IsTrue(Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureStatusComparison, [Model.Comparison.Count]),
    FFrame.StatusLabel.Caption) > 0);
  Assert.IsTrue(FFrame.ChangesCheck.Enabled);
  Assert.IsTrue(FFrame.Map.ShowChanges);
  Assert.IsTrue(FFrame.ClearCompareButton.Enabled);
  // Doppelklick auf einen Eintrag öffnet die Unit.
  for Index := 0 to FFrame.ComparisonTree.Items.Count - 1 do
    if FFrame.ComparisonTree.Items[Index].Data <> nil then
    begin
      FFrame.ComparisonTree.Selected := FFrame.ComparisonTree.Items[Index];
      Break;
    end;
  FFrame.ComparisonTree.OnDblClick(FFrame.ComparisonTree);
  Assert.IsTrue(EndsStr('.pas', FOpened), FOpened);
  // Karte ohne Änderungen.
  FFrame.ChangesCheck.Checked := False;
  Assert.IsFalse(FFrame.Map.ShowChanges);
  FFrame.ChangesCheck.Checked := True;
  // Filter wirkt auch hier.
  FFrame.Filter.Text := 'old';
  Text := Joined(FFrame.ComparisonText);
  Assert.IsTrue(Pos('App.Old', Text) > 0);
  Assert.AreEqual(0, Pos('App.Data.Cache', Text));
  FFrame.Filter.Text := '';
  Cleared := False;
  FFrame.OnClearComparison :=
    procedure
    begin
      Cleared := True;
    end;
  FFrame.ClearCompareButton.Click;
  Assert.IsTrue(Cleared);
  FFrame.OnClearComparison := nil;
end;

procedure TAtlasArchitectureFrameTests.WithoutComparisonShowsHint;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Answer: string;
begin
  Assert.AreEqual(0, Integer(Length(FFrame.ComparisonText)));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoComparison), FFrame.ComparisonInfo.Caption);
  Assert.IsFalse(FFrame.ChangesCheck.Enabled);
  Assert.IsFalse(FFrame.ClearCompareButton.Enabled);
  Assert.IsTrue(FFrame.SaveStateButton.Enabled);
  Assert.IsTrue(FFrame.CompareButton.Enabled);
  // Unlesbarer Stand: Meldung im Reiter und in der Statuszeile, die Übersicht bleibt.
  Answer := SampleAnswer;
  Answer := Copy(Answer, 1, Length(Answer) - 1) + ',"comparisonError":"Architekturstand ist beschädigt"}';
  Assert.IsTrue(TAtlasArchitectureModel.Parse(Answer, Model, Enabled));
  FFrame.SetModel(Model);
  Assert.IsTrue(Pos('beschädigt', FFrame.ComparisonInfo.Caption) > 0);
  Assert.IsTrue(Pos('beschädigt', FFrame.StatusLabel.Caption) > 0);
  Assert.IsTrue(FFrame.ClearCompareButton.Enabled);
  Assert.AreEqual(3, Integer(Length(FFrame.CentralText)));
end;

procedure TAtlasArchitectureFrameTests.RouteFromSymbolPath;
var
  Units, Edges: TArray<Integer>;
  Cache: Integer;
begin
  // Fester Weg aus „Weg zwischen Symbolen“ (#1117): Units und Kanten markiert, Zeile unter der Karte.
  Assert.IsTrue(FFrame.Model.RouteOf(TArray<string>.Create('App.Main', 'App.Data', 'App.Data.Cache'), Units, Edges));
  FFrame.Map.ShowRoute(Units, Edges);
  Assert.IsTrue(FFrame.Map.PathFound);
  Assert.AreEqual(4, Integer(Length(FFrame.Map.Route)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureRoute, [4,
    'App.Main → App.Data → App.Data.Db → App.Data.Cache']), FFrame.InfoLabel.Caption);
  // Er bleibt ohne implementation-uses stehen und blendet ein ausgeblendetes Teilsystem wieder ein.
  FFrame.ImplementationCheck.Checked := False;
  Assert.IsTrue(FFrame.Map.PathFound);
  FFrame.ImplementationCheck.Checked := True;
  Cache := FFrame.Model.IndexOf('App.Data.Cache');
  FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem] := False;
  FFrame.Map.ShowRoute(Units, Edges);
  Assert.IsTrue(FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem]);
  // Umschalt+Klick (ShowPath) und Esc heben ihn auf.
  FFrame.Map.ShowPath(Units[0], Units[1]);
  Assert.AreEqual(0, Integer(Length(FFrame.Map.Route)));
  FFrame.Map.ShowRoute(Units, Edges);
  FFrame.Map.ClearPath;
  Assert.AreEqual(0, Integer(Length(FFrame.Map.Route)));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureMapHint), FFrame.InfoLabel.Caption);
  // Ungültige Nummern: kein Weg.
  FFrame.Map.ShowRoute(TArray<Integer>.Create(999), nil);
  Assert.AreEqual(-1, FFrame.Map.PathFrom);
end;

procedure TAtlasArchitectureFrameTests.ResolutionSliderReportsOnRelease;
var
  mReported: Double;
  mCount: Integer;
begin
  mReported := 0;
  mCount := 0;
  FFrame.OnResolutionChanged :=
    procedure(AValue: Double)
    begin
      mReported := AValue;
      Inc(mCount);
    end;
  Assert.AreEqual(Double(1), FFrame.ResolutionValue, 1E-9);
  // Mit dem Wert der Karte steht die Zahl der Teilsysteme daneben.
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureResolutionInfo,
    [TAtlasArchResolution.Text(1, FormatSettings), FFrame.Model.SubsystemCount]), FFrame.ResolutionInfo.Caption);
  // Ziehen zeigt nur den Wert, meldet aber noch nichts.
  FFrame.ResolutionSlider.MoveTo(75, False);
  Assert.AreEqual(0, mCount);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureResolutionValue,
    [TAtlasArchResolution.Text(2.24, FormatSettings)]), FFrame.ResolutionInfo.Caption);
  // Loslassen meldet den Wert einmal.
  FFrame.ResolutionSlider.MoveTo(75, True);
  Assert.AreEqual(1, mCount);
  Assert.AreEqual(Double(2.24), mReported, 1E-9);
  FFrame.ResolutionSlider.MoveTo(75, True);
  Assert.AreEqual(1, mCount, 'gleiche Stellung meldet nicht erneut');
  // Doppelklick setzt 1,0.
  FFrame.ResolutionSlider.Reset;
  Assert.AreEqual(2, mCount);
  Assert.AreEqual(Double(1), mReported, 1E-9);
  // Setzen aus den Einstellungen meldet nichts.
  FFrame.ResolutionValue := 0.5;
  Assert.AreEqual(2, mCount);
  Assert.AreEqual(Double(0.5), FFrame.ResolutionValue, 0.01);
end;

procedure TAtlasArchitectureFrameTests.ResolutionSliderCanBeHidden;
begin
  Assert.IsTrue(FFrame.ShowResolution);
  FFrame.ShowResolution := False;
  Assert.IsFalse(FFrame.ResolutionSlider.Visible);
  Assert.IsFalse(FFrame.ResolutionInfo.Visible);
  FFrame.ShowResolution := True;
  Assert.IsTrue(FFrame.ResolutionSlider.Visible);
end;

procedure TAtlasArchitectureFrameTests.ComparisonNamesDifferentResolution;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mNote: string;
begin
  mNote := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureComparisonResolution,
    [TAtlasArchResolution.Text(1, FormatSettings), TAtlasArchResolution.Text(2, FormatSettings)]);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleResolutionAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsTrue(ContainsStr(FFrame.ComparisonInfo.Caption, mNote), FFrame.ComparisonInfo.Caption);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsFalse(ContainsStr(FFrame.ComparisonInfo.Caption, mNote), FFrame.ComparisonInfo.Caption);
end;

procedure TAtlasArchitectureFrameTests.SplitSubsystemsGroupedInMenuAndTree;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mLast: Integer;
  mFirst, mLine: string;
  mLines: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleSplitAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  mLast := High(mModel.Subsystems);
  // Menü: Überschrift „App (nachgeteilt in 2 Teile)“, darunter die beiden Teile eingerückt.
  FFrame.FillSubsystemsMenu;
  Assert.AreEqual(Integer(Length(mModel.Subsystems)) + 3, FFrame.SubsystemsMenu.Items.Count);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureSubsystemFamily, ['App', 2]),
    FFrame.SubsystemsMenu.Items[0].Caption);
  Assert.IsFalse(FFrame.SubsystemsMenu.Items[0].Enabled);
  Assert.AreEqual(0, FFrame.SubsystemsMenu.Items[1].Tag);
  Assert.AreEqual(mLast, FFrame.SubsystemsMenu.Items[2].Tag);
  Assert.IsTrue(StartsStr('      ', FFrame.SubsystemsMenu.Items[2].Caption));
  Assert.AreEqual(1, FFrame.SubsystemsMenu.Items[3].Tag);
  FFrame.SubsystemsMenu.Items[2].Click;
  Assert.IsFalse(FFrame.Map.SubsystemVisible[mLast]);
  // Reiter Teilsysteme: „… · Teil von App“, die Teile beieinander (erst das erste Teil mit seinen Units, dann das
  // letzte Teilsystem).
  mFirst := FFrame.SubsystemText[0];
  Assert.IsTrue(EndsStr(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureSubsystemPart, ['', 'App']), mFirst), mFirst);
  mLines := nil;
  for mLine in FFrame.SubsystemText do
    if not StartsStr(' ', mLine) then
      mLines := mLines + [mLine];
  Assert.IsTrue(StartsStr(mModel.Subsystems[mLast].Name + ' ', mLines[1]), mLines[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureFrameTests);

end.
