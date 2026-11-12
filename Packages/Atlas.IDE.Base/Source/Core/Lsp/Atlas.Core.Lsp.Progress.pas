unit Atlas.Core.Lsp.Progress;

// Index des Servers im Plugin (#492):
// - TLspProgress: verfolgt $/progress des Servers (begin/report/end) aus dem
//   Lese-Thread; Text liefert dem Hauptthread den aktuellen Stand, z. B.
//   "Index 45 %". Mehrere laufende Vorgänge: der zuletzt gemeldete zählt.
// - TLspIndexStatus: Antwort von atlas.server.status als Zeilen für die
//   Meldungsansicht (Units, Symbole, Indexgröße, letzter Lauf je Ordner) und
//   als Kennzahlen für die Einstellungsseite (Units, Deklarationen, Größe im
//   Speicher und auf der Platte, letzte Aktualisierung).
// - IndexingText: Text für die Statusleiste des Editors, solange der Server
//   indiziert ("Atlas indiziert … (45 %)"); die Vervollständigung zeigt
//   dann "eingeschränkt".
// - OnChanged (#591): nach jeder $/progress-Nachricht, im Lese-Thread; das
//   Atlas-Statusfeld aktualisiert so die Zeile „Index“ ohne Abfrage.
// - ActiveOf (#2142): Stand eines einzelnen Vorgangs über sein Token; die
//   Einrichtung ordnet so jedem Projekt der Gruppe seinen Fortschritt zu.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections;

type
  ILspProgress = interface
    ['{4E7D2B8A-91C3-4F65-B0D2-7A3E5C9F1B24}']
    /// <summary>params einer $/progress-Nachricht übernehmen (Lese-Thread).</summary>
    procedure Handle(const AParams: TJSONValue);
    /// <summary>Kurzer Stand ("Index 45 %"); '' ohne laufenden Vorgang.</summary>
    function Text: string;
    /// <summary>Statusleiste: "Atlas indiziert … (45 %)"; '' ohne laufenden Vorgang.</summary>
    function IndexingText: string;
    /// <summary>Fortschritt in Prozent (-1 = unbekannt) und ob ein Vorgang läuft.</summary>
    function Active(out APercent: Integer): Boolean;
    /// <summary>Läuft der Vorgang AToken? APercent = sein Fortschritt, -1 = unbekannt (#2142).</summary>
    function ActiveOf(const AToken: string; out APercent: Integer): Boolean;
    /// <summary>Beobachter für Änderungen; läuft im Lese-Thread.</summary>
    procedure SetOnChanged(const AProc: TProc);
  end;

  TLspProgress = class(TInterfacedObject, ILspProgress)
  private type
    TEntry = record
      Title: string;
      Percent: Integer;
    end;
  private
    FLock: TCriticalSection;
    FRunning: TDictionary<string, TEntry>;
    FLast: string;
    FOnChanged: TProc;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Handle(const AParams: TJSONValue);
    function Text: string;
    function IndexingText: string;
    function Active(out APercent: Integer): Boolean;
    function ActiveOf(const AToken: string; out APercent: Integer): Boolean;
    procedure SetOnChanged(const AProc: TProc);
    /// <summary>Wie IndexingText aus Prozent (-1 = unbekannt); '' wenn nicht AActive.</summary>
    class function IndexingTextOf(AActive: Boolean; APercent: Integer): string; static;
  end;

  /// <summary>Kennzahlen des Index für die Einstellungsseite (#492).</summary>
  TLspIndexMetrics = record
    Valid: Boolean;
    Units: Integer;
    Declarations: Integer;
    MemoryBytes: Int64;
    BudgetBytes: Int64;
    OffloadedUnits: Integer;
    DiskBytes: Int64;
    /// <summary>Jüngste Aktualisierung aller Ordner (Ortszeit); 0 = keine.</summary>
    LastUpdate: TDateTime;
    /// <summary>Mehrzeiliger Text für die Einstellungsseite.</summary>
    function Text: string;
  end;

  TLspIndexStatus = class
  public
    /// <summary>Zeilen aus der JSON-Antwort von atlas.server.status; leer bei unbekanntem Format.</summary>
    class function Lines(const AStatus: TJSONValue): TArray<string>; static;
    /// <summary>Kennzahlen aus derselben Antwort; Valid = False bei unbekanntem Format.</summary>
    class function Metrics(const AStatus: TJSONValue): TLspIndexMetrics; static;
    /// <summary>Meldung zur Antwort von atlas.server.clearIndex.</summary>
    class function ClearedText(const AAnswer: TJSONValue): string; static;
    /// <summary>Größe für Menschen: "12,3 MB".</summary>
    class function SizeText(ABytes: Int64): string; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TProgressText = (AtlasIsIndexing, AtlasIsIndexing2, FiguresNotAvailableServerNot, UnitsDeclarations, InMemory,
    OfText, UsagesOfUnitsOffloaded, OnDisk, LastUpdate, IndexDeletedItIsBeing, IndexDeletedCachesFreedIt,
    AtlasIndexUnitsSymbolsIn, LastRunMsReadFrom);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TProgressText] of string = (
    ('Atlas indiziert … (%d %%)',
     'Atlas indiziert …',
     'Kennzahlen nicht verfügbar (Server läuft nicht).',
     'Units: %d · Deklarationen: %d',
     'Im Speicher: ',
     ' von ',
     ' (Verwendungen von %d Units ausgelagert)',
     'Auf der Platte: ',
     'Letzte Aktualisierung: ',
     'Index gelöscht; er wird neu aufgebaut.',
     'Index gelöscht: %d Caches, %s frei; er wird neu aufgebaut.',
     'Atlas-Index: %d Units, %d Symbole, %s im Speicher, %s auf der Platte',
     '    %s: letzter Lauf %d ms, %d gelesen, %d aus dem Cache, %d fehlen, Cache %s'),
    ('Atlas is indexing … (%d %%)',
     'Atlas is indexing …',
     'Figures not available (server not running).',
     'Units: %d · declarations: %d',
     'In memory: ',
     ' of ',
     ' (usages of %d units offloaded)',
     'On disk: ',
     'Last update: ',
     'Index deleted; it is being rebuilt.',
     'Index deleted: %d caches, %s freed; it is being rebuilt.',
     'Atlas index: %d units, %d symbols, %s in memory, %s on disk',
     '    %s: last run %d ms, %d read, %d from the cache, %d missing, cache %s'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TProgressText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TLspProgress }

constructor TLspProgress.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRunning := TDictionary<string, TEntry>.Create;
end;

destructor TLspProgress.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

procedure TLspProgress.Handle(const AParams: TJSONValue);
var
  mToken, mKind: string;
  mValue: TJSONValue;
  mEntry: TEntry;
  mChanged: TProc;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mToken := TJSONObject(AParams).GetValue<string>('token', '');
  mValue := TJSONObject(AParams).GetValue('value');
  if not (mValue is TJSONObject) then
  begin
    Exit;
  end;
  mKind := TJSONObject(mValue).GetValue<string>('kind', '');
  FLock.Enter;
  try
    mChanged := FOnChanged;
    if mKind = 'end' then
    begin
      FRunning.Remove(mToken);
      if FLast = mToken then
      begin
        FLast := '';
      end;
    end
    else
    begin
      if not FRunning.TryGetValue(mToken, mEntry) then
      begin
        mEntry.Title := '';
        mEntry.Percent := -1;
      end;
      if TJSONObject(mValue).GetValue('title') <> nil then
      begin
        mEntry.Title := TJSONObject(mValue).GetValue<string>('title', '');
      end;
      if TJSONObject(mValue).GetValue('percentage') <> nil then
      begin
        mEntry.Percent := TJSONObject(mValue).GetValue<Integer>('percentage', -1);
      end;
      FRunning.AddOrSetValue(mToken, mEntry);
      FLast := mToken;
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(mChanged) then
  begin
    mChanged();
  end;
end;

procedure TLspProgress.SetOnChanged(const AProc: TProc);
begin
  FLock.Enter;
  try
    FOnChanged := AProc;
  finally
    FLock.Leave;
  end;
end;

function TLspProgress.Active(out APercent: Integer): Boolean;
var
  mEntry: TEntry;
  mKey: string;
begin
  APercent := -1;
  FLock.Enter;
  try
    mKey := FLast;
    Result := (mKey <> '') and FRunning.TryGetValue(mKey, mEntry);
    if not Result then
    begin
      for mKey in FRunning.Keys do
      begin
        Result := FRunning.TryGetValue(mKey, mEntry);
        Break;
      end;
    end;
    if Result then
    begin
      APercent := mEntry.Percent;
    end;
  finally
    FLock.Leave;
  end;
end;

function TLspProgress.ActiveOf(const AToken: string; out APercent: Integer): Boolean;
var
  mEntry: TEntry;
begin
  APercent := -1;
  FLock.Enter;
  try
    Result := FRunning.TryGetValue(AToken, mEntry);
    if Result then
    begin
      APercent := mEntry.Percent;
    end;
  finally
    FLock.Leave;
  end;
end;

function TLspProgress.Text: string;
var
  mEntry: TEntry;
  mKey, mCandidate: string;
begin
  FLock.Enter;
  try
    Result := '';
    mKey := FLast;
    if (mKey = '') or not FRunning.ContainsKey(mKey) then
    begin
      mKey := '';
      for mCandidate in FRunning.Keys do
      begin
        mKey := mCandidate;
        Break;
      end;
    end;
    if (mKey = '') or not FRunning.TryGetValue(mKey, mEntry) then
    begin
      Exit;
    end;
    Result := mEntry.Title;
    if Result = '' then
    begin
      Result := '…';
    end;
    if mEntry.Percent >= 0 then
    begin
      Result := Format('%s %d %%', [Result, mEntry.Percent]);
    end;
  finally
    FLock.Leave;
  end;
end;

class function TLspProgress.IndexingTextOf(AActive: Boolean; APercent: Integer): string;
begin
  if not AActive then
  begin
    Result := '';
  end
  else if APercent >= 0 then
  begin
    Result := Format(UiText(TProgressText.AtlasIsIndexing), [APercent]);
  end
  else
  begin
    Result := UiText(TProgressText.AtlasIsIndexing2);
  end;
end;

function TLspProgress.IndexingText: string;
var
  mEntry: TEntry;
  mKey: string;
  mActive: Boolean;
begin
  FLock.Enter;
  try
    mKey := FLast;
    mActive := (mKey <> '') and FRunning.TryGetValue(mKey, mEntry);
    if not mActive then
    begin
      for mKey in FRunning.Keys do
      begin
        mActive := FRunning.TryGetValue(mKey, mEntry);
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if mActive then
  begin
    Result := IndexingTextOf(True, mEntry.Percent);
  end
  else
  begin
    Result := '';
  end;
end;

{ TLspIndexMetrics }

function TLspIndexMetrics.Text: string;
begin
  if not Valid then
  begin
    Exit(UiText(TProgressText.FiguresNotAvailableServerNot));
  end;
  Result := Format(UiText(TProgressText.UnitsDeclarations), [Units, Declarations]) + sLineBreak +
    UiText(TProgressText.InMemory) + TLspIndexStatus.SizeText(MemoryBytes);
  if BudgetBytes > 0 then
  begin
    Result := Result + UiText(TProgressText.OfText) + TLspIndexStatus.SizeText(BudgetBytes);
  end;
  if OffloadedUnits > 0 then
  begin
    Result := Result + Format(UiText(TProgressText.UsagesOfUnitsOffloaded), [OffloadedUnits]);
  end;
  Result := Result + sLineBreak + UiText(TProgressText.OnDisk) + TLspIndexStatus.SizeText(DiskBytes) + sLineBreak +
    UiText(TProgressText.LastUpdate);
  if LastUpdate = 0 then
  begin
    Result := Result + '–';
  end
  else
  begin
    Result := Result + FormatDateTime('dd.mm.yyyy hh":"nn":"ss', LastUpdate);
  end;
end;

{ TLspIndexStatus }

class function TLspIndexStatus.SizeText(ABytes: Int64): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  mSettings.DecimalSeparator := ',';
  if ABytes < 1024 * 1024 then
  begin
    Result := FormatFloat('0.0', ABytes / 1024, mSettings) + ' KB';
  end
  else
  begin
    Result := FormatFloat('0.0', ABytes / (1024 * 1024), mSettings) + ' MB';
  end;
end;

function LocalTimeOf(const AText: string): TDateTime;
begin
  Result := 0;
  if AText = '' then
  begin
    Exit;
  end;
  try
    Result := ISO8601ToDate(AText, False);
  except
    on Exception do
      Result := 0;
  end;
end;

class function TLspIndexStatus.Metrics(const AStatus: TJSONValue): TLspIndexMetrics;
var
  mStatus: TJSONObject;
  mWorkspaces, mItem: TJSONValue;
  mUpdate: TDateTime;
begin
  Result := Default(TLspIndexMetrics);
  if not (AStatus is TJSONObject) then
  begin
    Exit;
  end;
  mStatus := TJSONObject(AStatus);
  if mStatus.GetValue('units') = nil then
  begin
    Exit;
  end;
  Result.Valid := True;
  Result.Units := mStatus.GetValue<Integer>('units', 0);
  Result.Declarations := mStatus.GetValue<Integer>('symbols', 0);
  Result.MemoryBytes := mStatus.GetValue<Int64>('indexBytes', 0);
  Result.BudgetBytes := mStatus.GetValue<Int64>('budgetBytes', 0);
  Result.OffloadedUnits := mStatus.GetValue<Integer>('offloadedUnits', 0);
  Result.DiskBytes := mStatus.GetValue<Int64>('diskBytes', 0);
  mWorkspaces := mStatus.GetValue('workspaces');
  if mWorkspaces is TJSONArray then
  begin
    for mItem in TJSONArray(mWorkspaces) do
    begin
      if mItem is TJSONObject then
      begin
        mUpdate := LocalTimeOf(TJSONObject(mItem).GetValue<string>('lastUpdate', ''));
        if mUpdate > Result.LastUpdate then
        begin
          Result.LastUpdate := mUpdate;
        end;
      end;
    end;
  end;
end;

class function TLspIndexStatus.ClearedText(const AAnswer: TJSONValue): string;
begin
  if not (AAnswer is TJSONObject) then
  begin
    Exit(UiText(TProgressText.IndexDeletedItIsBeing));
  end;
  Result := Format(UiText(TProgressText.IndexDeletedCachesFreedIt),
    [TJSONObject(AAnswer).GetValue<Integer>('removed', 0),
     SizeText(TJSONObject(AAnswer).GetValue<Int64>('freedBytes', 0))]);
end;

class function TLspIndexStatus.Lines(const AStatus: TJSONValue): TArray<string>;
var
  mStatus: TJSONObject;
  mWorkspaces: TJSONValue;
  mItem: TJSONValue;
  mBytes: Int64;
begin
  Result := nil;
  if not (AStatus is TJSONObject) then
  begin
    Exit;
  end;
  mStatus := TJSONObject(AStatus);
  mBytes := mStatus.GetValue<Int64>('indexBytes', 0);
  // Beide Größen wie SizeText mit Dezimalkomma, unabhängig vom Gebietsschema.
  Result := Result + [Format(UiText(TProgressText.AtlasIndexUnitsSymbolsIn),
    [mStatus.GetValue<Integer>('units', 0), mStatus.GetValue<Integer>('symbols', 0), SizeText(mBytes),
     SizeText(mStatus.GetValue<Int64>('diskBytes', 0))])];
  mWorkspaces := mStatus.GetValue('workspaces');
  if mWorkspaces is TJSONArray then
  begin
    for mItem in TJSONArray(mWorkspaces) do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [Format(UiText(TProgressText.LastRunMsReadFrom),
          [TJSONObject(mItem).GetValue<string>('name', ''), TJSONObject(mItem).GetValue<Integer>('lastIndexMs', 0),
          TJSONObject(mItem).GetValue<Integer>('parsed', 0), TJSONObject(mItem).GetValue<Integer>('fromCache', 0),
          TJSONObject(mItem).GetValue<Integer>('missing', 0),
          SizeText(TJSONObject(mItem).GetValue<Int64>('cacheBytes', 0) +
            TJSONObject(mItem).GetValue<Int64>('libraryCacheBytes', 0))])];
      end;
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.Progress', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
