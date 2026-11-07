unit Atlas.Core.Tracker.Attach;

// „An Issue anhängen …“ (#1276) ohne VCL und Open Tools API, damit alles
// außer dem Aufnehmen der Bilder ohne IDE testbar ist:
// - TAtlasAttachFile: eine Datei (Bildschirmfoto, Formular, Protokoll,
//   Debug-Notiz, Exception-Verlauf) mit Namen, Anzeigetext und Inhalt;
//   UniqueNames macht gleiche Namen eindeutig.
// - TAtlasAttachMultipart: Rumpf einer multipart/form-data-Anfrage (YouTrack:
//   POST /api/issues/<Kennung>/attachments).
// - TAtlasAttachLog: Protokolldateien aus issues.attach.logFiles (Platzhalter
//   $(ProjectDir), $(ProjectName) und Umgebungsvariablen wie $(TEMP); * und ?
//   wählen die neueste passende Datei) und ihr Ende (letzte N Zeilen, von
//   hinten höchstens MaxBytes gelesen, auch während das Programm schreibt).
// - TAtlasAttachImage: Zielgröße nach issues.attach.maxImageWidth.
// - IAtlasTrackerAttach: optionale Schnittstelle eines Anbieters. YouTrack lädt
//   Dateien hoch und verweist im Kommentar auf sie; GitHub nimmt per
//   Schnittstelle keine Dateien an, dort gehen Texte als Codeblock in einen
//   Kommentar.
// - TAtlasAttachSender: Ablauf im Hintergrund. Beim Rückfall (GitHub) bleiben
//   die Bilder für die Zwischenablage und die Seite des Issues für den Browser.
// - TAtlasAttachTemp: Ordner %TEMP%\Atlas\attach\<Lauf> mit genau den Dateien,
//   die gesendet werden; nach Senden oder Abbrechen gelöscht. Reste
//   abgestürzter Läufe räumt PruneStale beim nächsten Start weg.
// Gesendet wird erst, wenn die IDE-Schicht nach dem Klick auf „Senden“
// TAtlasAttachSender.Send aufruft. Kein Inhalt kommt ins Protokoll.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasAttachKind = (Screenshot, Form, LogFile, DebugNote, Exceptions);
{$SCOPEDENUMS OFF}

  TAtlasAttachFile = record
    Kind: TAtlasAttachKind;
    /// <summary>Dateiname beim Tracker, z. B. "bildschirmfoto.png".</summary>
    Name: string;
    /// <summary>Überschrift im Kommentar und Zeile im Dialog, z. B. "app.log (letzte 200 Zeilen)"; '' = Name.
    /// </summary>
    Caption: string;
    MimeType: string;
    Data: TBytes;
    /// <summary>Bild (PNG) aus AData.</summary>
    class function CreateImage(AKind: TAtlasAttachKind; const AName: string; const AData: TBytes): TAtlasAttachFile;
      static;
    /// <summary>Text als UTF-8; MIME-Typ nach der Endung (.md = text/markdown, sonst text/plain).</summary>
    class function CreateText(AKind: TAtlasAttachKind; const AName, AText: string): TAtlasAttachFile; static;
    function Size: Int64;
    function IsImage: Boolean;
    function IsMarkdown: Boolean;
    function Text: string;
    function DisplayName: string;
    /// <summary>Gleiche Namen (ohne Groß/klein) bekommen -2, -3 … vor der Endung; unzulässige Zeichen werden „_“.
    /// </summary>
    class function UniqueNames(const AFiles: TArray<TAtlasAttachFile>): TArray<TAtlasAttachFile>; static;
    /// <summary>Name wie TAtlasIssuePreview.SafeFileName, dazu ohne Klammern und Leerzeichen (Markdown-Verweise).
    /// </summary>
    class function SafeName(const AName: string): string; static;
  end;

  TAtlasAttachFiles = TArray<TAtlasAttachFile>;

  TAtlasAttachMultipart = record
  public const
    /// <summary>Name des Formularfelds jeder Datei (YouTrack nimmt jeden Namen an).</summary>
    cFieldName = 'upload';
  public
    /// <summary>Zufällige Grenze, die in keinem Inhalt vorkommt.</summary>
    class function NewBoundary: string; static;
    class function ContentType(const ABoundary: string): string; static;
    /// <summary>Rumpf mit allen Dateien in Reihenfolge.</summary>
    class function Build(const ABoundary: string; const AFiles: TAtlasAttachFiles): TBytes; static;
  end;

  TAtlasAttachLog = record
  public const
    /// <summary>Höchstens so viele Bytes liest Atlas vom Ende einer Protokolldatei.</summary>
    cMaxBytes = 4 * 1024 * 1024;
    /// <summary>Vorgabe für „nur die letzten N Zeilen“.</summary>
    cDefaultLines = 200;
  public
    /// <summary>Die letzten ACount Zeilen (CRLF, ohne leere Schlusszeile); ACount &lt;= 0 = alle.</summary>
    class function LastLines(const AText: string; ACount: Integer): string; static;
    /// <summary>Bytes einer Datei als Text: BOM, sonst UTF-8, sonst Windows-1252.</summary>
    class function Decode(const ABytes: TBytes): string; static;
    /// <summary>Ende von AFileName: höchstens AMaxBytes von hinten (die angeschnittene erste Zeile entfällt),
    /// davon die letzten ALines Zeilen (&lt;= 0 = alle). Liest auch Dateien, in die gerade geschrieben wird.
    /// False, wenn die Datei fehlt oder nicht lesbar ist.</summary>
    class function ReadTail(const AFileName: string; ALines, AMaxBytes: Integer; out AText: string): Boolean;
      static;
    /// <summary>$(ProjectDir) (ohne „\“ am Ende), $(ProjectName) und Umgebungsvariablen $(NAME) einsetzen;
    /// unbekannte bleiben stehen.</summary>
    class function Expand(const APattern, AProjectFile: string): string; static;
    /// <summary>Einträge aus issues.attach.logFiles (getrennt durch „;“ oder Zeilenumbruch): eingesetzt, relativ
    /// zum Projektordner, mit * und ? die neueste passende Datei; nur vorhandene Dateien, ohne Doppelte.</summary>
    class function Candidates(const AList, AProjectFile: string): TArray<string>; static;
  end;

  TAtlasAttachImage = record
  public const
    cMinWidth = 320;
    cMaxWidth = 7680;
  public
    /// <summary>Breite höchstens AMaxWidth (auf MinWidth..MaxWidth begrenzt), Seitenverhältnis bleibt. True, wenn
    /// verkleinert werden muss.</summary>
    class function ScaledSize(AWidth, AHeight, AMaxWidth: Integer; out ANewWidth, ANewHeight: Integer): Boolean;
      static;
  end;

  TAtlasAttachComment = record
  public const
    /// <summary>GitHub nimmt höchstens 65536 Zeichen je Kommentar; etwas Luft für Überschriften.</summary>
    cMaxTextsLength = 65000;
    /// <summary>So viele Zeichen bleiben je Text mindestens, wenn gekürzt werden muss.</summary>
    cMinTextLength = 1000;
  public
    /// <summary>Kommentar mit Verweisen auf hochgeladene Anhänge (YouTrack): AComment, darunter je Bild ![](Name),
    /// je Datei [Name](Name).</summary>
    class function Referencing(const AComment: string; const AFiles: TAtlasAttachFiles): string; static;
    /// <summary>Kommentar mit den Texten selbst (GitHub): AComment, darunter je Datei die Überschrift (fett) und
    /// der Inhalt, Markdown wie es ist, sonst als Codeblock. Bilder entfallen. Über AMaxLength behalten
    /// Protokolle ihr Ende und Markdown seinen Anfang.</summary>
    class function WithTexts(const AComment: string; const AFiles: TAtlasAttachFiles; AMaxLength: Integer): string;
      static;
    /// <summary>JSON-Rumpf {"AField": "AText"} als UTF-8.</summary>
    class function JsonBody(const AField, AText: string): TBytes; static;
  end;

  /// <summary>Optionale Schnittstelle eines Tracker-Anbieters für „An Issue anhängen“ (#1276).</summary>
  IAtlasTrackerAttach = interface
    ['{8E3C1F52-4A7D-4B29-9C60-D51E7A2B3F94}']
    /// <summary>Nimmt der Tracker Dateien per Schnittstelle an (YouTrack ja, GitHub nein)?</summary>
    function CanUpload: Boolean;
    /// <summary>Alle Dateien an AKey hängen; False mit AError.</summary>
    function Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey: string;
      const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Kommentar AMarkdown an AKey; False mit AError.</summary>
    function Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey,
      AMarkdown: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Kommentar aus AComment und den Dateien: mit CanUpload Verweise auf die Anhänge, sonst die Texte
    /// selbst (Bilder fehlen darin).</summary>
    function CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
  end;

  TAtlasAttachRequest = record
    Target: TAtlasTrackerTarget;
    Key: string;
    Files: TAtlasAttachFiles;
    /// <summary>Text des Nutzers; '' = keiner.</summary>
    Comment: string;
    /// <summary>Kommentar mit Verweis auf die Anhänge anlegen.</summary>
    WithComment: Boolean;
  end;

  TAtlasAttachOutcome = record
    /// <summary>Hochgeladene Dateien.</summary>
    Uploaded: Integer;
    Commented: Boolean;
    /// <summary>Rückfall ohne Hochladen (GitHub): Bilder in die Zwischenablage, Browser mit Page.</summary>
    Fallback: Boolean;
    Images: TAtlasAttachFiles;
    Page: string;
    Error: TAtlasCiFetchError;
    function Succeeded: Boolean;
  end;

  TAtlasAttachSender = record
  public
    /// <summary>Sendet ARequest an den Tracker; im Hintergrund. Ohne IAtlasTrackerAttach bzw. IAtlasCiPost:
    /// NotConfigured.</summary>
    class function Send(const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport;
      const ARequest: TAtlasAttachRequest; ATimeoutMs: Integer): TAtlasAttachOutcome; static;
    /// <summary>Ein POST für die Anbieter: True nur bei 200/201. Kam eine andere Antwort, steht ihr Status in
    /// AResponse (der Anbieter ordnet ihn zu) und Error ist Server; ohne Antwort ist Status 0.</summary>
    class function Post(const ASend: IAtlasCiPost; const AUrl, AContentType: string; const ABody: TBytes;
      ATimeoutMs: Integer; out AResponse: TAtlasCiResponse): Boolean; static;
  end;

  TAtlasAttachTemp = class
  public const
    /// <summary>Ordner älter als so viele Stunden gelten als Rest eines abgestürzten Laufs.</summary>
    cStaleHours = 24;
  private
    FRoot: string;
    FFolder: string;
  public
    /// <summary>ARoot: Ordner aller Läufe (DefaultRoot).</summary>
    constructor Create(const ARoot: string);
    destructor Destroy; override;
    /// <summary>%TEMP%\Atlas\attach.</summary>
    class function DefaultRoot: string; static;
    /// <summary>Ordner dieses Laufs; wird beim ersten Aufruf angelegt.</summary>
    function Folder: string;
    /// <summary>AFile in den Ordner schreiben; liefert den Pfad, '' wenn das Schreiben scheitert.</summary>
    function Write(const AFile: TAtlasAttachFile): string;
    /// <summary>Ordner dieses Laufs samt Inhalt löschen; danach legt Folder einen neuen an.</summary>
    procedure Cleanup;
    /// <summary>Ordner unter ARoot löschen, die älter als AMaxAgeHours sind (gemessen an ANow).</summary>
    class procedure PruneStale(const ARoot: string; ANow: TDateTime; AMaxAgeHours: Integer); static;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Text.Encoding,
  Atlas.Text.Anonymize,
  Atlas.Core.Tracker.Contract.Files,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Preview;

const
  cLineFeed = 10;
  cAtlasFolder = 'Atlas';
  cAttachFolder = 'attach';
  /// <summary>Name eines Laufs: Zeitstempel und die ersten acht Zeichen einer GUID ohne „{“.</summary>
  cRunStamp = 'yyyymmdd-hhnnss';
  cGuidStart = 2;
  cGuidLength = 8;

{ TAtlasAttachFile }

class function TAtlasAttachFile.CreateImage(AKind: TAtlasAttachKind; const AName: string;
  const AData: TBytes): TAtlasAttachFile;
begin
  Result := Default(TAtlasAttachFile);
  Result.Kind := AKind;
  Result.Name := SafeName(AName);
  Result.MimeType := 'image/png';
  Result.Data := AData;
end;

class function TAtlasAttachFile.CreateText(AKind: TAtlasAttachKind; const AName, AText: string): TAtlasAttachFile;
begin
  Result := Default(TAtlasAttachFile);
  Result.Kind := AKind;
  Result.Name := SafeName(AName);
  if SameText(ExtractFileExt(Result.Name), '.md') then
  begin
    Result.MimeType := 'text/markdown; charset=utf-8';
  end
  else
  begin
    Result.MimeType := 'text/plain; charset=utf-8';
  end;
  Result.Data := TEncoding.UTF8.GetBytes(AText);
end;

function TAtlasAttachFile.Size: Int64;
begin
  Result := Length(Data);
end;

function TAtlasAttachFile.IsImage: Boolean;
begin
  Result := MimeType.StartsWith('image/', True);
end;

function TAtlasAttachFile.IsMarkdown: Boolean;
begin
  Result := MimeType.StartsWith('text/markdown', True);
end;

function TAtlasAttachFile.Text: string;
begin
  Result := '';
  if not IsImage then
  begin
    Result := TEncoding.UTF8.GetString(Data);
  end;
end;

function TAtlasAttachFile.DisplayName: string;
begin
  Result := Caption;
  if Result = '' then
  begin
    Result := Name;
  end;
end;

class function TAtlasAttachFile.SafeName(const AName: string): string;
var
  mIndex: Integer;
begin
  // Regeln für Dateinamen wie beim Laden von Anhängen (#1264) …
  Result := TAtlasIssuePreview.SafeFileName(AName);
  // … dazu Zeichen, die einen Markdown-Verweis ![](Name) beenden; Leerzeichen trennen dort die Adresse vom Titel.
  for mIndex := 1 to Length(Result) do
  begin
    if CharInSet(Result[mIndex], ['(', ')', '[', ']']) then
    begin
      Result[mIndex] := '_';
    end
    else if Result[mIndex] = ' ' then
    begin
      Result[mIndex] := '-';
    end;
  end;
end;

class function TAtlasAttachFile.UniqueNames(const AFiles: TArray<TAtlasAttachFile>): TArray<TAtlasAttachFile>;
var
  mIndex, mNumber: Integer;
  mSeen: TDictionary<string, Boolean>;
  mBase, mExt, mName: string;
begin
  Result := Copy(AFiles);
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(Result) do
    begin
      mName := SafeName(Result[mIndex].Name);
      mExt := ExtractFileExt(mName);
      mBase := Copy(mName, 1, Length(mName) - Length(mExt));
      mNumber := 1;
      while mSeen.ContainsKey(LowerCase(mName)) do
      begin
        Inc(mNumber);
        mName := mBase + '-' + IntToStr(mNumber) + mExt;
      end;
      mSeen.Add(LowerCase(mName), True);
      Result[mIndex].Name := mName;
    end;
  finally
    mSeen.Free;
  end;
end;

{ TAtlasAttachMultipart }

class function TAtlasAttachMultipart.NewBoundary: string;
var
  mGuid: TGUID;
begin
  CreateGUID(mGuid);
  Result := '----AtlasAttach' + StringReplace(Copy(GUIDToString(mGuid), 2, 36), '-', '', [rfReplaceAll]);
end;

class function TAtlasAttachMultipart.ContentType(const ABoundary: string): string;
begin
  Result := 'multipart/form-data; boundary=' + ABoundary;
end;

class function TAtlasAttachMultipart.Build(const ABoundary: string; const AFiles: TAtlasAttachFiles): TBytes;
var
  mStream: TBytesStream;
  mFile: TAtlasAttachFile;

  procedure Put(const AText: string);
  var
    mBytes: TBytes;
  begin
    mBytes := TEncoding.UTF8.GetBytes(AText);
    if Length(mBytes) > 0 then
    begin
      mStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  end;

begin
  mStream := TBytesStream.Create;
  try
    for mFile in AFiles do
    begin
      Put('--' + ABoundary + #13#10);
      Put('Content-Disposition: form-data; name="' + cFieldName + '"; filename="' + TAtlasAttachFile.SafeName(
        mFile.Name) + '"' + #13#10);
      Put('Content-Type: ' + mFile.MimeType + #13#10#13#10);
      if Length(mFile.Data) > 0 then
      begin
        mStream.WriteBuffer(mFile.Data[0], Length(mFile.Data));
      end;
      Put(#13#10);
    end;
    Put('--' + ABoundary + '--' + #13#10);
    Result := Copy(mStream.Bytes, 0, mStream.Size);
  finally
    mStream.Free;
  end;
end;

{ TAtlasAttachLog }

class function TAtlasAttachLog.LastLines(const AText: string; ACount: Integer): string;
var
  mLines: TArray<string>;
  mFirst, mLast: Integer;
begin
  mLines := TTextLines.SplitLines(AText);
  mLast := High(mLines);
  // Ein Zeilenumbruch am Ende ergibt keine eigene Zeile.
  if (mLast >= 0) and (mLines[mLast] = '') then
  begin
    Dec(mLast);
  end;
  mFirst := 0;
  if (ACount > 0) and (mLast + 1 > ACount) then
  begin
    mFirst := mLast + 1 - ACount;
  end;
  Result := TTextLines.JoinLines(Copy(mLines, mFirst, mLast - mFirst + 1), #13#10);
end;

class function TAtlasAttachLog.Decode(const ABytes: TBytes): string;
var
  mBom: TTextBom;
  mStart: Integer;
begin
  mBom := TTextEncodingProbe.BomOf(ABytes);
  mStart := TTextEncodingProbe.BomLength(mBom);
  case mBom of
    TTextBom.Utf16LE:
      Result := TEncoding.Unicode.GetString(ABytes, mStart, Length(ABytes) - mStart);
    TTextBom.Utf16BE:
      Result := TEncoding.BigEndianUnicode.GetString(ABytes, mStart, Length(ABytes) - mStart);
  else
    if TTextEncodingProbe.IsValidUtf8(ABytes, mStart) then
    begin
      Result := TEncoding.UTF8.GetString(ABytes, mStart, Length(ABytes) - mStart);
    end
    else
    begin
      Result := TTextEncodingProbe.DecodeCp1252(ABytes, mStart);
    end;
  end;
end;

/// <summary>Ohne die angeschnittene erste Zeile (auch mitten in einem UTF-8-Zeichen): ab dem ersten
/// Zeilenumbruch.</summary>
function WithoutCutLine(const ABytes: TBytes): TBytes;
var
  mCut, mIndex: Integer;
begin
  mCut := 0;
  for mIndex := 0 to High(ABytes) do
  begin
    if ABytes[mIndex] = cLineFeed then
    begin
      mCut := mIndex + 1;
      Break;
    end;
  end;
  Result := Copy(ABytes, mCut, Length(ABytes) - mCut);
end;

class function TAtlasAttachLog.ReadTail(const AFileName: string; ALines, AMaxBytes: Integer;
  out AText: string): Boolean;
var
  mBytes: TBytes;
  mCut: Boolean;
begin
  AText := '';
  // Das laufende Programm hält die Datei oft offen und schreibt hinein.
  Result := TAtlasTrackerFiles.Files.ReadTail(AFileName, AMaxBytes, mBytes, mCut);
  if not Result then
  begin
    Exit;
  end;
  if mCut then
  begin
    mBytes := WithoutCutLine(mBytes);
  end;
  AText := LastLines(Decode(mBytes), ALines);
end;

/// <summary>Ende ")" eines Platzhalters "$(…)" ab AStart; 0, wenn dort keiner beginnt.</summary>
function PlaceholderEnd(const APattern: string; AStart: Integer): Integer;
begin
  Result := 0;
  if (APattern[AStart] = '$') and (AStart < Length(APattern)) and (APattern[AStart + 1] = '(') then
  begin
    Result := PosEx(')', APattern, AStart + 2);
  end;
end;

/// <summary>Wert des Platzhalters AName; '' ohne Wert.</summary>
function PlaceholderValue(const AName, AProjectFile: string): string;
begin
  if SameText(AName, 'ProjectDir') then
  begin
    Result := ExcludeTrailingPathDelimiter(ExtractFilePath(AProjectFile));
  end
  else if SameText(AName, 'ProjectName') then
  begin
    Result := ChangeFileExt(ExtractFileName(AProjectFile), '');
  end
  else
  begin
    Result := TAtlasTrackerFiles.Files.Environment(AName);
  end;
end;

class function TAtlasAttachLog.Expand(const APattern, AProjectFile: string): string;
var
  mStart, mEnd: Integer;
  mValue: string;
begin
  Result := '';
  mStart := 1;
  while mStart <= Length(APattern) do
  begin
    mEnd := PlaceholderEnd(APattern, mStart);
    if mEnd > 0 then
    begin
      mValue := PlaceholderValue(Copy(APattern, mStart + 2, mEnd - mStart - 2), AProjectFile);
      // Ohne Wert bleibt der Platzhalter stehen: Die Datei gibt es dann nicht, statt eines falschen Pfads.
      if mValue = '' then
      begin
        mValue := Copy(APattern, mStart, mEnd - mStart + 1);
      end;
      Result := Result + mValue;
      mStart := mEnd + 1;
    end
    else
    begin
      Result := Result + APattern[mStart];
      Inc(mStart);
    end;
  end;
end;

/// <summary>Neueste Datei zu einer Maske mit * oder ?; '' ohne Treffer.</summary>
function NewestMatch(const APath: string): string;
var
  mFiles: IAtlasTrackerFiles;
  mFolder, mMask, mFile: string;
  mBest: TDateTime;
  mTime: TDateTime;
begin
  Result := '';
  mFolder := ExtractFileDir(APath);
  mMask := ExtractFileName(APath);
  mFiles := TAtlasTrackerFiles.Files;
  if (mFolder = '') or (mMask = '') or not mFiles.FolderExists(mFolder) then
  begin
    Exit;
  end;
  mBest := 0;
  for mFile in mFiles.Files(mFolder, mMask) do
  begin
    mTime := mFiles.WriteTime(mFile);
    // Bei gleicher Zeit gewinnt der Name (stabil).
    if (Result = '') or (mTime > mBest) or ((mTime = mBest) and (CompareText(mFile, Result) < 0)) then
    begin
      Result := mFile;
      mBest := mTime;
    end;
  end;
end;

/// <summary>APath relativ zu AFolder (Projektordner) ergänzt; '' bei relativem Pfad ohne Ordner.</summary>
function RootedPath(const APath, AFolder: string): string;
begin
  Result := APath;
  // Ohne TPath: IsPathRooted und Combine lehnen * und ? als ungültige Zeichen ab.
  if (ExtractFileDrive(APath) = '') and not APath.StartsWith(PathDelim) then
  begin
    Result := '';
    if AFolder <> '' then
    begin
      Result := IncludeTrailingPathDelimiter(AFolder) + APath;
    end;
  end;
end;

/// <summary>Vorhandene Datei zu APath; mit * und ? die neueste passende; '' ohne.</summary>
function ExistingFile(const APath: string): string;
begin
  Result := APath;
  if (Pos('*', APath) > 0) or (Pos('?', APath) > 0) then
  begin
    Result := NewestMatch(APath);
  end
  else if not TAtlasTrackerFiles.Files.FileExists(APath) then
  begin
    Result := '';
  end;
end;

class function TAtlasAttachLog.Candidates(const AList, AProjectFile: string): TArray<string>;
var
  mEntry, mPath, mFolder: string;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mFolder := ExtractFilePath(AProjectFile);
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEntry in StringReplace(StringReplace(AList, #13, ';', [rfReplaceAll]), #10, ';',
      [rfReplaceAll]).Split([';']) do
    begin
      mPath := Trim(Expand(Trim(mEntry), AProjectFile));
      if mPath <> '' then
      begin
        mPath := RootedPath(mPath, mFolder);
      end;
      if mPath <> '' then
      begin
        mPath := ExistingFile(mPath);
      end;
      if (mPath <> '') and not mSeen.ContainsKey(LowerCase(mPath)) then
      begin
        mSeen.Add(LowerCase(mPath), True);
        Result := Result + [mPath];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

{ TAtlasAttachImage }

class function TAtlasAttachImage.ScaledSize(AWidth, AHeight, AMaxWidth: Integer; out ANewWidth,
  ANewHeight: Integer): Boolean;
var
  mMax: Integer;
begin
  ANewWidth := AWidth;
  ANewHeight := AHeight;
  mMax := AMaxWidth;
  if mMax < cMinWidth then
  begin
    mMax := cMinWidth;
  end;
  if mMax > cMaxWidth then
  begin
    mMax := cMaxWidth;
  end;
  Result := (AWidth > mMax) and (AHeight > 0);
  if not Result then
  begin
    Exit;
  end;
  ANewWidth := mMax;
  ANewHeight := Round(Int64(AHeight) * mMax / AWidth);
  if ANewHeight < 1 then
  begin
    ANewHeight := 1;
  end;
end;

{ TAtlasAttachComment }

class function TAtlasAttachComment.Referencing(const AComment: string; const AFiles: TAtlasAttachFiles): string;
var
  mFile: TAtlasAttachFile;
  mLines: TStringBuilder;
begin
  mLines := TStringBuilder.Create;
  try
    if Trim(AComment) <> '' then
    begin
      mLines.Append(Trim(AComment)).Append(#13#10#13#10);
    end;
    for mFile in AFiles do
    begin
      if mFile.IsImage then
      begin
        mLines.Append('![](').Append(mFile.Name).Append(')').Append(#13#10);
      end
      else
      begin
        mLines.Append('[').Append(mFile.DisplayName).Append('](').Append(mFile.Name).Append(')').Append(#13#10);
      end;
    end;
    Result := TrimRight(mLines.ToString);
  finally
    mLines.Free;
  end;
end;

/// <summary>Höchstens AMax Zeichen von AText: das Ende (ATail) bzw. der Anfang, an einer Zeilengrenze, mit „…“.
/// </summary>
function Clip(const AText: string; AMax: Integer; ATail: Boolean): string;
var
  mBreak: Integer;
begin
  Result := AText;
  if Length(Result) <= AMax then
  begin
    Exit;
  end;
  if ATail then
  begin
    Result := Copy(Result, Length(Result) - AMax + 1, AMax);
    mBreak := Pos(#10, Result);
    if (mBreak > 0) and (mBreak < Length(Result)) then
    begin
      Result := Copy(Result, mBreak + 1, MaxInt);
    end;
    Result := '…' + #13#10 + Result;
  end
  else
  begin
    Result := Copy(Result, 1, AMax);
    mBreak := LastDelimiter(#10, Result);
    if mBreak > 1 then
    begin
      Result := Copy(Result, 1, mBreak - 1);
    end;
    Result := TrimRight(Result) + #13#10 + '…';
  end;
end;

/// <summary>Überschrift und Text einer Datei: Markdown wie er ist, sonst als Code-Block.</summary>
procedure AppendFileText(ALines: TStringBuilder; const AFile: TAtlasAttachFile; const AText: string);
begin
  ALines.Append('**').Append(AFile.DisplayName).Append('**').Append(#13#10#13#10);
  if AFile.IsMarkdown then
  begin
    ALines.Append(AText);
  end
  else
  begin
    ALines.Append('```text').Append(#13#10).Append(TTextAnonymizer.FenceSafe(AText)).Append(#13#10).Append('```');
  end;
  ALines.Append(#13#10#13#10);
end;

class function TAtlasAttachComment.WithTexts(const AComment: string; const AFiles: TAtlasAttachFiles;
  AMaxLength: Integer): string;
var
  mTexts: TArray<string>;
  mFiles: TAtlasAttachFiles;
  mFile: TAtlasAttachFile;
  mIndex, mTotal, mBudget: Integer;
  mLines: TStringBuilder;
begin
  mFiles := nil;
  mTexts := nil;
  for mFile in AFiles do
  begin
    if not mFile.IsImage then
    begin
      mFiles := mFiles + [mFile];
      mTexts := mTexts + [TrimRight(mFile.Text)];
    end;
  end;
  // Zu lang: jedem Text gleich viel lassen (mindestens MinTextLength).
  mTotal := Length(AComment);
  for mIndex := 0 to High(mTexts) do
  begin
    Inc(mTotal, Length(mTexts[mIndex]) + Length(mFiles[mIndex].DisplayName) + 32);
  end;
  if (AMaxLength > 0) and (mTotal > AMaxLength) and (Length(mTexts) > 0) then
  begin
    mBudget := (AMaxLength - Length(AComment)) div Length(mTexts) - Length(mTexts) * 64;
    if mBudget < cMinTextLength then
    begin
      mBudget := cMinTextLength;
    end;
    for mIndex := 0 to High(mTexts) do
    begin
      mTexts[mIndex] := Clip(mTexts[mIndex], mBudget, not mFiles[mIndex].IsMarkdown);
    end;
  end;
  mLines := TStringBuilder.Create;
  try
    if Trim(AComment) <> '' then
    begin
      mLines.Append(Trim(AComment)).Append(#13#10#13#10);
    end;
    for mIndex := 0 to High(mFiles) do
    begin
      AppendFileText(mLines, mFiles[mIndex], mTexts[mIndex]);
    end;
    Result := TrimRight(mLines.ToString);
  finally
    mLines.Free;
  end;
end;

class function TAtlasAttachComment.JsonBody(const AField, AText: string): TBytes;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair(AField, TJSONString.Create(AText));
    Result := TEncoding.UTF8.GetBytes(mObject.ToJSON);
  finally
    mObject.Free;
  end;
end;

{ TAtlasAttachOutcome }

function TAtlasAttachOutcome.Succeeded: Boolean;
begin
  Result := Error = TAtlasCiFetchError.None;
end;

{ TAtlasAttachSender }

/// <summary>Kommentar mit AFiles senden; setzt Commented bzw. Error von AOutcome.</summary>
procedure SendComment(const AAttach: IAtlasTrackerAttach; const ASend: IAtlasCiPost;
  const ARequest: TAtlasAttachRequest; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer;
  var AOutcome: TAtlasAttachOutcome);
var
  mError: TAtlasCiFetchError;
begin
  if AAttach.Comment(ARequest.Target, ASend, ARequest.Key, AAttach.CommentText(ARequest.Comment, AFiles),
    ATimeoutMs, mError) then
  begin
    AOutcome.Commented := True;
  end
  else
  begin
    AOutcome.Error := mError;
  end;
end;

/// <summary>Tracker mit Anhängen (YouTrack): Dateien hochladen, dann der Kommentar.</summary>
procedure SendUploads(const AAttach: IAtlasTrackerAttach; const ASend: IAtlasCiPost;
  const ARequest: TAtlasAttachRequest; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer;
  var AOutcome: TAtlasAttachOutcome);
var
  mError: TAtlasCiFetchError;
begin
  if Length(AFiles) > 0 then
  begin
    if not AAttach.Upload(ARequest.Target, ASend, ARequest.Key, AFiles, ATimeoutMs, mError) then
    begin
      AOutcome.Error := mError;
      Exit;
    end;
    AOutcome.Uploaded := Length(AFiles);
  end;
  if ARequest.WithComment and ((Length(AFiles) > 0) or (Trim(ARequest.Comment) <> '')) then
  begin
    SendComment(AAttach, ASend, ARequest, AFiles, ATimeoutMs, AOutcome);
  end;
end;

/// <summary>Rückfall (GitHub): Texte in den Kommentar, Bilder bleiben für die Zwischenablage.</summary>
procedure SendFallback(const AAttach: IAtlasTrackerAttach; const ASend: IAtlasCiPost;
  const ARequest: TAtlasAttachRequest; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer;
  var AOutcome: TAtlasAttachOutcome);
var
  mTexts: TAtlasAttachFiles;
  mFile: TAtlasAttachFile;
begin
  mTexts := nil;
  for mFile in AFiles do
  begin
    if mFile.IsImage then
    begin
      AOutcome.Images := AOutcome.Images + [mFile];
    end
    else
    begin
      mTexts := mTexts + [mFile];
    end;
  end;
  if (Length(mTexts) > 0) or (ARequest.WithComment and (Trim(ARequest.Comment) <> '')) then
  begin
    SendComment(AAttach, ASend, ARequest, mTexts, ATimeoutMs, AOutcome);
  end;
end;

class function TAtlasAttachSender.Send(const AProvider: IAtlasTrackerProvider; const ATransport: IAtlasCiTransport;
  const ARequest: TAtlasAttachRequest; ATimeoutMs: Integer): TAtlasAttachOutcome;
var
  mAttach: IAtlasTrackerAttach;
  mSend: IAtlasCiPost;
  mFiles: TAtlasAttachFiles;
begin
  Result := Default(TAtlasAttachOutcome);
  Result.Images := nil;
  Result.Error := TAtlasCiFetchError.NotConfigured;
  if (AProvider = nil) or (ATransport = nil) or (ARequest.Key = '') or
    not Supports(AProvider, IAtlasTrackerAttach, mAttach) or not Supports(ATransport, IAtlasCiPost, mSend) then
  begin
    Exit;
  end;
  mFiles := TAtlasAttachFile.UniqueNames(ARequest.Files);
  Result.Error := TAtlasCiFetchError.None;
  if mAttach.CanUpload then
  begin
    SendUploads(mAttach, mSend, ARequest, mFiles, ATimeoutMs, Result);
  end
  else
  begin
    Result.Fallback := True;
    Result.Page := AProvider.IssuePage(ARequest.Target, ARequest.Key);
    SendFallback(mAttach, mSend, ARequest, mFiles, ATimeoutMs, Result);
  end;
end;

class function TAtlasAttachSender.Post(const ASend: IAtlasCiPost; const AUrl, AContentType: string;
  const ABody: TBytes; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse): Boolean;
begin
  Result := False;
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.NotConfigured);
  if (AUrl = '') or (ASend = nil) then
  begin
    Exit;
  end;
  if not ASend.Post(AUrl, AContentType, ABody, ATimeoutMs, AResponse) then
  begin
    AResponse.Status := 0;
    Exit;
  end;
  if (AResponse.Status <> 200) and (AResponse.Status <> 201) then
  begin
    AResponse.Error := TAtlasCiFetchError.Server;
    Exit;
  end;
  AResponse.Error := TAtlasCiFetchError.None;
  Result := True;
end;

{ TAtlasAttachTemp }

constructor TAtlasAttachTemp.Create(const ARoot: string);
begin
  inherited Create;
  FRoot := ARoot;
end;

destructor TAtlasAttachTemp.Destroy;
begin
  Cleanup;
  inherited;
end;

class function TAtlasAttachTemp.DefaultRoot: string;
begin
  Result := TAtlasTrackerFiles.Join(TAtlasTrackerFiles.Join(TAtlasTrackerFiles.Files.TempFolder, cAtlasFolder),
    cAttachFolder);
end;

function TAtlasAttachTemp.Folder: string;
var
  mGuid: TGUID;
begin
  if FFolder = '' then
  begin
    CreateGUID(mGuid);
    FFolder := TAtlasTrackerFiles.Join(FRoot, FormatDateTime(cRunStamp, Now, TFormatSettings.Invariant) + '-' +
      Copy(GUIDToString(mGuid), cGuidStart, cGuidLength));
    TAtlasTrackerFiles.Files.ForceFolder(FFolder);
  end;
  Result := FFolder;
end;

function TAtlasAttachTemp.Write(const AFile: TAtlasAttachFile): string;
begin
  Result := TAtlasTrackerFiles.Join(Folder, TAtlasAttachFile.SafeName(AFile.Name));
  // Kein Platz, keine Rechte: Die Datei geht trotzdem an den Tracker, nur Doppelklick öffnet nichts.
  if not TAtlasTrackerFiles.Files.WriteBytes(Result, AFile.Data) then
  begin
    Result := '';
  end;
end;

procedure TAtlasAttachTemp.Cleanup;
begin
  if FFolder = '' then
  begin
    Exit;
  end;
  // Eine Datei ist noch offen (z. B. im Bildbetrachter): PruneStale räumt beim nächsten Start auf.
  TAtlasTrackerFiles.Files.DeleteFolder(FFolder);
  FFolder := '';
end;

class procedure TAtlasAttachTemp.PruneStale(const ARoot: string; ANow: TDateTime; AMaxAgeHours: Integer);
var
  mFiles: IAtlasTrackerFiles;
  mFolder: string;
begin
  mFiles := TAtlasTrackerFiles.Files;
  if (ARoot = '') or not mFiles.FolderExists(ARoot) then
  begin
    Exit;
  end;
  // Gesperrte Ordner bleiben bis zum nächsten Start.
  for mFolder in mFiles.Folders(ARoot) do
  begin
    if HoursBetween(ANow, mFiles.WriteTime(mFolder)) >= AMaxAgeHours then
    begin
      mFiles.DeleteFolder(mFolder);
    end;
  end;
end;

end.
