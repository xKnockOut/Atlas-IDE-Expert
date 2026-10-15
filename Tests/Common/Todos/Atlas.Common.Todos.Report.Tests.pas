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
  KasseText = 'unit Kasse;'#10 +
    '// TODO Rundung prüfen'#10 +
    '// FIXME: Rabatt | doppelt'#10 +
    '{ TODO 2 -oMarco -cGUI : Fokus setzen }'#10 +
    '{ DONE 1 -oAnna -cDaten : Index angelegt }'#10 +
    'end.';
  LagerText = 'unit Lager;'#10'{ TODO -oMarco -cGUI : "Menü" }'#10'end.';

function SampleFiles: TArray<TFileTodos>;
begin
  Result := [TFileTodos.Create('Kasse.pas', TTodoScanner.ForText(KasseText)),
    TFileTodos.Create('Src/Lager.pas', TTodoScanner.ForText(LagerText)),
    TFileTodos.Create('Erledigt.pas', TTodoScanner.ForText('{ DONE fertig }'))];
end;

{ TTodoReportTests }

procedure TTodoReportTests.SummarizesOpenDoneAndKeywords;
var
  Summary: TTodoSummary;
begin
  Summary := TTodoReport.Summarize(SampleFiles);
  Assert.AreEqual(2, Summary.Files, 'Erledigt.pas hat nur Erledigtes');
  Assert.AreEqual(4, Summary.Open);
  Assert.AreEqual(2, Summary.Done);
  Assert.AreEqual(2, Integer(Length(Summary.Keywords)));
  Assert.AreEqual('FIXME', Summary.Keywords[0]);
  Assert.AreEqual(1, Summary.KeywordCounts[0]);
  Assert.AreEqual('TODO', Summary.Keywords[1]);
  Assert.AreEqual(3, Summary.CountOf('todo'));
  Assert.AreEqual(0, Summary.CountOf('HACK'));
  Summary := TTodoReport.Summarize(nil);
  Assert.AreEqual(0, Summary.Open);
  Assert.AreEqual(0, Integer(Length(Summary.Keywords)));
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
  Text: string;
begin
  Text := TTodoReport.Json(SampleFiles, 'C:\P');
  Assert.Contains(Text, '{"format": 1, "root": "C:\\P", "summary": {"files": 2');
  Assert.Contains(Text, '{"file": "Src/Lager.pas", "unit": "Lager", "todos": [{"keyword": "TODO", "done": false, ' +
    '"priority": 0, "owner": "Marco", "category": "GUI", "text": "\"Menü\"", "line": 2, "character": 1, ' +
    '"endLine": 2}]}');
  Assert.Contains(Text, '"keyword": "DONE", "done": true, "priority": 1');
  Assert.DoesNotContain(TTodoReport.Json(SampleFiles), '"root"');
end;

procedure TTodoReportTests.MarkdownGroupsByCategoryOwnerAndUnit;
var
  Text: string;
begin
  Text := TTodoReport.Markdown(TTodoScanner.Filter(SampleFiles, TTodoFilter.Default), 'Kasse');
  Assert.StartsWith('# TODOs: Kasse', Text);
  Assert.Contains(Text, '4 offene Einträge in 2 Dateien (FIXME 1, TODO 3).');
  Assert.Contains(Text, '## Nach Kategorie'#13#10#13#10'| Kategorie | Einträge |'#13#10'|---|---:|'#13#10 +
    '| (ohne) | 2 |'#13#10'| GUI | 2 |');
  Assert.Contains(Text, '## Nach Person');
  Assert.Contains(Text, '| Marco | 2 |');
  Assert.Contains(Text, '## Kasse (3)');
  Assert.Contains(Text, '`Kasse.pas`');
  Assert.Contains(Text, '| 3 | FIXME |  |  |  | Rabatt \| doppelt |');
  Assert.Contains(Text, '| 4 | TODO | 2 | GUI | Marco | Fokus setzen |');
  Assert.DoesNotContain(Text, 'Index angelegt');
  Text := TTodoReport.Markdown(SampleFiles, '');
  Assert.StartsWith('# TODOs'#13#10, Text);
  Assert.Contains(Text, ', 2 erledigt');
  Assert.Contains(Text, '| DONE (erledigt) | 1 | Daten | Anna | Index angelegt |');
end;

procedure TTodoReportTests.MarkdownWithoutEntries;
var
  Text: string;
begin
  Text := TTodoReport.Markdown(nil, 'Leer');
  Assert.Contains(Text, '0 offene Einträge in 0 Dateien.');
  Assert.Contains(Text, 'Keine Einträge.');
  // Nur Einträge ohne Kategorie: keine Tabelle „Nach Kategorie“.
  Assert.DoesNotContain(TTodoReport.Markdown([TFileTodos.Create('A.pas', TTodoScanner.ForText('// TODO a'))], ''),
    'Nach Kategorie');
end;

procedure TTodoReportTests.CaptionShowsDetails;
var
  Entries: TArray<TTodoEntry>;
begin
  Entries := TTodoScanner.ForText(KasseText);
  Assert.AreEqual('TODO: Rundung prüfen', TTodoReport.Caption(Entries[0]));
  Assert.AreEqual('TODO 2 [GUI, Marco]: Fokus setzen', TTodoReport.Caption(Entries[2]));
  Assert.AreEqual('FIXME', TTodoReport.Caption(TTodoScanner.ForText('// FIXME')[0]));
  Assert.AreEqual('TODO [Marco]: x', TTodoReport.Caption(TTodoScanner.ForText('// TODO -oMarco : x')[0]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTodoReportTests);

end.
