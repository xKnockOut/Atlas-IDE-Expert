unit Argus.Common.Lsp.MessageHandlers;

// Message-Handler einer Klasse (procedure WMPaint(var Message: TWMPaint); message WM_PAINT;)
// und welche Vorfahren dieselbe Nachricht schon behandeln. Grundlage für Code Lens und Hover (#36).

interface

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

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
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.Extractor;

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
  Index: Integer;
  Child: TSyntaxNode;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if (Child.Kind = TSyntaxKind.TypeDecl) and SameText(Child.Name, ATypeName) then
    begin
      Result := Child.FindChild(TSyntaxKind.ClassType);
      if Result <> nil then
        Exit;
    end;
    // Routinen enthalten keine Klassen, die hier gemeint sind.
    if Child.Kind <> TSyntaxKind.RoutineDecl then
    begin
      Result := FindClassNode(Child, ATypeName);
      if Result <> nil then
        Exit;
    end;
  end;
  Result := nil;
end;

procedure CollectHandlers(ATree: TSyntaxTree; ANode: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  Index, Inner, TokenIndex: Integer;
  Child, Directive: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Handler: TMessageHandler;
begin
  Tokens := ATree.Tokens;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    // Verschachtelte Typen gehören nicht zur Klasse.
    if Child.Kind = TSyntaxKind.TypeDecl then
      Continue;
    if Child.Kind <> TSyntaxKind.RoutineHeader then
    begin
      CollectHandlers(ATree, Child, AFileName, ATypeName, AList);
      Continue;
    end;
    for Inner := 0 to Child.ChildCount - 1 do
    begin
      Directive := Child[Inner];
      if (Directive.Kind <> TSyntaxKind.Directive) or (Directive.Name <> 'message') then
        Continue;
      Handler := Default(TMessageHandler);
      Handler.MethodName := Child.Name;
      Handler.TypeName := ATypeName;
      Handler.FileName := AFileName;
      Handler.SelectionRange := TTextRange.Create(Child.StartPos, Child.EndPos);
      // Argument: alle Tokens der Direktive hinter "message".
      TokenIndex := FirstTokenAt(Tokens, Directive.StartOffset) + 1;
      while (TokenIndex <= High(Tokens)) and (Tokens[TokenIndex].Offset < Directive.EndOffset) do
      begin
        if not (Tokens[TokenIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
          Handler.Message := Handler.Message + Tokens[TokenIndex].Text;
        Inc(TokenIndex);
      end;
      // Auswahl auf den Methodennamen.
      TokenIndex := FirstTokenAt(Tokens, Child.StartOffset);
      while (TokenIndex <= High(Tokens)) and (Tokens[TokenIndex].Offset < Child.EndOffset) do
      begin
        if (Tokens[TokenIndex].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[TokenIndex].Text, Child.Name) then
        begin
          Handler.SelectionRange := TTextRange.Create(Tokens[TokenIndex].StartPos, Tokens[TokenIndex].EndPos);
          Break;
        end;
        Inc(TokenIndex);
      end;
      if Handler.Message <> '' then
        AList.Add(Handler);
    end;
  end;
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
        Tree := TPascalParser.Parse(Text);
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
