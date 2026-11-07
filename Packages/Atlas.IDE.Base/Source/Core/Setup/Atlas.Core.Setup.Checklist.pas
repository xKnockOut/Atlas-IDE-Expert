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
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt64;
  end;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
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
  mArg: string;
  mProject: TAtlasSetupProject;
begin
  Result := Format('%d|%d|%d|%d|%d', [Ord(Check), Ord(Finding), Ord(State), Ord(Fix), Ord(Pending)]);
  for mArg in Args do
  begin
    Result := Result + '|' + mArg;
  end;
  for mProject in Projects do
  begin
    Result := Result + '|' + mProject.Name + '=' + IntToStr(Ord(mProject.State));
  end;
end;

{ TAtlasSetupServerStatus }

class function TAtlasSetupServerStatus.Parse(const AJson: string): TAtlasSetupServerStatus;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mWorkspace: TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupServerStatus);
  Result.Units := -1;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    Result.Known := True;
    Result.Units := Integer(JsonNumber(mRoot, 'units', -1));
    if mRoot.GetValue('workspaces') is TJSONArray then
    begin
      for mItem in TJSONArray(mRoot.GetValue('workspaces')) do
      begin
        if mItem is TJSONObject then
        begin
          mWorkspace.Name := JsonText(TJSONObject(mItem), 'name');
          mWorkspace.Done := JsonNumber(TJSONObject(mItem), 'lastIndexMs', -1) >= 0;
          mWorkspace.LibraryCacheBytes := JsonNumber(TJSONObject(mItem), 'libraryCacheBytes', 0);
          Result.Workspaces := Result.Workspaces + [mWorkspace];
        end;
      end;
    end;
  finally
    mValue.Free;
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
    mPlus: Integer;
  begin
    Result := Trim(AValue);
    if (Result <> '') and CharInSet(Result[1], ['v', 'V']) then
    begin
      Delete(Result, 1, 1);
    end;
    mPlus := Pos('+', Result);
    if mPlus > 0 then
    begin
      Result := Copy(Result, 1, mPlus - 1);
    end;
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
  cC = TAtlasSetupCheck.Server;
begin
  if not AInput.ServerFound then
  begin
    Exit(Make(cC, TAtlasSetupFinding.ServerMissing, TAtlasStatusState.Red, TAtlasSetupFix.ChooseServerPath, False,
      nil));
  end;
  case AInput.Server.Phase of
    TAtlasServerPhase.Starting:
      Result := Make(cC, TAtlasSetupFinding.ServerStarting, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil);
    TAtlasServerPhase.Stopped:
      Result := Make(cC, TAtlasSetupFinding.ServerStopped, TAtlasStatusState.Red, TAtlasSetupFix.RestartServer, False,
        nil);
    TAtlasServerPhase.Failed:
      Result := Make(cC, TAtlasSetupFinding.ServerFailed, TAtlasStatusState.Red, TAtlasSetupFix.RestartServer, False,
        [AInput.Server.Error]);
    TAtlasServerPhase.Running:
      if Trim(AInput.Server.Version) = '' then
      begin
        Result := Make(cC, TAtlasSetupFinding.ServerVersionUnknown, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain,
          True, nil);
      end
      else if not VersionsMatch(AInput.Server.Version, AInput.PluginVersion) then
      begin
        // Ein anderer Server (z. B. alter Pfad aus einer früheren Installation): richtigen wählen.
        Result := Make(cC, TAtlasSetupFinding.ServerVersionMismatch, TAtlasStatusState.Red,
          TAtlasSetupFix.ChooseServerPath, False, [Trim(AInput.Server.Version), AInput.PluginVersion]);
      end
      else
      begin
        Result := Make(cC, TAtlasSetupFinding.ServerReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
          [Trim(AInput.Server.Version)]);
      end;
  else
    // Gefunden, aber noch nicht gebraucht: Atlas startet ihn beim ersten Zugriff.
    Result := Make(cC, TAtlasSetupFinding.ServerNotStarted, TAtlasStatusState.Yellow, TAtlasSetupFix.StartServer,
      True, nil);
  end;
end;

class function TAtlasSetupChecklist.CheckDelphi(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  cC = TAtlasSetupCheck.Delphi;
var
  mCaption: string;
begin
  if Trim(AInput.BdsVersion) = '' then
  begin
    Exit(Make(cC, TAtlasSetupFinding.DelphiUnknown, TAtlasStatusState.Red, TAtlasSetupFix.Explain, False, nil));
  end;
  mCaption := TAtlasSettingChoices.DelphiCaption(Trim(AInput.BdsVersion));
  if Trim(AInput.Platform) = '' then
  begin
    Result := Make(cC, TAtlasSetupFinding.DelphiNoProject, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True,
      [mCaption]);
  end
  else
  begin
    Result := Make(cC, TAtlasSetupFinding.DelphiReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [mCaption, Trim(AInput.Platform)]);
  end;
end;

function WorkspaceState(const AWorkspace: TAtlasSetupWorkspace): TAtlasSetupProjectState;
begin
  if AWorkspace.Done then
  begin
    Result := TAtlasSetupProjectState.Done;
  end
  else
  begin
    Result := TAtlasSetupProjectState.Building;
  end;
end;

/// <summary>Zustand des Projekts AName nach der Antwort des Servers.</summary>
function ProjectStateOf(const AStatus: TAtlasSetupServerStatus; const AName: string): TAtlasSetupProjectState;
var
  mWorkspace: TAtlasSetupWorkspace;
begin
  // Vor der ersten Antwort des Servers gilt jedes Projekt als „wird aufgebaut“.
  Result := TAtlasSetupProjectState.Missing;
  if not AStatus.Known then
  begin
    Result := TAtlasSetupProjectState.Building;
  end;
  for mWorkspace in AStatus.Workspaces do
  begin
    if SameName(mWorkspace.Name, AName) then
    begin
      Result := WorkspaceState(mWorkspace);
    end;
  end;
end;

type
  /// <summary>Zählung von CheckIndex: Projekte mit Zustand, fertige und fehlende.</summary>
  TIndexTally = record
    Projects: TArray<TAtlasSetupProject>;
    DoneCount: Integer;
    MissingCount: Integer;
    Missing: string;
    Building: Boolean;
    procedure Add(const AName: string; AState: TAtlasSetupProjectState);
    function Verdict(const AInput: TAtlasSetupInput): TAtlasSetupResult;
  end;

procedure TIndexTally.Add(const AName: string; AState: TAtlasSetupProjectState);
begin
  case AState of
    TAtlasSetupProjectState.Done:
      Inc(DoneCount);
    TAtlasSetupProjectState.Building:
      Building := True;
  else
    begin
      Inc(MissingCount);
      if Missing <> '' then
      begin
        Missing := Missing + ', ';
      end;
      Missing := Missing + AName;
    end;
  end;
  Projects := Projects + [TAtlasSetupProject.Create(AName, AState)];
end;

function TIndexTally.Verdict(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  cC = TAtlasSetupCheck.Index;
var
  mTotal: Integer;
  mText: string;
begin
  mTotal := Length(Projects);
  if Building then
  begin
    mText := '';
    if AInput.Indexing and (AInput.IndexPercent >= 0) then
    begin
      mText := IntToStr(AInput.IndexPercent);
    end;
    Result := Make(cC, TAtlasSetupFinding.IndexBuilding, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True,
      [IntToStr(DoneCount), IntToStr(mTotal), mText]);
  end
  else if mTotal = 0 then
  begin
    Result := Make(cC, TAtlasSetupFinding.IndexNoProjects, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil);
  end
  else if MissingCount > 0 then
  begin
    Result := Make(cC, TAtlasSetupFinding.IndexIncomplete, TAtlasStatusState.Yellow, TAtlasSetupFix.RebuildIndex,
      False, [IntToStr(MissingCount), IntToStr(mTotal), Missing]);
  end
  else
  begin
    mText := '';
    if AInput.Status.Units >= 0 then
    begin
      mText := IntToStr(AInput.Status.Units);
    end;
    Result := Make(cC, TAtlasSetupFinding.IndexReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(mTotal), mText]);
  end;
end;
class function TAtlasSetupChecklist.CheckIndex(const AInput: TAtlasSetupInput): TAtlasSetupResult;
var
  mTally: TIndexTally;
  mName: string;
  mWorkspace: TAtlasSetupWorkspace;
begin
  if AInput.Server.Phase <> TAtlasServerPhase.Running then
  begin
    Exit(Make(TAtlasSetupCheck.Index, TAtlasSetupFinding.IndexNoServer, TAtlasStatusState.Yellow,
      TAtlasSetupFix.StartServer, True, nil));
  end;
  mTally := Default(TIndexTally);
  mTally.Building := AInput.Indexing or not AInput.Status.Known;
  for mName in AInput.Projects do
  begin
    mTally.Add(mName, ProjectStateOf(AInput.Status, mName));
  end;
  // Ohne Projektgruppe: die Arbeitsbereiche, die der Server aus geöffneten Dateien abgeleitet hat.
  if Length(AInput.Projects) = 0 then
  begin
    for mWorkspace in AInput.Status.Workspaces do
    begin
      mTally.Add(mWorkspace.Name, WorkspaceState(mWorkspace));
    end;
  end;
  Result := mTally.Verdict(AInput);
  Result.Projects := mTally.Projects;
end;

class function TAtlasSetupChecklist.CheckLibraryCache(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  cC = TAtlasSetupCheck.LibraryCache;
var
  mWorkspace: TAtlasSetupWorkspace;
  mBytes: Int64;
  mBuilding: Boolean;
begin
  if (AInput.Server.Phase <> TAtlasServerPhase.Running) or not AInput.Status.Known then
  begin
    Exit(Make(cC, TAtlasSetupFinding.LibraryUnknown, TAtlasStatusState.Yellow, TAtlasSetupFix.StartServer, True, nil));
  end;
  mBytes := 0;
  mBuilding := AInput.Indexing;
  for mWorkspace in AInput.Status.Workspaces do
  begin
    if mWorkspace.LibraryCacheBytes > mBytes then
    begin
      mBytes := mWorkspace.LibraryCacheBytes;
    end;
    if not mWorkspace.Done then
    begin
      mBuilding := True;
    end;
  end;
  if mBytes > 0 then
  begin
    Result := Make(cC, TAtlasSetupFinding.LibraryReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(mBytes)]);
  end
  else if mBuilding or (Length(AInput.Status.Workspaces) = 0) then
  begin
    // Der Cache entsteht am Ende des ersten Indexlaufs.
    Result := Make(cC, TAtlasSetupFinding.LibraryPending, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, True, nil);
  end
  else
  begin
    Result := Make(cC, TAtlasSetupFinding.LibraryMissing, TAtlasStatusState.Yellow, TAtlasSetupFix.BuildLibraryCache,
      False, nil);
  end;
end;

class function TAtlasSetupChecklist.CheckErrorInsight(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  cC = TAtlasSetupCheck.ErrorInsight;
begin
  if AInput.ErrorInsightRestart then
  begin
    Result := Make(cC, TAtlasSetupFinding.ErrorInsightRestart, TAtlasStatusState.Yellow, TAtlasSetupFix.Explain, False,
      nil);
  end
  else if AInput.ErrorInsight and AInput.AtlasProblems then
  begin
    Result := Make(cC, TAtlasSetupFinding.ErrorInsightDuplicate, TAtlasStatusState.Yellow,
      TAtlasSetupFix.DisableErrorInsight, False, nil);
  end
  else if AInput.ErrorInsight then
  begin
    Result := Make(cC, TAtlasSetupFinding.ErrorInsightIde, TAtlasStatusState.Green, TAtlasSetupFix.None, False, nil);
  end
  else if AInput.AtlasProblems then
  begin
    Result := Make(cC, TAtlasSetupFinding.ErrorInsightAtlas, TAtlasStatusState.Green, TAtlasSetupFix.None, False, nil);
  end
  else
  begin
    // Weder die IDE noch Atlas zeigen Fehler im Editor.
    Result := Make(cC, TAtlasSetupFinding.ErrorInsightNone, TAtlasStatusState.Yellow,
      TAtlasSetupFix.EnableErrorInsight, False, nil);
  end;
end;

class function TAtlasSetupChecklist.CheckKeys(const AInput: TAtlasSetupInput): TAtlasSetupResult;
const
  cC = TAtlasSetupCheck.Keys;
var
  mKey: TAtlasSetupKey;
  mConflicts, mWins: Integer;
  mFirst: TAtlasSetupKey;
begin
  mConflicts := 0;
  mWins := 0;
  mFirst := Default(TAtlasSetupKey);
  for mKey in AInput.Keys do
    case mKey.Entry.Status(mKey.Owner) of
      // Atlas überlässt die Taste der anderen Belegung: Die Atlas-Funktion hat keine Taste.
      TAtlasKeyStatus.Left:
        begin
          if mConflicts = 0 then
          begin
            mFirst := mKey;
          end;
          Inc(mConflicts);
        end;
      // Bewusst entschieden („Atlas verwenden“): kein offener Konflikt.
      TAtlasKeyStatus.AtlasWins:
        Inc(mWins);
    end;
  if mConflicts > 0 then
  begin
    Result := Make(cC, TAtlasSetupFinding.KeysConflict, TAtlasStatusState.Yellow, TAtlasSetupFix.OpenKeyConflicts,
      False, [IntToStr(mConflicts), mFirst.KeyText, mFirst.Owner]);
  end
  else
  begin
    Result := Make(cC, TAtlasSetupFinding.KeysReady, TAtlasStatusState.Green, TAtlasSetupFix.None, False,
      [IntToStr(mWins)]);
  end;
end;

class function TAtlasSetupChecklist.Evaluate(const AInput: TAtlasSetupInput): TArray<TAtlasSetupResult>;
begin
  Result := [CheckServer(AInput), CheckDelphi(AInput), CheckIndex(AInput), CheckLibraryCache(AInput),
    CheckErrorInsight(AInput), CheckKeys(AInput)];
end;

class procedure TAtlasSetupChecklist.Progress(const AResults: TArray<TAtlasSetupResult>; out ADone,
  ATotal: Integer);
var
  mItem: TAtlasSetupResult;
begin
  ADone := 0;
  ATotal := Length(AResults);
  for mItem in AResults do
  begin
    if mItem.State = TAtlasStatusState.Green then
    begin
      Inc(ADone);
    end;
  end;
end;

class function TAtlasSetupChecklist.Complete(const AResults: TArray<TAtlasSetupResult>): Boolean;
var
  mDone, mTotal: Integer;
begin
  Progress(AResults, mDone, mTotal);
  Result := (mTotal > 0) and (mDone = mTotal);
end;

class function TAtlasSetupChecklist.StartAction(AEnabled, AFirstStart: Boolean;
  const AResults: TArray<TAtlasSetupResult>; AElapsedMs, AWaitMs: Int64): TAtlasSetupStartAction;
var
  mItem: TAtlasSetupResult;
  mWaiting: Boolean;
begin
  if not AEnabled then
  begin
    Exit(TAtlasSetupStartAction.Skip);
  end;
  if AFirstStart then
  begin
    Exit(TAtlasSetupStartAction.Open);
  end;
  mWaiting := False;
  for mItem in AResults do
  begin
    if mItem.State <> TAtlasStatusState.Green then
    begin
      if not mItem.Pending then
      begin
        Exit(TAtlasSetupStartAction.Open);
      end;
      mWaiting := True;
    end;
  end;
  if (Length(AResults) = 0) or (mWaiting and (AElapsedMs < AWaitMs)) then
  begin
    Result := TAtlasSetupStartAction.Wait;
  end
  else
  begin
    Result := TAtlasSetupStartAction.Skip;
  end;
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

/// <summary>Namen ab zwei Zeichen, längere zuerst: Sonst bliebe vom Rechnernamen „WS-MARCO“ nach dem Benutzer
/// „marco“ ein Rest stehen.</summary>
function LongestFirst(const AIdentity: TArray<string>): TArray<string>;
var
  mIdentity, mSwap: string;
  mIndex, mOther: Integer;
begin
  Result := nil;
  for mIdentity in AIdentity do
  begin
    if Length(Trim(mIdentity)) >= 2 then
    begin
      Result := Result + [Trim(mIdentity)];
    end;
  end;
  for mIndex := 0 to High(Result) - 1 do
  begin
    for mOther := mIndex + 1 to High(Result) do
    begin
      if Length(Result[mOther]) > Length(Result[mIndex]) then
      begin
        mSwap := Result[mIndex];
        Result[mIndex] := Result[mOther];
        Result[mOther] := mSwap;
      end;
    end;
  end;
end;
class function TAtlasSetupChecklist.Report(const AInput: TAtlasSetupReportInput): string;
var
  mBuilder: TStringBuilder;
  mLine: TAtlasSetupReportLine;
  mIdentity, mVersions: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(AInput.Title).Append(sLineBreak);
    mVersions := 'Atlas ' + AInput.AtlasVersion;
    if AInput.IdeVersion <> '' then
    begin
      mVersions := mVersions + ', IDE ' + AInput.IdeVersion;
    end;
    if AInput.Platform <> '' then
    begin
      mVersions := mVersions + ', ' + AInput.Platform;
    end;
    mBuilder.Append(mVersions).Append(sLineBreak);
    mBuilder.Append(FormatDateTime('yyyy-mm-dd hh":"nn', AInput.Created)).Append(sLineBreak);
    mBuilder.Append(AInput.Summary).Append(sLineBreak).Append(sLineBreak);
    for mLine in AInput.Lines do
    begin
      if mLine.Indent then
      begin
        mBuilder.Append('       - ').Append(mLine.Text).Append(sLineBreak);
      end
      else
      begin
        mBuilder.Append(StateMark(mLine.State)).Append(' ').Append(mLine.Text).Append(sLineBreak);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  // Keine Namen von Benutzer, Rechner oder Domäne (#108); Pfade enthalten die Zeilen nicht.
  for mIdentity in LongestFirst(AInput.Identity) do
  begin
    Result := StringReplace(Result, mIdentity, IdentityMark, [rfReplaceAll, rfIgnoreCase]);
  end;
end;

{ TAtlasSetupController }

constructor TAtlasSetupController.Create(const AEnvironment: IAtlasSetupEnvironment);
begin
  inherited Create;
  FEnvironment := AEnvironment;
end;

function TAtlasSetupController.Refresh: TArray<TAtlasSetupResult>;
var
  mItem: TAtlasSetupResult;
  mKey: string;
begin
  FResults := TAtlasSetupChecklist.Evaluate(FEnvironment.Snapshot);
  mKey := '';
  for mItem in FResults do
  begin
    mKey := mKey + mItem.Key + #10;
  end;
  if mKey <> FKey then
  begin
    FKey := mKey;
    Inc(FVersion);
  end;
  Result := FResults;
end;

function TAtlasSetupController.Apply(AFix: TAtlasSetupFix): Boolean;
var
  mPath: string;
begin
  case AFix of
    TAtlasSetupFix.ChooseServerPath:
      begin
        Result := FEnvironment.ChooseServerPath(mPath) and (Trim(mPath) <> '');
        if Result then
        begin
          FEnvironment.SaveServerPath(Trim(mPath));
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
