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
    cPartPrefix = 'module:';
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
    class function Contains(const AParts: TArray<IAtlasFeaturePart>; const APart: IAtlasFeaturePart): Boolean;
      static;
    /// <summary>Teile, die nicht mehr in AWanted stehen, stoppen und austragen.</summary>
    procedure DropWithdrawn(const AWanted: TArray<IAtlasFeaturePart>);
    /// <summary>Neuen Teil eintragen; wirft, wenn sein Name schon in der Tabelle steht.</summary>
    procedure AppendPart(const AItem: TAtlasProvided; const APart: IAtlasFeaturePart);
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

uses
  Atlas.Text.LogMarks;

{ TAtlasModuleHosting.TListener }

procedure TAtlasModuleHosting.TListener.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if FOwner = nil then
  begin
    Exit;
  end;
  case AChange.Kind of
    rcModuleAdded:
      FOwner.Added(AChange.ModuleId);
    rcModuleRemoved:
      FOwner.Removed(AChange.ModuleId);
    rcProvided, rcRevoked:
      if IsEqualGUID(AChange.IID, IAtlasFeaturePart) and FOwner.SyncParts and Assigned(FOwner.FOnChanged) then
      begin
        FOwner.FOnChanged();
      end;
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
  begin
    Exit;
  end;
  for mModule in FRegistry.Modules do
  begin
    AddPart(mModule);
  end;
  SyncParts;
  FSubscription := FRegistry.Subscribe(FListenerRef);
end;

destructor TAtlasModuleHosting.Destroy;
begin
  FListener.FOwner := nil;
  if FSubscription <> nil then
  begin
    FSubscription.Revoke;
  end;
  FSubscription := nil;
  FListenerRef := nil;
  FParts := nil;
  FRegistry := nil;
  inherited;
end;

class function TAtlasModuleHosting.PartName(const AModuleId: string): string;
begin
  Result := cPartPrefix + AModuleId;
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
  begin
    Result := mModule.Info.Switch;
  end;
end;

function TAtlasModuleHosting.IndexOfPart(const APart: IAtlasFeaturePart): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FParts) do
  begin
    if Pointer(FParts[mIndex].Part) = Pointer(APart) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasModuleHosting.Contains(const AParts: TArray<IAtlasFeaturePart>;
  const APart: IAtlasFeaturePart): Boolean;
var
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  for mPart in AParts do
  begin
    if Pointer(mPart) = Pointer(APart) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasModuleHosting.DropWithdrawn(const AWanted: TArray<IAtlasFeaturePart>);
var
  mIndex: Integer;
begin
  // Zurückgezogen: stoppen, falls es läuft, und aus der Tabelle (rückwärts).
  for mIndex := High(FParts) downto 0 do
  begin
    if Contains(AWanted, FParts[mIndex].Part) then
    begin
      Continue;
    end;
    try
      if FParts[mIndex].Part.IsActive then
      begin
        FParts[mIndex].Part.Stop;
      end;
    except
      on mError: Exception do
      begin
        FFailures := FFailures + [FParts[mIndex].Name + ': ' + mError.ClassName + ': ' +
          TLogMarks.Text(mError.Message)];
      end;
    end;
    FFeatures.Remove(FParts[mIndex].Name);
    Delete(FParts, mIndex, 1);
  end;
end;

procedure TAtlasModuleHosting.AppendPart(const AItem: TAtlasProvided; const APart: IAtlasFeaturePart);
var
  mEntry: TPartEntry;
  mSwitch: string;
begin
  mEntry.Part := APart;
  mEntry.Name := APart.Name;
  if FFeatures.Contains(mEntry.Name) then
  begin
    raise EAtlasModuleRegistry.CreateFmt('Teil %s gibt es schon (Modul %s)', [mEntry.Name, AItem.OwnerId]);
  end;
  FFeatures.AddWanted(mEntry.Name, PartWanted(APart), PartIsActive(APart), PartStart(APart), PartStop(APart));
  mSwitch := SwitchOf(AItem.OwnerId);
  if mSwitch <> '' then
  begin
    FFeatures.Join(mSwitch, [mEntry.Name]);
  end;
  FParts := FParts + [mEntry];
end;

function TAtlasModuleHosting.SyncParts: Boolean;
var
  mProvided: TArray<TAtlasProvided>;
  mItem: TAtlasProvided;
  mWanted: TArray<IAtlasFeaturePart>;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mProvided := FRegistry.Provisions(IAtlasFeaturePart);
  mWanted := nil;
  for mItem in mProvided do
  begin
    if Supports(mItem.Instance, IAtlasFeaturePart, mPart) then
    begin
      mWanted := mWanted + [mPart];
    end;
  end;
  DropWithdrawn(mWanted);
  // Neu: in Reihenfolge der Bereitstellung anhängen.
  for mItem in mProvided do
  begin
    if Supports(mItem.Instance, IAtlasFeaturePart, mPart) and (IndexOfPart(mPart) < 0) then
    begin
      AppendPart(mItem, mPart);
      Result := True;
    end;
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
  begin
    Exit;
  end;
  FFeatures.Add(mName, mInfo.MinLevel, IsActiveOf(AModule), StartOf(AModule), StopOf(AModule));
  if mInfo.Switch <> '' then
  begin
    FFeatures.Join(mInfo.Switch, [mName]);
  end;
end;

procedure TAtlasModuleHosting.Added(const AModuleId: string);
var
  mModule: IAtlasModule;
begin
  if not FRegistry.FindModule(AModuleId, mModule) then
  begin
    Exit;
  end;
  AddPart(mModule);
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

procedure TAtlasModuleHosting.Removed(const AModuleId: string);
begin
  // Die Registry hat das Modul schon gestoppt und seinen Scope gelöst.
  FFeatures.Remove(PartName(AModuleId));
end;

end.
