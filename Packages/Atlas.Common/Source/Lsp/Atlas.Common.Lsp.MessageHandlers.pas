unit Atlas.Common.Lsp.MessageHandlers;

// Message-Handler einer Klasse (procedure WMPaint(var Message: TWMPaint); message WM_PAINT;)
// und welche Vorfahren dieselbe Nachricht schon behandeln. Grundlage für Code Lens und Hover (#36).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TMessageReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TMessageHandler = record
    /// <summary>Nachricht wie im Quelltext, z. B. WM_PAINT.</summary>
    Message: string;
    MethodName: string;
    TypeName: string;
    FileName: string;
    SelectionRange: TTextRange;
  end;

  TMessageOverview = record
    Own: TArray<TMessageHandler>;
    /// <summary>Je Eintrag in Own der nächste Vorfahr mit derselben Nachricht; TypeName '' = keiner.</summary>
    Inherited_: TArray<TMessageHandler>;
    function Found: Boolean;
    /// <summary>Kurzfassung für Code Lens, z. B. "behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in TWinControl)".</summary>
    function Title: string;
    function ToMarkdown: string;
  end;

  TMessageHandlers = class
  public const
    MaxDepth = 32;
  public
    /// <summary>Message-Handler, die ATypeName in ATree selbst deklariert.</summary>
    class function InTree(ATree: TSyntaxTree; const AFileName, ATypeName: string): TArray<TMessageHandler>; static;
    /// <summary>Eigene Handler von ATypeName und die Vorfahren, die dieselben Nachrichten behandeln.</summary>
    class function Overview(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, ATypeName: string; const AReadText: TMessageReadText): TMessageOverview; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor;

function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function FindClassNode(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  Root, Found: TSyntaxNode;
  TypeName: string;
begin
  Root := ANode;
  TypeName := ATypeName;
  // Search statt Rekursion (Bericht M1).
  Found := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if ACandidate = Root then
        Exit(TSyntaxSearchStep.Descend);
      if (ACandidate.Kind = TSyntaxKind.TypeDecl) and SameText(ACandidate.Name, TypeName) and
        (ACandidate.FindChild(TSyntaxKind.ClassType) <> nil) then
        Exit(TSyntaxSearchStep.Found);
      // Routinen enthalten keine Klassen, die hier gemeint sind.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := nil;
  if Found <> nil then
    Result := Found.FindChild(TSyntaxKind.ClassType);
end;

/// <summary>Botschaftsbehandler aus dem Methodenkopf AHeader (Direktive message) in AList.</summary>
procedure AddHandlers(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  Inner, TokenIndex: Integer;
  Directive: TSyntaxNode;
  Handler: TMessageHandler;
begin
  for Inner := 0 to AHeader.ChildCount - 1 do
  begin
    Directive := AHeader[Inner];
    if (Directive.Kind <> TSyntaxKind.Directive) or (Directive.Name <> 'message') then
      Continue;
    Handler := Default(TMessageHandler);
    Handler.MethodName := AHeader.Name;
    Handler.TypeName := ATypeName;
    Handler.FileName := AFileName;
    Handler.SelectionRange := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
    // Argument: alle Tokens der Direktive hinter "message".
    TokenIndex := FirstTokenAt(ATokens, Directive.StartOffset) + 1;
    while (TokenIndex <= High(ATokens)) and (ATokens[TokenIndex].Offset < Directive.EndOffset) do
    begin
      if not (ATokens[TokenIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Handler.Message := Handler.Message + ATokens[TokenIndex].Text;
      Inc(TokenIndex);
    end;
    // Auswahl auf den Methodennamen.
    TokenIndex := FirstTokenAt(ATokens, AHeader.StartOffset);
    while (TokenIndex <= High(ATokens)) and (ATokens[TokenIndex].Offset < AHeader.EndOffset) do
    begin
      if (ATokens[TokenIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[TokenIndex].Text, AHeader.Name) then
      begin
        Handler.SelectionRange := TTextRange.Create(ATokens[TokenIndex].StartPos, ATokens[TokenIndex].EndPos);
        Break;
      end;
      Inc(TokenIndex);
    end;
    if Handler.Message <> '' then
      AList.Add(Handler);
  end;
end;

procedure CollectHandlers(ATree: TSyntaxTree; ANode: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  Root: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  FileName, TypeName: string;
  List: TList<TMessageHandler>;
begin
  Root := ANode;
  Tokens := ATree.Tokens;
  FileName := AFileName;
  TypeName := ATypeName;
  List := AList;
  // Walk statt Rekursion (Bericht M1); die Reihenfolge der Behandler bleibt die des Quelltexts.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild = Root then
        Exit(True);
      // Verschachtelte Typen gehören nicht zur Klasse.
      if AChild.Kind = TSyntaxKind.TypeDecl then
        Exit(False);
      if AChild.Kind <> TSyntaxKind.RoutineHeader then
        Exit(True);
      AddHandlers(Tokens, AChild, FileName, TypeName, List);
      Result := False;
    end);
end;

{ TMessageOverview }

function TMessageOverview.Found: Boolean;
begin
  Result := Length(Own) > 0;
end;

function TMessageOverview.Title: string;
var
  Index: Integer;
  Also: string;
begin
  Result := '';
  Also := '';
  for Index := 0 to High(Own) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Own[Index].Message;
    if Inherited_[Index].TypeName <> '' then
    begin
      if Also <> '' then
        Also := Also + ', ';
      Also := Also + Own[Index].Message + ' auch in ' + Inherited_[Index].TypeName;
    end;
  end;
  Result := 'behandelt ' + Result;
  if Also <> '' then
    Result := Result + ' (' + Also + ')';
end;

function TMessageOverview.ToMarkdown: string;
var
  Index: Integer;
begin
  Result := '';
  if not Found then
    Exit;
  Result := '**Nachrichten**' + #10;
  for Index := 0 to High(Own) do
  begin
    Result := Result + #10 + '- `' + Own[Index].Message + '` → `' + Own[Index].MethodName + '`';
    if Inherited_[Index].TypeName <> '' then
      Result := Result + ', auch in `' + Inherited_[Index].TypeName + '.' + Inherited_[Index].MethodName + '`';
  end;
end;

{ TMessageHandlers }

class function TMessageHandlers.InTree(ATree: TSyntaxTree; const AFileName, ATypeName: string): TArray<TMessageHandler>;
var
  ClassNode: TSyntaxNode;
  List: TList<TMessageHandler>;
begin
  Result := nil;
  if ATree = nil then
    Exit;
  ClassNode := FindClassNode(ATree.Root, ATypeName);
  if ClassNode = nil then
    Exit;
  List := TList<TMessageHandler>.Create;
  try
    CollectHandlers(ATree, ClassNode, AFileName, ATypeName, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TMessageHandlers.Overview(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, ATypeName: string; const AReadText: TMessageReadText): TMessageOverview;
var
  Trees: TObjectDictionary<string, TSyntaxTree>;
  CurrentUnit: TUnitIndex;
  CurrentTree, Tree: TSyntaxTree;
  CurrentName, AncestorName, Text: string;
  Symbol, ClassSymbol: TIndexSymbol;
  Found: Boolean;
  Ancestor: TResolvedSymbol;
  Handlers: TArray<TMessageHandler>;
  Handler: TMessageHandler;
  Depth, Index: Integer;
begin
  Result := Default(TMessageOverview);
  Result.Own := InTree(ATree, AFileName, ATypeName);
  SetLength(Result.Inherited_, Length(Result.Own));
  if not Result.Found then
    Exit;
  Trees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  try
    CurrentTree := ATree;
    CurrentUnit := TIndexExtractor.Extract(ATree, AFileName);
    CurrentName := ATypeName;
    for Depth := 1 to MaxDepth do
    begin
      // Vorfahr der aktuellen Klasse aus ihrer Unit.
      Found := False;
      ClassSymbol := Default(TIndexSymbol);
      for Symbol in CurrentUnit.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, CurrentName) then
        begin
          ClassSymbol := Symbol;
          Found := True;
          Break;
        end;
      if not Found then
        Break;
      if Length(ClassSymbol.Ancestors) > 0 then
        AncestorName := ClassSymbol.Ancestors[0]
      else if not SameText(CurrentName, 'TObject') then
        AncestorName := 'TObject'
      else
        Break;
      if (Pos('<', AncestorName) > 0) or not AResolver.ResolveTypeFrom(CurrentUnit, AncestorName, Ancestor) or
        (Ancestor.SymbolKind <> TIndexSymbolKind.ClassType) then
        Break;
      if SameText(Ancestor.FileName, AFileName) then
        Tree := ATree
      else if not Trees.TryGetValue(UpperCase(Ancestor.FileName), Tree) then
      begin
        if not (Assigned(AReadText) and AReadText(Ancestor.FileName, Text)) then
          Break;
        Tree := TSyntaxTreeCache.Parse(Text);
        Trees.Add(UpperCase(Ancestor.FileName), Tree);
      end;
      Handlers := InTree(Tree, Ancestor.FileName, Ancestor.Name);
      for Index := 0 to High(Result.Own) do
        if Result.Inherited_[Index].TypeName = '' then
          for Handler in Handlers do
            if SameText(Handler.Message, Result.Own[Index].Message) then
            begin
              Result.Inherited_[Index] := Handler;
              Break;
            end;
      if Tree <> CurrentTree then
        CurrentUnit := TIndexExtractor.Extract(Tree, Ancestor.FileName);
      CurrentTree := Tree;
      CurrentName := Ancestor.Name;
    end;
  finally
    Trees.Free;
  end;
end;

end.
