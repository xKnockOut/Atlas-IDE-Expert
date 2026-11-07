unit Atlas.Core.Vcs.BranchPlan;

// Plan für „Branch anlegen“ (#1288), ohne VCL: was Atlas über die
// Arbeitskopie weiß (TAtlasVcsBranchFacts), welche Basen zur Wahl stehen, und
// die Schritte, die genau so im Dialog unter „Was passiert“ stehen und danach
// über IAtlasVcsBranching.RunStep laufen. Anzeige und Ausführung kommen so aus
// derselben Liste.
// Git (lokal, ohne Server):
//   checkout --quiet --no-track -b <Name> <Basis> --
//   Basis: refs/remotes/origin/<Hauptbranch>, refs/heads/<Hauptbranch> oder
//   der aktuelle Branch (losgelöst: HEAD). Vorgabe wie bisher bei „Beginnen“
//   (#765): der lokale Hauptbranch, sonst origin/<Hauptbranch>; ohne
//   Hauptbranch keine Vorgabe (der aktuelle Branch nur, wenn ihn der Dialog
//   ausdrücklich wählt).
// SVN (mit dem Server):
//   copy ^/<Basis>@<Revision> ^/<Ort>@ --parents -m <Nachricht>
//   danach (#1290, vcs.branch.svn.after) switch ^/<Ort>@ . (Vorgabe),
//   checkout ^/<Ort>@ <Ordner> oder nichts.
//   Ort (#1290, vcs.branch.svn.location): Vorgabe {projektwurzel}/branches/
//   <Name>, die Projektwurzel aus dem Pfad der Arbeitskopie (^/Kasse/trunk →
//   ^/Kasse, TAtlasSvnLayout); ohne erkennbares Layout fragt der Dialog.
//   Der Hauptbranch liegt ebenso unter der Projektwurzel ("trunk" →
//   "Kasse/trunk").
//   Basis: Hauptbranch @ HEAD (mit der Revision, die der Dialog vom Server
//   geholt hat; ohne sie zum Zeitpunkt des Kopierens) oder der Pfad der
//   Arbeitskopie @ ihrer Revision (gemischt: die höchste aus svnversion,
//   der Dialog warnt); die Vorgabe wählt vcs.branch.svn.source. Die Kopie
//   ändert den Server und wird bei einem späteren Fehler nicht
//   zurückgenommen. switch und checkout laufen mit dem langen Zeitlimit.
// Externals (#1291): Inspect liest svn:externals samt Zustand jeder
// External-Arbeitskopie (svnversion: Revision, lokale Änderungen); je
// External wählt die Anfrage festschreiben, lassen oder mitverzweigen
// (Vorgabe aus Regeln und vcs.externals.*). Reihenfolge der Schritte:
//   1. je mitverzweigtem Package copy ^/<Quelle>@<Rev> ^/<Ort des Packages>@
//      (Ort nach vcs.branch.svn.location unter der Projektwurzel des Packages)
//   2. copy des Projekts; sind alle Externals ohne Revision festzuschreiben
//      und kennt svn --pin-externals (ab 1.9), mit --pin-externals
//   3. sonst je Ordner mit geänderten Zeilen: checkout --depth empty des
//      Ordners im neuen Branch in einen Arbeitsordner unter %TEMP%, propset
//      svn:externals -F <Datei> (nur die betroffenen Zeilen geändert, Pin mit
//      -r <Revision der External-Arbeitskopie>) und commit
//   4. danach (switch, checkout oder nichts).
// Der Arbeitsordner wird vor und nach dem Ausführen gelöscht (Execute mit
// Anfrage).
// Git-Optionen (#1289, vcs.branch.git.*) als Felder der Anfrage und weitere
// Schritte, in dieser Reihenfolge:
//   fetch --quiet --no-tags <Remote> <Hauptbranch>      (Basis vom Server)
//   stash push --include-untracked --quiet -m "Atlas: vor <Name>"
//   checkout … bzw. worktree add --quiet --no-track -b <Name> <Ordner> <Basis>
//   push --set-upstream <Remote> refs/heads/<Name>:refs/heads/<Name>
//   Remote = verfolgter Remote des lokalen Hauptbranchs, sonst origin. Mit
//   worktree bleibt die Arbeitskopie unberührt: kein stash. Scheitert der
//   Abruf, ist noch nichts geändert (LocalFallback baut die Anfrage für den
//   lokalen Stand); scheitert nur der Push, bleibt der lokale Branch
//   (OnlyPushFailed).
// Inspect und InspectServer starten Prozesse: nur aus einem Hintergrund-Thread.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Wovon der neue Branch abzweigt.</summary>
  TAtlasVcsBranchBaseKind = (
    /// <summary>Git: origin/&lt;Hauptbranch&gt; im Stand des letzten Abrufs.</summary>
    RemoteMain,
    /// <summary>Git: lokaler Hauptbranch.</summary>
    LocalMain,
    /// <summary>Git: aktueller Branch (losgelöst: HEAD).</summary>
    Current,
    /// <summary>SVN: Hauptbranch @ HEAD.</summary>
    Head,
    /// <summary>SVN: Pfad der Arbeitskopie @ ihrer Revision.</summary>
    WorkingCopy);
  /// <summary>vcs.branch.git.base (#1289): Vorgabe der Basis unter Git.</summary>
  TAtlasVcsGitBaseOption = (
    /// <summary>Stand auf dem Server: vorher fetch, dann &lt;Remote&gt;/&lt;Hauptbranch&gt;.</summary>
    Remote,
    /// <summary>Lokaler Hauptbranch, sonst origin/&lt;Hauptbranch&gt; (Verhalten vor #1289).</summary>
    Local,
    /// <summary>Aktueller Branch (losgelöst: HEAD).</summary>
    Current);

  /// <summary>vcs.branch.git.uncommitted (#1289): offene Änderungen beim Umschalten.</summary>
  TAtlasVcsGitUncommitted = (
    /// <summary>Wandern mit (checkout -b, Verhalten vor #1289).</summary>
    Carry,
    /// <summary>Vorher beiseitelegen (stash push --include-untracked); der Stash bleibt liegen.</summary>
    Stash,
    /// <summary>Nachfragen: mitnehmen, beiseitelegen oder abbrechen.</summary>
    Ask);
{$SCOPEDENUMS OFF}

  /// <summary>Git-Vorgaben für „Branch anlegen“ (#1289) aus vcs.branch.git.*; der Dialog zeigt sie vorbelegt.
  /// </summary>
  TAtlasVcsGitBranchOptions = record
  public const
    DefaultWorktreeFolder = '..\{repo}-{kennung}';
  public
    Base: TAtlasVcsGitBaseOption;
    /// <summary>vcs.branch.git.push = now: nach dem Anlegen pushen und verfolgen.</summary>
    PushNow: Boolean;
    Uncommitted: TAtlasVcsGitUncommitted;
    /// <summary>vcs.branch.git.worktree: Branch in eigenem Ordner (git worktree add).</summary>
    Worktree: Boolean;
    /// <summary>vcs.branch.git.worktreeFolder mit {repo}, {name}, {kennung}; relativ zur Wurzel der
    /// Arbeitskopie.</summary>
    WorktreeFolder: string;
    /// <summary>Verhalten vor #1289: lokaler Hauptbranch, beim ersten Push, mitnehmen, kein worktree.</summary>
    class function Classic: TAtlasVcsGitBranchOptions; static;
    /// <summary>Aus den Werten der Einstellungen ("remote"/"local"/"current", "later"/"now",
    /// "carry"/"stash"/"ask"); Unbekanntes gilt als Vorgabe des Schemas (remote, later, carry), ein leerer
    /// Ordner als DefaultWorktreeFolder.</summary>
    class function FromSettings(const ABase, APush, AUncommitted: string; AWorktree: Boolean;
      const AWorktreeFolder: string): TAtlasVcsGitBranchOptions; static;
  end;

  /// <summary>Git- und SVN-Vorgaben zusammen (für „Beginnen“ ohne Dialog): je nach Art der Arbeitskopie gilt die
  /// eine oder die andere Gruppe.</summary>
  TAtlasVcsBranchOptions = record
    Git: TAtlasVcsGitBranchOptions;
    Svn: TAtlasVcsSvnBranchOptions;
    class function Make(const AGit: TAtlasVcsGitBranchOptions;
      const ASvn: TAtlasVcsSvnBranchOptions): TAtlasVcsBranchOptions; static;
  end;

TAtlasVcsBranchBase = record
    Kind: TAtlasVcsBranchBaseKind;
    /// <summary>Git: Branch ohne "origin/" ('' = losgelöster HEAD); SVN: Pfad im Repository wie "trunk".
    /// </summary>
    Name: string;
    /// <summary>SVN: Revision der Quelle; '' = HEAD beim Kopieren. Git ''.</summary>
    Revision: string;
    /// <summary>Git (#1289): Remote für Basis, Abruf und Push; '' = origin.</summary>
    Remote: string;
    class function Make(AKind: TAtlasVcsBranchBaseKind; const AName, ARevision: string): TAtlasVcsBranchBase;
      overload; static;
    class function Make(AKind: TAtlasVcsBranchBaseKind; const AName, ARevision,
      ARemote: string): TAtlasVcsBranchBase; overload; static;
    /// <summary>Remote oder origin.</summary>
    function RemoteName: string;
  end;

  /// <summary>Was Atlas vor dem Anlegen über die Arbeitskopie weiß.</summary>
  TAtlasVcsBranchFacts = record
    Kind: TAtlasVcsKind;
    /// <summary>Ergebnis von Inspect; ungleich Ok: keine Basen.</summary>
    Outcome: TAtlasVcsOutcome;
    /// <summary>Git: aktueller Branch ('' = losgelöst); SVN: voller Pfad der Arbeitskopie im Repository wie
    /// "Kasse/trunk".</summary>
    Current: string;
    /// <summary>SVN: Revision der Arbeitskopie; Git ''.</summary>
    Revision: string;
    /// <summary>Hauptbranch: der erste der Kandidaten, den es gibt (Git lokal oder auf origin); SVN der erste
    /// Kandidat. '' = keiner.</summary>
    MainBranch: string;
    LocalMain: Boolean;
    RemoteMain: Boolean;
    /// <summary>SVN: Revision von ^/&lt;MainBranch&gt; auf dem Server (InspectServer); '' = unbekannt.</summary>
    HeadRevision: string;
    /// <summary>InspectServer ist gelaufen (mit ServerOutcome).</summary>
    ServerChecked: Boolean;
    ServerOutcome: TAtlasVcsOutcome;
    /// <summary>SVN: die Arbeitskopie hat svn:externals.</summary>
    Externals: Boolean;
    /// <summary>Wurzel der Arbeitskopie (AVcs.WorkingCopy.Root); '' ohne. Git (#1289): Bezug für den
    /// worktree-Ordner.</summary>
    Root: string;
    /// <summary>Git (#1289): Remote des lokalen Hauptbranchs (verfolgter Branch), sonst origin.</summary>
    Remote: string;
    /// <summary>Geänderte Dateien der Arbeitskopie (ohne unversionierte); setzt der Aufrufer, Inspect nicht.
    /// </summary>
    LocalChanges: Integer;
    /// <summary>SVN (#1290): Projektwurzel im Repository ohne "^/" ('' = Wurzel des Repositorys), gültig mit
    /// LayoutKnown; ohne erkennbares Layout (kein trunk, branches/&lt;x&gt;, tags/&lt;x&gt;) False.</summary>
    ProjectRoot: string;
    LayoutKnown: Boolean;
    /// <summary>SVN (#1290): Arbeitskopie hat mehrere Revisionen (svnversion mit ":"); Revision ist die höchste.
    /// </summary>
    MixedRevision: Boolean;
    /// <summary>SVN (#1291): Zeilen aus svn:externals mit Zustand, die Definitionen je Ordner (zum Umschreiben),
    /// die URL der Wurzel des Repositorys und die Version von svn ('' unbekannt).</summary>
    SvnExternals: TArray<TAtlasVcsSvnExternal>;
    SvnDefinitions: TArray<TAtlasVcsSvnExternalDefinition>;
    RepositoryRoot: string;
    SvnVersion: string;
    class function Empty: TAtlasVcsBranchFacts; static;
    /// <summary>Werte vom Server noch nötig: SVN, bevor InspectServer gelaufen ist.</summary>
    function NeedsServer: Boolean;
  end;

  /// <summary>Was angelegt werden soll; im Dialog änderbar.</summary>
  TAtlasVcsBranchRequest = record
    Kind: TAtlasVcsKind;
    Name: string;
    Base: TAtlasVcsBranchBase;
    /// <summary>SVN: Nachricht für svn copy; '' = "Branch &lt;Name&gt;".</summary>
    Message: string;
    /// <summary>SVN (#1290): Ort des Branchs im Repository ohne "^/"; Make setzt "branches/&lt;Name&gt;" (wie vor
    /// #1290), ApplySvn den Ort aus den Optionen. '' = kein Ort, keine Schritte.</summary>
    Location: string;
    /// <summary>SVN (#1290): was nach der Kopie passiert; Make setzt Switch.</summary>
    After: TAtlasVcsSvnAfter;
    /// <summary>SVN (#1290): vollständiger Ordner für After = Checkout; sonst ''.</summary>
    CheckoutFolder: string;
    /// <summary>SVN (#1291): Externals aus den Fakten, je External die Wahl und bei Branch der Ort des Packages
    /// (ohne "^/"); dazu Definitionen, Wurzel des Repositorys und Version von svn aus den Fakten. Make setzt
    /// alles leer (Externals unverändert wie vor #1291).</summary>
    Externals: TArray<TAtlasVcsSvnExternal>;
    ExternalActions: TArray<TAtlasVcsExternalAction>;
    ExternalLocations: TArray<string>;
    Definitions: TArray<TAtlasVcsSvnExternalDefinition>;
    RepositoryRoot: string;
    SvnVersion: string;
    /// <summary>SVN (#1291): Arbeitsordner für das Umschreiben der Externals ('' = keiner nötig bzw. keiner da).
    /// </summary>
    WorkFolder: string;
    /// <summary>Git (#1289): vorher fetch &lt;Remote&gt; &lt;Hauptbranch&gt;; nur mit Basis RemoteMain.</summary>
    Fetch: Boolean;
    /// <summary>Git: danach push --set-upstream.</summary>
    PushNow: Boolean;
    /// <summary>Git: vorher stash push --include-untracked (nicht mit worktree).</summary>
    Stash: Boolean;
    /// <summary>Git: vollständiger Ordner für git worktree add; '' = in dieser Arbeitskopie umschalten.</summary>
    WorktreeFolder: string;
    class function Make(AKind: TAtlasVcsKind; const AName: string; const ABase: TAtlasVcsBranchBase;
      const AMessage: string): TAtlasVcsBranchRequest; static;
  end;

  /// <summary>Ergebnis der Ausführung.</summary>
  TAtlasVcsBranchRun = record
    Outcome: TAtlasVcsOutcome;
    /// <summary>So viele Schritte sind fertig.</summary>
    Done: Integer;
    /// <summary>Index des gescheiterten Schritts; -1 ohne.</summary>
    Failed: Integer;
    function Succeeded: Boolean;
  end;

  /// <summary>Fortschritt: Schritt AIndex (ab 0) von ACount beginnt (aus dem Hintergrund-Thread).</summary>
  TAtlasVcsBranchProgress = reference to procedure(AIndex, ACount: Integer; const AStep: TAtlasVcsBranchStep);

  TAtlasVcsBranchPlan = class
  public
    /// <summary>Lokaler Stand für den Plan (ohne Server): aktueller Branch bzw. Pfad und Revision, Hauptbranch
    /// aus ACandidates (Git: der erste, den es lokal oder auf origin gibt), SVN svn:externals. Ohne Git oder
    /// SVN Outcome NoWorkingCopy.</summary>
    class function Inspect(const AVcs: IAtlasVersionControl; const ACandidates: TArray<string>)
      : TAtlasVcsBranchFacts; static;
    /// <summary>SVN: HEAD-Revision des Hauptbranchs vom Server (für die Anzeige und die Kopie genau dieser
    /// Revision). Git: nichts zu tun.</summary>
    class procedure InspectServer(const AVcs: IAtlasVersionControl; var AFacts: TAtlasVcsBranchFacts); static;
    /// <summary>Basen zur Wahl, in der Reihenfolge des Dialogs.</summary>
    class function Bases(const AFacts: TAtlasVcsBranchFacts): TArray<TAtlasVcsBranchBase>; static;
    /// <summary>Vorgabe: Git der lokale Hauptbranch, sonst origin; SVN Hauptbranch @ HEAD. False ohne
    /// Hauptbranch (nie stillschweigend der aktuelle Branch).</summary>
    class function DefaultBase(const AFacts: TAtlasVcsBranchFacts; out ABase: TAtlasVcsBranchBase): Boolean;
      overload; static;
    /// <summary>Wie oben; SVN mit ASource = WorkingCopy: Arbeitskopie @ Revision vor dem Hauptbranch (#1290).
    /// </summary>
    class function DefaultBase(const AFacts: TAtlasVcsBranchFacts; ASource: TAtlasVcsSvnSource;
      out ABase: TAtlasVcsBranchBase): Boolean; overload; static;
    /// <summary>Vorgabe nach den Git-Optionen (#1289): remote origin vor lokal, local wie oben, current der
    /// aktuelle Branch (sonst der lokale Hauptbranch). SVN wie oben.</summary>
    class function DefaultBase(const AFacts: TAtlasVcsBranchFacts; const AOptions: TAtlasVcsGitBranchOptions;
      out ABase: TAtlasVcsBranchBase): Boolean; overload; static;
    /// <summary>Anfrage mit der Vorgabe-Basis (für „Beginnen“ ohne Dialog); False ohne Basis.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Wie oben mit den SVN-Optionen (#1290): Basis nach Quelle, Ort, Danach und Ordner (ApplySvn).
    /// False auch, wenn sich der Ort nicht auflösen lässt.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      const ASvn: TAtlasVcsSvnBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Wie oben nach den Git-Optionen (#1289): Basis, Abruf (nur Basis vom Server), Push, stash (nur
    /// Stash; Ask entscheidet der Aufrufer) und worktree-Ordner (WorktreePath mit AKey).</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage, AKey: string;
      const AOptions: TAtlasVcsGitBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Wie oben mit Git- und SVN-Optionen: je nach Art der Arbeitskopie gilt die eine oder die andere
    /// Gruppe (für „Beginnen“ ohne Dialog).</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage, AKey: string;
      const AOptions: TAtlasVcsBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Ordner für git worktree (#1289): APattern ('' = Vorgabe) mit {repo} (Ordnername von ARoot),
    /// {name} (AName) und {kennung} (AKey, ohne Issue AName); relativ zu ARoot, vollständig. '' ohne ARoot.
    /// </summary>
    class function WorktreePath(const ARoot, APattern, AName, AKey: string): string; static;
    /// <summary>Ordner taugt für git worktree add: vollständig, keine Steuerzeichen, nicht mit „-“.</summary>
    class function SafeFolder(const AFolder: string): Boolean; static;
    /// <summary>AProject (unter ARoot) im worktree AFolder; '' wenn AProject nicht unter ARoot liegt.</summary>
    class function ProjectInFolder(const AProject, ARoot, AFolder: string): string; static;
    /// <summary>Anzahl lokaler Änderungen, die ein Wechsel des Branchs betrifft (ohne unversionierte Dateien).
    /// </summary>
    class function LocalChanges(const AChanges: TArray<TAtlasVcsChange>): Integer; static;
    /// <summary>Nachricht des Stashs vor dem Anlegen: "Atlas: vor &lt;Name&gt;".</summary>
    class function StashMessage(const AName: string): string; static;
    /// <summary>Der gescheiterte Schritt ist der Abruf vor dem Anlegen (noch nichts geändert).</summary>
    class function FetchFailed(const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun): Boolean;
      static;
    /// <summary>Nur der Push danach ist gescheitert: Der lokale Branch ist angelegt.</summary>
    class function OnlyPushFailed(const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): Boolean; static;
    /// <summary>Nach gescheitertem Abruf: dieselbe Anfrage ohne Abruf mit der Basis wie bei base = local
    /// (lokaler Hauptbranch, sonst der zuletzt abgerufene Stand).</summary>
    class function LocalFallback(const AFacts: TAtlasVcsBranchFacts;
      const ARequest: TAtlasVcsBranchRequest): TAtlasVcsBranchRequest; static;
    /// <summary>SVN (#1290): Ort aus ASvn für AName ohne "^/"; False ohne Layout bei {projektwurzel} oder bei
    /// ungültigem Muster.</summary>
    class function SvnLocation(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
      const AName: string; out APath: string): Boolean; static;
    /// <summary>SVN (#1290): Ordner für „frisch auschecken“ aus ASvn.CheckoutFolder relativ zur Arbeitskopie.
    /// </summary>
    class function SvnCheckoutFolder(const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
      const AName: string): string; static;
    /// <summary>SVN (#1290): Nachricht für svn copy aus ASvn.Message mit Kennung und Titel aus ASvn; ohne
    /// Kennung "Branch &lt;Name&gt;".</summary>
    class function SvnMessage(const ASvn: TAtlasVcsSvnBranchOptions; const AName: string): string; static;
    /// <summary>SVN (#1290): Ort, Danach und Ordner aus ASvn in ARequest (Name schon gesetzt); False (Ort '')
    /// ohne auflösbaren Ort. Git: nichts zu tun, True.</summary>
    class function ApplySvn(var ARequest: TAtlasVcsBranchRequest; const AFacts: TAtlasVcsBranchFacts;
      const ASvn: TAtlasVcsSvnBranchOptions): Boolean; static;
    /// <summary>SVN (#1291): Vorgabe je External aus den Regeln und vcs.externals.* (Ask = keine Vorauswahl).
    /// </summary>
    class function DefaultActions(const AFacts: TAtlasVcsBranchFacts;
      const ASvn: TAtlasVcsSvnBranchOptions): TArray<TAtlasVcsExternalAction>; static;
    /// <summary>SVN (#1291): Externals mit AActions in ARequest (Name schon gesetzt), Orte der mitverzweigten
    /// Packages und den Arbeitsordner. Git: nichts zu tun.</summary>
    class procedure ApplyExternals(var ARequest: TAtlasVcsBranchRequest; const AFacts: TAtlasVcsBranchFacts;
      const ASvn: TAtlasVcsSvnBranchOptions; const AActions: TArray<TAtlasVcsExternalAction>); static;
    /// <summary>SVN (#1291): Ort für das mitverzweigte Package AExternal (ohne "^/"): vcs.branch.svn.location
    /// unter der Projektwurzel des Packages ("Packages/Drucken/branches/&lt;Name&gt;"); ein Muster mit "^/" gilt für
    /// Packages wie die Vorgabe. False ohne Layout im Pfad des Packages.</summary>
    class function ExternalLocation(const AExternal: TAtlasVcsSvnExternal; const ASvn: TAtlasVcsSvnBranchOptions;
      const AName: string; out APath: string): Boolean; static;
    /// <summary>SVN (#1291): alle Externals ohne Revision werden mit svn copy --pin-externals festgeschrieben
    /// (alle Pin, keines mitverzweigt, svn ab 1.9).</summary>
    class function UsesPinExternals(const ARequest: TAtlasVcsBranchRequest): Boolean; static;
    /// <summary>SVN (#1291): die Anfrage ändert Externals (festschreiben oder mitverzweigen) und schaltet die
    /// Arbeitskopie um: danach den Index der Packages neu aufbauen.</summary>
    class function ChangesExternals(const ARequest: TAtlasVcsBranchRequest): Boolean; static;
    /// <summary>Text für die Auswahl im Dialog: Revision der External-Arbeitskopie bzw. feste Revision.</summary>
    class function ExternalRevision(const AExternal: TAtlasVcsSvnExternal): string; static;
    /// <summary>Name taugt für git und svn (nicht leer, keine Option, kein „..“, keine Leer- und Steuerzeichen).
    /// Die strengere Prüfung nach Git-Regeln macht der Dialog (TAtlasVcsBranchNames.Valid).</summary>
    class function SafeName(const AName: string): Boolean; static;
    /// <summary>Git: Startpunkt für checkout (refs/…); SVN: Quelle ^/&lt;Pfad&gt;@&lt;Revision&gt;.</summary>
    class function BaseRef(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string; static;
    /// <summary>Kurzname der Basis für Meldungen: "main", "origin/main", "trunk@48230".</summary>
    class function BaseName(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string; static;
    /// <summary>Schritte für ARequest; leer, wenn Name oder Basis nicht taugen.</summary>
    class function Steps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>; static;
    /// <summary>Befehlszeile zur Anzeige: "git checkout …" bzw. "svn copy …", Argumente mit Leerzeichen in
    /// Anführungszeichen.</summary>
    class function StepText(AKind: TAtlasVcsKind; const AStep: TAtlasVcsBranchStep): string; static;
    /// <summary>Schritte der Reihe nach ausführen, beim ersten Fehler aufhören.</summary>
    class function Execute(const ABranching: IAtlasVcsBranching;
      const ASteps: TArray<TAtlasVcsBranchStep>): TAtlasVcsBranchRun; overload; static;
    /// <summary>Wie oben; AProgress vor jedem Schritt (im Thread des Aufrufers).</summary>
    class function Execute(const ABranching: IAtlasVcsBranching; const ASteps: TArray<TAtlasVcsBranchStep>;
      const AProgress: TAtlasVcsBranchProgress): TAtlasVcsBranchRun; overload; static;
    /// <summary>Wie oben; löscht den Arbeitsordner von ARequest vorher (Rest eines abgebrochenen Laufs) und
    /// danach (#1291).</summary>
    class function Execute(const ABranching: IAtlasVcsBranching; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const AProgress: TAtlasVcsBranchProgress): TAtlasVcsBranchRun;
      overload; static;
    /// <summary>SVN „frisch auschecken“ (#1290): AFile (z. B. die .groupproj) unter ARoot an derselben Stelle
    /// unter AFolder; '' wenn AFile nicht unter ARoot liegt.</summary>
    class function CheckoutTarget(const ARoot, AFolder, AFile: string): string; static;
    /// <summary>Die ersten ADone Schritte, die den Server geändert haben (für die Meldung nach einem Fehler).
    /// </summary>
    class function ServerStepsDone(const ASteps: TArray<TAtlasVcsBranchStep>;
      ADone: Integer): TArray<TAtlasVcsBranchStep>; static;
  end;

  /// <summary>Regeln für SVN-Externals beim Anlegen eines Branchs (#1291): vcs.externals.rules als JSON und als
  /// Text der Einstellungsseite.</summary>
  TAtlasVcsExternalRules = class
  public
    /// <summary>Regeln aus vcs.externals.rules (JSON-Liste mit source und onBranch = pin, keep, branch). Einträge
    /// ohne Quelle, mit anderer Behandlung oder doppelter Quelle fallen weg.</summary>
    class function RulesOf(const AJson: string): TArray<TAtlasVcsExternalRule>; static;
    /// <summary>ARules als JSON-Liste für vcs.externals.rules; '[]' ohne Regeln.</summary>
    class function RulesJson(const ARules: TArray<TAtlasVcsExternalRule>): string; static;
    /// <summary>ARules als Text für die Einstellungsseite: eine Regel je Zeile „Quelle = Behandlung“.</summary>
    class function RulesText(const ARules: TArray<TAtlasVcsExternalRule>): string; static;
    /// <summary>Regeln aus dem Text der Einstellungsseite; leere Zeilen und Zeilen mit # zählen nicht. False mit
    /// der ersten ungültigen Zeile in AInvalid (ohne „=“, ohne Quelle, andere Behandlung als pin, keep, branch).
    /// Eine doppelte Quelle gilt einmal (die letzte Zeile gewinnt).</summary>
    class function RulesOfText(const AText: string; out ARules: TArray<TAtlasVcsExternalRule>;
      out AInvalid: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Vcs.Internals.SvnExternals,
  Atlas.Core.Vcs.Internals.SvnLayout,
  Atlas.Core.Vcs.Internals.Text;

const
  cDefaultRemote = 'origin';

{ TAtlasVcsGitBranchOptions }

class function TAtlasVcsGitBranchOptions.Classic: TAtlasVcsGitBranchOptions;
begin
  Result.Base := TAtlasVcsGitBaseOption.Local;
  Result.PushNow := False;
  Result.Uncommitted := TAtlasVcsGitUncommitted.Carry;
  Result.Worktree := False;
  Result.WorktreeFolder := DefaultWorktreeFolder;
end;

class function TAtlasVcsGitBranchOptions.FromSettings(const ABase, APush, AUncommitted: string; AWorktree: Boolean;
  const AWorktreeFolder: string): TAtlasVcsGitBranchOptions;
begin
  Result.Base := TAtlasVcsGitBaseOption.Remote;
  if SameText(Trim(ABase), 'local') then
  begin
    Result.Base := TAtlasVcsGitBaseOption.Local;
  end
  else if SameText(Trim(ABase), 'current') then
  begin
    Result.Base := TAtlasVcsGitBaseOption.Current;
  end;
  Result.PushNow := SameText(Trim(APush), 'now');
  Result.Uncommitted := TAtlasVcsGitUncommitted.Carry;
  if SameText(Trim(AUncommitted), 'stash') then
  begin
    Result.Uncommitted := TAtlasVcsGitUncommitted.Stash;
  end
  else if SameText(Trim(AUncommitted), 'ask') then
  begin
    Result.Uncommitted := TAtlasVcsGitUncommitted.Ask;
  end;
  Result.Worktree := AWorktree;
  Result.WorktreeFolder := Trim(AWorktreeFolder);
  if Result.WorktreeFolder = '' then
  begin
    Result.WorktreeFolder := DefaultWorktreeFolder;
  end;
end;

{ TAtlasVcsBranchOptions }

class function TAtlasVcsBranchOptions.Make(const AGit: TAtlasVcsGitBranchOptions;
  const ASvn: TAtlasVcsSvnBranchOptions): TAtlasVcsBranchOptions;
begin
  Result.Git := AGit;
  Result.Svn := ASvn;
end;

{ TAtlasVcsBranchBase }

class function TAtlasVcsBranchBase.Make(AKind: TAtlasVcsBranchBaseKind; const AName,
  ARevision: string): TAtlasVcsBranchBase;
begin
  Result := Make(AKind, AName, ARevision, '');
end;

class function TAtlasVcsBranchBase.Make(AKind: TAtlasVcsBranchBaseKind; const AName, ARevision,
  ARemote: string): TAtlasVcsBranchBase;
begin
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Revision := ARevision;
  Result.Remote := ARemote;
end;

function TAtlasVcsBranchBase.RemoteName: string;
begin
  Result := Remote;
  if Result = '' then
  begin
    Result := cDefaultRemote;
  end;
end;

{ TAtlasVcsBranchFacts }

class function TAtlasVcsBranchFacts.Empty: TAtlasVcsBranchFacts;
begin
  Result.Kind := TAtlasVcsKind.None;
  Result.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
  Result.Current := '';
  Result.Revision := '';
  Result.MainBranch := '';
  Result.LocalMain := False;
  Result.RemoteMain := False;
  Result.HeadRevision := '';
  Result.ServerChecked := False;
  Result.ServerOutcome := TAtlasVcsOutcome.Ok;
  Result.Externals := False;
  Result.Root := '';
  Result.Remote := '';
  Result.LocalChanges := 0;
  Result.ProjectRoot := '';
  Result.LayoutKnown := False;
  Result.MixedRevision := False;
  Result.SvnExternals := nil;
  Result.SvnDefinitions := nil;
  Result.RepositoryRoot := '';
  Result.SvnVersion := '';
end;

function TAtlasVcsBranchFacts.NeedsServer: Boolean;
begin
  Result := (Kind = TAtlasVcsKind.Svn) and (Outcome = TAtlasVcsOutcome.Ok) and not ServerChecked;
end;

{ TAtlasVcsBranchRequest }

class function TAtlasVcsBranchRequest.Make(AKind: TAtlasVcsKind; const AName: string;
  const ABase: TAtlasVcsBranchBase; const AMessage: string): TAtlasVcsBranchRequest;
begin
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Base := ABase;
  Result.Message := AMessage;
  Result.Location := 'branches/' + AName;
  Result.After := TAtlasVcsSvnAfter.Switch;
  Result.CheckoutFolder := '';
  Result.Externals := nil;
  Result.ExternalActions := nil;
  Result.ExternalLocations := nil;
  Result.Definitions := nil;
  Result.RepositoryRoot := '';
  Result.SvnVersion := '';
  Result.WorkFolder := '';
  Result.Fetch := False;
  Result.PushNow := False;
  Result.Stash := False;
  Result.WorktreeFolder := '';
end;

{ TAtlasVcsBranchRun }

function TAtlasVcsBranchRun.Succeeded: Boolean;
begin
  Result := (Outcome = TAtlasVcsOutcome.Ok) and (Failed < 0);
end;

{ TAtlasVcsBranchPlan }

/// <summary>svn:externals der Arbeitskopie mit Zustand jeder External-Arbeitskopie (#1291).</summary>
procedure InspectExternals(const ASvn: IAtlasVcsSvnWorkingCopy; var AFacts: TAtlasVcsBranchFacts);
var
  mXml, mRepository, mVersion, mText, mRevision, mPath: string;
  mIndex: Integer;
  mMixed, mModified: Boolean;
begin
  if ASvn.ToolVersion(mVersion) = TAtlasVcsOutcome.Ok then
  begin
    AFacts.SvnVersion := mVersion;
  end;
  if (ASvn.ExternalsXml(mXml) <> TAtlasVcsOutcome.Ok) or (ASvn.RepositoryRoot(mRepository) <> TAtlasVcsOutcome.Ok) or
    (mRepository = '') then
  begin
    Exit;
  end;
  try
    AFacts.SvnDefinitions := TAtlasSvnExternals.Definitions(mXml, AFacts.Root);
  except
    on EAtlasVcsParse do
      Exit;
  end;
  AFacts.RepositoryRoot := mRepository;
  AFacts.SvnExternals := TAtlasSvnExternals.ParseAll(AFacts.SvnDefinitions, mRepository + '/' +
    StringReplace(AFacts.Current, ' ', '%20', [rfReplaceAll]), mRepository);
  for mIndex := 0 to High(AFacts.SvnExternals) do
  begin
    mPath := VcsFullPath(AFacts.Root, AFacts.SvnExternals[mIndex].Path);
    AFacts.SvnExternals[mIndex].IsFile := FileExists(mPath) and not DirectoryExists(mPath);
    if (ASvn.WorkingRevisions(AFacts.SvnExternals[mIndex].Path, mText) = TAtlasVcsOutcome.Ok) and
      TAtlasSvnExternals.VersionState(mText, mRevision, mMixed, mModified) then
    begin
      AFacts.SvnExternals[mIndex].WorkingRevision := mRevision;
      AFacts.SvnExternals[mIndex].Modified := mModified;
    end;
  end;
  AFacts.Externals := Length(AFacts.SvnExternals) > 0;
end;

/// <summary>Git: Remote des lokalen Hauptbranchs; liegt der Hauptbranch dort, RemoteMain.</summary>
procedure InspectRemote(const AVcs: IAtlasVersionControl;
  var AFacts: TAtlasVcsBranchFacts);
var
  mLocalWork: IAtlasVcsLocalWork;
  mIncoming: IAtlasVcsIncoming;
  mBranches: TArray<TAtlasVcsBranch>;
  mBranch: TAtlasVcsBranch;
  mRevision: string;
begin
  AFacts.Remote := cDefaultRemote;
  // Nur ein Hinweis für Abruf und Push: Fehler hier lassen origin stehen.
  if not AFacts.LocalMain or not Supports(AVcs, IAtlasVcsLocalWork, mLocalWork) or
    (mLocalWork.Branches(mBranches) <> TAtlasVcsOutcome.Ok) then
  begin
    Exit;
  end;
  for mBranch in mBranches do
  begin
    if (mBranch.Name = AFacts.MainBranch) and TAtlasVcsBranchPlan.SafeName(mBranch.Remote) then
    begin
      AFacts.Remote := mBranch.Remote;
    end;
  end;
  // RemoteBranchExists kennt nur origin: bei einem anderen Remote dessen Stand des letzten Abrufs.
  if (AFacts.Remote <> cDefaultRemote) and Supports(AVcs, IAtlasVcsIncoming, mIncoming) then
  begin
    AFacts.RemoteMain := mIncoming.Resolve('refs/remotes/' + AFacts.Remote + '/' + AFacts.MainBranch,
      mRevision) = TAtlasVcsOutcome.Ok;
  end;
end;

function GitSteps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mRemote: string;
begin
  Result := nil;
  mRemote := ARequest.Base.RemoteName;
  // Basis ist ein Branch-Name aus Inspect; losgelöster HEAD hat keinen.
  if ((ARequest.Base.Name <> '') and not TAtlasVcsBranchPlan.SafeName(ARequest.Base.Name)) or
    not TAtlasVcsBranchPlan.SafeName(mRemote) then
  begin
    Exit;
  end;
  if (ARequest.WorktreeFolder <> '') and not TAtlasVcsBranchPlan.SafeFolder(ARequest.WorktreeFolder) then
  begin
    Exit;
  end;
  // Basis vom Server (#1289): vorher genau den Hauptbranch abrufen; ohne Rückfrage nach Zugangsdaten.
  if ARequest.Fetch and (ARequest.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain) then
  begin
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('fetch', '--quiet', '--no-tags', mRemote,
      ARequest.Base.Name), True, False)];
  end;
  // --no-track: der neue Branch verfolgt nicht die Basis; den Upstream setzt erst der (erste) Push.
  if ARequest.WorktreeFolder <> '' then
  begin
    // Eigener Ordner: die Arbeitskopie bleibt, wie sie ist; offene Änderungen bleiben dort.
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('worktree', 'add', '--quiet', '--no-track',
      '-b', ARequest.Name, ARequest.WorktreeFolder, TAtlasVcsBranchPlan.BaseRef(TAtlasVcsKind.Git, ARequest.Base)),
        False, False)];
  end
  else
  begin
    if ARequest.Stash then
    begin
      Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('stash', 'push', '--include-untracked',
        '--quiet', '-m', TAtlasVcsBranchPlan.StashMessage(ARequest.Name)), False, False)];
    end;
    // "--" am Ende: der Startpunkt ist eine Revision, nie ein Dateiname.
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '--quiet', '--no-track', '-b',
      ARequest.Name, TAtlasVcsBranchPlan.BaseRef(TAtlasVcsKind.Git, ARequest.Base), '--'), False, False)];
  end;
  if ARequest.PushNow then
  begin
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('push', '--set-upstream', mRemote,
      'refs/heads/' + ARequest.Name + ':refs/heads/' + ARequest.Name), True, True)];
  end;
end;

/// <summary>Platzhalterwert für einen Ordnernamen: Trenner und unter Windows verbotene Zeichen werden „-“.
/// </summary>
function FolderPart(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(AText);
  for mIndex := 1 to Length(Result) do
  begin
    if (Ord(Result[mIndex]) < 32) or CharInSet(Result[mIndex], ['/', '\', ':', '*', '?', '"', '<', '>', '|']) then
    begin
      Result[mIndex] := '-';
    end;
  end;
end;

/// <summary>Vorgabe-Basis: Git nach AGit, SVN nach ASource.</summary>
function PreferredBase(const AFacts: TAtlasVcsBranchFacts;
  const AGit: TAtlasVcsGitBranchOptions; ASource: TAtlasVcsSvnSource; out ABase: TAtlasVcsBranchBase): Boolean;
var
  mBase: TAtlasVcsBranchBase;
  mBases: TArray<TAtlasVcsBranchBase>;
  mPreferred: TArray<TAtlasVcsBranchBaseKind>;
  mKind: TAtlasVcsBranchBaseKind;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  mBases := TAtlasVcsBranchPlan.Bases(AFacts);
  if AFacts.Kind = TAtlasVcsKind.Svn then
  begin
    // SVN der Hauptbranch, mit vcs.branch.svn.source = workingCopy die Arbeitskopie (#1290).
    if ASource = TAtlasVcsSvnSource.WorkingCopy then
    begin
      mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.WorkingCopy,
        TAtlasVcsBranchBaseKind.Head);
    end
    else
    begin
      mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.Head);
    end;
  end
  else
    case AGit.Base of
      TAtlasVcsGitBaseOption.Remote:
        mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.RemoteMain,
          TAtlasVcsBranchBaseKind.LocalMain);
      // Der aktuelle Branch ausdrücklich gewählt; steht er schon als lokaler Hauptbranch da, dieser.
      TAtlasVcsGitBaseOption.Current:
        mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.Current,
          TAtlasVcsBranchBaseKind.LocalMain);
    else
      // Wie „Beginnen“ bisher (#765): lokal vor origin.
      mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.LocalMain,
        TAtlasVcsBranchBaseKind.RemoteMain);
    end;
  for mKind in mPreferred do
  begin
    for mBase in mBases do
    begin
      if mBase.Kind = mKind then
      begin
        ABase := mBase;
        Exit(True);
      end;
    end;
  end;
  // Ohne Hauptbranch keine Vorgabe: wie bisher bei „Beginnen“ scheitern statt still vom aktuellen Branch
  // abzuzweigen.
  Result := False;
end;

/// <summary>SVN: höchste Revision einer gemischten Arbeitskopie (#1290), der Dialog warnt; ohne svnversion bleibt
/// die der Wurzel.</summary>
procedure InspectSvnRevision(const ASvn: IAtlasVcsSvnWorkingCopy; var AFacts: TAtlasVcsBranchFacts);
var
  mText, mRevision: string;
  mMixed: Boolean;
begin
  if (ASvn <> nil) and (ASvn.WorkingRevisions(mText) = TAtlasVcsOutcome.Ok) and
    TAtlasSvnLayout.WorkingRevision(mText, mRevision, mMixed) then
  begin
    AFacts.Revision := mRevision;
    AFacts.MixedRevision := mMixed;
  end;
end;

/// <summary>SVN: Hauptbranch aus ACandidates; "trunk" liegt unter der Projektwurzel ("Kasse/trunk"), nicht an der
/// Wurzel des Repositorys.</summary>
procedure InspectSvnMain(const ACandidates: TArray<string>; var AFacts: TAtlasVcsBranchFacts);
var
  mCandidate, mPath: string;
begin
  for mCandidate in ACandidates do
  begin
    mPath := TAtlasSvnLayout.MainPath(mCandidate, AFacts.LayoutKnown, AFacts.ProjectRoot);
    if TAtlasVcsBranchPlan.SafeName(mPath) then
    begin
      AFacts.MainBranch := mPath;
      Break;
    end;
  end;
end;

procedure InspectSvn(const AVcs: IAtlasVersionControl; const ABranching: IAtlasVcsBranching;
  const ACandidates: TArray<string>; const AHead: TAtlasVcsHead; var AFacts: TAtlasVcsBranchFacts);
var
  mSvn: IAtlasVcsSvnWorkingCopy;
  mPath: string;
begin
  AFacts.Revision := AHead.Revision;
  // Voller Pfad ("Kasse/trunk"): Head.Branch kürzt auf "trunk", die Kopie braucht den ganzen. Aus ihm die
  // Projektwurzel für Ort und Hauptbranch (#1290).
  if (ABranching.RepositoryPath(mPath) = TAtlasVcsOutcome.Ok) and (mPath <> '') then
  begin
    AFacts.Current := mPath;
    AFacts.LayoutKnown := TAtlasSvnLayout.ProjectRoot(mPath, AFacts.ProjectRoot);
  end;
  if not Supports(AVcs, IAtlasVcsSvnWorkingCopy, mSvn) then
  begin
    mSvn := nil;
  end;
  InspectSvnRevision(mSvn, AFacts);
  InspectSvnMain(ACandidates, AFacts);
  // Externals (#1291): Zeilen samt Zustand; ein Fehler hier hält das Anlegen nicht auf (Externals bleiben dann,
  // wie sie sind).
  if mSvn <> nil then
  begin
    InspectExternals(mSvn, AFacts);
  end;
  if (Length(AFacts.SvnExternals) = 0) and (ABranching.HasExternals(AFacts.Externals) <> TAtlasVcsOutcome.Ok) then
  begin
    AFacts.Externals := False;
  end;
end;

/// <summary>Git: der erste Kandidat, den es lokal oder auf origin gibt, als Hauptbranch; danach sein Remote.
/// </summary>
procedure InspectGit(const AVcs: IAtlasVersionControl; const ABranching: IAtlasVcsBranching;
  const ACandidates: TArray<string>; var AFacts: TAtlasVcsBranchFacts);
var
  mCandidate: string;
  mLocal, mRemote: Boolean;
begin
  for mCandidate in ACandidates do
  begin
    if not TAtlasVcsBranchPlan.SafeName(mCandidate) then
    begin
      Continue;
    end;
    AFacts.Outcome := ABranching.BranchExists(mCandidate, mLocal);
    if AFacts.Outcome = TAtlasVcsOutcome.Ok then
    begin
      AFacts.Outcome := ABranching.RemoteBranchExists(mCandidate, mRemote);
    end;
    if AFacts.Outcome <> TAtlasVcsOutcome.Ok then
    begin
      Exit;
    end;
    if mLocal or mRemote then
    begin
      AFacts.MainBranch := mCandidate;
      AFacts.LocalMain := mLocal;
      AFacts.RemoteMain := mRemote;
      Break;
    end;
  end;
  InspectRemote(AVcs, AFacts);
end;

class function TAtlasVcsBranchPlan.Inspect(const AVcs: IAtlasVersionControl;
  const ACandidates: TArray<string>): TAtlasVcsBranchFacts;
var
  mBranching: IAtlasVcsBranching;
  mHead: TAtlasVcsHead;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsBranching, mBranching) then
  begin
    Exit;
  end;
  Result.Kind := AVcs.Kind;
  if not (Result.Kind in [TAtlasVcsKind.Git, TAtlasVcsKind.Svn]) then
  begin
    Exit;
  end;
  Result.Outcome := AVcs.Head(mHead);
  if Result.Outcome <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  Result.Root := AVcs.WorkingCopy.Root;
  Result.Current := mHead.Branch;
  if Result.Kind = TAtlasVcsKind.Svn then
  begin
    InspectSvn(AVcs, mBranching, ACandidates, mHead, Result);
  end
  else
  begin
    InspectGit(AVcs, mBranching, ACandidates, Result);
  end;
end;

class procedure TAtlasVcsBranchPlan.InspectServer(const AVcs: IAtlasVersionControl;
  var AFacts: TAtlasVcsBranchFacts);
var
  mBranching: IAtlasVcsBranching;
  mRevision: string;
begin
  AFacts.ServerChecked := True;
  AFacts.ServerOutcome := TAtlasVcsOutcome.Ok;
  if (AFacts.Kind <> TAtlasVcsKind.Svn) or (AFacts.Outcome <> TAtlasVcsOutcome.Ok) or (AFacts.MainBranch = '') then
  begin
    Exit;
  end;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsBranching, mBranching) then
  begin
    AFacts.ServerOutcome := TAtlasVcsOutcome.NoWorkingCopy;
    Exit;
  end;
  AFacts.ServerOutcome := mBranching.ServerRevision(AFacts.MainBranch, mRevision);
  if AFacts.ServerOutcome = TAtlasVcsOutcome.Ok then
  begin
    AFacts.HeadRevision := mRevision;
  end;
end;

class function TAtlasVcsBranchPlan.Bases(const AFacts: TAtlasVcsBranchFacts): TArray<TAtlasVcsBranchBase>;
begin
  Result := nil;
  if AFacts.Outcome <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  if AFacts.Kind = TAtlasVcsKind.Git then
  begin
    // Remote an jeder Basis: Abruf und Push gehen an den Remote des Hauptbranchs.
    if AFacts.RemoteMain then
    begin
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, AFacts.MainBranch, '',
        AFacts.Remote)];
    end;
    if AFacts.LocalMain then
    begin
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, AFacts.MainBranch, '',
        AFacts.Remote)];
    end;
    // Der aktuelle Branch nur, wenn er nicht schon als lokaler Hauptbranch dasteht.
    if not AFacts.LocalMain or (AFacts.Current <> AFacts.MainBranch) then
    begin
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, AFacts.Current, '',
        AFacts.Remote)];
    end;
  end
  else if AFacts.Kind = TAtlasVcsKind.Svn then
  begin
    if AFacts.MainBranch <> '' then
    begin
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Head, AFacts.MainBranch,
        AFacts.HeadRevision)];
    end;
    if (AFacts.Current <> '') and (AFacts.Revision <> '') then
    begin
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.WorkingCopy, AFacts.Current,
        AFacts.Revision)];
    end;
  end;
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts;
  out ABase: TAtlasVcsBranchBase): Boolean;
begin
  // Wie „Beginnen“ bisher (#765): lokal vor origin; SVN der Hauptbranch.
  Result := PreferredBase(AFacts, TAtlasVcsGitBranchOptions.Classic, TAtlasVcsSvnSource.Head, ABase);
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts; ASource: TAtlasVcsSvnSource;
  out ABase: TAtlasVcsBranchBase): Boolean;
begin
  Result := PreferredBase(AFacts, TAtlasVcsGitBranchOptions.Classic, ASource, ABase);
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts;
  const AOptions: TAtlasVcsGitBranchOptions; out ABase: TAtlasVcsBranchBase): Boolean;
begin
  Result := PreferredBase(AFacts, AOptions, TAtlasVcsSvnSource.Head, ABase);
end;

class function TAtlasVcsBranchPlan.DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage: string; out ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mBase: TAtlasVcsBranchBase;
begin
  Result := DefaultBase(AFacts, mBase);
  ARequest := TAtlasVcsBranchRequest.Make(AFacts.Kind, AName, mBase, AMessage);
end;

class function TAtlasVcsBranchPlan.DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage: string; const ASvn: TAtlasVcsSvnBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean;
begin
  Result := DefaultRequest(AFacts, AName, AMessage, '', TAtlasVcsBranchOptions.Make(TAtlasVcsGitBranchOptions.Classic,
    ASvn), ARequest);
end;

class function TAtlasVcsBranchPlan.DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
  AKey: string; const AOptions: TAtlasVcsGitBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean;
begin
  Result := DefaultRequest(AFacts, AName, AMessage, AKey, TAtlasVcsBranchOptions.Make(AOptions,
    TAtlasVcsSvnBranchOptions.Default), ARequest);
end;

/// <summary>Git (#1289): Abruf, Push, worktree-Ordner bzw. Stash aus AGit in ARequest.</summary>
procedure ApplyGit(var ARequest: TAtlasVcsBranchRequest; const AFacts: TAtlasVcsBranchFacts;
  const AGit: TAtlasVcsGitBranchOptions; const AKey: string);
begin
  ARequest.Fetch := (AGit.Base = TAtlasVcsGitBaseOption.Remote) and
    (ARequest.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  ARequest.PushNow := AGit.PushNow;
  if AGit.Worktree then
  begin
    ARequest.WorktreeFolder := TAtlasVcsBranchPlan.WorktreePath(AFacts.Root, AGit.WorktreeFolder, ARequest.Name,
      AKey);
  end
  else
  begin
    ARequest.Stash := AGit.Uncommitted = TAtlasVcsGitUncommitted.Stash;
  end;
end;

/// <summary>Ist für jedes External eine Behandlung gewählt (keine Ask)?</summary>
function ActionsChosen(const AActions: TArray<TAtlasVcsExternalAction>): Boolean;
var
  mAction: TAtlasVcsExternalAction;
begin
  for mAction in AActions do
  begin
    if mAction = TAtlasVcsExternalAction.Ask then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TAtlasVcsBranchPlan.DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
  AKey: string; const AOptions: TAtlasVcsBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mBase: TAtlasVcsBranchBase;
begin
  Result := PreferredBase(AFacts, AOptions.Git, AOptions.Svn.Source, mBase);
  ARequest := TAtlasVcsBranchRequest.Make(AFacts.Kind, AName, mBase, AMessage);
  if AFacts.Kind = TAtlasVcsKind.Git then
  begin
    ApplyGit(ARequest, AFacts, AOptions.Git, AKey);
    Exit;
  end;
  // vcs.externals.onBranch = ask: ohne Dialog gibt es keine Wahl (#1291).
  Result := ApplySvn(ARequest, AFacts, AOptions.Svn) and Result and ActionsChosen(ARequest.ExternalActions);
end;

class function TAtlasVcsBranchPlan.SvnLocation(const AFacts: TAtlasVcsBranchFacts;
  const ASvn: TAtlasVcsSvnBranchOptions; const AName: string; out APath: string): Boolean;
begin
  Result := TAtlasSvnLayout.Resolve(ASvn.Location, AFacts.LayoutKnown, AFacts.ProjectRoot, AName, ASvn.Key, APath);
end;

class function TAtlasVcsBranchPlan.SvnCheckoutFolder(const AFacts: TAtlasVcsBranchFacts;
  const ASvn: TAtlasVcsSvnBranchOptions; const AName: string): string;
begin
  Result := TAtlasSvnLayout.CheckoutFolder(ASvn.CheckoutFolder, AFacts.Root, ASvn.Project, AName, ASvn.Key);
end;

class function TAtlasVcsBranchPlan.SvnMessage(const ASvn: TAtlasVcsSvnBranchOptions; const AName: string): string;
begin
  Result := TAtlasSvnLayout.MessageText(ASvn.Message, ASvn.Key, ASvn.Title, AName);
end;

class function TAtlasVcsBranchPlan.ApplySvn(var ARequest: TAtlasVcsBranchRequest;
  const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions): Boolean;
var
  mPath: string;
begin
  Result := True;
  if ARequest.Kind <> TAtlasVcsKind.Svn then
  begin
    Exit;
  end;
  Result := SvnLocation(AFacts, ASvn, ARequest.Name, mPath);
  ARequest.Location := mPath;
  ARequest.After := ASvn.After;
  ARequest.CheckoutFolder := '';
  if ASvn.After = TAtlasVcsSvnAfter.Checkout then
  begin
    ARequest.CheckoutFolder := SvnCheckoutFolder(AFacts, ASvn, ARequest.Name);
  end;
  ApplyExternals(ARequest, AFacts, ASvn, DefaultActions(AFacts, ASvn));
end;

class function TAtlasVcsBranchPlan.DefaultActions(const AFacts: TAtlasVcsBranchFacts;
  const ASvn: TAtlasVcsSvnBranchOptions): TArray<TAtlasVcsExternalAction>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFacts.SvnExternals));
  for mIndex := 0 to High(AFacts.SvnExternals) do
  begin
    Result[mIndex] := TAtlasSvnExternals.DefaultAction(AFacts.SvnExternals[mIndex], ASvn);
  end;
end;

class procedure TAtlasVcsBranchPlan.ApplyExternals(var ARequest: TAtlasVcsBranchRequest;
  const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
  const AActions: TArray<TAtlasVcsExternalAction>);
var
  mIndex: Integer;
  mPath, mFolder: string;
begin
  if ARequest.Kind <> TAtlasVcsKind.Svn then
  begin
    Exit;
  end;
  ARequest.Externals := AFacts.SvnExternals;
  ARequest.Definitions := AFacts.SvnDefinitions;
  ARequest.RepositoryRoot := AFacts.RepositoryRoot;
  ARequest.SvnVersion := AFacts.SvnVersion;
  SetLength(ARequest.ExternalActions, Length(ARequest.Externals));
  SetLength(ARequest.ExternalLocations, Length(ARequest.Externals));
  for mIndex := 0 to High(ARequest.Externals) do
  begin
    ARequest.ExternalActions[mIndex] := TAtlasVcsExternalAction.Keep;
    if mIndex <= High(AActions) then
    begin
      ARequest.ExternalActions[mIndex] := AActions[mIndex];
    end;
    ARequest.ExternalLocations[mIndex] := '';
    if (ARequest.ExternalActions[mIndex] = TAtlasVcsExternalAction.Branch) and
      ExternalLocation(ARequest.Externals[mIndex], ASvn, ARequest.Name, mPath) then
    begin
      ARequest.ExternalLocations[mIndex] := mPath;
    end;
  end;
  // Arbeitsordner je Branch-Name: ein Rest eines abgebrochenen Laufs wird vor dem Ausführen gelöscht.
  mFolder := StringReplace(StringReplace(ARequest.Name, '/', '-', [rfReplaceAll]), '\', '-', [rfReplaceAll]);
  ARequest.WorkFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-Branch-' + mFolder);
end;

class function TAtlasVcsBranchPlan.ExternalLocation(const AExternal: TAtlasVcsSvnExternal;
  const ASvn: TAtlasVcsSvnBranchOptions; const AName: string; out APath: string): Boolean;
var
  mPattern, mRoot: string;
  mLayout: Boolean;
begin
  APath := '';
  // Ein fester Ort (^/branches/{name}) läge für jedes Package auf demselben Pfad wie das Projekt.
  mPattern := ASvn.Location;
  if not TAtlasSvnLayout.NeedsRoot(mPattern) then
  begin
    mPattern := TAtlasVcsSvnBranchOptions.Default.Location;
  end;
  mLayout := TAtlasSvnLayout.ProjectRoot(AExternal.Source, mRoot);
  Result := AExternal.CanBranch and TAtlasSvnLayout.Resolve(mPattern, mLayout, mRoot, AName, ASvn.Key, APath);
end;

class function TAtlasVcsBranchPlan.UsesPinExternals(const ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mIndex: Integer;
begin
  Result := TAtlasSvnExternals.PinExternalsSupported(ARequest.SvnVersion);
  if not Result then
  begin
    Exit;
  end;
  Result := False;
  for mIndex := 0 to High(ARequest.Externals) do
  begin
    if ARequest.Externals[mIndex].Fixed then
    begin
      Continue;
    end;
    if (mIndex > High(ARequest.ExternalActions)) or
      (ARequest.ExternalActions[mIndex] <> TAtlasVcsExternalAction.Pin) then
    begin
      Exit(False);
    end;
    Result := True;
  end;
end;

class function TAtlasVcsBranchPlan.ChangesExternals(const ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if (ARequest.Kind <> TAtlasVcsKind.Svn) or (ARequest.After <> TAtlasVcsSvnAfter.Switch) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ARequest.ExternalActions) do
  begin
    if (mIndex <= High(ARequest.Externals)) and not ARequest.Externals[mIndex].Fixed and
      (ARequest.ExternalActions[mIndex] in [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Branch]) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasVcsBranchPlan.ExternalRevision(const AExternal: TAtlasVcsSvnExternal): string;
begin
  if AExternal.Revision <> '' then
  begin
    Result := AExternal.Revision;
  end
  else if AExternal.Peg <> '' then
  begin
    Result := AExternal.Peg;
  end
  else
  begin
    Result := AExternal.WorkingRevision;
  end;
end;

function RuleAction(const AText: string; out AAction: TAtlasVcsExternalAction): Boolean;
begin
  Result := True;
  if SameText(Trim(AText), 'pin') then
  begin
    AAction := TAtlasVcsExternalAction.Pin;
  end
  else if SameText(Trim(AText), 'keep') then
  begin
    AAction := TAtlasVcsExternalAction.Keep;
  end
  else if SameText(Trim(AText), 'branch') then
  begin
    AAction := TAtlasVcsExternalAction.Branch;
  end
  else
  begin
    AAction := TAtlasVcsExternalAction.Ask;
    Result := False;
  end;
end;

function RuleIndex(const ARules: TArray<TAtlasVcsExternalRule>; const ASource: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARules) do
  begin
    if SameText(ARules[mIndex].Source, ASource) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  // TJSONNumber erbt von TJSONString: Zahlen zählen nicht als Text.
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
  begin
    Result := Trim(TJSONString(mValue).Value);
  end;
end;

function JsonQuoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

class function TAtlasVcsExternalRules.RulesOf(const AJson: string): TArray<TAtlasVcsExternalRule>;
var
  mRoot, mItem: TJSONValue;
  mSource: string;
  mAction: TAtlasVcsExternalAction;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mSource := JsonText(TJSONObject(mItem), 'source');
      if (mSource = '') or not RuleAction(JsonText(TJSONObject(mItem), 'onBranch'), mAction) or
        (RuleIndex(Result, mSource) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [TAtlasVcsExternalRule.Make(mSource, mAction)];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasVcsExternalRules.RulesJson(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mRule in ARules do
  begin
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
    begin
      mParts := mParts + ['{"source": ' + JsonQuoted(mRule.Source) + ', "onBranch": ' +
        JsonQuoted(AtlasVcsExternalActionText(mRule.Action)) + '}'];
    end;
  end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasVcsExternalRules.RulesText(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mLines: TArray<string>;
begin
  mLines := nil;
  for mRule in ARules do
  begin
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
    begin
      mLines := mLines + [mRule.Source + ' = ' + AtlasVcsExternalActionText(mRule.Action)];
    end;
  end;
  Result := string.Join(sLineBreak, mLines);
end;

class function TAtlasVcsExternalRules.RulesOfText(const AText: string; out ARules: TArray<TAtlasVcsExternalRule>;
  out AInvalid: string): Boolean;
var
  mLine, mSource: string;
  mAction: TAtlasVcsExternalAction;
  mIndex: Integer;
begin
  ARules := nil;
  AInvalid := '';
  for mLine in StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    if (Trim(mLine) = '') or (Copy(Trim(mLine), 1, 1) = '#') then
    begin
      Continue;
    end;
    // Das letzte „=“ trennt: Quellen dürfen kein „=“ enthalten, Behandlungen erst recht nicht.
    mIndex := mLine.LastIndexOf('=');
    mSource := '';
    if mIndex > 0 then
    begin
      mSource := Trim(Copy(mLine, 1, mIndex));
    end;
    if (mSource = '') or not RuleAction(Copy(mLine, mIndex + 2, MaxInt), mAction) then
    begin
      AInvalid := Trim(mLine);
      ARules := nil;
      Exit(False);
    end;
    mIndex := RuleIndex(ARules, mSource);
    if mIndex >= 0 then
    begin
      ARules[mIndex].Action := mAction;
    end
    else
    begin
      ARules := ARules + [TAtlasVcsExternalRule.Make(mSource, mAction)];
    end;
  end;
  Result := True;
end;

class function TAtlasVcsBranchPlan.WorktreePath(const ARoot, APattern, AName, AKey: string): string;
var
  mRoot, mKey: string;
begin
  mRoot := ExcludeTrailingPathDelimiter(Trim(ARoot));
  if mRoot = '' then
  begin
    Exit('');
  end;
  Result := Trim(APattern);
  if Result = '' then
  begin
    Result := TAtlasVcsGitBranchOptions.DefaultWorktreeFolder;
  end;
  mKey := FolderPart(AKey);
  // Ohne Issue (Befehl „Branch anlegen …“) steht der Name an Stelle der Kennung.
  if mKey = '' then
  begin
    mKey := FolderPart(AName);
  end;
  Result := StringReplace(Result, '{repo}', FolderPart(ExtractFileName(mRoot)), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{name}', FolderPart(AName), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{kennung}', mKey, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(StringReplace(Result, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  // Vollständig: Laufwerk, UNC bzw. Wurzel; sonst relativ zur Wurzel der Arbeitskopie.
  if not ((Length(Result) > 1) and (Result[2] = ':')) and not ((Result <> '') and (Result[1] = PathDelim)) then
  begin
    Result := mRoot + PathDelim + Result;
  end;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
end;

class function TAtlasVcsBranchPlan.SafeFolder(const AFolder: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AFolder <> '') and (AFolder[1] <> '-') and (AFolder = Trim(AFolder)) and
    (((Length(AFolder) > 1) and (AFolder[2] = ':')) or (AFolder[1] = PathDelim));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(AFolder) do
  begin
    if Ord(AFolder[mIndex]) < 32 then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasVcsBranchPlan.ProjectInFolder(const AProject, ARoot, AFolder: string): string;
var
  mRoot: string;
begin
  Result := '';
  mRoot := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Trim(ARoot)));
  if (Trim(ARoot) = '') or (AFolder = '') or not SameText(Copy(AProject, 1, Length(mRoot)), mRoot) then
  begin
    Exit;
  end;
  Result := IncludeTrailingPathDelimiter(AFolder) + Copy(AProject, Length(mRoot) + 1, MaxInt);
end;

class function TAtlasVcsBranchPlan.LocalChanges(const AChanges: TArray<TAtlasVcsChange>): Integer;
var
  mChange: TAtlasVcsChange;
begin
  Result := 0;
  for mChange in AChanges do
  begin
    if mChange.Kind <> TAtlasVcsChangeKind.Untracked then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasVcsBranchPlan.StashMessage(const AName: string): string;
begin
  Result := 'Atlas: vor ' + AName;
end;

class function TAtlasVcsBranchPlan.FetchFailed(const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): Boolean;
begin
  Result := (ARun.Failed >= 0) and (ARun.Failed <= High(ASteps)) and (Length(ASteps[ARun.Failed].Arguments) > 0) and
    (ASteps[ARun.Failed].Arguments[0] = 'fetch');
end;

class function TAtlasVcsBranchPlan.OnlyPushFailed(const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): Boolean;
begin
  Result := (ARun.Failed >= 0) and (ARun.Failed = High(ASteps)) and (ARun.Done = ARun.Failed) and
    (Length(ASteps[ARun.Failed].Arguments) > 0) and (ASteps[ARun.Failed].Arguments[0] = 'push');
end;

class function TAtlasVcsBranchPlan.LocalFallback(const AFacts: TAtlasVcsBranchFacts;
  const ARequest: TAtlasVcsBranchRequest): TAtlasVcsBranchRequest;
var
  mBase: TAtlasVcsBranchBase;
begin
  Result := ARequest;
  Result.Fetch := False;
  if (ARequest.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain) and
    DefaultBase(AFacts, TAtlasVcsGitBranchOptions.Classic, mBase) then
  begin
    Result.Base := mBase;
  end;
end;

class function TAtlasVcsBranchPlan.SafeName(const AName: string): Boolean;
begin
  Result := VcsSafeBranchName(AName);
end;

class function TAtlasVcsBranchPlan.BaseRef(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string;
begin
  if AKind = TAtlasVcsKind.Svn then
  begin
    Exit('^/' + ABase.Name + '@' + ABase.Revision);
  end;
  case ABase.Kind of
    TAtlasVcsBranchBaseKind.RemoteMain:
      Result := 'refs/remotes/' + ABase.RemoteName + '/' + ABase.Name;
    TAtlasVcsBranchBaseKind.LocalMain:
      Result := 'refs/heads/' + ABase.Name;
  else
    if ABase.Name = '' then
    begin
      Result := 'HEAD';
    end
    else
    begin
      Result := 'refs/heads/' + ABase.Name;
    end;
  end;
end;

class function TAtlasVcsBranchPlan.BaseName(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string;
begin
  Result := ABase.Name;
  if AKind = TAtlasVcsKind.Svn then
  begin
    if ABase.Revision <> '' then
    begin
      Result := Result + '@' + ABase.Revision;
    end;
    Exit;
  end;
  if ABase.Kind = TAtlasVcsBranchBaseKind.RemoteMain then
  begin
    Result := ABase.RemoteName + '/' + Result;
  end
  else if Result = '' then
  begin
    Result := 'HEAD';
  end;
end;

type
  /// <summary>Baut die Schritte für die Externals (#1291) aus einer Anfrage.</summary>
  TExternalStepBuilder = class
  strict private
    FRequest: TAtlasVcsBranchRequest;
    FMessage: string;
    FPin: Boolean;
    /// <summary>Text je Definition mit den geänderten Zeilen.</summary>
    FTexts: TArray<string>;
    /// <summary>Hinweis je Definition für die Anzeige (", Ordner -r 12").</summary>
    FNotes: TArray<string>;
    /// <summary>Schon vergebene Orte, je mit "|" umschlossen.</summary>
    FUsed: string;
    function ActionOf(AIndex: Integer): TAtlasVcsExternalAction;
    function DefinitionOf(const AOwner: string): Integer;
    function PinnedLine(const AExternal: TAtlasVcsSvnExternal; ADefinition: Integer): string;
    function BranchedLine(AIndex, ADefinition: Integer): string;
    function AddExternal(AIndex: Integer): Boolean;
    function RewriteSteps(ADefinition: Integer): TArray<TAtlasVcsBranchStep>;
  public
    Packages: TArray<TAtlasVcsBranchStep>;
    Rewrites: TArray<TAtlasVcsBranchStep>;
    constructor Create(const ARequest: TAtlasVcsBranchRequest; const AMessage: string);
    /// <summary>False, wenn eine Wahl fehlt (Ask) oder nicht taugt.</summary>
    function Build: Boolean;
  end;

constructor TExternalStepBuilder.Create(const ARequest: TAtlasVcsBranchRequest; const AMessage: string);
var
  mDefinition: Integer;
begin
  inherited Create;
  FRequest := ARequest;
  FMessage := AMessage;
  FPin := TAtlasVcsBranchPlan.UsesPinExternals(ARequest);
  SetLength(FTexts, Length(ARequest.Definitions));
  SetLength(FNotes, Length(ARequest.Definitions));
  for mDefinition := 0 to High(ARequest.Definitions) do
  begin
    FTexts[mDefinition] := ARequest.Definitions[mDefinition].Text;
    FNotes[mDefinition] := '';
  end;
  FUsed := '|' + ARequest.Location + '|';
end;

function TExternalStepBuilder.ActionOf(AIndex: Integer): TAtlasVcsExternalAction;
begin
  Result := TAtlasVcsExternalAction.Keep;
  if AIndex <= High(FRequest.ExternalActions) then
  begin
    Result := FRequest.ExternalActions[AIndex];
  end;
end;

function TExternalStepBuilder.DefinitionOf(const AOwner: string): Integer;
begin
  Result := 0;
  while (Result <= High(FRequest.Definitions)) and (FRequest.Definitions[Result].Owner <> AOwner) do
  begin
    Inc(Result);
  end;
  if Result > High(FRequest.Definitions) then
  begin
    Result := -1;
  end;
end;

function TExternalStepBuilder.PinnedLine(const AExternal: TAtlasVcsSvnExternal; ADefinition: Integer): string;
var
  mRevision: string;
begin
  // Festschreiben auf die Revision, die die External-Arbeitskopie gerade hat.
  Result := '';
  mRevision := AExternal.WorkingRevision;
  if StrToIntDef(mRevision, -1) < 0 then
  begin
    Exit;
  end;
  Result := TAtlasSvnExternals.PinnedLine(FRequest.Definitions[ADefinition].Text, AExternal, mRevision);
  FNotes[ADefinition] := FNotes[ADefinition] + ', ' + AExternal.Folder + ' -r ' + mRevision;
end;

function TExternalStepBuilder.BranchedLine(AIndex, ADefinition: Integer): string;
var
  mExternal: TAtlasVcsSvnExternal;
  mLocation, mRevision: string;
begin
  // Mitverzweigen: eigener Ort je Package, nie derselbe wie das Projekt oder ein anderes Package.
  Result := '';
  mExternal := FRequest.Externals[AIndex];
  if AIndex > High(FRequest.ExternalLocations) then
  begin
    Exit;
  end;
  mLocation := FRequest.ExternalLocations[AIndex];
  mRevision := mExternal.WorkingRevision;
  if not VcsSafeBranchName(mLocation) or not VcsSafeBranchName(mExternal.Source) or
    (Pos('|' + mLocation + '|', FUsed) > 0) or ((mRevision <> '') and (StrToIntDef(mRevision, -1) < 0)) then
  begin
    Exit;
  end;
  FUsed := FUsed + mLocation + '|';
  Packages := Packages + [TAtlasVcsBranchStep.Make(TArray<string>.Create('copy', '^/' + mExternal.Source + '@' +
    mRevision, '^/' + mLocation + '@', '--parents', '-m', FMessage), True, True)];
  Result := TAtlasSvnExternals.RetargetedLine(FRequest.Definitions[ADefinition].Text, mExternal, mLocation,
    FRequest.RepositoryRoot);
  FNotes[ADefinition] := FNotes[ADefinition] + ', ' + mExternal.Folder + ' → ^/' + mLocation;
end;

function TExternalStepBuilder.AddExternal(AIndex: Integer): Boolean;
var
  mExternal: TAtlasVcsSvnExternal;
  mAction: TAtlasVcsExternalAction;
  mDefinition: Integer;
  mLine: string;
begin
  mExternal := FRequest.Externals[AIndex];
  mAction := ActionOf(AIndex);
  if (mAction = TAtlasVcsExternalAction.Keep) or ((mAction = TAtlasVcsExternalAction.Pin) and FPin) then
  begin
    Exit(True);
  end;
  mDefinition := DefinitionOf(mExternal.Owner);
  if (mAction = TAtlasVcsExternalAction.Ask) or not TAtlasSvnExternals.Allowed(mExternal, mAction) or
    (mDefinition < 0) then
  begin
    Exit(False);
  end;
  if mAction = TAtlasVcsExternalAction.Pin then
  begin
    mLine := PinnedLine(mExternal, mDefinition);
  end
  else
  begin
    mLine := BranchedLine(AIndex, mDefinition);
  end;
  // Zeilennummern beziehen sich auf die Definition; ReplaceLine ändert die Zahl der Zeilen nicht.
  Result := mLine <> '';
  if Result then
  begin
    FTexts[mDefinition] := TAtlasSvnExternals.ReplaceLine(FTexts[mDefinition], mExternal.Line, mLine);
  end;
end;

function TExternalStepBuilder.RewriteSteps(ADefinition: Integer): TArray<TAtlasVcsBranchStep>;
var
  mDir, mUrl: string;
  mStep: TAtlasVcsBranchStep;
begin
  // Schlanke Arbeitskopie nur des Ordners mit der Eigenschaft, im neuen Branch.
  mDir := TPath.Combine(FRequest.WorkFolder, 'p' + IntToStr(ADefinition));
  mUrl := '^/' + FRequest.Location;
  if FRequest.Definitions[ADefinition].Owner <> '' then
  begin
    mUrl := mUrl + '/' + FRequest.Definitions[ADefinition].Owner;
  end;
  mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('propset', 'svn:externals', '-F', mDir + '.txt', mDir),
    False, False);
  mStep.InputFile := mDir + '.txt';
  mStep.InputText := FTexts[ADefinition];
  mStep.Note := 'svn:externals: ' + Copy(FNotes[ADefinition], 3, MaxInt);
  Result := [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', mUrl + '@', mDir, '--depth', 'empty'), True,
    False), mStep, TAtlasVcsBranchStep.Make(TArray<string>.Create('commit', mDir, '-m', FMessage), True, True)];
end;

function TExternalStepBuilder.Build: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRequest.Externals) do
  begin
    if not AddExternal(mIndex) then
    begin
      Exit(False);
    end;
  end;
  for mIndex := 0 to High(FRequest.Definitions) do
  begin
    if FTexts[mIndex] = FRequest.Definitions[mIndex].Text then
    begin
      Continue;
    end;
    if Trim(FRequest.WorkFolder) = '' then
    begin
      Exit(False);
    end;
    Rewrites := Rewrites + RewriteSteps(mIndex);
  end;
  Result := True;
end;

/// <summary>Schritte für die Externals (#1291): APackages vor der Kopie des Projekts (mitverzweigte Packages),
/// ARewrites danach (Zeilen in svn:externals des neuen Branchs). False, wenn eine Wahl fehlt (Ask) oder nicht
/// taugt.</summary>
function ExternalSteps(const ARequest: TAtlasVcsBranchRequest; const AMessage: string;
  out APackages, ARewrites: TArray<TAtlasVcsBranchStep>): Boolean;
var
  mBuilder: TExternalStepBuilder;
begin
  APackages := nil;
  ARewrites := nil;
  mBuilder := TExternalStepBuilder.Create(ARequest, AMessage);
  try
    Result := mBuilder.Build;
    if Result then
    begin
      APackages := mBuilder.Packages;
      ARewrites := mBuilder.Rewrites;
    end;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Taugen Basis, Ort und Ordner einer SVN-Anfrage für die Befehle?</summary>
function SvnRequestUsable(const ARequest: TAtlasVcsBranchRequest): Boolean;
begin
  Result := TAtlasVcsBranchPlan.SafeName(ARequest.Base.Name) and TAtlasVcsBranchPlan.SafeName(ARequest.Location) and
    ((ARequest.Base.Revision = '') or (StrToIntDef(ARequest.Base.Revision, -1) >= 0));
  // Auschecken braucht einen Ordner, der keine Option ist.
  if Result and (ARequest.After = TAtlasVcsSvnAfter.Checkout) then
  begin
    Result := (Trim(ARequest.CheckoutFolder) <> '') and (ARequest.CheckoutFolder[1] <> '-');
  end;
end;

/// <summary>Schritt nach dem Anlegen: Arbeitskopie umstellen, frisch auschecken oder nichts.</summary>
function SvnAfterSteps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
begin
  case ARequest.After of
    TAtlasVcsSvnAfter.Switch:
      Result := [TAtlasVcsBranchStep.Make(TArray<string>.Create('switch', '^/' + ARequest.Location + '@', '.'), True,
        False, True)];
    TAtlasVcsSvnAfter.Checkout:
      Result := [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '^/' + ARequest.Location + '@',
        ARequest.CheckoutFolder), True, False, True)];
  else
    // None: nur anlegen, die Arbeitskopie bleibt.
    Result := nil;
  end;
end;

function SvnSteps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mMessage: string;
  mCopy: TArray<string>;
  mPackages, mRewrites: TArray<TAtlasVcsBranchStep>;
begin
  Result := nil;
  mMessage := Trim(ARequest.Message);
  if mMessage = '' then
  begin
    mMessage := 'Branch ' + ARequest.Name;
  end;
  // Externals (#1291): erst die Packages, dann das Projekt, dann die Zeilen im neuen Branch.
  if not SvnRequestUsable(ARequest) or not ExternalSteps(ARequest, mMessage, mPackages, mRewrites) then
  begin
    Exit;
  end;
  // "@" am Ende des Ziels: ein "@" im Namen ist dann keine Revision.
  mCopy := TArray<string>.Create('copy', TAtlasVcsBranchPlan.BaseRef(TAtlasVcsKind.Svn, ARequest.Base),
    '^/' + ARequest.Location + '@', '--parents', '-m', mMessage);
  if TAtlasVcsBranchPlan.UsesPinExternals(ARequest) then
  begin
    mCopy := mCopy + ['--pin-externals'];
  end;
  Result := mPackages + [TAtlasVcsBranchStep.Make(mCopy, True, True)] + mRewrites + SvnAfterSteps(ARequest);
end;

class function TAtlasVcsBranchPlan.Steps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
begin
  Result := nil;
  if not SafeName(ARequest.Name) then
  begin
    Exit;
  end;
  case ARequest.Kind of
    TAtlasVcsKind.Git:
      Result := GitSteps(ARequest);
    TAtlasVcsKind.Svn:
      Result := SvnSteps(ARequest);
  else
    // Ohne Git oder SVN gibt es nichts anzulegen.
  end;
end;

class function TAtlasVcsBranchPlan.StepText(AKind: TAtlasVcsKind; const AStep: TAtlasVcsBranchStep): string;
var
  mArgument: string;
begin
  if AKind = TAtlasVcsKind.Svn then
  begin
    Result := 'svn';
  end
  else
  begin
    Result := 'git';
  end;
  for mArgument in AStep.Arguments do
  begin
    if (mArgument = '') or (Pos(' ', mArgument) > 0) or (Pos('"', mArgument) > 0) then
    begin
      Result := Result + ' "' + StringReplace(mArgument, '"', '\"', [rfReplaceAll]) + '"';
    end
    else
    begin
      Result := Result + ' ' + mArgument;
    end;
  end;
  // Was die Datei für propset enthält (#1291), in Klartext.
  if AStep.Note <> '' then
  begin
    Result := Result + '   (' + AStep.Note + ')';
  end;
end;

class function TAtlasVcsBranchPlan.Execute(const ABranching: IAtlasVcsBranching;
  const ASteps: TArray<TAtlasVcsBranchStep>): TAtlasVcsBranchRun;
begin
  Result := Execute(ABranching, ASteps, nil);
end;

class function TAtlasVcsBranchPlan.Execute(const ABranching: IAtlasVcsBranching;
  const ASteps: TArray<TAtlasVcsBranchStep>; const AProgress: TAtlasVcsBranchProgress): TAtlasVcsBranchRun;
var
  mIndex: Integer;
begin
  Result.Outcome := TAtlasVcsOutcome.Ok;
  Result.Done := 0;
  Result.Failed := -1;
  if ABranching = nil then
  begin
    Result.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
    Result.Failed := 0;
    Exit;
  end;
  if Length(ASteps) = 0 then
  begin
    Result.Outcome := TAtlasVcsOutcome.Failed;
    Result.Failed := 0;
    Exit;
  end;
  for mIndex := 0 to High(ASteps) do
  begin
    if Assigned(AProgress) then
    begin
      AProgress(mIndex, Length(ASteps), ASteps[mIndex]);
    end;
    Result.Outcome := ABranching.RunStep(ASteps[mIndex]);
    if Result.Outcome <> TAtlasVcsOutcome.Ok then
    begin
      Result.Failed := mIndex;
      Exit;
    end;
    Result.Done := mIndex + 1;
  end;
end;

class function TAtlasVcsBranchPlan.Execute(const ABranching: IAtlasVcsBranching;
  const ARequest: TAtlasVcsBranchRequest; const ASteps: TArray<TAtlasVcsBranchStep>;
  const AProgress: TAtlasVcsBranchProgress): TAtlasVcsBranchRun;

  procedure Clean;
  begin
    if (ARequest.WorkFolder = '') or not TDirectory.Exists(ARequest.WorkFolder) then
    begin
      Exit;
    end;
    try
      TDirectory.Delete(ARequest.WorkFolder, True);
    except
      // Netz: Ein Rest im Temp-Ordner stört nicht; der nächste Lauf versucht es erneut.
      on EInOutError do
        ;
      on EOSError do
        ;
    end;
  end;

begin
  Clean;
  try
    Result := Execute(ABranching, ASteps, AProgress);
  finally
    Clean;
  end;
end;

class function TAtlasVcsBranchPlan.CheckoutTarget(const ARoot, AFolder, AFile: string): string;
var
  mRoot, mRelative: string;
begin
  Result := '';
  mRoot := VcsNormalizeDir(ARoot);
  if (mRoot = '') or (Trim(AFolder) = '') or not VcsRelativePath(mRoot, AFile, mRelative) then
  begin
    Exit;
  end;
  Result := VcsFullPath(AFolder, mRelative);
end;

class function TAtlasVcsBranchPlan.ServerStepsDone(const ASteps: TArray<TAtlasVcsBranchStep>;
  ADone: Integer): TArray<TAtlasVcsBranchStep>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ADone - 1 do
  begin
    if (mIndex <= High(ASteps)) and ASteps[mIndex].ChangesServer then
    begin
      Result := Result + [ASteps[mIndex]];
    end;
  end;
end;

end.
