unit Atlas.Core.Projects.Todos.Tests;

// Tests der TODO-Liste des Plugins (#68): Antwort von atlas.server.todos
// (Modus json) als Einträge des Ergebnisfensters.

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
  end;

implementation

uses
  System.SysUtils,
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasTodoListTests);

end.
