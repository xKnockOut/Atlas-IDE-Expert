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
  Atlas.UI.Tracker.Capture,
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

  /// <summary>Steuerelemente des Dialogs; sie gehören dem Dialog.</summary>
  TAtlasAttachDialogParts = record
    Issue: TComboBox;
    Hint: TLabel;
    Screenshot: TCheckBox;
    WindowBox: TComboBox;
    Pick: TButton;
    ShotMarkup: TButton;
    ShotInfo: TLabel;
    FormCheck: TCheckBox;
    FormMarkup: TButton;
    Log: TCheckBox;
    LogBox: TComboBox;
    LogBrowse: TButton;
    LogLines: TCheckBox;
    LogCount: TEdit;
    LogInfo: TLabel;
    DebugNote: TCheckBox;
    Exceptions: TCheckBox;
    Extra: TCheckBox;
    Comment: TCheckBox;
    CommentMemo: TMemo;
    List: TListView;
    Send: TButton;
  end;

  /// <summary>Bildschirmfoto und Formularbild mit zwischengespeichertem PNG (nil = neu erzeugen).</summary>
  TAtlasAttachDialogImages = record
    Shot: TBitmap;
    ShotPng: TBytes;
    Form: TBitmap;
    FormPng: TBytes;
  end;

  TAtlasAttachDialog = class(TAtlasDialog)
  public const
    cGap = 8;
    cDialogWidth = 680;
  private
    FInput: TAtlasAttachDialogInput;
    FTemp: TAtlasAttachTemp;
    FWindows: TArray<TAtlasWindowInfo>;
    FPicker: TAtlasWindowPicker;
    FImages: TAtlasAttachDialogImages;
    FFiles: TAtlasAttachFiles;
    FPaths: TArray<string>;
    FParts: TAtlasAttachDialogParts;
    FUpdating: Boolean;
    FFilled: Boolean;
    /// <summary>BuildControls ist durch; vorher kann CreateWnd schon laufen (ClientWidth im Konstruktor).</summary>
    FBuilt: Boolean;
    procedure BuildControls;
    /// <summary>Einträge der Auswahllisten (brauchen das Fenster); einmal, sobald Fenster und Steuerelemente da sind.
    /// </summary>
    procedure FillLists;
    procedure Changed(Sender: TObject);
    procedure TextChanged(Sender: TObject);
    procedure WindowChanged(Sender: TObject);
    procedure PickClick(Sender: TObject);
    procedure Picked(AWindow: HWND);
    /// <summary>„Markieren …“ beim Bildschirmfoto oder beim Formular.</summary>
    procedure MarkupClick(Sender: TObject);
    procedure LogBrowseClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure CaptureWindow(AWindow: HWND);
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
    /// <summary>Steuerelemente (für Tests).</summary>
    property Parts: TAtlasAttachDialogParts read FParts;
  end;

implementation

uses
  System.Types,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Tracker.Files,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.ImageMarkup;

{ TAtlasAttachDialogInput }

class function TAtlasAttachDialogInput.Empty: TAtlasAttachDialogInput;
begin
  Result := Default(TAtlasAttachDialogInput);
  Result.MaxImageWidth := 1920;
end;

/// <summary>Ende der Logdatei ALog als Anhang (ALines Zeilen, &lt;= 0 = alle); False, wenn sie fehlt oder nicht
/// lesbar ist.</summary>
function LogAttachment(const ALog: string; ALines: Integer; out AFile: TAtlasAttachFile): Boolean;
var
  mText: string;
begin
  AFile := Default(TAtlasAttachFile);
  Result := TAtlasAttachLog.ReadTail(ALog, ALines, TAtlasAttachLog.cMaxBytes, mText);
  if not Result then
  begin
    Exit;
  end;
  AFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.LogFile, ExtractFileName(ALog), mText);
  if ALines > 0 then
  begin
    AFile.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachLogCaption, [ExtractFileName(ALog), ALines]);
  end;
end;

{ TAtlasAttachDialog }

constructor TAtlasAttachDialog.CreateFor(AOwner: TComponent; const AInput: TAtlasAttachDialogInput;
  ATemp: TAtlasAttachTemp);
begin
  inherited CreateDialog(AOwner, '', 0);
  FInput := AInput;
  FTemp := ATemp;
  FPicker := TAtlasWindowPicker.Create;
  if FInput.FormImage <> nil then
  begin
    FImages.Form := TBitmap.Create;
    FImages.Form.Assign(FInput.FormImage);
  end;
  // Nicht festhalten: Der Aufrufer gibt das Bild frei.
  FInput.FormImage := nil;
  Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := ScaleValue(cDialogWidth);
  BuildControls;
end;

destructor TAtlasAttachDialog.Destroy;
begin
  FPicker.Free;
  FImages.Shot.Free;
  FImages.Form.Free;
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
  Result := FormatFloat('#,##0.0', ABytes / 1024, FormatSettings) + ' KB';
end;

function AddCheck(ADialog: TAtlasAttachDialog; AParent: TWinControl; ATop: Integer;
  const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(ADialog);
  Result.Parent := AParent;
  Result.SetBounds(TAtlasAttachDialog.cGap, ATop, 300, 21);
  Result.Caption := ACaption;
  Result.OnClick := ADialog.Changed;
end;

/// <summary>Knopf in AParent; ABounds mit Bounds(Links, Oben, Breite, 25).</summary>
function AddButton(ADialog: TAtlasAttachDialog; AParent: TWinControl; const ABounds: TRect; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(ADialog);
  Result.Parent := AParent;
  Result.BoundsRect := ABounds;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function AddInfo(ADialog: TAtlasAttachDialog; AParent: TWinControl; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(ADialog);
  Result.Parent := AParent;
  Result.SetBounds(28, ATop, 600, 15);
  Result.Caption := '';
end;

/// <summary>Eingabe des Issues und Hinweis zum Hochladen.</summary>
procedure AddIssueRows(ADialog: TAtlasAttachDialog; var ATop: Integer);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(ADialog);
  mLabel.Parent := ADialog;
  mLabel.SetBounds(TAtlasAttachDialog.cGap, ATop + 4, 60, 15);
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachIssue);
  ADialog.FParts.Issue := TComboBox.Create(ADialog);
  ADialog.FParts.Issue.Parent := ADialog;
  ADialog.FParts.Issue.SetBounds(TAtlasAttachDialog.cGap + 70, ATop,
    TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap - 70, 23);
  ADialog.FParts.Issue.Style := csDropDown;
  ADialog.FParts.Issue.OnChange := ADialog.TextChanged;
  ADialog.FParts.Issue.Text := ADialog.FInput.Key;
  Inc(ATop, 30);
  ADialog.FParts.Hint := TLabel.Create(ADialog);
  ADialog.FParts.Hint.Parent := ADialog;
  ADialog.FParts.Hint.AutoSize := False;
  ADialog.FParts.Hint.WordWrap := True;
  ADialog.FParts.Hint.SetBounds(TAtlasAttachDialog.cGap, ATop,
    TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap, 32);
  if ADialog.FInput.CanUpload then
  begin
    ADialog.FParts.Hint.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachUploadHint,
      [ADialog.FInput.Tracker]);
  end
  else
  begin
    ADialog.FParts.Hint.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachFallbackHint,
      [ADialog.FInput.Tracker]);
  end;
  Inc(ATop, 38);
end;

/// <summary>Bildschirmfoto: Fenster des Programms, per Klick, markieren.</summary>
procedure AddScreenshotRows(ADialog: TAtlasAttachDialog; AGroup: TWinControl; var ARow: Integer);
begin
  ADialog.FParts.Screenshot := AddCheck(ADialog, AGroup, ARow,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachScreenshot));
  ADialog.FParts.Screenshot.Width := ADialog.FParts.Screenshot.ScaleValue(250);
  ADialog.FParts.WindowBox := TComboBox.Create(ADialog);
  ADialog.FParts.WindowBox.Parent := AGroup;
  ADialog.FParts.WindowBox.Style := csDropDownList;
  ADialog.FParts.WindowBox.SetBounds(262, ARow - 2, 150, 23);
  ADialog.FParts.WindowBox.OnChange := ADialog.WindowChanged;
  ADialog.FParts.Pick := AddButton(ADialog, AGroup, Bounds(418, ARow - 3, 120, 25),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachWindowPick), ADialog.PickClick);
  ADialog.FParts.ShotMarkup := AddButton(ADialog, AGroup, Bounds(544, ARow - 3, 110, 25),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachMarkup), ADialog.MarkupClick);
  Inc(ARow, 24);
  ADialog.FParts.ShotInfo := AddInfo(ADialog, AGroup, ARow);
  Inc(ARow, 22);
end;

/// <summary>Formular im Designer.</summary>
procedure AddFormRow(ADialog: TAtlasAttachDialog; AGroup: TWinControl; var ARow: Integer);
var
  mCaption: string;
begin
  if ADialog.FImages.Form <> nil then
  begin
    mCaption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachForm, [ADialog.FInput.FormName]);
  end
  else
  begin
    mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachNoForm);
  end;
  ADialog.FParts.FormCheck := AddCheck(ADialog, AGroup, ARow, mCaption);
  ADialog.FParts.FormCheck.Width := ADialog.FParts.FormCheck.ScaleValue(520);
  ADialog.FParts.FormCheck.Enabled := ADialog.FImages.Form <> nil;
  ADialog.FParts.FormMarkup := AddButton(ADialog, AGroup, Bounds(544, ARow - 3, 110, 25),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachMarkup), ADialog.MarkupClick);
  Inc(ARow, 28);
end;

/// <summary>Logdatei mit Vorschlägen; nur die letzten N Zeilen.</summary>
procedure AddLogRows(ADialog: TAtlasAttachDialog; AGroup: TWinControl; var ARow: Integer);
begin
  ADialog.FParts.Log := AddCheck(ADialog, AGroup, ARow, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachLog));
  ADialog.FParts.Log.Width := ADialog.FParts.Log.ScaleValue(90);
  ADialog.FParts.LogBox := TComboBox.Create(ADialog);
  ADialog.FParts.LogBox.Parent := AGroup;
  ADialog.FParts.LogBox.Style := csDropDown;
  ADialog.FParts.LogBox.SetBounds(102, ARow - 2, 250, 23);
  if Length(ADialog.FInput.LogFiles) > 0 then
  begin
    ADialog.FParts.LogBox.Text := ADialog.FInput.LogFiles[0];
  end;
  ADialog.FParts.LogBox.OnChange := ADialog.Changed;
  ADialog.FParts.LogBrowse := AddButton(ADialog, AGroup, Bounds(356, ARow - 3, 28, 25),
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachLogBrowse), ADialog.LogBrowseClick);
  ADialog.FParts.LogLines := AddCheck(ADialog, AGroup, ARow,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachLogLines));
  ADialog.FParts.LogLines.SetBounds(394, ARow, 180, 21);
  ADialog.FParts.LogLines.Checked := True;
  ADialog.FParts.LogCount := TEdit.Create(ADialog);
  ADialog.FParts.LogCount.Parent := AGroup;
  ADialog.FParts.LogCount.NumbersOnly := True;
  ADialog.FParts.LogCount.SetBounds(580, ARow - 2, 74, 23);
  ADialog.FParts.LogCount.Text := IntToStr(TAtlasAttachLog.cDefaultLines);
  ADialog.FParts.LogCount.OnChange := ADialog.Changed;
  Inc(ARow, 24);
  ADialog.FParts.LogInfo := AddInfo(ADialog, AGroup, ARow);
  Inc(ARow, 22);
end;

/// <summary>Debug-Notiz nur bei angehaltenem Programm, Exception-Verlauf nur mit Einträgen, Dateien eines
/// Absturzfalls (#1355) vorgewählt und nur gemeinsam abwählbar.</summary>
procedure AddNoteRows(ADialog: TAtlasAttachDialog; AGroup: TWinControl; var ARow: Integer);
var
  mCaption: string;
begin
  mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachDebugNoteOff);
  if ADialog.FInput.DebugNote <> '' then
  begin
    mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachDebugNote);
  end;
  ADialog.FParts.DebugNote := AddCheck(ADialog, AGroup, ARow, mCaption);
  ADialog.FParts.DebugNote.Width := ADialog.FParts.DebugNote.ScaleValue(600);
  ADialog.FParts.DebugNote.Enabled := ADialog.FInput.DebugNote <> '';
  Inc(ARow, 26);
  mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachExceptionsNone);
  if ADialog.FInput.ExceptionCount > 0 then
  begin
    mCaption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachExceptions, [ADialog.FInput.ExceptionCount]);
  end;
  ADialog.FParts.Exceptions := AddCheck(ADialog, AGroup, ARow, mCaption);
  ADialog.FParts.Exceptions.Width := ADialog.FParts.Exceptions.ScaleValue(600);
  ADialog.FParts.Exceptions.Enabled := (ADialog.FInput.ExceptionCount > 0) and (ADialog.FInput.ExceptionsText <> '');
  Inc(ARow, 26);
  ADialog.FParts.Extra := AddCheck(ADialog, AGroup, ARow,
    TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachCrashCase, [Length(ADialog.FInput.Extra)]));
  ADialog.FParts.Extra.Width := ADialog.FParts.Extra.ScaleValue(600);
  ADialog.FParts.Extra.Enabled := Length(ADialog.FInput.Extra) > 0;
  ADialog.FParts.Extra.Checked := ADialog.FParts.Extra.Enabled;
end;

/// <summary>Gruppe „Was anhängen?“ mit allen Quellen.</summary>
procedure AddSources(ADialog: TAtlasAttachDialog; var ATop: Integer);
var
  mGroup: TGroupBox;
  mRow: Integer;
begin
  mGroup := TGroupBox.Create(ADialog);
  mGroup.Parent := ADialog;
  mGroup.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachSources);
  mGroup.SetBounds(TAtlasAttachDialog.cGap, ATop, TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap, 248);
  mRow := 22;
  AddScreenshotRows(ADialog, mGroup, mRow);
  AddFormRow(ADialog, mGroup, mRow);
  AddLogRows(ADialog, mGroup, mRow);
  AddNoteRows(ADialog, mGroup, mRow);
  Inc(ATop, mGroup.Height + TAtlasAttachDialog.cGap);
end;

/// <summary>Kommentar mit Verweis auf die Anhänge.</summary>
procedure AddCommentRows(ADialog: TAtlasAttachDialog; var ATop: Integer);
begin
  ADialog.FParts.Comment := AddCheck(ADialog, ADialog, ATop,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachComment));
  ADialog.FParts.Comment.Width := TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap;
  Inc(ATop, 24);
  ADialog.FParts.CommentMemo := TMemo.Create(ADialog);
  ADialog.FParts.CommentMemo.Parent := ADialog;
  ADialog.FParts.CommentMemo.SetBounds(TAtlasAttachDialog.cGap, ATop,
    TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap, 60);
  ADialog.FParts.CommentMemo.ScrollBars := ssVertical;
  // Tippen schreibt keine Dateien neu, nur „Senden“ wird geprüft.
  ADialog.FParts.CommentMemo.OnChange := ADialog.TextChanged;
  Inc(ATop, 60 + TAtlasAttachDialog.cGap);
end;

/// <summary>Liste der Dateien, die gesendet werden.</summary>
procedure AddFileList(ADialog: TAtlasAttachDialog; var ATop: Integer);
var
  mLabel: TLabel;
  mColumn: TListColumn;
begin
  mLabel := TLabel.Create(ADialog);
  mLabel.Parent := ADialog;
  mLabel.SetBounds(TAtlasAttachDialog.cGap, ATop, TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap, 15);
  mLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachFiles);
  Inc(ATop, 20);
  ADialog.FParts.List := TListView.Create(ADialog);
  ADialog.FParts.List.Parent := ADialog;
  ADialog.FParts.List.SetBounds(TAtlasAttachDialog.cGap, ATop,
    TAtlasAttachDialog.cDialogWidth - 2 * TAtlasAttachDialog.cGap, 110);
  ADialog.FParts.List.ViewStyle := vsReport;
  ADialog.FParts.List.ReadOnly := True;
  ADialog.FParts.List.RowSelect := True;
  ADialog.FParts.List.ShowColumnHeaders := True;
  mColumn := ADialog.FParts.List.Columns.Add;
  mColumn.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnName);
  mColumn.Width := ADialog.FParts.List.ScaleValue(480);
  mColumn := ADialog.FParts.List.Columns.Add;
  mColumn.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewColumnSize);
  mColumn.Width := ADialog.FParts.List.ScaleValue(120);
  mColumn.Alignment := taRightJustify;
  ADialog.FParts.List.OnDblClick := ADialog.ListDblClick;
  Inc(ATop, 110 + TAtlasAttachDialog.cGap);
end;

/// <summary>„Senden“ und „Abbrechen“ unten rechts.</summary>
procedure AddButtons(ADialog: TAtlasAttachDialog; ATop: Integer);
var
  mBottom: TPanel;
  mButton: TButton;
begin
  mBottom := TPanel.Create(ADialog);
  mBottom.Parent := ADialog;
  mBottom.BevelOuter := bvNone;
  mBottom.SetBounds(0, ATop, TAtlasAttachDialog.cDialogWidth, 44);
  ADialog.FParts.Send := TButton.Create(ADialog);
  ADialog.FParts.Send.Parent := mBottom;
  ADialog.FParts.Send.SetBounds(TAtlasAttachDialog.cDialogWidth - 2 * (110 + TAtlasAttachDialog.cGap), 8, 110, 28);
  ADialog.FParts.Send.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachSend);
  ADialog.FParts.Send.Default := True;
  ADialog.FParts.Send.ModalResult := mrOk;
  mButton := TButton.Create(ADialog);
  mButton.Parent := mBottom;
  mButton.SetBounds(TAtlasAttachDialog.cDialogWidth - (110 + TAtlasAttachDialog.cGap), 8, 110, 28);
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
end;

procedure TAtlasAttachDialog.BuildControls;
var
  mTop: Integer;
begin
  mTop := cGap;
  AddIssueRows(Self, mTop);
  AddSources(Self, mTop);
  AddCommentRows(Self, mTop);
  AddFileList(Self, mTop);
  AddButtons(Self, mTop);
  ClientHeight := mTop + ScaleValue(44);
  // Fenster des Programms; das Hauptfenster zuerst. In die Liste erst mit Fenster (CreateWnd).
  if FInput.ProcessId <> 0 then
  begin
    FWindows := TAtlasWindowCapture.WindowsOf(FInput.ProcessId);
  end;
  FParts.WindowBox.Enabled := Length(FWindows) > 0;
  FParts.Pick.Enabled := True;
  FBuilt := True;
  // ClientWidth im Konstruktor legt das Fenster schon vor BuildControls an: dann hier füllen.
  if HandleAllocated then
  begin
    FillLists;
  end;
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
  begin
    Exit;
  end;
  FFilled := True;
  // Einträge von Auswahllisten brauchen das Fenster: nicht im Konstruktor.
  FParts.WindowBox.Items.BeginUpdate;
  try
    for mInfo in FWindows do
    begin
      FParts.WindowBox.Items.Add(mInfo.Caption);
    end;
    if Length(FWindows) = 0 then
    begin
      FParts.WindowBox.Items.Add(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachNoWindows));
    end;
  finally
    FParts.WindowBox.Items.EndUpdate;
  end;
  FParts.WindowBox.ItemIndex := 0;
  FParts.Issue.Items.BeginUpdate;
  try
    for mText in FInput.Issues do
    begin
      FParts.Issue.Items.Add(mText);
    end;
  finally
    FParts.Issue.Items.EndUpdate;
  end;
  FParts.LogBox.Items.BeginUpdate;
  try
    for mText in FInput.LogFiles do
    begin
      FParts.LogBox.Items.Add(mText);
    end;
  finally
    FParts.LogBox.Items.EndUpdate;
  end;
  // Das Hauptfenster des Programms gleich aufnehmen; die Liste braucht ihr Fenster.
  if Length(FWindows) > 0 then
  begin
    CaptureWindow(FWindows[0].Handle);
  end
  else
  begin
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.SetScreenshot(ABitmap: TBitmap);
begin
  FreeAndNil(FImages.Shot);
  FImages.ShotPng := nil;
  if ABitmap <> nil then
  begin
    FImages.Shot := TBitmap.Create;
    FImages.Shot.Assign(ABitmap);
    FParts.ShotInfo.Caption := Format('%d × %d', [FImages.Shot.Width, FImages.Shot.Height]);
  end
  else
  begin
    FParts.ShotInfo.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachCaptureFailed);
  end;
  FUpdating := True;
  try
    FParts.Screenshot.Checked := FImages.Shot <> nil;
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
  if (FParts.WindowBox.ItemIndex >= 0) and (FParts.WindowBox.ItemIndex < Length(FWindows)) then
  begin
    CaptureWindow(FWindows[FParts.WindowBox.ItemIndex].Handle);
  end;
end;

procedure TAtlasAttachDialog.PickClick(Sender: TObject);
begin
  FParts.ShotInfo.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachWindowPicking);
  FParts.Pick.Enabled := False;
  FPicker.Start(Picked);
end;

procedure TAtlasAttachDialog.Picked(AWindow: HWND);
begin
  FParts.Pick.Enabled := True;
  // Abgebrochen oder ein Fenster der IDE selbst (auch dieser Dialog): nichts ändern.
  if (AWindow = 0) or (TAtlasWindowCapture.ProcessOf(AWindow) = GetCurrentProcessId) then
  begin
    if FImages.Shot <> nil then
    begin
      FParts.ShotInfo.Caption := Format('%d × %d', [FImages.Shot.Width, FImages.Shot.Height]);
    end
    else
    begin
      FParts.ShotInfo.Caption := '';
    end;
    Exit;
  end;
  CaptureWindow(AWindow);
end;

procedure TAtlasAttachDialog.MarkupClick(Sender: TObject);
begin
  if Sender = FParts.ShotMarkup then
  begin
    if (FImages.Shot <> nil) and TAtlasImageMarkupForm.Execute(FImages.Shot) then
    begin
      FImages.ShotPng := nil;
      Rebuild;
    end;
  end
  else if (FImages.Form <> nil) and TAtlasImageMarkupForm.Execute(FImages.Form) then
  begin
    FImages.FormPng := nil;
    FParts.FormCheck.Checked := True;
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.LogBrowseClick(Sender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(Self);
  try
    mDialog.Filter := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachLogFilter);
    mDialog.Options := [ofFileMustExist, ofEnableSizing];
    if FParts.LogBox.Text <> '' then
    begin
      mDialog.InitialDir := ExtractFilePath(FParts.LogBox.Text);
    end;
    if not mDialog.Execute then
    begin
      Exit;
    end;
    FParts.LogBox.Text := mDialog.FileName;
    FParts.Log.Checked := True;
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

procedure TAtlasAttachDialog.Changed(Sender: TObject);
begin
  if not FUpdating then
  begin
    Rebuild;
  end;
end;

procedure TAtlasAttachDialog.TextChanged(Sender: TObject);
begin
  UpdateSend;
end;

function ImagePng(ABitmap: TBitmap; AMaxWidth: Integer; var ACache: TBytes): TBytes;
var
  mScaled: TBitmap;
begin
  if ACache = nil then
  begin
    mScaled := TAtlasAttachImages.Scaled(ABitmap, AMaxWidth);
    try
      ACache := TAtlasAttachImages.PngBytes(mScaled);
    finally
      mScaled.Free;
    end;
  end;
  Result := ACache;
end;

function LogLineCount(const AParts: TAtlasAttachDialogParts): Integer;
begin
  Result := 0;
  if AParts.LogLines.Checked then
  begin
    Result := StrToIntDef(AParts.LogCount.Text, TAtlasAttachLog.cDefaultLines);
  end;
end;

/// <summary>Gewählte Bilder als PNG anhängen.</summary>
procedure AddImages(ADialog: TAtlasAttachDialog; var AFiles: TAtlasAttachFiles);
begin
  if ADialog.FParts.Screenshot.Checked and (ADialog.FImages.Shot <> nil) then
  begin
    AFiles := AFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Screenshot,
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachScreenshotName) + '.png',
      ImagePng(ADialog.FImages.Shot, ADialog.FInput.MaxImageWidth, ADialog.FImages.ShotPng))];
  end;
  if ADialog.FParts.FormCheck.Checked and (ADialog.FImages.Form <> nil) then
  begin
    AFiles := AFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Form,
      TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachFormName, [ADialog.FInput.FormName]) + '.png',
      ImagePng(ADialog.FImages.Form, ADialog.FInput.MaxImageWidth, ADialog.FImages.FormPng))];
  end;
end;

/// <summary>Gewählte Logdatei anhängen; nicht lesbar (fehlt, gesperrt): nur der Hinweis, kein Dialog.</summary>
procedure AddLog(const AParts: TAtlasAttachDialogParts; var AFiles: TAtlasAttachFiles);
var
  mLog: string;
  mFile: TAtlasAttachFile;
begin
  AParts.LogInfo.Caption := '';
  mLog := Trim(AParts.LogBox.Text);
  if not AParts.Log.Checked or (mLog = '') then
  begin
    Exit;
  end;
  if LogAttachment(mLog, LogLineCount(AParts), mFile) then
  begin
    AFiles := AFiles + [mFile];
  end
  else
  begin
    AParts.LogInfo.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.AttachLogMissing, [ExtractFileName(mLog)]);
  end;
end;

/// <summary>Debug-Notiz, Exception-Verlauf und Dateien des Absturzfalls anhängen.</summary>
procedure AddNotes(ADialog: TAtlasAttachDialog; var AFiles: TAtlasAttachFiles);
var
  mFile: TAtlasAttachFile;
begin
  if ADialog.FParts.DebugNote.Checked and (ADialog.FInput.DebugNote <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.DebugNote, ADialog.FInput.DebugNoteName,
      ADialog.FInput.DebugNote);
    mFile.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachDebugNoteCaption);
    AFiles := AFiles + [mFile];
  end;
  if ADialog.FParts.Exceptions.Checked and (ADialog.FInput.ExceptionsText <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.Exceptions,
      TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachExceptionsName), ADialog.FInput.ExceptionsText);
    mFile.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachExceptionsCaption);
    AFiles := AFiles + [mFile];
  end;
  if ADialog.FParts.Extra.Checked then
  begin
    AFiles := AFiles + ADialog.FInput.Extra;
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
      AList.Items.Add.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.AttachCommentOnly);
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
  FParts.ShotMarkup.Enabled := FImages.Shot <> nil;
  FParts.Screenshot.Enabled := FImages.Shot <> nil;
  FParts.FormMarkup.Enabled := FImages.Form <> nil;
  AddImages(Self, mFiles);
  AddLog(FParts, mFiles);
  AddNotes(Self, mFiles);
  FFiles := TAtlasAttachFile.UniqueNames(mFiles);
  FPaths := WriteTemp(FTemp, FFiles);
  FillFileList(FParts.List, FFiles, WithComment);
  UpdateSend;
end;

procedure TAtlasAttachDialog.UpdateSend;
begin
  if FParts.Send <> nil then
  begin
    FParts.Send.Enabled := CanSend;
  end;
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

end.
