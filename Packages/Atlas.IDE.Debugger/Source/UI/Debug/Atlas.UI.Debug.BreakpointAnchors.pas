unit Atlas.UI.Debug.BreakpointAnchors;

// Haltepunkte wandern mit dem Code (#841), Fensterteil (nur VCL):
//   Verwaiste Haltepunkte
//   Diese Haltepunkte ließen sich nach der Änderung nicht eindeutig …
//   ┌────────────────────────────────────────────────────────────────┐
//   │ Kunden.pas:42  Schreibe;  (Vorschlag: Zeile 40)                │
//   └────────────────────────────────────────────────────────────────┘
//   [Vorschlag übernehmen] [Löschen] [Schließen]
// Übernehmen und Löschen wirken auf den gewählten Eintrag über AAction; gelingt
// es, verschwindet er aus der Liste. Zeilen zeigt der Dialog ab 1.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.BreakpointAnchors,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Vorschlag übernehmen (ADelete False) bzw. Haltepunkt löschen; True, wenn es gelang.</summary>
  TAtlasOrphanAction = reference to function(const AOrphan: TAtlasAnchorOrphan; ADelete: Boolean): Boolean;

  TAtlasBreakpointOrphanDialog = class(TAtlasDialog)
  private
    FOrphans: TAtlasAnchorOrphans;
    FAction: TAtlasOrphanAction;
    FList: TListBox;
    FApply: TButton;
    FDelete: TButton;
    procedure CreateHint;
    procedure CreateList;
    procedure CreateButtons;
    procedure ApplyClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure UpdateButtons;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AOrphans: TAtlasAnchorOrphans;
      const AAction: TAtlasOrphanAction);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded).</summary>
    procedure Fill;
    /// <summary>Gewählten Eintrag übernehmen bzw. löschen (wie die Knöpfe).</summary>
    procedure Act(ADelete: Boolean);
    /// <summary>Text eines Eintrags: „Kunden.pas:42  Schreibe;  (Vorschlag: Zeile 40)“.</summary>
    class function ItemText(const AOrphan: TAtlasAnchorOrphan): string; static;
    /// <summary>Zeigt den Dialog modal; Ergebnis: die noch verwaisten Haltepunkte.</summary>
    class function Execute(const AOrphans: TAtlasAnchorOrphans; const AAction: TAtlasOrphanAction):
      TAtlasAnchorOrphans; static;
    property Orphans: TAtlasAnchorOrphans read FOrphans;
    property OrphanList: TListBox read FList;
    property ApplyButton: TButton read FApply;
    property DeleteButton: TButton read FDelete;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Debug.Strings;

const
  cDialogWidth = 620;
  cHintHeight = 36;
  cListHeight = 200;

{ TAtlasBreakpointOrphanDialog }

constructor TAtlasBreakpointOrphanDialog.CreateDialog(AOwner: TComponent; const AOrphans: TAtlasAnchorOrphans;
  const AAction: TAtlasOrphanAction);
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsTitle), cDialogWidth);
  FOrphans := AOrphans;
  FAction := AAction;
  CreateHint;
  CreateList;
  CreateButtons;
  FitHeight;
  AllowResize(FList);
  ActiveControl := FList;
end;

procedure TAtlasBreakpointOrphanDialog.CreateHint;
var
  mRow: TPanel;
  mLabel: TLabel;
begin
  mRow := AddRow(cHintHeight);
  mLabel := AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsHint));
  mLabel.ShowAccelChar := False;
  // Feste Breite aus der Zeile: kein Schrumpfen auf die längste Zeile.
  mLabel.AutoSize := False;
  mLabel.Align := alClient;
  mLabel.WordWrap := True;
end;

procedure TAtlasBreakpointOrphanDialog.CreateList;
begin
  FList := TListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
  FList.OnClick := ListClick;
end;

procedure TAtlasBreakpointOrphanDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
  mClose: TButton;
begin
  mButtons := AddButtonRow;
  FApply := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsApply),
    TAtlasButtonKind.Default);
  FApply.OnClick := ApplyClick;
  FDelete := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsDelete));
  FDelete.OnClick := DeleteClick;
  mClose := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsClose),
    TAtlasButtonKind.Cancel);
  mClose.ModalResult := mrCancel;
end;

class function TAtlasBreakpointOrphanDialog.ItemText(const AOrphan: TAtlasAnchorOrphan): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointAnchorsItem,
    [ExtractFileName(AOrphan.Item.FileName.Replace('/', PathDelim)), AOrphan.Item.Line + 1,
    AOrphan.Item.Anchor.Anchor.Text, AOrphan.Suggestion + 1]);
end;

procedure TAtlasBreakpointOrphanDialog.Fill;
var
  mOrphan: TAtlasAnchorOrphan;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mOrphan in FOrphans do
    begin
      FList.Items.Add(ItemText(mOrphan));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.ItemIndex := 0;
  end;
  UpdateButtons;
end;

procedure TAtlasBreakpointOrphanDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster: erst hier füllen.
  Fill;
end;

procedure TAtlasBreakpointOrphanDialog.UpdateButtons;
var
  mChosen: Boolean;
begin
  mChosen := (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FOrphans));
  FApply.Enabled := mChosen;
  FDelete.Enabled := mChosen;
end;

procedure TAtlasBreakpointOrphanDialog.Act(ADelete: Boolean);
var
  mIndex: Integer;
begin
  mIndex := FList.ItemIndex;
  if (mIndex < 0) or (mIndex > High(FOrphans)) or not Assigned(FAction) then
  begin
    Exit;
  end;
  if not FAction(FOrphans[mIndex], ADelete) then
  begin
    Exit;
  end;
  System.Delete(FOrphans, mIndex, 1);
  FList.Items.Delete(mIndex);
  if FList.Items.Count > 0 then
  begin
    FList.ItemIndex := Min(mIndex, FList.Items.Count - 1);
  end;
  UpdateButtons;
end;

procedure TAtlasBreakpointOrphanDialog.ApplyClick(Sender: TObject);
begin
  Act(False);
end;

procedure TAtlasBreakpointOrphanDialog.DeleteClick(Sender: TObject);
begin
  Act(True);
end;

procedure TAtlasBreakpointOrphanDialog.ListClick(Sender: TObject);
begin
  UpdateButtons;
end;

class function TAtlasBreakpointOrphanDialog.Execute(const AOrphans: TAtlasAnchorOrphans;
  const AAction: TAtlasOrphanAction): TAtlasAnchorOrphans;
var
  mDialog: TAtlasBreakpointOrphanDialog;
begin
  mDialog := TAtlasBreakpointOrphanDialog.CreateDialog(nil, AOrphans, AAction);
  try
    mDialog.ShowModal;
    Result := mDialog.Orphans;
  finally
    mDialog.Free;
  end;
end;

end.
