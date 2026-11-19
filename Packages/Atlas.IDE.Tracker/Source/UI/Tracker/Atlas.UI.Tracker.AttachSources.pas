unit Atlas.UI.Tracker.AttachSources;

// Gruppe „Was anhängen?“ im Dialog „An Issue anhängen“ (#1276), reine VCL ohne Open Tools API:
//   [x] Bildschirmfoto des laufenden Programms: [Fenster ▼] [Per Klick wählen] [Markieren …]
//   [ ] Formular im Designer: Form1                                           [Markieren …]
//   [ ] Logdatei: [C:\…\app.log ▼] […]   [x] nur die letzten Zeilen: [200]
//   [ ] Debug-Notiz (Ort, Aufrufstapel, letzte Exception)
//   [ ] Exception-Verlauf (3 Einträge)
//   [ ] Dateien des Absturzfalls
// - Hält Bildschirmfoto und Formularbild samt zwischengespeichertem PNG und
//   sammelt die gewählten Quellen als Dateien (Collect). Jede Änderung meldet
//   OnChanged; der Dialog baut daraufhin seine Liste neu.
// - Bilder werden auf issues.attach.maxImageWidth verkleinert und als PNG
//   angehängt; „Markieren …“ zeichnet Rahmen, Pfeile und Schwärzungen in das
//   Bild selbst (TAtlasImageMarkupForm).
// - Bildschirmfoto: Fenster des debuggten Prozesses (das Hauptfenster zuerst)
//   oder per Klick gewählt; Fenster der IDE selbst gelten nicht. „Per Klick
//   wählen“ holt das debuggte Programm dafür nach vorn
//   (issues.attach.raiseProgram) und danach den Dialog zurück.
// - Ein Pfad bei „Logdatei“ setzt den Haken davor.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Atlas.Core.Tracker.Attach,
  Atlas.UI.Tracker.Capture;

type
  /// <summary>Was die Gruppe anbieten kann; die IDE-Schicht füllt es.</summary>
  TAtlasAttachSourcesInput = record
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
    /// <summary>„Per Klick wählen“ holt das Hauptfenster von ProcessId nach vorn (issues.attach.raiseProgram).
    /// </summary>
    RaiseProgram: Boolean;
    /// <summary>Weitere Dateien, vorgewählt und gemeinsam abwählbar, etwa die eines Absturzfalls (#1355).
    /// </summary>
    Extra: TArray<TAtlasAttachFile>;
    class function Empty: TAtlasAttachSourcesInput; static;
  end;

  /// <summary>Steuerelemente der Gruppe; sie gehören dem Dialog.</summary>
  TAtlasAttachSourceParts = record
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
  end;

  /// <summary>Bildschirmfoto und Formularbild mit zwischengespeichertem PNG (nil = neu erzeugen).</summary>
  TAtlasAttachSourceImages = record
    Shot: TBitmap;
    ShotPng: TBytes;
    Form: TBitmap;
    FormPng: TBytes;
  end;

  /// <summary>Quellen des Anhangs: Steuerelemente der Gruppe, Bilder, Fensterwahl und das Sammeln der Dateien.
  /// </summary>
  TAtlasAttachSources = class
  private
    FDialog: TWinControl;
    FInput: TAtlasAttachSourcesInput;
    FWindows: TArray<TAtlasWindowInfo>;
    FPicker: TAtlasWindowPicker;
    FImages: TAtlasAttachSourceImages;
    FParts: TAtlasAttachSourceParts;
    FUpdating: Boolean;
    /// <summary>„Per Klick wählen“ hat das Programm nach vorn geholt: danach den Dialog zurückholen.</summary>
    FRaised: Boolean;
    FOnChanged: TNotifyEvent;
    procedure AddScreenshotRows(AGroup: TWinControl; var ARow: Integer);
    procedure AddFormRow(AGroup: TWinControl; var ARow: Integer);
    procedure AddLogRows(AGroup: TWinControl; var ARow: Integer);
    procedure AddNoteRows(AGroup: TWinControl; var ARow: Integer);
    procedure AddImages(var AFiles: TAtlasAttachFiles);
    procedure AddNotes(var AFiles: TAtlasAttachFiles);
    procedure Changed(Sender: TObject);
    procedure LogChanged(Sender: TObject);
    procedure WindowChanged(Sender: TObject);
    procedure PickClick(Sender: TObject);
    procedure Picked(AWindow: HWND);
    procedure PickedWindow(AWindow: HWND);
    /// <summary>„Markieren …“ beim Bildschirmfoto oder beim Formular.</summary>
    procedure MarkupClick(Sender: TObject);
    procedure LogBrowseClick(Sender: TObject);
    procedure CaptureWindow(AWindow: HWND);
  public
    /// <summary>ADialog: Besitzer der Steuerelemente; ihn holt „Per Klick wählen“ nach dem Bild nach vorn. Das
    /// Formularbild wird kopiert, AInput.FormImage bleibt beim Aufrufer.</summary>
    constructor Create(ADialog: TWinControl; const AInput: TAtlasAttachSourcesInput);
    destructor Destroy; override;
    /// <summary>Gruppe „Was anhängen?“ ab ATop in ADialog; ATop wandert unter die Gruppe.</summary>
    procedure Build(var ATop: Integer);
    /// <summary>Einträge der Auswahllisten (brauchen das Fenster); nimmt das Hauptfenster des Programms auf.
    /// True, wenn dabei schon OnChanged kam.</summary>
    function FillLists: Boolean;
    /// <summary>Knöpfe nach den Bildern sperren bzw. freigeben.</summary>
    procedure UpdateState;
    /// <summary>Gewählte Quellen als Dateien an AFiles anhängen.</summary>
    procedure Collect(var AFiles: TAtlasAttachFiles);
    /// <summary>Bildschirmfoto setzen (übernimmt eine Kopie; nil löscht); auch für Tests.</summary>
    procedure SetScreenshot(ABitmap: TBitmap);
    /// <summary>Laufendes „Per Klick wählen“ beenden (Dialog schließt).</summary>
    procedure Cancel;
    property Parts: TAtlasAttachSourceParts read FParts;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Types,
  Vcl.Dialogs,
  Atlas.UI.Tracker.Attach.Strings,
  Atlas.UI.Tracker.ImageMarkup,
  Atlas.UI.Foundation.Scaling;

const
  cGap = 8;
  /// <summary>Breite der Gruppe bei 96 dpi (Breite des Dialogs ohne Ränder).</summary>
  cGroupWidth = 664;
  cGroupHeight = 248;
  /// <summary>Vorgabe für die größte Breite eines Bilds in Pixeln.</summary>
  cMaxImageWidth = 1920;
  // Maße der Zeilen in der Gruppe bei 96 dpi.
  cFirstRow = 22;
  cCheckWidth = 300;
  cCheckHeight = 21;
  cBoxHeight = 23;
  cButtonHeight = 25;
  /// <summary>Feld bzw. Knopf steht so viel höher als das Häkchen derselben Zeile.</summary>
  cBoxRaise = 2;
  cButtonRaise = 3;
  /// <summary>Hinweis unter einer Zeile, eingerückt wie der Text des Häkchens.</summary>
  cInfoLeft = 28;
  cInfoWidth = 600;
  cInfoHeight = 15;
  cRow = 24;
  cInfoRow = 22;
  cFormRow = 28;
  cNoteRow = 26;
  cMarkupLeft = 544;
  cMarkupWidth = 110;
  cScreenshotWidth = 250;
  cWindowLeft = 262;
  cWindowWidth = 150;
  cPickLeft = 418;
  cPickWidth = 120;
  cFormWidth = 520;
  cLogWidth = 90;
  cLogLeft = 102;
  cLogBoxWidth = 250;
  cBrowseLeft = 356;
  cBrowseWidth = 28;
  cLinesLeft = 394;
  cLinesWidth = 180;
  cCountLeft = 580;
  cCountWidth = 74;

{ TAtlasAttachSourcesInput }

class function TAtlasAttachSourcesInput.Empty: TAtlasAttachSourcesInput;
begin
  Result := Default(TAtlasAttachSourcesInput);
  Result.MaxImageWidth := cMaxImageWidth;
  Result.RaiseProgram := True;
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
    AFile.Caption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachLogCaption, [ExtractFileName(ALog), ALines]);
  end;
end;

/// <summary>Hauptfenster des debuggten Programms nach vorn; False ohne Programm, Fenster oder Einstellung.</summary>
function RaiseProgram(const AInput: TAtlasAttachSourcesInput): Boolean;
var
  mWindows: TArray<TAtlasWindowInfo>;
begin
  Result := False;
  if not AInput.RaiseProgram or (AInput.ProcessId = 0) then
  begin
    Exit;
  end;
  // Neu suchen: Seit dem Öffnen des Dialogs kann das Programm ein Fenster bekommen haben.
  mWindows := TAtlasWindowCapture.WindowsOf(AInput.ProcessId);
  Result := (Length(mWindows) > 0) and TAtlasWindowCapture.BringToFront(mWindows[0].Handle);
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

function LogLineCount(const AParts: TAtlasAttachSourceParts): Integer;
begin
  Result := 0;
  if AParts.LogLines.Checked then
  begin
    Result := StrToIntDef(AParts.LogCount.Text, TAtlasAttachLog.cDefaultLines);
  end;
end;

/// <summary>Gewählte Logdatei anhängen; nicht lesbar (fehlt, gesperrt): nur der Hinweis, kein Dialog.</summary>
procedure AddLog(const AParts: TAtlasAttachSourceParts; var AFiles: TAtlasAttachFiles);
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
    AParts.LogInfo.Caption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachLogMissing, [ExtractFileName(mLog)]);
  end;
end;

function AddCheck(AOwner: TComponent; AParent: TWinControl; ATop: Integer; const ACaption: string;
  AClick: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(AOwner);
  Result.Parent := AParent;
  TAtlasControlScaling.Place(Result, cGap, ATop, cCheckWidth, cCheckHeight);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

/// <summary>Knopf in AParent; ABounds mit Bounds(Links, Oben, Breite, cButtonHeight) in logischen Pixeln.</summary>
function AddButton(AOwner: TComponent; AParent: TWinControl; const ABounds: TRect; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  TAtlasControlScaling.Place(Result, ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function AddInfo(AOwner: TComponent; AParent: TWinControl; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  TAtlasControlScaling.Place(Result, cInfoLeft, ATop, cInfoWidth, cInfoHeight);
  Result.Caption := '';
end;

{ TAtlasAttachSources }

constructor TAtlasAttachSources.Create(ADialog: TWinControl; const AInput: TAtlasAttachSourcesInput);
begin
  inherited Create;
  FDialog := ADialog;
  FInput := AInput;
  FPicker := TAtlasWindowPicker.Create;
  if FInput.FormImage <> nil then
  begin
    FImages.Form := TBitmap.Create;
    FImages.Form.Assign(FInput.FormImage);
  end;
  // Nicht festhalten: Der Aufrufer gibt das Bild frei.
  FInput.FormImage := nil;
end;

destructor TAtlasAttachSources.Destroy;
begin
  FPicker.Free;
  FImages.Shot.Free;
  FImages.Form.Free;
  FImages := Default(TAtlasAttachSourceImages);
  FWindows := nil;
  inherited;
end;

/// <summary>Bildschirmfoto: Fenster des Programms, per Klick, markieren.</summary>
procedure TAtlasAttachSources.AddScreenshotRows(AGroup: TWinControl; var ARow: Integer);
begin
  FParts.Screenshot := AddCheck(FDialog, AGroup, ARow, TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachScreenshot),
    Changed);
  FParts.Screenshot.Width := FParts.Screenshot.ScaleValue(cScreenshotWidth);
  FParts.WindowBox := TComboBox.Create(FDialog);
  FParts.WindowBox.Parent := AGroup;
  FParts.WindowBox.Style := csDropDownList;
  TAtlasControlScaling.Place(FParts.WindowBox, cWindowLeft, ARow - cBoxRaise, cWindowWidth, cBoxHeight);
  FParts.WindowBox.OnChange := WindowChanged;
  FParts.Pick := AddButton(FDialog, AGroup, Bounds(cPickLeft, ARow - cButtonRaise, cPickWidth, cButtonHeight),
    TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachWindowPick), PickClick);
  FParts.Pick.Hint := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachWindowPickHint);
  FParts.Pick.ShowHint := True;
  // Die VCL zeigt Hinweise auch über gesperrten Steuerelementen (TApplication.DoMouseIdle).
  FParts.WindowBox.ShowHint := True;
  FParts.ShotMarkup := AddButton(FDialog, AGroup, Bounds(cMarkupLeft, ARow - cButtonRaise, cMarkupWidth, cButtonHeight),
    TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachMarkup), MarkupClick);
  Inc(ARow, cRow);
  FParts.ShotInfo := AddInfo(FDialog, AGroup, ARow);
  Inc(ARow, cInfoRow);
end;

/// <summary>Formular im Designer.</summary>
procedure TAtlasAttachSources.AddFormRow(AGroup: TWinControl; var ARow: Integer);
var
  mCaption: string;
begin
  if FImages.Form <> nil then
  begin
    mCaption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachForm, [FInput.FormName]);
  end
  else
  begin
    mCaption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachNoForm);
  end;
  FParts.FormCheck := AddCheck(FDialog, AGroup, ARow, mCaption, Changed);
  FParts.FormCheck.Width := FParts.FormCheck.ScaleValue(cFormWidth);
  FParts.FormCheck.Enabled := FImages.Form <> nil;
  FParts.FormMarkup := AddButton(FDialog, AGroup, Bounds(cMarkupLeft, ARow - cButtonRaise, cMarkupWidth, cButtonHeight),
    TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachMarkup), MarkupClick);
  Inc(ARow, cFormRow);
end;

/// <summary>Logdatei mit Vorschlägen; nur die letzten N Zeilen.</summary>
procedure TAtlasAttachSources.AddLogRows(AGroup: TWinControl; var ARow: Integer);
begin
  FParts.Log := AddCheck(FDialog, AGroup, ARow, TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachLog), Changed);
  FParts.Log.Width := FParts.Log.ScaleValue(cLogWidth);
  FParts.LogBox := TComboBox.Create(FDialog);
  FParts.LogBox.Parent := AGroup;
  FParts.LogBox.Style := csDropDown;
  TAtlasControlScaling.Place(FParts.LogBox, cLogLeft, ARow - cBoxRaise, cLogBoxWidth, cBoxHeight);
  if Length(FInput.LogFiles) > 0 then
  begin
    FParts.LogBox.Text := FInput.LogFiles[0];
  end;
  FParts.LogBox.OnChange := LogChanged;
  FParts.LogBrowse := AddButton(FDialog, AGroup, Bounds(cBrowseLeft, ARow - cButtonRaise, cBrowseWidth, cButtonHeight),
    TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachLogBrowse), LogBrowseClick);
  FParts.LogLines := AddCheck(FDialog, AGroup, ARow, TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachLogLines),
    Changed);
  TAtlasControlScaling.Place(FParts.LogLines, cLinesLeft, ARow, cLinesWidth, cCheckHeight);
  FParts.LogLines.Checked := True;
  FParts.LogCount := TEdit.Create(FDialog);
  FParts.LogCount.Parent := AGroup;
  FParts.LogCount.NumbersOnly := True;
  TAtlasControlScaling.Place(FParts.LogCount, cCountLeft, ARow - cBoxRaise, cCountWidth, cBoxHeight);
  FParts.LogCount.Text := IntToStr(TAtlasAttachLog.cDefaultLines);
  FParts.LogCount.OnChange := Changed;
  Inc(ARow, cRow);
  FParts.LogInfo := AddInfo(FDialog, AGroup, ARow);
  Inc(ARow, cInfoRow);
end;

/// <summary>Debug-Notiz nur bei angehaltenem Programm, Exception-Verlauf nur mit Einträgen, Dateien eines
/// Absturzfalls (#1355) vorgewählt und nur gemeinsam abwählbar.</summary>
procedure TAtlasAttachSources.AddNoteRows(AGroup: TWinControl; var ARow: Integer);
var
  mCaption: string;
begin
  mCaption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachDebugNoteOff);
  if FInput.DebugNote <> '' then
  begin
    mCaption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachDebugNote);
  end;
  FParts.DebugNote := AddCheck(FDialog, AGroup, ARow, mCaption, Changed);
  FParts.DebugNote.Width := FParts.DebugNote.ScaleValue(cInfoWidth);
  FParts.DebugNote.Enabled := FInput.DebugNote <> '';
  Inc(ARow, cNoteRow);
  mCaption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachExceptionsNone);
  if FInput.ExceptionCount > 0 then
  begin
    mCaption := TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachExceptions, [FInput.ExceptionCount]);
  end;
  FParts.Exceptions := AddCheck(FDialog, AGroup, ARow, mCaption, Changed);
  FParts.Exceptions.Width := FParts.Exceptions.ScaleValue(cInfoWidth);
  FParts.Exceptions.Enabled := (FInput.ExceptionCount > 0) and (FInput.ExceptionsText <> '');
  Inc(ARow, cNoteRow);
  FParts.Extra := AddCheck(FDialog, AGroup, ARow,
    TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachCrashCase, [Length(FInput.Extra)]), Changed);
  FParts.Extra.Width := FParts.Extra.ScaleValue(cInfoWidth);
  FParts.Extra.Enabled := Length(FInput.Extra) > 0;
  FParts.Extra.Checked := FParts.Extra.Enabled;
end;

procedure TAtlasAttachSources.Build(var ATop: Integer);
var
  mGroup: TGroupBox;
  mRow: Integer;
begin
  mGroup := TGroupBox.Create(FDialog);
  mGroup.Parent := FDialog;
  mGroup.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachSources);
  TAtlasControlScaling.Place(mGroup, cGap, ATop, cGroupWidth, cGroupHeight);
  mGroup.Anchors := [akLeft, akTop, akRight];
  mRow := cFirstRow;
  AddScreenshotRows(mGroup, mRow);
  AddFormRow(mGroup, mRow);
  AddLogRows(mGroup, mRow);
  AddNoteRows(mGroup, mRow);
  Inc(ATop, cGroupHeight + cGap);
  // Fenster des Programms; das Hauptfenster zuerst. In die Liste erst mit Fenster (FillLists).
  if FInput.ProcessId <> 0 then
  begin
    FWindows := TAtlasWindowCapture.WindowsOf(FInput.ProcessId);
  end;
  FParts.WindowBox.Enabled := Length(FWindows) > 0;
  FParts.Pick.Enabled := True;
end;

function TAtlasAttachSources.FillLists: Boolean;
var
  mInfo: TAtlasWindowInfo;
  mText: string;
begin
  FParts.WindowBox.Items.BeginUpdate;
  try
    for mInfo in FWindows do
    begin
      FParts.WindowBox.Items.Add(mInfo.Caption);
    end;
    // Kurz in der Liste, die Erklärung als Hinweis: Die Liste ist schmal.
    if FInput.ProcessId = 0 then
    begin
      FParts.WindowBox.Items.Add(TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachNoProgram));
      FParts.WindowBox.Hint := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachNoProgramHint);
    end
    else if Length(FWindows) = 0 then
    begin
      FParts.WindowBox.Items.Add(TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachNoWindows));
      FParts.WindowBox.Hint := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachNoWindowsHint);
    end;
  finally
    FParts.WindowBox.Items.EndUpdate;
  end;
  FParts.WindowBox.ItemIndex := 0;
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
  Result := Length(FWindows) > 0;
  if Result then
  begin
    CaptureWindow(FWindows[0].Handle);
  end;
end;

procedure TAtlasAttachSources.UpdateState;
begin
  FParts.ShotMarkup.Enabled := FImages.Shot <> nil;
  FParts.Screenshot.Enabled := FImages.Shot <> nil;
  FParts.FormMarkup.Enabled := FImages.Form <> nil;
end;

/// <summary>Gewählte Bilder als PNG anhängen.</summary>
procedure TAtlasAttachSources.AddImages(var AFiles: TAtlasAttachFiles);
begin
  if FParts.Screenshot.Checked and (FImages.Shot <> nil) then
  begin
    AFiles := AFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Screenshot,
      TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachScreenshotName) + '.png',
      ImagePng(FImages.Shot, FInput.MaxImageWidth, FImages.ShotPng))];
  end;
  if FParts.FormCheck.Checked and (FImages.Form <> nil) then
  begin
    AFiles := AFiles + [TAtlasAttachFile.CreateImage(TAtlasAttachKind.Form,
      TAtlasAttachStrings.Fmt(TAtlasAttachTextId.AttachFormName, [FInput.FormName]) + '.png',
      ImagePng(FImages.Form, FInput.MaxImageWidth, FImages.FormPng))];
  end;
end;

/// <summary>Debug-Notiz, Exception-Verlauf und Dateien des Absturzfalls anhängen.</summary>
procedure TAtlasAttachSources.AddNotes(var AFiles: TAtlasAttachFiles);
var
  mFile: TAtlasAttachFile;
begin
  if FParts.DebugNote.Checked and (FInput.DebugNote <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.DebugNote, FInput.DebugNoteName, FInput.DebugNote);
    mFile.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachDebugNoteCaption);
    AFiles := AFiles + [mFile];
  end;
  if FParts.Exceptions.Checked and (FInput.ExceptionsText <> '') then
  begin
    mFile := TAtlasAttachFile.CreateText(TAtlasAttachKind.Exceptions,
      TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachExceptionsName), FInput.ExceptionsText);
    mFile.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachExceptionsCaption);
    AFiles := AFiles + [mFile];
  end;
  if FParts.Extra.Checked then
  begin
    AFiles := AFiles + FInput.Extra;
  end;
end;

procedure TAtlasAttachSources.Collect(var AFiles: TAtlasAttachFiles);
begin
  AddImages(AFiles);
  AddLog(FParts, AFiles);
  AddNotes(AFiles);
end;

procedure TAtlasAttachSources.Changed(Sender: TObject);
begin
  if not FUpdating and Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

procedure TAtlasAttachSources.LogChanged(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  // Pfad eingetragen oder gewählt: Logdatei anhängen. Checked löst über OnClick schon Changed aus.
  if (Trim(FParts.LogBox.Text) <> '') and not FParts.Log.Checked then
  begin
    FParts.Log.Checked := True;
    Exit;
  end;
  Changed(Sender);
end;

procedure TAtlasAttachSources.WindowChanged(Sender: TObject);
begin
  if (FParts.WindowBox.ItemIndex >= 0) and (FParts.WindowBox.ItemIndex < Length(FWindows)) then
  begin
    CaptureWindow(FWindows[FParts.WindowBox.ItemIndex].Handle);
  end;
end;

procedure TAtlasAttachSources.PickClick(Sender: TObject);
begin
  FParts.ShotInfo.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachWindowPicking);
  FParts.Pick.Enabled := False;
  FRaised := RaiseProgram(FInput);
  FPicker.Start(Picked);
end;

procedure TAtlasAttachSources.Picked(AWindow: HWND);
begin
  FParts.Pick.Enabled := True;
  // Das Programm liegt über dem Dialog: ihn nach dem Bild wieder nach vorn holen.
  try
    PickedWindow(AWindow);
  finally
    if FRaised and FDialog.HandleAllocated then
    begin
      SetWindowPos(FDialog.Handle, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
    end;
    FRaised := False;
  end;
end;

procedure TAtlasAttachSources.PickedWindow(AWindow: HWND);
begin
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

procedure TAtlasAttachSources.MarkupClick(Sender: TObject);
begin
  if Sender = FParts.ShotMarkup then
  begin
    if (FImages.Shot <> nil) and TAtlasImageMarkupForm.Execute(FImages.Shot) then
    begin
      FImages.ShotPng := nil;
      Changed(Sender);
    end;
  end
  else if (FImages.Form <> nil) and TAtlasImageMarkupForm.Execute(FImages.Form) then
  begin
    FImages.FormPng := nil;
    FParts.FormCheck.Checked := True;
    Changed(Sender);
  end;
end;

procedure TAtlasAttachSources.LogBrowseClick(Sender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(FDialog);
  try
    mDialog.Filter := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachLogFilter);
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
    Changed(Sender);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasAttachSources.CaptureWindow(AWindow: HWND);
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

procedure TAtlasAttachSources.SetScreenshot(ABitmap: TBitmap);
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
    FParts.ShotInfo.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachCaptureFailed);
  end;
  FUpdating := True;
  try
    FParts.Screenshot.Checked := FImages.Shot <> nil;
  finally
    FUpdating := False;
  end;
  Changed(Self);
end;

procedure TAtlasAttachSources.Cancel;
begin
  FPicker.Cancel;
end;

end.
