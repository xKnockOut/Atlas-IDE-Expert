unit Atlas.IDE.Problems.Service;

// Fenster „Atlas-Prüfung“ (#909), IDE-Seite: füllt den Frame aus demselben
// Speicher wie Wellenlinien und Hover (TAtlasProblemsController.Current);
// es gibt keine zweite Prüfung. Ein Zeitgeber (250 ms) baut die Liste nur
// neu, wenn sich Speicher, Bereich oder obere Datei geändert haben, und nur
// bei sichtbarem Fenster. Bereich „Projekt“ = Dateien des aktiven Projekts,
// „Projektgruppe“ = alle Dateien im Speicher (workspace/diagnostic liefert
// die ungeöffneten Units im Hintergrund), „aktuelle Datei“ = oberer Editor.
// Zeilentext ungeöffneter Dateien kommt von der Platte und bleibt je Datei
// und Änderungszeit im Speicher.
// Statuszeile: Anzahl Befunde und Dateien, letzte Prüfung (Datei, Dauer,
// Uhrzeit, TAtlasProblemsController.LastCheck) und „a von b Units geprüft“
// für das Projekt. Rechts „Live“ bzw. „Angehalten“ nach problems.live.
// Aktionen: Springen (TAtlasIdeNavigation), Schnellkorrektur und
// „Für diese Zeile unterdrücken“ über die Code-Aktion mit Kennung (Hooks
// ApplyTagged, Atlas.Common.Rules.CodeActions), „Regel einstellen…“ (Hook
// ConfigureRule, Seite Prüfregeln), „Regel abschalten“ schreibt
// rules.<id> = "off" in atlas.json des Projekts bzw. ohne Projekt in die
// globale Datei, „Regel erklären“ zeigt den Katalogtext (Hook Command,
// atlas.server.settingsCatalog im Hintergrund, #874).
// Markierung folgt dem Cursor (problems.window.followCursor); F8/Umschalt+F8
// gehen bei sichtbarem Fenster durch dessen gefilterte Liste (StepWindow).
// Offene Units zuerst (#1108): Der Takt gibt dem Frame die Datei des oberen
// Editors und alle in der IDE geöffneten Module (.dfm/.fmx als ihre .pas,
// das ordnet das Modell zu); geänderte Eingaben bauen die Liste neu, sonst
// nichts. Statuszeile dann „n Befunde · a offene Units (b) · c nicht geöffnete
// Units (d)“ bzw. „… ausgeblendet“. Schnellkorrektur und Unterdrücken öffnen
// eine nicht geöffnete Unit zuerst (ApplyTag).
// Bereich, Gruppierung, Spalten und „Offene zuerst“ landen in den
// Einstellungen (problems.window.scope/groupBy/columns/openFirst). Mit
// problems.window aus gibt es weder Menüeintrag noch Fenster. Nur im
// Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings;

type
  TAtlasProblemsCommandProc = reference to procedure(const ACommand, AArgumentsJson: string;
    const ADone: TProc<TJSONValue>);
  /// <summary>Baut der Server gerade den Index auf? APercent: Fortschritt, -1 = unbekannt.</summary>
  TAtlasProblemsIndexingFunc = reference to function(out APercent: Integer): Boolean;

  /// <summary>Was das Fenster von anderen Features braucht; setzt die Composition (keine Zyklen).</summary>
  TAtlasIdeProblemsHooks = record
    /// <summary>Code-Aktion mit Kennung (data.tag) am Befund im oberen Editor anwenden.</summary>
    ApplyTagged: TProc<TAtlasProblem, string>;
    /// <summary>Optionen auf der Seite Prüfregeln bei der Regel öffnen.</summary>
    ConfigureRule: TProc<string>;
    /// <summary>Befehl an den laufenden Server im Hintergrund; ADone im Hauptthread (nil ohne Server).</summary>
    Command: TAtlasProblemsCommandProc;
    /// <summary>Zeile in der Meldungsansicht.</summary>
    Message: TProc<string>;
    /// <summary>Indexaufbau des Servers; projektweite Regeln (unused-public-member, #1102) schweigen so lange.
    /// nil = unbekannt.</summary>
    Indexing: TAtlasProblemsIndexingFunc;
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
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Problems.Store,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.RuleTable,
  Atlas.Core.Settings.JsonText,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Frame,
  Atlas.UI.Problems.Explain,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Window,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings;

const
  TickMs = 250;
  /// <summary>Kennungen der Code-Aktionen (RuleFixTag, RuleSuppressLineTag in Atlas.Common.Editing.CodeActions;
  /// das Plugin hängt nicht von Atlas.Common ab).</summary>
  FixTag = 'rule.fix';
  SuppressLineTag = 'rule.suppressLine';

type
  TLineCache = record
    Age: TDateTime;
    Lines: TArray<string>;
  end;

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
    Lines: TDictionary<string, TLineCache>;
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
    State.Hooks.Message(AText);
end;

function TopFile(out ALine: Integer): string;
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
begin
  Result := '';
  ALine := -1;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    View := Editors.TopView;
    if (View <> nil) and (View.Buffer <> nil) then
    begin
      Result := View.Buffer.FileName;
      ALine := View.CursorPos.Line - 1;
    end;
  end;
end;

function ProjectFiles: TArray<string>;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Index: Integer;
  Info: IOTAModuleInfo;
  Main: string;
  Mains: array[0..1] of string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Project := Modules.GetActiveProject;
  if Project = nil then
    Exit;
  Mains[0] := ChangeFileExt(Project.FileName, '.dpr');
  Mains[1] := ChangeFileExt(Project.FileName, '.dpk');
  for Main in Mains do
    if TFile.Exists(Main) then
      Result := Result + [Main];
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    Info := Project.GetModule(Index);
    if (Info <> nil) and SameText(ExtractFileExt(Info.FileName), '.pas') then
      Result := Result + [Info.FileName];
  end;
end;

/// <summary>Alle in der IDE geöffneten Module (#1108), auch Projektdateien und Includes.</summary>
function OpenFiles: TArray<string>;
var
  Modules: IOTAModuleServices;
  Index: Integer;
  Module: IOTAModule;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[Index];
    if (Module <> nil) and (Module.FileName <> '') then
      Result := Result + [Module.FileName];
  end;
end;

function ClosedUnitsOf(const AText: string): TAtlasClosedUnits;
begin
  TAtlasFindings.TryParseClosedUnits(AText, Result);
end;

/// <summary>Zeile einer ungeöffneten Datei (0-basiert) von der Platte; je Datei und Änderungszeit gemerkt.</summary>
function DiskLine(const AFileName: string; ALine: Integer): string;
var
  Key: string;
  Cache: TLineCache;
  Age: TDateTime;
begin
  Result := '';
  if (State = nil) or not TFile.Exists(AFileName) then
    Exit;
  Key := AFileName.ToLower;
  try
    Age := TFile.GetLastWriteTime(AFileName);
    if not State.Lines.TryGetValue(Key, Cache) or (Cache.Age <> Age) then
    begin
      Cache.Age := Age;
      Cache.Lines := TAtlasTextFile.Load(AFileName).Text.Split([#13#10, #10]);
      State.Lines.AddOrSetValue(Key, Cache);
    end;
  except
    // Gesperrt, gelöscht oder binär: Die Spalte „Zeile“ bleibt leer, das Fenster läuft weiter.
    on Exception do
      Exit;
  end;
  if (ALine >= 0) and (ALine < Length(Cache.Lines)) then
    Result := Cache.Lines[ALine];
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
  Next: TAtlasPluginSettings;
begin
  if AFrame = nil then
    Exit;
  Next := TAtlasIdeSettings.Stored;
  Next.ProblemsWindowScope := TAtlasFindings.ScopeNames[AFrame.Scope];
  Next.ProblemsWindowGroupBy := TAtlasFindings.GroupingNames[AFrame.Grouping];
  Next.ProblemsWindowColumns := AFrame.ColumnsText;
  Next.ProblemsWindowOpenFirst := AFrame.OpenFirst;
  if (Next.ProblemsWindowScope = TAtlasIdeSettings.Stored.ProblemsWindowScope) and
    (Next.ProblemsWindowGroupBy = TAtlasIdeSettings.Stored.ProblemsWindowGroupBy) and
    (Next.ProblemsWindowColumns = TAtlasIdeSettings.Stored.ProblemsWindowColumns) and
    (Next.ProblemsWindowOpenFirst = TAtlasIdeSettings.Stored.ProblemsWindowOpenFirst) then
    Exit;
  TAtlasIdeSettings.Update(Next);
end;

procedure Refresh(AForce: Boolean);
var
  Frame: TAtlasProblemsFrame;
  Store: TAtlasProblemStore;
  Current, Inputs, Status, Last: string;
  Line: Integer;
  Files, Project, Opened: TArray<string>;
  Checked: Boolean;
  Findings: TArray<TAtlasFinding>;
  Counts: TAtlasFindingCounts;
  Check: TAtlasProblemsCheck;
  ReadLine: TFunc<string, Integer, string>;
  Percent: Integer;
begin
  Frame := TAtlasIdeProblemsWindow.ExistingFrame;
  if (Frame = nil) or not TAtlasIdeProblemsWindow.Visible then
    Exit;
  Store := TAtlasProblemsController.Current;
  Current := TopFile(Line);
  Files := nil;
  Project := nil;
  if Frame.Scope <> TAtlasFindingScope.CurrentFile then
    Project := ProjectFiles;
  if Frame.Scope = TAtlasFindingScope.Project then
    Files := Project;
  // Offene Units zuerst (#1108): geöffnete Module gehören zu den Eingaben; die Modulliste ist billig.
  Opened := nil;
  if Frame.OpenFirst then
    Opened := OpenFiles;
  // Zeigt der Editor das Formular, gilt die Unit: Hat der Server die .pas schon geliefert?
  Checked := (Store <> nil) and (Current <> '') and (Store.Contains(Current) or
    Store.Contains(ChangeFileExt(Current, '.pas')));
  Inputs := Ord(Frame.Scope).ToString + '|' + Current + '|' + string.Join(';', Files) + '|' +
    string.Join(';', Opened) + '|' + BoolToStr(Checked, True);
  Frame.SetLive(Settings.ProblemsLive and Settings.Problems);
  if (Store <> nil) and (AForce or (Store.Version <> State.Version) or (Inputs <> State.Inputs)) then
  begin
    State.Version := Store.Version;
    State.Inputs := Inputs;
    ReadLine :=
      function(AFileName: string; ALine: Integer): string
      begin
        Result := DiskLine(AFileName, ALine);
      end;
    if Frame.Scope = TAtlasFindingScope.CurrentFile then
      Findings := TAtlasFindings.FromStore(Store, [Current], ReadLine)
    else
      Findings := TAtlasFindings.FromStore(Store, Files, ReadLine);
    Frame.SetFindings(Findings, Current, Files);
    Frame.SetOpenFiles(Current, Opened, Checked);
  end
  else if Store = nil then
  begin
    Frame.SetFindings(nil, Current, Files);
    Frame.SetOpenFiles(Current, Opened, False);
  end;
  // Statuszeile.
  Counts := Frame.View.Counts;
  if Frame.View.TiersActive then
  begin
    Status := TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusTiers, [Counts.Total, Counts.OpenUnits,
      Counts.OpenFindings, Counts.ClosedUnits, Counts.ClosedFindings]);
    if Counts.HiddenUnits > 0 then
      Status := Status + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusHidden, [Counts.HiddenUnits]);
  end
  else
    Status := TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusCount, [Counts.Total, Counts.Files]);
  Check := TAtlasProblemsController.LastCheck;
  if Check.FileName <> '' then
  begin
    Last := FormatDateTime('hh":"nn":"ss', Check.At);
    Status := Status + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusLast, [Last,
      ExtractFileName(Check.FileName), Integer(Check.DurationMs)]);
  end;
  if (Store <> nil) and (Length(Project) > 0) then
    Status := Status + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusProject,
      [TAtlasFindings.CheckedCount(Store, Project), Length(Project)]);
  // Projektweite Regeln (#1102) prüfen erst mit vollständigem Index; bis dahin fehlen ihre Befunde.
  if (State <> nil) and Assigned(State.Hooks.Indexing) and State.Hooks.Indexing(Percent) then
  begin
    if Percent < 0 then
      Percent := 0;
    Status := Status + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusWaiting, [Percent]);
  end;
  if Status <> State.Status then
  begin
    State.Status := Status;
    Frame.SetStatus(Status);
  end;
  // Markierung folgt dem Cursor.
  if Settings.ProblemsWindowFollowCursor and (Current <> '') and
    (State.Cursor <> Current + ':' + Line.ToString) then
  begin
    State.Cursor := Current + ':' + Line.ToString;
    Frame.FollowCursor(Current, Line);
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
    State.Hooks.ApplyTagged(AFinding.Problem, ATag);
end;

procedure DisableRule(const AFinding: TAtlasFinding);
var
  Root: TJSONObject;
  Rules: TJSONValue;
  RulesJson, Path, Json, Target: string;
  Content: TAtlasTextFileContent;
begin
  RulesJson := '';
  Target := TAtlasProjectSettings.SettingsFile;
  if Target <> '' then
  begin
    Root := TAtlasProjectSettings.ReadProject;
    try
      if Root <> nil then
      begin
        Rules := Root.GetValue('rules');
        if Rules <> nil then
          RulesJson := Rules.ToJSON;
      end;
    finally
      Root.Free;
    end;
    // Nur "severity", wenn die Regel Optionen hat.
    TAtlasRuleTable.SeverityChange(RulesJson, AFinding.Rule, 'off', Path, Json);
    if TAtlasProjectSettings.WriteValue(Path, Json) then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.ProblemsRuleDisabled, [AFinding.Rule, ExtractFileName(Target)]));
      Exit;
    end;
  end;
  // Ohne Projekt: globale Datei.
  Target := TAtlasIdeSettings.GlobalFile;
  if (Target = '') or not TAtlasIdeSettings.LoadGlobal(Content) then
    Exit;
  Root := TAtlasJsonText.Parse(Content.Text);
  try
    if Root <> nil then
    begin
      Rules := Root.GetValue('rules');
      if Rules <> nil then
        RulesJson := Rules.ToJSON;
    end;
  finally
    Root.Free;
  end;
  // Nur dieser Wert ändert sich; Kommentare und alle anderen Schlüssel bleiben.
  TAtlasRuleTable.SeverityChange(RulesJson, AFinding.Rule, 'off', Path, Json);
  TAtlasIdeSettings.SaveGlobal(Content, TAtlasJsonText.SetValue(Content.Text, Path, Json));
  Say(TAtlasStrings.Fmt(TAtlasTextId.ProblemsRuleDisabled, [AFinding.Rule, ExtractFileName(Target)]));
end;

procedure ShowExplanation(ACatalog: TJSONValue; const ARule: string);
var
  Rows: TArray<TAtlasRuleRow>;
  Row: TAtlasRuleRow;
  Explanation: TAtlasRuleExplanation;
begin
  Rows := TAtlasRuleTable.Rows(ACatalog, '');
  for Row in Rows do
    if SameText(Row.Id, ARule) then
    begin
      Explanation.Id := Row.Id;
      Explanation.Name := Row.Name;
      Explanation.Description := Row.Description;
      Explanation.Bad := Row.Bad;
      Explanation.Good := Row.Good;
      Explanation.Experimental := Row.Experimental;
      TAtlasRuleExplainDialog.Execute(Explanation);
      Exit;
    end;
  Say(TAtlasStrings.Fmt(TAtlasTextId.ProblemsExplainUnknown, [ARule]));
end;

procedure Explain(const AFinding: TAtlasFinding);
var
  Rule, Language: string;
begin
  Rule := AFinding.Rule;
  if (State.Catalog <> nil) and (State.CatalogLanguage = TAtlasStrings.Language) then
  begin
    ShowExplanation(State.Catalog, Rule);
    Exit;
  end;
  if not Assigned(State.Hooks.Command) then
    Exit;
  Language := 'de';
  if TAtlasStrings.Language = TAtlasLanguage.English then
    Language := 'en';
  State.Hooks.Command(TAtlasProjectSettings.CatalogCommand, '["' + Language + '"]',
    procedure(AValue: TJSONValue)
    begin
      if State = nil then
        Exit;
      if AValue = nil then
      begin
        Say(TAtlasStrings.Text(TAtlasTextId.ProblemsNoServer));
        Exit;
      end;
      // Der Wert gehört dem Absender: eine Kopie merken.
      FreeAndNil(State.Catalog);
      State.Catalog := AValue.Clone as TJSONValue;
      State.CatalogLanguage := TAtlasStrings.Language;
      ShowExplanation(State.Catalog, Rule);
    end);
end;

procedure Wire(AFrame: TAtlasProblemsFrame);
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  AFrame.ShowCompilerCode := Settings.ProblemsShowCompilerCode;
  AFrame.ApplySettings(ScopeOf(Settings.ProblemsWindowScope), GroupingOf(Settings.ProblemsWindowGroupBy),
    Settings.ProblemsWindowColumns, Settings.ProblemsWindowCompiler);
  AFrame.ApplyTierSettings(Settings.ProblemsWindowOpenFirst, ClosedUnitsOf(Settings.ProblemsWindowClosedUnits),
    Settings.ProblemsWindowShowCleanActive);
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
          ApplyTag(AFinding, FixTag);
        end);
    end;
  AFrame.OnSuppress :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          ApplyTag(AFinding, SuppressLineTag);
        end);
    end;
  AFrame.OnConfigure :=
    procedure(const AFinding: TAtlasFinding)
    begin
      if (State <> nil) and Assigned(State.Hooks.ConfigureRule) then
        State.Hooks.ConfigureRule(AFinding.Rule);
    end;
  AFrame.OnDisable :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          DisableRule(AFinding);
        end);
    end;
  AFrame.OnExplain :=
    procedure(const AFinding: TAtlasFinding)
    begin
      TAtlasGuard.Run(TAtlasFeature.Problems,
        procedure
        begin
          Explain(AFinding);
        end);
    end;
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
  Lines := TDictionary<string, TLineCache>.Create;
  Version := -1;
  Timer := TTimer.Create(nil);
  Timer.Interval := TickMs;
  Timer.OnTimer := Tick;
  Timer.Enabled := True;
end;

destructor TState.Destroy;
begin
  Timer.Free;
  Lines.Free;
  Catalog.Free;
  inherited Destroy;
end;

procedure TState.Tick(Sender: TObject);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
    Exit;
  try
    Refresh(False);
  except
    on E: Exception do
    begin
      Say('Atlas-Prüfung: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

{ TAtlasIdeProblems }

class function TAtlasIdeProblems.Enabled: Boolean;
begin
  Result := Settings.Enabled and Settings.Problems and Settings.ProblemsWindow;
end;

class procedure TAtlasIdeProblems.Start(const AHooks: TAtlasIdeProblemsHooks);
begin
  if State = nil then
    State := TState.Create;
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
    TAtlasIdeProblemsWindow.Prepare;
end;

class procedure TAtlasIdeProblems.Release;
begin
  if State <> nil then
    SaveLayout(TAtlasIdeProblemsWindow.ExistingFrame);
  TAtlasIdeProblemsWindow.Release;
  FreeAndNil(State);
end;

class procedure TAtlasIdeProblems.ApplySettings;
var
  Frame: TAtlasProblemsFrame;
begin
  if not Enabled then
  begin
    TAtlasIdeProblemsWindow.Hide;
    Exit;
  end;
  TAtlasIdeProblemsWindow.Prepare;
  Frame := TAtlasIdeProblemsWindow.ExistingFrame;
  if Frame <> nil then
  begin
    Frame.ShowCompilerCode := Settings.ProblemsShowCompilerCode;
    Frame.ApplySettings(ScopeOf(Settings.ProblemsWindowScope), GroupingOf(Settings.ProblemsWindowGroupBy),
      Settings.ProblemsWindowColumns, Settings.ProblemsWindowCompiler);
    Frame.ApplyTierSettings(Settings.ProblemsWindowOpenFirst, ClosedUnitsOf(Settings.ProblemsWindowClosedUnits),
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
    Exit;
  if TAtlasIdeProblemsWindow.Show <> nil then
    Refresh(True);
end;

class procedure TAtlasIdeProblems.ShowCurrentFile;
var
  Frame: TAtlasProblemsFrame;
begin
  if not Enabled then
    Exit;
  Frame := TAtlasIdeProblemsWindow.Show;
  if Frame = nil then
    Exit;
  if Frame.Scope <> TAtlasFindingScope.CurrentFile then
  begin
    Frame.ApplySettings(TAtlasFindingScope.CurrentFile, Frame.Grouping, Frame.ColumnsText,
      Settings.ProblemsWindowCompiler);
    SaveLayout(Frame);
  end;
  Refresh(True);
end;

class function TAtlasIdeProblems.StepWindow(AForward: Boolean): Boolean;
var
  Frame: TAtlasProblemsFrame;
  Finding: TAtlasFinding;
begin
  Result := False;
  if not Enabled or not TAtlasIdeProblemsWindow.Visible then
    Exit;
  Frame := TAtlasIdeProblemsWindow.ExistingFrame;
  if (Frame = nil) or not Frame.Step(AForward, Finding) then
    Exit;
  Open(Finding);
  // Der Sprung soll die Auswahl nicht gleich wieder dem Cursor nachführen.
  if State <> nil then
    State.Cursor := Finding.FileName + ':' + Finding.Problem.StartLine.ToString;
  Result := True;
end;

end.
