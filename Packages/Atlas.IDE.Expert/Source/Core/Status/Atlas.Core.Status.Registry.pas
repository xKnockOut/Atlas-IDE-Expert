unit Atlas.Core.Status.Registry;

// Registry und Zeilen des Atlas-Statusfelds (#591), ohne VCL:
// - TAtlasStatusRegistry: threadsichere Liste der Zeilen, sortiert nach
//   Order und Kennung, mit Beobachtern für Änderungen. Default ist die
//   Registry des Plugins; Tests legen eigene an.
// - TAtlasStatusLine: einfache Zeile mit Text, Kurztext, Zustand und optionaler
//   Aktion, dazu Kurzform und Zusatz für die Zustandskachel (#754,
//   IAtlasStatusBrief); Update meldet nur echte Änderungen an die Registry.
// - TAtlasStatusSummary: was das Feld zeigt: sichtbare Zeilen (ohne
//   statusField.hidden), Gesamtzustand (der schlechteste aller Zeilen), Text
//   „Atlas“ bzw. „Atlas · 2 Fehler“ und Tooltip mit den Zeilen, die nicht grün sind.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Status.Contract;

type
  TAtlasStatusRegistry = class(TInterfacedObject, IAtlasStatusRegistry)
  private
    FLock: TCriticalSection;
    FItems: TList<IAtlasStatusItem>;
    FListeners: TDictionary<Integer, TProc>;
    FNextListener: Integer;
    FVersion: Integer;
    class var FDefault: IAtlasStatusRegistry;
    function IndexOf(const AId: string): Integer;
    procedure Notify;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AItem: IAtlasStatusItem);
    procedure Remove(const AId: string);
    function Find(const AId: string): IAtlasStatusItem;
    function Items: TArray<IAtlasStatusItem>;
    procedure Changed;
    function Version: Integer;
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
    /// <summary>Registry des Plugins; andere Funktionen melden hier ihre Zeile an.</summary>
    class function Default: IAtlasStatusRegistry; static;
    /// <summary>Gibt die Registry des Plugins frei (Entladen).</summary>
    class procedure ReleaseDefault; static;
  end;

  /// <summary>Zeile mit festen Daten, die der Besitzer über Update setzt. Die Registry hält die Zeile;
  /// die Zeile kennt die Registry nur schwach und muss vor ihr abgemeldet werden.</summary>
  TAtlasStatusLine = class(TInterfacedObject, IAtlasStatusItem, IAtlasStatusBrief)
  private
    FLock: TCriticalSection;
    FId: string;
    FOrder: Integer;
    FText: string;
    FSummary: string;
    FBrief: string;
    FDetail: string;
    FState: TAtlasStatusState;
    FAction: TProc;
    FEnabled: TFunc<Boolean>;
    FRegistry: Pointer;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer); overload;
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
      const AAction: TProc); overload;
    /// <summary>Mit Aktion, die nur gilt, solange AEnabled True liefert (Einstellung, z. B. server.statusWindow
    /// #1356); sonst ist die Zeile nicht anklickbar.</summary>
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
      const AAction: TProc; const AEnabled: TFunc<Boolean>); overload;
    destructor Destroy; override;
    function Id: string;
    function Text: string;
    function Summary: string;
    function State: TAtlasStatusState;
    function Order: Integer;
    function HasAction: Boolean;
    procedure Execute;
    { IAtlasStatusBrief }
    function Brief: string;
    function Detail: string;
    /// <summary>Setzt den Inhalt; meldet Changed nur, wenn sich etwas ändert. Aus jedem Thread. Ohne ABrief und
    /// ADetail sind beide leer (die Kachel zeigt dann AText).</summary>
    procedure Update(const AText: string; AState: TAtlasStatusState); overload;
    procedure Update(const AText: string; AState: TAtlasStatusState; const ASummary: string); overload;
    /// <summary>Mit Kurzform und Zusatz rechts für die Zustandskachel (#754).</summary>
    procedure Update(const AText: string; AState: TAtlasStatusState; const ASummary, ABrief,
      ADetail: string); overload;
    /// <summary>Löst die Verbindung zur Registry; danach meldet Update nichts mehr.</summary>
    procedure Detach;
  end;

  TAtlasStatusSummary = class
  public const
    FieldCaption = 'Atlas';
    Separator = ' · ';
  public
    /// <summary>AItems ohne die Kennungen in AHidden (ohne Groß-/Kleinschreibung).</summary>
    class function Visible(const AItems: TArray<IAtlasStatusItem>;
      const AHidden: TArray<string>): TArray<IAtlasStatusItem>; static;
    /// <summary>Schlechtester Zustand aller Zeilen; Neutral ohne Zeilen.</summary>
    class function Overall(const AItems: TArray<IAtlasStatusItem>): TAtlasStatusState; static;
    /// <summary>Wichtigste Zeile: schlechtester Zustand, dann Reihenfolge; nil ohne Zeilen.</summary>
    class function Leading(const AItems: TArray<IAtlasStatusItem>): IAtlasStatusItem; static;
    /// <summary>„Atlas“, mit AShowSummary und gelber oder roter wichtigster Zeile mit Kurztext
    /// „Atlas · Kurztext“.</summary>
    class function FieldText(const AItems: TArray<IAtlasStatusItem>; AShowSummary: Boolean): string; overload; static;
    /// <summary>Wie oben; dazu immer der Kurztext der gelben oder roten Zeile AAlwaysId (Fortschritt des
    /// Symbol-Index), auch ohne AShowSummary und wenn eine andere Zeile wichtiger ist:
    /// „Atlas · Server langsam · Index 45 %“.</summary>
    class function FieldText(const AItems: TArray<IAtlasStatusItem>; AShowSummary: Boolean;
      const AAlwaysId: string): string; overload; static;
    /// <summary>Zeilen, die nicht grün sind, eine je Zeile; ohne solche „Atlas: alles in Ordnung“.</summary>
    class function Tooltip(const AItems: TArray<IAtlasStatusItem>): string; static;
    /// <summary>Kennungen aus einem Text mit Komma, Semikolon oder Leerzeichen.</summary>
    class function ParseIds(const AText: string): TArray<string>; static;
    /// <summary>Kennungen durch Komma und Leerzeichen getrennt.</summary>
    class function JoinIds(const AIds: TArray<string>): string; static;
    class function StateName(AState: TAtlasStatusState): string; static;
  end;

implementation

{ TAtlasStatusRegistry }

constructor TAtlasStatusRegistry.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TList<IAtlasStatusItem>.Create;
  FListeners := TDictionary<Integer, TProc>.Create;
end;

destructor TAtlasStatusRegistry.Destroy;
begin
  FListeners.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasStatusRegistry.Default: IAtlasStatusRegistry;
begin
  if FDefault = nil then
    FDefault := TAtlasStatusRegistry.Create;
  Result := FDefault;
end;

class procedure TAtlasStatusRegistry.ReleaseDefault;
begin
  FDefault := nil;
end;

function TAtlasStatusRegistry.IndexOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    if SameText(FItems[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

function Comes(const ALeft, ARight: IAtlasStatusItem): Boolean;
begin
  if ALeft.Order <> ARight.Order then
    Result := ALeft.Order < ARight.Order
  else
    Result := CompareText(ALeft.Id, ARight.Id) < 0;
end;

procedure TAtlasStatusRegistry.Add(const AItem: IAtlasStatusItem);
var
  Index, Existing: Integer;
begin
  if AItem = nil then
    Exit;
  FLock.Enter;
  try
    Existing := IndexOf(AItem.Id);
    if Existing >= 0 then
      FItems.Delete(Existing);
    Index := 0;
    while (Index < FItems.Count) and not Comes(AItem, FItems[Index]) do
      Inc(Index);
    FItems.Insert(Index, AItem);
  finally
    FLock.Leave;
  end;
  Notify;
end;

procedure TAtlasStatusRegistry.Remove(const AId: string);
var
  Index: Integer;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if Index < 0 then
      Exit;
    FItems.Delete(Index);
  finally
    FLock.Leave;
  end;
  Notify;
end;

function TAtlasStatusRegistry.Find(const AId: string): IAtlasStatusItem;
var
  Index: Integer;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if Index >= 0 then
      Result := FItems[Index]
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusRegistry.Items: TArray<IAtlasStatusItem>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasStatusRegistry.Changed;
begin
  Notify;
end;

procedure TAtlasStatusRegistry.Notify;
var
  Listeners: TArray<TProc>;
  Listener: TProc;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    Listeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Registry lesen.
  for Listener in Listeners do
    try
      Listener();
    except
      // Ein Fehler im Beobachter darf die meldende Zeile nicht stören.
      on Exception do
        ;
    end;
end;

function TAtlasStatusRegistry.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusRegistry.AddListener(const AListener: TProc): Integer;
begin
  FLock.Enter;
  try
    Inc(FNextListener);
    Result := FNextListener;
    FListeners.Add(Result, AListener);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasStatusRegistry.RemoveListener(AHandle: Integer);
begin
  FLock.Enter;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Leave;
  end;
end;

{ TAtlasStatusLine }

constructor TAtlasStatusLine.Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer);
begin
  Create(ARegistry, AId, AOrder, nil);
end;

constructor TAtlasStatusLine.Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
  const AAction: TProc);
begin
  Create(ARegistry, AId, AOrder, AAction, nil);
end;

constructor TAtlasStatusLine.Create(const ARegistry: IAtlasStatusRegistry; const AId: string; AOrder: Integer;
  const AAction: TProc; const AEnabled: TFunc<Boolean>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRegistry := Pointer(ARegistry);
  FId := AId;
  FOrder := AOrder;
  FAction := AAction;
  FEnabled := AEnabled;
  FState := TAtlasStatusState.Neutral;
end;

destructor TAtlasStatusLine.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasStatusLine.Id: string;
begin
  Result := FId;
end;

function TAtlasStatusLine.Order: Integer;
begin
  Result := FOrder;
end;

function TAtlasStatusLine.Text: string;
begin
  FLock.Enter;
  try
    Result := FText;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusLine.Summary: string;
begin
  FLock.Enter;
  try
    Result := FSummary;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusLine.State: TAtlasStatusState;
begin
  FLock.Enter;
  try
    Result := FState;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusLine.HasAction: Boolean;
begin
  Result := Assigned(FAction) and (not Assigned(FEnabled) or FEnabled());
end;

procedure TAtlasStatusLine.Execute;
begin
  if HasAction then
    FAction();
end;

function TAtlasStatusLine.Brief: string;
begin
  FLock.Enter;
  try
    Result := FBrief;
  finally
    FLock.Leave;
  end;
end;

function TAtlasStatusLine.Detail: string;
begin
  FLock.Enter;
  try
    Result := FDetail;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasStatusLine.Update(const AText: string; AState: TAtlasStatusState);
begin
  Update(AText, AState, '');
end;

procedure TAtlasStatusLine.Update(const AText: string; AState: TAtlasStatusState; const ASummary: string);
begin
  Update(AText, AState, ASummary, '', '');
end;

procedure TAtlasStatusLine.Update(const AText: string; AState: TAtlasStatusState; const ASummary, ABrief,
  ADetail: string);
var
  Different: Boolean;
  Registry: Pointer;
begin
  FLock.Enter;
  try
    Different := (FText <> AText) or (FState <> AState) or (FSummary <> ASummary) or (FBrief <> ABrief) or
      (FDetail <> ADetail);
    FText := AText;
    FState := AState;
    FSummary := ASummary;
    FBrief := ABrief;
    FDetail := ADetail;
    Registry := FRegistry;
  finally
    FLock.Leave;
  end;
  if Different and (Registry <> nil) then
    IAtlasStatusRegistry(Registry).Changed;
end;

procedure TAtlasStatusLine.Detach;
begin
  FLock.Enter;
  try
    FRegistry := nil;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasStatusSummary }

class function TAtlasStatusSummary.Visible(const AItems: TArray<IAtlasStatusItem>;
  const AHidden: TArray<string>): TArray<IAtlasStatusItem>;
var
  Item: IAtlasStatusItem;
  Hidden: string;
  Skip: Boolean;
begin
  Result := nil;
  for Item in AItems do
  begin
    Skip := False;
    for Hidden in AHidden do
      if SameText(Trim(Hidden), Item.Id) then
        Skip := True;
    if not Skip then
      Result := Result + [Item];
  end;
end;

class function TAtlasStatusSummary.Overall(const AItems: TArray<IAtlasStatusItem>): TAtlasStatusState;
var
  Item: IAtlasStatusItem;
begin
  Result := TAtlasStatusState.Neutral;
  for Item in AItems do
    if Ord(Item.State) > Ord(Result) then
      Result := Item.State;
end;

class function TAtlasStatusSummary.Leading(const AItems: TArray<IAtlasStatusItem>): IAtlasStatusItem;
var
  Item: IAtlasStatusItem;
begin
  // AItems ist nach Reihenfolge sortiert: die erste Zeile mit dem schlechtesten Zustand.
  Result := nil;
  for Item in AItems do
    if (Result = nil) or (Ord(Item.State) > Ord(Result.State)) then
      Result := Item;
end;

class function TAtlasStatusSummary.FieldText(const AItems: TArray<IAtlasStatusItem>;
  AShowSummary: Boolean): string;
begin
  Result := FieldText(AItems, AShowSummary, '');
end;

class function TAtlasStatusSummary.FieldText(const AItems: TArray<IAtlasStatusItem>; AShowSummary: Boolean;
  const AAlwaysId: string): string;
var
  Lead, Item: IAtlasStatusItem;
begin
  Result := FieldCaption;
  Lead := nil;
  if AShowSummary then
    Lead := Leading(AItems);
  if (Lead <> nil) and (Ord(Lead.State) >= Ord(TAtlasStatusState.Yellow)) and (Lead.Summary <> '') then
    Result := Result + Separator + Lead.Summary
  else
    Lead := nil;
  if AAlwaysId = '' then
    Exit;
  for Item in AItems do
    if SameText(Item.Id, AAlwaysId) and (Item <> Lead) and (Ord(Item.State) >= Ord(TAtlasStatusState.Yellow)) and
      (Item.Summary <> '') then
    begin
      Result := Result + Separator + Item.Summary;
      Exit;
    end;
end;

class function TAtlasStatusSummary.Tooltip(const AItems: TArray<IAtlasStatusItem>): string;
var
  Item: IAtlasStatusItem;
  Lines: TArray<string>;
begin
  Lines := nil;
  for Item in AItems do
    if (Item.State <> TAtlasStatusState.Green) and (Item.Text <> '') then
      Lines := Lines + [Item.Text];
  if Length(Lines) = 0 then
    Result := FieldCaption + ': alles in Ordnung'
  else
    Result := string.Join(sLineBreak, Lines);
end;

class function TAtlasStatusSummary.ParseIds(const AText: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in AText.Split([',', ';', ' ', #9, #13, #10]) do
    if Trim(Part) <> '' then
      Result := Result + [Trim(Part)];
end;

class function TAtlasStatusSummary.JoinIds(const AIds: TArray<string>): string;
begin
  Result := string.Join(', ', AIds);
end;

class function TAtlasStatusSummary.StateName(AState: TAtlasStatusState): string;
const
  Names: array[TAtlasStatusState] of string = ('neutral', 'grün', 'gelb', 'rot');
begin
  Result := Names[AState];
end;

end.
