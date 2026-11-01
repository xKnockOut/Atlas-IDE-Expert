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
    procedure Added(const AModuleId: string);
    procedure Removed(const AModuleId: string);
    procedure AddPart(const AModule: IAtlasModule);
    class function IsActiveOf(const AModule: IAtlasModule): TFunc<Boolean>; static;
    class function StartOf(const AModule: IAtlasModule): TProc; static;
    class function StopOf(const AModule: IAtlasModule): TProc; static;
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
  FSubscription := FRegistry.Subscribe(FListenerRef);
end;

destructor TAtlasModuleHosting.Destroy;
begin
  FListener.FOwner := nil;
  if FSubscription <> nil then
    FSubscription.Revoke;
  FSubscription := nil;
  FListenerRef := nil;
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
