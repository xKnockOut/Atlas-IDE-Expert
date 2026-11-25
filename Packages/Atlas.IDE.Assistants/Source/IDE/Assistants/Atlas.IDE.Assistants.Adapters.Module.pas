unit Atlas.IDE.Assistants.Adapters.Module;

// Modulklasse der KI-Assistenten (#1888): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Assistants.Composition) über den Scope des Moduls bereitstellt: die Befehle „Pause für
// KI-Assistenten“ (#1906), „Auswahl an den Assistenten“ (#2377) und „KI-Protokoll“ (#2049), den Eintrag im
// Kontextmenü des Editors, die Taste, Einstellungen und Thema an die laufenden Teile und den letzten Build für den
// IDE-Zustand (#2050). Die Teile der Feature-Tabelle baut die Composition; sie reicht den Zugriff darauf als
// TAtlasAssistantsModuleHooks herein.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Plugin.Build.Contract,
  Atlas.IDE.Assistants.DebugBar,
  Atlas.IDE.Assistants.ContextExport;

type
  /// <summary>Was die Modulklasse von den Teilen der Composition braucht.</summary>
  TAtlasAssistantsModuleHooks = record
    /// <summary>Pause für KI-Assistenten ein bzw. aus (#1906); Paused liefert den Stand.</summary>
    TogglePause: TProc;
    Paused: TFunc<Boolean>;
    /// <summary>Fenster „KI-Protokoll“ zeigen (#2049).</summary>
    ShowLog: TProc;
    /// <summary>Auswahl an den verbundenen Assistenten (#2377), abgesichert; sichtbar nur mit Verbindung.</summary>
    Mention: TProc;
    MentionVisible: TFunc<Boolean>;
    /// <summary>Geänderte Einstellungen an die laufenden Teile (Debuggen, Kopplung, Protokoll).</summary>
    ApplySettings: TProc;
    /// <summary>Leiste beim Debuggen (#1874) bzw. Zustand der IDE (#2050); nil, solange ihr Teil nicht läuft.
    /// </summary>
    DebugBar: TFunc<TAtlasIdeAssistantDebugBar>;
    Context: TFunc<TAtlasIdeContextExport>;
  end;

  TAtlasAssistantsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasBuildVerdictListener)
  public const
    cModuleId = 'atlas.assistants';
    cSwitch = 'assistants';
  private
    FActive: Boolean;
    FHooks: TAtlasAssistantsModuleHooks;
    function PauseCaption: string;
  public
    constructor Create(const AHooks: TAtlasAssistantsModuleHooks);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    procedure ApplySettings;
    procedure ThemeChanged;
    /// <summary>Befehl „Pause für KI-Assistenten“ (#1906).</summary>
    function Commands: TArray<TAtlasModuleCommand>;
    /// <summary>„Auswahl an den Assistenten“ im Kontextmenü des Editors (#2377).</summary>
    function MenuEntries: TArray<TAtlasMenuEntry>;
    /// <summary>Taste für „Auswahl an den Assistenten“ (#2377).</summary>
    function Keys: TArray<TAtlasModuleKey>;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.LogWindow,
  Atlas.UI.Assistants.Strings;

const
  cPauseCommand = 'Atlas.AssistantsPause';
  cMentionCommand = 'Atlas.AssistantsLinkMention';
  /// <summary>Pause, Auswahl an den Assistenten, KI-Protokoll.</summary>
  cCommandCount = 3;
  cLogCommand = 'Atlas.AssistantsLog';

function TAtlasAssistantsModule.PauseCaption: string;
begin
  if FHooks.Paused() then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOff);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOn);
  end;
end;
function MentionKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.AssistantsLinkMentionKey;
end;
{ TAtlasAssistantsModule }

constructor TAtlasAssistantsModule.Create(const AHooks: TAtlasAssistantsModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasAssistantsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := nil;
  SetLength(Result, cCommandCount);
  Result[0] := Default(TAtlasModuleCommand);
  Result[0].Id := cPauseCommand;
  Result[0].Caption := PauseCaption;
  Result[0].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandHint);
  Result[0].Run := FHooks.TogglePause;
  // Auswahl an den verbundenen Assistenten (#2377).
  Result[1] := Default(TAtlasModuleCommand);
  Result[1].Id := cMentionCommand;
  Result[1].Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionCommand);
  Result[1].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionHint);
  Result[1].Run := FHooks.Mention;
  Result[1].Visible := FHooks.MentionVisible;
  Result[1].Key := MentionKey;
  // KI-Protokoll (#2049).
  Result[2] := Default(TAtlasModuleCommand);
  Result[2].Id := cLogCommand;
  Result[2].Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogCaption);
  Result[2].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogCommandHint);
  Result[2].Run := FHooks.ShowLog;
end;
function TAtlasAssistantsModule.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
begin
  mEntry := Default(TAtlasMenuEntry);
  mEntry.CommandId := cMentionCommand;
  mEntry.Place := TAtlasMenuPlace.EditorContext;
  Result := [mEntry];
end;
function TAtlasAssistantsModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  // Ohne Kopplung oder ohne Taste bleibt die Taste der IDE.
  if not TAtlasIdeSettings.Current.AssistantsLink or (MentionKey = 0) then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := cMentionCommand;
  mKey.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionCommand);
  mKey.Key := MentionKey;
  mKey.Priority := TAtlasKeyPriority.Shared;
  mKey.Run := FHooks.Mention;
  Result := [mKey];
end;
function TAtlasAssistantsModule.Info: TAtlasModuleInfo;
begin
  // Wie bisher: Aufträge nimmt die IDE nur im normalen Start an.
  Result := TAtlasModuleHost.Info(cModuleId, 'KI-Assistenten', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Normal, cSwitch);
end;
procedure TAtlasAssistantsModule.Start;
begin
  FActive := True;
end;
procedure TAtlasAssistantsModule.Stop;
begin
  FActive := False;
end;
function TAtlasAssistantsModule.IsActive: Boolean;
begin
  Result := FActive;
end;
procedure TAtlasAssistantsModule.ApplySettings;
begin
  // debug.mcp.banner, assistants.link.shareSelection und .diffPreview (#2377), assistants.log.max gelten sofort.
  FHooks.ApplySettings();
end;
procedure TAtlasAssistantsModule.ThemeChanged;
var
  mBar: TAtlasIdeAssistantDebugBar;
begin
  mBar := FHooks.DebugBar();
  if mBar <> nil then
  begin
    mBar.ApplyTheme;
  end;
  TAtlasIdeAssistantsLogWindow.ApplyTheme;
end;
procedure TAtlasAssistantsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
var
  mContext: TAtlasIdeContextExport;
begin
  // Letzter Build für den IDE-Zustand (#2050); ohne laufenden Teil nichts.
  mContext := FHooks.Context();
  if mContext <> nil then
  begin
    mContext.BuildRemembered(AMessages, AProject, AVerdict);
  end;
end;

end.
