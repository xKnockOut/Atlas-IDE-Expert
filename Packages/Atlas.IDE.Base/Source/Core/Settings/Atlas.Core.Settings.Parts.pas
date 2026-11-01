unit Atlas.Core.Settings.Parts;

// Zentrale Stelle der Einstellungen in Base (#1455, ADR 0017 Entscheidung 3):
// Module melden ihren Teil an (Schlüssel mit Vorgaben, Schema-Teil, Seite,
// Umbenennungen); Base hält eine Ablage für alle.
// - AtlasSettingsParts besteht ab der Unit-Initialisierung (Regel 1); bis
//   Base mit UseStorage seine Ablage setzt, liegen die Werte im
//   Arbeitsspeicher und ziehen dann um.
// - Werte fremder und fehlender Module bleiben erhalten: Abmelden eines Teils
//   entfernt keinen Wert. Welche Schlüssel ein Modul je angemeldet hat, steht
//   unter „$parts.{Modul-Id}.keys“ in der Ablage; ForgetOwner entfernt damit
//   alle Werte eines Moduls, das der Benutzer aus der Liste der bekannten
//   entfernt, auch wenn das Modul nicht mehr installiert ist.
// - Umbenennungen wie x-renamedFrom (#1280): Der Wert unter dem alten
//   Schlüssel zieht um, solange der neue keinen hat; der alte wird entfernt.
//   Angewandt beim Anmelden und beim Wechsel der Ablage.
// - Änderungsmeldung außerhalb der Sperre; ein gelöster Hörer wird nicht mehr
//   gerufen (Regel 3).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registration,
  Atlas.Core.Settings.Contract;

const
  /// <summary>Anfang der Namen, unter denen Base die Schlüssel je Modul vermerkt („$parts.{Id}.keys“).</summary>
  cAtlasOwnerKeysPrefix = '$parts.';
  cAtlasOwnerKeysSuffix = '.keys';

type
  /// <summary>Ablage im Arbeitsspeicher: Vorgabe bis zum Laden der Einstellungen und für Tests.</summary>
  TAtlasMemorySettingsStorage = class(TInterfacedObject, IAtlasSettingsStorage)
  private
    FLock: TCriticalSection;
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Contains(const AName: string): Boolean;
    function ReadText(const AName: string): string;
    procedure WriteText(const AName, AValue: string);
    procedure Remove(const AName: string);
    function Names: TArray<string>;
  end;

  TAtlasSettingsParts = class(TInterfacedObject, IAtlasSettingsParts, IAtlasSettingsValues)
  private type
    TPartEntry = record
      Part: IAtlasSettingsPart;
      OwnerId: string;
      Keys: TArray<TAtlasSettingsKey>;
      Renames: TArray<TAtlasSettingsKeyRename>;
      Item: TAtlasRegistration;
      Ref: IAtlasRegistration;
    end;

    TKeyEntry = record
      Key: TAtlasSettingsKey;
      OwnerId: string;
    end;

    TListenerEntry = record
      Listener: IAtlasSettingsListener;
      Item: TAtlasRegistration;
      Ref: IAtlasRegistration;
    end;
  private
    FLock: TCriticalSection;
    FStorage: IAtlasSettingsStorage;
    FParts: TList<TPartEntry>;
    FKeys: TDictionary<string, TKeyEntry>;
    FListeners: TList<TListenerEntry>;
    function KeyOf(const AKey: string; AKind: TAtlasSettingsValueKind): TKeyEntry;
    function TextOf(const AEntry: TKeyEntry): string;
    procedure WriteValue(const AEntry: TKeyEntry; const AText: string);
    function ApplyRenames(const AEntry: TPartEntry): TArray<TAtlasSettingsChange>;
    procedure RecordOwnerKeys(const AEntry: TPartEntry);
    procedure Notify(const AChanges: TArray<TAtlasSettingsChange>);
    procedure RemovePart(AItem: TAtlasRegistration);
    procedure RemoveListener(AItem: TAtlasRegistration);
    class function ChangeOf(AKind: TAtlasSettingsChangeKind; const AOwnerId, AKey, AOldKey: string): TAtlasSettingsChange; static;
    class function OwnerKeysName(const AOwnerId: string): string; static;
  public
    /// <summary>Mit einer Ablage im Arbeitsspeicher.</summary>
    constructor Create; overload;
    constructor Create(const AStorage: IAtlasSettingsStorage); overload;
    destructor Destroy; override;
    { IAtlasSettingsParts }
    function Add(const APart: IAtlasSettingsPart): IAtlasRegistration;
    function Parts: TArray<IAtlasSettingsPart>;
    function FindKey(const AKey: string; out AEntry: TAtlasSettingsKey): Boolean;
    function Values: IAtlasSettingsValues;
    procedure UseStorage(const AStorage: IAtlasSettingsStorage);
    function ForgetOwner(const AOwnerId: string): Integer;
    function Subscribe(const AListener: IAtlasSettingsListener): IAtlasRegistration;
    { IAtlasSettingsValues }
    function Contains(const AKey: string): Boolean;
    function ReadBoolean(const AKey: string): Boolean;
    function ReadInteger(const AKey: string): Integer;
    function ReadString(const AKey: string): string;
    procedure WriteBoolean(const AKey: string; AValue: Boolean);
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure WriteString(const AKey, AValue: string);
    procedure Reset(const AKey: string);
    function StoredKeys: TArray<string>;
  end;

/// <summary>Die zentrale Stelle der Einstellungen von Base; nil nach dem Abbau in der Finalisierung.</summary>
function AtlasSettingsParts: IAtlasSettingsParts;

implementation

type
  TAtlasPartRegistration = class(TAtlasRegistration)
  private
    FOwner: TAtlasSettingsParts;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(AOwner: TAtlasSettingsParts);
  end;

  TAtlasSettingsListenerRegistration = class(TAtlasRegistration)
  private
    FOwner: TAtlasSettingsParts;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(AOwner: TAtlasSettingsParts);
  end;

var
  GParts: IAtlasSettingsParts;
  GTornDown: Boolean;

function AtlasSettingsParts: IAtlasSettingsParts;
begin
  if (GParts = nil) and not GTornDown then
    GParts := TAtlasSettingsParts.Create;
  Result := GParts;
end;

const
  cKindNames: array[TAtlasSettingsValueKind] of string = ('Wahrheitswert', 'Zahl', 'Text');

function BooleanText(AValue: Boolean): string;
begin
  if AValue then
    Result := '1'
  else
    Result := '0';
end;

function TryParseBoolean(const AText: string; out AValue: Boolean): Boolean;
begin
  Result := True;
  if (AText = '1') or SameText(AText, 'true') then
    AValue := True
  else if (AText = '0') or SameText(AText, 'false') then
    AValue := False
  else
  begin
    AValue := False;
    Result := False;
  end;
end;

function Clamp(const AKey: TAtlasSettingsKey; AValue: Integer): Integer;
begin
  Result := AValue;
  if AKey.Minimum > AKey.Maximum then
    Exit;
  if Result < AKey.Minimum then
    Result := AKey.Minimum;
  if Result > AKey.Maximum then
    Result := AKey.Maximum;
end;

function IsAdministrative(const AName: string): Boolean;
begin
  Result := AName.StartsWith('$');
end;

{ TAtlasMemorySettingsStorage }

constructor TAtlasMemorySettingsStorage.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TAtlasMemorySettingsStorage.Destroy;
begin
  FValues.Free;
  FLock.Free;
  inherited;
end;

function TAtlasMemorySettingsStorage.Contains(const AName: string): Boolean;
begin
  FLock.Acquire;
  try
    Result := FValues.ContainsKey(AName);
  finally
    FLock.Release;
  end;
end;

function TAtlasMemorySettingsStorage.ReadText(const AName: string): string;
begin
  FLock.Acquire;
  try
    if not FValues.TryGetValue(AName, Result) then
      Result := '';
  finally
    FLock.Release;
  end;
end;

procedure TAtlasMemorySettingsStorage.WriteText(const AName, AValue: string);
begin
  FLock.Acquire;
  try
    FValues.AddOrSetValue(AName, AValue);
  finally
    FLock.Release;
  end;
end;

procedure TAtlasMemorySettingsStorage.Remove(const AName: string);
begin
  FLock.Acquire;
  try
    FValues.Remove(AName);
  finally
    FLock.Release;
  end;
end;

function TAtlasMemorySettingsStorage.Names: TArray<string>;
var
  mList: TList<string>;
  mName: string;
begin
  mList := TList<string>.Create;
  try
    FLock.Acquire;
    try
      for mName in FValues.Keys do
        mList.Add(mName);
    finally
      FLock.Release;
    end;
    // Ordinal sortiert: Namen sind eindeutig, die Reihenfolge damit fest.
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TAtlasPartRegistration }

constructor TAtlasPartRegistration.Create(AOwner: TAtlasSettingsParts);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TAtlasPartRegistration.DoRevoke;
begin
  FOwner.RemovePart(Self);
end;

{ TAtlasSettingsListenerRegistration }

constructor TAtlasSettingsListenerRegistration.Create(AOwner: TAtlasSettingsParts);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TAtlasSettingsListenerRegistration.DoRevoke;
begin
  FOwner.RemoveListener(Self);
end;

{ TAtlasSettingsParts }

constructor TAtlasSettingsParts.Create;
var
  mStorage: IAtlasSettingsStorage;
begin
  // Über eine Variable: ein frisch erzeugtes Objekt direkt an einen const-Interface-Parameter würde nie gezählt.
  mStorage := TAtlasMemorySettingsStorage.Create;
  Create(mStorage);
end;

constructor TAtlasSettingsParts.Create(const AStorage: IAtlasSettingsStorage);
begin
  inherited Create;
  if AStorage = nil then
    raise EAtlasSettingsParts.Create('Keine Ablage angegeben');
  FLock := TCriticalSection.Create;
  FStorage := AStorage;
  FParts := TList<TPartEntry>.Create;
  FKeys := TDictionary<string, TKeyEntry>.Create;
  FListeners := TList<TListenerEntry>.Create;
end;

destructor TAtlasSettingsParts.Destroy;
var
  mPart: TPartEntry;
  mListener: TListenerEntry;
begin
  // Noch gehaltene Anmeldungen verweisen auf dieses Objekt: abtrennen, damit ein späteres Revoke ins Leere geht.
  for mPart in FParts do
    mPart.Item.Detach;
  for mListener in FListeners do
    mListener.Item.Detach;
  FListeners.Free;
  FKeys.Free;
  FParts.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasSettingsParts.ChangeOf(AKind: TAtlasSettingsChangeKind; const AOwnerId, AKey,
  AOldKey: string): TAtlasSettingsChange;
begin
  Result.Kind := AKind;
  Result.OwnerId := AOwnerId;
  Result.Key := AKey;
  Result.OldKey := AOldKey;
end;

class function TAtlasSettingsParts.OwnerKeysName(const AOwnerId: string): string;
begin
  Result := cAtlasOwnerKeysPrefix + AOwnerId + cAtlasOwnerKeysSuffix;
end;

procedure TAtlasSettingsParts.Notify(const AChanges: TArray<TAtlasSettingsChange>);
var
  mListeners: TArray<TListenerEntry>;
  mListener: TListenerEntry;
  mChange: TAtlasSettingsChange;
  mFailures: TArray<string>;
begin
  if Length(AChanges) = 0 then
    Exit;
  FLock.Acquire;
  try
    mListeners := FListeners.ToArray;
  finally
    FLock.Release;
  end;
  mFailures := nil;
  for mChange in AChanges do
    for mListener in mListeners do
    begin
      if mListener.Item.IsRevoked then
        Continue;
      try
        mListener.Listener.SettingsChanged(mChange);
      except
        on mError: Exception do
          mFailures := mFailures + [mError.ClassName + ': ' + mError.Message];
      end;
    end;
  // Alle Hörer haben die Änderung erfahren; erst dann den Fehler melden.
  if Length(mFailures) > 0 then
    raise EAtlasSettingsParts.Create(string.Join(sLineBreak, mFailures));
end;

function TAtlasSettingsParts.ApplyRenames(const AEntry: TPartEntry): TArray<TAtlasSettingsChange>;
var
  mRename: TAtlasSettingsKeyRename;
begin
  Result := nil;
  for mRename in AEntry.Renames do
  begin
    if not FStorage.Contains(mRename.OldKey) then
      Continue;
    if not FStorage.Contains(mRename.NewKey) then
    begin
      FStorage.WriteText(mRename.NewKey, FStorage.ReadText(mRename.OldKey));
      Result := Result + [ChangeOf(scRenamed, AEntry.OwnerId, mRename.NewKey, mRename.OldKey)];
    end;
    FStorage.Remove(mRename.OldKey);
  end;
end;

procedure TAtlasSettingsParts.RecordOwnerKeys(const AEntry: TPartEntry);
var
  mName: string;
  mKeys: TList<string>;
  mKey: string;
  mEntry: TAtlasSettingsKey;
begin
  mName := OwnerKeysName(AEntry.OwnerId);
  mKeys := TList<string>.Create;
  try
    // Vereinigung mit dem bisherigen Vermerk: Auch Werte von Schlüsseln, die eine frühere Version des Moduls
    // hatte, entfernt ForgetOwner später.
    for mKey in FStorage.ReadText(mName).Split([#10]) do
      if (mKey <> '') and not mKeys.Contains(mKey) then
        mKeys.Add(mKey);
    for mEntry in AEntry.Keys do
      if not mKeys.Contains(mEntry.Key) then
        mKeys.Add(mEntry.Key);
    mKeys.Sort;
    FStorage.WriteText(mName, string.Join(#10, mKeys.ToArray));
  finally
    mKeys.Free;
  end;
end;

function TAtlasSettingsParts.Add(const APart: IAtlasSettingsPart): IAtlasRegistration;
var
  mEntry: TPartEntry;
  mItem: TAtlasPartRegistration;
  mKey: TAtlasSettingsKey;
  mKeyEntry: TKeyEntry;
  mRename: TAtlasSettingsKeyRename;
  mOwnKeys: TList<string>;
  mChanges: TArray<TAtlasSettingsChange>;
begin
  if APart = nil then
    raise EAtlasSettingsParts.Create('Kein Einstellungsteil angegeben');
  mEntry.Part := APart;
  mEntry.OwnerId := Trim(APart.OwnerId);
  mEntry.Keys := APart.Keys;
  mEntry.Renames := APart.Renames;
  if mEntry.OwnerId = '' then
    raise EAtlasSettingsParts.Create('Einstellungsteil ohne Besitzer');
  mOwnKeys := TList<string>.Create;
  try
    FLock.Acquire;
    try
      for mKey in mEntry.Keys do
      begin
        if (Trim(mKey.Key) = '') or IsAdministrative(mKey.Key) then
          raise EAtlasSettingsParts.CreateFmt('Ungültiger Schlüssel „%s“ in %s', [mKey.Key, mEntry.OwnerId]);
        if mOwnKeys.Contains(mKey.Key) then
          raise EAtlasSettingsParts.CreateFmt('Schlüssel %s doppelt in %s', [mKey.Key, mEntry.OwnerId]);
        if FKeys.TryGetValue(mKey.Key, mKeyEntry) then
          raise EAtlasSettingsParts.CreateFmt('Schlüssel %s gehört schon %s', [mKey.Key, mKeyEntry.OwnerId]);
        mOwnKeys.Add(mKey.Key);
      end;
      for mRename in mEntry.Renames do
      begin
        if not mOwnKeys.Contains(mRename.NewKey) then
          raise EAtlasSettingsParts.CreateFmt('Umbenennung nach %s: kein Schlüssel von %s',
            [mRename.NewKey, mEntry.OwnerId]);
        if (Trim(mRename.OldKey) = '') or IsAdministrative(mRename.OldKey) or mOwnKeys.Contains(mRename.OldKey) or
          FKeys.ContainsKey(mRename.OldKey) then
          raise EAtlasSettingsParts.CreateFmt('Umbenennung von „%s“ in %s: Schlüssel ist angemeldet oder ungültig',
            [mRename.OldKey, mEntry.OwnerId]);
      end;
      mItem := TAtlasPartRegistration.Create(Self);
      mEntry.Item := mItem;
      mEntry.Ref := mItem;
      FParts.Add(mEntry);
      for mKey in mEntry.Keys do
      begin
        mKeyEntry.Key := mKey;
        mKeyEntry.OwnerId := mEntry.OwnerId;
        FKeys.Add(mKey.Key, mKeyEntry);
      end;
      mChanges := TArray<TAtlasSettingsChange>.Create(ChangeOf(scPartAdded, mEntry.OwnerId, '', '')) +
        ApplyRenames(mEntry);
      RecordOwnerKeys(mEntry);
    finally
      FLock.Release;
    end;
  finally
    mOwnKeys.Free;
  end;
  Result := mEntry.Ref;
  Notify(mChanges);
end;

procedure TAtlasSettingsParts.RemovePart(AItem: TAtlasRegistration);
var
  mIndex: Integer;
  mEntry: TPartEntry;
  mKey: TAtlasSettingsKey;
  mFound: Boolean;
begin
  mFound := False;
  FLock.Acquire;
  try
    for mIndex := 0 to FParts.Count - 1 do
      if FParts[mIndex].Item = AItem then
      begin
        mEntry := FParts[mIndex];
        FParts.Delete(mIndex);
        // Nur die Zuordnung der Schlüssel fällt weg; die Werte bleiben in der Ablage.
        for mKey in mEntry.Keys do
          FKeys.Remove(mKey.Key);
        mFound := True;
        Break;
      end;
  finally
    FLock.Release;
  end;
  if mFound then
    Notify([ChangeOf(scPartRemoved, mEntry.OwnerId, '', '')]);
end;

procedure TAtlasSettingsParts.RemoveListener(AItem: TAtlasRegistration);
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

function TAtlasSettingsParts.Parts: TArray<IAtlasSettingsPart>;
var
  mEntry: TPartEntry;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mEntry in FParts do
      Result := Result + [mEntry.Part];
  finally
    FLock.Release;
  end;
end;

function TAtlasSettingsParts.FindKey(const AKey: string; out AEntry: TAtlasSettingsKey): Boolean;
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    Result := FKeys.TryGetValue(AKey, mEntry);
    if Result then
      AEntry := mEntry.Key
    else
      AEntry := Default(TAtlasSettingsKey);
  finally
    FLock.Release;
  end;
end;

function TAtlasSettingsParts.Values: IAtlasSettingsValues;
begin
  Result := Self;
end;

procedure TAtlasSettingsParts.UseStorage(const AStorage: IAtlasSettingsStorage);
var
  mName: string;
  mEntry: TPartEntry;
  mChanges: TArray<TAtlasSettingsChange>;
begin
  if AStorage = nil then
    raise EAtlasSettingsParts.Create('Keine Ablage angegeben');
  FLock.Acquire;
  try
    if AStorage = FStorage then
      Exit;
    // Was bisher nur im Arbeitsspeicher stand, zieht um; gespeicherte Werte der neuen Ablage gelten.
    for mName in FStorage.Names do
      if not AStorage.Contains(mName) then
        AStorage.WriteText(mName, FStorage.ReadText(mName));
    FStorage := AStorage;
    mChanges := TArray<TAtlasSettingsChange>.Create(ChangeOf(scStorageChanged, '', '', ''));
    for mEntry in FParts do
    begin
      mChanges := mChanges + ApplyRenames(mEntry);
      RecordOwnerKeys(mEntry);
    end;
  finally
    FLock.Release;
  end;
  Notify(mChanges);
end;

function TAtlasSettingsParts.ForgetOwner(const AOwnerId: string): Integer;
var
  mEntry: TPartEntry;
  mName: string;
  mKey: string;
begin
  Result := 0;
  FLock.Acquire;
  try
    for mEntry in FParts do
      if SameText(mEntry.OwnerId, AOwnerId) then
        raise EAtlasSettingsParts.CreateFmt('Modul %s ist angemeldet; seine Werte bleiben', [AOwnerId]);
    mName := OwnerKeysName(AOwnerId);
    for mKey in FStorage.ReadText(mName).Split([#10]) do
      if (mKey <> '') and FStorage.Contains(mKey) then
      begin
        FStorage.Remove(mKey);
        Inc(Result);
      end;
    FStorage.Remove(mName);
  finally
    FLock.Release;
  end;
  Notify([ChangeOf(scOwnerForgotten, AOwnerId, '', '')]);
end;

function TAtlasSettingsParts.Subscribe(const AListener: IAtlasSettingsListener): IAtlasRegistration;
var
  mEntry: TListenerEntry;
  mItem: TAtlasSettingsListenerRegistration;
begin
  if AListener = nil then
    raise EAtlasSettingsParts.Create('Kein Hörer angegeben');
  mItem := TAtlasSettingsListenerRegistration.Create(Self);
  mEntry.Listener := AListener;
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

function TAtlasSettingsParts.KeyOf(const AKey: string; AKind: TAtlasSettingsValueKind): TKeyEntry;
begin
  if not FKeys.TryGetValue(AKey, Result) then
    raise EAtlasSettingsKey.CreateFmt('Einstellung %s ist nicht angemeldet', [AKey]);
  if Result.Key.Kind <> AKind then
    raise EAtlasSettingsKey.CreateFmt('Einstellung %s ist kein %s, sondern %s',
      [AKey, cKindNames[AKind], cKindNames[Result.Key.Kind]]);
end;

function TAtlasSettingsParts.TextOf(const AEntry: TKeyEntry): string;
begin
  if FStorage.Contains(AEntry.Key.Key) then
    Result := FStorage.ReadText(AEntry.Key.Key)
  else
    Result := AEntry.Key.Default;
end;

procedure TAtlasSettingsParts.WriteValue(const AEntry: TKeyEntry; const AText: string);
var
  mChanged: Boolean;
begin
  FLock.Acquire;
  try
    mChanged := not FStorage.Contains(AEntry.Key.Key) or (FStorage.ReadText(AEntry.Key.Key) <> AText);
    if mChanged then
      FStorage.WriteText(AEntry.Key.Key, AText);
  finally
    FLock.Release;
  end;
  if mChanged then
    Notify([ChangeOf(scValueChanged, AEntry.OwnerId, AEntry.Key.Key, '')]);
end;

function TAtlasSettingsParts.Contains(const AKey: string): Boolean;
begin
  if IsAdministrative(AKey) then
    Exit(False);
  FLock.Acquire;
  try
    Result := FStorage.Contains(AKey);
  finally
    FLock.Release;
  end;
end;

function TAtlasSettingsParts.ReadBoolean(const AKey: string): Boolean;
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    mEntry := KeyOf(AKey, svBoolean);
    if not TryParseBoolean(TextOf(mEntry), Result) then
      TryParseBoolean(mEntry.Key.Default, Result);
  finally
    FLock.Release;
  end;
end;

function TAtlasSettingsParts.ReadInteger(const AKey: string): Integer;
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    mEntry := KeyOf(AKey, svInteger);
    if not TryStrToInt(TextOf(mEntry), Result) then
      Result := StrToIntDef(mEntry.Key.Default, 0);
    Result := Clamp(mEntry.Key, Result);
  finally
    FLock.Release;
  end;
end;

function TAtlasSettingsParts.ReadString(const AKey: string): string;
begin
  FLock.Acquire;
  try
    Result := TextOf(KeyOf(AKey, svString));
  finally
    FLock.Release;
  end;
end;

procedure TAtlasSettingsParts.WriteBoolean(const AKey: string; AValue: Boolean);
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    mEntry := KeyOf(AKey, svBoolean);
  finally
    FLock.Release;
  end;
  WriteValue(mEntry, BooleanText(AValue));
end;

procedure TAtlasSettingsParts.WriteInteger(const AKey: string; AValue: Integer);
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    mEntry := KeyOf(AKey, svInteger);
  finally
    FLock.Release;
  end;
  WriteValue(mEntry, IntToStr(Clamp(mEntry.Key, AValue)));
end;

procedure TAtlasSettingsParts.WriteString(const AKey, AValue: string);
var
  mEntry: TKeyEntry;
begin
  FLock.Acquire;
  try
    mEntry := KeyOf(AKey, svString);
  finally
    FLock.Release;
  end;
  WriteValue(mEntry, AValue);
end;

procedure TAtlasSettingsParts.Reset(const AKey: string);
var
  mEntry: TKeyEntry;
  mRemoved: Boolean;
begin
  FLock.Acquire;
  try
    if not FKeys.TryGetValue(AKey, mEntry) then
      raise EAtlasSettingsKey.CreateFmt('Einstellung %s ist nicht angemeldet', [AKey]);
    mRemoved := FStorage.Contains(AKey);
    if mRemoved then
      FStorage.Remove(AKey);
  finally
    FLock.Release;
  end;
  if mRemoved then
    Notify([ChangeOf(scValueChanged, mEntry.OwnerId, AKey, '')]);
end;

function TAtlasSettingsParts.StoredKeys: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mName in FStorage.Names do
      if not IsAdministrative(mName) then
        Result := Result + [mName];
  finally
    FLock.Release;
  end;
end;

initialization
  AtlasSettingsParts;

finalization
  // Die Reihenfolge gegenüber Atlas.Core.Modules.Registry ist offen: Noch angemeldete Teile trennt der Destruktor
  // ab, ein späteres Revoke aus dem Scope eines Moduls geht dann ins Leere.
  GTornDown := True;
  GParts := nil;

end.
