unit Atlas.UI.Architecture.Frame.Tests;

// Fenster „Atlas-Architektur“ (#1118), Fensterinhalt: Tabellen und Bäume aus
// den Daten des Servers, Sortieren per Spaltenklick, Filter, Öffnen von Unit
// und uses-Eintrag, Hinweise, Umfang und Bibliotheks-Units, Treffer der
// Karte; Reiter „Vergleich“ und Änderungen auf der Karte (#1121); Regler
// „Feinheit“ mit Wert und Zahl der Teilsysteme (#1366); Zuordnung im
// Steckbrief, knappe Units im Baum und Erklärung (#1368).

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Architecture.Frame;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
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
    [Test]
    procedure FoundationInMenuAndTree;
    [Test]
    procedure AssignmentInProfileTreeAndExplanation;
    [Test]
    procedure WithoutAssignmentNothingExtra;
    /// <summary>Angleichung (#1367): Statuszeile und „Teilsysteme neu benennen“ im Menü.</summary>
    [Test]
    procedure AlignedStatusAndRename;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.UI.Analysis.Strings,
  Atlas.Core.Architecture.MapState,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Model.Tests,
  Atlas.UI.Architecture.Assignment;

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
  // Erste Anzeige der Scrollbox mit Erklärung legt einmalige VCL-Puffer an.
  Setup;
  try
    AssignmentInProfileTreeAndExplanation;
  finally
    TearDown;
  end;
end;

procedure TAtlasArchitectureFrameTests.SetUp;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
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
  TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled);
  FFrame.SetModel(mModel);
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
  Assert.AreEqual(3, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Central))));
  Assert.IsTrue(Length(FFrame.ListText(TAtlasArchFrameList.Subsystems)) >= 7, 'Teilsysteme und ihre sechs Units');
  // Zyklus mit Weg und seinen beiden uses-Einträgen.
  Assert.AreEqual(3, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Cycles))));
  Assert.IsTrue(StartsStr(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleImplementation),
    FFrame.ListText(TAtlasArchFrameList.Cycles)[0]));
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.ListText(TAtlasArchFrameList.Cycles))) > 0);
  Assert.AreEqual(1, Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatus,
    [6, Length(FFrame.Model.Subsystems), 1,
    Length(FFrame.Model.CrossLinks), Integer(FFrame.Model.Generation and $7FFFFFFF), FFrame.Model.DurationMs]),
    FFrame.Parts.Status.Caption));
  // Aktive Ausschlüsse stehen in der Statuszeile.
  Assert.IsTrue(Pos('Tests/**', FFrame.Parts.Status.Caption) > 0);
  Assert.IsTrue(FFrame.Parts.Save.Enabled);
end;

procedure TAtlasArchitectureFrameTests.SortsByColumnClick;
var
  mLines: TArray<string>;
begin
  // Vorgabe: gesamt abhängig, die größten zuerst.
  mLines := FFrame.ListText(TAtlasArchFrameList.Central);
  Assert.IsTrue(StrToInt(mLines[0].Split([#9])[3]) >= StrToInt(mLines[1].Split([#9])[3]));
  FFrame.Parts.Central.OnColumnClick(FFrame.Parts.Central, FFrame.Parts.Central.Columns[0]);
  Assert.AreEqual<TAtlasArchColumn>(TAtlasArchColumn.Name, FFrame.Sort.Column);
  Assert.IsFalse(FFrame.Sort.Descending);
  mLines := FFrame.ListText(TAtlasArchFrameList.Central);
  Assert.IsTrue(CompareText(mLines[0].Split([#9])[0], mLines[1].Split([#9])[0]) < 0);
  FFrame.Parts.Central.OnColumnClick(FFrame.Parts.Central, FFrame.Parts.Central.Columns[0]);
  Assert.IsTrue(FFrame.Sort.Descending);
  mLines := FFrame.ListText(TAtlasArchFrameList.Central);
  Assert.IsTrue(CompareText(mLines[0].Split([#9])[0], mLines[1].Split([#9])[0]) > 0);
end;

procedure TAtlasArchitectureFrameTests.CostRankingSortsByTotal;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  // Teuerste Units (#554): auch nach anderer Sortierung und auf anderem Reiter wieder „gesamt abhängig“ absteigend.
  FFrame.Parts.Central.OnColumnClick(FFrame.Parts.Central, FFrame.Parts.Central.Columns[0]);
  FFrame.Parts.Pages.ActivePageIndex := 0;
  FFrame.ShowCostRanking;
  Assert.AreEqual<TAtlasArchColumn>(TAtlasArchColumn.Total, FFrame.Sort.Column);
  Assert.IsTrue(FFrame.Sort.Descending);
  Assert.AreSame(FFrame.Parts.Central.Parent, FFrame.Parts.Pages.ActivePage, 'Reiter „Zentrale Units“');
  mLines := FFrame.ListText(TAtlasArchFrameList.Central);
  for mIndex := 1 to High(mLines) do
  begin
    Assert.IsTrue(StrToInt(mLines[mIndex - 1].Split([#9])[3]) >= StrToInt(mLines[mIndex].Split([#9])[3]));
  end;
end;

procedure TAtlasArchitectureFrameTests.FilterNarrowsEverything;
begin
  FFrame.Parts.Filter.Text := 'cache';
  Assert.AreEqual('cache', FFrame.Map.State.Filter);
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.ListText(TAtlasArchFrameList.Subsystems))) > 0);
  Assert.AreEqual(0, Pos('App.Ui.Form', Joined(FFrame.ListText(TAtlasArchFrameList.Subsystems))));
  Assert.AreEqual(3, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Cycles))), 'der Zyklus enthält App.Data.Cache');
  FFrame.Parts.Filter.Text := 'ui form';
  Assert.AreEqual(0, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Cycles))));
  FFrame.Parts.Filter.Text := '';
end;

procedure TAtlasArchitectureFrameTests.OpensUnitAndUsesEntry;
var
  mUnit_: Integer;
begin
  mUnit_ := FFrame.Model.IndexOf('App.Data.Db');
  FFrame.OpenUnit(mUnit_);
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
  mScope: string;
  mLibrary_: Boolean;
begin
  FFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureLoading), True);
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureLoading), FFrame.Parts.Status.Caption);
  Assert.IsTrue(FFrame.HasModel, 'bisherige Daten bleiben');
  FFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoProject), False);
  Assert.IsFalse(FFrame.HasModel);
  Assert.AreEqual(0, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Central))));
  Assert.IsFalse(FFrame.Parts.Save.Enabled);
  mScope := '';
  FFrame.OnScopeChanged :=
    procedure(AScope: string)
    begin
      mScope := AScope;
    end;
  FFrame.ScopeValue := 'project';
  Assert.AreEqual('', mScope, 'Setzen von außen meldet nichts');
  Assert.AreEqual('project', FFrame.ScopeValue);
  mLibrary_ := False;
  FFrame.OnLibraryChanged :=
    procedure(AValue: Boolean)
    begin
      mLibrary_ := AValue;
    end;
  FFrame.IncludeLibrary := True;
  Assert.IsFalse(mLibrary_, 'Setzen von außen meldet nichts');
  FFrame.Parts.LibraryUnits.Checked := False;
  Assert.IsFalse(FFrame.IncludeLibrary);
  FFrame.OnScopeChanged := nil;
  FFrame.OnLibraryChanged := nil;
end;

procedure TAtlasArchitectureFrameTests.MapSelectsUnitUnderMouse;
var
  mUnit_: Integer;
  mFitted: Double;
begin
  FFrame.Map.FitView;
  mFitted := FFrame.Map.View.Scale;
  mUnit_ := FFrame.Model.IndexOf('App.Main');
  Assert.AreEqual(mUnit_, FFrame.Map.View.UnitAt(FFrame.Map.State.Model,
    FFrame.Map.View.ScreenX(FFrame.Model.Units[mUnit_].X), FFrame.Map.View.ScreenY(FFrame.Model.Units[mUnit_].Y)));
  FFrame.Map.SelectUnit(mUnit_, True);
  Assert.AreEqual(mUnit_, FFrame.Map.State.Selected);
  Assert.AreEqual(Double(FFrame.Map.ClientWidth / 2), FFrame.Map.View.ScreenX(FFrame.Model.Units[mUnit_].X), 0.5);
  FFrame.Map.SelectUnit(99, False);
  Assert.AreEqual(-1, FFrame.Map.State.Selected);
  // „Namen“ blendet die Beschriftungen aus, „Einpassen“ holt die Karte zurück.
  FFrame.Parts.Names.Checked := False;
  Assert.IsFalse(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowNames));
  FFrame.Parts.Names.Checked := True;
  Assert.IsTrue(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowNames));
  FFrame.Map.ZoomBy(4);
  FFrame.Parts.Fit.Click;
  Assert.AreEqual(mFitted, FFrame.Map.View.Scale, 0.0001, 'nach dem Einpassen wieder der Maßstab vom Anfang');
end;

procedure TAtlasArchitectureFrameTests.PathCyclesAndSubsystems;
var
  mMain, mCache, mDb: Integer;
begin
  mMain := FFrame.Model.IndexOf('App.Main');
  mCache := FFrame.Model.IndexOf('App.Data.Cache');
  mDb := FFrame.Model.IndexOf('App.Data.Db');
  // Weg wie in der HTML-Karte; die Zeile unter der Karte nennt ihn.
  Assert.IsTrue(FFrame.Map.State.ShowPath(mMain, mCache));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitecturePath, [3,
    'App.Main → App.Data → App.Data.Db → App.Data.Cache']), FFrame.Parts.Info.Caption);
  Assert.IsFalse(FFrame.Map.State.ShowPath(mCache, mMain));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureNoPath, ['App.Data.Cache', 'App.Main']),
    FFrame.Parts.Info.Caption);
  // Ohne implementation-uses gibt es Cache → Db nicht mehr; der Weg wird neu gesucht.
  Assert.IsTrue(FFrame.Map.State.ShowPath(mCache, mDb));
  FFrame.Parts.ImplementationUses.Checked := False;
  Assert.IsFalse(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowImplementation));
  Assert.IsFalse(FFrame.Map.State.Path.Found);
  FFrame.Parts.ImplementationUses.Checked := True;
  Assert.IsTrue(FFrame.Map.State.Path.Found);
  // Esc hebt den Weg auf, danach wieder der Hinweis.
  FFrame.Map.State.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.State.Path.From);
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint), FFrame.Parts.Info.Caption);
  FFrame.Map.State.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.State.Path.To_, 'zweimal aufheben schadet nicht');
  // Zyklen markieren.
  Assert.IsFalse(FFrame.Map.State.Has(TAtlasArchMapFlag.MarkCycles));
  FFrame.Parts.MarkCycles.Checked := True;
  Assert.IsTrue(FFrame.Map.State.Has(TAtlasArchMapFlag.MarkCycles));
  // Teilsysteme aus- und einblenden über das Menü.
  FFrame.FillSubsystemsMenu;
  Assert.AreEqual(Integer(Length(FFrame.Model.Subsystems)) + 2, FFrame.Parts.SubsystemsMenu.Items.Count);
  FFrame.Parts.SubsystemsMenu.Items[FFrame.Model.Units[mCache].Subsystem].Click;
  Assert.IsFalse(FFrame.Map.State.SubsystemVisible[FFrame.Model.Units[mCache].Subsystem]);
  Assert.IsFalse(FFrame.Parts.SubsystemsMenu.Items[FFrame.Model.Units[mCache].Subsystem].Checked);
  Assert.IsFalse(FFrame.Map.State.ShowPath(mMain, mCache), 'Units ausgeblendeter Teilsysteme sind kein Ziel');
  FFrame.Parts.SubsystemsMenu.Items[FFrame.Parts.SubsystemsMenu.Items.Count - 1].Click;
  Assert.IsTrue(FFrame.Map.State.SubsystemVisible[FFrame.Model.Units[mCache].Subsystem]);
  Assert.IsTrue(FFrame.Map.State.Path.Found, 'nach dem Einblenden wird der Weg neu gesucht');
  FFrame.Map.State.ClearPath;
end;

procedure TAtlasArchitectureFrameTests.ComparisonTabAndMapChanges;
var
  mModel: TAtlasArchitectureModel;
  mEnabled, mCleared: Boolean;
  mText: string;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  mText := Joined(FFrame.ListText(TAtlasArchFrameList.Comparison));
  Assert.IsTrue(Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureChangeNewCycles, [1]), mText) > 0,
    mText);
  Assert.IsTrue(Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureChangeRemovedUnits, [1]), mText) > 0,
    mText);
  Assert.IsTrue(Pos('App.Old', mText) > 0);
  // Leere Abschnitte stehen nicht da.
  Assert.AreEqual(0, Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureChangeRemovedCycles, [0]), mText));
  Assert.IsTrue(Pos('stand.json', FFrame.Parts.CompareInfo.Caption) > 0, FFrame.Parts.CompareInfo.Caption);
  Assert.IsTrue(Pos('newCycle', FFrame.Parts.CompareInfo.Caption) > 0, 'verletzte Art aus failOn');
  Assert.IsTrue(Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusComparison,
    [mModel.Comparison.Count]),
    FFrame.Parts.Status.Caption) > 0);
  Assert.IsTrue(FFrame.Parts.Changes.Enabled);
  Assert.IsTrue(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowChanges));
  Assert.IsTrue(FFrame.Parts.ClearCompare.Enabled);
  // Doppelklick auf einen Eintrag öffnet die Unit.
  for mIndex := 0 to FFrame.Parts.Comparison.Items.Count - 1 do
  begin
    if FFrame.Parts.Comparison.Items[mIndex].Data <> nil then
    begin
      FFrame.Parts.Comparison.Selected := FFrame.Parts.Comparison.Items[mIndex];
      Break;
    end;
  end;
  FFrame.Parts.Comparison.OnDblClick(FFrame.Parts.Comparison);
  Assert.IsTrue(EndsStr('.pas', FOpened), FOpened);
  // Karte ohne Änderungen.
  FFrame.Parts.Changes.Checked := False;
  Assert.IsFalse(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowChanges));
  FFrame.Parts.Changes.Checked := True;
  // Filter wirkt auch hier.
  FFrame.Parts.Filter.Text := 'old';
  mText := Joined(FFrame.ListText(TAtlasArchFrameList.Comparison));
  Assert.IsTrue(Pos('App.Old', mText) > 0);
  Assert.AreEqual(0, Pos('App.Data.Cache', mText));
  FFrame.Parts.Filter.Text := '';
  mCleared := False;
  FFrame.OnClearComparison :=
    procedure
    begin
      mCleared := True;
    end;
  FFrame.Parts.ClearCompare.Click;
  Assert.IsTrue(mCleared);
  FFrame.OnClearComparison := nil;
end;

procedure TAtlasArchitectureFrameTests.WithoutComparisonShowsHint;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mAnswer: string;
begin
  Assert.AreEqual(0, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Comparison))));
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoComparison),
    FFrame.Parts.CompareInfo.Caption);
  Assert.IsFalse(FFrame.Parts.Changes.Enabled);
  Assert.IsFalse(FFrame.Parts.ClearCompare.Enabled);
  Assert.IsTrue(FFrame.Parts.SaveState.Enabled);
  Assert.IsTrue(FFrame.Parts.Compare.Enabled);
  // Unlesbarer Stand: Meldung im Reiter und in der Statuszeile, die Übersicht bleibt.
  mAnswer := SampleAnswer;
  mAnswer := Copy(mAnswer, 1, Length(mAnswer) - 1) + ',"comparisonError":"Architekturstand ist beschädigt"}';
  Assert.IsTrue(TAtlasArchitectureModel.Parse(mAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsTrue(Pos('beschädigt', FFrame.Parts.CompareInfo.Caption) > 0);
  Assert.IsTrue(Pos('beschädigt', FFrame.Parts.Status.Caption) > 0);
  Assert.IsTrue(FFrame.Parts.ClearCompare.Enabled);
  Assert.AreEqual(3, Integer(Length(FFrame.ListText(TAtlasArchFrameList.Central))));
end;

procedure TAtlasArchitectureFrameTests.RouteFromSymbolPath;
var
  mUnits, mEdges: TArray<Integer>;
  mCache: Integer;
begin
  // Fester Weg aus „Weg zwischen Symbolen“ (#1117): Units und Kanten markiert, Zeile unter der Karte.
  Assert.IsTrue(FFrame.Model.RouteOf(TArray<string>.Create('App.Main', 'App.Data', 'App.Data.Cache'), mUnits, mEdges));
  FFrame.Map.State.ShowRoute(mUnits, mEdges);
  Assert.IsTrue(FFrame.Map.State.Path.Found);
  Assert.AreEqual(4, Integer(Length(FFrame.Map.State.Path.Route)));
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureRoute, [4,
    'App.Main → App.Data → App.Data.Db → App.Data.Cache']), FFrame.Parts.Info.Caption);
  // Er bleibt ohne implementation-uses stehen und blendet ein ausgeblendetes Teilsystem wieder ein.
  FFrame.Parts.ImplementationUses.Checked := False;
  Assert.IsTrue(FFrame.Map.State.Path.Found);
  FFrame.Parts.ImplementationUses.Checked := True;
  mCache := FFrame.Model.IndexOf('App.Data.Cache');
  FFrame.Map.State.SubsystemVisible[FFrame.Model.Units[mCache].Subsystem] := False;
  FFrame.Map.State.ShowRoute(mUnits, mEdges);
  Assert.IsTrue(FFrame.Map.State.SubsystemVisible[FFrame.Model.Units[mCache].Subsystem]);
  // Umschalt+Klick (ShowPath) und Esc heben ihn auf.
  FFrame.Map.State.ShowPath(mUnits[0], mUnits[1]);
  Assert.AreEqual(0, Integer(Length(FFrame.Map.State.Path.Route)));
  FFrame.Map.State.ShowRoute(mUnits, mEdges);
  FFrame.Map.State.ClearPath;
  Assert.AreEqual(0, Integer(Length(FFrame.Map.State.Path.Route)));
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureMapHint), FFrame.Parts.Info.Caption);
  // Ungültige Nummern: kein Weg.
  FFrame.Map.State.ShowRoute(TArray<Integer>.Create(999), nil);
  Assert.AreEqual(-1, FFrame.Map.State.Path.From);
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
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureResolutionInfo,
    [TAtlasArchResolution.Text(1, FormatSettings), FFrame.Model.SubsystemCount]), FFrame.Parts.ResolutionInfo.Caption);
  // Ziehen zeigt nur den Wert, meldet aber noch nichts.
  FFrame.Parts.Resolution.MoveTo(75, False);
  Assert.AreEqual(0, mCount);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureResolutionValue,
    [TAtlasArchResolution.Text(2.24, FormatSettings)]), FFrame.Parts.ResolutionInfo.Caption);
  // Loslassen meldet den Wert einmal.
  FFrame.Parts.Resolution.MoveTo(75, True);
  Assert.AreEqual(1, mCount);
  Assert.AreEqual(Double(2.24), mReported, 1E-9);
  FFrame.Parts.Resolution.MoveTo(75, True);
  Assert.AreEqual(1, mCount, 'gleiche Stellung meldet nicht erneut');
  // Doppelklick setzt 1,0.
  FFrame.Parts.Resolution.Reset;
  Assert.AreEqual(2, mCount);
  Assert.AreEqual(Double(1), mReported, 1E-9);
  // Setzen aus den Einstellungen meldet nichts.
  FFrame.ResolutionValue := 0.5;
  Assert.AreEqual(2, mCount);
  // Die Stellung rastet auf Schritte: 0,5 wird zum nächsten Schritt (0,49).
  Assert.AreEqual(Double(0.5), FFrame.ResolutionValue, 0.02);
end;

procedure TAtlasArchitectureFrameTests.ResolutionSliderCanBeHidden;
begin
  Assert.IsTrue(FFrame.ShowResolution);
  FFrame.ShowResolution := False;
  Assert.IsFalse(FFrame.Parts.Resolution.Visible);
  Assert.IsFalse(FFrame.Parts.ResolutionInfo.Visible);
  FFrame.ShowResolution := True;
  Assert.IsTrue(FFrame.Parts.Resolution.Visible);
end;

procedure TAtlasArchitectureFrameTests.ComparisonNamesDifferentResolution;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mNote: string;
begin
  mNote := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonResolution,
    [TAtlasArchResolution.Text(1, FormatSettings), TAtlasArchResolution.Text(2, FormatSettings)]);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleResolutionAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsTrue(ContainsStr(FFrame.Parts.CompareInfo.Caption, mNote), FFrame.Parts.CompareInfo.Caption);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsFalse(ContainsStr(FFrame.Parts.CompareInfo.Caption, mNote), FFrame.Parts.CompareInfo.Caption);
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
  Assert.AreEqual(Integer(Length(mModel.Subsystems)) + 3, FFrame.Parts.SubsystemsMenu.Items.Count);
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemFamily, ['App', 2]),
    FFrame.Parts.SubsystemsMenu.Items[0].Caption);
  Assert.IsFalse(FFrame.Parts.SubsystemsMenu.Items[0].Enabled);
  Assert.AreEqual(0, Integer(FFrame.Parts.SubsystemsMenu.Items[1].Tag));
  Assert.AreEqual(mLast, Integer(FFrame.Parts.SubsystemsMenu.Items[2].Tag));
  Assert.IsTrue(StartsStr('      ', FFrame.Parts.SubsystemsMenu.Items[2].Caption));
  Assert.AreEqual(1, Integer(FFrame.Parts.SubsystemsMenu.Items[3].Tag));
  FFrame.Parts.SubsystemsMenu.Items[2].Click;
  Assert.IsFalse(FFrame.Map.State.SubsystemVisible[mLast]);
  // Reiter Teilsysteme: „… · Teil von App“, die Teile beieinander (erst das erste Teil mit seinen Units, dann das
  // letzte Teilsystem).
  mFirst := FFrame.ListText(TAtlasArchFrameList.Subsystems)[0];
  Assert.IsTrue(EndsStr(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemPart, ['', 'App']),
    mFirst), mFirst);
  mLines := nil;
  for mLine in FFrame.ListText(TAtlasArchFrameList.Subsystems) do
  begin
    if not StartsStr(' ', mLine) then
    begin
      mLines := mLines + [mLine];
    end;
  end;
  Assert.IsTrue(StartsStr(mModel.Subsystems[mLast].Name + ' ', mLines[1]), mLines[1]);
end;

procedure TAtlasArchitectureFrameTests.FoundationInMenuAndTree;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mToggle: TMenuItem;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleFoundationAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  // Reiter: „Fundament (n Units, übergreifende Fundamente)“, darunter zuerst die Regel.
  Assert.AreEqual(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureFoundationLine, ['Fundament',
    Length(mModel.Subsystems[0].Units)]), FFrame.ListText(TAtlasArchFrameList.Subsystems)[0]);
  Assert.AreEqual('  ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationRule),
    FFrame.ListText(TAtlasArchFrameList.Subsystems)[1]);
  // Menü: Schalter „Kanten zum Fundament“ vor „Alle einblenden“.
  FFrame.FillSubsystemsMenu;
  mToggle := nil;
  for mIndex := 0 to FFrame.Parts.SubsystemsMenu.Items.Count - 1 do
  begin
    if FFrame.Parts.SubsystemsMenu.Items[mIndex].Caption = TAtlasAnalysisStrings.Text(
      TAtlasAnalysisTextId.ArchitectureFoundationEdges) then
    begin
      mToggle := FFrame.Parts.SubsystemsMenu.Items[mIndex];
    end;
  end;
  Assert.IsNotNull(mToggle);
  Assert.IsTrue(mToggle.Checked);
  mToggle.Click;
  Assert.IsFalse(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowFoundationEdges));
  Assert.IsFalse(mToggle.Checked);
  mToggle.Click;
  Assert.IsTrue(FFrame.Map.State.Has(TAtlasArchMapFlag.ShowFoundationEdges));
end;

procedure TAtlasArchitectureFrameTests.AssignmentInProfileTreeAndExplanation;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mMid: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAssignmentAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  mMid := FFrame.Model.IndexOf('Z.Own.Mid');
  // Reiter „Teilsysteme“: knappe Unit markiert, Fragezeichen mit Erklärung.
  Assert.Contains(Joined(FFrame.ListText(TAtlasArchFrameList.Subsystems)),
    'Z.Own.Mid — ' + TAtlasArchitectureAssignment.CloseMark(FFrame.Model, mMid));
  Assert.IsTrue(FFrame.Parts.ExplainButton.Parent.Visible);
  FFrame.Parts.ExplainButton.Click;
  Assert.AreEqual(TAtlasArchitectureAssignment.Explanation(FFrame.Model), FFrame.Parts.Explanation.Caption);
  FFrame.Parts.ExplainButton.Click;
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplainHint),
    FFrame.Parts.Explanation.Caption);
  // Steckbrief unter der Karte, sobald eine Unit gewählt ist.
  Assert.IsFalse(FFrame.Parts.AssignmentBox.Visible);
  FFrame.Map.SelectUnit(mMid, False);
  FFrame.Map.OnSelect(mMid);
  Assert.IsTrue(FFrame.Parts.AssignmentBox.Visible);
  Assert.IsTrue(FFrame.Parts.AssignmentBox.Height > 0);
  // Links neben dem Diagramm, nicht darunter: Bei vielen Teilsystemen verdrängte die Liste sonst das Diagramm.
  Assert.AreEqual(Ord(alLeft), Ord(FFrame.Parts.AssignmentBox.Align));
  FFrame.Parts.AssignmentBox.Repaint;
  FFrame.Map.SelectUnit(-1, False);
  FFrame.Map.OnSelect(-1);
  Assert.IsFalse(FFrame.Parts.AssignmentBox.Visible);
end;

procedure TAtlasArchitectureFrameTests.WithoutAssignmentNothingExtra;
begin
  // SampleAnswer kommt ohne architecture.explainAssignment.
  Assert.IsFalse(FFrame.Parts.ExplainButton.Parent.Visible);
  Assert.AreEqual(0, Pos(' — knapp', Joined(FFrame.ListText(TAtlasArchFrameList.Subsystems))));
  FFrame.Map.SelectUnit(0, False);
  FFrame.Map.OnSelect(0);
  Assert.IsFalse(FFrame.Parts.AssignmentBox.Visible);
end;

procedure TAtlasArchitectureFrameTests.AlignedStatusAndRename;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mCount, mRenamed: Integer;
begin
  // Ohne Angleichung kein Zusatz.
  Assert.AreEqual(0, Pos('angeglichen', FFrame.Parts.Status.Caption));
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAlignedAnswer, mModel, mEnabled));
  FFrame.SetModel(mModel);
  Assert.IsTrue(Pos(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusAlignedBaseline,
    ['2026-10-29 14:23']),
    FFrame.Parts.Status.Caption) > 0, FFrame.Parts.Status.Caption);
  mRenamed := 0;
  FFrame.OnRenameSubsystems :=
    procedure
    begin
      Inc(mRenamed);
    end;
  FFrame.FillSubsystemsMenu;
  mCount := FFrame.Parts.SubsystemsMenu.Items.Count;
  Assert.AreEqual(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRenameSubsystems),
    FFrame.Parts.SubsystemsMenu.Items[mCount - 1].Caption);
  FFrame.Parts.SubsystemsMenu.Items[mCount - 1].Click;
  Assert.AreEqual(1, mRenamed);
  FFrame.OnRenameSubsystems := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureFrameTests);

end.
