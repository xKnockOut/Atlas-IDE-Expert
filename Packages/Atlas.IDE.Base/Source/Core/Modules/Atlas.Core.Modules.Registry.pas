unit Atlas.Core.Modules.Registry;

// Modul-Registry von Base (#1455, ADR 0017, Regeln 1–5, 8, 9):
// - AtlasModuleRegistry besteht ab der Unit-Initialisierung (verzögert
//   erzeugt); nach dem Abbau in der Finalisierung liefert es nil, damit Module
//   sich in ihrer Finalisierung nur abmelden, solange Base läuft (Regel 5).
// - Die Modulliste entsteht nur aus Anmeldungen (Regel 9). Jedes Modul, das
//   sich einmal angemeldet hat, bleibt mit Id, Name und Version bekannt und
//   steht unter „$modules.known“ in der Ablage der Einstellungen, sobald Base
//   sie mit UseStorage setzt.
// - Abmelden stoppt ein aktives Modul und löst seinen Scope rückwärts; ein
//   Fehler hält den Abbau nicht an (wie TAtlasFeatureTable.StopAll, #886).
// - Objekte nach Interface-GUID (Provide/FindAll); die Registry versteht
//   nicht, was dahinter steckt.
// - Änderungsmeldung außerhalb der Sperre; ein gelöster Hörer wird auch
//   mitten in einer Meldung nicht mehr gerufen (Regel 3). Wirft ein Hörer,
//   erfahren die übrigen die Änderung trotzdem; danach meldet die Registry den
//   Fehler (EAtlasModuleRegistry), beim Abmelden im Ergebnis.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registration,
  Atlas.Core.Settings.Contract;

const
  /// <summary>Name der Liste bekannter Module in der Ablage der Einstellungen.</summary>
  cAtlasKnownModulesName = '$modules.known';

type
  /// <summary>Liste bekannter Module als Text: je Modul eine Zeile „Id Tab Name Tab Version“. Tabulatoren und
  /// Zeilenumbrüche in den Angaben werden zu Leerzeichen.</summary>
  TAtlasKnownModulesText = class
  public
    class function Encode(const AModules: TArray<TAtlasModuleInfo>): string; static;
    /// <summary>Zeilen ohne Id und doppelte Ids werden übergangen; Handle ist immer 0.</summary>
    class function Decode(const AText: string): TArray<TAtlasModuleInfo>; static;
  end;

  TAtlasModuleRegistry = class(TInterfacedObject, IAtlasModuleRegistry)
  private type
    TModuleEntry = record
      Module: IAtlasModule;
      Info: TAtlasModuleInfo;
      Scope: TObject;
      ScopeRef: IAtlasModuleScope;
    end;

    TProvision = record
      IID: TGUID;
      Instance: IInterface;
      OwnerId: string;
      Item: TAtlasRegistration;
      Ref: IAtlasRegistration;
    end;

    TListenerEntry = record
      Listener: IAtlasRegistryListener;
      OwnerId: string;
      Item: TAtlasRegistration;
      Ref: IAtlasRegistration;
    end;
  private
    FLock: TCriticalSection;
    FModules: TList<TModuleEntry>;
    FProvisions: TList<TProvision>;
    FListeners: TList<TListenerEntry>;
    FKnown: TList<TAtlasModuleInfo>;
    FStorage: IAtlasSettingsStorage;
    FShutDown: Boolean;
    function IndexOfModule(const AModuleId: string): Integer;
    function IndexOfKnown(const AModuleId: string): Integer;
    procedure RememberModule(const AInfo: TAtlasModuleInfo);
    procedure SaveKnown;
    function Notify(AKind: TAtlasRegistryChangeKind; const AModuleId: string; const AIID: TGUID): TArray<string>;
    function NotifyModule(AKind: TAtlasRegistryChangeKind; const AModuleId: string): TArray<string>;
    function AddProvision(const AOwnerId: string; const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    function AddListener(const AOwnerId: string; const AListener: IAtlasRegistryListener): IAtlasRegistration;
    procedure RemoveProvision(AItem: TAtlasRegistration);
    procedure RemoveListener(AItem: TAtlasRegistration);
    class procedure RaiseFailures(const AFailures: TArray<string>); static;
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterModule(const AModule: IAtlasModule): IAtlasModuleScope;
    function UnregisterModule(const AModuleId: string): TArray<string>;
    function Modules: TArray<IAtlasModule>;
    function FindModule(const AModuleId: string; out AModule: IAtlasModule): Boolean;
    function Known: TArray<TAtlasKnownModule>;
    function ForgetModule(const AModuleId: string): Boolean;
    function IsModuleHandle(AHandle: NativeUInt): Boolean;
    function Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    function FindAll(const AIID: TGUID): TArray<IInterface>;
    function Provisions(const AIID: TGUID): TArray<TAtlasProvided>;
    function Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
    /// <summary>Ablage der Einstellungen setzen (Base beim Laden): Die dort gespeicherte Liste bekannter Module
    /// kommt zuerst, bisher bekannte, die dort fehlen, folgen; das Ergebnis wird zurückgeschrieben.</summary>
    procedure UseStorage(const AStorage: IAtlasSettingsStorage);
    /// <summary>Alle Module rückwärts abmelden und keine neuen mehr annehmen (Finalisierung von Base, Regel 5).
    /// Ergebnis wie UnregisterModule, über alle Module.</summary>
    function ShutDown: TArray<string>;
  end;

/// <summary>Die Registry von Base; nil nach dem Abbau in der Finalisierung (Regel 5).</summary>
function AtlasModuleRegistry: IAtlasModuleRegistry;
/// <summary>Dieselbe Registry für Base selbst (UseStorage); nil nach dem Abbau.</summary>
function AtlasModuleRegistryInstance: TAtlasModuleRegistry;

implementation

type
  TAtlasModuleScope = class(TInterfacedObject, IAtlasModuleScope)
  private
    FLock: TCriticalSection;
    FRegistry: TAtlasModuleRegistry;
    FModuleId: string;
    FOpen: Boolean;
    FOwned: TList<IAtlasRegistration>;
    function Registry: TAtlasModuleRegistry;
  public
    constructor Create(ARegistry: TAtlasModuleRegistry; const AModuleId: string);
    destructor Destroy; override;
    function ModuleId: string;
    function IsOpen: Boolean;
    procedure Own(const ARegistration: IAtlasRegistration);
    function Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    function Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
    /// <summary>Schließen und jede Anmeldung rückwärts lösen; Ergebnis: fehlgeschlagene als „Klasse: Meldung“.</summary>
    function Close: TArray<string>;
    /// <summary>Registry abgebaut: schließen, ohne die Anmeldungen zu lösen (sie sind schon abgetrennt).</summary>
    procedure Detach;
  end;

  TAtlasProvisionRegistration = class(TAtlasRegistration)
  private
    FRegistry: TAtlasModuleRegistry;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(ARegistry: TAtlasModuleRegistry);
  end;

  TAtlasListenerRegistration = class(TAtlasRegistration)
  private
    FRegistry: TAtlasModuleRegistry;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(ARegistry: TAtlasModuleRegistry);
  end;

const
  cNoIID: TGUID = '{00000000-0000-0000-0000-000000000000}';

var
  GRegistry: IAtlasModuleRegistry;
  GRegistryInstance: TAtlasModuleRegistry;
  GTornDown: Boolean;

function AtlasModuleRegistry: IAtlasModuleRegistry;
begin
  if (GRegistry = nil) and not GTornDown then
  begin
    GRegistryInstance := TAtlasModuleRegistry.Create;
    GRegistry := GRegistryInstance;
  end;
  Result := GRegistry;
end;

function AtlasModuleRegistryInstance: TAtlasModuleRegistry;
begin
  AtlasModuleRegistry;
  Result := GRegistryInstance;
end;

function FailureOf(const AStep: string; AError: Exception): string;
begin
  Result := AStep + ': ' + AError.ClassName + ': ' + AError.Message;
end;

procedure AppendFailures(var AList: TArray<string>; const AMore: TArray<string>);
var
  mItem: string;
begin
  for mItem in AMore do
    AList := AList + [mItem];
end;

function CleanField(const AText: string): string;
begin
  Result := StringReplace(AText, #9, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

{ TAtlasKnownModulesText }

class function TAtlasKnownModulesText.Encode(const AModules: TArray<TAtlasModuleInfo>): string;
var
  mInfo: TAtlasModuleInfo;
begin
  Result := '';
  for mInfo in AModules do
  begin
    if Result <> '' then
      Result := Result + #10;
    Result := Result + CleanField(mInfo.Id) + #9 + CleanField(mInfo.Name) + #9 + CleanField(mInfo.Version);
  end;
end;

class function TAtlasKnownModulesText.Decode(const AText: string): TArray<TAtlasModuleInfo>;
var
  mLines: TArray<string>;
  mFields: TArray<string>;
  mLine: string;
  mInfo: TAtlasModuleInfo;
  mSeen: TList<string>;
begin
  Result := nil;
  mLines := StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]);
  mSeen := TList<string>.Create;
  try
    for mLine in mLines do
    begin
      mFields := mLine.Split([#9]);
      if (Length(mFields) = 0) or (Trim(mFields[0]) = '') or mSeen.Contains(Trim(mFields[0])) then
        Continue;
      mInfo := Default(TAtlasModuleInfo);
      mInfo.Id := Trim(mFields[0]);
      if Length(mFields) > 1 then
        mInfo.Name := mFields[1];
      if Length(mFields) > 2 then
        mInfo.Version := mFields[2];
      mSeen.Add(mInfo.Id);
      Result := Result + [mInfo];
    end;
  finally
    mSeen.Free;
  end;
end;

{ TAtlasModuleScope }

constructor TAtlasModuleScope.Create(ARegistry: TAtlasModuleRegistry; const AModuleId: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRegistry := ARegistry;
  FModuleId := AModuleId;
  FOpen := True;
  FOwned := TList<IAtlasRegistration>.Create;
end;

destructor TAtlasModuleScope.Destroy;
begin
  FOwned.Free;
  FLock.Free;
  inherited;
end;

function TAtlasModuleScope.Registry: TAtlasModuleRegistry;
begin
  FLock.Acquire;
  try
    if not FOpen then
      raise EAtlasModuleRegistry.CreateFmt('Modul %s ist abgemeldet; es kann nichts mehr anmelden', [FModuleId]);
    Result := FRegistry;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleScope.ModuleId: string;
begin
  Result := FModuleId;
end;

function TAtlasModuleScope.IsOpen: Boolean;
begin
  FLock.Acquire;
  try
    Result := FOpen;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasModuleScope.Own(const ARegistration: IAtlasRegistration);
var
  mOpen: Boolean;
  mIndex: Integer;
begin
  if ARegistration = nil then
    Exit;
  FLock.Acquire;
  try
    mOpen := FOpen;
    if mOpen then
    begin
      // Schon gelöste Anmeldungen (etwa gelieferte Antworten) fallen weg, damit die Liste nicht wächst.
      for mIndex := FOwned.Count - 1 downto 0 do
        if FOwned[mIndex].IsRevoked then
          FOwned.Delete(mIndex);
      FOwned.Add(ARegistration);
    end;
  finally
    FLock.Release;
  end;
  if not mOpen then
    ARegistration.Revoke;
end;

function TAtlasModuleScope.Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
begin
  Result := Registry.AddProvision(FModuleId, AIID, AObject);
  Own(Result);
end;

function TAtlasModuleScope.Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
begin
  Result := Registry.AddListener(FModuleId, AListener);
  Own(Result);
end;

function TAtlasModuleScope.Close: TArray<string>;
var
  mOwned: TArray<IAtlasRegistration>;
  mIndex: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    FOpen := False;
    mOwned := FOwned.ToArray;
    FOwned.Clear;
  finally
    FLock.Release;
  end;
  for mIndex := High(mOwned) downto 0 do
  begin
    try
      mOwned[mIndex].Revoke;
    except
      on mError: Exception do
        Result := Result + [FailureOf(FModuleId + ' Anmeldung ' + IntToStr(mIndex + 1), mError)];
    end;
  end;
end;

procedure TAtlasModuleScope.Detach;
begin
  FLock.Acquire;
  try
    FOpen := False;
    FOwned.Clear;
    FRegistry := nil;
  finally
    FLock.Release;
  end;
end;

{ TAtlasProvisionRegistration }

constructor TAtlasProvisionRegistration.Create(ARegistry: TAtlasModuleRegistry);
begin
  inherited Create;
  FRegistry := ARegistry;
end;

procedure TAtlasProvisionRegistration.DoRevoke;
begin
  FRegistry.RemoveProvision(Self);
end;

{ TAtlasListenerRegistration }

constructor TAtlasListenerRegistration.Create(ARegistry: TAtlasModuleRegistry);
begin
  inherited Create;
  FRegistry := ARegistry;
end;

procedure TAtlasListenerRegistration.DoRevoke;
begin
  FRegistry.RemoveListener(Self);
end;

{ TAtlasModuleRegistry }

constructor TAtlasModuleRegistry.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FModules := TList<TModuleEntry>.Create;
  FProvisions := TList<TProvision>.Create;
  FListeners := TList<TListenerEntry>.Create;
  FKnown := TList<TAtlasModuleInfo>.Create;
end;

destructor TAtlasModuleRegistry.Destroy;
var
  mModule: TModuleEntry;
  mProvision: TProvision;
  mListener: TListenerEntry;
begin
  // Was noch angemeldet ist, verweist auf diese Registry: abtrennen, damit ein späteres Revoke ins Leere geht.
  for mModule in FModules do
    TAtlasModuleScope(mModule.Scope).Detach;
  for mProvision in FProvisions do
    mProvision.Item.Detach;
  for mListener in FListeners do
    mListener.Item.Detach;
  FKnown.Free;
  FListeners.Free;
  FProvisions.Free;
  FModules.Free;
  FLock.Free;
  inherited;
end;

class procedure TAtlasModuleRegistry.RaiseFailures(const AFailures: TArray<string>);
begin
  if Length(AFailures) > 0 then
    raise EAtlasModuleRegistry.Create(string.Join(sLineBreak, AFailures));
end;

function TAtlasModuleRegistry.IndexOfModule(const AModuleId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FModules.Count - 1 do
    if SameText(FModules[mIndex].Info.Id, AModuleId) then
      Exit(mIndex);
end;

function TAtlasModuleRegistry.IndexOfKnown(const AModuleId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FKnown.Count - 1 do
    if SameText(FKnown[mIndex].Id, AModuleId) then
      Exit(mIndex);
end;

procedure TAtlasModuleRegistry.RememberModule(const AInfo: TAtlasModuleInfo);
var
  mInfo: TAtlasModuleInfo;
  mIndex: Integer;
begin
  mInfo := AInfo;
  mInfo.Handle := 0;
  mIndex := IndexOfKnown(AInfo.Id);
  if mIndex < 0 then
    FKnown.Add(mInfo)
  else
    FKnown[mIndex] := mInfo;
  SaveKnown;
end;

procedure TAtlasModuleRegistry.SaveKnown;
begin
  if FStorage <> nil then
    FStorage.WriteText(cAtlasKnownModulesName, TAtlasKnownModulesText.Encode(FKnown.ToArray));
end;

function TAtlasModuleRegistry.Notify(AKind: TAtlasRegistryChangeKind; const AModuleId: string;
  const AIID: TGUID): TArray<string>;
var
  mListeners: TArray<TListenerEntry>;
  mListener: TListenerEntry;
  mChange: TAtlasRegistryChange;
begin
  Result := nil;
  FLock.Acquire;
  try
    mListeners := FListeners.ToArray;
  finally
    FLock.Release;
  end;
  mChange.Kind := AKind;
  mChange.ModuleId := AModuleId;
  mChange.IID := AIID;
  for mListener in mListeners do
  begin
    // Ein früherer Hörer kann diesen gelöst haben (Regel 3).
    if mListener.Item.IsRevoked then
      Continue;
    try
      mListener.Listener.RegistryChanged(mChange);
    except
      on mError: Exception do
        Result := Result + [FailureOf('Hörer von ' + mListener.OwnerId, mError)];
    end;
  end;
end;

function TAtlasModuleRegistry.NotifyModule(AKind: TAtlasRegistryChangeKind; const AModuleId: string): TArray<string>;
begin
  Result := Notify(AKind, AModuleId, cNoIID);
end;

function TAtlasModuleRegistry.RegisterModule(const AModule: IAtlasModule): IAtlasModuleScope;
var
  mEntry: TModuleEntry;
  mScope: TAtlasModuleScope;
begin
  if AModule = nil then
    raise EAtlasModuleRegistry.Create('Kein Modul angegeben');
  mEntry.Module := AModule;
  mEntry.Info := AModule.Info;
  mEntry.Info.Id := Trim(mEntry.Info.Id);
  if mEntry.Info.Id = '' then
    raise EAtlasModuleRegistry.Create('Modul ohne Id');
  FLock.Acquire;
  try
    if FShutDown then
      raise EAtlasModuleRegistry.CreateFmt('Base ist abgebaut; Modul %s wird nicht angemeldet', [mEntry.Info.Id]);
    if IndexOfModule(mEntry.Info.Id) >= 0 then
      raise EAtlasModuleRegistry.CreateFmt('Modul %s ist schon angemeldet', [mEntry.Info.Id]);
    mScope := TAtlasModuleScope.Create(Self, mEntry.Info.Id);
    mEntry.Scope := mScope;
    mEntry.ScopeRef := mScope;
    FModules.Add(mEntry);
    RememberModule(mEntry.Info);
  finally
    FLock.Release;
  end;
  Result := mEntry.ScopeRef;
  RaiseFailures(NotifyModule(rcModuleAdded, mEntry.Info.Id));
end;

function TAtlasModuleRegistry.UnregisterModule(const AModuleId: string): TArray<string>;
var
  mIndex: Integer;
  mEntry: TModuleEntry;
begin
  Result := nil;
  FLock.Acquire;
  try
    mIndex := IndexOfModule(AModuleId);
    if mIndex < 0 then
      Exit;
    mEntry := FModules[mIndex];
    FModules.Delete(mIndex);
  finally
    FLock.Release;
  end;
  // Erst stoppen, dann die Anmeldungen lösen: Stop darf noch auf eigene Anmeldungen zugreifen.
  try
    if mEntry.Module.IsActive then
      mEntry.Module.Stop;
  except
    on mError: Exception do
      Result := Result + [FailureOf(mEntry.Info.Id + ' Stop', mError)];
  end;
  AppendFailures(Result, TAtlasModuleScope(mEntry.Scope).Close);
  AppendFailures(Result, NotifyModule(rcModuleRemoved, mEntry.Info.Id));
end;

function TAtlasModuleRegistry.Modules: TArray<IAtlasModule>;
var
  mEntry: TModuleEntry;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mEntry in FModules do
      Result := Result + [mEntry.Module];
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.FindModule(const AModuleId: string; out AModule: IAtlasModule): Boolean;
var
  mIndex: Integer;
begin
  AModule := nil;
  FLock.Acquire;
  try
    mIndex := IndexOfModule(AModuleId);
    Result := mIndex >= 0;
    if Result then
      AModule := FModules[mIndex].Module;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.Known: TArray<TAtlasKnownModule>;
var
  mIndex: Integer;
  mModule: Integer;
  mKnown: TAtlasKnownModule;
begin
  Result := nil;
  FLock.Acquire;
  try
    SetLength(Result, FKnown.Count);
    for mIndex := 0 to FKnown.Count - 1 do
    begin
      mModule := IndexOfModule(FKnown[mIndex].Id);
      mKnown.Installed := mModule >= 0;
      if mKnown.Installed then
        mKnown.Info := FModules[mModule].Info
      else
        mKnown.Info := FKnown[mIndex];
      Result[mIndex] := mKnown;
    end;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.ForgetModule(const AModuleId: string): Boolean;
var
  mIndex: Integer;
begin
  FLock.Acquire;
  try
    mIndex := IndexOfKnown(AModuleId);
    Result := (mIndex >= 0) and (IndexOfModule(AModuleId) < 0);
    if Result then
    begin
      FKnown.Delete(mIndex);
      SaveKnown;
    end;
  finally
    FLock.Release;
  end;
  if Result then
    RaiseFailures(NotifyModule(rcKnownChanged, AModuleId));
end;

function TAtlasModuleRegistry.IsModuleHandle(AHandle: NativeUInt): Boolean;
var
  mEntry: TModuleEntry;
begin
  Result := False;
  if AHandle = 0 then
    Exit;
  FLock.Acquire;
  try
    for mEntry in FModules do
      if mEntry.Info.Handle = AHandle then
        Exit(True);
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.AddProvision(const AOwnerId: string; const AIID: TGUID;
  const AObject: IInterface): IAtlasRegistration;
var
  mProvision: TProvision;
  mItem: TAtlasProvisionRegistration;
begin
  if (AObject = nil) or not Supports(AObject, AIID) then
    raise EAtlasModuleRegistry.CreateFmt('Objekt unterstützt %s nicht', [GUIDToString(AIID)]);
  mItem := TAtlasProvisionRegistration.Create(Self);
  mProvision.IID := AIID;
  mProvision.Instance := AObject;
  mProvision.OwnerId := AOwnerId;
  mProvision.Item := mItem;
  mProvision.Ref := mItem;
  FLock.Acquire;
  try
    FProvisions.Add(mProvision);
  finally
    FLock.Release;
  end;
  Result := mProvision.Ref;
  RaiseFailures(Notify(rcProvided, AOwnerId, AIID));
end;

function TAtlasModuleRegistry.AddListener(const AOwnerId: string;
  const AListener: IAtlasRegistryListener): IAtlasRegistration;
var
  mEntry: TListenerEntry;
  mItem: TAtlasListenerRegistration;
begin
  if AListener = nil then
    raise EAtlasModuleRegistry.Create('Kein Hörer angegeben');
  mItem := TAtlasListenerRegistration.Create(Self);
  mEntry.Listener := AListener;
  mEntry.OwnerId := AOwnerId;
  mEntry.Item := mItem;
  mEntry.Ref := mItem;
  FLock.Acquire;
  try
    FListeners.Add(mEntry);
  finally
    FLock.Release;
  end;
  Result := mEntry.Ref;
end;

procedure TAtlasModuleRegistry.RemoveProvision(AItem: TAtlasRegistration);
var
  mIndex: Integer;
  mProvision: TProvision;
  mFound: Boolean;
begin
  mFound := False;
  FLock.Acquire;
  try
    for mIndex := 0 to FProvisions.Count - 1 do
      if FProvisions[mIndex].Item = AItem then
      begin
        mProvision := FProvisions[mIndex];
        FProvisions.Delete(mIndex);
        mFound := True;
        Break;
      end;
  finally
    FLock.Release;
  end;
  if mFound then
    RaiseFailures(Notify(rcRevoked, mProvision.OwnerId, mProvision.IID));
end;

procedure TAtlasModuleRegistry.RemoveListener(AItem: TAtlasRegistration);
var
  mIndex: Integer;
begin
  // Wer Revoke ruft, hält selbst eine Referenz: AItem lebt über das Löschen hinaus.
  FLock.Acquire;
  try
    for mIndex := 0 to FListeners.Count - 1 do
      if FListeners[mIndex].Item = AItem then
      begin
        FListeners.Delete(mIndex);
        Break;
      end;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
begin
  Result := AddProvision('', AIID, AObject);
end;

function TAtlasModuleRegistry.FindAll(const AIID: TGUID): TArray<IInterface>;
var
  mProvision: TProvision;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mProvision in FProvisions do
      if IsEqualGUID(mProvision.IID, AIID) then
        Result := Result + [mProvision.Instance];
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.Provisions(const AIID: TGUID): TArray<TAtlasProvided>;
var
  mProvision: TProvision;
  mItem: TAtlasProvided;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mProvision in FProvisions do
      if IsEqualGUID(mProvision.IID, AIID) then
      begin
        mItem.OwnerId := mProvision.OwnerId;
        mItem.Instance := mProvision.Instance;
        Result := Result + [mItem];
      end;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
begin
  Result := AddListener('', AListener);
end;

procedure TAtlasModuleRegistry.UseStorage(const AStorage: IAtlasSettingsStorage);
var
  mStored: TArray<TAtlasModuleInfo>;
  mMerged: TList<TAtlasModuleInfo>;
  mInfo: TAtlasModuleInfo;
  mFound: Boolean;
  mIndex: Integer;
begin
  FLock.Acquire;
  try
    FStorage := AStorage;
    if FStorage = nil then
      Exit;
    mStored := TAtlasKnownModulesText.Decode(FStorage.ReadText(cAtlasKnownModulesName));
    mMerged := TList<TAtlasModuleInfo>.Create;
    try
      mMerged.AddRange(mStored);
      for mInfo in FKnown do
      begin
        mFound := False;
        for mIndex := 0 to mMerged.Count - 1 do
          if SameText(mMerged[mIndex].Id, mInfo.Id) then
          begin
            // Angaben eines in dieser Sitzung angemeldeten Moduls sind neuer als die gespeicherten.
            mMerged[mIndex] := mInfo;
            mFound := True;
            Break;
          end;
        if not mFound then
          mMerged.Add(mInfo);
      end;
      FKnown.Clear;
      FKnown.AddRange(mMerged);
    finally
      mMerged.Free;
    end;
    SaveKnown;
  finally
    FLock.Release;
  end;
end;

function TAtlasModuleRegistry.ShutDown: TArray<string>;
var
  mIds: TArray<string>;
  mEntry: TModuleEntry;
  mIndex: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    FShutDown := True;
    mIds := nil;
    for mEntry in FModules do
      mIds := mIds + [mEntry.Info.Id];
  finally
    FLock.Release;
  end;
  for mIndex := High(mIds) downto 0 do
    AppendFailures(Result, UnregisterModule(mIds[mIndex]));
end;

initialization
  AtlasModuleRegistry;

finalization
  // Regel 5: zuerst alle Module stoppen und abmelden, dann die Registry abbauen. Base ruft ShutDown mit der
  // Verdrahtung (#1456) schon vorher und protokolliert die Fehler; das hier ist nur das Sicherheitsnetz für den
  // Fall, dass die Finalisierung ohne diesen Schritt erreicht wird.
  if GRegistryInstance <> nil then
    GRegistryInstance.ShutDown;
  GTornDown := True;
  GRegistryInstance := nil;
  GRegistry := nil;

end.
