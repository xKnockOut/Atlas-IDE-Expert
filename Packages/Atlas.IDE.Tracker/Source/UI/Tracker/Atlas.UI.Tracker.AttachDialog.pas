unit Atlas.UI.Tracker.AttachDialog;

// Dialog „An Issue anhängen“ (#1276), reine VCL ohne Open Tools API:
//   Issue: [ATL-123 Titel            ▼]
//   (Hinweis: hochladen bzw. GitHub-Rückfall über Zwischenablage und Kommentar)
//   Was anhängen?   (TAtlasAttachSources: Bildschirmfoto, Formular, Logdatei, Notizen)
//   [ ] Kommentar mit Verweis auf die Anhänge:
//       [                                                       ]
//   Wird erst mit „Senden“ übertragen:  Name | Größe
//                                                  [Senden] [Abbrechen]
// - Die Liste zeigt genau die Dateien, die gesendet werden; sie liegen
//   zugleich im Ordner des Laufs (TAtlasAttachTemp), Doppelklick öffnet eine
//   zur Kontrolle. Gesendet wird nichts im Dialog: Die IDE-Schicht liest nach
//   „Senden“ Key, Files, Comment und WithComment.
// - Text im Kommentar setzt den Haken davor.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.Attach,
  Atlas.UI.Tracker.AttachSources,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Was der Dialog anbieten kann; die IDE-Schicht füllt es.</summary>
  TAtlasAttachDialogInput = record
    /// <summary>Anzeigename des Trackers („YouTrack“, „GitHub“).</summary>
    Tracker: string;
    /// <summary>Nimmt der Tracker Dateien an (sonst Rückfall über Zwischenablage und Kommentar)?</summary>
    CanUpload: Boolean;
    /// <summary>Vorschläge „KEY Titel“ (etwa aus „Meine Issues“).</summary>
    Issues: TArray<string>;
    /// <summary>Vorgewähltes Issue (das aktuelle bzw. das der Vorschau); '' = keins.</summary>
    Key: string;
    /// <summary>Kennung aus der Eingabe; '' = ungültig.</summary>
    KeyOf: TFunc<string, string>;
    /// <summary>Was die Gruppe „Was anhängen?“ anbietet.</summary>
    Sources: TAtlasAttachSourcesInput;
    class function Empty: TAtlasAttachDialogInput; static;
  end;

  /// <summary>Steuerelemente des Dialogs außerhalb der Quellen; sie gehören dem Dialog.</summary>
  TAtlasAttachDialogParts = record
    Issue: TComboBox;
    Hint: TLabel;
    Comment: TCheckBox;
    CommentMemo: TMemo;
    List: TListView;
    Send: TButton;
  end;

  TAtlasAttachDialog = class(TAtlasDialog)
  public const
    cGap = 8;
    cDialogWidth = 680;
  private
    FInput: TAtlasAttachDialogInput;
    FTemp: TAtlasAttachTemp;
    FSources: TAtlasAttachSources;
    FFiles: TAtlasAttachFiles;
    FPaths: TArray<string>;
    FParts: TAtlasAttachDialogParts;
    FFilled: Boolean;
    /// <summary>BuildControls ist durch; vorher kann CreateWnd schon laufen (ClientWidth im Konstruktor).</summary>
    FBuilt: Boolean;
    procedure BuildControls;
    /// <summary>Eingabe des Issues und Hinweis zum Hochladen.</summary>
    procedure AddIssueRows(var ATop: Integer);
    /// <summary>Kommentar mit Verweis auf die Anhänge.</summary>
    procedure AddCommentRows(var ATop: Integer);
    /// <summary>Liste der Dateien, die gesendet werden.</summary>
    procedure AddFileList(var ATop: Integer);
    /// <summary>„Senden“ und „Abbrechen“ unten rechts.</summary>
    procedure AddButtons(ATop: Integer);
    /// <summary>Einträge der Auswahllisten (brauchen das Fenster); einmal, sobald Fenster und Steuerelemente da sind.
    /// </summary>
    procedure FillLists;
    /// <summary>Quellen oder Kommentar-Haken geändert: Liste neu.</summary>
    procedure Changed(Sender: TObject);
    procedure TextChanged(Sender: TObject);
    procedure CommentChanged(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure Rebuild;
    procedure UpdateSend;
  protected
    procedure CreateWnd; override;
    procedure DoClose(var Action: TCloseAction); override;
  public
    /// <summary>ATemp: Ordner dieses Laufs (bleibt beim Aufrufer, der ihn nach Senden oder Abbrechen leert).
    /// </summary>
    constructor CreateFor(AOwner: TComponent; const AInput: TAtlasAttachDialogInput; ATemp: TAtlasAttachTemp);
    destructor Destroy; override;
    /// <summary>Gewählte Kennung; '' = ungültig.</summary>
    function Key: string;
    /// <summary>Dateien, die gesendet werden (Namen eindeutig).</summary>
    function Files: TAtlasAttachFiles;
    function CommentText: string;
    function WithComment: Boolean;
    /// <summary>Kann gesendet werden (gültige Kennung und etwas zu senden)?</summary>
    function CanSend: Boolean;
    /// <summary>„1,5 KB“ wie in der Issue-Vorschau.</summary>
    class function SizeText(ABytes: Int64): string; static;
    /// <summary>Steuerelemente (für Tests).</summary>
    property Parts: TAtlasAttachDialogParts read FParts;
    /// <summary>Gruppe „Was anhängen?“ (für Tests).</summary>
    property Sources: TAtlasAttachSources read FSources;
  end;

implementation

uses
  System.UITypes,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Files,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Attach.Strings,
  Atlas.UI.Foundation.WrapLabel;

const
  // Maße bei 96 dpi.
  cLabelTop = 4;
  cLabelHeight = 15;
  cEditHeight = 23;
  cCheckHeight = 21;
  /// <summary>Linke Kante des Felds „Issue“ hinter seiner Beschriftung.</summary>
  cIssueLeft = 70;
  cIssueLabelWidth = 60;
  cIssueRow = 30;
  /// <summary>Hinweis unter dem Issue: zwei Zeilen.</summary>
  cHintHeight = 32;
  cHintRow = 38;
  cCheckRow = 24;
  cMemoHeight = 60;
  cListLabelRow = 20;
  cListHeight = 110;
  cNameColumnWidth = 480;
  cSizeColumnWidth = 120;
  cBottomHeight = 44;
  cButtonWidth = 110;
  cButtonHeight = 28;
  cBytesPerKilobyte = 1024;

{ TAtlasAttachDialogInput }

class function TAtlasAttachDialogInput.Empty: TAtlasAttachDialogInput;
begin
  Result := Default(TAtlasAttachDialogInput);
  Result.Sources := TAtlasAttachSourcesInput.Empty;
end;

{ TAtlasAttachDialog }

constructor TAtlasAttachDialog.CreateFor(AOwner: TComponent; const AInput: TAtlasAttachDialogInput;
  ATemp: TAtlasAttachTemp);
begin
  inherited CreateDialog(AOwner, '', 0);
  FInput := AInput;
  // Nicht festhalten: Die Quellen kopieren das Bild, der Aufrufer gibt es frei.
  FInput.Sources.FormImage := nil;
  FTemp := ATemp;
  FSources := TAtlasAttachSources.Create(Self, AInput.Sources);
  FSources.OnChanged := Changed;
  Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := ScaleValue(cDialogWidth);
  BuildControls;
end;

destructor TAtlasAttachDialog.Destroy;
begin
  FreeAndNil(FSources);
  FFiles := nil;
  FPaths := nil;
  inherited;
end;

procedure TAtlasAttachDialog.CreateWnd;
begin
  inherited;
  FillLists;
end;

procedure TAtlasAttachDialog.DoClose(var Action: TCloseAction);
begin
  FSources.Cancel;
  inherited;
end;

procedure TAtlasAttachDialog.AddIssueRows(var ATop: Integer);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.SetBounds(cGap, ATop + cLabelTop, cIssueLabelWidth, cLabelHeight);
  mLabel.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachIssue);
  FParts.Issue := TComboBox.Create(Self);
  FParts.Issue.Parent := Self;
  FParts.Issue.SetBounds(cGap + cIssueLeft, ATop, cDialogWidth - 2 * cGap - cIssueLeft, cEditHeight);
  FParts.Issue.Anchors := [akLeft, akTop, akRight];
  FParts.Issue.Style := csDropDown;
  FParts.Issue.OnChange := TextChanged;
  FParts.Issue.Text := FInput.Key;
  Inc(ATop, cIssueRow);
  FParts.Hint := TAtlasWrapLabel.Create(Self);
  FParts.Hint.Parent := Self;
  FParts.Hint.AutoSize := False;
  FParts.Hint.SetBounds(cGap, ATop, cDialogWidth - 2 * cGap, cHintHeight);
  FParts.Hint.Anchors := [akLeft, akTop, akRight];
  if FInput.CanUpload then
  begin
    FParts.Hint.Caption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachUploadHint, [FInput.Tracker]);
  end
  else
  begin
    FParts.Hint.Caption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachFallbackHint, [FInput.Tracker]);
  end;
  Inc(ATop, cHintRow);
end;

procedure TAtlasAttachDialog.AddCommentRows(var ATop: Integer);
begin
  FParts.Comment := TCheckBox.Create(Self);
  FParts.Comment.Parent := Self;
  FParts.Comment.SetBounds(cGap, ATop, cDialogWidth - 2 * cGap, cCheckHeight);
  FParts.Comment.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachComment);
  FParts.Comment.OnClick := Changed;
  Inc(ATop, cCheckRow);
  FParts.CommentMemo := TMemo.Create(Self);
  FParts.CommentMemo.Parent := Self;
  FParts.CommentMemo.SetBounds(cGap, ATop, cDialogWidth - 2 * cGap, cMemoHeight);
  FParts.CommentMemo.Anchors := [akLeft, akTop, akRight];
  FParts.CommentMemo.ScrollBars := ssVertical;
  // Tippen schreibt keine Dateien neu, nur „Senden“ wird geprüft.
  FParts.CommentMemo.OnChange := CommentChanged;
  Inc(ATop, cMemoHeight + cGap);
end;

procedure TAtlasAttachDialog.AddFileList(var ATop: Integer);
var
  mLabel: TLabel;
  mColumn: TListColumn;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.SetBounds(cGap, ATop, cDialogWidth - 2 * cGap, cLabelHeight);
  mLabel.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachFiles);
  Inc(ATop, cListLabelRow);
  FParts.List := TListView.Create(Self);
  FParts.List.Parent := Self;
  FParts.List.SetBounds(cGap, ATop, cDialogWidth - 2 * cGap, cListHeight);
  FParts.List.Anchors := [akLeft, akTop, akRight];
  FParts.List.ViewStyle := vsReport;
  FParts.List.ReadOnly := True;
  FParts.List.RowSelect := True;
  FParts.List.ShowColumnHeaders := True;
  mColumn := FParts.List.Columns.Add;
  mColumn.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnName);
  mColumn.Width := FParts.List.ScaleValue(cNameColumnWidth);
  mColumn := FParts.List.Columns.Add;
  mColumn.Caption := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewColumnSize);
  mColumn.Width := FParts.List.ScaleValue(cSizeColumnWidth);
  mColumn.Alignment := taRightJustify;
  FParts.List.OnDblClick := ListDblClick;
  Inc(ATop, cListHeight + cGap);
end;

procedure TAtlasAttachDialog.AddButtons(ATop: Integer);
var
  mBottom: TPanel;
  mButton: TButton;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.BevelOuter := bvNone;
  mBottom.SetBounds(0, ATop, cDialogWidth, cBottomHeight);
  mBottom.Anchors := [akLeft, akTop, akRight];
  FParts.Send := TButton.Create(Self);
  FParts.Send.Parent := mBottom;
  FParts.Send.SetBounds(cDialogWidth - 2 * (cButtonWidth + cGap), cGap, cButtonWidth, cButtonHeight);
  FParts.Send.Anchors := [akTop, akRight];
  FParts.Send.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachSend);
  FParts.Send.Default := True;
  FParts.Send.ModalResult := mrOk;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(cDialogWidth - (cButtonWidth + cGap), cGap, cButtonWidth, cButtonHeight);
  mButton.Anchors := [akTop, akRight];
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
end;

procedure TAtlasAttachDialog.BuildControls;
var
  mTop: Integer;
begin
  mTop := cGap;
  AddIssueRows(mTop);
  FSources.Build(mTop);
  AddCommentRows(mTop);
  AddFileList(mTop);
  AddButtons(mTop);
  ClientHeight := mTop + ScaleValue(cBottomHeight);
  // Größer ziehen: Felder werden breiter, die Dateiliste nimmt die Höhe auf.
  AllowResize(FParts.List);
  FBuilt := True;
  // ClientWidth im Konstruktor legt das Fenster schon vor BuildControls an: dann hier füllen.
  if HandleAllocated then
  begin
    FillLists;
  end;
end;

procedure TAtlasAttachDialog.FillLists;
var
  mText: string;
begin
  if FFilled or not FBuilt then
  begin
    Exit;
  end;
  FFilled := True;
  // Einträge von Auswahllisten brauchen das Fenster: nicht im Konstruktor.
  FParts.Issue.Items.BeginUpdate;
  try
    for mText in FInput.Issues do
    begin
      FParts.Issue.Items.Add(mText);
    end;
  finally
    FParts.Issue.Items.EndUpdate;
  end;
  // Mit dem Hauptfenster des Programms meldet sich die Gruppe schon selbst.
  if not FSources.FillLists then
  begin
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.Changed(Sender: TObject);
begin
  Rebuild;
end;

procedure TAtlasAttachDialog.TextChanged(Sender: TObject);
begin
  UpdateSend;
end;

procedure TAtlasAttachDialog.CommentChanged(Sender: TObject);
begin
  // Wer Text einträgt, will ihn senden: Haken setzen (OnClick baut die Liste neu).
  if Trim(FParts.CommentMemo.Lines.Text) <> '' then
  begin
    FParts.Comment.Checked := True;
  end;
  UpdateSend;
end;

procedure TAtlasAttachDialog.ListDblClick(Sender: TObject);
var
  mIndex: Integer;
begin
  // Kontrolle vor dem Senden: nur Bilder und Texte, die Atlas selbst geschrieben hat.
  if FParts.List.Selected = nil then
  begin
    Exit;
  end;
  mIndex := FParts.List.Selected.Index;
  if (mIndex >= 0) and (mIndex < Length(FPaths)) and (FPaths[mIndex] <> '') then
  begin
    TAtlasTrackerFiles.Shell.Open(FPaths[mIndex]);
  end;
end;

procedure TAtlasAttachDialog.UpdateSend;
begin
  if FParts.Send <> nil then
  begin
    FParts.Send.Enabled := CanSend;
  end;
end;

/// <summary>Der Ordner des Laufs enthält genau die Dateien von AFiles; Ergebnis: ihre Pfade.</summary>
function WriteTemp(ATemp: TAtlasAttachTemp; const AFiles: TAtlasAttachFiles): TArray<string>;
var
  mFile: TAtlasAttachFile;
begin
  Result := nil;
  if ATemp = nil then
  begin
    Exit;
  end;
  ATemp.Cleanup;
  for mFile in AFiles do
  begin
    Result := Result + [ATemp.Write(mFile)];
  end;
end;

/// <summary>Liste der Dateien; ohne Dateien, aber mit Kommentar: „nur Kommentar“.</summary>
procedure FillFileList(AList: TListView; const AFiles: TAtlasAttachFiles; AWithComment: Boolean);
var
  mFile: TAtlasAttachFile;
  mItem: TListItem;
begin
  AList.Items.BeginUpdate;
  try
    AList.Items.Clear;
    for mFile in AFiles do
    begin
      mItem := AList.Items.Add;
      mItem.Caption := mFile.DisplayName;
      mItem.SubItems.Add(TAtlasAttachDialog.SizeText(mFile.Size));
    end;
    if (Length(AFiles) = 0) and AWithComment then
    begin
      AList.Items.Add.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachCommentOnly);
    end;
  finally
    AList.Items.EndUpdate;
  end;
end;

procedure TAtlasAttachDialog.Rebuild;
var
  mFiles: TAtlasAttachFiles;
begin
  if not FFilled then
  begin
    Exit;
  end;
  mFiles := nil;
  FSources.UpdateState;
  FSources.Collect(mFiles);
  FFiles := TAtlasAttachFile.UniqueNames(mFiles);
  FPaths := WriteTemp(FTemp, FFiles);
  FillFileList(FParts.List, FFiles, WithComment);
  UpdateSend;
end;

function TAtlasAttachDialog.Key: string;
var
  mText: string;
  mSpace: Integer;
begin
  mText := Trim(FParts.Issue.Text);
  // „ATL-123 Titel“ aus den Vorschlägen: nur die Kennung.
  mSpace := Pos(' ', mText);
  if mSpace > 0 then
  begin
    mText := Copy(mText, 1, mSpace - 1);
  end;
  if Assigned(FInput.KeyOf) then
  begin
    Result := FInput.KeyOf(mText);
  end
  else
  begin
    Result := mText;
  end;
end;

function TAtlasAttachDialog.Files: TAtlasAttachFiles;
begin
  Result := FFiles;
end;

function TAtlasAttachDialog.CommentText: string;
begin
  Result := '';
  if FParts.Comment.Checked then
  begin
    Result := Trim(FParts.CommentMemo.Lines.Text);
  end;
end;

function TAtlasAttachDialog.WithComment: Boolean;
begin
  Result := FParts.Comment.Checked;
end;

function TAtlasAttachDialog.CanSend: Boolean;
begin
  Result := (Key <> '') and ((Length(FFiles) > 0) or (CommentText <> ''));
end;

class function TAtlasAttachDialog.SizeText(ABytes: Int64): string;
begin
  Result := FormatFloat('#,##0.0', ABytes / cBytesPerKilobyte, FormatSettings) + ' KB';
end;

end.
