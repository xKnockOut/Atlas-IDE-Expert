unit Atlas.Common.Architecture.Report.Tests;

// Tests der Ausgaben der Architekturübersicht (#1118): Markdown, JSON, HTML
// (offline, Daten eingebettet), MCP-Abschnitte und Unit-Steckbrief.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArchitectureReportTests = class
  public
    [Test]
    procedure MarkdownHasAllSections;
    [Test]
    procedure JsonIsValidAndComplete;
    [Test]
    procedure HtmlEmbedsDataWithoutExternalLinks;
    [Test]
    procedure TextSectionsAndLimit;
    [Test]
    procedure UnitProfileText;
    [Test]
    procedure ParsesSections;
    [Test]
    procedure SameOverviewSameReports;
    [Test]
    procedure TemplateHasPlaceholdersOnce;
    [Test]
    procedure ReportsCarryComparison;
    /// <summary>Feinheit γ (#1366): im Kopf nur, wenn sie von 1,0 abweicht; JSON immer.</summary>
    [Test]
    procedure HeaderNamesChangedResolution;
    [Test]
    procedure NamesParentOfSplitSubsystem;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.MapTemplate,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.UsesGraph.Tests;

/// <summary>Drei Namensräume wie in den Übersichtstests, dazu ein Zyklus über implementation in Data und eine
/// Fundstelle für Ui.Main → Data.Model.</summary>
function Sample: TArchitectureOverview;
var
  Units: TArray<TUnitIndex>;
  Graph: TUsesGraph;
  Locator: TUsesLocator;
  Files: TDictionary<string, string>;
begin
  Units := nil;
  Units := Units + [UsesUnit('App.Core.Base', nil, nil), UsesUnit('App.Core.Types', ['App.Core.Base'], nil),
    UsesUnit('App.Core.Log', ['App.Core.Base', 'App.Core.Types'], nil),
    UsesUnit('App.Core.Util', ['App.Core.Base', 'App.Core.Types'], nil)];
  Units := Units + [UsesUnit('App.Data.Db', nil, ['App.Core.Base', 'App.Data.Cache']), UsesUnit('App.Data.Model',
    ['App.Data.Db'], nil), UsesUnit('App.Data.Query', ['App.Data.Db', 'App.Data.Model'], nil),
    UsesUnit('App.Data.Cache', ['App.Data.Query', 'App.Data.Model'], nil)];
  Units := Units + [UsesUnit('App.Ui.Theme', nil, nil), UsesUnit('App.Ui.Grid', ['App.Ui.Theme'], nil),
    UsesUnit('App.Ui.Form', ['App.Ui.Theme', 'App.Ui.Grid'], nil),
    UsesUnit('App.Ui.Main', ['App.Ui.Form', 'App.Ui.Grid'], ['App.Data.Model'])];
  Files := TDictionary<string, string>.Create;
  Files.Add(Units[11].FileName, 'unit App.Ui.Main;'#10'interface'#10'uses App.Ui.Form, App.Ui.Grid;'#10 +
    'implementation'#10'uses'#10'  App.Data.Model;'#10'end.');
  Graph := TUsesGraph.Create(Units, TUsesGraphOptions.Default);
  Locator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
  try
    Result := TArchitectureAnalyzer.Analyze(Graph, Locator, 5);
  finally
    Locator.Free;
    Graph.Free;
    Files.Free;
  end;
  Result.Title := 'Beispiel';
  Result.Root := 'C:\Projekt';
  Result.Scope := 'projectGroup';
  Result.Created := EncodeDate(2026, 10, 23) + EncodeTime(10, 30, 0, 0);
  Result.Generation := 7;
  Result.DurationMs := 12;
end;

function Item(ARoot: TJSONObject; const AArray: string; AIndex: Integer): TJSONObject;
begin
  Result := ARoot.GetValue<TJSONArray>(AArray).Items[AIndex] as TJSONObject;
end;

{ TArchitectureReportTests }

procedure TArchitectureReportTests.MarkdownHasAllSections;
var
  Text: string;
begin
  Text := TArchitectureReport.Markdown(Sample);
  Assert.StartsWith('# Architektur: Beispiel', Text);
  Assert.Contains(Text, 'Stand 2026-10-23 10:30 · Index-Generation 7 · Rechendauer 12 ms');
  Assert.Contains(Text, 'Units: 12 · uses-Kanten: 18 · Teilsysteme: 3 · Zyklen: 1');
  Assert.Contains(Text, '## Zentrale Units');
  Assert.Contains(Text, '| 1 | App.Core.Base | Core | 4 | 4 | 0 | Fundament |');
  Assert.Contains(Text, '## Teilsysteme');
  Assert.Contains(Text, '### Data');
  Assert.Contains(Text, '## Ausreißer');
  Assert.Contains(Text, '### 1. Zyklus über implementation');
  Assert.Contains(Text, 'App.Data.Db → App.Data.Cache (implementation)');
  Assert.Contains(Text, '| App.Ui.Main | App.Data.Model | implementation | Ui → Data | selten (1 hin, 0 zurück) | ' +
    'App/Ui/Main.pas:6:3 |');
end;

procedure TArchitectureReportTests.JsonIsValidAndComplete;
var
  Data: TArchitectureOverview;
  Value: TJSONValue;
  Root: TJSONObject;
begin
  Data := Sample;
  Value := TJSONObject.ParseJSONValue(TArchitectureReport.Json(Data, TArchitectureLayouter.Compute(Data)));
  try
    Assert.IsNotNull(Value);
    Root := Value as TJSONObject;
    Assert.AreEqual(1, Root.GetValue<Integer>('format'));
    Assert.AreEqual('Beispiel', Root.GetValue<string>('title'));
    Assert.AreEqual('2026-10-23T10:30:00', Root.GetValue<string>('created'));
    Assert.AreEqual(12, Integer(Root.GetValue<TJSONArray>('units').Count));
    Assert.AreEqual(18, Integer(Root.GetValue<TJSONArray>('edges').Count));
    Assert.AreEqual(3, Root.GetValue<Integer>('summary.subsystems'));
    Assert.AreEqual('App/Core/Base.pas', Item(Root, 'units', 0).GetValue<string>('file'));
    Assert.AreEqual('foundation', Item(Root, 'units', 0).GetValue<string>('role'));
    Assert.AreEqual('implementation', Item(Root, 'crossLinks', 1).GetValue<string>('section'));
    Assert.AreEqual(6, Item(Root, 'crossLinks', 1).GetValue<Integer>('line'));
    Assert.AreEqual(3, Item(Root, 'crossLinks', 1).GetValue<Integer>('character'));
    Assert.IsFalse(Item(Root, 'cycles', 0).GetValue<Boolean>('interfaceOnly'));
    Assert.IsTrue(Item(Root, 'subsystems', 0).GetValue<Double>('r') > 0);
  finally
    Value.Free;
  end;
end;

procedure TArchitectureReportTests.HtmlEmbedsDataWithoutExternalLinks;
var
  Data: TArchitectureOverview;
  Html: string;
begin
  Data := Sample;
  Data.Title := 'A</script><b>';
  Html := TArchitectureReport.Html(Data);
  Assert.StartsWith('<!doctype html>', Html);
  Assert.Contains(Html, '<title>Architektur: A&lt;/script&gt;&lt;b&gt;</title>');
  Assert.Contains(Html, '"title":"A<\/script><b>"');
  Assert.DoesNotContain(Html, '{{DATA}}');
  Assert.DoesNotContain(Html, '{{TITLE}}');
  Assert.DoesNotContain(Html, 'src="http');
  Assert.DoesNotContain(Html, 'href="http');
  Assert.Contains(Html, '"name":"App.Core.Base"');
  Assert.Contains(Html, 'Weg zeigen');
  Assert.Contains(Html, 'Zyklen markieren');
end;

procedure TArchitectureReportTests.ReportsCarryComparison;
var
  Data, Older: TArchitectureOverview;
  Comparison: TArchitectureComparison;
  Text: string;
  Root: TJSONValue;
begin
  // Vergleich (#1121): Der alte Stand hatte den Zyklus in Data noch nicht.
  Data := Sample;
  Older := Data;
  Older.Cycles := nil;
  Comparison := TArchitectureComparer.Compare(TArchitectureSnapshots.FromOverview(Older),
    TArchitectureSnapshots.FromOverview(Data));
  Assert.AreEqual(1, Integer(Length(Comparison.NewCycles)));
  Text := TArchitectureReport.Markdown(Data, Comparison);
  Assert.Contains(Text, '- [Vergleich](#vergleich)');
  Assert.Contains(Text, '## Vergleich');
  Assert.Contains(Text, '### Neue Zyklen (1)');
  Assert.DoesNotContain(TArchitectureReport.Markdown(Data), '## Vergleich');
  Text := TArchitectureReport.Json(Data, TArchitectureLayouter.Compute(Data), Comparison,
    TArchitectureComparer.DefaultFailOn);
  Root := TJSONObject.ParseJSONValue(Text);
  try
    Assert.IsTrue(Root is TJSONObject);
    Assert.AreEqual(1, ((Root as TJSONObject).GetValue('comparison') as TJSONObject).GetValue<TJSONArray>(
      'newCycles').Count);
  finally
    Root.Free;
  end;
  Text := TArchitectureReport.Html(Data, Comparison, TArchitectureComparer.DefaultFailOn);
  Assert.Contains(Text, '"comparison":{"baseline":');
  Assert.Contains(Text, 'id="vergleich"');
  Assert.Contains(TArchitectureReport.ForFile(Data, 'bericht.htm', Comparison, []), '"comparison":');
  Assert.Contains(TArchitectureReport.ForFile(Data, 'bericht.md', Comparison, []), '## Vergleich');
end;

procedure TArchitectureReportTests.TextSectionsAndLimit;
var
  Data: TArchitectureOverview;
  Text: string;
begin
  Data := Sample;
  Text := TArchitectureReport.Text(Data, TArchitectureSection.Overview, 30);
  Assert.Contains(Text, 'Architektur Beispiel (Projektgruppe, ohne Bibliotheks-Units)');
  Assert.Contains(Text, 'Core: 4 Units, Zusammenhalt');
  Text := TArchitectureReport.Text(Data, TArchitectureSection.Central, 2);
  Assert.Contains(Text, 'App.Core.Base | Core | 4 | 4 | 0 | Fundament');
  Assert.Contains(Text, '… 3 weitere (insgesamt 5)');
  Text := TArchitectureReport.Text(Data, TArchitectureSection.Cycles, 30);
  Assert.Contains(Text, '1. Zyklus über implementation: App.Data.');
  Text := TArchitectureReport.Text(Data, TArchitectureSection.CrossLinks, 30);
  Assert.Contains(Text, 'App.Ui.Main → App.Data.Model (implementation, App/Ui/Main.pas:6:3) Ui → Data, selten');
  Text := TArchitectureReport.Text(Data, TArchitectureSection.Subsystems, 1);
  Assert.Contains(Text, '… 2 weitere (insgesamt 3)');
end;

procedure TArchitectureReportTests.UnitProfileText;
var
  Data: TArchitectureOverview;
  Text: string;
begin
  Data := Sample;
  Text := TArchitectureReport.UnitText(Data, 'app.data.model');
  Assert.StartsWith('App.Data.Model (App/Data/Model.pas)', Text);
  Assert.Contains(Text, 'Teilsystem: Data');
  Assert.Contains(Text, 'verwendet von: App.Data.Cache, App.Data.Query, App.Ui.Main');
  Assert.Contains(Text, 'Querverbindung: App.Ui.Main → App.Data.Model');
  Assert.Contains(TArchitectureReport.UnitText(Data, 'Fehlt'), 'nicht in der Architekturübersicht');
end;

procedure TArchitectureReportTests.ParsesSections;
var
  Section: TArchitectureSection;
begin
  Assert.IsTrue(TArchitectureReport.ParseSection('', Section));
  Assert.IsTrue(Section = TArchitectureSection.Overview);
  Assert.IsTrue(TArchitectureReport.ParseSection('crosslinks', Section));
  Assert.IsTrue(Section = TArchitectureSection.CrossLinks);
  Assert.IsFalse(TArchitectureReport.ParseSection('alles', Section));
  Assert.AreEqual('crossLinks', TArchitectureReport.SectionName(TArchitectureSection.CrossLinks));
end;

procedure TArchitectureReportTests.SameOverviewSameReports;
begin
  Assert.AreEqual(TArchitectureReport.Markdown(Sample), TArchitectureReport.Markdown(Sample));
  Assert.AreEqual(TArchitectureReport.Html(Sample), TArchitectureReport.Html(Sample));
end;

procedure TArchitectureReportTests.TemplateHasPlaceholdersOnce;
var
  Html: string;
begin
  Html := ArchitectureMapHtml;
  Assert.AreEqual(1, Integer(Length(Html.Split(['{{DATA}}'])) - 1));
  Assert.AreEqual(1, Integer(Length(Html.Split(['{{TITLE}}'])) - 1));
  Assert.Contains(Html, '</html>');
end;

procedure TArchitectureReportTests.HeaderNamesChangedResolution;
var
  mOverview: TArchitectureOverview;
  mText: string;
begin
  mOverview := Sample;
  mText := TArchitectureReport.Markdown(mOverview);
  Assert.IsFalse(Pos('Feinheit', mText) > 0, 'γ = 1,0 steht nicht im Kopf');
  Assert.Contains(TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview)),
    '"grouping":{"resolution":1}');
  mOverview.Grouping.Resolution := 2.5;
  mText := TArchitectureReport.Markdown(mOverview);
  Assert.Contains(mText, 'Umfang: Projektgruppe, ohne Bibliotheks-Units, Feinheit γ = 2,5', False);
  Assert.Contains(TArchitectureReport.Text(mOverview, TArchitectureSection.Overview, 10), 'Feinheit γ = 2,5', False);
  Assert.Contains(TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview)),
    '"grouping":{"resolution":2.5}');
  // Die HTML-Seite liest denselben Wert aus den Daten.
  Assert.Contains(TArchitectureReport.Html(mOverview), 'Feinheit γ = ', False);
end;

procedure TArchitectureReportTests.NamesParentOfSplitSubsystem;
var
  mOverview: TArchitectureOverview;
  mJson, mName: string;
begin
  mOverview := Sample;
  mJson := TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview));
  Assert.IsFalse(Pos('"parent"', mJson) > 0, 'ohne Nachteilung kein "parent"');
  Assert.Contains(mJson, '"color":1,"shade":0');
  // Teil eines nachgeteilten Teilsystems (#1364).
  mName := mOverview.Subsystems[0].Name;
  mOverview.Subsystems[0].Parent := 'App';
  mOverview.Subsystems[0].Shade := 1;
  mJson := TArchitectureReport.Json(mOverview, TArchitectureLayouter.Compute(mOverview));
  Assert.Contains(mJson, '"color":0,"shade":1,"parent":"App"');
  Assert.Contains(TArchitectureReport.Markdown(mOverview), '### ' + mName + ' (Teil von App)');
  Assert.Contains(TArchitectureReport.Text(mOverview, TArchitectureSection.Subsystems, 10),
    mName + ' (Teil von App): ');
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureReportTests);

end.
