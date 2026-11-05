unit Atlas.Core.Editor.FormatLog.Tests;

// Tests für die Protokollzeilen beim Formatieren (#43): Zustand des Blocks,
// gesendeter Bereich, Zeilen der Antwort, Änderungen außerhalb der Markierung
// und dass nur Zahlen ins Protokoll gehen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFormatLogTests = class
  public
    [Test]
    procedure RequestWithoutSelectionNamesWholeFile;
    [Test]
    procedure RequestWithSelectionNamesLines;
    [Test]
    procedure SelectionEndingAtLineStartExcludesThatLine;
    [Test]
    procedure AnswerWithoutEdits;
    [Test]
    procedure AnswerCountsEditsOutsideSelection;
    [Test]
    procedure AnswerForWholeFileHasNoOutsideCount;
    [Test]
    procedure TextIsAnonymous;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.FormatLog;

function Edit(AStartLine, AEndLine, AEndCharacter: Integer): TLspTextEdit;
begin
  Result := Default(TLspTextEdit);
  Result.StartPos := TLspTextPosition.Create(AStartLine, 0);
  Result.EndPos := TLspTextPosition.Create(AEndLine, AEndCharacter);
  Result.NewText := 'begin';
end;

function Caret: TLspRange;
begin
  Result := TLspRange.Create(4, 2, 4, 2);
end;

procedure TAtlasFormatLogTests.RequestWithoutSelectionNamesWholeFile;
begin
  Assert.AreEqual('Format: block valid=no size=0, no selection -> formatting (whole file)',
    TAtlasFormatLog.Request(False, 0, Caret));
end;

procedure TAtlasFormatLogTests.RequestWithSelectionNamesLines;
begin
  Assert.AreEqual('Format: block valid=yes size=120, selection lines 12-30 -> rangeFormatting',
    TAtlasFormatLog.Request(True, 120, TLspRange.Create(11, 3, 29, 7)));
end;

procedure TAtlasFormatLogTests.SelectionEndingAtLineStartExcludesThatLine;
begin
  Assert.AreEqual('Format: block valid=yes size=40, selection lines 12-14 -> rangeFormatting',
    TAtlasFormatLog.Request(True, 40, TLspRange.Create(11, 0, 14, 0)));
end;

procedure TAtlasFormatLogTests.AnswerWithoutEdits;
begin
  Assert.AreEqual('Format: 0 edits', TAtlasFormatLog.Answer(nil, TLspRange.Create(1, 0, 3, 0)));
end;

procedure TAtlasFormatLogTests.AnswerCountsEditsOutsideSelection;
var
  mEdits: TArray<TLspTextEdit>;
begin
  mEdits := [Edit(0, 0, 5), Edit(11, 11, 4), Edit(13, 14, 0), Edit(40, 41, 2)];
  Assert.AreEqual('Format: 4 edits, lines 1-42, 2 outside selection',
    TAtlasFormatLog.Answer(mEdits, TLspRange.Create(11, 0, 14, 0)));
end;

procedure TAtlasFormatLogTests.AnswerForWholeFileHasNoOutsideCount;
var
  mEdits: TArray<TLspTextEdit>;
begin
  mEdits := [Edit(2, 2, 5), Edit(7, 7, 1)];
  Assert.AreEqual('Format: 2 edits, lines 3-8', TAtlasFormatLog.Answer(mEdits, Caret));
end;

procedure TAtlasFormatLogTests.TextIsAnonymous;
var
  mEdits: TArray<TLspTextEdit>;
  mText: string;
begin
  mEdits := [Edit(2, 2, 5)];
  mText := TAtlasFormatLog.Request(True, 10, TLspRange.Create(1, 0, 3, 0)) +
    TAtlasFormatLog.Answer(mEdits, TLspRange.Create(1, 0, 3, 0));
  // Neuer Text der Änderung (Quelltext) steht nicht im Protokoll.
  Assert.IsFalse(mText.Contains('begin'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormatLogTests);

end.
