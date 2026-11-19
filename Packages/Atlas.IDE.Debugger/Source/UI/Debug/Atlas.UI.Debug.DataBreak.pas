unit Atlas.UI.Debug.DataBreak;

// Anhalten bei Datenzugriff (#870), Fensterteil (nur VCL):
// - TAtlasDataBreakDialog: Arten (SQL, HTTP, je mit Zahl der Stellen) und ihre
//   Muster, Groß-/Kleinschreibung, was bei Treffer geschieht (anhalten oder
//   nur protokollieren), darunter die Zahl der Aufrufe und Haltestellen zur
//   aktuellen Wahl.
// - TAtlasDataBreakBar: Leiste nach dem Halt (TAtlasStopBar)
//     Angehalten bei Datenzugriff: Kunde.pas:43 · TfrmKunde.Speichern · qryKunde.ExecSQL
//     UPDATE Kunden SET Name = :Name WHERE ID = :ID [Name='Müller', ID='7']
//     Weiter beobachten   Nur protokollieren   Beenden
// Der Dialog erbt von TAtlasDialog (IDE-Thema, Dialogschrift, Knopfleiste);
// Zeilen in logischen Pixeln.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.DataBreak,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Debug.StopBar;

type
  /// <summary>Text unter der Wahl („12 Aufrufe an 9 Stellen …“) zur aktuellen Wahl.</summary>
  TAtlasDataBreakCount = reference to function(const AChoice: TAtlasDataChoice): string;

  TAtlasDataBreakDialog = class(TAtlasDialog)
  private
    FSql: TCheckBox;
    FSqlPattern: TEdit;
    FHttp: TCheckBox;
    FHttpPattern: TEdit;
    FIgnoreCase: TCheckBox;
    FStop: TRadioButton;
    FLog: TRadioButton;
    FCount: TAtlasNoteLabel;
    FOk: TButton;
    FCancel: TButton;
    FChoice: TAtlasDataChoice;
    FCountText: TAtlasDataBreakCount;
    FPrepared: Boolean;
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPattern(const AHint: string): TEdit;
    function AddRadio(const ACaption: string): TRadioButton;
    procedure CreateButtons;
    procedure Changed(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    /// <summary>ASqlCount/AHttpCount: Zahl der gefundenen Stellen je Art.</summary>
    constructor CreateDialog(AOwner: TComponent; const AChoice: TAtlasDataChoice; ASqlCount, AHttpCount: Integer;
      const ACount: TAtlasDataBreakCount);
    /// <summary>Setzt die Wahl in die Controls (braucht ein Fenster); einmal.</summary>
    procedure Prepare;
    /// <summary>Wahl aus den Controls.</summary>
    function Choice: TAtlasDataChoice;
    /// <summary>Zeigt den Dialog modal; True mit der Wahl in AChoice.</summary>
    class function Execute(var AChoice: TAtlasDataChoice; ASqlCount, AHttpCount: Integer;
      const ACount: TAtlasDataBreakCount): Boolean; static;
    property SqlCheck: TCheckBox read FSql;
    property SqlPatternEdit: TEdit read FSqlPattern;
    property HttpCheck: TCheckBox read FHttp;
    property HttpPatternEdit: TEdit read FHttpPattern;
    property IgnoreCaseCheck: TCheckBox read FIgnoreCase;
    property StopRadio: TRadioButton read FStop;
    property LogRadio: TRadioButton read FLog;
    property CountLabel: TAtlasNoteLabel read FCount;
    property OkButton: TButton read FOk;
  end;

  /// <summary>Verweis der Leiste.</summary>
  {$SCOPEDENUMS ON}
  TAtlasDataBreakAction = (KeepWatching, LogOnly, Finish);
  {$SCOPEDENUMS OFF}

  TAtlasDataBreakBar = class(TAtlasStopBar)
  private
    FOnAction: TProc<TAtlasDataBreakAction>;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt „Angehalten bei Datenzugriff: APlace“, darunter ADetail, unter APoint (Bildschirm).</summary>
    procedure ShowFor(const APlace, ADetail: string; const APoint: TPoint);
    /// <summary>Wie ein Klick auf den Verweis AAction.</summary>
    procedure Act(AAction: TAtlasDataBreakAction);
    function ActionRect(AAction: TAtlasDataBreakAction): TRect;
    property OnAction: TProc<TAtlasDataBreakAction> read FOnAction write FOnAction;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.DataBreak.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cDialogWidth = 480;
  /// <summary>Höhe einer Zeile mit Kästchen, Knopf oder Eingabefeld und der Zahl darunter, logische Pixel.
  /// </summary>
  cLineHeight = 22;
  cEditHeight = 26;
  cCountHeight = 52;
  /// <summary>Einzug der Muster und Optionsfelder unter ihrer Überschrift, logische Pixel.</summary>
  cIndent = 20;

{ TAtlasDataBreakDialog }

constructor TAtlasDataBreakDialog.CreateDialog(AOwner: TComponent; const AChoice: TAtlasDataChoice; ASqlCount,
  AHttpCount: Integer; const ACount: TAtlasDataBreakCount);
var
  mHeading: TLabel;
begin
  inherited CreateDialog(AOwner, TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakTitle), cDialogWidth);
  FChoice := AChoice;
  FCountText := ACount;
  BorderIcons := [biSystemMenu];
  FSql := AddCheck(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakSql, [ASqlCount]));
  FSql.Enabled := ASqlCount > 0;
  FSqlPattern := AddPattern(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakSqlHint));
  FHttp := AddCheck(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakHttp, [AHttpCount]));
  FHttp.Enabled := AHttpCount > 0;
  FHttpPattern := AddPattern(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakHttpHint));
  FIgnoreCase := AddCheck(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakIgnoreCase));
  mHeading := AddLabel(AddRow(cLineHeight), TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakOnMatch));
  mHeading.Font.Style := [fsBold];
  FStop := AddRadio(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakModeStop));
  FLog := AddRadio(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakModeLog));
  FCount := AddNote(cCountHeight);
  FCount.ShowAccelChar := False;
  FCount.AutoSize := False;
  FCount.WordWrap := True;
  CreateButtons;
  FitHeight;
end;

procedure TAtlasDataBreakDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
begin
  mButtons := AddButtonRow;
  FOk := mButtons.AddButton(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakOk), TAtlasButtonKind.Default);
  FOk.OnClick := OkClick;
  FCancel := mButtons.AddButton(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakCancel),
    TAtlasButtonKind.Cancel);
  FCancel.OnClick := CancelClick;
end;

procedure TAtlasDataBreakDialog.DoShow;
begin
  Prepare;
  inherited;
end;

function TAtlasDataBreakDialog.AddCheck(const ACaption: string): TCheckBox;
begin
  // Füllt die Zeile, damit längere Übersetzungen nicht abgeschnitten werden.
  Result := TCheckBox.Create(Self);
  Result.Caption := ACaption;
  Result.Align := alClient;
  Result.Parent := AddRow(cLineHeight);
  Result.OnClick := Changed;
end;

function TAtlasDataBreakDialog.AddPattern(const AHint: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.TextHint := AHint;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cIndent), 0, 0, 0);
  Result.Align := alClient;
  Result.Parent := AddRow(cEditHeight);
  Result.OnChange := Changed;
end;

function TAtlasDataBreakDialog.AddRadio(const ACaption: string): TRadioButton;
begin
  Result := TRadioButton.Create(Self);
  Result.Caption := ACaption;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cIndent), 0, 0, 0);
  Result.Align := alClient;
  Result.Parent := AddRow(cLineHeight);
  Result.OnClick := Changed;
end;

procedure TAtlasDataBreakDialog.Changed(Sender: TObject);
var
  mCurrent: TAtlasDataChoice;
begin
  if not FPrepared then
  begin
    Exit;
  end;
  FSqlPattern.Enabled := FSql.Checked;
  FHttpPattern.Enabled := FHttp.Checked;
  mCurrent := Choice;
  FOk.Enabled := mCurrent.Kinds <> [];
  if Assigned(FCountText) then
  begin
    FCount.ShowNote(FCountText(mCurrent), TAtlasSignalKind.Info);
  end
  else
  begin
    FCount.ShowNote('', TAtlasSignalKind.Info);
  end;
end;

procedure TAtlasDataBreakDialog.OkClick(Sender: TObject);
begin
  if Choice.Kinds = [] then
  begin
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TAtlasDataBreakDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TAtlasDataBreakDialog.Prepare;
begin
  if FPrepared then
  begin
    Exit;
  end;
  FPrepared := True;
  HandleNeeded;
  FSql.Checked := FSql.Enabled and (TAtlasDataKind.Sql in FChoice.Kinds);
  FHttp.Checked := FHttp.Enabled and (TAtlasDataKind.Http in FChoice.Kinds);
  FSqlPattern.Text := FChoice.SqlPattern;
  FHttpPattern.Text := FChoice.HttpPattern;
  FIgnoreCase.Checked := FChoice.IgnoreCase;
  FStop.Checked := FChoice.Mode = TAtlasDataMode.Stop;
  FLog.Checked := FChoice.Mode = TAtlasDataMode.Log;
  Changed(nil);
end;

function TAtlasDataBreakDialog.Choice: TAtlasDataChoice;
begin
  Result := TAtlasDataChoice.Defaults;
  Result.Kinds := [];
  if FSql.Checked then
  begin
    Include(Result.Kinds, TAtlasDataKind.Sql);
  end;
  if FHttp.Checked then
  begin
    Include(Result.Kinds, TAtlasDataKind.Http);
  end;
  Result.SqlPattern := Trim(FSqlPattern.Text);
  Result.HttpPattern := Trim(FHttpPattern.Text);
  Result.IgnoreCase := FIgnoreCase.Checked;
  Result.Mode := TAtlasDataMode.Stop;
  if FLog.Checked then
  begin
    Result.Mode := TAtlasDataMode.Log;
  end;
end;

class function TAtlasDataBreakDialog.Execute(var AChoice: TAtlasDataChoice; ASqlCount, AHttpCount: Integer;
  const ACount: TAtlasDataBreakCount): Boolean;
var
  mDialog: TAtlasDataBreakDialog;
begin
  mDialog := TAtlasDataBreakDialog.CreateDialog(nil, AChoice, ASqlCount, AHttpCount, ACount);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AChoice := mDialog.Choice;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasDataBreakBar }

constructor TAtlasDataBreakBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetAccessible(cUiaToolTipControlType, TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakTitle));
  OnLink :=
    procedure(AIndex: Integer)
    begin
      if Assigned(FOnAction) then
      begin
        FOnAction(TAtlasDataBreakAction(AIndex));
      end;
    end;
end;

procedure TAtlasDataBreakBar.ShowFor(const APlace, ADetail: string; const APoint: TPoint);
begin
  ShowLinks(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakStopped, [APlace]), ADetail,
    TArray<string>.Create(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakContinue),
    TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakLogOnly),
    TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakFinish)), APoint);
end;

procedure TAtlasDataBreakBar.Act(AAction: TAtlasDataBreakAction);
begin
  Choose(Ord(AAction));
end;

function TAtlasDataBreakBar.ActionRect(AAction: TAtlasDataBreakAction): TRect;
begin
  Result := LinkRect(Ord(AAction));
end;

end.
