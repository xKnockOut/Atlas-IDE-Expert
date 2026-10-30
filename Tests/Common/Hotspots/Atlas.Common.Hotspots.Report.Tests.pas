unit Atlas.Common.Hotspots.Report.Tests;

// Tests der Ausgaben der Hotspots (#1354): JSON (Format 1) mit Einträgen,
// Verlauf und Kopplung, Markdown-Tabellen, eigenständige HTML-Seite mit
// Blasendiagramm, Wahl nach Endung und der kompakte Text für get_hotspots.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Hotspots.Analysis;

type
  [TestFixture]
  THotspotReportTests = class
  public
    [Test]
    procedure JsonHasFormatEntriesAndCoupling;
    [Test]
    procedure MarkdownHasTablesAndRange;
    [Test]
    procedure HtmlIsStandaloneWithChart;
    [Test]
    procedure ChoosesFormatByExtension;
    [Test]
    procedure TextLimitsSections;
    [Test]
    procedure ParsesSections;
  end;

/// <summary>Ergebnis mit drei Units (eine mit Methode und Trend) und einem Kopplungspaar.</summary>
function SampleHotspots: THotspotResult;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Report;

function Entry(const AUnit, APath: string; AChanges, AComplexity: Integer; AScore: Double): THotspotEntry;
var
  mCommit: THotspotLineCommit;
begin
  Result := Default(THotspotEntry);
  Result.UnitName := AUnit;
  Result.Path := APath;
  Result.Line := 1;
  Result.Lines := 100;
  Result.EndLine := 100;
  Result.Changes.Changes := AChanges;
  Result.Changes.Authors := ['anna', 'bernd'];
  Result.Changes.Added := 10;
  Result.Changes.Deleted := 4;
  Result.Changes.LastChange := EncodeDate(2026, 10, 20);
  mCommit := Default(THotspotLineCommit);
  mCommit.Revision := 'abc1234';
  mCommit.Author := 'anna';
  mCommit.Date := EncodeDate(2026, 10, 20);
  mCommit.Summary := 'Fehler <behoben> & "getestet"';
  mCommit.Added := 3;
  mCommit.Deleted := 1;
  Result.Changes.History := [mCommit];
  Result.Complexity := AComplexity;
  Result.PastComplexity := -1;
  Result.Score := AScore;
end;

function SampleHotspots: THotspotResult;
var
  mMethod: THotspotEntry;
  mPair: THotspotCoupling;
begin
  Result := Default(THotspotResult);
  Result.Title := 'Demo';
  Result.Root := 'C:\Projekt';
  Result.Kind := THotspotVcsKind.Git;
  Result.Head := 'abc1234';
  Result.Months := 12;
  Result.Since := EncodeDate(2025, 10, 29);
  Result.Commits := 42;
  Result.Level := THotspotLevel.Units;
  Result.Units := [Entry('App.Kern', 'App/Kern.pas', 12, 80, 1), Entry('App.Daten', 'App/Daten.pas', 6, 40, 0.25),
    Entry('App.Form', 'App/Form.pas', 2, 10, 0.02)];
  Result.Units[0].PastComplexity := 60;
  Result.Units[0].Trend := THotspotTrend.Rising;
  mMethod := Entry('App.Kern', 'App/Kern.pas', 7, 25, 1);
  mMethod.Method := 'TKern.Rechne';
  mMethod.Line := 120;
  mMethod.EndLine := 180;
  Result.Methods := [mMethod];
  mPair := Default(THotspotCoupling);
  mPair.First.UnitName := 'App.Daten';
  mPair.First.Path := 'App/Daten.pas';
  mPair.Second.UnitName := 'App.Form';
  mPair.Second.Path := 'App/Form.pas';
  mPair.Shared := 6;
  mPair.FirstChanges := 6;
  mPair.SecondChanges := 7;
  mPair.Ratio := 0.923;
  Result.Coupling := [mPair];
end;

{ THotspotReportTests }

procedure THotspotReportTests.JsonHasFormatEntriesAndCoupling;
var
  mRoot: TJSONValue;
  mData, mUnit, mPair, mItem: TJSONObject;
begin
  mRoot := TJSONObject.ParseJSONValue(THotspotReport.Json(SampleHotspots));
  try
    Assert.IsTrue(mRoot is TJSONObject, 'gültiges JSON');
    mData := TJSONObject(mRoot);
    Assert.AreEqual(1, mData.GetValue<Integer>('format'));
    Assert.AreEqual('git', mData.GetValue<string>('vcs'));
    Assert.AreEqual('unit', mData.GetValue<string>('level'));
    Assert.AreEqual(42, mData.GetValue<Integer>('commits'));
    Assert.AreEqual('2025-10-29T00:00:00Z', mData.GetValue<string>('since'));
    Assert.AreEqual(3, mData.GetValue<TJSONArray>('units').Count);
    mUnit := mData.GetValue<TJSONArray>('units').Items[0] as TJSONObject;
    Assert.AreEqual('App.Kern', mUnit.GetValue<string>('unit'));
    Assert.AreEqual('App/Kern.pas', mUnit.GetValue<string>('path'));
    Assert.AreEqual(12, mUnit.GetValue<Integer>('changes'));
    Assert.AreEqual(2, mUnit.GetValue<Integer>('authors'));
    Assert.AreEqual('rising', mUnit.GetValue<string>('trend'));
    Assert.AreEqual(60, mUnit.GetValue<Integer>('pastComplexity'));
    mItem := mUnit.GetValue<TJSONArray>('history').Items[0] as TJSONObject;
    Assert.AreEqual('Fehler <behoben> & "getestet"', mItem.GetValue<string>('summary'));
    Assert.IsNull(mUnit.GetValue('method'), 'Unit ohne Methode');
    mItem := mData.GetValue<TJSONArray>('methods').Items[0] as TJSONObject;
    Assert.AreEqual('TKern.Rechne', mItem.GetValue<string>('method'));
    mPair := mData.GetValue<TJSONArray>('coupling').Items[0] as TJSONObject;
    mItem := mPair.GetValue('first') as TJSONObject;
    Assert.AreEqual('App.Daten', mItem.GetValue<string>('unit'));
    Assert.AreEqual(6, mPair.GetValue<Integer>('shared'));
    Assert.IsFalse(THotspotReport.Json(SampleHotspots).Contains('C:\\Projekt'), 'Wurzel nicht im Bericht');
  finally
    mRoot.Free;
  end;
end;

procedure THotspotReportTests.MarkdownHasTablesAndRange;
var
  mText: string;
  mResult: THotspotResult;
begin
  mText := THotspotReport.Markdown(SampleHotspots);
  Assert.IsTrue(mText.StartsWith('# Hotspots Demo'));
  Assert.IsTrue(mText.Contains('Git, 12 Monate seit 2025-10-29, 42 Commits'), mText);
  Assert.IsTrue(mText.Contains('## Units'));
  Assert.IsTrue(mText.Contains('| 1 | App.Kern'), mText);
  // Ohne den Pfeil: Der Linux-Testlauf mit Codepage 1252 ersetzt ihn.
  Assert.IsTrue(mText.Contains('steigend (60 '), mText);
  Assert.IsTrue(mText.Contains('## Änderungskopplung'));
  Assert.IsFalse(mText.Contains('## Methoden'), 'Unit-Ebene');
  mResult := SampleHotspots;
  mResult.Level := THotspotLevel.Methods;
  mText := THotspotReport.Markdown(mResult);
  Assert.IsTrue(mText.Contains('## Methoden'));
  Assert.IsTrue(mText.Contains('TKern.Rechne'));
end;

procedure THotspotReportTests.HtmlIsStandaloneWithChart;
var
  mText: string;
  mParts: TArray<string>;
begin
  mText := THotspotReport.Html(SampleHotspots);
  Assert.IsTrue(mText.StartsWith('<!DOCTYPE html>'), Copy(mText, 1, 40));
  Assert.IsTrue(mText.Contains('<svg class="chart"'));
  mParts := mText.Split(TArray<string>.Create('<circle'));
  Assert.AreEqual(3, Integer(Length(mParts)) - 1, 'eine Blase je Unit');
  Assert.IsTrue(mText.Contains('prefers-color-scheme:dark'));
  Assert.IsTrue(mText.Contains('<h2>Änderungskopplung</h2>'));
  Assert.IsFalse(mText.Contains('<script'), 'ohne Skript');
  Assert.IsFalse(mText.Contains('<behoben>'), 'Text maskiert');
end;

procedure THotspotReportTests.ChoosesFormatByExtension;
begin
  Assert.IsTrue(THotspotReport.ForFile(SampleHotspots, 'C:\x\Bericht.HTML').StartsWith('<!DOCTYPE html>'));
  Assert.IsTrue(THotspotReport.ForFile(SampleHotspots, 'Bericht.htm').StartsWith('<!DOCTYPE html>'));
  Assert.IsTrue(THotspotReport.ForFile(SampleHotspots, 'Bericht.json').StartsWith('{"format":1'));
  Assert.IsTrue(THotspotReport.ForFile(SampleHotspots, 'Bericht.md').StartsWith('# Hotspots'));
  Assert.IsTrue(THotspotReport.ForFile(SampleHotspots, 'Bericht').StartsWith('# Hotspots'));
end;

procedure THotspotReportTests.TextLimitsSections;
var
  mText: string;
begin
  mText := THotspotReport.Text(SampleHotspots, THotspotSection.Hotspots, 2);
  Assert.IsTrue(mText.Contains('2 von 3'), mText);
  Assert.IsTrue(mText.Contains('1. App.Kern (App/Kern.pas)'), mText);
  Assert.IsFalse(mText.Contains('App.Form (App/Form.pas)'), 'auf 2 gekürzt');
  mText := THotspotReport.Text(SampleHotspots, THotspotSection.Coupling, 20);
  Assert.IsTrue(mText.Contains('App/Form.pas: 6 gemeinsame Commits'), mText);
  Assert.IsTrue(mText.StartsWith('Änderungskopplung'), mText);
  Assert.AreEqual('TKern.Rechne (App/Kern.pas:120)', THotspotReport.EntryName(SampleHotspots.Methods[0]));
  Assert.AreEqual('steigend', THotspotReport.TrendCaption(THotspotTrend.Rising));
  Assert.AreEqual('', THotspotReport.TrendCaption(THotspotTrend.Unknown));
end;

procedure THotspotReportTests.ParsesSections;
var
  mSection: THotspotSection;
begin
  Assert.IsTrue(THotspotReport.ParseSection('', mSection) and (mSection = THotspotSection.Hotspots));
  Assert.IsTrue(THotspotReport.ParseSection('coupling', mSection) and (mSection = THotspotSection.Coupling));
  Assert.IsFalse(THotspotReport.ParseSection('trend', mSection));
  Assert.AreEqual('coupling', THotspotReport.SectionName(THotspotSection.Coupling));
end;

initialization
  TDUnitX.RegisterTestFixture(THotspotReportTests);

end.
