unit Argus.Common.Lsp.HoverTypes;

// Typen im Hover-Tooltip (#588): welche Namen in der Deklaration auf einen Typ
// verweisen (Links mit Fundort), die Vererbungskette eines Typs bis TObject
// bzw. IInterface, Art und Herkunft für die Kopfzeile. Das Plugin zeigt damit
// anklickbare Typen und fragt den gewählten Typ über seinen Fundort ab.
//
// Aufgelöst wird über TNameResolver im Scope der Unit, in der die Deklaration
// steht; die Zieldatei muss dafür nicht geparst werden.

interface

uses
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

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
    MaxChain = 32;
    KindClassRef = 'classref';
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
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Lsp.DocWiki;

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
  Tokens: TArray<TPascalToken>;
  Index, Last: Integer;
  Name: string;
  Resolved: TResolvedSymbol;
  Link: THoverLink;
begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(ADeclaration);
  Index := 0;
  while Index <= High(Tokens) do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
    begin
      Inc(Index);
      Continue;
    end;
    // Punktketten wie Vcl.Forms.TFrame als ein Name.
    Last := Index;
    Name := Tokens[Index].Text;
    while (Last + 2 <= High(Tokens)) and Tokens[Last + 1].IsSymbol('.') and
      (Tokens[Last + 2].Kind = TPascalTokenKind.Identifier) do
    begin
      Name := Name + '.' + Tokens[Last + 2].Text;
      Inc(Last, 2);
    end;
    // Nach einem Punkt (Mitgliedszugriff) und der deklarierte Name selbst sind keine Typverweise.
    if not ((Index > 0) and Tokens[Index - 1].IsSymbol('.')) and not SameText(Name, ASelf) and
      AResolver.ResolveTypeFrom(AUnit, Name, Resolved) and Resolved.IsType and not Resolved.Builtin and
      (Resolved.FileName <> '') then
    begin
      Link.Start := Tokens[Index].StartPos.Character;
      Link.Length := Tokens[Last].EndPos.Character - Tokens[Index].StartPos.Character;
      Link.Target := FromResolved(Resolved);
      Result := Result + [Link];
    end;
    Index := Last + 1;
  end;
end;

class function TLspHoverTypes.Chain(AResolver: TNameResolver; const AType: TResolvedSymbol): TArray<THoverTypeRef>;
var
  Current, Next: TResolvedSymbol;
  Seen: TArray<string>;
  Key: string;
begin
  Result := nil;
  if not (AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.InterfaceType]) then
    Exit;
  Current := AType;
  Seen := nil;
  while Length(Result) < MaxChain do
  begin
    Key := UpperCase(Current.QualifiedName);
    if MatchStr(Key, Seen) then
      Break;
    Seen := Seen + [Key];
    Result := Result + [FromResolved(Current)];
    if not AResolver.AncestorOf(Current, Next) then
      Break;
    Current := Next;
  end;
end;

class function TLspHoverTypes.ClassRefTarget(const ADeclaration: string): string;
var
  Match: TMatch;
begin
  Match := TRegEx.Match(ADeclaration, '=\s*class\s+of\s+([A-Za-z_&][\w.]*)', [roIgnoreCase]);
  if Match.Success then
    Result := Match.Groups[1].Value
  else
    Result := '';
end;

class function TLspHoverTypes.KindOf(AKind: TIndexSymbolKind; const ADeclaration: string): string;
begin
  case AKind of
    TIndexSymbolKind.ClassType:
      if ClassRefTarget(ADeclaration) <> '' then
        Result := KindClassRef
      else
        Result := 'class';
    TIndexSymbolKind.ObjectType:
      Result := 'object';
    TIndexSymbolKind.RecordType:
      Result := 'record';
    TIndexSymbolKind.InterfaceType:
      Result := 'interface';
    TIndexSymbolKind.HelperType:
      Result := 'helper';
    TIndexSymbolKind.EnumType:
      Result := 'enum';
    TIndexSymbolKind.TypeAlias:
      Result := 'type';
    TIndexSymbolKind.EnumMember:
      Result := 'enumMember';
    TIndexSymbolKind.Constant:
      Result := 'constant';
    TIndexSymbolKind.Variable:
      Result := 'variable';
    TIndexSymbolKind.Field:
      Result := 'field';
    TIndexSymbolKind.Property_:
      Result := 'property';
    TIndexSymbolKind.Method:
      Result := 'method';
    TIndexSymbolKind.Constructor_:
      Result := 'constructor';
  else
    Result := 'routine';
  end;
end;

class function TLspHoverTypes.Origin(const AUnitName: string): string;
begin
  if not TDocWiki.IsLibraryUnit(AUnitName) then
    Exit('');
  if StartsText('Vcl.', AUnitName) then
    Result := 'VCL'
  else if StartsText('FMX.', AUnitName) then
    Result := 'FMX'
  else
    Result := 'RTL';
end;

end.
