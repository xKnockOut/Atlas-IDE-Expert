unit Atlas.Common.Lsp.Internals.FormCache;

// Auszüge aus Formulardateien für die Vervollständigung (Code-Review P-06): Komponentennamen (#455) und
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
    MaxEntries = 16;
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
  Child: TDfmObject;
  Component: TFormSnapshotComponent;
begin
  for Child in AObject.Children do
  begin
    if (Child.Kind = TDfmObjectKind.Item) or (Child.Name = '') or (Child.TypeName = '') then
      Continue;
    Component.Name := Child.Name;
    Component.TypeName := Child.TypeName;
    AList.Add(Component);
    if Child.Kind <> TDfmObjectKind.Inline_ then
      CollectComponents(Child, AList);
  end;
end;

/// <summary>Ereigniszuweisungen von AObject und allen Objekten darunter, auch in Frames.</summary>
procedure CollectHandlers(AObject: TDfmObject; var AObjectIndex: Integer; AList: TList<TFormSnapshotHandler>);
var
  Child: TDfmObject;
  Prop: TDfmProperty;
  Handler: TFormSnapshotHandler;
  Own: Integer;
begin
  Own := AObjectIndex;
  Inc(AObjectIndex);
  for Prop in AObject.Properties do
    if Prop.IsEvent then
    begin
      Handler.ObjectIndex := Own;
      Handler.ObjectName := AObject.Name;
      Handler.TypeName := AObject.TypeName;
      Handler.MethodName := Prop.Value;
      AList.Add(Handler);
    end;
  for Child in AObject.Children do
    CollectHandlers(Child, AObjectIndex, AList);
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
  Index: Integer;
begin
  Index := FOrder.IndexOf(AKey);
  if Index >= 0 then
    FOrder.Delete(Index);
  FOrder.Add(AKey);
end;

function TFormSnapshotCache.TryGet(const AFormFile, AStamp: string; out ASnapshot: TFormSnapshot): Boolean;
var
  Key: string;
  Entry: TEntry;
begin
  ASnapshot := Default(TFormSnapshot);
  Key := AnsiUpperCase(AFormFile);
  TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(Key, Entry) and (Entry.Stamp = AStamp);
    if Result then
    begin
      ASnapshot := Entry.Snapshot;
      Touch(Key);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TFormSnapshotCache.Put(const AFormFile, AStamp: string; const ASnapshot: TFormSnapshot);
var
  Key: string;
  Entry: TEntry;
begin
  Key := AnsiUpperCase(AFormFile);
  Entry.Stamp := AStamp;
  Entry.Snapshot := ASnapshot;
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(Key, Entry);
    Touch(Key);
    while FOrder.Count > MaxEntries do
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
  Components: TList<TFormSnapshotComponent>;
  Handlers: TList<TFormSnapshotHandler>;
  ObjectIndex: Integer;
begin
  Result := Default(TFormSnapshot);
  Result.FormFile := AFormFile;
  if (ADocument = nil) or (ADocument.Root = nil) then
    Exit;
  Result.RootName := ADocument.Root.Name;
  Result.RootType := ADocument.Root.TypeName;
  Components := TList<TFormSnapshotComponent>.Create;
  Handlers := TList<TFormSnapshotHandler>.Create;
  try
    CollectComponents(ADocument.Root, Components);
    ObjectIndex := 0;
    CollectHandlers(ADocument.Root, ObjectIndex, Handlers);
    Result.Components := Components.ToArray;
    Result.Handlers := Handlers.ToArray;
  finally
    Handlers.Free;
    Components.Free;
  end;
end;

end.
