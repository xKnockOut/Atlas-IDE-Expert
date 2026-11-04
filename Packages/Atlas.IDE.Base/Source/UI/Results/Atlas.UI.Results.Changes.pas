unit Atlas.UI.Results.Changes;

// Liste „Atlas-Änderungen“ (#721) im Ergebnisfenster: die Sätze des Änderungsprotokolls mit ihren Dateien.
// Doppelklick oder Enter zeigt den Unterschied (OnDiff), das Kontextmenü nimmt einen Satz zurück oder stellt ihn
// wieder her.

interface

uses
  Vcl.Menus,
  Atlas.Core.Undo.Contract,
  Atlas.UI.Results.View;

type
  /// <summary>Satz (#721) zurücknehmen bzw. wiederherstellen.</summary>
  TAtlasChangeSetAction = reference to procedure(ASetId: Integer);
  /// <summary>Unterschied eines Satzes zeigen; AFileName = '' für alle Dateien.</summary>
  TAtlasChangeDiff = reference to procedure(ASetId: Integer; const AFileName: string);

  TAtlasResultsChangesPart = class(TAtlasResultsPart)
  private type
    TItems = record
      Undo: TMenuItem;
      Redo: TMenuItem;
      Diff: TMenuItem;
    end;
    THandlers = record
      OnUndo: TAtlasChangeSetAction;
      OnRedo: TAtlasChangeSetAction;
      OnDiff: TAtlasChangeDiff;
    end;
  private
    FItems: TItems;
    FHandlers: THandlers;
    FShows: Boolean;
    function SelectedSet: TAtlasResultsNode;
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure DiffClick(Sender: TObject);
  protected
    procedure Reset; override;
    function Open(const AData: TAtlasResultsNode): Boolean; override;
    procedure Popup; override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Neueste Sätze zuerst, je Satz seine Dateien (zugeklappt). AKeepSelection: den bisher gewählten Satz
    /// wieder wählen (nach Zurücknehmen).</summary>
    procedure Show(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
      AKeepSelection: Boolean);
    /// <summary>Unterschied, Zurücknehmen und Wiederherstellen für den gewählten Satz bzw. die gewählte Datei.
    /// </summary>
    procedure ShowSelectedDiff;
    procedure UndoSelected;
    procedure RedoSelected;
    /// <summary>Zeigt gerade die Liste „Atlas-Änderungen“.</summary>
    property Shows: Boolean read FShows;
    property OnUndo: TAtlasChangeSetAction read FHandlers.OnUndo write FHandlers.OnUndo;
    property OnRedo: TAtlasChangeSetAction read FHandlers.OnRedo write FHandlers.OnRedo;
    property OnDiff: TAtlasChangeDiff read FHandlers.OnDiff write FHandlers.OnDiff;
  end;

implementation

uses
  Vcl.ComCtrls,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Messages;

{ TAtlasResultsChangesPart }

constructor TAtlasResultsChangesPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Kontextmenü der Liste „Atlas-Änderungen“ (#721); in anderen Listen verborgen.
  FItems.Undo := TAtlasResultsControls.MenuItem(AView.Menu, TAtlasStrings.Text(TAtlasTextId.UndoActionUndo), UndoClick);
  FItems.Redo := TAtlasResultsControls.MenuItem(AView.Menu, TAtlasStrings.Text(TAtlasTextId.UndoActionRedo), RedoClick);
  FItems.Diff := TAtlasResultsControls.MenuItem(AView.Menu, TAtlasStrings.Text(TAtlasTextId.UndoActionDiff), DiffClick);
end;

procedure TAtlasResultsChangesPart.Reset;
begin
  FShows := False;
end;

procedure TAtlasResultsChangesPart.Show(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
  AKeepSelection: Boolean);
var
  mSet: TAtlasChangeSet;
  mChange: TAtlasFileChange;
  mData: TAtlasResultsNode;
  mSetNode, mSelected: TTreeNode;
  mPreviousId: Integer;
begin
  mPreviousId := 0;
  if AKeepSelection and FShows then
  begin
    mPreviousId := SelectedSet.SetId;
  end;
  View.Clear(ATitle);
  FShows := True;
  mSelected := nil;
  View.Tree.Items.BeginUpdate;
  try
    for mSet in ASets do
    begin
      mData := TAtlasResultsNode.Create(TAtlasResultsNodeKind.ChangeSet);
      mData.SetId := mSet.Id;
      mData.State := mSet.State;
      mSetNode := View.AddNode(nil, TAtlasUndoMessages.SetCaption(mSet, ANow), mData);
      if mSet.Id = mPreviousId then
      begin
        mSelected := mSetNode;
      end;
      for mChange in mSet.Files do
      begin
        mData.Kind := TAtlasResultsNodeKind.ChangeFile;
        mData.FileName := mChange.FileName;
        View.AddNode(mSetNode, TAtlasUndoMessages.FileCaption(mChange), mData);
      end;
    end;
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(mSelected);
end;

function TAtlasResultsChangesPart.SelectedSet: TAtlasResultsNode;
begin
  Result := View.DataOf(View.Tree.Selected);
  if not (Result.Kind in [TAtlasResultsNodeKind.ChangeSet, TAtlasResultsNodeKind.ChangeFile]) then
  begin
    Result := Default(TAtlasResultsNode);
  end;
end;

function TAtlasResultsChangesPart.Open(const AData: TAtlasResultsNode): Boolean;
begin
  // Doppelklick zeigt den Unterschied.
  Result := AData.Kind in [TAtlasResultsNodeKind.ChangeSet, TAtlasResultsNodeKind.ChangeFile];
  if Result then
  begin
    ShowSelectedDiff;
  end;
end;

procedure TAtlasResultsChangesPart.Popup;
var
  mData: TAtlasResultsNode;
begin
  mData := SelectedSet;
  FItems.Undo.Visible := FShows;
  FItems.Redo.Visible := FShows;
  FItems.Diff.Visible := FShows;
  FItems.Undo.Enabled := (mData.SetId > 0) and (mData.State <> TAtlasChangeSetState.Undone);
  FItems.Redo.Enabled := (mData.SetId > 0) and (mData.State <> TAtlasChangeSetState.Applied);
  FItems.Diff.Enabled := mData.SetId > 0;
end;

procedure TAtlasResultsChangesPart.ShowSelectedDiff;
var
  mData: TAtlasResultsNode;
begin
  mData := SelectedSet;
  if (mData.SetId > 0) and Assigned(FHandlers.OnDiff) then
  begin
    FHandlers.OnDiff(mData.SetId, mData.FileName);
  end;
end;

procedure TAtlasResultsChangesPart.UndoSelected;
var
  mData: TAtlasResultsNode;
begin
  mData := SelectedSet;
  if (mData.SetId > 0) and Assigned(FHandlers.OnUndo) then
  begin
    FHandlers.OnUndo(mData.SetId);
  end;
end;

procedure TAtlasResultsChangesPart.RedoSelected;
var
  mData: TAtlasResultsNode;
begin
  mData := SelectedSet;
  if (mData.SetId > 0) and Assigned(FHandlers.OnRedo) then
  begin
    FHandlers.OnRedo(mData.SetId);
  end;
end;

procedure TAtlasResultsChangesPart.UndoClick(Sender: TObject);
begin
  UndoSelected;
end;

procedure TAtlasResultsChangesPart.RedoClick(Sender: TObject);
begin
  RedoSelected;
end;

procedure TAtlasResultsChangesPart.DiffClick(Sender: TObject);
begin
  ShowSelectedDiff;
end;

end.
