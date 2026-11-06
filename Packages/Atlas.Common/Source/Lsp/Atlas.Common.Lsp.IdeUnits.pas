unit Atlas.Common.Lsp.IdeUnits;

// Ersatz-Units für Units, die die IDE als Package geladen hat, deren Quelltext Atlas aber nicht findet. Ablauf:
// - Ist der Index aufgebaut (oder kommen neue Typen über atlas/ideTypes), fragt der Server mit
//   atlas/ideMembersWanted {"units": [...]} nach den Units des Typkatalogs, die nicht im Index stehen.
// - Das Plugin antwortet mit atlas/ideMembers {"units": [{"unit": ..., "types": [...]}]} (Format in
//   Atlas.Common.Lsp.IdeUnits.Source).
// - TIdeUnits erzeugt daraus je Unit einen Pascal-Text unter dem Pfad "atlas-ide:<Unit>.pas", liest ihn wie
//   jede Unit ein und hält ihn in einem eigenen Index.
// Den gemeinsamen Index berührt das nicht: Prüfregeln, Referenzen und Umbenennen sehen die Ersatz-Units nie.
// Hover, Vervollständigung und Parameterhilfe bekommen sie über TIdeIndex (Atlas.Common.Lsp.IdeIndex).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Index.Contract;

type
  TIdeMembersEvent = reference to procedure(ACount: Integer);

  /// <summary>Ersatz-Units aus atlas/ideMembers; threadsicher.</summary>
  TIdeUnits = class
  public const
    WantedMethod = 'atlas/ideMembersWanted';
    Method = 'atlas/ideMembers';
    /// <summary>Anfang der Pfade der Ersatz-Units.</summary>
    PathPrefix = 'atlas-ide:';
  private
    FLock: TObject;
    FIndex: ISymbolIndex;
    // Pfad (groß) → Text der Ersatz-Unit.
    FTexts: TDictionary<string, string>;
    // Units (groß), nach denen schon gefragt wurde.
    FRequested: TDictionary<string, Boolean>;
    FOnChanged: TIdeMembersEvent;
    procedure HandleNotification(const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Pfad der Ersatz-Unit AUnit.</summary>
    class function PathOf(const AUnit: string): string; static;
    /// <summary>Gehört AFileName zu einer Ersatz-Unit?</summary>
    class function IsIdePath(const AFileName: string): Boolean; static;
    /// <summary>Units aus ACandidates, die weder AIndex noch die Ersatz-Units kennen und nach denen noch nicht
    /// gefragt wurde; sie gelten danach als gefragt.</summary>
    function Wanted(const ACandidates: TArray<string>; const AIndex: ISymbolIndex): TArray<string>;
    /// <summary>Nimmt die Units aus AParams (atlas/ideMembers) auf; Ergebnis: Zahl der Units.</summary>
    function Add(const AParams: TJSONValue): Integer;
    /// <summary>Text der Ersatz-Unit unter AFileName; False für andere Pfade.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Index nur mit den Ersatz-Units.</summary>
    property Index: ISymbolIndex read FIndex;
    /// <summary>Nach jeder Meldung mit der Zahl der aufgenommenen Units (Thread des Dispatchers).</summary>
    property OnChanged: TIdeMembersEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.IdeUnits.Source;

constructor TIdeUnits.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FIndex := TSymbolIndex.Create;
  FTexts := TDictionary<string, string>.Create;
  FRequested := TDictionary<string, Boolean>.Create;
end;

destructor TIdeUnits.Destroy;
begin
  FRequested.Free;
  FTexts.Free;
  FIndex := nil;
  FLock.Free;
  inherited Destroy;
end;

procedure TIdeUnits.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(Method, HandleNotification);
end;

procedure TIdeUnits.HandleNotification(const AParams: TJSONValue);
var
  mCount: Integer;
begin
  mCount := Add(AParams);
  if Assigned(FOnChanged) then
  begin
    FOnChanged(mCount);
  end;
end;

class function TIdeUnits.PathOf(const AUnit: string): string;
begin
  Result := PathPrefix + AUnit + '.pas';
end;

class function TIdeUnits.IsIdePath(const AFileName: string): Boolean;
begin
  Result := AFileName.StartsWith(PathPrefix, True);
end;

function TIdeUnits.Wanted(const ACandidates: TArray<string>; const AIndex: ISymbolIndex): TArray<string>;
var
  mUnit, mKey: string;
  mFound: TUnitIndex;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mUnit in ACandidates do
    begin
      mKey := UpperCase(mUnit);
      if (mUnit = '') or FRequested.ContainsKey(mKey) or FIndex.FindUnit(mUnit, mFound) or
        ((AIndex <> nil) and AIndex.FindUnit(mUnit, mFound)) then
      begin
        Continue;
      end;
      FRequested.Add(mKey, True);
      Result := Result + [mUnit];
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TIdeUnits.Add(const AParams: TJSONValue): Integer;
var
  mUnits: TJSONArray;
  mValue: TJSONValue;
  mItem: TJSONObject;
  mName, mPath, mText: string;
  mIndexed: TUnitIndex;
begin
  Result := 0;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('units', mUnits)) then
  begin
    Exit;
  end;
  for mValue in mUnits do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    mName := Trim(mItem.GetValue<string>('unit', ''));
    if mName = '' then
    begin
      Continue;
    end;
    mPath := PathOf(mName);
    mText := TIdeUnitSource.Build(mName, mItem.GetValue<TJSONArray>('types', nil));
    // Außerhalb der Sperre lesen; der Index hat seine eigene.
    mIndexed := TIndexExtractor.ExtractText(mText, mPath, nil);
    mIndexed.Library_ := True;
    System.TMonitor.Enter(FLock);
    try
      FTexts.AddOrSetValue(UpperCase(mPath), mText);
    finally
      System.TMonitor.Exit(FLock);
    end;
    FIndex.AddUnit(mIndexed);
    Inc(Result);
  end;
end;

function TIdeUnits.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  if not IsIdePath(AFileName) then
  begin
    Exit(False);
  end;
  System.TMonitor.Enter(FLock);
  try
    Result := FTexts.TryGetValue(UpperCase(AFileName), AText);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
