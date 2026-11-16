unit Atlas.UI.Debug.LogpointDialog;

// Eingabe eines Logpunkts (#583), reine VCL: Text mit Platzhaltern
// („x={x}, Summe {Summe:0.00}“), optional Bedingung und „nur die ersten N
// Treffer“. Unter dem Text steht laufend der Fehler mit Stelle
// (TAtlasLogpointTemplate) bzw. die Hilfe zu den Formaten. „Setzen“ schließt
// nur mit gültigem Text; „Entfernen“ gibt es bei einem vorhandenen Logpunkt.
// Aufgebaut im Code (keine DFM).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.Logpoint,
  Atlas.UI.Foundation.Dialog;

type
  {$SCOPEDENUMS ON}
  TAtlasLogpointChoice = (Cancel, SetLogpoint, Remove);
  {$SCOPEDENUMS OFF}

  TAtlasLogpointInput = record
    Text: string;
    Condition: string;
    PassCount: Integer;
  end;

  TAtlasLogpointDialog = class(TAtlasDialog)
  private
    FText: TEdit;
    FCondition: TEdit;
    FHits: TEdit;
    FNote: TAtlasNoteLabel;
    FSet: TButton;
    procedure InputChange(Sender: TObject);
    procedure SetClick(Sender: TObject);
    function LabeledEdit(const ACaption, AHint: string): TEdit;
    function GetInput: TAtlasLogpointInput;
    procedure SetInput(const AValue: TAtlasLogpointInput);
  public
    constructor CreateFor(AOwner: TComponent; const APlace: string; ACanRemove: Boolean);
    /// <summary>Text zum Fehler in ATemplate; '' ohne Fehler.</summary>
    class function ErrorText(const ATemplate: TAtlasLogpointTemplate): string; static;
    /// <summary>Modal zeigen; AInput vorbelegt und bei „Setzen“ mit der Eingabe.</summary>
    class function Execute(const APlace: string; ACanRemove: Boolean;
      var AInput: TAtlasLogpointInput): TAtlasLogpointChoice; static;
    property Input: TAtlasLogpointInput read GetInput write SetInput;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Logpoints.Strings;

const
  cWidth = 460;
  cRowHeight = 26;
  cLabelWidth = 150;
  cNoteHeight = 36;
  cModalRemove = 100;

{ TAtlasLogpointDialog }

constructor TAtlasLogpointDialog.CreateFor(AOwner: TComponent; const APlace: string; ACanRemove: Boolean);
var
  mButtons: TAtlasButtonRow;
  mRemove: TButton;
begin
  inherited CreateDialog(AOwner, TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.LogpointDialogTitle, [APlace]),
    cWidth);
  FText := LabeledEdit(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointText),
    TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointTextHint));
  FNote := AddNote(cNoteHeight);
  FCondition := LabeledEdit(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointCondition),
    TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointConditionHint));
  FHits := LabeledEdit(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointHits), '');
  FHits.NumbersOnly := True;
  mButtons := AddButtonRow;
  FSet := mButtons.AddButton(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointSet), TAtlasButtonKind.Default);
  FSet.ModalResult := mrNone;
  FSet.OnClick := SetClick;
  if ACanRemove then
  begin
    mRemove := mButtons.AddButton(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointRemove));
    mRemove.ModalResult := cModalRemove;
  end;
  mButtons.AddButton(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  ActiveControl := FText;
  InputChange(nil);
end;

function TAtlasLogpointDialog.GetInput: TAtlasLogpointInput;
begin
  Result.Text := FText.Text;
  Result.Condition := Trim(FCondition.Text);
  Result.PassCount := StrToIntDef(Trim(FHits.Text), 0);
end;

procedure TAtlasLogpointDialog.SetInput(const AValue: TAtlasLogpointInput);
begin
  FText.Text := AValue.Text;
  FCondition.Text := AValue.Condition;
  FHits.Text := '';
  if AValue.PassCount > 0 then
  begin
    FHits.Text := IntToStr(AValue.PassCount);
  end;
  InputChange(nil);
end;

procedure TAtlasLogpointDialog.InputChange(Sender: TObject);
var
  mTemplate: TAtlasLogpointTemplate;
  mError: string;
begin
  mTemplate := TAtlasLogpointTemplate.Parse(FText.Text);
  mError := ErrorText(mTemplate);
  if mError <> '' then
  begin
    FNote.ShowNote(mError, TAtlasSignalKind.Error);
  end
  else
  begin
    FNote.ShowNote(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointFormats), TAtlasSignalKind.Info);
  end;
  FSet.Enabled := (Trim(FText.Text) <> '') and mTemplate.Valid;
end;

procedure TAtlasLogpointDialog.SetClick(Sender: TObject);
begin
  if FSet.Enabled then
  begin
    ModalResult := mrOk;
  end;
end;

function TAtlasLogpointDialog.LabeledEdit(const ACaption, AHint: string): TEdit;
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, ACaption);
  Result := TEdit.Create(Self);
  Result.Parent := mRow;
  Result.Left := ScaleValue(cLabelWidth);
  Result.Width := mRow.Width - Result.Left;
  Result.TextHint := AHint;
  Result.OnChange := InputChange;
  FitRight(Result);
end;

class function TAtlasLogpointDialog.ErrorText(const ATemplate: TAtlasLogpointTemplate): string;
begin
  Result := '';
  case ATemplate.Error of
    TAtlasLogpointError.MissingClose:
      Result := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.LogpointMissingClose, [ATemplate.ErrorPos]);
    TAtlasLogpointError.StrayClose:
      Result := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.LogpointStrayClose, [ATemplate.ErrorPos]);
    TAtlasLogpointError.EmptyPlaceholder:
      Result := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.LogpointEmpty, [ATemplate.ErrorPos]);
    TAtlasLogpointError.None:
      Result := '';
  end;
end;

class function TAtlasLogpointDialog.Execute(const APlace: string; ACanRemove: Boolean;
  var AInput: TAtlasLogpointInput): TAtlasLogpointChoice;
var
  mDialog: TAtlasLogpointDialog;
begin
  Result := TAtlasLogpointChoice.Cancel;
  mDialog := TAtlasLogpointDialog.CreateFor(nil, APlace, ACanRemove);
  try
    mDialog.Input := AInput;
    case mDialog.ShowModal of
      mrOk:
        begin
          AInput := mDialog.Input;
          Result := TAtlasLogpointChoice.SetLogpoint;
        end;
      cModalRemove:
        Result := TAtlasLogpointChoice.Remove;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
