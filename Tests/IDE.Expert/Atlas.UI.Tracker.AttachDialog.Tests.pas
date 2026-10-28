unit Atlas.UI.Tracker.AttachDialog.Tests;

// Dialog „An Issue anhängen“ (#1276) ohne IDE: Quellen ohne Daten sind
// gesperrt, die Liste zeigt genau die Dateien (Namen eindeutig, Größe), die
// auch im Ordner des Laufs liegen; Bilder werden auf die Höchstbreite
// verkleinert; Logdatei mit „nur die letzten Zeilen“; „Senden“ nur mit
// gültiger Kennung und Inhalt.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasAttachDialogTests = class
  private
    FLanguage: TAtlasLanguage;
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SourcesWithoutDataAreDisabled;
    [Test]
    procedure DebugNoteAndExceptionsAreListed;
    /// <summary>Abnahme: Formular und Bildschirmfoto in einem Schritt, verkleinert auf maxImageWidth.</summary>
    [Test]
    procedure ImagesScaledWithUniqueNames;
    /// <summary>Abnahme: Logdatei mit den letzten 200 Zeilen.</summary>
    [Test]
    procedure LogFileLastLines;
    [Test]
    procedure MissingLogShowsHint;
    [Test]
    procedure SendNeedsKeyAndContent;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Tracker.Attach,
  Atlas.UI.Tracker.Capture,
  Atlas.UI.Tracker.AttachDialog;

function Input: TAtlasAttachDialogInput;
begin
  Result := TAtlasAttachDialogInput.Empty;
  Result.Tracker := 'YouTrack';
  Result.CanUpload := True;
  Result.Key := 'ATL-7';
  Result.KeyOf :=
    function(AInput: string): string
    begin
      Result := '';
      if (Pos('-', AInput) > 1) and (Pos(' ', AInput) = 0) then
        Result := UpperCase(AInput);
    end;
end;

function Bitmap(AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := clSilver;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

function ImageWidth(const AFile: TAtlasAttachFile): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TAtlasAttachImages.FromPng(AFile.Data);
  try
    Result := mBitmap.Width;
  finally
    mBitmap.Free;
  end;
end;

{ TAtlasAttachDialogTests }

procedure TAtlasAttachDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasAttachDialogTests-' + TGUID.NewGuid.ToString);
end;

procedure TAtlasAttachDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  FDir := '';
end;

procedure TAtlasAttachDialogTests.SourcesWithoutDataAreDisabled;
var
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
begin
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, Input, mTemp);
    try
      mDialog.HandleNeeded;
      Assert.IsFalse(mDialog.ScreenshotCheck.Enabled, 'kein Programm');
      Assert.IsFalse(mDialog.WindowBox.Enabled);
      Assert.IsFalse(mDialog.FormCheck.Enabled, 'kein Formular');
      Assert.IsFalse(mDialog.DebugNoteCheck.Enabled, 'nicht angehalten');
      Assert.IsFalse(mDialog.ExceptionsCheck.Enabled, 'leerer Verlauf');
      Assert.AreEqual(0, mDialog.FileList.Items.Count);
      Assert.IsFalse(mDialog.SendButton.Enabled, 'nichts zu senden');
      Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.AttachUploadHint, ['YouTrack']), mDialog.HintLabel.Caption);
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
  end;
end;

procedure TAtlasAttachDialogTests.DebugNoteAndExceptionsAreListed;
var
  mInput: TAtlasAttachDialogInput;
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
  mFiles: TAtlasAttachFiles;
begin
  mInput := Input;
  mInput.CanUpload := False;
  mInput.Tracker := 'GitHub';
  mInput.DebugNote := '# Debug-Notiz' + #13#10;
  mInput.DebugNoteName := 'debug-notiz-2026-10-28-1405.md';
  mInput.ExceptionsText := 'EConvertError: x' + #13#10;
  mInput.ExceptionCount := 3;
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, mTemp);
    try
      mDialog.HandleNeeded;
      Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.AttachFallbackHint, ['GitHub']), mDialog.HintLabel.Caption);
      Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.AttachExceptions, [3]), mDialog.ExceptionsCheck.Caption);
      mDialog.DebugNoteCheck.Checked := True;
      mDialog.ExceptionsCheck.Checked := True;
      mFiles := mDialog.Files;
      Assert.AreEqual(2, Integer(Length(mFiles)));
      Assert.AreEqual('debug-notiz-2026-10-28-1405.md', mFiles[0].Name);
      Assert.IsTrue(mFiles[0].IsMarkdown);
      Assert.AreEqual('exception-verlauf.txt', mFiles[1].Name);
      Assert.AreEqual(2, mDialog.FileList.Items.Count);
      Assert.AreEqual('Debug-Notiz', mDialog.FileList.Items[0].Caption);
      Assert.AreEqual(TAtlasAttachDialog.SizeText(mFiles[1].Size), mDialog.FileList.Items[1].SubItems[0]);
      // Der Ordner des Laufs enthält genau diese Dateien.
      Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(mTemp.Folder))));
      mDialog.DebugNoteCheck.Checked := False;
      Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(mTemp.Folder))));
      Assert.IsTrue(mDialog.CanSend);
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
  end;
  mFiles := nil;
end;

procedure TAtlasAttachDialogTests.ImagesScaledWithUniqueNames;
var
  mInput: TAtlasAttachDialogInput;
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
  mForm, mShot: TBitmap;
  mFiles: TAtlasAttachFiles;
begin
  mForm := Bitmap(1000, 500);
  mShot := Bitmap(640, 100);
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mInput := Input;
    mInput.FormImage := mForm;
    mInput.FormName := 'Form1';
    mInput.MaxImageWidth := 500;
    mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, mTemp);
    try
      mDialog.HandleNeeded;
      Assert.IsTrue(mDialog.FormCheck.Enabled);
      Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.AttachForm, ['Form1']), mDialog.FormCheck.Caption);
      mDialog.SetScreenshot(mShot);
      Assert.IsTrue(mDialog.ScreenshotCheck.Checked, 'aufgenommen = angehakt');
      mDialog.FormCheck.Checked := True;
      mFiles := mDialog.Files;
      Assert.AreEqual(2, Integer(Length(mFiles)));
      Assert.AreEqual('bildschirmfoto.png', mFiles[0].Name);
      Assert.AreEqual('formular-Form1.png', mFiles[1].Name);
      Assert.IsTrue(mFiles[0].IsImage);
      Assert.AreEqual(500, ImageWidth(mFiles[0]), 'verkleinert');
      Assert.AreEqual(500, ImageWidth(mFiles[1]));
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
    mForm.Free;
    mShot.Free;
  end;
  mFiles := nil;
end;

procedure TAtlasAttachDialogTests.LogFileLastLines;
var
  mInput: TAtlasAttachDialogInput;
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
  mLines: TStringList;
  mLog: string;
  mIndex: Integer;
  mFiles: TAtlasAttachFiles;
begin
  TDirectory.CreateDirectory(FDir);
  mLog := TPath.Combine(FDir, 'app.log');
  mLines := TStringList.Create;
  try
    for mIndex := 1 to 300 do
      mLines.Add('Zeile ' + IntToStr(mIndex));
    mLines.SaveToFile(mLog, TEncoding.UTF8);
  finally
    mLines.Free;
  end;
  mInput := Input;
  mInput.LogFiles := TArray<string>.Create(mLog);
  mTemp := TAtlasAttachTemp.Create(TPath.Combine(FDir, 'runs'));
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, mTemp);
    try
      mDialog.HandleNeeded;
      Assert.AreEqual(mLog, mDialog.LogBox.Text);
      Assert.AreEqual('200', mDialog.LogCountEdit.Text);
      mDialog.LogCheck.Checked := True;
      mFiles := mDialog.Files;
      Assert.AreEqual(1, Integer(Length(mFiles)));
      Assert.AreEqual('app.log', mFiles[0].Name);
      Assert.AreEqual('app.log (letzte 200 Zeilen)', mFiles[0].DisplayName);
      Assert.IsTrue(mFiles[0].Text.StartsWith('Zeile 101'#13#10), mFiles[0].Text);
      Assert.IsTrue(mFiles[0].Text.EndsWith('Zeile 300'), mFiles[0].Text);
      mDialog.LogLinesCheck.Checked := False;
      mFiles := mDialog.Files;
      Assert.IsTrue(mFiles[0].Text.StartsWith('Zeile 1'#13#10), 'ganze Datei');
      Assert.AreEqual('app.log', mFiles[0].DisplayName);
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
  end;
  mFiles := nil;
end;

procedure TAtlasAttachDialogTests.MissingLogShowsHint;
var
  mInput: TAtlasAttachDialogInput;
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
begin
  mInput := Input;
  mInput.LogFiles := TArray<string>.Create(TPath.Combine(FDir, 'fehlt.log'));
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, mTemp);
    try
      mDialog.HandleNeeded;
      mDialog.LogCheck.Checked := True;
      Assert.AreEqual(0, Integer(Length(mDialog.Files)));
      Assert.IsFalse(mDialog.SendButton.Enabled);
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
  end;
end;

procedure TAtlasAttachDialogTests.SendNeedsKeyAndContent;
var
  mTemp: TAtlasAttachTemp;
  mDialog: TAtlasAttachDialog;
  mInput: TAtlasAttachDialogInput;
begin
  mInput := Input;
  mInput.Issues := TArray<string>.Create('ATL-1 Erstes Issue', 'ATL-2 Zweites Issue');
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mDialog := TAtlasAttachDialog.CreateFor(nil, mInput, mTemp);
    try
      mDialog.HandleNeeded;
      Assert.AreEqual(2, mDialog.IssueBox.Items.Count);
      Assert.AreEqual('ATL-7', mDialog.Key, 'vorgewählt');
      mDialog.IssueBox.Text := 'ATL-2 Zweites Issue';
      Assert.AreEqual('ATL-2', mDialog.Key, 'nur die Kennung');
      mDialog.CommentCheck.Checked := True;
      Assert.IsFalse(mDialog.CanSend, 'leerer Kommentar');
      mDialog.CommentMemo.Lines.Text := 'Siehe Anhang';
      Assert.IsTrue(mDialog.CanSend);
      Assert.AreEqual('Siehe Anhang', mDialog.CommentText);
      Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.AttachCommentOnly), mDialog.FileList.Items[0].Caption);
      mDialog.IssueBox.Text := 'kaputt';
      Assert.AreEqual('', mDialog.Key);
      Assert.IsFalse(mDialog.CanSend, 'ungültige Kennung');
      mDialog.CommentCheck.Checked := False;
      Assert.AreEqual('', mDialog.CommentText, 'Haken aus = kein Kommentar');
    finally
      mDialog.Free;
    end;
  finally
    mTemp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAttachDialogTests);

end.
