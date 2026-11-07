unit Atlas.Common.Lsp.IdeTypes;

// Typen aus der laufenden IDE. Die Delphi-IDE lädt jedes installierte Package als BPL in ihren Prozess; deren
// Typen samt Unit kennt sie über die RTTI, Komponenten zusätzlich über RegisterComponents. Das gilt auch für
// Packages, die nur als BPL/DCP/DCU ausgeliefert sind und deren .pas fehlt oder nicht zur installierten Fassung
// passt. Das IDE-Plugin meldet diese Typen nach initialize als atlas/ideTypes:
//   {"units": [{"unit": "Vendor.Grid", "types": [{"name": "TVendorGrid", "parent": "Vcl.Controls.TCustomControl"},
//     "TVendorKind", ...]}, ...]}
// Ein Typ ist ein Name oder ein Objekt mit Namen und, bei Klassen, dem direkten Vorfahren samt Unit (parent).
// Jede Meldung ersetzt den ganzen Stand. TIdeTypeCatalog hält ihn threadsicher und beantwortet für die
// Prüfregeln (IRuleIdeTypes) und die Vervollständigung, in welchen Units die IDE einen Typ kennt. Ohne Plugin
// (Linter, MCP) bleibt der Katalog leer.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Ein Typ, den die IDE kennt, mit seiner Unit.</summary>
  TIdeTypeEntry = record
    Name: string;
    UnitName: string;
    /// <summary>Direkter Vorfahr einer Klasse mit Unit (Vcl.Controls.TCustomControl); '' ohne Angabe.</summary>
    Parent: string;
  end;

  /// <summary>Typen der laufenden IDE; threadsicher. Inhalt ersetzt Replace.</summary>
  TIdeTypeCatalog = class(TInterfacedObject, IRuleIdeTypes)
  private
    FLock: TObject;
    // Typname (groß) → Units, in denen die IDE ihn kennt.
    FUnits: TDictionary<string, TArray<string>>;
    FEntries: TArray<TIdeTypeEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    { IRuleIdeTypes }
    function UnitsOf(const ATypeName: string): TArray<string>;
    /// <summary>Ersetzt den Stand durch die Einträge aus AParams (Format oben); Einträge ohne Unit oder Namen,
    /// generische Instanzen (mit &lt;) und Namen mit Punkt entfallen. Ergebnis: Zahl der Typen.</summary>
    function Replace(const AParams: TJSONValue): Integer;
    /// <summary>Alle Typen mit Unit, in der Reihenfolge der Meldung (geteilter Schnappschuss, nur lesen).</summary>
    function Entries: TArray<TIdeTypeEntry>;
    function Count: Integer;
    /// <summary>Einträge aus AParams ohne Doppelte; nil bei ungültigen Parametern.</summary>
    class function Parse(const AParams: TJSONValue): TArray<TIdeTypeEntry>; static;
  end;

  TIdeTypesChangedEvent = reference to procedure(ACount: Integer);

  /// <summary>Nimmt atlas/ideTypes an und hält den Katalog.</summary>
  TLspIdeTypes = class
  public const
    cMethod = 'atlas/ideTypes';
  private
    FCatalog: TIdeTypeCatalog;
    // Hält FCatalog am Leben, solange Regeldienste ihn über IRuleIdeTypes teilen.
    FCatalogRef: IRuleIdeTypes;
    FOnChanged: TIdeTypesChangedEvent;
    procedure HandleNotification(const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    property Catalog: TIdeTypeCatalog read FCatalog;
    /// <summary>Nach jeder Meldung mit der neuen Zahl der Typen (Thread des Dispatchers).</summary>
    property OnChanged: TIdeTypesChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

/// <summary>Taugt AName als Typname ohne Unit-Präfix?</summary>
function UsableName(const AName: string): Boolean;
begin
  // Nur Bezeichner: kein Punkt, keine generische Instanz, keine Zahl (TJSONNumber erbt von TJSONString).
  Result := IsValidIdent(AName);
end;

/// <summary>Typ aus einem Element von "types": Name oder {"name": …, "parent": …}.</summary>
function EntryOf(AValue: TJSONValue; const AUnit: string): TIdeTypeEntry;
var
  mObject: TJSONObject;
begin
  Result := Default(TIdeTypeEntry);
  Result.UnitName := AUnit;
  if AValue is TJSONString then
  begin
    Result.Name := Trim(AValue.Value);
  end
  else if AValue is TJSONObject then
  begin
    mObject := TJSONObject(AValue);
    Result.Name := Trim(mObject.GetValue<string>('name', ''));
    Result.Parent := Trim(mObject.GetValue<string>('parent', ''));
  end;
end;

/// <summary>Typen eines Eintrags {"unit": …, "types": […]} an AResult anhängen, ohne Doppelte (ASeen).</summary>
procedure AddUnitEntries(AItem: TJSONObject; ASeen: TDictionary<string, Boolean>;
  var AResult: TArray<TIdeTypeEntry>);
var
  mUnit: string;
  mTypes: TJSONArray;
  mValue: TJSONValue;
  mEntry: TIdeTypeEntry;
  mKey: string;
begin
  if not (AItem.TryGetValue<string>('unit', mUnit) and AItem.TryGetValue<TJSONArray>('types', mTypes)) then
  begin
    Exit;
  end;
  mUnit := Trim(mUnit);
  if mUnit = '' then
  begin
    Exit;
  end;
  for mValue in mTypes do
  begin
    mEntry := EntryOf(mValue, mUnit);
    mKey := UpperCase(mUnit + '|' + mEntry.Name);
    if UsableName(mEntry.Name) and not ASeen.ContainsKey(mKey) then
    begin
      ASeen.Add(mKey, True);
      AResult := AResult + [mEntry];
    end;
  end;
end;

{ TIdeTypeCatalog }

constructor TIdeTypeCatalog.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FUnits := TDictionary<string, TArray<string>>.Create;
end;

destructor TIdeTypeCatalog.Destroy;
begin
  FUnits.Free;
  FLock.Free;
  inherited Destroy;
end;

class function TIdeTypeCatalog.Parse(const AParams: TJSONValue): TArray<TIdeTypeEntry>;
var
  mUnits: TJSONArray;
  mItem: TJSONValue;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('units', mUnits)) then
  begin
    Exit;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mItem in mUnits do
    begin
      if mItem is TJSONObject then
      begin
        AddUnitEntries(TJSONObject(mItem), mSeen, Result);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TIdeTypeCatalog.Replace(const AParams: TJSONValue): Integer;
var
  mEntries: TArray<TIdeTypeEntry>;
  mUnits: TDictionary<string, TArray<string>>;
  mEntry: TIdeTypeEntry;
  mKnown: TArray<string>;
begin
  mEntries := Parse(AParams);
  // Außerhalb der Sperre aufbauen, dann tauschen: Prüfregeln lesen jederzeit.
  mUnits := TDictionary<string, TArray<string>>.Create;
  for mEntry in mEntries do
  begin
    if not mUnits.TryGetValue(UpperCase(mEntry.Name), mKnown) then
    begin
      mKnown := nil;
    end;
    mUnits.AddOrSetValue(UpperCase(mEntry.Name), mKnown + [mEntry.UnitName]);
  end;
  System.TMonitor.Enter(FLock);
  try
    FUnits.Free;
    FUnits := mUnits;
    FEntries := mEntries;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := Length(mEntries);
end;

function TIdeTypeCatalog.UnitsOf(const ATypeName: string): TArray<string>;
begin
  System.TMonitor.Enter(FLock);
  try
    if not FUnits.TryGetValue(UpperCase(ATypeName), Result) then
    begin
      Result := nil;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TIdeTypeCatalog.Entries: TArray<TIdeTypeEntry>;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEntries;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TIdeTypeCatalog.Count: Integer;
begin
  Result := Length(Entries);
end;

{ TLspIdeTypes }

constructor TLspIdeTypes.Create;
begin
  inherited Create;
  FCatalog := TIdeTypeCatalog.Create;
  FCatalogRef := FCatalog;
end;

destructor TLspIdeTypes.Destroy;
begin
  FCatalog := nil;
  FCatalogRef := nil;
  inherited Destroy;
end;

procedure TLspIdeTypes.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(cMethod, HandleNotification);
end;

procedure TLspIdeTypes.HandleNotification(const AParams: TJSONValue);
var
  mCount: Integer;
begin
  mCount := FCatalog.Replace(AParams);
  if Assigned(FOnChanged) then
  begin
    FOnChanged(mCount);
  end;
end;

end.
