unit Atlas.Common.Editing.RoutineBody;

// Gemeinsame Bausteine der Refactorings im Rumpf einer Routine (#50): Routine
// und Anweisung an einer Stelle finden, Anweisungslisten erkennen (nur dort
// darf eine neue Anweisung davor stehen), Text eines Knotens, Einrückung,
// eindeutige Namen und neue Einträge im var- bzw. const-Abschnitt der Routine,
// Mitglieder und Felder einer Klasse.
// Ohne Namensauflösung; die Aufrufer bringen sie bei Bedarf mit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Neues Mitglied einer Klasse: Sichtbarkeitsabschnitt und Deklaration ("procedure Rechne;").</summary>
  TMemberEntry = record
    Section: string;
    Declaration: string;
    class function Create(const ASection, ADeclaration: string): TMemberEntry; static;
  end;

  TRoutineBody = class
  public
    /// <summary>Innerste Routine, deren Rumpf (begin … end) AOffset enthält; nil sonst.</summary>
    class function RoutineAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Anweisungsblock einer Routine; nil ohne.</summary>
    class function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Innerster Knoten unter ARoot, der AFirst..ALast (Offsets) ganz enthält.</summary>
    class function Enclosing(ARoot: TSyntaxNode; AFirst, ALast: Integer): TSyntaxNode; static;
    /// <summary>Knoten ist eine Anweisung.</summary>
    class function IsStatement(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Anweisung steht in einer Anweisungsliste (begin … end, try, finally, except ohne Handler,
    /// repeat, else von case): Davor darf eine weitere Anweisung stehen.</summary>
    class function InList(AStatement: TSyntaxNode): Boolean; static;
    /// <summary>ANode liegt in AAncestor (oder ist es).</summary>
    class function Within(ANode, AAncestor: TSyntaxNode): Boolean; static;
    /// <summary>Quelltext eines Knotens.</summary>
    class function TextOf(const AText: string; ANode: TSyntaxNode): string; static;
    /// <summary>Eine Einrückungsstufe nach AStyle.</summary>
    class function IndentUnit(const AStyle: TFormatStyle): string; static;
    /// <summary>ABase, sonst ABase2, ABase3 …, bis kein Bezeichner im Text so heißt (Mitglieder hinter einem Punkt
    /// zählen nicht).</summary>
    class function UniqueName(const ATokens: TArray<TPascalToken>; const ABase: string): string; static;
    /// <summary>Index des ersten Tokens ab AOffset; Length(ATokens) dahinter.</summary>
    class function TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer; static;
    /// <summary>Nächstes bzw. vorheriges Token ohne Kommentare und Direktiven; -1 bzw. Length ohne.</summary>
    class function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer; static;
    class function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer; static;
    /// <summary>Text vor die Anweisung AStatement setzen: ALine, Umbruch und die Einrückung der Anweisung.</summary>
    class function InsertBefore(const AText: string; AStatement: TSyntaxNode; const ALine: string): TTextEdit;
      static;
    /// <summary>Eintrag "AName: AType;" im var-Abschnitt der Routine; ohne Abschnitt entsteht einer direkt vor
    /// dem Rumpf.</summary>
    class function AddVariable(const AText: string; ARoutine: TSyntaxNode; const AName, AType: string;
      const AStyle: TFormatStyle): TTextEdit; static;
    /// <summary>Eintrag "AName = AValue;" im const-Abschnitt der Routine bzw. ein neuer Abschnitt vor dem Rumpf.</summary>
    class function AddConstant(const AText: string; ARoutine: TSyntaxNode; const AName, AValue: string;
      const AStyle: TFormatStyle): TTextEdit; static;
    /// <summary>Text, dessen Zeilen ab der zweiten um ARemove gekürzt (soweit vorhanden) und um AAdd ergänzt
    /// sind; die erste Zeile bekommt nur AAdd.</summary>
    class function Reindent(const ABlock, ARemove, AAdd, ALineBreak: string): string; static;
    /// <summary>Rumpf (class, record oder object) des Typs AName in der Datei; nil ohne.</summary>
    class function TypeBody(ARoot: TSyntaxNode; const AName: string): TSyntaxNode; static;
    /// <summary>Deklaration AMember.Declaration am Ende des Abschnitts AMember.Section ("private", "protected",
    /// "public") der Klasse ABody; bei private zählt auch strict private. Ohne Abschnitt ein neuer vor end, das dann allein am
    /// Zeilenanfang stehen muss.</summary>
    class function MemberDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode;
      const AMember: TMemberEntry; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Feld ADecl ("FName: Typ;") hinter dem letzten Feld des private-Abschnitts der Klasse ABody (auch
    /// strict private), ohne Feld direkt unter private (vor den Methoden); ohne Abschnitt wie MemberDeclaration.
    /// </summary>
    class function FieldDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode; const ADecl: string;
      const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Namen der Mitglieder (Felder, Methoden, Properties) der Typdeklaration ABody.</summary>
    class function MemberNames(ABody: TSyntaxNode): TArray<string>; static;
    /// <summary>Sichtbarkeit des Mitglieds AMember in ABody klein geschrieben ('' ohne Abschnitt).</summary>
    class function VisibilityOf(ABody, AMember: TSyntaxNode): string; static;
    /// <summary>Klasse vor dem Namen: TKunde aus TKunde.Rechne; '' ohne.</summary>
    class function QualifierOf(const AName: string): string; static;
    /// <summary>Name ohne Klasse: Rechne aus TKunde.Rechne.</summary>
    class function ShortNameOf(const AName: string): string; static;
    /// <summary>Zeile, vor der eine neue Routine entsteht: Anfang von ARoutine samt Kommentaren direkt darüber.
    /// </summary>
    class function RoutineInsertLine(const AText: string; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Kette ohne Aufrufe (A, A.B, A[I]): könnte ein var-Argument sein.</summary>
    class function IsVariableChain(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Anweisung, vor die eine Variable für den Ausdruck ANode kommt; nil, wenn der Ausdruck dort nicht
    /// ohne Bedeutungsänderung vorab berechnet werden kann (Ziel einer Zuweisung, var-Argument, Schleifen- oder
    /// case-Bedingung, rechte Seite von and/or, Zweig ohne begin, anonyme Methode, with, asm).</summary>
    class function HostStatement(ANode, ABody: TSyntaxNode): TSyntaxNode; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines;

const
  StatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

{ TMemberEntry }

class function TMemberEntry.Create(const ASection, ADeclaration: string): TMemberEntry;
begin
  Result.Section := ASection;
  Result.Declaration := ADeclaration;
end;

{ TRoutineBody }

class function TRoutineBody.IsStatement(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in StatementKinds);
end;

class function TRoutineBody.BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ARoutine <> nil then
  begin
    Result := ARoutine.FindChild(TSyntaxKind.Block);
  end;
end;

/// <summary>Kind von ANode, das AOffset enthält (Ende eingeschlossen); nil ohne.</summary>
function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset <= AOffset) and (AOffset <= ANode[mIndex].EndOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Liegt AOffset im Rumpf der Routine ARoutine?</summary>
function InRoutineBody(ARoutine: TSyntaxNode; AOffset: Integer): Boolean;
var
  mBody: TSyntaxNode;
begin
  mBody := TRoutineBody.BodyOf(ARoutine);
  Result := (mBody <> nil) and (mBody.StartOffset <= AOffset) and (AOffset <= mBody.EndOffset);
end;

class function TRoutineBody.RoutineAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mNode := ChildAt(ATree.Root, AOffset);
  while mNode <> nil do
  begin
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and InRoutineBody(mNode, AOffset) then
    begin
      Result := mNode;
    end;
    mNode := ChildAt(mNode, AOffset);
  end;
end;

class function TRoutineBody.Enclosing(ARoot: TSyntaxNode; AFirst, ALast: Integer): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := ARoot;
  Node := ARoot;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Node[Index].StartOffset <= AFirst) and (ALast <= Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        Result := Node;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

class function TRoutineBody.InList(AStatement: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Result := False;
  if (AStatement = nil) or (AStatement.Parent = nil) then
  begin
    Exit;
  end;
  Parent := AStatement.Parent;
  case Parent.Kind of
    TSyntaxKind.Block, TSyntaxKind.FinallyBlock, TSyntaxKind.CaseElse:
      Result := True;
    TSyntaxKind.ExceptBlock:
      Result := AStatement.Kind <> TSyntaxKind.ExceptionHandler;
    TSyntaxKind.TryStatement:
      Result := not (AStatement.Kind in [TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock]);
    TSyntaxKind.RepeatStatement:
      // Das letzte Kind ist die Bedingung hinter until.
      Result := Parent[Parent.ChildCount - 1] <> AStatement;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Result := Result and IsStatement(AStatement);
end;

class function TRoutineBody.Within(ANode, AAncestor: TSyntaxNode): Boolean;
begin
  while ANode <> nil do
  begin
    if ANode = AAncestor then
    begin
      Exit(True);
    end;
    ANode := ANode.Parent;
  end;
  Result := False;
end;

class function TRoutineBody.TextOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

class function TRoutineBody.IndentUnit(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
  begin
    Result := #9;
  end
  else if AStyle.IndentSize > 0 then
  begin
    Result := StringOfChar(' ', AStyle.IndentSize);
  end
  else
  begin
    Result := '  ';
  end;
end;

class function TRoutineBody.UniqueName(const ATokens: TArray<TPascalToken>; const ABase: string): string;

  function Taken(const AName: string): Boolean;
  var
    Index, Before: Integer;
  begin
    // Namen hinter einem Punkt (Liste.Count) sind Mitglieder und kollidieren nicht.
    for Index := 0 to High(ATokens) do
    begin
      if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) then
      begin
        Before := PreviousToken(ATokens, Index);
        if (Before < 0) or not ATokens[Before].IsSymbol('.') then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

var
  Number: Integer;
begin
  Result := ABase;
  Number := 1;
  while Taken(Result) do
  begin
    Inc(Number);
    Result := ABase + IntToStr(Number);
  end;
end;

class function TRoutineBody.TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  Result := TSyntaxTree.FirstTokenOf(ATokens, AOffset);
end;

class function TRoutineBody.NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

class function TRoutineBody.PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

class function TRoutineBody.InsertBefore(const AText: string; AStatement: TSyntaxNode;
  const ALine: string): TTextEdit;
var
  Indent: string;
begin
  Indent := TTextLines.IndentOf(AText, AStatement.StartPos.Line);
  // Steht die Anweisung nicht am Zeilenanfang (begin X := 1;), bekommt die neue Zeile dieselbe Einrückung
  // wie die Zeile; die Anweisung rückt in die nächste.
  Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
    ALine + TTextLines.LineBreakOf(AText) + Indent);
end;

/// <summary>Einfügestelle für einen neuen Abschnitt vor dem Rumpf: Anfang der Zeile mit begin.</summary>
function BeforeBody(ARoutine: TSyntaxNode): TTextPosition;
var
  Body: TSyntaxNode;
begin
  Body := TRoutineBody.BodyOf(ARoutine);
  Result := TTextPosition.Create(Body.StartPos.Line, 0);
end;

type
  /// <summary>Abschnitt für Einträge vor dem Rumpf: Art des Abschnitts, der Einträge und Schlüsselwort.</summary>
  TLocalSection = record
    SectionKind: TSyntaxKind;
    EntryKind: TSyntaxKind;
    Keyword: string;
  end;

const
  cVarSection: TLocalSection = (SectionKind: TSyntaxKind.VarSection; EntryKind: TSyntaxKind.VarDecl; Keyword: 'var');
  cConstSection: TLocalSection = (SectionKind: TSyntaxKind.ConstSection; EntryKind: TSyntaxKind.ConstDecl;
    Keyword: 'const');

/// <summary>Letzter Abschnitt der Art AKind vor dem Rumpf von ARoutine; nil ohne.</summary>
function LastSectionBeforeBody(ARoutine: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.Block then
    begin
      Break;
    end;
    if ARoutine[mIndex].Kind = AKind then
    begin
      Result := ARoutine[mIndex];
    end;
  end;
end;

/// <summary>Letztes Kind der Art AKind in ASection; nil ohne oder ohne Abschnitt.</summary>
function LastChildOf(ASection: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind = AKind then
    begin
      Result := ASection[mIndex];
    end;
  end;
end;

/// <summary>Eintrag AEntry hinter den letzten des letzten Abschnitts ASection vor dem Rumpf, sonst in einem neuen
/// Abschnitt vor begin.</summary>
function AddEntry(const AText: string; ARoutine: TSyntaxNode; const ASection: TLocalSection; const AEntry: string;
  const AStyle: TFormatStyle): TTextEdit;
var
  mLast: TSyntaxNode;
  mLineBreak, mIndent: string;
  mPosition: TTextPosition;
begin
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLast := LastChildOf(LastSectionBeforeBody(ARoutine, ASection.SectionKind), ASection.EntryKind);
  if mLast <> nil then
  begin
    mIndent := TTextLines.IndentOf(AText, mLast.StartPos.Line);
    // Hinter das ";" des letzten Eintrags: Ende seiner Zeile.
    mPosition := TTextPosition.Create(mLast.EndPos.Line + 1, 0);
    Exit(TTextEdit.Create(TTextRange.Create(mPosition, mPosition), mIndent + AEntry + mLineBreak));
  end;
  mIndent := TTextLines.IndentOf(AText, ARoutine.StartPos.Line);
  mPosition := BeforeBody(ARoutine);
  Result := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), mIndent + ASection.Keyword + mLineBreak +
    mIndent + TRoutineBody.IndentUnit(AStyle) + AEntry + mLineBreak);
end;

class function TRoutineBody.AddVariable(const AText: string; ARoutine: TSyntaxNode; const AName, AType: string;
  const AStyle: TFormatStyle): TTextEdit;
begin
  Result := AddEntry(AText, ARoutine, cVarSection, AName + ': ' + AType + ';', AStyle);
end;

class function TRoutineBody.AddConstant(const AText: string; ARoutine: TSyntaxNode; const AName, AValue: string;
  const AStyle: TFormatStyle): TTextEdit;
begin
  Result := AddEntry(AText, ARoutine, cConstSection, AName + ' = ' + AValue + ';', AStyle);
end;

class function TRoutineBody.Reindent(const ABlock, ARemove, AAdd, ALineBreak: string): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Line: string;
begin
  Lines := TTextLines.SplitLines(ABlock);
  Result := '';
  for Index := 0 to High(Lines) do
  begin
    Line := Lines[Index];
    if Index > 0 then
    begin
      Result := Result + ALineBreak;
      if StartsStr(ARemove, Line) then
      begin
        Line := Copy(Line, Length(ARemove) + 1, MaxInt);
      end
      else
      begin
        Line := TrimLeft(Line);
      end;
    end;
    if Trim(Line) <> '' then
    begin
      Result := Result + AAdd + Line;
    end;
  end;
end;

/// <summary>Rumpf einer Typdeklaration: class, record oder object; nil ohne.</summary>
function BodyOfType(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := ADecl.FindChild(TSyntaxKind.ClassType);
  if Result = nil then
  begin
    Result := ADecl.FindChild(TSyntaxKind.RecordType);
  end;
  if Result = nil then
  begin
    Result := ADecl.FindChild(TSyntaxKind.ObjectType);
  end;
end;

class function TRoutineBody.TypeBody(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Name: string;
  Found: TSyntaxNode;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  Name := AName;
  // Search statt Rekursion (Bericht M1).
  Found := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (SameText(ANode.Name, Name) or StartsText(Name + '<', ANode.Name)) and
        (BodyOfType(ANode) <> nil) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  if Found <> nil then
  begin
    Result := BodyOfType(Found);
  end;
end;

/// <summary>Sichtbarkeitsabschnitt ASection (auch strict) in ABody und der folgende Abschnitt; nil ohne.</summary>
function SectionOf(ABody: TSyntaxNode; const ASection: string; out ANext: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := nil;
  ANext := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mChild := ABody[mIndex];
    if mChild.Kind <> TSyntaxKind.Visibility then
    begin
      Continue;
    end;
    if Result <> nil then
    begin
      ANext := mChild;
      Break;
    end;
    if SameText(mChild.Name, ASection) or SameText(mChild.Name, 'strict ' + ASection) then
    begin
      Result := mChild;
    end;
  end;
end;

class function TRoutineBody.MemberDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode;
  const AMember: TMemberEntry; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean;
var
  mEndToken, mLine: Integer;
  mVisibility, mNext: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mIndent, mLineBreak: string;
  mPosition: TTextPosition;
begin
  AEdit := Default(TTextEdit);
  mLineBreak := TTextLines.LineBreakOf(AText);
  mVisibility := SectionOf(ABody, AMember.Section, mNext);
  mTokens := ATree.Tokens;
  mEndToken := PreviousToken(mTokens, TokenAt(mTokens, ABody.EndOffset));
  if (mEndToken < 0) or not mTokens[mEndToken].IsKeyword('end') then
  begin
    Exit(False);
  end;
  if mVisibility <> nil then
  begin
    mIndent := TTextLines.IndentOf(AText, mVisibility.StartPos.Line) + IndentUnit(AStyle);
    mLine := mTokens[mEndToken].StartPos.Line;
    if mNext <> nil then
    begin
      mLine := mNext.StartPos.Line;
    end;
    mPosition := TTextPosition.Create(mLine, 0);
    AEdit := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), mIndent + AMember.Declaration + mLineBreak);
    Exit(True);
  end;
  // Kein passender Abschnitt: neuer Abschnitt vor dem end der Klasse, das allein am Zeilenanfang stehen muss.
  mIndent := TTextLines.IndentOf(AText, mTokens[mEndToken].StartPos.Line);
  if Length(mIndent) <> mTokens[mEndToken].StartPos.Character then
  begin
    Exit(False);
  end;
  mPosition := TTextPosition.Create(mTokens[mEndToken].StartPos.Line, 0);
  AEdit := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), mIndent + AMember.Section + mLineBreak +
    mIndent + IndentUnit(AStyle) + AMember.Declaration + mLineBreak);
  Result := True;
end;

class function TRoutineBody.FieldDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode;
  const ADecl: string; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean;
var
  Index: Integer;
  Visibility, LastField: TSyntaxNode;
  Position: TTextPosition;
  Indent: string;
begin
  AEdit := Default(TTextEdit);
  Visibility := nil;
  LastField := nil;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index].Kind = TSyntaxKind.Visibility then
    begin
      if Visibility <> nil then
      begin
        Break;
      end;
      if MatchText(ABody[Index].Name, ['private', 'strict private']) then
      begin
        Visibility := ABody[Index];
      end;
    end
    else if (Visibility <> nil) and (ABody[Index].Kind = TSyntaxKind.Field) then
    begin
      LastField := ABody[Index];
    end
    else if Visibility <> nil then
    begin
      // Felder stehen vor Methoden und Properties (E2169).
      Break;
    end;
  end;
  if Visibility = nil then
  begin
    Exit(MemberDeclaration(AText, ATree, ABody, TMemberEntry.Create('private', ADecl), AStyle, AEdit));
  end;
  if LastField <> nil then
  begin
    Indent := TTextLines.IndentOf(AText, LastField.StartPos.Line);
    Position := TTextPosition.Create(LastField.EndPos.Line + 1, 0);
  end
  else
  begin
    Indent := TTextLines.IndentOf(AText, Visibility.StartPos.Line) + IndentUnit(AStyle);
    Position := TTextPosition.Create(Visibility.EndPos.Line + 1, 0);
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(Position, Position), Indent + ADecl + TTextLines.LineBreakOf(AText));
  Result := True;
end;

class function TRoutineBody.MemberNames(ABody: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.PropertyDecl] then
    begin
      for Name in ABody[Index].Name.Split([',']) do
      begin
        Result := Result + [Trim(Name)];
      end;
    end;
  end;
end;

class function TRoutineBody.VisibilityOf(ABody, AMember: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index] = AMember then
    begin
      Exit;
    end;
    if ABody[Index].Kind = TSyntaxKind.Visibility then
    begin
      Result := LowerCase(ABody[Index].Name);
    end;
  end;
end;

class function TRoutineBody.QualifierOf(const AName: string): string;
begin
  Result := '';
  if AName.LastIndexOf('.') > 0 then
  begin
    Result := AName.Substring(0, AName.LastIndexOf('.'));
  end;
end;

class function TRoutineBody.ShortNameOf(const AName: string): string;
begin
  Result := AName;
  if Result.LastIndexOf('.') >= 0 then
  begin
    Result := Result.Substring(Result.LastIndexOf('.') + 1);
  end;
end;

/// <summary>Ist ALine (ohne Leerraum am Rand) ein Kommentar oder dessen Ende, aber keine Direktive?</summary>
function IsCommentLine(const ALine: string): Boolean;
begin
  if StartsStr('{$', ALine) then
  begin
    Exit(False);
  end;
  Result := StartsStr('//', ALine) or StartsStr('{', ALine) or StartsStr('(*', ALine) or
    ((ALine <> '') and EndsStr('}', ALine) and (Pos('{', ALine) = 0));
end;

class function TRoutineBody.RoutineInsertLine(const AText: string; ARoutine: TSyntaxNode): Integer;
var
  Lines: TArray<string>;
  Line: string;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := ARoutine.StartPos.Line;
  while Result > 0 do
  begin
    Line := Trim(Lines[Result - 1]);
    if IsCommentLine(Line) then
    begin
      Dec(Result);
    end
    else
    begin
      Break;
    end;
  end;
end;

class function TRoutineBody.IsVariableChain(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  // Schleife statt Rekursion (Bericht M1).
  Node := ANode;
  while Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference, TSyntaxKind.IndexAccess] do
  begin
    Node := Node[0];
  end;
  Result := Node.Kind = TSyntaxKind.Identifier;
end;

/// <summary>Hängt bei ANode der rechte Teil vom linken ab (and, or, if-Ausdruck)?</summary>
function IsShortCircuit(ANode: TSyntaxNode): Boolean;
begin
  Result := SameText(ANode.Name, 'and') or SameText(ANode.Name, 'or') or (ANode.Kind = TSyntaxKind.IfExpr);
end;

/// <summary>Verbietet ANode, das Kind AChild auf dem Weg vom Ausdruck AOrigin vorab zu rechnen?</summary>
function BlocksHoisting(ANode, AChild, AOrigin: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock:
      Result := True;
    TSyntaxKind.AssignStatement:
      Result := ANode[0] = AChild;
    TSyntaxKind.Call:
      Result := (ANode[0] = AChild) or (TRoutineBody.IsVariableChain(AChild) and (AChild = AOrigin));
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.CaseItem:
      // Bedingungen laufen mehrfach bzw. sind case-Marken.
      Result := not TRoutineBody.IsStatement(AChild);
    TSyntaxKind.IfExpr, TSyntaxKind.BinaryExpr:
      // Kurzschluss: rechts nur, wenn links es zulässt.
      Result := (ANode.ChildCount > 1) and (AChild <> ANode[0]) and IsShortCircuit(ANode);
  else
    Result := False;
  end;
end;

class function TRoutineBody.HostStatement(ANode, ABody: TSyntaxNode): TSyntaxNode;
var
  mNode, mChild: TSyntaxNode;
begin
  Result := nil;
  mChild := ANode;
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode <> ABody) do
  begin
    if BlocksHoisting(mNode, mChild, ANode) then
    begin
      Exit;
    end;
    if IsStatement(mNode) and InList(mNode) then
    begin
      Exit(mNode);
    end;
    // Zweig ohne begin (if A then X := F(Y)): vorab rechnen änderte die Bedeutung.
    if IsStatement(mNode) and (mNode.Parent <> nil) and (mNode.Parent.Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    mChild := mNode;
    mNode := mNode.Parent;
  end;
end;

end.
