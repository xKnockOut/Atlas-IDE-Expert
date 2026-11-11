unit Atlas.Common.Semantics.TreeUnits;

// Geteilte Auswertung eines Syntaxbaums für die Namensauflösung (#1322).
//
// Die Regel-Engine legt je Prüflauf eine TTreeUnits für den geprüften Baum an
// und gibt sie über TRuleContext.TreeUnits an jeden TNameResolver weiter. So
// extrahiert ein Lauf die Unit je Dateiname genau einmal, statt bei jedem
// NodeType-Aufruf eines nicht gepinnten Resolvers. Die Regeln rufen den Baum
// unter verschiedenen Namen auf (FileName, RelativePath, Unit-Name + .pas),
// darum gilt der Speicher je Dateiname.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.Contract;

type
  /// <summary>Wie TIndexExtractor.Extract(Baum, Dateiname), je Dateiname einmal; threadsicher.</summary>
  ITreeExtracts = interface
    ['{5E8A3C71-2B9D-4F06-8A14-C7D2E9B01F35}']
    function Extracted(const AFileName: string): TUnitIndex;
  end;

  /// <summary>Extrahierte Units eines Baums, am Baum selbst geteilt (TSyntaxTree.Derived, #1761): Resolver ohne
  /// TTreeUnits des Prüflaufs (Code-Aktionen, Hover, Vervollständigung …) werten denselben Baum so nur einmal
  /// aus. Nur das Extrahieren: Die Zusammenführung mit dem Index ändert sich mit dem Index.</summary>
  TTreeExtracts = class(TInterfacedObject, ITreeExtracts)
  private
    FTree: TSyntaxTree;
    FLock: TObject;
    // Dateiname groß -> Unit. Unter FLock.
    FEntries: TDictionary<string, TUnitIndex>;
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    function Extracted(const AFileName: string): TUnitIndex;
    /// <summary>Die am Baum ATree geteilte Auswertung.</summary>
    class function ForTree(ATree: TSyntaxTree): ITreeExtracts; static;
  end;

  TTreeUnits = class(TInterfacedObject, ITreeUnits)
  private type
    TEntry = record
      FileName: string;
      Extracted: TUnitIndex;
      HasMerged: Boolean;
      // Hält den Index fest, damit der Vergleich nie eine wiederverwendete Adresse trifft.
      MergedIndex: ISymbolIndex;
      Merged: TUnitIndex;
    end;
  private
    FTree: TSyntaxTree;
    FEntries: TList<TEntry>;
    FExtractions: Integer;
    FMerges: Integer;
    function EntryIndex(const AFileName: string): Integer;
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    /// <summary>AExtracted samt der Symbole ihrer $I-Dateien aus AIndex (#500), mit Namenstabelle; AIndex nil
    /// oder ohne die Datei: nur AExtracted mit Namenstabelle.</summary>
    class function Merge(const AIndex: ISymbolIndex; const AExtracted: TUnitIndex;
      const AFileName: string): TUnitIndex; static;
    function Holds(ATree: TSyntaxTree): Boolean;
    function Extracted(const AFileName: string): TUnitIndex;
    function Merged(const AIndex: ISymbolIndex; const AFileName: string): TUnitIndex;
    procedure Clear;
    /// <summary>Zahl der Auswertungen mit TIndexExtractor.Extract seit dem Anlegen (für Tests).</summary>
    property Extractions: Integer read FExtractions;
    /// <summary>Zahl der Zusammenführungen mit dem Index seit dem Anlegen (für Tests).</summary>
    property Merges: Integer read FMerges;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Extractor;

{ TTreeExtracts }

constructor TTreeExtracts.Create(ATree: TSyntaxTree);
begin
  inherited Create;
  FTree := ATree;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TUnitIndex>.Create;
end;

destructor TTreeExtracts.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited Destroy;
end;

function TTreeExtracts.Extracted(const AFileName: string): TUnitIndex;
var
  mKey: string;
begin
  mKey := AnsiUpperCase(AFileName);
  System.TMonitor.Enter(FLock);
  try
    if not FEntries.TryGetValue(mKey, Result) then
    begin
      Result := TIndexExtractor.Extract(FTree, AFileName);
      FEntries.Add(mKey, Result);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

/// <summary>Legt die Auswertung für ATree an (für TSyntaxTree.Derived).</summary>
function ExtractsFactory(ATree: TSyntaxTree): TFunc<IInterface>;
begin
  Result :=
    function: IInterface
    begin
      Result := TTreeExtracts.Create(ATree) as ITreeExtracts;
    end;
end;

class function TTreeExtracts.ForTree(ATree: TSyntaxTree): ITreeExtracts;
begin
  Result := ATree.Derived(ExtractsFactory(ATree)) as ITreeExtracts;
end;

{ TTreeUnits }

constructor TTreeUnits.Create(ATree: TSyntaxTree);
begin
  inherited Create;
  FTree := ATree;
  FEntries := TList<TEntry>.Create;
end;

destructor TTreeUnits.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

class function TTreeUnits.Merge(const AIndex: ISymbolIndex; const AExtracted: TUnitIndex;
  const AFileName: string): TUnitIndex;
var
  mIndexed: TUnitIndex;
  mCount, mPosition: Integer;
begin
  Result := AExtracted;
  // Der Baum kennt nur die Datei selbst; Deklarationen aus Include-Dateien stehen im Index.
  if (AIndex <> nil) and (AFileName <> '') and AIndex.FindFile(AFileName, mIndexed) then
  begin
    // Eigenes Array (Copy): Result.Symbols teilt es sonst mit AExtracted. Einmal vergrößern statt je
    // Symbol anhängen.
    mCount := Length(AExtracted.Symbols);
    Result.Symbols := Copy(AExtracted.Symbols);
    SetLength(Result.Symbols, mCount + Length(mIndexed.Symbols));
    for mPosition := 0 to High(mIndexed.Symbols) do
    begin
      if mIndexed.Symbols[mPosition].FileName <> '' then
      begin
        Result.Symbols[mCount] := mIndexed.Symbols[mPosition];
        Inc(mCount);
      end;
    end;
    SetLength(Result.Symbols, mCount);
    Result.Includes := mIndexed.Includes;
  end;
  Result.PrepareNames;
end;

function TTreeUnits.EntryIndex(const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if SameText(FEntries[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TTreeUnits.Holds(ATree: TSyntaxTree): Boolean;
begin
  Result := (FTree <> nil) and (ATree = FTree);
end;

function TTreeUnits.Extracted(const AFileName: string): TUnitIndex;
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  mIndex := EntryIndex(AFileName);
  if mIndex >= 0 then
  begin
    Exit(FEntries[mIndex].Extracted);
  end;
  if FTree = nil then
  begin
    raise EInvalidOpException.Create('TTreeUnits.Extracted ohne Baum');
  end;
  mEntry := Default(TEntry);
  mEntry.FileName := AFileName;
  mEntry.Extracted := TIndexExtractor.Extract(FTree, AFileName);
  Inc(FExtractions);
  FEntries.Add(mEntry);
  Result := mEntry.Extracted;
end;

function TTreeUnits.Merged(const AIndex: ISymbolIndex; const AFileName: string): TUnitIndex;
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  Extracted(AFileName);
  mIndex := EntryIndex(AFileName);
  mEntry := FEntries[mIndex];
  if mEntry.HasMerged and (mEntry.MergedIndex = AIndex) then
  begin
    Exit(mEntry.Merged);
  end;
  // Ein anderer Index ersetzt den gemerkten Stand; in einem Lauf ist es immer derselbe.
  mEntry.Merged := Merge(AIndex, mEntry.Extracted, AFileName);
  mEntry.MergedIndex := AIndex;
  mEntry.HasMerged := True;
  Inc(FMerges);
  FEntries[mIndex] := mEntry;
  Result := mEntry.Merged;
end;

procedure TTreeUnits.Clear;
begin
  FTree := nil;
  FEntries.Clear;
end;

end.
