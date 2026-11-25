unit Atlas.IDE.Help.Adapters.Module;

// Modulklasse der Hilfe (#1886): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Help.Composition) über den Scope des Moduls bereitstellt:
// - IAtlasHelpProvider (Atlas.IDE.Base.Foundation.Help): Base fragt ihn bei F1 in Atlas-Fenstern und auf der
//   Optionsseite (TAtlasIdeHelp).
// - IAtlasKeySource: F1 im Editor mit Rückfall. Steht die Einfügemarke auf einem Atlas-Befund, öffnet F1 dessen
//   Regelseite; sonst geht die Taste an die Hilfe der IDE.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.IDE.Base.Foundation.Help;

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
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Menus,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.Core.Help.Links,
  Atlas.UI.Help.Strings,
  Atlas.IDE.Problems.Caret,
  Atlas.IDE.Help.Pages;

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

end.
