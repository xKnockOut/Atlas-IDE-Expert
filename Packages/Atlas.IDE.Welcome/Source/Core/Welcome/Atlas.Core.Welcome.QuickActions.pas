unit Atlas.Core.Welcome.QuickActions;

// Schnellaktionen je Projekt auf der Willkommensseite (#764, Mockup #ws10),
// Teil ohne VCL und Open Tools API:
// - Knöpfe in fester Reihenfolge „Öffnen und bauen“, „Tests“, „Startprofil ▾“,
//   „Pull“, „Ordner“, „Konsole“, „Aufgaben ▾“; welche erscheinen, legt
//   welcomePage.quickActions.items fest (Liste aus build, tests, run, pull,
//   folder, console, tasks; Vorgabe alle, leer = keiner). „Aufgaben ▾“
//   startet eine Projektaufgabe aus atlas.json (#900); die IDE-Schicht zeigt
//   ihn nur bei eingeschalteten Aufgaben und mit Aufgaben im Projekt.
// - Sperrlogik von „Pull“: gesperrt bei lokalen Änderungen im Projektordner
//   (wie die Marke „N geändert“ des Bereichs „Projekte“, #592) mit dem Tooltip
//   „Erst lokale Änderungen sichern“, ohne Arbeitskopie und solange auf dem
//   Projekt schon eine Aktion läuft. Unbekannter Stand sperrt nicht: Pull
//   prüft vor dem Holen die ganze Arbeitskopie noch einmal (TAtlasVcsPull in
//   Atlas.Core.VersionControl.Pull, Base). Bei SVN
//   heißt der Knopf „Aktualisieren“. vcs.externals.update (#1292) wählt bei
//   SVN mit Externals bzw. ohne (--ignore-externals); „fragen“ gibt dem Knopf
//   die Auswahl „mit Externals“/„ohne Externals“ (AskExternals).
// - Zuordnung Projekt → Testprojekt ohne IDE: ein DUnitX-Programm ist sein
//   eigenes Testprojekt; sonst die Testprojekte nach Namensmuster neben dem
//   Projekt, in Tests\ bzw. Test\ darunter oder daneben (<Name>.Tests.dproj,
//   <Name>Tests.dproj, <Name>.Test.dproj, <Name>Test.dproj); bei einer
//   Projektgruppe ihre DUnitX-Projekte (bei mehreren das mit passendem Namen,
//   sonst fragt die IDE wie bei „Tests ausführen“, #69/#585).
// - Konfigurationen und Plattformen einer .dproj und die Projekte einer
//   .groupproj aus dem Text der Datei (für die Auswahl „Öffnen und bauen“;
//   Vorgabe: zuletzt benutzte aus der Projekt-Zusammenfassung).
// - Kommandozeile für „Konsole“: Windows-Terminal (wt.exe, Vorgabe), cmd,
//   PowerShell oder ein anderes Programm mit dem Projektordner als
//   Arbeitsordner; ohne Windows-Terminal nimmt die IDE-Schicht cmd.exe.
// - Tastatur: Pfeiltasten wählen Zeile und Knopf, Strg+B baut, Strg+T testet
//   (Tasten einstellbar, #399).
// - Stand je Projekt: läuft seit …, Ergebnis.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Pull;

type
{$SCOPEDENUMS ON}
  TAtlasQuickAction = (Build, Tests, Run, Pull, Folder, Console, Tasks);
  /// <summary>Stand einer Aktion je Projekt: läuft, fertig (ok bzw. fehlgeschlagen) oder nicht ausgeführt.</summary>
  TAtlasQuickActionPhase = (Idle, Running, Succeeded, Failed, Refused);
  /// <summary>Grund, aus dem „Pull“ gesperrt ist.</summary>
  TAtlasPullBlock = (None, LocalChanges, NoWorkingCopy, Busy);
  /// <summary>Text, den die IDE nach einem Pull in Detail und als Meldung setzt: keiner, lokale Änderungen
  /// (mit Meldung), keine Arbeitskopie, Anmeldung fehlt (mit Meldung), sonst fehlgeschlagen (mit Meldung).</summary>
  TAtlasPullNote = (None, LocalChanges, NoWorkingCopy, Login, Failed);
{$SCOPEDENUMS OFF}
  TAtlasQuickActions = set of TAtlasQuickAction;

  TAtlasQuickActionButton = record
    Action: TAtlasQuickAction;
    Enabled: Boolean;
    /// <summary>Nur Pull: warum gesperrt; None sonst.</summary>
    Block: TAtlasPullBlock;
    /// <summary>Pull heißt „Aktualisieren“ (SVN).</summary>
    Update: Boolean;
    /// <summary>Der Knopf hat eine Auswahl (▾): Konfiguration und Plattform, Startprofil bzw. Aufgabe.</summary>
    HasMenu: Boolean;
    /// <summary>Nur Pull unter SVN mit vcs.externals.update = ask (#1292): Auswahl „mit Externals“ bzw. „ohne
    /// Externals“ statt sofort zu aktualisieren.</summary>
    AskExternals: Boolean;
  end;

  TAtlasQuickActionButtons = TArray<TAtlasQuickActionButton>;

  /// <summary>Stand der letzten Schnellaktion eines Projekts in dieser Sitzung.</summary>
  TAtlasQuickActionState = record
    Action: TAtlasQuickAction;
    Phase: TAtlasQuickActionPhase;
    /// <summary>Beginn (Tick in ms).</summary>
    StartedMs: UInt64;
    /// <summary>Grund bzw. Ergebnis als fertiger Text der IDE-Schicht (etwa der Grund von „nicht gebaut“).</summary>
    Detail: string;
    /// <summary>Tests: bestanden und fehlgeschlagen (mit Fehlern); Pull: neue Commits geholt.</summary>
    Passed: Integer;
    Failed: Integer;
    Pull: TAtlasPullOutcome;
    class function Idle: TAtlasQuickActionState; static;
    class function Started(AAction: TAtlasQuickAction; ANowMs: UInt64): TAtlasQuickActionState; static;
    function Running: Boolean;
    /// <summary>Ganze Sekunden seit dem Beginn; 0 vor dem Beginn.</summary>
    function ElapsedSeconds(ANowMs: UInt64): Integer;
    /// <summary>Stand nach einem Pull mit Ergebnis AOutcome; AReason ist der Grund eines Fehlschlags. ANote sagt,
    /// welchen Text die IDE noch setzt; bei Failed steht der Name von AReason schon in Detail.</summary>
    function AfterPull(AOutcome: TAtlasPullOutcome; AReason: TAtlasVcsOutcome;
      out ANote: TAtlasPullNote): TAtlasQuickActionState;
    /// <summary>Ein Testlauf endete ohne Ergebnis: läuft nicht mehr oder die Schonzeit AGraceMs ist um.</summary>
    function TestEnded(ANowMs, AGraceMs: UInt64): Boolean;
  end;

  /// <summary>Konfigurationen (ohne „Base“) und eingeschaltete Plattformen einer .dproj in Dateireihenfolge.</summary>
  TAtlasProjectTargets = record
    Configurations: TArray<string>;
    Platforms: TArray<string>;
    function HasConfiguration(const AName: string): Boolean;
    function HasPlatform(const AName: string): Boolean;
  end;

  TAtlasQuickFileExists = reference to function(const AFileName: string): Boolean;
  /// <summary>Zeilen einer Datei ohne Zeilenende; False, wenn sie nicht lesbar ist.</summary>
  TAtlasQuickReadLines = reference to function(const AFileName: string; out ALines: TArray<string>): Boolean;

  TAtlasWelcomeQuickActions = class
  public const
    cNames: array[TAtlasQuickAction] of string = ('build', 'tests', 'run', 'pull', 'folder', 'console', 'tasks');
    cDefaultItems = 'build,tests,run,pull,folder,console,tasks';
    cDefaultConsole = 'wt.exe';
    cFallbackConsole = 'cmd.exe';
    /// <summary>Strg+B und Strg+T als TShortCut (scCtrl or Ord(Taste)).</summary>
    cDefaultBuildKey = $4042;
    cDefaultTestKey = $4054;
    /// <summary>Zeitlimit für Pull bzw. svn update (spricht mit dem Server).</summary>
    cPullTimeoutMs = 120000;
    /// <summary>Auftraggeber der Builds in den Compile-Ereignissen (#527): keine Tests nach dem Build (#69).</summary>
    cRequestedBy = 'welcome';
  public
    /// <summary>Bekannte Namen aus AText (Komma, Semikolon, Leerzeichen; Groß-/Kleinschreibung egal).</summary>
    class function ParseItems(const AText: string): TAtlasQuickActions; static;
    /// <summary>Namen in fester Reihenfolge, durch Komma getrennt; '' ohne.</summary>
    class function ItemsText(AItems: TAtlasQuickActions): string; static;
    /// <summary>Für die Einstellungen: bekannte Namen in fester Reihenfolge, jeder einmal.</summary>
    class function NormalizedItems(const AText: string): string; static;
    /// <summary>Programm für „Konsole“: getrimmt; leer = DefaultConsole.</summary>
    class function NormalizedConsole(const AText: string): string; static;
    /// <summary>Gesperrt? None = Pull ist möglich (auch bei unbekanntem Stand; Pull prüft dann selbst).</summary>
    class function PullBlock(const AVcs: TAtlasProjectVcs): TAtlasPullBlock; static;
    /// <summary>SVN: Der Knopf heißt „Aktualisieren“.</summary>
    class function IsUpdate(const AVcs: TAtlasProjectVcs): Boolean; static;
    /// <summary>Knöpfe aus AItems in fester Reihenfolge. ABusy: auf dem Projekt läuft eine Aktion; dann gehen nur
    /// „Ordner“ und „Konsole“. AIdeBusy: in der IDE läuft schon eine Aktion eines anderen Projekts (Bauen, Tests,
    /// Start); dann gehen „Öffnen und bauen“, „Tests“ und „Startprofil“ nicht, Pull schon.</summary>
    class function Buttons(AItems: TAtlasQuickActions; const AVcs: TAtlasProjectVcs; ABusy: Boolean;
      AIdeBusy: Boolean): TAtlasQuickActionButtons; overload; static;
    /// <summary>Wie oben mit AIdeBusy = False.</summary>
    class function Buttons(AItems: TAtlasQuickActions; const AVcs: TAtlasProjectVcs;
      ABusy: Boolean): TAtlasQuickActionButtons; overload; static;
    /// <summary>Braucht die Aktion die IDE (Projekt öffnen)? Bauen, Tests, Startprofil.</summary>
    class function UsesIde(AAction: TAtlasQuickAction): Boolean; static;
    /// <summary>Index des Knopfs für AAction; -1 ohne.</summary>
    class function IndexOf(const AButtons: TAtlasQuickActionButtons; AAction: TAtlasQuickAction): Integer; static;
    /// <summary>Strg+B bzw. Strg+T (eingestellt, 0 = keine Taste) auf „Öffnen und bauen“ bzw. „Tests“, nur wenn
    /// der Knopf eingestellt ist.</summary>
    class function ActionForKey(AShortCut, ABuildKey, ATestKey: Integer; AItems: TAtlasQuickActions;
      out AAction: TAtlasQuickAction): Boolean; static;
    /// <summary>Zeile nach Pfeil auf/ab: begrenzt auf 0..ACount-1; -1 ohne Zeilen.</summary>
    class function MoveRow(ARow, ADelta, ACount: Integer): Integer; static;
    /// <summary>Knopf nach Pfeil links/rechts: nächster nutzbarer in ADelta-Richtung; ohne einen bleibt
    /// ACurrent.</summary>
    class function MoveButton(const AButtons: TAtlasQuickActionButtons; ACurrent, ADelta: Integer): Integer; static;
    /// <summary>Programm und Parameter für „Konsole“ in AFolder; Arbeitsordner ist immer AFolder. False ohne
    /// Ordner.</summary>
    class function ConsoleCommand(const AProgram, AFolder: string; out AFileName, AParameters: string): Boolean;
      static;
    /// <summary>Konfigurationen und Plattformen aus dem Text einer .dproj.</summary>
    class function ReadTargets(const AText: string): TAtlasProjectTargets; static;
    /// <summary>Vorgabe der Auswahl: die zuletzt benutzte Konfiguration bzw. Plattform, wenn das Projekt sie
    /// kennt; sonst '' (aktive der IDE).</summary>
    class procedure ChooseTarget(const ATargets: TAtlasProjectTargets; const ALastConfiguration,
      ALastPlatform: string; out AConfiguration, APlatform: string); static;
    /// <summary>Projekte einer .groupproj (Text) als vollständige Pfade relativ zu AFolder.</summary>
    class function GroupProjects(const AText, AFolder: string): TArray<string>; static;
    class function IsGroup(const AFileName: string): Boolean; static;
    /// <summary>Mögliche Testprojekte zu AProject (.dproj) nach Namensmuster, in Suchreihenfolge.</summary>
    class function TestCandidates(const AProject: string): TArray<string>; static;
    /// <summary>Testprojekt zu AProject: das Projekt selbst, wenn es ein DUnitX-Programm ist, sonst das erste
    /// gefundene nach TestCandidates; bei einer Projektgruppe ihr einziges DUnitX-Projekt bzw. das mit passendem
    /// Namen. '' ohne bzw. bei mehreren gleichwertigen (ACandidates nennt sie dann; die IDE fragt).</summary>
    class function TestProjectFor(const AProject: string; const AExists: TAtlasQuickFileExists;
      const AReadLines: TAtlasQuickReadLines; out ACandidates: TArray<string>): string; static;
    /// <summary>Pull-Knöpfe unter SVN mit vcs.externals.update = ask bekommen die Auswahl (#1292).</summary>
    class procedure AskExternals(var AButtons: TAtlasQuickActionButtons); static;
    /// <summary>„a\..\b“ und doppelte Trenner auflösen (Windows-Pfade, auch unter Linux in den Tests).</summary>
    class function CombinePath(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  Atlas.Text.DUnitX;

const
  cDelimiter = '\';

function FolderOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := Length(AFileName) downto 1 do
  begin
    if (AFileName[mIndex] = '\') or (AFileName[mIndex] = '/') then
    begin
      Exit(Copy(AFileName, 1, mIndex - 1));
    end;
  end;
end;

function NameOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := AFileName;
  for mIndex := Length(AFileName) downto 1 do
  begin
    if (AFileName[mIndex] = '\') or (AFileName[mIndex] = '/') then
    begin
      Exit(Copy(AFileName, mIndex + 1, MaxInt));
    end;
  end;
end;

function BaseNameOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := NameOf(AFileName);
  for mIndex := Length(Result) downto 1 do
  begin
    if Result[mIndex] = '.' then
    begin
      Exit(Copy(Result, 1, mIndex - 1));
    end;
  end;
end;

function ExtensionOf(const AFileName: string): string;
var
  mName: string;
  mIndex: Integer;
begin
  Result := '';
  mName := NameOf(AFileName);
  for mIndex := Length(mName) downto 1 do
  begin
    if mName[mIndex] = '.' then
    begin
      Exit(LowerCase(Copy(mName, mIndex, MaxInt)));
    end;
  end;
end;

function WithExtension(const AFileName, AExtension: string): string;
var
  mName: string;
  mIndex: Integer;
begin
  mName := NameOf(AFileName);
  Result := AFileName;
  for mIndex := Length(mName) downto 1 do
  begin
    if mName[mIndex] = '.' then
    begin
      Exit(Copy(AFileName, 1, Length(AFileName) - Length(mName) + mIndex - 1) + AExtension);
    end;
  end;
  Result := AFileName + AExtension;
end;

function ContainsText(const AItems: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AItems do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Wert des Attributs bzw. Inhalts zwischen AStart (ab APos) und ADelimiter; '' ohne.</summary>
function NextValue(const AText, AStart, ADelimiter: string; var APos: Integer; out AValue: string): Boolean;
var
  mStart, mStop: Integer;
begin
  AValue := '';
  mStart := Pos(AStart, AText, APos);
  if mStart = 0 then
  begin
    Exit(False);
  end;
  Inc(mStart, Length(AStart));
  mStop := Pos(ADelimiter, AText, mStart);
  if mStop = 0 then
  begin
    Exit(False);
  end;
  AValue := Copy(AText, mStart, mStop - mStart);
  APos := mStop + Length(ADelimiter);
  Result := True;
end;

function XmlDecoded(const AText: string): string;
begin
  Result := StringReplace(AText, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', '''', [rfReplaceAll]);
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

{ TAtlasQuickActionState }

class function TAtlasQuickActionState.Idle: TAtlasQuickActionState;
begin
  Result := Default(TAtlasQuickActionState);
  Result.Phase := TAtlasQuickActionPhase.Idle;
end;

class function TAtlasQuickActionState.Started(AAction: TAtlasQuickAction; ANowMs: UInt64): TAtlasQuickActionState;
begin
  Result := Idle;
  Result.Action := AAction;
  Result.Phase := TAtlasQuickActionPhase.Running;
  Result.StartedMs := ANowMs;
end;

function TAtlasQuickActionState.Running: Boolean;
begin
  Result := Phase = TAtlasQuickActionPhase.Running;
end;

function TAtlasQuickActionState.ElapsedSeconds(ANowMs: UInt64): Integer;
begin
  Result := 0;
  if (StartedMs = 0) or (ANowMs <= StartedMs) then
  begin
    Exit;
  end;
  Result := Integer((ANowMs - StartedMs) div 1000);
end;

function TAtlasQuickActionState.AfterPull(AOutcome: TAtlasPullOutcome; AReason: TAtlasVcsOutcome;
  out ANote: TAtlasPullNote): TAtlasQuickActionState;
begin
  Result := Self;
  Result.Action := TAtlasQuickAction.Pull;
  Result.Pull := AOutcome;
  Result.Detail := '';
  Result.Phase := TAtlasQuickActionPhase.Failed;
  ANote := TAtlasPullNote.None;
  case AOutcome of
    TAtlasPullOutcome.Updated, TAtlasPullOutcome.UpToDate:
      Result.Phase := TAtlasQuickActionPhase.Succeeded;
    TAtlasPullOutcome.Blocked:
      ANote := TAtlasPullNote.LocalChanges;
    TAtlasPullOutcome.NoWorkingCopy:
      ANote := TAtlasPullNote.NoWorkingCopy;
  else
    // Fehlende Anmeldung (#1287): Ursache und Weg zur Seite Versionsverwaltung statt eines Codes.
    if AReason = TAtlasVcsOutcome.LoginNeeded then
    begin
      ANote := TAtlasPullNote.Login;
    end
    else
    begin
      ANote := TAtlasPullNote.Failed;
      Result.Detail := AtlasVcsOutcomeName(AReason);
    end;
  end;
end;

function TAtlasQuickActionState.TestEnded(ANowMs, AGraceMs: UInt64): Boolean;
begin
  Result := not Running or (ANowMs >= StartedMs + AGraceMs);
end;

{ TAtlasProjectTargets }

function TAtlasProjectTargets.HasConfiguration(const AName: string): Boolean;
begin
  Result := (AName <> '') and ContainsText(Configurations, AName);
end;

function TAtlasProjectTargets.HasPlatform(const AName: string): Boolean;
begin
  Result := (AName <> '') and ContainsText(Platforms, AName);
end;

{ TAtlasWelcomeQuickActions }

class function TAtlasWelcomeQuickActions.ParseItems(const AText: string): TAtlasQuickActions;
var
  mPart: string;
  mAction: TAtlasQuickAction;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    begin
      if SameText(Trim(mPart), cNames[mAction]) then
      begin
        Include(Result, mAction);
      end;
    end;
  end;
end;

class function TAtlasWelcomeQuickActions.ItemsText(AItems: TAtlasQuickActions): string;
var
  mAction: TAtlasQuickAction;
begin
  Result := '';
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    if mAction in AItems then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cNames[mAction];
    end;
  end;
end;

class function TAtlasWelcomeQuickActions.NormalizedItems(const AText: string): string;
begin
  Result := ItemsText(ParseItems(AText));
end;

class function TAtlasWelcomeQuickActions.NormalizedConsole(const AText: string): string;
begin
  Result := Trim(AText);
  if Result = '' then
  begin
    Result := cDefaultConsole;
  end;
end;

class function TAtlasWelcomeQuickActions.PullBlock(const AVcs: TAtlasProjectVcs): TAtlasPullBlock;
begin
  Result := TAtlasPullBlock.None;
  if not AVcs.Known then
  begin
    Exit;
  end;
  if SameText(AVcs.Kind, 'none') then
  begin
    Exit(TAtlasPullBlock.NoWorkingCopy);
  end;
  if AVcs.InWorkingCopy and (AVcs.Changed > 0) then
  begin
    Result := TAtlasPullBlock.LocalChanges;
  end;
end;

class function TAtlasWelcomeQuickActions.IsUpdate(const AVcs: TAtlasProjectVcs): Boolean;
begin
  Result := AVcs.Known and SameText(AVcs.Kind, 'svn');
end;

class function TAtlasWelcomeQuickActions.UsesIde(AAction: TAtlasQuickAction): Boolean;
begin
  Result := (AAction = TAtlasQuickAction.Build) or (AAction = TAtlasQuickAction.Tests) or
    (AAction = TAtlasQuickAction.Run);
end;

class function TAtlasWelcomeQuickActions.Buttons(AItems: TAtlasQuickActions; const AVcs: TAtlasProjectVcs;
  ABusy: Boolean): TAtlasQuickActionButtons;
begin
  Result := Buttons(AItems, AVcs, ABusy, False);
end;

class function TAtlasWelcomeQuickActions.Buttons(AItems: TAtlasQuickActions; const AVcs: TAtlasProjectVcs;
  ABusy: Boolean; AIdeBusy: Boolean): TAtlasQuickActionButtons;
var
  mAction: TAtlasQuickAction;
  mButton: TAtlasQuickActionButton;
begin
  Result := nil;
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    if not (mAction in AItems) then
    begin
      Continue;
    end;
    mButton := Default(TAtlasQuickActionButton);
    mButton.Action := mAction;
    mButton.Block := TAtlasPullBlock.None;
    // Ordner und Konsole stören keine laufende Aktion.
    mButton.Enabled := not ABusy or (mAction = TAtlasQuickAction.Folder) or (mAction = TAtlasQuickAction.Console);
    // Die IDE öffnet immer nur ein Projekt zur Zeit.
    if AIdeBusy and UsesIde(mAction) then
    begin
      mButton.Enabled := False;
    end;
    mButton.HasMenu := (mAction = TAtlasQuickAction.Build) or (mAction = TAtlasQuickAction.Run) or
      (mAction = TAtlasQuickAction.Tasks);
    if mAction = TAtlasQuickAction.Pull then
    begin
      mButton.Update := IsUpdate(AVcs);
      mButton.Block := PullBlock(AVcs);
      if (mButton.Block = TAtlasPullBlock.None) and ABusy then
      begin
        mButton.Block := TAtlasPullBlock.Busy;
      end;
      mButton.Enabled := mButton.Block = TAtlasPullBlock.None;
    end;
    Result := Result + [mButton];
  end;
end;

class function TAtlasWelcomeQuickActions.IndexOf(const AButtons: TAtlasQuickActionButtons;
  AAction: TAtlasQuickAction): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AButtons) do
  begin
    if AButtons[mIndex].Action = AAction then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasWelcomeQuickActions.ActionForKey(AShortCut, ABuildKey, ATestKey: Integer;
  AItems: TAtlasQuickActions; out AAction: TAtlasQuickAction): Boolean;
begin
  AAction := TAtlasQuickAction.Build;
  Result := False;
  if AShortCut = 0 then
  begin
    Exit;
  end;
  if (AShortCut = ABuildKey) and (TAtlasQuickAction.Build in AItems) then
  begin
    AAction := TAtlasQuickAction.Build;
    Exit(True);
  end;
  if (AShortCut = ATestKey) and (TAtlasQuickAction.Tests in AItems) then
  begin
    AAction := TAtlasQuickAction.Tests;
    Exit(True);
  end;
end;

class function TAtlasWelcomeQuickActions.MoveRow(ARow, ADelta, ACount: Integer): Integer;
begin
  if ACount <= 0 then
  begin
    Exit(-1);
  end;
  Result := ARow + ADelta;
  if ARow < 0 then
  begin
    Result := 0;
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
  if Result > ACount - 1 then
  begin
    Result := ACount - 1;
  end;
end;

class function TAtlasWelcomeQuickActions.MoveButton(const AButtons: TAtlasQuickActionButtons; ACurrent,
  ADelta: Integer): Integer;
var
  mIndex, mStep: Integer;
begin
  Result := ACurrent;
  if (ADelta = 0) or (Length(AButtons) = 0) then
  begin
    Exit;
  end;
  mStep := 1;
  if ADelta < 0 then
  begin
    mStep := -1;
  end;
  mIndex := ACurrent + mStep;
  // Ohne gewählten Knopf beginnt „links“ beim letzten.
  if (ACurrent < 0) and (mStep < 0) then
  begin
    mIndex := High(AButtons);
  end;
  while (mIndex >= 0) and (mIndex <= High(AButtons)) do
  begin
    if AButtons[mIndex].Enabled then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex, mStep);
  end;
end;

class function TAtlasWelcomeQuickActions.ConsoleCommand(const AProgram, AFolder: string; out AFileName,
  AParameters: string): Boolean;
var
  mFolder, mQuoted, mBase: string;
begin
  AFileName := NormalizedConsole(AProgram);
  AParameters := '';
  mFolder := Trim(AFolder);
  Result := mFolder <> '';
  if not Result then
  begin
    Exit;
  end;
  // Ein Backslash vor dem schließenden Anführungszeichen würde es maskieren („C:\“ → „C:\.“).
  mQuoted := mFolder;
  if (mQuoted[Length(mQuoted)] = '\') or (mQuoted[Length(mQuoted)] = '/') then
  begin
    mQuoted := mQuoted + '.';
  end;
  mBase := LowerCase(BaseNameOf(AFileName));
  if mBase = 'wt' then
  begin
    AParameters := '-d "' + mQuoted + '"';
  end
  else if mBase = 'cmd' then
  begin
    AParameters := '/K cd /d "' + mQuoted + '"';
  end
  else if (mBase = 'powershell') or (mBase = 'pwsh') then
  begin
    AParameters := '-NoExit -Command Set-Location -LiteralPath ''' + StringReplace(mQuoted, '''', '''''',
      [rfReplaceAll]) + '''';
  end;
end;

class function TAtlasWelcomeQuickActions.ReadTargets(const AText: string): TAtlasProjectTargets;
var
  mPosition: Integer;
  mValue, mContent: string;
  mStop: Integer;
begin
  Result := Default(TAtlasProjectTargets);
  mPosition := 1;
  while NextValue(AText, '<BuildConfiguration Include="', '"', mPosition, mValue) do
  begin
    mValue := Trim(XmlDecoded(mValue));
    if (mValue <> '') and not SameText(mValue, 'Base') and not ContainsText(Result.Configurations, mValue) then
    begin
      Result.Configurations := Result.Configurations + [mValue];
    end;
  end;
  mPosition := 1;
  while NextValue(AText, '<Platform value="', '"', mPosition, mValue) do
  begin
    // <Platform value="Win64">True</Platform>; False = im Projekt abgeschaltet.
    mContent := '';
    if Copy(AText, mPosition, 1) = '>' then
    begin
      Inc(mPosition);
      mStop := Pos('<', AText, mPosition);
      if mStop > 0 then
      begin
        mContent := Copy(AText, mPosition, mStop - mPosition);
        mPosition := mStop;
      end;
    end;
    mValue := Trim(XmlDecoded(mValue));
    if (mValue <> '') and SameText(Trim(mContent), 'True') and not ContainsText(Result.Platforms, mValue) then
    begin
      Result.Platforms := Result.Platforms + [mValue];
    end;
  end;
end;

class procedure TAtlasWelcomeQuickActions.ChooseTarget(const ATargets: TAtlasProjectTargets;
  const ALastConfiguration, ALastPlatform: string; out AConfiguration, APlatform: string);
var
  mName: string;
begin
  AConfiguration := '';
  APlatform := '';
  // Schreibweise der Datei, damit die IDE die Konfiguration sicher findet.
  for mName in ATargets.Configurations do
  begin
    if SameText(mName, ALastConfiguration) then
    begin
      AConfiguration := mName;
    end;
  end;
  for mName in ATargets.Platforms do
  begin
    if SameText(mName, ALastPlatform) then
    begin
      APlatform := mName;
    end;
  end;
end;

class function TAtlasWelcomeQuickActions.CombinePath(const AFolder, ARelative: string): string;
var
  mParts, mKept: TArray<string>;
  mPart, mJoined: string;
begin
  mJoined := StringReplace(ARelative, '/', cDelimiter, [rfReplaceAll]);
  // Absoluter Pfad (Laufwerk oder UNC) bleibt, sonst relativ zu AFolder.
  if not ((Length(mJoined) > 1) and ((mJoined[2] = ':') or (Copy(mJoined, 1, 2) = '\\'))) then
  begin
    mJoined := StringReplace(AFolder, '/', cDelimiter, [rfReplaceAll]) + cDelimiter + mJoined;
  end;
  mKept := nil;
  mParts := mJoined.Split([cDelimiter]);
  for mPart in mParts do
  begin
    if (mPart = '.') or ((mPart = '') and (Length(mKept) > 0)) then
    begin
      Continue;
    end;
    if (mPart = '..') and (Length(mKept) > 1) and (mKept[High(mKept)] <> '..') then
    begin
      SetLength(mKept, Length(mKept) - 1);
      Continue;
    end;
    mKept := mKept + [mPart];
  end;
  Result := string.Join(cDelimiter, mKept);
  // UNC: zwei führende Trenner.
  if Copy(mJoined, 1, 2) = '\\' then
  begin
    Result := cDelimiter + Result;
  end;
end;

class function TAtlasWelcomeQuickActions.GroupProjects(const AText, AFolder: string): TArray<string>;
var
  mPosition: Integer;
  mValue, mPath: string;
begin
  Result := nil;
  mPosition := 1;
  while NextValue(AText, '<Projects Include="', '"', mPosition, mValue) do
  begin
    mValue := Trim(XmlDecoded(mValue));
    if mValue = '' then
    begin
      Continue;
    end;
    mPath := CombinePath(AFolder, mValue);
    if not ContainsText(Result, mPath) then
    begin
      Result := Result + [mPath];
    end;
  end;
end;

class function TAtlasWelcomeQuickActions.IsGroup(const AFileName: string): Boolean;
begin
  Result := ExtensionOf(AFileName) = '.groupproj';
end;

class function TAtlasWelcomeQuickActions.TestCandidates(const AProject: string): TArray<string>;
const
  cPatterns: array[0..3] of string = ('%s.Tests.dproj', '%sTests.dproj', '%s.Test.dproj', '%sTest.dproj');
  cFolders: array[0..4] of string = ('', 'Tests', 'Test', '..\Tests', '..\Test');
var
  mName, mFolder, mSub, mPattern, mPath: string;
begin
  Result := nil;
  mName := BaseNameOf(AProject);
  mFolder := FolderOf(AProject);
  if mName = '' then
  begin
    Exit;
  end;
  for mSub in cFolders do
  begin
    for mPattern in cPatterns do
    begin
      if mSub = '' then
      begin
        mPath := CombinePath(mFolder, Format(mPattern, [mName]));
      end
      else
      begin
        mPath := CombinePath(mFolder, mSub + cDelimiter + Format(mPattern, [mName]));
      end;
      if not SameText(mPath, AProject) and not ContainsText(Result, mPath) then
      begin
        Result := Result + [mPath];
      end;
    end;
  end;
end;

function IsTestProject(const AFileName: string; const AExists: TAtlasQuickFileExists;
  const AReadLines: TAtlasQuickReadLines): Boolean;
var
  mLines: TArray<string>;
  mMain: string;
begin
  // Wie die IDE (#69): Hauptdatei .dpr neben der .dproj verwendet DUnitX.TestFramework.
  mMain := WithExtension(AFileName, '.dpr');
  Result := AExists(mMain) and AReadLines(mMain, mLines) and TDUnitXSource.UsesDUnitX(mLines);
end;

function NamedAfterGroup(const ACandidate, AGroup: string): Boolean;
begin
  Result := SameText(BaseNameOf(ACandidate), AGroup + '.Tests') or SameText(BaseNameOf(ACandidate), AGroup + 'Tests');
end;

function GroupTestProject(const AGroup: string; const AExists: TAtlasQuickFileExists;
  const AReadLines: TAtlasQuickReadLines; out ACandidates: TArray<string>): string;
var
  mLines: TArray<string>;
  mCandidate, mGroup: string;
begin
  Result := '';
  ACandidates := nil;
  if not AReadLines(AGroup, mLines) then
  begin
    Exit;
  end;
  for mCandidate in TAtlasWelcomeQuickActions.GroupProjects(string.Join(#10, mLines), FolderOf(AGroup)) do
  begin
    if IsTestProject(mCandidate, AExists, AReadLines) then
    begin
      ACandidates := ACandidates + [mCandidate];
    end;
  end;
  if Length(ACandidates) = 1 then
  begin
    Exit(ACandidates[0]);
  end;
  // Mehrere: das nach der Gruppe benannte, sonst fragt die IDE.
  mGroup := BaseNameOf(AGroup);
  for mCandidate in ACandidates do
  begin
    if NamedAfterGroup(mCandidate, mGroup) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function SingleTestProject(const AProject: string; const AExists: TAtlasQuickFileExists;
  const AReadLines: TAtlasQuickReadLines; out ACandidates: TArray<string>): string;
var
  mCandidate: string;
begin
  Result := '';
  ACandidates := nil;
  if IsTestProject(AProject, AExists, AReadLines) then
  begin
    ACandidates := [AProject];
    Exit(AProject);
  end;
  for mCandidate in TAtlasWelcomeQuickActions.TestCandidates(AProject) do
  begin
    if AExists(mCandidate) and IsTestProject(mCandidate, AExists, AReadLines) then
    begin
      ACandidates := ACandidates + [mCandidate];
    end;
  end;
  if Length(ACandidates) > 0 then
  begin
    Result := ACandidates[0];
  end;
end;

class function TAtlasWelcomeQuickActions.TestProjectFor(const AProject: string;
  const AExists: TAtlasQuickFileExists; const AReadLines: TAtlasQuickReadLines;
  out ACandidates: TArray<string>): string;
begin
  Result := '';
  ACandidates := nil;
  if (AProject = '') or not Assigned(AExists) or not Assigned(AReadLines) then
  begin
    Exit;
  end;
  if IsGroup(AProject) then
  begin
    Result := GroupTestProject(AProject, AExists, AReadLines, ACandidates);
  end
  else
  begin
    Result := SingleTestProject(AProject, AExists, AReadLines, ACandidates);
  end;
end;

class procedure TAtlasWelcomeQuickActions.AskExternals(var AButtons: TAtlasQuickActionButtons);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AButtons) do
  begin
    if (AButtons[mIndex].Action = TAtlasQuickAction.Pull) and AButtons[mIndex].Update then
    begin
      AButtons[mIndex].AskExternals := True;
      AButtons[mIndex].HasMenu := True;
    end;
  end;
end;

end.
