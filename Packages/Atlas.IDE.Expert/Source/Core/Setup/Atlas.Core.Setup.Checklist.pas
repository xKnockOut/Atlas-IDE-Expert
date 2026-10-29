unit Atlas.Core.Setup.Checklist;

// Einrichtung mit Prüfliste (#625), Teil ohne VCL und Open Tools API:
// Sechs Prüfungen bewerten einen Zustand, den die IDE-Schicht sammelt
// (TAtlasSetupInput), und liefern je Prüfung Befund, Ampel (grün, gelb, rot),
// den Knopf, der das Problem behebt oder erklärt, und ob der Befund noch im
// Gange ist (Server startet, Index wird aufgebaut):
// - Server: gefunden, gestartet und Version passend zum Plugin.
// - Delphi: Version der IDE und Plattform des aktiven Projekts erkannt.
// - Index: alle Projekte der Gruppe indiziert, Fortschritt je Projekt (#619).
// - Bibliotheks-Cache (#492): von mindestens einem Arbeitsbereich angelegt.
// - Error Insight (#407): genau eine Fehleranzeige (IDE oder Atlas-Probleme);
//   beide an heißt doppelte Meldungen.
// - Tastenkürzel (#494, #520): keine Atlas-Taste, die einer anderen Belegung
//   überlassen ist.
// Texte macht die Oberfläche aus Befund und Args (Sprache der IDE). Der
// Bericht für „Bericht kopieren“ (#108) setzt die fertigen Zeilen zusammen und
// ersetzt Benutzer- und Rechnernamen. TAtlasSetupController führt die Knöpfe
// über IAtlasSetupEnvironment aus und prüft danach neu; StartAction entscheidet,
// ob die Prüfliste beim IDE-Start von selbst aufgeht (ui.setupChecklist).

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Commands.KeyConflicts;

type
{$SCOPEDENUMS ON}
  TAtlasSetupCheck = (Server, Delphi, Index, LibraryCache, ErrorInsight, Keys);
  /// <summary>Befund einer Prüfung; die Oberfläche macht daraus Text und Erklärung.</summary>
  TAtlasSetupFinding = (ServerReady, ServerMissing, ServerNotStarted, ServerStarting, ServerStopped, ServerFailed,
    ServerVersionUnknown, ServerVersionMismatch,
    DelphiReady, DelphiNoProject, DelphiUnknown,
    IndexReady, IndexBuilding, IndexIncomplete, IndexNoServer, IndexNoProjects,
    LibraryReady, LibraryMissing, LibraryPending, LibraryUnknown,
    ErrorInsightAtlas, ErrorInsightIde, ErrorInsightDuplicate, ErrorInsightNone, ErrorInsightRestart,
    KeysReady, KeysConflict);
  /// <summary>Knopf eines gelben oder roten Punkts: beheben oder (Explain) erklären.</summary>
  TAtlasSetupFix = (None, Explain, ChooseServerPath, StartServer, RestartServer, RebuildIndex, BuildLibraryCache,
    DisableErrorInsight, EnableErrorInsight, OpenKeyConflicts);
  TAtlasSetupProjectState = (Done, Building, Missing);
  /// <summary>Wait: Ergebnis steht noch nicht fest; Open: Prüfliste zeigen; Skip: nicht von selbst zeigen.</summary>
  TAtlasSetupStartAction = (Wait, Open, Skip);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Projekt der Gruppe mit seinem Stand im Index (#619).</summary>
  TAtlasSetupProject = record
    Name: string;
    State: TAtlasSetupProjectState;
    class function Create(const AName: string; AState: TAtlasSetupProjectState): TAtlasSetupProject; static;
  end;

  TAtlasSetupResult = record
    Check: TAtlasSetupCheck;
    Finding: TAtlasSetupFinding;
    State: TAtlasStatusState;
    Fix: TAtlasSetupFix;
    /// <summary>Noch im Gange (Server startet, Index wird aufgebaut, noch kein Projekt): zählt nicht als
    /// erledigt, öffnet die Prüfliste beim Start aber nicht von selbst.</summary>
    Pending: Boolean;
    /// <summary>Werte für den Text, je Befund fest: ServerReady [Version]; ServerFailed [Grund];
    /// ServerVersionMismatch [Server, Plugin]; DelphiReady [Produkt, Plattform]; DelphiNoProject [Produkt];
    /// IndexReady [Projekte, Units oder ''], IndexBuilding [fertig, gesamt, Prozent oder ''];
    /// IndexIncomplete [fehlend, gesamt, Namen]; LibraryReady [Byte]; KeysReady [mit Vorrang];
    /// KeysConflict [Anzahl, Taste, Belegung]; sonst leer.</summary>
    Args: TArray<string>;
    /// <summary>Nur beim Index: Stand je Projekt der Gruppe.</summary>
    Projects: TArray<TAtlasSetupProject>;
    /// <summary>Gleich, wenn sich für die Anzeige nichts geändert hat.</summary>
    function Key: string;
  end;

  /// <summary>Arbeitsbereich aus atlas.server.status (Name = Projektdatei ohne Endung).</summary>
  TAtlasSetupWorkspace = record
    Name: string;
    /// <summary>Erster Indexlauf fertig (lastIndexMs ≥ 0).</summary>
    Done: Boolean;
    LibraryCacheBytes: Int64;
  end;

  TAtlasSetupServerStatus = record
    /// <summary>False, solange keine Antwort von atlas.server.status vorliegt.</summary>
    Known: Boolean;
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    Units: Integer;
    Workspaces: TArray<TAtlasSetupWorkspace>;
    /// <summary>Antwort von atlas.server.status (#28, #492); Known = False bei leerem oder ungültigem Text.</summary>
    class function Parse(const AJson: string): TAtlasSetupServerStatus; static;
  end;

  /// <summary>Eine Atlas-Taste mit Text und fremder Belegung ('' = frei).</summary>
  TAtlasSetupKey = record
    Entry: TAtlasKeyEntry;
    KeyText: string;
    Owner: string;
    class function Create(const AEntry: TAtlasKeyEntry; const AKeyText, AOwner: string): TAtlasSetupKey; static;
  end;

  /// <summary>Was die IDE-Schicht für die Prüfungen sammelt (Hauptthread).</summary>
  TAtlasSetupInput = record
    /// <summary>AtlasServer.exe am eingestellten bzw. vorgegebenen Pfad vorhanden.</summary>
    ServerFound: Boolean;
    Server: TAtlasServerInfo;
    PluginVersion: string;
    /// <summary>Version der laufenden IDE aus ihrem Registry-Schlüssel, z. B. "37.0"; '' = unbekannt.</summary>
    BdsVersion: string;
    /// <summary>Plattform des aktiven Projekts, z. B. "Win64"; '' ohne Projekt.</summary>
    Platform: string;
    /// <summary>Projekte der Gruppe als Name der .dproj ohne Endung, aktives zuerst.</summary>
    Projects: TArray<string>;
    /// <summary>Fortschrittsmeldung des Servers ($/progress) läuft; Prozent -1 = unbekannt.</summary>
    Indexing: Boolean;
    IndexPercent: Integer;
    Status: TAtlasSetupServerStatus;
    /// <summary>Error Insight der IDE an (Registry; ohne Wert gilt die Vorgabe der IDE: an).</summary>
    ErrorInsight: Boolean;
    /// <summary>Atlas zeigt Probleme im Editor (Hauptschalter und Probleme, #398).</summary>
    AtlasProblems: Boolean;
    /// <summary>Atlas hat Error Insight in dieser Sitzung umgeschaltet; wirkt erst nach dem Neustart der IDE.</summary>
    ErrorInsightRestart: Boolean;
    Keys: TArray<TAtlasSetupKey>;
  end;

  TAtlasSetupReportLine = record
    State: TAtlasStatusState;
    Text: string;
    /// <summary>Unterzeile (Projekt beim Index).</summary>
    Indent: Boolean;
    class function Create(AState: TAtlasStatusState; const AText: string; AIndent: Boolean): TAtlasSetupReportLine;
      static;
  end;

  /// <summary>Bausteine von „Bericht kopieren“; Texte schon in der Sprache der Oberfläche.</summary>
  TAtlasSetupReportInput = record
    Title: string;
    /// <summary>z. B. „5 von 6 erledigt“.</summary>
    Summary: string;
    AtlasVersion: string;
    IdeVersion: string;
    Platform: string;
    Created: TDateTime;
    /// <summary>Benutzer-, Rechner- und Domänenname; werden zu &lt;benutzer&gt;.</summary>
    Identity: TArray<string>;
    Lines: TArray<TAtlasSetupReportLine>;
  end;

  TAtlasSetupChecklist = class
  public const
    /// <summary>Zeile im Atlas-Statusfeld (#591), auch Quelle der Zustandskachel (#754).</summary>
    StatusId = TAtlasStatusLines.SetupId;
    StatusOrder = 4;
    /// <summary>Befehl der Palette und des Menüs Atlas › Einrichtung prüfen.</summary>
    CommandId = 'Atlas.SetupChecklist';
    /// <summary>Höchstens so lange wartet der Start auf Befunde, die noch im Gange sind.</summary>
    StartWaitMs = 120000;
    RebuildCommand = 'atlas.server.rebuildIndex';
    IdentityMark = '<benutzer>';
  public
    class function CheckServer(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    class function CheckDelphi(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    class function CheckIndex(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    class function CheckLibraryCache(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    class function CheckErrorInsight(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    class function CheckKeys(const AInput: TAtlasSetupInput): TAtlasSetupResult; static;
    /// <summary>Alle Prüfungen in der Reihenfolge von TAtlasSetupCheck.</summary>
    class function Evaluate(const AInput: TAtlasSetupInput): TArray<TAtlasSetupResult>; static;
    /// <summary>ADone = grüne Punkte, ATotal = alle.</summary>
    class procedure Progress(const AResults: TArray<TAtlasSetupResult>; out ADone, ATotal: Integer); static;
    /// <summary>Alles grün (und mindestens eine Prüfung).</summary>
    class function Complete(const AResults: TArray<TAtlasSetupResult>): Boolean; static;
    /// <summary>Soll die Prüfliste beim IDE-Start von selbst aufgehen? Aus: nie. Erster Start: sofort.
    /// Sonst, sobald ein Punkt fest gelb oder rot ist; alles grün oder nach AWaitMs nur noch Punkte im Gange:
    /// nicht.</summary>
    class function StartAction(AEnabled, AFirstStart: Boolean; const AResults: TArray<TAtlasSetupResult>;
      AElapsedMs, AWaitMs: Int64): TAtlasSetupStartAction; static;
    /// <summary>Gleiche Version ohne Build-Angabe (+…) und ohne führendes „v“.</summary>
    class function VersionsMatch(const AServer, APlugin: string): Boolean; static;
    /// <summary>Name eines Projekts wie der Server seinen Arbeitsbereich nennt: Datei ohne Ordner und Endung.</summary>
    class function ProjectName(const AProjectFile: string): string; static;
    /// <summary>Text für „Bericht kopieren“.</summary>
    class function Report(const AInput: TAtlasSetupReportInput): string; static;
    /// <summary>Kennung eines Zustands im Bericht: [ok], [!] bzw. [x].</summary>
    class function StateMark(AState: TAtlasStatusState): string; static;
  end;

  /// <summary>Was die Knöpfe in der IDE tun; Tests setzen eine eigene Umgebung ein.</summary>
  IAtlasSetupEnvironment = interface
    ['{5E2A9C61-7B3D-4F08-A1C4-93D6E28B7F15}']
    /// <summary>Zustand für die Prüfungen sammeln (Hauptthread, schnell; die Serverabfrage läuft im Hintergrund).</summary>
    function Snapshot: TAtlasSetupInput;
    /// <summary>Dateiauswahl für AtlasServer.exe; False bei Abbruch.</summary>
    function ChooseServerPath(out APath: string): Boolean;
    /// <summary>Pfad in den Plugin-Einstellungen speichern (ServerPath).</summary>
    procedure SaveServerPath(const APath: string);
    /// <summary>Server starten bzw. neu starten; True, wenn er läuft.</summary>
    function StartServer(ARestart: Boolean): Boolean;
    /// <summary>atlas.server.rebuildIndex; True, wenn der Server den Befehl angenommen hat.</summary>
    function RebuildIndex: Boolean;
    /// <summary>Error Insight der IDE schalten; True, wenn geschrieben.</summary>
    function SetErrorInsight(AEnabled: Boolean): Boolean;
    /// <summary>Optionsseite „Tastenkonflikte“ öffnen.</summary>
    procedure OpenKeyConflicts;
  end;

  TAtlasSetupController = class
  private
    FEnvironment: IAtlasSetupEnvironment;
    FResults: TArray<TAtlasSetupResult>;
    FKey: string;
    FVersion: Integer;
  public
    constructor Create(const AEnvironment: IAtlasSetupEnvironment);
    /// <summary>Neu prüfen; Version steigt nur, wenn sich ein Punkt geändert hat.</summary>
    function Refresh: TArray<TAtlasSetupResult>;
    /// <summary>Knopf ausführen und neu prüfen; False, wenn nichts zu tun war (None, Explain, Abbruch).</summary>
    function Apply(AFix: TAtlasSetupFix): Boolean;
    function Results: TArray<TAtlasSetupResult>;
    procedure Progress(out ADone, ATotal: Integer);
    function Complete: Boolean;
    property Version: Integer read FVersion;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.Choices;

function Make(ACheck: TAtlasSetupCheck; AFinding: TAtlasSetupFinding; AState: TAtlasStatusState;
  AFix: TAtlasSetupFix; APending: Boolean; const AArgs: TArray<string>): TAtlasSetupResult;
begin
  Result := Default(TAtlasSetupResult);
  Result.Check := ACheck;
  Result.Finding := AFinding;
  Result.State := AState;
  Result.Fix := AFix;
  Result.Pending := APending;
  Result.Args := AArgs;
end;

function JsonNumber(AObject: TJSONObject; const AName: string; ADefault: Int64): Int64;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt64;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function SameName(const A, B: string): Boolean;
begin
  Result := SameText(Trim(A), Trim(B));
end;

{ TAtlasSetupProject }

class function TAtlasSetupProject.Create(const AName: string; AState: TAtlasSetupProjectState): TAtlasSetupProject;
begin
  Result.Name := AName;
  Result.State := AState;
end;

{ TAtlasSetupResult }

function TAtlasSetupResult.Key: string;
var
  Arg: string;
  Project: TAtlasSetupProject;
begin
  Result := Format('%d|%d|%d|%d|%d', [Ord(Check), Ord(Finding), Ord(State), Ord(Fix), Ord(Pending)]);
  for Arg in Args do
    Result := Result + '|' + Arg;
  for Project in Projects do
    Result := Result + '|' + Project.Name + '=' + IntToStr(Ord(Project.State));
end;

{ TAtlasSetupServerStatus }

class function TAtlasSetupServerStatus.Parse(const AJson: string): TAtlasSetupServerStatus;
var
  Value, Item: TJSONValue;
  Root: TJSONObject;
  Workspace: TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupServerStatus);
  Result.Units := -1;
  if Trim(AJson) = '' then
    Exit;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    Result.Known := True;
    Result.Units := Integer(JsonNumber(Root, 'units', -1));
    if Root.GetValue('workspaces') is TJSONArray then
      for Item in TJSONArray(Root.GetValue('workspaces')) do
        if Item is TJSONObject then
        begin
          Workspace.Name := JsonText(TJSONObject(Item), 'name');
          Workspace.Done := JsonNumber(TJSONObject(Item), 'lastIndexMs', -1) >= 0;
          Workspace.LibraryCacheBytes := JsonNumber(TJSONObject(Item), 'libraryCacheBytes', 0);
          Result.Workspaces := Result.Workspaces + [Workspace];
        end;
  finally
    Value.Free;
  end;
end;

{ TAtlasSetupKey }

class function TAtlasSetupKey.Create(const AEntry: TAtlasKeyEntry; const AKeyText, AOwner: string): TAtlasSetupKey;
begin
  Result.Entry := AEntry;
  Result.KeyText := AKeyText;
  Result.Owner := AOwner;
end;

{ TAtlasSetupReportLine }

class function TAtlasSetupReportLine.Create(AState: TAtlasStatusState; const AText: string;
  AIndent: Boolean): TAtlasSetupReportLine;
begin
  Result.State := AState;
  Result.Text := AText;
  Result.Indent := AIndent;
end;

{ TAtlasSetupChecklist }

class function TAtlasSetupChecklist.VersionsMatch(const AServer, APlugin: string): Boolean;

  function Core(const AValue: string): string;
  var
    Plus: Integer;
  begin
    Result := Trim(AValue);
    if (Result <> '') and CharInSet(Result[1], ['v', 'V']) then
      Delete(Result, 1, 1);
    Plus := Pos('+', Result);
    if Plus > 0 then
      Result := Copy(Result, 1, Plus - 1);
  end;

begin
  Result := (Core(AServer) <> '') and SameText(Core(AServer), Core(APlugin));
end;

class function TAtlasSetupChecklist.ProjectName(const AProjectFile: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AProjectFile), '');
end;

class function TAtlasSetupChecklist.CheckServer(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.Server;
begin
  if not AInput.ServerFound then
    Exit(Make(C, TAtlasSetupFinding.ServerMissing, TAtlasStatusState.Red, TAtlasSetupFix.ChooseServerPath, False,
      nil));
  case AInput.Server.Phase of
    TAtlasServerPhase.Starting:
      Result := Make(C, TAtlasSetupFinding.ServerStarting, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil);
    TAtlasServerPhase.Stopped:
      Result := Make(C, TAtlasSetupFinding.ServerStopped, TAtlasStatusState.Red, TAtlasSetupFix.RestartServer, False,
        nil);
    TAtlasServerPhase.Failed:
      Result := Make(C, TAtlasSetupFinding.ServerFailed, TAtlasStatusState.Red, TAtlasSetupFix.RestartServer, False,
        [AInput.Server.Error]);
    TAtlasServerPhase.Running:
      if Trim(AInput.Server.Version) = '' then
        Result := Make(C, TAtlasSetupFinding.ServerVersionUnknown, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain,
          True, nil)
      else if not VersionsMatch(AInput.Server.Version, AInput.PluginVersion) then
        // Ein anderer Server (z. B. alter Pfad aus einer früheren Installation): richtigen wählen.
        Result := Make(C, TAtlasSetupFinding.ServerVersionMismatch, TAtlasStatusState.Red,
          TAtlasSetupFix.ChooseServerPath, False, [Trim(AInput.Server.Version), AInput.PluginVersion])
      else
        Result := Make(C, TAtlasSetupFinding.ServerReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
          [Trim(AInput.Server.Version)]);
  else
    // Gefunden, aber noch nicht gebraucht: Atlas startet ihn beim ersten Zugriff.
    Result := Make(C, TAtlasSetupFinding.ServerNotStarted, TAtlasStatusState.Yellow, TAtlasSetupFix.StartServer,
      True, nil);
  end;
end;

class function TAtlasSetupChecklist.CheckDelphi(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.Delphi;
var
  Caption: string;
begin
  if Trim(AInput.BdsVersion) = '' then
    Exit(Make(C, TAtlasSetupFinding.DelphiUnknown, TAtlasStatusState.Red, TAtlasSetupFix.Explain, False, nil));
  Caption := TAtlasSettingChoices.DelphiCaption(Trim(AInput.BdsVersion));
  if Trim(AInput.Platform) = '' then
    Result := Make(C, TAtlasSetupFinding.DelphiNoProject, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True,
      [Caption])
  else
    Result := Make(C, TAtlasSetupFinding.DelphiReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [Caption, Trim(AInput.Platform)]);
end;

class function TAtlasSetupChecklist.CheckIndex(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.Index;
var
  Projects: TArray<TAtlasSetupProject>;
  Name, Missing, Units, Percent: string;
  Workspace: TAtlasSetupWorkspace;
  Found, Building: Boolean;
  State: TAtlasSetupProjectState;
  DoneCount, MissingCount, Total: Integer;
begin
  if AInput.Server.Phase <> TAtlasServerPhase.Running then
    Exit(Make(C, TAtlasSetupFinding.IndexNoServer, TAtlasStatusState.Yellow, TAtlasSetupFix.StartServer, True, nil));
  Projects := nil;
  DoneCount := 0;
  MissingCount := 0;
  Missing := '';
  Building := AInput.Indexing or not AInput.Status.Known;
  for Name in AInput.Projects do
  begin
    Found := False;
    State := TAtlasSetupProjectState.Missing;
    for Workspace in AInput.Status.Workspaces do
      if SameName(Workspace.Name, Name) then
      begin
        Found := True;
        if Workspace.Done then
          State := TAtlasSetupProjectState.Done
        else
          State := TAtlasSetupProjectState.Building;
      end;
    // Vor der ersten Antwort des Servers gilt jedes Projekt als „wird aufgebaut“.
    if not Found and not AInput.Status.Known then
      State := TAtlasSetupProjectState.Building;
    case State of
      TAtlasSetupProjectState.Done:
        Inc(DoneCount);
      TAtlasSetupProjectState.Building:
        Building := True;
    else
      begin
        Inc(MissingCount);
        if Missing <> '' then
          Missing := Missing + ', ';
        Missing := Missing + Name;
      end;
    end;
    Projects := Projects + [TAtlasSetupProject.Create(Name, State)];
  end;
  // Ohne Projektgruppe: die Arbeitsbereiche, die der Server aus geöffneten Dateien abgeleitet hat.
  if Length(AInput.Projects) = 0 then
    for Workspace in AInput.Status.Workspaces do
    begin
      if Workspace.Done then
      begin
        Inc(DoneCount);
        Projects := Projects + [TAtlasSetupProject.Create(Workspace.Name, TAtlasSetupProjectState.Done)];
      end
      else
      begin
        Building := True;
        Projects := Projects + [TAtlasSetupProject.Create(Workspace.Name, TAtlasSetupProjectState.Building)];
      end;
    end;
  Total := Length(Projects);
  if Building then
  begin
    Percent := '';
    if AInput.Indexing and (AInput.IndexPercent >= 0) then
      Percent := IntToStr(AInput.IndexPercent);
    Result := Make(C, TAtlasSetupFinding.IndexBuilding, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True,
      [IntToStr(DoneCount), IntToStr(Total), Percent]);
  end
  else if Total = 0 then
    Result := Make(C, TAtlasSetupFinding.IndexNoProjects, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil)
  else if MissingCount > 0 then
    Result := Make(C, TAtlasSetupFinding.IndexIncomplete, TAtlasStatusState.Yellow, TAtlasSetupFix.RebuildIndex,
      False, [IntToStr(MissingCount), IntToStr(Total), Missing])
  else
  begin
    Units := '';
    if AInput.Status.Units >= 0 then
      Units := IntToStr(AInput.Status.Units);
    Result := Make(C, TAtlasSetupFinding.IndexReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(Total), Units]);
  end;
  Result.Projects := Projects;
end;

class function TAtlasSetupChecklist.CheckLibraryCache(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.LibraryCache;
var
  Workspace: TAtlasSetupWorkspace;
  Bytes: Int64;
  Building: Boolean;
begin
  if (AInput.Server.Phase <> TAtlasServerPhase.Running) or not AInput.Status.Known then
    Exit(Make(C, TAtlasSetupFinding.LibraryUnknown, TAtlasStatusState.Yellow, TAtlasSetupFix.StartServer, True, nil));
  Bytes := 0;
  Building := AInput.Indexing;
  for Workspace in AInput.Status.Workspaces do
  begin
    if Workspace.LibraryCacheBytes > Bytes then
      Bytes := Workspace.LibraryCacheBytes;
    if not Workspace.Done then
      Building := True;
  end;
  if Bytes > 0 then
    Result := Make(C, TAtlasSetupFinding.LibraryReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(Bytes)])
  else if Building or (Length(AInput.Status.Workspaces) = 0) then
    // Der Cache entsteht am Ende des ersten Indexlaufs.
    Result := Make(C, TAtlasSetupFinding.LibraryPending, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil)
  else
    Result := Make(C, TAtlasSetupFinding.LibraryMissing, TAtlasStatusState.Yellow, TAtlasSetupFix.BuildLibraryCache,
      False, nil);
end;

class function TAtlasSetupChecklist.CheckErrorInsight(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.ErrorInsight;
begin
  if AInput.ErrorInsightRestart then
    Result := Make(C, TAtlasSetupFinding.ErrorInsightRestart, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, False,
      nil)
  else if AInput.ErrorInsight and AInput.AtlasProblems then
    Result := Make(C, TAtlasSetupFinding.ErrorInsightDuplicate, TAtlasStatusState.Yellow,
      TAtlasSetupFix.DisableErrorInsight, False, nil)
  else if AInput.ErrorInsight then
    Result := Make(C, TAtlasSetupFinding.ErrorInsightIde, TAtlasStatusState.Green, TAtlasSetupFix.None, False, nil)
  else if AInput.AtlasProblems then
    Result := Make(C, TAtlasSetupFinding.ErrorInsightAtlas, TAtlasStatusState.Green, TAtlasSetupFix.None, False, nil)
  else
    // Weder die IDE noch Atlas zeigen Fehler im Editor.
    Result := Make(C, TAtlasSetupFinding.ErrorInsightNone, TAtlasStatusState.Yellow,
      TAtlasSetupFix.EnableErrorInsight, False, nil);
end;

class function TAtlasSetupChecklist.CheckKeys(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  C = TAtlasSetupCheck.Keys;
var
  Key: TAtlasSetupKey;
  Conflicts, Wins: Integer;
  First: TAtlasSetupKey;
begin
  Conflicts := 0;
  Wins := 0;
  First := Default(TAtlasSetupKey);
  for Key in AInput.Keys do
    case Key.Entry.Status(Key.Owner) of
      // Atlas überlässt die Taste der anderen Belegung: Die Atlas-Funktion hat keine Taste.
      TAtlasKeyStatus.Left:
        begin
          if Conflicts = 0 then
            First := Key;
          Inc(Conflicts);
        end;
      // Bewusst entschieden („Atlas verwenden“): kein offener Konflikt.
      TAtlasKeyStatus.AtlasWins:
        Inc(Wins);
    end;
  if Conflicts > 0 then
    Result := Make(C, TAtlasSetupFinding.KeysConflict, TAtlasStatusState.Yellow, TAtlasSetupFix.OpenKeyConflicts,
      False, [IntToStr(Conflicts), First.KeyText, First.Owner])
  else
    Result := Make(C, TAtlasSetupFinding.KeysReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(Wins)]);
end;

class function TAtlasSetupChecklist.Evaluate(const AInput: TAtlasSetupInput): TArray<TAtlasSetupResult>;
begin
  Result := [CheckServer(AInput), CheckDelphi(AInput), CheckIndex(AInput), CheckLibraryCache(AInput),
    CheckErrorInsight(AInput), CheckKeys(AInput)];
end;

class procedure TAtlasSetupChecklist.Progress(const AResults: TArray<TAtlasSetupResult>; out ADone,
  ATotal: Integer);
var
  Item: TAtlasSetupResult;
begin
  ADone := 0;
  ATotal := Length(AResults);
  for Item in AResults do
    if Item.State = TAtlasStatusState.Green then
      Inc(ADone);
end;

class function TAtlasSetupChecklist.Complete(const AResults: TArray<TAtlasSetupResult>): Boolean;
var
  Done, Total: Integer;
begin
  Progress(AResults, Done, Total);
  Result := (Total > 0) and (Done = Total);
end;

class function TAtlasSetupChecklist.StartAction(AEnabled, AFirstStart: Boolean;
  const AResults: TArray<TAtlasSetupResult>; AElapsedMs, AWaitMs: Int64): TAtlasSetupStartAction;
var
  Item: TAtlasSetupResult;
  Waiting: Boolean;
begin
  if not AEnabled then
    Exit(TAtlasSetupStartAction.Skip);
  if AFirstStart then
    Exit(TAtlasSetupStartAction.Open);
  Waiting := False;
  for Item in AResults do
    if Item.State <> TAtlasStatusState.Green then
    begin
      if not Item.Pending then
        Exit(TAtlasSetupStartAction.Open);
      Waiting := True;
    end;
  if (Length(AResults) = 0) or (Waiting and (AElapsedMs < AWaitMs)) then
    Result := TAtlasSetupStartAction.Wait
  else
    Result := TAtlasSetupStartAction.Skip;
end;

class function TAtlasSetupChecklist.StateMark(AState: TAtlasStatusState): string;
begin
  case AState of
    TAtlasStatusState.Green:
      Result := '[ok]';
    TAtlasStatusState.Yellow:
      Result := '[!] ';
    TAtlasStatusState.Red:
      Result := '[x] ';
  else
    Result := '[-] ';
  end;
end;

class function TAtlasSetupChecklist.Report(const AInput: TAtlasSetupReportInput): string;
var
  Builder: TStringBuilder;
  Line: TAtlasSetupReportLine;
  Identity, Versions, Swap: string;
  Identities: TArray<string>;
  Index, Other: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append(AInput.Title).Append(sLineBreak);
    Versions := 'Atlas ' + AInput.AtlasVersion;
    if AInput.IdeVersion <> '' then
      Versions := Versions + ', IDE ' + AInput.IdeVersion;
    if AInput.Platform <> '' then
      Versions := Versions + ', ' + AInput.Platform;
    Builder.Append(Versions).Append(sLineBreak);
    Builder.Append(FormatDateTime('yyyy-mm-dd hh":"nn', AInput.Created)).Append(sLineBreak);
    Builder.Append(AInput.Summary).Append(sLineBreak).Append(sLineBreak);
    for Line in AInput.Lines do
      if Line.Indent then
        Builder.Append('       - ').Append(Line.Text).Append(sLineBreak)
      else
        Builder.Append(StateMark(Line.State)).Append(' ').Append(Line.Text).Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
  // Keine Namen von Benutzer, Rechner oder Domäne (#108); Pfade enthalten die Zeilen nicht. Längere Namen
  // zuerst, sonst bliebe vom Rechnernamen „WS-MARCO“ nach dem Benutzer „marco“ ein Rest stehen.
  Identities := nil;
  for Identity in AInput.Identity do
    if Length(Trim(Identity)) >= 2 then
      Identities := Identities + [Trim(Identity)];
  for Index := 0 to High(Identities) - 1 do
    for Other := Index + 1 to High(Identities) do
      if Length(Identities[Other]) > Length(Identities[Index]) then
      begin
        Swap := Identities[Index];
        Identities[Index] := Identities[Other];
        Identities[Other] := Swap;
      end;
  for Identity in Identities do
    Result := StringReplace(Result, Identity, IdentityMark, [rfReplaceAll, rfIgnoreCase]);
end;

{ TAtlasSetupController }

constructor TAtlasSetupController.Create(const AEnvironment: IAtlasSetupEnvironment);
begin
  inherited Create;
  FEnvironment := AEnvironment;
end;

function TAtlasSetupController.Refresh: TArray<TAtlasSetupResult>;
var
  Item: TAtlasSetupResult;
  Key: string;
begin
  FResults := TAtlasSetupChecklist.Evaluate(FEnvironment.Snapshot);
  Key := '';
  for Item in FResults do
    Key := Key + Item.Key + #10;
  if Key <> FKey then
  begin
    FKey := Key;
    Inc(FVersion);
  end;
  Result := FResults;
end;

function TAtlasSetupController.Apply(AFix: TAtlasSetupFix): Boolean;
var
  Path: string;
begin
  case AFix of
    TAtlasSetupFix.ChooseServerPath:
      begin
        Result := FEnvironment.ChooseServerPath(Path) and (Trim(Path) <> '');
        if Result then
        begin
          FEnvironment.SaveServerPath(Trim(Path));
          // Mit dem neuen Pfad starten, damit die Prüfung gleich den neuen Server sieht.
          FEnvironment.StartServer(True);
        end;
      end;
    TAtlasSetupFix.StartServer:
      Result := FEnvironment.StartServer(False);
    TAtlasSetupFix.RestartServer:
      Result := FEnvironment.StartServer(True);
    TAtlasSetupFix.RebuildIndex, TAtlasSetupFix.BuildLibraryCache:
      Result := FEnvironment.RebuildIndex;
    TAtlasSetupFix.DisableErrorInsight:
      Result := FEnvironment.SetErrorInsight(False);
    TAtlasSetupFix.EnableErrorInsight:
      Result := FEnvironment.SetErrorInsight(True);
    TAtlasSetupFix.OpenKeyConflicts:
      begin
        FEnvironment.OpenKeyConflicts;
        Result := True;
      end;
  else
    Result := False;
  end;
  Refresh;
end;

function TAtlasSetupController.Results: TArray<TAtlasSetupResult>;
begin
  Result := FResults;
end;

procedure TAtlasSetupController.Progress(out ADone, ATotal: Integer);
begin
  TAtlasSetupChecklist.Progress(FResults, ADone, ATotal);
end;

function TAtlasSetupController.Complete: Boolean;
begin
  Result := TAtlasSetupChecklist.Complete(FResults);
end;

end.
