unit Atlas.UI.Debug.LogpointDialog;

// Eingabe eines Logpunkts (#583), reine VCL: Text mit Platzhaltern
// („x={x}, Summe {Summe:0.00}“), optional Bedingung und „nur die ersten N
// Treffer“. Unter dem Text steht laufend der Fehler mit Stelle
// (TAtlasLogpointTemplate) bzw. die Hilfe zu den Formaten. Mit
// debug.logpoints.recordValues gibt es „Zahl aufzeichnen“ samt Name der Reihe
// (#2552), nur bei genau einem Platzhalter wählbar. „Setzen“ schließt
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
    /// <summary>Werte als Zahlenreihe aufzeichnen (#2552).</summary>
    RecordValues: Boolean;
    /// <summary>Name der Reihe; '' = Text des Logpunkts.</summary>
    SeriesName: string;
  end;

  TAtlasLogpointDialog = class(TAtlasDialog)
  private
    FText: TEdit;
    FCondition: TEdit;
    FHits: TEdit;
    FRecord: TCheckBox;
    FSeriesName: TEdit;
    FNote: TAtlasNoteLabel;
    FSet: TButton;
    procedure InputChange(Sender: TObject);
    procedure SetClick(Sender: TObject);
    function LabeledEdit(const ACaption, AHint: string): TEdit;
    function GetInput: TAtlasLogpointInput;
    procedure SetInput(const AValue: TAtlasLogpointInput);
  public
    /// <summary>ARecordable: „Zahl aufzeichnen“ anbieten (debug.logpoints.recordValues).</summary>
    constructor CreateFor(AOwner: TComponent; const APlace: string; ACanRemove, ARecordable: Boolean);
    /// <summary>Text zum Fehler in ATemplate; '' ohne Fehler.</summary>
    class function ErrorText(const ATemplate: TAtlasLogpointTemplate): string; static;
    /// <summary>Modal zeigen; AInput vorbelegt und bei „Setzen“ mit der Eingabe.</summary>
    class function Execute(const APlace: string; ACanRemove, ARecordable: Boolean;
      var AInput: TAtlasLogpointInput): TAtlasLogpointChoice; static;
    property Input: TAtlasLogpointInput read GetInput write SetInput;
  end;

implementation

uses
  Atlas.Core.Debug.ValueSeries,
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.Logpoints.Strings;

const
  cWidth = 460;
  cRowHeight = 26;
  cLabelWidth = 150;
  cNoteHeight = 36;
  cModalRemove = 100;

{ TAtlasLogpointDialog }

constructor TAtlasLogpointDialog.CreateFor(AOwner: TComponent; const APlace: string; ACanRemove,
  ARecordable: Boolean);
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
  if ARecordable then
  begin
    FRecord := TCheckBox.Create(Self);
    FRecord.Parent := AddRow(cRowHeight);
    FRecord.Align := alClient;
    FRecord.Caption := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointRecord);
    FRecord.OnClick := InputChange;
    FSeriesName := LabeledEdit(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointSeriesName),
      TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointSeriesNameHint));
  end;
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
  Result.RecordValues := False;
  Result.SeriesName := '';
  if FRecord <> nil then
  begin
    Result.RecordValues := FRecord.Checked and FRecord.Enabled;
    Result.SeriesName := Trim(FSeriesName.Text);
  end;
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
  if FRecord <> nil then
  begin
    FRecord.Checked := AValue.RecordValues;
    FSeriesName.Text := AValue.SeriesName;
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
  if FRecord <> nil then
  begin
    FRecord.Enabled := TAtlasLogpointValue.CanRecord(mTemplate);
    FSeriesName.Enabled := FRecord.Enabled and FRecord.Checked;
    if FRecord.Checked and not FRecord.Enabled and (mError = '') then
    begin
      FNote.ShowNote(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.LogpointRecordNeedsOne),
        TAtlasSignalKind.Warn);
    end;
  end;
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

class function TAtlasLogpointDialog.Execute(const APlace: string; ACanRemove, ARecordable: Boolean;
  var AInput: TAtlasLogpointInput): TAtlasLogpointChoice;
var
  mDialog: TAtlasLogpointDialog;
begin
  Result := TAtlasLogpointChoice.Cancel;
  mDialog := TAtlasLogpointDialog.CreateFor(nil, APlace, ACanRemove, ARecordable);
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
