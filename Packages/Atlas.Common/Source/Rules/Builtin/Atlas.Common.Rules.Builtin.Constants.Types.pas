unit Atlas.Common.Rules.Builtin.Constants.Types;

// Gemeinsame Bausteine der Regeln für Konstanten und Zahlen (Atlas.Common.Rules.Builtin.Constants und ihre
// Teil-Units): Wertebereiche ganzzahliger Typen, einheitliche Typnamen, Namen bestimmter Typen in einer Datei und
// Art eines Operanden.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Ganzzahliger Typ fester Größe: Bits und Vorzeichen; Bits = 0 bei anderen Typen.</summary>
  TIntegerKind = record
    Bits: Integer;
    Signed: Boolean;
  end;

  /// <summary>Vorfilter vor der Namensauflösung: Namen (Variablen, Felder, Parameter, Properties, Funktionen),
  /// deren Deklaration einen der gesuchten Typen nennt, in der Datei oder im Index. Gesuchte Typen sind
  /// einheitliche Namen (CanonicalTypeName); eigene Aliase der Datei und Aliase aus dem Index zählen mit.</summary>
  TTypedNames = class
  private
    FIndex: ISymbolIndex;
    FText: string;
    FWanted: TDictionary<string, Boolean>;
    // Typname → gesucht (auch über Aliase), zwischengespeichert.
    FTypes: TDictionary<string, Boolean>;
    FLocal: TDictionary<string, Boolean>;
    FSuspects: TDictionary<string, Boolean>;
    function NodeText(ANode: TSyntaxNode): string;
    function Mentions(const AText: string): Boolean;
    procedure CollectTypes(ANode: TSyntaxNode);
    procedure CollectLocal(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AWanted: TArray<string>);
    destructor Destroy; override;
    /// <summary>Ist ATypeName einer der gesuchten Typen oder ein Alias darauf?</summary>
    function Wanted(const ATypeName: string): Boolean;
    /// <summary>Kann der Name AName (letzter Teil eines Operanden) einen gesuchten Typ haben?</summary>
    function Suspect(const AName: string): Boolean;
  end;

/// <summary>Einheitlicher Name eines eingebauten Zahltyps (LongInt → integer, DWORD → cardinal, Real → double);
/// sonst der Name in Kleinbuchstaben ohne "System.".</summary>
function CanonicalTypeName(const ATypeName: string): string;

/// <summary>Wertebereich eines ganzzahligen Typs fester Größe (Byte … Int64); False bei Zeichen, Boolean,
/// Gleitkomma, UInt64 und unbekannten Typen.</summary>
function IntegerRange(const ATypeName: string; out ALow, AHigh: Int64): Boolean;

/// <summary>Bereich eines Teilbereichstyps aus seiner Signatur ("TProzent = 0..100"); nur mit Zahlen.</summary>
function SubrangeOf(const ASignature: string; out ALow, AHigh: Int64): Boolean;

/// <summary>Text hinter "=" einer Typsignatur ("TGroesse = UInt64" → UInt64), ohne Semikolon; '' ohne "=" und
/// bei gekürzten Signaturen.</summary>
function TypeBodyOf(const ASignature: string): string;

/// <summary>Art des ganzzahligen Typs ATypeName (Integer, Cardinal, DWORD …); NativeInt und NativeUInt hängen
/// von der Plattform ab und zählen nicht.</summary>
function IntegerKindOf(const ATypeName: string): TIntegerKind;

/// <summary>Wörter einer Deklaration oder Signatur (Namen, Typen) ohne Satzzeichen.</summary>
function DeclarationWords(const AText: string): TArray<string>;

/// <summary>Letzter Name eines Operanden (Liste.Count → Count, F(X) → F, A[I] → A); '' ohne.</summary>
function OperandName(ANode: TSyntaxNode): string;

/// <summary>Ganzzahliger Typ des Operanden ANode (Variable, Feld, Property, Funktionsergebnis, Element) über die
/// Namensauflösung; False, wenn er nicht sicher bekannt ist. ATypeName ist der Name wie deklariert.</summary>
function OperandKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AKind: TIntegerKind; out ATypeName: string): Boolean;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.NameFacts,
  System.StrUtils,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

const
  // Einheitliche Namen eingebauter Zahltypen (klein geschrieben): Alias, Name.
  cTypeAliases: array[0..11, 0..1] of string = (('longint', 'integer'), ('int32', 'integer'),
    ('longword', 'cardinal'), ('uint32', 'cardinal'), ('dword', 'cardinal'), ('int16', 'smallint'),
    ('int8', 'shortint'), ('uint16', 'word'), ('uint8', 'byte'), ('intptr', 'nativeint'), ('uintptr', 'nativeuint'),
    ('real', 'double'));

function CanonicalTypeName(const ATypeName: string): string;
var
  mIndex: Integer;
begin
  Result := LowerCase(Trim(ATypeName));
  if Result.StartsWith('system.') then
  begin
    Result := Copy(Result, Length('system.') + 1, MaxInt);
  end;
  for mIndex := 0 to High(cTypeAliases) do
  begin
    if Result = cTypeAliases[mIndex, 0] then
    begin
      Result := cTypeAliases[mIndex, 1];
    end;
  end;
end;

function IntegerRange(const ATypeName: string; out ALow, AHigh: Int64): Boolean;
var
  Name: string;
  HighKnown: Boolean;
  Size: Integer;
begin
  Name := LowerCase(ATypeName);
  if Name.StartsWith('system.') then
  begin
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  end;
  Result := (Name <> 'char') and (Name <> 'widechar') and (Name <> 'ansichar') and (Name <> 'boolean') and
    (Name <> 'bytebool') and TOrdinalConstants.FixedType(Name, ALow, AHigh, HighKnown, Size) and HighKnown;
end;

function SubrangeOf(const ASignature: string; out ALow, AHigh: Int64): Boolean;
var
  Text: string;
  Equals, Dots: Integer;
begin
  Result := False;
  Equals := Pos('=', ASignature);
  if Equals = 0 then
  begin
    Exit;
  end;
  Text := Trim(Copy(ASignature, Equals + 1, MaxInt));
  if Text.EndsWith(';') then
  begin
    Text := Trim(Copy(Text, 1, Length(Text) - 1));
  end;
  Dots := Pos('..', Text);
  if Dots = 0 then
  begin
    Exit;
  end;
  Result := TOrdinalConstants.Evaluate(Copy(Text, 1, Dots - 1), nil, ALow) and
    TOrdinalConstants.Evaluate(Copy(Text, Dots + 2, MaxInt), nil, AHigh) and (ALow <= AHigh);
end;

function TypeBodyOf(const ASignature: string): string;
var
  Equals: Integer;
begin
  Result := '';
  Equals := Pos('=', ASignature);
  if (Equals = 0) or ASignature.EndsWith('…') then
  begin
    Exit;
  end;
  Result := Trim(Copy(ASignature, Equals + 1, MaxInt));
  if Result.EndsWith(';') then
  begin
    Result := Trim(Copy(Result, 1, Length(Result) - 1));
  end;
end;

const
  // Ganzzahlige Typen fester Größe (klein geschrieben): Name, Bits, Vorzeichen.
  cIntegerNames: array[0..16] of string = ('shortint', 'int8', 'smallint', 'int16', 'integer', 'longint', 'int32',
    'int64', 'byte', 'uint8', 'word', 'uint16', 'cardinal', 'longword', 'uint32', 'dword', 'uint64');
  cIntegerBits: array[0..16] of Integer = (8, 8, 16, 16, 32, 32, 32, 64, 8, 8, 16, 16, 32, 32, 32, 32, 64);
  // Die ersten acht Namen haben ein Vorzeichen.
  cFirstUnsigned = 8;

function IntegerKindOf(const ATypeName: string): TIntegerKind;
var
  mName: string;
  mIndex: Integer;
begin
  Result := Default(TIntegerKind);
  mName := LowerCase(ATypeName);
  if mName.StartsWith('system.') then
  begin
    mName := Copy(mName, Length('system.') + 1, MaxInt);
  end;
  mIndex := IndexStr(mName, cIntegerNames);
  if mIndex >= 0 then
  begin
    Result.Bits := cIntegerBits[mIndex];
    Result.Signed := mIndex < cFirstUnsigned;
  end;
end;

function DeclarationWords(const AText: string): TArray<string>;
begin
  Result := AText.Split([' ', ':', ';', '(', ')', '[', ']', ',', '=', '<', '>', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty);
end;

constructor TTypedNames.Create(const AContext: TRuleContext; const AWanted: TArray<string>);
var
  Name: string;
begin
  inherited Create;
  FIndex := AContext.Index;
  FText := AContext.Text;
  FWanted := TDictionary<string, Boolean>.Create;
  for Name in AWanted do
  begin
    FWanted.AddOrSetValue(CanonicalTypeName(Name), True);
  end;
  FTypes := TDictionary<string, Boolean>.Create;
  FLocal := TDictionary<string, Boolean>.Create;
  FSuspects := TDictionary<string, Boolean>.Create;
  if (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) then
  begin
    CollectTypes(AContext.Tree.Root);
    CollectLocal(AContext.Tree.Root);
  end;
end;

destructor TTypedNames.Destroy;
begin
  FSuspects.Free;
  FLocal.Free;
  FTypes.Free;
  FWanted.Free;
  inherited;
end;

function TTypedNames.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TTypedNames.Wanted(const ATypeName: string): Boolean;
var
  Key: string;
begin
  Key := CanonicalTypeName(ATypeName);
  if FWanted.ContainsKey(Key) then
  begin
    Exit(True);
  end;
  if FTypes.TryGetValue(Key, Result) then
  begin
    Exit;
  end;
  // Vorläufig False: schützt vor zyklischen Aliasen.
  FTypes.Add(Key, False);
  Result := False;
  if (FIndex <> nil) and IsValidIdent(ATypeName, True) then
  begin
    Result := FIndex.HasSymbol(ATypeName,
      function(const ASymbol: TIndexSymbol): Boolean
      begin
        Result := (ASymbol.Kind = TIndexSymbolKind.TypeAlias) and Wanted(TypeBodyOf(ASymbol.Signature));
      end);
  end;
  FTypes[Key] := Result;
end;

function TTypedNames.Mentions(const AText: string): Boolean;
var
  Word: string;
begin
  for Word in DeclarationWords(AText) do
  begin
    if Wanted(Word) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TTypedNames.CollectTypes(ANode: TSyntaxNode);
var
  Index: Integer;
  Body: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and (Node.ChildCount > 0) then
      begin
        Body := Trim(NodeText(Node[0]));
        if (Pos(' ', Body) = 0) and Wanted(Body) then
        begin
          FTypes.AddOrSetValue(CanonicalTypeName(Node.Name), True);
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TTypedNames.CollectLocal(ANode: TSyntaxNode);
var
  Index: Integer;
  Name, Header: string;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl,
        TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar]) and (Node.ChildCount > 0) and
        Mentions(NodeText(Node[0])) then
      begin
        for Name in Node.Name.Split([',']) do
        begin
          FLocal.AddOrSetValue(LowerCase(Trim(Name)), True);
        end;
      end;
      // Funktionen mit gesuchtem Ergebnistyp.
      if Node.Kind = TSyntaxKind.RoutineHeader then
      begin
        Header := NodeText(Node);
        if Mentions(Copy(Header, LastDelimiter(')', Header) + 1, MaxInt)) then
        begin
          FLocal.AddOrSetValue(LowerCase(Copy(Node.Name, LastDelimiter('.', Node.Name) + 1, MaxInt)), True);
        end;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function TTypedNames.Suspect(const AName: string): Boolean;
var
  Key: string;
begin
  Key := LowerCase(AName);
  if (Key = '') or FLocal.ContainsKey(Key) then
  begin
    Exit(Key <> '');
  end;
  if FSuspects.TryGetValue(Key, Result) then
  begin
    Exit;
  end;
  Result := False;
  if FIndex <> nil then
  begin
    Result := FIndex.HasSymbol(AName,
      function(const ASymbol: TIndexSymbol): Boolean
      begin
        Result := (ASymbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
          TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constant]) and
          (ASymbol.TypeName <> '') and Wanted(ASymbol.TypeName);
      end);
  end;
  FSuspects.Add(Key, Result);
end;

function OperandName(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  // Iterativ (Bericht M1): an Aufrufen, Indizes und Klammern entlang nach links.
  Node := ANode;
  while ((Node.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess]) and (Node.ChildCount > 0)) or
    ((Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1)) do
  begin
    Node := Node[0];
  end;
  Result := '';
  if Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := Node.Name;
  end;
end;

function OperandKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AKind: TIntegerKind; out ATypeName: string): Boolean;
var
  Symbol, TypeInfo: TResolvedSymbol;
  TypeFound: Boolean;
  Node: TSyntaxNode;
begin
  Result := False;
  AKind := Default(TIntegerKind);
  ATypeName := '';
  // Iterativ (Bericht M1): Klammern ablösen statt sich selbst aufzurufen.
  Node := ANode;
  while (Node.Kind = TSyntaxKind.ParenExpr) and (Node.ChildCount = 1) do
  begin
    Node := Node[0];
  end;
  if not (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess]) or not AResolver.NodeType(ATree, AFileName, Node, Symbol, TypeInfo, TypeFound) or
    not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
  begin
    Exit;
  end;
  ATypeName := Symbol.TypeName;
  AKind := IntegerKindOf(ATypeName);
  // Eigene Aliase (type TGroesse = UInt64) über den aufgelösten Typ.
  if (AKind.Bits = 0) and TypeFound then
  begin
    AKind := IntegerKindOf(TypeInfo.Name);
    if AKind.Bits = 0 then
    begin
      AKind := IntegerKindOf(TypeBodyOf(TypeInfo.Signature));
    end;
  end;
  Result := AKind.Bits > 0;
end;

end.
