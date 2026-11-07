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
    cFieldCaption = 'Atlas';
    cSeparator = ' · ';
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
  begin
    FDefault := TAtlasStatusRegistry.Create;
  end;
  Result := FDefault;
end;

class procedure TAtlasStatusRegistry.ReleaseDefault;
begin
  FDefault := nil;
end;

function TAtlasStatusRegistry.IndexOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if SameText(FItems[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function Comes(const ALeft, ARight: IAtlasStatusItem): Boolean;
begin
  if ALeft.Order <> ARight.Order then
  begin
    Result := ALeft.Order < ARight.Order;
  end
  else
  begin
    Result := CompareText(ALeft.Id, ARight.Id) < 0;
  end;
end;

procedure TAtlasStatusRegistry.Add(const AItem: IAtlasStatusItem);
var
  mIndex, mExisting: Integer;
begin
  if AItem = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mExisting := IndexOf(AItem.Id);
    if mExisting >= 0 then
    begin
      FItems.Delete(mExisting);
    end;
    mIndex := 0;
    while (mIndex < FItems.Count) and not Comes(AItem, FItems[mIndex]) do
    begin
      Inc(mIndex);
    end;
    FItems.Insert(mIndex, AItem);
  finally
    FLock.Leave;
  end;
  Notify;
end;

procedure TAtlasStatusRegistry.Remove(const AId: string);
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    if mIndex < 0 then
    begin
      Exit;
    end;
    FItems.Delete(mIndex);
  finally
    FLock.Leave;
  end;
  Notify;
end;

function TAtlasStatusRegistry.Find(const AId: string): IAtlasStatusItem;
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    if mIndex >= 0 then
    begin
      Result := FItems[mIndex];
    end
    else
    begin
      Result := nil;
    end;
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
  mListeners: TArray<TProc>;
  mListener: TProc;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    mListeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Registry lesen.
  for mListener in mListeners do
    try
      mListener();
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
  begin
    FAction();
  end;
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
  mDifferent: Boolean;
  mRegistry: Pointer;
begin
  FLock.Enter;
  try
    mDifferent := (FText <> AText) or (FState <> AState) or (FSummary <> ASummary) or (FBrief <> ABrief) or
      (FDetail <> ADetail);
    FText := AText;
    FState := AState;
    FSummary := ASummary;
    FBrief := ABrief;
    FDetail := ADetail;
    mRegistry := FRegistry;
  finally
    FLock.Leave;
  end;
  if mDifferent and (mRegistry <> nil) then
  begin
    IAtlasStatusRegistry(mRegistry).Changed;
  end;
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
  mItem: IAtlasStatusItem;
  mHidden: string;
  mSkip: Boolean;
begin
  Result := nil;
  for mItem in AItems do
  begin
    mSkip := False;
    for mHidden in AHidden do
    begin
      if SameText(Trim(mHidden), mItem.Id) then
      begin
        mSkip := True;
      end;
    end;
    if not mSkip then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasStatusSummary.Overall(const AItems: TArray<IAtlasStatusItem>): TAtlasStatusState;
var
  mItem: IAtlasStatusItem;
begin
  Result := TAtlasStatusState.Neutral;
  for mItem in AItems do
  begin
    if Ord(mItem.State) > Ord(Result) then
    begin
      Result := mItem.State;
    end;
  end;
end;

class function TAtlasStatusSummary.Leading(const AItems: TArray<IAtlasStatusItem>): IAtlasStatusItem;
var
  mItem: IAtlasStatusItem;
begin
  // AItems ist nach Reihenfolge sortiert: die erste Zeile mit dem schlechtesten Zustand.
  Result := nil;
  for mItem in AItems do
  begin
    if (Result = nil) or (Ord(mItem.State) > Ord(Result.State)) then
    begin
      Result := mItem;
    end;
  end;
end;

class function TAtlasStatusSummary.FieldText(const AItems: TArray<IAtlasStatusItem>;
  AShowSummary: Boolean): string;
begin
  Result := FieldText(AItems, AShowSummary, '');
end;

class function TAtlasStatusSummary.FieldText(const AItems: TArray<IAtlasStatusItem>; AShowSummary: Boolean;
  const AAlwaysId: string): string;
var
  mLead, mItem: IAtlasStatusItem;
begin
  Result := cFieldCaption;
  mLead := nil;
  if AShowSummary then
  begin
    mLead := Leading(AItems);
  end;
  if (mLead <> nil) and (Ord(mLead.State) >= Ord(TAtlasStatusState.Yellow)) and (mLead.Summary <> '') then
  begin
    Result := Result + cSeparator + mLead.Summary;
  end
  else
  begin
    mLead := nil;
  end;
  if AAlwaysId = '' then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if SameText(mItem.Id, AAlwaysId) and (mItem <> mLead) and (Ord(mItem.State) >= Ord(TAtlasStatusState.Yellow)) and
      (mItem.Summary <> '') then
    begin
      Result := Result + cSeparator + mItem.Summary;
      Exit;
    end;
  end;
end;

class function TAtlasStatusSummary.Tooltip(const AItems: TArray<IAtlasStatusItem>): string;
var
  mItem: IAtlasStatusItem;
  mLines: TArray<string>;
begin
  mLines := nil;
  for mItem in AItems do
  begin
    if (mItem.State <> TAtlasStatusState.Green) and (mItem.Text <> '') then
    begin
      mLines := mLines + [mItem.Text];
    end;
  end;
  if Length(mLines) = 0 then
  begin
    Result := cFieldCaption + ': alles in Ordnung';
  end
  else
  begin
    Result := string.Join(sLineBreak, mLines);
  end;
end;

class function TAtlasStatusSummary.ParseIds(const AText: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' ', #9, #13, #10]) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
end;

class function TAtlasStatusSummary.JoinIds(const AIds: TArray<string>): string;
begin
  Result := string.Join(', ', AIds);
end;

end.
