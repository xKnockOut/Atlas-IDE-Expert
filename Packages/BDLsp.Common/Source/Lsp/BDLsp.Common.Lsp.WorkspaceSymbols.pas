unit BDLsp.Common.Lsp.WorkspaceSymbols;

// Projektweite Symbolsuche (workspace/symbol) über den Symbolindex.
//
// Treffer sind Symbole, deren Name die Anfrage enthält (ohne Groß-/
// Kleinschreibung). Reihenfolge: exakter Name, dann Namensanfang, dann
// Teilstring; innerhalb gleicher Güte Typen vor Mitgliedern und danach
// alphabetisch. Höchstens MaxResults Treffer. Implementierungen von
// Methoden (TFoo.Bar in implementation) erscheinen nicht doppelt.
// Eine leere Anfrage liefert nichts, damit der Client nicht den ganzen
// Index erhält.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Index.Contract;

type
  TWorkspaceSymbol = record
    Symbol: TIndexSymbol;
    UnitName: string;
    FileName: string;
  end;

  TLspWorkspaceSymbols = class
  public const
    Method = 'workspace/symbol';
    MaxResults = 200;
  private
    FIndex: ISymbolIndex;
    function HandleSymbol(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AIndex: ISymbolIndex);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sortierte Treffer für AQuery, höchstens AMax.</summary>
    class function Search(const AIndex: ISymbolIndex; const AQuery: string; AMax: Integer;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<TWorkspaceSymbol>; static;
    /// <summary>LSP-SymbolKind zur Symbolart.</summary>
    class function LspKind(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>SymbolInformation[]. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ASymbols: TArray<TWorkspaceSymbol>): TJSONArray; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.Positions;

type
  TCandidate = record
    Item: TWorkspaceSymbol;
    Rank: Integer;
  end;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

function MatchRank(const AName, AQuery: string): Integer;
var
  Found: Integer;
begin
  // 0 exakt, 1 Anfang, 2 enthalten, -1 kein Treffer.
  Found := Pos(AQuery, LowerCase(AName));
  if Found = 0 then
    Result := -1
  else if Found > 1 then
    Result := 2
  else if Length(AName) = Length(AQuery) then
    Result := 0
  else
    Result := 1;
end;

{ TLspWorkspaceSymbols }

constructor TLspWorkspaceSymbols.Create(const AIndex: ISymbolIndex);
begin
  inherited Create;
  FIndex := AIndex;
end;

procedure TLspWorkspaceSymbols.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleSymbol);
end;

class function TLspWorkspaceSymbols.Search(const AIndex: ISymbolIndex; const AQuery: string; AMax: Integer;
  const ACancellation: IJsonRpcCancellationToken): TArray<TWorkspaceSymbol>;
var
  Query: string;
  Candidates: TList<TCandidate>;
  Seen: TDictionary<string, Boolean>;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Candidate: TCandidate;
  Rank, Index: Integer;
  Key: string;
begin
  Result := nil;
  Query := LowerCase(Trim(AQuery));
  if Query = '' then
    Exit;
  Candidates := TList<TCandidate>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for UnitIndex in AIndex.Units do
    begin
      if ACancellation <> nil then
        ACancellation.ThrowIfCancellationRequested;
      for Symbol in UnitIndex.Symbols do
      begin
        Rank := MatchRank(Symbol.Name, Query);
        if Rank < 0 then
          Continue;
        // Deklaration und Implementierung derselben Routine nur einmal.
        Key := LowerCase(UnitIndex.FileName + '|' + Symbol.Container + '|' + Symbol.Name + '|' +
          IntToStr(Ord(Symbol.Kind)));
        if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) then
        begin
          if Seen.ContainsKey(Key) then
            Continue;
          Seen.Add(Key, True);
        end;
        Candidate.Item.Symbol := Symbol;
        Candidate.Item.UnitName := UnitIndex.UnitName;
        Candidate.Item.FileName := UnitIndex.FileName;
        Candidate.Rank := Rank * 2;
        if not (Symbol.Kind in TypeKinds) then
          Inc(Candidate.Rank);
        Candidates.Add(Candidate);
      end;
    end;
    Candidates.Sort(TComparer<TCandidate>.Construct(
      function(const A, B: TCandidate): Integer
      begin
        Result := A.Rank - B.Rank;
        if Result = 0 then
          Result := CompareText(A.Item.Symbol.Name, B.Item.Symbol.Name);
        if Result = 0 then
          Result := CompareText(A.Item.Symbol.Container, B.Item.Symbol.Container);
        if Result = 0 then
          Result := CompareText(A.Item.UnitName, B.Item.UnitName);
      end));
    if Candidates.Count < AMax then
      AMax := Candidates.Count;
    SetLength(Result, AMax);
    for Index := 0 to AMax - 1 do
      Result[Index] := Candidates[Index].Item;
  finally
    Seen.Free;
    Candidates.Free;
  end;
end;

class function TLspWorkspaceSymbols.LspKind(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.TypeAlias:
      Result := 5;
    TIndexSymbolKind.RecordType:
      Result := 23;
    TIndexSymbolKind.InterfaceType:
      Result := 11;
    TIndexSymbolKind.EnumType:
      Result := 10;
    TIndexSymbolKind.EnumMember:
      Result := 22;
    TIndexSymbolKind.Constant:
      Result := 14;
    TIndexSymbolKind.Variable:
      Result := 13;
    TIndexSymbolKind.Field:
      Result := 8;
    TIndexSymbolKind.Property_:
      Result := 7;
    TIndexSymbolKind.Method:
      Result := 6;
    TIndexSymbolKind.Constructor_:
      Result := 9;
  else
    Result := 12;
  end;
end;

class function TLspWorkspaceSymbols.ToJson(const ASymbols: TArray<TWorkspaceSymbol>): TJSONArray;
var
  Item: TWorkspaceSymbol;
  Info, Location: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Item in ASymbols do
  begin
    Info := TJSONObject.Create;
    Info.AddPair('name', Item.Symbol.Name);
    Info.AddPair('kind', TJSONNumber.Create(LspKind(Item.Symbol.Kind)));
    if Item.Symbol.Container <> '' then
      Info.AddPair('containerName', Item.UnitName + '.' + Item.Symbol.Container)
    else
      Info.AddPair('containerName', Item.UnitName);
    Location := TJSONObject.Create;
    Location.AddPair('uri', TDocumentUris.FromPath(Item.FileName));
    Location.AddPair('range', TLspPositions.RangeToJson(Item.Symbol.SelectionRange));
    Info.AddPair('location', Location);
    Result.AddElement(Info);
  end;
end;

function TLspWorkspaceSymbols.HandleSymbol(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Query: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('query', Query)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "query" fehlt in ' + Method);
  Result := ToJson(Search(FIndex, Query, MaxResults, ACancellation));
end;

end.
