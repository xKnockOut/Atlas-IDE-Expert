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
// Die Optionen aus #1289 (Git) kommen als weitere Felder der Anfrage und
// weitere Schritte hinzu.
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
{$SCOPEDENUMS OFF}

  TAtlasVcsBranchBase = record
    Kind: TAtlasVcsBranchBaseKind;
    /// <summary>Git: Branch ohne "origin/" ('' = losgelöster HEAD); SVN: Pfad im Repository wie "trunk".
    /// </summary>
    Name: string;
    /// <summary>SVN: Revision der Quelle; '' = HEAD beim Kopieren. Git ''.</summary>
    Revision: string;
    class function Make(AKind: TAtlasVcsBranchBaseKind; const AName, ARevision: string): TAtlasVcsBranchBase;
      static;
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
    /// <summary>Wurzel der Arbeitskopie (AVcs.WorkingCopy.Root); '' ohne.</summary>
    Root: string;
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
    /// <summary>Anfrage mit der Vorgabe-Basis (für „Beginnen“ ohne Dialog); False ohne Basis.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Wie oben mit den SVN-Optionen (#1290): Basis nach Quelle, Ort, Danach und Ordner (ApplySvn).
    /// False auch, wenn sich der Ort nicht auflösen lässt.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      const ASvn: TAtlasVcsSvnBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
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
    /// <summary>Name taugt für git und svn (nicht leer, keine Option, kein „..“, keine Leer- und Steuerzeichen).
    /// Die strengere Prüfung nach Git-Regeln macht der Dialog (TAtlasTrackerNaming.ValidBranchName).</summary>
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

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Core.Vcs.Internals.SvnExternals,
  Atlas.Core.Vcs.Internals.SvnLayout,
  Atlas.Core.Vcs.Internals.Text;

{ TAtlasVcsBranchBase }

class function TAtlasVcsBranchBase.Make(AKind: TAtlasVcsBranchBaseKind; const AName,
  ARevision: string): TAtlasVcsBranchBase;
begin
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Revision := ARevision;
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
    AFacts.SvnVersion := mVersion;
  if (ASvn.ExternalsXml(mXml) <> TAtlasVcsOutcome.Ok) or (ASvn.RepositoryRoot(mRepository) <> TAtlasVcsOutcome.Ok) or
    (mRepository = '') then
    Exit;
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

class function TAtlasVcsBranchPlan.Inspect(const AVcs: IAtlasVersionControl;
  const ACandidates: TArray<string>): TAtlasVcsBranchFacts;
var
  mBranching: IAtlasVcsBranching;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mHead: TAtlasVcsHead;
  mCandidate, mPath, mText, mRevision: string;
  mLocal, mRemote, mMixed: Boolean;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsBranching, mBranching) then
    Exit;
  Result.Kind := AVcs.Kind;
  if (Result.Kind <> TAtlasVcsKind.Git) and (Result.Kind <> TAtlasVcsKind.Svn) then
    Exit;
  Result.Outcome := AVcs.Head(mHead);
  if Result.Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  Result.Root := AVcs.WorkingCopy.Root;
  Result.Current := mHead.Branch;
  if Result.Kind = TAtlasVcsKind.Svn then
  begin
    Result.Revision := mHead.Revision;
    // Voller Pfad ("Kasse/trunk"): Head.Branch kürzt auf "trunk", die Kopie braucht den ganzen. Aus ihm die
    // Projektwurzel für Ort und Hauptbranch (#1290).
    if (mBranching.RepositoryPath(mPath) = TAtlasVcsOutcome.Ok) and (mPath <> '') then
    begin
      Result.Current := mPath;
      Result.LayoutKnown := TAtlasSvnLayout.ProjectRoot(mPath, Result.ProjectRoot);
    end;
    // Gemischte Arbeitskopie (#1290): die höchste Revision, der Dialog warnt. Ohne svnversion die der Wurzel.
    if not Supports(AVcs, IAtlasVcsSvnWorkingCopy, mSvn) then
      mSvn := nil;
    if (mSvn <> nil) and (mSvn.WorkingRevisions(mText) = TAtlasVcsOutcome.Ok) and
      TAtlasSvnLayout.WorkingRevision(mText, mRevision, mMixed) then
    begin
      Result.Revision := mRevision;
      Result.MixedRevision := mMixed;
    end;
    for mCandidate in ACandidates do
    begin
      // "trunk" liegt unter der Projektwurzel ("Kasse/trunk"), nicht an der Wurzel des Repositorys.
      mPath := TAtlasSvnLayout.MainPath(mCandidate, Result.LayoutKnown, Result.ProjectRoot);
      if SafeName(mPath) then
      begin
        Result.MainBranch := mPath;
        Break;
      end;
    end;
    // Externals (#1291): Zeilen samt Zustand; ein Fehler hier hält das Anlegen nicht auf (Externals bleiben dann,
    // wie sie sind).
    if mSvn <> nil then
      InspectExternals(mSvn, Result);
    if (Length(Result.SvnExternals) = 0) and (mBranching.HasExternals(Result.Externals) <> TAtlasVcsOutcome.Ok) then
      Result.Externals := False;
    Exit;
  end;
  for mCandidate in ACandidates do
  begin
    if not SafeName(mCandidate) then
      Continue;
    Result.Outcome := mBranching.BranchExists(mCandidate, mLocal);
    if Result.Outcome <> TAtlasVcsOutcome.Ok then
      Exit;
    Result.Outcome := mBranching.RemoteBranchExists(mCandidate, mRemote);
    if Result.Outcome <> TAtlasVcsOutcome.Ok then
      Exit;
    if mLocal or mRemote then
    begin
      Result.MainBranch := mCandidate;
      Result.LocalMain := mLocal;
      Result.RemoteMain := mRemote;
      Exit;
    end;
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
    Exit;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsBranching, mBranching) then
  begin
    AFacts.ServerOutcome := TAtlasVcsOutcome.NoWorkingCopy;
    Exit;
  end;
  AFacts.ServerOutcome := mBranching.ServerRevision(AFacts.MainBranch, mRevision);
  if AFacts.ServerOutcome = TAtlasVcsOutcome.Ok then
    AFacts.HeadRevision := mRevision;
end;

class function TAtlasVcsBranchPlan.Bases(const AFacts: TAtlasVcsBranchFacts): TArray<TAtlasVcsBranchBase>;
begin
  Result := nil;
  if AFacts.Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  if AFacts.Kind = TAtlasVcsKind.Git then
  begin
    if AFacts.RemoteMain then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, AFacts.MainBranch, '')];
    if AFacts.LocalMain then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, AFacts.MainBranch, '')];
    // Der aktuelle Branch nur, wenn er nicht schon als lokaler Hauptbranch dasteht.
    if not AFacts.LocalMain or (AFacts.Current <> AFacts.MainBranch) then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, AFacts.Current, '')];
  end
  else if AFacts.Kind = TAtlasVcsKind.Svn then
  begin
    if AFacts.MainBranch <> '' then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Head, AFacts.MainBranch,
        AFacts.HeadRevision)];
    if (AFacts.Current <> '') and (AFacts.Revision <> '') then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.WorkingCopy, AFacts.Current,
        AFacts.Revision)];
  end;
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts;
  out ABase: TAtlasVcsBranchBase): Boolean;
begin
  Result := DefaultBase(AFacts, TAtlasVcsSvnSource.Head, ABase);
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts; ASource: TAtlasVcsSvnSource;
  out ABase: TAtlasVcsBranchBase): Boolean;
var
  mBase: TAtlasVcsBranchBase;
  mBases: TArray<TAtlasVcsBranchBase>;
  mPreferred: TArray<TAtlasVcsBranchBaseKind>;
  mKind: TAtlasVcsBranchBaseKind;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  mBases := Bases(AFacts);
  // Wie „Beginnen“ bisher (#765): lokal vor origin; SVN der Hauptbranch, mit vcs.branch.svn.source = workingCopy
  // die Arbeitskopie (#1290).
  if ASource = TAtlasVcsSvnSource.WorkingCopy then
    mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.LocalMain,
      TAtlasVcsBranchBaseKind.RemoteMain, TAtlasVcsBranchBaseKind.WorkingCopy, TAtlasVcsBranchBaseKind.Head)
  else
    mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.LocalMain,
      TAtlasVcsBranchBaseKind.RemoteMain, TAtlasVcsBranchBaseKind.Head);
  for mKind in mPreferred do
    for mBase in mBases do
      if mBase.Kind = mKind then
      begin
        ABase := mBase;
        Exit(True);
      end;
  // Ohne Hauptbranch keine Vorgabe: wie bisher bei „Beginnen“ scheitern statt still vom aktuellen Branch
  // abzuzweigen.
  Result := False;
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
var
  mBase: TAtlasVcsBranchBase;
  mAction: TAtlasVcsExternalAction;
begin
  Result := DefaultBase(AFacts, ASvn.Source, mBase);
  ARequest := TAtlasVcsBranchRequest.Make(AFacts.Kind, AName, mBase, AMessage);
  if not ApplySvn(ARequest, AFacts, ASvn) then
    Result := False;
  // vcs.externals.onBranch = ask: ohne Dialog gibt es keine Wahl (#1291).
  for mAction in ARequest.ExternalActions do
    if mAction = TAtlasVcsExternalAction.Ask then
      Result := False;
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
    Exit;
  Result := SvnLocation(AFacts, ASvn, ARequest.Name, mPath);
  ARequest.Location := mPath;
  ARequest.After := ASvn.After;
  ARequest.CheckoutFolder := '';
  if ASvn.After = TAtlasVcsSvnAfter.Checkout then
    ARequest.CheckoutFolder := SvnCheckoutFolder(AFacts, ASvn, ARequest.Name);
  ApplyExternals(ARequest, AFacts, ASvn, DefaultActions(AFacts, ASvn));
end;

class function TAtlasVcsBranchPlan.DefaultActions(const AFacts: TAtlasVcsBranchFacts;
  const ASvn: TAtlasVcsSvnBranchOptions): TArray<TAtlasVcsExternalAction>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFacts.SvnExternals));
  for mIndex := 0 to High(AFacts.SvnExternals) do
    Result[mIndex] := TAtlasSvnExternals.DefaultAction(AFacts.SvnExternals[mIndex], ASvn);
end;

class procedure TAtlasVcsBranchPlan.ApplyExternals(var ARequest: TAtlasVcsBranchRequest;
  const AFacts: TAtlasVcsBranchFacts; const ASvn: TAtlasVcsSvnBranchOptions;
  const AActions: TArray<TAtlasVcsExternalAction>);
var
  mIndex: Integer;
  mPath, mFolder: string;
begin
  if ARequest.Kind <> TAtlasVcsKind.Svn then
    Exit;
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
      ARequest.ExternalActions[mIndex] := AActions[mIndex];
    ARequest.ExternalLocations[mIndex] := '';
    if (ARequest.ExternalActions[mIndex] = TAtlasVcsExternalAction.Branch) and
      ExternalLocation(ARequest.Externals[mIndex], ASvn, ARequest.Name, mPath) then
      ARequest.ExternalLocations[mIndex] := mPath;
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
    mPattern := TAtlasVcsSvnBranchOptions.Default.Location;
  mLayout := TAtlasSvnLayout.ProjectRoot(AExternal.Source, mRoot);
  Result := AExternal.CanBranch and TAtlasSvnLayout.Resolve(mPattern, mLayout, mRoot, AName, ASvn.Key, APath);
end;

class function TAtlasVcsBranchPlan.UsesPinExternals(const ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mIndex: Integer;
begin
  Result := TAtlasSvnExternals.PinExternalsSupported(ARequest.SvnVersion);
  if not Result then
    Exit;
  Result := False;
  for mIndex := 0 to High(ARequest.Externals) do
  begin
    if ARequest.Externals[mIndex].Fixed then
      Continue;
    if (mIndex > High(ARequest.ExternalActions)) or
      (ARequest.ExternalActions[mIndex] <> TAtlasVcsExternalAction.Pin) then
      Exit(False);
    Result := True;
  end;
end;

class function TAtlasVcsBranchPlan.ChangesExternals(const ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if (ARequest.Kind <> TAtlasVcsKind.Svn) or (ARequest.After <> TAtlasVcsSvnAfter.Switch) then
    Exit;
  for mIndex := 0 to High(ARequest.ExternalActions) do
    if (mIndex <= High(ARequest.Externals)) and not ARequest.Externals[mIndex].Fixed and
      (ARequest.ExternalActions[mIndex] in [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Branch]) then
      Exit(True);
end;

class function TAtlasVcsBranchPlan.ExternalRevision(const AExternal: TAtlasVcsSvnExternal): string;
begin
  if AExternal.Revision <> '' then
    Result := AExternal.Revision
  else if AExternal.Peg <> '' then
    Result := AExternal.Peg
  else
    Result := AExternal.WorkingRevision;
end;

function RuleAction(const AText: string; out AAction: TAtlasVcsExternalAction): Boolean;
begin
  Result := True;
  if SameText(Trim(AText), 'pin') then
    AAction := TAtlasVcsExternalAction.Pin
  else if SameText(Trim(AText), 'keep') then
    AAction := TAtlasVcsExternalAction.Keep
  else if SameText(Trim(AText), 'branch') then
    AAction := TAtlasVcsExternalAction.Branch
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
    if SameText(ARules[mIndex].Source, ASource) then
      Exit(mIndex);
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
    Result := Trim(TJSONString(mValue).Value);
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

class function TAtlasVcsBranchPlan.RulesOf(const AJson: string): TArray<TAtlasVcsExternalRule>;
var
  mRoot, mItem: TJSONValue;
  mSource: string;
  mAction: TAtlasVcsExternalAction;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
      Exit;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mSource := JsonText(TJSONObject(mItem), 'source');
      if (mSource = '') or not RuleAction(JsonText(TJSONObject(mItem), 'onBranch'), mAction) or
        (RuleIndex(Result, mSource) >= 0) then
        Continue;
      Result := Result + [TAtlasVcsExternalRule.Make(mSource, mAction)];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasVcsBranchPlan.RulesJson(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mRule in ARules do
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
      mParts := mParts + ['{"source": ' + JsonQuoted(mRule.Source) + ', "onBranch": ' +
        JsonQuoted(AtlasVcsExternalActionText(mRule.Action)) + '}'];
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasVcsBranchPlan.RulesText(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mLines: TArray<string>;
begin
  mLines := nil;
  for mRule in ARules do
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
      mLines := mLines + [mRule.Source + ' = ' + AtlasVcsExternalActionText(mRule.Action)];
  Result := string.Join(sLineBreak, mLines);
end;

class function TAtlasVcsBranchPlan.RulesOfText(const AText: string; out ARules: TArray<TAtlasVcsExternalRule>;
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
      Continue;
    // Das letzte „=“ trennt: Quellen dürfen kein „=“ enthalten, Behandlungen erst recht nicht.
    mIndex := mLine.LastIndexOf('=');
    mSource := '';
    if mIndex > 0 then
      mSource := Trim(Copy(mLine, 1, mIndex));
    if (mSource = '') or not RuleAction(Copy(mLine, mIndex + 2, MaxInt), mAction) then
    begin
      AInvalid := Trim(mLine);
      ARules := nil;
      Exit(False);
    end;
    mIndex := RuleIndex(ARules, mSource);
    if mIndex >= 0 then
      ARules[mIndex].Action := mAction
    else
      ARules := ARules + [TAtlasVcsExternalRule.Make(mSource, mAction)];
  end;
  Result := True;
end;

class function TAtlasVcsBranchPlan.SafeName(const AName: string): Boolean;
begin
  Result := VcsSafeBranchName(AName);
end;

class function TAtlasVcsBranchPlan.BaseRef(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string;
begin
  if AKind = TAtlasVcsKind.Svn then
    Exit('^/' + ABase.Name + '@' + ABase.Revision);
  case ABase.Kind of
    TAtlasVcsBranchBaseKind.RemoteMain:
      Result := 'refs/remotes/origin/' + ABase.Name;
    TAtlasVcsBranchBaseKind.LocalMain:
      Result := 'refs/heads/' + ABase.Name;
  else
    if ABase.Name = '' then
      Result := 'HEAD'
    else
      Result := 'refs/heads/' + ABase.Name;
  end;
end;

class function TAtlasVcsBranchPlan.BaseName(AKind: TAtlasVcsKind; const ABase: TAtlasVcsBranchBase): string;
begin
  Result := ABase.Name;
  if AKind = TAtlasVcsKind.Svn then
  begin
    if ABase.Revision <> '' then
      Result := Result + '@' + ABase.Revision;
    Exit;
  end;
  if ABase.Kind = TAtlasVcsBranchBaseKind.RemoteMain then
    Result := 'origin/' + Result
  else if Result = '' then
    Result := 'HEAD';
end;

/// <summary>Schritte für die Externals (#1291): APackages vor der Kopie des Projekts (mitverzweigte Packages),
/// ARewrites danach (Zeilen in svn:externals des neuen Branchs). False, wenn eine Wahl fehlt (Ask) oder nicht
/// taugt.</summary>
function ExternalSteps(const ARequest: TAtlasVcsBranchRequest; const AMessage: string;
  out APackages, ARewrites: TArray<TAtlasVcsBranchStep>): Boolean;
var
  mIndex, mDefinition: Integer;
  mExternal: TAtlasVcsSvnExternal;
  mAction: TAtlasVcsExternalAction;
  mTexts: TArray<string>;
  mNotes: TArray<string>;
  mLine, mRevision, mDir, mUrl, mUsed: string;
  mPin: Boolean;
  mStep: TAtlasVcsBranchStep;
begin
  Result := False;
  APackages := nil;
  ARewrites := nil;
  mPin := TAtlasVcsBranchPlan.UsesPinExternals(ARequest);
  SetLength(mTexts, Length(ARequest.Definitions));
  SetLength(mNotes, Length(ARequest.Definitions));
  for mDefinition := 0 to High(ARequest.Definitions) do
  begin
    mTexts[mDefinition] := ARequest.Definitions[mDefinition].Text;
    mNotes[mDefinition] := '';
  end;
  mUsed := '|' + ARequest.Location + '|';
  for mIndex := 0 to High(ARequest.Externals) do
  begin
    mExternal := ARequest.Externals[mIndex];
    mAction := TAtlasVcsExternalAction.Keep;
    if mIndex <= High(ARequest.ExternalActions) then
      mAction := ARequest.ExternalActions[mIndex];
    if mAction = TAtlasVcsExternalAction.Ask then
      Exit;
    if (mAction = TAtlasVcsExternalAction.Keep) or ((mAction = TAtlasVcsExternalAction.Pin) and mPin) then
      Continue;
    if not TAtlasSvnExternals.Allowed(mExternal, mAction) then
      Exit;
    mDefinition := 0;
    while (mDefinition <= High(ARequest.Definitions)) and (ARequest.Definitions[mDefinition].Owner <> mExternal.Owner) do
      Inc(mDefinition);
    if mDefinition > High(ARequest.Definitions) then
      Exit;
    if mAction = TAtlasVcsExternalAction.Pin then
    begin
      // Festschreiben auf die Revision, die die External-Arbeitskopie gerade hat.
      mRevision := mExternal.WorkingRevision;
      if StrToIntDef(mRevision, -1) < 0 then
        Exit;
      mLine := TAtlasSvnExternals.PinnedLine(ARequest.Definitions[mDefinition].Text, mExternal, mRevision);
      mNotes[mDefinition] := mNotes[mDefinition] + ', ' + mExternal.Folder + ' -r ' + mRevision;
    end
    else
    begin
      // Mitverzweigen: eigener Ort je Package, nie derselbe wie das Projekt oder ein anderes Package.
      if (mIndex > High(ARequest.ExternalLocations)) or not VcsSafeBranchName(ARequest.ExternalLocations[mIndex]) or
        not VcsSafeBranchName(mExternal.Source) or (Pos('|' + ARequest.ExternalLocations[mIndex] + '|', mUsed) > 0) then
        Exit;
      mUsed := mUsed + ARequest.ExternalLocations[mIndex] + '|';
      mRevision := mExternal.WorkingRevision;
      if (mRevision <> '') and (StrToIntDef(mRevision, -1) < 0) then
        Exit;
      APackages := APackages + [TAtlasVcsBranchStep.Make(TArray<string>.Create('copy', '^/' + mExternal.Source + '@' +
        mRevision, '^/' + ARequest.ExternalLocations[mIndex] + '@', '--parents', '-m', AMessage), True, True)];
      mLine := TAtlasSvnExternals.RetargetedLine(ARequest.Definitions[mDefinition].Text, mExternal,
        ARequest.ExternalLocations[mIndex], ARequest.RepositoryRoot);
      mNotes[mDefinition] := mNotes[mDefinition] + ', ' + mExternal.Folder + ' → ^/' +
        ARequest.ExternalLocations[mIndex];
    end;
    if mLine = '' then
      Exit;
    // Zeilennummern beziehen sich auf die Definition; ReplaceLine ändert die Zahl der Zeilen nicht.
    mTexts[mDefinition] := TAtlasSvnExternals.ReplaceLine(mTexts[mDefinition], mExternal.Line, mLine);
  end;
  for mDefinition := 0 to High(ARequest.Definitions) do
  begin
    if mTexts[mDefinition] = ARequest.Definitions[mDefinition].Text then
      Continue;
    if Trim(ARequest.WorkFolder) = '' then
      Exit;
    // Schlanke Arbeitskopie nur des Ordners mit der Eigenschaft, im neuen Branch.
    mDir := TPath.Combine(ARequest.WorkFolder, 'p' + IntToStr(mDefinition));
    mUrl := '^/' + ARequest.Location;
    if ARequest.Definitions[mDefinition].Owner <> '' then
      mUrl := mUrl + '/' + ARequest.Definitions[mDefinition].Owner;
    ARewrites := ARewrites + [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', mUrl + '@', mDir, '--depth',
      'empty'), True, False)];
    mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('propset', 'svn:externals', '-F', mDir + '.txt', mDir),
      False, False);
    mStep.InputFile := mDir + '.txt';
    mStep.InputText := mTexts[mDefinition];
    mStep.Note := 'svn:externals: ' + Copy(mNotes[mDefinition], 3, MaxInt);
    ARewrites := ARewrites + [mStep];
    ARewrites := ARewrites + [TAtlasVcsBranchStep.Make(TArray<string>.Create('commit', mDir, '-m', AMessage), True,
      True)];
  end;
  Result := True;
end;

class function TAtlasVcsBranchPlan.Steps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mMessage: string;
  mCopy: TArray<string>;
  mPackages, mRewrites: TArray<TAtlasVcsBranchStep>;
begin
  Result := nil;
  if not SafeName(ARequest.Name) then
    Exit;
  case ARequest.Kind of
    TAtlasVcsKind.Git:
      begin
        // Basis ist ein Branch-Name aus Inspect; losgelöster HEAD hat keinen.
        if (ARequest.Base.Name <> '') and not SafeName(ARequest.Base.Name) then
          Exit;
        // --no-track: der neue Branch verfolgt nicht die Basis; den Upstream setzt erst der erste Push.
        // "--" am Ende: der Startpunkt ist eine Revision, nie ein Dateiname.
        Result := [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '--quiet', '--no-track', '-b',
          ARequest.Name, BaseRef(TAtlasVcsKind.Git, ARequest.Base), '--'), False, False)];
      end;
    TAtlasVcsKind.Svn:
      begin
        if not SafeName(ARequest.Base.Name) or not SafeName(ARequest.Location) or
          ((ARequest.Base.Revision <> '') and (StrToIntDef(ARequest.Base.Revision, -1) < 0)) then
          Exit;
        // Auschecken braucht einen Ordner, der keine Option ist.
        if (ARequest.After = TAtlasVcsSvnAfter.Checkout) and
          ((Trim(ARequest.CheckoutFolder) = '') or (ARequest.CheckoutFolder[1] = '-')) then
          Exit;
        mMessage := Trim(ARequest.Message);
        if mMessage = '' then
          mMessage := 'Branch ' + ARequest.Name;
        // Externals (#1291): erst die Packages, dann das Projekt, dann die Zeilen im neuen Branch.
        if not ExternalSteps(ARequest, mMessage, mPackages, mRewrites) then
          Exit;
        mCopy := TArray<string>.Create('copy', BaseRef(TAtlasVcsKind.Svn, ARequest.Base), '^/' + ARequest.Location +
          '@', '--parents', '-m', mMessage);
        if UsesPinExternals(ARequest) then
          mCopy := mCopy + ['--pin-externals'];
        // "@" am Ende des Ziels: ein "@" im Namen ist dann keine Revision.
        Result := mPackages + [TAtlasVcsBranchStep.Make(mCopy, True, True)] + mRewrites;
        case ARequest.After of
          TAtlasVcsSvnAfter.Switch:
            Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('switch', '^/' + ARequest.Location +
              '@', '.'), True, False, True)];
          TAtlasVcsSvnAfter.Checkout:
            Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '^/' +
              ARequest.Location + '@', ARequest.CheckoutFolder), True, False, True)];
        else
          // None: nur anlegen, die Arbeitskopie bleibt.
        end;
      end;
  else
    // Ohne Git oder SVN gibt es nichts anzulegen.
  end;
end;

class function TAtlasVcsBranchPlan.StepText(AKind: TAtlasVcsKind; const AStep: TAtlasVcsBranchStep): string;
var
  mArgument: string;
begin
  if AKind = TAtlasVcsKind.Svn then
    Result := 'svn'
  else
    Result := 'git';
  for mArgument in AStep.Arguments do
    if (mArgument = '') or (Pos(' ', mArgument) > 0) or (Pos('"', mArgument) > 0) then
      Result := Result + ' "' + StringReplace(mArgument, '"', '\"', [rfReplaceAll]) + '"'
    else
      Result := Result + ' ' + mArgument;
  // Was die Datei für propset enthält (#1291), in Klartext.
  if AStep.Note <> '' then
    Result := Result + '   (' + AStep.Note + ')';
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
      AProgress(mIndex, Length(ASteps), ASteps[mIndex]);
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
      Exit;
    try
      TDirectory.Delete(ARequest.WorkFolder, True);
    except
      // Netz: Ein Rest im Temp-Ordner stört nicht; der nächste Lauf versucht es erneut.
      on EInOutError do
        ;
      on EDirectoryNotFoundException do
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
    Exit;
  Result := VcsFullPath(AFolder, mRelative);
end;

class function TAtlasVcsBranchPlan.ServerStepsDone(const ASteps: TArray<TAtlasVcsBranchStep>;
  ADone: Integer): TArray<TAtlasVcsBranchStep>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ADone - 1 do
    if (mIndex <= High(ASteps)) and ASteps[mIndex].ChangesServer then
      Result := Result + [ASteps[mIndex]];
end;

end.
