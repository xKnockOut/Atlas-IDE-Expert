unit Atlas.Core.Completion.CommitPlan.Tests;

// Übernehmen eines Eintrags (Atlas.Core.Completion.CommitPlan): eingesetzter Text, Änderungen in Bytes, Schreibmarke,
// Code-Vorlagen mit weiteren Änderungen, Wächter und Auffüllen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionCommitPlanTests = class
  public
    [Test]
    procedure WordEndAtCommitCharacterOrIdentifierEnd;
    [Test]
    procedure TextKeepsTypedCaseWithoutFixCase;
    [Test]
    procedure TextAddsParenthesesForRoutines;
    [Test]
    procedure TextFromServerEdit;
    [Test]
    procedure EditsSortedWithUses;
    [Test]
    procedure EditsWithoutUsesSetting;
    [Test]
    procedure CursorAfterWordAndEditsBefore;
    [Test]
    procedure CursorAtMarkerOfLaterEdit;
    [Test]
    procedure SnippetWordStartFromServerEdit;
    [Test]
    procedure SnippetEditsShiftByEditsBefore;
    [Test]
    procedure LinkedFieldsShiftedByEdits;
    [Test]
    procedure GuardAfterConstructor;
    [Test]
    procedure SnippetPadOnlyOnEmptyLine;
  end;

implementation

uses
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Completion.CommitPlan;

function Context(const AText, ALineText: string; ALine, AWordStart, ACharacter: Integer): TAtlasCommitContext;
begin
  Result := Default(TAtlasCommitContext);
  Result.Text := AText;
  Result.LineText := ALineText;
  Result.Line := ALine;
  Result.WordStart := AWordStart;
  Result.Character := ACharacter;
  Result.CommitWordEnd := -1;
end;

function Item(const AName: string; AKind: TAtlasItemKind): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.Kind := AKind;
end;

function TextEdit(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer; const ANewText: string):
  TAtlasTextEdit;
begin
  Result.StartLine := AStartLine;
  Result.StartCharacter := AStartCharacter;
  Result.EndLine := AEndLine;
  Result.EndCharacter := AEndCharacter;
  Result.NewText := ANewText;
end;

{ TCompletionCommitPlanTests }

procedure TCompletionCommitPlanTests.WordEndAtCommitCharacterOrIdentifierEnd;
begin
  Assert.AreEqual(7, TAtlasCommitPlan.WordEnd('WriteLn(x)', 3, -1));
  Assert.AreEqual(3, TAtlasCommitPlan.WordEnd('Wri;', 3, 3));
  Assert.AreEqual(3, TAtlasCommitPlan.WordEnd('Wri ', 3, -1));
end;

procedure TCompletionCommitPlanTests.TextKeepsTypedCaseWithoutFixCase;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
begin
  mItem := Item('WriteLn', TAtlasItemKind.Variable);
  mContext := Context('wri', 'wri', 1, 0, 3);
  Assert.AreEqual('writeLn', TAtlasCommitPlan.TextOf(mItem, mContext).Text);
  mContext.FixCase := True;
  Assert.AreEqual('WriteLn', TAtlasCommitPlan.TextOf(mItem, mContext).Text);
  mItem.InsertText := 'WriteLn<T>';
  Assert.AreEqual('WriteLn<T>', TAtlasCommitPlan.TextOf(mItem, mContext).Text);
end;

procedure TCompletionCommitPlanTests.TextAddsParenthesesForRoutines;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mText: TAtlasCommitText;
begin
  mItem := Item('WriteLn', TAtlasItemKind.Procedure_);
  mItem.HasParameters := True;
  mContext := Context('Wri', 'Wri', 1, 0, 3);
  mContext.AutoParentheses := True;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  Assert.AreEqual('WriteLn()', mText.Text);
  Assert.IsTrue(mText.AutoParen);
  Assert.AreEqual(9, mText.CaretMarker);
  // Mit einem Commit-Zeichen übernommen: keine Klammern.
  mContext.CommitWordEnd := 3;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  Assert.AreEqual('WriteLn', mText.Text);
  Assert.IsFalse(mText.AutoParen);
  Assert.AreEqual(0, mText.CaretMarker);
  // Folgt schon „(“: keine Klammern.
  mContext := Context('Wri(', 'Wri(', 1, 0, 3);
  mContext.AutoParentheses := True;
  Assert.IsFalse(TAtlasCommitPlan.TextOf(mItem, mContext).AutoParen);
end;

procedure TCompletionCommitPlanTests.TextFromServerEdit;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mText: TAtlasCommitText;
begin
  mItem := Item('Create', TAtlasItemKind.Constructor_);
  mItem.HasParameters := True;
  mItem.HasTextEdit := True;
  mItem.TextEdit := TextEdit(0, 0, 0, 3, 'Create($0)');
  mContext := Context('Cre', 'Cre', 1, 0, 3);
  mContext.AutoParentheses := True;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  Assert.AreEqual('Create()', mText.Text);
  Assert.AreEqual(8, mText.CaretMarker);
  Assert.IsFalse(mText.AutoParen);
end;

procedure TCompletionCommitPlanTests.EditsSortedWithUses;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mText: TAtlasCommitText;
  mEdits: TAtlasCommitEdits;
begin
  mItem := Item('Größe', TAtlasItemKind.Variable);
  mItem.AdditionalEdits := TArray<TAtlasTextEdit>.Create(TextEdit(0, 0, 0, 0, 'uses X;'#10));
  mContext := Context('ä'#10'  Grö', '  Grö', 2, 2, 5);
  mContext.AutoUses := True;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, mText);
  Assert.AreEqual(2, Integer(Length(mEdits)));
  Assert.AreEqual(0, mEdits[0].Start);
  Assert.IsFalse(mEdits[0].IsWord);
  // Zeile 2 beginnt nach „ä“ und #10 bei Byte 3, das Wort zwei Zeichen weiter; „ö“ hat zwei Bytes.
  Assert.AreEqual(5, mEdits[1].Start);
  Assert.AreEqual(9, mEdits[1].Stop);
  Assert.IsTrue(mEdits[1].IsWord);
  Assert.AreEqual('Größe', mEdits[1].Text);
end;

procedure TCompletionCommitPlanTests.EditsWithoutUsesSetting;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mEdits: TAtlasCommitEdits;
begin
  mItem := Item('Foo', TAtlasItemKind.Variable);
  mItem.AdditionalEdits := TArray<TAtlasTextEdit>.Create(TextEdit(0, 0, 0, 0, 'uses X;'#10));
  mContext := Context('Fo', 'Fo', 1, 0, 2);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, TAtlasCommitPlan.TextOf(mItem, mContext));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  // Aktionen immer.
  mItem.IsAction := True;
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, TAtlasCommitPlan.TextOf(mItem, mContext));
  Assert.AreEqual(2, Integer(Length(mEdits)));
end;

procedure TCompletionCommitPlanTests.CursorAfterWordAndEditsBefore;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mText: TAtlasCommitText;
  mEdits: TAtlasCommitEdits;
begin
  mItem := Item('WriteLn', TAtlasItemKind.Procedure_);
  mItem.HasParameters := True;
  mItem.AdditionalEdits := TArray<TAtlasTextEdit>.Create(TextEdit(0, 0, 0, 0, 'X'#10));
  mContext := Context('a'#10'  Wri', '  Wri', 2, 2, 5);
  mContext.AutoUses := True;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, mText);
  // Wort ab Byte 4, zwei Bytes davor eingefügt.
  Assert.AreEqual(4 + 2 + 7, TAtlasCommitPlan.CursorByte(mEdits, mContext, mText.CaretMarker));
  mContext.AutoParentheses := True;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, mText);
  Assert.AreEqual(4 + 2 + 8, TAtlasCommitPlan.CursorByte(mEdits, mContext, mText.CaretMarker));
  // Hinter das Commit-Zeichen.
  mContext.AutoParentheses := False;
  mContext.CommitWordEnd := 5;
  mContext.CommitSuffixBytes := 1;
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, mText);
  Assert.AreEqual(4 + 2 + 7 + 1, TAtlasCommitPlan.CursorByte(mEdits, mContext, mText.CaretMarker));
end;

procedure TCompletionCommitPlanTests.CursorAtMarkerOfLaterEdit;
var
  mContext: TAtlasCommitContext;
  mItem: TAtlasCompletionItem;
  mText: TAtlasCommitText;
  mEdits: TAtlasCommitEdits;
begin
  mItem := Item('Run', TAtlasItemKind.Variable);
  mItem.IsAction := True;
  mItem.AdditionalEdits := TArray<TAtlasTextEdit>.Create(TextEdit(1, 0, 1, 0, 'begin $0end'));
  mContext := Context('Ru'#10'x', 'Ru', 1, 0, 2);
  mText := TAtlasCommitPlan.TextOf(mItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(mItem, mContext, mText);
  Assert.AreEqual('begin end', mEdits[1].Text);
  // „Run“ statt „Ru“ verschiebt um ein Byte; die Marke steht nach „begin “ ab Byte 3.
  Assert.AreEqual(3 + 1 + 6, TAtlasCommitPlan.CursorByte(mEdits, mContext, mText.CaretMarker));
end;

procedure TCompletionCommitPlanTests.SnippetWordStartFromServerEdit;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := Item('for', TAtlasItemKind.Snippet);
  Assert.AreEqual(4, TAtlasCommitPlan.SnippetWordStart(mItem, 3, 4));
  mItem.HasTextEdit := True;
  mItem.TextEdit := TextEdit(2, 1, 2, 5, 'for');
  Assert.AreEqual(1, TAtlasCommitPlan.SnippetWordStart(mItem, 3, 4));
  Assert.AreEqual(4, TAtlasCommitPlan.SnippetWordStart(mItem, 2, 4));
end;

procedure TCompletionCommitPlanTests.SnippetEditsShiftByEditsBefore;
var
  mItem: TAtlasCompletionItem;
  mExpansion: TAtlasSnippetExpansion;
  mPlace: TAtlasCommitSnippetPlace;
  mEdits: TAtlasCommitEdits;
  mShift: Integer;
begin
  mItem := Item('try', TAtlasItemKind.Snippet);
  mItem.AdditionalEdits := TArray<TAtlasTextEdit>.Create(TextEdit(0, 0, 0, 1, 'uses'), TextEdit(1, 5, 1, 5, ';'));
  mExpansion := Default(TAtlasSnippetExpansion);
  mExpansion.Text := 'try end';
  mPlace.Text := 'x'#10'  tr';
  mPlace.LineBreak := #13#10;
  mPlace.Line := 2;
  mPlace.WordStart := 2;
  mPlace.WordEnd := 4;
  mEdits := TAtlasCommitPlan.SnippetEdits(mItem, mPlace, mExpansion, mShift);
  Assert.AreEqual(3, Integer(Length(mEdits)));
  Assert.IsFalse(mEdits[0].IsWord);
  Assert.IsTrue(mEdits[1].IsWord);
  Assert.AreEqual(4, mEdits[1].CharStart);
  Assert.AreEqual(6, mEdits[1].CharStop);
  // Nur die Änderung davor verschiebt: „x“ wird zu „uses“.
  Assert.AreEqual(3, mShift);
end;

procedure TCompletionCommitPlanTests.LinkedFieldsShiftedByEdits;
var
  mEdits: TAtlasCommitEdits;
  mStop: TAtlasSnippetStop;
  mFields: TArray<TAtlasPlaceholderField>;
begin
  SetLength(mEdits, 2);
  mEdits[0] := Default(TAtlasCommitEdit);
  mEdits[0].CharStart := 0;
  mEdits[0].CharStop := 1;
  mEdits[0].Text := 'abc';
  mEdits[1] := Default(TAtlasCommitEdit);
  mEdits[1].CharStart := 10;
  mEdits[1].CharStop := 10;
  mEdits[1].Text := 'Name';
  mStop.Number := 1;
  mStop.Start := 0;
  mStop.Length := 4;
  mEdits[1].Stops := TArray<TAtlasSnippetStop>.Create(mStop);
  mFields := TAtlasCommitPlan.LinkedFields(mEdits);
  Assert.AreEqual(1, Integer(Length(mFields)));
  Assert.AreEqual(1, mFields[0].Number);
  Assert.AreEqual(12, mFields[0].Start);
  Assert.AreEqual(4, mFields[0].Length);
end;

procedure TCompletionCommitPlanTests.GuardAfterConstructor;
begin
  Assert.AreEqual<TAtlasCommitGuard>(TAtlasCommitGuard.None, TAtlasCommitPlan.Guard(TAtlasItemKind.Method, 'Foo;', 3));
  Assert.AreEqual<TAtlasCommitGuard>(TAtlasCommitGuard.Watch,
    TAtlasCommitPlan.Guard(TAtlasItemKind.Constructor_, 'Create', -1));
  Assert.AreEqual<TAtlasCommitGuard>(TAtlasCommitGuard.InvokeNow,
    TAtlasCommitPlan.Guard(TAtlasItemKind.Constructor_, 'Create;', 6));
  Assert.AreEqual<TAtlasCommitGuard>(TAtlasCommitGuard.Watch,
    TAtlasCommitPlan.Guard(TAtlasItemKind.Constructor_, 'Create(', 6));
end;

procedure TCompletionCommitPlanTests.SnippetPadOnlyOnEmptyLine;
begin
  Assert.AreEqual('    ', TAtlasCommitPlan.SnippetPad('  ', 6, 2));
  Assert.AreEqual('', TAtlasCommitPlan.SnippetPad('  x', 6, 3));
  Assert.AreEqual('', TAtlasCommitPlan.SnippetPad('', 0, 0));
end;

end.
