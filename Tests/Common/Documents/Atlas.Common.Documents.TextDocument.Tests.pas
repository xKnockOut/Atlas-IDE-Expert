unit Atlas.Common.Documents.TextDocument.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextDocumentTests = class
  public
    [Test]
    procedure KeepsUriLanguageAndVersion;
    [Test]
    procedure SplitsLinesAtCrLfLfAndCr;
    [Test]
    procedure CountsTrailingLineBreakAsEmptyLine;
    [Test]
    procedure OffsetAtClampsCharacterToLineEnd;
    [Test]
    procedure OffsetAtOutsideDocument;
    [Test]
    procedure PositionAtFindsLineAndCharacter;
    [Test]
    procedure CountsUtf16CodeUnits;
    [Test]
    procedure InsertsText;
    [Test]
    procedure ReplacesRangeAcrossLines;
    [Test]
    procedure DeletesLineBreak;
    [Test]
    procedure ReplacesWholeTextWithoutRange;
    [Test]
    procedure AppliesChangesOneAfterAnother;
    [Test]
    procedure KeepsOriginalSnapshotUnchanged;
    [Test]
    procedure RejectsRangeEndingBeforeStart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.TextDocument,
  Atlas.Tests.RecordText;

function Doc(const AText: string): ITextDocument;
begin
  Result := TTextDocument.Create('file:///c%3A/test.pas', 'pascal', 1, AText);
end;

function Change(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer; const AText: string): TTextChange;
begin
  Result := TTextChange.Ranged(TTextRange.Create(AStartLine, AStartCharacter, AEndLine, AEndCharacter), AText);
end;

{ TTextDocumentTests }

procedure TTextDocumentTests.KeepsUriLanguageAndVersion;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('unit A;');
  Assert.AreEqual('file:///c%3A/test.pas', mDocument.Uri);
  Assert.AreEqual('pascal', mDocument.LanguageId);
  Assert.AreEqual(1, mDocument.Version);
  Assert.AreEqual('unit A;', mDocument.Text);
end;

procedure TTextDocumentTests.SplitsLinesAtCrLfLfAndCr;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('eins'#13#10'zwei'#10'drei'#13'vier');
  Assert.AreEqual(4, mDocument.LineCount);
  Assert.AreEqual('eins', mDocument.LineText(0));
  Assert.AreEqual('zwei', mDocument.LineText(1));
  Assert.AreEqual('drei', mDocument.LineText(2));
  Assert.AreEqual('vier', mDocument.LineText(3));
  Assert.AreEqual('', mDocument.LineText(4));
  Assert.AreEqual('', mDocument.LineText(-1));
end;

procedure TTextDocumentTests.CountsTrailingLineBreakAsEmptyLine;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('a'#13#10);
  Assert.AreEqual(2, mDocument.LineCount);
  Assert.AreEqual('', mDocument.LineText(1));
  Assert.AreEqual(1, Doc('').LineCount);
end;

procedure TTextDocumentTests.OffsetAtClampsCharacterToLineEnd;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('ab'#13#10'cde');
  Assert.AreEqual(0, mDocument.OffsetAt(TTextPosition.Create(0, 0)));
  Assert.AreEqual(2, mDocument.OffsetAt(TTextPosition.Create(0, 2)));
  // Hinter dem Zeilenende zählt das Zeilenende, nicht der Zeilenumbruch.
  Assert.AreEqual(2, mDocument.OffsetAt(TTextPosition.Create(0, 99)));
  Assert.AreEqual(4, mDocument.OffsetAt(TTextPosition.Create(1, 0)));
  Assert.AreEqual(7, mDocument.OffsetAt(TTextPosition.Create(1, 99)));
end;

procedure TTextDocumentTests.OffsetAtOutsideDocument;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('ab'#10'cd');
  Assert.AreEqual(0, mDocument.OffsetAt(TTextPosition.Create(-1, 5)));
  Assert.AreEqual(5, mDocument.OffsetAt(TTextPosition.Create(7, 0)));
end;

procedure TTextDocumentTests.PositionAtFindsLineAndCharacter;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('ab'#13#10'cde'#10'f');
  Assert.AreEqual(TRecordText.Position(0, 0), TRecordText.Position(mDocument.PositionAt(0)));
  Assert.AreEqual(TRecordText.Position(0, 2), TRecordText.Position(mDocument.PositionAt(2)));
  // Offset innerhalb von CRLF: Zeilenende.
  Assert.AreEqual(TRecordText.Position(0, 2), TRecordText.Position(mDocument.PositionAt(3)));
  Assert.AreEqual(TRecordText.Position(1, 0), TRecordText.Position(mDocument.PositionAt(4)));
  Assert.AreEqual(TRecordText.Position(1, 3), TRecordText.Position(mDocument.PositionAt(7)));
  Assert.AreEqual(TRecordText.Position(2, 0), TRecordText.Position(mDocument.PositionAt(8)));
  Assert.AreEqual(TRecordText.Position(2, 1), TRecordText.Position(mDocument.PositionAt(99)));
  Assert.AreEqual(TRecordText.Position(0, 0), TRecordText.Position(mDocument.PositionAt(-3)));
end;

procedure TTextDocumentTests.CountsUtf16CodeUnits;
var
  mDocument: ITextDocument;
begin
  // U+1F600 belegt zwei UTF-16-Codeeinheiten, wie im LSP gezählt.
  mDocument := Doc('a'#$D83D#$DE00'b');
  Assert.AreEqual(3, mDocument.OffsetAt(TTextPosition.Create(0, 3)));
  mDocument := mDocument.ApplyChanges([Change(0, 3, 0, 4, 'c')], 2);
  Assert.AreEqual('a'#$D83D#$DE00'c', mDocument.Text);
end;

procedure TTextDocumentTests.InsertsText;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('unit A;'#13#10'end.').ApplyChanges([Change(1, 0, 1, 0, 'interface'#13#10)], 2);
  Assert.AreEqual('unit A;'#13#10'interface'#13#10'end.', mDocument.Text);
  Assert.AreEqual(2, mDocument.Version);
  Assert.AreEqual(3, mDocument.LineCount);
end;

procedure TTextDocumentTests.ReplacesRangeAcrossLines;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('eins'#10'zwei'#10'drei').ApplyChanges([Change(0, 2, 2, 2, 'XY')], 2);
  Assert.AreEqual('eiXYei', mDocument.Text);
  Assert.AreEqual(1, mDocument.LineCount);
end;

procedure TTextDocumentTests.DeletesLineBreak;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('ab'#13#10'cd').ApplyChanges([Change(0, 2, 1, 0, '')], 2);
  Assert.AreEqual('abcd', mDocument.Text);
end;

procedure TTextDocumentTests.ReplacesWholeTextWithoutRange;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('alt').ApplyChanges([TTextChange.Full('neu'#10'zwei')], 5);
  Assert.AreEqual('neu'#10'zwei', mDocument.Text);
  Assert.AreEqual(5, mDocument.Version);
  Assert.AreEqual(2, mDocument.LineCount);
end;

procedure TTextDocumentTests.AppliesChangesOneAfterAnother;
var
  mDocument: ITextDocument;
begin
  // Die zweite Änderung bezieht sich auf den Text nach der ersten.
  mDocument := Doc('abc').ApplyChanges([
    Change(0, 0, 0, 0, 'x'#10),
    Change(1, 1, 1, 2, 'B')], 2);
  Assert.AreEqual('x'#10'aBc', mDocument.Text);
end;

procedure TTextDocumentTests.KeepsOriginalSnapshotUnchanged;
var
  mOriginal: ITextDocument;
  mChanged: ITextDocument;
begin
  mOriginal := Doc('abc');
  mChanged := mOriginal.ApplyChanges([Change(0, 0, 0, 3, 'xyz')], 2);
  Assert.AreEqual('abc', mOriginal.Text);
  Assert.AreEqual(1, mOriginal.Version);
  Assert.AreEqual('xyz', mChanged.Text);
end;

procedure TTextDocumentTests.RejectsRangeEndingBeforeStart;
var
  mDocument: ITextDocument;
begin
  mDocument := Doc('abc');
  Assert.WillRaise(
    procedure
    begin
      mDocument.ApplyChanges([Change(0, 2, 0, 1, '')], 2);
    end,
    EDocumentError);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDocumentTests);

end.
