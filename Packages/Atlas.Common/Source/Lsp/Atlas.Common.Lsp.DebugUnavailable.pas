unit Atlas.Common.Lsp.DebugUnavailable;

// Warum der Debugger einen Wert nicht liefert (#840): Anfrage
// atlas/debugUnavailable mit textDocument, position (Halt, Zeile 0-basiert)
// und name (Bezeichner, dessen Auswertung scheiterte). Der Server nennt die
// Tatsachen, das Plugin wählt daraus die Ursache:
//   - switches: D (DEBUGINFO), L (LOCALSYMBOLS) und O (OPTIMIZATION) an der
//     Stelle mit Herkunft wie atlas/compilerSwitches (#558);
//   - routine: innerste benannte Routine am Halt mit Zeilen und ob sie inline
//     deklariert ist (am Kopf der Implementierung oder an der Deklaration in
//     der Klasse bzw. im interface);
//   - variable: lokal (lokale Variable, Parameter, Result, Inline- oder
//     Schleifenvariable), erste und letzte Verwendung im Rumpf und daraus die
//     Lebensdauer am Halt (before, within, after, unused). Eine Verwendung in
//     einer Schleife zählt für die ganze Schleife. Parameter leben ab dem
//     Routinenanfang. Das ist eine Näherung: Der Compiler kann Register früher
//     freigeben oder später belegen.
//   - fixes: Änderungen als WorkspaceEdit: {$OPTIMIZATION OFF} vor und
//     {$OPTIMIZATION ON} nach der äußeren Routine, {$O-} unter dem Kopf der
//     Unit; fehlt, wo nichts einzufügen ist.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.CompilerSwitches;

type
  {$SCOPEDENUMS ON}
  TVariableLifetime = (Unknown, Unused, Before, Within, After);
  {$SCOPEDENUMS OFF}

  TUnavailableFacts = record
    HasRoutine: Boolean;
    RoutineName: string;
    RoutineInline: Boolean;
    RoutineStartLine: Integer;
    RoutineEndLine: Integer;
    /// <summary>Lokale Variable, Parameter, Result, Inline- oder Schleifenvariable der Routine.</summary>
    Local: Boolean;
    IsParameter: Boolean;
    /// <summary>Erste und letzte Verwendung (Zeilen, 0-basiert, Schleifen ganz); -1 ohne.</summary>
    FirstUse: Integer;
    LastUse: Integer;
    Lifetime: TVariableLifetime;
    /// <summary>Einfügungen für {$OPTIMIZATION OFF}/{$OPTIMIZATION ON} um die äußere Routine; leer ohne.</summary>
    RoutineFix: TArray<TTextEdit>;
    /// <summary>Einfügung {$O-} unter dem Kopf der Unit.</summary>
    UnitFix: TArray<TTextEdit>;
  end;

  TLspDebugUnavailable = class
  public const
    Method = 'atlas/debugUnavailable';
    LifetimeNames: array[TVariableLifetime] of string = ('unknown', 'unused', 'before', 'within', 'after');
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FContextFor: TCompilerSwitchContextFunc;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
      const AContextFor: TCompilerSwitchContextFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Tatsachen zu AName beim Halt in Zeile AStoppedLine (0-basiert). AResolver darf nil sein; dann
    /// gilt ein Name als lokal, wenn er in der Routine deklariert ist.</summary>
    class function Facts(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText, AName: string;
      AStoppedLine: Integer): TUnavailableFacts; static;
    /// <summary>Antwort wie im Kopf beschrieben; gehört dem Aufrufer.</summary>
    class function ToJson(const AFacts: TUnavailableFacts; const AState: TCompilerSwitchState;
      const AFileName: string): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Text.Lines;

function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Innerste (AOuter: äußerste) benannte Routine, die AOffset enthält; nil außerhalb.</summary>
function RoutineAt(ARoot: TSyntaxNode; AOffset: Integer; AOuter: Boolean): TSyntaxNode;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  Node := ARoot;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      Child := Node[Index];
      if (Child.StartOffset <= AOffset) and (AOffset < Child.EndOffset) then
      begin
        Node := Child;
        if (Node.Kind = TSyntaxKind.RoutineDecl) and not (AOuter and (Result <> nil)) then
        begin
          Result := Node;
        end;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Offset des ersten bedeutsamen Tokens in ALine bzw. danach; -1 ohne.</summary>
function LineOffset(const ATokens: TArray<TPascalToken>; ALine: Integer): Integer;
var
  Token: TPascalToken;
begin
  for Token in ATokens do
  begin
    if (Token.StartPos.Line >= ALine) and Significant(Token) then
    begin
      Exit(Token.Offset);
    end;
  end;
  Result := -1;
end;

function HasInlineDirective(AHeader: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, 'inline') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Name des umgebenden Typs eines Kopfs in einer Klassen- bzw. Record-Deklaration; '' sonst.</summary>
function OwnerTypeName(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Result := '';
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.TypeDecl then
    begin
      Exit(Node.Name);
    end;
    if Node.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.RoutineDecl] then
    begin
      Exit;
    end;
    Node := Node.Parent;
  end;
end;

function InInterface(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.InterfaceSection then
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>inline am Kopf der Routine oder an ihrer Deklaration (Klasse bzw. interface).</summary>
function RoutineIsInline(ARoot, ARoutine: TSyntaxNode): Boolean;
var
  ShortName, TypeName: string;
  Found: Boolean;
begin
  Result := HasInlineDirective(ARoutine.FindChild(TSyntaxKind.RoutineHeader));
  if Result then
  begin
    Exit;
  end;
  ShortName := LastPart(ARoutine.Name);
  TypeName := '';
  if Pos('.', ARoutine.Name) > 0 then
  begin
    TypeName := LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1));
  end;
  Found := False;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not Found;
      if Found or (ANode.Kind <> TSyntaxKind.RoutineHeader) or (ANode.Parent = nil) or
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (ANode.Parent = ARoutine) then
      begin
        Exit;
      end;
      if not SameText(LastPart(ANode.Name), ShortName) then
      begin
        Exit;
      end;
      if TypeName <> '' then
      begin
        if not SameText(OwnerTypeName(ANode), TypeName) then
        begin
          Exit;
        end;
      end
      else if not InInterface(ANode) then
      begin
        Exit;
      end;
      if HasInlineDirective(ANode) then
      begin
        Found := True;
      end;
    end);
  Result := Found;
end;

/// <summary>Zeile hinter dem Kopf "unit X;" bzw. "program X;"; 0 ohne Kopf.</summary>
function LineAfterHeader(const ATokens: TArray<TPascalToken>): Integer;
var
  Index, Last: Integer;
begin
  Result := 0;
  Index := 0;
  while (Index <= High(ATokens)) and not Significant(ATokens[Index]) do
  begin
    Inc(Index);
  end;
  if (Index > High(ATokens)) or not (SameText(ATokens[Index].Text, 'unit') or
    SameText(ATokens[Index].Text, 'program') or SameText(ATokens[Index].Text, 'library') or
    SameText(ATokens[Index].Text, 'package')) then
  begin
    Exit;
  end;
  Last := Index;
  while (Last <= High(ATokens)) and not ATokens[Last].IsSymbol(';') do
  begin
    Inc(Last);
  end;
  if Last <= High(ATokens) then
  begin
    Result := ATokens[Last].EndPos.Line + 1;
  end;
end;

{ TLspDebugUnavailable }

constructor TLspDebugUnavailable.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const AContextFor: TCompilerSwitchContextFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FContextFor := AContextFor;
end;

procedure TLspDebugUnavailable.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspDebugUnavailable.Facts(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText, AName: string; AStoppedLine: Integer): TUnavailableFacts;
var
  Tokens: TArray<TPascalToken>;
  Offset, Index, Before, Line, FirstLine, LastLine: Integer;
  Routine, Outer, Body, Params: TSyntaxNode;
  Loops: TList<TSyntaxNode>;
  Loop: TSyntaxNode;
  Token: TPascalToken;
  mIndex: Integer;
  Symbol: TResolvedSymbol;
  Resolved, Declared: Boolean;
  LineEnd: string;
begin
  Result := Default(TUnavailableFacts);
  Result.FirstUse := -1;
  Result.LastUse := -1;
  Tokens := ATree.Tokens;
  LineEnd := TTextLines.LineBreakOf(AText);
  Result.UnitFix := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(LineAfterHeader(Tokens), 0,
    LineAfterHeader(Tokens), 0), '{$O-}' + LineEnd));
  Offset := LineOffset(Tokens, AStoppedLine);
  if Offset < 0 then
  begin
    Exit;
  end;
  Routine := RoutineAt(ATree.Root, Offset, False);
  if Routine = nil then
  begin
    Exit;
  end;
  Outer := RoutineAt(ATree.Root, Offset, True);
  Result.HasRoutine := True;
  Result.RoutineName := Routine.Name;
  Result.RoutineStartLine := Routine.StartPos.Line;
  Result.RoutineEndLine := Routine.EndPos.Line;
  Result.RoutineInline := RoutineIsInline(ATree.Root, Routine);
  Result.RoutineFix := TArray<TTextEdit>.Create(
    TTextEdit.Create(TTextRange.Create(Outer.StartPos.Line, 0, Outer.StartPos.Line, 0),
      '{$OPTIMIZATION OFF}' + LineEnd),
    TTextEdit.Create(TTextRange.Create(Outer.EndPos.Line + 1, 0, Outer.EndPos.Line + 1, 0),
      '{$OPTIMIZATION ON}' + LineEnd));
  Body := Routine.FindChild(TSyntaxKind.Block);
  if Body = nil then
  begin
    Exit;
  end;
  // Parameter: Name in der Parameterliste des Kopfs; deklariert: Name vor dem Rumpf (Parameter, var-Abschnitt).
  Params := nil;
  if Routine.FindChild(TSyntaxKind.RoutineHeader) <> nil then
  begin
    Params := Routine.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.Parameters);
  end;
  Declared := SameText(AName, 'Result');
  for mIndex := TSyntaxTree.FirstTokenOf(Tokens, Routine.StartOffset) to High(Tokens) do
  begin
    Token := Tokens[mIndex];
    if Token.Offset >= Body.StartOffset then
    begin
      Break;
    end;
    if (Token.Offset < Routine.StartOffset) or (Token.Kind <> TPascalTokenKind.Identifier) or
      not SameText(Token.Text, AName) then
    begin
      Continue;
    end;
    if (Params <> nil) and (Params.StartOffset <= Token.Offset) and (Token.Offset < Params.EndOffset) then
    begin
      Result.IsParameter := True;
    end;
    if not SameText(LastPart(Routine.Name), AName) then
    begin
      Declared := True;
    end;
  end;
  Loops := TList<TSyntaxNode>.Create;
  try
    Body.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
        begin
          Loops.Add(ANode);
        end;
        // Anonyme Methoden haben eigene Lebensdauern.
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
      end);
    Resolved := False;
    if AResolver <> nil then
    begin
      AResolver.PinTree(ATree, AFileName);
    end;
    try
      for Index := TSyntaxTree.FirstTokenOf(Tokens, Body.StartOffset) to High(Tokens) do
      begin
        Token := Tokens[Index];
        if Token.Offset >= Body.EndOffset then
        begin
          Break;
        end;
        if (Token.Offset < Body.StartOffset) or (Token.Kind <> TPascalTokenKind.Identifier) or
          not SameText(Token.Text, AName) or ATree.IsControlCharPart(Index) then
        begin
          Continue;
        end;
        // Mitglied eines anderen Ausdrucks (X.Name) ist ein anderer Name.
        Before := Index - 1;
        while (Before >= 0) and not Significant(Tokens[Before]) do
        begin
          Dec(Before);
        end;
        if (Before >= 0) and Tokens[Before].IsSymbol('.') then
        begin
          Continue;
        end;
        // Inline-Variable (var Name) bzw. Schleifenvariable (for var Name) ist lokal.
        if (Before >= 0) and SameText(Tokens[Before].Text, 'var') then
        begin
          Declared := True;
        end;
        if not Resolved and (AResolver <> nil) then
        begin
          Symbol := AResolver.Resolve(ATree, AFileName, Token.StartPos);
          Result.Local := (Symbol.Kind = TResolvedKind.Local) and (Symbol.SymbolKind = TIndexSymbolKind.Variable);
          Resolved := True;
        end;
        Line := Token.StartPos.Line;
        FirstLine := Line;
        if (Result.FirstUse < 0) or (Line < Result.FirstUse) then
        begin
          Result.FirstUse := Line;
        end;
        LastLine := Line;
        for Loop in Loops do
        begin
          if (Loop.StartOffset <= Token.Offset) and (Token.Offset < Loop.EndOffset) then
          begin
            if Loop.StartPos.Line < FirstLine then
            begin
              FirstLine := Loop.StartPos.Line;
            end;
            if Loop.EndPos.Line > LastLine then
            begin
              LastLine := Loop.EndPos.Line;
            end;
          end;
        end;
        if FirstLine < Result.FirstUse then
        begin
          Result.FirstUse := FirstLine;
        end;
        if LastLine > Result.LastUse then
        begin
          Result.LastUse := LastLine;
        end;
      end;
    finally
      if AResolver <> nil then
      begin
        AResolver.UnpinTree;
      end;
    end;
  finally
    Loops.Free;
  end;
  // Deklaration in der Routine zählt auch, wenn der Index den Namen anders auflöst.
  if Result.IsParameter or Declared then
  begin
    Result.Local := True;
  end;
  if Result.IsParameter and (Result.FirstUse >= 0) then
  begin
    Result.FirstUse := Result.RoutineStartLine;
  end;
  if Result.FirstUse < 0 then
  begin
    Result.Lifetime := TVariableLifetime.Unused;
  end
  else if AStoppedLine < Result.FirstUse then
  begin
    Result.Lifetime := TVariableLifetime.Before;
  end
  else if AStoppedLine > Result.LastUse then
  begin
    Result.Lifetime := TVariableLifetime.After;
  end
  else
  begin
    Result.Lifetime := TVariableLifetime.Within;
  end;
end;

class function TLspDebugUnavailable.ToJson(const AFacts: TUnavailableFacts; const AState: TCompilerSwitchState;
  const AFileName: string): TJSONObject;
var
  Switches: TJSONArray;
  Entry: TSwitchEntry;
  Routine, Variable, Fixes: TJSONObject;
begin
  Result := TJSONObject.Create;
  Switches := TJSONArray.Create;
  for Entry in AState.Switches do
  begin
    if (Entry.Name = 'D') or (Entry.Name = 'L') or (Entry.Name = 'O') then
    begin
      Switches.AddElement(TLspCompilerSwitches.EntryToJson(Entry));
    end;
  end;
  Result.AddPair('switches', Switches);
  if AFacts.HasRoutine then
  begin
    Routine := TJSONObject.Create;
    Routine.AddPair('name', AFacts.RoutineName);
    Routine.AddPair('inline', TJSONBool.Create(AFacts.RoutineInline));
    Routine.AddPair('startLine', TJSONNumber.Create(AFacts.RoutineStartLine));
    Routine.AddPair('endLine', TJSONNumber.Create(AFacts.RoutineEndLine));
    Result.AddPair('routine', Routine);
  end;
  Variable := TJSONObject.Create;
  Variable.AddPair('local', TJSONBool.Create(AFacts.Local));
  Variable.AddPair('parameter', TJSONBool.Create(AFacts.IsParameter));
  Variable.AddPair('firstUse', TJSONNumber.Create(AFacts.FirstUse));
  Variable.AddPair('lastUse', TJSONNumber.Create(AFacts.LastUse));
  Variable.AddPair('lifetime', LifetimeNames[AFacts.Lifetime]);
  Result.AddPair('variable', Variable);
  Fixes := TJSONObject.Create;
  if Length(AFacts.RoutineFix) > 0 then
  begin
    Fixes.AddPair('routineOptimization', TLspApplyEdit.TextEdits(AFileName, AFacts.RoutineFix));
  end;
  if Length(AFacts.UnitFix) > 0 then
  begin
    Fixes.AddPair('unitOptimization', TLspApplyEdit.TextEdits(AFileName, AFacts.UnitFix));
  end;
  Result.AddPair('fixes', Fixes);
end;

function TLspDebugUnavailable.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, Name, FileName: string;
  PositionValue: TJSONValue;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TCompilerSwitchContext;
  Facts: TUnavailableFacts;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue) and
    TJSONObject(AParams).TryGetValue<string>('name', Name)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri", "position" und "name" fehlen in ' + Method);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  ACancellation.ThrowIfCancellationRequested;
  Position := TLspPositions.ReadPosition(PositionValue);
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TCompilerSwitchContext);
  if Assigned(FContextFor) then
  begin
    Context := FContextFor(Uri);
  end;
  Resolver := nil;
  if FIndex <> nil then
  begin
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  end;
  try
    Facts := TLspDebugUnavailable.Facts(Resolver, Shared.Tree, FileName, Document.Text, Name, Position.Line);
  finally
    Resolver.Free;
  end;
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(Facts, TLspCompilerSwitches.StateAt(Document.Text, Position, Context), FileName);
end;

end.
