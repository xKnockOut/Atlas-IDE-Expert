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
