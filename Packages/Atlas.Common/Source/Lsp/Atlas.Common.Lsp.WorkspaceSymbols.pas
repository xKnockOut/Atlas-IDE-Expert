unit Atlas.Common.Lsp.WorkspaceSymbols;

// Projektweite Symbolsuche (workspace/symbol) über den Symbolindex.
//
// Treffer und Reihenfolge nach TFuzzyMatch: exakter Name, Namensanfang,
// Teilstring, dann Teilfolge mit Kürzeln wie "TBB" für TBButton (#39);
// innerhalb gleicher Güte Typen vor Mitgliedern und danach alphabetisch. Höchstens MaxResults Treffer. Implementierungen von
// Methoden (TFoo.Bar in implementation) erscheinen nicht doppelt.
// Eine leere Anfrage liefert nichts, damit der Client nicht den ganzen
// Index erhält. Lesezeichen ("// @bookmark Name", #306) kommen vor den
// Symbolen, wenn BookmarksFor gesetzt ist.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Bookmarks;

type
  TWorkspaceSymbol = record
    Symbol: TIndexSymbol;
    UnitName: string;
    FileName: string;
    /// <summary>Lesezeichen statt Symbol aus dem Index.</summary>
    Bookmark: Boolean;
  end;

  /// <summary>Alle bekannten Lesezeichen.</summary>
  TBookmarkSource = reference to function: TArray<TBookmarkHit>;

  TLspWorkspaceSymbols = class
  public const
    Method = 'workspace/symbol';
    MaxResults = 200;
    /// <summary>SymbolKind.Key für Lesezeichen.</summary>
    BookmarkKind = 20;
  private
    FIndex: ISymbolIndex;
    FBookmarksFor: TBookmarkSource;
    function HandleSymbol(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AIndex: ISymbolIndex);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sortierte Treffer für AQuery, höchstens AMax.</summary>
    class function Search(const AIndex: ISymbolIndex; const AQuery: string; AMax: Integer;
      const ACancellation: IJsonRpcCancellationToken): TArray<TWorkspaceSymbol>; overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function Search(const AIndex: ISymbolIndex; const AQuery: string; AMax: Integer): TArray<TWorkspaceSymbol>;
      overload; static;
    /// <summary>Lesezeichen aus AHits, die zu AQuery passen, beste zuerst.</summary>
    class function SearchBookmarks(const AHits: TArray<TBookmarkHit>; const AQuery: string): TArray<TWorkspaceSymbol>;
      static;
    /// <summary>LSP-SymbolKind zur Symbolart.</summary>
    class function LspKind(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>SymbolInformation[]. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ASymbols: TArray<TWorkspaceSymbol>): TJSONArray; static;
    property BookmarksFor: TBookmarkSource read FBookmarksFor write FBookmarksFor;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.FuzzyMatch,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWorkspaceSymbolsText = (FieldQueryMissingIn);

const
  cTexts: array[TWorkspaceSymbolsText] of TAtlasText = (
    (De: 'Feld "query" fehlt in '; En: 'Field "query" missing in '));

{$SCOPEDENUMS OFF}

type
  TCandidate = record
    Item: TWorkspaceSymbol;
    Rank: Integer;
  end;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

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

class function TLspWorkspaceSymbols.Search(const AIndex: ISymbolIndex; const AQuery: string;
  AMax: Integer): TArray<TWorkspaceSymbol>;
begin
  Result := Search(AIndex, AQuery, AMax, nil);
end;

/// <summary>Deklaration und Implementierung derselben Routine nur einmal: True, wenn ASymbol schon in ASeen
/// steht; sonst wird es eingetragen.</summary>
function IsRepeat(ASeen: TDictionary<string, Boolean>; const AUnit: TUnitIndex; const ASymbol: TIndexSymbol): Boolean;
var
  mKey: string;
begin
  Result := False;
  if not (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) then
  begin
    Exit;
  end;
  mKey := LowerCase(AUnit.FileName + '|' + ASymbol.Container + '|' + ASymbol.Name + '|' +
    IntToStr(Ord(ASymbol.Kind)));
  Result := ASeen.ContainsKey(mKey);
  if not Result then
  begin
    ASeen.Add(mKey, True);
  end;
end;

/// <summary>Treffer ASymbol mit der Güte ARank; höhere Punktzahl zuerst, bei Gleichstand Typen vor anderen
/// Symbolen.</summary>
function NewCandidate(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; ARank: Integer): TCandidate;
begin
  Result.Item.Symbol := ASymbol;
  Result.Item.UnitName := AUnit.UnitName;
  Result.Item.FileName := AUnit.FileName;
  Result.Item.Bookmark := False;
  Result.Rank := -ARank * 2;
  if not (ASymbol.Kind in TypeKinds) then
  begin
    Inc(Result.Rank);
  end;
end;

/// <summary>Treffer der Unit AUnit für AQuery (klein geschrieben) an ACandidates anhängen.</summary>
procedure AddUnitCandidates(ACandidates: TList<TCandidate>; ASeen: TDictionary<string, Boolean>;
  const AUnit: TUnitIndex; const AQuery: string);
var
  mSymbol: TIndexSymbol;
  mRank: Integer;
begin
  for mSymbol in AUnit.Symbols do
  begin
    mRank := TFuzzyMatch.Score(mSymbol.Name, AQuery);
    if (mRank <> TFuzzyMatch.NoMatch) and not IsRepeat(ASeen, AUnit, mSymbol) then
    begin
      ACandidates.Add(NewCandidate(AUnit, mSymbol, mRank));
    end;
  end;
end;

/// <summary>Reihenfolge: Güte, Name, Klasse, Unit.</summary>
function CompareCandidates(const A, B: TCandidate): Integer;
begin
  Result := A.Rank - B.Rank;
  if Result = 0 then
  begin
    Result := CompareText(A.Item.Symbol.Name, B.Item.Symbol.Name);
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Item.Symbol.Container, B.Item.Symbol.Container);
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Item.UnitName, B.Item.UnitName);
  end;
end;

class function TLspWorkspaceSymbols.Search(const AIndex: ISymbolIndex; const AQuery: string; AMax: Integer;
  const ACancellation: IJsonRpcCancellationToken): TArray<TWorkspaceSymbol>;
var
  mQuery: string;
  mCandidates: TList<TCandidate>;
  mSeen: TDictionary<string, Boolean>;
  mUnit: TUnitIndex;
  mIndex: Integer;
begin
  Result := nil;
  mQuery := LowerCase(Trim(AQuery));
  if mQuery = '' then
  begin
    Exit;
  end;
  mCandidates := TList<TCandidate>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mUnit in AIndex.Units do
    begin
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      AddUnitCandidates(mCandidates, mSeen, mUnit, mQuery);
    end;
    mCandidates.Sort(TComparer<TCandidate>.Construct(
      function(const A, B: TCandidate): Integer
      begin
        Result := CompareCandidates(A, B);
      end));
    SetLength(Result, Min(AMax, mCandidates.Count));
    for mIndex := 0 to High(Result) do
    begin
      Result[mIndex] := mCandidates[mIndex].Item;
    end;
  finally
    mSeen.Free;
    mCandidates.Free;
  end;
end;

class function TLspWorkspaceSymbols.SearchBookmarks(const AHits: TArray<TBookmarkHit>;
  const AQuery: string): TArray<TWorkspaceSymbol>;
var
  Query: string;
  Hit: TBookmarkHit;
  Candidates: TList<TCandidate>;
  Candidate: TCandidate;
  Rank: Integer;
begin
  Result := nil;
  Query := LowerCase(Trim(AQuery));
  if Query = '' then
  begin
    Exit;
  end;
  Candidates := TList<TCandidate>.Create;
  try
    for Hit in AHits do
    begin
      Rank := TFuzzyMatch.Score(Hit.Bookmark.Name, Query);
      if Rank = TFuzzyMatch.NoMatch then
      begin
        Continue;
      end;
      Candidate.Item.Symbol := Default(TIndexSymbol);
      Candidate.Item.Symbol.Name := Hit.Bookmark.Name;
      Candidate.Item.Symbol.Range := Hit.Bookmark.Range;
      Candidate.Item.Symbol.SelectionRange := Hit.Bookmark.Range;
      Candidate.Item.UnitName := ChangeFileExt(ExtractFileName(Hit.FileName), '');
      Candidate.Item.FileName := Hit.FileName;
      Candidate.Item.Bookmark := True;
      Candidate.Rank := -Rank;
      Candidates.Add(Candidate);
    end;
    Candidates.Sort(TComparer<TCandidate>.Construct(
      function(const A, B: TCandidate): Integer
      begin
        Result := A.Rank - B.Rank;
        if Result = 0 then
        begin
          Result := CompareText(A.Item.Symbol.Name, B.Item.Symbol.Name);
        end;
      end));
    for Candidate in Candidates do
    begin
      Result := Result + [Candidate.Item];
    end;
  finally
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
    if Item.Bookmark then
    begin
      Info.AddPair('kind', TJSONNumber.Create(BookmarkKind));
    end
    else
    begin
      Info.AddPair('kind', TJSONNumber.Create(LspKind(Item.Symbol.Kind)));
    end;
    if Item.Symbol.Container <> '' then
    begin
      Info.AddPair('containerName', Item.UnitName + '.' + Item.Symbol.Container);
    end
    else
    begin
      Info.AddPair('containerName', Item.UnitName);
    end;
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
  Found: TArray<TWorkspaceSymbol>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('query', Query)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TWorkspaceSymbolsText.FieldQueryMissingIn].Text + Method);
  end;
  Found := nil;
  if Assigned(FBookmarksFor) then
  begin
    Found := SearchBookmarks(FBookmarksFor(), Query);
  end;
  Found := Found + Search(FIndex, Query, MaxResults, ACancellation);
  if Length(Found) > MaxResults then
  begin
    SetLength(Found, MaxResults);
  end;
  Result := ToJson(Found);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.WorkspaceSymbols', cTexts);

end.
