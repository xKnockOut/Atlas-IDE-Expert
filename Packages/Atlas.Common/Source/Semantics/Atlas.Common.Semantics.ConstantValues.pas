unit Atlas.Common.Semantics.ConstantValues;

// Werte konstanter Ausdrücke im Quelltext einer Unit (#983, #992): Zahlen,
// Zeichen, Konstanten und Aufzählungswerte über die Namensauflösung, auch aus
// anderen Units über deren Signatur im Index. Ausgewertet wird mit
// TOrdinalConstants; Check sagt dazu, ob ein Ausdruck sicher durch null teilt
// oder überläuft. Bei Check gilt eine Konstante aus einem {$IF}-Zweig nur,
// wenn die geprüfte Stelle in demselben Zweig steht (Pascal.ConditionalBranches),
// sonst bleibt der Ausdruck unbekannt. Dazu die Wertebereiche der eingebauten
// ganzzahligen Typen und die Werte einer Aufzählung in ihrer Reihenfolge
// (#1011, #1015). Früher Teil von Rules.Builtin.Statements (duplicate-case-label).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants;

type
  /// <summary>Werte konstanter Ausdrücke einer Unit; ATree, AIndex und AResolver gehören dem Aufrufer und müssen
  /// länger leben.</summary>
  TConstantValues = class
  private
    FTree: TSyntaxTree;
    FTokens: TArray<TPascalToken>;
    FFileName: string;
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    FLookup: TOrdinalNameLookup;
    FDepth: Integer;
    FPaths: TArray<string>;
    FCheckPaths: Boolean;
    FSitePath: string;
    function OwnerUnit(const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
    function TokenAt(const APosition: TTextPosition): Integer;
    function EnumOrdinal(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
    function ForeignValue(const AOwner: TUnitIndex; const ASymbol: TIndexSymbol; out AValue: Int64): Boolean;
  public
    /// <summary>AResolver muss ATree (AFileName) gepinnt haben, solange die Werte gefragt werden.</summary>
    constructor Create(ATree: TSyntaxTree; const AFileName: string; const AIndex: ISymbolIndex;
      AResolver: TNameResolver);
    /// <summary>Wert der Namenskette ANames, deren erstes Token in den Token des Baums an ATokenIndex steht:
    /// Konstante ohne Typ oder Aufzählungswert (Position, nur ohne eigene Werte wie a = 3).</summary>
    function NameValue(const ANames: TArray<string>; ATokenIndex: Integer; out AValue: Int64): Boolean;
    /// <summary>Wert der Konstanten ASymbol (aus der Namensauflösung).</summary>
    function ConstantValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
    /// <summary>Wert der Token AFirst..ALast des Baums; False, wenn nicht sicher auswertbar.</summary>
    function Evaluate(AFirst, ALast: Integer; out AValue: Int64): Boolean;
    /// <summary>Wert des Ausdrucks ANode aus dem Baum; False auch für nil.</summary>
    function EvaluateNode(ANode: TSyntaxNode; out AValue: Int64): Boolean;
    /// <summary>Wie Evaluate mit Grund (#992); Konstanten aus {$IF}-Zweigen nur, wenn die Stelle sie sicher
    /// mit übersetzt.</summary>
    function Check(AFirst, ALast: Integer; out AValue: Int64): TOrdinalStatus; overload;
    /// <summary>Check über die Token des Knotens ANode.</summary>
    function Check(ANode: TSyntaxNode; out AValue: Int64): TOrdinalStatus; overload;
    /// <summary>Erstes und letztes Token des Knotens ANode; False bei leerem Bereich.</summary>
    function TokenRange(ANode: TSyntaxNode; out AFirst, ALast: Integer): Boolean;
    /// <summary>Werte der Aufzählung AEnum (Typ aus der Namensauflösung) in ihrer Reihenfolge; False, wenn die
    /// Aufzählung unbekannt ist, eigene Werte hat (a = 3), Werte unter einer Bedingung stehen (Condition im Index;
    /// die Extraktion aus dem Baum setzt sie nicht) oder ihre Signatur gekürzt ist.</summary>
    function EnumMembers(const AEnum: TResolvedSymbol; out ANames: TArray<string>): Boolean;
    /// <summary>Wertebereich des eingebauten ganzzahligen Typs ATypeName auf jeder Plattform: NativeInt,
    /// LongInt und ihre vorzeichenlosen Gegenstücke mit dem weitesten Bereich (64 Bit), UInt64 bis High(Int64).
    /// False für andere Typen.</summary>
    class function IntegerRange(const ATypeName: string; out ALow, AHigh: Int64): Boolean; static;
    /// <summary>Erstes Token ab AOffset (Index), Length(ATokens) ohne.</summary>
    class function TokenFrom(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.ConditionalBranches;

/// <summary>Erstes Token AText (Symbol) in AFrom..AStop-1 auf Klammerebene 0; -1 ohne.</summary>
function SymbolAtDepthZero(const ATokens: TArray<TPascalToken>; AFrom, AStop: Integer; const AText: string): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFrom to AStop - 1 do
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and ATokens[Index].IsSymbol(AText) then
      Exit(Index);
  Result := -1;
end;

{ TConstantValues }

constructor TConstantValues.Create(ATree: TSyntaxTree; const AFileName: string; const AIndex: ISymbolIndex;
  AResolver: TNameResolver);
begin
  inherited Create;
  FTree := ATree;
  FTokens := ATree.Tokens;
  FFileName := AFileName;
  FIndex := AIndex;
  FResolver := AResolver;
  FPaths := TConditionalBranches.Paths(FTokens);
  // Fängt nur Self, keinen Verweis auf sich selbst.
  FLookup :=
    function(const ANames: TArray<string>; ATokenIndex: Integer; out AValue: Int64): Boolean
    begin
      Result := NameValue(ANames, ATokenIndex, AValue);
    end;
end;

function TConstantValues.Evaluate(AFirst, ALast: Integer; out AValue: Int64): Boolean;
begin
  Result := TOrdinalConstants.Evaluate(FTokens, AFirst, ALast, FLookup, AValue);
end;

function TConstantValues.OwnerUnit(const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName, FFileName) then
  begin
    AUnit := FResolver.ExtractedUnit(FTree, FFileName);
    Exit(True);
  end;
  Result := (FIndex <> nil) and FIndex.FindFile(ASymbol.FileName, AUnit);
end;

function TConstantValues.TokenAt(const APosition: TTextPosition): Integer;
var
  Low, High, Middle: Integer;
begin
  // Erstes Token, das an APosition oder dahinter beginnt.
  Low := 0;
  High := Length(FTokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if (FTokens[Middle].StartPos.Line < APosition.Line) or ((FTokens[Middle].StartPos.Line = APosition.Line) and
      (FTokens[Middle].StartPos.Character < APosition.Character)) then
      Low := Middle + 1
    else
      High := Middle;
  end;
  Result := Low;
end;

function TConstantValues.EnumOrdinal(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  Position: Int64;
  Signature: string;
begin
  // Position in der Aufzählung; mit eigenen Werten (a = 3) nur über den Namen vergleichbar.
  Result := False;
  AValue := 0;
  if (ASymbol.Container = '') or not OwnerUnit(ASymbol, Owner) then
    Exit;
  for Symbol in Owner.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumType) and SameText(Symbol.QualifiedName, ASymbol.Container) then
    begin
      Signature := Symbol.Signature;
      if (Signature = '') or (Pos('=', Copy(Signature, Pos('(', Signature) + 1, MaxInt)) > 0) or
        Signature.EndsWith('…') then
        Exit;
    end;
  Position := 0;
  for Symbol in Owner.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, ASymbol.Container) then
    begin
      if SameText(Symbol.Name, ASymbol.Name) then
      begin
        AValue := Position;
        Exit(True);
      end;
      Inc(Position);
    end;
end;

function TConstantValues.ForeignValue(const AOwner: TUnitIndex; const ASymbol: TIndexSymbol;
  out AValue: Int64): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Lookup: TOrdinalNameLookup;
  Owner: TUnitIndex;
begin
  // "Max = Basis + 1" aus der Signatur; Namen darin gelten in der Unit der Konstanten.
  Result := False;
  AValue := 0;
  if ASymbol.Signature.EndsWith('…') then
    Exit;
  Tokens := TPascalLexer.Tokenize(ASymbol.Signature);
  Index := SymbolAtDepthZero(Tokens, 0, Length(Tokens), '=');
  if Index < 0 then
    Exit;
  Last := High(Tokens);
  if (Last > Index) and Tokens[Last].IsSymbol(';') then
    Dec(Last);
  Owner := AOwner;
  Lookup :=
    function(const AParts: TArray<string>; AAt: Integer; out AResult: Int64): Boolean
    var
      Resolved: TResolvedSymbol;
    begin
      AResult := 0;
      Result := (Length(AParts) = 1) and FResolver.ResolveNameFrom(Owner, AParts[0], Resolved) and
        Resolved.Found;
      if not Result then
        Exit;
      if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
        Result := EnumOrdinal(Resolved, AResult)
      else if Resolved.SymbolKind = TIndexSymbolKind.Constant then
        Result := ConstantValue(Resolved, AResult)
      else
        Result := False;
    end;
  Result := TOrdinalConstants.Evaluate(Tokens, Index + 1, Last, Lookup, AValue);
end;

function TConstantValues.ConstantValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  First, Last, Equals: Integer;
begin
  Result := False;
  AValue := 0;
  // Konstanten, die aufeinander verweisen, enden hier.
  if FDepth >= 8 then
    Exit;
  Inc(FDepth);
  try
    if (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName, FFileName) then
    begin
      // Deklaration im eigenen Baum: Ausdruck hinter "=" bis vor das Semikolon.
      First := TokenAt(ASymbol.Range.StartPos);
      Last := TokenAt(ASymbol.Range.EndPos) - 1;
      if (First > High(FTokens)) or (Last < First) then
        Exit;
      // Steht die Deklaration in einem {$IF}-Zweig, den die geprüfte Stelle nicht sicher mit übersetzt, kann
      // in der anderen Konfiguration ein anderer Wert gelten.
      if FCheckPaths and not TConditionalBranches.Implies(FSitePath, TConditionalBranches.PathAt(FPaths, First)) then
        Exit;
      if FTokens[Last].IsSymbol(';') then
        Dec(Last);
      Equals := SymbolAtDepthZero(FTokens, First, Last + 1, '=');
      if Equals < 0 then
        Exit;
      Result := Evaluate(Equals + 1, Last, AValue);
      Exit;
    end;
    if not OwnerUnit(ASymbol, Owner) then
      Exit;
    for Symbol in Owner.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Constant) and SameText(Symbol.Name, ASymbol.Name) and
        (Symbol.Range.StartPos.Line = ASymbol.Range.StartPos.Line) and
        (Symbol.Range.StartPos.Character = ASymbol.Range.StartPos.Character) then
        Exit(ForeignValue(Owner, Symbol, AValue));
  finally
    Dec(FDepth);
  end;
end;

function TConstantValues.NameValue(const ANames: TArray<string>; ATokenIndex: Integer; out AValue: Int64): Boolean;
var
  Resolved: TResolvedSymbol;
begin
  Result := False;
  AValue := 0;
  if (ATokenIndex < 0) or (ATokenIndex > High(FTokens)) then
    Exit;
  Resolved := FResolver.ResolveChain(FTree, FFileName, ANames, FTokens[ATokenIndex].Offset);
  if not Resolved.Found then
    Exit;
  if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
    Result := EnumOrdinal(Resolved, AValue)
  else if Resolved.SymbolKind = TIndexSymbolKind.Constant then
    Result := ConstantValue(Resolved, AValue);
end;

class function TConstantValues.TokenFrom(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Lower, Upper, Middle: Integer;
begin
  Lower := 0;
  Upper := Length(ATokens);
  while Lower < Upper do
  begin
    Middle := (Lower + Upper) div 2;
    if ATokens[Middle].Offset < AOffset then
      Lower := Middle + 1
    else
      Upper := Middle;
  end;
  Result := Lower;
end;

function TConstantValues.TokenRange(ANode: TSyntaxNode; out AFirst, ALast: Integer): Boolean;
begin
  // Erstes Token ab dem Knotenanfang, letztes vor dem Knotenende.
  AFirst := TokenFrom(FTokens, ANode.StartOffset);
  ALast := TokenFrom(FTokens, ANode.EndOffset) - 1;
  Result := ALast >= AFirst;
end;

function TConstantValues.EvaluateNode(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  First, Last: Integer;
begin
  AValue := 0;
  Result := (ANode <> nil) and TokenRange(ANode, First, Last) and Evaluate(First, Last, AValue);
end;

function TConstantValues.EnumMembers(const AEnum: TResolvedSymbol; out ANames: TArray<string>): Boolean;
var
  Owner: TUnitIndex;
  Symbol: TIndexSymbol;
  Signature, Container: string;
  Known: Boolean;
begin
  ANames := nil;
  Result := False;
  if (AEnum.SymbolKind <> TIndexSymbolKind.EnumType) or not OwnerUnit(AEnum, Owner) then
    Exit;
  Container := AEnum.QualifiedName;
  Known := False;
  for Symbol in Owner.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumType) and SameText(Symbol.QualifiedName, Container) then
    begin
      Signature := Symbol.Signature;
      // Eigene Werte (a = 3) oder gekürzte Signatur: Positionen und Anzahl sind nicht sicher.
      if (Signature = '') or (Pos('=', Copy(Signature, Pos('(', Signature) + 1, MaxInt)) > 0) or
        Signature.EndsWith('…') then
        Exit;
      Known := True;
    end;
  if not Known then
    Exit;
  for Symbol in Owner.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, Container) then
    begin
      // Werte in {$IFDEF}: Anzahl und Positionen hängen von der Konfiguration ab.
      if Symbol.Condition <> '' then
      begin
        ANames := nil;
        Exit;
      end;
      ANames := ANames + [Symbol.Name];
    end;
  Result := Length(ANames) > 0;
end;

class function TConstantValues.IntegerRange(const ATypeName: string; out ALow, AHigh: Int64): Boolean;
begin
  Result := True;
  case IndexText(ATypeName, ['Byte', 'UInt8', 'ShortInt', 'Int8', 'Word', 'UInt16', 'SmallInt', 'Int16',
    'Cardinal', 'UInt32', 'FixedUInt', 'Integer', 'Int32', 'FixedInt', 'Int64', 'UInt64', 'NativeInt', 'LongInt',
    'NativeUInt', 'LongWord']) of
    0, 1:
      begin
        ALow := 0;
        AHigh := 255;
      end;
    2, 3:
      begin
        ALow := -128;
        AHigh := 127;
      end;
    4, 5:
      begin
        ALow := 0;
        AHigh := 65535;
      end;
    6, 7:
      begin
        ALow := -32768;
        AHigh := 32767;
      end;
    8, 9, 10:
      begin
        ALow := 0;
        AHigh := 4294967295;
      end;
    11, 12, 13:
      begin
        ALow := -2147483648;
        AHigh := 2147483647;
      end;
    14, 16, 17:
      begin
        // NativeInt und LongInt: auf 64-Bit-Plattformen (LongInt unter Linux, iOS) wie Int64.
        ALow := Low(Int64);
        AHigh := High(Int64);
      end;
    15, 18, 19:
      begin
        ALow := 0;
        AHigh := High(Int64);
      end;
  else
    ALow := 0;
    AHigh := 0;
    Result := False;
  end;
end;


function TConstantValues.Check(AFirst, ALast: Integer; out AValue: Int64): TOrdinalStatus;
begin
  FCheckPaths := True;
  FSitePath := TConditionalBranches.PathAt(FPaths, AFirst);
  try
    Result := TOrdinalConstants.Check(FTokens, AFirst, ALast, FLookup, AValue);
  finally
    FCheckPaths := False;
  end;
end;

function TConstantValues.Check(ANode: TSyntaxNode; out AValue: Int64): TOrdinalStatus;
var
  First, Last: Integer;
begin
  AValue := 0;
  if not TokenRange(ANode, First, Last) then
    Exit(TOrdinalStatus.Unknown);
  Result := Check(First, Last, AValue);
end;

end.
