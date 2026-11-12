unit Atlas.IDE.Generate.Gallery;

// Kategorie „Atlas“ in Datei › Neu › Weitere (#1821, generate.galleryWizards).
// Die Assistenten bieten die Module als Menüeinträge mit
// TAtlasMenuPlace.Gallery an (Atlas.Core.Generate.Gallery); Base meldet je
// Eintrag einen IOTARepositoryWizard80 unter der Kategorie „Atlas“ an
// (IOTAGalleryCategoryManager, unter „Delphi-Projekte“ bzw. „Delphi
// Projects“ der IDE) und baut die Liste neu, wenn sich die Registry ändert
// (Modul an- oder abgemeldet, Beitrag bereitgestellt oder zurückgezogen) und
// nach geänderten Einstellungen (Modulschalter, generate.galleryWizards; aus
// = keine Assistenten und keine Kategorie). Ein Assistent sucht beim
// Ausführen seinen Befehl über die Id neu: Ein abgemeldetes Modul erreicht er
// nicht mehr (Regel 3). Uninstall meldet alle Assistenten ab und löscht die
// Kategorie, damit die Galerie nach dem Entladen keine toten Einträge behält.
// Nur im Hauptthread verwenden.

interface

type
  TAtlasIdeGallery = class
  public
    /// <summary>Auf die Registry hören und angleichen (Refresh).</summary>
    class procedure Install; static;
    /// <summary>Assistenten an die laufenden Module und die Einstellung angleichen (nur bei geänderter Liste neu
    /// anmelden); ohne Assistenten auch ohne Kategorie.</summary>
    class procedure Refresh; static;
    /// <summary>Assistenten abmelden, Kategorie löschen, nicht mehr hören.</summary>
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Generate.Gallery,
  Atlas.IDE.Foundation.Settings;

type
  /// <summary>Ein Assistent der Galerie; die IDE hält ihn bis RemoveWizard.</summary>
  TGalleryWizard = class(TNotifierObject, IOTAWizard, IOTARepositoryWizard, IOTARepositoryWizard60,
    IOTARepositoryWizard80, IOTAFormWizard)
  private
    FItem: TAtlasGalleryItem;
  public
    constructor Create(const AItem: TAtlasGalleryItem);
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    { IOTARepositoryWizard }
    function GetAuthor: string;
    function GetComment: string;
    function GetPage: string;
    function GetGlyph: THandle;
    { IOTARepositoryWizard60 }
    function GetDesigner: string;
    { IOTARepositoryWizard80 }
    function GetGalleryCategory: IOTAGalleryCategory;
    function GetPersonality: string;
  end;

  /// <summary>Hört auf die Registry und gleicht die Assistenten an.</summary>
  TGalleryWatch = class(TInterfacedObject, IAtlasRegistryListener)
  public
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
  end;

var
  GInstalled: Boolean;
  GCategory: IOTAGalleryCategory;
  GItems: TArray<TAtlasGalleryItem>;
  /// <summary>Indizes von IOTAWizardServices.AddWizard in Reihenfolge von GItems.</summary>
  GWizards: TArray<Integer>;
  GSubscription: IAtlasRegistration;

/// <summary>Assistenten der laufenden Module; leer, wenn die Einstellung aus ist.</summary>
function CurrentItems: TArray<TAtlasGalleryItem>;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.Enabled or not TAtlasIdeSettings.Current.GalleryWizards or
    TAtlasGuard.Disabled(TAtlasFeature.Generate) then
  begin
    Exit;
  end;
  Result := TAtlasGallery.Items(TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.Gallery),
    TAtlasModuleContributions.Commands(AtlasModuleRegistry));
end;

procedure RemoveWizards;
var
  mServices: IOTAWizardServices;
  mIndex: Integer;
begin
  if Supports(BorlandIDEServices, IOTAWizardServices, mServices) then
  begin
    for mIndex := High(GWizards) downto 0 do
    begin
      mServices.RemoveWizard(GWizards[mIndex]);
    end;
  end;
  GWizards := nil;
  GItems := nil;
end;

procedure AddWizards(const AItems: TArray<TAtlasGalleryItem>);
var
  mServices: IOTAWizardServices;
  mItem: TAtlasGalleryItem;
begin
  GItems := AItems;
  if not Supports(BorlandIDEServices, IOTAWizardServices, mServices) then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    GWizards := GWizards + [mServices.AddWizard(TGalleryWizard.Create(mItem))];
  end;
end;

procedure CreateCategory;
var
  mManager: IOTAGalleryCategoryManager;
begin
  if (GCategory <> nil) or not Supports(BorlandIDEServices, IOTAGalleryCategoryManager, mManager) then
  begin
    Exit;
  end;
  GCategory := mManager.FindCategory(TAtlasGallery.cCategoryId);
  if GCategory = nil then
  begin
    GCategory := mManager.AddCategory(mManager.FindCategory(sCategoryDelphiNew), TAtlasGallery.cCategoryId,
      TAtlasGallery.cCategoryName);
  end;
end;

procedure DeleteCategory;
var
  mManager: IOTAGalleryCategoryManager;
begin
  if (GCategory <> nil) and Supports(BorlandIDEServices, IOTAGalleryCategoryManager, mManager) then
  begin
    mManager.DeleteCategory(GCategory);
  end;
  GCategory := nil;
end;

/// <summary>Befehl des Assistenten ausführen; der Befehl wird neu gesucht.</summary>
procedure RunCommand(const ACommandId: string);
var
  mCommand: TAtlasModuleCommand;
begin
  if not GInstalled or not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, ACommandId, mCommand) or
    not Assigned(mCommand.Run) then
  begin
    TAtlasGuard.Log('Gallery: command ' + ACommandId + ' is gone');
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.Generate, mCommand.Run);
end;

{ TGalleryWizard }

constructor TGalleryWizard.Create(const AItem: TAtlasGalleryItem);
begin
  inherited Create;
  FItem := AItem;
end;

function TGalleryWizard.GetIDString: string;
begin
  Result := TAtlasGallery.WizardId(FItem.CommandId);
end;

function TGalleryWizard.GetName: string;
begin
  Result := FItem.Caption;
end;

function TGalleryWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TGalleryWizard.Execute;
begin
  RunCommand(FItem.CommandId);
end;

function TGalleryWizard.GetAuthor: string;
begin
  Result := TAtlasGallery.cCategoryName;
end;

function TGalleryWizard.GetComment: string;
begin
  Result := FItem.Comment;
end;

function TGalleryWizard.GetPage: string;
begin
  Result := TAtlasGallery.cCategoryName;
end;

function TGalleryWizard.GetGlyph: THandle;
begin
  // 0: Symbol der IDE für Assistenten.
  Result := 0;
end;

function TGalleryWizard.GetDesigner: string;
begin
  Result := dAny;
end;

function TGalleryWizard.GetGalleryCategory: IOTAGalleryCategory;
begin
  Result := GCategory;
end;

function TGalleryWizard.GetPersonality: string;
begin
  Result := sDelphiPersonality;
end;

{ TGalleryWatch }

procedure RefreshGallery;
begin
  TAtlasIdeGallery.Refresh;
end;

procedure TGalleryWatch.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if AChange.Kind in [rcModuleAdded, rcModuleRemoved, rcProvided, rcRevoked] then
  begin
    TAtlasGuard.Run(TAtlasFeature.Generate, RefreshGallery);
  end;
end;

{ TAtlasIdeGallery }

class procedure TAtlasIdeGallery.Install;
begin
  if GInstalled then
  begin
    Exit;
  end;
  GInstalled := True;
  GSubscription := AtlasModuleRegistry.Subscribe(TGalleryWatch.Create);
  Refresh;
end;

class procedure TAtlasIdeGallery.Refresh;
var
  mItems: TArray<TAtlasGalleryItem>;
begin
  if not GInstalled then
  begin
    Exit;
  end;
  mItems := CurrentItems;
  if TAtlasGallery.Same(mItems, GItems) and (Length(GWizards) = Length(GItems)) then
  begin
    Exit;
  end;
  RemoveWizards;
  if mItems = nil then
  begin
    DeleteCategory;
    Exit;
  end;
  CreateCategory;
  AddWizards(mItems);
end;

class procedure TAtlasIdeGallery.Uninstall;
begin
  if not GInstalled then
  begin
    Exit;
  end;
  GInstalled := False;
  if GSubscription <> nil then
  begin
    GSubscription.Revoke;
    GSubscription := nil;
  end;
  RemoveWizards;
  DeleteCategory;
end;

class function TAtlasIdeGallery.Installed: Boolean;
begin
  Result := GInstalled;
end;

end.
