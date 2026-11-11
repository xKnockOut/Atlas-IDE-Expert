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
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Semantics.OrdinalConstants;

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
  mName: string;
  mHighKnown: Boolean;
  mSize: Integer;
begin
  mName := LowerCase(ATypeName);
  if mName.StartsWith('system.') then
  begin
    mName := Copy(mName, Length('system.') + 1, MaxInt);
  end;
  Result := (mName <> 'char') and (mName <> 'widechar') and (mName <> 'ansichar') and (mName <> 'boolean') and
    (mName <> 'bytebool') and TOrdinalConstants.FixedType(mName, ALow, AHigh, mHighKnown, mSize) and mHighKnown;
end;

function SubrangeOf(const ASignature: string; out ALow, AHigh: Int64): Boolean;
var
  mText: string;
  mEquals, mDots: Integer;
begin
  Result := False;
  mEquals := Pos('=', ASignature);
  if mEquals = 0 then
  begin
    Exit;
  end;
  mText := Trim(Copy(ASignature, mEquals + 1, MaxInt));
  if mText.EndsWith(';') then
  begin
    mText := Trim(Copy(mText, 1, Length(mText) - 1));
  end;
  mDots := Pos('..', mText);
  if mDots = 0 then
  begin
    Exit;
  end;
  Result := TOrdinalConstants.Evaluate(Copy(mText, 1, mDots - 1), nil, ALow) and
    TOrdinalConstants.Evaluate(Copy(mText, mDots + 2, MaxInt), nil, AHigh) and (ALow <= AHigh);
end;

function TypeBodyOf(const ASignature: string): string;
var
  mEquals: Integer;
begin
  Result := '';
  mEquals := Pos('=', ASignature);
  if (mEquals = 0) or ASignature.EndsWith('…') then
  begin
    Exit;
  end;
  Result := Trim(Copy(ASignature, mEquals + 1, MaxInt));
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
  mName: string;
begin
  inherited Create;
  FIndex := AContext.Index;
  FText := AContext.Text;
  FWanted := TDictionary<string, Boolean>.Create;
  for mName in AWanted do
  begin
    FWanted.AddOrSetValue(CanonicalTypeName(mName), True);
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
  mKey: string;
begin
  mKey := CanonicalTypeName(ATypeName);
  if FWanted.ContainsKey(mKey) then
  begin
    Exit(True);
  end;
  if FTypes.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  // Vorläufig False: schützt vor zyklischen Aliasen.
  FTypes.Add(mKey, False);
  Result := False;
  if (FIndex <> nil) and IsValidIdent(ATypeName, True) then
  begin
    Result := FIndex.HasSymbol(ATypeName,
      function(const ASymbol: TIndexSymbol): Boolean
      begin
        Result := (ASymbol.Kind = TIndexSymbolKind.TypeAlias) and Wanted(TypeBodyOf(ASymbol.Signature));
      end);
  end;
  FTypes[mKey] := Result;
end;

function TTypedNames.Mentions(const AText: string): Boolean;
var
  mWord: string;
begin
  for mWord in DeclarationWords(AText) do
  begin
    if Wanted(mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TTypedNames.CollectTypes(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mBody: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.ChildCount > 0) then
      begin
        mBody := Trim(NodeText(mNode[0]));
        if (Pos(' ', mBody) = 0) and Wanted(mBody) then
        begin
          FTypes.AddOrSetValue(CanonicalTypeName(mNode.Name), True);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TTypedNames.CollectLocal(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mName, mHeader: string;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl,
        TSyntaxKind.PropertyDecl, TSyntaxKind.InlineVar]) and (mNode.ChildCount > 0) and
        Mentions(NodeText(mNode[0])) then
      begin
        for mName in mNode.Name.Split([',']) do
        begin
          FLocal.AddOrSetValue(LowerCase(Trim(mName)), True);
        end;
      end;
      // Funktionen mit gesuchtem Ergebnistyp.
      if mNode.Kind = TSyntaxKind.RoutineHeader then
      begin
        mHeader := NodeText(mNode);
        if Mentions(Copy(mHeader, LastDelimiter(')', mHeader) + 1, MaxInt)) then
        begin
          FLocal.AddOrSetValue(LowerCase(Copy(mNode.Name, LastDelimiter('.', mNode.Name) + 1, MaxInt)), True);
        end;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TTypedNames.Suspect(const AName: string): Boolean;
var
  mKey: string;
begin
  mKey := LowerCase(AName);
  if (mKey = '') or FLocal.ContainsKey(mKey) then
  begin
    Exit(mKey <> '');
  end;
  if FSuspects.TryGetValue(mKey, Result) then
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
  FSuspects.Add(mKey, Result);
end;

function OperandName(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  // Iterativ (Bericht M1): an Aufrufen, Indizes und Klammern entlang nach links.
  mNode := ANode;
  while ((mNode.Kind in [TSyntaxKind.Call, TSyntaxKind.IndexAccess]) and (mNode.ChildCount > 0)) or
    ((mNode.Kind = TSyntaxKind.ParenExpr) and (mNode.ChildCount = 1)) do
  begin
    mNode := mNode[0];
  end;
  Result := '';
  if mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := mNode.Name;
  end;
end;

function OperandKind(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out AKind: TIntegerKind; out ATypeName: string): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
  mNode: TSyntaxNode;
begin
  Result := False;
  AKind := Default(TIntegerKind);
  ATypeName := '';
  // Iterativ (Bericht M1): Klammern ablösen statt sich selbst aufzurufen.
  mNode := ANode;
  while (mNode.Kind = TSyntaxKind.ParenExpr) and (mNode.ChildCount = 1) do
  begin
    mNode := mNode[0];
  end;
  if not (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess]) or not AResolver.NodeType(ATree, AFileName, mNode, mSymbol, mTypeInfo, mTypeFound) or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
  begin
    Exit;
  end;
  ATypeName := mSymbol.TypeName;
  AKind := IntegerKindOf(ATypeName);
  // Eigene Aliase (type TGroesse = UInt64) über den aufgelösten Typ.
  if (AKind.Bits = 0) and mTypeFound then
  begin
    AKind := IntegerKindOf(mTypeInfo.Name);
    if AKind.Bits = 0 then
    begin
      AKind := IntegerKindOf(TypeBodyOf(mTypeInfo.Signature));
    end;
  end;
  Result := AKind.Bits > 0;
end;

end.
