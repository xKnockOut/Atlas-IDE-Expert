unit Atlas.Common.Lsp.InvertBoolean;

// „Boolean umkehren“ über das Protokoll (#715):
//   - Code-Aktion „Bedeutung umkehren (X → Y)“ auf einer Boolean-Variablen,
//     einem Feld, einer Konstanten, einer Property, einem Parameter oder einer
//     Boolean-Funktion des Projekts, nur mit refactoring.invertBoolean. Sie
//     trägt den Client-Befehl atlas.invertBoolean mit [uri, position,
//     vorgeschlagener Name]; das Plugin fragt den Namen nach.
//   - Befehl atlas.server.invertBoolean [uri, position, neuer Name]:
//     WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) für die
//     Vorschau, dazu Warnungen.
// Welche Stellen dazugehören:
//   - Variable, Feld, Konstante: alle Verweise samt Deklaration. Felder und
//     globale Variablen starten mit False; die umgekehrten bekommen True
//     (Konstruktoren der Klasse bzw. Startwert), sonst eine Warnung.
//   - Funktion: alle Köpfe samt Überschreibungen und Interfaces (wie „Signatur
//     ändern“), ihre Rümpfe liefern das Gegenteil, Aufrufe werden verneint.
//   - Parameter: in allen Köpfen der Routine und ihren Rümpfen; Aufrufer
//     übergeben den verneinten Wert, ein Standardwert wird umgedreht.
//   - Property: Verweise, das gelesene Feld bzw. der Getter, der Setter
//     (umbenannt, sein Wertparameter umgekehrt, Aufrufer übergeben den
//     verneinten Wert) und ein default; ist sie published, mit
//     refactoring.invertBooleanIncludeDfm auch die Formulare der Klasse und
//     ihrer Nachfahren.
// Felder und Getter, die eine Property liest oder schreibt, kehrt nur die
// Property selbst um. Zeichenketten mit dem alten Namen (RTTI, FindComponent)
// und gebundene Ereignisse melden Warnungen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  TInvertBooleanContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für Referenzen, Formulare und Zeichenketten.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>Eigene Gegensatzpaare "A=B".</summary>
    Antonyms: TArray<string>;
    Prefix: string;
    IncludeDfm: Boolean;
  end;

  TLspInvertBoolean = class
  public const
    ClientCommand = 'atlas.invertBoolean';
    ApplyCommand = 'atlas.server.invertBoolean';
    Kind = 'refactor.rewrite';
    AnnotationId = 'invertBoolean';
  public
    /// <summary>Steht an APosition ein umkehrbares Boolean-Symbol des Projekts? ASymbol ist dann aufgelöst.</summary>
    class function Target(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; const AFiles: TArray<string>; out ASymbol: TResolvedSymbol): Boolean; static;
    /// <summary>Die Code-Aktion an APosition oder nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AUri: string; const APosition: TTextPosition; const AContext: TInvertBooleanContext):
      TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "places": n, "files": n}; EJsonRpcError, wenn dort
    /// nichts umkehrbar ist, ANewName ungültig ist oder das Ergebnis nicht parst. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const ANewName: string; const AContext: TInvertBooleanContext): TJSONObject;
      static;
    /// <summary>var, out oder '' für Parameter AIndex (ab 0) laut Kopf ASignature.</summary>
    class function ParameterModifier(const ASignature: string; AIndex: Integer): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.InvertBoolean,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.Rename,
  Atlas.Text.Lines;

const
  BooleanTypes: array[0..4] of string = ('Boolean', 'System.Boolean', 'ByteBool', 'WordBool', 'LongBool');
  FormExtensions: array[0..1] of string = ('.dfm', '.fmx');

type
  TSourceFile = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    OwnsTree: Boolean;
    Lines: TLineTable;
    Targets: TInvertTargets;
    Extra: TArray<TTextEdit>;
    Resolver: TNameResolver;
    destructor Destroy; override;
    function Offset(const APosition: TTextPosition): Integer;
    function TokenAt(const APosition: TTextPosition): Integer;
    function IsVarArgument(ACall: TSyntaxNode; AArgument: Integer): Boolean;
  end;

destructor TSourceFile.Destroy;
begin
  if OwnsTree then
    Tree.Free;
  inherited;
end;

function TSourceFile.Offset(const APosition: TTextPosition): Integer;
begin
  Result := Lines.OffsetAt(APosition);
end;

function TSourceFile.TokenAt(const APosition: TTextPosition): Integer;
var
  Index, At: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := Tree.Tokens;
  At := Offset(APosition);
  for Index := 0 to High(Tokens) do
    if Tokens[Index].Offset = At then
      Exit(Index)
    else if Tokens[Index].Offset > At then
      Break;
  Result := -1;
end;

function TSourceFile.IsVarArgument(ACall: TSyntaxNode; AArgument: Integer): Boolean;
var
  Callee: TSyntaxNode;
  Candidate: TResolvedSymbol;
  Modifier: string;
  Index: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Result := False;
  if (Resolver = nil) or (ACall.ChildCount = 0) then
    Exit;
  Callee := ACall[0];
  // Der Name ist das letzte Token des Aufgerufenen (Obj.Toggle → Toggle).
  Tokens := Tree.Tokens;
  for Index := High(Tokens) downto 0 do
    if (Tokens[Index].Offset < Callee.EndOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
    begin
      for Candidate in Resolver.ResolveAll(Tree, FileName, Tokens[Index].StartPos) do
      begin
        Modifier := TLspInvertBoolean.ParameterModifier(Candidate.Signature, AArgument);
        if (Modifier = 'var') or (Modifier = 'out') then
          Exit(True);
      end;
      Exit;
    end;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function Where(const AFileName: string; const APosition: TTextPosition): string;
begin
  Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), APosition.Line + 1]);
end;

function IsBooleanType(const ATypeName: string): Boolean;
begin
  Result := IndexText(Trim(ATypeName), BooleanTypes) >= 0;
end;

/// <summary>Vorheriges Token ohne Kommentare; -1 am Anfang.</summary>
function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Result);
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
  if Result > High(ATokens) then
    Result := -1;
end;

class function TLspInvertBoolean.ParameterModifier(const ASignature: string; AIndex: Integer): string;
var
  Open, Close, Depth, Index, Count: Integer;
  List, Part, Names, Word: string;
  Parts: TArray<string>;
begin
  Result := '';
  Open := Pos('(', ASignature);
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(ASignature) do
  begin
    if ASignature[Index] = '(' then
      Inc(Depth)
    else if ASignature[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  end;
  if Close = 0 then
    Exit;
  List := Copy(ASignature, Open + 1, Close - Open - 1);
  Parts := List.Split([';']);
  Count := 0;
  for Part in Parts do
  begin
    Names := Trim(Part);
    // Attribute wie [ref] vorn weglassen.
    while StartsStr('[', Names) and (Pos(']', Names) > 0) do
      Names := Trim(Copy(Names, Pos(']', Names) + 1, MaxInt));
    Word := LowerCase(Copy(Names, 1, Pos(' ', Names + ' ') - 1));
    if (Word = 'var') or (Word = 'out') or (Word = 'const') or (Word = 'constref') then
      Names := Trim(Copy(Names, Length(Word) + 1, MaxInt))
    else
      Word := '';
    if Pos(':', Names) > 0 then
      Names := Copy(Names, 1, Pos(':', Names) - 1);
    Inc(Count, Length(Names.Split([','])));
    if AIndex < Count then
    begin
      if (Word = 'var') or (Word = 'out') then
        Result := Word;
      Exit;
    end;
  end;
end;

/// <summary>Ist ASymbol ein Boolean, das sich umkehren lässt?</summary>
function IsInvertible(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := False;
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) or not IsBooleanType(ASymbol.TypeName) then
    Exit;
  if MatchText(ASymbol.Name, ['True', 'False', 'Result', 'Self']) then
    Exit;
  Result := ASymbol.IsParameter or (ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
    TIndexSymbolKind.Constant, TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine]);
end;

function Inside(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Wie TNameResolver.Resolve, dazu Namen in Deklarationen: Mitglieder und globale Symbole aus dem
/// Index der Datei, Parameter aus dem Kopf.</summary>
function ResolveAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  Symbol: TIndexSymbol;
  Found: TSyntaxNode;
  Token: TPascalToken;
  TypeRef: TSyntaxNode;
begin
  Result := AResolver.Resolve(ATree, AFileName, APosition);
  if Result.Kind <> TResolvedKind.None then
    Exit;
  for Symbol in AResolver.ExtractedUnit(ATree, AFileName).Symbols do
    if Inside(APosition, Symbol.SelectionRange) then
    begin
      Result.Kind := TResolvedKind.Symbol;
      Result.Name := Symbol.Name;
      Result.Container := Symbol.Container;
      Result.SymbolKind := Symbol.Kind;
      Result.FileName := AFileName;
      if Symbol.FileName <> '' then
        Result.FileName := Symbol.FileName;
      Result.Range := Symbol.Range;
      Result.SelectionRange := Symbol.SelectionRange;
      Result.TypeName := Symbol.TypeName;
      Result.Visibility := Symbol.Visibility;
      Result.Signature := Symbol.Signature;
      Result.IsVirtual := Symbol.IsVirtual;
      Exit;
    end;
  // Parameter im Kopf einer Routine.
  for Token in ATree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and Inside(APosition, TTextRange.Create(Token.StartPos,
      Token.EndPos)) then
    begin
      Found := nil;
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := (ANode.StartOffset <= Token.Offset) and (Token.Offset < ANode.EndOffset);
          if Result and (ANode.Kind = TSyntaxKind.Parameter) and SameText(ANode.Name, Token.Text) then
            Found := ANode;
        end);
      if Found = nil then
        Exit;
      Result.Kind := TResolvedKind.Local;
      Result.Name := Found.Name;
      Result.FileName := AFileName;
      Result.IsParameter := True;
      Result.SymbolKind := TIndexSymbolKind.Variable;
      Result.SelectionRange := TTextRange.Create(Token.StartPos, Token.EndPos);
      Result.Range := Result.SelectionRange;
      TypeRef := Found.FindChild(TSyntaxKind.TypeReference);
      if TypeRef <> nil then
        Result.TypeName := TypeRef.Name;
      Exit;
    end;
end;

class function TLspInvertBoolean.Target(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const AFiles: TArray<string>; out ASymbol: TResolvedSymbol): Boolean;
begin
  Result := False;
  ASymbol := Default(TResolvedSymbol);
  if (AResolver = nil) or (ATree = nil) then
    Exit;
  ASymbol := ResolveAt(AResolver, ATree, AFileName, APosition);
  if not IsInvertible(ASymbol) then
    Exit;
  // Nur, was im Projekt steht: RTL und VCL (TControl.Visible) bleiben.
  Result := (ASymbol.Kind = TResolvedKind.Local) or SameText(ASymbol.FileName, AFileName) or
    (IndexText(ASymbol.FileName, AFiles) >= 0);
end;

class function TLspInvertBoolean.Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AUri: string; const APosition: TTextPosition; const AContext: TInvertBooleanContext):
  TArray<TJSONObject>;
var
  Symbol: TResolvedSymbol;
  Suggested, Title: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled or not Target(AResolver, ATree, AFileName, APosition, AContext.Files, Symbol) then
    Exit;
  Suggested := TInvertBoolean.Suggest(Symbol.Name, AContext.Antonyms, AContext.Prefix);
  Title := Format('Bedeutung umkehren (%s → %s)', [Symbol.Name, Suggested]);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Arguments.Add(Suggested);
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

function EditsJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Document, Item: TJSONObject;
  Items: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Items := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Item.AddPair('annotationId', TLspInvertBoolean.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

type
  /// <summary>Sammelt die Stellen je Datei.</summary>
  TInvertPlan = class
  private
    FResolver: TNameResolver;
    FContext: TInvertBooleanContext;
    FFileName: string;
    FText: string;
    FTree: TSyntaxTree;
    FSources: TObjectDictionary<string, TSourceFile>;
    FForms: TDictionary<string, TArray<TTextEdit>>;
    FFormTexts: TDictionary<string, string>;
  public
    Order: TList<string>;
    FormOrder: TList<string>;
    Warnings: TArray<string>;
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TInvertBooleanContext);
    destructor Destroy; override;
    function Source(const AFileName: string): TSourceFile;
    function Suggest(const AName: string): string;
    /// <summary>Mitglied AName der Klasse AContainer aus der Datei AFileName.</summary>
    function Member(const AFileName, AContainer, AName: string; out ASymbol: TResolvedSymbol): Boolean;
    /// <summary>Property der Klasse, die AName liest oder schreibt; ''.</summary>
    function AccessingProperty(const AFileName, AContainer, AName: string): string;
    procedure Warn(const AText: string);
    /// <summary>Verweise samt Deklaration; AAccessorCheck: Fail, wenn eine Property es liest oder schreibt.
    /// </summary>
    procedure AddReferences(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
      AInvert, AAccessorCheck: Boolean);
    procedure AddVariable(const ASymbol: TResolvedSymbol; const ANewName: string; AAccessorCheck: Boolean);
    procedure AddFunction(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
      AAccessorCheck: Boolean);
    procedure AddSetter(const AFileName: string; const APosition: TTextPosition; const ANewName: string);
    procedure AddParameter(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure AddProperty(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure AddForms(const AClassName, AOld, ANew: string);
    procedure AddStartValue(const ASymbol: TResolvedSymbol; const ANewName: string);
    procedure CheckStrings(const AOld: string);
    function FormEdits(const AFileName: string): TArray<TTextEdit>;
    function FormText(const AFileName: string): string;
  end;

constructor TInvertPlan.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TInvertBooleanContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FSources := TObjectDictionary<string, TSourceFile>.Create([doOwnsValues]);
  FForms := TDictionary<string, TArray<TTextEdit>>.Create;
  FFormTexts := TDictionary<string, string>.Create;
  Order := TList<string>.Create;
  FormOrder := TList<string>.Create;
end;

destructor TInvertPlan.Destroy;
begin
  FormOrder.Free;
  Order.Free;
  FFormTexts.Free;
  FForms.Free;
  FSources.Free;
  inherited;
end;

function TInvertPlan.Source(const AFileName: string): TSourceFile;
var
  Text: string;
  Created: TSourceFile;
begin
  if FSources.TryGetValue(UpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  if SameText(AFileName, FFileName) then
  begin
    Result := TSourceFile.Create;
    Result.Text := FText;
    Result.Tree := FTree;
  end
  else if Assigned(FContext.ReadText) and FContext.ReadText(AFileName, Text) then
  begin
    Result := TSourceFile.Create;
    Result.Text := Text;
    Result.Tree := TSyntaxTreeCache.Parse(Text);
    Result.OwnsTree := True;
  end;
  if Result = nil then
    Exit;
  Result.FileName := AFileName;
  Result.Lines := TLineTable.Build(Result.Text);
  Result.Resolver := FResolver;
  // Methodenzeiger über eine lokale Variable: Result lässt sich nicht erfassen (E2555).
  Created := Result;
  Result.Targets.VarArgument := Created.IsVarArgument;
  FSources.Add(UpperCase(AFileName), Result);
  Order.Add(AFileName);
end;

function TInvertPlan.Suggest(const AName: string): string;
begin
  Result := TInvertBoolean.Suggest(AName, FContext.Antonyms, FContext.Prefix);
end;

function TInvertPlan.Member(const AFileName, AContainer, AName: string; out ASymbol: TResolvedSymbol): Boolean;
var
  Unit_: TSourceFile;
  Symbol: TIndexSymbol;
begin
  Result := False;
  ASymbol := Default(TResolvedSymbol);
  Unit_ := Source(AFileName);
  if (Unit_ = nil) or (Unit_.Tree = nil) then
    Exit;
  for Symbol in FResolver.ExtractedUnit(Unit_.Tree, AFileName).Symbols do
    if SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) and
      (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Method]) then
    begin
      ASymbol.Kind := TResolvedKind.Symbol;
      ASymbol.Name := Symbol.Name;
      ASymbol.Container := Symbol.Container;
      ASymbol.SymbolKind := Symbol.Kind;
      ASymbol.FileName := AFileName;
      ASymbol.Range := Symbol.Range;
      ASymbol.SelectionRange := Symbol.SelectionRange;
      ASymbol.TypeName := Symbol.TypeName;
      ASymbol.Visibility := Symbol.Visibility;
      ASymbol.Signature := Symbol.Signature;
      Exit(True);
    end;
end;

function TInvertPlan.AccessingProperty(const AFileName, AContainer, AName: string): string;
var
  Unit_: TSourceFile;
  Tokens: TArray<TPascalToken>;
  Found: string;
begin
  Result := '';
  Unit_ := Source(AFileName);
  if (Unit_ = nil) or (Unit_.Tree = nil) or (AContainer = '') then
    Exit;
  Tokens := Unit_.Tree.Tokens;
  Found := '';
  Unit_.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Index: Integer;
      InClause: Boolean;
    begin
      Result := Found = '';
      if not Result or (ANode.Kind <> TSyntaxKind.PropertyDecl) or (ANode.Parent = nil) or
        (ANode.Parent.Parent = nil) or not SameText(ANode.Parent.Parent.Name, AContainer) then
        Exit;
      InClause := False;
      for Index := 0 to High(Tokens) - 1 do
      begin
        if Tokens[Index].Offset >= ANode.EndOffset then
          Break;
        if Tokens[Index].Offset < ANode.StartOffset then
          Continue;
        if MatchText(Tokens[Index].Text, ['read', 'write']) then
          InClause := True
        else if InClause and SameText(Tokens[Index].Text, AName) then
          Found := ANode.Name;
      end;
    end);
  Result := Found;
end;

procedure TInvertPlan.Warn(const AText: string);
begin
  if IndexStr(AText, Warnings) < 0 then
    Warnings := Warnings + [AText];
end;

procedure TInvertPlan.AddReferences(const AFileName: string; const APosition: TTextPosition;
  const ANewName: string; AInvert, AAccessorCheck: Boolean);
var
  Origin, Unit_: TSourceFile;
  Location: TReferenceLocation;
  Token, Previous: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Origin := Source(AFileName);
  if (Origin = nil) or (Origin.Tree = nil) then
    raise Fail(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  for Location in TLspReferences.Find(FResolver, FContext.Index, Origin.Tree, AFileName, APosition, True,
    FContext.Files, FContext.ReadText) do
  begin
    if MatchText(ExtractFileExt(Location.FileName), ['.dfm', '.fmx']) then
      Continue;
    Unit_ := Source(Location.FileName);
    if (Unit_ = nil) or (Unit_.Tree = nil) then
      Continue;
    Token := Unit_.TokenAt(Location.Range.StartPos);
    if Token < 0 then
      Continue;
    Tokens := Unit_.Tree.Tokens;
    if AAccessorCheck then
    begin
      Previous := PreviousToken(Tokens, Token);
      if (Previous >= 0) and MatchText(Tokens[Previous].Text, ['read', 'write']) then
        raise Fail(Format('%s: %s ist Zugriff einer Property. Bitte die Property umkehren.',
          [Where(Location.FileName, Location.Range.StartPos), Tokens[Token].Text]));
    end;
    Unit_.Targets.AddName(Tokens[Token].Offset, ANewName, AInvert);
  end;
end;

procedure TInvertPlan.AddVariable(const ASymbol: TResolvedSymbol; const ANewName: string; AAccessorCheck: Boolean);
var
  Owner: string;
begin
  if AAccessorCheck and (ASymbol.SymbolKind = TIndexSymbolKind.Field) then
  begin
    Owner := AccessingProperty(ASymbol.FileName, ASymbol.Container, ASymbol.Name);
    if Owner <> '' then
      raise Fail(Format('%s ist Zugriff der Property %s. Bitte die Property umkehren.', [ASymbol.Name, Owner]));
  end;
  AddReferences(ASymbol.FileName, ASymbol.SelectionRange.StartPos, ANewName, True, AAccessorCheck);
  AddStartValue(ASymbol, ANewName);
end;

/// <summary>Knoten der Art AKind, dessen Bereich APosition enthält (der innerste).</summary>
function NodeAt(ATree: TSyntaxTree; AKind: TSyntaxKind; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset);
      if Result and (ANode.Kind = AKind) then
        Found := ANode;
    end);
  Result := Found;
end;

procedure TInvertPlan.AddStartValue(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  Unit_: TSourceFile;
  Decl, TypeDecl, Block: TSyntaxNode;
  Constructors: Integer;
  ClassName, Indent: string;
  Tokens: TArray<TPascalToken>;
  Token, Insert: Integer;
  Position: TTextPosition;
begin
  // Felder und globale Variablen beginnen mit False; umgekehrt muss es True sein.
  if ASymbol.Kind = TResolvedKind.Local then
    Exit;
  Unit_ := Source(ASymbol.FileName);
  if (Unit_ = nil) or (Unit_.Tree = nil) then
    Exit;
  Tokens := Unit_.Tree.Tokens;
  Token := Unit_.TokenAt(ASymbol.SelectionRange.StartPos);
  if Token < 0 then
    Exit;
  if ASymbol.SymbolKind = TIndexSymbolKind.Variable then
  begin
    Decl := NodeAt(Unit_.Tree, TSyntaxKind.VarDecl, Tokens[Token].Offset);
    if Decl = nil then
      Exit;
    // Schon mit Startwert: VisitDeclaration verneint ihn.
    if Decl.ChildCount > 1 then
      Exit;
    if (Decl.FindChild(TSyntaxKind.TypeReference) = nil) or (NextToken(Tokens, Token) < 0) or
      not Tokens[NextToken(Tokens, Token)].IsSymbol(':') then
    begin
      Warn(Format('%s: %s beginnt mit False; bitte als %s: Boolean = True deklarieren.',
        [Where(ASymbol.FileName, ASymbol.SelectionRange.StartPos), ASymbol.Name, ANewName]));
      Exit;
    end;
    Position := Unit_.Lines.PositionAt(Decl.FindChild(TSyntaxKind.TypeReference).EndOffset);
    Unit_.Extra := Unit_.Extra + [TTextEdit.Create(TTextRange.Create(Position, Position), ' = True')];
    Exit;
  end;
  if ASymbol.SymbolKind <> TIndexSymbolKind.Field then
    Exit;
  TypeDecl := NodeAt(Unit_.Tree, TSyntaxKind.TypeDecl, Tokens[Token].Offset);
  if (TypeDecl = nil) or (TypeDecl.FindChild(TSyntaxKind.ClassType) = nil) then
  begin
    Warn(Format('%s: %s beginnt mit False; bitte %s := True setzen, wo der Wert entsteht.',
      [Where(ASymbol.FileName, ASymbol.SelectionRange.StartPos), ASymbol.Name, ANewName]));
    Exit;
  end;
  ClassName := TypeDecl.Name;
  if Pos('<', ClassName) > 0 then
    ClassName := Copy(ClassName, 1, Pos('<', ClassName) - 1);
  Constructors := 0;
  Unit_.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Header, Statement: TSyntaxNode;
      Begin_, Index, At: Integer;
      Text: string;
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if Result then
        Exit;
      Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
      Block := ANode.FindChild(TSyntaxKind.Block);
      if (Header = nil) or (Block = nil) or not StartsText(ClassName + '.', ANode.Name) then
        Exit;
      Text := Copy(Unit_.Text, Header.StartOffset + 1, Header.EndOffset - Header.StartOffset);
      if not StartsText('constructor', TrimLeft(Text)) then
        Exit;
      Inc(Constructors);
      // Hinter inherited …, sonst gleich hinter begin.
      Begin_ := -1;
      for Index := 0 to High(Tokens) do
        if (Tokens[Index].Offset >= Block.StartOffset) and Tokens[Index].IsKeyword('begin') then
        begin
          Begin_ := Index;
          Break;
        end;
      if Begin_ < 0 then
        Exit;
      Insert := Tokens[Begin_].Offset + Length(Tokens[Begin_].Text);
      Indent := '  ';
      for Index := 0 to Block.ChildCount - 1 do
      begin
        Statement := Block[Index];
        if Index = 0 then
          Indent := StringOfChar(' ', Unit_.Lines.PositionAt(Statement.StartOffset).Character);
        if StartsText('inherited', Copy(Unit_.Text, Statement.StartOffset + 1, 9)) then
        begin
          Insert := Statement.EndOffset;
          At := NextToken(Tokens, Unit_.TokenAt(Unit_.Lines.PositionAt(Statement.StartOffset)));
          while (At >= 0) and (Tokens[At].Offset < Statement.EndOffset) do
            At := NextToken(Tokens, At);
          if (At >= 0) and Tokens[At].IsSymbol(';') then
            Insert := Tokens[At].Offset + 1;
          Break;
        end;
      end;
      Position := Unit_.Lines.PositionAt(Insert);
      Unit_.Extra := Unit_.Extra + [TTextEdit.Create(TTextRange.Create(Position, Position),
        TTextLines.LineBreakOf(Unit_.Text) + Indent + ANewName + ' := True;')];
    end);
  if Constructors = 0 then
    Warn(Format('%s hat keinen Konstruktor in %s: %s beginnt mit False; bitte im Konstruktor %s := True setzen.',
      [ClassName, ExtractFileName(ASymbol.FileName), ASymbol.Name, ANewName]));
end;

procedure TInvertPlan.AddFunction(const AFileName: string; const APosition: TTextPosition; const ANewName: string;
  AAccessorCheck: Boolean);
var
  Origin, Unit_: TSourceFile;
  Family: TRoutineFamily;
  Header: TRoutineFamilyHeader;
  Call: TRoutineFamilyCall;
  Warning: string;
  Token: Integer;
  Owner: TResolvedSymbol;
begin
  Origin := Source(AFileName);
  Family := TLspChangeSignature.Family(FResolver, FContext.Index, Origin.Tree, AFileName, APosition,
    FContext.Files, FContext.ReadText, nil);
  if AAccessorCheck and (Family.Accessors <> nil) then
    raise Fail(Format('%s ist Zugriffsmethode einer Property (%s). Bitte die Property umkehren.',
      [Family.Name, Family.Accessors[0]]));
  if AAccessorCheck and (Origin <> nil) then
  begin
    Owner := ResolveAt(FResolver, Origin.Tree, AFileName, APosition);
    if (Owner.Container <> '') and (AccessingProperty(Owner.FileName, Owner.Container, Owner.Name) <> '') then
      raise Fail(Format('%s ist Zugriffsmethode der Property %s. Bitte die Property umkehren.',
        [Owner.Name, AccessingProperty(Owner.FileName, Owner.Container, Owner.Name)]));
  end;
  if Family.BoundEvent <> '' then
    raise Fail(Format('%s ist an ein Ereignis gebunden (%s).', [Family.Name, Family.BoundEvent]));
  for Warning in Family.Warnings do
    Warn(Warning);
  for Header in Family.Headers do
  begin
    Unit_ := Source(Header.FileName);
    if Unit_ = nil then
      Continue;
    Token := Unit_.TokenAt(Header.NamePos);
    if Token < 0 then
      Continue;
    Unit_.Targets.AddName(Unit_.Tree.Tokens[Token].Offset, ANewName, True);
    if Header.IsBody then
      Unit_.Targets.AddBody(Unit_.Tree.Tokens[Token].Offset);
  end;
  for Call in Family.Calls do
  begin
    Unit_ := Source(Call.FileName);
    if Unit_ <> nil then
      Unit_.Targets.AddName(Unit_.Offset(Call.NamePos), ANewName, True);
  end;
end;

procedure TInvertPlan.AddSetter(const AFileName: string; const APosition: TTextPosition; const ANewName: string);
var
  Origin, Unit_: TSourceFile;
  Family: TRoutineFamily;
  Header: TRoutineFamilyHeader;
  Call: TRoutineFamilyCall;
  Last: Integer;
  Name: string;
begin
  Origin := Source(AFileName);
  Family := TLspChangeSignature.Family(FResolver, FContext.Index, Origin.Tree, AFileName, APosition,
    FContext.Files, FContext.ReadText, nil);
  Last := -1;
  for Header in Family.Headers do
  begin
    Unit_ := Source(Header.FileName);
    if Unit_ = nil then
      Continue;
    Unit_.Targets.AddName(Unit_.Offset(Header.NamePos), ANewName, False);
    if Header.Parameters = nil then
      Continue;
    Last := High(Header.Parameters);
    // Der Wertparameter steht zuletzt; sein Name bleibt, seine Bedeutung kehrt sich um.
    Name := Header.Parameters[Last].Name;
    if Header.IsBody then
      Unit_.Targets.AddLocal(Unit_.Offset(Header.NamePos), Name, Name);
  end;
  for Call in Family.Calls do
  begin
    Unit_ := Source(Call.FileName);
    if Unit_ = nil then
      Continue;
    Unit_.Targets.AddName(Unit_.Offset(Call.NamePos), ANewName, False);
    if Last >= 0 then
      Unit_.Targets.AddCall(Unit_.Offset(Call.NamePos), Last);
  end;
  for Name in Family.Warnings do
    Warn(Name);
end;

/// <summary>Literal True/False nach "=" ab Token AFrom bis vor ";" bzw. ")"; -1 ohne.</summary>
function DefaultToken(const ATokens: TArray<TPascalToken>; AFrom: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  Index := AFrom;
  while (Index >= 0) and (Index <= High(ATokens)) do
  begin
    if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(')') then
      Exit;
    if ATokens[Index].IsSymbol('=') then
    begin
      Index := NextToken(ATokens, Index);
      if (Index >= 0) and (TInvertBoolean.NegateLiteral(ATokens[Index].Text) <> '') then
        Result := Index;
      Exit;
    end;
    Index := NextToken(ATokens, Index);
  end;
end;

procedure TInvertPlan.AddParameter(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  Origin, Unit_: TSourceFile;
  Header: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Token, NameToken, Index, Parameter, Literal: Integer;
  Family: TRoutineFamily;
  Item: TRoutineFamilyHeader;
  Call: TRoutineFamilyCall;
  Name, NewName, Modifier: string;
begin
  Origin := Source(ASymbol.FileName);
  if (Origin = nil) or (Origin.Tree = nil) then
    raise Fail(Format('%s lässt sich nicht lesen.', [ExtractFileName(ASymbol.FileName)]));
  Tokens := Origin.Tree.Tokens;
  Token := Origin.TokenAt(ASymbol.SelectionRange.StartPos);
  Header := nil;
  if Token >= 0 then
    Header := NodeAt(Origin.Tree, TSyntaxKind.RoutineHeader, Tokens[Token].Offset);
  if Header = nil then
    raise Fail(Format('Zum Parameter %s fehlt die Routine.', [ASymbol.Name]));
  // Name der Routine: letzter Bezeichner vor "(".
  NameToken := -1;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Offset < Header.StartOffset then
      Continue;
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('<') then
      Break;
    if Tokens[Index].Kind = TPascalTokenKind.Identifier then
      NameToken := Index;
  end;
  if NameToken < 0 then
    raise Fail(Format('Zum Parameter %s fehlt die Routine.', [ASymbol.Name]));
  Family := TLspChangeSignature.Family(FResolver, FContext.Index, Origin.Tree, ASymbol.FileName,
    Tokens[NameToken].StartPos, FContext.Files, FContext.ReadText, nil);
  if Family.BoundEvent <> '' then
    raise Fail(Format('%s ist an ein Ereignis gebunden (%s); seine Parameter liegen fest.', [Family.Name,
      Family.BoundEvent]));
  Parameter := -1;
  for Item in Family.Headers do
    if SameText(Item.FileName, ASymbol.FileName) then
      for Index := 0 to High(Item.ParameterPos) do
        if Item.ParameterPos[Index] = ASymbol.SelectionRange.StartPos then
          Parameter := Index;
  if (Parameter < 0) and (Family.Headers <> nil) then
    for Index := 0 to High(Family.Headers[0].Parameters) do
      if SameText(Family.Headers[0].Parameters[Index].Name, ASymbol.Name) then
        Parameter := Index;
  if Parameter < 0 then
    raise Fail(Format('Der Parameter %s steht nicht im Kopf von %s.', [ASymbol.Name, Family.Name]));
  Modifier := LowerCase(Trim(Family.Headers[0].Parameters[Parameter].Modifier));
  if EndsText('var', Modifier) or EndsText('out', Modifier) then
    raise Fail(Format('%s ist ein %s-Parameter: Der Aufrufer bekäme den umgekehrten Wert zurück.',
      [ASymbol.Name, Modifier]));
  for Item in Family.Headers do
  begin
    Unit_ := Source(Item.FileName);
    if (Unit_ = nil) or (Parameter > High(Item.Parameters)) or (Item.ParameterPos[Parameter].Line < 0) then
      Continue;
    Name := Item.Parameters[Parameter].Name;
    NewName := ANewName;
    if not SameText(Name, ASymbol.Name) then
      NewName := Suggest(Name);
    Token := Unit_.TokenAt(Item.ParameterPos[Parameter]);
    if Token < 0 then
      Continue;
    Unit_.Targets.AddName(Unit_.Tree.Tokens[Token].Offset, NewName, True);
    if Item.IsBody then
      Unit_.Targets.AddLocal(Unit_.Offset(Item.NamePos), Name, NewName);
    // Standardwert umdrehen: Aufrufer ohne Argument behalten ihr Verhalten.
    Literal := DefaultToken(Unit_.Tree.Tokens, Token);
    if Literal >= 0 then
      Unit_.Extra := Unit_.Extra + [TTextEdit.Create(TTextRange.Create(Unit_.Tree.Tokens[Literal].StartPos,
        Unit_.Tree.Tokens[Literal].EndPos), TInvertBoolean.NegateLiteral(Unit_.Tree.Tokens[Literal].Text))];
  end;
  for Call in Family.Calls do
  begin
    Unit_ := Source(Call.FileName);
    if Unit_ <> nil then
      Unit_.Targets.AddCall(Unit_.Offset(Call.NamePos), Parameter);
  end;
  for Name in Family.Warnings do
    Warn(Name);
end;

procedure TInvertPlan.AddProperty(const ASymbol: TResolvedSymbol; const ANewName: string);
var
  Unit_: TSourceFile;
  Decl: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Token, Index, Reader, Writer, Default_: Integer;
  Accessor: TResolvedSymbol;
begin
  AddReferences(ASymbol.FileName, ASymbol.SelectionRange.StartPos, ANewName, True, False);
  Unit_ := Source(ASymbol.FileName);
  Tokens := Unit_.Tree.Tokens;
  Token := Unit_.TokenAt(ASymbol.SelectionRange.StartPos);
  Decl := nil;
  if Token >= 0 then
    Decl := NodeAt(Unit_.Tree, TSyntaxKind.PropertyDecl, Tokens[Token].Offset);
  if Decl = nil then
    raise Fail(Format('Die Deklaration von %s fehlt.', [ASymbol.Name]));
  Reader := -1;
  Writer := -1;
  Default_ := -1;
  for Index := Token + 1 to High(Tokens) do
  begin
    if Tokens[Index].Offset >= Decl.EndOffset then
      Break;
    if (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      (NextToken(Tokens, Index) >= 0) then
      if SameText(Tokens[Index].Text, 'read') then
        Reader := NextToken(Tokens, Index)
      else if SameText(Tokens[Index].Text, 'write') then
        Writer := NextToken(Tokens, Index)
      else if SameText(Tokens[Index].Text, 'default') then
        Default_ := NextToken(Tokens, Index);
  end;
  if (Default_ >= 0) and (TInvertBoolean.NegateLiteral(Tokens[Default_].Text) <> '') then
    Unit_.Extra := Unit_.Extra + [TTextEdit.Create(TTextRange.Create(Tokens[Default_].StartPos,
      Tokens[Default_].EndPos), TInvertBoolean.NegateLiteral(Tokens[Default_].Text))];
  // Die Klauseln "read FX" und "write SetX" findet die Referenzsuche nicht; sie werden hier umbenannt.
  if (Reader >= 0) and Member(Unit_.FileName, ASymbol.Container, Tokens[Reader].Text, Accessor) then
  begin
    if Accessor.SymbolKind = TIndexSymbolKind.Field then
      AddVariable(Accessor, Suggest(Accessor.Name), False)
    else
      AddFunction(Accessor.FileName, Accessor.SelectionRange.StartPos, Suggest(Accessor.Name), False);
    Unit_.Targets.AddName(Tokens[Reader].Offset, Suggest(Accessor.Name), True);
  end;
  if (Writer >= 0) and Member(Unit_.FileName, ASymbol.Container, Tokens[Writer].Text, Accessor) then
  begin
    if Accessor.SymbolKind = TIndexSymbolKind.Method then
      AddSetter(Accessor.FileName, Accessor.SelectionRange.StartPos, Suggest(Accessor.Name))
    else if (Reader < 0) or not SameText(Tokens[Writer].Text, Tokens[Reader].Text) then
      AddVariable(Accessor, Suggest(Accessor.Name), False);
    Unit_.Targets.AddName(Tokens[Writer].Offset, Suggest(Accessor.Name), Accessor.SymbolKind <> TIndexSymbolKind.Method);
  end;
  if ASymbol.Visibility = TIndexVisibility.Published then
  begin
    if FContext.IncludeDfm then
      AddForms(ASymbol.Container, ASymbol.Name, ANewName)
    else
      Warn(Format('%s ist published: Formulare speichern noch %s (Formulare einbeziehen ist abgeschaltet).',
        [ASymbol.Name, ASymbol.Name]));
    Warn(Format('%s ist published: Formulare außerhalb des Projekts und gespeicherte Einstellungen behalten den ' +
      'alten Namen.', [ASymbol.Name]));
  end;
end;

procedure TInvertPlan.AddForms(const AClassName, AOld, ANew: string);
var
  Classes, Queue: TArray<string>;
  Current, FileName, Form, Extension, Text: string;
  Location: TSymbolLocation;
  Edits: TArray<TTextEdit>;
  Found: TArray<TInvertWarning>;
  Warning: TInvertWarning;
begin
  // Die Klasse und alle Nachfahren: Formulare speichern Objekte unter ihrem eigenen Typ.
  Classes := [AClassName];
  Queue := [AClassName];
  while Queue <> nil do
  begin
    Current := Queue[0];
    Delete(Queue, 0, 1);
    if FContext.Index = nil then
      Break;
    for Location in FContext.Index.Descendants(Current) do
      if IndexText(Location.Symbol.Name, Classes) < 0 then
      begin
        Classes := Classes + [Location.Symbol.Name];
        Queue := Queue + [Location.Symbol.Name];
      end;
  end;
  for FileName in FContext.Files do
    for Extension in FormExtensions do
    begin
      Form := ChangeFileExt(FileName, Extension);
      if FFormTexts.ContainsKey(UpperCase(Form)) or not Assigned(FContext.ReadText) or
        not FContext.ReadText(Form, Text) or not ContainsText(Text, AOld) then
        Continue;
      if TFileEncoding.IsBinaryFormFile(Form) then
      begin
        Warn(Format('%s ist binär gespeichert und bleibt; bitte in Textform umwandeln.', [ExtractFileName(Form)]));
        Continue;
      end;
      Edits := TInvertBoolean.DfmEdits(Text, Classes, AOld, ANew, Found);
      for Warning in Found do
        Warn(Format('%s, Zeile %d: %s', [ExtractFileName(Form), Warning.Position.Line + 1, Warning.Text]));
      if Edits = nil then
        Continue;
      FFormTexts.Add(UpperCase(Form), Text);
      FForms.Add(UpperCase(Form), Edits);
      FormOrder.Add(Form);
    end;
end;

function TInvertPlan.FormEdits(const AFileName: string): TArray<TTextEdit>;
begin
  Result := FForms[UpperCase(AFileName)];
end;

function TInvertPlan.FormText(const AFileName: string): string;
begin
  Result := FFormTexts[UpperCase(AFileName)];
end;

procedure TInvertPlan.CheckStrings(const AOld: string);
var
  FileName, Text: string;
  Tree: TSyntaxTree;
  Token: TPascalToken;
begin
  // Zeichenketten mit dem alten Namen: RTTI (GetPropValue, FindComponent, MethodAddress) findet ihn nicht mehr.
  for FileName in FContext.Files do
  begin
    if not Assigned(FContext.ReadText) or not FContext.ReadText(FileName, Text) or
      not ContainsText(Text, '''' + AOld + '''') then
      Continue;
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      for Token in Tree.Tokens do
        if (Token.Kind = TPascalTokenKind.StringLiteral) and SameText(Token.Text, '''' + AOld + '''') then
          Warn(Format('%s: Zeichenkette %s (RTTI oder Streaming?) bleibt, bitte prüfen.',
            [Where(FileName, Token.StartPos), Token.Text]));
    finally
      Tree.Free;
    end;
  end;
end;

{ TLspInvertBoolean }

class function TLspInvertBoolean.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const ANewName: string; const AContext: TInvertBooleanContext): TJSONObject;
var
  Symbol: TResolvedSymbol;
  Plan: TInvertPlan;
  Unit_: TSourceFile;
  Name, Text, Warning: string;
  Edits: TArray<TTextEdit>;
  Found: TArray<TInvertWarning>;
  Item: TInvertWarning;
  Tree: TSyntaxTree;
  Changes, WarningList: TJSONArray;
  Edit, Annotation, Annotations: TJSONObject;
  Places, FileCount: Integer;
  Warnings: TArray<string>;
begin
  if not TLspRename.IsValidName(ANewName) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('"%s" ist kein gültiger Bezeichner.',
      [ANewName]));
  if not Target(AResolver, ATree, AFileName, APosition, AContext.Files, Symbol) then
    raise Fail('Hier steht kein Boolean des Projekts.');
  if SameText(ANewName, Symbol.Name) then
    raise Fail('Der neue Name ist der alte.');
  Places := 0;
  FileCount := 0;
  Plan := TInvertPlan.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    if Symbol.IsParameter then
      Plan.AddParameter(Symbol, ANewName)
    else
      case Symbol.SymbolKind of
        TIndexSymbolKind.Property_:
          Plan.AddProperty(Symbol, ANewName);
        TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
          Plan.AddFunction(Symbol.FileName, Symbol.SelectionRange.StartPos, ANewName, True);
      else
        Plan.AddVariable(Symbol, ANewName, True);
      end;
    if Symbol.Kind <> TResolvedKind.Local then
      Plan.CheckStrings(Symbol.Name);
    Changes := TJSONArray.Create;
    try
      for Name in Plan.Order do
      begin
        Unit_ := Plan.Source(Name);
        Edits := Unit_.Extra;
        if not Unit_.Targets.IsEmpty then
        begin
          Edits := Edits + TInvertBoolean.Rewrite(Unit_.Tree, Unit_.Text, Unit_.Targets, Found);
          for Item in Found do
            Plan.Warn(Format('%s: %s', [Where(Name, Item.Position), Item.Text]));
        end;
        if Edits = nil then
          Continue;
        Text := TChangeSignature.ApplyEdits(Unit_.Text, Edits);
        Tree := TSyntaxTreeCache.Parse(Text);
        try
          if Length(Tree.Diagnostics) > Length(Unit_.Tree.Diagnostics) then
            raise Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
              [ExtractFileName(Name), Tree.Diagnostics[0].StartPos.Line + 1, Tree.Diagnostics[0].Message]));
        finally
          Tree.Free;
        end;
        Changes.AddElement(EditsJson(TDocumentUris.FromPath(Name), Edits));
        Inc(Places, Length(Edits));
        Inc(FileCount);
      end;
      for Name in Plan.FormOrder do
      begin
        Edits := Plan.FormEdits(Name);
        Changes.AddElement(EditsJson(TDocumentUris.FromPath(Name), Edits));
        Inc(Places, Length(Edits));
        Inc(FileCount);
      end;
    except
      Changes.Free;
      raise;
    end;
    Warnings := Plan.Warnings;
  finally
    Plan.Free;
  end;
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', 'Boolean umkehren');
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%s → %s: %d Stellen in %d Dateien', [Symbol.Name, ANewName, Places,
    FileCount]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(AnnotationId, Annotation);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Edit.AddPair('changeAnnotations', Annotations);
  WarningList := TJSONArray.Create;
  for Warning in Warnings do
    WarningList.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('warnings', WarningList);
  Result.AddPair('places', TJSONNumber.Create(Places));
  Result.AddPair('files', TJSONNumber.Create(FileCount));
end;

end.
