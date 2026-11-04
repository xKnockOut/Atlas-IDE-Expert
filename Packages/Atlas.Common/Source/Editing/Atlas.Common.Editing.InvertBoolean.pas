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
  begin
    Exit(True);
  end;
  if not IsUpper(AName[AIndex]) then
  begin
    Exit(False);
  end;
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
  begin
    Result[1] := LowerCase(Copy(Result, 1, 1))[1];
  end;
end;

class function TInvertBoolean.BuiltinAntonyms: TArray<string>;
var
  Pair: string;
begin
  Result := nil;
  for Pair in Antonyms do
  begin
    Result := Result + [Pair];
  end;
end;

class function TInvertBoolean.Suggest(const AName: string): string;
begin
  Result := Suggest(AName, nil, 'Not');
end;

/// <summary>Erste Stelle (ab 1), an der AWord als ganzes Wort in AName steht, vorn auch in anderer
/// Schreibweise; 0 ohne.</summary>
function WordPosition(const AName, AWord: string): Integer;
var
  mAt: Integer;
begin
  Result := 0;
  for mAt := 1 to Length(AName) - Length(AWord) + 1 do
  begin
    if WordStart(AName, mAt) and WordEnd(AName, mAt + Length(AWord) - 1) and
      ((Copy(AName, mAt, Length(AWord)) = AWord) or
      ((mAt = 1) and SameText(Copy(AName, 1, Length(AWord)), AWord))) then
    begin
      Exit(mAt);
    end;
  end;
end;

type
  /// <summary>Längstes Wort eines Gegensatzpaars, das im Namen vorkommt, mit seinem Gegenwort.</summary>
  TAntonymMatch = record
    Word: string;
    Replacement: string;
    At: Integer;
    procedure Consider(const AName, AFrom, ATo: string);
    function Applied(const AName: string): string;
  end;

procedure TAntonymMatch.Consider(const AName, AFrom, ATo: string);
var
  mAt: Integer;
begin
  if (AFrom = '') or (ATo = '') or (Length(AFrom) <= Length(Word)) then
  begin
    Exit;
  end;
  mAt := WordPosition(AName, AFrom);
  if mAt > 0 then
  begin
    Word := AFrom;
    Replacement := ATo;
    At := mAt;
  end;
end;

function TAntonymMatch.Applied(const AName: string): string;
var
  mReplacement: string;
begin
  mReplacement := Replacement;
  if At = 1 then
  begin
    mReplacement := SameCaseFirst(mReplacement, AName);
  end;
  Result := Copy(AName, 1, At - 1) + mReplacement + Copy(AName, At + Length(Word), MaxInt);
end;

/// <summary>Bester Treffer aus den Paaren "A=B", in beiden Richtungen.</summary>
function AntonymMatch(const AName: string; const APairs: TArray<string>): TAntonymMatch;
var
  mPair, mLeft, mRight: string;
  mSplit: Integer;
begin
  Result := Default(TAntonymMatch);
  for mPair in APairs do
  begin
    mSplit := Pos('=', mPair);
    if mSplit >= 2 then
    begin
      mLeft := Trim(Copy(mPair, 1, mSplit - 1));
      mRight := Trim(Copy(mPair, mSplit + 1, MaxInt));
      Result.Consider(AName, mLeft, mRight);
      Result.Consider(AName, mRight, mLeft);
    end;
  end;
end;

/// <summary>AName ohne vorhandenes Präfix (IsNotReady → IsReady); '' ohne.</summary>
function WithoutPrefix(const AName, APrefix: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to Length(AName) - Length(APrefix) do
  begin
    if WordStart(AName, mIndex) and SameText(Copy(AName, mIndex, Length(APrefix)), APrefix) and
      IsUpper(AName[mIndex + Length(APrefix)]) then
    begin
      Result := Copy(AName, 1, mIndex - 1) + Copy(AName, mIndex + Length(APrefix), MaxInt);
      if mIndex = 1 then
      begin
        Result := SameCaseFirst(Result, AName);
      end;
      Exit;
    end;
  end;
end;

/// <summary>APrefix hinter F/A/L bzw. Is/Has/Can/Should/Get/Set einfügen, sonst vorn.</summary>
function WithPrefix(const AName, APrefix: string): string;
var
  mPart: string;
begin
  if (Length(AName) > 1) and CharInSet(AName[1], ['F', 'A', 'L']) and IsUpper(AName[2]) then
  begin
    Exit(AName[1] + APrefix + Copy(AName, 2, MaxInt));
  end;
  for mPart in WordPrefixes do
  begin
    if (Length(AName) > Length(mPart)) and StartsStr(mPart, AName) and IsUpper(AName[Length(mPart) + 1]) then
    begin
      Exit(mPart + APrefix + Copy(AName, Length(mPart) + 1, MaxInt));
    end;
  end;
  Result := SameCaseFirst(APrefix, AName) + UpperCase(AName[1]) + Copy(AName, 2, MaxInt);
end;

class function TInvertBoolean.Suggest(const AName: string; const AAntonyms: TArray<string>;
  const APrefix: string): string;
var
  mMatch: TAntonymMatch;
  mPrefix: string;
begin
  Result := AName;
  if AName = '' then
  begin
    Exit;
  end;
  mMatch := AntonymMatch(AName, AAntonyms + BuiltinAntonyms);
  mPrefix := APrefix;
  if mPrefix = '' then
  begin
    mPrefix := 'Not';
  end;
  if mMatch.Word <> '' then
  begin
    Result := mMatch.Applied(AName);
  end
  else
  begin
    Result := WithoutPrefix(AName, mPrefix);
    if Result = '' then
    begin
      Result := WithPrefix(AName, mPrefix);
    end;
  end;
end;

class function TInvertBoolean.NegateLiteral(const AValue: string): string;
begin
  if SameText(AValue, 'True') then
  begin
    Result := 'False';
  end
  else if SameText(AValue, 'False') then
  begin
    Result := 'True';
  end
  else
  begin
    Result := '';
  end;
end;

{ TRewriter }

type
  TOffsetEdit = record
    StartOffset: Integer;
    EndOffset: Integer;
    Text: string;
  end;

  /// <summary>Quelltext und Tokens der Unit: Ausschnitte, Tokensuche, Text zwischen Knoten.</summary>
  TSourceTokens = record
    Text: string;
    Tokens: TArray<TPascalToken>;
    function Slice(AStart, AEnd: Integer): string;
    function FirstToken(AOffset: Integer): Integer;
    function NodeText(ANode: TSyntaxNode): string;
    /// <summary>Text zwischen ALeft und ARight; mit AFlip ist der Operator dort durch ANewOp ersetzt.</summary>
    function Between(ALeft, ARight: TSyntaxNode; AFlip: Boolean; const ANewOp: string): string;
    /// <summary>Offset des Namens im Kopf der Routine ARoutine; -1 ohne.</summary>
    function HeaderNameOffset(ARoutine: TSyntaxNode): Integer;
    /// <summary>Operand AOperand von "not" ohne die Klammern, wenn sie entbehrlich sind.</summary>
    function WithoutNot(AOperand: TSyntaxNode; ABare: Boolean): string;
    /// <summary>Verneinter Text von ANode ohne umgekehrte Namen darin.</summary>
    function Negation(ANode: TSyntaxNode; ABare: Boolean): string;
    /// <summary>Text von ANode, mit ANegate verneint.</summary>
    function Printed(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
    /// <summary>Token, das genau an AOffset beginnt und ein Bezeichner ist; -1 ohne.</summary>
    function IdentifierAt(AOffset: Integer): Integer;
  end;

  TRewriter = class
  private
    FSource: TSourceTokens;
    FRoot: TSyntaxNode;
    FNames: TDictionary<Integer, TInvertName>;
    FCalls: TDictionary<Integer, TArray<Integer>>;
    FBodies: TDictionary<Integer, Boolean>;
    FLocals: TArray<TInvertLocal>;
    FTokenAtEnd: TDictionary<Integer, Integer>;
    FVarArgument: TInvertVarArgument;
    FEdits: TList<TOffsetEdit>;
    FLines: TLineTable;
    function NameOffset(ANode: TSyntaxNode): Integer;
    function IsValueRef(ANode: TSyntaxNode): Boolean;
    function InvertedName(AOffset: Integer; out AName: TInvertName): Boolean;
    function ContainsDirect(ANode: TSyntaxNode): Boolean;
    function Renamed(AStart, AStop: Integer): string;
    function Rebuild(ANode: TSyntaxNode): string;
    function RebuildGeneric(ANode: TSyntaxNode): string;
    function RebuildCall(ANode: TSyntaxNode): string;
    function Print(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
    /// <summary>@X mit umgekehrtem X: nur umbenennen und warnen.</summary>
    function PrintAddress(ANode: TSyntaxNode; ANegate: Boolean): string;
    /// <summary>not, Klammer, Vergleich und De Morgan; False für andere Knoten.</summary>
    function PrintStructured(ANode: TSyntaxNode; ANegate, ABare: Boolean; out AText: string): Boolean;
    /// <summary>X = True → Y bzw. not Y; X = Z → Y &lt;&gt; Z.</summary>
    function PrintEquality(ANode: TSyntaxNode; const AOp: string; ANegate, ABare: Boolean): string;
    /// <summary>Eine Seite eines Vergleichs; ein umgekehrter Wert zählt AFlips hoch.</summary>
    function PrintSide(ANode: TSyntaxNode; var AFlips: Integer): string;
    /// <summary>De Morgan: not (X and Z) → Y or not Z.</summary>
    function PrintDeMorgan(ANode: TSyntaxNode; const AOp: string; ABare: Boolean): string;
    function LocalRewrite(ANode: TSyntaxNode): string;
    procedure Emit(ANode: TSyntaxNode; const AText: string); overload;
    procedure Emit(AStart, AEnd: Integer; const AText: string); overload;
    procedure Warn(AOffset: Integer; const AText: string);
    procedure CollectLocals(ANode: TSyntaxNode);
    procedure CollectIdentifiers(ANode: TSyntaxNode; const AName, ANewName: string);
    procedure Visit(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitExpression(ANode: TSyntaxNode);
    procedure VisitAssign(ANode: TSyntaxNode);
    procedure VisitCall(ANode: TSyntaxNode; AInBody: Boolean);
    procedure VisitDeclaration(ANode: TSyntaxNode);
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
  FRoot := ATree.Root;
  FSource.Text := AText;
  FSource.Tokens := ATree.Tokens;
  FLines := TLineTable.Build(AText);
  FNames := TDictionary<Integer, TInvertName>.Create;
  FCalls := TDictionary<Integer, TArray<Integer>>.Create;
  FBodies := TDictionary<Integer, Boolean>.Create;
  FTokenAtEnd := TDictionary<Integer, Integer>.Create;
  FEdits := TList<TOffsetEdit>.Create;
  FVarArgument := ATargets.VarArgument;
  FLocals := ATargets.Locals;
  for Index := 0 to High(FSource.Tokens) do
  begin
    if FSource.Tokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      FTokenAtEnd.AddOrSetValue(FSource.Tokens[Index].Offset + Length(FSource.Tokens[Index].Text), Index);
    end;
  end;
  for Item in ATargets.Names do
  begin
    FNames.AddOrSetValue(Item.Offset, Item);
  end;
  for Call in ATargets.Calls do
  begin
    if not FCalls.TryGetValue(Call.CalleeOffset, Arguments) then
    begin
      Arguments := nil;
    end;
    FCalls.AddOrSetValue(Call.CalleeOffset, Arguments + [Call.Argument]);
  end;
  for Offset in ATargets.Bodies do
  begin
    FBodies.AddOrSetValue(Offset, True);
  end;
end;

destructor TRewriter.Destroy;
begin
  FEdits.Free;
  FTokenAtEnd.Free;
  FBodies.Free;
  FCalls.Free;
  FNames.Free;
  inherited;
end;

{ TSourceTokens }

function TSourceTokens.Slice(AStart, AEnd: Integer): string;
begin
  Result := Copy(Text, AStart + 1, AEnd - AStart);
end;

/// <summary>Index des ersten Tokens ab AOffset (binäre Suche); Length(Tokens), wenn keines folgt.</summary>
function TSourceTokens.FirstToken(AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(Tokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if Tokens[mMiddle].Offset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
end;

function TSourceTokens.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Slice(ANode.StartOffset, ANode.EndOffset);
end;

function TSourceTokens.IdentifierAt(AOffset: Integer): Integer;
begin
  Result := FirstToken(AOffset);
  if (Result > High(Tokens)) or (Tokens[Result].Offset <> AOffset) or
    (Tokens[Result].Kind <> TPascalTokenKind.Identifier) then
  begin
    Result := -1;
  end;
end;

function TSourceTokens.HeaderNameOffset(ARoutine: TSyntaxNode): Integer;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := -1;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  // Letzter Bezeichner vor "(", ":" bzw. ";" ohne generische Parameter: der Name.
  for mIndex := FirstToken(mHeader.StartOffset) to High(Tokens) do
  begin
    if (Tokens[mIndex].Offset >= mHeader.EndOffset) or Tokens[mIndex].IsSymbol('(') or
      Tokens[mIndex].IsSymbol(':') or Tokens[mIndex].IsSymbol(';') or Tokens[mIndex].IsSymbol('<') then
    begin
      Break;
    end;
    if Tokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      Result := Tokens[mIndex].Offset;
    end;
  end;
end;

function TSourceTokens.Between(ALeft, ARight: TSyntaxNode; AFlip: Boolean; const ANewOp: string): string;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  Result := Slice(ALeft.EndOffset, ARight.StartOffset);
  if not AFlip then
  begin
    Exit;
  end;
  // Den Operator selbst ersetzen, Leerraum und Kommentare bleiben.
  for mIndex := FirstToken(ALeft.EndOffset) to High(Tokens) do
  begin
    mToken := Tokens[mIndex];
    if mToken.Offset >= ARight.StartOffset then
    begin
      Break;
    end;
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Exit(Slice(ALeft.EndOffset, mToken.Offset) + ANewOp + Slice(mToken.Offset + Length(mToken.Text),
        ARight.StartOffset));
    end;
  end;
end;

{ TRewriter }

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
      begin
        Result := FSource.Tokens[Token].Offset;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TRewriter.InvertedName(AOffset: Integer; out AName: TInvertName): Boolean;
begin
  Result := (AOffset >= 0) and FNames.TryGetValue(AOffset, AName);
end;

function IsCallee(ANode: TSyntaxNode): Boolean;
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
  else
    // Übrige Werte bewusst ohne Wirkung.
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
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.InheritedExpr]) and
        (InvertedName(NameOffset(ACandidate), Name) or FCalls.TryGetValue(NameOffset(ACandidate), Arguments)) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function HasAnonymous(ANode: TSyntaxNode): Boolean;
begin
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ACandidate.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
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
  begin
    Result := TInvertBoolean.NegateLiteral(ANode.Name);
  end;
end;

function ContainsValue(AValue: Integer; const AValues: TArray<Integer>): Boolean;
var
  Item: Integer;
begin
  Result := False;
  for Item in AValues do
  begin
    if Item = AValue then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Quoted := not Quoted;
    end;
    if Quoted then
    begin
      Continue;
    end;
    case AText[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ' ', #9, #10, #13, '+', '-', '*', '/', '=', '<', '>':
        if Depth = 0 then
        begin
          Exit(False);
        end;
    end;
  end;
  Result := AText <> '';
end;

/// <summary>"not X" mit atomarem X.</summary>
function IsSimpleNot(const AText: string): Boolean;
begin
  Result := StartsText('not ', AText) and IsAtomic(Copy(AText, 5, MaxInt));
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
    Result := FSource.NodeText(ANode);
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
  begin
    Result := RebuildCall(ANode);
  end
  else
  begin
    Result := RebuildGeneric(ANode);
  end;
end;

/// <summary>Text zwischen AStart und AStop, nur mit umbenannten Bezeichnern.</summary>
function TRewriter.Renamed(AStart, AStop: Integer): string;
var
  Offset, Token: Integer;
  Name: TInvertName;
begin
  Result := '';
  Offset := AStart;
  for Token := FSource.FirstToken(AStart) to High(FSource.Tokens) do
  begin
    if FSource.Tokens[Token].Offset >= AStop then
    begin
      Break;
    end;
    if FSource.Tokens[Token].Kind <> TPascalTokenKind.Identifier then
    begin
      Continue;
    end;
    if InvertedName(FSource.Tokens[Token].Offset, Name) then
    begin
      Result := Result + FSource.Slice(Offset, FSource.Tokens[Token].Offset) + Name.NewName;
      Offset := FSource.Tokens[Token].Offset + Length(FSource.Tokens[Token].Text);
    end;
  end;
  Result := Result + FSource.Slice(Offset, AStop);
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
  begin
    Exit(LocalRewrite(ANode));
  end;
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
    begin
      Part := '(' + Part + ')';
    end;
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
  begin
    Result := '(' + Result + ')';
  end;
  Arguments := nil;
  if ANode.Kind = TSyntaxKind.Call then
  begin
    if not FCalls.TryGetValue(NameOffset(Callee), Arguments) then
    begin
      Arguments := nil;
    end;
  end;
  for Index := 1 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    Result := Result + FSource.Slice(ANode[Index - 1].EndOffset, Child.StartOffset);
    Negated := ContainsValue(Index - 1, Arguments);
    if IsValueRef(Child) and not Negated and (ANode.Kind = TSyntaxKind.Call) and Assigned(FVarArgument) and
      FVarArgument(ANode, Index - 1) then
    begin
      Warn(Child.StartOffset, 'Übergabe an einen var- oder out-Parameter: nur umbenannt, bitte prüfen');
      Part := Rebuild(Child);
    end
    else
    begin
      Part := Print(Child, Negated, True);
    end;
    Result := Result + Part;
  end;
  Result := Result + FSource.Slice(ANode[ANode.ChildCount - 1].EndOffset, ANode.EndOffset);
end;

/// <summary>AInner in Klammern, außer ABare oder AInner ist atomar bzw. ein einfaches "not".</summary>
function Parenthesized(const AInner: string; ABare: Boolean): string;
begin
  Result := AInner;
  if not (ABare or IsAtomic(AInner) or IsSimpleNot(AInner)) then
  begin
    Result := '(' + AInner + ')';
  end;
end;

/// <summary>Bleibt der Wert bei "X AOp ALiteral" erhalten (= True, &lt;&gt; False)?</summary>
function KeepsValue(const AOp: string; ALiteral: TSyntaxNode): Boolean;
begin
  Result := (AOp = '=') = SameText(ALiteral.Name, 'True');
end;

function FlippedEquality(const AOp: string): string;
begin
  Result := '=';
  if AOp = '=' then
  begin
    Result := '<>';
  end;
end;

function DeMorganOp(const AOp: string): string;
begin
  Result := 'and';
  if AOp = 'and' then
  begin
    Result := 'or';
  end;
end;

/// <summary>"not" vor AText; nicht atomare Ausdrücke in Klammern.</summary>
function Negated(const AText: string; AAtomic: Boolean): string;
begin
  if AAtomic then
  begin
    Result := 'not ' + AText;
  end
  else
  begin
    Result := 'not (' + AText + ')';
  end;
end;

function IsNotExpr(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.UnaryExpr) and SameText(ANode.Name, 'not') and (ANode.ChildCount = 1);
end;

function IsBinary(ANode: TSyntaxNode; const AFirst, ASecond: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) and
    (SameText(ANode.Name, AFirst) or SameText(ANode.Name, ASecond));
end;

function TSourceTokens.WithoutNot(AOperand: TSyntaxNode; ABare: Boolean): string;
begin
  Result := NodeText(AOperand);
  if (AOperand.Kind = TSyntaxKind.ParenExpr) and (AOperand.ChildCount = 1) and
    (ABare or IsAtomic(NodeText(AOperand[0]))) then
  begin
    Result := NodeText(AOperand[0]);
  end;
end;

function TSourceTokens.Negation(ANode: TSyntaxNode; ABare: Boolean): string;
begin
  Result := NegateLiteralText(ANode);
  if Result <> '' then
  begin
    Exit;
  end;
  if IsNotExpr(ANode) then
  begin
    Result := WithoutNot(ANode[0], ABare);
  end
  else if IsBinary(ANode, '=', '<>') then
  begin
    Result := NodeText(ANode[0]) + Between(ANode[0], ANode[1], True, FlippedEquality(LowerCase(ANode.Name))) +
      NodeText(ANode[1]);
  end
  else
  begin
    Result := Negated(NodeText(ANode), IsAtomic(NodeText(ANode)));
  end;
end;

function TSourceTokens.Printed(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
begin
  if ANegate then
  begin
    Result := Negation(ANode, ABare);
  end
  else
  begin
    Result := NodeText(ANode);
  end;
end;

function TRewriter.PrintAddress(ANode: TSyntaxNode; ANegate: Boolean): string;
begin
  // @X: Wer die Adresse bekommt, liest und schreibt den Wert selbst.
  Warn(ANode.StartOffset, 'Adresse übergeben (@): nur umbenannt, bitte prüfen');
  Result := Renamed(ANode.StartOffset, ANode.EndOffset);
  if ANegate then
  begin
    Result := 'not ' + Result;
  end;
end;

function TRewriter.PrintSide(ANode: TSyntaxNode; var AFlips: Integer): string;
begin
  if IsValueRef(ANode) then
  begin
    Result := Rebuild(ANode);
    Inc(AFlips);
  end
  else
  begin
    Result := Print(ANode, False, False);
  end;
end;

function TRewriter.PrintEquality(ANode: TSyntaxNode; const AOp: string; ANegate, ABare: Boolean): string;
var
  mFlips: Integer;
  mLeft, mRight, mNewOp: string;
begin
  // X = True → Y bzw. not Y.
  if IsBoolLiteral(ANode[1]) and ContainsDirect(ANode[0]) then
  begin
    Exit(Print(ANode[0], ANegate = KeepsValue(AOp, ANode[1]), ABare));
  end;
  if IsBoolLiteral(ANode[0]) and ContainsDirect(ANode[1]) then
  begin
    Exit(Print(ANode[1], ANegate = KeepsValue(AOp, ANode[0]), ABare));
  end;
  // X = Z → Y <> Z: jede umgekehrte Seite und die Verneinung drehen den Vergleich.
  mFlips := Ord(ANegate);
  mLeft := PrintSide(ANode[0], mFlips);
  mRight := PrintSide(ANode[1], mFlips);
  mNewOp := AOp;
  if Odd(mFlips) then
  begin
    mNewOp := FlippedEquality(AOp);
  end;
  Result := mLeft + FSource.Between(ANode[0], ANode[1], mNewOp <> AOp, mNewOp) + mRight;
end;

function TRewriter.PrintDeMorgan(ANode: TSyntaxNode; const AOp: string; ABare: Boolean): string;
begin
  Result := Print(ANode[0], True, False) + FSource.Between(ANode[0], ANode[1], True, DeMorganOp(AOp)) +
    Print(ANode[1], True, False);
  if not ABare then
  begin
    Result := '(' + Result + ')';
  end;
end;

function TRewriter.PrintStructured(ANode: TSyntaxNode; ANegate, ABare: Boolean; out AText: string): Boolean;
begin
  Result := True;
  AText := '';
  if IsNotExpr(ANode) then
  begin
    AText := Print(ANode[0], not ANegate, ABare);
  end
  else if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
  begin
    AText := Parenthesized(Print(ANode[0], ANegate, True), ABare);
  end
  else if IsBinary(ANode, '=', '<>') then
  begin
    AText := PrintEquality(ANode, LowerCase(ANode.Name), ANegate, ABare);
  end
  else if ANegate and IsBinary(ANode, 'and', 'or') then
  begin
    AText := PrintDeMorgan(ANode, LowerCase(ANode.Name), ABare);
  end
  else
  begin
    Result := False;
  end;
end;

function TRewriter.Print(ANode: TSyntaxNode; ANegate, ABare: Boolean): string;
begin
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
  begin
    Result := LocalRewrite(ANode);
  end
  else if (ANode.Kind = TSyntaxKind.AddressOf) and ContainsDirect(ANode) then
  begin
    Result := PrintAddress(ANode, ANegate);
  end
  else if IsValueRef(ANode) then
  begin
    Result := Rebuild(ANode);
    if not ANegate then
    begin
      Result := 'not ' + Result;
    end;
  end
  else if not ContainsDirect(ANode) and not HasAnonymous(ANode) then
  begin
    Result := FSource.Printed(ANode, ANegate, ABare);
  end
  else if not PrintStructured(ANode, ANegate, ABare, Result) then
  begin
    Result := Rebuild(ANode);
    if ANegate then
    begin
      Result := Negated(Result, ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess,
        TSyntaxKind.Identifier, TSyntaxKind.InheritedExpr]);
    end;
  end;
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
  if AText <> FSource.NodeText(ANode) then
  begin
    Emit(ANode.StartOffset, ANode.EndOffset, AText);
  end;
end;

procedure TRewriter.Warn(AOffset: Integer; const AText: string);
var
  Warning: TInvertWarning;
begin
  Warning.Position := FLines.PositionAt(AOffset);
  Warning.Text := AText;
  Warnings := Warnings + [Warning];
end;

/// <summary>Result(…) als Aufruf der Funktion selbst, nicht ihr Rückgabewert.</summary>
function IsResultCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode) and
    SameText(ANode.Name, 'Result');
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
      begin
        Exit(False);
      end;
      if (AChild.Kind = TSyntaxKind.Identifier) and SameText(AChild.Name, Name) and not IsResultCall(AChild) then
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
        begin
          Routines.Add(AChild);
        end;
        Result := True;
      end);
    for Routine in Routines do
    begin
      Offset := FSource.HeaderNameOffset(Routine);
      Block := Routine.FindChild(TSyntaxKind.Block);
      if (Block = nil) or (Offset < 0) then
      begin
        Continue;
      end;
      if FBodies.ContainsKey(Offset) then
      begin
        CollectIdentifiers(Block, 'Result', 'Result');
      end;
      for Local in FLocals do
      begin
        if Local.BodyOffset = Offset then
        begin
          CollectIdentifiers(Block, Local.Name, Local.NewName);
        end;
      end;
    end;
  finally
    Routines.Free;
  end;
end;

procedure TRewriter.VisitExpression(ANode: TSyntaxNode);
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
      begin
        Visit(Node, False);
      end
      else if ContainsDirect(Node) then
      begin
        Emit(Node, Print(Node, False, True));
      end
      else
      begin
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TRewriter.VisitAssign(ANode: TSyntaxNode);
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
  VisitExpression(Target);
  VisitExpression(Value);
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
  begin
    Emit(Call, Rebuild(Call));
  end
  else
  begin
    VisitExpression(Call);
  end;
end;

procedure TRewriter.VisitDeclaration(ANode: TSyntaxNode);
var
  Index, Token: Integer;
  Value: TSyntaxNode;
  Name: TInvertName;
begin
  // var X: Boolean = True, const X: Boolean = True, var X := A: Ist X umgekehrt, wird der Startwert verneint.
  Value := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind in ExpressionKinds + [TSyntaxKind.AnonymousMethod] then
    begin
      Value := ANode[Index];
    end;
  end;
  if Value = nil then
  begin
    Exit;
  end;
  Token := FSource.FirstToken(ANode.StartOffset);
  while (Token <= High(FSource.Tokens)) and (FSource.Tokens[Token].Offset < Value.StartOffset) and
    not ((FSource.Tokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(FSource.Tokens[Token].Text, ANode.Name)) do
  begin
    Inc(Token);
  end;
  if (Token <= High(FSource.Tokens)) and (FSource.Tokens[Token].Offset < Value.StartOffset) and
    InvertedName(FSource.Tokens[Token].Offset, Name) and Name.Invert then
  begin
    Emit(Value, Print(Value, True, True));
  end
  else
  begin
    VisitExpression(Value);
  end;
end;

procedure TRewriter.Visit(ANode: TSyntaxNode; AInBody: Boolean);
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  case ANode.Kind of
    TSyntaxKind.RoutineDecl:
      AInBody := FBodies.ContainsKey(FSource.HeaderNameOffset(ANode));
    TSyntaxKind.AnonymousMethod:
      AInBody := False;
    TSyntaxKind.AssignStatement:
      if ANode.ChildCount >= 2 then
      begin
        VisitAssign(ANode);
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
        VisitDeclaration(ANode);
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind in ExpressionKinds then
    begin
      VisitExpression(Child);
    end
    else
    begin
      Visit(Child, AInBody);
    end;
  end;
end;

function TRewriter.Edits: TArray<TTextEdit>;
var
  Item: TInvertName;
  Edit: TOffsetEdit;
  Covered: Boolean;
  Token: Integer;
begin
  CollectLocals(FRoot);
  Visit(FRoot, False);
  // Übrige Stellen (Deklarationen, Property-Klauseln, uses von Methodenzeigern): nur umbenennen.
  for Item in FNames.Values do
  begin
    Covered := False;
    for Edit in FEdits do
    begin
      if (Item.Offset >= Edit.StartOffset) and (Item.Offset < Edit.EndOffset) then
      begin
        Covered := True;
      end;
    end;
    Token := FSource.IdentifierAt(Item.Offset);
    if not Covered and (Token >= 0) and
      (FSource.Tokens[Token].Text <> Item.NewName) then
    begin
      Emit(Item.Offset, Item.Offset + Length(FSource.Tokens[Token].Text), Item.NewName);
    end;
  end;
  Result := nil;
  for Edit in FEdits do
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(FLines.PositionAt(Edit.StartOffset),
      FLines.PositionAt(Edit.EndOffset)), Edit.Text)];
  end;
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
  begin
    Exit;
  end;
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
    begin
      for Item in AObject.Properties do
      begin
        if SameText(Item.Name, AOld) then
        begin
          Value := NegateLiteral(Trim(Item.Value));
          Edits := Edits + [TTextEdit.Create(Item.NameRange, ANew)];
          if Value <> '' then
          begin
            Edits := Edits + [TTextEdit.Create(Item.ValueRange, Value)];
          end
          else
          begin
            Warning.Position := Item.ValueRange.StartPos;
            Warning.Text := Format('%s = %s in %s: Wert nicht umgekehrt, bitte prüfen', [AOld, Item.Value,
              AObject.Name]);
            Warnings := Warnings + [Warning];
          end;
        end;
      end;
    end;
    for Child in AObject.Children do
    begin
      Walk(Child);
    end;
  end;

begin
  Edits := nil;
  Warnings := nil;
  Document := TDfmParser.Parse(AText);
  try
    if Document.Root <> nil then
    begin
      Walk(Document.Root);
    end;
  finally
    Document.Free;
  end;
  AWarnings := Warnings;
  Result := Edits;
end;

end.
