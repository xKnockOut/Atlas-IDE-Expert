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
//   prüft vor dem Holen die ganze Arbeitskopie noch einmal (geänderte
//   versionierte Dateien sperren, unversionierte nicht) und holt dann nur
//   vorwärts (Git: pull --ff-only, SVN: update; IAtlasVcsUpdate). Bei SVN
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
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasQuickAction = (Build, Tests, Run, Pull, Folder, Console, Tasks);
  /// <summary>Stand einer Aktion je Projekt: läuft, fertig (ok bzw. fehlgeschlagen) oder nicht ausgeführt.</summary>
  TAtlasQuickActionPhase = (Idle, Running, Succeeded, Failed, Refused);
  /// <summary>Grund, aus dem „Pull“ gesperrt ist.</summary>
  TAtlasPullBlock = (None, LocalChanges, NoWorkingCopy, Busy);
  /// <summary>Ergebnis von Pull: neue Commits geholt, schon aktuell, wegen lokaler Änderungen nicht geholt, keine
  /// Arbeitskopie, Fehler (auch Zeitüberschreitung oder fehlendes Programm).</summary>
  TAtlasPullOutcome = (Updated, UpToDate, Blocked, NoWorkingCopy, Failed);
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
    Names: array[TAtlasQuickAction] of string = ('build', 'tests', 'run', 'pull', 'folder', 'console', 'tasks');
    DefaultItems = 'build,tests,run,pull,folder,console,tasks';
    DefaultConsole = 'wt.exe';
    FallbackConsole = 'cmd.exe';
    /// <summary>Strg+B und Strg+T als TShortCut (scCtrl or Ord(Taste)).</summary>
    DefaultBuildKey = $4042;
    DefaultTestKey = $4054;
    /// <summary>Zeitlimit für Pull bzw. svn update (spricht mit dem Server).</summary>
    PullTimeoutMs = 120000;
    /// <summary>Auftraggeber der Builds in den Compile-Ereignissen (#527): keine Tests nach dem Build (#69).</summary>
    RequestedBy = 'welcome';
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
      AIdeBusy: Boolean = False): TAtlasQuickActionButtons; static;
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
    /// <summary>Sperren die Änderungen der Arbeitskopie Pull? Ja bei jeder Änderung außer unversionierten Dateien.
    /// </summary>
    class function ChangesBlockPull(const AChanges: TArray<TAtlasVcsChange>): Boolean; static;
    /// <summary>Pull bzw. svn update (startet Prozesse: nur im Hintergrund).</summary>
    class function Pull(const AVcs: IAtlasVersionControl): TAtlasPullOutcome; overload; static;
    /// <summary>Wie oben; AReason ist das Ergebnis des gescheiterten Aufrufs (für die Meldung bei Failed), sonst
    /// Ok.</summary>
    class function Pull(const AVcs: IAtlasVersionControl; out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
      overload; static;
    /// <summary>Wie oben; AIgnoreExternals: SVN ohne Externals (svn update --ignore-externals, #1292), sonst wie
    /// Pull. Git kennt das nicht und holt wie immer.</summary>
    class function Pull(const AVcs: IAtlasVersionControl; AIgnoreExternals: Boolean;
      out AReason: TAtlasVcsOutcome): TAtlasPullOutcome; overload; static;
    /// <summary>Pull-Knöpfe unter SVN mit vcs.externals.update = ask bekommen die Auswahl (#1292).</summary>
    class procedure AskExternals(var AButtons: TAtlasQuickActionButtons); static;
    /// <summary>„a\..\b“ und doppelte Trenner auflösen (Windows-Pfade, auch unter Linux in den Tests).</summary>
    class function CombinePath(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  Atlas.Text.DUnitX;

const
  Delimiter = '\';

function FolderOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Length(AFileName) downto 1 do
    if (AFileName[Index] = '\') or (AFileName[Index] = '/') then
      Exit(Copy(AFileName, 1, Index - 1));
end;

function NameOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(AFileName) downto 1 do
    if (AFileName[Index] = '\') or (AFileName[Index] = '/') then
      Exit(Copy(AFileName, Index + 1, MaxInt));
end;

function BaseNameOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := NameOf(AFileName);
  for Index := Length(Result) downto 1 do
    if Result[Index] = '.' then
      Exit(Copy(Result, 1, Index - 1));
end;

function ExtensionOf(const AFileName: string): string;
var
  Name: string;
  Index: Integer;
begin
  Result := '';
  Name := NameOf(AFileName);
  for Index := Length(Name) downto 1 do
    if Name[Index] = '.' then
      Exit(LowerCase(Copy(Name, Index, MaxInt)));
end;

function WithExtension(const AFileName, AExtension: string): string;
var
  Name: string;
  Index: Integer;
begin
  Name := NameOf(AFileName);
  Result := AFileName;
  for Index := Length(Name) downto 1 do
    if Name[Index] = '.' then
      Exit(Copy(AFileName, 1, Length(AFileName) - Length(Name) + Index - 1) + AExtension);
  Result := AFileName + AExtension;
end;

function ContainsText(const AItems: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in AItems do
    if SameText(Item, AValue) then
      Exit(True);
end;

/// <summary>Wert des Attributs bzw. Inhalts zwischen AStart (ab APos) und ADelimiter; '' ohne.</summary>
function NextValue(const AText, AStart, ADelimiter: string; var APos: Integer; out AValue: string): Boolean;
var
  Start, Stop: Integer;
begin
  AValue := '';
  Start := Pos(AStart, AText, APos);
  if Start = 0 then
    Exit(False);
  Inc(Start, Length(AStart));
  Stop := Pos(ADelimiter, AText, Start);
  if Stop = 0 then
    Exit(False);
  AValue := Copy(AText, Start, Stop - Start);
  APos := Stop + Length(ADelimiter);
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
    Exit;
  Result := Integer((ANowMs - StartedMs) div 1000);
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
  Part: string;
  Action: TAtlasQuickAction;
begin
  Result := [];
  for Part in AText.Split([',', ';', ' ']) do
    for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
      if SameText(Trim(Part), Names[Action]) then
        Include(Result, Action);
end;

class function TAtlasWelcomeQuickActions.ItemsText(AItems: TAtlasQuickActions): string;
var
  Action: TAtlasQuickAction;
begin
  Result := '';
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    if Action in AItems then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + Names[Action];
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
    Result := DefaultConsole;
end;

class function TAtlasWelcomeQuickActions.PullBlock(const AVcs: TAtlasProjectVcs): TAtlasPullBlock;
begin
  Result := TAtlasPullBlock.None;
  if not AVcs.Known then
    Exit;
  if SameText(AVcs.Kind, 'none') then
    Exit(TAtlasPullBlock.NoWorkingCopy);
  if AVcs.InWorkingCopy and (AVcs.Changed > 0) then
    Result := TAtlasPullBlock.LocalChanges;
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
  ABusy: Boolean; AIdeBusy: Boolean): TAtlasQuickActionButtons;
var
  Action: TAtlasQuickAction;
  Button: TAtlasQuickActionButton;
begin
  Result := nil;
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    if not (Action in AItems) then
      Continue;
    Button := Default(TAtlasQuickActionButton);
    Button.Action := Action;
    Button.Block := TAtlasPullBlock.None;
    // Ordner und Konsole stören keine laufende Aktion.
    Button.Enabled := not ABusy or (Action = TAtlasQuickAction.Folder) or (Action = TAtlasQuickAction.Console);
    // Die IDE öffnet immer nur ein Projekt zur Zeit.
    if AIdeBusy and UsesIde(Action) then
      Button.Enabled := False;
    Button.HasMenu := (Action = TAtlasQuickAction.Build) or (Action = TAtlasQuickAction.Run) or
      (Action = TAtlasQuickAction.Tasks);
    if Action = TAtlasQuickAction.Pull then
    begin
      Button.Update := IsUpdate(AVcs);
      Button.Block := PullBlock(AVcs);
      if (Button.Block = TAtlasPullBlock.None) and ABusy then
        Button.Block := TAtlasPullBlock.Busy;
      Button.Enabled := Button.Block = TAtlasPullBlock.None;
    end;
    Result := Result + [Button];
  end;
end;

class function TAtlasWelcomeQuickActions.IndexOf(const AButtons: TAtlasQuickActionButtons;
  AAction: TAtlasQuickAction): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(AButtons) do
    if AButtons[Index].Action = AAction then
      Exit(Index);
end;

class function TAtlasWelcomeQuickActions.ActionForKey(AShortCut, ABuildKey, ATestKey: Integer;
  AItems: TAtlasQuickActions; out AAction: TAtlasQuickAction): Boolean;
begin
  AAction := TAtlasQuickAction.Build;
  Result := False;
  if AShortCut = 0 then
    Exit;
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
    Exit(-1);
  Result := ARow + ADelta;
  if ARow < 0 then
    Result := 0;
  if Result < 0 then
    Result := 0;
  if Result > ACount - 1 then
    Result := ACount - 1;
end;

class function TAtlasWelcomeQuickActions.MoveButton(const AButtons: TAtlasQuickActionButtons; ACurrent,
  ADelta: Integer): Integer;
var
  Index, Step: Integer;
begin
  Result := ACurrent;
  if (ADelta = 0) or (Length(AButtons) = 0) then
    Exit;
  Step := 1;
  if ADelta < 0 then
    Step := -1;
  Index := ACurrent + Step;
  // Ohne gewählten Knopf beginnt „links“ beim letzten.
  if (ACurrent < 0) and (Step < 0) then
    Index := High(AButtons);
  while (Index >= 0) and (Index <= High(AButtons)) do
  begin
    if AButtons[Index].Enabled then
      Exit(Index);
    Inc(Index, Step);
  end;
end;

class function TAtlasWelcomeQuickActions.ConsoleCommand(const AProgram, AFolder: string; out AFileName,
  AParameters: string): Boolean;
var
  Folder, Quoted, Base: string;
begin
  AFileName := NormalizedConsole(AProgram);
  AParameters := '';
  Folder := Trim(AFolder);
  Result := Folder <> '';
  if not Result then
    Exit;
  // Ein Backslash vor dem schließenden Anführungszeichen würde es maskieren („C:\“ → „C:\.“).
  Quoted := Folder;
  if (Quoted[Length(Quoted)] = '\') or (Quoted[Length(Quoted)] = '/') then
    Quoted := Quoted + '.';
  Base := LowerCase(BaseNameOf(AFileName));
  if Base = 'wt' then
    AParameters := '-d "' + Quoted + '"'
  else if Base = 'cmd' then
    AParameters := '/K cd /d "' + Quoted + '"'
  else if (Base = 'powershell') or (Base = 'pwsh') then
    AParameters := '-NoExit -Command Set-Location -LiteralPath ''' + StringReplace(Quoted, '''', '''''',
      [rfReplaceAll]) + '''';
end;

class function TAtlasWelcomeQuickActions.ReadTargets(const AText: string): TAtlasProjectTargets;
var
  Position: Integer;
  Value, Content: string;
  Stop: Integer;
begin
  Result := Default(TAtlasProjectTargets);
  Position := 1;
  while NextValue(AText, '<BuildConfiguration Include="', '"', Position, Value) do
  begin
    Value := Trim(XmlDecoded(Value));
    if (Value <> '') and not SameText(Value, 'Base') and not ContainsText(Result.Configurations, Value) then
      Result.Configurations := Result.Configurations + [Value];
  end;
  Position := 1;
  while NextValue(AText, '<Platform value="', '"', Position, Value) do
  begin
    // <Platform value="Win64">True</Platform>; False = im Projekt abgeschaltet.
    Content := '';
    if Copy(AText, Position, 1) = '>' then
    begin
      Inc(Position);
      Stop := Pos('<', AText, Position);
      if Stop > 0 then
      begin
        Content := Copy(AText, Position, Stop - Position);
        Position := Stop;
      end;
    end;
    Value := Trim(XmlDecoded(Value));
    if (Value <> '') and SameText(Trim(Content), 'True') and not ContainsText(Result.Platforms, Value) then
      Result.Platforms := Result.Platforms + [Value];
  end;
end;

class procedure TAtlasWelcomeQuickActions.ChooseTarget(const ATargets: TAtlasProjectTargets;
  const ALastConfiguration, ALastPlatform: string; out AConfiguration, APlatform: string);
var
  Name: string;
begin
  AConfiguration := '';
  APlatform := '';
  // Schreibweise der Datei, damit die IDE die Konfiguration sicher findet.
  for Name in ATargets.Configurations do
    if SameText(Name, ALastConfiguration) then
      AConfiguration := Name;
  for Name in ATargets.Platforms do
    if SameText(Name, ALastPlatform) then
      APlatform := Name;
end;

class function TAtlasWelcomeQuickActions.CombinePath(const AFolder, ARelative: string): string;
var
  Parts, Kept: TArray<string>;
  Part, Joined: string;
begin
  Joined := StringReplace(ARelative, '/', Delimiter, [rfReplaceAll]);
  // Absoluter Pfad (Laufwerk oder UNC) bleibt, sonst relativ zu AFolder.
  if not ((Length(Joined) > 1) and ((Joined[2] = ':') or (Copy(Joined, 1, 2) = '\\'))) then
    Joined := StringReplace(AFolder, '/', Delimiter, [rfReplaceAll]) + Delimiter + Joined;
  Kept := nil;
  Parts := Joined.Split([Delimiter]);
  for Part in Parts do
  begin
    if (Part = '.') or ((Part = '') and (Length(Kept) > 0)) then
      Continue;
    if (Part = '..') and (Length(Kept) > 1) and (Kept[High(Kept)] <> '..') then
    begin
      SetLength(Kept, Length(Kept) - 1);
      Continue;
    end;
    Kept := Kept + [Part];
  end;
  Result := string.Join(Delimiter, Kept);
  // UNC: zwei führende Trenner.
  if Copy(Joined, 1, 2) = '\\' then
    Result := Delimiter + Result;
end;

class function TAtlasWelcomeQuickActions.GroupProjects(const AText, AFolder: string): TArray<string>;
var
  Position: Integer;
  Value, Path: string;
begin
  Result := nil;
  Position := 1;
  while NextValue(AText, '<Projects Include="', '"', Position, Value) do
  begin
    Value := Trim(XmlDecoded(Value));
    if Value = '' then
      Continue;
    Path := CombinePath(AFolder, Value);
    if not ContainsText(Result, Path) then
      Result := Result + [Path];
  end;
end;

class function TAtlasWelcomeQuickActions.IsGroup(const AFileName: string): Boolean;
begin
  Result := ExtensionOf(AFileName) = '.groupproj';
end;

class function TAtlasWelcomeQuickActions.TestCandidates(const AProject: string): TArray<string>;
const
  Patterns: array[0..3] of string = ('%s.Tests.dproj', '%sTests.dproj', '%s.Test.dproj', '%sTest.dproj');
  Folders: array[0..4] of string = ('', 'Tests', 'Test', '..\Tests', '..\Test');
var
  Name, Folder, Sub, Pattern, Path: string;
begin
  Result := nil;
  Name := BaseNameOf(AProject);
  Folder := FolderOf(AProject);
  if Name = '' then
    Exit;
  for Sub in Folders do
    for Pattern in Patterns do
    begin
      if Sub = '' then
        Path := CombinePath(Folder, Format(Pattern, [Name]))
      else
        Path := CombinePath(Folder, Sub + Delimiter + Format(Pattern, [Name]));
      if not SameText(Path, AProject) and not ContainsText(Result, Path) then
        Result := Result + [Path];
    end;
end;

class function TAtlasWelcomeQuickActions.TestProjectFor(const AProject: string;
  const AExists: TAtlasQuickFileExists; const AReadLines: TAtlasQuickReadLines;
  out ACandidates: TArray<string>): string;

  function IsTestProject(const AFileName: string): Boolean;
  var
    Lines: TArray<string>;
    Main: string;
  begin
    // Wie die IDE (#69): Hauptdatei .dpr neben der .dproj verwendet DUnitX.TestFramework.
    Main := WithExtension(AFileName, '.dpr');
    Result := AExists(Main) and AReadLines(Main, Lines) and TDUnitXSource.UsesDUnitX(Lines);
  end;

var
  Lines: TArray<string>;
  Candidate, Group: string;
begin
  Result := '';
  ACandidates := nil;
  if (AProject = '') or not Assigned(AExists) or not Assigned(AReadLines) then
    Exit;
  if IsGroup(AProject) then
  begin
    if not AReadLines(AProject, Lines) then
      Exit;
    for Candidate in GroupProjects(string.Join(#10, Lines), FolderOf(AProject)) do
      if IsTestProject(Candidate) then
        ACandidates := ACandidates + [Candidate];
    if Length(ACandidates) = 1 then
      Exit(ACandidates[0]);
    // Mehrere: das nach der Gruppe benannte, sonst fragt die IDE.
    Group := BaseNameOf(AProject);
    for Candidate in ACandidates do
      if SameText(BaseNameOf(Candidate), Group + '.Tests') or SameText(BaseNameOf(Candidate), Group + 'Tests') then
        Exit(Candidate);
    Exit;
  end;
  if IsTestProject(AProject) then
  begin
    ACandidates := [AProject];
    Exit(AProject);
  end;
  for Candidate in TestCandidates(AProject) do
    if AExists(Candidate) and IsTestProject(Candidate) then
      ACandidates := ACandidates + [Candidate];
  if Length(ACandidates) > 0 then
    Result := ACandidates[0];
end;

class function TAtlasWelcomeQuickActions.ChangesBlockPull(const AChanges: TArray<TAtlasVcsChange>): Boolean;
var
  Change: TAtlasVcsChange;
begin
  Result := False;
  for Change in AChanges do
    if Change.Kind <> TAtlasVcsChangeKind.Untracked then
      Exit(True);
end;

class function TAtlasWelcomeQuickActions.Pull(const AVcs: IAtlasVersionControl): TAtlasPullOutcome;
var
  Reason: TAtlasVcsOutcome;
begin
  Result := Pull(AVcs, Reason);
end;

class function TAtlasWelcomeQuickActions.Pull(const AVcs: IAtlasVersionControl;
  out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
begin
  Result := Pull(AVcs, False, AReason);
end;

class procedure TAtlasWelcomeQuickActions.AskExternals(var AButtons: TAtlasQuickActionButtons);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AButtons) do
    if (AButtons[mIndex].Action = TAtlasQuickAction.Pull) and AButtons[mIndex].Update then
    begin
      AButtons[mIndex].AskExternals := True;
      AButtons[mIndex].HasMenu := True;
    end;
end;

class function TAtlasWelcomeQuickActions.Pull(const AVcs: IAtlasVersionControl; AIgnoreExternals: Boolean;
  out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
var
  Before, After: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Outcome: TAtlasVcsOutcome;
  Update: IAtlasVcsUpdate;
  mExternals: IAtlasVcsSvnExternals;
begin
  AReason := TAtlasVcsOutcome.Ok;
  if AVcs = nil then
    Exit(TAtlasPullOutcome.NoWorkingCopy);
  Outcome := AVcs.Head(Before);
  if (Outcome = TAtlasVcsOutcome.NoWorkingCopy) or (Outcome = TAtlasVcsOutcome.Disabled) then
    Exit(TAtlasPullOutcome.NoWorkingCopy);
  AReason := Outcome;
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit(TAtlasPullOutcome.Failed);
  // Vor dem Holen frisch prüfen: Der gezeigte Stand kann älter sein.
  AReason := AVcs.Changes(Changes);
  if AReason <> TAtlasVcsOutcome.Ok then
    Exit(TAtlasPullOutcome.Failed);
  if ChangesBlockPull(Changes) then
    Exit(TAtlasPullOutcome.Blocked);
  if AIgnoreExternals and Supports(AVcs, IAtlasVcsSvnExternals, mExternals) then
    AReason := mExternals.Update(True)
  else if Supports(AVcs, IAtlasVcsUpdate, Update) then
    AReason := Update.Pull
  else
  begin
    AReason := TAtlasVcsOutcome.Failed;
    Exit(TAtlasPullOutcome.Failed);
  end;
  if AReason <> TAtlasVcsOutcome.Ok then
    Exit(TAtlasPullOutcome.Failed);
  Result := TAtlasPullOutcome.UpToDate;
  if (AVcs.Head(After) = TAtlasVcsOutcome.Ok) and (After.Revision <> Before.Revision) then
    Result := TAtlasPullOutcome.Updated;
end;

end.
