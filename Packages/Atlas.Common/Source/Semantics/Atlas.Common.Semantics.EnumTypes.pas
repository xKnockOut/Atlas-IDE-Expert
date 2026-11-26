unit Atlas.Common.Semantics.EnumTypes;

// Aufzählungstypen über die Namensauflösung (#448): Typ an einer Stelle, Aliase und Mengen bis zur Aufzählung
// verfolgt, Werte in Deklarationsreihenfolge, {$SCOPEDENUMS} an der Deklaration und Positionen der Werte. Dazu
// die Werte für „case vervollständigen“ (#50), „Muster fortsetzen“ (#671) und „Werte ändern“ (#868). Geteilt von
// Vervollständigung, Code-Aktionen und Befehlen des Sprachservers.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Was die Auflösung von Aufzählungstypen braucht: Auflöser, Index, Baum und Text der Datei und das
  /// Lesen anderer Dateien.</summary>
  TEnumLookup = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    Text: string;
    FileName: string;
    ReadText: TDocumentReadText;
  end;

  /// <summary>Aufzählungstyp mit seinen Werten (#448).</summary>
  TEnumType = record
    Name: string;
    /// <summary>Mengentyp, über den er gefunden wurde ("TAnchors"); '' ohne.</summary>
    SetName: string;
    Values: TArray<string>;
    /// <summary>Namenspositionen der Werte in FileName; Line -1, wenn unbekannt.</summary>
    Positions: TArray<TTextPosition>;
    FileName: string;
    /// <summary>{$SCOPEDENUMS ON} an der Deklaration: Werte nur mit Typpräfix.</summary>
    Scoped: Boolean;
  end;

  TEnumTypes = class
  public const
    /// <summary>So oft folgt die Auflösung Aliasen und Mengen bis zur Aufzählung.</summary>
    cMaxAliasSteps = 4;
  public
    /// <summary>Typ ATypeName, wie er an AOffset stünde; sonst ein gleichnamiger Typ aus dem Index.</summary>
    class function TypeAt(const ALookup: TEnumLookup; AOffset: Integer; const ATypeName: string): TResolvedSymbol;
      static;
    /// <summary>Aufzählung zu AType, Aliase verfolgt; mit AAllowSet auch der Elementtyp einer Menge.</summary>
    class function EnumOf(const ALookup: TEnumLookup; AType: TResolvedSymbol; AAllowSet: Boolean;
      out AEnum: TEnumType): Boolean; static;
    /// <summary>Quelltext der Datei von ASymbol: das offene Dokument oder über ReadText.</summary>
    class function SourceOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out ASource: string): Boolean;
      static;
    /// <summary>Text von ARange in AText, über höchstens cMaxRangeLines Zeilen.</summary>
    class function RangeText(const AText: string; const ARange: TTextRange): string; static;
    /// <summary>„case vervollständigen“ (#50): Werte der Aufzählung, über die die case-Anweisung verzweigt, deren
    /// "of" vor APosition endet; APrefix ist "TAlign." bei {$SCOPEDENUMS ON}. False ohne Aufzählungstyp.</summary>
    class function CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>; out APrefix: string): Boolean; static;
    /// <summary>Muster fortsetzen (#671): alle Werte des Aufzählungstyps, zu dem der Wert an APosition gehört, in
    /// Deklarationsreihenfolge (ohne Typpräfix). False, wenn dort kein Aufzählungswert steht.</summary>
    class function EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>): Boolean; static;
    /// <summary>Werte ändern (#868): Werte des Aufzählungstyps ATypeName, wie er an AOffset sichtbar ist, in
    /// Deklarationsreihenfolge; bei einer Menge die Werte des Elementtyps mit AIsSet; APrefix „TModus.“ bei
    /// {$SCOPEDENUMS ON}. False ohne Aufzählung.</summary>
    class function EnumOfType(const ALookup: TEnumLookup; AOffset: Integer; const ATypeName: string;
      out AValues: TArray<string>; out AIsSet: Boolean; out APrefix: string): Boolean; static;
    /// <summary>Text der Deklaration von ASymbol (höchstens einige Zeilen); '' ohne Quelltext.</summary>
    class function DeclarationOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Semantics.ExpectedTypes,
  Atlas.Common.Pascal.EnumSlots,
  Atlas.Text.Lines;

const
  /// <summary>Höchstens so viele Zeilen liest RangeText (lange Aufzählungen stehen über viele Zeilen).</summary>
  cMaxRangeLines = 400;

class function TEnumTypes.RangeText(const AText: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  Result := '';
  mLines := TTextLines.SplitAtLineFeed(AText);
  for mLine := Max(0, ARange.StartPos.Line) to Min(Min(ARange.EndPos.Line, ARange.StartPos.Line + cMaxRangeLines),
    High(mLines)) do
  begin
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(mLines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + #10 + mLines[mLine];
    end;
  end;
end;

/// <summary>Offset (0-basiert) von APosition in AText.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  mIndex, mLine: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex - 1 + APosition.Character;
end;

class function TEnumTypes.SourceOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol;
  out ASource: string): Boolean;
begin
  ASource := '';
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    ASource := ALookup.Text;
    Exit(True);
  end;
  Result := (ASymbol.FileName <> '') and Assigned(ALookup.ReadText) and ALookup.ReadText(ASymbol.FileName, ASource);
end;

/// <summary>Index-Eintrag der Unit von ASymbol; für das offene Dokument aus dessen Baum.</summary>
function OwnerUnit(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    AUnit := ALookup.Resolver.ExtractedUnit(ALookup.Tree, ALookup.FileName);
    Exit(True);
  end;
  Result := (ALookup.Index <> nil) and ALookup.Index.FindFile(ASymbol.FileName, AUnit);
end;

class function TEnumTypes.TypeAt(const ALookup: TEnumLookup; AOffset: Integer;
  const ATypeName: string): TResolvedSymbol;
var
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
begin
  Result := ALookup.Resolver.ResolveChain(ALookup.Tree, ALookup.FileName, ATypeName.Split(['.']), AOffset);
  // Eingebaute Typen (Integer, string) stehen nicht im Index: nicht danach suchen.
  if (Result.Found and Result.IsType) or (ALookup.Index = nil) or (Pos('.', ATypeName) > 0) or
    TResolverText.IsBuiltinTypeName(ATypeName) then
  begin
    Exit;
  end;
  // Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
  for mLocation in ALookup.Index.FindSymbols(ATypeName) do
  begin
    if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) and ALookup.Index.FindUnit(mLocation.UnitName, mOwner) and
      ALookup.Resolver.ResolveTypeFrom(mOwner, ATypeName, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ein Schritt von einem Alias oder einer Menge zum Typ dahinter, von der Unit der Deklaration aus;
/// False, wenn er nicht weiterführt.</summary>
function FollowAlias(const ALookup: TEnumLookup; const ADeclaration: string; AAllowSet: Boolean;
  var AType: TResolvedSymbol; var AEnum: TEnumType): Boolean;
var
  mOwner: TUnitIndex;
  mElement: string;
begin
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit(False);
  end;
  mElement := TPascalEnumSlots.SetElement(ADeclaration);
  if mElement = '' then
  begin
    Exit((AType.TypeName <> '') and ALookup.Resolver.ResolveTypeFrom(mOwner, AType.TypeName, AType));
  end;
  Result := AAllowSet and (AEnum.SetName = '');
  if Result then
  begin
    AEnum.SetName := AType.Name;
    Result := ALookup.Resolver.ResolveTypeFrom(mOwner, mElement, AType);
  end;
end;

/// <summary>Folgt Aliasen (und mit AAllowSet einer Menge) bis zur Aufzählung; ASource und ADeclaration sind dann
/// ihr Quelltext und ihre Deklaration.</summary>
function FindEnumDeclaration(const ALookup: TEnumLookup; AAllowSet: Boolean; var AType: TResolvedSymbol;
  var AEnum: TEnumType; out ASource, ADeclaration: string): Boolean;
var
  mStep: Integer;
begin
  ASource := '';
  ADeclaration := '';
  for mStep := 1 to TEnumTypes.cMaxAliasSteps do
  begin
    // Erst die Art prüfen: Klassen und eingebaute Typen brauchen den Quelltext nicht.
    if not AType.Found or not AType.IsType or not (AType.SymbolKind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) or not TEnumTypes.SourceOf(ALookup, AType, ASource) then
    begin
      Exit(False);
    end;
    ADeclaration := TEnumTypes.RangeText(ASource, AType.Range);
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Exit(True);
    end;
    // Alias oder Menge: von der Unit der Deklaration aus weiter auflösen.
    if not FollowAlias(ALookup, ADeclaration, AAllowSet, AType, AEnum) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Namenspositionen der Werte für completionItem/resolve.</summary>
procedure FindEnumPositions(const ALookup: TEnumLookup; const AType: TResolvedSymbol; var AEnum: TEnumType);
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mIndex: Integer;
begin
  SetLength(AEnum.Positions, Length(AEnum.Values));
  for mIndex := 0 to High(AEnum.Positions) do
  begin
    AEnum.Positions[mIndex] := TTextPosition.Create(-1, 0);
  end;
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit;
  end;
  for mSymbol in mOwner.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.EnumMember) or not SameText(mSymbol.Container, AType.QualifiedName) then
    begin
      Continue;
    end;
    for mIndex := 0 to High(AEnum.Values) do
    begin
      if SameText(AEnum.Values[mIndex], mSymbol.Name) then
      begin
        AEnum.Positions[mIndex] := mSymbol.SelectionRange.StartPos;
      end;
    end;
  end;
end;

class function TEnumTypes.EnumOf(const ALookup: TEnumLookup; AType: TResolvedSymbol; AAllowSet: Boolean;
  out AEnum: TEnumType): Boolean;
var
  mSource, mDeclaration: string;
begin
  AEnum := Default(TEnumType);
  Result := FindEnumDeclaration(ALookup, AAllowSet, AType, AEnum, mSource, mDeclaration);
  if Result then
  begin
    AEnum.Values := TPascalEnumSlots.EnumValues(mDeclaration);
    Result := AEnum.Values <> nil;
  end;
  if Result then
  begin
    AEnum.Name := AType.Name;
    AEnum.FileName := AType.FileName;
    AEnum.Scoped := TPascalEnumSlots.ScopedAt(mSource, OffsetOf(mSource, AType.Range.StartPos));
    FindEnumPositions(ALookup, AType, AEnum);
  end;
end;

{ TEnumTypes }

class function TEnumTypes.CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>; out APrefix: string): Boolean;
var
  mExpected: string;
  mEnum: TEnumType;
begin
  AValues := nil;
  APrefix := '';
  mExpected := '';
  // Am Anfang eines Zweigs ist der erwartete Typ der des Selektors (#448).
  if ALookup.Tree <> nil then
  begin
    mExpected := TExpectedTypes.At(ALookup.Resolver, ALookup.Tree, ALookup.FileName, APosition);
  end;
  Result := (mExpected <> '') and EnumOf(ALookup, TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mExpected),
    False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
    if mEnum.Scoped then
    begin
      APrefix := mEnum.Name + '.';
    end;
  end;
end;

class function TEnumTypes.EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>): Boolean;
var
  mMember, mType: TResolvedSymbol;
  mOwner: TUnitIndex;
  mEnum: TEnumType;
begin
  AValues := nil;
  if ALookup.Tree = nil then
  begin
    Exit(False);
  end;
  mMember := ALookup.Resolver.Resolve(ALookup.Tree, ALookup.FileName, APosition);
  if not mMember.Found or (mMember.SymbolKind <> TIndexSymbolKind.EnumMember) or (mMember.Container = '') then
  begin
    Exit(False);
  end;
  // Der Typ, wie er an der Stelle sichtbar ist; sonst von der Unit des Werts aus.
  mType := TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mMember.Container);
  if not (mType.Found and mType.IsType) and OwnerUnit(ALookup, mMember, mOwner) then
  begin
    ALookup.Resolver.ResolveTypeFrom(mOwner, mMember.Container, mType);
  end;
  Result := EnumOf(ALookup, mType, False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
  end;
end;

class function TEnumTypes.EnumOfType(const ALookup: TEnumLookup; AOffset: Integer; const ATypeName: string;
  out AValues: TArray<string>; out AIsSet: Boolean; out APrefix: string): Boolean;
var
  mEnum: TEnumType;
begin
  AValues := nil;
  AIsSet := False;
  APrefix := '';
  if (ALookup.Tree = nil) or (ATypeName = '') then
  begin
    Exit(False);
  end;
  Result := EnumOf(ALookup, TypeAt(ALookup, AOffset, ATypeName), True, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
    AIsSet := mEnum.SetName <> '';
    if mEnum.Scoped then
    begin
      APrefix := mEnum.Name + '.';
    end;
  end;
end;

class function TEnumTypes.DeclarationOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol): string;
var
  mSource: string;
begin
  Result := '';
  if ASymbol.Found and SourceOf(ALookup, ASymbol, mSource) then
  begin
    Result := RangeText(mSource, ASymbol.Range);
  end;
end;

end.
