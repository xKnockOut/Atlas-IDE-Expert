unit Atlas.Core.Editor.MethodPlacement.Tests;

// Methodenrümpfe in Deklarationsreihenfolge (#660), Kern im Plugin:
// Argumente, Antwort, neue Methodenköpfe, die eine Änderung über
// Klassenvervollständigung und Verschieben, Schreibmarke und Vorschau.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMethodPlacementTests = class
  public
    [Test]
    procedure ArgumentsForBothScopes;
    [Test]
    procedure ReadsReply;
    [Test]
    procedure DetectsNewMethodHeaders;
    [Test]
    procedure DifferenceIsOneEdit;
    [Test]
    procedure CaretFollowsMovedBody;
    [Test]
    procedure PreviewTexts;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.MethodPlacement;

const
  LB = #13#10;

function Texts: TAtlasMethodPlacementTexts;
begin
  Result := Default(TAtlasMethodPlacementTexts);
  Result.Up := 'hoch %d';
  Result.Down := 'runter %d';
  Result.Stays := 'bleibt: %s';
  Result.Region := 'Region';
  Result.Conditional := 'IFDEF';
  Result.SharedLine := 'Zeile';
end;

function Applied(const AText: string; const ARange: TLspTextRange): string;
begin
  Result := Copy(AText, 1, ARange.StartOffset) + ARange.NewText + Copy(AText, ARange.EndOffset + 1, MaxInt);
end;

procedure TAtlasMethodPlacementTests.ArgumentsForBothScopes;
begin
  Assert.AreEqual('["file:///C:/P/U.pas",{"mode":"declaration","scope":"all"}]',
    TAtlasMethodPlacement.Arguments('file:///C:/P/U.pas', 'declaration', True, 'egal'));
  Assert.AreEqual('["file:///C:/P/U.pas",{"mode":"alphabetical","scope":"new","before":"x"}]',
    TAtlasMethodPlacement.Arguments('file:///C:/P/U.pas', 'alphabetical', False, 'x'));
end;

procedure TAtlasMethodPlacementTests.ReadsReply;
var
  Answer: TJSONValue;
  Reply: TAtlasMethodPlacementReply;
begin
  Answer := TJSONObject.ParseJSONValue('{"edits": [{"range": {"start": {"line": 3, "character": 0}, ' +
    '"end": {"line": 9, "character": 0}}, "newText": "neu"}], "moves": [' +
    '{"type": "TKunde", "name": "Speichern", "line": 8, "newLine": 3, "size": 4, "delta": -2, "fixed": false, ' +
    '"reason": ""}, {"type": "TKunde", "name": "Laden", "line": 20, "newLine": -1, "size": 3, "delta": 0, ' +
    '"fixed": true, "reason": "region"}]}');
  try
    Assert.IsTrue(TAtlasMethodPlacement.Read(Answer, Reply));
  finally
    Answer.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Reply.Edits)));
  Assert.AreEqual(3, Reply.Edits[0].StartPos.Line);
  Assert.AreEqual('neu', Reply.Edits[0].NewText);
  Assert.AreEqual(2, Integer(Length(Reply.Moves)));
  Assert.AreEqual(1, Reply.Moved);
  Assert.AreEqual('Speichern', Reply.Moves[0].Name);
  Assert.AreEqual(3, Reply.Moves[0].NewLine);
  Assert.AreEqual(4, Reply.Moves[0].Size);
  Assert.AreEqual(-2, Reply.Moves[0].Delta);
  Assert.IsTrue(Reply.Moves[1].Fixed);
  Assert.AreEqual('region', Reply.Moves[1].Reason);
  Assert.IsFalse(TAtlasMethodPlacement.Read(nil, Reply));
end;

procedure TAtlasMethodPlacementTests.DetectsNewMethodHeaders;
const
  Before = 'implementation' + LB + LB + 'procedure TFoo.A;' + LB + 'begin' + LB + 'end;' + LB;
begin
  Assert.IsTrue(TAtlasMethodPlacement.NewHeaders(Before,
    Before + LB + 'procedure TFoo.B(X: Integer);' + LB + 'begin' + LB + 'end;' + LB));
  Assert.IsTrue(TAtlasMethodPlacement.NewHeaders(Before,
    Before + LB + '  class function TFoo.Neu: TFoo;' + LB + 'begin' + LB + 'end;' + LB));
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(Before, Before), 'unverändert');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(Before,
    Before + LB + 'procedure Hilfe(A: TFoo.TArt);' + LB + 'begin' + LB + 'end;' + LB), 'freie Routine');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(Before,
    StringReplace(Before, 'begin', 'begin' + LB + '  Lauf;', [])), 'Änderung im Rumpf');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(Before,
    StringReplace(Before, 'procedure TFoo.A;', '  procedure TFoo.A;', [])), 'nur eingerückt');
end;

procedure TAtlasMethodPlacementTests.DifferenceIsOneEdit;
const
  Before = 'A' + LB + 'B' + LB + 'C' + LB;
  Final = 'A' + LB + 'B' + LB + 'neu' + LB + 'C' + LB;
var
  Range: TLspTextRange;
begin
  Assert.IsTrue(TAtlasMethodPlacement.Difference(Before, Final, Range));
  Assert.AreEqual(Final, Applied(Before, Range));
  Assert.IsFalse(TAtlasMethodPlacement.Difference(Before, Before, Range));
  // Nie zwischen #13 und #10 schneiden.
  Assert.IsTrue(TAtlasMethodPlacement.Difference('A' + #13#10 + 'B', 'A' + #13 + 'B', Range));
  Assert.AreEqual(1, Range.StartOffset);
  Assert.AreEqual('A' + #13 + 'B', Applied('A' + #13#10 + 'B', Range));
  Assert.IsTrue(TAtlasMethodPlacement.Difference('X' + #$D83D#$DE00, 'X' + #$D83D#$DE01, Range));
  Assert.AreEqual(1, Range.StartOffset, 'Ersatzpaar ganz');
end;

procedure TAtlasMethodPlacementTests.CaretFollowsMovedBody;
var
  Moves: TArray<TAtlasMethodMove>;
  Line: Integer;
begin
  SetLength(Moves, 2);
  Moves[0].Fixed := True;
  Moves[0].Line := 30;
  Moves[0].NewLine := -1;
  Moves[0].Size := 5;
  Moves[1].Line := 40;
  Moves[1].NewLine := 12;
  Moves[1].Size := 4;
  Assert.IsTrue(TAtlasMethodPlacement.CaretLine(Moves, 42, Line));
  Assert.AreEqual(14, Line);
  Assert.IsFalse(TAtlasMethodPlacement.CaretLine(Moves, 44, Line), 'hinter dem Rumpf');
  Assert.IsFalse(TAtlasMethodPlacement.CaretLine(Moves, 31, Line), 'stehen bleibender Rumpf');
  Assert.AreEqual(31, Line);
end;

procedure TAtlasMethodPlacementTests.PreviewTexts;
var
  Move: TAtlasMethodMove;
begin
  Move := Default(TAtlasMethodMove);
  Move.TypeName := 'TKunde';
  Move.Name := 'Speichern';
  Move.Delta := -3;
  Assert.AreEqual('hoch 3  TKunde.Speichern', TAtlasMethodPlacement.MoveText(Move, Texts));
  Move.Delta := 2;
  Assert.AreEqual('runter 2  TKunde.Speichern', TAtlasMethodPlacement.MoveText(Move, Texts));
  Move.Fixed := True;
  Move.Reason := 'ifdef';
  Assert.AreEqual('bleibt: IFDEF  TKunde.Speichern', TAtlasMethodPlacement.MoveText(Move, Texts));
  Move.Reason := 'region';
  Assert.AreEqual('bleibt: Region  TKunde.Speichern', TAtlasMethodPlacement.MoveText(Move, Texts));
  Move.Reason := 'line';
  Assert.AreEqual('bleibt: Zeile  TKunde.Speichern', TAtlasMethodPlacement.MoveText(Move, Texts));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodPlacementTests);

end.
