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
  Head = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10;
  Tail = #13#10'end;'#13#10'end.'#13#10;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
  begin
    if Index > 0 then
      Result := Result + #13#10;
    Result := Result + ALines[Index];
  end;
end;

/// <summary>Position des ersten ANeedle im Rumpf (Zeilen ab 5).</summary>
function At(const ABody, ANeedle: string): TTextPosition;
var
  Lines: TArray<string>;
  Index, Column: Integer;
begin
  Lines := ABody.Split([#13#10]);
  for Index := 0 to High(Lines) do
  begin
    Column := Pos(ANeedle, Lines[Index]);
    if Column > 0 then
      Exit(TTextPosition.Create(5 + Index, Column - 1));
  end;
  raise Exception.Create('nicht gefunden: ' + ANeedle);
end;

function CandidatesOf(const ABody, ANeedle: string; const AOptions: TUnwrapOptions): TArray<TUnwrapCandidate>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Head + ABody + Tail);
  try
    Result := TUnwrap.Candidates(Head + ABody + Tail, Tree, At(ABody, ANeedle), AOptions);
  finally
    Tree.Free;
  end;
end;

function Find(const ABody, ANeedle: string): TArray<TUnwrapCandidate>;
begin
  Result := CandidatesOf(ABody, ANeedle, TUnwrapOptions.Default);
end;

/// <summary>Rumpf nach Anwenden der Variante; das Ergebnis muss fehlerfrei parsen.</summary>
function Apply(const ABody: string; const AVariant: TUnwrapVariant): string;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := TChangeSignature.ApplyEdits(Head + ABody + Tail, AVariant.Edits);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'parst nicht: ' + Text);
  finally
    Tree.Free;
  end;
  Assert.IsTrue(Text.StartsWith(Head) and Text.EndsWith(Tail), Text);
  Result := Copy(Text, Length(Head) + 1, Length(Text) - Length(Head) - Length(Tail));
end;

function TextOf(const ABody: string; const ARange: TTextRange): string;
var
  Lines: TArray<string>;
begin
  Lines := (Head + ABody + Tail).Split([#13#10]);
  Assert.AreEqual(ARange.StartPos.Line, ARange.EndPos.Line, 'Stück über mehrere Zeilen');
  Result := Copy(Lines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
    ARange.EndPos.Character - ARange.StartPos.Character);
end;

function Texts(const ABody: string; const ARanges: TArray<TTextRange>): string;
var
  Range: TTextRange;
begin
  Result := '';
  for Range in ARanges do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + TextOf(ABody, Range);
  end;
end;

procedure TUnwrapTests.BeginEndInList;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  X;', '  begin', '    Y; // bleibt', '    { auch das }', '    Z;', '  end;', '  W;']);
  Found := Find(Body, 'Y;');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y; // bleibt', '  { auch das }', '  Z;', '  W;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.RoutineBodyIsNotOffered;
begin
  Assert.AreEqual(0, Integer(Length(Find(Join(['  X;', '  Y;']), 'Y;'))));
end;

procedure TUnwrapTests.BeginEndAfterThen;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then', '  begin', '    X;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.IfThen), Ord(Found[1].Kind));
  Assert.AreEqual(Join(['  if A then', '    X;']), Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual('  X;', Apply(Body, Found[1].Variants[0]));
  // Ein Block mit zwei Anweisungen hinter then wird nicht angeboten.
  Body := Join(['  if A then', '  begin', '    X;', '    Y;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.BeginEndBeforeElse;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then', '  begin', '    X;', '  end', '  else', '    Y;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.IfElseBranches;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then', '    X', '  else', '  begin', '    Y;', '    Z;', '  end;']);
  Found := Find(Body, 'X');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.IfThen), Ord(Found[0].Kind));
  Assert.AreEqual(2, Integer(Length(Found[0].Variants)));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ThenBranch), Ord(Found[0].Variants[0].Kind));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ElseBranch), Ord(Found[0].Variants[1].Kind));
  Assert.AreEqual('  X;', Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual(Join(['  Y;', '  Z;']), Apply(Body, Found[0].Variants[1]));
  // Ohne else nur der then-Zweig.
  Body := Join(['  if A then', '    X;', '  W;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(1, Integer(Length(Found[0].Variants)));
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.TryFinallyVariants;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  L := TList.Create;', '  try', '    L.Add(1); // eins', '  finally', '    L.Free;', '  end;']);
  Found := Find(Body, 'L.Add');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapVariantKind.KeepFinally), Ord(Found[0].Variants[0].Kind));
  Assert.AreEqual(Join(['  L := TList.Create;', '  L.Add(1); // eins', '  L.Free;']),
    Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual(Ord(TUnwrapVariantKind.DropFinally), Ord(Found[0].Variants[1].Kind));
  Assert.AreEqual(Join(['  L := TList.Create;', '  L.Add(1); // eins']), Apply(Body, Found[0].Variants[1]));
  // Ohne Semikolon vor finally kommt eins dazu.
  Body := Join(['  try', '    X', '  finally', '    Y', '  end;']);
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(Body, Find(Body, 'X')[0].Variants[0]));
end;

procedure TUnwrapTests.TryExceptWarnsAboutRaise;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  try', '    X;', '  except', '    on E: EA do raise;', '    on E: EB do raise;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.TryExcept), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.MultipleRaise), Ord(Found[0].Note));
  Assert.AreEqual('2', Found[0].NoteText);
  Assert.AreEqual('  X;', Apply(Body, Found[0].Variants[0]));
  Body := Join(['  try', '    X;', '  except', '    raise;', '  end;']);
  Assert.AreEqual(Ord(TUnwrapNote.None), Ord(Find(Body, 'X;')[0].Note));
end;

procedure TUnwrapTests.NestedTry;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  try', '    try', '      X;', '    except', '      Y;', '    end;', '  finally', '    Z;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.TryExcept), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(Found[1].Kind));
  Assert.AreEqual(Join(['  try', '    X;', '  finally', '    Z;', '  end;']), Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual(Join(['  try', '    X;', '  except', '    Y;', '  end;', '  Z;']), Apply(Body, Found[1].Variants[0]));
end;

procedure TUnwrapTests.Loops;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  for I := 1 to 3 do', '    X(I);']);
  Found := Find(Body, 'X(I)');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.LoopVariable), Ord(Found[0].Note));
  Assert.AreEqual('I', Found[0].NoteText);
  Assert.AreEqual('  X(I);', Apply(Body, Found[0].Variants[0]));

  Body := Join(['  for S in L do', '  begin', '    X(S);', '    Y;', '  end;']);
  Found := Find(Body, 'X(S)');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(Found[0].Kind));
  Assert.AreEqual('S', Found[0].NoteText);
  Assert.AreEqual(Join(['  X(S);', '  Y;']), Apply(Body, Found[0].Variants[0]));

  Body := Join(['  while A do', '  begin', '    X;', '    Y;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.WhileDo), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapNote.None), Ord(Found[0].Note));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(Body, Found[0].Variants[0]));

  Body := Join(['  repeat', '    X;', '    Y', '  until A;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.RepeatUntil), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.SeveralStatementsGetBeginEnd;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then', '    while B do', '    begin', '      X;', '      Y;', '    end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.WhileDo), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  if A then', '  begin', '    X;', '    Y;', '  end;']), Apply(Body, Found[0].Variants[0]));
  // try … finally hinter do mit beiden Teilen.
  Body := Join(['  for I := 1 to 2 do', '    try', '      X;', '    finally', '      Y;', '    end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.TryFinally), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  for I := 1 to 2 do', '  begin', '    X;', '    Y;', '  end;']),
    Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual(Join(['  for I := 1 to 2 do', '    X;']), Apply(Body, Found[0].Variants[1]));
end;

procedure TUnwrapTests.SemicolonBeforeElse;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then', '    for I := 1 to 2 do', '      X;', '  W;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Join(['  if A then', '    X;', '  W;']), Apply(Body, Found[0].Variants[0]));
  Body := Join(['  if A then', '    for I := 1 to 2 do', '      X', '  else', '    Y;']);
  Found := Find(Body, 'X');
  Assert.AreEqual(Ord(TUnwrapKind.ForDo), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.InlineAndMidLine;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  if A then X;', '  W;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(Body, Found[0].Variants[0]));
  Body := Join(['  Q; if A then X; W;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual('  Q; X; W;', Apply(Body, Found[0].Variants[0]));
  Body := Join(['  if A then begin', '    X;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  if A then', '    X;']), Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual('  X;', Apply(Body, Found[1].Variants[0]));
  Body := Join(['  if A then begin', '    X;', '  end else', '    Y;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(Join(['  if A then', '    X', '  else', '    Y;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.Directives;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['{$IFDEF DEBUG}', '  X;', '{$ELSE}', '  Y;', '{$ENDIF}', '  W;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.IfDef), Ord(Found[0].Kind));
  Assert.AreEqual(2, Integer(Length(Found[0].Variants)));
  Assert.AreEqual(Join(['  X;', '  W;']), Apply(Body, Found[0].Variants[0]));
  Assert.AreEqual(Ord(TUnwrapVariantKind.ElseBranch), Ord(Found[0].Variants[1].Kind));
  Assert.AreEqual(Join(['  Y;', '  W;']), Apply(Body, Found[0].Variants[1]));

  Body := Join(['  {$REGION ''Teil''}', '  X;', '  Y;', '  {$ENDREGION}']);
  Found := Find(Body, 'Y;');
  Assert.AreEqual(Ord(TUnwrapKind.Region), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  X;', '  Y;']), Apply(Body, Found[0].Variants[0]));

  // Direktive in einem Block: der Block ist innen, die Direktive außen.
  Body := Join(['  {$IFDEF A}', '  begin', '    X;', '  end;', '  {$ENDIF}']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.BeginEnd), Ord(Found[0].Kind));
  Assert.AreEqual(Ord(TUnwrapKind.IfDef), Ord(Found[1].Kind));
end;

function Owners(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner;
begin
  AElement := -1;
  Result := TWithOwner.Other;
  if SameText(AIdentifier.Name, 'Caption') then
    AElement := 0
  else if SameText(AIdentifier.Name, 'Width') then
    AElement := 1;
  if AElement >= 0 then
    Result := TWithOwner.Element;
end;

procedure TUnwrapTests.WithTwoObjects;
var
  Body, Text: string;
  Tree: TSyntaxTree;
  Options: TUnwrapOptions;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  with A, B do', '  begin', '    Caption := IntToStr(Width); // Kommentar', '    X;', '  end;']);
  Text := Head + Body + Tail;
  Tree := TPascalParser.Parse(Text);
  try
    Options := TUnwrapOptions.Default;
    Options.ResolveWith :=
      function(AWith: TSyntaxNode; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
      var
        Action: TCodeAction;
      begin
        Result := TWithResolution.Resolve(Text, Tree, AWith,
          function(AOwnerWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
          begin
            Result := Owners(AOwnerWith, AIdentifier, AElement);
          end, TExtractOptions.Default, Action, AReason);
        AEdits := Action.Edits;
      end;
    Found := TUnwrap.Candidates(Text, Tree, At(Body, 'X;'), Options);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TUnwrapKind.WithDo), Ord(Found[0].Kind));
  Assert.AreEqual(Join(['  A.Caption := IntToStr(B.Width); // Kommentar', '  X;']), Apply(Body, Found[0].Variants[0]));
end;

procedure TUnwrapTests.WithWithoutResolverIsNoted;
var
  Found: TArray<TUnwrapCandidate>;
begin
  Found := Find(Join(['  with A do', '    X;']), 'X;');
  Assert.AreEqual(Ord(TUnwrapNote.WithUnresolved), Ord(Found[0].Note));
  Assert.AreEqual(0, Integer(Length(Found[0].Variants)));
end;

procedure TUnwrapTests.PreviewRanges;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  try', '    X; // a', '  finally', '    Y;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual('X; // a|Y;', Texts(Body, Found[0].Variants[0].Keep));
  Assert.AreEqual('try|finally|end', Texts(Body, Found[0].Variants[0].Remove));
  Assert.AreEqual('X; // a', Texts(Body, Found[0].Variants[1].Keep));
  Assert.AreEqual('try|finally|Y;|end', Texts(Body, Found[0].Variants[1].Remove));
  Body := Join(['  if A then X else Y;']);
  Found := Find(Body, 'X');
  Assert.AreEqual('X', Texts(Body, Found[0].Variants[0].Keep));
  Assert.AreEqual('if A then|else Y', Texts(Body, Found[0].Variants[0].Remove));
end;

procedure TUnwrapTests.AtMostFiveLevels;
var
  Body: string;
  Found: TArray<TUnwrapCandidate>;
begin
  Body := Join(['  begin', '  begin', '  begin', '  begin', '  begin', '  begin', '    X;', '  end;', '  end;', '  end;',
    '  end;', '  end;', '  end;']);
  Found := Find(Body, 'X;');
  Assert.AreEqual(5, Integer(Length(Found)));
  Assert.AreEqual(10, Found[0].Range.StartPos.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnwrapTests);

end.
