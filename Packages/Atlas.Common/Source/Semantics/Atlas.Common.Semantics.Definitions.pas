unit Atlas.Common.Semantics.Definitions;

// Sprungziele für Gehe zu Definition, Deklaration und Typ über die Namensauflösung;
// die Anfragen des Sprachservers beantwortet Atlas.Common.Lsp.Definition.
//
// Bei Routinen und Methoden mit getrennter Deklaration und Implementierung:
//   - declaration springt immer zur Deklaration (interface bzw. Klasse),
//   - definition springt zur Implementierung; steht der Cursor bereits auf
//     dem Namen der Implementierung, zurück zur Deklaration. So wechselt
//     dieselbe Taste zwischen beiden.
// Bei Überladungen gehören nur Deklaration und Implementierung derselben
// Variante (gleiche Parametertypen) zusammen; steht der Cursor auf einer
// Routine der Datei, gilt deren Variante.
// Unit-Namen (z. B. in uses) führen an den Anfang der Unit-Datei.
// Das Typziel führt von Variablen, Feldern, Parametern, Properties und
// Funktionen zur Deklaration ihres Typs.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Sprungziel: Datei, ganzer Bereich und Name.</summary>
  TDefinitionTarget = record
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
    class function Create(const AFileName: string; const ARange, ASelectionRange: TTextRange): TDefinitionTarget;
      static;
  end;

  /// <summary>Stelle einer Sprungabfrage: Baum, Datei, Position und ob zur Deklaration.</summary>
  TDefinitionQuery = record
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    /// <summary>Immer zur Deklaration springen (sonst wechselt die Taste zwischen beiden).</summary>
    Declaration: Boolean;
    class function Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      ADeclaration: Boolean): TDefinitionQuery; static;
  end;

  TDefinitions = class
  public
    /// <summary>Sprungziele für den Bezeichner an APosition; leer, wenn er nicht auflösbar ist.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
        static;
    /// <summary>Wie Targets, für ein schon aufgelöstes Symbol (etwa einen Kandidaten aus ResolveAll, #1119).
    /// </summary>
    class function TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
      const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>; static;
    /// <summary>Deklaration des Typs des Bezeichners an APosition; leer, wenn er keinen bekannten Typ hat.</summary>
    class function TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Files;

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

/// <summary>Gleiche Parametertypen (Groß-/Kleinschreibung egal): dieselbe Variante einer Überladung.</summary>
function SameParams(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if not SameText(A[mIndex], B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

function Target(const AFileName: string; const ARange, ASelectionRange: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelectionRange;
end;

{ TDefinitionQuery }

class function TDefinitionQuery.Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  ADeclaration: Boolean): TDefinitionQuery;
begin
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.Declaration := ADeclaration;
end;

/// <summary>Die Deklaration unter dem Cursor in der eigenen Datei; Kind None, wenn dort keine steht.</summary>
function DeclarationAt(AResolver: TNameResolver; const AQuery: TDefinitionQuery): TResolvedSymbol;
var
  mOwnerUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := Default(TResolvedSymbol);
  // Über den Resolver: bei gepinntem Baum ohne neue Auswertung.
  mOwnerUnit := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  for mSymbol in mOwnerUnit.Symbols do
  begin
    if SameText(mOwnerUnit.SymbolFile(mSymbol), AQuery.FileName) and
      mSymbol.SelectionRange.Encloses(AQuery.Position) then
    begin
      Result.Kind := TResolvedKind.Symbol;
      Result.Name := mSymbol.Name;
      Result.Container := mSymbol.Container;
      Result.SymbolKind := mSymbol.Kind;
      Result.FileName := AQuery.FileName;
      Result.Range := mSymbol.Range;
      Result.SelectionRange := mSymbol.SelectionRange;
      Result.ParamTypes := mSymbol.ParamTypes;
      Exit;
    end;
  end;
end;

/// <summary>Parametertypen der gemeinten Variante: die der Routine unter dem Cursor in AHere, sonst die von
/// AResolved.</summary>
function VariantParams(AHere: TUnitIndex; const AResolved: TResolvedSymbol;
  const APosition: TTextPosition): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AHere.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AResolved.Name) and
      mSymbol.SelectionRange.Encloses(APosition) then
    begin
      Exit(mSymbol.ParamTypes);
    end;
  end;
  Result := AResolved.ParamTypes;
end;

/// <summary>Fundstellen der Routine AResolved in AOwner: erst die Variante mit AParams, ohne zweite Fundstelle
/// das einzige Paar ohne Überladungen (die Implementierung darf ihre Parameter weglassen). False ohne Paar.
/// </summary>
function RoutinePair(AOwner: TUnitIndex; const AResolved: TResolvedSymbol; const AParams: TArray<string>;
  out AVariant: TArray<TIndexSymbol>): Boolean;
var
  mSymbol: TIndexSymbol;
  mSame: TArray<TIndexSymbol>;
begin
  mSame := nil;
  AVariant := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AResolved.Container) and
      SameText(mSymbol.Name, AResolved.Name) then
    begin
      mSame := mSame + [mSymbol];
      if SameParams(mSymbol.ParamTypes, AParams) then
      begin
        AVariant := AVariant + [mSymbol];
      end;
    end;
  end;
  if (Length(AVariant) < 2) and (Length(mSame) = 2) then
  begin
    AVariant := mSame;
  end;
  Result := Length(AVariant) >= 2;
end;

/// <summary>Ziel einer Routine: Deklaration und Implementierung derselben Variante. Steht der Cursor auf einer
/// Routine dieser Datei (Deklaration oder Implementierung), gilt deren Variante. Ohne Paar das Symbol selbst.
/// </summary>
function RoutineTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
  const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mHere, mOwnerUnit: TUnitIndex;
  mVariant: TArray<TIndexSymbol>;
  mFirst, mLast, mChosen: TIndexSymbol;
  mFound: Boolean;
begin
  Result := [Target(AResolved.FileName, AResolved.Range, AResolved.SelectionRange)];
  mHere := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  mOwnerUnit := mHere;
  mFound := SameText(AResolved.FileName, AQuery.FileName) or TIndexFiles.UnitOf(AIndex, AResolved.FileName,
    mOwnerUnit);
  if not mFound or not RoutinePair(mOwnerUnit, AResolved, VariantParams(mHere, AResolved, AQuery.Position),
    mVariant) then
  begin
    Exit;
  end;
  mFirst := mVariant[0];
  mLast := mVariant[High(mVariant)];
  // Mit Include-Dateien (#500) kann jede Fundstelle in einer anderen Datei stehen.
  mChosen := mLast;
  if AQuery.Declaration or (SameText(mOwnerUnit.SymbolFile(mLast), AQuery.FileName) and
    mLast.SelectionRange.Encloses(AQuery.Position)) then
  begin
    mChosen := mFirst;
  end;
  Result := [Target(mOwnerUnit.SymbolFile(mChosen), mChosen.Range, mChosen.SelectionRange)];
end;

class function TDefinitions.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
begin
  Result := TargetsOf(AResolver, AIndex, TDefinitionQuery.Create(ATree, AFileName, APosition, ADeclaration),
    AResolver.Resolve(ATree, AFileName, APosition));
end;

class function TDefinitions.TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AQuery: TDefinitionQuery; const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mResolved: TResolvedSymbol;
  mEmpty: TTextRange;
begin
  // Namen in Deklarationen (z. B. Methoden in der Klasse) sind keine Verwendungen:
  // dann gilt die Deklaration unter dem Cursor selbst. Zuerst prüfen: Die
  // Namensauflösung liest einen solchen Namen sonst wie eine Verwendung und nimmt
  // bei Überladungen die erste (Hover auf der zweiten zeigte die erste).
  // Das Ergebnis erst zuweisen statt Exit([...]): In der früheren Form brach dcc64 (Delphi 13) ohne Meldung ab.
  mResolved := DeclarationAt(AResolver, AQuery);
  // Sonst die schon aufgelöste Verwendung des Aufrufers (TargetsOf, #1119).
  if mResolved.Kind = TResolvedKind.None then
  begin
    mResolved := AResolved;
  end;
  case mResolved.Kind of
    TResolvedKind.None:
      Result := nil;
    TResolvedKind.UnitName:
      begin
        mEmpty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
        Result := [Target(mResolved.FileName, mEmpty, mEmpty)];
      end;
    TResolvedKind.Local:
      Result := [Target(AQuery.FileName, mResolved.Range, mResolved.SelectionRange)];
  else
    if mResolved.SymbolKind in cRoutineKinds then
    begin
      Result := RoutineTargets(AResolver, AIndex, AQuery, mResolved);
    end
    else
    begin
      Result := [Target(mResolved.FileName, mResolved.Range, mResolved.SelectionRange)];
    end;
  end;
end;

class function TDefinitions.TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mTypeInfo: TResolvedSymbol;
begin
  mTypeInfo := AResolver.ResolveType(ATree, AFileName, APosition);
  if mTypeInfo.Kind = TResolvedKind.Symbol then
  begin
    Result := [Target(mTypeInfo.FileName, mTypeInfo.Range, mTypeInfo.SelectionRange)];
  end
  else
  begin
    Result := nil;
  end;
end;


{ TDefinitionTarget }

class function TDefinitionTarget.Create(const AFileName: string; const ARange,
  ASelectionRange: TTextRange): TDefinitionTarget;
begin
  Result := Target(AFileName, ARange, ASelectionRange);
end;

end.
