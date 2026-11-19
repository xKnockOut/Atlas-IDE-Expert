unit Atlas.Common.Editing.BodySpacing.Tests;

interface

// Einheitliche Leerzeilen um angelegte und geordnete Methodenrümpfe (#1839).

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBodySpacingTests = class
  public
    [Test]
    procedure SpacedSetsOneBlankLineAtBodyEdges;
    [Test]
    procedure SpacedKeepsLinesOutsideRangeAndInsideBodies;
    [Test]
    procedure SpacedAddsNothingNextToDirectives;
    [Test]
    procedure InsertBehindBodyGetsOneBlankLine;
    [Test]
    procedure InsertBeforeUnitEndCollapsesBlankLines;
    [Test]
    procedure InsertBeforeInitializationGetsOneBlankLine;
    [Test]
    procedure FittingInsertStaysAsItIs;
    [Test]
    procedure InsertInsideLineStaysAsItIs;
    [Test]
    procedure MissingBodiesBeforeUnitEnd;
    [Test]
    procedure BodyEditWithSettingOff;
    [Test]
    procedure ArrangeSpacesMovedBodies;
    [Test]
    procedure ArrangeKeepsOrderedUnit;
    [Test]
    procedure ArrangeWithSettingOff;
    [Test]
    procedure PlaceNewSpacesNewBody;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.ClassBodies,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.MethodOrder,
  Atlas.Common.Editing.BodySpacing;

const
  cKopf =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '    procedure C;'#10 +
    '  end;'#10 +
    'implementation'#10;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#10]);
end;

function Flags(ACount: Integer; const AIndexes: array of Integer): TArray<Boolean>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for mIndex in AIndexes do
  begin
    Result[mIndex] := True;
  end;
end;

function Spaced(const AText: string; const AStarts, AEnds: array of Integer; AFirst, ALast: Integer): string;
var
  mLines: TArray<string>;
  mSources: TArray<Integer>;
begin
  mLines := Lines(AText);
  Result := string.Join(#10, TBodySpacing.Spaced(mLines, Flags(Length(mLines), AStarts),
    Flags(Length(mLines), AEnds), AFirst, ALast, mSources));
end;

function Inserted(const AText: string; ALine, ACharacter: Integer; const ANewText: string): string;
var
  mEdit: TTextEdit;
begin
  mEdit := TTextEdit.Create(TTextRange.Create(ALine, ACharacter, ALine, ACharacter), ANewText);
  Result := TTextChanges.Apply(AText, [TBodySpacing.SpacedInsert(AText, mEdit)]);
end;

function Body(const AName: string): string;
begin
  Result := 'procedure ' + AName + ';'#10'begin'#10'end;';
end;

function Arranged(const AText: string; ABlankLines: Boolean; out AResult: TMethodOrderResult): string;
var
  mTree: TSyntaxTree;
  mOptions: TMethodOrderOptions;
begin
  mOptions := TMethodOrderOptions.Create(TMethodPlacement.Declaration);
  mOptions.BlankLines := ABlankLines;
  mTree := TPascalParser.Parse(AText);
  try
    AResult := TMethodOrder.Arrange(mTree, AText, mOptions);
  finally
    mTree.Free;
  end;
  Result := TTextChanges.Apply(AText, AResult.Edits);
end;

function WithBody(const AText, ATypeName, ABody: string; ABlankLines: Boolean): string;
var
  mTree: TSyntaxTree;
  mOptions: TClassBodyOptions;
  mEdit: TTextEdit;
begin
  mOptions := TClassBodyOptions.Default;
  mOptions.BlankLines := ABlankLines;
  mTree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TClassCompletion.BodyEdit(mTree, AText, ATypeName, ABody, mOptions, mEdit));
  finally
    mTree.Free;
  end;
  Result := TTextChanges.Apply(AText, [mEdit]);
end;

{ TBodySpacingTests }

procedure TBodySpacingTests.SpacedSetsOneBlankLineAtBodyEdges;
begin
  // Rumpf in den Zeilen 1 bis 3: davor keine, dahinter drei Leerzeilen.
  Assert.AreEqual('x;'#10#10'procedure A;'#10'begin'#10'end;'#10#10'end.',
    Spaced('x;'#10'procedure A;'#10'begin'#10'end;'#10#10#10#10'end.', [1], [3], 1, 3));
end;

procedure TBodySpacingTests.SpacedKeepsLinesOutsideRangeAndInsideBodies;
const
  cText = 'a;'#10#10#10'procedure A;'#10'begin'#10#10#10'end;'#10#10#10'procedure B;'#10'begin'#10'end;';
begin
  // Nur B (ab Zeile 10) liegt im Bereich: die Lücke über A bleibt, die Leerzeilen in A auch.
  Assert.AreEqual('a;'#10#10#10'procedure A;'#10'begin'#10#10#10'end;'#10#10'procedure B;'#10'begin'#10'end;',
    Spaced(cText, [3, 10], [7, 12], 10, 12));
end;

procedure TBodySpacingTests.SpacedAddsNothingNextToDirectives;
begin
  Assert.AreEqual('{$REGION ''TFoo''}'#10'procedure A;'#10'begin'#10'end;'#10'{$ENDREGION}',
    Spaced('{$REGION ''TFoo''}'#10'procedure A;'#10'begin'#10'end;'#10'{$ENDREGION}', [1], [3], 1, 3));
  Assert.AreEqual('{$REGION ''TFoo''}'#10#10'procedure A;'#10'begin'#10'end;'#10#10'{$ENDREGION}',
    Spaced('{$REGION ''TFoo''}'#10#10#10'procedure A;'#10'begin'#10'end;'#10#10#10'{$ENDREGION}', [3], [5], 3, 5),
    'Mehrere werden auch dort zu einer');
end;

procedure TBodySpacingTests.InsertBehindBodyGetsOneBlankLine;
const
  cText = 'implementation'#10#10'procedure TFoo.A;'#10'begin'#10'end;'#10'end.';
begin
  Assert.AreEqual('implementation'#10#10'procedure TFoo.A;'#10'begin'#10'end;'#10#10 + Body('TFoo.B') + #10#10 +
    'end.', Inserted(cText, 4, 4, #10#10 + Body('TFoo.B')));
end;

procedure TBodySpacingTests.InsertBeforeUnitEndCollapsesBlankLines;
const
  cText = 'implementation'#10#10'procedure TFoo.A;'#10'begin'#10'end;'#10#10#10#10'end.';
begin
  Assert.AreEqual('implementation'#10#10'procedure TFoo.A;'#10'begin'#10'end;'#10#10 + Body('TFoo.B') + #10#10 +
    'end.', Inserted(cText, 8, 0, Body('TFoo.B') + #10#10));
end;

procedure TBodySpacingTests.InsertBeforeInitializationGetsOneBlankLine;
const
  cText = 'implementation'#10'uses X;'#10'initialization'#10'end.';
begin
  Assert.AreEqual('implementation'#10'uses X;'#10#10 + Body('TFoo.A') + #10#10'initialization'#10'end.',
    Inserted(cText, 2, 0, Body('TFoo.A') + #10));
end;

procedure TBodySpacingTests.FittingInsertStaysAsItIs;
const
  cText = 'implementation'#10#10'procedure TFoo.A;'#10'begin'#10'end;'#10#10'end.';
var
  mEdit, mSpaced: TTextEdit;
begin
  mEdit := TTextEdit.Create(TTextRange.Create(4, 4, 4, 4), #10#10 + Body('TFoo.B'));
  mSpaced := TBodySpacing.SpacedInsert(cText, mEdit);
  Assert.AreEqual(mEdit.NewText, mSpaced.NewText);
  Assert.AreEqual(4, mSpaced.Range.StartPos.Line);
  Assert.AreEqual(4, mSpaced.Range.StartPos.Character);
end;

procedure TBodySpacingTests.InsertInsideLineStaysAsItIs;
const
  cText = 'a;'#10'b; c;'#10#10#10'end.';
var
  mEdit, mSpaced: TTextEdit;
begin
  mEdit := TTextEdit.Create(TTextRange.Create(1, 3, 1, 3), 'x;');
  mSpaced := TBodySpacing.SpacedInsert(cText, mEdit);
  Assert.AreEqual('x;', mSpaced.NewText);
  Assert.AreEqual(3, mSpaced.Range.StartPos.Character);
end;

procedure TBodySpacingTests.MissingBodiesBeforeUnitEnd;
const
  cText = cKopf + #10'uses X;'#10#10#10'end.';
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
  mOptions: TClassBodyOptions;
  mDone: string;
begin
  mOptions := TClassBodyOptions.Default;
  mOptions.BodyStubs := False;
  mTree := TPascalParser.Parse(cText);
  try
    Assert.IsTrue(TClassCompletion.MissingBodies(mTree, cText, TTextPosition.Create(4, 6), mOptions, mAction));
  finally
    mTree.Free;
  end;
  mDone := TTextChanges.Apply(cText, mAction.Edits);
  Assert.AreEqual(cKopf + #10'uses X;'#10#10'{ TFoo }'#10#10'procedure TFoo.A;'#10'begin'#10#10'end;'#10#10'end.',
    mDone);
end;

procedure TBodySpacingTests.BodyEditWithSettingOff;
const
  cText = cKopf + #10'procedure TFoo.A;'#10'begin'#10'end;'#10#10#10'end.';
begin
  Assert.AreEqual(cKopf + #10'procedure TFoo.A;'#10'begin'#10'end;'#10#10 + Body('TFoo.B') + #10#10'end.',
    WithBody(cText, 'TFoo', Body('TFoo.B'), True));
  Assert.AreEqual(cKopf + #10'procedure TFoo.A;'#10'begin'#10'end;'#10#10 + Body('TFoo.B') + #10#10#10'end.',
    WithBody(cText, 'TFoo', Body('TFoo.B'), False), 'Aus: Leerzeilen wie bisher');
end;

procedure TBodySpacingTests.ArrangeSpacesMovedBodies;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(cKopf + #10 + Body('TFoo.A') + #10#10 + Body('TFoo.B') + #10#10 + Body('TFoo.C') + #10#10'end.',
    Arranged(cKopf + #10 + Body('TFoo.C') + #10 + Body('TFoo.B') + #10#10#10 + Body('TFoo.A') + #10#10#10'end.', True,
    mOrder));
  Assert.AreEqual(2, Integer(Length(mOrder.Moves)));
  Assert.AreEqual('C', mOrder.Moves[1].Name);
  Assert.AreEqual(18, mOrder.Moves[1].NewLine, 'Zeile nach dem Angleichen');
end;

procedure TBodySpacingTests.ArrangeKeepsOrderedUnit;
var
  mOrder: TMethodOrderResult;
  mText: string;
begin
  mText := cKopf + #10 + Body('TFoo.A') + #10 + Body('TFoo.B') + #10#10#10'end.';
  // Geordnet: nichts zu tun, auch wenn die Leerzeilen nicht passen (das ist Sache des Formatierers).
  Assert.AreEqual(mText, Arranged(mText, True, mOrder));
  Assert.AreEqual(0, Integer(Length(mOrder.Edits)));
end;

procedure TBodySpacingTests.ArrangeWithSettingOff;
var
  mOrder: TMethodOrderResult;
begin
  Assert.AreEqual(cKopf + #10 + Body('TFoo.A') + #10 + Body('TFoo.B') + #10#10#10'end.',
    Arranged(cKopf + #10 + Body('TFoo.B') + #10 + Body('TFoo.A') + #10#10#10'end.', False, mOrder));
end;

procedure TBodySpacingTests.PlaceNewSpacesNewBody;
var
  mTree: TSyntaxTree;
  mOptions: TMethodOrderOptions;
  mOrder: TMethodOrderResult;
  mBefore, mText: string;
begin
  mBefore := cKopf + #10 + Body('TFoo.A') + #10#10 + Body('TFoo.C') + #10#10'end.';
  mText := cKopf + #10 + Body('TFoo.A') + #10#10 + Body('TFoo.C') + #10#10 + Body('TFoo.B') + #10#10#10'end.';
  mOptions := TMethodOrderOptions.Create(TMethodPlacement.Declaration);
  mOptions.BlankLines := True;
  mTree := TPascalParser.Parse(mText);
  try
    mOrder := TMethodOrder.PlaceNew(mTree, mText, mBefore, mOptions);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(cKopf + #10 + Body('TFoo.A') + #10#10 + Body('TFoo.B') + #10#10 + Body('TFoo.C') + #10#10'end.',
    TTextChanges.Apply(mText, mOrder.Edits));
end;

end.
