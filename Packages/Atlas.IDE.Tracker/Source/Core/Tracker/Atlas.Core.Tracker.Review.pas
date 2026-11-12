unit Atlas.Core.Tracker.Review;

// „Prüfen“ für Issues im Prüfzustand (#2126), der Teil ohne IDE:
// - Angeboten wird „Prüfen“ für Issues, deren Zustand in issues.reviewStates
//   steht (ohne Groß-/Kleinschreibung); sonst nur über das Kontextmenü.
// - Branch des Issues: zuerst der nach dem Muster (issues.branchPattern), wenn
//   es ihn lokal oder entfernt gibt, dann jeder Branch, der die Kennung trägt
//   (wie der Reiter „Entwicklung“, #1269). Bei genau einem wechselt Atlas ohne
//   Rückfrage, sonst wählt der Benutzer; ohne Treffer aus allen Branches.
// - Schritte: eigener Stand gemerkt, Branch gewechselt, Build, Tests; jeder
//   wartet, läuft, ist fertig, gescheitert oder ausgelassen.
// - Rückweg: Git auf den eigenen Branch, SVN nur von einem Branch unter
//   ^/branches (SwitchBranch kennt nur diese), sonst kein Rückweg.
// - Build-Ergebnis aus dem Bericht des Builds auf Auftrag (Fehler, Warnungen,
//   Hinweise) und Kommentarvorlage issues.reviewComment mit {build}, {tests},
//   {branch} und {kennung}; die unveränderte Vorgabe folgt der Sprache der IDE.

interface

uses
  Atlas.Core.Build.Requests,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.VersionControl.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Schritte des Prüfens in ihrer Reihenfolge.</summary>
  TAtlasReviewStep = (Saved, Switched, Build, Tests);
  /// <summary>Stand eines Schritts.</summary>
  TAtlasReviewMark = (Waiting, Running, Done, Failed, Skipped);
{$SCOPEDENUMS OFF}

  /// <summary>Ergebnis des Builds: Plattform, Konfiguration und Zahl der Meldungen.</summary>
  TAtlasReviewBuild = record
    Platform: string;
    Configuration: string;
    Succeeded: Boolean;
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
  end;

  /// <summary>Stand einer Prüfung: Schritte, Branches, Build und Tests.</summary>
  TAtlasReviewState = record
    Marks: array[TAtlasReviewStep] of TAtlasReviewMark;
    /// <summary>Kennung des geprüften Issues.</summary>
    Key: string;
    /// <summary>Branch des Issues; '' noch nicht gewählt.</summary>
    Branch: string;
    /// <summary>Eigener Branch vor dem Wechsel; '' unbekannt (dann gibt es keinen Rückweg).</summary>
    OwnBranch: string;
    /// <summary>Eigenes aktuelles Issue vor dem Wechsel; '' ohne.</summary>
    OwnKey: string;
    /// <summary>Fehler beim Wechsel; '' ohne.</summary>
    SwitchError: string;
    Build: TAtlasReviewBuild;
    TestsPassed: Integer;
    TestsFailed: Integer;
    /// <summary>Alle Schritte warten; ohne AWithBuild sind Build und Tests ausgelassen.</summary>
    class function Create(const AKey: string; AWithBuild: Boolean): TAtlasReviewState; static;
    /// <summary>Läuft noch ein Schritt oder wartet einer?</summary>
    function Busy: Boolean;
    /// <summary>Gibt es einen Weg zurück auf den eigenen Branch?</summary>
    function CanReturn: Boolean;
    /// <summary>Build fertig: Marke und Ergebnis; ein gescheiterter Build lässt die Tests aus.</summary>
    procedure Built(const ABuild: TAtlasReviewBuild);
    /// <summary>Tests fertig: Marke und Zahlen; fehlgeschlagene Tests markieren den Schritt als gescheitert.
    /// </summary>
    procedure Tested(APassed, AFailed: Integer);
  end;

  TAtlasTrackerReview = class
  public const
    /// <summary>Vorgaben von issues.reviewComment in beiden Sprachen.</summary>
    cDefaultComment = 'Geprüft: {build}, {tests}.'; // german-ok: Vorgabe der Einstellung, wie issues.endComment
    cDefaultCommentEn = 'Reviewed: {build}, {tests}.';
    /// <summary>Auftraggeber des Builds auf Auftrag (IAtlasBuildRequests.Forget).</summary>
    cRequestedBy = 'atlas.tracker.review';
  public
    /// <summary>AState ist einer der Prüfzustände AReviewStates (ohne Groß-/Kleinschreibung und Rand).</summary>
    class function Offered(const AState: string; const AReviewStates: TArray<string>): Boolean; static;
    /// <summary>issues.reviewComment für die Oberfläche in AEnglish: Die unveränderte Vorgabe einer Sprache folgt
    /// der Sprache der IDE, jeder andere Text bleibt.</summary>
    class function CommentFor(const AStored: string; AEnglish: Boolean): string; static;
    /// <summary>Vorlage ATemplate mit {build}, {tests}, {branch} und {kennung} gefüllt, "\n" wird #10.</summary>
    class function Comment(const ATemplate, AKey, ABranch, ABuild, ATests: string): string; static;
    /// <summary>Branches des Issues zum Wechseln: APlanned (Muster), wenn es ihn in ARefs gibt, dann die mit der
    /// Kennung aus ARequest; ohne doppelte Namen.</summary>
    class function Candidates(const ARequest: TAtlasIssueDevelopmentRequest; const APlanned: string;
      const ARefs: TArray<TAtlasVcsRef>): TArray<string>; static;
    /// <summary>Alle Namen zum Wechseln aus ARefs (lokal und entfernt zusammen), nach Namen geordnet.</summary>
    class function AllBranches(const ARefs: TArray<TAtlasVcsRef>): TArray<string>; static;
    /// <summary>Ergebnis des Builds aus dem Bericht AReport: Fehler (samt fatalen), Warnungen und Hinweise.
    /// </summary>
    class function BuildOf(const AReport: TAtlasBuildReport): TAtlasReviewBuild; static;
    /// <summary>Name für den Rückweg (SwitchBranch) aus dem Stand AHead: Git der Branch (losgelöst ''), SVN nur
    /// unter branches/ ohne das Präfix; trunk, Tags und Unbekanntes haben keinen Rückweg ('').</summary>
    class function ReturnName(AKind: TAtlasVcsKind; const AHead: TAtlasVcsHead): string; static;
    /// <summary>Zeile AIssue in „Meine Issues“ bietet „Prüfen …“ statt „Beginnen“: Zustand in den Prüfzuständen der
    /// Ansicht, Git oder SVN, nicht das aktuelle Issue.</summary>
    class function Reviews(const AView: TAtlasIssuesView; const AIssue: TAtlasTrackerIssue): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Build.Messages,
  Atlas.Core.Tracker.Workflow;

{ TAtlasReviewState }

class function TAtlasReviewState.Create(const AKey: string; AWithBuild: Boolean): TAtlasReviewState;
var
  mStep: TAtlasReviewStep;
begin
  Result := Default(TAtlasReviewState);
  Result.Key := AKey;
  for mStep := Low(TAtlasReviewStep) to High(TAtlasReviewStep) do
  begin
    Result.Marks[mStep] := TAtlasReviewMark.Waiting;
  end;
  if not AWithBuild then
  begin
    Result.Marks[TAtlasReviewStep.Build] := TAtlasReviewMark.Skipped;
    Result.Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Skipped;
  end;
end;

function TAtlasReviewState.Busy: Boolean;
var
  mMark: TAtlasReviewMark;
begin
  Result := False;
  for mMark in Marks do
  begin
    if (mMark = TAtlasReviewMark.Waiting) or (mMark = TAtlasReviewMark.Running) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasReviewState.CanReturn: Boolean;
begin
  Result := (OwnBranch <> '') and (Marks[TAtlasReviewStep.Switched] = TAtlasReviewMark.Done) and
    not SameText(OwnBranch, Branch);
end;

procedure TAtlasReviewState.Built(const ABuild: TAtlasReviewBuild);
begin
  Build := ABuild;
  if ABuild.Succeeded then
  begin
    Marks[TAtlasReviewStep.Build] := TAtlasReviewMark.Done;
  end
  else
  begin
    Marks[TAtlasReviewStep.Build] := TAtlasReviewMark.Failed;
    Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Skipped;
  end;
end;

procedure TAtlasReviewState.Tested(APassed, AFailed: Integer);
begin
  TestsPassed := APassed;
  TestsFailed := AFailed;
  if AFailed > 0 then
  begin
    Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Failed;
  end
  else
  begin
    Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Done;
  end;
end;

{ TAtlasTrackerReview }

class function TAtlasTrackerReview.Offered(const AState: string; const AReviewStates: TArray<string>): Boolean;
var
  mState: string;
begin
  Result := False;
  if Trim(AState) = '' then
  begin
    Exit;
  end;
  for mState in AReviewStates do
  begin
    if SameText(Trim(mState), Trim(AState)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTrackerReview.CommentFor(const AStored: string; AEnglish: Boolean): string;
begin
  Result := AStored;
  if (AStored = cDefaultComment) and AEnglish then
  begin
    Result := cDefaultCommentEn;
  end
  else if (AStored = cDefaultCommentEn) and not AEnglish then
  begin
    Result := cDefaultComment;
  end;
end;

class function TAtlasTrackerReview.Comment(const ATemplate, AKey, ABranch, ABuild, ATests: string): string;
var
  mText: string;
begin
  mText := StringReplace(ATemplate, '{build}', ABuild, [rfReplaceAll, rfIgnoreCase]);
  mText := StringReplace(mText, '{tests}', ATests, [rfReplaceAll, rfIgnoreCase]);
  Result := TAtlasTrackerWorkflow.Fill(mText, TAtlasTrackerPlaceholders.Create(AKey, ABranch));
end;

/// <summary>AName an AList anhängen, wenn er dort noch fehlt (ohne Groß-/Kleinschreibung).</summary>
procedure AddUnique(var AList: TArray<string>; const AName: string);
var
  mName: string;
begin
  if AName = '' then
  begin
    Exit;
  end;
  for mName in AList do
  begin
    if SameText(mName, AName) then
    begin
      Exit;
    end;
  end;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AName;
end;

class function TAtlasTrackerReview.Candidates(const ARequest: TAtlasIssueDevelopmentRequest;
  const APlanned: string; const ARefs: TArray<TAtlasVcsRef>): TArray<string>;
var
  mRef: TAtlasVcsRef;
  mBranch: TAtlasIssueBranch;
begin
  Result := nil;
  if Trim(APlanned) <> '' then
  begin
    for mRef in ARefs do
    begin
      if SameText(mRef.LocalName, Trim(APlanned)) then
      begin
        AddUnique(Result, mRef.LocalName);
      end;
    end;
  end;
  for mBranch in TAtlasIssueDevelopmentQuery.BranchesOf(ARequest, ARefs) do
  begin
    AddUnique(Result, mBranch.Name);
  end;
end;

class function TAtlasTrackerReview.AllBranches(const ARefs: TArray<TAtlasVcsRef>): TArray<string>;
var
  mRef: TAtlasVcsRef;
begin
  Result := nil;
  for mRef in ARefs do
  begin
    AddUnique(Result, mRef.LocalName);
  end;
  // Gleich ohne Groß-/Kleinschreibung gibt es nach AddUnique nicht mehr: die Reihenfolge ist eindeutig.
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(ALeft, ARight);
    end));
end;

class function TAtlasTrackerReview.BuildOf(const AReport: TAtlasBuildReport): TAtlasReviewBuild;
var
  mMessage: TAtlasCompilerMessage;
begin
  Result := Default(TAtlasReviewBuild);
  Result.Platform := AReport.Project.Platform;
  Result.Configuration := AReport.Project.Configuration;
  for mMessage in AReport.Messages do
  begin
    if mMessage.Severity in [TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal] then
    begin
      Inc(Result.Errors);
    end
    else if mMessage.Severity = TAtlasCompilerSeverity.Warning then
    begin
      Inc(Result.Warnings);
    end
    else if mMessage.Severity = TAtlasCompilerSeverity.Hint then
    begin
      Inc(Result.Hints);
    end;
  end;
  Result.Succeeded := AReport.Succeeded and (Result.Errors = 0);
end;

class function TAtlasTrackerReview.Reviews(const AView: TAtlasIssuesView; const AIssue: TAtlasTrackerIssue): Boolean;
begin
  Result := (AView.VcsKind in [TAtlasVcsKind.Git, TAtlasVcsKind.Svn]) and
    not SameText(AIssue.Key, AView.Active.Key) and Offered(AIssue.State, AView.ReviewStates);
end;

class function TAtlasTrackerReview.ReturnName(AKind: TAtlasVcsKind; const AHead: TAtlasVcsHead): string;
const
  cSvnBranches = 'branches/';
begin
  Result := '';
  if (AKind = TAtlasVcsKind.Git) and not AHead.Detached then
  begin
    Result := Trim(AHead.Branch);
  end
  else if (AKind = TAtlasVcsKind.Svn) and AHead.Branch.StartsWith(cSvnBranches, True) then
  begin
    Result := Trim(Copy(AHead.Branch, Length(cSvnBranches) + 1, MaxInt));
  end;
end;

end.
