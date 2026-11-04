unit Atlas.Common.Editing.Extract.Shared.Tests;

// Tests für die gemeinsamen Teile der Extrahieren-Aktionen (Atlas.Common.Editing.Extract.Shared): Auswahl auf
// Token zuschneiden, Sperren, Kopf der neuen Routine (frei, Methode, Klasse fehlt), Signatur und Rumpf; dazu
// TMethodExtraction aus Atlas.Common.Editing.Extract.Method direkt mit Grund bei Ablehnung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExtractSharedTests = class
  public
    [Test]
    procedure TrimmedSkipsCommentsAndSemicolons;
    [Test]
    procedure SelectionRejectsEmptyRangeAndMissingTree;
    [Test]
    procedure InsideBlockedNamesAnonymousMethod;
    [Test]
    procedure RoutineOnlyNamesListsNestedRoutinesAndTypes;
    [Test]
    procedure HeadOfFreeRoutine;
    [Test]
    procedure HeadOfMethodAddsPrivateDeclaration;
    [Test]
    procedure HeadReportsMissingClass;
    [Test]
    procedure SignatureJoinsParametersAndDeclarations;
    [Test]
    procedure MethodExtractionReportsReason;
    [Test]
    procedure MethodExtractionBuildsCall;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Extract.Shared,
  Atlas.Common.Editing.Extract.Method;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Kopfanfrage für die Routine, in der AMarker steht.</summary>
function Request(ATree: TSyntaxTree; const AText, AMarker: string): TRoutineHeadRequest;
begin
  Result := Default(TRoutineHeadRequest);
  Result.Routine := TRoutineBody.RoutineAt(ATree, Pos(AMarker, AText) - 1);
  Result.Body := TRoutineBody.BodyOf(Result.Routine);
  Result.BaseName := cExtractedMethodName;
  Result.Kind := 'procedure';
  Result.Params := '(const A: Integer)';
  Result.Style := TExtractOptions.Default.Style;
end;

procedure TExtractSharedTests.TrimmedSkipsCommentsAndSemicolons;
var
  mText: string;
  mTokens: TArray<TPascalToken>;
  mStart, mEnd: Integer;
begin
  mText := '  { Notiz } X := 1; ;  ';
  mTokens := TPascalLexer.Tokenize(mText);
  Assert.IsTrue(TExtractSupport.Trimmed(mTokens, 0, Length(mText), mStart, mEnd));
  Assert.AreEqual('X := 1', Copy(mText, mStart + 1, mEnd - mStart));
  Assert.IsFalse(TExtractSupport.Trimmed(mTokens, 0, Pos('X', mText) - 1, mStart, mEnd), 'nur Kommentar');
end;

procedure TExtractSharedTests.SelectionRejectsEmptyRangeAndMissingTree;
var
  mText: string;
  mTree: TSyntaxTree;
  mStart, mEnd: Integer;
begin
  mText := Join(['procedure P;', 'begin', '  X := 1;', 'end;']);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsFalse(TExtractSupport.Selection(mText, mTree, TTextRange.Create(2, 2, 2, 2), mStart, mEnd));
    Assert.IsFalse(TExtractSupport.Selection(mText, nil, TTextRange.Create(2, 2, 2, 9), mStart, mEnd));
    Assert.IsTrue(TExtractSupport.Selection(mText, mTree, TTextRange.Create(2, 0, 2, 9), mStart, mEnd));
    Assert.AreEqual('X := 1', Copy(mText, mStart + 1, mEnd - mStart));
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.InsideBlockedNamesAnonymousMethod;
var
  mText, mReason: string;
  mTree: TSyntaxTree;
  mRoutine, mInner: TSyntaxNode;
  mOffset: Integer;
begin
  mText := Join(['procedure P;', 'begin', '  Run(procedure', '    begin', '      Y := 2;', '    end);',
    '  X := 1;', 'end;']);
  mTree := TPascalParser.Parse(mText);
  try
    mRoutine := TRoutineBody.RoutineAt(mTree, Pos('Run', mText));
    mOffset := Pos('Y :=', mText) - 1;
    mInner := TRoutineBody.Enclosing(TRoutineBody.BodyOf(mRoutine), mOffset, mOffset + Length('Y := 2'));
    Assert.IsTrue(TExtractSupport.InsideBlocked(mInner, TRoutineBody.BodyOf(mRoutine), mReason));
    Assert.AreEqual('in einer anonymen Methode', mReason);
    mOffset := Pos('X :=', mText) - 1;
    mInner := TRoutineBody.Enclosing(TRoutineBody.BodyOf(mRoutine), mOffset, mOffset + Length('X := 1'));
    Assert.IsFalse(TExtractSupport.InsideBlocked(mInner, TRoutineBody.BodyOf(mRoutine), mReason));
    Assert.AreEqual('', mReason);
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.RoutineOnlyNamesListsNestedRoutinesAndTypes;
var
  mText: string;
  mTree: TSyntaxTree;
  mNames: TArray<string>;
begin
  mText := Join(['procedure P;', 'type', '  TLocal = Integer;', '  procedure Inner;', '  begin', '  end;',
    'begin', '  Inner;', 'end;']);
  mTree := TPascalParser.Parse(mText);
  try
    mNames := TExtractSupport.RoutineOnlyNames(TRoutineBody.RoutineAt(mTree, Pos('  Inner;', mText) + 2));
    Assert.AreEqual('TLocal,Inner', string.Join(',', mNames));
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.HeadOfFreeRoutine;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mHead: TRoutineHead;
begin
  mText := Join(['procedure P;', 'begin', '  X := 1;', 'end;']);
  mTree := TPascalParser.Parse(mText);
  try
    mEdits := nil;
    Assert.IsTrue(TExtractSupport.NewRoutineHead(mText, mTree, Request(mTree, mText, 'X :='), mEdits, mHead));
    Assert.AreEqual('ExtractedMethod', mHead.ShortName);
    Assert.AreEqual('procedure ExtractedMethod(const A: Integer);'#10, mHead.Text);
    Assert.AreEqual(0, Integer(Length(mEdits)));
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.HeadOfMethodAddsPrivateDeclaration;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mHead: TRoutineHead;
begin
  mText := Join(['unit U;', 'interface', 'type', '  TFoo = class', '  public', '    procedure P;', '  end;',
    'implementation', 'procedure TFoo.P;', 'begin', '  X := 1;', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mEdits := nil;
    Assert.IsTrue(TExtractSupport.NewRoutineHead(mText, mTree, Request(mTree, mText, 'X :='), mEdits, mHead));
    Assert.AreEqual('procedure TFoo.ExtractedMethod(const A: Integer);'#10, mHead.Text);
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.IsTrue(Pos('private', TChangeSignature.ApplyEdits(mText, mEdits)) > 0, 'private-Abschnitt');
    Assert.IsTrue(Pos('procedure ExtractedMethod(const A: Integer);', TChangeSignature.ApplyEdits(mText,
      mEdits)) > 0, 'Deklaration');
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.HeadReportsMissingClass;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mHead: TRoutineHead;
begin
  mText := Join(['unit U;', 'implementation', 'procedure TBar.P;', 'begin', '  X := 1;', 'end;', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    mEdits := nil;
    Assert.IsFalse(TExtractSupport.NewRoutineHead(mText, mTree, Request(mTree, mText, 'X :='), mEdits, mHead));
    Assert.AreEqual('Klasse TBar nicht in der Datei', mHead.Reason);
  finally
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.SignatureJoinsParametersAndDeclarations;
var
  mText, mRoutineText: string;
  mTree: TSyntaxTree;
  mSignature: TExtractSignature;
begin
  mText := Join(['procedure P;', 'begin', '  X := 1;', 'end;']);
  mTree := TPascalParser.Parse(mText);
  mSignature := TExtractSignature.Create(mText, mTree, TRoutineBody.RoutineAt(mTree, Pos('X :=', mText)),
    TExtractOptions.Default);
  try
    Assert.AreEqual('', mSignature.ParamsText);
    Assert.AreEqual('', mSignature.ArgsText);
    mSignature.AddParameter('const ', 'A', 'Integer');
    mSignature.AddParameter('var ', 'B', 'string');
    mSignature.AddVariable('C', 'Double');
    Assert.AreEqual('(const A: Integer; var B: string)', mSignature.ParamsText);
    Assert.AreEqual('(A, B)', mSignature.ArgsText);
    mRoutineText := mSignature.RoutineText('procedure Q;'#10, 'C := A;', '  ');
    Assert.AreEqual(Join(['procedure Q;', 'var', '  C: Double;', 'begin', '  C := A;', 'end;', '']), mRoutineText);
  finally
    mSignature.Free;
    mTree.Free;
  end;
end;

/// <summary>Ergebnis von TMethodExtraction für die Zeilen AFirst bis ALast (ganze Zeilen); '-' ohne Angebot.
/// </summary>
function Extracted(const AText: string; AFirst, ALast: Integer; out AReason: string): string;
var
  mTree: TSyntaxTree;
  mExtraction: TMethodExtraction;
  mAction: TCodeAction;
begin
  Result := '-';
  mTree := TPascalParser.Parse(AText);
  mExtraction := TMethodExtraction.Create(AText, mTree, TExtractOptions.Default);
  try
    if mExtraction.Run(TTextRange.Create(AFirst, 0, ALast + 1, 0), mAction, AReason) then
    begin
      Result := TChangeSignature.ApplyEdits(AText, mAction.Edits);
    end;
  finally
    mExtraction.Free;
    mTree.Free;
  end;
end;

procedure TExtractSharedTests.MethodExtractionReportsReason;
var
  mReason: string;
begin
  Assert.AreEqual('-', Extracted(Join(['procedure P;', 'begin', '  Exit;', 'end;']), 2, 2, mReason));
  Assert.AreEqual('Exit in der Auswahl', mReason);
  Assert.AreEqual('-', Extracted(Join(['function F: Integer;', 'begin', '  Result := 1;', 'end;']), 2, 2,
    mReason));
  Assert.AreEqual('Result in der Auswahl', mReason);
end;

procedure TExtractSharedTests.MethodExtractionBuildsCall;
var
  mReason, mResult: string;
begin
  mResult := Extracted(Join(['procedure P(A: Integer);', 'var', '  B: Integer;', 'begin', '  B := A + 1;',
    '  Use(B);', 'end;']), 4, 4, mReason);
  Assert.AreEqual('', mReason);
  Assert.IsTrue(Pos('procedure ExtractedMethod(const A: Integer; out B: Integer);', mResult) > 0, mResult);
  Assert.IsTrue(Pos('  ExtractedMethod(A, B);', mResult) > 0, mResult);
end;

end.
