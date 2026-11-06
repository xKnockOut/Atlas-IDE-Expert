unit Atlas.Common.Lsp.HoverTypes;

// Typen im Hover-Tooltip (#588): welche Namen in der Deklaration auf einen Typ
// verweisen (Links mit Fundort), die Vererbungskette eines Typs bis TObject
// bzw. IInterface, Art und Herkunft für die Kopfzeile. Das Plugin zeigt damit
// anklickbare Typen und fragt den gewählten Typ über seinen Fundort ab.
//
// Aufgelöst wird über TNameResolver im Scope der Unit, in der die Deklaration
// steht; die Zieldatei muss dafür nicht geparst werden.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Verweis auf einen Typ mit Fundort (Position des Namens, 0-basiert).</summary>
  THoverTypeRef = record
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  /// <summary>Typname in der Deklaration: Start (0-basiert) und Länge im Deklarationstext.</summary>
  THoverLink = record
    Start: Integer;
    Length: Integer;
    Target: THoverTypeRef;
  end;

  TLspHoverTypes = class
  public const
    /// <summary>Höchstzahl der Glieder einer Vererbungskette.</summary>
    cMaxChain = 32;
    cKindClassRef = 'classref';
  public
    /// <summary>Typnamen in ADeclaration (eine Zeile) außer ASelf, aufgelöst aus AUnit.</summary>
    class function Links(AResolver: TNameResolver; const AUnit: TUnitIndex; const ADeclaration,
      ASelf: string): TArray<THoverLink>; static;
    /// <summary>AType und seine Vorfahren bis TObject bzw. IInterface; leer bei anderen Arten.</summary>
    class function Chain(AResolver: TNameResolver; const AType: TResolvedSymbol): TArray<THoverTypeRef>; static;
    /// <summary>Schlüssel für die Art (class, record, interface, classref, method ...).</summary>
    class function KindOf(AKind: TIndexSymbolKind; const ADeclaration: string): string; static;
    /// <summary>Zieltyp von "class of T" in ADeclaration; '' sonst.</summary>
    class function ClassRefTarget(const ADeclaration: string): string; static;
    /// <summary>VCL, FMX oder RTL bei Bibliotheks-Units; '' bei eigenen.</summary>
    class function Origin(const AUnitName: string): string; static;
    class function FromResolved(const ASymbol: TResolvedSymbol): THoverTypeRef; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.DocWiki;

const
  /// <summary>Schlüssel je Art; classref ergibt sich aus der Deklaration (KindOf).</summary>
  cKindNames: array[TIndexSymbolKind] of string = ('class', 'object', 'record', 'interface', 'helper',
    'enum', 'type', 'enumMember', 'constant', 'variable', 'field', 'property', 'method', 'constructor',
    'routine');

/// <summary>True, wenn der Name ab ATokens[AIndex] ein Typverweis sein kann: nicht nach einem Punkt
/// (Mitgliedszugriff) und nicht der deklarierte Name ASelf.</summary>
function MayReferType(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AName, ASelf: string): Boolean;
begin
  Result := not ((AIndex > 0) and ATokens[AIndex - 1].IsSymbol('.')) and not SameText(AName, ASelf);
end;

/// <summary>AName ist ein eigener Typ mit Fundort (kein eingebauter).</summary>
function ResolvesToSourceType(AResolver: TNameResolver; const AUnit: TUnitIndex; const AName: string;
  out AResolved: TResolvedSymbol): Boolean;
begin
  Result := AResolver.ResolveTypeFrom(AUnit, AName, AResolved) and AResolved.IsType and
    not AResolved.Builtin and (AResolved.FileName <> '');
end;

class function TLspHoverTypes.FromResolved(const ASymbol: TResolvedSymbol): THoverTypeRef;
begin
  Result.Name := ASymbol.Name;
  Result.UnitName := ASymbol.UnitName;
  Result.FileName := ASymbol.FileName;
  Result.Line := ASymbol.SelectionRange.StartPos.Line;
  Result.Character := ASymbol.SelectionRange.StartPos.Character;
end;

class function TLspHoverTypes.Links(AResolver: TNameResolver; const AUnit: TUnitIndex; const ADeclaration,
  ASelf: string): TArray<THoverLink>;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mLast: Integer;
  mName: string;
  mResolved: TResolvedSymbol;
  mLink: THoverLink;
begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(ADeclaration);
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    if mTokens[mIndex].Kind <> TPascalTokenKind.Identifier then
    begin
      Inc(mIndex);
      Continue;
    end;
    // Punktketten wie Vcl.Forms.TFrame als ein Name.
    mLast := mIndex;
    mName := mTokens[mIndex].Text;
    while (mLast + 2 <= High(mTokens)) and mTokens[mLast + 1].IsSymbol('.') and
      (mTokens[mLast + 2].Kind = TPascalTokenKind.Identifier) do
    begin
      mName := mName + '.' + mTokens[mLast + 2].Text;
      Inc(mLast, 2);
    end;
    if MayReferType(mTokens, mIndex, mName, ASelf) and ResolvesToSourceType(AResolver, AUnit, mName, mResolved) then
    begin
      mLink.Start := mTokens[mIndex].StartPos.Character;
      mLink.Length := mTokens[mLast].EndPos.Character - mTokens[mIndex].StartPos.Character;
      mLink.Target := FromResolved(mResolved);
      Result := Result + [mLink];
    end;
    mIndex := mLast + 1;
  end;
end;

class function TLspHoverTypes.Chain(AResolver: TNameResolver; const AType: TResolvedSymbol): TArray<THoverTypeRef>;
var
  mCurrent, mNext: TResolvedSymbol;
  mSeen: TArray<string>;
  mKey: string;
begin
  Result := nil;
  // Helfer nur mit Vorfahr-Helfer (#848); der Zieltyp ist kein Vorfahr.
  if (AType.SymbolKind = TIndexSymbolKind.HelperType) and not AResolver.Queries.HelperParent(AType, mNext) then
  begin
    Exit;
  end;
  if not (AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) then
  begin
    Exit;
  end;
  mCurrent := AType;
  mSeen := nil;
  while Length(Result) < cMaxChain do
  begin
    mKey := UpperCase(mCurrent.QualifiedName);
    if MatchStr(mKey, mSeen) then
    begin
      Break;
    end;
    mSeen := mSeen + [mKey];
    Result := Result + [FromResolved(mCurrent)];
    if mCurrent.SymbolKind = TIndexSymbolKind.HelperType then
    begin
      if not AResolver.Queries.HelperParent(mCurrent, mNext) then
      begin
        Break;
      end;
    end
    else if not AResolver.AncestorOf(mCurrent, mNext) then
    begin
      Break;
    end;
    mCurrent := mNext;
  end;
end;

class function TLspHoverTypes.ClassRefTarget(const ADeclaration: string): string;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(ADeclaration, '=\s*class\s+of\s+([A-Za-z_&][\w.]*)', [roIgnoreCase]);
  if mMatch.Success then
  begin
    Result := mMatch.Groups[1].Value;
  end
  else
  begin
    Result := '';
  end;
end;

class function TLspHoverTypes.KindOf(AKind: TIndexSymbolKind; const ADeclaration: string): string;
begin
  if (AKind = TIndexSymbolKind.ClassType) and (ClassRefTarget(ADeclaration) <> '') then
  begin
    Result := cKindClassRef;
  end
  else
  begin
    Result := cKindNames[AKind];
  end;
end;

class function TLspHoverTypes.Origin(const AUnitName: string): string;
begin
  if not TDocWiki.IsLibraryUnit(AUnitName) then
  begin
    Exit('');
  end;
  if StartsText('Vcl.', AUnitName) then
  begin
    Result := 'VCL';
  end
  else if StartsText('FMX.', AUnitName) then
  begin
    Result := 'FMX';
  end
  else
  begin
    Result := 'RTL';
  end;
end;

end.
