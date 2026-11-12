unit Atlas.Common.Monitor.Results.Tests;

// Tests für die Ergebnisse des Prüffensters von AtlasMonitor (#1900): SARIF lesen (Wurzel, Baseline, Meldung in der
// Sprache des Laufs), filtern, zusammenführen und als HTML-Seite schreiben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorResultsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsSarif;
    [Test]
    procedure RejectsInvalidText;
    [Test]
    procedure FiltersByTextAndLevel;
    [Test]
    procedure MergesRuns;
    [Test]
    procedure WritesHtml;
    [Test]
    procedure ColumnsMatchTitles;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Runs,
  Atlas.Common.Monitor.Results;

const
  cSarif = '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"Atlas"}},' +
    '"originalUriBaseIds":{"%SRCROOT%":{"uri":"file:///c%3A/Projekte/App/"}},"results":[' +
    '{"ruleId":"magic-number","level":"warning","message":{"text":"Magic number"},' +
    '"locations":[{"physicalLocation":{"artifactLocation":{"uri":"Src/Main%20Form.pas","uriBaseId":"%SRCROOT%"},' +
    '"region":{"startLine":12,"startColumn":5}}}],"properties":{"detail":"Zahl 3 ohne Namen"}},' +
    '{"ruleId":"unused-uses","level":"error","message":{"text":"Unused unit"},' +
    '"locations":[{"physicalLocation":{"artifactLocation":{"uri":"file:///d%3A/Lib/A.pas"},' +
    '"region":{"startLine":1,"startColumn":1}}}]},' +
    '{"ruleId":"old","level":"warning","message":{"text":"x"},"baselineState":"unchanged",' +
    '"suppressions":[{"kind":"external"}]},' +
    '{"ruleId":"gone","level":"warning","message":{"text":"x"},"baselineState":"absent"},' +
    '{"ruleId":"hint","level":"note","message":{"text":"Hinweis ohne Stelle"}}]}]}';

function Sample: TArray<TMonitorFinding>;
var
  mError: string;
begin
  Assert.IsTrue(TMonitorResults.ParseSarif(cSarif, 'C:\Projekte\App', Result, mError), mError);
end;

procedure TMonitorResultsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorResultsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorResultsTests.ReadsSarif;
var
  mFindings: TArray<TMonitorFinding>;
begin
  mFindings := Sample;
  Assert.AreEqual(3, Integer(Length(mFindings)), 'ohne Baseline-Treffer');
  Assert.AreEqual('c:\Projekte\App\Src\Main Form.pas', mFindings[0].FileName);
  Assert.AreEqual(12, mFindings[0].Line);
  Assert.AreEqual(5, mFindings[0].Column);
  Assert.AreEqual('Zahl 3 ohne Namen', mFindings[0].Message, 'Meldung aus properties.detail');
  Assert.AreEqual('C:\Projekte\App', mFindings[0].Target);
  Assert.AreEqual('d:\Lib\A.pas', mFindings[1].FileName);
  Assert.AreEqual('Unused unit', mFindings[1].Message, 'ohne detail der Text');
  Assert.AreEqual('', mFindings[2].FileName);
  Assert.AreEqual(0, mFindings[2].Line);
  mFindings := nil;
end;

procedure TMonitorResultsTests.RejectsInvalidText;
var
  mFindings: TArray<TMonitorFinding>;
  mError: string;
begin
  Assert.IsFalse(TMonitorResults.ParseSarif('', 'A', mFindings, mError));
  Assert.AreEqual('Die Ausgabe ist kein SARIF.', mError);
  Assert.IsFalse(TMonitorResults.ParseSarif('{"files":[]}', 'A', mFindings, mError));
  Assert.IsTrue(TMonitorResults.ParseSarif('{"runs":[{}]}', 'A', mFindings, mError));
  Assert.AreEqual(0, Integer(Length(mFindings)));
  mError := '';
end;

procedure TMonitorResultsTests.FiltersByTextAndLevel;
var
  mFindings: TArray<TMonitorFinding>;
begin
  mFindings := Sample;
  Assert.AreEqual(3, Integer(Length(TMonitorResults.Filter(mFindings, '', ''))));
  Assert.AreEqual(2, Integer(Length(TMonitorResults.Filter(mFindings, '', 'warning'))));
  Assert.AreEqual(1, Integer(Length(TMonitorResults.Filter(mFindings, '', 'error'))));
  Assert.AreEqual(1, Integer(Length(TMonitorResults.Filter(mFindings, 'MAIN form', ''))), 'Datei');
  Assert.AreEqual(1, Integer(Length(TMonitorResults.Filter(mFindings, 'unused', ''))), 'Regel');
  Assert.AreEqual(1, Integer(Length(TMonitorResults.Filter(mFindings, 'ohne namen', ''))), 'Meldung');
  Assert.AreEqual(0, Integer(Length(TMonitorResults.Filter(mFindings, 'hinweis', 'warning'))));
  mFindings := nil;
end;

procedure TMonitorResultsTests.MergesRuns;
var
  mMerged: string;
  mFindings: TArray<TMonitorFinding>;
  mError: string;
begin
  mMerged := TMonitorResults.MergeSarif(TArray<string>.Create(cSarif, 'kaputt', cSarif));
  Assert.IsTrue(mMerged.Contains('"version":"2.1.0"'), mMerged);
  Assert.IsTrue(TMonitorResults.ParseSarif(mMerged, 'X', mFindings, mError), mError);
  Assert.AreEqual(6, Integer(Length(mFindings)), 'zwei Läufe');
  mMerged := '';
  mFindings := nil;
end;

procedure TMonitorResultsTests.WritesHtml;
var
  mFindings: TArray<TMonitorFinding>;
  mHtml: string;
begin
  mFindings := Sample;
  mFindings[0].Message := '<script>';
  mHtml := TMonitorResults.Html(mFindings, 'Atlas & Co');
  Assert.IsTrue(mHtml.StartsWith('<!DOCTYPE html><html lang="de">'), mHtml);
  Assert.IsTrue(mHtml.Contains('<title>Atlas &amp; Co</title>'), mHtml);
  Assert.IsTrue(mHtml.Contains('<h2>C:\Projekte\App</h2>'), mHtml);
  Assert.IsTrue(mHtml.Contains('&lt;script&gt;'), mHtml);
  Assert.IsFalse(mHtml.Contains('<script>'), mHtml);
  Assert.IsTrue(mHtml.Contains('3 Befunde'), mHtml);
  Assert.IsTrue(mHtml.Contains('<td class="error">Fehler</td>'), mHtml);
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.IsTrue(TMonitorResults.Html(nil, 'T').Contains('No findings.'));
  mFindings := nil;
  mHtml := '';
end;

procedure TMonitorResultsTests.ColumnsMatchTitles;
var
  mCells: TArray<string>;
begin
  mCells := TMonitorResults.Columns(Sample[0]);
  Assert.AreEqual(Integer(Length(TMonitorResults.ColumnTitles)), Integer(Length(mCells)));
  Assert.AreEqual('Warnung', mCells[0]);
  Assert.AreEqual('12', mCells[2]);
  Assert.AreEqual('magic-number', mCells[3]);
  Assert.AreEqual('Hinweis', TMonitorResults.LevelText('note'));
  mCells := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorResultsTests);

end.
