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
//   copy ^/<Basis>@<Revision> ^/branches/<Name>@ --parents -m <Nachricht>
//   switch ^/branches/<Name>@ .
//   Basis: Hauptbranch @ HEAD (mit der Revision, die der Dialog vom Server
//   geholt hat; ohne sie zum Zeitpunkt des Kopierens) oder der Pfad der
//   Arbeitskopie @ ihrer Revision. Die Kopie ändert den Server und wird bei
//   einem späteren Fehler nicht zurückgenommen.
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
// Die Optionen aus #1290 (SVN) und #1291 (Externals) kommen als weitere
// Felder der Anfrage und weitere Schritte hinzu.
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
    /// <summary>Git (#1289): Remote des lokalen Hauptbranchs (verfolgter Branch), sonst origin.</summary>
    Remote: string;
    /// <summary>Geänderte Dateien der Arbeitskopie (ohne unversionierte); setzt der Aufrufer, Inspect nicht.
    /// </summary>
    LocalChanges: Integer;
    /// <summary>Wurzel der Arbeitskopie (WorkingCopy.Root); Git: Bezug für den worktree-Ordner.</summary>
    Root: string;
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
  private
    /// <summary>Git: Remote des lokalen Hauptbranchs; liegt der Hauptbranch dort, RemoteMain.</summary>
    class procedure InspectRemote(const AVcs: IAtlasVersionControl; var AFacts: TAtlasVcsBranchFacts); static;
    class function GitSteps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>; static;
    /// <summary>Platzhalterwert für einen Ordnernamen: Trenner und unter Windows verbotene Zeichen werden „-“.
    /// </summary>
    class function FolderPart(const AText: string): string; static;
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
      static;
    /// <summary>Vorgabe nach den Git-Optionen (#1289): remote origin vor lokal, local wie oben, current der
    /// aktuelle Branch (sonst der lokale Hauptbranch). SVN wie oben.</summary>
    class function DefaultBase(const AFacts: TAtlasVcsBranchFacts; const AOptions: TAtlasVcsGitBranchOptions;
      out ABase: TAtlasVcsBranchBase): Boolean; overload; static;
    /// <summary>Anfrage mit der Vorgabe-Basis (für „Beginnen“ ohne Dialog); False ohne Basis.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Wie oben nach den Git-Optionen (#1289): Basis, Abruf (nur Basis vom Server), Push, stash (nur
    /// Stash; Ask entscheidet der Aufrufer) und worktree-Ordner (WorktreePath mit AKey).</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage, AKey: string;
      const AOptions: TAtlasVcsGitBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean; overload; static;
    /// <summary>Ordner für git worktree (#1289): APattern ('' = Vorgabe) mit {repo} (Ordnername von ARoot),
    /// {name} (AName) und {kennung} (AKey, ohne Issue AName); relativ zu ARoot, vollständig. '' ohne ARoot.
    /// </summary>
    class function WorktreePath(const ARoot, APattern, AName, AKey: string): string; static;
    /// <summary>Ordner taugt für git worktree add: vollständig, keine Steuerzeichen, nicht mit „-“.</summary>
    class function SafeFolder(const AFolder: string): Boolean; static;
    /// <summary>AProject (unter ARoot) im worktree AFolder; '' wenn AProject nicht unter ARoot liegt.</summary>
    class function ProjectInFolder(const AProject, ARoot, AFolder: string): string; static;
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
    /// <summary>Die ersten ADone Schritte, die den Server geändert haben (für die Meldung nach einem Fehler).
    /// </summary>
    class function ServerStepsDone(const ASteps: TArray<TAtlasVcsBranchStep>;
      ADone: Integer): TArray<TAtlasVcsBranchStep>; static;
  end;

implementation

uses
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
    Result.Base := TAtlasVcsGitBaseOption.Local
  else if SameText(Trim(ABase), 'current') then
    Result.Base := TAtlasVcsGitBaseOption.Current;
  Result.PushNow := SameText(Trim(APush), 'now');
  Result.Uncommitted := TAtlasVcsGitUncommitted.Carry;
  if SameText(Trim(AUncommitted), 'stash') then
    Result.Uncommitted := TAtlasVcsGitUncommitted.Stash
  else if SameText(Trim(AUncommitted), 'ask') then
    Result.Uncommitted := TAtlasVcsGitUncommitted.Ask;
  Result.Worktree := AWorktree;
  Result.WorktreeFolder := Trim(AWorktreeFolder);
  if Result.WorktreeFolder = '' then
    Result.WorktreeFolder := DefaultWorktreeFolder;
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
    Result := cDefaultRemote;
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
  Result.Remote := '';
  Result.LocalChanges := 0;
  Result.Root := '';
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

class function TAtlasVcsBranchPlan.Inspect(const AVcs: IAtlasVersionControl;
  const ACandidates: TArray<string>): TAtlasVcsBranchFacts;
var
  mBranching: IAtlasVcsBranching;
  mHead: TAtlasVcsHead;
  mCandidate, mPath: string;
  mLocal, mRemote: Boolean;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  if (AVcs = nil) or not Supports(AVcs, IAtlasVcsBranching, mBranching) then
    Exit;
  Result.Kind := AVcs.Kind;
  if (Result.Kind <> TAtlasVcsKind.Git) and (Result.Kind <> TAtlasVcsKind.Svn) then
    Exit;
  Result.Root := AVcs.WorkingCopy.Root;
  Result.Outcome := AVcs.Head(mHead);
  if Result.Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  Result.Current := mHead.Branch;
  if Result.Kind = TAtlasVcsKind.Svn then
  begin
    Result.Revision := mHead.Revision;
    // Voller Pfad ("Kasse/trunk"): Head.Branch kürzt auf "trunk", die Kopie braucht den ganzen.
    if (mBranching.RepositoryPath(mPath) = TAtlasVcsOutcome.Ok) and (mPath <> '') then
      Result.Current := mPath;
    for mCandidate in ACandidates do
      if SafeName(mCandidate) then
      begin
        Result.MainBranch := mCandidate;
        Break;
      end;
    // Externals sind nur ein Hinweis im Dialog: ein Fehler hier hält das Anlegen nicht auf.
    if mBranching.HasExternals(Result.Externals) <> TAtlasVcsOutcome.Ok then
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
      Break;
    end;
  end;
  InspectRemote(AVcs, Result);
end;

class procedure TAtlasVcsBranchPlan.InspectRemote(const AVcs: IAtlasVersionControl;
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
    Exit;
  for mBranch in mBranches do
    if (mBranch.Name = AFacts.MainBranch) and SafeName(mBranch.Remote) then
      AFacts.Remote := mBranch.Remote;
  // RemoteBranchExists kennt nur origin: bei einem anderen Remote dessen Stand des letzten Abrufs.
  if (AFacts.Remote <> cDefaultRemote) and Supports(AVcs, IAtlasVcsIncoming, mIncoming) then
    AFacts.RemoteMain := mIncoming.Resolve('refs/remotes/' + AFacts.Remote + '/' + AFacts.MainBranch,
      mRevision) = TAtlasVcsOutcome.Ok;
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
    // Remote an jeder Basis: Abruf und Push gehen an den Remote des Hauptbranchs.
    if AFacts.RemoteMain then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, AFacts.MainBranch, '',
        AFacts.Remote)];
    if AFacts.LocalMain then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, AFacts.MainBranch, '',
        AFacts.Remote)];
    // Der aktuelle Branch nur, wenn er nicht schon als lokaler Hauptbranch dasteht.
    if not AFacts.LocalMain or (AFacts.Current <> AFacts.MainBranch) then
      Result := Result + [TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, AFacts.Current, '',
        AFacts.Remote)];
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
  // Wie „Beginnen“ bisher (#765): lokal vor origin; SVN der Hauptbranch.
  Result := DefaultBase(AFacts, TAtlasVcsGitBranchOptions.Classic, ABase);
end;

class function TAtlasVcsBranchPlan.DefaultBase(const AFacts: TAtlasVcsBranchFacts;
  const AOptions: TAtlasVcsGitBranchOptions; out ABase: TAtlasVcsBranchBase): Boolean;
var
  mBase: TAtlasVcsBranchBase;
  mBases: TArray<TAtlasVcsBranchBase>;
  mPreferred: TArray<TAtlasVcsBranchBaseKind>;
  mKind: TAtlasVcsBranchBaseKind;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  mBases := Bases(AFacts);
  case AOptions.Base of
    TAtlasVcsGitBaseOption.Remote:
      mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.RemoteMain,
        TAtlasVcsBranchBaseKind.LocalMain, TAtlasVcsBranchBaseKind.Head);
    // Der aktuelle Branch ausdrücklich gewählt; steht er schon als lokaler Hauptbranch da, dieser.
    TAtlasVcsGitBaseOption.Current:
      mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.Current,
        TAtlasVcsBranchBaseKind.LocalMain, TAtlasVcsBranchBaseKind.Head);
  else
    mPreferred := TArray<TAtlasVcsBranchBaseKind>.Create(TAtlasVcsBranchBaseKind.LocalMain,
      TAtlasVcsBranchBaseKind.RemoteMain, TAtlasVcsBranchBaseKind.Head);
  end;
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

class function TAtlasVcsBranchPlan.DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
  AKey: string; const AOptions: TAtlasVcsGitBranchOptions; out ARequest: TAtlasVcsBranchRequest): Boolean;
var
  mBase: TAtlasVcsBranchBase;
begin
  Result := DefaultBase(AFacts, AOptions, mBase);
  ARequest := TAtlasVcsBranchRequest.Make(AFacts.Kind, AName, mBase, AMessage);
  if AFacts.Kind <> TAtlasVcsKind.Git then
    Exit;
  ARequest.Fetch := (AOptions.Base = TAtlasVcsGitBaseOption.Remote) and
    (mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  ARequest.PushNow := AOptions.PushNow;
  if AOptions.Worktree then
    ARequest.WorktreeFolder := WorktreePath(AFacts.Root, AOptions.WorktreeFolder, AName, AKey)
  else
    ARequest.Stash := AOptions.Uncommitted = TAtlasVcsGitUncommitted.Stash;
end;

class function TAtlasVcsBranchPlan.FolderPart(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(AText);
  for mIndex := 1 to Length(Result) do
    if (Ord(Result[mIndex]) < 32) or CharInSet(Result[mIndex], ['/', '\', ':', '*', '?', '"', '<', '>', '|']) then
      Result[mIndex] := '-';
end;

class function TAtlasVcsBranchPlan.WorktreePath(const ARoot, APattern, AName, AKey: string): string;
var
  mRoot, mKey: string;
begin
  mRoot := ExcludeTrailingPathDelimiter(Trim(ARoot));
  if mRoot = '' then
    Exit('');
  Result := Trim(APattern);
  if Result = '' then
    Result := TAtlasVcsGitBranchOptions.DefaultWorktreeFolder;
  mKey := FolderPart(AKey);
  // Ohne Issue (Befehl „Branch anlegen …“) steht der Name an Stelle der Kennung.
  if mKey = '' then
    mKey := FolderPart(AName);
  Result := StringReplace(Result, '{repo}', FolderPart(ExtractFileName(mRoot)), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{name}', FolderPart(AName), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{kennung}', mKey, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(StringReplace(Result, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  // Vollständig: Laufwerk, UNC bzw. Wurzel; sonst relativ zur Wurzel der Arbeitskopie.
  if not ((Length(Result) > 1) and (Result[2] = ':')) and not ((Result <> '') and (Result[1] = PathDelim)) then
    Result := mRoot + PathDelim + Result;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
end;

class function TAtlasVcsBranchPlan.SafeFolder(const AFolder: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AFolder <> '') and (AFolder[1] <> '-') and (AFolder = Trim(AFolder)) and
    (((Length(AFolder) > 1) and (AFolder[2] = ':')) or (AFolder[1] = PathDelim));
  if not Result then
    Exit;
  for mIndex := 1 to Length(AFolder) do
    if Ord(AFolder[mIndex]) < 32 then
      Exit(False);
end;

class function TAtlasVcsBranchPlan.ProjectInFolder(const AProject, ARoot, AFolder: string): string;
var
  mRoot: string;
begin
  Result := '';
  mRoot := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Trim(ARoot)));
  if (Trim(ARoot) = '') or (AFolder = '') or not SameText(Copy(AProject, 1, Length(mRoot)), mRoot) then
    Exit;
  Result := IncludeTrailingPathDelimiter(AFolder) + Copy(AProject, Length(mRoot) + 1, MaxInt);
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
    Result.Base := mBase;
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
      Result := 'refs/remotes/' + ABase.RemoteName + '/' + ABase.Name;
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
    Result := ABase.RemoteName + '/' + Result
  else if Result = '' then
    Result := 'HEAD';
end;

class function TAtlasVcsBranchPlan.Steps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mMessage: string;
begin
  Result := nil;
  if not SafeName(ARequest.Name) then
    Exit;
  case ARequest.Kind of
    TAtlasVcsKind.Git:
      Result := GitSteps(ARequest);
    TAtlasVcsKind.Svn:
      begin
        if not SafeName(ARequest.Base.Name) or
          ((ARequest.Base.Revision <> '') and (StrToIntDef(ARequest.Base.Revision, -1) < 0)) then
          Exit;
        mMessage := Trim(ARequest.Message);
        if mMessage = '' then
          mMessage := 'Branch ' + ARequest.Name;
        // "@" am Ende des Ziels: ein "@" im Namen ist dann keine Revision.
        Result := [TAtlasVcsBranchStep.Make(TArray<string>.Create('copy', BaseRef(TAtlasVcsKind.Svn, ARequest.Base),
          '^/branches/' + ARequest.Name + '@', '--parents', '-m', mMessage), True, True),
          TAtlasVcsBranchStep.Make(TArray<string>.Create('switch', '^/branches/' + ARequest.Name + '@', '.'), True,
          False)];
      end;
  else
    // Ohne Git oder SVN gibt es nichts anzulegen.
  end;
end;

class function TAtlasVcsBranchPlan.GitSteps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mRemote: string;
begin
  Result := nil;
  mRemote := ARequest.Base.RemoteName;
  // Basis ist ein Branch-Name aus Inspect; losgelöster HEAD hat keinen.
  if ((ARequest.Base.Name <> '') and not SafeName(ARequest.Base.Name)) or not SafeName(mRemote) then
    Exit;
  if (ARequest.WorktreeFolder <> '') and not SafeFolder(ARequest.WorktreeFolder) then
    Exit;
  // Basis vom Server (#1289): vorher genau den Hauptbranch abrufen; ohne Rückfrage nach Zugangsdaten.
  if ARequest.Fetch and (ARequest.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain) then
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('fetch', '--quiet', '--no-tags', mRemote,
      ARequest.Base.Name), True, False)];
  // --no-track: der neue Branch verfolgt nicht die Basis; den Upstream setzt erst der (erste) Push.
  if ARequest.WorktreeFolder <> '' then
    // Eigener Ordner: die Arbeitskopie bleibt, wie sie ist; offene Änderungen bleiben dort.
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('worktree', 'add', '--quiet', '--no-track',
      '-b', ARequest.Name, ARequest.WorktreeFolder, BaseRef(TAtlasVcsKind.Git, ARequest.Base)), False, False)]
  else
  begin
    if ARequest.Stash then
      Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('stash', 'push', '--include-untracked',
        '--quiet', '-m', StashMessage(ARequest.Name)), False, False)];
    // "--" am Ende: der Startpunkt ist eine Revision, nie ein Dateiname.
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '--quiet', '--no-track', '-b',
      ARequest.Name, BaseRef(TAtlasVcsKind.Git, ARequest.Base), '--'), False, False)];
  end;
  if ARequest.PushNow then
    Result := Result + [TAtlasVcsBranchStep.Make(TArray<string>.Create('push', '--set-upstream', mRemote,
      'refs/heads/' + ARequest.Name + ':refs/heads/' + ARequest.Name), True, True)];
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
