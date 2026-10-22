unit Atlas.Common.Editing.RoutineLocals;

// Lokale Namen einer Routine und ihre Zugriffe, gemeinsam für Extrahieren
// (#50) und Einbetten (#103): Parameter, var- und const-Abschnitt,
// Inline-Variablen und for var mit ihrem Gültigkeitsbereich; Zugriff eines
// Bezeichners (Lesen, Schreiben, beides) und das Entfernen von Namen aus
// einem var-Eintrag.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow;

type
{$SCOPEDENUMS ON}
  TRoutineLocalKind = (Parameter, Variable, InlineVariable, LoopVariable, Constant);
  TLocalAccess = (Read, Write, ReadWrite);
{$SCOPEDENUMS OFF}

  TRoutineLocal = record
    Name: string;
    TypeText: string;
    Kind: TRoutineLocalKind;
    Decl: TSyntaxNode;
    /// <summary>Ausdruck, aus dem der Typ folgt (Inline-Variable ohne Typ, Laufvariable).</summary>
    Initializer: TSyntaxNode;
    /// <summary>Anweisung, vor der die Inline-Variable bzw. Laufvariable steht (für die Typabfrage).</summary>
    Statement: TSyntaxNode;
    ScopeStart: Integer;
    ScopeEnd: Integer;
  end;

  TRoutineLocals = class
  public const
    TypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType, TSyntaxKind.PointerType,
      TSyntaxKind.ProcedureType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType, TSyntaxKind.EnumType,
      TSyntaxKind.RecordType, TSyntaxKind.ClassOfType];
  public
    /// <summary>Alle Knoten der Art AKind unter ANode (einschließlich) in Baumreihenfolge.</summary>
    class procedure CollectKind(ANode: TSyntaxNode; AKind: TSyntaxKind; AList: TList<TSyntaxNode>); static;
    /// <summary>Kommt unter ANode (einschließlich) ein Knoten der Art AKind vor?</summary>
    class function HasKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean; static;
    /// <summary>for var I := … bzw. for var X in …</summary>
    class function IsInlineFor(const ATokens: TArray<TPascalToken>; AFor: TSyntaxNode): Boolean; static;
    /// <summary>Typ als Text, wenn das erste Kind ein Typ ist; sonst ''.</summary>
    class function TypeChildText(const AText: string; ANode: TSyntaxNode): string; static;
    /// <summary>Lokale Namen der Routine: Parameter, var- und const-Abschnitt, Inline-Variablen, for var.</summary>
    class function Collect(const AText: string; ATree: TSyntaxTree; ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
      static;
    /// <summary>Lokaler Name AName, der an AOffset gilt (innerster zuerst); -1 ohne.</summary>
    class function IndexOf(const ALocals: TArray<TRoutineLocal>; const AName: string; AOffset: Integer): Integer;
      static;
    /// <summary>Zugriff des Bezeichners ANode: Ziel einer Zuweisung, Teilzuweisung, var-Argument oder Lesen.</summary>
    class function AccessOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TLocalAccess; static;
    /// <summary>Bearbeitungen, die die Namen ARemoved aus dem var-Eintrag ADecl entfernen (bei letztem Namen die
    /// Zeile, beim letzten Eintrag auch "var").</summary>
    class procedure RemoveVariables(const AText: string; ATree: TSyntaxTree; ADecl: TSyntaxNode;
      const ARemoved: TArray<string>; var AEdits: TArray<TTextEdit>); static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Editing.RoutineBody;

class procedure TRoutineLocals.CollectKind(ANode: TSyntaxNode; AKind: TSyntaxKind; AList: TList<TSyntaxNode>);
var
  Kind: TSyntaxKind;
  List: TList<TSyntaxNode>;
begin
  Kind := AKind;
  List := AList;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = Kind then
        List.Add(AChild);
      Result := True;
    end);
end;

class function TRoutineLocals.HasKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(AChild: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if AChild.Kind = Kind then
        Result := TSyntaxSearchStep.Found;
    end) <> nil;
end;

class function TRoutineLocals.IsInlineFor(const ATokens: TArray<TPascalToken>; AFor: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.NextToken(ATokens, TRoutineBody.TokenAt(ATokens, AFor.StartOffset));
  Result := (Index <= High(ATokens)) and ATokens[Index].IsKeyword('var');
end;

class function TRoutineLocals.TypeChildText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode.ChildCount > 0) and (ANode[0].Kind in TRoutineLocals.TypeKinds) then
    Result := TRoutineBody.TextOf(AText, ANode[0]);
end;

class function TRoutineLocals.Collect(const AText: string; ATree: TSyntaxTree;
  ARoutine: TSyntaxNode): TArray<TRoutineLocal>;
var
  Body, Header, Parameters, Section, Node: TSyntaxNode;
  Nodes: TList<TSyntaxNode>;
  Index, Inner: Integer;
  Local: TRoutineLocal;
  Name: string;
  List: TList<TRoutineLocal>;
begin
  Body := TRoutineBody.BodyOf(ARoutine);
  List := TList<TRoutineLocal>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  try
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Parameters := nil;
    if Header <> nil then
      Parameters := Header.FindChild(TSyntaxKind.Parameters);
    if Parameters <> nil then
      for Index := 0 to Parameters.ChildCount - 1 do
        // "A, B: Integer" ist ein Knoten mit beiden Namen.
        for Name in Parameters[Index].Name.Split([',']) do
        begin
          Local := Default(TRoutineLocal);
          Local.Name := Trim(Name);
          Local.Kind := TRoutineLocalKind.Parameter;
          Local.Decl := Parameters[Index];
          Local.TypeText := TypeChildText(AText, Parameters[Index]);
          Local.ScopeStart := Body.StartOffset;
          Local.ScopeEnd := Body.EndOffset;
          List.Add(Local);
        end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if Section.Kind = TSyntaxKind.VarSection then
        for Inner := 0 to Section.ChildCount - 1 do
          for Name in Section[Inner].Name.Split([',']) do
          begin
            Local := Default(TRoutineLocal);
            Local.Name := Trim(Name);
            Local.Kind := TRoutineLocalKind.Variable;
            Local.Decl := Section[Inner];
            Local.TypeText := TypeChildText(AText, Section[Inner]);
            Local.ScopeStart := Body.StartOffset;
            Local.ScopeEnd := Body.EndOffset;
            List.Add(Local);
          end
      else if Section.Kind = TSyntaxKind.ConstSection then
        for Inner := 0 to Section.ChildCount - 1 do
        begin
          Local := Default(TRoutineLocal);
          Local.Name := Section[Inner].Name;
          Local.Kind := TRoutineLocalKind.Constant;
          Local.Decl := Section[Inner];
          Local.ScopeStart := Body.StartOffset;
          Local.ScopeEnd := Body.EndOffset;
          List.Add(Local);
        end;
    end;
    CollectKind(Body, TSyntaxKind.InlineVar, Nodes);
    CollectKind(Body, TSyntaxKind.InlineConst, Nodes);
    for Node in Nodes do
      for Name in Node.Name.Split([',']) do
      begin
        Local := Default(TRoutineLocal);
        Local.Name := Trim(Name);
        Local.Kind := TRoutineLocalKind.InlineVariable;
        Local.Decl := Node;
        Local.Statement := Node;
        Local.TypeText := TypeChildText(AText, Node);
        if (Local.TypeText = '') and (Node.ChildCount > 0) then
          Local.Initializer := Node[Node.ChildCount - 1];
        Local.ScopeStart := Node.StartOffset;
        Local.ScopeEnd := Node.Parent.EndOffset;
        List.Add(Local);
      end;
    Nodes.Clear;
    CollectKind(Body, TSyntaxKind.ForStatement, Nodes);
    CollectKind(Body, TSyntaxKind.ForInStatement, Nodes);
    for Node in Nodes do
      if IsInlineFor(ATree.Tokens, Node) then
      begin
        Local := Default(TRoutineLocal);
        Local.Name := Node.Name;
        Local.Kind := TRoutineLocalKind.LoopVariable;
        Local.Decl := Node;
        Local.Statement := Node;
        if Node.ChildCount > 0 then
          Local.Initializer := Node[0];
        Local.ScopeStart := Node.StartOffset;
        Local.ScopeEnd := Node.EndOffset;
        List.Add(Local);
      end;
    Result := List.ToArray;
  finally
    Nodes.Free;
    List.Free;
  end;
end;

class function TRoutineLocals.IndexOf(const ALocals: TArray<TRoutineLocal>; const AName: string;
  AOffset: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ALocals) do
    if SameText(ALocals[Index].Name, AName) and (ALocals[Index].ScopeStart <= AOffset) and
      (AOffset <= ALocals[Index].ScopeEnd) and
      ((Result < 0) or (ALocals[Index].ScopeStart >= ALocals[Result].ScopeStart)) then
      Result := Index;
end;

class function TRoutineLocals.AccessOf(ANode: TSyntaxNode; const ALookup: TFlowSignatureLookup): TLocalAccess;
var
  Node, Parent: TSyntaxNode;
  Index: Integer;
  Mode: TFlowArgumentMode;
begin
  Result := TLocalAccess.Read;
  Parent := ANode.Parent;
  if Parent = nil then
    Exit;
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = ANode) then
    Exit(TLocalAccess.Write);
  if Parent.Kind = TSyntaxKind.AddressOf then
    Exit(TLocalAccess.ReadWrite);
  // Teil eines Ziels: A.Feld := …, A[I] := …
  Node := ANode;
  while (Node.Parent <> nil) and (Node.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Node.Parent[0] = Node) do
    Node := Node.Parent;
  if (Node <> ANode) and (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.AssignStatement) and
    (Node.Parent[0] = Node) then
    Exit(TLocalAccess.ReadWrite);
  // Argument eines Aufrufs: var/out oder unbekannte Signatur ändern womöglich.
  if (Parent.Kind = TSyntaxKind.Call) and (Parent[0] <> ANode) then
  begin
    Index := 0;
    while (Index < Parent.ChildCount) and (Parent[Index] <> ANode) do
      Inc(Index);
    Mode := TFlowArgumentMode.Unknown;
    if Assigned(ALookup) then
      Mode := ALookup(Parent, Index - 1);
    if Mode <> TFlowArgumentMode.Value then
      Result := TLocalAccess.ReadWrite;
  end;
end;

class procedure TRoutineLocals.RemoveVariables(const AText: string; ATree: TSyntaxTree; ADecl: TSyntaxNode;
  const ARemoved: TArray<string>; var AEdits: TArray<TTextEdit>);
var
  Names, Kept: TArray<string>;
  Name: string;
  Tokens: TArray<TPascalToken>;
  Colon: Integer;
  Section: TSyntaxNode;
  Index: Integer;
  AllRemoved: Boolean;
begin
  Names := ADecl.Name.Split([',']);
  Kept := nil;
  for Name in Names do
    if IndexText(Trim(Name), ARemoved) < 0 then
      Kept := Kept + [Trim(Name)];
  if Length(Kept) = Length(Names) then
    Exit;
  if Kept <> nil then
  begin
    Tokens := ATree.Tokens;
    Colon := TRoutineBody.TokenAt(Tokens, ADecl.StartOffset);
    while (Colon <= High(Tokens)) and not Tokens[Colon].IsSymbol(':') do
      Inc(Colon);
    if Colon > High(Tokens) then
      Exit;
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ADecl.StartPos, Tokens[Colon].StartPos),
      string.Join(', ', Kept))];
    Exit;
  end;
  // Ganze Zeile weg; war es der einzige Eintrag, auch "var".
  Section := ADecl.Parent;
  AllRemoved := True;
  for Index := 0 to Section.ChildCount - 1 do
    if Section[Index] <> ADecl then
      for Name in Section[Index].Name.Split([',']) do
        if IndexText(Trim(Name), ARemoved) < 0 then
          AllRemoved := False;
  if AllRemoved then
  begin
    if Section[0] = ADecl then
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Section.StartPos.Line, 0, ADecl.EndPos.Line + 1, 0),
        '')]
    else
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ADecl.StartPos.Line, 0, ADecl.EndPos.Line + 1, 0), '')];
  end
  else
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ADecl.StartPos.Line, 0, ADecl.EndPos.Line + 1, 0), '')];
end;

end.
