unit Atlas.Common.Editing.InvertBoolean;

// Boolean umkehren (#715): Ein Boolean-Symbol bekommt einen Namen mit der
// Gegenbedeutung, und jede Stelle wird so verneint, dass das Programm gleich
// bleibt.
//   - Namensvorschlag: eingebaute Gegensatzpaare (Hidden ↔ Visible,
//     IsEmpty ↔ HasItems …) und eigene Paare, an Wortgrenzen im Namen
//     (FHidden → FVisible, GetHidden → GetVisible); sonst "Not" entfernen
//     oder als Präfix einfügen (FReady → FNotReady, IsReady → IsNotReady).
//   - Umschreiben: Zuweisungen an das Symbol bekommen den verneinten Wert
//     (X := True → Y := False, X := not A → Y := A), lesende Stellen werden
//     verneint (if X → if not Y, not X → Y, X = False → Y, X = Z → Y <> Z,
//     not (X and Z) → Y or not Z). Doppelte Verneinungen und = True/= False
//     fallen weg, Klammern bleiben nur, wo sie nötig sind.
//   - Funktionen: Im Rumpf werden Result und Exit(…) verneint, Aufrufe wie
//     Lesestellen. Lokale Namen (Parameter eines Setters) lassen sich in einem
//     Rumpf mit umkehren, Argumente von Aufrufen (der Setter, ein umgekehrter
//     Parameter) werden verneint übergeben.
//   - Übergaben an var- und out-Parameter und @X werden nur umbenannt und als
//     Warnung gemeldet.
// Welche Stellen dazugehören (Referenzsuche, Überschreibungen, Zugriffs-
// methoden) bestimmt Atlas.Common.Lsp.InvertBoolean.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Bezeichner an Offset: neuer Name; Invert False = nur umbenennen (Setter, Methodenname einer
  /// Prozedur).</summary>
  TInvertName = record
    Offset: Integer;
    NewName: string;
    Invert: Boolean;
  end;

  /// <summary>Lokaler Name, der im Rumpf der Routine mit dem Namen an BodyOffset umgekehrt wird.</summary>
  TInvertLocal = record
    BodyOffset: Integer;
    Name: string;
    NewName: string;
  end;

  /// <summary>Aufruf, dessen Argument Argument (ab 0) verneint übergeben wird; CalleeOffset ist der Name.</summary>
  TInvertCall = record
    CalleeOffset: Integer;
    Argument: Integer;
  end;

  TInvertWarning = record
    Position: TTextPosition;
    Text: string;
  end;

  /// <summary>Ist Argument AArgument (ab 0) von ACall ein var- oder out-Parameter?</summary>
  TInvertVarArgument = reference to function(ACall: TSyntaxNode; AArgument: Integer): Boolean;

  TInvertTargets = record
    Names: TArray<TInvertName>;
    /// <summary>Offsets der Namen in Rumpfköpfen umgekehrter Funktionen: Result und Exit(…) werden verneint.
    /// </summary>
    Bodies: TArray<Integer>;
    Locals: TArray<TInvertLocal>;
    Calls: TArray<TInvertCall>;
    /// <summary>nil = keine Übergabe gilt als var/out.</summary>
    VarArgument: TInvertVarArgument;
    procedure AddName(AOffset: Integer; const ANewName: string; AInvert: Boolean);
    procedure AddBody(AOffset: Integer);
    procedure AddLocal(ABodyOffset: Integer; const AName, ANewName: string);
    procedure AddCall(ACalleeOffset, AArgument: Integer);
    function IsEmpty: Boolean;
  end;

  TInvertBoolean = class
  public
    /// <summary>Eingebaute Gegensatzpaare als "Hidden=Visible".</summary>
    class function BuiltinAntonyms: TArray<string>; static;
    /// <summary>Name mit der Gegenbedeutung; AAntonyms sind eigene Paare "A=B" (beide Richtungen) vor den
    /// eingebauten, APrefix ersetzt "Not".</summary>
    class function Suggest(const AName: string; const AAntonyms: TArray<string>; const APrefix: string): string;
      overload; static;
    class function Suggest(const AName: string): string; overload; static;
    /// <summary>Alle Änderungen in einer Datei.</summary>
    class function Rewrite(ATree: TSyntaxTree; const AText: string; const ATargets: TInvertTargets;
      out AWarnings: TArray<TInvertWarning>): TArray<TTextEdit>; static;
    /// <summary>True ↔ False; sonst ''.</summary>
    class function NegateLiteral(const AValue: string): string; static;
    /// <summary>In einer Formulardatei: AOld = True/False in Objekten der Klassen AClasses wird zu ANew mit dem
    /// Gegenwert; andere Werte melden AWarnings.</summary>
    class function DfmEdits(const AText: string; const AClasses: TArray<string>; const AOld, ANew: string;
      out AWarnings: TArray<TInvertWarning>): TArray<TTextEdit>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Text.Lines;

const
  Antonyms: array[0..22] of string = ('Hidden=Visible', 'Enabled=Disabled', 'IsEmpty=HasItems', 'Valid=Invalid',
    'Locked=Unlocked', 'Active=Inactive', 'Checked=Unchecked', 'Open=Closed', 'Allowed=Forbidden',
    'Available=Unavailable', 'Connected=Disconnected', 'Modified=Unmodified', 'Selected=Unselected', 'Show=Hide',
    'Succeeded=Failed', 'ReadOnly=Writable', 'Online=Offline', 'Expanded=Collapsed', 'Started=Stopped',
    'Include=Exclude', 'Accepted=Rejected', 'Known=Unknown', 'Empty=NotEmpty');
  WordPrefixes: array[0..5] of string = ('Is', 'Has', 'Can', 'Should', 'Get', 'Set');

{ TInvertTargets }

procedure TInvertTargets.AddName(AOffset: Integer; const ANewName: string; AInvert: Boolean);
var
  Item: TInvertName;
begin
  Item.Offset := AOffset;
  Item.NewName := ANewName;
  Item.Invert := AInvert;
  Names := Names + [Item];
end;

procedure TInvertTargets.AddBody(AOffset: Integer);
begin
  Bodies := Bodies + [AOffset];
end;

procedure TInvertTargets.AddLocal(ABodyOffset: Integer; const AName, ANewName: string);
var
  Item: TInvertLocal;
begin
  Item.BodyOffset := ABodyOffset;
  Item.Name := AName;
  Item.NewName := ANewName;
  Locals := Locals + [Item];
end;

procedure TInvertTargets.AddCall(ACalleeOffset, AArgument: Integer);
var
  Item: TInvertCall;
begin
  Item.CalleeOffset := ACalleeOffset;
  Item.Argument := AArgument;
  Calls := Calls + [Item];
end;

function TInvertTargets.IsEmpty: Boolean;
begin
  Result := (Names = nil) and (Bodies = nil) and (Locals = nil) and (Calls = nil);
end;

{ Namen }

function IsUpper(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z']);
end;

function IsLowerOrDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z', '0'..'9', '_']);
end;

/// <summary>Beginnt bei AIndex (ab 1) ein Wort? FHidden: bei 2; IsEmpty: bei 1 und 3.</summary>
function WordStart(const AName: string; AIndex: Integer): Boolean;
begin
  if AIndex = 1 then
    Exit(True);
  if not IsUpper(AName[AIndex]) then
    Exit(False);
  Result := IsLowerOrDigit(AName[AIndex - 1]) or
    (IsUpper(AName[AIndex - 1]) and (AIndex < Length(AName)) and CharInSet(AName[AIndex + 1], ['a'..'z']));
end;

function WordEnd(const AName: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= Length(AName)) or not CharInSet(AName[AIndex + 1], ['a'..'z']);
end;

/// <summary>Erstes Zeichen von AText in der Schreibweise von ALike.</summary>
function SameCaseFirst(const AText, ALike: string): string;
begin
  Result := AText;
  if (Result <> '') and (ALike <> '') and CharInSet(ALike[1], ['a'..'z']) then
    Result[1] := LowerCase(Copy(Result, 1, 1))[1];
end;

class function TInvertBoolean.BuiltinAntonyms: TArray<string>;
var
  Pair: string;
begin
  Result := nil;
  for Pair in Antonyms do
    Result := Result + [Pair];
end;

class function TInvertBoolean.Suggest(const AName: string): string;
begin
  Result := Suggest(AName, nil, 'Not');
end;

class function TInvertBoolean.Suggest(const AName: string; const AAntonyms: TArray<string>;
  const APrefix: string): string;
var
  Pairs: TArray<string>;
  Pair, From, To_, Best, BestTo, Prefix, Part: string;
  Index, Split, At, BestAt: Integer;
begin
  Result := AName;
  if AName = '' then
    Exit;
  Pairs := AAntonyms + BuiltinAntonyms;
  Best := '';
  BestTo := '';
  BestAt := 0;
  for Pair in Pairs do
  begin
    Split := Pos('=', Pair);
    if Split < 2 then
      Continue;
    for Index := 0 to 1 do
    begin
      From := Trim(Copy(Pair, 1, Split - 1));
      To_ := Trim(Copy(Pair, Split + 1, MaxInt));
      if Index = 1 then
      begin
        Part := From;
        From := To_;
        To_ := Part;
      end;
      if (From = '') or (To_ = '') or (Length(From) <= Length(Best)) then
        Continue;
      for At := 1 to Length(AName) - Length(From) + 1 do
        if WordStart(AName, At) and WordEnd(AName, At + Length(From) - 1) and
          ((Copy(AName, At, Length(From)) = From) or ((At = 1) and
          SameText(Copy(AName, 1, Length(From)), From))) then
        begin
          Best := From;
          BestTo := To_;
          BestAt := At;
          Break;
        end;
    end;
  end;
  if Best <> '' then
  begin
    if BestAt = 1 then
      BestTo := SameCaseFirst(BestTo, AName);
    Exit(Copy(AName, 1, BestAt - 1) + BestTo + Copy(AName, BestAt + Length(Best), MaxInt));
  end;
  // Vorhandenes Präfix entfernen: IsNotReady → IsReady.
  Prefix := APrefix;
  if Prefix = '' then
    Prefix := 'Not';
  for Index := 1 to Length(AName) - Length(Prefix) do
    if WordStart(AName, Index) and SameText(Copy(AName, Index, Length(Prefix)), Prefix) and
      IsUpper(AName[Index + Length(Prefix)]) then
    begin
      Result := Copy(AName, 1, Index - 1) + Copy(AName, Index + Length(Prefix), MaxInt);
      if Index = 1 then
        Result := SameCaseFirst(Result, AName);
      Exit;
    end;
  // Präfix hinter F/A/L bzw. Is/Has/Can/Should/Get/Set einfügen.
  if (Length(AName) > 1) and CharInSet(AName[1], ['F', 'A', 'L']) and IsUpper(AName[2]) then
    Exit(AName[1] + Prefix + Copy(AName, 2, MaxInt));
  for Part in WordPrefixes do
    if (Length(AName) > Length(Part)) and StartsStr(Part, AName) and IsUpper(AName[Length(Part) + 1]) then
      Exit(Part + Prefix + Copy(AName, Length(Part) + 1, MaxInt));
  Result := UpperCase(AName[1]) + Copy(AName, 2, MaxInt);
  Result := SameCaseFirst(Prefix, AName) + Result;
end;

class function TInvertBoolean.NegateLiteral(const AValue: string): string;
begin
  if SameText(AValue, 'True') then
    Result := 'False'
  else if SameText(AValue, 'False') then
    Result := 'True'
  else
    Result := '';
end;

{ TRewriter }

type
  TOffsetEdit = record
    StartOffset: Integer;
    EndOffset: Integer;
    Text: string;
  end;

  TRewriter = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FTokens: TArray<TPascalToken>;
    FNames: TDictionary<Integer, TInvertName>;
    FCalls: TDictionary<Integer, TArray<Integer>>;
    FBodies: TDictionary<Integer, Boolean>;
    FLocals: TArray<TInvertLocal>;
    FTokenAtEnd: TDictionary<Integer, Integer>;
    FTokenAtStart: TDictionary<Integer, Integer>;
    FVarArgument: TInvertVarArgument;
    FEdits: TList<TOffsetEdit>;
    FLines: TLineTable;
    function Slice(AStart, AEnd: Integer): string;
    function FirstToken(AOffset: Integer): Integer;
    function NodeText(ANode: TSyntaxNode): string;
    function NameOffset(ANode: TSyntaxNode): Integer;
    function IsCallee(ANode: TSyntaxNode): Boolean;
    function IsValueRef(ANode: TSyntaxNode): Boolean;
    function InvertedName(AOffset: Integer; out AName: TInvertName): Boolean;
    function ContainsDirect(ANode: TSyntaxNode): Boolean;
    function HasAnonymous(ANode: TSyntaxNode): Boolean;
    function HeaderNameOffset(ARoutine: TSyntaxNode): Integer;
    function Renamed(AStart, AStop: Integer): string;
    function Rebuild(ANode: TSyntaxNode): string;
    function RebuildGeneric(ANode: TSyntaxNode): string;
    function RebuildCall(ANode: TSyntaxNode): string;
    function Print(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
    function NegateText(ANode: TSyntaxNode; ABare: Boolean): string;
    function LocalRewrite(ANode: TSyntaxNode): string;
    function Between(ALeft, ARight: TSyntaxNode; AFlip: Boolean; const ANewOp: string): string;
    procedure Emit(ANode: TSyntaxNode; const AText: string); overload;
    procedure Emit(AStart, AEnd: Integer; const AText: string); overload;
    procedure Warn(AOffset: Integer; const AText: string);
    procedure CollectLocals(ANode: TSyntaxNode);
    procedure CollectIdentifiers(ANode: TSyntaxNode; const AName, ANewName: string);
    procedure Visit(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitExpression(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitAssign(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitCall(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitDeclaration(ANode: TSyntaxNode; AInBody: Boolean);
  public
    Warnings: TArray<TInvertWarning>;
    constructor Create(ATree: TSyntaxTree; const AText: string; const ATargets: TInvertTargets);
    destructor Destroy; override;
    function Edits: TArray<TTextEdit>;
  end;

const
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.InheritedExpr,
    TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr];

constructor TRewriter.Create(ATree: TSyntaxTree; const AText: string; const ATargets: TInvertTargets);
var
  Item: TInvertName;
  Call: TInvertCall;
  Arguments: TArray<Integer>;
  Offset, Index: Integer;
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FTokens := ATree.Tokens;
  FLines := TLineTable.Build(AText);
  FNames := TDictionary<Integer, TInvertName>.Create;
  FCalls := TDictionary<Integer, TArray<Integer>>.Create;
  FBodies := TDictionary<Integer, Boolean>.Create;
  FTokenAtEnd := TDictionary<Integer, Integer>.Create;
  FTokenAtStart := TDictionary<Integer, Integer>.Create;
  FEdits := TList<TOffsetEdit>.Create;
  FVarArgument := ATargets.VarArgument;
  FLocals := ATargets.Locals;
  for Index := 0 to High(FTokens) do
    if FTokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      FTokenAtEnd.AddOrSetValue(FTokens[Index].Offset + Length(FTokens[Index].Text), Index);
      FTokenAtStart.AddOrSetValue(FTokens[Index].Offset, Index);
    end;
  for Item in ATargets.Names do
    FNames.AddOrSetValue(Item.Offset, Item);
  for Call in ATargets.Calls do
  begin
    if not FCalls.TryGetValue(Call.CalleeOffset, Arguments) then
      Arguments := nil;
    FCalls.AddOrSetValue(Call.CalleeOffset, Arguments + [Call.Argument]);
  end;
  for Offset in ATargets.Bodies do
    FBodies.AddOrSetValue(Offset, True);
end;

destructor TRewriter.Destroy;
begin
  FEdits.Free;
  FTokenAtStart.Free;
  FTokenAtEnd.Free;
  FBodies.Free;
  FCalls.Free;
  FNames.Free;
  inherited;
end;

function TRewriter.Slice(AStart, AEnd: Integer): string;
begin
  Result := Copy(FText, AStart + 1, AEnd - AStart);
end;

/// <summary>Index des ersten Tokens ab AOffset (binäre Suche); Length(FTokens), wenn keines folgt.</summary>
function TRewriter.FirstToken(AOffset: Integer): Integer;
var
  Low, High_, Middle: Integer;
begin
  Low := 0;
  High_ := Length(FTokens);
  while Low < High_ do
  begin
    Middle := (Low + High_) div 2;
    if FTokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else
      High_ := Middle;
  end;
  Result := Low;
end;

function TRewriter.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Slice(ANode.StartOffset, ANode.EndOffset);
end;

function TRewriter.NameOffset(ANode: TSyntaxNode): Integer;
var
  Token: Integer;
begin
  Result := -1;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := ANode.StartOffset;
    TSyntaxKind.MemberAccess, TSyntaxKind.InheritedExpr:
      if FTokenAtEnd.TryGetValue(ANode.EndOffset, Token) then
        Result := FTokens[Token].Offset;
  end;
end;

function TRewriter.InvertedName(AOffset: Integer; out AName: TInvertName): Boolean;
begin
  Result := (AOffset >= 0) and FNames.TryGetValue(AOffset, AName);
end;

function TRewriter.IsCallee(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess]) and
    (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode);
end;

function TRewriter.IsValueRef(ANode: TSyntaxNode): Boolean;
var
  Name: TInvertName;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.InheritedExpr:
      Result := not IsCallee(ANode) and InvertedName(NameOffset(ANode), Name) and Name.Invert;
    TSyntaxKind.Call, TSyntaxKind.IndexAccess:
      Result := (ANode.ChildCount > 0) and
        (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.InheritedExpr]) and
        InvertedName(NameOffset(ANode[0]), Name) and Name.Invert;
  end;
end;

function TRewriter.ContainsDirect(ANode: TSyntaxNode): Boolean;
begin
  // Search statt Rekursion (Bericht M1); anonyme Methoden zählen nicht.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Name: TInvertName;
      Arguments: TArray<Integer>;
    begin
      if ACandidate.Kind = TSyntaxKind.AnonymousMethod then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.InheritedExpr]) and
        (InvertedName(NameOffset(ACandidate), Name) or FCalls.TryGetValue(NameOffset(ACandidate), Arguments)) then
        Result := TSyntaxSearchStep.Found;
    end) <> nil;
end;

function TRewriter.HasAnonymous(ANode: TSyntaxNode): Boolean;
begin
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ACandidate.Kind = TSyntaxKind.AnonymousMethod then
        Result := TSyntaxSearchStep.Found;
    end) <> nil;
end;

function TRewriter.HeaderNameOffset(ARoutine: TSyntaxNode): Integer;
var
  Header: TSyntaxNode;
  Index: Integer;
begin
  Result := -1;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  // Letzter Bezeichner vor "(", ":" bzw. ";" ohne generische Parameter: der Name.
  for Index := FirstToken(Header.StartOffset) to High(FTokens) do
  begin
    if FTokens[Index].Offset >= Header.EndOffset then
      Break;
    if FTokens[Index].IsSymbol('(') or FTokens[Index].IsSymbol(':') or FTokens[Index].IsSymbol(';') then
      Break;
    if FTokens[Index].IsSymbol('<') then
      Break;
    if FTokens[Index].Kind = TPascalTokenKind.Identifier then
      Result := FTokens[Index].Offset;
  end;
end;

function IsBoolLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
    (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False'));
end;

/// <summary>True ↔ False für ein Literal; sonst ''.</summary>
function NegateLiteralText(ANode: TSyntaxNode): string;
begin
  Result := '';
  if IsBoolLiteral(ANode) then
    Result := TInvertBoolean.NegateLiteral(ANode.Name);
end;

function ContainsValue(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  Item: Integer;
begin
  Result := False;
  for Item in AValues do
    if Item = AValue then
      Exit(True);
end;

/// <summary>Ein Ausdruck ohne Operator auf oberster Ebene: Name, Aufruf, Index, Klammer.</summary>
function IsAtomic(const AText: string): Boolean;
var
  Index, Depth: Integer;
  Quoted: Boolean;
begin
  Depth := 0;
  Quoted := False;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = '''' then
      Quoted := not Quoted;
    if Quoted then
      Continue;
    case AText[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ' ', #9, #10, #13, '+', '-', '*', '/', '=', '<', '>':
        if Depth = 0 then
          Exit(False);
    end;
  end;
  Result := AText <> '';
end;

/// <summary>"not X" mit atomarem X.</summary>
function IsSimpleNot(const AText: string): Boolean;
begin
  Result := StartsText('not ', AText) and IsAtomic(Copy(AText, 5, MaxInt));
end;

function TRewriter.Between(ALeft, ARight: TSyntaxNode; AFlip: Boolean; const ANewOp: string): string;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Result := Slice(ALeft.EndOffset, ARight.StartOffset);
  if not AFlip then
    Exit;
  // Den Operator selbst ersetzen, Leerraum und Kommentare bleiben.
  for Index := FirstToken(ALeft.EndOffset) to High(FTokens) do
  begin
    Token := FTokens[Index];
    if Token.Offset >= ARight.StartOffset then
      Break;
    if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Slice(ALeft.EndOffset, Token.Offset) + ANewOp +
        Slice(Token.Offset + Length(Token.Text), ARight.StartOffset);
      Exit;
    end;
  end;
end;

function TRewriter.LocalRewrite(ANode: TSyntaxNode): string;
var
  Saved: TList<TOffsetEdit>;
  Edit: TOffsetEdit;
  Index: Integer;
begin
  // Anweisungen in einer anonymen Methode: Änderungen auf ihren Text anwenden.
  Saved := FEdits;
  FEdits := TList<TOffsetEdit>.Create;
  try
    Visit(ANode, False);
    Result := NodeText(ANode);
    for Index := FEdits.Count - 1 downto 0 do
    begin
      Edit := FEdits[Index];
      Result := Copy(Result, 1, Edit.StartOffset - ANode.StartOffset) + Edit.Text +
        Copy(Result, Edit.EndOffset - ANode.StartOffset + 1, MaxInt);
    end;
  finally
    FEdits.Free;
    FEdits := Saved;
  end;
end;

function TRewriter.Rebuild(ANode: TSyntaxNode): string;
begin
  if ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess] then
    Result := RebuildCall(ANode)
  else
    Result := RebuildGeneric(ANode);
end;

/// <summary>Text zwischen AStart und AStop, nur mit umbenannten Bezeichnern.</summary>
function TRewriter.Renamed(AStart, AStop: Integer): string;
var
  Offset, Token: Integer;
  Name: TInvertName;
begin
  Result := '';
  Offset := AStart;
  for Token := FirstToken(AStart) to High(FTokens) do
  begin
    if FTokens[Token].Offset >= AStop then
      Break;
    if FTokens[Token].Kind <> TPascalTokenKind.Identifier then
      Continue;
    if InvertedName(FTokens[Token].Offset, Name) then
    begin
      Result := Result + Slice(Offset, FTokens[Token].Offset) + Name.NewName;
      Offset := FTokens[Token].Offset + Length(FTokens[Token].Text);
    end;
  end;
  Result := Result + Slice(Offset, AStop);
end;

function TRewriter.RebuildGeneric(ANode: TSyntaxNode): string;
var
  Index, Position: Integer;
  Child: TSyntaxNode;
  Part: string;

  function Own(AStop: Integer): string;
  begin
    Result := Renamed(Position, AStop);
  end;

begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit(LocalRewrite(ANode));
  Result := '';
  Position := ANode.StartOffset;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    Result := Result + Own(Child.StartOffset);
    Part := Print(Child, False, ANode.Kind = TSyntaxKind.ParenExpr);
    // Vor "." und "^" braucht ein verneinter Ausdruck Klammern.
    if (Index = 0) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and
      not IsAtomic(Part) then
      Part := '(' + Part + ')';
    Result := Result + Part;
    Position := Child.EndOffset;
  end;
  Result := Result + Own(ANode.EndOffset);
end;

function TRewriter.RebuildCall(ANode: TSyntaxNode): string;
var
  Index: Integer;
  Child, Callee: TSyntaxNode;
  Arguments: TArray<Integer>;
  Part: string;
  Negated: Boolean;
begin
  Callee := ANode[0];
  Result := Rebuild(Callee);
  if not IsAtomic(Result) then
    Result := '(' + Result + ')';
  Arguments := nil;
  if ANode.Kind = TSyntaxKind.Call then
    if not FCalls.TryGetValue(NameOffset(Callee), Arguments) then
      Arguments := nil;
  for Index := 1 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    Result := Result + Slice(ANode[Index - 1].EndOffset, Child.StartOffset);
    Negated := ContainsValue(Index - 1, Arguments);
    if IsValueRef(Child) and not Negated and (ANode.Kind = TSyntaxKind.Call) and Assigned(FVarArgument) and
      FVarArgument(ANode, Index - 1) then
    begin
      Warn(Child.StartOffset, 'Übergabe an einen var- oder out-Parameter: nur umbenannt, bitte prüfen');
      Part := Rebuild(Child);
    end
    else
      Part := Print(Child, Negated, True);
    Result := Result + Part;
  end;
  Result := Result + Slice(ANode[ANode.ChildCount - 1].EndOffset, ANode.EndOffset);
end;

function TRewriter.NegateText(ANode: TSyntaxNode; ABare: Boolean): string;
var
  Op: string;
begin
  Result := NegateLiteralText(ANode);
  if Result <> '' then
    Exit;
  Result := NodeText(ANode);
  case ANode.Kind of
    TSyntaxKind.UnaryExpr:
      if SameText(ANode.Name, 'not') and (ANode.ChildCount = 1) then
      begin
        Result := NodeText(ANode[0]);
        if (ANode[0].Kind = TSyntaxKind.ParenExpr) and (ANode[0].ChildCount = 1) and
          (ABare or IsAtomic(NodeText(ANode[0][0]))) then
          Result := NodeText(ANode[0][0]);
        Exit;
      end;
    TSyntaxKind.BinaryExpr:
      begin
        Op := LowerCase(ANode.Name);
        if ((Op = '=') or (Op = '<>')) and (ANode.ChildCount = 2) then
        begin
          if Op = '=' then
            Op := '<>'
          else
            Op := '=';
          Exit(NodeText(ANode[0]) + Between(ANode[0], ANode[1], True, Op) + NodeText(ANode[1]));
        end;
      end;
  end;
  if IsAtomic(Result) then
    Result := 'not ' + Result
  else
    Result := 'not (' + Result + ')';
end;

function TRewriter.Print(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
var
  Op, NewOp, Inner, Left, Right: string;
  Keep: Boolean;
  Flips: Integer;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit(LocalRewrite(ANode));
  // @X: Wer die Adresse bekommt, liest und schreibt den Wert selbst.
  if (ANode.Kind = TSyntaxKind.AddressOf) and ContainsDirect(ANode) then
  begin
    Warn(ANode.StartOffset, 'Adresse übergeben (@): nur umbenannt, bitte prüfen');
    Result := Renamed(ANode.StartOffset, ANode.EndOffset);
    if ANegate then
      Result := 'not ' + Result;
    Exit;
  end;
  if IsValueRef(ANode) then
  begin
    Result := Rebuild(ANode);
    if not ANegate then
      Result := 'not ' + Result;
    Exit;
  end;
  if not ContainsDirect(ANode) and not HasAnonymous(ANode) then
  begin
    if ANegate then
      Result := NegateText(ANode, ABare)
    else
      Result := NodeText(ANode);
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.UnaryExpr:
      if SameText(ANode.Name, 'not') and (ANode.ChildCount = 1) then
        Exit(Print(ANode[0], not ANegate, ABare));
    TSyntaxKind.ParenExpr:
      if ANode.ChildCount = 1 then
      begin
        Inner := Print(ANode[0], ANegate, True);
        if ABare or IsAtomic(Inner) or IsSimpleNot(Inner) then
          Exit(Inner);
        Exit('(' + Inner + ')');
      end;
    TSyntaxKind.BinaryExpr:
      if ANode.ChildCount = 2 then
      begin
        Op := LowerCase(ANode.Name);
        if (Op = '=') or (Op = '<>') then
        begin
          // X = True → Y bzw. not Y.
          if IsBoolLiteral(ANode[1]) and ContainsDirect(ANode[0]) then
          begin
            Keep := (Op = '=') = SameText(ANode[1].Name, 'True');
            Exit(Print(ANode[0], ANegate = Keep, ABare));
          end;
          if IsBoolLiteral(ANode[0]) and ContainsDirect(ANode[1]) then
          begin
            Keep := (Op = '=') = SameText(ANode[0].Name, 'True');
            Exit(Print(ANode[1], ANegate = Keep, ABare));
          end;
          // X = Z → Y <> Z: jede umgekehrte Seite und die Verneinung drehen den Vergleich.
          Flips := Ord(ANegate);
          if IsValueRef(ANode[0]) then
          begin
            Left := Rebuild(ANode[0]);
            Inc(Flips);
          end
          else
            Left := Print(ANode[0], False, False);
          if IsValueRef(ANode[1]) then
          begin
            Right := Rebuild(ANode[1]);
            Inc(Flips);
          end
          else
            Right := Print(ANode[1], False, False);
          NewOp := Op;
          if Odd(Flips) then
            if Op = '=' then
              NewOp := '<>'
            else
              NewOp := '=';
          Exit(Left + Between(ANode[0], ANode[1], NewOp <> Op, NewOp) + Right);
        end;
        if ANegate and ((Op = 'and') or (Op = 'or')) then
        begin
          // De Morgan: not (X and Z) → Y or not Z.
          if Op = 'and' then
            NewOp := 'or'
          else
            NewOp := 'and';
          Result := Print(ANode[0], True, False) + Between(ANode[0], ANode[1], True, NewOp) +
            Print(ANode[1], True, False);
          if not ABare then
            Result := '(' + Result + ')';
          Exit;
        end;
      end;
  end;
  Result := Rebuild(ANode);
  if ANegate then
    if ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess,
      TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr] then
      Result := 'not ' + Result
    else
      Result := 'not (' + Result + ')';
end;

procedure TRewriter.Emit(AStart, AEnd: Integer; const AText: string);
var
  Edit: TOffsetEdit;
begin
  Edit.StartOffset := AStart;
  Edit.EndOffset := AEnd;
  Edit.Text := AText;
  FEdits.Add(Edit);
end;

procedure TRewriter.Emit(ANode: TSyntaxNode; const AText: string);
begin
  if AText <> NodeText(ANode) then
    Emit(ANode.StartOffset, ANode.EndOffset, AText);
end;

procedure TRewriter.Warn(AOffset: Integer; const AText: string);
var
  Warning: TInvertWarning;
begin
  Warning.Position := FLines.PositionAt(AOffset);
  Warning.Text := AText;
  Warnings := Warnings + [Warning];
end;

procedure TRewriter.CollectIdentifiers(ANode: TSyntaxNode; const AName, ANewName: string);
var
  Name, NewName: string;
begin
  Name := AName;
  NewName := ANewName;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Item: TInvertName;
    begin
      if AChild.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        Exit(False);
      if (AChild.Kind = TSyntaxKind.Identifier) and SameText(AChild.Name, Name) and
        not ((AChild.Parent <> nil) and (AChild.Parent.Kind = TSyntaxKind.Call) and (AChild.Parent[0] = AChild) and
        SameText(Name, 'Result')) then
      begin
        Item.Offset := AChild.StartOffset;
        Item.NewName := NewName;
        Item.Invert := True;
        FNames.AddOrSetValue(Item.Offset, Item);
      end;
      Result := True;
    end);
end;

procedure TRewriter.CollectLocals(ANode: TSyntaxNode);
var
  Routines: TList<TSyntaxNode>;
  Routine, Block: TSyntaxNode;
  Offset: Integer;
  Local: TInvertLocal;
begin
  // Walk statt Rekursion (Bericht M1): erst die Routinen sammeln, dann ihre Rümpfe durchgehen.
  Routines := TList<TSyntaxNode>.Create;
  try
    ANode.Walk(
      function(AChild: TSyntaxNode): Boolean
      begin
        if AChild.Kind = TSyntaxKind.RoutineDecl then
          Routines.Add(AChild);
        Result := True;
      end);
    for Routine in Routines do
    begin
      Offset := HeaderNameOffset(Routine);
      Block := Routine.FindChild(TSyntaxKind.Block);
      if (Block = nil) or (Offset < 0) then
        Continue;
      if FBodies.ContainsKey(Offset) then
        CollectIdentifiers(Block, 'Result', 'Result');
      for Local in FLocals do
        if Local.BodyOffset = Offset then
          CollectIdentifiers(Block, Local.Name, Local.NewName);
    end;
  finally
    Routines.Free;
  end;
end;

procedure TRewriter.VisitExpression(ANode: TSyntaxNode; AInBody: Boolean);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Eigener Stapel statt Rekursion (Bericht M1), in derselben Reihenfolge. Print und Rebuild bleiben rekursiv;
  // sie folgen nur Teilausdrücken mit dem umgekehrten Namen.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node.Kind = TSyntaxKind.AnonymousMethod then
        Visit(Node, False)
      else if ContainsDirect(Node) then
        Emit(Node, Print(Node, False, True))
      else
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

procedure TRewriter.VisitAssign(ANode: TSyntaxNode; AInBody: Boolean);
var
  Target, Value: TSyntaxNode;
begin
  Target := ANode[0];
  Value := ANode[1];
  if IsValueRef(Target) then
  begin
    Emit(Target, Rebuild(Target));
    Emit(Value, Print(Value, True, True));
    Exit;
  end;
  VisitExpression(Target, AInBody);
  VisitExpression(Value, AInBody);
end;

procedure TRewriter.VisitCall(ANode: TSyntaxNode; AInBody: Boolean);
var
  Call: TSyntaxNode;
begin
  Call := ANode[0];
  // Exit(Wert) im Rumpf einer umgekehrten Funktion liefert das Gegenteil.
  if AInBody and (Call.Kind = TSyntaxKind.Call) and (Call.ChildCount = 2) and
    (Call[0].Kind = TSyntaxKind.Identifier) and SameText(Call[0].Name, 'Exit') then
  begin
    Emit(Call[1], Print(Call[1], True, True));
    Exit;
  end;
  if ContainsDirect(Call) then
    Emit(Call, Rebuild(Call))
  else
    VisitExpression(Call, AInBody);
end;

procedure TRewriter.VisitDeclaration(ANode: TSyntaxNode; AInBody: Boolean);
var
  Index, Token: Integer;
  Value: TSyntaxNode;
  Name: TInvertName;
begin
  // var X: Boolean = True, const X: Boolean = True, var X := A: Ist X umgekehrt, wird der Startwert verneint.
  Value := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind in ExpressionKinds + [TSyntaxKind.AnonymousMethod] then
      Value := ANode[Index];
  if Value = nil then
    Exit;
  Token := FirstToken(ANode.StartOffset);
  while (Token <= High(FTokens)) and (FTokens[Token].Offset < Value.StartOffset) and
    not ((FTokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[Token].Text, ANode.Name)) do
    Inc(Token);
  if (Token <= High(FTokens)) and (FTokens[Token].Offset < Value.StartOffset) and
    InvertedName(FTokens[Token].Offset, Name) and Name.Invert then
    Emit(Value, Print(Value, True, True))
  else
    VisitExpression(Value, AInBody);
end;

procedure TRewriter.Visit(ANode: TSyntaxNode; AInBody: Boolean);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  case ANode.Kind of
    TSyntaxKind.RoutineDecl:
      AInBody := FBodies.ContainsKey(HeaderNameOffset(ANode));
    TSyntaxKind.AnonymousMethod:
      AInBody := False;
    TSyntaxKind.AssignStatement:
      if ANode.ChildCount >= 2 then
      begin
        VisitAssign(ANode, AInBody);
        Exit;
      end;
    TSyntaxKind.CallStatement:
      if ANode.ChildCount >= 1 then
      begin
        VisitCall(ANode, AInBody);
        Exit;
      end;
    TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      begin
        VisitDeclaration(ANode, AInBody);
        Exit;
      end;
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in ExpressionKinds then
      VisitExpression(Child, AInBody)
    else
      Visit(Child, AInBody);
  end;
end;

function TRewriter.Edits: TArray<TTextEdit>;
var
  Item: TInvertName;
  Edit: TOffsetEdit;
  Covered: Boolean;
  Token: Integer;
begin
  CollectLocals(FTree.Root);
  Visit(FTree.Root, False);
  // Übrige Stellen (Deklarationen, Property-Klauseln, uses von Methodenzeigern): nur umbenennen.
  for Item in FNames.Values do
  begin
    Covered := False;
    for Edit in FEdits do
      if (Item.Offset >= Edit.StartOffset) and (Item.Offset < Edit.EndOffset) then
        Covered := True;
    if not Covered and FTokenAtStart.TryGetValue(Item.Offset, Token) and
      (FTokens[Token].Text <> Item.NewName) then
      Emit(Item.Offset, Item.Offset + Length(FTokens[Token].Text), Item.NewName);
  end;
  Result := nil;
  for Edit in FEdits do
    Result := Result + [TTextEdit.Create(TTextRange.Create(FLines.PositionAt(Edit.StartOffset),
      FLines.PositionAt(Edit.EndOffset)), Edit.Text)];
end;

{ TInvertBoolean }

class function TInvertBoolean.Rewrite(ATree: TSyntaxTree; const AText: string; const ATargets: TInvertTargets;
  out AWarnings: TArray<TInvertWarning>): TArray<TTextEdit>;
var
  Rewriter: TRewriter;
begin
  AWarnings := nil;
  Result := nil;
  if (ATree = nil) or ATargets.IsEmpty then
    Exit;
  Rewriter := TRewriter.Create(ATree, AText, ATargets);
  try
    Result := Rewriter.Edits;
    AWarnings := Rewriter.Warnings;
  finally
    Rewriter.Free;
  end;
end;

class function TInvertBoolean.DfmEdits(const AText: string; const AClasses: TArray<string>; const AOld,
  ANew: string; out AWarnings: TArray<TInvertWarning>): TArray<TTextEdit>;
var
  Document: TDfmDocument;
  Edits: TArray<TTextEdit>;
  Warnings: TArray<TInvertWarning>;

  procedure Walk(AObject: TDfmObject);
  var
    Item: TDfmProperty;
    Child: TDfmObject;
    Value: string;
    Warning: TInvertWarning;
  begin
    if IndexText(AObject.TypeName, AClasses) >= 0 then
      for Item in AObject.Properties do
        if SameText(Item.Name, AOld) then
        begin
          Value := NegateLiteral(Trim(Item.Value));
          Edits := Edits + [TTextEdit.Create(Item.NameRange, ANew)];
          if Value <> '' then
            Edits := Edits + [TTextEdit.Create(Item.ValueRange, Value)]
          else
          begin
            Warning.Position := Item.ValueRange.StartPos;
            Warning.Text := Format('%s = %s in %s: Wert nicht umgekehrt, bitte prüfen', [AOld, Item.Value,
              AObject.Name]);
            Warnings := Warnings + [Warning];
          end;
        end;
    for Child in AObject.Children do
      Walk(Child);
  end;

begin
  Edits := nil;
  Warnings := nil;
  Document := TDfmParser.Parse(AText);
  try
    if Document.Root <> nil then
      Walk(Document.Root);
  finally
    Document.Free;
  end;
  AWarnings := Warnings;
  Result := Edits;
end;

end.
