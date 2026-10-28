unit Atlas.Core.Tracker.Attach.Tests;

// „An Issue anhängen“ (#1276) ohne IDE und ohne Netz: Aufbau der
// Multipart-Anfrage, eindeutige und sichere Dateinamen, Ende einer
// Protokolldatei (letzte N Zeilen, angeschnittene erste Zeile, Kodierung),
// Platzhalter und Masken in issues.attach.logFiles, Verkleinern auf
// issues.attach.maxImageWidth, Kommentartexte für YouTrack und GitHub, Senden
// über eine Fake-Transport-Schicht (YouTrack lädt hoch, GitHub fällt zurück)
// und der Ordner für temporäre Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAttachTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: Aufbau der Multipart-Anfrage.</summary>
    [Test]
    procedure MultipartLayout;
    [Test]
    procedure MultipartKeepsBinaryData;
    [Test]
    procedure SafeAndUniqueNames;
    /// <summary>Abnahme: Kürzen der Protokolldatei (letzte 200 Zeilen).</summary>
    [Test]
    procedure LastLinesOfLog;
    [Test]
    procedure ReadTailCutsPartialFirstLine;
    [Test]
    procedure DecodeUtf8AndAnsi;
    /// <summary>Abnahme: Platzhalter in logFiles.</summary>
    [Test]
    procedure ExpandPlaceholders;
    [Test]
    procedure CandidatesResolveMasksAndRelativePaths;
    /// <summary>Abnahme: Verkleinern auf maxImageWidth.</summary>
    [Test]
    procedure ScaledSizeKeepsAspect;
    [Test]
    procedure CommentReferencesAttachments;
    [Test]
    procedure CommentWithTextsAsCodeBlocks;
    [Test]
    procedure CommentWithTextsKeepsLogTail;
    [Test]
    procedure JsonBodyEscapes;
    /// <summary>Abnahme: PNG und Kommentar am YouTrack-Issue.</summary>
    [Test]
    procedure YouTrackUploadsThenComments;
    [Test]
    procedure YouTrackUploadRejected;
    /// <summary>Abnahme: GitHub-Rückfall gegen eine Fake-Transport-Schicht.</summary>
    [Test]
    procedure GitHubFallsBackToCommentAndClipboard;
    [Test]
    procedure GitHubOnlyImageSendsNothing;
    [Test]
    procedure TransportWithoutSendIsNotConfigured;
    /// <summary>Abnahme: temporäre Dateien sind nach dem Senden oder Abbrechen gelöscht.</summary>
    [Test]
    procedure TempFolderIsDeleted;
    [Test]
    procedure PruneStaleRemovesOldRuns;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Attach,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack;

type
  /// <summary>Transport mit festen Antworten auf POST; merkt sich Adressen, Inhaltstypen und Rümpfe.</summary>
  TFakeSend = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiPost)
  private
    FStatus: TArray<Integer>;
  public
    Urls: TArray<string>;
    ContentTypes: TArray<string>;
    Bodies: TArray<string>;
    /// <summary>Status der Antworten der Reihe nach; danach 200.</summary>
    procedure Answer(const AStatus: array of Integer);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer; out AStatus: Integer;
      out AText: string; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Transport nur zum Lesen (wie vor #1276).</summary>
  TFakeGetOnly = class(TInterfacedObject, IAtlasCiTransport)
  public
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TFakeSend.Answer(const AStatus: array of Integer);
var
  mIndex: Integer;
begin
  SetLength(FStatus, Length(AStatus));
  for mIndex := 0 to High(AStatus) do
    FStatus[mIndex] := AStatus[mIndex];
end;

function TFakeSend.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AStatus := 404;
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TFakeSend.Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer;
  out AStatus: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Length(Urls);
  Urls := Urls + [AUrl];
  ContentTypes := ContentTypes + [AContentType];
  Bodies := Bodies + [TEncoding.UTF8.GetString(ABody)];
  AStatus := 200;
  if mIndex < Length(FStatus) then
    AStatus := FStatus[mIndex];
  AText := '{}';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TFakeGetOnly.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AStatus := 404;
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function Png(const AName: string): TAtlasAttachFile;
begin
  Result := TAtlasAttachFile.CreateImage(TAtlasAttachKind.Screenshot, AName, TBytes.Create($89, $50, $4E, $47));
end;

function Log(const AName, AText: string): TAtlasAttachFile;
begin
  Result := TAtlasAttachFile.CreateText(TAtlasAttachKind.LogFile, AName, AText);
end;

function NumberedLines(AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
    Result := Result + 'Zeile ' + IntToStr(mIndex) + #13#10;
end;

{ TAtlasAttachTests }

procedure TAtlasAttachTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasAttachTests-' + IntToStr(Random(MaxInt)));
  ForceDirectories(FDir);
end;

procedure TAtlasAttachTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  FDir := '';
end;

procedure TAtlasAttachTests.MultipartLayout;
var
  mFiles: TAtlasAttachFiles;
  mBody: string;
begin
  mFiles := [Log('app.log', 'a'#13#10'b'), TAtlasAttachFile.CreateText(TAtlasAttachKind.DebugNote, 'notiz.md', '# N')];
  mBody := TEncoding.UTF8.GetString(TAtlasAttachMultipart.Build('XYZ', mFiles));
  Assert.AreEqual(
    '--XYZ'#13#10 +
    'Content-Disposition: form-data; name="upload"; filename="app.log"'#13#10 +
    'Content-Type: text/plain; charset=utf-8'#13#10#13#10 +
    'a'#13#10'b'#13#10 +
    '--XYZ'#13#10 +
    'Content-Disposition: form-data; name="upload"; filename="notiz.md"'#13#10 +
    'Content-Type: text/markdown; charset=utf-8'#13#10#13#10 +
    '# N'#13#10 +
    '--XYZ--'#13#10, mBody);
  Assert.AreEqual('multipart/form-data; boundary=XYZ', TAtlasAttachMultipart.ContentType('XYZ'));
  // Jede Grenze ist neu.
  Assert.AreNotEqual(TAtlasAttachMultipart.NewBoundary, TAtlasAttachMultipart.NewBoundary);
end;

procedure TAtlasAttachTests.MultipartKeepsBinaryData;
var
  mBytes: TBytes;
  mHeader: TBytes;
  mFile: TAtlasAttachFile;
begin
  mFile := TAtlasAttachFile.CreateImage(TAtlasAttachKind.Form, 'f.png', TBytes.Create(0, 255, 13, 10, 0));
  mBytes := TAtlasAttachMultipart.Build('B', [mFile]);
  mHeader := TEncoding.UTF8.GetBytes('--B'#13#10'Content-Disposition: form-data; name="upload"; filename="f.png"' +
    #13#10'Content-Type: image/png'#13#10#13#10);
  Assert.AreEqual(Integer(Length(mHeader) + 5 + 2 + Length('--B--'#13#10)), Integer(Length(mBytes)));
  Assert.AreEqual(0, Integer(mBytes[Length(mHeader)]));
  Assert.AreEqual(255, Integer(mBytes[Length(mHeader) + 1]));
  Assert.AreEqual(0, Integer(mBytes[Length(mHeader) + 4]));
  Assert.AreEqual(Int64(5), mFile.Size);
  Assert.IsTrue(mFile.IsImage);
end;

procedure TAtlasAttachTests.SafeAndUniqueNames;
var
  mFiles: TAtlasAttachFiles;
begin
  Assert.AreEqual('app.log', TAtlasAttachFile.SafeName('C:\Logs\app.log'));
  Assert.AreEqual('mein-log_1_.txt', TAtlasAttachFile.SafeName('mein log(1).txt'));
  Assert.AreEqual('a_b.png', TAtlasAttachFile.SafeName('a"b.png'));
  mFiles := TAtlasAttachFile.UniqueNames([Png('bild.png'), Png('Bild.png'), Log('bild.png', 'x'), Log('x.log', '')]);
  Assert.AreEqual('bild.png', mFiles[0].Name);
  Assert.AreEqual('Bild-2.png', mFiles[1].Name);
  Assert.AreEqual('bild-3.png', mFiles[2].Name);
  Assert.AreEqual('x.log', mFiles[3].Name);
end;

procedure TAtlasAttachTests.LastLinesOfLog;
var
  mText: string;
begin
  mText := TAtlasAttachLog.LastLines(NumberedLines(1, 500), TAtlasAttachLog.DefaultLines);
  Assert.AreEqual(NumberedLines(301, 500).TrimRight, mText);
  // Weniger Zeilen als verlangt, ohne Umbruch am Ende, 0 = alle.
  Assert.AreEqual('a'#13#10'b', TAtlasAttachLog.LastLines('a'#10'b', 200));
  Assert.AreEqual(NumberedLines(1, 3).TrimRight, TAtlasAttachLog.LastLines(NumberedLines(1, 3), 0));
  Assert.AreEqual('', TAtlasAttachLog.LastLines('', 10));
end;

procedure TAtlasAttachTests.ReadTailCutsPartialFirstLine;
var
  mFileName, mText: string;
  mBytes: TBytes;
begin
  mFileName := TPath.Combine(FDir, 'app.log');
  TFile.WriteAllText(mFileName, NumberedLines(1, 100), TEncoding.ASCII);
  // Alles lesen: letzte 10 Zeilen.
  Assert.AreEqual(NumberedLines(91, 100).TrimRight, TAtlasAttachLog.ReadTail(mFileName, 10, 0));
  // Nur 30 Bytes von hinten: die angeschnittene Zeile entfällt.
  mBytes := TFile.ReadAllBytes(mFileName);
  mText := TAtlasAttachLog.ReadTail(mFileName, 0, 30);
  Assert.AreEqual('Zeile 99'#13#10'Zeile 100', mText);
  Assert.IsTrue(Length(mBytes) > 30);
end;

procedure TAtlasAttachTests.DecodeUtf8AndAnsi;
begin
  Assert.AreEqual('Größe', TAtlasAttachLog.Decode(TEncoding.UTF8.GetBytes('Größe')));
  // Windows-1252: ö = $F6, ß = $DF.
  Assert.AreEqual('Größe', TAtlasAttachLog.Decode(TBytes.Create(Ord('G'), Ord('r'), $F6, $DF, Ord('e'))));
  // BOM entfällt.
  Assert.AreEqual('x', TAtlasAttachLog.Decode(TBytes.Create($EF, $BB, $BF, Ord('x'))));
end;

procedure TAtlasAttachTests.ExpandPlaceholders;
var
  mProject: string;
begin
  mProject := TPath.Combine(TPath.Combine(FDir, 'Kasse'), 'Kasse.dproj');
  Assert.AreEqual(TPath.Combine(FDir, 'Kasse') + PathDelim + 'logs' + PathDelim + 'Kasse.log',
    TAtlasAttachLog.Expand('$(ProjectDir)' + PathDelim + 'logs' + PathDelim + '$(ProjectName).log', mProject));
  Assert.AreEqual(TPath.Combine(FDir, 'Kasse'), TAtlasAttachLog.Expand('$(projectdir)', mProject));
  // Umgebungsvariablen; unbekannte und unvollständige bleiben stehen.
  Assert.AreEqual(GetEnvironmentVariable('PATH'), TAtlasAttachLog.Expand('$(PATH)', mProject));
  Assert.AreEqual('$(GibtEsNichtAtlas1276)\a', TAtlasAttachLog.Expand('$(GibtEsNichtAtlas1276)\a', mProject));
  Assert.AreEqual('$(ProjectDir', TAtlasAttachLog.Expand('$(ProjectDir', mProject));
end;

procedure TAtlasAttachTests.CandidatesResolveMasksAndRelativePaths;
var
  mProject, mLogs, mOld, mNew, mFixed: string;
  mList: TArray<string>;
begin
  mProject := TPath.Combine(FDir, 'Kasse.dproj');
  mLogs := TPath.Combine(FDir, 'logs');
  ForceDirectories(mLogs);
  mOld := TPath.Combine(mLogs, 'app-1.log');
  mNew := TPath.Combine(mLogs, 'app-2.log');
  mFixed := TPath.Combine(FDir, 'fest.txt');
  TFile.WriteAllText(mOld, 'alt');
  TFile.WriteAllText(mNew, 'neu');
  TFile.WriteAllText(mFixed, 'fest');
  TFile.SetLastWriteTime(mOld, Now - 1);
  TFile.SetLastWriteTime(mNew, Now);
  mList := TAtlasAttachLog.Candidates('$(ProjectDir)' + PathDelim + 'logs' + PathDelim + 'app-*.log; fest.txt' +
    #13#10'fehlt.log;;' + mFixed, mProject);
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual(mNew, mList[0], 'Maske: neueste Datei');
  Assert.AreEqual(mFixed, mList[1], 'relativ zum Projekt, doppelt nur einmal, fehlende entfallen');
  Assert.AreEqual(0, Integer(Length(TAtlasAttachLog.Candidates('', mProject))));
end;

procedure TAtlasAttachTests.ScaledSizeKeepsAspect;
var
  mWidth, mHeight: Integer;
begin
  Assert.IsTrue(TAtlasAttachImage.ScaledSize(3840, 2160, 1920, mWidth, mHeight));
  Assert.AreEqual(1920, mWidth);
  Assert.AreEqual(1080, mHeight);
  Assert.IsFalse(TAtlasAttachImage.ScaledSize(1280, 720, 1920, mWidth, mHeight));
  Assert.AreEqual(1280, mWidth);
  Assert.AreEqual(720, mHeight);
  // Grenzen: unter MinWidth gilt MinWidth.
  Assert.IsTrue(TAtlasAttachImage.ScaledSize(1000, 500, 10, mWidth, mHeight));
  Assert.AreEqual(TAtlasAttachImage.MinWidth, mWidth);
  Assert.AreEqual(160, mHeight);
end;

procedure TAtlasAttachTests.CommentReferencesAttachments;
var
  mFile: TAtlasAttachFile;
begin
  mFile := Log('app.log', 'x');
  mFile.Caption := 'app.log (letzte 200 Zeilen)';
  Assert.AreEqual('Absturz beim Speichern.'#13#10#13#10'![](bild.png)'#13#10'[app.log (letzte 200 Zeilen)](app.log)',
    TAtlasAttachComment.Referencing('  Absturz beim Speichern. ', [Png('bild.png'), mFile]));
  Assert.AreEqual('![](bild.png)', TAtlasAttachComment.Referencing('', [Png('bild.png')]));
end;

procedure TAtlasAttachTests.CommentWithTextsAsCodeBlocks;
var
  mText: string;
  mNote: TAtlasAttachFile;
begin
  mNote := TAtlasAttachFile.CreateText(TAtlasAttachKind.DebugNote, 'notiz.md', '# Debug-Notiz'#13#10'- Ort');
  mText := TAtlasAttachComment.WithTexts('Siehe unten.', [Png('bild.png'), Log('app.log', 'a'#13#10'```b'),
    mNote], TAtlasAttachComment.MaxTextsLength);
  Assert.AreEqual('Siehe unten.'#13#10#13#10 +
    '**app.log**'#13#10#13#10'```text'#13#10'a'#13#10'` ` `b'#13#10'```'#13#10#13#10 +
    '**notiz.md**'#13#10#13#10'# Debug-Notiz'#13#10'- Ort', mText);
  Assert.DoesNotContain(mText, 'bild.png');
end;

procedure TAtlasAttachTests.CommentWithTextsKeepsLogTail;
var
  mText: string;
begin
  mText := TAtlasAttachComment.WithTexts('', [Log('app.log', NumberedLines(1, 5000))], 2000);
  Assert.IsTrue(Length(mText) < 2200, IntToStr(Length(mText)));
  Assert.Contains(mText, 'Zeile 5000');
  Assert.DoesNotContain(mText, 'Zeile 1'#13#10);
  Assert.Contains(mText, '```text'#13#10'…'#13#10'Zeile ');
end;

procedure TAtlasAttachTests.JsonBodyEscapes;
begin
  Assert.AreEqual('{"text":"a\"b\\c\nd"}', TEncoding.UTF8.GetString(TAtlasAttachComment.JsonBody('text',
    'a"b\c'#10'd')));
end;

procedure TAtlasAttachTests.YouTrackUploadsThenComments;
var
  mSend: TFakeSend;
  mTransport: IAtlasCiTransport;
  mRequest: TAtlasAttachRequest;
  mOutcome: TAtlasAttachOutcome;
begin
  mSend := TFakeSend.Create;
  mTransport := mSend;
  mRequest := Default(TAtlasAttachRequest);
  mRequest.Target := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud', 'ATL', '');
  mRequest.Key := 'ATL-123';
  mRequest.Files := [Png('bildschirmfoto.png'), Log('app.log', 'Zeile')];
  mRequest.Comment := 'Fehlerbild';
  mRequest.WithComment := True;
  mOutcome := TAtlasAttachSender.Send(TAtlasYouTrackTracker.Create, mTransport, mRequest, 1000);
  Assert.IsTrue(mOutcome.Succeeded);
  Assert.IsFalse(mOutcome.Fallback);
  Assert.AreEqual(2, mOutcome.Uploaded);
  Assert.IsTrue(mOutcome.Commented);
  Assert.AreEqual(2, Integer(Length(mSend.Urls)));
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues/ATL-123/attachments?fields=id,name', mSend.Urls[0]);
  Assert.IsTrue(mSend.ContentTypes[0].StartsWith('multipart/form-data; boundary='), mSend.ContentTypes[0]);
  Assert.Contains(mSend.Bodies[0], 'filename="bildschirmfoto.png"');
  Assert.Contains(mSend.Bodies[0], 'filename="app.log"');
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues/ATL-123/comments?fields=id', mSend.Urls[1]);
  Assert.AreEqual('application/json', mSend.ContentTypes[1]);
  Assert.AreEqual('{"text":"Fehlerbild\r\n\r\n![](bildschirmfoto.png)\r\n[app.log](app.log)"}', mSend.Bodies[1]);
  mRequest.Files := nil;
end;

procedure TAtlasAttachTests.YouTrackUploadRejected;
var
  mSend: TFakeSend;
  mTransport: IAtlasCiTransport;
  mRequest: TAtlasAttachRequest;
  mOutcome: TAtlasAttachOutcome;
begin
  mSend := TFakeSend.Create;
  mTransport := mSend;
  mSend.Answer([403]);
  mRequest := Default(TAtlasAttachRequest);
  mRequest.Target := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud', 'ATL', '');
  mRequest.Key := 'ATL-123';
  mRequest.Files := [Png('a.png')];
  mRequest.WithComment := True;
  mOutcome := TAtlasAttachSender.Send(TAtlasYouTrackTracker.Create, mTransport, mRequest, 1000);
  Assert.IsFalse(mOutcome.Succeeded);
  Assert.AreEqual(TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.Unauthorized), TAtlasCiBuild.ErrorKey(mOutcome.Error));
  Assert.AreEqual(1, Integer(Length(mSend.Urls)), 'kein Kommentar nach abgelehntem Hochladen');
  // Ungültige Kennung: nichts geht ins Netz.
  mRequest.Key := 'ATL 1/../x';
  mOutcome := TAtlasAttachSender.Send(TAtlasYouTrackTracker.Create, mTransport, mRequest, 1000);
  Assert.AreEqual(TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.NotConfigured), TAtlasCiBuild.ErrorKey(mOutcome.Error));
  Assert.AreEqual(1, Integer(Length(mSend.Urls)));
  mRequest.Files := nil;
end;

procedure TAtlasAttachTests.GitHubFallsBackToCommentAndClipboard;
var
  mSend: TFakeSend;
  mTransport: IAtlasCiTransport;
  mRequest: TAtlasAttachRequest;
  mOutcome: TAtlasAttachOutcome;
begin
  mSend := TFakeSend.Create;
  mTransport := mSend;
  mSend.Answer([201]);
  mRequest := Default(TAtlasAttachRequest);
  mRequest.Target := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
  mRequest.Key := '#12';
  mRequest.Files := [Png('bildschirmfoto.png'), Log('app.log', 'Fehler 42')];
  mRequest.Comment := 'Absturz';
  mRequest.WithComment := True;
  mOutcome := TAtlasAttachSender.Send(TAtlasGitHubTracker.Create, mTransport, mRequest, 1000);
  Assert.IsTrue(mOutcome.Succeeded);
  Assert.IsTrue(mOutcome.Fallback);
  Assert.AreEqual(0, mOutcome.Uploaded);
  Assert.IsTrue(mOutcome.Commented);
  Assert.AreEqual(1, Integer(Length(mSend.Urls)), 'nur der Kommentar, kein Hochladen');
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/issues/12/comments', mSend.Urls[0]);
  Assert.AreEqual('{"body":"Absturz\r\n\r\n**app.log**\r\n\r\n```text\r\nFehler 42\r\n```"}', mSend.Bodies[0]);
  Assert.AreEqual(1, Integer(Length(mOutcome.Images)));
  Assert.AreEqual('bildschirmfoto.png', mOutcome.Images[0].Name);
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/12', mOutcome.Page);
  mRequest.Files := nil;
  mOutcome.Images := nil;
end;

procedure TAtlasAttachTests.GitHubOnlyImageSendsNothing;
var
  mSend: TFakeSend;
  mTransport: IAtlasCiTransport;
  mRequest: TAtlasAttachRequest;
  mOutcome: TAtlasAttachOutcome;
begin
  mSend := TFakeSend.Create;
  mTransport := mSend;
  mRequest := Default(TAtlasAttachRequest);
  mRequest.Target := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
  mRequest.Key := '#12';
  mRequest.Files := [Png('formular.png')];
  mRequest.WithComment := True;
  mOutcome := TAtlasAttachSender.Send(TAtlasGitHubTracker.Create, mTransport, mRequest, 1000);
  Assert.IsTrue(mOutcome.Succeeded);
  Assert.IsTrue(mOutcome.Fallback);
  Assert.IsFalse(mOutcome.Commented);
  Assert.AreEqual(0, Integer(Length(mSend.Urls)));
  Assert.AreEqual(1, Integer(Length(mOutcome.Images)));
  mRequest.Files := nil;
  mOutcome.Images := nil;
end;

procedure TAtlasAttachTests.TransportWithoutSendIsNotConfigured;
var
  mRequest: TAtlasAttachRequest;
  mOutcome: TAtlasAttachOutcome;
begin
  mRequest := Default(TAtlasAttachRequest);
  mRequest.Target := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud', 'ATL', '');
  mRequest.Key := 'ATL-1';
  mOutcome := TAtlasAttachSender.Send(TAtlasYouTrackTracker.Create, TFakeGetOnly.Create, mRequest, 1000);
  Assert.AreEqual(TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.NotConfigured), TAtlasCiBuild.ErrorKey(mOutcome.Error));
  mOutcome := TAtlasAttachSender.Send(nil, TFakeSend.Create, mRequest, 1000);
  Assert.AreEqual(TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.NotConfigured), TAtlasCiBuild.ErrorKey(mOutcome.Error));
end;

procedure TAtlasAttachTests.TempFolderIsDeleted;
var
  mTemp: TAtlasAttachTemp;
  mPath, mFolder: string;
begin
  mTemp := TAtlasAttachTemp.Create(FDir);
  try
    mPath := mTemp.Write(Log('Pfad\app.log', 'x'));
    mFolder := mTemp.Folder;
    Assert.IsTrue(TFile.Exists(mPath));
    Assert.AreEqual('app.log', ExtractFileName(mPath));
    Assert.AreEqual(mFolder, ExtractFileDir(mPath));
    mTemp.Cleanup;
    Assert.IsFalse(TDirectory.Exists(mFolder), 'nach Senden bzw. Abbrechen gelöscht');
    // Ein neuer Lauf legt einen neuen Ordner an; das Freigeben räumt ihn weg.
    mPath := mTemp.Write(Png('a.png'));
    mFolder := mTemp.Folder;
  finally
    mTemp.Free;
  end;
  Assert.IsFalse(TDirectory.Exists(mFolder));
  Assert.IsTrue(TAtlasAttachTemp.DefaultRoot.EndsWith(TPath.Combine('Atlas', 'attach')));
end;

procedure TAtlasAttachTests.PruneStaleRemovesOldRuns;
var
  mRun: string;
begin
  mRun := TPath.Combine(FDir, 'alt');
  ForceDirectories(mRun);
  TFile.WriteAllText(TPath.Combine(mRun, 'a.png'), 'x');
  TAtlasAttachTemp.PruneStale(FDir, Now, TAtlasAttachTemp.StaleHours);
  Assert.IsTrue(TDirectory.Exists(mRun), 'frisch: bleibt');
  TAtlasAttachTemp.PruneStale(FDir, Now + 2, TAtlasAttachTemp.StaleHours);
  Assert.IsFalse(TDirectory.Exists(mRun), 'älter als StaleHours: weg');
  // Fehlender Ordner: nichts zu tun.
  TAtlasAttachTemp.PruneStale(TPath.Combine(FDir, 'fehlt'), Now, 1);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAttachTests);

end.
