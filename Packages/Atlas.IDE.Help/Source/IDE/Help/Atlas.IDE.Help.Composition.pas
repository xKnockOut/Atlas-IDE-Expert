unit Atlas.IDE.Help.Composition;

// Modul Hilfe (#1886): einzige Unit, die F1 zu Atlas-Elementen beantwortet. Sie meldet in ihrer
// Initialisierung das Modul „atlas.help“ (Modulschalter help) bei der Registry von Base an und stellt über dessen
// Scope bereit:
// - IAtlasHelpProvider (Atlas.IDE.Contracts.Help): Base fragt ihn bei F1 in Atlas-Fenstern und auf der
//   Optionsseite (TAtlasIdeHelp).
// - IAtlasKeySource: F1 im Editor mit Rückfall. Steht die Einfügemarke auf einem Atlas-Befund, öffnet F1 dessen
//   Regelseite; sonst geht die Taste an die Hilfe der IDE.
// - den Abschnitt „Allgemein“ im Optionsdialog (help.enabled, help.source).
// Ist das Modul aus, liefert Base die Beiträge nicht mehr; F1 verhält sich dann wie ohne Atlas. Abmelden in der
// Finalisierung, solange Base läuft (Regel 5); passt die Vertragsversion von Base nicht, meldet sich das Modul nicht
// an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.Help;

type
  TAtlasHelpModule = class(TInterfacedObject, IAtlasModule, IAtlasHelpProvider, IAtlasKeySource)
  public const
    cModuleId = 'atlas.help';
    cSwitch = 'help';
    cFindingKeyId = 'Atlas.HelpFinding';
  private
    FActive: Boolean;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function HasHelp(const ATopic: TAtlasHelpTopic): Boolean;
    function ShowHelp(const ATopic: TAtlasHelpTopic): Boolean;
    function Keys: TArray<TAtlasModuleKey>;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Menus,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Help.Links,
  Atlas.UI.Help.Strings,
  Atlas.UI.Help.SettingsSection,
  Atlas.IDE.Problems.Caret,
  Atlas.IDE.Help.Pages;

var
  GScope: IAtlasModuleScope;

/// <summary>F1 im Editor: Regelseite des Atlas-Befunds an der Einfügemarke; False = Taste an die IDE.</summary>
function FindingHelp: Boolean;
var
  mRule: string;
  mTopic: TAtlasHelpTopic;
begin
  Result := False;
  if TAtlasIdeProblemAtCaret.Rule(mRule) then
  begin
    mTopic.Kind := TAtlasHelpKind.Rule;
    mTopic.Id := mRule;
    Result := TAtlasIdeHelpPages.Show(mTopic);
  end;
end;

{ TAtlasHelpModule }

function TAtlasHelpModule.Info: TAtlasModuleInfo;
begin
  // Nur Verweise auf die Doku, kein Editoreingriff: auch im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Help', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;

procedure TAtlasHelpModule.Start;
begin
  FActive := True;
end;

procedure TAtlasHelpModule.Stop;
begin
  FActive := False;
end;

function TAtlasHelpModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasHelpModule.HasHelp(const ATopic: TAtlasHelpTopic): Boolean;
var
  mTarget: TAtlasHelpTarget;
begin
  Result := FActive and TAtlasIdeHelpPages.TargetOf(ATopic, mTarget);
end;

function TAtlasHelpModule.ShowHelp(const ATopic: TAtlasHelpTopic): Boolean;
begin
  Result := FActive and TAtlasIdeHelpPages.Show(ATopic);
end;

function TAtlasHelpModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  mKey := Default(TAtlasModuleKey);
  mKey.Id := cFindingKeyId;
  mKey.Caption := TAtlasHelpStrings.Text(TAtlasHelpTextId.KeyFindingHelp);
  mKey.Key := ShortCut(VK_F1, []);
  // Vorrang vor der Hilfe der IDE, aber nur auf einem Befund: ohne Befund geht F1 weiter (Attempt = False).
  mKey.Priority := TAtlasKeyPriority.Take;
  mKey.Attempt := FindingHelp;
  Result := [mKey];
end;

class function TAtlasHelpModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasHelpModule;
  mRef: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasHelpModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  GScope.Provide(IAtlasHelpProvider, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  // Ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  TAtlasHelpSettingsSection.ProvideIn(GScope);
  Result := True;
end;

class procedure TAtlasHelpModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
end;

initialization
  TAtlasHelpModule.RegisterModule;

finalization
  TAtlasHelpModule.UnregisterModule;

end.
