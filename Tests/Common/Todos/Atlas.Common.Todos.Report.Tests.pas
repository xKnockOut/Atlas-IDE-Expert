unit Atlas.Common.Todos.Report.Tests;

// Tests der TODO-Übersicht (#68): Zusammenfassung für die
// Projekt-Zusammenfassung (#758), JSON-Daten, Markdown und Kurztext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTodoReportTests = class
  public
    [Test]
    procedure SummarizesOpenDoneAndKeywords;
    [Test]
    procedure SummaryJson;
    [Test]
    procedure JsonHasLinesFromOne;
    [Test]
    procedure MarkdownGroupsByCategoryOwnerAndUnit;
    [Test]
    procedure MarkdownWithoutEntries;
    [Test]
    procedure CaptionShowsDetails;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Todos.Scanner,
  Atlas.Common.Todos.Report;

const
  cKasseText = 'unit Kasse;'#10 +
    '// TODO Rundung prüfen'#10 +
    '// FIXME: Rabatt | doppelt'#10 +
    '{ TODO 2 -oMarco -cGUI : Fokus setzen }'#10 +
    '{ DONE 1 -oAnna -cDaten : Index angelegt }'#10 +
    'end.';
  cLagerText = 'unit Lager;'#10'{ TODO -oMarco -cGUI : "Menü" }'#10'end.';

function SampleFiles: TArray<TFileTodos>;
begin
  Result := [TFileTodos.Create('Kasse.pas', TTodoScanner.ForText(cKasseText)),
    TFileTodos.Create('Src/Lager.pas', TTodoScanner.ForText(cLagerText)),
    TFileTodos.Create('Erledigt.pas', TTodoScanner.ForText('{ DONE fertig }'))];
end;

{ TTodoReportTests }

procedure TTodoReportTests.SummarizesOpenDoneAndKeywords;
var
  mSummary: TTodoSummary;
begin
  mSummary := TTodoReport.Summarize(SampleFiles);
  Assert.AreEqual(2, mSummary.Files, 'Erledigt.pas hat nur Erledigtes');
  Assert.AreEqual(4, mSummary.Open);
  Assert.AreEqual(2, mSummary.Done);
  Assert.AreEqual(2, Integer(Length(mSummary.Keywords)));
  Assert.AreEqual('FIXME', mSummary.Keywords[0]);
  Assert.AreEqual(1, mSummary.KeywordCounts[0]);
  Assert.AreEqual('TODO', mSummary.Keywords[1]);
  Assert.AreEqual(3, mSummary.CountOf('todo'));
  Assert.AreEqual(0, mSummary.CountOf('HACK'));
  mSummary := TTodoReport.Summarize(nil);
  Assert.AreEqual(0, mSummary.Open);
  Assert.AreEqual(0, Integer(Length(mSummary.Keywords)));
end;

procedure TTodoReportTests.SummaryJson;
begin
  Assert.AreEqual('{"files": 2, "open": 4, "done": 2, "keywords": {"FIXME": 1, "TODO": 3}}',
    TTodoReport.SummaryJson(TTodoReport.Summarize(SampleFiles)));
  Assert.AreEqual('{"files": 0, "open": 0, "done": 0, "keywords": {}}',
    TTodoReport.SummaryJson(TTodoReport.Summarize(nil)));
end;

procedure TTodoReportTests.JsonHasLinesFromOne;
var
  mText: string;
begin
  mText := TTodoReport.Json(SampleFiles, 'C:\P');
  Assert.Contains(mText, '{"format": 1, "root": "C:\\P", "summary": {"files": 2');
  Assert.Contains(mText, '{"file": "Src/Lager.pas", "unit": "Lager", "todos": [{"keyword": "TODO", "done": false, ' +
    '"priority": 0, "owner": "Marco", "category": "GUI", "text": "\"Menü\"", "line": 2, "character": 1, ' +
    '"endLine": 2}]}');
  Assert.Contains(mText, '"keyword": "DONE", "done": true, "priority": 1');
  Assert.DoesNotContain(TTodoReport.Json(SampleFiles), '"root"');
end;

procedure TTodoReportTests.MarkdownGroupsByCategoryOwnerAndUnit;
var
  mText: string;
begin
  mText := TTodoReport.Markdown(TTodoScanner.Filter(SampleFiles, TTodoFilter.Default), 'Kasse');
  Assert.StartsWith('# TODOs: Kasse', mText);
  Assert.Contains(mText, '4 offene Einträge in 2 Dateien (FIXME 1, TODO 3).');
  Assert.Contains(mText, '## Nach Kategorie'#13#10#13#10'| Kategorie | Einträge |'#13#10'|---|---:|'#13#10 +
    '| (ohne) | 2 |'#13#10'| GUI | 2 |');
  Assert.Contains(mText, '## Nach Person');
  Assert.Contains(mText, '| Marco | 2 |');
  Assert.Contains(mText, '## Kasse (3)');
  Assert.Contains(mText, '`Kasse.pas`');
  Assert.Contains(mText, '| 3 | FIXME |  |  |  | Rabatt \| doppelt |');
  Assert.Contains(mText, '| 4 | TODO | 2 | GUI | Marco | Fokus setzen |');
  Assert.DoesNotContain(mText, 'Index angelegt');
  mText := TTodoReport.Markdown(SampleFiles, '');
  Assert.StartsWith('# TODOs'#13#10, mText);
  Assert.Contains(mText, ', 2 erledigt');
  Assert.Contains(mText, '| DONE (erledigt) | 1 | Daten | Anna | Index angelegt |');
end;

procedure TTodoReportTests.MarkdownWithoutEntries;
var
  mText: string;
begin
  mText := TTodoReport.Markdown(nil, 'Leer');
  Assert.Contains(mText, '0 offene Einträge in 0 Dateien.');
  Assert.Contains(mText, 'Keine Einträge.');
  // Nur Einträge ohne Kategorie: keine Tabelle „Nach Kategorie“.
  Assert.DoesNotContain(TTodoReport.Markdown([TFileTodos.Create('A.pas', TTodoScanner.ForText('// TODO a'))], ''),
    'Nach Kategorie');
end;

procedure TTodoReportTests.CaptionShowsDetails;
var
  mEntries: TArray<TTodoEntry>;
begin
  mEntries := TTodoScanner.ForText(cKasseText);
  Assert.AreEqual('TODO: Rundung prüfen', TTodoReport.Caption(mEntries[0]));
  Assert.AreEqual('TODO 2 [GUI, Marco]: Fokus setzen', TTodoReport.Caption(mEntries[2]));
  Assert.AreEqual('FIXME', TTodoReport.Caption(TTodoScanner.ForText('// FIXME')[0]));
  Assert.AreEqual('TODO [Marco]: x', TTodoReport.Caption(TTodoScanner.ForText('// TODO -oMarco : x')[0]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTodoReportTests);

end.
