unit Atlas.Common.Lsp.WorkspaceSymbols;

// Projektweite Symbolsuche (workspace/symbol) über den Symbolindex.
//
// Treffer und Reihenfolge nach TFuzzyMatch: exakter Name, Namensanfang,
// Teilstring, dann Teilfolge mit Kürzeln wie "TBB" für TBButton (#39);
// innerhalb gleicher Güte Typen vor Mitgliedern und danach alphabetisch. Höchstens MaxResults Treffer.
// Implementierungen von
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
    cMethod = 'workspace/symbol';
    cMaxResults = 200;
    /// <summary>SymbolKind.Key für Lesezeichen.</summary>
    cBookmarkKind = 20;
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
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
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
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleSymbol);
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
  if not (ASymbol.Kind in cTypeKinds) then
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
    if (mRank <> TFuzzyMatch.cNoMatch) and not IsRepeat(ASeen, AUnit, mSymbol) then
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
  mQuery: string;
  mHit: TBookmarkHit;
  mCandidates: TList<TCandidate>;
  mCandidate: TCandidate;
  mRank: Integer;
begin
  Result := nil;
  mQuery := LowerCase(Trim(AQuery));
  if mQuery = '' then
  begin
    Exit;
  end;
  mCandidates := TList<TCandidate>.Create;
  try
    for mHit in AHits do
    begin
      mRank := TFuzzyMatch.Score(mHit.Bookmark.Name, mQuery);
      if mRank = TFuzzyMatch.cNoMatch then
      begin
        Continue;
      end;
      mCandidate.Item.Symbol := Default(TIndexSymbol);
      mCandidate.Item.Symbol.Name := mHit.Bookmark.Name;
      mCandidate.Item.Symbol.Range := mHit.Bookmark.Range;
      mCandidate.Item.Symbol.SelectionRange := mHit.Bookmark.Range;
      mCandidate.Item.UnitName := ChangeFileExt(ExtractFileName(mHit.FileName), '');
      mCandidate.Item.FileName := mHit.FileName;
      mCandidate.Item.Bookmark := True;
      mCandidate.Rank := -mRank;
      mCandidates.Add(mCandidate);
    end;
    mCandidates.Sort(TComparer<TCandidate>.Construct(
      function(const A, B: TCandidate): Integer
      begin
        Result := A.Rank - B.Rank;
        if Result = 0 then
        begin
          Result := CompareText(A.Item.Symbol.Name, B.Item.Symbol.Name);
        end;
      end));
    for mCandidate in mCandidates do
    begin
      Result := Result + [mCandidate.Item];
    end;
  finally
    mCandidates.Free;
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
  mItem: TWorkspaceSymbol;
  mInfo, mLocation: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mItem in ASymbols do
  begin
    mInfo := TJSONObject.Create;
    mInfo.AddPair('name', mItem.Symbol.Name);
    if mItem.Bookmark then
    begin
      mInfo.AddPair('kind', TJSONNumber.Create(cBookmarkKind));
    end
    else
    begin
      mInfo.AddPair('kind', TJSONNumber.Create(LspKind(mItem.Symbol.Kind)));
    end;
    if mItem.Symbol.Container <> '' then
    begin
      mInfo.AddPair('containerName', mItem.UnitName + '.' + mItem.Symbol.Container);
    end
    else
    begin
      mInfo.AddPair('containerName', mItem.UnitName);
    end;
    mLocation := TJSONObject.Create;
    mLocation.AddPair('uri', TDocumentUris.FromPath(mItem.FileName));
    mLocation.AddPair('range', TLspPositions.RangeToJson(mItem.Symbol.SelectionRange));
    mInfo.AddPair('location', mLocation);
    Result.AddElement(mInfo);
  end;
end;

function TLspWorkspaceSymbols.HandleSymbol(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mQuery: string;
  mFound: TArray<TWorkspaceSymbol>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('query', mQuery)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TWorkspaceSymbolsText.FieldQueryMissingIn].Text + cMethod);
  end;
  mFound := nil;
  if Assigned(FBookmarksFor) then
  begin
    mFound := SearchBookmarks(FBookmarksFor(), mQuery);
  end;
  mFound := mFound + Search(FIndex, mQuery, cMaxResults, ACancellation);
  if Length(mFound) > cMaxResults then
  begin
    SetLength(mFound, cMaxResults);
  end;
  Result := ToJson(mFound);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.WorkspaceSymbols', cTexts);

end.
