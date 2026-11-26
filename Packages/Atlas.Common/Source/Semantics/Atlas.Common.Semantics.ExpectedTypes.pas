unit Atlas.Common.Semantics.ExpectedTypes;

// Erwarteter Typ an einer Stelle (#417): Typ des aktiven Parameters im innersten Aufruf, sonst der linken Seite
// einer Zuweisung (auch Result), sonst der Kette eines Vergleichs oder case-Zweigs (#448). Für Vervollständigung,
// Deklarieren unbekannter Namen und Refactorings.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver;

type
  TExpectedTypes = class
  public
    /// <summary>Erwarteter Typ an APosition; '' wenn unbekannt.</summary>
    class function At(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
    /// <summary>Wie At, bei Zuweisungen aber samt Typargumenten der linken Seite (TProc&lt;string&gt; statt TProc,
    /// #468). At bleibt ohne, weil die Gruppierung nach Fits mit den Typnamen der Kandidaten ohne Typargumente
    /// vergleicht.</summary>
    class function FullAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.CallSites,
  Atlas.Common.Pascal.EnumSlots,
  Atlas.Common.Pascal.TypeTexts,
  Atlas.Text.Names;

const
  /// <summary>Ergebnis von AssignmentBefore, wenn die Kette vor dem Cursor kein Bezeichner ist.</summary>
  cBrokenChain = -2;

/// <summary>Argument eines Aufrufs: Typ des aktiven Parameters (erste passende Überladung). False außerhalb
/// eines Aufrufs.</summary>
function ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AType: string): Boolean;
var
  mSite: TPascalCallSite;
  mCallee: TResolvedSymbol;
begin
  AType := '';
  mSite := TPascalCallSites.At(ATree, APosition);
  Result := mSite.Found;
  if not Result then
  begin
    Exit;
  end;
  mCallee := AResolver.Resolve(ATree, AFileName, mSite.NamePosition);
  // Mitglied einer generischen Instanz (TBox<TKunde>.Where): Typparameter der Klasse einsetzen (#468).
  if mCallee.Found and (mSite.ActiveParameter < Length(mCallee.ParamTypes)) then
  begin
    AType := TPascalTypeTexts.SubstituteWords(mCallee.ParamTypes[mSite.ActiveParameter], mCallee.Bindings);
  end;
end;

/// <summary>"Ziel := A.B.Anf|": Index des ":=" rückwärts über die Kette rechts; -1 ohne Zuweisung,
/// cBrokenChain, wenn vor einem Punkt kein Bezeichner steht.</summary>
function AssignmentBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
begin
  Result := PreviousCode(ATokens, TokenBeforePosition(ATokens, APosition) + 1);
  if (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (TTextPosition.Compare(APosition, ATokens[Result].EndPos) <= 0) then
  begin
    Result := PreviousCode(ATokens, Result);
  end;
  while (Result >= 0) and ATokens[Result].IsSymbol('.') do
  begin
    Result := PreviousCode(ATokens, Result);
    if (Result < 0) or (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(cBrokenChain);
    end;
    Result := PreviousCode(ATokens, Result);
  end;
  if (Result >= 0) and not ATokens[Result].IsSymbol(':=') then
  begin
    Result := -1;
  end;
end;

/// <summary>Vergleich ("Shape.Kind = ") und case-Zweig (#448): Typ der Kette. Ein Typ selbst steht bei typisierten
/// Konstanten und Standardwerten ("const C: TAlign = ", "A: TAlign = ").</summary>
function ComparedType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
var
  mSlot: TEnumValueSlot;
  mTarget: TResolvedSymbol;
begin
  Result := '';
  if not TPascalEnumSlots.ValueSlot(ATree.Tokens, APosition, mSlot) then
  begin
    Exit;
  end;
  mTarget := AResolver.ResolveChain(ATree, AFileName, mSlot.Names, mSlot.Offset);
  if mTarget.Found and mTarget.IsType then
  begin
    Result := mTarget.Name;
  end
  else if mTarget.Found then
  begin
    Result := mTarget.TypeName;
  end;
end;

/// <summary>Kette links vom ":=" an AIndex.</summary>
function TargetNames(const ATokens: TArray<TPascalToken>; AIndex: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := PreviousCode(ATokens, AIndex);
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := [TTextNames.WithoutAmpersand(ATokens[mIndex].Text)] + Result;
    mIndex := PreviousCode(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
end;

/// <summary>Rückgabetyp der Funktion, in deren Rumpf APosition steht; '' ohne.</summary>
function ResultTypeAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AResolver.ExtractedUnit(ATree, AFileName).Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and (mSymbol.TypeName <> '') and
      (mSymbol.Range.StartPos.Line < APosition.Line) and (mSymbol.Range.EndPos.Line >= APosition.Line) then
    begin
      Result := mSymbol.TypeName;
    end;
  end;
end;

/// <summary>Typ eines Zuweisungsziels; mit AWithArgs samt Typargumenten.</summary>
function TargetType(const ATarget: TResolvedSymbol; AWithArgs: Boolean): string;
begin
  Result := '';
  if ATarget.Found and not ATarget.IsType and (ATarget.SymbolKind <> TIndexSymbolKind.Routine) and
    (ATarget.SymbolKind <> TIndexSymbolKind.Method) then
  begin
    Result := ATarget.TypeName;
    if AWithArgs and (Result <> '') and (ATarget.TypeArgs <> '') then
    begin
      Result := Result + '<' + ATarget.TypeArgs + '>';
    end;
  end;
end;

/// <summary>Erwarteter Typ am Cursor (siehe TExpectedTypes.At); mit AWithArgs bei Zuweisungen samt
/// Typargumenten der Variablen.</summary>
function ExpectedTypeOf(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AWithArgs: Boolean): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mNames: TArray<string>;
begin
  Result := '';
  if (ATree = nil) or ArgumentType(AResolver, ATree, AFileName, APosition, Result) then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mIndex := AssignmentBefore(mTokens, APosition);
  if mIndex = -1 then
  begin
    Exit(ComparedType(AResolver, ATree, AFileName, APosition));
  end;
  mNames := nil;
  if mIndex >= 0 then
  begin
    mNames := TargetNames(mTokens, mIndex);
  end;
  if mNames = nil then
  begin
    Exit;
  end;
  Result := TargetType(AResolver.ResolveChain(ATree, AFileName, mNames, mTokens[mIndex].Offset), AWithArgs);
  // Result: Rückgabetyp der umgebenden Funktion.
  if (Result = '') and (Length(mNames) = 1) and SameText(mNames[0], 'Result') then
  begin
    Result := ResultTypeAt(AResolver, ATree, AFileName, APosition);
  end;
end;

{ TExpectedTypes }

class function TExpectedTypes.At(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, False);
end;

class function TExpectedTypes.FullAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): string;
begin
  Result := ExpectedTypeOf(AResolver, ATree, AFileName, APosition, True);
end;

end.
