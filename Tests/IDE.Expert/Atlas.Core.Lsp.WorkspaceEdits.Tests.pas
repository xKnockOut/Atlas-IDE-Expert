unit Atlas.Core.Lsp.WorkspaceEdits.Tests;

// Tests für WorkspaceEdits des Servers (#397).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspWorkspaceEditTests = class
  public
    [Test]
    procedure ReadsChangesPerFile;
    /// <summary>atlasUnchanged der Umbenennen-Antwort (#1119).</summary>
    [Test]
    procedure ReadsUnchangedPlaces;
    [Test]
    procedure PrefersDocumentChangesAndReadsFileOperations;
    [Test]
    procedure ReadsFileOperationOptionsAndCountsUnknown;
    [Test]
    procedure DropsEditsOfOwnProject;
    [Test]
    procedure AppliesSeveralEditsAgainstTheOriginalText;
    [Test]
    procedure InsertsAtTheSamePositionInListOrder;
    [Test]
    procedure RejectsOverlappingAndOutOfRangeEdits;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.WorkspaceEdits;

function E(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer; const ANewText: string): TLspTextEdit;
begin
  Result.StartPos.Line := AStartLine;
  Result.StartPos.Character := AStartCharacter;
  Result.EndPos.Line := AEndLine;
  Result.EndPos.Character := AEndCharacter;
  Result.NewText := ANewText;
end;

function Parse(const AJson: string): TLspWorkspaceEdit;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TLspWorkspaceEdit.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TLspWorkspaceEditTests.ReadsChangesPerFile;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := Parse('{"changes":{' +
    '"file:///c%3A/p/a.pas":[{"range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}},"newText":"Neu"},' +
    '{"range":{"start":{"line":4,"character":0},"end":{"line":4,"character":3}},"newText":"Neu"}],' +
    '"file:///c%3A/p/b.pas":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":""}],' +
    '"file:///c%3A/p/leer.pas":[]}}');
  Assert.AreEqual(2, Integer(Length(mEdit.Files)), 'Datei ohne Änderungen entfällt');
  Assert.AreEqual('c:\p\a.pas', mEdit.Files[0].FileName);
  Assert.AreEqual(2, Integer(Length(mEdit.Files[0].Edits)));
  Assert.AreEqual(1, mEdit.Files[0].Edits[0].StartPos.Line);
  Assert.AreEqual(5, mEdit.Files[0].Edits[0].EndPos.Character);
  Assert.AreEqual('Neu', mEdit.Files[0].Edits[1].NewText);
  Assert.AreEqual(3, mEdit.EditCount);
  Assert.IsFalse(mEdit.IsEmpty);
  Assert.AreEqual(0, mEdit.Unsupported);
  Assert.IsTrue(Parse('null').IsEmpty);
  Assert.IsTrue(Parse('{"changes":{}}').IsEmpty);
end;

procedure TLspWorkspaceEditTests.ReadsUnchangedPlaces;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := Parse('{"changes":{"file:///c%3A/p/a.pas":[{"range":{"start":{"line":1,"character":2},' +
    '"end":{"line":1,"character":5}},"newText":"Neu"}]},"atlasUnchanged":[{"uri":"file:///c%3A/p/b.pas",' +
    '"range":{"start":{"line":7,"character":4},"end":{"line":7,"character":7}},' +
    '"atlasConfidence":{"level":"inferred","reason":"virtual","detail":"Aufruf von T.M"}},{"range":{}}]}');
  Assert.AreEqual(1, mEdit.EditCount);
  Assert.AreEqual(1, Integer(Length(mEdit.Unchanged)), 'Eintrag ohne uri entfällt');
  Assert.AreEqual('c:\p\b.pas', mEdit.Unchanged[0].FileName);
  Assert.AreEqual(7, mEdit.Unchanged[0].Line);
  Assert.AreEqual(4, mEdit.Unchanged[0].Character);
  Assert.AreEqual('virtual', mEdit.Unchanged[0].Confidence.Reason);
  Assert.AreEqual(0, Integer(Length(Parse('{"changes":{}}').Unchanged)));
end;

procedure TLspWorkspaceEditTests.PrefersDocumentChangesAndReadsFileOperations;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := Parse('{"changes":{"file:///c%3A/p/x.pas":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":0}},"newText":"x"}]},' +
    '"documentChanges":[' +
    '{"textDocument":{"uri":"file:///c%3A/p/a.pas","version":3},"edits":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":1}},"newText":"b","annotationId":"r"}]},' +
    '{"kind":"rename","oldUri":"file:///c%3A/p/a.pas","newUri":"file:///c%3A/p/b.pas"},' +
    '{"kind":"create","uri":"file:///c%3A/p/c.pas"}]}');
  Assert.AreEqual(1, Integer(Length(mEdit.Files)));
  Assert.AreEqual('c:\p\a.pas', mEdit.Files[0].FileName);
  Assert.AreEqual('b', mEdit.Files[0].Edits[0].NewText);
  // #721: Dateioperationen in der Reihenfolge des Servers.
  Assert.AreEqual(0, mEdit.Unsupported);
  Assert.AreEqual(2, Integer(Length(mEdit.Operations)));
  Assert.AreEqual<TLspFileOperationKind>(TLspFileOperationKind.Rename, mEdit.Operations[0].Kind);
  Assert.AreEqual('c:\p\a.pas', mEdit.Operations[0].FileName);
  Assert.AreEqual('c:\p\b.pas', mEdit.Operations[0].NewFileName);
  Assert.AreEqual<TLspFileOperationKind>(TLspFileOperationKind.Create, mEdit.Operations[1].Kind);
  Assert.AreEqual('c:\p\c.pas', mEdit.Operations[1].FileName);
  Assert.IsFalse(mEdit.IsEmpty);
end;

procedure TLspWorkspaceEditTests.ReadsFileOperationOptionsAndCountsUnknown;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := Parse('{"documentChanges":[' +
    '{"kind":"create","uri":"file:///c%3A/p/c.pas","options":{"overwrite":true,"ignoreIfExists":true}},' +
    '{"kind":"delete","uri":"file:///c%3A/p/d.pas","options":{"ignoreIfNotExists":true,"recursive":true}},' +
    '{"kind":"rename","oldUri":"file:///c%3A/p/e.pas","newUri":"file:///c%3A/p/f.pas",' +
    '"options":{"ignoreIfExists":true}},' +
    '{"kind":"copy","uri":"file:///c%3A/p/g.pas"},' +
    '{"kind":"rename","oldUri":"file:///c%3A/p/h.pas"},' +
    '{"kind":"delete"}]}');
  Assert.AreEqual(3, Integer(Length(mEdit.Operations)));
  Assert.AreEqual(3, mEdit.Unsupported);
  // overwrite gewinnt über ignoreIfExists.
  Assert.IsTrue(mEdit.Operations[0].Overwrite);
  Assert.IsFalse(mEdit.Operations[0].IgnoreIfExists);
  Assert.AreEqual<TLspFileOperationKind>(TLspFileOperationKind.Delete, mEdit.Operations[1].Kind);
  Assert.IsTrue(mEdit.Operations[1].IgnoreIfNotExists);
  Assert.IsTrue(mEdit.Operations[1].Recursive);
  Assert.IsTrue(mEdit.Operations[2].IgnoreIfExists);
  Assert.IsFalse(mEdit.Operations[2].Overwrite);
  Assert.AreEqual(0, mEdit.EditCount);
  Assert.IsFalse(mEdit.IsEmpty);
end;

procedure TLspWorkspaceEditTests.DropsEditsOfOwnProject;
const
  cInsert = '"edits":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"x"}]}';
var
  mEdit, mRest: TLspWorkspaceEdit;
begin
  // Neue Testunit (#274): .dpr und .dproj des Testprojekts trägt die IDE selbst ein, wenn es geladen ist.
  mEdit := Parse('{"documentChanges":[' +
    '{"kind":"create","uri":"file:///c%3A/p/tests/k.tests.pas"},' +
    '{"textDocument":{"uri":"file:///c%3A/p/tests/k.tests.pas","version":null},' + cInsert + ',' +
    '{"textDocument":{"uri":"file:///c%3A/p/tests/tests.dpr","version":null},' + cInsert + ',' +
    '{"textDocument":{"uri":"file:///c%3A/p/tests/tests.dproj","version":null},' + cInsert + ']}');
  Assert.AreEqual('c:\p\tests\tests.dproj', mEdit.ProjectFile);
  mRest := mEdit.WithoutProject(mEdit.ProjectFile);
  Assert.AreEqual(1, Integer(Length(mRest.Files)));
  Assert.AreEqual('c:\p\tests\k.tests.pas', mRest.Files[0].FileName);
  Assert.AreEqual(1, Integer(Length(mRest.Operations)));
  Assert.AreEqual('', Parse('{"changes":{}}').ProjectFile);
end;

procedure TLspWorkspaceEditTests.AppliesSeveralEditsAgainstTheOriginalText;
const
  cText = 'unit Alt;'#13#10'uses Alt2;'#13#10'var X: TAlt;';
begin
  // Unsortiert und mit Längenänderung: Alle Positionen beziehen sich auf den Ausgangstext.
  Assert.AreEqual('unit Neuer;'#13#10'uses Alt2;'#13#10'var X: TNeuer;',
    TLspEdits.Apply(cText, [E(2, 8, 2, 11, 'Neuer'), E(0, 5, 0, 8, 'Neuer')]));
  // Zeichen hinter dem Zeilenende zählen als Zeilenende (wie im LSP).
  Assert.AreEqual('unit Alt;!'#13#10'uses Alt2;'#13#10'var X: TAlt;',
    TLspEdits.Apply(cText, [E(0, 99, 0, 99, '!')]));
  Assert.AreEqual(cText, TLspEdits.Apply(cText, []));
end;

procedure TLspWorkspaceEditTests.InsertsAtTheSamePositionInListOrder;
begin
  Assert.AreEqual('abXYc', TLspEdits.Apply('abc', [E(0, 2, 0, 2, 'X'), E(0, 2, 0, 2, 'Y')]));
  // Einfügen und Ersetzen ab derselben Stelle.
  Assert.AreEqual('aXZ', TLspEdits.Apply('abc', [E(0, 1, 0, 1, 'X'), E(0, 1, 0, 3, 'Z')]));
end;

procedure TLspWorkspaceEditTests.RejectsOverlappingAndOutOfRangeEdits;
begin
  Assert.WillRaise(
    procedure
    begin
      TLspEdits.Apply('abcdef', [E(0, 1, 0, 4, 'x'), E(0, 3, 0, 5, 'y')]);
    end, ELspEditError);
  Assert.WillRaise(
    procedure
    begin
      TLspEdits.Apply('abc'#13#10'def', [E(5, 0, 5, 1, 'x')]);
    end, ELspEditError);
  Assert.WillRaise(
    procedure
    begin
      TLspEdits.Apply('abc', [E(0, 2, 0, 1, 'x')]);
    end, ELspEditError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkspaceEditTests);

end.
