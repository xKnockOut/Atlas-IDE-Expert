unit Atlas.Core.Vcs.Contract;

// Versionsverwaltung über eine gemeinsame Schnittstelle (#571). Funktionen, die
// Branch, Revision, geänderte Dateien oder Zeilenherkunft brauchen, fragen nur
// IAtlasVersionControl; ob dahinter Git, SVN oder nichts steht, entscheidet die
// Auswahl (Atlas.Core.Vcs.Composition) nach gefundener Arbeitskopie und der
// Einstellung vcs.provider.
// Die Umsetzungen rufen git bzw. svn über IAtlasVcsRunner auf (Kommandozeile,
// keine Bibliotheken). Jeder Aufruf startet einen Prozess: Er gehört nie in
// den Hauptthread der IDE (siehe Atlas.Core.Vcs.Worker), der Prozessläufer der
// IDE lehnt ihn dort ab.
// Ohne VCL und Open Tools API; auch der Server (--changed mit SVN, #276)
// übersetzt diese Units mit.
// IAtlasVcsLocalWork (#762) ergänzt, was noch nicht auf dem Server liegt:
// lokale Branches mit Vorsprung, Commits, die nur lokal sind, Stashes und das
// Pushen nach Bestätigung. Abfragen lesen nur das lokale Repository (kein
// fetch); nur Push spricht mit dem Server.
// IAtlasVcsIncoming (#755) liefert eingehende Commits: was auf dem verfolgten
// Branch (z. B. origin/main) liegt, aber nicht in gemerkten Ständen, mit Autor
// und geänderten Dateien. Grundlage ist der lokale Stand der Remote-Branches;
// nur Fetch spricht mit dem Server (ohne Rückfrage nach Zugangsdaten).
// IAtlasVcsUpdate (#764) holt neue Commits in die Arbeitskopie: Git nur
// vorwärts (pull --ff-only), SVN mit update; für die Schnellaktion „Pull“
// der Willkommensseite.
// IAtlasVcsBranching (#765) legt für ein Issue einen Branch an und wechselt
// dorthin: Git lokal von einer Basis (checkout -b), SVN als Kopie im
// Repository (svn copy ^/trunk ^/branches/…) mit svn switch; dazu die Ordner
// für den Commit-Hook (Git prepare-commit-msg).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Arbeitskopie.</summary>
  TAtlasVcsKind = (None, Git, Svn);

  /// <summary>Einstellung vcs.provider: auto wählt nach gefundener Arbeitskopie (die nächstliegende gilt,
  /// bei Gleichstand Git), git bzw. svn nur diese Art, off schaltet die Versionsverwaltung ab.</summary>
  TAtlasVcsProvider = (Auto, Git, Svn, Off);

  /// <summary>Ergebnis eines Aufrufs. Ok: Werte gültig. NoWorkingCopy: Ordner liegt in keiner Arbeitskopie.
  /// Disabled: vcs.provider = off. ToolMissing: git bzw. svn nicht installiert. Failed: Programm meldete einen
  /// Fehler (Exit-Code ungleich 0 oder unlesbare Ausgabe). TimedOut: Zeitlimit überschritten, Prozess
  /// beendet. Cancelled: Abbruch (Entladen der IDE). MainThread: im Hauptthread abgelehnt.</summary>
  TAtlasVcsOutcome = (Ok, NoWorkingCopy, Disabled, ToolMissing, Failed, TimedOut, Cancelled, MainThread);

  /// <summary>Art einer Änderung gegenüber dem Stand im Repository.</summary>
  TAtlasVcsChangeKind = (Modified, Added, Deleted, Renamed, Copied, TypeChanged, Replaced, Untracked,
    Conflicted, Missing);

  /// <summary>Erkannter Wechsel zwischen zwei Ständen. Branch: anderer Branch bzw. SVN-Pfad (git checkout,
  /// git switch, svn switch). Revision: gleicher Branch, andere Revision (Commit, Pull, svn update).</summary>
  TAtlasVcsSwitch = (None, Branch, Revision);
{$SCOPEDENUMS OFF}

  /// <summary>Gefundene Arbeitskopie.</summary>
  TAtlasVcsWorkingCopy = record
    Kind: TAtlasVcsKind;
    /// <summary>Wurzelordner ohne abschließenden Trenner; '' ohne Arbeitskopie.</summary>
    Root: string;
    class function Empty: TAtlasVcsWorkingCopy; static;
  end;

  /// <summary>Aktueller Stand der Arbeitskopie.</summary>
  TAtlasVcsHead = record
    /// <summary>Git: Name des Branchs, '' bei losgelöstem HEAD. SVN: Pfad im Repository wie "trunk" oder
    /// "branches/x".</summary>
    Branch: string;
    /// <summary>Git: vollständiger Commit-Hash, '' vor dem ersten Commit. SVN: Revisionsnummer der
    /// Arbeitskopie.</summary>
    Revision: string;
    /// <summary>Git: HEAD zeigt auf keinen Branch.</summary>
    Detached: Boolean;
    /// <summary>Git: verfolgter Branch, z. B. "origin/main"; '' ohne (SVN immer '').</summary>
    Upstream: string;
    /// <summary>Git: Commits vor bzw. hinter dem verfolgten Branch nach dem letzten Abruf; -1 unbekannt
    /// (kein verfolgter Branch, SVN).</summary>
    Ahead: Integer;
    Behind: Integer;
    class function Empty: TAtlasVcsHead; static;
    /// <summary>Kurzform der Revision: Git die ersten 7 Zeichen, SVN "r42".</summary>
    function ShortRevision(AKind: TAtlasVcsKind): string;
  end;

  /// <summary>Geänderte oder neue Datei gegenüber dem Stand im Repository.</summary>
  TAtlasVcsChange = record
    /// <summary>Vollständiger Pfad.</summary>
    Path: string;
    /// <summary>Vorheriger vollständiger Pfad bei Renamed und Copied, sonst ''.</summary>
    OldPath: string;
    Kind: TAtlasVcsChangeKind;
    /// <summary>Git: Änderung steht (auch) im Index. SVN: immer False.</summary>
    Staged: Boolean;
    /// <summary>Git: Änderung steht (auch) nur im Arbeitsverzeichnis. SVN: immer True.</summary>
    Unstaged: Boolean;
  end;

  /// <summary>Herkunft einer Zeile (blame).</summary>
  TAtlasVcsBlameLine = record
    /// <summary>Zeilennummer, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Commit bzw. Revision; '' für noch nicht übernommene Zeilen.</summary>
    Revision: string;
    Author: string;
    /// <summary>Zeitpunkt in UTC; 0 für noch nicht übernommene Zeilen.</summary>
    Date: TDateTime;
    /// <summary>Git: erste Zeile der Commit-Nachricht. SVN: ''.</summary>
    Summary: string;
    /// <summary>Zeile ist noch nicht übernommen (lokale Änderung).</summary>
    function Uncommitted: Boolean;
  end;

  /// <summary>Lokaler Branch (Git, #762).</summary>
  TAtlasVcsBranch = record
    /// <summary>Kurzname, z. B. "feature/x".</summary>
    Name: string;
    /// <summary>Verfolgter Branch, z. B. "origin/main"; '' ohne.</summary>
    Upstream: string;
    /// <summary>Remote des verfolgten Branchs, z. B. "origin"; '' ohne.</summary>
    Remote: string;
    /// <summary>Ref auf dem Remote, z. B. "refs/heads/main"; '' ohne.</summary>
    RemoteRef: string;
    /// <summary>Der verfolgte Branch existiert nicht mehr (auf dem Server gelöscht).</summary>
    Gone: Boolean;
    /// <summary>Commits vor bzw. hinter dem verfolgten Branch nach dem letzten Abruf; -1 unbekannt bzw. ohne.</summary>
    Ahead: Integer;
    Behind: Integer;
    /// <summary>Zeitpunkt des letzten Commits (Committer, UTC); 0 unbekannt.</summary>
    TipDate: TDateTime;
    /// <summary>HEAD zeigt auf diesen Branch.</summary>
    Current: Boolean;
    /// <summary>Hat einen verfolgten Branch, der noch existiert.</summary>
    function Tracked: Boolean;
  end;

  /// <summary>Eintrag der Stash-Liste (Git, #762).</summary>
  TAtlasVcsStash = record
    /// <summary>Commit des Stashs (bleibt gleich, wenn neuere dazukommen).</summary>
    Hash: string;
    /// <summary>Auswahl wie "stash@{0}".</summary>
    Ref: string;
    /// <summary>Branch beim Anlegen.</summary>
    Branch: string;
    /// <summary>Name bzw. Nachricht ohne "WIP on …:"/"On …:".</summary>
    Message: string;
    /// <summary>Angelegt (UTC).</summary>
    Date: TDateTime;
  end;

  /// <summary>Commit in einer Liste (z. B. noch nicht gepusht, #762).</summary>
  TAtlasVcsCommit = record
    Hash: string;
    /// <summary>Committer-Zeitpunkt (UTC).</summary>
    Date: TDateTime;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Kurzform des Hashs (7 Zeichen).</summary>
    function ShortHash: string;
  end;

  /// <summary>Eingehender Commit mit Autor und geänderten Dateien (#755).</summary>
  TAtlasVcsIncomingCommit = record
    Hash: string;
    /// <summary>Committer-Zeitpunkt (UTC).</summary>
    Date: TDateTime;
    Author: string;
    /// <summary>Erste Zeile der Nachricht.</summary>
    Summary: string;
    /// <summary>Geänderte Dateien, vollständige Pfade; leer bei Merges.</summary>
    Files: TArray<string>;
    /// <summary>Kurzform des Hashs (7 Zeichen).</summary>
    function ShortHash: string;
  end;

  /// <summary>Ergebnis eines Prozessaufrufs.</summary>
  TAtlasVcsRunResult = record
    Outcome: TAtlasVcsOutcome;
    ExitCode: Integer;
    /// <summary>stdout als Bytes; die Umsetzung kennt die Kodierung (Git und svn --xml: UTF-8).</summary>
    Output: TBytes;
    /// <summary>stderr, nur für die Fehlersuche; enthält Pfade und gehört deshalb nie ins Protokoll.</summary>
    ErrorText: string;
    class function Make(AOutcome: TAtlasVcsOutcome; AExitCode: Integer; const AOutput: TBytes): TAtlasVcsRunResult;
      static;
  end;

  /// <summary>Startet git bzw. svn unsichtbar (ohne Konsolenfenster) und wartet höchstens ATimeoutMs.</summary>
  IAtlasVcsRunner = interface
    ['{6B3C8E1D-2F47-4A9B-B0C5-8D1E7A2F9C34}']
    /// <summary>AExecutable: vollständiger Pfad des Programms. AWorkingDir: Arbeitsverzeichnis des Prozesses.
    /// Outcome ist Ok, sobald der Prozess gelaufen ist, auch bei Exit-Code ungleich 0.</summary>
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

  /// <summary>Gemeinsame Schnittstelle für Git, SVN und „keine Versionsverwaltung“ (#571). Jede Methode
  /// außer Kind, WorkingCopy und ChangeMarker startet einen Prozess: nur aus einem Hintergrund-Thread
  /// aufrufen. Implementierungen sind zustandslos und dürfen aus mehreren Threads benutzt werden.</summary>
  IAtlasVersionControl = interface
    ['{9A2E4C61-7D3B-4F58-8E19-C4B6A0D2F713}']
    function Kind: TAtlasVcsKind;
    /// <summary>Arbeitskopie mit Wurzelordner und Art.</summary>
    function WorkingCopy: TAtlasVcsWorkingCopy;
    /// <summary>Aktueller Branch bzw. SVN-Pfad und Revision bzw. Commit.</summary>
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    /// <summary>Geänderte und neue Dateien gegenüber dem Stand im Repository (Git: HEAD samt Index, SVN: BASE),
    /// unversionierte eingeschlossen, ignorierte nicht.</summary>
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    /// <summary>Inhalt von AFileName (vollständiger Pfad) in ARevision als Bytes, für Vergleiche.
    /// ARevision '' = Stand im Repository (Git HEAD, SVN BASE).</summary>
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    /// <summary>Herkunft jeder Zeile von AFileName im Arbeitsverzeichnis (blame), Zeile für Zeile.</summary>
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    /// <summary>Billige Marke aus Dateizeitstempeln der Verwaltungsdaten (ohne Prozess); ändert sie sich, kann
    /// sich Branch oder Revision geändert haben. '' ohne Arbeitskopie.</summary>
    function ChangeMarker: string;
  end;

  /// <summary>Was noch nicht auf dem Server liegt (#762). Git, SVN und die leere Umsetzung bieten diese
  /// Schnittstelle zusätzlich zu IAtlasVersionControl (Supports). SVN kennt weder lokale Commits noch Stashes:
  /// Branches, Stashes, Remotes und Outgoing liefern dort Ok mit leerer Liste, ChangesIn und Push Failed. Jede
  /// Methode startet einen Prozess: nur aus einem Hintergrund-Thread aufrufen. Keine Abfrage spricht mit dem
  /// Server (kein fetch); Vorsprung und Rückstand gelten seit dem letzten Abruf.</summary>
  IAtlasVcsLocalWork = interface
    ['{3F1C7B52-8E4A-4D19-A6E0-5B2D9C8F7A61}']
    /// <summary>Lokale Branches mit verfolgtem Branch und Vorsprung.</summary>
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    /// <summary>Stashes, neuester zuerst.</summary>
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    /// <summary>Namen der Remotes, z. B. "origin".</summary>
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    /// <summary>Commits von ABranch, die nicht in AUpstream liegen ('' = auf keinem Remote), neueste zuerst,
    /// höchstens AMax.</summary>
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    /// <summary>Dateien, die ARevision (Commit oder Stash) gegenüber ihrem ersten Vorgänger ändert.</summary>
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    /// <summary>Pusht ABranch nach ARemote auf ARemoteRef (z. B. "refs/heads/main"); ASetUpstream trägt ihn als
    /// verfolgten Branch ein. Spricht mit dem Server; nur nach Bestätigung durch den Benutzer.</summary>
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
  end;

  /// <summary>Eingehende Commits (#755). Git, SVN und die leere Umsetzung bieten diese Schnittstelle
  /// zusätzlich zu IAtlasVersionControl (Supports). Resolve und Incoming lesen nur das lokale Repository (Git:
  /// den Stand der Remote-Branches seit dem letzten Abruf); nur Fetch spricht mit dem Server. SVN hält keinen
  /// lokalen Stand des Servers: Resolve liefert dort '', Incoming eine leere Liste und Fetch tut nichts (alle
  /// Ok ohne Prozess). Jede Methode der Git-Umsetzung startet einen Prozess: nur aus einem Hintergrund-Thread
  /// aufrufen.</summary>
  IAtlasVcsIncoming = interface
    ['{5D8B2E47-1C9A-4F63-B7D0-2E6A4C9F1B83}']
    /// <summary>Commit zu ARef (z. B. "origin/main", "HEAD" oder ein Hash); Failed, wenn es ihn nicht gibt.
    /// </summary>
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    /// <summary>Commits von AUpstream, die in keinem Stand aus AExclude liegen (leere Einträge zählen nicht),
    /// neueste zuerst, höchstens AMax, mit Autor und geänderten Dateien.</summary>
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    /// <summary>Remote-Branches von ARemote abrufen ('' = Remote des aktuellen Branchs bzw. origin), ohne
    /// Rückfrage nach Zugangsdaten. Spricht mit dem Server.</summary>
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
  end;

  /// <summary>Arbeitskopie auf den Stand des Servers bringen (#764). Git: pull --ff-only ohne Rückfrage nach
  /// Zugangsdaten (kein Merge, kein Rebase; weicht der Branch ab, Failed); SVN: update. Die leere Umsetzung
  /// liefert ihr Outcome. Ob lokale Änderungen das Holen sperren, entscheidet der Aufrufer vorher. Spricht mit
  /// dem Server und startet einen Prozess: nur aus einem Hintergrund-Thread aufrufen, mit Zeitlimit.</summary>
  IAtlasVcsUpdate = interface
    ['{8AFD73A9-6F83-48FE-B1B8-4B4D0E96D7E8}']
    function Pull: TAtlasVcsOutcome;
  end;

  /// <summary>Branch für ein Issue anlegen und dorthin wechseln (#765). Git: lokaler Branch von einer Basis
  /// (checkout -b, ohne verfolgten Branch); SVN: Kopie im Repository (svn copy ^/&lt;Basis&gt; ^/branches/&lt;Name&gt;
  /// --parents) und Umstellen der Arbeitskopie (svn switch). Die leere Umsetzung liefert ihr Outcome. Ob lokale
  /// Änderungen vorher eine Rückfrage brauchen, entscheidet der Aufrufer. Jede Methode der Git- und SVN-Umsetzung
  /// startet einen Prozess (SVN spricht dabei mit dem Server): nur aus einem Hintergrund-Thread aufrufen, mit
  /// Zeitlimit. Namen mit Leer- oder Steuerzeichen, „..“ oder „-“ am Anfang lehnen alle mit Failed ab.</summary>
  IAtlasVcsBranching = interface
    ['{2C7E9A41-6B5D-4F38-9E12-A8D4C3B7F605}']
    /// <summary>Git: lokaler Branch refs/heads/&lt;AName&gt; existiert. SVN: ^/branches/&lt;AName&gt; existiert
    /// (fehlt er oder antwortet der Server mit einem Fehler, gilt er als nicht vorhanden).</summary>
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    /// <summary>Git: neuen Branch AName von ABase anlegen und auschecken; ABase ist ein lokaler Branch, sonst
    /// origin/&lt;ABase&gt;, '' = HEAD; gibt es beides nicht, Failed. SVN: ^/&lt;ABase&gt; ('' = trunk) nach
    /// ^/branches/&lt;AName&gt; kopieren (Nachricht AMessage) und die Arbeitskopie dorthin umstellen.</summary>
    function CreateBranch(const AName, ABase, AMessage: string): TAtlasVcsOutcome;
    /// <summary>Zu einem vorhandenen Branch wechseln (Git checkout, SVN switch ^/branches/&lt;AName&gt;).</summary>
    function SwitchBranch(const AName: string): TAtlasVcsOutcome;
    /// <summary>Git: Ordner der Hooks (beachtet core.hooksPath) und Verwaltungsordner dieser Arbeitskopie
    /// (bei Worktrees der eigene), beide vollständig. SVN kennt keine Hooks auf dem Rechner: Ok mit ''. Die leere
    /// Umsetzung liefert ihr Outcome mit ''.</summary>
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
  end;

  /// <summary>Fehler beim Lesen einer Ausgabe; die Umsetzungen machen daraus Outcome Failed.</summary>
  EAtlasVcsParse = class(Exception);

/// <summary>Name für Meldungen: "Git", "SVN" oder "".</summary>
function AtlasVcsKindName(AKind: TAtlasVcsKind): string;
/// <summary>Name des Ergebnisses für Protokoll und Meldungen, z. B. "TimedOut".</summary>
function AtlasVcsOutcomeName(AOutcome: TAtlasVcsOutcome): string;
/// <summary>vcs.provider aus dem Text der Einstellung (auch in Anführungszeichen); unbekannt oder leer = Auto.</summary>
function AtlasVcsProviderOf(const AText: string): TAtlasVcsProvider;
/// <summary>Text der Einstellung: "auto", "git", "svn" oder "off".</summary>
function AtlasVcsProviderText(AProvider: TAtlasVcsProvider): string;

implementation

function AtlasVcsKindName(AKind: TAtlasVcsKind): string;
begin
  case AKind of
    TAtlasVcsKind.Git:
      Result := 'Git';
    TAtlasVcsKind.Svn:
      Result := 'SVN';
  else
    Result := '';
  end;
end;

function AtlasVcsOutcomeName(AOutcome: TAtlasVcsOutcome): string;
const
  Names: array[TAtlasVcsOutcome] of string = ('Ok', 'NoWorkingCopy', 'Disabled', 'ToolMissing', 'Failed',
    'TimedOut', 'Cancelled', 'MainThread');
begin
  Result := Names[AOutcome];
end;

function AtlasVcsProviderOf(const AText: string): TAtlasVcsProvider;
var
  Text: string;
begin
  // Auch als JSON-Text mit Anführungszeichen, wie ihn TAtlasJsonText.ValueAt liefert.
  Text := LowerCase(Trim(AText).Trim(['"']));
  if Text = 'git' then
    Result := TAtlasVcsProvider.Git
  else if Text = 'svn' then
    Result := TAtlasVcsProvider.Svn
  else if Text = 'off' then
    Result := TAtlasVcsProvider.Off
  else
    Result := TAtlasVcsProvider.Auto;
end;

function AtlasVcsProviderText(AProvider: TAtlasVcsProvider): string;
begin
  case AProvider of
    TAtlasVcsProvider.Git:
      Result := 'git';
    TAtlasVcsProvider.Svn:
      Result := 'svn';
    TAtlasVcsProvider.Off:
      Result := 'off';
  else
    Result := 'auto';
  end;
end;

{ TAtlasVcsWorkingCopy }

class function TAtlasVcsWorkingCopy.Empty: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.None;
  Result.Root := '';
end;

{ TAtlasVcsHead }

class function TAtlasVcsHead.Empty: TAtlasVcsHead;
begin
  Result.Branch := '';
  Result.Revision := '';
  Result.Detached := False;
  Result.Upstream := '';
  Result.Ahead := -1;
  Result.Behind := -1;
end;

function TAtlasVcsHead.ShortRevision(AKind: TAtlasVcsKind): string;
begin
  if Revision = '' then
    Result := ''
  else if AKind = TAtlasVcsKind.Svn then
    Result := 'r' + Revision
  else
    Result := Copy(Revision, 1, 7);
end;

{ TAtlasVcsBlameLine }

function TAtlasVcsBlameLine.Uncommitted: Boolean;
begin
  Result := Revision = '';
end;

{ TAtlasVcsBranch }

function TAtlasVcsBranch.Tracked: Boolean;
begin
  Result := (Upstream <> '') and not Gone;
end;

{ TAtlasVcsCommit }

function TAtlasVcsCommit.ShortHash: string;
begin
  Result := Copy(Hash, 1, 7);
end;

{ TAtlasVcsIncomingCommit }

function TAtlasVcsIncomingCommit.ShortHash: string;
begin
  Result := Copy(Hash, 1, 7);
end;

{ TAtlasVcsRunResult }

class function TAtlasVcsRunResult.Make(AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
  const AOutput: TBytes): TAtlasVcsRunResult;
begin
  Result.Outcome := AOutcome;
  Result.ExitCode := AExitCode;
  Result.Output := AOutput;
  Result.ErrorText := '';
end;

end.
