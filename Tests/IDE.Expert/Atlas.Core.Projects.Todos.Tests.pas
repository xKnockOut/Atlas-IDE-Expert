unit Atlas.Core.Projects.Todos.Tests;

// Tests der TODO-Liste des Plugins (#68): Antwort von atlas.server.todos
// (Modus json) als Einträge des Ergebnisfensters, Filter als Argument für
// den Server und Vorschläge für den Filterdialog.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTodoListTests = class
  public
    [Test]
    procedure EntriesWithAbsolutePathsAndZeroBasedPositions;
    [Test]
    procedure EmptyAnswerIsValid;
    [Test]
    procedure RejectsInvalidAnswer;
    [Test]
    procedure CaptionLeavesOutEmptyParts;
    [Test]
    procedure FullPathKeepsAbsolutePaths;
    [Test]
    procedure FilterAsServerArgument;
    [Test]
    procedure FilterDescription;
    [Test]
    procedure ChoicesFromAnswer;
    [Test]
    procedure ChoicesRejectInvalidAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Results.Model,
  Atlas.Core.Projects.Todos;

const
  cAnswer = '{"format": 1, "root": "C:\\Projekte\\Kasse", "summary": {"files": 2, "open": 3, "done": 0, ' +
    '"keywords": {"FIXME": 1, "TODO": 2}}, "files": [' +
    '{"file": "Source/Main.pas", "unit": "Main", "todos": [' +
    '{"keyword": "TODO", "done": false, "priority": 2, "owner": "Marco", "category": "GUI", ' +
    '"text": "Fokus setzen", "line": 12, "character": 3, "endLine": 12}, ' +
    '{"keyword": "FIXME", "done": false, "priority": 0, "owner": "", "category": "", ' +
    '"text": "Rabatt", "line": 20, "character": 1, "endLine": 20}]}, ' +
    '{"file": "D:\\Lib\\Hilfe.pas", "unit": "Hilfe", "todos": [' +
    '{"keyword": "TODO", "done": false, "priority": 0, "owner": "", "category": "", "text": "", "line": 1, ' +
    '"character": 1, "endLine": 1}]}]}';

{ TAtlasTodoListTests }

procedure TAtlasTodoListTests.EntriesWithAbsolutePathsAndZeroBasedPositions;
var
  mEntries: TArray<TAtlasResultEntry>;
begin
  Assert.IsTrue(TAtlasTodoList.Entries(cAnswer, mEntries));
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('C:\Projekte\Kasse\Source\Main.pas', mEntries[0].FileName);
  Assert.AreEqual(11, mEntries[0].Line);
  Assert.AreEqual(2, mEntries[0].Character);
  Assert.AreEqual('TODO 2 [GUI, Marco]: Fokus setzen', mEntries[0].Text);
  Assert.AreEqual('FIXME: Rabatt', mEntries[1].Text);
  Assert.AreEqual(19, mEntries[1].Line);
  Assert.AreEqual('D:\Lib\Hilfe.pas', mEntries[2].FileName);
  Assert.AreEqual('TODO', mEntries[2].Text);
  // Das Ergebnisfenster gruppiert nach Datei (Unit).
  Assert.AreEqual(2, Integer(Length(TAtlasResults.Group(mEntries))));
end;

procedure TAtlasTodoListTests.EmptyAnswerIsValid;
var
  mEntries: TArray<TAtlasResultEntry>;
begin
  Assert.IsTrue(TAtlasTodoList.Entries('{"format": 1, "root": "C:\\P", "summary": {}, "files": []}', mEntries));
  Assert.AreEqual(0, Integer(Length(mEntries)));
end;

procedure TAtlasTodoListTests.RejectsInvalidAnswer;
var
  mEntries: TArray<TAtlasResultEntry>;
begin
  Assert.IsFalse(TAtlasTodoList.Entries('', mEntries));
  Assert.IsFalse(TAtlasTodoList.Entries('"# TODOs"', mEntries));
  Assert.IsFalse(TAtlasTodoList.Entries('{"format": 1, "summary": {"open": 1}}', mEntries));
  Assert.AreEqual(0, Integer(Length(mEntries)));
end;

procedure TAtlasTodoListTests.CaptionLeavesOutEmptyParts;
begin
  Assert.AreEqual('TODO 1 [GUI, Marco]: x', TAtlasTodoList.Caption('TODO', 1, 'GUI', 'Marco', 'x'));
  Assert.AreEqual('FIXME [Marco]: x', TAtlasTodoList.Caption('FIXME', 0, '', 'Marco', 'x'));
  Assert.AreEqual('TODO [GUI]', TAtlasTodoList.Caption('TODO', 0, 'GUI', '', ''));
  Assert.AreEqual('HACK', TAtlasTodoList.Caption('HACK', 0, '', '', ''));
end;

procedure TAtlasTodoListTests.FullPathKeepsAbsolutePaths;
begin
  Assert.AreEqual('C:\P\Source\A.pas', TAtlasTodoList.FullPath('C:\P', 'Source/A.pas'));
  Assert.AreEqual('C:\P\A.pas', TAtlasTodoList.FullPath('C:\P\', 'A.pas'));
  Assert.AreEqual('D:\Lib\B.pas', TAtlasTodoList.FullPath('C:\P', 'D:\Lib\B.pas'));
  Assert.AreEqual('\\server\share\C.pas', TAtlasTodoList.FullPath('C:\P', '\\server\share\C.pas'));
  Assert.AreEqual('Source\A.pas', TAtlasTodoList.FullPath('', 'Source/A.pas'));
end;

procedure TAtlasTodoListTests.FilterAsServerArgument;
var
  mFilter: TAtlasTodoFilter;
  mValue: TJSONValue;
begin
  mFilter := Default(TAtlasTodoFilter);
  Assert.IsTrue(mFilter.IsEmpty);
  Assert.AreEqual('{}', mFilter.ToJson);
  mFilter.Category := ' GUI ';
  mFilter.Owner := 'Marco "M"';
  mFilter.IncludeDone := True;
  Assert.IsFalse(mFilter.IsEmpty);
  Assert.AreEqual('{"category": "GUI", "owner": "Marco \"M\"", "includeDone": true}', mFilter.ToJson);
  // Gültiges JSON, das der Server versteht.
  mValue := TJSONObject.ParseJSONValue(mFilter.ToJson);
  try
    Assert.IsTrue(mValue is TJSONObject);
    Assert.AreEqual('Marco "M"', TJSONObject(mValue).GetValue('owner').Value);
  finally
    mValue.Free;
  end;
  mFilter := Default(TAtlasTodoFilter);
  mFilter.UnitName := 'Main';
  mFilter.Keyword := 'fixme';
  Assert.AreEqual('{"unit": "Main", "keyword": "fixme"}', mFilter.ToJson);
  mFilter := Default(TAtlasTodoFilter);
  mFilter.IncludeDone := True;
  Assert.IsFalse(mFilter.IsEmpty, 'nur „Erledigte zeigen“ ist auch ein Filter');
  mFilter := Default(TAtlasTodoFilter);
  mFilter.Owner := '   ';
  Assert.IsTrue(mFilter.IsEmpty, 'nur Leerraum filtert nicht');
end;

procedure TAtlasTodoListTests.FilterDescription;
var
  mFilter: TAtlasTodoFilter;
begin
  mFilter := Default(TAtlasTodoFilter);
  Assert.AreEqual('', mFilter.Describe);
  mFilter.Category := 'GUI';
  mFilter.Owner := 'Marco';
  mFilter.UnitName := 'Main';
  mFilter.Keyword := 'fixme';
  mFilter.IncludeDone := True;
  Assert.AreEqual('-cGUI, -oMarco, Main, FIXME, DONE', mFilter.Describe);
  mFilter := Default(TAtlasTodoFilter);
  mFilter.Owner := ' Anna ';
  Assert.AreEqual('-oAnna', mFilter.Describe);
end;

procedure TAtlasTodoListTests.ChoicesFromAnswer;
const
  cWithDone = '{"format": 1, "root": "C:\\P", "files": [' +
    '{"file": "A.pas", "unit": "A", "todos": [' +
    '{"keyword": "TODO", "done": false, "owner": "marco", "category": "GUI", "text": "x"}, ' +
    '{"keyword": "DONE", "done": true, "owner": "Anna", "category": "", "text": "y"}, ' +
    '{"keyword": "hack", "done": false, "owner": "Marco", "category": "Export", "text": "z"}]}, ' +
    '{"file": "B.pas", "unit": "B", "todos": []}]}';
var
  mChoices: TAtlasTodoChoices;
begin
  Assert.IsTrue(TAtlasTodoList.Choices(cAnswer, mChoices));
  Assert.AreEqual('GUI', string.Join(',', mChoices.Categories));
  Assert.AreEqual('Marco', string.Join(',', mChoices.Owners));
  Assert.AreEqual('Hilfe,Main', string.Join(',', mChoices.Units));
  Assert.AreEqual('FIXME,TODO', string.Join(',', mChoices.Keywords));
  Assert.IsTrue(TAtlasTodoList.Choices(cWithDone, mChoices));
  Assert.AreEqual('Export,GUI', string.Join(',', mChoices.Categories));
  // Groß-/Kleinschreibung egal: der erste Treffer bleibt.
  Assert.AreEqual('Anna,marco', string.Join(',', mChoices.Owners));
  Assert.AreEqual('A,B', string.Join(',', mChoices.Units), 'auch Units ohne Einträge');
  Assert.AreEqual('HACK,TODO', string.Join(',', mChoices.Keywords), 'DONE ist keine Marke zum Filtern');
end;

procedure TAtlasTodoListTests.ChoicesRejectInvalidAnswer;
var
  mChoices: TAtlasTodoChoices;
begin
  Assert.IsFalse(TAtlasTodoList.Choices('', mChoices));
  Assert.IsFalse(TAtlasTodoList.Choices('{"summary": {}}', mChoices));
  Assert.AreEqual(0, Integer(Length(mChoices.Units)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTodoListTests);

end.
