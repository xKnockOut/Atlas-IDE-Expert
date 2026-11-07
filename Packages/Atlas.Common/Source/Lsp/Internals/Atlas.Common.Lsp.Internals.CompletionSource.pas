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
  cMaxAncestorChain = 32;

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

/// <summary>Umschließt der Bereich von ASymbol die Zeile ALine (Ende mit AInclusiveEnd eingeschlossen)?</summary>
function SpansLine(const ASymbol: TIndexSymbol; ALine: Integer; AInclusiveEnd: Boolean): Boolean;
begin
  Result := (ASymbol.Range.StartPos.Line < ALine) and
    ((ASymbol.Range.EndPos.Line > ALine) or (AInclusiveEnd and (ASymbol.Range.EndPos.Line = ALine)));
end;

function EnclosingTypeAt(const AUnit: TUnitIndex; ALine: Integer; const AKinds: TIndexSymbolKinds;
  AMinAncestors: Integer; AInclusiveEnd: Boolean; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ASymbol := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in AKinds) and (Length(mSymbol.Ancestors) >= AMinAncestors) and
      SpansLine(mSymbol, ALine, AInclusiveEnd) and
      (not Result or (mSymbol.Range.StartPos.Line >= ASymbol.Range.StartPos.Line)) then
    begin
      ASymbol := mSymbol;
      Result := True;
    end;
  end;
end;

function QualifiedTypeName(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + '.' + ASymbol.Name;
  end
  else
  begin
    Result := ASymbol.Name;
  end;
end;

function TypeChain(AResolver: TNameResolver; const AUnit: TUnitIndex; const AType: string): TArray<string>;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := nil;
  Result := [AType];
  if not AResolver.ResolveTypeFrom(AUnit, AType, mCurrent) then
  begin
    Exit;
  end;
  for mDepth := 1 to cMaxAncestorChain do
  begin
    if not AResolver.AncestorOf(mCurrent, mAncestor) then
    begin
      Break;
    end;
    Result := Result + [mAncestor.Name];
    mCurrent := mAncestor;
  end;
end;

end.
