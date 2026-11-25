unit Atlas.Common.Index.Extractor.ParamOwnership;

// Besitz-Zusammenfassung je Parameter für den Symbolindex (TIndexSymbol.ParamOwnership): Für jede Routine mit
// Rumpf im implementation-Abschnitt hält der Extraktor fest, ob sie ein übergebenes Objekt freigibt, übernimmt,
// nur leiht oder weiterreicht (Atlas.Common.Pascal.ParamOwnership), an Deklaration und Implementierung. Die
// Analyse läuft einmal beim Einlesen der Unit und liegt danach im Index-Cache; die Abfrage beim Aufruf kostet
// nur das Nachschlagen im Index.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TIndexParamOwnership = class
  public
    /// <summary>Trägt ParamOwnership an Deklaration und Implementierung der Routinen aus ASection
    /// (implementation-Abschnitt) ein; nil tut nichts.</summary>
    class procedure Add(ASymbols: TList<TIndexSymbol>; ASection: TSyntaxNode); static;
  end;

implementation

uses
  Atlas.Common.Pascal.ParamOwnership,
  Atlas.Common.Index.Extractor.Routines;

class procedure TIndexParamOwnership.Add(ASymbols: TList<TIndexSymbol>; ASection: TSyntaxNode);
var
  mRoutines: TIndexRoutineSymbols;
  mIndex, mFound: Integer;
  mNode: TSyntaxNode;
  mName, mContainer, mSummary: string;
begin
  if ASection = nil then
  begin
    Exit;
  end;
  mRoutines := TIndexRoutineSymbols.Create(ASymbols);
  try
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      mNode := ASection[mIndex];
      if (mNode.Kind <> TSyntaxKind.RoutineDecl) or (mNode.FindChild(TSyntaxKind.Block) = nil) then
      begin
        Continue;
      end;
      mSummary := TParamOwnership.Summarize(mNode);
      if mSummary = '' then
      begin
        Continue;
      end;
      TIndexRoutineSymbols.SplitName(mNode.Name, mContainer, mName);
      mFound := mRoutines.FindDeclaration(mNode, mName, mContainer);
      if mFound = -2 then
      begin
        // Überladungen ohne Parameterliste in der Implementierung: Zuordnung unklar.
        Continue;
      end;
      mRoutines.Change(mNode, mName, mContainer, mFound,
        procedure(var ASymbol: TIndexSymbol)
        begin
          ASymbol.ParamOwnership := mSummary;
        end);
    end;
  finally
    mRoutines.Free;
  end;
end;

end.
