unit Atlas.IDE.CodeInsight.Composition.Features;

// Teile des Plugins in Startreihenfolge (Code-Review S-03) in einer TAtlasFeatureTable: je Teil die Stufe des
// abgesicherten Starts (#722) bzw. die Einstellung, unter der es läuft, Start und Stop; danach die angemeldeten
// Module (#1455). RegisterFeatures startet beim Laden und nach jeder Einstellungsänderung, was gewünscht ist und
// noch fehlt; StopFeatures baut rückwärts ab.

interface

/// <summary>Gewünschte, noch fehlende Teile starten (beim Laden und nach jeder Einstellungsänderung); zuvor die
/// laufenden Teile ausgeschalteter Module stoppen (#1454).</summary>
procedure RegisterFeatures;
/// <summary>Startanteile beenden (Bericht N4): Danach zählen weder Aktionen noch Teile mit.</summary>
procedure EndStartTimes;
/// <summary>Nachrichtenschleife frei nach ALoadMs: Ladezeit in die Startmarke (#722), Startanteile ins Protokoll
/// und bei einem langsamen Start (safeMode.startupTimeoutMs) eine Zeile im Meldungsfenster (abschaltbar mit
/// robustness.hangHint). Bericht N4: Ein langsamer Start zählt nicht mehr wie ein Absturz und schaltet beim
/// nächsten Start nichts ab; er nennt, was Atlas daran hatte, damit sich die Ursache beheben lässt.</summary>
procedure ReportStartup(ALoadMs: Int64);
/// <summary>Angemeldete Module melden keine Änderung mehr (vor ihrem Stopp, Regel 5).</summary>
procedure DetachModuleHosting;
/// <summary>Alle Teile rückwärts stoppen; Ergebnis: die fehlgeschlagenen als „Name: Klasse“.</summary>
function StopFeatures: TArray<string>;
/// <summary>Feature-Tabelle und Modulanbindung freigeben.</summary>
procedure FreeFeatures;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.FeatureTable,
  Atlas.Core.Diagnostics.ModuleHosting,
  Atlas.Core.Diagnostics.StartTimes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Diagnostics.KnownPackages,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Editor.Reassigned,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Build,
  Atlas.IDE.CodeInsight.Composition.Background,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.Palette,
  Atlas.IDE.CodeInsight.Composition.EditorBars,
  Atlas.IDE.CodeInsight.Composition.Drawing,
  Atlas.IDE.CodeInsight.Composition.Keys,
  Atlas.IDE.CodeInsight.Composition.Startup;

var
  // Teile des Plugins in Startreihenfolge (Code-Review S-03); gefüllt beim ersten RegisterFeatures.
  Features: TAtlasFeatureTable;
  // Angemeldete Module als Teile der Feature-Tabelle (#1455, ADR 0017 Regeln 1, 2); lebt mit Features.
  ModuleHosting: TAtlasModuleHosting;

/// <summary>Notifier und Hintergrundaufgaben nur im normalen Betrieb bzw. wenn ihr Schalter wieder an ist.
/// </summary>
function CompileWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel = TAtlasSafeLevel.Normal) or TAtlasIdeSettings.Current.CheckOnSave;
end;

/// <summary>Manager, Zusammenfassungen, Compile-Ereignisse, Wächter, Prüfung beim Speichern, Befehle,
/// Projektdatei, Umbenennen von Units und Hinweis „Prüfregeln sind aus“.</summary>
procedure AddCoreFeatures;
begin
  Features.Add('Manager', TAtlasSafeLevel.Safe, ManagerStarted, StartManager, StopManager);
  // Projekt-Zusammenfassungen (#592, #1455): vor Compile, damit Builds sie finden; gehen nach Compile.
  Features.Add('ProjectSummaries', TAtlasSafeLevel.Normal, ProjectSummariesStarted, StartProjectSummaries,
    StopProjectSummaries);
  Features.AddWanted('Compile', CompileWanted, CompileStarted, RegisterCompileEvents, UnregisterCompileEvents);
  Features.Add('Watchdog', TAtlasSafeLevel.Normal, WatchdogStarted, StartWatchdog, StopWatchdog);
  Features.AddWanted('CheckOnSave',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := CompileStarted;
    end,
    CheckOnSaveStarted, StartCheckOnSave, StopCheckOnSave);
  Features.Add('Commands', TAtlasSafeLevel.Safe, CommandsStarted, StartCommands, StopCommands);
  // Projektdatei .atlas (#486): in jeder Stufe, solange die Einstellung TeamFile an ist (abgesichert erst nach dem
  // Schnellschalter); liest nur eine Datei.
  Features.AddWanted('TeamFile',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := TAtlasIdeSettings.Current.TeamFile;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeTeamFile.Started;
    end,
    TAtlasIdeTeamFile.Start, TAtlasIdeTeamFile.Stop);
  // Builds für KI-Assistenten (#261, McpBuild) startet das Modul Build-Pipeline.
  // uses nachziehen nach dem Umbenennen einer Unit (#512): ob es angeboten wird, entscheidet der Server
  // (refactoring.unitRenameFollowUp).
  Features.Add('UnitRename', TAtlasSafeLevel.Normal, UnitRenameStarted, StartUnitRename, StopUnitRename);
  // Hinweis „Prüfregeln sind aus“ (#1454): je atlas.json mit Regeln einmal, solange das Modul aus ist.
  Features.Add('RuleChecksNotice', TAtlasSafeLevel.Normal, RuleChecksNoticeStarted, StartRuleChecksNotice,
    StopRuleChecksNotice);
  // Hinweis „kein Kommandozeilen-Compiler“ (#1822): einmal überhaupt, auch abgesichert (liest nur Dateien).
  Features.Add('EditionNotice', TAtlasSafeLevel.Safe, EditionNoticeStarted, StartEditionNotice, StopEditionNotice);
  // Module unter „Known Packages“ (Meldung vom 05.11.2026): auch abgesichert, liest nur die Registry; meldet
  // fehlende Module und protokolliert Änderungen der Liste.
  Features.Add('KnownPackages', TAtlasSafeLevel.Safe, KnownPackagesStarted, StartKnownPackages, StopKnownPackages);
end;

/// <summary>Einrichtung (#625): auch abgesichert, sie fragt den Server nie selbst und startet ihn nur auf
/// Knopfdruck.</summary>
function SetupWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel <> TAtlasSafeLevel.Minimal) and (StatusLines <> nil);
end;

/// <summary>Tastenkürzel-Tipps (#600): Beobachtung an oder aus nach shortcutTips.enabled (ApplySettings); zählt
/// auch für „Atlas entdecken“ (#757), solange die Karte und die Zählung an sind.</summary>
function ShortcutTipsWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel = TAtlasSafeLevel.Normal) and CommandUsageStarted;
end;

/// <summary>Änderungsprotokoll, Updates, Tasten der Editorbefehle, Formulare, Diagnosemodus, Einrichtung,
/// Tastenübersicht, Zählung, Tipps und Palette.</summary>
procedure AddToolFeatures;
begin
  // Änderungsprotokoll vor den Tasten: Strg+Alt+Z braucht es (#721).
  Features.Add('Undo', TAtlasSafeLevel.Safe, UndoStarted, StartUndo, TAtlasIdeUndo.Stop);
  // Update-Prüfung nur nach Zustimmung und höchstens einmal täglich (#495).
  Features.Add('Updates', TAtlasSafeLevel.Safe, UpdatesStarted, StartUpdates, StopUpdates);
  Features.Add('EditorKeys', TAtlasSafeLevel.Safe, EditorKeysStarted, StartEditorKeys, StopEditorKeys);
  // Designer-Notifier nur im normalen Betrieb (#722).
  Features.Add('Forms', TAtlasSafeLevel.Normal, FormsStarted, StartForms, StopForms);
  // Diagnosemodus (#479): ohne Einstellung nur Taste und Befehl, keine Messung.
  Features.Add('DiagnosticMode', TAtlasSafeLevel.Safe, DiagnosticModeStarted, StartDiagnosticMode,
    StopDiagnosticMode);
  Features.AddWanted('Setup', SetupWanted, SetupStarted, StartSetup, StopSetup);
  // Tastenkürzel-Übersicht (#520): auch abgesichert, sie liest nur die Belegungen der IDE.
  Features.Add('KeyMap', TAtlasSafeLevel.Safe, KeyMapStarted, StartKeyMap, StopKeyMap);
  // Gemeinsame Zählung (#757): vor den Tastenkürzel-Tipps und der Willkommensseite, die sie nutzen; Abbau
  // danach, er speichert die Zählung.
  Features.Add('CommandUsage', TAtlasSafeLevel.Safe, CommandUsageStarted, StartCommandUsage, StopCommandUsage);
  Features.AddWanted('ShortcutTips', ShortcutTipsWanted, ShortcutTipsStarted, StartShortcutTips, StopShortcutTips);
  Features.Add('Palette', TAtlasSafeLevel.Safe, PaletteStarted, StartPalette, StopPalette);
end;

function HideWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := ALevel <> TAtlasSafeLevel.Minimal;
end;

/// <summary>Editor-Zeichnungen: im normalen Start oder mit einer ihrer Einstellungen.</summary>
function PairsWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := (ALevel = TAtlasSafeLevel.Normal) or TAtlasIdeSettings.Current.PairColors or
    TAtlasIdeSettings.Current.PairGuides or TAtlasIdeSettings.Current.InactiveDim;
end;

/// <summary>Nicht minimal und dazu normal oder mit Einstellung AOn.</summary>
function NormalOrSetting(ALevel: TAtlasSafeLevel; AOn: Boolean): Boolean;
begin
  Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or AOn);
end;

function GutterMarksWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.RecursionMarkers or
    TAtlasIdeGutterMarks.ModuleLayersWanted);
end;

function GutterColumnWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.GutterColumn);
end;

function SelectionMatchesWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.SelectionMatches);
end;

function ExitPointsWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.ExitPoints);
end;

function ReassignedWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.Reassigned);
end;

function ExitPointsStarted: Boolean;
begin
  Result := TAtlasIdeExitPoints.Installed;
end;

function ReassignedStarted: Boolean;
begin
  Result := TAtlasIdeReassigned.Installed;
end;

/// <summary>Ausblenden, Klammerpaare, Fenster „Atlas-Prüfung“, Rinne, Atlas-Spalte, gleicher Text,
/// Austrittspunkte und neu zugewiesene Variablen.</summary>
procedure AddDrawingFeatures;
begin
  // Gezeichnete Elemente und Ausblenden am Element (#628): vor den Zeichnern, Abbau nach ihnen.
  Features.AddWanted('Hide', HideWanted, HideStarted, StartHide, StopHide);
  Features.AddWanted('Pairs', PairsWanted, PairsStarted, StartPairs, StopPairs);
  // Fenster „Atlas-Prüfung“ (#909): liest den Problemspeicher des Managers.
  Features.Add('ProblemsWindow', TAtlasSafeLevel.Normal, ProblemsWindowStarted, StartProblemsWindow,
    StopProblemsWindow);
  // Gemeinsame Zeichenschicht der Rinne: Rekursionssymbole (#623) und die Schichten der Module (Notizen und
  // Lesezeichen, #545, #622, #1455), die sie über die Registry findet.
  Features.AddWanted('GutterMarks', GutterMarksWanted, GutterMarksStarted, StartGutterMarks, StopGutterMarks);
  // Atlas-Spalte in der Zeilenleiste (#768): eigene Spalte, nur im normalen Start oder mit Einstellung.
  Features.AddWanted('GutterColumn', GutterColumnWanted, GutterColumnStarted, StartGutterColumn,
    StopGutterColumn);
  // Gleichen Text wie die Markierung hervorheben (#709): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('SelectionMatches', SelectionMatchesWanted, SelectionMatchesStarted, StartSelectionMatches,
    StopSelectionMatches);
  // Austrittspunkte hervorheben (#698): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('ExitPoints', ExitPointsWanted, ExitPointsStarted, StartExitPoints, StopExitPoints);
  // Neu zugewiesene Variablen unterstreichen (#712): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('Reassigned', ReassignedWanted, ReassignedStarted, StartReassigned, StopReassigned);
end;

/// <summary>Eigene Tasten für Vervollständigung und Parameter-Hint: nicht minimal, normal oder mit Atlas an.
/// </summary>
function CodeInsightKeyWanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := NormalOrSetting(ALevel, TAtlasIdeSettings.Current.Enabled);
end;

/// <summary>Modul-Schalter (#1454) für die Feature-Tabelle; eigene Routine statt anonymer Methode.</summary>
function ModuleOn(const AModule: string): Boolean;
begin
  Result := TAtlasIdeSettings.ModuleOn(AModule);
end;

/// <summary>Tasten, Paketbeobachtung, Hauptmenü und die Dateiwege der MCP-Werkzeuge und des Neuladens.</summary>
procedure AddShellFeatures;
begin
  Features.AddWanted('CompletionKey', CodeInsightKeyWanted, CompletionKeyStarted, StartCompletionKey,
    StopCompletionKey);
  Features.AddWanted('SignatureKey', CodeInsightKeyWanted, SignatureKeyStarted, StartSignatureKey,
    StopSignatureKey);
  Features.Add('KeysWatched', TAtlasSafeLevel.Safe, KeysWatched, WatchKeys, UnwatchKeys);
  Features.Add('MainMenu', TAtlasSafeLevel.Safe, MainMenuStarted, StartMainMenu, StopMainMenu);
  Features.Add('DirtyExport', TAtlasSafeLevel.Normal, DirtyExportStarted, StartDirtyExport, StopDirtyExport);
  Features.Add('Reloader', TAtlasSafeLevel.Normal, ReloaderStarted, StartReloader, StopReloader);
end;

/// <summary>Teile des Plugins in Startreihenfolge (Code-Review S-03); StopAll baut sie rückwärts ab.
/// Normal = nur im normalen Start, Safe = auch abgesichert, Minimal = immer (#722).</summary>
procedure AddFeatures;
begin
  Features := TAtlasFeatureTable.Create;
  AddCoreFeatures;
  AddToolFeatures;
  AddDrawingFeatures;
  AddShellFeatures;
  // Module (#1454): Ist der Modul-Schalter aus, startet keines dieser Teile, laufende stoppt RegisterFeatures.
  // Die übrigen Teile eines Moduls folgen ihren eigenen Einstellungen, die bei ausgeschaltetem Modul „aus“
  // liefern (TAtlasModuleSwitches). Angemeldete Module (Debugger, #1455) bringen ihren Schalter selbst mit.
  Features.ModuleOn := ModuleOn;
  // Module zuletzt: Sie bauen auf den Teilen von Base auf und gehen beim Abbau zuerst (#1455).
  ModuleHosting := TAtlasModuleHosting.Create(AtlasModuleRegistry, Features);
end;

procedure RegisterFeatures;
var
  mFailure: string;
begin
  if Features = nil then
  begin
    AddFeatures;
  end;
  // Ein Modul, das sich nach dem Start anmeldet, startet über denselben Weg (Regel 2).
  if (ModuleHosting <> nil) and not Assigned(ModuleHosting.OnChanged) then
  begin
    ModuleHosting.OnChanged := RegisterFeatures;
  end;
  for mFailure in Features.StopOffModules do
  begin
    TAtlasGuard.Log('Modul ausgeschaltet, Teil nicht sauber gestoppt: ' + mFailure);
  end;
  // Bis zur freien Nachrichtenschleife zählt jedes Teil zu den Startanteilen (Bericht N4).
  Features.Times := StartTimes;
  Features.StartWanted(Level);
  if MainMenu <> nil then
  begin
    MainMenu.UpdateKeyMap;
  end;
  // Abschaltbare Einträge im Kontextmenü des Editors (#1120).
  TAtlasIdeEditorCommands.UpdateContextMenus;
  // Phase und Fortschritt des Servers melden sich aus jedem Thread; gezeichnet wird gesammelt.
  if (Manager <> nil) and (StatusField <> nil) then
  begin
    Manager.OnServerChanged := RequestStatusRefresh;
  end;
  // Eigene Blocklinien: Strukturhervorhebung der IDE abgleichen (#514).
  TAtlasIdeStructureSwitch.Sync;
  RebindKeys;
end;

procedure EndStartTimes;
begin
  TAtlasActivity.TimeInto(nil);
  if Features <> nil then
  begin
    Features.Times := nil;
  end;
  FreeStartTimes;
end;

/// <summary>Zeile im Meldungsfenster bei einem langsamen Start mit den langsamsten Anteilen.</summary>
procedure ReportSlowStart(ALoadMs: Int64; ALimit: Integer);
var
  mParts: string;
begin
  mParts := StartTimes.SlowestText;
  if mParts <> '' then
  begin
    mParts := ': ' + mParts;
  end;
  MessageLine(TAtlasStrings.Fmt(TAtlasTextId.StartSlow, [ALoadMs, ALimit, StartTimes.Total, mParts]));
end;

procedure ReportStartup(ALoadMs: Int64);
var
  mLimit: Integer;
  mLine: string;
begin
  if SafeMode <> nil then
  begin
    SafeMode.Loaded(ALoadMs);
  end;
  if StartTimes = nil then
  begin
    Exit;
  end;
  try
    // Erst anhalten, dann lesen: Keine Aktion zählt mehr mit.
    TAtlasActivity.TimeInto(nil);
    mLimit := TAtlasIdeSettings.Current.SafeStartupTimeoutMs;
    mLine := StartTimes.LogLine(ALoadMs, mLimit);
    TAtlasGuard.Log(mLine);
    LogLine(mLine);
    if TAtlasStartTimes.IsSlow(ALoadMs, mLimit) and TAtlasIdeSettings.Current.HangHint then
    begin
      ReportSlowStart(ALoadMs, mLimit);
    end;
  finally
    EndStartTimes;
  end;
end;

procedure DetachModuleHosting;
begin
  if ModuleHosting <> nil then
  begin
    ModuleHosting.OnChanged := nil;
  end;
end;

function StopFeatures: TArray<string>;
begin
  Result := nil;
  if Features <> nil then
  begin
    Result := Features.StopAll;
  end;
end;

procedure FreeFeatures;
begin
  FreeAndNil(ModuleHosting);
  FreeAndNil(Features);
end;

end.
