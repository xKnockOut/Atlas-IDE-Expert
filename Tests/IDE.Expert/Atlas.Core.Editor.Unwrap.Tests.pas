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
  cAnswer =
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
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    Result := TAtlasUnwrap.ReadEntries(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasUnwrapTests.ArgumentsCarryPositionAndIndent;
begin
  Assert.AreEqual('["file:///C:/a.pas",{"line":4,"character":7},2]',
    TAtlasUnwrap.Arguments('file:///C:/a.pas', 4, 7, 2));
end;

procedure TAtlasUnwrapTests.EntriesPerVariant;
var
  mList: TArray<TAtlasUnwrapEntry>;
begin
  mList := Entries;
  Assert.AreEqual(3, Integer(Length(mList)));
  Assert.AreEqual('tryFinally', mList[0].Kind);
  Assert.AreEqual('keepFinally', mList[0].VariantKind);
  Assert.AreEqual(2, mList[0].VariantCount);
  Assert.AreEqual(5, mList[0].Line);
  Assert.IsTrue(mList[0].Available);
  Assert.AreEqual(2, Integer(Length(mList[0].Keep)));
  Assert.AreEqual(3, Integer(Length(mList[0].Remove)));
  Assert.AreEqual('  X;'#13#10'  Y;'#13#10, mList[0].Edits[0].NewText);
  Assert.AreEqual('dropFinally', mList[1].VariantKind);
  Assert.AreEqual('withDo', mList[2].Kind);
  Assert.AreEqual('withUnresolved', mList[2].Note);
  Assert.AreEqual('Caption ist nicht eindeutig', mList[2].NoteText);
  Assert.IsFalse(mList[2].Available);
  Assert.AreEqual(3, mList[2].Line);
end;

procedure TAtlasUnwrapTests.ForeignAnswerGivesNothing;
var
  mValue: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(nil))));
  mValue := TJSONObject.ParseJSONValue('{"candidates":[]}');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(mValue))));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue('[1,2]');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.ReadEntries(mValue))));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasUnwrapTests.SingleEntrySkipsList;
var
  mList: TArray<TAtlasUnwrapEntry>;
begin
  mList := Entries;
  Assert.IsFalse(TAtlasUnwrap.SingleEntry(mList));
  Assert.IsTrue(TAtlasUnwrap.SingleEntry([mList[0]]));
  Assert.IsFalse(TAtlasUnwrap.SingleEntry([mList[2]]), 'nicht übernehmbar: Liste mit Hinweis');
  Assert.IsFalse(TAtlasUnwrap.SingleEntry(nil));
end;

procedure TAtlasUnwrapTests.NextAvailableSkipsUnavailable;
var
  mList: TArray<TAtlasUnwrapEntry>;
begin
  mList := Entries;
  Assert.AreEqual(0, TAtlasUnwrap.NextAvailable(mList, 0, 1));
  Assert.AreEqual(0, TAtlasUnwrap.NextAvailable(mList, 2, 1), 'ringsum');
  Assert.AreEqual(1, TAtlasUnwrap.NextAvailable(mList, 2, -1));
  Assert.AreEqual(-1, TAtlasUnwrap.NextAvailable([mList[2]], 0, 1));
  Assert.AreEqual(-1, TAtlasUnwrap.NextAvailable(nil, 0, 1));
end;

procedure TAtlasUnwrapTests.SpansOnLine;
var
  mList: TArray<TAtlasUnwrapEntry>;
  mSpans: TArray<TAtlasUnwrapSpan>;
  mFirst, mLast: Integer;
begin
  mList := Entries;
  mSpans := TAtlasUnwrap.SpansOnLine(mList[0], 6);
  Assert.AreEqual(1, Integer(Length(mSpans)));
  Assert.IsTrue(mSpans[0].Keep);
  Assert.AreEqual(4, mSpans[0].Start);
  Assert.AreEqual(6, mSpans[0].Stop);
  mSpans := TAtlasUnwrap.SpansOnLine(mList[0], 7);
  Assert.AreEqual(1, Integer(Length(mSpans)));
  Assert.IsFalse(mSpans[0].Keep);
  Assert.AreEqual(0, Integer(Length(TAtlasUnwrap.SpansOnLine(mList[0], 4))));
  Assert.IsTrue(TAtlasUnwrap.LineSpan(mList[0], mFirst, mLast));
  Assert.AreEqual(5, mFirst);
  Assert.AreEqual(9, mLast);
  Assert.IsFalse(TAtlasUnwrap.LineSpan(mList[1], mFirst, mLast));
end;

procedure TAtlasUnwrapTests.EditForFile;
var
  mList: TArray<TAtlasUnwrapEntry>;
  mEdit: TLspWorkspaceEdit;
begin
  mList := Entries;
  mEdit := TAtlasUnwrap.EditOf(mList[0], 'C:\a.pas');
  Assert.AreEqual(1, Integer(Length(mEdit.Files)));
  Assert.AreEqual('C:\a.pas', mEdit.Files[0].FileName);
  Assert.AreEqual(1, mEdit.EditCount);
  Assert.IsTrue(TAtlasUnwrap.EditOf(mList[2], 'C:\a.pas').IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnwrapTests);

end.
