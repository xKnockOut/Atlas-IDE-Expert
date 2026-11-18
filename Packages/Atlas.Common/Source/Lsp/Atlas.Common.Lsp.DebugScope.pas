unit Atlas.Common.Lsp.DebugScope;

// Ort eines Debug-Halts für überwachte Ausdrücke je Klasse oder Unit (#2550), Teil der Antwort von
// atlas.server.debugVariables:
//   - unit: Name der Unit aus dem Syntaxbaum.
//   - class: Klasse der Methode, in der die Zeile steht. Verschachtelte Routinen und anonyme Methoden zählen zur
//     Methode, die sie umgibt; verschachtelte Typen mit Punkt („TAussen.TInnen“), generische ohne Typparameter
//     („TListe<T>.Add“ → „TListe“). Freie Routinen haben keine Klasse.
//   - ancestors: Vorfahren der Klasse aus dem Index über die jeweils erste Basisklasse, nächster zuerst, höchstens
//     cMaxDepth; ohne Index oder unbekannte Klasse leer.
// Antwort: {"unit": "Auftrag.Lauf", "class": "TAuftragsLauf", "ancestors": ["TBasisLauf"]}; leere Felder fehlen.

interface

uses
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TLspDebugScope = record
  public const
    cMaxDepth = 32;
  public
    UnitName: string;
    TypeName: string;
    Ancestors: TArray<string>;
    /// <summary>Ort der Zeile ALine (ab 0) in ATree; AIndex darf nil sein (dann ohne Vorfahren).</summary>
    class function At(ATree: TSyntaxTree; ALine: Integer; const AIndex: ISymbolIndex): TLspDebugScope; static;
    /// <summary>Klasse aus dem Namen einer Methode im Syntaxbaum („TA.TB.Methode“ → „TA.TB“); '' ohne Punkt.
    /// </summary>
    class function TypeOfRoutine(const ARoutineName: string): string; static;
    /// <summary>Vorfahren von ATypeName aus AIndex (siehe Kopf).</summary>
    class function AncestorChain(const AIndex: ISymbolIndex; const ATypeName: string): TArray<string>; static;
    /// <summary>Felder unit, class und ancestors an AJson anhängen; leere fehlen.</summary>
    procedure AddTo(AJson: TJSONObject);
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Common.Pascal.RoutineSignatures;

/// <summary>Letzter Teil eines Typnamens mit Unit oder umgebendem Typ („System.Classes.TComponent“ →
/// „TComponent“).</summary>
function ShortName(const ATypeName: string): string;
var
  mDot: Integer;
begin
  Result := Trim(TRoutineSignatures.WithoutTypeParams(ATypeName));
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

/// <summary>Name der innersten Methode (mit Punkt) unter den Routinen, die ALine enthalten; '' ohne.</summary>
function MethodAt(ATree: TSyntaxTree; ALine: Integer): string;
var
  mNode, mNext: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mNode := ATree.Root;
  while mNode <> nil do
  begin
    // Die innerste Methode mit Punkt gilt; verschachtelte Routinen darin tragen keinen.
    if (mNode.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mNode.Name) > 0) then
    begin
      Result := mNode.Name;
    end;
    mNext := nil;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if (mNode.Children[mIndex].StartPos.Line <= ALine) and (ALine <= mNode.Children[mIndex].EndPos.Line) then
      begin
        mNext := mNode.Children[mIndex];
        Break;
      end;
    end;
    mNode := mNext;
  end;
end;

{ TLspDebugScope }

class function TLspDebugScope.At(ATree: TSyntaxTree; ALine: Integer; const AIndex: ISymbolIndex): TLspDebugScope;
begin
  Result := Default(TLspDebugScope);
  if (ATree = nil) or (ATree.Root = nil) or (ALine < 0) then
  begin
    Exit;
  end;
  Result.UnitName := ATree.Root.Name;
  Result.TypeName := TypeOfRoutine(MethodAt(ATree, ALine));
  if (Result.TypeName <> '') and (AIndex <> nil) then
  begin
    Result.Ancestors := AncestorChain(AIndex, Result.TypeName);
  end;
end;

class function TLspDebugScope.TypeOfRoutine(const ARoutineName: string): string;
var
  mPlain: string;
  mDot: Integer;
begin
  mPlain := Trim(TRoutineSignatures.WithoutTypeParams(ARoutineName));
  mDot := LastDelimiter('.', mPlain);
  Result := '';
  if mDot > 1 then
  begin
    Result := Copy(mPlain, 1, mDot - 1);
  end;
end;

class function TLspDebugScope.AncestorChain(const AIndex: ISymbolIndex; const ATypeName: string): TArray<string>;
var
  mName, mNext: string;
  mSeen: TDictionary<string, Boolean>;
  mFound: TSymbolLocation;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mName := ShortName(ATypeName);
    mSeen.Add(LowerCase(mName), True);
    while (mName <> '') and (Length(Result) < cMaxDepth) do
    begin
      mNext := '';
      for mFound in AIndex.FindSymbols(mName) do
      begin
        if (mFound.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType]) and
          (Length(mFound.Symbol.Ancestors) > 0) then
        begin
          mNext := ShortName(mFound.Symbol.Ancestors[0]);
          Break;
        end;
      end;
      // Kreis im Index (zwei Klassen gleichen Namens): aufhören.
      if (mNext = '') or mSeen.ContainsKey(LowerCase(mNext)) then
      begin
        Break;
      end;
      mSeen.Add(LowerCase(mNext), True);
      Result := Result + [mNext];
      mName := mNext;
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TLspDebugScope.AddTo(AJson: TJSONObject);
begin
  if UnitName <> '' then
  begin
    AJson.AddPair('unit', UnitName);
  end;
  if TypeName <> '' then
  begin
    AJson.AddPair('class', TypeName);
    AJson.AddPair('ancestors', TJsonBuild.Strings(Ancestors));
  end;
end;

end.
