unit Atlas.UI.Tracker.StateDialog;

// „Mit Kommentar …“ am Statusfeld (#2124), reine VCL:
//   ATL-2052: Zustand ändern
//   Übergang:  [Zustand behalten (nur Kommentar) ▾]
//   Kommentar:
//   [ Kommentar-Editor (#1278)                    ]
//                                 [Senden] [Abbrechen]
// Die Liste bringt die erlaubten Übergänge bzw. die Werte des Zustandsfeldes
// in der Reihenfolge des Menüs; davor „Zustand behalten“. Strg+Enter sendet,
// Esc bricht ab. Geschrieben wird in der IDE-Schicht.

interface

uses
  System.Classes,
  Vcl.StdCtrls,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.CommentEditor;

type
  TAtlasTrackerStateDialog = class(TAtlasDialog)
  private
    FChoice: TAtlasChoiceBox;
    FEditor: TAtlasCommentEditor;
    FSend: TButton;
    procedure EditorSend(Sender: TObject);
    procedure EditorCancel(Sender: TObject);
  public
    /// <summary>Dialog für AKey; AChoices sind die Einträge des Menüs, APreselect der vorgewählte (-1 = Zustand
    /// behalten).</summary>
    constructor CreateDialog(AOwner: TComponent; const AKey: string; const AChoices: TArray<string>;
      APreselect: Integer);
    /// <summary>Gewählter Eintrag in AChoices; -1 = Zustand behalten.</summary>
    function Entry: Integer;
    /// <summary>Kommentar mit #10 als Zeilenumbruch, ohne Leerraum außen; '' = keiner.</summary>
    function Comment: string;
    property ChoiceBox: TAtlasChoiceBox read FChoice;
    property Editor: TAtlasCommentEditor read FEditor;
    property SendButton: TButton read FSend;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.UI.Tracker.Workflow.Strings;

const
  cDialogWidth = 480;
  cRowHeight = 26;
  cLabelWidth = 90;
  cCommentHeight = 140;

{ TAtlasTrackerStateDialog }

constructor TAtlasTrackerStateDialog.CreateDialog(AOwner: TComponent; const AKey: string;
  const AChoices: TArray<string>; APreselect: Integer);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.StatusDialogTitle, [AKey]),
    cDialogWidth);
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.StatusDialogChoice));
  FChoice := TAtlasChoiceBox.Create(Self);
  FChoice.Parent := mRow;
  FChoice.Left := ScaleValue(cLabelWidth);
  FChoice.Top := 0;
  FChoice.Width := ScaleValue(cDialogWidth - cLabelWidth);
  FChoice.SetChoices(TArray<string>.Create(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.StatusDialogKeep)) +
    AChoices);
  FChoice.Choice := APreselect + 1;
  FitRight(FChoice);

  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerEndComment));
  FEditor := TAtlasCommentEditor.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FEditor.Top := NextTop;
  FEditor.Height := ScaleValue(cCommentHeight);
  FEditor.AlignWithMargins := True;
  FEditor.Margins.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cRowGap), 0);
  FEditor.Align := alTop;
  FEditor.Parent := Self;
  FEditor.Events := TAtlasCommentEditorEvents.Create(EditorSend, EditorCancel);

  mButtons := AddButtonRow;
  FSend := mButtons.AddButton(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerEndSend),
    TAtlasButtonKind.Default);
  FSend.ModalResult := mrOk;
  mButtons.AddButton(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerEndCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  // Größer ziehen: Der Kommentar nimmt die Höhe auf.
  AllowResize(FEditor);
  ActiveControl := FEditor.Memo;
end;

procedure TAtlasTrackerStateDialog.EditorSend(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TAtlasTrackerStateDialog.EditorCancel(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function TAtlasTrackerStateDialog.Entry: Integer;
begin
  Result := FChoice.Choice - 1;
end;

function TAtlasTrackerStateDialog.Comment: string;
begin
  Result := Trim(FEditor.Text);
end;

end.
