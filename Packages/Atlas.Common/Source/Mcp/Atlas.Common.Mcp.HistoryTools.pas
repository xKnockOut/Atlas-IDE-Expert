unit Atlas.Common.Mcp.HistoryTools;

// MCP-Werkzeug get_symbol_history (#2641): Geschichte einer Routine oder eines Typs über Umbenennen und
// Verschieben. Den Namen löst der Index auf (wie find_symbol); den Bereich bestimmt der übernommene Stand der Datei
// (Git HEAD, SVN BASE), weil git log -L und svn log in diesem Stand zählen; ohne ihn der Text der Arbeitskopie.
// Routinen über ihren Rumpf (TSymbolHistoryService.FindRoutine), Typen über ihre Deklaration. Ein mehrdeutiger
// Name ergibt die Trefferliste, ein unbekannter einen Hinweis.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.History.Contract;

type
  /// <summary>Argumente eines Aufrufs.</summary>
  TMcpHistoryArgs = record
    Name: string;
    /// <summary>Höchstzahl der Einträge; 0 = Vorgabe.</summary>
    Limit: Integer;
    FollowMoves: Boolean;
    Json: Boolean;
    TimeoutMs: Integer;
    Cancelled: TFunc<Boolean>;
    /// <summary>Vorgaben: limit 20, followMoves an, Markdown.</summary>
    class function Default: TMcpHistoryArgs; static;
  end;

  TMcpHistoryTools = class
  public const
    /// <summary>Höchstens so viele Treffer in der Liste eines mehrdeutigen Namens.</summary>
    cMaxCandidates = 20;
  private
    FIndex: ISymbolIndex;
    FService: ISymbolHistoryService;
    FReadText: TReferenceReadText;
    function Candidates(const AName: string): TArray<TSymbolLocation>;
    function SourceText(const AVcs: ISymbolHistoryVcs; const ALocation: TSymbolLocation; const APath: string): string;
    function RequestFor(const AVcs: ISymbolHistoryVcs; const ALocation: TSymbolLocation; const APath: string;
      const AArgs: TMcpHistoryArgs): TSymbolHistoryRequest;
  public
    constructor Create(const AIndex: ISymbolIndex; const AService: ISymbolHistoryService;
      const AReadText: TReferenceReadText);
    /// <summary>get_symbol_history für AArgs.Name mit der Versionsverwaltung AVcs.</summary>
    function Run(const AVcs: ISymbolHistoryVcs; const AArgs: TMcpHistoryArgs): string;
    /// <summary>Antwort ohne Versionsverwaltung (Hinweis statt Fehler); AReason sagt warum.</summary>
    class function NoVcs(const AReason: string): string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.History.Report,
  Atlas.Common.Localization.Texts,
  Atlas.Common.History.Service;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THistoryToolsText = (NoSymbol, Ambiguous, AmbiguousHint, Outside, NoVcs);

{$SCOPEDENUMS OFF}

const
  cTexts: array[THistoryToolsText] of TAtlasText = (
    (De: 'Kein Symbol "%s" im Index.'; En: 'No symbol "%s" in the index.'),
    (De: '"%s" ist mehrdeutig, %d Treffer:'; En: '"%s" is ambiguous, %d matches:'),
    (De: 'Mit Unit.TTyp.Name genauer fassen.'; En: 'Narrow it down with Unit.TType.Name.'),
    (De: '%s liegt nicht in der Arbeitskopie %s.'; En: '%s is not in the working copy %s.'),
    (De: 'Keine Geschichte: %s. Die Symbolgeschichte braucht ein Git-Repository oder eine SVN-Arbeitskopie.';
     En: 'No history: %s. The symbol history needs a Git repository or an SVN working copy.'));

  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType];

{ TMcpHistoryArgs }

class function TMcpHistoryArgs.Default: TMcpHistoryArgs;
begin
  Result.Name := '';
  Result.Limit := TSymbolHistoryService.cDefaultLimit;
  Result.FollowMoves := True;
  Result.Json := False;
  Result.TimeoutMs := 0;
  Result.Cancelled := nil;
end;

{ TMcpHistoryTools }

constructor TMcpHistoryTools.Create(const AIndex: ISymbolIndex; const AService: ISymbolHistoryService;
  const AReadText: TReferenceReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FService := AService;
  FReadText := AReadText;
end;

class function TMcpHistoryTools.NoVcs(const AReason: string): string;
begin
  Result := cTexts[THistoryToolsText.NoVcs].Fmt([AReason]);
end;

function TMcpHistoryTools.Candidates(const AName: string): TArray<TSymbolLocation>;
var
  mLookup: TMcpIndexTools;
  mLocation: TSymbolLocation;
  mSeen: TDictionary<string, Boolean>;
  mKey: string;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  mLookup := TMcpIndexTools.Create(FIndex, nil);
  try
    for mLocation in mLookup.Matches(AName) do
    begin
      mKey := UpperCase(mLocation.FileName + '|' + mLocation.Symbol.QualifiedName);
      if ((mLocation.Symbol.Kind in cRoutineKinds) or (mLocation.Symbol.Kind in cTypeKinds)) and
        not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        Result := Result + [mLocation];
      end;
    end;
  finally
    mLookup.Free;
    mSeen.Free;
  end;
end;

/// <summary>Trefferliste eines mehrdeutigen Namens als Markdown oder JSON.</summary>
function AmbiguousText(const AName: string; const AFound: TArray<TSymbolLocation>; AJson: Boolean): string;
var
  mEntries: TArray<string>;
  mIndex: Integer;
  mRoot: TJSONObject;
  mList: TJSONArray;
begin
  mEntries := nil;
  for mIndex := 0 to Min(High(AFound), TMcpHistoryTools.cMaxCandidates - 1) do
  begin
    mEntries := mEntries + [Format('%s.%s  %s:%d', [AFound[mIndex].UnitName, AFound[mIndex].Symbol.QualifiedName,
      AFound[mIndex].FileName, AFound[mIndex].Symbol.SelectionRange.StartPos.Line + 1])];
  end;
  if not AJson then
  begin
    Result := cTexts[THistoryToolsText.Ambiguous].Fmt([AName, Length(AFound)]) + #10 + '  ' +
      string.Join(#10'  ', mEntries) + #10 + cTexts[THistoryToolsText.AmbiguousHint].Text;
    Exit;
  end;
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', 'json');
    mRoot.AddPair('ambiguous', AName);
    mList := TJSONArray.Create;
    mRoot.AddPair('candidates', mList);
    for mIndex := 0 to High(mEntries) do
    begin
      mList.Add(mEntries[mIndex]);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function TMcpHistoryTools.SourceText(const AVcs: ISymbolHistoryVcs; const ALocation: TSymbolLocation;
  const APath: string): string;
begin
  if (AVcs.TextAt(APath, '', False, Result) <> THotspotTextState.Found) and
    not (Assigned(FReadText) and FReadText(ALocation.FileName, Result)) then
  begin
    Result := '';
  end;
end;

/// <summary>Bereich der Deklaration des Typs AName in AText, 1-basiert; sonst der Bereich aus dem Index.</summary>
procedure TypeRange(const AText: string; const ALocation: TSymbolLocation; out AFirstLine, ALastLine: Integer);
var
  mSymbol: TIndexSymbol;
begin
  AFirstLine := ALocation.Symbol.Range.StartPos.Line + 1;
  ALastLine := ALocation.Symbol.Range.EndPos.Line + 1;
  for mSymbol in TIndexExtractor.ExtractText(AText, ALocation.FileName, nil).Symbols do
  begin
    if (mSymbol.Kind in cTypeKinds) and SameText(mSymbol.QualifiedName, ALocation.Symbol.QualifiedName) then
    begin
      AFirstLine := mSymbol.Range.StartPos.Line + 1;
      ALastLine := mSymbol.Range.EndPos.Line + 1;
      Exit;
    end;
  end;
end;

function TMcpHistoryTools.RequestFor(const AVcs: ISymbolHistoryVcs; const ALocation: TSymbolLocation;
  const APath: string; const AArgs: TMcpHistoryArgs): TSymbolHistoryRequest;
var
  mText: string;
begin
  Result := Default(TSymbolHistoryRequest);
  Result.Symbol := ALocation.Symbol.QualifiedName;
  Result.Path := APath;
  Result.IsRoutine := ALocation.Symbol.Kind in cRoutineKinds;
  Result.Limit := Max(1, Min(AArgs.Limit, TSymbolHistoryService.cMaxLimit));
  Result.FollowMoves := AArgs.FollowMoves;
  Result.TimeoutMs := AArgs.TimeoutMs;
  Result.Cancelled := AArgs.Cancelled;
  mText := SourceText(AVcs, ALocation, APath);
  if Result.IsRoutine then
  begin
    // Ohne Rumpf (abstract, Interface-Methode, external) die Deklaration.
    if not TSymbolHistoryService.FindRoutine(mText, Result.Symbol, Result.FirstLine, Result.LastLine) then
    begin
      Result.IsRoutine := False;
      Result.FirstLine := ALocation.Symbol.Range.StartPos.Line + 1;
      Result.LastLine := ALocation.Symbol.Range.EndPos.Line + 1;
    end;
  end
  else
  begin
    TypeRange(mText, ALocation, Result.FirstLine, Result.LastLine);
  end;
end;

function TMcpHistoryTools.Run(const AVcs: ISymbolHistoryVcs; const AArgs: TMcpHistoryArgs): string;
var
  mFound: TArray<TSymbolLocation>;
  mPath: string;
  mRequest: TSymbolHistoryRequest;
  mResult: TSymbolHistoryResult;
begin
  mFound := Candidates(AArgs.Name);
  if Length(mFound) = 0 then
  begin
    Exit(cTexts[THistoryToolsText.NoSymbol].Fmt([AArgs.Name]));
  end;
  if Length(mFound) > 1 then
  begin
    Exit(AmbiguousText(AArgs.Name, mFound, AArgs.Json));
  end;
  mPath := TMetricsCollector.RelativePath(AVcs.Root, mFound[0].FileName);
  if mPath = mFound[0].FileName then
  begin
    Exit(cTexts[THistoryToolsText.Outside].Fmt([mFound[0].FileName, AVcs.Root]));
  end;
  mRequest := RequestFor(AVcs, mFound[0], mPath, AArgs);
  mResult := FService.Run(AVcs, mRequest);
  if AArgs.Json then
  begin
    Result := TSymbolHistoryReport.Json(mResult, mRequest.Limit);
  end
  else
  begin
    Result := TSymbolHistoryReport.Markdown(mResult, mRequest.Limit, AArgs.TimeoutMs);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.HistoryTools', cTexts);

end.
