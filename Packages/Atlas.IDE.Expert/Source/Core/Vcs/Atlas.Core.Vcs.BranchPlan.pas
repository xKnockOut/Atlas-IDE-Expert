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
// Die Optionen aus #1289 (Git), #1290 (SVN) und #1291 (Externals) kommen als
// weitere Felder der Anfrage und weitere Schritte hinzu.
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
      static;
    /// <summary>Anfrage mit der Vorgabe-Basis (für „Beginnen“ ohne Dialog); False ohne Basis.</summary>
    class function DefaultRequest(const AFacts: TAtlasVcsBranchFacts; const AName, AMessage: string;
      out ARequest: TAtlasVcsBranchRequest): Boolean; static;
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
var
  mBase: TAtlasVcsBranchBase;
  mBases: TArray<TAtlasVcsBranchBase>;
  mPreferred: TArray<TAtlasVcsBranchBaseKind>;
  mKind: TAtlasVcsBranchBaseKind;
begin
  ABase := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, '', '');
  mBases := Bases(AFacts);
  // Wie „Beginnen“ bisher (#765): lokal vor origin; SVN der Hauptbranch.
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

class function TAtlasVcsBranchPlan.Steps(const ARequest: TAtlasVcsBranchRequest): TArray<TAtlasVcsBranchStep>;
var
  mMessage: string;
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
