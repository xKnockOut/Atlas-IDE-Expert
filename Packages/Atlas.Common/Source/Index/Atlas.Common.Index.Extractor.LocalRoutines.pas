unit Atlas.Common.Index.Extractor.LocalRoutines;

// Lokale (verschachtelte) Routinen einer Projekt-Unit für die Projekt-Symbolsuche (workspace/symbol): Routinen im
// Rumpf einer Methode oder Routine, auch mehrstufig. Sie stehen getrennt von Symbols in TUnitIndex.LocalRoutines,
// damit Namensauflösung, Referenzen und Prüfregeln sie nicht als Symbole der Unit sehen. Container ist die
// umgebende Routine mit Besitzer (TFoo.Bar, bei tieferen Ebenen TFoo.Bar.Aussen). Reine Funktion über dem
// Syntaxbaum, threadsicher.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TIndexLocalRoutines = class
  public
    /// <summary>Lokale Routinen aller Routinen im implementation-Teil (bzw. im Programm) von ATree in
    /// Quelltextreihenfolge.</summary>
    class function Collect(ATree: TSyntaxTree): TArray<TIndexSymbol>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor.Tokens;

/// <summary>Lokale Routinen von ARoutine samt deren lokalen Routinen an AList; AContainer ist ARoutine mit
/// Besitzer.</summary>
procedure AddLocals(AReader: TIndexTokenReader; ARoutine: TSyntaxNode; const AContainer: string;
  AList: TList<TIndexSymbol>);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mSymbol: TIndexSymbol;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mChild := ARoutine[mIndex];
    if (mChild.Kind <> TSyntaxKind.RoutineDecl) or (mChild.Name = '') then
    begin
      Continue;
    end;
    mSymbol := Default(TIndexSymbol);
    mSymbol.Name := TPascalLexer.PlainName(mChild.Name);
    mSymbol.Container := AContainer;
    mSymbol.Kind := TIndexSymbolKind.Routine;
    mSymbol.Range := TTextRange.Create(mChild.StartPos, mChild.EndPos);
    mSymbol.SelectionRange := AReader.NameRange(mChild, mSymbol.Name);
    // Außerhalb der Routine nicht sichtbar.
    mSymbol.Visibility := TIndexVisibility.Private;
    AList.Add(mSymbol);
    AddLocals(AReader, mChild, AContainer + '.' + mSymbol.Name, AList);
  end;
end;

{ TIndexLocalRoutines }

class function TIndexLocalRoutines.Collect(ATree: TSyntaxTree): TArray<TIndexSymbol>;
var
  mParent, mChild: TSyntaxNode;
  mIndex: Integer;
  mReader: TIndexTokenReader;
  mList: TList<TIndexSymbol>;
begin
  Result := nil;
  mParent := ATree.Root;
  if mParent.Kind = TSyntaxKind.UnitFile then
  begin
    mParent := mParent.FindChild(TSyntaxKind.ImplementationSection);
  end;
  if mParent = nil then
  begin
    Exit;
  end;
  mReader := TIndexTokenReader.Create(ATree.Tokens);
  mList := TList<TIndexSymbol>.Create;
  try
    for mIndex := 0 to mParent.ChildCount - 1 do
    begin
      mChild := mParent[mIndex];
      if mChild.Kind = TSyntaxKind.RoutineDecl then
      begin
        AddLocals(mReader, mChild, TPascalLexer.PlainName(mChild.Name), mList);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mReader.Free;
  end;
end;

end.
