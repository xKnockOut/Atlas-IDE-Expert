unit Atlas.IDE.Designer.Composition;

// Modul Designer (#1455, ADR 0017): einzige Unit, die die Designer-Leiste
// (#1442) über dem Formular-Designer erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.designer“ (Modulschalter designer, #1454)
// bei der Registry von Base an und stellt über dessen Scope den Teil
// DesignerBar der Feature-Tabelle und Hörer für Einstellungen und Thema
// bereit. Die Benachrichtigungen des Designers (#722, Teil Forms) bleiben in
// Base. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasDesignerModule = class(TInterfacedObject, IAtlasModule, IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    ModuleId = 'atlas.designer';
    Switch = 'designer';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    procedure ApplySettings;
    procedure ThemeChanged;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Designer.Bar;

var
  GScope: IAtlasModuleScope;
  GBarStarted: Boolean;

procedure ShowMessage(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure StartDesignerBar;
var
  mHooks: TAtlasIdeDesignerBar.THooks;
begin
  mHooks := Default(TAtlasIdeDesignerBar.THooks);
  mHooks.Message := ShowMessage;
  TAtlasIdeDesignerBar.Install(mHooks);
  GBarStarted := True;
end;

procedure StopDesignerBar;
begin
  GBarStarted := False;
  TAtlasIdeDesignerBar.Uninstall;
end;

function DesignerBarStarted: Boolean;
begin
  Result := GBarStarted;
end;

{ TAtlasDesignerModule }

function TAtlasDesignerModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Designer';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Die Leiste lief mit den Editorbefehlen schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
end;

procedure TAtlasDesignerModule.Start;
begin
  FActive := True;
end;

procedure TAtlasDesignerModule.Stop;
begin
  FActive := False;
end;

function TAtlasDesignerModule.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TAtlasDesignerModule.ApplySettings;
begin
  // editor.designerBar.* (#1442).
  TAtlasIdeDesignerBar.ApplySettings;
end;

procedure TAtlasDesignerModule.ThemeChanged;
begin
  TAtlasIdeDesignerBar.ThemeChanged;
end;

class function TAtlasDesignerModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // Designer-Leiste (#1442): ab abgesichertem Start und solange editor.designerBar an ist.
  Result := [
    TAtlasFeaturePart.When('DesignerBar',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.EditorDesignerBar;
      end, DesignerBarStarted, StartDesignerBar, StopDesignerBar)];
end;

class function TAtlasDesignerModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDesignerModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasDesignerModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
    GScope.Provide(IAtlasFeaturePart, mPart);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  Result := True;
end;

class procedure TAtlasDesignerModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasDesignerModule.RegisterModule;

finalization
  TAtlasDesignerModule.UnregisterModule;

end.
