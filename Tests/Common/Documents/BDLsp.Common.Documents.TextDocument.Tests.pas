unit BDLsp.Common.Documents.TextDocument.Tests;

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
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.TextDocument;

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
  Document: ITextDocument;
begin
  Document := Doc('unit A;');
  Assert.AreEqual('file:///c%3A/test.pas', Document.Uri);
  Assert.AreEqual('pascal', Document.LanguageId);
  Assert.AreEqual(1, Document.Version);
  Assert.AreEqual('unit A;', Document.Text);
end;

procedure TTextDocumentTests.SplitsLinesAtCrLfLfAndCr;
var
  Document: ITextDocument;
begin
  Document := Doc('eins'#13#10'zwei'#10'drei'#13'vier');
  Assert.AreEqual(4, Document.LineCount);
  Assert.AreEqual('eins', Document.LineText(0));
  Assert.AreEqual('zwei', Document.LineText(1));
  Assert.AreEqual('drei', Document.LineText(2));
  Assert.AreEqual('vier', Document.LineText(3));
  Assert.AreEqual('', Document.LineText(4));
  Assert.AreEqual('', Document.LineText(-1));
end;

procedure TTextDocumentTests.CountsTrailingLineBreakAsEmptyLine;
var
  Document: ITextDocument;
begin
  Document := Doc('a'#13#10);
  Assert.AreEqual(2, Document.LineCount);
  Assert.AreEqual('', Document.LineText(1));
  Assert.AreEqual(1, Doc('').LineCount);
end;

procedure TTextDocumentTests.OffsetAtClampsCharacterToLineEnd;
var
  Document: ITextDocument;
begin
  Document := Doc('ab'#13#10'cde');
  Assert.AreEqual(0, Document.OffsetAt(TTextPosition.Create(0, 0)));
  Assert.AreEqual(2, Document.OffsetAt(TTextPosition.Create(0, 2)));
  // Hinter dem Zeilenende zählt das Zeilenende, nicht der Zeilenumbruch.
  Assert.AreEqual(2, Document.OffsetAt(TTextPosition.Create(0, 99)));
  Assert.AreEqual(4, Document.OffsetAt(TTextPosition.Create(1, 0)));
  Assert.AreEqual(7, Document.OffsetAt(TTextPosition.Create(1, 99)));
end;

procedure TTextDocumentTests.OffsetAtOutsideDocument;
var
  Document: ITextDocument;
begin
  Document := Doc('ab'#10'cd');
  Assert.AreEqual(0, Document.OffsetAt(TTextPosition.Create(-1, 5)));
  Assert.AreEqual(5, Document.OffsetAt(TTextPosition.Create(7, 0)));
end;

procedure TTextDocumentTests.PositionAtFindsLineAndCharacter;
var
  Document: ITextDocument;
begin
  Document := Doc('ab'#13#10'cde'#10'f');
  Assert.IsTrue(TTextPosition.Create(0, 0) = Document.PositionAt(0));
  Assert.IsTrue(TTextPosition.Create(0, 2) = Document.PositionAt(2));
  // Offset innerhalb von CRLF: Zeilenende.
  Assert.IsTrue(TTextPosition.Create(0, 2) = Document.PositionAt(3));
  Assert.IsTrue(TTextPosition.Create(1, 0) = Document.PositionAt(4));
  Assert.IsTrue(TTextPosition.Create(1, 3) = Document.PositionAt(7));
  Assert.IsTrue(TTextPosition.Create(2, 0) = Document.PositionAt(8));
  Assert.IsTrue(TTextPosition.Create(2, 1) = Document.PositionAt(99));
  Assert.IsTrue(TTextPosition.Create(0, 0) = Document.PositionAt(-3));
end;

procedure TTextDocumentTests.CountsUtf16CodeUnits;
var
  Document: ITextDocument;
begin
  // U+1F600 belegt zwei UTF-16-Codeeinheiten, wie im LSP gezählt.
  Document := Doc('a'#$D83D#$DE00'b');
  Assert.AreEqual(3, Document.OffsetAt(TTextPosition.Create(0, 3)));
  Document := Document.ApplyChanges([Change(0, 3, 0, 4, 'c')], 2);
  Assert.AreEqual('a'#$D83D#$DE00'c', Document.Text);
end;

procedure TTextDocumentTests.InsertsText;
var
  Document: ITextDocument;
begin
  Document := Doc('unit A;'#13#10'end.').ApplyChanges([Change(1, 0, 1, 0, 'interface'#13#10)], 2);
  Assert.AreEqual('unit A;'#13#10'interface'#13#10'end.', Document.Text);
  Assert.AreEqual(2, Document.Version);
  Assert.AreEqual(3, Document.LineCount);
end;

procedure TTextDocumentTests.ReplacesRangeAcrossLines;
var
  Document: ITextDocument;
begin
  Document := Doc('eins'#10'zwei'#10'drei').ApplyChanges([Change(0, 2, 2, 2, 'XY')], 2);
  Assert.AreEqual('eiXYei', Document.Text);
  Assert.AreEqual(1, Document.LineCount);
end;

procedure TTextDocumentTests.DeletesLineBreak;
var
  Document: ITextDocument;
begin
  Document := Doc('ab'#13#10'cd').ApplyChanges([Change(0, 2, 1, 0, '')], 2);
  Assert.AreEqual('abcd', Document.Text);
end;

procedure TTextDocumentTests.ReplacesWholeTextWithoutRange;
var
  Document: ITextDocument;
begin
  Document := Doc('alt').ApplyChanges([TTextChange.Full('neu'#10'zwei')], 5);
  Assert.AreEqual('neu'#10'zwei', Document.Text);
  Assert.AreEqual(5, Document.Version);
  Assert.AreEqual(2, Document.LineCount);
end;

procedure TTextDocumentTests.AppliesChangesOneAfterAnother;
var
  Document: ITextDocument;
begin
  // Die zweite Änderung bezieht sich auf den Text nach der ersten.
  Document := Doc('abc').ApplyChanges([
    Change(0, 0, 0, 0, 'x'#10),
    Change(1, 1, 1, 2, 'B')], 2);
  Assert.AreEqual('x'#10'aBc', Document.Text);
end;

procedure TTextDocumentTests.KeepsOriginalSnapshotUnchanged;
var
  Original: ITextDocument;
  Changed: ITextDocument;
begin
  Original := Doc('abc');
  Changed := Original.ApplyChanges([Change(0, 0, 0, 3, 'xyz')], 2);
  Assert.AreEqual('abc', Original.Text);
  Assert.AreEqual(1, Original.Version);
  Assert.AreEqual('xyz', Changed.Text);
end;

procedure TTextDocumentTests.RejectsRangeEndingBeforeStart;
var
  Document: ITextDocument;
begin
  Document := Doc('abc');
  Assert.WillRaise(
    procedure
    begin
      Document.ApplyChanges([Change(0, 2, 0, 1, '')], 2);
    end,
    EDocumentError);
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDocumentTests);

end.
