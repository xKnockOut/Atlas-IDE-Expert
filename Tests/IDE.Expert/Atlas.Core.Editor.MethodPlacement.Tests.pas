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
  cLB = #13#10;

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
  mAnswer: TJSONValue;
  mReply: TAtlasMethodPlacementReply;
begin
  mAnswer := TJSONObject.ParseJSONValue('{"edits": [{"range": {"start": {"line": 3, "character": 0}, ' +
    '"end": {"line": 9, "character": 0}}, "newText": "neu"}], "moves": [' +
    '{"type": "TKunde", "name": "Speichern", "line": 8, "newLine": 3, "size": 4, "delta": -2, "fixed": false, ' +
    '"reason": ""}, {"type": "TKunde", "name": "Laden", "line": 20, "newLine": -1, "size": 3, "delta": 0, ' +
    '"fixed": true, "reason": "region"}]}');
  try
    Assert.IsTrue(TAtlasMethodPlacement.Read(mAnswer, mReply));
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mReply.Edits)));
  Assert.AreEqual(3, mReply.Edits[0].StartPos.Line);
  Assert.AreEqual('neu', mReply.Edits[0].NewText);
  Assert.AreEqual(2, Integer(Length(mReply.Moves)));
  Assert.AreEqual(1, mReply.Moved);
  Assert.AreEqual('Speichern', mReply.Moves[0].Name);
  Assert.AreEqual(3, mReply.Moves[0].NewLine);
  Assert.AreEqual(4, mReply.Moves[0].Size);
  Assert.AreEqual(-2, mReply.Moves[0].Delta);
  Assert.IsTrue(mReply.Moves[1].Fixed);
  Assert.AreEqual('region', mReply.Moves[1].Reason);
  Assert.IsFalse(TAtlasMethodPlacement.Read(nil, mReply));
end;

procedure TAtlasMethodPlacementTests.DetectsNewMethodHeaders;
const
  cBefore = 'implementation' + cLB + cLB + 'procedure TFoo.A;' + cLB + 'begin' + cLB + 'end;' + cLB;
begin
  Assert.IsTrue(TAtlasMethodPlacement.NewHeaders(cBefore,
    cBefore + cLB + 'procedure TFoo.B(X: Integer);' + cLB + 'begin' + cLB + 'end;' + cLB));
  Assert.IsTrue(TAtlasMethodPlacement.NewHeaders(cBefore,
    cBefore + cLB + '  class function TFoo.Neu: TFoo;' + cLB + 'begin' + cLB + 'end;' + cLB));
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(cBefore, cBefore), 'unverändert');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(cBefore,
    cBefore + cLB + 'procedure Hilfe(A: TFoo.TArt);' + cLB + 'begin' + cLB + 'end;' + cLB), 'freie Routine');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(cBefore,
    StringReplace(cBefore, 'begin', 'begin' + cLB + '  Lauf;', [])), 'Änderung im Rumpf');
  Assert.IsFalse(TAtlasMethodPlacement.NewHeaders(cBefore,
    StringReplace(cBefore, 'procedure TFoo.A;', '  procedure TFoo.A;', [])), 'nur eingerückt');
end;

procedure TAtlasMethodPlacementTests.DifferenceIsOneEdit;
const
  cBefore = 'A' + cLB + 'B' + cLB + 'C' + cLB;
  cFinal = 'A' + cLB + 'B' + cLB + 'neu' + cLB + 'C' + cLB;
var
  mRange: TLspTextRange;
begin
  Assert.IsTrue(TAtlasMethodPlacement.Difference(cBefore, cFinal, mRange));
  Assert.AreEqual(cFinal, Applied(cBefore, mRange));
  Assert.IsFalse(TAtlasMethodPlacement.Difference(cBefore, cBefore, mRange));
  // Nie zwischen #13 und #10 schneiden.
  Assert.IsTrue(TAtlasMethodPlacement.Difference('A' + #13#10 + 'B', 'A' + #13 + 'B', mRange));
  Assert.AreEqual(1, mRange.StartOffset);
  Assert.AreEqual('A' + #13 + 'B', Applied('A' + #13#10 + 'B', mRange));
  Assert.IsTrue(TAtlasMethodPlacement.Difference('X' + #$D83D#$DE00, 'X' + #$D83D#$DE01, mRange));
  Assert.AreEqual(1, mRange.StartOffset, 'Ersatzpaar ganz');
end;

procedure TAtlasMethodPlacementTests.CaretFollowsMovedBody;
var
  mMoves: TArray<TAtlasMethodMove>;
  mLine: Integer;
begin
  SetLength(mMoves, 2);
  mMoves[0].Fixed := True;
  mMoves[0].Line := 30;
  mMoves[0].NewLine := -1;
  mMoves[0].Size := 5;
  mMoves[1].Line := 40;
  mMoves[1].NewLine := 12;
  mMoves[1].Size := 4;
  Assert.IsTrue(TAtlasMethodPlacement.CaretLine(mMoves, 42, mLine));
  Assert.AreEqual(14, mLine);
  Assert.IsFalse(TAtlasMethodPlacement.CaretLine(mMoves, 44, mLine), 'hinter dem Rumpf');
  Assert.IsFalse(TAtlasMethodPlacement.CaretLine(mMoves, 31, mLine), 'stehen bleibender Rumpf');
  Assert.AreEqual(31, mLine);
end;

procedure TAtlasMethodPlacementTests.PreviewTexts;
var
  mMove: TAtlasMethodMove;
begin
  mMove := Default(TAtlasMethodMove);
  mMove.TypeName := 'TKunde';
  mMove.Name := 'Speichern';
  mMove.Delta := -3;
  Assert.AreEqual('hoch 3  TKunde.Speichern', TAtlasMethodPlacement.MoveText(mMove, Texts));
  mMove.Delta := 2;
  Assert.AreEqual('runter 2  TKunde.Speichern', TAtlasMethodPlacement.MoveText(mMove, Texts));
  mMove.Fixed := True;
  mMove.Reason := 'ifdef';
  Assert.AreEqual('bleibt: IFDEF  TKunde.Speichern', TAtlasMethodPlacement.MoveText(mMove, Texts));
  mMove.Reason := 'region';
  Assert.AreEqual('bleibt: Region  TKunde.Speichern', TAtlasMethodPlacement.MoveText(mMove, Texts));
  mMove.Reason := 'line';
  Assert.AreEqual('bleibt: Zeile  TKunde.Speichern', TAtlasMethodPlacement.MoveText(mMove, Texts));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodPlacementTests);

end.
