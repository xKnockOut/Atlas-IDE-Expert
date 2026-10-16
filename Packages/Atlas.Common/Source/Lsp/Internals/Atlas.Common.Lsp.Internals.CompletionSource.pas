unit Atlas.Common.Lsp.Internals.CompletionSource;

// Gemeinsame Helfer der Vervollständigung über den Index der eigenen Unit (Code-Review D-09): innerster
// Typ um eine Zeile (vorher doppelt in EnclosingType und InterfaceItems) und die Vorfahrenkette eines
// Typs (mit benannter Höchsttiefe statt der Zahl 32).

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TIndexSymbolKinds = set of TIndexSymbolKind;

const
  /// <summary>So viele Vorfahren verfolgt TypeChain höchstens (Schutz vor Zyklen im Index).</summary>
  MaxAncestorChain = 32;

/// <summary>Innerster Typ aus AKinds, in dessen Deklaration ALine liegt: Kopf vor ALine, Ende ab ALine
/// (AInclusiveEnd) bzw. hinter ALine. AMinAncestors: Mindestzahl der Einträge in Ancestors (2 für Klassen
/// mit Interfaces, #466). Bei gleichem Anfang gewinnt der spätere Eintrag.</summary>
function EnclosingTypeAt(const AUnit: TUnitIndex; ALine: Integer; const AKinds: TIndexSymbolKinds;
  AMinAncestors: Integer; AInclusiveEnd: Boolean; out ASymbol: TIndexSymbol): Boolean;
/// <summary>Name von ASymbol samt umgebendem Typ ("TAussen.TInnen").</summary>
function QualifiedTypeName(const ASymbol: TIndexSymbol): string;
/// <summary>AType und seine Vorfahren, nächster zuerst; nur AType, wenn er sich nicht auflösen lässt.</summary>
function TypeChain(AResolver: TNameResolver; const AUnit: TUnitIndex; const AType: string): TArray<string>;

implementation

function EnclosingTypeAt(const AUnit: TUnitIndex; ALine: Integer; const AKinds: TIndexSymbolKinds;
  AMinAncestors: Integer; AInclusiveEnd: Boolean; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  ASymbol := Default(TIndexSymbol);
  for Symbol in AUnit.Symbols do
    if (Symbol.Kind in AKinds) and (Length(Symbol.Ancestors) >= AMinAncestors) and
      (Symbol.Range.StartPos.Line < ALine) and
      ((Symbol.Range.EndPos.Line > ALine) or (AInclusiveEnd and (Symbol.Range.EndPos.Line = ALine))) and
      (not Result or (Symbol.Range.StartPos.Line >= ASymbol.Range.StartPos.Line)) then
    begin
      ASymbol := Symbol;
      Result := True;
    end;
end;

function QualifiedTypeName(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
    Result := ASymbol.Container + '.' + ASymbol.Name
  else
    Result := ASymbol.Name;
end;

function TypeChain(AResolver: TNameResolver; const AUnit: TUnitIndex; const AType: string): TArray<string>;
var
  Current, Ancestor: TResolvedSymbol;
  Depth: Integer;
begin
  Result := nil;
  Result := [AType];
  if not AResolver.ResolveTypeFrom(AUnit, AType, Current) then
    Exit;
  for Depth := 1 to MaxAncestorChain do
  begin
    if not AResolver.AncestorOf(Current, Ancestor) then
      Break;
    Result := Result + [Ancestor.Name];
    Current := Ancestor;
  end;
end;

end.
