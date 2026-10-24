unit Atlas.Common.Lsp.InlayHints;

// Inlay Hints (textDocument/inlayHint):
//   - Parameternamen vor den Argumenten eines Aufrufs (über die Parameterhilfe, #32);
//     entfällt, wenn das Argument schon so heißt,
//   - abgeleiteter Typ hinter var X := …, const X = … und for var X in … (Literale, Konstruktoren, Funktionen,
//     Variablen, Elemente von Arrays und Enumeratoren; #453), dazu die Aktion „Typ ausschreiben“
//     (ExplicitTypeAction) mit uses-Eintrag für die Unit des Typs,
//   - Endmarkierungen hinter dem end langer Blöcke: Routine, Typ, if/while/for/with/case/try,
//   - hinter {$I datei.inc} die Symbole, die die Datei dort setzt und die eine Bedingung dieser Unit
//     prüft: „definiert COMPLIB_VCL“ (#860), aus dem Präprozessor-Lauf des gemeinsamen Baums,
//   - hinter Steuerzeichen wie ^C im Wert einer Konstanten ihr Code „#3“ (#862).
// Was erscheint, steuert "inlayHints" in atlas.json.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.Hover;

type
  TInlayHint = record
    Position: TTextPosition;
    Text: string;
    /// <summary>InlayHintKind des LSP: 1 Typ, 2 Parameter, 0 ohne.</summary>
    Kind: Integer;
    PaddingLeft: Boolean;
    PaddingRight: Boolean;
    /// <summary>Endmarke (#620): Anfang des Blocks, zu dem ein Klick springt; nur mit HasBlockStart.</summary>
    BlockStart: TTextPosition;
    HasBlockStart: Boolean;
    /// <summary>Hinweis hinter {$I} (#860): gesetzte Symbole und Name der Include-Datei; leer sonst.</summary>
    Defines: TArray<string>;
    IncludeFile: string;
    /// <summary>Code eines Steuerzeichens wie ^C (#862); nur mit ControlChar.</summary>
    CharCode: Integer;
    ControlChar: Boolean;
    /// <summary>Marke „ohne Self“ am Ende des Kopfs einer Methode (#686).</summary>
    MethodWithoutSelf: Boolean;
  end;

  /// <summary>Abgeleiteter Typ einer Inline-Variablen ohne Typangabe (#453).</summary>
  TInferredType = record
    Name: string;
    NameStart: TTextPosition;
    /// <summary>Ende des Namens: Stelle der Marke und von ": Typ".</summary>
    NameEnd: TTextPosition;
    /// <summary>Typ wie im Quelltext, z. B. "TList&lt;TKunde&gt;".</summary>
    TypeName: string;
    /// <summary>Laufvariable in for var X in ….</summary>
    ForIn: Boolean;
    /// <summary>Unit der Typdeklaration, wenn die Namensauflösung sie kennt; '' sonst.</summary>
    TypeUnit: string;
    /// <summary>Symbol, von dessen Unit aus TypeName gilt (Funktion, Feld, Enumerator); Name '' ohne.</summary>
    Origin: TResolvedSymbol;
  end;

  /// <summary>Einstellungen für das Dokument AUri.</summary>
  TInlayHintSettingsProvider = reference to function(const AUri: string): TInlayHintSettings;

  TLspInlayHints = class
  public const
    Method = 'textDocument/inlayHint';
    MaxLabelLength = 50;
    /// <summary>Längste Bedingung einer Endmarke (#620), danach „…“.</summary>
    MaxEndLabelLength = 40;
    /// <summary>Mindestlänge des Blocks aus der Anfrage (#620, editor.blockEndLabels.minLines im Plugin); geht
    /// inlayHints.endMarkerMinLines vor.</summary>
    MinLinesParam = 'atlas.endMarkerMinLines';
    /// <summary>Anfang der Beschriftung hinter {$I} (#860).</summary>
    DefinesPrefix = 'definiert ';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FSettings: TInlayHintSettingsProvider;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function ParameterNames(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>; static;
    class function InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Inline-Variablen, -Konstanten und for-in-Laufvariablen ohne Typangabe in ARange mit ihrem
    /// abgeleiteten Typ (#453).</summary>
    class function Inferred(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const ARange: TTextRange): TArray<TInferredType>; static;
    /// <summary>„Typ ausschreiben“ (#453) für die Inline-Variable, auf deren Namen APosition steht: fügt
    /// ": Typ" ein und trägt fehlende Units des Typs ins uses ein. False ohne Treffer.</summary>
    class function ExplicitTypeAction(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const ALineBreak: string; out AAction: TCodeAction): Boolean; static;
    class function EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange; AMinLines: Integer): TArray<TInlayHint>; static;
    /// <summary>Hinter jedem {$I datei} in ARange die Symbole, die die Include-Datei setzt und die eine
    /// $IFDEF/$IF-Bedingung von ATree prüft (#860); AProcessed ist der Präprozessor-Lauf zum Baum.</summary>
    class function IncludeDefines(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Hinter jedem Steuerzeichen wie ^C im Wert einer Konstanten in ARange sein Code „#3“ (#862);
    /// ATreeText ist der Text, aus dem ATree gelesen wurde.</summary>
    class function ControlChars(ATree: TSyntaxTree; const ATreeText: string;
      const ARange: TTextRange): TArray<TInlayHint>; static;
    /// <summary>Hinter dem Kopf jeder Methode in ARange, die Self nicht braucht, die Marke „ohne Self“ (#686);
    /// Mitglieder, Interfaces und Formular über AResolver und AReadText.</summary>
    class function MethodMarkers(AResolver: TNameResolver; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>; static;
    /// <summary>Alle eingeschalteten Hinweise in ARange, nach Position sortiert.</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
      const AReadText: THoverReadText): TArray<TInlayHint>; overload; static;
    /// <summary>Wie oben, dazu die Symbole hinter {$I} aus dem Präprozessor-Lauf AProcessed (#860).</summary>
    class function Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
      const AReadText: THoverReadText; const AProcessed: TPreprocessorResult): TArray<TInlayHint>; overload; static;
    /// <summary>InlayHint[] des LSP. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHints: TArray<TInlayHint>): TJSONArray; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.MethodWithoutSelf,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Text.Chars;

type
  TSyntaxKinds = set of TSyntaxKind;

const
  KindType = 1;
  KindParameter = 2;
  ParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function InRange(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ARange.StartPos, APosition) <= 0) and (ComparePositions(APosition, ARange.EndPos) <= 0);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

/// <summary>Index des ersten Tokens mit Offset >= AOffset.</summary>
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

procedure CollectNodes(ANode: TSyntaxNode; const AKinds: TSyntaxKinds; AList: TList<TSyntaxNode>);
var
  Kinds: TSyntaxKinds;
  List: TList<TSyntaxNode>;
begin
  Kinds := AKinds;
  List := AList;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind in Kinds then
        List.Add(AChild);
      Result := True;
    end);
end;

/// <summary>Parametername aus "const A: Integer = 1" bzw. "A".</summary>
function ParameterName(const AText: string): string;
var
  Modifier: string;
  Colon: Integer;
begin
  Result := Trim(AText);
  for Modifier in ParameterModifiers do
    if StartsText(Modifier, Result) then
      Delete(Result, 1, Length(Modifier));
  Colon := Pos(':', Result);
  if Colon > 0 then
    Result := Copy(Result, 1, Colon - 1);
  Colon := Pos('=', Result);
  if Colon > 0 then
    Result := Copy(Result, 1, Colon - 1);
  Result := Trim(Result);
end;

/// <summary>Kopfzeile eines Blocks als Text, z. B. "if Assigned(FTheme)".</summary>
function HeaderText(const ATokens: TArray<TPascalToken>; AFirst, ALast, AMaxLength: Integer): string;
var
  Index: Integer;
  Token: TPascalToken;
  Glue, AfterName: Boolean;
begin
  Result := '';
  Glue := True;
  AfterName := False;
  for Index := AFirst to ALast do
  begin
    Token := ATokens[Index];
    if IsTrivia(Token) then
      Continue;
    if Token.IsKeyword('then') or Token.IsKeyword('do') or Token.IsKeyword('of') then
      Break;
    // Kein Leerzeichen nach ( [ . und vor ) ] , . ; sowie zwischen Name und Aufrufklammer.
    if not (Glue or Token.IsSymbol(')') or Token.IsSymbol(']') or Token.IsSymbol(',') or Token.IsSymbol('.') or
      Token.IsSymbol(';') or AfterName and (Token.IsSymbol('(') or Token.IsSymbol('['))) then
      Result := Result + ' ';
    Result := Result + Token.Text;
    Glue := Token.IsSymbol('(') or Token.IsSymbol('[') or Token.IsSymbol('.');
    AfterName := Token.Kind = TPascalTokenKind.Identifier;
    if Length(Result) > AMaxLength then
      Exit(TrimRight(Copy(Result, 1, AMaxLength)) + '…');
  end;
end;

{ TLspInlayHints }

function TLspInlayHints.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspInlayHints.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspInlayHints.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const ASettings: TInlayHintSettingsProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FSettings := ASettings;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspInlayHints.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspInlayHints.ParameterNames(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  ATree: TSyntaxTree; const ATreeText, AFileName: string; const ARange: TTextRange;
  const AReadText: THoverReadText): TArray<TInlayHint>;
var
  Tokens: TArray<TPascalToken>;
  Blocks: TList<TSyntaxNode>;
  Block: TSyntaxNode;
  Index, Open, Scan, Depth, Argument, Last: Integer;
  Starts: TList<Integer>;
  InBlock: Boolean;
  Help: TSignatureHelp;
  Signature: TSignature;
  Chosen: Integer;
  Name: string;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  Tokens := ATree.Tokens;
  Blocks := TList<TSyntaxNode>.Create;
  Starts := TList<Integer>.Create;
  List := TList<TInlayHint>.Create;
  try
    // Nur Anweisungen: Köpfe von Routinen haben auch Bezeichner vor "(".
    CollectNodes(ATree.Root, [TSyntaxKind.Block], Blocks);
    for Index := 0 to High(Tokens) - 1 do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
        Continue;
      Open := NextToken(Tokens, Index);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') or not InRange(ARange, Tokens[Open].EndPos) then
        Continue;
      InBlock := False;
      for Block in Blocks do
        if (Block.StartOffset <= Tokens[Index].Offset) and (Tokens[Index].Offset < Block.EndOffset) then
        begin
          InBlock := True;
          Break;
        end;
      if not InBlock then
        Continue;
      // Argumente bis zur passenden Klammer.
      Starts.Clear;
      Depth := 0;
      Scan := NextToken(Tokens, Open);
      if (Scan <= High(Tokens)) and not Tokens[Scan].IsSymbol(')') then
        Starts.Add(Scan);
      while Scan <= High(Tokens) do
      begin
        if Tokens[Scan].IsSymbol('(') or Tokens[Scan].IsSymbol('[') then
          Inc(Depth)
        else if Tokens[Scan].IsSymbol(')') or Tokens[Scan].IsSymbol(']') then
        begin
          if Depth = 0 then
            Break;
          Dec(Depth);
        end
        else if (Depth = 0) and Tokens[Scan].IsSymbol(',') then
          Starts.Add(NextToken(Tokens, Scan))
        else if (Depth = 0) and Tokens[Scan].IsSymbol(';') then
          Break;
        Scan := NextToken(Tokens, Scan);
      end;
      if Starts.Count = 0 then
        Continue;
      Help := TLspSignatureHelp.HelpAt(AResolver, AIndex, ATree, ATreeText, AFileName, Tokens[Open].EndPos, AReadText);
      // Parameternamen der Compiler-Routinen (Assigned(P), Inc(X) ...) sagen nichts: keine Hinweise (#880).
      if Help.Intrinsic then
        Help.Signatures := nil;
      Chosen := -1;
      for Scan := 0 to High(Help.Signatures) do
        if Length(Help.Signatures[Scan].Parameters) >= Starts.Count then
        begin
          Chosen := Scan;
          Break;
        end;
      if Chosen < 0 then
        Continue;
      Signature := Help.Signatures[Chosen];
      for Argument := 0 to Starts.Count - 1 do
      begin
        Scan := Starts[Argument];
        if Scan > High(Tokens) then
          Continue;
        Name := ParameterName(Copy(Signature.Text, Signature.Parameters[Argument].StartIndex + 1,
          Signature.Parameters[Argument].EndIndex - Signature.Parameters[Argument].StartIndex));
        if Name = '' then
          Continue;
        // Argument heißt schon wie der Parameter (auch Self.Name, FName).
        Last := Scan;
        while (NextToken(Tokens, Last) <= High(Tokens)) and Tokens[NextToken(Tokens, Last)].IsSymbol('.') and
          (NextToken(Tokens, NextToken(Tokens, Last)) <= High(Tokens)) and
          (Tokens[NextToken(Tokens, NextToken(Tokens, Last))].Kind = TPascalTokenKind.Identifier) do
          Last := NextToken(Tokens, NextToken(Tokens, Last));
        if (Tokens[Last].Kind = TPascalTokenKind.Identifier) and
          (SameText(CleanName(Tokens[Last].Text), Name) or SameText(CleanName(Tokens[Last].Text), 'F' + Name) or
          SameText(CleanName(Tokens[Last].Text), 'A' + Name)) then
          Continue;
        Hint := Default(TInlayHint);
        Hint.Position := Tokens[Scan].StartPos;
        Hint.Text := Name + ':';
        Hint.Kind := KindParameter;
        Hint.PaddingRight := True;
        List.Add(Hint);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Starts.Free;
    Blocks.Free;
  end;
end;

/// <summary>Typ wie im Quelltext: eingebaut mit Namen, generisch mit eingesetzten Typargumenten ohne Unit.</summary>
function TypeDisplay(AResolver: TNameResolver; const AType: TResolvedSymbol): string;
var
  Binding: string;
  Values: TArray<string>;
begin
  Result := AType.Name;
  if Length(AType.Bindings) = 0 then
    Exit;
  Values := nil;
  for Binding in AType.Bindings do
    Values := Values + [AResolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  Result := Result + '<' + string.Join(', ', Values) + '>';
end;

/// <summary>Typtext mit eingesetzten Bindungen ("T" wird zu "TKunde"), ohne Unit davor.</summary>
function BoundText(AResolver: TNameResolver; const AText: string; const ABindings: TArray<string>): string;
var
  Binding: string;
  Unqualified: TArray<string>;
begin
  Unqualified := nil;
  for Binding in ABindings do
    Unqualified := Unqualified + [Copy(Binding, 1, Pos('=', Binding)) +
      AResolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  Result := TInterfaceStubs.SubstituteWords(AText, Unqualified);
end;

/// <summary>Elementtyp für "for var X in Ausdruck" (#453): Kette A.B.C; Array-Typen, string und
/// GetEnumerator.Current.</summary>
function ForInElement(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AOrigin: TResolvedSymbol): string;
var
  Names: TArray<string>;
  Index: Integer;
  Owner, TypeInfo, Member: TResolvedSymbol;
  TypeFound: Boolean;
  OwnerType: string;
begin
  Result := '';
  AOrigin := Default(TResolvedSymbol);
  // Nur eine Kette A.B.C ohne Aufruf.
  Names := nil;
  Index := AFirst;
  while Index <= ALast do
  begin
    if ATokens[Index].Kind <> TPascalTokenKind.Identifier then
      Exit;
    Names := Names + [CleanName(ATokens[Index].Text)];
    Index := NextToken(ATokens, Index);
    if Index > ALast then
      Break;
    if not ATokens[Index].IsSymbol('.') then
      Exit;
    Index := NextToken(ATokens, Index);
  end;
  if (Length(Names) = 0) or not AResolver.ChainType(ATree, AFileName, Names, ATokens[ALast].Offset, Owner, TypeInfo,
    TypeFound) then
    Exit;
  AOrigin := Owner;
  OwnerType := Owner.TypeName;
  if Owner.TypeArgs <> '' then
    OwnerType := OwnerType + '<' + Owner.TypeArgs + '>';
  Result := TPostfixTemplates.ElementOf(OwnerType);
  if (Result = '') and TypeFound then
    Result := TPostfixTemplates.ElementOf(TypeInfo.TypeName);
  if Result <> '' then
    Exit;
  if TPostfixTemplates.IsStringType(Owner.TypeName) or
    (TypeFound and TypeInfo.Builtin and TPostfixTemplates.IsStringType(TypeInfo.Name)) then
    Exit('Char');
  if not TypeFound or TypeInfo.Builtin then
    Exit;
  // Enumerator: Current von GetEnumerator, mit eingesetzten Typparametern.
  for Member in AResolver.MemberCandidates(ATree, AFileName, Names + ['GetEnumerator'], ATokens[ALast].Offset) do
    if SameText(Member.Name, 'Current') and (Member.TypeName <> '') then
    begin
      AOrigin := Member;
      Exit(BoundText(AResolver, Member.TypeName, Member.Bindings));
    end;
end;

class function TLspInlayHints.Inferred(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInferredType>;
var
  Tokens: TArray<TPascalToken>;
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, NameToken, Assign, First, Last, Scan, Depth: Integer;
  TypeName, TypeUnit: string;
  Resolved, Owner, TypeInfo, Origin: TResolvedSymbol;
  TypeFound: Boolean;
  Found: TInferredType;
  List: TList<TInferredType>;
  Typed: Boolean;
begin
  Tokens := ATree.Tokens;
  Nodes := TList<TSyntaxNode>.Create;
  List := TList<TInferredType>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.ForInStatement], Nodes);
    for Node in Nodes do
    begin
      if not InRange(ARange, Node.StartPos) or (Pos(',', Node.Name) > 0) then
        Continue;
      TypeName := '';
      TypeUnit := '';
      Origin := Default(TResolvedSymbol);
      NameToken := -1;
      if Node.Kind = TSyntaxKind.ForInStatement then
      begin
        // for var X in Ausdruck do: "var", Name, dann "in" ohne ":" dazwischen.
        Index := FirstTokenAt(Tokens, Node.StartOffset);
        if (Index + 3 > High(Tokens)) or not Tokens[Index].IsKeyword('for') then
          Continue;
        Index := NextToken(Tokens, Index);
        if not Tokens[Index].IsKeyword('var') then
          Continue;
        NameToken := NextToken(Tokens, Index);
        First := NextToken(Tokens, NameToken);
        if (First > High(Tokens)) or not Tokens[First].IsKeyword('in') then
          Continue;
        First := NextToken(Tokens, First);
        Last := First;
        while (NextToken(Tokens, Last) <= High(Tokens)) and not Tokens[NextToken(Tokens, Last)].IsKeyword('do') and
          (Tokens[NextToken(Tokens, Last)].Offset < Node.EndOffset) do
          Last := NextToken(Tokens, Last);
        if First > High(Tokens) then
          Continue;
        TypeName := ForInElement(AResolver, ATree, AFileName, Tokens, First, Last, Origin);
      end
      else
      begin
        // var X := …: Name, dann ":=" ohne ":" davor; const X = … mit "=".
        Assign := -1;
        Typed := False;
        Index := FirstTokenAt(Tokens, Node.StartOffset);
        while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) do
        begin
          if (NameToken < 0) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
            NameToken := Index
          else if Tokens[Index].IsSymbol(':') then
            Typed := True
          else if Tokens[Index].IsSymbol(':=') or ((Node.Kind = TSyntaxKind.InlineConst) and
            Tokens[Index].IsSymbol('=')) then
          begin
            Assign := Index;
            Break;
          end;
          Inc(Index);
        end;
        if Typed or (NameToken < 0) or (Assign < 0) then
          Continue;
        First := NextToken(Tokens, Assign);
        Last := First;
        while (NextToken(Tokens, Last) <= High(Tokens)) and (Tokens[NextToken(Tokens, Last)].Offset < Node.EndOffset) and
          not Tokens[NextToken(Tokens, Last)].IsSymbol(';') do
          Last := NextToken(Tokens, Last);
        if First > High(Tokens) then
          Continue;
        if First = Last then
          case Tokens[First].Kind of
            TPascalTokenKind.Number:
              if (Tokens[First].Text[1] <> '$') and (Tokens[First].Text[1] <> '%') and
                ((Pos('.', Tokens[First].Text) > 0) or (Pos('e', LowerCase(Tokens[First].Text)) > 0)) then
                TypeName := 'Extended'
              else
                TypeName := 'Integer';
            TPascalTokenKind.StringLiteral:
              if (Length(Tokens[First].Text) = 3) or (Tokens[First].Text = '''''''''') then
                TypeName := 'Char'
              else
                TypeName := 'string';
            TPascalTokenKind.CharLiteral:
              TypeName := 'Char';
            TPascalTokenKind.Identifier:
              if SameText(Tokens[First].Text, 'True') or SameText(Tokens[First].Text, 'False') then
                TypeName := 'Boolean';
          end;
        // Typ aus dem Ausdruck über die Namensauflösung (#453): auch generisch, TList<TKunde>.Create.
        if (TypeName = '') and AResolver.ChainType(ATree, AFileName, [CleanName(Tokens[NameToken].Text)],
          Node.EndOffset, Owner, TypeInfo, TypeFound) and TypeFound and (TypeInfo.Name <> '') then
        begin
          TypeName := TypeDisplay(AResolver, TypeInfo);
          if not TypeInfo.Builtin then
            TypeUnit := TypeInfo.UnitName;
          Origin := TypeInfo;
        end;
        if (TypeName = '') and (Tokens[First].Kind = TPascalTokenKind.Identifier) then
        begin
          // Kette A.B.C, optional mit einem Aufruf (…) am Ende, sonst nichts.
          Scan := First;
          while (NextToken(Tokens, Scan) <= Last) and Tokens[NextToken(Tokens, Scan)].IsSymbol('.') and
            (NextToken(Tokens, NextToken(Tokens, Scan)) <= Last) and
            (Tokens[NextToken(Tokens, NextToken(Tokens, Scan))].Kind = TPascalTokenKind.Identifier) do
            Scan := NextToken(Tokens, NextToken(Tokens, Scan));
          Index := Scan;
          if (Index < Last) and Tokens[NextToken(Tokens, Index)].IsSymbol('(') then
          begin
            Depth := 0;
            Index := NextToken(Tokens, Index);
            while Index <= Last do
            begin
              if Tokens[Index].IsSymbol('(') then
                Inc(Depth)
              else if Tokens[Index].IsSymbol(')') then
              begin
                Dec(Depth);
                if Depth = 0 then
                  Break;
              end;
              Index := NextToken(Tokens, Index);
            end;
          end;
          if Index = Last then
          begin
            Resolved := AResolver.Resolve(ATree, AFileName, Tokens[Scan].StartPos);
            if Resolved.Found and (Resolved.Kind <> TResolvedKind.UnitName) then
              Origin := Resolved;
            if Resolved.Found and (Resolved.Kind <> TResolvedKind.UnitName) then
              if Resolved.SymbolKind = TIndexSymbolKind.Constructor_ then
                TypeName := Resolved.Container
              else if Resolved.IsType then
                // Typumwandlung TFoo(X)
                TypeName := Resolved.Name
              else if Resolved.TypeName <> '' then
                TypeName := BoundText(AResolver, Resolved.TypeName, Resolved.Bindings)
              else if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
                // Enum-Werte stehen im Index unter ihrem Typ.
                TypeName := Resolved.Container;
          end;
        end;
      end;
      if (TypeName = '') or (NameToken < 0) then
        Continue;
      Found := Default(TInferredType);
      Found.NameStart := Tokens[NameToken].StartPos;
      Found.NameEnd := Tokens[NameToken].EndPos;
      Found.Name := CleanName(Tokens[NameToken].Text);
      Found.TypeName := TypeName;
      Found.ForIn := Node.Kind = TSyntaxKind.ForInStatement;
      Found.TypeUnit := TypeUnit;
      Found.Origin := Origin;
      List.Add(Found);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Nodes.Free;
  end;
end;

class function TLspInlayHints.InferredTypes(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  Found: TInferredType;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  List := TList<TInlayHint>.Create;
  try
    for Found in Inferred(AResolver, ATree, AFileName, ARange) do
    begin
      Hint := Default(TInlayHint);
      Hint.Position := Found.NameEnd;
      Hint.Text := ': ' + Found.TypeName;
      Hint.Kind := KindType;
      List.Add(Hint);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TLspInlayHints.ExplicitTypeAction(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const ALineBreak: string;
  out AAction: TCodeAction): Boolean;
var
  Found, Candidate: TInferredType;
  Tokens: TArray<TPascalToken>;
  Own, FromUnit: TUnitIndex;
  Used, Words, Added: TArray<string>;
  OwnName, Word, Base, UnitName: string;
  Resolved: TResolvedSymbol;
  Edit: TTextEdit;
  Index, Offset: Integer;
begin
  AAction := Default(TCodeAction);
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  for Candidate in Inferred(AResolver, ATree, AFileName, TTextRange.Create(APosition.Line, 0, APosition.Line,
    MaxInt)) do
    if (Candidate.NameStart.Line = APosition.Line) and (Candidate.NameStart.Character <= APosition.Character) and
      (APosition.Character <= Candidate.NameEnd.Character) then
    begin
      Found := Candidate;
      Result := True;
      Break;
    end;
  if not Result then
    Exit;
  AAction.Title := 'Typ ausschreiben';
  AAction.Kind := RewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(Found.NameEnd, Found.NameEnd), ': ' + Found.TypeName)];
  // Units der Namen im Typ (#180), die hier noch nicht sichtbar sind.
  Tokens := ATree.Tokens;
  Offset := 0;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].StartPos.Line = Found.NameStart.Line) and
      (Tokens[Index].StartPos.Character = Found.NameStart.Character) then
    begin
      Offset := Tokens[Index].Offset;
      Break;
    end;
  Own := AResolver.ExtractedUnit(ATree, AFileName);
  OwnName := TUsesClauses.OwnName(Tokens);
  Used := TUsesClauses.UsedUnits(Tokens);
  Added := nil;
  Base := Found.TypeName;
  if Pos('<', Base) > 0 then
    Base := Copy(Base, 1, Pos('<', Base) - 1);
  Words := Found.TypeName.Split([' ', '<', '>', ',', '^', '[', ']', '(', ')'], TStringSplitOptions.ExcludeEmpty);
  for Word in Words do
  begin
    if SameText(Word, 'array') or SameText(Word, 'of') or SameText(Word, 'string') or
      AResolver.ResolveTypeFrom(Own, Word, Resolved) then
      Continue;
    UnitName := '';
    if SameText(Word, Base) and (Found.TypeUnit <> '') then
      UnitName := Found.TypeUnit
    else if (Found.Origin.Name <> '') and AResolver.DeclaringUnit(Found.Origin, FromUnit) and
      AResolver.ResolveTypeFrom(FromUnit, Word, Resolved) and not Resolved.Builtin then
      UnitName := Resolved.UnitName;
    if (UnitName = '') or SameText(UnitName, OwnName) or SameText(UnitName, 'System') or
      TUsesClauses.IsUsed(Used, UnitName, AResolver.Namespaces) or (IndexText(UnitName, Added) >= 0) then
      Continue;
    if TUsesClauses.AddUnit(Tokens, Offset, UnitName, ALineBreak, Edit) then
    begin
      AAction.Edits := AAction.Edits + [Edit];
      Added := Added + [UnitName];
    end;
  end;
end;

class function TLspInlayHints.EndMarkers(ATree: TSyntaxTree; const ARange: TTextRange;
  AMinLines: Integer): TArray<TInlayHint>;
var
  Tokens: TArray<TPascalToken>;
  Nodes: TList<TSyntaxNode>;
  Node, Body: TSyntaxNode;
  EndToken, Next, First: Integer;
  Text: string;
  Hint: TInlayHint;
  List: TList<TInlayHint>;
begin
  Tokens := ATree.Tokens;
  Nodes := TList<TSyntaxNode>.Create;
  List := TList<TInlayHint>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl, TSyntaxKind.IfStatement,
      TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WithStatement,
      TSyntaxKind.CaseStatement, TSyntaxKind.TryStatement], Nodes);
    for Node in Nodes do
    begin
      if Node.EndPos.Line - Node.StartPos.Line + 1 < AMinLines then
        Continue;
      // Letztes Token des Knotens muss "end" sein (bei Routinen das des Rumpfs).
      Body := Node;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        Body := Node.FindChild(TSyntaxKind.Block);
        if Body = nil then
          Continue;
      end;
      EndToken := FirstTokenAt(Tokens, Body.EndOffset) - 1;
      while (EndToken >= 0) and (IsTrivia(Tokens[EndToken]) or Tokens[EndToken].IsSymbol(';')) do
        Dec(EndToken);
      if (EndToken < 0) or not Tokens[EndToken].IsKeyword('end') then
        Continue;
      case Node.Kind of
        TSyntaxKind.RoutineDecl, TSyntaxKind.TypeDecl:
          Text := Node.Name;
        // Woran der Block endet: try (finally) bzw. try (except).
        TSyntaxKind.TryStatement:
          if Node.FindChild(TSyntaxKind.FinallyBlock) <> nil then
            Text := 'try (finally)'
          else if Node.FindChild(TSyntaxKind.ExceptBlock) <> nil then
            Text := 'try (except)'
          else
            Text := 'try';
      else
        First := FirstTokenAt(Tokens, Node.StartOffset);
        Text := HeaderText(Tokens, First, EndToken, MaxEndLabelLength);
      end;
      if Text = '' then
        Continue;
      Hint := Default(TInlayHint);
      Hint.Position := Tokens[EndToken].EndPos;
      Next := NextToken(Tokens, EndToken);
      if (Next <= High(Tokens)) and (Tokens[Next].IsSymbol(';') or Tokens[Next].IsSymbol('.')) and
        (Tokens[Next].StartPos.Line = Tokens[EndToken].EndPos.Line) then
      begin
        Hint.Position := Tokens[Next].EndPos;
        EndToken := Next;
      end;
      if not InRange(ARange, Hint.Position) then
        Continue;
      // Steht hinter dem end schon ein Kommentar, sagt der genug.
      Next := EndToken + 1;
      if (Next <= High(Tokens)) and (Tokens[Next].Kind = TPascalTokenKind.Comment) and
        (Tokens[Next].StartPos.Line = Hint.Position.Line) then
        Continue;
      Hint.Text := '// ' + Text;
      Hint.PaddingLeft := True;
      Hint.BlockStart := Node.StartPos;
      Hint.HasBlockStart := True;
      List.Add(Hint);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Nodes.Free;
  end;
end;

/// <summary>Bezeichner in den Bedingungen ($IFDEF, $IFNDEF, $IF, $ELSEIF) der Datei, groß geschrieben.</summary>
function ConditionWords(ATree: TSyntaxTree): TDictionary<string, Boolean>;
var
  Token: TPascalToken;
  Text, Head: string;
  Index, Start: Integer;
begin
  Result := TDictionary<string, Boolean>.Create;
  for Token in ATree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Text := UpperCase(Token.Text);
    if Text.StartsWith('{$') then
      Text := Copy(Text, 3, MaxInt)
    else if Text.StartsWith('(*$') then
      Text := Copy(Text, 4, MaxInt)
    else
      Continue;
    Index := 1;
    while (Index <= Length(Text)) and TTextChars.IsIdentChar(Text[Index]) do
      Inc(Index);
    Head := Copy(Text, 1, Index - 1);
    if (Head <> 'IFDEF') and (Head <> 'IFNDEF') and (Head <> 'IF') and (Head <> 'ELSEIF') then
      Continue;
    while Index <= Length(Text) do
      if TTextChars.IsIdentStart(Text[Index]) then
      begin
        Start := Index;
        while (Index <= Length(Text)) and TTextChars.IsIdentChar(Text[Index]) do
          Inc(Index);
        Result.AddOrSetValue(Copy(Text, Start, Index - Start), True);
      end
      else
        Inc(Index);
  end;
end;

class function TLspInlayHints.IncludeDefines(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  Used: TDictionary<string, Boolean>;
  Site: TDefineSite;
  Token: TPascalToken;
  Hint: TInlayHint;
  Names: TArray<string>;
  Name, IncludeName: string;
  Index: Integer;
begin
  Result := nil;
  if Length(AProcessed.DefineSites) = 0 then
    Exit;
  Used := ConditionWords(ATree);
  try
    for Token in ATree.Tokens do
    begin
      if (Token.Kind <> TPascalTokenKind.Directive) or not InRange(ARange, Token.StartPos) or
        not TPascalPreprocessor.IncludeFileOf(Token.Text, IncludeName) then
        Continue;
      // Stand nach der Include-Datei: ein späteres $UNDEF dort nimmt das Symbol wieder heraus.
      Names := nil;
      for Site in AProcessed.DefineSites do
      begin
        if (Site.FileIndex = 0) or (Site.RootPos <> Token.StartPos) or not Used.ContainsKey(UpperCase(Site.Name)) then
          Continue;
        Index := IndexText(Site.Name, Names);
        if Site.Undefine and (Index >= 0) then
          Delete(Names, Index, 1)
        else if not Site.Undefine and (Index < 0) then
          Names := Names + [Site.Name];
      end;
      if Length(Names) = 0 then
        Continue;
      Hint := Default(TInlayHint);
      Hint.Position := Token.EndPos;
      Hint.Text := DefinesPrefix;
      for Name in Names do
        if Hint.Text = DefinesPrefix then
          Hint.Text := Hint.Text + Name
        else
          Hint.Text := Hint.Text + ', ' + Name;
      if Length(Hint.Text) > MaxLabelLength then
        Hint.Text := Copy(Hint.Text, 1, MaxLabelLength - 1) + '…';
      Hint.PaddingLeft := True;
      Hint.Defines := Names;
      Hint.IncludeFile := ExtractFileName(StringReplace(Trim(IncludeName), '''', '', [rfReplaceAll]));
      Result := Result + [Hint];
    end;
  finally
    Used.Free;
  end;
end;

/// <summary>Liegt ANode im Wert einer Konstanten (const-Abschnitt oder Inline-Konstante)?</summary>
function InConstant(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and not (Node.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst]) do
    Node := Node.Parent;
  Result := Node <> nil;
end;

class function TLspInlayHints.ControlChars(ATree: TSyntaxTree; const ATreeText: string;
  const ARange: TTextRange): TArray<TInlayHint>;
var
  Literals: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Hint: TInlayHint;
begin
  Result := nil;
  Literals := TList<TSyntaxNode>.Create;
  try
    CollectNodes(ATree.Root, [TSyntaxKind.Literal], Literals);
    for Node in Literals do
    begin
      // Ein Literal aus genau einem ^X: der Parser schreibt es als #Code (#862).
      if (Node.EndOffset - Node.StartOffset <> 2) or (Node.StartOffset >= Length(ATreeText)) or
        (ATreeText[Node.StartOffset + 1] <> '^') or not Node.Name.StartsWith('#') or
        not InRange(ARange, Node.StartPos) or not InConstant(Node) then
        Continue;
      Hint := Default(TInlayHint);
      Hint.Position := Node.EndPos;
      Hint.Text := Node.Name;
      Hint.PaddingLeft := True;
      Hint.ControlChar := True;
      Hint.CharCode := StrToIntDef(Copy(Node.Name, 2, MaxInt), 0);
      Result := Result + [Hint];
    end;
  finally
    Literals.Free;
  end;
end;

class function TLspInlayHints.MethodMarkers(AResolver: TNameResolver; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const ARange: TTextRange; const AReadText: THoverReadText): TArray<TInlayHint>;
var
  ReadText: TReferenceReadText;
  Position: TTextPosition;
  Hint: TInlayHint;
begin
  Result := nil;
  ReadText :=
    function(const AName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(AReadText) and AReadText(AName, AText);
    end;
  AResolver.PinTree(ATree, AFileName);
  try
    for Position in TLspMethodWithoutSelf.Markers(ATree, ATreeText, ARange,
      TLspMethodWithoutSelf.Lookup(AResolver, ATree, AFileName, ReadText)) do
    begin
      Hint := Default(TInlayHint);
      Hint.Position := Position;
      Hint.Text := TMethodWithoutSelf.MarkerText;
      Hint.PaddingLeft := True;
      Hint.MethodWithoutSelf := True;
      Result := Result + [Hint];
    end;
  finally
    AResolver.UnpinTree;
  end;
end;

function CompareHints(const A, B: TInlayHint): Integer;
begin
  Result := ComparePositions(A.Position, B.Position);
end;

class function TLspInlayHints.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
  const AReadText: THoverReadText): TArray<TInlayHint>;
begin
  Result := Collect(AResolver, AIndex, ATree, ATreeText, AFileName, ARange, ASettings, AReadText,
    Default(TPreprocessorResult));
end;

class function TLspInlayHints.Collect(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const ARange: TTextRange; const ASettings: TInlayHintSettings;
  const AReadText: THoverReadText; const AProcessed: TPreprocessorResult): TArray<TInlayHint>;
var
  List: TList<TInlayHint>;
begin
  List := TList<TInlayHint>.Create(TComparer<TInlayHint>.Construct(CompareHints));
  try
    if ASettings.ParameterNames then
      List.AddRange(ParameterNames(AResolver, AIndex, ATree, ATreeText, AFileName, ARange, AReadText));
    if ASettings.InferredTypes then
      List.AddRange(InferredTypes(AResolver, ATree, AFileName, ARange));
    if ASettings.EndMarkers then
      List.AddRange(EndMarkers(ATree, ARange, ASettings.EndMarkerMinLines));
    if ASettings.IncludeDefines then
      List.AddRange(IncludeDefines(ATree, AProcessed, ARange));
    if ASettings.ControlChars then
      List.AddRange(ControlChars(ATree, ATreeText, ARange));
    if ASettings.MethodWithoutSelf and (AResolver <> nil) then
      List.AddRange(MethodMarkers(AResolver, ATree, ATreeText, AFileName, ARange, AReadText));
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TLspInlayHints.ToJson(const AHints: TArray<TInlayHint>): TJSONArray;
var
  Hint: TInlayHint;
  Entry: TJSONObject;
  Defines: TJSONArray;
  Name: string;
begin
  Result := TJSONArray.Create;
  for Hint in AHints do
  begin
    Entry := TJSONObject.Create;
    Result.AddElement(Entry);
    Entry.AddPair('position', TLspPositions.PositionToJson(Hint.Position));
    Entry.AddPair('label', Hint.Text);
    if Hint.Kind <> 0 then
      Entry.AddPair('kind', TJSONNumber.Create(Hint.Kind));
    if Hint.PaddingLeft then
      Entry.AddPair('paddingLeft', TJSONBool.Create(True));
    if Hint.PaddingRight then
      Entry.AddPair('paddingRight', TJSONBool.Create(True));
    // Blockanfang für den Sprung per Klick (#620).
    if Hint.HasBlockStart then
      Entry.AddPair('data', TJSONObject.Create(TJSONPair.Create('blockStart',
        TLspPositions.PositionToJson(Hint.BlockStart))));
    // Symbole hinter {$I} (#860), für das Plugin getrennt von Endmarken.
    if Length(Hint.Defines) > 0 then
    begin
      Defines := TJSONArray.Create;
      for Name in Hint.Defines do
        Defines.Add(Name);
      Entry.AddPair('data', TJSONObject.Create(TJSONPair.Create('includeDefines',
        TJSONObject.Create.AddPair('file', Hint.IncludeFile).AddPair('names', Defines))));
    end;
    // Code eines Steuerzeichens (#862), für das Plugin getrennt von Endmarken.
    if Hint.ControlChar then
      Entry.AddPair('data', TJSONObject.Create(TJSONPair.Create('controlChar',
        TJSONObject.Create(TJSONPair.Create('code', TJSONNumber.Create(Hint.CharCode))))));
    // Methode ohne Self (#686): Das Plugin beschriftet die Marke in der Sprache der IDE.
    if Hint.MethodWithoutSelf then
      Entry.AddPair('data', TJSONObject.Create(TJSONPair.Create('methodWithoutSelf', TJSONBool.Create(True))));
  end;
end;

function TLspInlayHints.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  RangeValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Settings: TInlayHintSettings;
  MinLines: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('range', RangeValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Felder "textDocument.uri" und "range" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  if Assigned(FSettings) then
    Settings := FSettings(Uri)
  else
    Settings := TInlayHintSettings.Default;
  // Mindestlänge des Plugins (#620).
  if TJSONObject(AParams).TryGetValue<Integer>(MinLinesParam, MinLines) and (MinLines > 0) then
    Settings.EndMarkerMinLines := MinLines;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Result := ToJson(Collect(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadRange(RangeValue), Settings, FReadText, Shared.Processed));
  finally
    Resolver.Free;
  end;
end;

end.
