unit Atlas.IDE.Problems.Service;

// Fenster „Atlas-Prüfung“ (#909), IDE-Seite: füllt den Frame aus demselben
// Speicher wie Wellenlinien und Hover (TAtlasProblemsController.Current);
// es gibt keine zweite Prüfung. Ein Zeitgeber (250 ms) baut die Liste nur
// neu, wenn sich Speicher, Bereich oder obere Datei geändert haben, und nur
// bei sichtbarem Fenster. Bereich „Projekt“ = Dateien des aktiven bzw. des
// gewählten Einzelprojekts (#1843), „Projektgruppe“ = Dateien aller Projekte
// der Gruppe (TAtlasIdeProblemFiles; workspace/diagnostic liefert die
// ungeöffneten Units im Hintergrund), „aktuelle Datei“ = oberer Editor. Der
// Takt gibt dem Frame die Projekte der Gruppe für die Bereichsliste.
// Zeilentext ungeöffneter Dateien kommt von der Platte und bleibt je Datei
// und Änderungszeit im Speicher.
// Statuszeile: Anzahl Befunde und Dateien, letzte Prüfung (Datei, Dauer,
// Uhrzeit, TAtlasProblemsController.LastCheck) und „a von b Units geprüft“
// für das Projekt. Rechts „Live“ bzw. „Angehalten“ nach problems.live.
// Aktionen: Springen (TAtlasIdeNavigation), Schnellkorrektur über die
// Code-Aktion mit Kennung (Hook ApplyTagged, Atlas.Common.Rules.CodeActions),
// „Regel erklären“ zeigt den Katalogtext (Hook Command,
// atlas.server.settingsCatalog im Hintergrund, #874). „Regel einstellen…“,
// „Für diese Zeile unterdrücken“ und „Regel abschalten“ liefert das Modul
// Prüfregeln (TAtlasRuleActions, #1755); ohne Modul fehlen die Einträge. „Alle sicheren Treffer
// von <Regel> korrigieren …“ (#1352) bietet das Modul Prüfregeln über
// IAtlasBulkFixer an (#1455); ohne laufendes Modul fehlt der Eintrag.
// Markierung folgt dem Cursor (problems.window.followCursor); F8/Umschalt+F8
// gehen bei sichtbarem Fenster durch dessen gefilterte Liste (StepWindow).
// Offene Units zuerst (#1108): Der Takt gibt dem Frame die Datei des oberen
// Editors und alle in der IDE geöffneten Module (.dfm/.fmx als ihre .pas,
// das ordnet das Modell zu); geänderte Eingaben bauen die Liste neu, sonst
// nichts. Statuszeile dann „n Befunde · a offene Units (b) · c nicht geöffnete
// Units (d)“ bzw. „… ausgeblendet“. Schnellkorrektur und Unterdrücken öffnen
// eine nicht geöffnete Unit zuerst.
// Bereich, Einzelprojekt, Gruppierung, Spalten und „Offene zuerst“ landen in
// den Einstellungen (problems.window.scope/scopeProject/groupBy/columns/
// openFirst). Mit
// problems.window aus gibt es weder Menüeintrag noch Fenster. Nur im
// Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.FindingsCache,
  Atlas.Core.Problems.Refresh,
  Atlas.Core.Settings.ProblemsUpdate;

type
  TAtlasProblemsCommandProc = reference to procedure(const ACommand, AArgumentsJson: string;
    const ADone: TProc<TJSONValue>);
  /// <summary>Baut der Server gerade den Index auf? APercent: Fortschritt, -1 = unbekannt.</summary>
  TAtlasProblemsIndexingFunc = reference to function(out APercent: Integer): Boolean;

  /// <summary>Was das Fenster von anderen Features braucht; setzt die Composition (keine Zyklen).</summary>
  TAtlasIdeProblemsHooks = record
    /// <summary>Code-Aktion mit Kennung (data.tag) am Befund im oberen Editor anwenden.</summary>
    ApplyTagged: TProc<TAtlasProblem, string>;
    /// <summary>Befehl an den laufenden Server im Hintergrund; ADone im Hauptthread (nil ohne Server).</summary>
    Command: TAtlasProblemsCommandProc;
    /// <summary>Zeile in der Meldungsansicht.</summary>
    Message: TProc<string>;
    /// <summary>Indexaufbau des Servers; projektweite Regeln (unused-public-member, #1102) schweigen so lange.
    /// nil = unbekannt.</summary>
    Indexing: TAtlasProblemsIndexingFunc;
    /// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) mit den markierten Befunden; nil = kein Eintrag.
    /// </summary>
    CreateIssue: TProc<TArray<TAtlasFinding>>;
    /// <summary>Eintrag sichtbar (issues.create).</summary>
    CanCreateIssue: TFunc<Boolean>;
  end;

  TAtlasIdeProblems = class
  public
    class procedure Start(const AHooks: TAtlasIdeProblemsHooks); static;
    class procedure Release; static;
    /// <summary>problems.* geändert: Fenster schließen (aus) bzw. Bereich, Gruppierung, Spalten übernehmen.</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>„Atlas-Prüfung“ zeigen (Menü, Palette, Taste).</summary>
    class procedure ShowWindow; static;
    /// <summary>„Atlas-Prüfung“ mit Bereich „aktuelle Datei“ zeigen (Doppelklick auf die Zähler der
    /// Atlas-Statusleiste, #1155); der Bereich bleibt wie nach einer Wahl im Fenster gespeichert.</summary>
    class procedure ShowCurrentFile; static;
    /// <summary>F8/Umschalt+F8 (#637): bei sichtbarem Fenster nächster bzw. vorheriger Befund der gefilterten
    /// Liste, auch in anderen Dateien. False, wenn das Fenster nicht sichtbar ist (dann gilt die Datei).</summary>
    class function StepWindow(AForward: Boolean): Boolean; static;
    /// <summary>problems.window an.</summary>
    class function Enabled: Boolean; static;
    /// <summary>Wann die offene Datei geprüft wird (problems.update).</summary>
    class function UpdateMode: TAtlasProblemsUpdate; static;
    /// <summary>„Datei jetzt prüfen“: Der Controller prüft die Datei des oberen Editors im nächsten Takt, auch
    /// ungespeichert und ohne Live-Prüfung.</summary>
    class procedure CheckFileNow; static;
    /// <summary>„Mit Atlas prüfen“ (#1817): AFiles im nächsten Takt prüfen lassen, auch ungeöffnete, und das
    /// Fenster zeigen.</summary>
    class procedure CheckFiles(const AFiles: TArray<string>); static;
    /// <summary>Fortschritt der Projektprüfung (#1232): geprüfte und alle Units des aktiven Projekts wie in der
    /// Statuszeile des Fensters. False ohne Projekt oder Speicher. Die Projektliste höchstens alle 2 s neu.</summary>
    class function ProjectProgress(out AChecked, ATotal: Integer): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Problems.Store,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings,
  Atlas.UI.Problems.Frame,
  Atlas.UI.Problems.Explain,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.RuleActions,
  Atlas.IDE.Problems.IdeErrors,
  Atlas.IDE.Problems.Window,
  Atlas.IDE.Problems.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Project,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TProblemsServiceText = (AtlasCheck);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TProblemsServiceText] of string = (
    ('Atlas-Prüfung: '),
    ('Atlas check: '));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TProblemsServiceText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  cTickMs = 250;
  /// <summary>Kennung der Code-Aktion (RuleFixTag in Atlas.Common.Editing.CodeActions; das Plugin hängt nicht von
  /// Atlas.Common ab).</summary>
  cFixTag = 'rule.fix';

type
  TState = class
  public
    Hooks: TAtlasIdeProblemsHooks;
    Timer: TTimer;
    /// <summary>Zuletzt gezeigter Stand: Version des Speichers und Eingaben (Bereich, Dateien, obere Datei).</summary>
    Version: Integer;
    Inputs: string;
    /// <summary>Datei und Zeile des Cursors beim letzten Folgen.</summary>
    Cursor: string;
    Status: string;
    /// <summary>Befunde je Datei: Neu gebaut (und von der Platte gelesen) werden nur Dateien mit neuem Stand.
    /// </summary>
    Findings: TAtlasFindingsCache;
    Catalog: TJSONValue;
    CatalogLanguage: TAtlasLanguage;
    constructor Create;
    destructor Destroy; override;
    procedure Tick(Sender: TObject);
  end;

var
  State: TState;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

procedure Say(const AText: string);
begin
  if (State <> nil) and Assigned(State.Hooks.Message) then
  begin
    State.Hooks.Message(AText);
  end;
end;

function TopFile(out ALine: Integer): string;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  Result := '';
  ALine := -1;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
    if (mView <> nil) and (mView.Buffer <> nil) then
    begin
      Result := mView.Buffer.FileName;
      ALine := mView.CursorPos.Line - 1;
    end;
  end;
end;

/// <summary>Alle in der IDE geöffneten Module (#1108), auch Projektdateien und Includes.</summary>
function OpenFiles: TArray<string>;
var
  mModules: IOTAModuleServices;
  mIndex: Integer;
  mModule: IOTAModule;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  for mIndex := 0 to mModules.ModuleCount - 1 do
  begin
    mModule := mModules.Modules[mIndex];
    if (mModule <> nil) and (mModule.FileName <> '') then
    begin
      Result := Result + [mModule.FileName];
    end;
  end;
end;

function ClosedUnitsOf(const AText: string): TAtlasClosedUnits;
begin
  TAtlasFindings.TryParseClosedUnits(AText, Result);
end;

function ScopeOf(const AText: string): TAtlasFindingScope;
begin
  TAtlasFindings.TryParseScope(AText, Result);
end;

function GroupingOf(const AText: string): TAtlasFindingGrouping;
begin
  TAtlasFindings.TryParseGrouping(AText, Result);
end;

/// <summary>Bereich, Gruppierung und Spalten des Frames in die Einstellungen.</summary>
procedure SaveLayout(AFrame: TAtlasProblemsFrame);
var
  mNext: TAtlasPluginSettings;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  mNext := TAtlasIdeSettings.Stored;
  mNext.ProblemsWindowScope := TAtlasFindings.cScopeNames[AFrame.Scope];
  // Das Einzelprojekt (#1843) bleibt gemerkt, solange ein anderer Bereich gilt.
  if AFrame.Scope = TAtlasFindingScope.Project then
  begin
    mNext.ProblemsWindowScopeProject := AFrame.ScopeProject;
  end;
  mNext.ProblemsWindowGroupBy := TAtlasFindings.cGroupingNames[AFrame.Grouping];
  mNext.ProblemsWindowColumns := AFrame.ColumnsText;
  mNext.ProblemsWindowOpenFirst := AFrame.OpenFirst;
  if (mNext.ProblemsWindowScope = TAtlasIdeSettings.Stored.ProblemsWindowScope) and
    (mNext.ProblemsWindowScopeProject = TAtlasIdeSettings.Stored.ProblemsWindowScopeProject) and
    (mNext.ProblemsWindowGroupBy = TAtlasIdeSettings.Stored.ProblemsWindowGroupBy) and
    (mNext.ProblemsWindowColumns = TAtlasIdeSettings.Stored.ProblemsWindowColumns) and
    (mNext.ProblemsWindowOpenFirst = TAtlasIdeSettings.Stored.ProblemsWindowOpenFirst) then
  begin
    Exit;
  end;
  TAtlasIdeSettings.Update(mNext);
end;

type
  /// <summary>Eingaben eines Refresh: obere Datei und Zeile, Dateien des Bereichs, geöffnete Module.</summary>
  TRefreshInputs = record
    Current: string;
    Line: Integer;
    Files: TArray<string>;
    Project: TArray<string>;
    Opened: TArray<string>;
    Checked: Boolean;
    /// <summary>Alles zusammen als Text: Ändert er sich, wird neu aufgebaut.</summary>
    Key: string;
  end;

function GatherInputs(AFrame: TAtlasProblemsFrame; AStore: TAtlasProblemStore): TRefreshInputs;
var
  mFilesKey: string;
begin
  Result := Default(TRefreshInputs);
  Result.Current := TopFile(Result.Line);
  // Projekte der Gruppe für die Bereichsliste (#1843); fehlt das gewählte Einzelprojekt, gilt danach das aktive.
  AFrame.SetScopeProjects(TAtlasIdeProblemFiles.Projects);
  if AFrame.Scope <> TAtlasFindingScope.CurrentFile then
  begin
    Result.Project := TAtlasIdeProblemFiles.FilesOf(AFrame.ScopeProject);
  end;
  if AFrame.Scope = TAtlasFindingScope.Project then
  begin
    Result.Files := Result.Project;
  end;
  mFilesKey := string.Join(';', Result.Files);
  if AFrame.Scope = TAtlasFindingScope.Group then
  begin
    Result.Files := TAtlasIdeProblemFiles.GroupFiles(mFilesKey);
  end;
  // Offene Units zuerst (#1108): geöffnete Module gehören zu den Eingaben; die Modulliste ist billig.
  if AFrame.OpenFirst then
  begin
    Result.Opened := OpenFiles;
  end;
  // Zeigt der Editor das Formular, gilt die Unit: Hat der Server die .pas schon geliefert?
  Result.Checked := (AStore <> nil) and (Result.Current <> '') and (AStore.Contains(Result.Current) or
    AStore.Contains(ChangeFileExt(Result.Current, '.pas')));
  Result.Key := Ord(AFrame.Scope).ToString + '|' + Result.Current + '|' + mFilesKey + '|' +
    string.Join(';', Result.Opened) + '|' + BoolToStr(Result.Checked, True);
end;

/// <summary>Befunde neu aus dem Speicher, wenn sich Speicher oder Eingaben geändert haben.</summary>
procedure UpdateFindings(AFrame: TAtlasProblemsFrame; AStore: TAtlasProblemStore; const AInputs: TRefreshInputs;
  AForce: Boolean);
var
  mFiles: TArray<string>;
  mChanged, mInputsChanged: Boolean;
  mFindings: TArray<TAtlasFinding>;
  mReadLines: TFunc<string, TArray<string>>;
begin
  if AStore = nil then
  begin
    AFrame.SetFindings(nil, AInputs.Current, AInputs.Files, AInputs.Opened, False);
    Exit;
  end;
  mInputsChanged := AForce or (AInputs.Key <> State.Inputs);
  if not mInputsChanged and (AStore.Version = State.Version) then
  begin
    Exit;
  end;
  State.Version := AStore.Version;
  State.Inputs := AInputs.Key;
  if AForce then
  begin
    State.Findings.Clear;
  end;
  mReadLines :=
    function(AFileName: string): TArray<string>
    begin
      Result := TAtlasIdeProblemFiles.DiskLines(AFileName);
    end;
  // Neue Version des Speichers heißt oft nur: eine andere Datei hat neue Befunde. Liste und Ansicht
  // nur neu aufbauen, wenn sich an den gezeigten Dateien etwas geändert hat.
  mFiles := AInputs.Files;
  if AFrame.Scope = TAtlasFindingScope.CurrentFile then
  begin
    mFiles := TArray<string>.Create(AInputs.Current);
  end;
  mFindings := State.Findings.Build(AStore, mFiles, mReadLines, mChanged);
  if mChanged or mInputsChanged then
  begin
    AFrame.SetFindings(mFindings, AInputs.Current, AInputs.Files, AInputs.Opened, AInputs.Checked);
  end;
end;

/// <summary>Zähler der Statuszeile: mit Stufen geöffnet/nicht geöffnet, sonst Befunde und Dateien.</summary>
function CountsStatus(AFrame: TAtlasProblemsFrame): string;
var
  mCounts: TAtlasFindingCounts;
begin
  mCounts := AFrame.View.Counts;
  if not AFrame.View.TiersActive then
  begin
    Exit(TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsStatusCount, [mCounts.Total, mCounts.Files]));
  end;
  Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsStatusTiers, [mCounts.Total, mCounts.OpenUnits,
    mCounts.OpenFindings, mCounts.ClosedUnits, mCounts.ClosedFindings]);
  if mCounts.HiddenUnits > 0 then
  begin
    Result := Result + ' · ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsStatusHidden,
      [mCounts.HiddenUnits]);
  end;
end;

function StatusText(AFrame: TAtlasProblemsFrame; AStore: TAtlasProblemStore;
  const AProject: TArray<string>): string;
var
  mCheck: TAtlasProblemsCheck;
  mPercent: Integer;
begin
  Result := CountsStatus(AFrame);
  mCheck := TAtlasProblemsController.LastCheck;
  if mCheck.FileName <> '' then
  begin
    Result := Result + ' · ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsStatusLast,
      [FormatDateTime('hh":"nn":"ss', mCheck.At), ExtractFileName(mCheck.FileName), Integer(mCheck.DurationMs)]);
  end;
  if (AStore <> nil) and (Length(AProject) > 0) then
  begin
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusProject,
      [TAtlasFindings.CheckedCount(AStore, AProject), Length(AProject)]);
  end;
  // Projektweite Regeln (#1102) prüfen erst mit vollständigem Index; bis dahin fehlen ihre Befunde.
  if (State <> nil) and Assigned(State.Hooks.Indexing) and State.Hooks.Indexing(mPercent) then
  begin
    Result := Result + ' · ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsStatusWaiting, [Max(mPercent,
      0)]);
  end;
end;

procedure Refresh(AForce: Boolean);
var
  mFrame: TAtlasProblemsFrame;
  mStore: TAtlasProblemStore;
  mInputs: TRefreshInputs;
  mStatus, mCursor: string;
begin
  mFrame := TAtlasIdeProblemsWindow.ExistingFrame;
  if (mFrame = nil) or not TAtlasIdeProblemsWindow.Visible then
  begin
    Exit;
  end;
  mStore := TAtlasProblemsController.Current;
  mInputs := GatherInputs(mFrame, mStore);
  mFrame.SetUpdate(TAtlasIdeProblems.UpdateMode);
  UpdateFindings(mFrame, mStore, mInputs, AForce);
  mStatus := StatusText(mFrame, mStore, mInputs.Project);
  if mStatus <> State.Status then
  begin
    State.Status := mStatus;
    mFrame.SetStatus(mStatus);
  end;
  // Markierung folgt dem Cursor.
  mCursor := mInputs.Current + ':' + mInputs.Line.ToString;
  if Settings.ProblemsWindowFollowCursor and (mInputs.Current <> '') and (State.Cursor <> mCursor) then
  begin
    State.Cursor := mCursor;
    mFrame.FollowCursor(mInputs.Current, mInputs.Line);
  end;
end;

procedure Open(const AFinding: TAtlasFinding);
begin
  TAtlasIdeNavigation.GoToLocation(AFinding.FileName, AFinding.Problem.StartLine, AFinding.Problem.StartCharacter);
end;

procedure ApplyTag(const AFinding: TAtlasFinding; const ATag: string);
begin
  // Die Code-Aktion gilt für den oberen Editor: erst hin, dann anwenden.
  Open(AFinding);
  if (State <> nil) and Assigned(State.Hooks.ApplyTagged) then
  begin
    State.Hooks.ApplyTagged(AFinding.Problem, ATag);
  end;
end;

procedure ShowExplanation(ACatalog: TJSONValue; const ARule: string);
var
  mExplanation: TAtlasRuleExplanation;
begin
  if TAtlasRuleExplanation.Find(ACatalog, ARule, mExplanation) then
  begin
    TAtlasRuleExplainDialog.Execute(mExplanation);
  end
  else
  begin
    Say(TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsExplainUnknown, [ARule]));
  end;
end;

procedure Explain(const AFinding: TAtlasFinding);
var
  mRule, mLanguage: string;
begin
  mRule := AFinding.Rule;
  if (State.Catalog <> nil) and (State.CatalogLanguage = TAtlasStrings.Language) then
  begin
    ShowExplanation(State.Catalog, mRule);
    Exit;
  end;
  if not Assigned(State.Hooks.Command) then
  begin
    Exit;
  end;
  mLanguage := 'de';
  if TAtlasStrings.Language = TAtlasLanguage.English then
  begin
    mLanguage := 'en';
  end;
  State.Hooks.Command(TAtlasProjectSettings.cCatalogCommand, '["' + mLanguage + '"]',
    procedure(AValue: TJSONValue)
    begin
      if State = nil then
      begin
        Exit;
      end;
      if AValue = nil then
      begin
        Say(TAtlasStrings.Text(TAtlasTextId.ProblemsNoServer));
        Exit;
      end;
      // Der Wert gehört dem Absender: eine Kopie merken.
      FreeAndNil(State.Catalog);
      State.Catalog := AValue.Clone as TJSONValue;
      State.CatalogLanguage := TAtlasStrings.Language;
      ShowExplanation(State.Catalog, mRule);
    end);
end;

/// <summary>Sammelkorrektur (#1352) eines laufenden Moduls; False ohne.</summary>
function BulkFixer(out AFixer: IAtlasBulkFixer): Boolean;
var
  mItem: IInterface;
begin
  AFixer := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBulkFixer) do
  begin
    if Supports(mItem, IAtlasBulkFixer, AFixer) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Einstellungen des Fensters aus den Plugin-Einstellungen.</summary>
procedure WireSettings(AFrame: TAtlasProblemsFrame);
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  AFrame.ShowCompilerCode := mSettings.ProblemsShowCompilerCode;
  AFrame.ShowIdeErrors := TAtlasIdeErrorSource.Enabled;
  AFrame.ApplySettings(ScopeOf(mSettings.ProblemsWindowScope), GroupingOf(mSettings.ProblemsWindowGroupBy),
    mSettings.ProblemsWindowColumns, mSettings.ProblemsWindowCompiler);
  AFrame.ApplyScopeSettings(mSettings.ProblemsWindowScopeProjects, mSettings.ProblemsWindowScopeProject);
  AFrame.ApplyTierSettings(mSettings.ProblemsWindowOpenFirst, ClosedUnitsOf(mSettings.ProblemsWindowClosedUnits),
    mSettings.ProblemsWindowShowCleanActive);
end;

/// <summary>Öffnen, Beheben und Unterdrücken aus der Liste.</summary>
procedure WireFixes(AFrame: TAtlasProblemsFrame);
begin
  AFrame.OnOpen :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          Open(AFinding);
        end);
    end;
  AFrame.OnFix :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          ApplyTag(AFinding, cFixTag);
        end);
    end;
  AFrame.OnFixAll :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        var
          mFixer: IAtlasBulkFixer;
        begin
          // Beim Klick neu fragen (Regel 3): Das Modul kann inzwischen fort sein.
          if (State <> nil) and BulkFixer(mFixer) then
          begin
            mFixer.FixAll(AFinding.Rule, AFrame.View.Visible);
          end;
        end);
    end;
  AFrame.CanFixAll :=
    function: Boolean
    var
      mFixer: IAtlasBulkFixer;
    begin
      Result := (State <> nil) and BulkFixer(mFixer) and mFixer.CanFixAll;
    end;
end;

/// <summary>Regel einstellen, unterdrücken und abschalten: Beiträge des Moduls Prüfregeln (#1755).</summary>
procedure WireRuleActions(AFrame: TAtlasProblemsFrame);
begin
  AFrame.CanRuleActions :=
    function: Boolean
    begin
      Result := (State <> nil) and TAtlasRuleActions.Available;
    end;
  AFrame.OnSuppress :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          // Die Code-Aktion gilt für den oberen Editor: Das Modul springt erst hin.
          TAtlasRuleActions.Suppress(TAtlasRuleActions.Place(AFinding.FileName, AFinding.Problem));
        end);
    end;
  AFrame.OnConfigure :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          TAtlasRuleActions.Configure(AFinding.Rule);
        end);
    end;
  AFrame.OnDisable :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          TAtlasRuleActions.Disable(AFinding.Rule);
        end);
    end;
end;

/// <summary>Regel erklären; Issue anlegen.</summary>
procedure WireRules(AFrame: TAtlasProblemsFrame);
begin
  AFrame.OnExplain :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          Explain(AFinding);
        end);
    end;
  AFrame.OnCreateIssue :=
    procedure(const AFindings: TArray<TAtlasFinding>)
    begin
      if (State <> nil) and Assigned(State.Hooks.CreateIssue) then
      begin
        State.Hooks.CreateIssue(AFindings);
      end;
    end;
  AFrame.CanCreateIssue :=
    function: Boolean
    begin
      Result := (State <> nil) and Assigned(State.Hooks.CreateIssue) and Assigned(State.Hooks.CanCreateIssue) and
        State.Hooks.CanCreateIssue();
    end;
end;

procedure Wire(AFrame: TAtlasProblemsFrame);
begin
  WireSettings(AFrame);
  WireFixes(AFrame);
  WireRuleActions(AFrame);
  WireRules(AFrame);
  AFrame.OnScope :=
    procedure(AScope: TAtlasFindingScope)
    begin
      Refresh(True);
    end;
  AFrame.OnLayout :=
    procedure
    begin
      SaveLayout(AFrame);
      // „Offene zuerst“ braucht die geöffneten Module: gleich neu füllen statt beim nächsten Takt.
      Refresh(True);
    end;
end;

{ TState }

constructor TState.Create;
begin
  inherited Create;
  Findings := TAtlasFindingsCache.Create;
  Version := -1;
  Timer := TTimer.Create(nil);
  Timer.Interval := cTickMs;
  Timer.OnTimer := Tick;
  Timer.Enabled := True;
end;

destructor TState.Destroy;
begin
  Timer.Free;
  Findings.Free;
  Catalog.Free;
  inherited Destroy;
end;

procedure TState.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
  begin
    Exit;
  end;
  try
    Refresh(False);
  except
    on E: Exception do
    begin
      Say(UiText(TProblemsServiceText.AtlasCheck) + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

{ TAtlasIdeProblems }

class function TAtlasIdeProblems.UpdateMode: TAtlasProblemsUpdate;
begin
  Result := TAtlasProblemsUpdateSetting.Parse(Settings.ProblemsUpdate);
end;

class procedure TAtlasIdeProblems.CheckFileNow;
begin
  TAtlasProblemsCheckRequest.Request;
end;

class procedure TAtlasIdeProblems.CheckFiles(const AFiles: TArray<string>);
begin
  if not Enabled or (Length(AFiles) = 0) then
  begin
    Exit;
  end;
  TAtlasProblemsCheckRequest.RequestFiles(AFiles);
  ShowWindow;
end;

class function TAtlasIdeProblems.Enabled: Boolean;
begin
  Result := Settings.Enabled and Settings.Problems and Settings.ProblemsWindow;
end;

var
  // Projektliste für ProjectProgress (#1232): Die Statusleiste fragt alle 250 ms.
  ProgressFiles: TArray<string>;
  ProgressAt: UInt64;

class function TAtlasIdeProblems.ProjectProgress(out AChecked, ATotal: Integer): Boolean;
const
  cRefreshMs = 2000;
var
  mStore: TAtlasProblemStore;
begin
  AChecked := 0;
  ATotal := 0;
  mStore := TAtlasProblemsController.Current;
  if mStore = nil then
  begin
    Exit(False);
  end;
  if (ProgressAt = 0) or (TThread.GetTickCount64 - ProgressAt >= cRefreshMs) then
  begin
    ProgressFiles := TAtlasIdeProblemFiles.ActiveFiles;
    ProgressAt := TThread.GetTickCount64;
  end;
  ATotal := Length(ProgressFiles);
  if ATotal = 0 then
  begin
    Exit(False);
  end;
  AChecked := TAtlasFindings.CheckedCount(mStore, ProgressFiles);
  Result := True;
end;

class procedure TAtlasIdeProblems.Start(const AHooks: TAtlasIdeProblemsHooks);
begin
  if State = nil then
  begin
    State := TState.Create;
  end;
  State.Hooks := AHooks;
  TAtlasIdeProblemsWindow.OnFrame :=
    procedure(AFrame: TAtlasProblemsFrame)
    begin
      Wire(AFrame);
      Refresh(True);
    end;
  TAtlasIdeProblemsWindow.OnSave :=
    procedure
    begin
      SaveLayout(TAtlasIdeProblemsWindow.ExistingFrame);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  if Enabled then
  begin
    TAtlasIdeProblemsWindow.Prepare;
  end;
end;

class procedure TAtlasIdeProblems.Release;
begin
  if State <> nil then
  begin
    SaveLayout(TAtlasIdeProblemsWindow.ExistingFrame);
  end;
  TAtlasIdeProblemsWindow.Release;
  FreeAndNil(State);
  ProgressFiles := nil;
  ProgressAt := 0;
  TAtlasIdeProblemFiles.Release;
end;

class procedure TAtlasIdeProblems.ApplySettings;
var
  mFrame: TAtlasProblemsFrame;
begin
  if not Enabled then
  begin
    TAtlasIdeProblemsWindow.Hide;
    Exit;
  end;
  TAtlasIdeProblemsWindow.Prepare;
  mFrame := TAtlasIdeProblemsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.ShowCompilerCode := Settings.ProblemsShowCompilerCode;
    mFrame.ShowIdeErrors := TAtlasIdeErrorSource.Enabled;
    mFrame.ApplySettings(ScopeOf(Settings.ProblemsWindowScope), GroupingOf(Settings.ProblemsWindowGroupBy),
      Settings.ProblemsWindowColumns, Settings.ProblemsWindowCompiler);
    mFrame.ApplyScopeSettings(Settings.ProblemsWindowScopeProjects, Settings.ProblemsWindowScopeProject);
    mFrame.ApplyTierSettings(Settings.ProblemsWindowOpenFirst, ClosedUnitsOf(Settings.ProblemsWindowClosedUnits),
      Settings.ProblemsWindowShowCleanActive);
    Refresh(True);
  end;
end;

class procedure TAtlasIdeProblems.ThemeChanged;
begin
  TAtlasIdeProblemsWindow.ApplyTheme;
end;

class procedure TAtlasIdeProblems.ShowWindow;
begin
  if not Enabled then
  begin
    Exit;
  end;
  if TAtlasIdeProblemsWindow.Show <> nil then
  begin
    Refresh(True);
  end;
end;

class procedure TAtlasIdeProblems.ShowCurrentFile;
var
  mFrame: TAtlasProblemsFrame;
begin
  if not Enabled then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeProblemsWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  if mFrame.Scope <> TAtlasFindingScope.CurrentFile then
  begin
    mFrame.ApplySettings(TAtlasFindingScope.CurrentFile, mFrame.Grouping, mFrame.ColumnsText,
      Settings.ProblemsWindowCompiler);
    SaveLayout(mFrame);
  end;
  Refresh(True);
end;

class function TAtlasIdeProblems.StepWindow(AForward: Boolean): Boolean;
var
  mFrame: TAtlasProblemsFrame;
  mFinding: TAtlasFinding;
begin
  Result := False;
  if not Enabled or not TAtlasIdeProblemsWindow.Visible then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeProblemsWindow.ExistingFrame;
  if (mFrame = nil) or not mFrame.Step(AForward, mFinding) then
  begin
    Exit;
  end;
  Open(mFinding);
  // Der Sprung soll die Auswahl nicht gleich wieder dem Cursor nachführen.
  if State <> nil then
  begin
    State.Cursor := mFinding.FileName + ':' + mFinding.Problem.StartLine.ToString;
  end;
  Result := True;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Problems.Service', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
