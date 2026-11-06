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
    /// <summary>Wert einer Konstanten, deren Deklaration im eigenen Baum steht.</summary>
    function OwnValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
    /// <summary>Wert einer Konstanten aus einer anderen Unit über deren Index.</summary>
    function IndexedValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
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
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and ATokens[Index].IsSymbol(AText) then
    begin
      Exit(Index);
    end;
  end;
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

/// <summary>Aufzählung ohne eigene Werte (a = 3) und mit ungekürzter Signatur: Positionen sind sicher.</summary>
function PlainEnumSignature(const ASignature: string): Boolean;
begin
  Result := (ASignature <> '') and (Pos('=', Copy(ASignature, Pos('(', ASignature) + 1, MaxInt)) = 0) and
    not ASignature.EndsWith('…');
end;

/// <summary>Keine Deklaration der Aufzählung AContainer in AOwner hat unsichere Positionen; AKnown: es gibt eine.</summary>
function EnumPositionsSafe(const AOwner: TUnitIndex; const AContainer: string; out AKnown: Boolean): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  AKnown := False;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumType) and SameText(mSymbol.QualifiedName, AContainer) then
    begin
      if not PlainEnumSignature(mSymbol.Signature) then
      begin
        Exit(False);
      end;
      AKnown := True;
    end;
  end;
  Result := True;
end;

/// <summary>Position des Werts AName in der Aufzählung AContainer aus AOwner.</summary>
function MemberPosition(const AOwner: TUnitIndex; const AContainer, AName: string; out APosition: Int64): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  APosition := 0;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AContainer) then
    begin
      if SameText(mSymbol.Name, AName) then
      begin
        Exit(True);
      end;
      Inc(APosition);
    end;
  end;
  APosition := 0;
  Result := False;
end;

/// <summary>Namen aller Werte der Aufzählung AContainer aus AOwner; False, wenn einer in {$IFDEF} steht.</summary>
function MemberNames(const AOwner: TUnitIndex; const AContainer: string; out ANames: TArray<string>): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  ANames := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AContainer) then
    begin
      // Werte in {$IFDEF}: Anzahl und Positionen hängen von der Konfiguration ab.
      if mSymbol.Condition <> '' then
      begin
        ANames := nil;
        Exit(False);
      end;
      ANames := ANames + [mSymbol.Name];
    end;
  end;
  Result := Length(ANames) > 0;
end;

function TConstantValues.EnumOrdinal(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
var
  mOwner: TUnitIndex;
  mKnown: Boolean;
begin
  // Position in der Aufzählung; mit eigenen Werten (a = 3) nur über den Namen vergleichbar.
  AValue := 0;
  Result := (ASymbol.Container <> '') and OwnerUnit(ASymbol, mOwner) and
    EnumPositionsSafe(mOwner, ASymbol.Container, mKnown) and
    MemberPosition(mOwner, ASymbol.Container, ASymbol.Name, AValue);
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
  begin
    Exit;
  end;
  Tokens := TPascalLexer.Tokenize(ASymbol.Signature);
  Index := SymbolAtDepthZero(Tokens, 0, Length(Tokens), '=');
  if Index < 0 then
  begin
    Exit;
  end;
  Last := High(Tokens);
  if (Last > Index) and Tokens[Last].IsSymbol(';') then
  begin
    Dec(Last);
  end;
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
      begin
        Exit;
      end;
      if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
      begin
        Result := EnumOrdinal(Resolved, AResult);
      end
      else if Resolved.SymbolKind = TIndexSymbolKind.Constant then
      begin
        Result := ConstantValue(Resolved, AResult);
      end
      else
      begin
        Result := False;
      end;
    end;
  Result := TOrdinalConstants.Evaluate(Tokens, Index + 1, Last, Lookup, AValue);
end;

function TConstantValues.OwnValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
var
  mFirst, mLast, mEquals: Integer;
begin
  Result := False;
  AValue := 0;
  // Ausdruck hinter "=" bis vor das Semikolon.
  mFirst := TokenAt(ASymbol.Range.StartPos);
  mLast := TokenAt(ASymbol.Range.EndPos) - 1;
  if (mFirst > High(FTokens)) or (mLast < mFirst) then
  begin
    Exit;
  end;
  // Steht die Deklaration in einem {$IF}-Zweig, den die geprüfte Stelle nicht sicher mit übersetzt, kann
  // in der anderen Konfiguration ein anderer Wert gelten.
  if FCheckPaths and not TConditionalBranches.Implies(FSitePath, TConditionalBranches.PathAt(FPaths, mFirst)) then
  begin
    Exit;
  end;
  if FTokens[mLast].IsSymbol(';') then
  begin
    Dec(mLast);
  end;
  mEquals := SymbolAtDepthZero(FTokens, mFirst, mLast + 1, '=');
  Result := (mEquals >= 0) and Evaluate(mEquals + 1, mLast, AValue);
end;

function TConstantValues.IndexedValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  AValue := 0;
  if not OwnerUnit(ASymbol, mOwner) then
  begin
    Exit;
  end;
  for mSymbol in mOwner.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Constant) and SameText(mSymbol.Name, ASymbol.Name) and
      (mSymbol.Range.StartPos.Line = ASymbol.Range.StartPos.Line) and
      (mSymbol.Range.StartPos.Character = ASymbol.Range.StartPos.Character) then
    begin
      Exit(ForeignValue(mOwner, mSymbol, AValue));
    end;
  end;
end;

function TConstantValues.ConstantValue(const ASymbol: TResolvedSymbol; out AValue: Int64): Boolean;
begin
  Result := False;
  AValue := 0;
  // Konstanten, die aufeinander verweisen, enden hier.
  if FDepth >= 8 then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    if (ASymbol.Kind = TResolvedKind.Local) or (ASymbol.FileName = '') or SameText(ASymbol.FileName, FFileName) then
    begin
      // Deklaration im eigenen Baum.
      Result := OwnValue(ASymbol, AValue);
    end
    else
    begin
      Result := IndexedValue(ASymbol, AValue);
    end;
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
  begin
    Exit;
  end;
  Resolved := FResolver.ResolveChain(FTree, FFileName, ANames, FTokens[ATokenIndex].Offset);
  if not Resolved.Found then
  begin
    Exit;
  end;
  if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := EnumOrdinal(Resolved, AValue);
  end
  else if Resolved.SymbolKind = TIndexSymbolKind.Constant then
  begin
    Result := ConstantValue(Resolved, AValue);
  end;
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
    begin
      Lower := Middle + 1;
    end
    else
    begin
      Upper := Middle;
    end;
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
  mOwner: TUnitIndex;
  mKnown: Boolean;
begin
  ANames := nil;
  // Eigene Werte (a = 3) oder gekürzte Signatur: Positionen und Anzahl sind nicht sicher.
  Result := (AEnum.SymbolKind = TIndexSymbolKind.EnumType) and OwnerUnit(AEnum, mOwner) and
    EnumPositionsSafe(mOwner, AEnum.QualifiedName, mKnown) and mKnown and
    MemberNames(mOwner, AEnum.QualifiedName, ANames);
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
  begin
    Exit(TOrdinalStatus.Unknown);
  end;
  Result := Check(First, Last, AValue);
end;

end.
