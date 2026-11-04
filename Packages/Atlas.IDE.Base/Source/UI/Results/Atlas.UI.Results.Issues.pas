unit Atlas.UI.Results.Issues;

// Issues zu einer Methode (#1275) im Ergebnisfenster: je Issue eine Zeile, die Commits zugeklappt darunter. Klick
// (oder Enter) auf ein Issue meldet OnOpen, Doppelklick (oder Enter) auf einen Commit OnCommit. SetText ersetzt den
// Text eines Issues, sobald Titel und Zustand geladen sind.

interface

uses
  Vcl.ComCtrls,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.View;

type
  /// <summary>Issue bzw. Commit (#1275) der Liste AList gewählt; AId wie in TAtlasResultIssue bzw.
  /// TAtlasResultCommit.</summary>
  TAtlasResultsIssueAction = reference to procedure(AList, AId: Integer);

  TAtlasResultsIssuesPart = class(TAtlasResultsPart)
  private type
    THandlers = record
      OnOpen: TAtlasResultsIssueAction;
      OnCommit: TAtlasResultsIssueAction;
    end;
  private
    FHandlers: THandlers;
    FShows: Boolean;
    FList: Integer;
  protected
    procedure Reset; override;
    function Open(const AData: TAtlasResultsNode): Boolean; override;
    procedure Click(ANode: TTreeNode); override;
  public
    /// <summary>Issues zu einer Methode bzw. Unit: je Issue eine Zeile, die Commits zugeklappt darunter. AList
    /// kennzeichnet die Liste für OnOpen, OnCommit und SetText.</summary>
    procedure Show(const ATitle: string; AList: Integer; const AIssues: TArray<TAtlasResultIssue>);
    /// <summary>Text des Issues AId ersetzen, solange die Liste AList gezeigt wird; False sonst.</summary>
    function SetText(AList, AId: Integer; const AText: string): Boolean;
    /// <summary>Gewähltes Issue öffnen bzw. Commit zeigen (Klick, Doppelklick, Enter).</summary>
    procedure OpenSelected;
    /// <summary>Zeigt gerade Issues zu einer Methode.</summary>
    property Shows: Boolean read FShows;
    property List: Integer read FList;
    property OnOpen: TAtlasResultsIssueAction read FHandlers.OnOpen write FHandlers.OnOpen;
    property OnCommit: TAtlasResultsIssueAction read FHandlers.OnCommit write FHandlers.OnCommit;
  end;

implementation

{ TAtlasResultsIssuesPart }

procedure TAtlasResultsIssuesPart.Reset;
begin
  FShows := False;
end;

procedure TAtlasResultsIssuesPart.Show(const ATitle: string; AList: Integer;
  const AIssues: TArray<TAtlasResultIssue>);
var
  mIssue: TAtlasResultIssue;
  mCommit: TAtlasResultCommit;
  mData: TAtlasResultsNode;
  mNode: TTreeNode;
begin
  View.Clear(ATitle);
  FShows := True;
  FList := AList;
  View.Tree.Items.BeginUpdate;
  try
    for mIssue in AIssues do
    begin
      mData := TAtlasResultsNode.Create(TAtlasResultsNodeKind.Issue);
      mData.SetId := mIssue.Id;
      mNode := View.AddNode(nil, mIssue.Text, mData);
      for mCommit in mIssue.Commits do
      begin
        mData := TAtlasResultsNode.Create(TAtlasResultsNodeKind.Commit);
        mData.SetId := mCommit.Id;
        View.AddNode(mNode, mCommit.Text, mData);
      end;
    end;
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(nil);
end;

function TAtlasResultsIssuesPart.SetText(AList, AId: Integer; const AText: string): Boolean;
var
  mNode: TTreeNode;
  mData: TAtlasResultsNode;
begin
  Result := False;
  if not FShows or (AList <> FList) then
  begin
    Exit;
  end;
  mNode := View.Tree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    mData := View.DataOf(mNode);
    if (mData.Kind = TAtlasResultsNodeKind.Issue) and (mData.SetId = AId) then
    begin
      mNode.Text := AText;
      Exit(True);
    end;
    mNode := mNode.getNextSibling;
  end;
end;

procedure TAtlasResultsIssuesPart.OpenSelected;
var
  mData: TAtlasResultsNode;
begin
  if not FShows then
  begin
    Exit;
  end;
  mData := View.DataOf(View.Tree.Selected);
  if (mData.Kind = TAtlasResultsNodeKind.Issue) and Assigned(FHandlers.OnOpen) then
  begin
    FHandlers.OnOpen(FList, mData.SetId);
  end
  else if (mData.Kind = TAtlasResultsNodeKind.Commit) and Assigned(FHandlers.OnCommit) then
  begin
    FHandlers.OnCommit(FList, mData.SetId);
  end;
end;

function TAtlasResultsIssuesPart.Open(const AData: TAtlasResultsNode): Boolean;
begin
  // Issue öffnen, Commit zeigen.
  Result := AData.Kind in [TAtlasResultsNodeKind.Issue, TAtlasResultsNodeKind.Commit];
  if Result then
  begin
    OpenSelected;
  end;
end;

procedure TAtlasResultsIssuesPart.Click(ANode: TTreeNode);
begin
  // Klick auf die Zeile eines Issues (nicht auf das Aufklappzeichen) öffnet es.
  if FShows and (View.DataOf(ANode).Kind = TAtlasResultsNodeKind.Issue) then
  begin
    OpenSelected;
  end;
end;

end.
