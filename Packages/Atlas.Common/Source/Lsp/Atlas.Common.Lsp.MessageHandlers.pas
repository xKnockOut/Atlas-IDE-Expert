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
    class function Overview(AResolver: TNameResolver; ATree: TSyntaxTree;
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
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
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
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if (ACandidate.Kind = TSyntaxKind.TypeDecl) and SameText(ACandidate.Name, TypeName) and
        (ACandidate.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      // Routinen enthalten keine Klassen, die hier gemeint sind.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := nil;
  if Found <> nil then
  begin
    Result := Found.FindChild(TSyntaxKind.ClassType);
  end;
end;

/// <summary>Argument der Direktive message: alle Tokens der Direktive ADirective hinter "message".</summary>
function DirectiveArgument(const ATokens: TArray<TPascalToken>; ADirective: TSyntaxNode): string;
var
  TokenIndex: Integer;
begin
  Result := '';
  TokenIndex := FirstTokenAt(ATokens, ADirective.StartOffset) + 1;
  while (TokenIndex <= High(ATokens)) and (ATokens[TokenIndex].Offset < ADirective.EndOffset) do
  begin
    if not (ATokens[TokenIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + ATokens[TokenIndex].Text;
    end;
    Inc(TokenIndex);
  end;
end;

/// <summary>Bereich des Methodennamens im Kopf AHeader; ohne Fund der ganze Kopf.</summary>
function NameRange(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  TokenIndex: Integer;
begin
  TokenIndex := FirstTokenAt(ATokens, AHeader.StartOffset);
  while (TokenIndex <= High(ATokens)) and (ATokens[TokenIndex].Offset < AHeader.EndOffset) do
  begin
    if (ATokens[TokenIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[TokenIndex].Text, AHeader.Name) then
    begin
      Exit(TTextRange.Create(ATokens[TokenIndex].StartPos, ATokens[TokenIndex].EndPos));
    end;
    Inc(TokenIndex);
  end;
  Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
end;

/// <summary>Botschaftsbehandler aus dem Methodenkopf AHeader (Direktive message) in AList.</summary>
procedure AddHandlers(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  Inner: Integer;
  Directive: TSyntaxNode;
  Handler: TMessageHandler;
begin
  for Inner := 0 to AHeader.ChildCount - 1 do
  begin
    Directive := AHeader[Inner];
    if (Directive.Kind <> TSyntaxKind.Directive) or (Directive.Name <> 'message') then
    begin
      Continue;
    end;
    Handler := Default(TMessageHandler);
    Handler.MethodName := AHeader.Name;
    Handler.TypeName := ATypeName;
    Handler.FileName := AFileName;
    Handler.Message := DirectiveArgument(ATokens, Directive);
    Handler.SelectionRange := NameRange(ATokens, AHeader);
    if Handler.Message <> '' then
    begin
      AList.Add(Handler);
    end;
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
      begin
        Exit(True);
      end;
      // Verschachtelte Typen gehören nicht zur Klasse.
      if AChild.Kind = TSyntaxKind.TypeDecl then
      begin
        Exit(False);
      end;
      if AChild.Kind <> TSyntaxKind.RoutineHeader then
      begin
        Exit(True);
      end;
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
    begin
      Result := Result + ', ';
    end;
    Result := Result + Own[Index].Message;
    if Inherited_[Index].TypeName <> '' then
    begin
      if Also <> '' then
      begin
        Also := Also + ', ';
      end;
      Also := Also + Own[Index].Message + ' auch in ' + Inherited_[Index].TypeName;
    end;
  end;
  Result := 'behandelt ' + Result;
  if Also <> '' then
  begin
    Result := Result + ' (' + Also + ')';
  end;
end;

function TMessageOverview.ToMarkdown: string;
var
  Index: Integer;
begin
  Result := '';
  if not Found then
  begin
    Exit;
  end;
  Result := '**Nachrichten**' + #10;
  for Index := 0 to High(Own) do
  begin
    Result := Result + #10 + '- `' + Own[Index].Message + '` → `' + Own[Index].MethodName + '`';
    if Inherited_[Index].TypeName <> '' then
    begin
      Result := Result + ', auch in `' + Inherited_[Index].TypeName + '.' + Inherited_[Index].MethodName + '`';
    end;
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
  begin
    Exit;
  end;
  ClassNode := FindClassNode(ATree.Root, ATypeName);
  if ClassNode = nil then
  begin
    Exit;
  end;
  List := TList<TMessageHandler>.Create;
  try
    CollectHandlers(ATree, ClassNode, AFileName, ATypeName, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Klasse ATypeName (nicht verschachtelt) im Index AUnit.</summary>
function ClassSymbolOf(const AUnit: TUnitIndex; const ATypeName: string; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, ATypeName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Vorfahr der Klasse ATypeName aus ihrer Unit AUnit; False am Ende der Kette oder ohne Auflösung.
/// </summary>
function ResolveAncestor(AResolver: TNameResolver; const AUnit: TUnitIndex; const ATypeName: string;
  out AAncestor: TResolvedSymbol): Boolean;
var
  ClassSymbol: TIndexSymbol;
  AncestorName: string;
begin
  Result := False;
  if not ClassSymbolOf(AUnit, ATypeName, ClassSymbol) then
  begin
    Exit;
  end;
  if Length(ClassSymbol.Ancestors) > 0 then
  begin
    AncestorName := ClassSymbol.Ancestors[0];
  end
  else if not SameText(ATypeName, 'TObject') then
  begin
    AncestorName := 'TObject';
  end
  else
  begin
    Exit;
  end;
  Result := (Pos('<', AncestorName) = 0) and AResolver.ResolveTypeFrom(AUnit, AncestorName, AAncestor) and
    (AAncestor.SymbolKind = TIndexSymbolKind.ClassType);
end;

/// <summary>Baum der Datei AFileName: AOwnTree für die eigene Datei AOwnFile, sonst aus ATrees oder gelesen.
/// </summary>
function TreeOf(const AFileName, AOwnFile: string; AOwnTree: TSyntaxTree;
  ATrees: TObjectDictionary<string, TSyntaxTree>; const AReadText: TMessageReadText; out ATree: TSyntaxTree): Boolean;
var
  Text: string;
begin
  Result := True;
  if SameText(AFileName, AOwnFile) then
  begin
    ATree := AOwnTree;
  end
  else if not ATrees.TryGetValue(UpperCase(AFileName), ATree) then
  begin
    Result := Assigned(AReadText) and AReadText(AFileName, Text);
    if Result then
    begin
      ATree := TSyntaxTreeCache.Parse(Text);
      ATrees.Add(UpperCase(AFileName), ATree);
    end;
  end;
end;

/// <summary>Trägt für noch nicht gefundene eigene Behandler den gleichen Behandler aus AHandlers ein.</summary>
procedure MatchInherited(var AOverview: TMessageOverview; const AHandlers: TArray<TMessageHandler>);
var
  Handler: TMessageHandler;
  Index: Integer;
begin
  for Index := 0 to High(AOverview.Own) do
  begin
    for Handler in AHandlers do
    begin
      if (AOverview.Inherited_[Index].TypeName = '') and SameText(Handler.Message, AOverview.Own[Index].Message) then
      begin
        AOverview.Inherited_[Index] := Handler;
      end;
    end;
  end;
end;

class function TMessageHandlers.Overview(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, ATypeName: string; const AReadText: TMessageReadText): TMessageOverview;
var
  Trees: TObjectDictionary<string, TSyntaxTree>;
  CurrentUnit: TUnitIndex;
  CurrentTree, Tree: TSyntaxTree;
  CurrentName: string;
  Ancestor: TResolvedSymbol;
  Depth: Integer;
begin
  Result := Default(TMessageOverview);
  Result.Own := InTree(ATree, AFileName, ATypeName);
  SetLength(Result.Inherited_, Length(Result.Own));
  if not Result.Found then
  begin
    Exit;
  end;
  Trees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  try
    CurrentTree := ATree;
    CurrentUnit := TIndexExtractor.Extract(ATree, AFileName);
    CurrentName := ATypeName;
    for Depth := 1 to MaxDepth do
    begin
      if not ResolveAncestor(AResolver, CurrentUnit, CurrentName, Ancestor) or
        not TreeOf(Ancestor.FileName, AFileName, ATree, Trees, AReadText, Tree) then
      begin
        Break;
      end;
      MatchInherited(Result, InTree(Tree, Ancestor.FileName, Ancestor.Name));
      if Tree <> CurrentTree then
      begin
        CurrentUnit := TIndexExtractor.Extract(Tree, Ancestor.FileName);
      end;
      CurrentTree := Tree;
      CurrentName := Ancestor.Name;
    end;
  finally
    Trees.Free;
  end;
end;

end.
