unit Atlas.Core.Architecture.Model.Tests;

// Fenster „Atlas-Architektur“ (#1118), Kern: Antwort des Servers lesen
// (dieselben Daten wie TArchitectureReport.Json), Sortieren, Filter, Pfade,
// Farben und Umrechnung der Karte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasArchitectureModelTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure DisabledAndBrokenAnswers;
    [Test]
    procedure SortsStableAndFilters;
    [Test]
    procedure FullPathAndCyclePath;
    [Test]
    procedure PaletteAndDarkness;
    [Test]
    procedure ViewFitsZoomsAndHits;
    [Test]
    procedure CommandArguments;
    [Test]
    procedure ShortestPathOverUses;
  end;

/// <summary>Antwort von atlas.architecture zu einem kleinen Projekt mit Zyklus (für Kern- und UI-Tests).</summary>
function SampleAnswer: string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Core.Architecture.Model;

function SampleAnswer: string;
var
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
  Overview: TArchitectureOverview;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Main', ['App.Data', 'App.Ui.Form'], nil));
  Index.AddUnit(UsesUnit('App.Data', ['App.Data.Db'], nil));
  Index.AddUnit(UsesUnit('App.Data.Db', ['App.Data.Cache'], nil));
  Index.AddUnit(UsesUnit('App.Data.Cache', nil, ['App.Data.Db']));
  Index.AddUnit(UsesUnit('App.Ui.Form', ['App.Ui.Grid'], nil));
  Index.AddUnit(UsesUnit('App.Ui.Grid', ['App.Data'], nil));
  Service := TArchitectureService.Create(Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
  try
    Request := Default(TArchitectureRequest);
    Request.Title := 'App';
    Request.Root := 'C:\Projekt';
    Request.Scope := 'project';
    Request.CentralUnits := 3;
    Request.Exclude := ['Tests/**'];
    Overview := Service.Overview(Request);
    Result := '{"enabled":true,"root":"C:\\Projekt","format":"json","data":' +
      TArchitectureReport.Json(Overview, TArchitectureLayouter.Compute(Overview)) + '}';
  finally
    Service.Free;
  end;
end;

{ TAtlasArchitectureModelTests }

procedure TAtlasArchitectureModelTests.ParsesServerAnswer;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Db: Integer;
  Subsystem: TAtlasArchSubsystem;
  Count: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Assert.IsTrue(Enabled);
  Assert.AreEqual('App', Model.Title);
  Assert.AreEqual('C:\Projekt', Model.Root);
  Assert.AreEqual('project', Model.Scope);
  Assert.AreEqual(1, Integer(Length(Model.Excludes)));
  Assert.AreEqual('Tests/**', Model.Excludes[0]);
  Assert.AreEqual(6, Integer(Length(Model.Units)));
  Assert.AreEqual(3, Integer(Length(Model.Central)));
  Assert.AreEqual(Integer(Length(Model.Edges)), Model.EdgeCount);
  Assert.AreEqual(1, Integer(Length(Model.Cycles)));
  Db := Model.IndexOf('app.data.db');
  Assert.IsTrue(Db >= 0);
  Assert.IsTrue(Model.Units[Db].OnCycle);
  Assert.IsFalse(Model.Units[Model.IndexOf('App.Main')].OnCycle);
  Assert.AreEqual('App/Data/Db.pas', Model.Units[Db].FileName);
  Assert.IsTrue(Length(Model.Cycles[0].Edges) >= 2);
  Count := 0;
  for Subsystem in Model.Subsystems do
  begin
    Inc(Count, Length(Subsystem.Units));
    Assert.IsTrue(Subsystem.R > 0, 'Kreis der Karte');
  end;
  Assert.AreEqual(6, Count, 'jede Unit in genau einem Teilsystem');
  Assert.AreEqual(Model.Units[Db].Outlier, Model.OutlierOf(Db) >= 0);
end;

procedure TAtlasArchitectureModelTests.DisabledAndBrokenAnswers;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse('{"enabled":false}', Model, Enabled));
  Assert.IsFalse(Enabled);
  Assert.AreEqual(0, Integer(Length(Model.Units)));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('', Model, Enabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('[]', Model, Enabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":2}}', Model, Enabled),
    'fremdes Format');
  // Verweis auf eine Unit, die es nicht gibt: lieber nichts zeigen als abstürzen.
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":1,"units":[],' +
    '"edges":[[0,1,"i"]],"subsystems":[]}}', Model, Enabled));
  Assert.AreEqual(0, Integer(Length(Model.Edges)));
end;

procedure TAtlasArchitectureModelTests.SortsStableAndFilters;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  All, Sorted: TArray<Integer>;
  Index: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  All := nil;
  for Index := 0 to High(Model.Units) do
    All := All + [Index];
  Sorted := Model.Sorted(All, TAtlasArchColumn.Name, False);
  for Index := 1 to High(Sorted) do
    Assert.IsTrue(CompareText(Model.Units[Sorted[Index - 1]].Name, Model.Units[Sorted[Index]].Name) < 0);
  Sorted := Model.Sorted(All, TAtlasArchColumn.Name, True);
  Assert.AreEqual('App.Ui.Grid', Model.Units[Sorted[0]].Name);
  Sorted := Model.Sorted(All, TAtlasArchColumn.Total, True);
  for Index := 1 to High(Sorted) do
  begin
    Assert.IsTrue(Model.Units[Sorted[Index - 1]].Total >= Model.Units[Sorted[Index]].Total);
    // Gleichstand: nach Name aufsteigend, auch absteigend sortiert.
    if Model.Units[Sorted[Index - 1]].Total = Model.Units[Sorted[Index]].Total then
      Assert.IsTrue(CompareText(Model.Units[Sorted[Index - 1]].Name, Model.Units[Sorted[Index]].Name) < 0);
  end;
  Assert.IsTrue(Model.Matches(Model.IndexOf('App.Data.Db'), 'data db'));
  Assert.IsFalse(Model.Matches(Model.IndexOf('App.Data.Db'), 'data ui'));
  Assert.IsTrue(Model.Matches(0, ''));
  Assert.IsFalse(Model.Matches(99, ''));
end;

procedure TAtlasArchitectureModelTests.FullPathAndCyclePath;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Path: string;
  Parts: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Path := Model.FullPath('App/Data/Db.pas');
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\Projekt') + 'App' + PathDelim + 'Data' + PathDelim + 'Db.pas', Path);
  Assert.AreEqual('D:' + PathDelim + 'X.pas', Model.FullPath('D:/X.pas'), 'absolut bleibt');
  Model.Root := '';
  Assert.AreEqual('X.pas', Model.FullPath('X.pas'));
  // Der Zyklus beginnt bei einer seiner Units und kehrt zu ihr zurück.
  Parts := Model.CyclePath(Model.Cycles[0]).Split([' → ']);
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual(Parts[0], Parts[2]);
  Assert.IsTrue((Parts[0] = 'App.Data.Db') or (Parts[0] = 'App.Data.Cache'));
  Assert.AreNotEqual(Parts[0], Parts[1]);
end;

procedure TAtlasArchitectureModelTests.PaletteAndDarkness;
begin
  // #2F6FB3 als $00BBGGRR.
  Assert.AreEqual(Cardinal($B36F2F), TAtlasArchitecturePalette.Color(0, False));
  Assert.AreEqual(TAtlasArchitecturePalette.Color(1, True), TAtlasArchitecturePalette.Color(11, True));
  Assert.AreNotEqual(TAtlasArchitecturePalette.Color(2, False), TAtlasArchitecturePalette.Color(2, True));
  Assert.IsTrue(TAtlasArchitecturePalette.IsDark($00202020));
  Assert.IsFalse(TAtlasArchitecturePalette.IsDark($00FFFFFF));
end;

procedure TAtlasArchitectureModelTests.ViewFitsZoomsAndHits;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  View: TAtlasArchitectureView;
  Subsystem: TAtlasArchSubsystem;
  X, Y: Double;
  Db: Integer;
  Hidden: TArray<Boolean>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  View := Default(TAtlasArchitectureView);
  View.Fit(Model, 800, 600);
  Assert.IsTrue(View.Scale > 0);
  for Subsystem in Model.Subsystems do
  begin
    Assert.IsTrue(View.ScreenX(Subsystem.X - Subsystem.R) >= TAtlasArchitectureView.Margin - 0.5);
    Assert.IsTrue(View.ScreenX(Subsystem.X + Subsystem.R) <= 800 - TAtlasArchitectureView.Margin + 0.5);
    Assert.IsTrue(View.ScreenY(Subsystem.Y + Subsystem.R) <= 600 - TAtlasArchitectureView.Margin + 0.5);
  end;
  Db := Model.IndexOf('App.Data.Db');
  X := View.ScreenX(Model.Units[Db].X);
  Y := View.ScreenY(Model.Units[Db].Y);
  Assert.AreEqual(Db, View.UnitAt(Model, X, Y));
  // Units ausgeblendeter Teilsysteme sind nicht treffbar.
  SetLength(Hidden, Length(Model.Subsystems));
  Hidden[Model.Units[Db].Subsystem] := True;
  Assert.AreNotEqual(Db, View.UnitAt(Model, X, Y, Hidden));
  // Zoomen um den Punkt der Unit: Sie bleibt unter dem Mauszeiger.
  View.ZoomAt(2, X, Y);
  Assert.AreEqual(X, View.ScreenX(Model.Units[Db].X), 0.001);
  Assert.AreEqual(Y, View.ScreenY(Model.Units[Db].Y), 0.001);
  View.Pan(10, -5);
  Assert.AreEqual(X + 10, View.ScreenX(Model.Units[Db].X), 0.001);
  Assert.AreEqual(-1, View.UnitAt(Model, -1000, -1000));
  View.ZoomAt(1000, 0, 0);
  Assert.AreEqual(Double(TAtlasArchitectureView.MaxScale), View.Scale, 0.0001);
end;

procedure TAtlasArchitectureModelTests.CommandArguments;
var
  Value: TJSONValue;
  Items: TJSONArray;
  Options: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', True));
  try
    Items := Value as TJSONArray;
    Assert.AreEqual('file:///C:/P/App.dproj', Items.Items[0].Value);
    Options := Items.Items[1] as TJSONObject;
    Assert.AreEqual('project', Options.GetValue<string>('scope'));
    Assert.IsTrue(Options.GetValue<Boolean>('includeLibraryUnits'));
    Assert.AreEqual('json', Options.GetValue<string>('format'));
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\P\Architektur.html', 'projectGroup', False));
  try
    Items := Value as TJSONArray;
    Assert.AreEqual(3, Integer(Items.Count));
    Assert.AreEqual('C:\P\Architektur.html', Items.Items[1].Value);
    Assert.AreEqual('projectGroup', (Items.Items[2] as TJSONObject).GetValue<string>('scope'));
  finally
    Value.Free;
  end;
  Assert.AreEqual('C:\P\a.md', TAtlasArchitectureCommands.SavedFile('{"file":"C:\\P\\a.md","units":3}'));
  Assert.AreEqual('', TAtlasArchitectureCommands.SavedFile('kein JSON'));
end;

procedure TAtlasArchitectureModelTests.ShortestPathOverUses;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Path: TArray<Integer>;
  Hidden: TArray<Boolean>;
  Main, Cache, Db: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Main := Model.IndexOf('App.Main');
  Cache := Model.IndexOf('App.Data.Cache');
  Db := Model.IndexOf('App.Data.Db');
  // Kürzester Weg in Richtung der uses: Main → Data → Db → Cache, nicht über Ui.
  Assert.IsTrue(Model.ShortestPath(Main, Cache, True, nil, Path));
  Assert.AreEqual(3, Integer(Length(Path)));
  Assert.AreEqual('App.Main → App.Data → App.Data.Db → App.Data.Cache', Model.PathText(Main, Path));
  // Gegen die Richtung gibt es keinen Weg, ebenso nicht zu sich selbst.
  Assert.IsFalse(Model.ShortestPath(Cache, Main, True, nil, Path));
  Assert.AreEqual(0, Integer(Length(Path)));
  Assert.IsFalse(Model.ShortestPath(Main, Main, True, nil, Path));
  // Cache → Db geht nur über implementation.
  Assert.IsTrue(Model.ShortestPath(Cache, Db, True, nil, Path));
  Assert.IsFalse(Model.ShortestPath(Cache, Db, False, nil, Path));
  // Ein ausgeblendetes Teilsystem sperrt seine Units als Ziel und Zwischenschritt.
  SetLength(Hidden, Length(Model.Subsystems));
  Hidden[Model.Units[Cache].Subsystem] := True;
  Assert.IsTrue(Model.IsHidden(Cache, Hidden));
  Assert.IsFalse(Model.ShortestPath(Main, Cache, True, Hidden, Path));
  Assert.AreEqual(-1, Model.IndexOf('Fehlt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureModelTests);

end.
