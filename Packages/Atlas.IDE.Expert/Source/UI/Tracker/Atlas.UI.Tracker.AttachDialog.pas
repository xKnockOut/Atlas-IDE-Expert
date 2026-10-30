unit Atlas.UI.Tracker.AttachDialog;

// Dialog „An Issue anhängen“ (#1276), reine VCL ohne Open Tools API:
//   Issue: [ATL-123 Titel            ▼]
//   (Hinweis: hochladen bzw. GitHub-Rückfall über Zwischenablage und Kommentar)
//   Was anhängen?
//   [x] Bildschirmfoto des laufenden Programms: [Fenster ▼] [Per Klick wählen] [Markieren …]
//   [ ] Formular im Designer: Form1                                           [Markieren …]
//   [ ] Logdatei: [C:\…\app.log ▼] […]   [x] nur die letzten Zeilen: [200]
//   [ ] Debug-Notiz (Ort, Aufrufstapel, letzte Exception)
//   [ ] Exception-Verlauf (3 Einträge)
//   [ ] Kommentar mit Verweis auf die Anhänge:
//       [                                                       ]
//   Wird erst mit „Senden“ übertragen:  Name | Größe
//                                                  [Senden] [Abbrechen]
// - Die Liste zeigt genau die Dateien, die gesendet werden; sie liegen
//   zugleich im Ordner des Laufs (TAtlasAttachTemp), Doppelklick öffnet eine
//   zur Kontrolle. Gesendet wird nichts im Dialog: Die IDE-Schicht liest nach
//   „Senden“ Key, Files, Comment und WithComment.
// - Bilder werden auf issues.attach.maxImageWidth verkleinert und als PNG
//   angehängt; „Markieren …“ zeichnet Rahmen, Pfeile und Schwärzungen in das
//   Bild selbst (TAtlasImageMarkupForm).
// - Bildschirmfoto: Fenster des debuggten Prozesses (das Hauptfenster zuerst)
//   oder per Klick gewählt; Fenster der IDE selbst gelten nicht.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Atlas.Core.Tracker.Attach,
  Atlas.UI.Tracker.Capture;

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
    /// <summary>Debuggter Prozess; 0 = keiner (nur „Per Klick wählen“).</summary>
    ProcessId: DWORD;
    /// <summary>Formular im Designer; nil = keins. Bleibt beim Aufrufer.</summary>
    FormImage: TBitmap;
    FormName: string;
    LogFiles: TArray<string>;
    /// <summary>Debug-Notiz als Markdown; '' = Programm nicht angehalten.</summary>
    DebugNote: string;
    DebugNoteName: string;
    ExceptionsText: string;
    ExceptionCount: Integer;
    MaxImageWidth: Integer;
    /// <summary>Weitere Dateien, vorgewählt und gemeinsam abwählbar, etwa die eines Absturzfalls (#1355).
    /// </summary>
    Extra: TArray<TAtlasAttachFile>;
    class function Empty: TAtlasAttachDialogInput; static;
  end;

  TAtlasAttachDialog = class(TForm)
  public const
    Gap = 8;
    DialogWidth = 680;
  private
    FInput: TAtlasAttachDialogInput;
    FTemp: TAtlasAttachTemp;
    FWindows: TArray<TAtlasWindowInfo>;
    FPicker: TAtlasWindowPicker;
    FShot: TBitmap;
    FShotPng: TBytes;
    FForm: TBitmap;
    FFormPng: TBytes;
    FFiles: TAtlasAttachFiles;
    FPaths: TArray<string>;
    FIssue: TComboBox;
    FHint: TLabel;
    FScreenshot: TCheckBox;
    FWindowBox: TComboBox;
    FPick: TButton;
    FShotMarkup: TButton;
    FShotInfo: TLabel;
    FFormCheck: TCheckBox;
    FFormMarkup: TButton;
    FLog: TCheckBox;
    FLogBox: TComboBox;
    FLogBrowse: TButton;
    FLogLines: TCheckBox;
    FLogCount: TEdit;
    FLogInfo: TLabel;
    FDebugNote: TCheckBox;
    FExceptions: TCheckBox;
    FExtra: TCheckBox;
    FComment: TCheckBox;
    FCommentMemo: TMemo;
    FList: TListView;
    FSend: TButton;
    FUpdating: Boolean;
    FFilled: Boolean;
    /// <summary>BuildControls ist durch; vorher kann CreateWnd schon laufen (ClientWidth im Konstruktor).</summary>
    FBuilt: Boolean;
    function AddCheck(AParent: TWinControl; ATop: Integer; const ACaption: string): TCheckBox;
    function AddButton(AParent: TWinControl; ALeft, ATop, AWidth: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    procedure BuildControls;
    /// <summary>Einträge der Auswahllisten (brauchen das Fenster); einmal, sobald Fenster und Steuerelemente da sind.
    /// </summary>
    procedure FillLists;
    procedure Changed(Sender: TObject);
    procedure TextChanged(Sender: TObject);
    procedure WindowChanged(Sender: TObject);
    procedure PickClick(Sender: TObject);
    procedure Picked(AWindow: HWND);
    procedure ShotMarkupClick(Sender: TObject);
    procedure FormMarkupClick(Sender: TObject);
    procedure LogBrowseClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure CaptureWindow(AWindow: HWND);
    function ImagePng(ABitmap: TBitmap; var ACache: TBytes): TBytes;
    function LogLineCount: Integer;
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
    /// <summary>Bildschirmfoto setzen (übernimmt eine Kopie; nil löscht); auch für Tests.</summary>
    procedure SetScreenshot(ABitmap: TBitmap);
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
    property IssueBox: TComboBox read FIssue;
    property HintLabel: TLabel read FHint;
    property ScreenshotCheck: TCheckBox read FScreenshot;
    property WindowBox: TComboBox read FWindowBox;
    property FormCheck: TCheckBox read FFormCheck;
    property LogCheck: TCheckBox read FLog;
    property LogBox: TComboBox read FLogBox;
    property LogLinesCheck: TCheckBox read FLogLines;
    property LogCountEdit: TEdit read FLogCount;
    property DebugNoteCheck: TCheckBox read FDebugNote;
    property ExceptionsCheck: TCheckBox read FExceptions;
    property CommentCheck: TCheckBox read FComment;
    property CommentMemo: TMemo read FCommentMemo;
    property FileList: TListView read FList;
    property SendButton: TButton read FSend;
  end;

implementation

uses
  Winapi.ShellAPI,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.ImageMarkup;

{ TAtlasAttachDialogInput }

class function TAtlasAttachDialogInput.Empty: TAtlasAttachDialogInput;
begin
  Result := Default(TAtlasAttachDialogInput);
  Result.MaxImageWidth := 1920;
end;

{ TAtlasAttachDialog }

constructor TAtlasAttachDialog.CreateFor(AOwner: TComponent; const AInput: TAtlasAttachDialogInput;
  ATemp: TAtlasAttachTemp);
begin
  inherited CreateNew(AOwner);
  FInput := AInput;
  FTemp := ATemp;
  FPicker := TAtlasWindowPicker.Create;
  if FInput.FormImage <> nil then
  begin
    FForm := TBitmap.Create;
    FForm.Assign(FInput.FormImage);
  end;
  // Nicht festhalten: Der Aufrufer gibt das Bild frei.
  FInput.FormImage := nil;
  Caption := TAtlasStrings.Text(TAtlasTextId.AttachCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := DialogWidth;
  BuildControls;
end;

destructor TAtlasAttachDialog.Destroy;
begin
  FPicker.Free;
  FShot.Free;
  FForm.Free;
  FFiles := nil;
  FPaths := nil;
  inherited;
end;

procedure TAtlasAttachDialog.DoClose(var Action: TCloseAction);
begin
  FPicker.Cancel;
  inherited;
end;

class function TAtlasAttachDialog.SizeText(ABytes: Int64): string;
begin
  Result := FormatFloat('#,##0.0', ABytes / 1024) + ' KB';
end;

function TAtlasAttachDialog.AddCheck(AParent: TWinControl; ATop: Integer; const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(Gap, ATop, 300, 21);
  Result.Caption := ACaption;
  Result.OnClick := Changed;
end;

function TAtlasAttachDialog.AddButton(AParent: TWinControl; ALeft, ATop, AWidth: Integer; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 25);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TAtlasAttachDialog.BuildControls;
var
  mLabel: TLabel;
  mGroup: TGroupBox;
  mBottom: TPanel;
  mButton: TButton;
  mColumn: TListColumn;
  mTop, mRow: Integer;
begin
  mTop := Gap;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.SetBounds(Gap, mTop + 4, 60, 15);
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.AttachIssue);
  FIssue := TComboBox.Create(Self);
  FIssue.Parent := Self;
  FIssue.SetBounds(Gap + 70, mTop, DialogWidth - 2 * Gap - 70, 23);
  FIssue.Style := csDropDown;
  FIssue.OnChange := TextChanged;
  FIssue.Text := FInput.Key;
  Inc(mTop, 30);

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.AutoSize := False;
  FHint.WordWrap := True;
  FHint.SetBounds(Gap, mTop, DialogWidth - 2 * Gap, 32);
  if FInput.CanUpload then
    FHint.Caption := TAtlasStrings.Fmt(TAtlasTextId.AttachUploadHint, [FInput.Tracker])
  else
    FHint.Caption := TAtlasStrings.Fmt(TAtlasTextId.AttachFallbackHint, [FInput.Tracker]);
  Inc(mTop, 38);

  mGroup := TGroupBox.Create(Self);
  mGroup.Parent := Self;
  mGroup.Caption := TAtlasStrings.Text(TAtlasTextId.AttachSources);
  mGroup.SetBounds(Gap, mTop, DialogWidth - 2 * Gap, 248);
  mRow := 22;
  // Bildschirmfoto: Fenster des Programms, per Klick, markieren.
  FScreenshot := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachScreenshot));
  FScreenshot.Width := 250;
  FWindowBox := TComboBox.Create(Self);
  FWindowBox.Parent := mGroup;
  FWindowBox.Style := csDropDownList;
  FWindowBox.SetBounds(262, mRow - 2, 150, 23);
  FWindowBox.OnChange := WindowChanged;
  FPick := AddButton(mGroup, 418, mRow - 3, 120, TAtlasStrings.Text(TAtlasTextId.AttachWindowPick), PickClick);
  FShotMarkup := AddButton(mGroup, 544, mRow - 3, 110, TAtlasStrings.Text(TAtlasTextId.AttachMarkup),
    ShotMarkupClick);
  Inc(mRow, 24);
  FShotInfo := TLabel.Create(Self);
  FShotInfo.Parent := mGroup;
  FShotInfo.SetBounds(28, mRow, 600, 15);
  FShotInfo.Caption := '';
  Inc(mRow, 22);
  // Formular im Designer.
  if FForm <> nil then
    FFormCheck := AddCheck(mGroup, mRow, TAtlasStrings.Fmt(TAtlasTextId.AttachForm, [FInput.FormName]))
  else
    FFormCheck := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachNoForm));
  FFormCheck.Width := 520;
  FFormCheck.Enabled := FForm <> nil;
  FFormMarkup := AddButton(mGroup, 544, mRow - 3, 110, TAtlasStrings.Text(TAtlasTextId.AttachMarkup),
    FormMarkupClick);
  Inc(mRow, 28);
  // Logdatei mit Vorschlägen; nur die letzten N Zeilen.
  FLog := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachLog));
  FLog.Width := 90;
  FLogBox := TComboBox.Create(Self);
  FLogBox.Parent := mGroup;
  FLogBox.Style := csDropDown;
  FLogBox.SetBounds(102, mRow - 2, 250, 23);
  if Length(FInput.LogFiles) > 0 then
    FLogBox.Text := FInput.LogFiles[0];
  FLogBox.OnChange := Changed;
  FLogBrowse := AddButton(mGroup, 356, mRow - 3, 28, TAtlasStrings.Text(TAtlasTextId.AttachLogBrowse),
    LogBrowseClick);
  FLogLines := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachLogLines));
  FLogLines.SetBounds(394, mRow, 180, 21);
  FLogLines.Checked := True;
  FLogCount := TEdit.Create(Self);
  FLogCount.Parent := mGroup;
  FLogCount.NumbersOnly := True;
  FLogCount.SetBounds(580, mRow - 2, 74, 23);
  FLogCount.Text := IntToStr(TAtlasAttachLog.DefaultLines);
  FLogCount.OnChange := Changed;
  Inc(mRow, 24);
  FLogInfo := TLabel.Create(Self);
  FLogInfo.Parent := mGroup;
  FLogInfo.SetBounds(28, mRow, 600, 15);
  FLogInfo.Caption := '';
  Inc(mRow, 22);
  // Debug-Notiz nur bei angehaltenem Programm, Exception-Verlauf nur mit Einträgen.
  if FInput.DebugNote <> '' then
    FDebugNote := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachDebugNote))
  else
    FDebugNote := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachDebugNoteOff));
  FDebugNote.Width := 600;
  FDebugNote.Enabled := FInput.DebugNote <> '';
  Inc(mRow, 26);
  if FInput.ExceptionCount > 0 then
    FExceptions := AddCheck(mGroup, mRow, TAtlasStrings.Fmt(TAtlasTextId.AttachExceptions,
      [FInput.ExceptionCount]))
  else
    FExceptions := AddCheck(mGroup, mRow, TAtlasStrings.Text(TAtlasTextId.AttachExceptionsNone));
  FExceptions.Width := 600;
  FExceptions.Enabled := (FInput.ExceptionCount > 0) and (FInput.ExceptionsText <> '');
  Inc(mRow, 26);
  // Dateien eines Absturzfalls (#1355): vorgewählt, nur gemeinsam abwählbar.
  FExtra := AddCheck(mGroup, mRow, TAtlasStrings.Fmt(TAtlasTextId.AttachCrashCase, [Length(FInput.Extra)]));
  FExtra.Width := 600;
  FExtra.Enabled := Length(FInput.Extra) > 0;
  FExtra.Checked := FExtra.Enabled;
  Inc(mTop, mGroup.Height + Gap);

  FComment := AddCheck(Self, mTop, TAtlasStrings.Text(TAtlasTextId.AttachComment));
  FComment.Width := DialogWidth - 2 * Gap;
  Inc(mTop, 24);
  FCommentMemo := TMemo.Create(Self);
  FCommentMemo.Parent := Self;
  FCommentMemo.SetBounds(Gap, mTop, DialogWidth - 2 * Gap, 60);
  FCommentMemo.ScrollBars := ssVertical;
  // Tippen schreibt keine Dateien neu, nur „Senden“ wird geprüft.
  FCommentMemo.OnChange := TextChanged;
  Inc(mTop, 60 + Gap);

  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.SetBounds(Gap, mTop, DialogWidth - 2 * Gap, 15);
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.AttachFiles);
  Inc(mTop, 20);
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(Gap, mTop, DialogWidth - 2 * Gap, 110);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.ShowColumnHeaders := True;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnName);
  mColumn.Width := 480;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnSize);
  mColumn.Width := 120;
  mColumn.Alignment := taRightJustify;
  FList.OnDblClick := ListDblClick;
  Inc(mTop, 110 + Gap);

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.BevelOuter := bvNone;
  mBottom.SetBounds(0, mTop, DialogWidth, 44);
  FSend := TButton.Create(Self);
  FSend.Parent := mBottom;
  FSend.SetBounds(DialogWidth - 2 * (110 + Gap), 8, 110, 28);
  FSend.Caption := TAtlasStrings.Text(TAtlasTextId.AttachSend);
  FSend.Default := True;
  FSend.ModalResult := mrOk;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(DialogWidth - (110 + Gap), 8, 110, 28);
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  ClientHeight := mTop + 44;
  // Fenster des Programms; das Hauptfenster zuerst. In die Liste erst mit Fenster (CreateWnd).
  if FInput.ProcessId <> 0 then
    FWindows := TAtlasWindowCapture.WindowsOf(FInput.ProcessId);
  FWindowBox.Enabled := Length(FWindows) > 0;
  FPick.Enabled := True;
  FBuilt := True;
  // ClientWidth im Konstruktor legt das Fenster schon vor BuildControls an: dann hier füllen.
  if HandleAllocated then
    FillLists;
end;

procedure TAtlasAttachDialog.CreateWnd;
begin
  inherited;
  FillLists;
end;

procedure TAtlasAttachDialog.FillLists;
var
  mInfo: TAtlasWindowInfo;
  mText: string;
begin
  if FFilled or not FBuilt then
    Exit;
  FFilled := True;
  // Einträge von Auswahllisten brauchen das Fenster: nicht im Konstruktor.
  FWindowBox.Items.BeginUpdate;
  try
    for mInfo in FWindows do
      FWindowBox.Items.Add(mInfo.Caption);
    if Length(FWindows) = 0 then
      FWindowBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.AttachNoWindows));
  finally
    FWindowBox.Items.EndUpdate;
  end;
  FWindowBox.ItemIndex := 0;
  FIssue.Items.BeginUpdate;
  try
    for mText in FInput.Issues do
      FIssue.Items.Add(mText);
  finally
    FIssue.Items.EndUpdate;
  end;
  FLogBox.Items.BeginUpdate;
  try
    for mText in FInput.LogFiles do
      FLogBox.Items.Add(mText);
  finally
    FLogBox.Items.EndUpdate;
  end;
  // Das Hauptfenster des Programms gleich aufnehmen; die Liste braucht ihr Fenster.
  if Length(FWindows) > 0 then
    CaptureWindow(FWindows[0].Handle)
  else
    Rebuild;
end;

procedure TAtlasAttachDialog.SetScreenshot(ABitmap: TBitmap);
begin
  FreeAndNil(FShot);
  FShotPng := nil;
  if ABitmap <> nil then
  begin
    FShot := TBitmap.Create;
    FShot.Assign(ABitmap);
    FShotInfo.Caption := Format('%d × %d', [FShot.Width, FShot.Height]);
  end
  else
    FShotInfo.Caption := TAtlasStrings.Text(TAtlasTextId.AttachCaptureFailed);
  FUpdating := True;
  try
    FScreenshot.Checked := FShot <> nil;
  finally
    FUpdating := False;
  end;
  Rebuild;
end;

procedure TAtlasAttachDialog.CaptureWindow(AWindow: HWND);
var
  mBitmap: TBitmap;
begin
  mBitmap := TAtlasWindowCapture.Capture(AWindow);
  try
    SetScreenshot(mBitmap);
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasAttachDialog.WindowChanged(Sender: TObject);
begin
  if (FWindowBox.ItemIndex >= 0) and (FWindowBox.ItemIndex < Length(FWindows)) then
    CaptureWindow(FWindows[FWindowBox.ItemIndex].Handle);
end;

procedure TAtlasAttachDialog.PickClick(Sender: TObject);
begin
  FShotInfo.Caption := TAtlasStrings.Text(TAtlasTextId.AttachWindowPicking);
  FPick.Enabled := False;
  FPicker.Start(Picked);
end;

procedure TAtlasAttachDialog.Picked(AWindow: HWND);
begin
  FPick.Enabled := True;
  // Abgebrochen oder ein Fenster der IDE selbst (auch dieser Dialog): nichts ändern.
  if (AWindow = 0) or (TAtlasWindowCapture.ProcessOf(AWindow) = GetCurrentProcessId) then
  begin
    if FShot <> nil then
      FShotInfo.Caption := Format('%d × %d', [FShot.Width, FShot.Height])
    else
      FShotInfo.Caption := '';
    Exit;
  end;
  CaptureWindow(AWindow);
end;

procedure TAtlasAttachDialog.ShotMarkupClick(Sender: TObject);
begin
  if (FShot <> nil) and TAtlasImageMarkupForm.Execute(FShot) then
  begin
    FShotPng := nil;
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.FormMarkupClick(Sender: TObject);
begin
  if (FForm <> nil) and TAtlasImageMarkupForm.Execute(FForm) then
  begin
    FFormPng := nil;
    FFormCheck.Checked := True;
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.LogBrowseClick(Sender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(Self);
  try
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.AttachLogFilter);
    mDialog.Options := [ofFileMustExist, ofEnableSizing];
    if FLogBox.Text <> '' then
      mDialog.InitialDir := ExtractFilePath(FLogBox.Text);
    if not mDialog.Execute then
      Exit;
    FLogBox.Text := mDialog.FileName;
    FLog.Checked := True;
    Rebuild;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasAttachDialog.ListDblClick(Sender: TObject);
var
  mIndex: Integer;
begin
  // Kontrolle vor dem Senden: nur Bilder und Texte, die Atlas selbst geschrieben hat.
  if FList.Selected = nil then
    Exit;
  mIndex := FList.Selected.Index;
  if (mIndex >= 0) and (mIndex < Length(FPaths)) and (FPaths[mIndex] <> '') then
    ShellExecute(Handle, 'open', PChar(FPaths[mIndex]), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasAttachDialog.Changed(Sender: TObject);
begin
  if not FUpdating then
    Rebuild;
end;

procedure TAtlasAttachDialog.TextChanged(Sender: TObject);
begin
  UpdateSend;
end;

function TAtlasAttachDialog.ImagePng(ABitmap: TBitmap; var ACache: TBytes): TBytes;
var
  mScaled: TBitmap;
begin
  if ACache = nil then
  begin
    mScaled := TAtlasAttachImages.Scaled(ABitmap, FInput.MaxImageWidth);
    try
      ACache := TAtlasAttachImages.PngBytes(mScaled);
    finally
      mScaled.Free;
    end;
  end;
  Result := ACache;
end;

function TAtlasAttachDialog.LogLineCount: Integer;
begin
  Result := 0;
  if FLogLines.Checked then
    Result := StrToIntDef(FLogCount.Text, TAtlasAttachLog.DefaultLines);
end;

procedure TAtlasAttachDialog.Rebuild;
var
  mFiles: TAtlasAttachFiles;
  mFile: TAtlasAttachFile;
  mItem: TListItem;
  mLog, mText: string;
  mLines: Integer;
begin
  if not FFilled then
    Exit;
  mFiles := nil;
  FShotMarkup.Enabled := FShot <> nil;
  FScreenshot.Enabled := FShot <> nil;
  FFormMarkup.Enabled := FForm <> nil;
  FLogInfo.Caption := '';
  if FScreenshot.Checked and (FShot <> nil) then
    mFiles := mFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Screenshot,
      TAtlasStrings.Text(TAtlasTextId.AttachScreenshotName) + '.png', ImagePng(FShot, FShotPng))];
  if FFormCheck.Checked and (FForm <> nil) then
    mFiles := mFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Form,
      TAtlasStrings.Fmt(TAtlasTextId.AttachFormName, [FInput.FormName]) + '.png', ImagePng(FForm, FFormPng))];
  mLog := Trim(FLogBox.Text);
  if FLog.Checked and (mLog <> '') then
  begin
    mLines := LogLineCount;
    try
      mText := TAtlasAttachLog.ReadTail(mLog, mLines, TAtlasAttachLog.MaxBytes);
      mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.LogFile, ExtractFileName(mLog), mText);
      if mLines > 0 then
        mFile.Caption := TAtlasStrings.Fmt(TAtlasTextId.AttachLogCaption, [ExtractFileName(mLog), mLines]);
      mFiles := mFiles + [mFile];
    except
      // Nicht lesbar (fehlt, gesperrt): nur der Hinweis, kein Dialog.
      on E: EInOutError do
        FLogInfo.Caption := TAtlasStrings.Fmt(TAtlasTextId.AttachLogMissing, [ExtractFileName(mLog)]);
      on E: EFileStreamError do
        FLogInfo.Caption := TAtlasStrings.Fmt(TAtlasTextId.AttachLogMissing, [ExtractFileName(mLog)]);
    end;
  end;
  if FDebugNote.Checked and (FInput.DebugNote <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.DebugNote, FInput.DebugNoteName, FInput.DebugNote);
    mFile.Caption := TAtlasStrings.Text(TAtlasTextId.AttachDebugNoteCaption);
    mFiles := mFiles + [mFile];
  end;
  if FExceptions.Checked and (FInput.ExceptionsText <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.Exceptions,
      TAtlasStrings.Text(TAtlasTextId.AttachExceptionsName), FInput.ExceptionsText);
    mFile.Caption := TAtlasStrings.Text(TAtlasTextId.AttachExceptionsCaption);
    mFiles := mFiles + [mFile];
  end;
  if FExtra.Checked then
    mFiles := mFiles + FInput.Extra;
  FFiles := TAtlasAttachFile.UniqueNames(mFiles);
  // Der Ordner des Laufs enthält genau diese Dateien.
  FPaths := nil;
  if FTemp <> nil then
  begin
    FTemp.Cleanup;
    for mFile in FFiles do
      FPaths := FPaths + [FTemp.Write(mFile)];
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mFile in FFiles do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mFile.DisplayName;
      mItem.SubItems.Add(SizeText(mFile.Size));
    end;
    if (Length(FFiles) = 0) and WithComment then
      FList.Items.Add.Caption := TAtlasStrings.Text(TAtlasTextId.AttachCommentOnly);
  finally
    FList.Items.EndUpdate;
  end;
  UpdateSend;
end;

procedure TAtlasAttachDialog.UpdateSend;
begin
  if FSend <> nil then
    FSend.Enabled := CanSend;
end;

function TAtlasAttachDialog.Key: string;
var
  mText: string;
  mSpace: Integer;
begin
  mText := Trim(FIssue.Text);
  // „ATL-123 Titel“ aus den Vorschlägen: nur die Kennung.
  mSpace := Pos(' ', mText);
  if mSpace > 0 then
    mText := Copy(mText, 1, mSpace - 1);
  if Assigned(FInput.KeyOf) then
    Result := FInput.KeyOf(mText)
  else
    Result := mText;
end;

function TAtlasAttachDialog.Files: TAtlasAttachFiles;
begin
  Result := FFiles;
end;

function TAtlasAttachDialog.CommentText: string;
begin
  Result := '';
  if FComment.Checked then
    Result := Trim(FCommentMemo.Lines.Text);
end;

function TAtlasAttachDialog.WithComment: Boolean;
begin
  Result := FComment.Checked;
end;

function TAtlasAttachDialog.CanSend: Boolean;
begin
  Result := (Key <> '') and ((Length(FFiles) > 0) or (CommentText <> ''));
end;

end.
