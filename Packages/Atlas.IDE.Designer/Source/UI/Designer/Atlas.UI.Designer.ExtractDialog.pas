unit Atlas.UI.Designer.ExtractDialog;

// Dialog „In Frame auslagern“ (#611), reine VCL:
//   Frame-Klasse [TfrmAdresse ]  Unit [uAdresseFrame ]
//   Ordner       [C:\Projekt\ ]  Name im Formular [frmAdresse]
//   ☑ Handler mitnehmen  ☑ Container selbst zum Frame machen
//   [uAdresseFrame.pas][uAdresseFrame.dfm][uKunden.pas][uKunden.dfm][Hinweise]
//   │ Vorschau der Datei                                              │
//   [Letzte Auslagerung rückgängig]             [Übernehmen] [Abbrechen]
// - Jede Eingabe berechnet die Vorschau neu (OnPreview); ein Fehler steht
//   unter den Optionen und sperrt „Übernehmen“.
// - Ergebnis: Übernehmen (mit den Eingaben), Rückgängig oder Abbrechen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasExtractInput = record
    FrameClass: string;
    FrameUnit: string;
    Folder: string;
    InstanceName: string;
    MoveHandlers: Boolean;
    ContainerAsFrame: Boolean;
    /// <summary>Genau ein Container markiert: Option „Container selbst zum Frame“ wählbar.</summary>
    CanContainer: Boolean;
  end;

  TAtlasExtractPreview = record
    /// <summary>Reiter: Dateiname und Text je Datei.</summary>
    Captions: TArray<string>;
    Texts: TArray<string>;
    /// <summary>Hinweise und Probleme als fertige Zeilen.</summary>
    Notes: TArray<string>;
    /// <summary>Leer, wenn „Übernehmen“ möglich ist.</summary>
    Error: string;
  end;

{$SCOPEDENUMS ON}
  TAtlasExtractDialogResult = (Cancel, Apply, Undo);
{$SCOPEDENUMS OFF}

  TAtlasExtractDialog = class(TAtlasDialog)
  private
    FInput: TAtlasExtractInput;
    FOnPreview: TFunc<TAtlasExtractInput, TAtlasExtractPreview>;
    FFrameClass: TEdit;
    FFrameUnit: TEdit;
    FFolder: TEdit;
    FInstance: TEdit;
    FMoveHandlers: TCheckBox;
    FContainer: TCheckBox;
    FError: TLabel;
    FPages: TPageControl;
    FApply: TButton;
    FUpdating: Boolean;
    function AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult; AAlign: TAlign): TButton;
    function AddEdit(AGrid: TGridPanel; const ACaption, AText: string): TEdit;
    function AddMemo(const ACaption, AText: string): TMemo;
    function AddCheck(AParent: TWinControl; const ACaption: string; AChecked: Boolean): TCheckBox;
    procedure BuildGrid(const AInput: TAtlasExtractInput);
    procedure BuildOptions(const AInput: TAtlasExtractInput);
    procedure BuildButtons(ACanUndo: Boolean);
    procedure InputChanged(Sender: TObject);
    procedure Refresh;
  public
    constructor CreateDialog(AOwner: TComponent; const AFormName: string; const AInput: TAtlasExtractInput;
      ACanUndo: Boolean; const AOnPreview: TFunc<TAtlasExtractInput, TAtlasExtractPreview>);
    /// <summary>Zeigt den Dialog; AInput enthält danach die Eingaben. APrepare (darf nil sein) bekommt das Fenster
    /// vor dem Zeigen (Farben der IDE).</summary>
    class function Execute(const AFormName: string; var AInput: TAtlasExtractInput; ACanUndo: Boolean;
      const AOnPreview: TFunc<TAtlasExtractInput, TAtlasExtractPreview>;
      const APrepare: TProc<TForm>): TAtlasExtractDialogResult; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Graphics,
  Atlas.UI.Designer.ViewStrings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cBasePpi = 96;
  cWidth = 820;
  cHeight = 600;
  cUndoWidth = 240;
  cRowHeight = 30;
  cLabelWidth = 130;
  cGridColumns = 4;
  cGridRows = 2;
  /// <summary>Halbe Restbreite bzw. -höhe im Raster (Prozent).</summary>
  cHalf = 50;
  cCodeFont = 'Consolas';

{ TAtlasExtractDialog }

procedure TAtlasExtractDialog.BuildGrid(const AInput: TAtlasExtractInput);
var
  mGrid: TGridPanel;
  mColumn: TColumnItem;
  mIndex: Integer;
begin
  mGrid := TGridPanel.Create(Self);
  mGrid.Parent := Self;
  mGrid.Align := alTop;
  mGrid.BevelOuter := bvNone;
  mGrid.Height := MulDiv(cGridRows * cRowHeight, CurrentPPI, cBasePpi);
  mGrid.ColumnCollection.BeginUpdate;
  try
    mGrid.ColumnCollection.Clear;
    // Abwechselnd Beschriftung (fest) und Eingabe (halbe Restbreite).
    for mIndex := 0 to cGridColumns - 1 do
    begin
      mColumn := mGrid.ColumnCollection.Add;
      if Odd(mIndex) then
      begin
        mColumn.Value := cHalf;
      end
      else
      begin
        mColumn.SizeStyle := ssAbsolute;
        mColumn.Value := MulDiv(cLabelWidth, CurrentPPI, cBasePpi);
      end;
    end;
  finally
    mGrid.ColumnCollection.EndUpdate;
  end;
  mGrid.RowCollection.Clear;
  for mIndex := 0 to cGridRows - 1 do
  begin
    mGrid.RowCollection.Add.Value := cHalf;
  end;
  FFrameClass := AddEdit(mGrid, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfFrameClass),
    AInput.FrameClass);
  FFrameUnit := AddEdit(mGrid, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfUnit), AInput.FrameUnit);
  FFolder := AddEdit(mGrid, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfFolder), AInput.Folder);
  FInstance := AddEdit(mGrid, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfInstance),
    AInput.InstanceName);
end;

function TAtlasExtractDialog.AddCheck(AParent: TWinControl; const ACaption: string; AChecked: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  Result.Width := Canvas.TextWidth(ACaption) + MulDiv(cRowHeight, CurrentPPI, cBasePpi);
  Result.Checked := AChecked;
  Result.OnClick := InputChanged;
end;

procedure TAtlasExtractDialog.BuildOptions(const AInput: TAtlasExtractInput);
var
  mOptions: TPanel;
begin
  mOptions := TPanel.Create(Self);
  mOptions.Parent := Self;
  mOptions.Align := alTop;
  mOptions.Top := ClientHeight;
  mOptions.BevelOuter := bvNone;
  mOptions.Height := MulDiv(cRowHeight, CurrentPPI, cBasePpi);
  FContainer := AddCheck(mOptions, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfContainer),
    AInput.ContainerAsFrame);
  FContainer.Enabled := AInput.CanContainer;
  FMoveHandlers := AddCheck(mOptions, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfMoveHandlers),
    AInput.MoveHandlers);
  FError := TLabel.Create(Self);
  FError.Parent := mOptions;
  FError.Align := alClient;
  FError.AlignWithMargins := True;
  FError.Layout := tlCenter;
  FError.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  FError.StyleElements := FError.StyleElements - [seFont];
end;

procedure TAtlasExtractDialog.BuildButtons(ACanUndo: Boolean);
var
  mBottom: TPanel;
  mUndo: TButton;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.BevelOuter := bvNone;
  mBottom.AutoSize := True;
  mUndo := AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfUndo), mrRetry, alLeft);
  mUndo.Width := MulDiv(cUndoWidth, CurrentPPI, cBasePpi);
  mUndo.Enabled := ACanUndo;
  AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameCancel), mrCancel,
    alRight).Cancel := True;
  FApply := AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameApply), mrOk, alRight);
  FApply.Default := True;
end;

constructor TAtlasExtractDialog.CreateDialog(AOwner: TComponent; const AFormName: string;
  const AInput: TAtlasExtractInput; ACanUndo: Boolean; const AOnPreview: TFunc<TAtlasExtractInput,
  TAtlasExtractPreview>);
begin
  inherited CreateDialog(AOwner, '', 0);
  FInput := AInput;
  FOnPreview := AOnPreview;
  Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EfTitle, [AFormName]);
  BorderStyle := bsSizeToolWin;
  Width := MulDiv(cWidth, CurrentPPI, cBasePpi);
  Height := MulDiv(cHeight, CurrentPPI, cBasePpi);
  FUpdating := True;
  try
    BuildGrid(AInput);
    BuildOptions(AInput);
    BuildButtons(ACanUndo);
    FPages := TPageControl.Create(Self);
    FPages.Parent := Self;
    FPages.Align := alClient;
    FPages.AlignWithMargins := True;
  finally
    FUpdating := False;
  end;
  Refresh;
end;

function TAtlasExtractDialog.AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult;
  AAlign: TAlign): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
end;

function TAtlasExtractDialog.AddEdit(AGrid: TGridPanel; const ACaption, AText: string): TEdit;
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := AGrid;
  mLabel.Caption := ACaption;
  mLabel.Align := alClient;
  mLabel.AlignWithMargins := True;
  mLabel.Layout := tlCenter;
  Result := TEdit.Create(Self);
  Result.Parent := AGrid;
  Result.Align := alClient;
  Result.AlignWithMargins := True;
  Result.Text := AText;
  Result.OnChange := InputChanged;
end;

function TAtlasExtractDialog.AddMemo(const ACaption, AText: string): TMemo;
var
  mPage: TTabSheet;
begin
  mPage := TTabSheet.Create(Self);
  mPage.PageControl := FPages;
  mPage.Caption := ACaption;
  Result := TMemo.Create(Self);
  Result.Parent := mPage;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.ScrollBars := ssBoth;
  Result.WordWrap := False;
  Result.Font.Name := cCodeFont;
  Result.Text := AText;
end;

procedure TAtlasExtractDialog.InputChanged(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  FInput.FrameClass := Trim(FFrameClass.Text);
  FInput.FrameUnit := Trim(FFrameUnit.Text);
  FInput.Folder := Trim(FFolder.Text);
  FInput.InstanceName := Trim(FInstance.Text);
  FInput.MoveHandlers := FMoveHandlers.Checked;
  FInput.ContainerAsFrame := FContainer.Checked and FInput.CanContainer;
  Refresh;
end;

procedure TAtlasExtractDialog.Refresh;
var
  mPreview: TAtlasExtractPreview;
  mIndex, mPage: Integer;
  mNotes: string;
begin
  mPreview := Default(TAtlasExtractPreview);
  if Assigned(FOnPreview) then
  begin
    mPreview := FOnPreview(FInput);
  end;
  mPage := FPages.ActivePageIndex;
  FPages.Hide;
  try
    while FPages.PageCount > 0 do
    begin
      FPages.Pages[0].Free;
    end;
    for mIndex := 0 to High(mPreview.Captions) do
    begin
      if mIndex <= High(mPreview.Texts) then
      begin
        AddMemo(mPreview.Captions[mIndex], mPreview.Texts[mIndex]);
      end;
    end;
    mNotes := string.Join(sLineBreak, mPreview.Notes);
    if mNotes = '' then
    begin
      mNotes := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfNoNotes);
    end;
    AddMemo(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EfNotes), mNotes);
    if (mPage >= 0) and (mPage < FPages.PageCount) then
    begin
      FPages.ActivePageIndex := mPage;
    end;
  finally
    FPages.Show;
  end;
  FError.Caption := mPreview.Error;
  FApply.Enabled := mPreview.Error = '';
end;

class function TAtlasExtractDialog.Execute(const AFormName: string; var AInput: TAtlasExtractInput;
  ACanUndo: Boolean; const AOnPreview: TFunc<TAtlasExtractInput, TAtlasExtractPreview>;
  const APrepare: TProc<TForm>): TAtlasExtractDialogResult;
var
  mDialog: TAtlasExtractDialog;
begin
  Result := TAtlasExtractDialogResult.Cancel;
  mDialog := TAtlasExtractDialog.CreateDialog(nil, AFormName, AInput, ACanUndo, AOnPreview);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    case mDialog.ShowModal of
      mrOk:
        begin
          AInput := mDialog.FInput;
          Result := TAtlasExtractDialogResult.Apply;
        end;
      mrRetry:
        Result := TAtlasExtractDialogResult.Undo;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
