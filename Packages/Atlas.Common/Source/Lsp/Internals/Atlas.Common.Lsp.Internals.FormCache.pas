unit Atlas.Common.Lsp.Internals.FormCache;

// Auszüge aus Formulardateien für die Vervollständigung: Komponentennamen (#455) und
// Ereigniszuweisungen (#480). Vorher las und zerlegte jede Anfrage in einer Formular-Unit die .dfm neu,
// auch außerhalb der Methoden der Formularklasse. Der Zwischenspeicher hält je Formulardatei einen
// unveränderlichen Auszug (nur Records mit Strings, kein Objektbaum) zusammen mit dem Stand, aus dem er
// stammt; jeder Zugriff vergleicht den Stand, daher braucht es keinen Ablauf. Die Vervollständigung läuft
// nebenläufig: Alle Zugriffe laufen unter einer Sperre.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Dfm.Contract;

type
  /// <summary>Benannte Komponente des Formulars (wie Felder der Formularklasse).</summary>
  TFormSnapshotComponent = record
    Name: string;
    TypeName: string;
  end;

  /// <summary>Ereigniszuweisung "OnClick = Button1Click" eines Objekts im Formular.</summary>
  TFormSnapshotHandler = record
    /// <summary>Fortlaufende Nummer des Objekts im Formular (Wurzel = 0); unterscheidet Objekte ohne Namen.</summary>
    ObjectIndex: Integer;
    ObjectName: string;
    TypeName: string;
    MethodName: string;
  end;

  /// <summary>Unveränderlicher Auszug einer Formulardatei.</summary>
  TFormSnapshot = record
    FormFile: string;
    RootName: string;
    RootType: string;
    /// <summary>Benannte Komponenten ohne Collection-Einträge; in Frames nur der Frame selbst.</summary>
    Components: TArray<TFormSnapshotComponent>;
    /// <summary>Alle Ereigniszuweisungen, in der Reihenfolge der Objekte und ihrer Eigenschaften.</summary>
    Handlers: TArray<TFormSnapshotHandler>;
  end;

  /// <summary>Zuletzt benutzte Auszüge je Formulardatei; threadsicher.</summary>
  TFormSnapshotCache = class
  public const
    cMaxEntries = 16;
  private type
    TEntry = record
      Stamp: string;
      Snapshot: TFormSnapshot;
    end;
  private
    FLock: TObject;
    // Schlüssel AnsiUpperCase(Formulardatei).
    FEntries: TDictionary<string, TEntry>;
    // Schlüssel, zuletzt benutzter am Ende; für die Obergrenze.
    FOrder: TList<string>;
    procedure Touch(const AKey: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Auszug für AFormFile, wenn er aus dem Stand AStamp stammt. Stand z. B. "v&lt;Version&gt;" für
    /// offene Dokumente, "t&lt;Dateizeit&gt;" für Dateien auf der Platte.</summary>
    function TryGet(const AFormFile, AStamp: string; out ASnapshot: TFormSnapshot): Boolean;
    /// <summary>Merkt sich den Auszug; über MaxEntries fällt der am längsten nicht benutzte heraus.</summary>
    procedure Put(const AFormFile, AStamp: string; const ASnapshot: TFormSnapshot);
    function Count: Integer;
    /// <summary>Auszug aus einem zerlegten Formular; ADocument.Root darf nicht nil sein.</summary>
    class function FromDocument(const AFormFile: string; ADocument: TDfmDocument): TFormSnapshot; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Benannte Komponenten unter AObject; in Frames (inline) nur der Frame selbst, seine Komponenten
/// sind keine Felder des Formulars.</summary>
procedure CollectComponents(AObject: TDfmObject; AList: TList<TFormSnapshotComponent>);
var
  mChild: TDfmObject;
  mComponent: TFormSnapshotComponent;
begin
  for mChild in AObject.Children do
  begin
    if (mChild.Kind = TDfmObjectKind.Item) or (mChild.Name = '') or (mChild.TypeName = '') then
    begin
      Continue;
    end;
    mComponent.Name := mChild.Name;
    mComponent.TypeName := mChild.TypeName;
    AList.Add(mComponent);
    if mChild.Kind <> TDfmObjectKind.Inline_ then
    begin
      CollectComponents(mChild, AList);
    end;
  end;
end;

/// <summary>Ereigniszuweisungen von AObject und allen Objekten darunter, auch in Frames.</summary>
procedure CollectHandlers(AObject: TDfmObject; var AObjectIndex: Integer; AList: TList<TFormSnapshotHandler>);
var
  mChild: TDfmObject;
  mProp: TDfmProperty;
  mHandler: TFormSnapshotHandler;
  mOwn: Integer;
begin
  mOwn := AObjectIndex;
  Inc(AObjectIndex);
  for mProp in AObject.Properties do
  begin
    if mProp.IsEvent then
    begin
      mHandler.ObjectIndex := mOwn;
      mHandler.ObjectName := AObject.Name;
      mHandler.TypeName := AObject.TypeName;
      mHandler.MethodName := mProp.Value;
      AList.Add(mHandler);
    end;
  end;
  for mChild in AObject.Children do
  begin
    CollectHandlers(mChild, AObjectIndex, AList);
  end;
end;

{ TFormSnapshotCache }

constructor TFormSnapshotCache.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FOrder := TList<string>.Create;
end;

destructor TFormSnapshotCache.Destroy;
begin
  FOrder.Free;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

procedure TFormSnapshotCache.Touch(const AKey: string);
var
  mIndex: Integer;
begin
  mIndex := FOrder.IndexOf(AKey);
  if mIndex >= 0 then
  begin
    FOrder.Delete(mIndex);
  end;
  FOrder.Add(AKey);
end;

function TFormSnapshotCache.TryGet(const AFormFile, AStamp: string; out ASnapshot: TFormSnapshot): Boolean;
var
  mKey: string;
  mEntry: TEntry;
begin
  ASnapshot := Default(TFormSnapshot);
  mKey := AnsiUpperCase(AFormFile);
  TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(mKey, mEntry) and (mEntry.Stamp = AStamp);
    if Result then
    begin
      ASnapshot := mEntry.Snapshot;
      Touch(mKey);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TFormSnapshotCache.Put(const AFormFile, AStamp: string; const ASnapshot: TFormSnapshot);
var
  mKey: string;
  mEntry: TEntry;
begin
  mKey := AnsiUpperCase(AFormFile);
  mEntry.Stamp := AStamp;
  mEntry.Snapshot := ASnapshot;
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(mKey, mEntry);
    Touch(mKey);
    while FOrder.Count > cMaxEntries do
    begin
      FEntries.Remove(FOrder[0]);
      FOrder.Delete(0);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TFormSnapshotCache.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TFormSnapshotCache.FromDocument(const AFormFile: string; ADocument: TDfmDocument): TFormSnapshot;
var
  mComponents: TList<TFormSnapshotComponent>;
  mHandlers: TList<TFormSnapshotHandler>;
  mObjectIndex: Integer;
begin
  Result := Default(TFormSnapshot);
  Result.FormFile := AFormFile;
  if (ADocument = nil) or (ADocument.Root = nil) then
  begin
    Exit;
  end;
  Result.RootName := ADocument.Root.Name;
  Result.RootType := ADocument.Root.TypeName;
  mComponents := TList<TFormSnapshotComponent>.Create;
  mHandlers := TList<TFormSnapshotHandler>.Create;
  try
    CollectComponents(ADocument.Root, mComponents);
    mObjectIndex := 0;
    CollectHandlers(ADocument.Root, mObjectIndex, mHandlers);
    Result.Components := mComponents.ToArray;
    Result.Handlers := mHandlers.ToArray;
  finally
    mHandlers.Free;
    mComponents.Free;
  end;
end;

end.
