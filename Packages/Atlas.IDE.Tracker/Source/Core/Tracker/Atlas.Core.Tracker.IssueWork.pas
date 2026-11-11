unit Atlas.Core.Tracker.IssueWork;

// Zustand eines Issues für den Arbeitsstand je Issue (#2052), ohne VCL und
// Open Tools API. Der Tracker beantwortet die Frage der Willkommensseite
// „offen oder behoben?“ ohne eigene Abfrage aus dem, was er schon hat:
// - Stand der Vorschau im Zwischenspeicher (#1264): GitHub „closed …“ gilt als
//   behoben; YouTrack die Zielzustände aus issues.endStates (#1266, wie im
//   Dialog „Beenden“) und übliche englische Namen erledigter Zustände.
// - Liste „Meine Issues“: Steht das Issue in der letzten Abfrage, gilt es als
//   offen, solange kein frischer Stand der Vorschau etwas anderes sagt.
// - Sonst unbekannt (ohne Netz); der Aufrufer fragt im Hintergrund nach.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand eines Issues: unbekannt, offen oder behoben bzw. geschlossen.</summary>
  TAtlasTrackerResolution = (Unknown, Open, Resolved);
{$SCOPEDENUMS OFF}

  /// <summary>Was der Tracker über ein Issue weiß.</summary>
  TAtlasTrackerIssueFacts = record
    /// <summary>Anbieter ("github", "youtrack").</summary>
    Provider: string;
    /// <summary>Steht in der letzten Liste „Meine Issues“.</summary>
    InList: Boolean;
    /// <summary>Stand der Vorschau liegt im Zwischenspeicher.</summary>
    Cached: Boolean;
    /// <summary>Dieser Stand ist frisch (TAtlasIdeIssueLookups.Fresh).</summary>
    Fresh: Boolean;
    /// <summary>Zustand laut Vorschau ("open", "closed", "Fixed" …).</summary>
    State: string;
    /// <summary>Zielzustände aus issues.endStates.</summary>
    EndStates: TArray<string>;
    class function Empty: TAtlasTrackerIssueFacts; static;
  end;

  TAtlasTrackerIssueStates = class
  public const
    cGitHub = 'github';
  public
    /// <summary>Gilt AState als erledigt? GitHub: beginnt mit "closed"; sonst Zustand in AEndStates oder einer der
    /// üblichen englischen Namen (Fixed, Done, Closed, Resolved, Verified …), ohne Groß-/Kleinschreibung.</summary>
    class function IsResolvedState(const AProvider, AState: string; const AEndStates: TArray<string>): Boolean;
      static;
    /// <summary>Zustand aus AFacts: frischer Stand der Vorschau, sonst die Liste (offen), sonst ein älterer Stand,
    /// sonst unbekannt.</summary>
    class function StatusOf(const AFacts: TAtlasTrackerIssueFacts): TAtlasTrackerResolution; static;
    /// <summary>Nachfragen lohnt sich: kein frischer Stand der Vorschau.</summary>
    class function NeedsLookup(const AFacts: TAtlasTrackerIssueFacts): Boolean; static;
  end;

implementation

const
  /// <summary>Übliche Namen erledigter Zustände (YouTrack-Vorlagen, englisch).</summary>
  cResolvedNames: array[0..10] of string = ('fixed', 'done', 'closed', 'resolved', 'verified', 'completed',
    'won''t fix', 'duplicate', 'obsolete', 'can''t reproduce', 'incomplete');

{ TAtlasTrackerIssueFacts }

class function TAtlasTrackerIssueFacts.Empty: TAtlasTrackerIssueFacts;
begin
  Result := Default(TAtlasTrackerIssueFacts);
end;

{ TAtlasTrackerIssueStates }

class function TAtlasTrackerIssueStates.IsResolvedState(const AProvider, AState: string;
  const AEndStates: TArray<string>): Boolean;
var
  mState, mName: string;
begin
  mState := Trim(AState);
  if mState = '' then
  begin
    Exit(False);
  end;
  if SameText(Trim(AProvider), cGitHub) then
  begin
    Exit(SameText(Copy(mState, 1, 6), 'closed'));
  end;
  for mName in AEndStates do
  begin
    if SameText(Trim(mName), mState) then
    begin
      Exit(True);
    end;
  end;
  for mName in cResolvedNames do
  begin
    if SameText(mName, mState) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTrackerIssueStates.StatusOf(const AFacts: TAtlasTrackerIssueFacts): TAtlasTrackerResolution;
begin
  if AFacts.Cached and (AFacts.Fresh or not AFacts.InList) then
  begin
    if IsResolvedState(AFacts.Provider, AFacts.State, AFacts.EndStates) then
    begin
      Exit(TAtlasTrackerResolution.Resolved);
    end;
    Exit(TAtlasTrackerResolution.Open);
  end;
  if AFacts.InList then
  begin
    Exit(TAtlasTrackerResolution.Open);
  end;
  Result := TAtlasTrackerResolution.Unknown;
end;

class function TAtlasTrackerIssueStates.NeedsLookup(const AFacts: TAtlasTrackerIssueFacts): Boolean;
begin
  Result := not (AFacts.Cached and AFacts.Fresh);
end;

end.
