unit Atlas.IDE.Designer.OpenWatch;

// Zählt offene Formular-Designer (IDesignNotification), damit Takte des
// Designer-Moduls nur laufen, solange es einen gibt: Designer-Leiste (200 ms)
// und Desktop-Layout (100 ms) liefen vorher auch auf der Willkommensseite.
// - Beim Anlegen zählt die Unit schon offene Formulare (Plugin nach dem
//   Projekt geladen), danach DesignerOpened/DesignerClosed.
// - AOnChange kommt, wenn sich „mindestens einer offen“ ändert; der Besitzer
//   schaltet damit seinen Timer und räumt beim letzten Schließen ab.
// Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasDesignerOpenWatch = class
  private
    FNotification: TObject;
    FNotificationRef: IInterface;
    FCount: Integer;
    FOnChange: TProc;
    procedure Opened;
    procedure Closed;
  public
    /// <summary>AOnChange: Wechsel zwischen „kein Designer“ und „mindestens einer“.</summary>
    constructor Create(const AOnChange: TProc);
    destructor Destroy; override;
    /// <summary>Ist mindestens ein Formular-Designer offen?</summary>
    function Any: Boolean;
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  DesignIntf;

type
  TNotification = class(TInterfacedObject, IDesignNotification)
  private
    FOwner: TAtlasDesignerOpenWatch;
  public
    procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemsModified(const ADesigner: IDesigner);
    procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
    procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
    procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
  end;

/// <summary>Offene Module mit Formular-Editor (beim Start schon geladene Formulare).</summary>
function OpenFormCount: Integer;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mFormEditor: IOTAFormEditor;
  mModuleIndex, mFileIndex: Integer;
begin
  Result := 0;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mModuleIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mModuleIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mFileIndex], IOTAFormEditor, mFormEditor) then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

{ TNotification }

procedure TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TNotification.ItemsModified(const ADesigner: IDesigner);
begin
end;

procedure TNotification.SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
begin
end;

procedure TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Opened;
  end;
end;

procedure TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Closed;
  end;
end;

{ TAtlasDesignerOpenWatch }

constructor TAtlasDesignerOpenWatch.Create(const AOnChange: TProc);
var
  mNotification: TNotification;
begin
  inherited Create;
  FOnChange := AOnChange;
  FCount := OpenFormCount;
  mNotification := TNotification.Create;
  mNotification.FOwner := Self;
  FNotification := mNotification;
  FNotificationRef := mNotification as IDesignNotification;
  RegisterDesignNotification(FNotificationRef as IDesignNotification);
end;

destructor TAtlasDesignerOpenWatch.Destroy;
begin
  TNotification(FNotification).FOwner := nil;
  UnregisterDesignNotification(FNotificationRef as IDesignNotification);
  FNotificationRef := nil;
  FOnChange := nil;
  inherited Destroy;
end;

function TAtlasDesignerOpenWatch.Any: Boolean;
begin
  Result := FCount > 0;
end;

procedure TAtlasDesignerOpenWatch.Opened;
begin
  Inc(FCount);
  if (FCount = 1) and Assigned(FOnChange) then
  begin
    FOnChange();
  end;
end;

procedure TAtlasDesignerOpenWatch.Closed;
begin
  if FCount = 0 then
  begin
    Exit;
  end;
  Dec(FCount);
  if (FCount = 0) and Assigned(FOnChange) then
  begin
    FOnChange();
  end;
end;

end.
