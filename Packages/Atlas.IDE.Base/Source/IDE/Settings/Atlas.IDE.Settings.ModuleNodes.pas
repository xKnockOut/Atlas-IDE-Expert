unit Atlas.IDE.Settings.ModuleNodes;

// Knoten je Package unter Tools › Optionen › Atlas › Module (#1903, INTAAddInOptions):
// - „Module“ selbst zeigt alle bekannten Module mit Version und ob sie installiert sind.
// - Darunter „Base“ und je angemeldetem Modul ein Knoten (Caption „Atlas.Module.<Name>“: Der zweite Punkt
//   hängt ihn unter „Module“), alphabetisch. Die Seiten baut der Aufrufer (AFactory).
// - Kommt oder geht ein Modul, meldet die Liste alle Modulknoten ab und sortiert neu an (Modulregel 2);
//   Delphi ordnet die Knoten in der Reihenfolge der Anmeldung. Base kennt keine Modulnamen (Regel 9): Namen
//   und Ids kommen aus der Registry.

interface

uses
  System.Classes,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Modules.Contract;

type
  /// <summary>Seite eines Moduls im Optionsdialog.</summary>
  TAtlasModuleNodeFactory = reference to function(const AInfo: TAtlasModuleInfo): INTAAddInOptions;

  /// <summary>Seite „Module“: bekannte Module mit Version und Zustand.</summary>
  TAtlasModuleNodePage = class(TFrame)
  public
    procedure ShowModules(const AModules: TArray<TAtlasKnownModule>);
  end;

  TAtlasModuleNodes = class
  public
    /// <summary>Meldet „Module“, ABase und die Knoten der angemeldeten Module an und hört auf die Registry.
    /// </summary>
    class procedure Start(const ABase: INTAAddInOptions; const AFactory: TAtlasModuleNodeFactory); static;
    class procedure Stop; static;
    /// <summary>Caption eines Knotens unter „Module“.</summary>
    class function CaptionOf(const AName: string): string; static;
    /// <summary>Knoten des Moduls mit dem Schalter ASwitch ('' = Base); nil, wenn es nicht angemeldet ist.
    /// </summary>
    class function NodeOfSwitch(const ASwitch: string): INTAAddInOptions; static;
    /// <summary>Name des Moduls mit dem Schalter ASwitch; '' wenn unbekannt.</summary>
    class function NameOfSwitch(const ASwitch: string): string; static;
  end;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Strings;

type
  TAtlasModuleListOptions = class(TInterfacedObject, INTAAddInOptions)
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  TAtlasModuleNodeWatch = class(TInterfacedObject, IAtlasRegistryListener)
  public
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
  end;

var
  ListNode: INTAAddInOptions;
  BaseNode: INTAAddInOptions;
  Factory: TAtlasModuleNodeFactory;
  /// <summary>Angemeldete Modulknoten und die Ids dazu, gleicher Index.</summary>
  Nodes: TArray<INTAAddInOptions>;
  NodeIds: TArray<string>;
  NodeSwitches: TArray<string>;
  Subscription: IAtlasRegistration;

function Services(out AServices: INTAEnvironmentOptionsServices): Boolean;
begin
  Result := Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, AServices);
end;

procedure DropNodes;
var
  mServices: INTAEnvironmentOptionsServices;
  mNode: INTAAddInOptions;
begin
  if Services(mServices) then
  begin
    for mNode in Nodes do
    begin
      mServices.UnregisterAddInOptions(mNode);
    end;
  end;
  Nodes := nil;
  NodeIds := nil;
  NodeSwitches := nil;
end;

function SortedModules: TArray<TAtlasModuleInfo>;
var
  mModule: IAtlasModule;
begin
  Result := nil;
  for mModule in AtlasModuleRegistry.Modules do
  begin
    Result := Result + [mModule.Info];
  end;
  TArray.Sort<TAtlasModuleInfo>(Result, TComparer<TAtlasModuleInfo>.Construct(
    function(const ALeft, ARight: TAtlasModuleInfo): Integer
    begin
      Result := CompareText(ALeft.Name, ARight.Name);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Id, ARight.Id);
      end;
    end));
end;

function SameIds(const AModules: TArray<TAtlasModuleInfo>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AModules) = Length(NodeIds);
  for mIndex := 0 to High(AModules) do
  begin
    Result := Result and SameText(AModules[mIndex].Id, NodeIds[mIndex]);
  end;
end;

procedure Sync;
var
  mServices: INTAEnvironmentOptionsServices;
  mModules: TArray<TAtlasModuleInfo>;
  mInfo: TAtlasModuleInfo;
  mNode: INTAAddInOptions;
begin
  if not Assigned(Factory) or not Services(mServices) then
  begin
    Exit;
  end;
  mModules := SortedModules;
  if SameIds(mModules) then
  begin
    Exit;
  end;
  // Alle neu in Namensfolge: Delphi zeigt die Knoten in der Reihenfolge der Anmeldung.
  DropNodes;
  for mInfo in mModules do
  begin
    mNode := Factory(mInfo);
    mServices.RegisterAddInOptions(mNode);
    Nodes := Nodes + [mNode];
    NodeIds := NodeIds + [mInfo.Id];
    NodeSwitches := NodeSwitches + [mInfo.Switch];
  end;
end;

{ TAtlasModuleNodePage }

procedure TAtlasModuleNodePage.ShowModules(const AModules: TArray<TAtlasKnownModule>);
var
  mModule: TAtlasKnownModule;
  mTop: Integer;
  mLabel: TLabel;
  mState: string;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.Left := 12;
  mLabel.Top := 12;
  mLabel.Font.Style := [fsBold];
  mLabel.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesTitle);
  mTop := 40;
  for mModule in AModules do
  begin
    if mModule.Installed then
    begin
      mState := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModuleInstalled);
    end
    else
    begin
      mState := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModuleMissing);
    end;
    mLabel := TLabel.Create(Self);
    mLabel.Parent := Self;
    mLabel.Left := 12;
    mLabel.Top := mTop;
    mLabel.ShowAccelChar := False;
    mLabel.Caption := Format('%s  %s  (%s)', [mModule.Info.Name, mModule.Info.Version, mState]);
    Inc(mTop, 22);
  end;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.Left := 12;
  mLabel.Top := mTop + 12;
  mLabel.Font.Style := [fsItalic];
  mLabel.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesHint);
end;

{ TAtlasModuleListOptions }

function TAtlasModuleListOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasModuleListOptions.GetCaption: string;
begin
  Result := 'Atlas.' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesNode);
end;

function TAtlasModuleListOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasModuleNodePage;
end;

procedure TAtlasModuleListOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    (AFrame as TAtlasModuleNodePage).ShowModules(AtlasModuleRegistry.Known);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasModuleListOptions.DialogClosed(Accepted: Boolean);
begin
  // Nur Anzeige.
end;

function TAtlasModuleListOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasModuleListOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasModuleListOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasModuleNodeWatch }

procedure TAtlasModuleNodeWatch.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if AChange.Kind in [rcModuleAdded, rcModuleRemoved] then
  begin
    TAtlasGuard.Run(TAtlasFeature.Settings, Sync);
  end;
end;

{ TAtlasModuleNodes }

class function TAtlasModuleNodes.CaptionOf(const AName: string): string;
begin
  // Zwei Punkte: Atlas › Module › <Name>.
  Result := 'Atlas.' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesNode) + '.' + AName;
end;

class function TAtlasModuleNodes.NodeOfSwitch(const ASwitch: string): INTAAddInOptions;
var
  mIndex: Integer;
begin
  if ASwitch = '' then
  begin
    Exit(BaseNode);
  end;
  for mIndex := 0 to High(NodeSwitches) do
  begin
    if SameText(NodeSwitches[mIndex], ASwitch) then
    begin
      Exit(Nodes[mIndex]);
    end;
  end;
  Result := nil;
end;

class function TAtlasModuleNodes.NameOfSwitch(const ASwitch: string): string;
var
  mModule: TAtlasKnownModule;
begin
  for mModule in AtlasModuleRegistry.Known do
  begin
    if (ASwitch <> '') and SameText(mModule.Info.Switch, ASwitch) then
    begin
      Exit(mModule.Info.Name);
    end;
  end;
  Result := '';
end;

class procedure TAtlasModuleNodes.Start(const ABase: INTAAddInOptions; const AFactory: TAtlasModuleNodeFactory);
var
  mServices: INTAEnvironmentOptionsServices;
begin
  if (ListNode <> nil) or not Services(mServices) then
  begin
    Exit;
  end;
  Factory := AFactory;
  ListNode := TAtlasModuleListOptions.Create;
  mServices.RegisterAddInOptions(ListNode);
  BaseNode := ABase;
  if BaseNode <> nil then
  begin
    mServices.RegisterAddInOptions(BaseNode);
  end;
  Subscription := AtlasModuleRegistry.Subscribe(TAtlasModuleNodeWatch.Create);
  Sync;
end;

class procedure TAtlasModuleNodes.Stop;
var
  mServices: INTAEnvironmentOptionsServices;
begin
  if Subscription <> nil then
  begin
    Subscription.Revoke;
    Subscription := nil;
  end;
  DropNodes;
  if Services(mServices) then
  begin
    if BaseNode <> nil then
    begin
      mServices.UnregisterAddInOptions(BaseNode);
    end;
    if ListNode <> nil then
    begin
      mServices.UnregisterAddInOptions(ListNode);
    end;
  end;
  BaseNode := nil;
  ListNode := nil;
  Factory := nil;
end;

end.
