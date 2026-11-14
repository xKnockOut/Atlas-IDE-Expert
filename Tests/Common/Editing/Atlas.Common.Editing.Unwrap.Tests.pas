unit Atlas.Common.Editing.Unwrap.Tests;

// Tests für „Umschließung entfernen“ (#657): jedes Konstrukt mit erwartetem
// Ergebnis und Einrückung, Kommentare im Rumpf, Semikolons vor else,
// begin … end hinter then/do, with mit zwei Objekten, try in try,
// Direktiven, Vorschau-Bereiche und höchstens fünf Ebenen. Jedes Ergebnis
// muss fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnwrapTests = class
  public
    [Test]
    procedure BeginEndInList;
    [Test]
    procedure RoutineBodyIsNotOffered;
    [Test]
    procedure BeginEndAfterThen;
    [Test]
    procedure BeginEndBeforeElse;
    [Test]
    procedure IfElseBranches;
    [Test]
    procedure TryFinallyVariants;
    [Test]
    procedure TryExceptWarnsAboutRaise;
    [Test]
    procedure NestedTry;
    [Test]
    procedure Loops;
    [Test]
    procedure SeveralStatementsGetBeginEnd;
    [Test]
    procedure SemicolonBeforeElse;
    [Test]
    procedure InlineAndMidLine;
    [Test]
    procedure Directives;
    [Test]
    procedure WithTwoObjects;
    [Test]
    procedure WithWithoutResolverIsNoted;
    [Test]
    procedure PreviewRanges;
    [Test]
    procedure AtMostFiveLevels;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.WithResolution,
  Atlas.Common.Editing.Unwrap;

const
  cHead = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10;
  cTail = #13#10'end;'#13#10'end.'#13#10;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + #13#10;
    end;
    Result := Result + ALines[mIndex];
  end;
end;

/// <summary>Position des ersten ANeedle im Rumpf (Zeilen ab 5).</summary>
function At(const ABody, ANeedle: string): TTextPosition;
var
  mLines: TArray<string>;
  mIndex, mColumn: Integer;
begin
  mLines := ABody.Split([#13#10]);
  for mIndex := 0 to High(mLines) do
  begin
    mColumn := Pos(ANeedle, mLines[mIndex]);
    if mColumn > 0 then
    begin
      Exit(TTextPosition.Create(5 + mIndex, mColumn - 1));
    end;
  end;
  raise Exception.Create('nicht gefunden: ' + ANeedle);
end;

function CandidatesOf(const ABody, ANeedle: string; const AOptions: TUnwrapOptions): TArray<TUnwrapCandidate>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cHead + ABody + cTail);
  try
    Result := TUnwrap.Candidates(cHead + ABody + cTail, mTree, At(ABody, ANeedle), AOptions);
  finally
    mTree.Free;
  end;
end;

function Find(const ABody, ANeedle: string): TArray<TUnwrapCandidate>;
begin
  Result := CandidatesOf(ABody, ANeedle, TUnwrapOptions.Default);
end;

/// <summary>Rumpf nach Anwenden der Variante; das Ergebnis muss fehlerfrei parsen.</summary>
function Apply(const ABody: string; const AVariant: TUnwrapVariant): string;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := TChangeSignature.ApplyEdits(cHead + ABody + cTail, AVariant.Edits);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'parst nicht: ' + mText);
  finally
    mTree.Free;
  end;
  Assert.IsTrue(mText.StartsWith(cHead) and mText.EndsWith(cTail), mText);
  Result := Copy(mText, Length(cHead) + 1, Length(mText) - Length(cHead) - Length(cTail));
end;

function TextOf(const ABody: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
begin
  mLines := (cHead + ABody + cTail).Split([#13#10]);
  Assert.AreEqual(ARange.StartPos.Line, ARange.EndPos.Line, 'Stück über mehrere Zeilen');
  Result := Copy(mLines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
    ARange.EndPos.Character - ARange.StartPos.Character);
end;

function Texts(const ABody: string; const ARanges: TArray<TTextRange>): string;
var
  mRange: TTextRange;
begin
  Result := '';
  for mRange in ARanges do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + TextOf(ABody, mRange);
  end;
end;

procedure TUnwrapTests.BeginEndInList;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  X;', '  begin', '    Y; // bleibt', '    { auch das }', '    Z;', '  end;', '  W;']);
  mFound := Find(mBody, 'Y;');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y; // bleibt', '  { auch das }', '  Z;', '  W;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.RoutineBodyIsNotOffered;
begin
  Assert.AreEqual(0, Integer(Length(Find(Join(['  X;', '  Y;']), 'Y;'))));
end;

procedure TUnwrapTests.BeginEndAfterThen;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then', '  begin', '    X;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.IfThen), Ord(mFound[1].Kind));
  Assert.AreEqual(Join(['  if A then', '    X;']), Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual('  X;', Apply(mBody, mFound[1].Variants[0]));
  // Ein Block mit zwei Anweisungen hinter then wird nicht angeboten.
  mBody := Join(['  if A then', '  begin', '    X;', '    Y;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.BeginEndBeforeElse;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then', '  begin', '    X;', '  end', '  else', '    Y;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.IfElseBranches;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then', '    X', '  else', '  begin', '    Y;', '    Z;', '  end;']);
  mFound := Find(mBody, 'X');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.IfThen), Ord(mFound[0].Kind));
  Assert.AreEqual(2, Integer(Length(mFound[0].Variants)));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ThenBranch), Ord(mFound[0].Variants[0].Kind));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ElseBranch), Ord(mFound[0].Variants[1].Kind));
  Assert.AreEqual('  X;', Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual(Join(['  Y;', '  Z;']), Apply(mBody, mFound[0].Variants[1]));
  // Ohne else nur der then-Zweig.
  mBody := Join(['  if A then', '    X;', '  W;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(1, Integer(Length(mFound[0].Variants)));
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.TryFinallyVariants;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  L := TList.Create;', '  try', '    L.Add(1); // eins', '  finally', '    L.Free;', '  end;']);
  mFound := Find(mBody, 'L.Add');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapVariantKind.KeepFinally), Ord(mFound[0].Variants[0].Kind));
  Assert.AreEqual(Join(['  L := TList.Create;', '  L.Add(1); // eins', '  L.Free;']),
    Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual(Ord(TUnwrapVariantKind.DropFinally), Ord(mFound[0].Variants[1].Kind));
  Assert.AreEqual(Join(['  L := TList.Create;', '  L.Add(1); // eins']), Apply(mBody, mFound[0].Variants[1]));
  // Ohne Semikolon vor finally kommt eins dazu.
  mBody := Join(['  try', '    X', '  finally', '    Y', '  end;']);
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(mBody, Find(mBody, 'X')[0].Variants[0]));
end;

procedure TUnwrapTests.TryExceptWarnsAboutRaise;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  try', '    X;', '  except', '    on E: EA do raise;', '    on E: EB do raise;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.TryExcept), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.MultipleRaise), Ord(mFound[0].Note));
  Assert.AreEqual('2', mFound[0].NoteText);
  Assert.AreEqual('  X;', Apply(mBody, mFound[0].Variants[0]));
  mBody := Join(['  try', '    X;', '  except', '    raise;', '  end;']);
  Assert.AreEqual(Ord(TUnwrapNote.None), Ord(Find(mBody, 'X;')[0].Note));
end;

procedure TUnwrapTests.NestedTry;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  try', '    try', '      X;', '    except', '      Y;', '    end;', '  finally', '    Z;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.TryExcept), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(mFound[1].Kind));
  Assert.AreEqual(Join(['  try', '    X;', '  finally', '    Z;', '  end;']), Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual(Join(['  try', '    X;', '  except', '    Y;', '  end;', '  Z;']), Apply(mBody, mFound[1].Variants[0]));
end;

procedure TUnwrapTests.Loops;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  for I := 1 to 3 do', '    X(I);']);
  mFound := Find(mBody, 'X(I)');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.LoopVariable), Ord(mFound[0].Note));
  Assert.AreEqual('I', mFound[0].NoteText);
  Assert.AreEqual('  X(I);', Apply(mBody, mFound[0].Variants[0]));

  mBody := Join(['  for S in L do', '  begin', '    X(S);', '    Y;', '  end;']);
  mFound := Find(mBody, 'X(S)');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(mFound[0].Kind));
  Assert.AreEqual('S', mFound[0].NoteText);
  Assert.AreEqual(Join(['  X(S);', '  Y;']), Apply(mBody, mFound[0].Variants[0]));

  mBody := Join(['  while A do', '  begin', '    X;', '    Y;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.WhileDo), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.None), Ord(mFound[0].Note));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(mBody, mFound[0].Variants[0]));

  mBody := Join(['  repeat', '    X;', '    Y', '  until A;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.RepeatUntil), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.SeveralStatementsGetBeginEnd;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then', '    while B do', '    begin', '      X;', '      Y;', '    end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.WhileDo), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  if A then', '  begin', '    X;', '    Y;', '  end;']), Apply(mBody, mFound[0].Variants[0]));
  // try … finally hinter do mit beiden Teilen.
  mBody := Join(['  for I := 1 to 2 do', '    try', '      X;', '    finally', '      Y;', '    end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  for I := 1 to 2 do', '  begin', '    X;', '    Y;', '  end;']),
    Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual(Join(['  for I := 1 to 2 do', '    X;']), Apply(mBody, mFound[0].Variants[1]));
end;

procedure TUnwrapTests.SemicolonBeforeElse;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then', '    for I := 1 to 2 do', '      X;', '  W;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Join(['  if A then', '    X;', '  W;']), Apply(mBody, mFound[0].Variants[0]));
  mBody := Join(['  if A then', '    for I := 1 to 2 do', '      X', '  else', '    Y;']);
  mFound := Find(mBody, 'X');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.InlineAndMidLine;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  if A then X;', '  W;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(mBody, mFound[0].Variants[0]));
  mBody := Join(['  Q; if A then X; W;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual('  Q; X; W;', Apply(mBody, mFound[0].Variants[0]));
  mBody := Join(['  if A then begin', '    X;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X;']), Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual('  X;', Apply(mBody, mFound[1].Variants[0]));
  mBody := Join(['  if A then begin', '    X;', '  end else', '    Y;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.Directives;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['{$IFDEF DEBUG}', '  X;', '{$ELSE}', '  Y;', '{$ENDIF}', '  W;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.IfDef), Ord(mFound[0].Kind));
  Assert.AreEqual(2, Integer(Length(mFound[0].Variants)));
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(mBody, mFound[0].Variants[0]));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ElseBranch), Ord(mFound[0].Variants[1].Kind));
  Assert.AreEqual(Join(['  Y;', '  W;']), Apply(mBody, mFound[0].Variants[1]));

  mBody := Join(['  {$REGION ''Teil''}', '  X;', '  Y;', '  {$ENDREGION}']);
  mFound := Find(mBody, 'Y;');
  Assert.AreEqual(Ord(TUnwrapKind.Region), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(mBody, mFound[0].Variants[0]));

  // Direktive in einem Block: der Block ist innen, die Direktive außen.
  mBody := Join(['  {$IFDEF A}', '  begin', '    X;', '  end;', '  {$ENDIF}']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(mFound[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.IfDef), Ord(mFound[1].Kind));
end;

function Owners(AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner;
begin
  AElement := -1;
  Result := TWithOwner.Other;
  if SameText(AIdentifier.Name, 'Caption') then
  begin
    AElement := 0;
  end
  else if SameText(AIdentifier.Name, 'Width') then
  begin
    AElement := 1;
  end;
  if AElement >= 0 then
  begin
    Result := TWithOwner.Element;
  end;
end;

procedure TUnwrapTests.WithTwoObjects;
var
  mBody, mText: string;
  mTree: TSyntaxTree;
  mOptions: TUnwrapOptions;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  with A, B do', '  begin', '    Caption := IntToStr(Width); // Kommentar', '    X;', '  end;']);
  mText := cHead + mBody + cTail;
  mTree := TPascalParser.Parse(mText);
  try
    mOptions := TUnwrapOptions.Default;
    mOptions.ResolveWith :=
      function(AWith: TSyntaxNode; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
      var
        Resolved: TWithResolved;
      begin
        Result := TWithResolution.Resolve(mText, mTree, AWith,
          function(AOwnerWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
          begin
            Result := Owners(AIdentifier, AElement);
          end, TExtractOptions.Default, Resolved);
        AEdits := Resolved.Action.Edits;
        AReason := Resolved.Reason;
      end;
    mFound := TUnwrap.Candidates(mText, mTree, At(mBody, 'X;'), mOptions);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TUnwrapKind.WithDo), Ord(mFound[0].Kind));
  Assert.AreEqual(Join(['  A.Caption := IntToStr(B.Width); // Kommentar', '  X;']), Apply(mBody, mFound[0].Variants[0]));
end;

procedure TUnwrapTests.WithWithoutResolverIsNoted;
var
  mFound: TArray<TUnwrapCandidate>;
begin
  mFound := Find(Join(['  with A do', '    X;']), 'X;');
  Assert.AreEqual(Ord(TUnwrapNote.WithUnresolved), Ord(mFound[0].Note));
  Assert.AreEqual(0, Integer(Length(mFound[0].Variants)));
end;

procedure TUnwrapTests.PreviewRanges;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  try', '    X; // a', '  finally', '    Y;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual('X; // a|Y;', Texts(mBody, mFound[0].Variants[0].Keep));
  Assert.AreEqual('try|finally|end', Texts(mBody, mFound[0].Variants[0].Remove));
  Assert.AreEqual('X; // a', Texts(mBody, mFound[0].Variants[1].Keep));
  Assert.AreEqual('try|finally|Y;|end', Texts(mBody, mFound[0].Variants[1].Remove));
  mBody := Join(['  if A then X else Y;']);
  mFound := Find(mBody, 'X');
  Assert.AreEqual('X', Texts(mBody, mFound[0].Variants[0].Keep));
  Assert.AreEqual('if A then|else Y', Texts(mBody, mFound[0].Variants[0].Remove));
end;

procedure TUnwrapTests.AtMostFiveLevels;
var
  mBody: string;
  mFound: TArray<TUnwrapCandidate>;
begin
  mBody := Join(['  begin', '  begin', '  begin', '  begin', '  begin', '  begin', '    X;', '  end;', '  end;', '  end;',
    '  end;', '  end;', '  end;']);
  mFound := Find(mBody, 'X;');
  Assert.AreEqual(5, Integer(Length(mFound)));
  Assert.AreEqual(10, mFound[0].Range.StartPos.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnwrapTests);

end.
