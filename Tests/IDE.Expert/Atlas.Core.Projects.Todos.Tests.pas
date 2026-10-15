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
  Atlas.Core.Results.Model,
  Atlas.Core.Projects.Todos;

const
  Answer = '{"format": 1, "root": "C:\\Projekte\\Kasse", "summary": {"files": 2, "open": 3, "done": 0, ' +
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
  Entries: TArray<TAtlasResultEntry>;
begin
  Assert.IsTrue(TAtlasTodoList.Entries(Answer, Entries));
  Assert.AreEqual(3, Integer(Length(Entries)));
  Assert.AreEqual('C:\Projekte\Kasse\Source\Main.pas', Entries[0].FileName);
  Assert.AreEqual(11, Entries[0].Line);
  Assert.AreEqual(2, Entries[0].Character);
  Assert.AreEqual('TODO 2 [GUI, Marco]: Fokus setzen', Entries[0].Text);
  Assert.AreEqual('FIXME: Rabatt', Entries[1].Text);
  Assert.AreEqual(19, Entries[1].Line);
  Assert.AreEqual('D:\Lib\Hilfe.pas', Entries[2].FileName);
  Assert.AreEqual('TODO', Entries[2].Text);
  // Das Ergebnisfenster gruppiert nach Datei (Unit).
  Assert.AreEqual(2, Integer(Length(TAtlasResults.Group(Entries))));
end;

procedure TAtlasTodoListTests.EmptyAnswerIsValid;
var
  Entries: TArray<TAtlasResultEntry>;
begin
  Assert.IsTrue(TAtlasTodoList.Entries('{"format": 1, "root": "C:\\P", "summary": {}, "files": []}', Entries));
  Assert.AreEqual(0, Integer(Length(Entries)));
end;

procedure TAtlasTodoListTests.RejectsInvalidAnswer;
var
  Entries: TArray<TAtlasResultEntry>;
begin
  Assert.IsFalse(TAtlasTodoList.Entries('', Entries));
  Assert.IsFalse(TAtlasTodoList.Entries('"# TODOs"', Entries));
  Assert.IsFalse(TAtlasTodoList.Entries('{"format": 1, "summary": {"open": 1}}', Entries));
  Assert.AreEqual(0, Integer(Length(Entries)));
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
  Filter: TAtlasTodoFilter;
  Value: TJSONValue;
begin
  Filter := Default(TAtlasTodoFilter);
  Assert.IsTrue(Filter.IsEmpty);
  Assert.AreEqual('{}', Filter.ToJson);
  Filter.Category := ' GUI ';
  Filter.Owner := 'Marco "M"';
  Filter.IncludeDone := True;
  Assert.IsFalse(Filter.IsEmpty);
  Assert.AreEqual('{"category": "GUI", "owner": "Marco \"M\"", "includeDone": true}', Filter.ToJson);
  // Gültiges JSON, das der Server versteht.
  Value := TJSONObject.ParseJSONValue(Filter.ToJson);
  try
    Assert.IsTrue(Value is TJSONObject);
    Assert.AreEqual('Marco "M"', TJSONObject(Value).GetValue('owner').Value);
  finally
    Value.Free;
  end;
  Filter := Default(TAtlasTodoFilter);
  Filter.UnitName := 'Main';
  Filter.Keyword := 'fixme';
  Assert.AreEqual('{"unit": "Main", "keyword": "fixme"}', Filter.ToJson);
  Filter := Default(TAtlasTodoFilter);
  Filter.IncludeDone := True;
  Assert.IsFalse(Filter.IsEmpty, 'nur „Erledigte zeigen“ ist auch ein Filter');
  Filter := Default(TAtlasTodoFilter);
  Filter.Owner := '   ';
  Assert.IsTrue(Filter.IsEmpty, 'nur Leerraum filtert nicht');
end;

procedure TAtlasTodoListTests.FilterDescription;
var
  Filter: TAtlasTodoFilter;
begin
  Filter := Default(TAtlasTodoFilter);
  Assert.AreEqual('', Filter.Describe);
  Filter.Category := 'GUI';
  Filter.Owner := 'Marco';
  Filter.UnitName := 'Main';
  Filter.Keyword := 'fixme';
  Filter.IncludeDone := True;
  Assert.AreEqual('-cGUI, -oMarco, Main, FIXME, DONE', Filter.Describe);
  Filter := Default(TAtlasTodoFilter);
  Filter.Owner := ' Anna ';
  Assert.AreEqual('-oAnna', Filter.Describe);
end;

procedure TAtlasTodoListTests.ChoicesFromAnswer;
const
  WithDone = '{"format": 1, "root": "C:\\P", "files": [' +
    '{"file": "A.pas", "unit": "A", "todos": [' +
    '{"keyword": "TODO", "done": false, "owner": "marco", "category": "GUI", "text": "x"}, ' +
    '{"keyword": "DONE", "done": true, "owner": "Anna", "category": "", "text": "y"}, ' +
    '{"keyword": "hack", "done": false, "owner": "Marco", "category": "Export", "text": "z"}]}, ' +
    '{"file": "B.pas", "unit": "B", "todos": []}]}';
var
  Choices: TAtlasTodoChoices;
begin
  Assert.IsTrue(TAtlasTodoList.Choices(Answer, Choices));
  Assert.AreEqual('GUI', string.Join(',', Choices.Categories));
  Assert.AreEqual('Marco', string.Join(',', Choices.Owners));
  Assert.AreEqual('Hilfe,Main', string.Join(',', Choices.Units));
  Assert.AreEqual('FIXME,TODO', string.Join(',', Choices.Keywords));
  Assert.IsTrue(TAtlasTodoList.Choices(WithDone, Choices));
  Assert.AreEqual('Export,GUI', string.Join(',', Choices.Categories));
  // Groß-/Kleinschreibung egal: der erste Treffer bleibt.
  Assert.AreEqual('Anna,marco', string.Join(',', Choices.Owners));
  Assert.AreEqual('A,B', string.Join(',', Choices.Units), 'auch Units ohne Einträge');
  Assert.AreEqual('HACK,TODO', string.Join(',', Choices.Keywords), 'DONE ist keine Marke zum Filtern');
end;

procedure TAtlasTodoListTests.ChoicesRejectInvalidAnswer;
var
  Choices: TAtlasTodoChoices;
begin
  Assert.IsFalse(TAtlasTodoList.Choices('', Choices));
  Assert.IsFalse(TAtlasTodoList.Choices('{"summary": {}}', Choices));
  Assert.AreEqual(0, Integer(Length(Choices.Units)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTodoListTests);

end.
