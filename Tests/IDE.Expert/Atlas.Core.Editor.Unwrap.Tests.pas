unit Atlas.Core.Editor.Unwrap.Tests;

// Tests für „Umschließung entfernen“ im Plugin (#657): Argumente, Einträge
// aus der Antwort (je Variante einer, Konstrukt ohne Variante mit Hinweis),
// Wegfall der Liste bei nur einem Eintrag, Weiterschalten, Stücke der
// Vorschau und das WorkspaceEdit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUnwrapTests = class
  public
    [Test]
    procedure ArgumentsCarryPositionAndIndent;
    [Test]
    procedure EntriesPerVariant;
    [Test]
    procedure ForeignAnswerGivesNothing;
    [Test]
    procedure SingleEntrySkipsList;
    [Test]
    procedure NextAvailableSkipsUnavailable;
    [Test]
    procedure SpansOnLine;
    [Test]
    procedure EditForFile;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.Unwrap;

const
  Answer =
    '{"candidates":[' +
    '{"kind":"tryFinally","range":{"start":{"line":5,"character":2},"end":{"line":9,"character":5}},' +
    '"note":"","noteText":"","variants":[' +
    '{"kind":"keepFinally","branch":0,"edits":[{"range":{"start":{"line":5,"character":0},' +
    '"end":{"line":10,"character":0}},"newText":"  X;\r\n  Y;\r\n"}],' +
    '"keep":[{"start":{"line":6,"character":4},"end":{"line":6,"character":6}},' +
    '{"start":{"line":8,"character":4},"end":{"line":8,"character":6}}],' +
    '"remove":[{"start":{"line":5,"character":2},"end":{"line":5,"character":5}},' +
    '{"start":{"line":7,"character":2},"end":{"line":7,"character":9}},' +
    '{"start":{"line":9,"character":2},"end":{"line":9,"character":5}}]},' +
    '{"kind":"dropFinally","branch":0,"edits":[{"range":{"start":{"line":5,"character":0},' +
    '"end":{"line":10,"character":0}},"newText":"  X;\r\n"}],"keep":[],"remove":[]}]},' +
    '{"kind":"withDo","range":{"start":{"line":3,"character":2},"end":{"line":11,"character":5}},' +
    '"note":"withUnresolved","noteText":"Caption ist nicht eindeutig","variants":[]}]}';

function Entries: TArray<TAtlasUnwrapEntry>;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Result := TAtlasUnwrap.ReadEntries(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasUnwrapTests.ArgumentsCarryPositionAndIndent;
begin
  Assert.AreEqual('["file:///C:/a.pas",{"line":4,"character":7},2]',
    TAtlasUnwrap.Arguments('file:///C:/a.pas', 4, 7, 2));
end;

procedure TAtlasUnwrapTests.EntriesPerVariant;
var
  List: TArray<TAtlasUnwrapEntry>;
begin
  List := Entries;
  Assert.AreEqual(3, Integer(Length(List)));
  Assert.AreEqual('tryFinally', List[0].Kind);
  Assert.AreEqual('keepFinally', List[0].VariantKind);
  Assert.AreEqual(2, List[0].VariantCount);
  Assert.AreEqual(5, List[0].Line);
  Assert.IsTrue(List[0].Available);
  Assert.AreEqual(2, Integer(Length(List[0].Keep)));
  Assert.AreEqual(3, Integer(Length(List[0].Remove)));
  Assert.AreEqual('  X;'#13#10'  Y;'#13#10, List[0].Edits[0].NewText);
  Assert.AreEqual('dropFinally', List[1].VariantKind);
  Assert.AreEqual('withDo', List[2].Kind);
  Assert.AreEqual('withUnresolved', List[2].Note);
  Assert.AreEqual('Caption ist nicht eindeutig', List[2].NoteText);
  Assert.IsFalse(List[2].Available);
  Assert.AreEqual(3, List[2].Line);
end;

procedure TAtlasUnwrapTests.ForeignAnswerGivesNothing;
var
  Value: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(nil))));
  Value := TJSONObject.ParseJSONValue('{"candidates":[]}');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(Value))));
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue('[1,2]');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(Value))));
  finally
    Value.Free;
  end;
end;

procedure TAtlasUnwrapTests.SingleEntrySkipsList;
var
  List: TArray<TAtlasUnwrapEntry>;
begin
  List := Entries;
  Assert.IsFalse(TAtlasUnwrap.SingleEntry(List));
  Assert.IsTrue(TAtlasUnwrap.SingleEntry([List[0]]));
  Assert.IsFalse(TAtlasUnwrap.SingleEntry([List[2]]), 'nicht übernehmbar: Liste mit Hinweis');
  Assert.IsFalse(TAtlasUnwrap.SingleEntry(nil));
end;

procedure TAtlasUnwrapTests.NextAvailableSkipsUnavailable;
var
  List: TArray<TAtlasUnwrapEntry>;
begin
  List := Entries;
  Assert.AreEqual(0, TAtlasUnwrap.NextAvailable(List, 0, 1));
  Assert.AreEqual(0, TAtlasUnwrap.NextAvailable(List, 2, 1), 'ringsum');
  Assert.AreEqual(1, TAtlasUnwrap.NextAvailable(List, 2, -1));
  Assert.AreEqual(-1, TAtlasUnwrap.NextAvailable([List[2]], 0, 1));
  Assert.AreEqual(-1, TAtlasUnwrap.NextAvailable(nil, 0, 1));
end;

procedure TAtlasUnwrapTests.SpansOnLine;
var
  List: TArray<TAtlasUnwrapEntry>;
  Spans: TArray<TAtlasUnwrapSpan>;
  First, Last: Integer;
begin
  List := Entries;
  Spans := TAtlasUnwrap.SpansOnLine(List[0], 6);
  Assert.AreEqual(1, Integer(Length(Spans)));
  Assert.IsTrue(Spans[0].Keep);
  Assert.AreEqual(4, Spans[0].Start);
  Assert.AreEqual(6, Spans[0].Stop);
  Spans := TAtlasUnwrap.SpansOnLine(List[0], 7);
  Assert.AreEqual(1, Integer(Length(Spans)));
  Assert.IsFalse(Spans[0].Keep);
  Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.SpansOnLine(List[0], 4))));
  Assert.IsTrue(TAtlasUnwrap.LineSpan(List[0], First, Last));
  Assert.AreEqual(5, First);
  Assert.AreEqual(9, Last);
  Assert.IsFalse(TAtlasUnwrap.LineSpan(List[1], First, Last));
end;

procedure TAtlasUnwrapTests.EditForFile;
var
  List: TArray<TAtlasUnwrapEntry>;
  Edit: TLspWorkspaceEdit;
begin
  List := Entries;
  Edit := TAtlasUnwrap.EditOf(List[0], 'C:\a.pas');
  Assert.AreEqual(1, Integer(Length(Edit.Files)));
  Assert.AreEqual('C:\a.pas', Edit.Files[0].FileName);
  Assert.AreEqual(1, Edit.EditCount);
  Assert.IsTrue(TAtlasUnwrap.EditOf(List[2], 'C:\a.pas').IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnwrapTests);

end.
