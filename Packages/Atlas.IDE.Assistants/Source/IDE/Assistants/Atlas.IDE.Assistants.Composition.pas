unit Atlas.IDE.Assistants.Composition;

// Modul KI-Assistenten (#1888): einzige Unit, die die Eingänge für
// Aufträge von MCP-Clients in der laufenden IDE erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.assistants“ (Modulschalter assistants) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - Teil „AssistantBuilds“: Eingang des MCP-Werkzeugs build_project (#261);
//   gebaut wird über IAtlasBuildRequests des Moduls Build-Pipeline, das der
//   Eingang bei jedem Auftrag neu in der Registry sucht (Regel 2). Nur im
//   normalen Start und solange compiler.mcpBuild an ist.
// - Teil „AssistantEdits“: Eingang für Änderungen an offenen Dateien (#397),
//   solange assistants.edit an ist; Änderungen an ungespeicherten Dateien
//   wartet er mit assistants.editHoldModified auf den Menschen (#2605).
// - Teil „AssistantQuestions“: Eingang des MCP-Werkzeugs ask_user (#2620) mit
//   dem Fenster „KI-Assistent fragt“, solange assistants.questionsInIde an ist.
// - Teil „AssistantLog“: Fenster „Atlas-KI-Protokoll“ (#2049) samt Befehl, solange
//   assistants.log an ist. Das Protokoll selbst gehört dem Modul wie die
//   Aktivität; ausgeschaltet nimmt es nichts an und hält nichts.
// - Teil „AiGhostText“: Schattentext vom KI-Anbieter (#1922), solange
//   assistants.inlineSuggestions an ist; HTTP und Anmeldespeicher von Windows
//   entstehen nur in Atlas.IDE.Assistants.Composition.Adapters.
// - Teil „AssistantDebug“: Eingang der MCP-Werkzeuge debug_* (#1874); ausgeführt
//   wird über IAtlasDebugControl des Moduls Debugger, das der Eingang bei jedem
//   Auftrag neu in der Registry sucht (Regel 2). Nur im normalen Start und
//   solange debug.mcp an ist; Rechte aus debug.mcp.sideEffects, .modify, .attach.
//   Dazu die Leiste „KI-Assistent debuggt“ im Editor (debug.mcp.banner).
// - Teil „AssistantBanner“: Feld „KI-Assistent aktiv“ im Statusfeld mit Pause
//   für KI-Assistenten (#1906), solange assistants.banner an ist.
// - den Befehl „Pause für KI-Assistenten“ in der Palette (#1906).
// - Teil „AssistantContext“: Zustand der IDE für get_ide_context (#2050),
//   solange assistants.context an ist; den letzten Build bekommt er über
//   IAtlasBuildVerdictListener.
// - den Abschnitt mit dem Modulschalter im Optionsdialog und den Haken für die
//   Schlüssel der KI-Anbieter, „Verbindung testen“ und „Modelle abrufen“
//   (#2056, in Atlas.IDE.Assistants.Composition.Adapters, ab der Anmeldung).
// - Teil „AssistantLink“: RAD Studio als verbundene IDE für Kommandozeilen-Assistenten (#2377), solange
//   assistants.link an ist (WebSocket nur auf 127.0.0.1, Lock-Datei, Statusfeld „Assistent verbunden“); dazu der
//   Befehl „Auswahl an den Assistenten“ mit Taste (assistants.link.mentionKey) und Eintrag im Kontextmenü des
//   Editors, sichtbar nur mit verbundenem Assistenten.
// - Text für einfache Aufgaben anderer Module (IAtlasAiText, #2462): vom eigenen Anbieter oder einem Anbieter der
//   IDE (Smart CodeInsight, #2744) nach assistants.textSource; ab der Anmeldung.
// - Teil „AiIdePlugin“: der eigene Anbieter als „Atlas (…)“ bei Smart CodeInsight der IDE (#2745), solange
//   assistants.registerInIde an und ein eigener Anbieter eingerichtet ist.
// - Befehl „Anweisungen für KI-Assistenten aktualisieren“ samt Hinweis nach dem Speichern der atlas.json (#2615,
//   Atlas.IDE.Assistants.Adapters.Instructions).
// Was KI-Assistenten gerade tun und ob sie pausiert sind
// (TAtlasAssistantsActivity), gehört dem Modul und lebt von der Anmeldung bis
// nach dem Abmelden: Die Pause bleibt so über das Neustarten einzelner Teile
// hinweg stehen.
// Die Liste der offenen und ungespeicherten Dateien (DirtyExport) bleibt in
// Base: Sie schützt Dateien auch dann vor dem Überschreiben, wenn das Modul
// fehlt. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt
// die Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Contract;

type
  TAtlasAssistantsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasBuildVerdictListener)
  public const
    cModuleId = 'atlas.assistants';
    cSwitch = 'assistants';
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
    /// <summary>Befehl „Pause für KI-Assistenten“ (#1906).</summary>
    function Commands: TArray<TAtlasModuleCommand>;
    /// <summary>„Auswahl an den Assistenten“ im Kontextmenü des Editors (#2377).</summary>
    function MenuEntries: TArray<TAtlasMenuEntry>;
    /// <summary>Taste für „Auswahl an den Assistenten“ (#2377).</summary>
    function Keys: TArray<TAtlasModuleKey>;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Core.Assistants.Activity,
  Atlas.Core.Assistants.BuildInbox,
  Atlas.Core.Assistants.Log,
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Contracts.AiText,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.IDE.Contracts.DebugControl,
  Atlas.Core.Assistants.DebugGate,
  Atlas.IDE.Assistants.DebugInbox,
  Atlas.IDE.Assistants.DebugBar,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.BuildInbox,
  Atlas.IDE.Assistants.EditInbox,
  Atlas.IDE.Assistants.QuestionInbox,
  Atlas.IDE.Assistants.LogWindow,
  Atlas.IDE.Assistants.Composition.Adapters,
  Atlas.IDE.Assistants.Banner,
  Atlas.UI.Assistants.Strings,
  Atlas.IDE.Assistants.ContextExport,
  Atlas.IDE.Assistants.Adapters.Link,
  Atlas.IDE.Assistants.Adapters.Instructions,
  Atlas.UI.Assistants.SettingsSection;

const
  cPauseCommand = 'Atlas.AssistantsPause';
  cMentionCommand = 'Atlas.AssistantsLinkMention';
  /// <summary>Pause, Auswahl an den Assistenten, KI-Protokoll.</summary>
  cCommandCount = 3;
  cLogCommand = 'Atlas.AssistantsLog';

var
  GScope: IAtlasModuleScope;
  GActivity: TAtlasAssistantsActivity;
  GBuildInbox: TAtlasIdeBuildInbox;
  GEditInbox: TAtlasIdeEditInbox;
  GDebugInbox: TAtlasIdeDebugInbox;
  GDebugBar: TAtlasIdeAssistantDebugBar;
  GBanner: TAtlasIdeAssistantsBanner;
  GContext: TAtlasIdeContextExport;
  GLink: TAtlasIdeLink;
  GLog: TAtlasAssistantsLog;
  GQuestionInbox: TAtlasIdeQuestionInbox;
  GLogView: TAtlasIdeAssistantsLogView;

{ Dienste von Base und anderer Module }

/// <summary>Builds des Moduls Build-Pipeline; nil, solange es fehlt oder nicht läuft.</summary>
function BuildRequests: IAtlasBuildRequests;
begin
  TAtlasModuleContributions.First(AtlasModuleRegistry, IAtlasBuildRequests, Result);
end;

function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

/// <summary>Debugger des Moduls Debugger; nil, solange es fehlt oder nicht läuft.</summary>
function DebugControl: IAtlasDebugControl;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasDebugControl) do
  begin
    if Supports(mItem, IAtlasDebugControl, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Rechte des Assistenten aus den Einstellungen, bei jedem Auftrag neu gelesen.</summary>
function DebugRights: TAtlasDebugRights;
begin
  Result := TAtlasDebugRights.Make(TAtlasIdeSettings.Current.DebugMcpSideEffects,
    TAtlasIdeSettings.Current.DebugMcpModify, TAtlasIdeSettings.Current.DebugMcpAttach);
end;

{ Teile der Feature-Tabelle }

procedure StartBuilds;
begin
  GBuildInbox := TAtlasIdeBuildInbox.Create(BuildRequests, GActivity, GLog, TAtlasIdeHost.Warnings());
end;

procedure StopBuilds;
var
  mRequests: IAtlasBuildRequests;
begin
  // Ein laufender Build ruft danach nicht mehr in dieses Modul zurück (Regel 3, #1906).
  mRequests := BuildRequests;
  if mRequests <> nil then
  begin
    mRequests.Forget(TAtlasBuildInbox.cRequestedBy);
  end;
  // Der verworfene Rückruf meldet das Ende nicht mehr; sonst bliebe „baut …“ stehen.
  GActivity.BuildEnded;
  FreeAndNil(GBuildInbox);
end;

function BuildsStarted: Boolean;
begin
  Result := GBuildInbox <> nil;
end;

procedure StartEdits;
begin
  GEditInbox := TAtlasIdeEditInbox.Create(TAtlasIdeHost.EditorFiles, GActivity, GLog, TAtlasIdeHost.Warnings());
end;

procedure StopEdits;
begin
  FreeAndNil(GEditInbox);
end;

function EditsStarted: Boolean;
begin
  Result := GEditInbox <> nil;
end;

procedure StartQuestions;
begin
  GQuestionInbox := TAtlasIdeQuestionInbox.Create(GActivity, GLog);
end;

procedure StopQuestions;
begin
  // Offene Fragen bekommen „abgelehnt“; Fenster und Statusfeld gehen mit dem Eingang.
  FreeAndNil(GQuestionInbox);
end;

function QuestionsStarted: Boolean;
begin
  Result := GQuestionInbox <> nil;
end;

/// <summary>Protokoll nach den Einstellungen: aus = nichts annehmen, nichts halten.</summary>
procedure ApplyLogSettings;
begin
  GLog.Enabled := TAtlasIdeSettings.Current.AssistantsLog;
  GLog.MaxEntries := TAtlasIdeSettings.Current.AssistantsLogMax;
end;

procedure StartLog;
begin
  ApplyLogSettings;
  GLogView := TAtlasIdeAssistantsLogView.Create(GLog, TAtlasIdeHost.EditorFiles, TAtlasIdeHost.Messages());
end;

procedure StopLog;
begin
  // Fenster schließt, Einträge werden freigegeben (Regel 3).
  FreeAndNil(GLogView);
  GLog.Enabled := False;
end;

function LogStarted: Boolean;
begin
  Result := GLogView <> nil;
end;

/// <summary>Befehl „Atlas-KI-Protokoll“.</summary>
procedure ShowLog;
begin
  if GLogView = nil then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogOff));
    Exit;
  end;
  GLogView.ShowWindow;
end;

procedure DebugChanged;
begin
  if GDebugBar <> nil then
  begin
    GDebugBar.Refresh;
  end;
end;

function DebugInbox: TAtlasIdeDebugInbox;
begin
  Result := GDebugInbox;
end;

function DebugBanner: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugMcpBanner;
end;

procedure StartDebug;
begin
  GDebugInbox := TAtlasIdeDebugInbox.Create(DebugControl, DebugRights, DebugChanged,
    procedure(const AMessage: string)
    begin
      TAtlasIdeHost.Warning(AMessage);
    end);
  GDebugBar := TAtlasIdeAssistantDebugBar.Create(DebugInbox, DebugBanner);
  // Die Pause für KI-Assistenten (#1906) gilt auch für Debug-Aufträge.
  if GActivity.Paused then
  begin
    GDebugInbox.SetPaused(True);
  end;
end;

procedure StopDebug;
begin
  // Zuerst die Leiste: Der Eingang meldet beim Abbau noch eine Änderung.
  FreeAndNil(GDebugBar);
  FreeAndNil(GDebugInbox);
end;

function DebugStarted: Boolean;
begin
  Result := GDebugInbox <> nil;
end;

/// <summary>Pause für KI-Assistenten ein bzw. aus (Befehl und Klick auf die Anzeige).</summary>
procedure TogglePause;
begin
  GActivity.Paused := not GActivity.Paused;
  if GActivity.Paused then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseOn));
  end
  else
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseOff));
  end;
  if GBanner <> nil then
  begin
    GBanner.Refresh;
  end;
  if GDebugInbox <> nil then
  begin
    GDebugInbox.SetPaused(GActivity.Paused);
  end;
end;

procedure StartBanner;
begin
  GBanner := TAtlasIdeAssistantsBanner.Create(GActivity, TogglePause, ShowLog);
end;

procedure StopBanner;
begin
  FreeAndNil(GBanner);
end;

function BannerStarted: Boolean;
begin
  Result := GBanner <> nil;
end;

function PauseCaption: string;
begin
  if GActivity.Paused then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOff);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOn);
  end;
end;

procedure StartContext;
begin
  GContext := TAtlasIdeContextExport.Create;
end;

procedure StopContext;
begin
  FreeAndNil(GContext);
end;

function ContextStarted: Boolean;
begin
  Result := GContext <> nil;
end;

procedure StartLink;
begin
  GLink := TAtlasIdeLink.Create(GActivity);
end;

procedure StopLink;
begin
  FreeAndNil(GLink);
end;

function LinkStarted: Boolean;
begin
  Result := GLink <> nil;
end;

/// <summary>Befehl „Auswahl an den Assistenten“ nur mit verbundenem Assistenten.</summary>
function MentionVisible: Boolean;
begin
  Result := (GLink <> nil) and GLink.IsConnected;
end;

procedure MentionRun;
begin
  if GLink <> nil then
  begin
    GLink.Mention;
  end;
end;

function MentionKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.AssistantsLinkMentionKey;
end;

procedure StartIdePlugin;
begin
  StartAiIdePlugin(TAtlasAssistantsModule.cSwitch);
end;

{ TAtlasAssistantsModule }

class function TAtlasAssistantsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Builds für KI-Assistenten (#261): nur im normalen Start und solange compiler.mcpBuild an ist.
    TAtlasFeaturePart.When('AssistantBuilds',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.McpBuild;
      end, BuildsStarted, StartBuilds, StopBuilds),
    // Änderungen an offenen Dateien (#397): nur im normalen Start und solange assistants.edit an ist.
    TAtlasFeaturePart.When('AssistantEdits',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsEdit;
      end, EditsStarted, StartEdits, StopEdits),
    // Schattentext vom KI-Anbieter (#1922): nur im normalen Start und solange assistants.inlineSuggestions an ist.
    TAtlasFeaturePart.When('AiGhostText',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsInlineSuggestions;
      end, AiGhostStarted, StartAiGhost, StopAiGhost),
    // Debuggen durch KI-Assistenten (#1874): nur im normalen Start und solange debug.mcp an ist.
    TAtlasFeaturePart.When('AssistantDebug',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugMcp;
      end, DebugStarted, StartDebug, StopDebug),
    // Anzeige „KI-Assistent aktiv“ mit Pause (#1906): solange assistants.banner an ist.
    TAtlasFeaturePart.When('AssistantBanner',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsBanner;
      end, BannerStarted, StartBanner, StopBanner),
    // Zustand der IDE für get_ide_context (#2050): solange assistants.context an ist.
    TAtlasFeaturePart.When('AssistantContext',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsContext;
      end, ContextStarted, StartContext, StopContext),
    // Verbundene IDE für Kommandozeilen-Assistenten (#2377): solange assistants.link an ist.
    TAtlasFeaturePart.When('AssistantLink',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsLink;
      end, LinkStarted, StartLink, StopLink),
    // Rückfragen in der IDE (#2620): solange assistants.questionsInIde an ist.
    TAtlasFeaturePart.When('AssistantQuestions',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsQuestionsInIde;
      end, QuestionsStarted, StartQuestions, StopQuestions),
    // KI-Protokoll (#2049): solange assistants.log an ist.
    TAtlasFeaturePart.When('AssistantLog',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsLog;
      end, LogStarted, StartLog, StopLog),
    // Eigener Anbieter bei Smart CodeInsight der IDE (#2745): solange assistants.registerInIde an ist und ein
    // eigener Anbieter eingerichtet ist.
    TAtlasFeaturePart.When('AiIdePlugin',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and AiIdePluginWanted;
      end, AiIdePluginStarted, StartIdePlugin, StopAiIdePlugin)];
end;

function TAtlasAssistantsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := nil;
  SetLength(Result, cCommandCount);
  Result[0] := Default(TAtlasModuleCommand);
  Result[0].Id := cPauseCommand;
  Result[0].Caption := PauseCaption;
  Result[0].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandHint);
  Result[0].Run := TogglePause;
  // Auswahl an den verbundenen Assistenten (#2377).
  Result[1] := Default(TAtlasModuleCommand);
  Result[1].Id := cMentionCommand;
  Result[1].Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionCommand);
  Result[1].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionHint);
  Result[1].Run := TAtlasIdeLink.Guarded(MentionRun);
  Result[1].Visible := MentionVisible;
  Result[1].Key := MentionKey;
  // KI-Protokoll (#2049).
  Result[2] := Default(TAtlasModuleCommand);
  Result[2].Id := cLogCommand;
  Result[2].Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogCaption);
  Result[2].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogCommandHint);
  Result[2].Run := ShowLog;
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
  mKey.Run := TAtlasIdeLink.Guarded(MentionRun);
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
  // debug.mcp.banner gilt sofort.
  DebugChanged;
  // assistants.link.shareSelection und .diffPreview gelten sofort (#2377).
  if GLink <> nil then
  begin
    GLink.ApplySettings;
  end;
  // assistants.log.max gilt sofort; aus schaltet der Teil „AssistantLog“.
  if GLogView <> nil then
  begin
    ApplyLogSettings;
  end;
end;

procedure TAtlasAssistantsModule.ThemeChanged;
begin
  if GDebugBar <> nil then
  begin
    GDebugBar.ApplyTheme;
  end;
  TAtlasIdeAssistantsLogWindow.ApplyTheme;
end;

procedure TAtlasAssistantsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  // Letzter Build für den IDE-Zustand (#2050); ohne laufenden Teil nichts.
  if GContext <> nil then
  begin
    GContext.BuildRemembered(AMessages, AProject, AVerdict);
  end;
end;

class function TAtlasAssistantsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAssistantsModule;
  mPart: IAtlasFeaturePart;
  mRef: IInterface;
  mInstructions: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  GActivity := TAtlasAssistantsActivity.Create;
  // Ausgeschaltet, bis der Teil „AssistantLog“ startet.
  GLog := TAtlasAssistantsLog.Create;
  mModule := TAtlasAssistantsModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  // Letzter Build für den IDE-Zustand (#2050).
  GScope.Provide(IAtlasBuildVerdictListener, mModule as IAtlasBuildVerdictListener);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  // „Auswahl an den Assistenten“ (#2377) im Kontextmenü und als Taste.
  GScope.Provide(IAtlasMenuSource, mModule as IAtlasMenuSource);
  GScope.Provide(IAtlasKeySource, mModule as IAtlasKeySource);
  // KI-Protokoll (#2049): früh bei der IDE anmelden, damit der Desktop das Fenster wiederherstellt.
  TAtlasIdeAssistantsLogWindow.Prepare;
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  StartAiProbe;
  // Text für andere Module (Zusammenfassen im Tracker, #2462); wer fragt, filtert nach aktiven Modulen.
  GScope.Provide(IAtlasAiText, StartAiText);
  TAtlasAssistantsSettingsSection.KeyHooks := AiKeyHooks;
  TAtlasAssistantsSettingsSection.ProvideIn(GScope);
  // Anweisungsdateien für KI-Assistenten (#2615): Befehl, Menüeintrag und Hinweis nach dem Speichern.
  mInstructions := TAtlasIdeInstructions.Create(ModuleScope) as IAtlasCommandSource;
  GScope.Provide(IAtlasCommandSource, mInstructions);
  GScope.Provide(IAtlasMenuSource, mInstructions);
  GScope.Provide(IAtlasFollowsSaves, mInstructions);
  Result := True;
end;

class procedure TAtlasAssistantsModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance,
    procedure
    begin
      TAtlasAssistantsSettingsSection.KeyHooks := Default(TAtlasAssistantsKeyHooks);
      StopAiProbe;
      StopAiText;
      TAtlasIdeAssistantsLogWindow.Release;
    end);
  // Erst nach dem Stoppen aller Teile: Eingänge und Anzeige halten Aktivität und Protokoll bis dahin.
  FreeAndNil(GActivity);
  FreeAndNil(GLog);
end;

initialization
  TAtlasAssistantsModule.RegisterModule;

finalization
  TAtlasAssistantsModule.UnregisterModule;

end.
