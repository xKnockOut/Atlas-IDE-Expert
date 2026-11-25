unit Atlas.IDE.Tracker.Adapters.CommentAssist;

// Kommentar-Editor (#1278), Rolle Adapters: TAtlasCommentAssistAdapter erfüllt
// IAtlasCommentAssist aus Atlas.Core.Tracker.Contract.CommentAssist und
// reicht an TAtlasIdeCommentAssist (Atlas.IDE.Tracker.CommentAssist) weiter;
// hält die Hilfe, solange das Feld den Adapter hält. Die Komposition reicht
// Adapt als Hook an „Meine Issues“ (TAtlasIdeIssuesHooks.CommentAssist).

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.CommentAssist,
  Atlas.IDE.Tracker.CommentAssist;

type
  /// <summary>Hilfe eines Kommentarfelds über AAssist.</summary>
  TAtlasCommentAssistAdapter = class(TInterfacedObject, IAtlasCommentAssist)
  private
    FAssist: TAtlasIdeCommentAssist;
    FAssistRef: IInterface;
  public
    constructor Create(AAssist: TAtlasIdeCommentAssist);
    function Target: TAtlasTrackerTarget;
    function Snippets: TArray<TAtlasCommentSnippet>;
    procedure FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
    procedure FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
    procedure Values(const ADone: TAtlasCommentValuesDone);
    procedure Cancel;
    function LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
    procedure SaveDraft(const AText: string);
    procedure DeleteDraft;
  end;

implementation

{ TAtlasCommentAssistAdapter }

constructor TAtlasCommentAssistAdapter.Create(AAssist: TAtlasIdeCommentAssist);
begin
  inherited Create;
  FAssist := AAssist;
  FAssistRef := AAssist;
end;

function TAtlasCommentAssistAdapter.Target: TAtlasTrackerTarget;
begin
  Result := FAssist.Target;
end;

function TAtlasCommentAssistAdapter.Snippets: TArray<TAtlasCommentSnippet>;
begin
  Result := FAssist.Snippets;
end;

procedure TAtlasCommentAssistAdapter.FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
begin
  FAssist.FindUsers(AText, ADone);
end;

procedure TAtlasCommentAssistAdapter.FindIssues(const AQuery: TAtlasIssueSearchQuery;
  const ADone: TAtlasCommentIssuesDone);
begin
  FAssist.FindIssues(AQuery, ADone);
end;

procedure TAtlasCommentAssistAdapter.Values(const ADone: TAtlasCommentValuesDone);
begin
  FAssist.Values(ADone);
end;

procedure TAtlasCommentAssistAdapter.Cancel;
begin
  FAssist.Cancel;
end;

function TAtlasCommentAssistAdapter.LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
begin
  Result := FAssist.LoadDraft(AText, ASaved);
end;

procedure TAtlasCommentAssistAdapter.SaveDraft(const AText: string);
begin
  FAssist.SaveDraft(AText);
end;

procedure TAtlasCommentAssistAdapter.DeleteDraft;
begin
  FAssist.DeleteDraft;
end;

end.
