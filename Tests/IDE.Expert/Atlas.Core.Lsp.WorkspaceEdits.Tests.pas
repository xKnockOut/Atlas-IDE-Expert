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
    [Test]
    procedure PrefersDocumentChangesAndCountsFileOperations;
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
  Atlas.Core.Lsp.TextChanges,
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
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TLspWorkspaceEdit.FromJson(Value);
  finally
    Value.Free;
  end;
end;

procedure TLspWorkspaceEditTests.ReadsChangesPerFile;
var
  Edit: TLspWorkspaceEdit;
begin
  Edit := Parse('{"changes":{' +
    '"file:///c%3A/p/a.pas":[{"range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}},"newText":"Neu"},' +
    '{"range":{"start":{"line":4,"character":0},"end":{"line":4,"character":3}},"newText":"Neu"}],' +
    '"file:///c%3A/p/b.pas":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":""}],' +
    '"file:///c%3A/p/leer.pas":[]}}');
  Assert.AreEqual(2, Integer(Length(Edit.Files)), 'Datei ohne Änderungen entfällt');
  Assert.AreEqual('c:\p\a.pas', Edit.Files[0].FileName);
  Assert.AreEqual(2, Integer(Length(Edit.Files[0].Edits)));
  Assert.AreEqual(1, Edit.Files[0].Edits[0].StartPos.Line);
  Assert.AreEqual(5, Edit.Files[0].Edits[0].EndPos.Character);
  Assert.AreEqual('Neu', Edit.Files[0].Edits[1].NewText);
  Assert.AreEqual(3, Edit.EditCount);
  Assert.IsFalse(Edit.IsEmpty);
  Assert.AreEqual(0, Edit.Unsupported);
  Assert.IsTrue(Parse('null').IsEmpty);
  Assert.IsTrue(Parse('{"changes":{}}').IsEmpty);
end;

procedure TLspWorkspaceEditTests.PrefersDocumentChangesAndCountsFileOperations;
var
  Edit: TLspWorkspaceEdit;
begin
  Edit := Parse('{"changes":{"file:///c%3A/p/x.pas":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":0}},"newText":"x"}]},' +
    '"documentChanges":[' +
    '{"textDocument":{"uri":"file:///c%3A/p/a.pas","version":3},"edits":[{"range":{"start":{"line":0,"character":0},' +
    '"end":{"line":0,"character":1}},"newText":"b","annotationId":"r"}]},' +
    '{"kind":"rename","oldUri":"file:///c%3A/p/a.pas","newUri":"file:///c%3A/p/b.pas"},' +
    '{"kind":"create","uri":"file:///c%3A/p/c.pas"}]}');
  Assert.AreEqual(1, Integer(Length(Edit.Files)));
  Assert.AreEqual('c:\p\a.pas', Edit.Files[0].FileName);
  Assert.AreEqual('b', Edit.Files[0].Edits[0].NewText);
  Assert.AreEqual(2, Edit.Unsupported);
end;

procedure TLspWorkspaceEditTests.AppliesSeveralEditsAgainstTheOriginalText;
const
  Text = 'unit Alt;'#13#10'uses Alt2;'#13#10'var X: TAlt;';
begin
  // Unsortiert und mit Längenänderung: Alle Positionen beziehen sich auf den Ausgangstext.
  Assert.AreEqual('unit Neuer;'#13#10'uses Alt2;'#13#10'var X: TNeuer;',
    TLspEdits.Apply(Text, [E(2, 8, 2, 11, 'Neuer'), E(0, 5, 0, 8, 'Neuer')]));
  // Zeichen hinter dem Zeilenende zählen als Zeilenende (wie im LSP).
  Assert.AreEqual('unit Alt;!'#13#10'uses Alt2;'#13#10'var X: TAlt;',
    TLspEdits.Apply(Text, [E(0, 99, 0, 99, '!')]));
  Assert.AreEqual(Text, TLspEdits.Apply(Text, []));
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
