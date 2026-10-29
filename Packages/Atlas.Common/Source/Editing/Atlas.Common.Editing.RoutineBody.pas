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
    /// <summary>Deklaration ADecl am Ende des Abschnitts ASection ("private", "protected", "public") der Klasse
    /// ABody; bei private zählt auch strict private. Ohne Abschnitt ein neuer vor end, das dann allein am
    /// Zeilenanfang stehen muss.</summary>
    class function MemberDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode;
      const ASection, ADecl: string; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean; static;
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

class function TRoutineBody.IsStatement(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in StatementKinds);
end;

class function TRoutineBody.BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ARoutine <> nil then
    Result := ARoutine.FindChild(TSyntaxKind.Block);
end;

class function TRoutineBody.RoutineAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
  Body: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
      if (Node[Index].StartOffset <= AOffset) and (AOffset <= Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Body := BodyOf(Node);
          if (Body <> nil) and (Body.StartOffset <= AOffset) and (AOffset <= Body.EndOffset) then
            Result := Node;
        end;
        Descended := True;
        Break;
      end;
  until not Descended;
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
      if (Node[Index].StartOffset <= AFirst) and (ALast <= Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        Result := Node;
        Descended := True;
        Break;
      end;
  until not Descended;
end;

class function TRoutineBody.InList(AStatement: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Result := False;
  if (AStatement = nil) or (AStatement.Parent = nil) then
    Exit;
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
      Exit(True);
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
    Result := #9
  else if AStyle.IndentSize > 0 then
    Result := StringOfChar(' ', AStyle.IndentSize)
  else
    Result := '  ';
end;

class function TRoutineBody.UniqueName(const ATokens: TArray<TPascalToken>; const ABase: string): string;

  function Taken(const AName: string): Boolean;
  var
    Index, Before: Integer;
  begin
    // Namen hinter einem Punkt (Liste.Count) sind Mitglieder und kollidieren nicht.
    for Index := 0 to High(ATokens) do
      if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) then
      begin
        Before := PreviousToken(ATokens, Index);
        if (Before < 0) or not ATokens[Before].IsSymbol('.') then
          Exit(True);
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
    Inc(Result);
end;

class function TRoutineBody.PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
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

function AddEntry(const AText: string; ARoutine: TSyntaxNode; ASectionKind, AEntryKind: TSyntaxKind;
  const AKeyword, AEntry: string; const AStyle: TFormatStyle): TTextEdit;
var
  Section, Last: TSyntaxNode;
  Index: Integer;
  LineBreak, Indent: string;
  Position: TTextPosition;
begin
  LineBreak := TTextLines.LineBreakOf(AText);
  // Letzter Abschnitt der Art vor dem Rumpf; Einträge kommen hinter seinen letzten.
  Section := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
    if ARoutine[Index].Kind = ASectionKind then
      Section := ARoutine[Index]
    else if ARoutine[Index].Kind = TSyntaxKind.Block then
      Break;
  Last := nil;
  if Section <> nil then
    for Index := 0 to Section.ChildCount - 1 do
      if Section[Index].Kind = AEntryKind then
        Last := Section[Index];
  if Last <> nil then
  begin
    Indent := TTextLines.IndentOf(AText, Last.StartPos.Line);
    // Hinter das ";" des letzten Eintrags: Ende seiner Zeile.
    Position := TTextPosition.Create(Last.EndPos.Line + 1, 0);
    Result := TTextEdit.Create(TTextRange.Create(Position, Position), Indent + AEntry + LineBreak);
    Exit;
  end;
  Indent := TTextLines.IndentOf(AText, ARoutine.StartPos.Line);
  Position := BeforeBody(ARoutine);
  Result := TTextEdit.Create(TTextRange.Create(Position, Position), Indent + AKeyword + LineBreak + Indent +
    TRoutineBody.IndentUnit(AStyle) + AEntry + LineBreak);
end;

class function TRoutineBody.AddVariable(const AText: string; ARoutine: TSyntaxNode; const AName, AType: string;
  const AStyle: TFormatStyle): TTextEdit;
begin
  Result := AddEntry(AText, ARoutine, TSyntaxKind.VarSection, TSyntaxKind.VarDecl, 'var', AName + ': ' + AType +
    ';', AStyle);
end;

class function TRoutineBody.AddConstant(const AText: string; ARoutine: TSyntaxNode; const AName, AValue: string;
  const AStyle: TFormatStyle): TTextEdit;
begin
  Result := AddEntry(AText, ARoutine, TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, 'const', AName + ' = ' +
    AValue + ';', AStyle);
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
        Line := Copy(Line, Length(ARemove) + 1, MaxInt)
      else
        Line := TrimLeft(Line);
    end;
    if Trim(Line) <> '' then
      Result := Result + AAdd + Line;
  end;
end;

/// <summary>Rumpf einer Typdeklaration: class, record oder object; nil ohne.</summary>
function BodyOfType(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := ADecl.FindChild(TSyntaxKind.ClassType);
  if Result = nil then
    Result := ADecl.FindChild(TSyntaxKind.RecordType);
  if Result = nil then
    Result := ADecl.FindChild(TSyntaxKind.ObjectType);
end;

class function TRoutineBody.TypeBody(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Name: string;
  Found: TSyntaxNode;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  Name := AName;
  // Search statt Rekursion (Bericht M1).
  Found := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (SameText(ANode.Name, Name) or StartsText(Name + '<', ANode.Name)) and
        (BodyOfType(ANode) <> nil) then
        Result := TSyntaxSearchStep.Found;
    end);
  if Found <> nil then
    Result := BodyOfType(Found);
end;

class function TRoutineBody.MemberDeclaration(const AText: string; ATree: TSyntaxTree; ABody: TSyntaxNode;
  const ASection, ADecl: string; const AStyle: TFormatStyle; out AEdit: TTextEdit): Boolean;
var
  Index, EndToken: Integer;
  Visibility, Next: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Indent, LineBreak: string;
  Position: TTextPosition;
begin
  Result := False;
  AEdit := Default(TTextEdit);
  LineBreak := TTextLines.LineBreakOf(AText);
  Visibility := nil;
  Next := nil;
  for Index := 0 to ABody.ChildCount - 1 do
    if ABody[Index].Kind = TSyntaxKind.Visibility then
      if Visibility = nil then
      begin
        if SameText(ABody[Index].Name, ASection) or SameText(ABody[Index].Name, 'strict ' + ASection) then
          Visibility := ABody[Index];
      end
      else if Next = nil then
        Next := ABody[Index];
  Tokens := ATree.Tokens;
  EndToken := PreviousToken(Tokens, TokenAt(Tokens, ABody.EndOffset));
  if (EndToken < 0) or not Tokens[EndToken].IsKeyword('end') then
    Exit;
  if Visibility <> nil then
  begin
    Indent := TTextLines.IndentOf(AText, Visibility.StartPos.Line) + IndentUnit(AStyle);
    if Next <> nil then
      Position := TTextPosition.Create(Next.StartPos.Line, 0)
    else
      Position := TTextPosition.Create(Tokens[EndToken].StartPos.Line, 0);
    AEdit := TTextEdit.Create(TTextRange.Create(Position, Position), Indent + ADecl + LineBreak);
    Exit(True);
  end;
  // Kein passender Abschnitt: neuer Abschnitt vor dem end der Klasse, das allein am Zeilenanfang stehen muss.
  Indent := TTextLines.IndentOf(AText, Tokens[EndToken].StartPos.Line);
  if Length(Indent) <> Tokens[EndToken].StartPos.Character then
    Exit;
  Position := TTextPosition.Create(Tokens[EndToken].StartPos.Line, 0);
  AEdit := TTextEdit.Create(TTextRange.Create(Position, Position), Indent + ASection + LineBreak + Indent +
    IndentUnit(AStyle) + ADecl + LineBreak);
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
    if ABody[Index].Kind = TSyntaxKind.Visibility then
    begin
      if Visibility <> nil then
        Break;
      if MatchText(ABody[Index].Name, ['private', 'strict private']) then
        Visibility := ABody[Index];
    end
    else if (Visibility <> nil) and (ABody[Index].Kind = TSyntaxKind.Field) then
      LastField := ABody[Index]
    else if Visibility <> nil then
      // Felder stehen vor Methoden und Properties (E2169).
      Break;
  if Visibility = nil then
    Exit(MemberDeclaration(AText, ATree, ABody, 'private', ADecl, AStyle, AEdit));
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
    if ABody[Index].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.PropertyDecl] then
      for Name in ABody[Index].Name.Split([',']) do
        Result := Result + [Trim(Name)];
end;

class function TRoutineBody.VisibilityOf(ABody, AMember: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[Index] = AMember then
      Exit;
    if ABody[Index].Kind = TSyntaxKind.Visibility then
      Result := LowerCase(ABody[Index].Name);
  end;
end;

class function TRoutineBody.QualifierOf(const AName: string): string;
begin
  Result := '';
  if AName.LastIndexOf('.') > 0 then
    Result := AName.Substring(0, AName.LastIndexOf('.'));
end;

class function TRoutineBody.ShortNameOf(const AName: string): string;
begin
  Result := AName;
  if Result.LastIndexOf('.') >= 0 then
    Result := Result.Substring(Result.LastIndexOf('.') + 1);
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
    if StartsStr('//', Line) or (StartsStr('{', Line) and not StartsStr('{$', Line)) or StartsStr('(*', Line) or
      ((Line <> '') and EndsStr('}', Line) and not StartsStr('{$', Line) and (Pos('{', Line) = 0)) then
      Dec(Result)
    else
      Break;
  end;
end;

class function TRoutineBody.IsVariableChain(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  // Schleife statt Rekursion (Bericht M1).
  Node := ANode;
  while Node.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference, TSyntaxKind.IndexAccess] do
    Node := Node[0];
  Result := Node.Kind = TSyntaxKind.Identifier;
end;

class function TRoutineBody.HostStatement(ANode, ABody: TSyntaxNode): TSyntaxNode;
var
  Node, Child: TSyntaxNode;
begin
  Result := nil;
  Child := ANode;
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> ABody) do
  begin
    case Node.Kind of
      TSyntaxKind.AnonymousMethod, TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock:
        Exit;
      TSyntaxKind.AssignStatement:
        if Node[0] = Child then
          Exit;
      TSyntaxKind.Call:
        if Node[0] = Child then
          Exit
        else if IsVariableChain(Child) and (Child = ANode) then
          Exit;
      TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement:
        // Bedingungen laufen mehrfach.
        if not TRoutineBody.IsStatement(Child) then
          Exit;
      TSyntaxKind.CaseItem:
        if not TRoutineBody.IsStatement(Child) then
          Exit;
      TSyntaxKind.IfExpr, TSyntaxKind.BinaryExpr:
        // Kurzschluss: rechts nur, wenn links es zulässt.
        if (Node.ChildCount > 1) and (Child <> Node[0]) and (SameText(Node.Name, 'and') or
          SameText(Node.Name, 'or') or (Node.Kind = TSyntaxKind.IfExpr)) then
          Exit;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if TRoutineBody.IsStatement(Node) then
    begin
      if TRoutineBody.InList(Node) then
        Exit(Node);
      // Zweig ohne begin (if A then X := F(Y)): vorab rechnen änderte die Bedeutung.
      if (Node.Parent <> nil) and not (Node.Parent.Kind in [TSyntaxKind.Block]) then
        Exit;
    end;
    Child := Node;
    Node := Node.Parent;
  end;
end;

end.
