unit Atlas.Core.Diagnostics.ModuleHosting;

// Base startet die angemeldeten Module über seine Feature-Tabelle (#1455,
// ADR 0017, Regeln 1, 2 und 5):
// - Jedes Modul der Registry wird ein Teil der Tabelle („module:<Id>“) mit
//   seiner Mindeststufe des abgesicherten Starts und, falls angegeben, seinem
//   Modulschalter (#1454). Module stehen hinter den Teilen von Base: Sie
//   bauen auf dessen Diensten auf und gehen beim Abbau zuerst.
// - Meldet sich ein Modul nach dem Start von Base an, kommt es in die Tabelle,
//   und OnChanged startet, was gewünscht ist (Regel 2). Meldet es sich ab,
//   hat die Registry es schon gestoppt; der Teil verschwindet aus der Tabelle.
// - Gestartet wird nur über die Tabelle (Regel 1); das Modul selbst startet
//   nichts in seinem Register.
// - Teile eines Moduls (IAtlasFeaturePart, über seinen Scope bereitgestellt)
//   kommen in Reihenfolge der Bereitstellung hinter das Modul, mit dessen
//   Modulschalter. Zieht die Registry ein Teil zurück (Abmelden des Moduls),
//   stoppt der Wirt es, falls es läuft, und nimmt es aus der Tabelle. Beim
//   Abmelden ruft die Registry erst Stop des Moduls, dann gehen seine Teile.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.FeatureTable;

type
  TAtlasModuleHosting = class
  public const
    /// <summary>Vorsilbe der Teile in der Feature-Tabelle.</summary>
    PartPrefix = 'module:';
  private type
    TPartEntry = record
      Part: IAtlasFeaturePart;
      Name: string;
    end;

    /// <summary>Hört auf die Registry; FOwner ist nil, sobald der Wirt abgebaut wird.</summary>
    TListener = class(TInterfacedObject, IAtlasRegistryListener)
    private
      FOwner: TAtlasModuleHosting;
    public
      procedure RegistryChanged(const AChange: TAtlasRegistryChange);
    end;
  private
    FRegistry: IAtlasModuleRegistry;
    FFeatures: TAtlasFeatureTable;
    FListener: TListener;
    FListenerRef: IAtlasRegistryListener;
    FSubscription: IAtlasRegistration;
    FOnChanged: TProc;
    FParts: TArray<TPartEntry>;
    FFailures: TArray<string>;
    procedure Added(const AModuleId: string);
    procedure Removed(const AModuleId: string);
    procedure AddPart(const AModule: IAtlasModule);
    /// <summary>Teile der Tabelle mit den bereitgestellten abgleichen; True, wenn eins dazukam.</summary>
    function SyncParts: Boolean;
    function SwitchOf(const AOwnerId: string): string;
    function IndexOfPart(const APart: IAtlasFeaturePart): Integer;
    class function IsActiveOf(const AModule: IAtlasModule): TFunc<Boolean>; static;
    class function StartOf(const AModule: IAtlasModule): TProc; static;
    class function StopOf(const AModule: IAtlasModule): TProc; static;
    class function PartWanted(const APart: IAtlasFeaturePart): TAtlasFeatureWanted; static;
    class function PartIsActive(const APart: IAtlasFeaturePart): TFunc<Boolean>; static;
    class function PartStart(const APart: IAtlasFeaturePart): TProc; static;
    class function PartStop(const APart: IAtlasFeaturePart): TProc; static;
  public
    /// <summary>ARegistry und AFeatures gehören dem Aufrufer; AFeatures muss länger leben. Schon angemeldete Module
    /// kommen sofort in die Tabelle (ohne OnChanged).</summary>
    constructor Create(const ARegistry: IAtlasModuleRegistry; AFeatures: TAtlasFeatureTable);
    destructor Destroy; override;
    /// <summary>Name des Teils zu AModuleId.</summary>
    class function PartName(const AModuleId: string): string; static;
    /// <summary>Nach jeder Änderung der Tabelle durch ein spätes An- oder Abmelden: Base startet dann, was gewünscht
    /// ist (StartWanted mit der Stufe der Sitzung).</summary>
    property OnChanged: TProc read FOnChanged write FOnChanged;
    /// <summary>Fehler beim Stoppen zurückgezogener Teile als „Name: Klasse: Meldung“ seit dem letzten Abholen.
    /// </summary>
    function TakeFailures: TArray<string>;
  end;

implementation

{ TAtlasModuleHosting.TListener }

procedure TAtlasModuleHosting.TListener.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if FOwner = nil then
    Exit;
  case AChange.Kind of
    rcModuleAdded:
      FOwner.Added(AChange.ModuleId);
    rcModuleRemoved:
      FOwner.Removed(AChange.ModuleId);
    rcProvided, rcRevoked:
      if IsEqualGUID(AChange.IID, IAtlasFeaturePart) and FOwner.SyncParts and Assigned(FOwner.FOnChanged) then
        FOwner.FOnChanged();
  else
    // Bereitstellungen und die Liste bekannter Module ändern die Tabelle nicht.
  end;
end;

{ TAtlasModuleHosting }

constructor TAtlasModuleHosting.Create(const ARegistry: IAtlasModuleRegistry; AFeatures: TAtlasFeatureTable);
var
  mModule: IAtlasModule;
begin
  inherited Create;
  FRegistry := ARegistry;
  FFeatures := AFeatures;
  FListener := TListener.Create;
  FListener.FOwner := Self;
  FListenerRef := FListener;
  if FRegistry = nil then
    Exit;
  for mModule in FRegistry.Modules do
    AddPart(mModule);
  SyncParts;
  FSubscription := FRegistry.Subscribe(FListenerRef);
end;

destructor TAtlasModuleHosting.Destroy;
begin
  FListener.FOwner := nil;
  if FSubscription <> nil then
    FSubscription.Revoke;
  FSubscription := nil;
  FListenerRef := nil;
  FParts := nil;
  FRegistry := nil;
  inherited;
end;

class function TAtlasModuleHosting.PartName(const AModuleId: string): string;
begin
  Result := PartPrefix + AModuleId;
end;

class function TAtlasModuleHosting.IsActiveOf(const AModule: IAtlasModule): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AModule.IsActive;
    end;
end;

class function TAtlasModuleHosting.StartOf(const AModule: IAtlasModule): TProc;
begin
  Result :=
    procedure
    begin
      AModule.Start;
    end;
end;

class function TAtlasModuleHosting.StopOf(const AModule: IAtlasModule): TProc;
begin
  Result :=
    procedure
    begin
      AModule.Stop;
    end;
end;

class function TAtlasModuleHosting.PartWanted(const APart: IAtlasFeaturePart): TAtlasFeatureWanted;
begin
  Result :=
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := APart.Wanted(ALevel);
    end;
end;

class function TAtlasModuleHosting.PartIsActive(const APart: IAtlasFeaturePart): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := APart.IsActive;
    end;
end;

class function TAtlasModuleHosting.PartStart(const APart: IAtlasFeaturePart): TProc;
begin
  Result :=
    procedure
    begin
      APart.Start;
    end;
end;

class function TAtlasModuleHosting.PartStop(const APart: IAtlasFeaturePart): TProc;
begin
  Result :=
    procedure
    begin
      APart.Stop;
    end;
end;

function TAtlasModuleHosting.SwitchOf(const AOwnerId: string): string;
var
  mModule: IAtlasModule;
begin
  Result := '';
  if (AOwnerId <> '') and FRegistry.FindModule(AOwnerId, mModule) then
    Result := mModule.Info.Switch;
end;

function TAtlasModuleHosting.IndexOfPart(const APart: IAtlasFeaturePart): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FParts) do
    if Pointer(FParts[mIndex].Part) = Pointer(APart) then
      Exit(mIndex);
end;

function TAtlasModuleHosting.SyncParts: Boolean;
var
  mProvided: TArray<TAtlasProvided>;
  mItem: TAtlasProvided;
  mWanted: TArray<IAtlasFeaturePart>;
  mPart: IAtlasFeaturePart;
  mIndex: Integer;
  mFound: Boolean;
  mEntry: TPartEntry;
  mSwitch: string;
begin
  Result := False;
  mProvided := FRegistry.Provisions(IAtlasFeaturePart);
  mWanted := nil;
  for mItem in mProvided do
    if Supports(mItem.Instance, IAtlasFeaturePart, mPart) then
      mWanted := mWanted + [mPart];
  // Zurückgezogen: stoppen, falls es läuft, und aus der Tabelle (rückwärts).
  for mIndex := High(FParts) downto 0 do
  begin
    mFound := False;
    for mPart in mWanted do
      if Pointer(mPart) = Pointer(FParts[mIndex].Part) then
        mFound := True;
    if mFound then
      Continue;
    try
      if FParts[mIndex].Part.IsActive then
        FParts[mIndex].Part.Stop;
    except
      on mError: Exception do
        FFailures := FFailures + [FParts[mIndex].Name + ': ' + mError.ClassName + ': ' + mError.Message];
    end;
    FFeatures.Remove(FParts[mIndex].Name);
    Delete(FParts, mIndex, 1);
  end;
  // Neu: in Reihenfolge der Bereitstellung anhängen.
  for mItem in mProvided do
  begin
    if not Supports(mItem.Instance, IAtlasFeaturePart, mPart) or (IndexOfPart(mPart) >= 0) then
      Continue;
    mEntry.Part := mPart;
    mEntry.Name := mPart.Name;
    if FFeatures.Contains(mEntry.Name) then
      raise EAtlasModuleRegistry.CreateFmt('Teil %s gibt es schon (Modul %s)', [mEntry.Name, mItem.OwnerId]);
    FFeatures.AddWanted(mEntry.Name, PartWanted(mPart), PartIsActive(mPart), PartStart(mPart), PartStop(mPart));
    mSwitch := SwitchOf(mItem.OwnerId);
    if mSwitch <> '' then
      FFeatures.Join(mSwitch, [mEntry.Name]);
    FParts := FParts + [mEntry];
    Result := True;
  end;
end;

function TAtlasModuleHosting.TakeFailures: TArray<string>;
begin
  Result := FFailures;
  FFailures := nil;
end;

procedure TAtlasModuleHosting.AddPart(const AModule: IAtlasModule);
var
  mInfo: TAtlasModuleInfo;
  mName: string;
begin
  mInfo := AModule.Info;
  mName := PartName(mInfo.Id);
  if FFeatures.Contains(mName) then
    Exit;
  FFeatures.Add(mName, mInfo.MinLevel, IsActiveOf(AModule), StartOf(AModule), StopOf(AModule));
  if mInfo.Switch <> '' then
    FFeatures.Join(mInfo.Switch, [mName]);
end;

procedure TAtlasModuleHosting.Added(const AModuleId: string);
var
  mModule: IAtlasModule;
begin
  if not FRegistry.FindModule(AModuleId, mModule) then
    Exit;
  AddPart(mModule);
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TAtlasModuleHosting.Removed(const AModuleId: string);
begin
  // Die Registry hat das Modul schon gestoppt und seinen Scope gelöst.
  FFeatures.Remove(PartName(AModuleId));
end;

end.
