unit Atlas.Core.Lsp.CrashCases;

// Absturzfälle des Servers im Plugin (#1355). Der Server legt Fälle unter
// %LOCALAPPDATA%\Atlas\crash\<Zeitpunkt>_<pid>\ an und meldet sie mit
// atlas/crashCase; das Sicherheitsnetz meldet Beginn und Ende des
// Überspringens mit atlas/crashSkip. Diese Unit liest beides (Benachrichtigung
// bzw. anfrage.json, wenn der Server dabei starb), baut die Texte für die
// Meldung „Atlas-Server neu gestartet: textDocument/hover in UI.Auftrag.pas:812
// löste EStackOverflow aus“, für „Issue anlegen“ (#1268: Titel, Text mit Stapel
// und Version) und die Dateien des Falls für den Anhang (#1276; als Name und
// Text, ohne Abhängigkeit vom Tracker-Feature), und führt die
// Liste der gerade übersprungenen Anfragen (Statusleiste, Prüffenster).
// Kein Netzzugriff: Fälle verlassen den Rechner nur über „Issue anlegen“.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  /// <summary>Ein gesicherter Fall (atlas/crashCase bzw. anfrage.json).</summary>
  TAtlasCrashCase = record
    /// <summary>„textDocument/hover in UI.Auftrag.pas:812 löste EStackOverflow aus“.</summary>
    Summary: string;
    Folder: string;
    Method: string;
    /// <summary>„exception“ oder „timeout“.</summary>
    Kind: string;
    FileName: string;
    Uri: string;
    /// <summary>Zeile ab 0; -1 ohne.</summary>
    Line: Integer;
    ExceptionClass: string;
    ExceptionMessage: string;
    Version: string;
    /// <summary>Wird die Anfrage ab jetzt übersprungen (zweiter Absturz)?</summary>
    Skipping: Boolean;
    class function Empty: TAtlasCrashCase; static;
  end;

  /// <summary>Eine Datei des Falls: Name im Ordner und Inhalt.</summary>
  TAtlasCrashCaseFile = record
    Name: string;
    Text: string;
  end;

  /// <summary>Beginn (Active) bzw. Ende des Überspringens einer Anfrage an einer Datei (atlas/crashSkip).</summary>
  TAtlasCrashSkip = record
    Active: Boolean;
    Method: string;
    Uri: string;
    FileName: string;
    Crashes: Integer;
    ExceptionClass: string;
    Folder: string;
  end;

  TAtlasCrashCases = class
  public const
    cCaseNotification = 'atlas/crashCase';
    cSkipNotification = 'atlas/crashSkip';
    cRetryCommand = 'atlas.crash.retry';
    cRequestName = 'anfrage.json';
    cStackName = 'stapel.txt';
    /// <summary>Quelle der Einträge im Prüffenster.</summary>
    cProblemSource = 'Atlas-Server';
    cProblemCode = 'crash-skip';
    /// <summary>Höchstens so lang wird eine Datei des Falls angehängt (Schnappschüsse großer Units).</summary>
    cMaxAttachChars = 2 * 1024 * 1024;
  public
    class function ParseCase(const AParams: TJSONValue; out ACase: TAtlasCrashCase): Boolean; static;
    class function ParseSkip(const AParams: TJSONValue; out ASkip: TAtlasCrashSkip): Boolean; static;
    /// <summary>Liest anfrage.json im Ordner AFolder; Summary wie beim Server.</summary>
    class function Load(const AFolder: string; out ACase: TAtlasCrashCase): Boolean; static;
    /// <summary>Ordner der Fälle: %LOCALAPPDATA%\Atlas\crash.</summary>
    class function DefaultRoot: string; static;
    /// <summary>Jüngster Fall unter ARoot, der ab ASince (Ortszeit) entstand; False ohne.</summary>
    class function Newest(const ARoot: string; ASince: TDateTime; out ACase: TAtlasCrashCase): Boolean; static;
    /// <summary>Text der Meldung nach dem Neustart bzw. bei einem gesicherten Fall.</summary>
    class function SummaryText(const ACase: TAtlasCrashCase): string; static;
    /// <summary>Titel für „Issue anlegen“.</summary>
    class function IssueTitle(const ACase: TAtlasCrashCase): string; static;
    /// <summary>Text für „Issue anlegen“ (Markdown): Zusammenfassung, Version, Ausnahme, Stapel aus stapel.txt.
    /// </summary>
    class function IssueDescription(const ACase: TAtlasCrashCase): string; static;
    /// <summary>Dateien des Falls als Anhang (Text, ohne wiederholen.cmd), anfrage.json zuerst.</summary>
    class function AttachFiles(const AFolder: string): TArray<TAtlasCrashCaseFile>; static;
    /// <summary>Argumente von atlas.crash.retry: die Uri ('' = alle).</summary>
    class function RetryArguments(const AUri: string): TJSONArray; static;
  end;

  /// <summary>Gerade übersprungene Anfragen je (Methode, Uri); nur im Hauptthread.</summary>
  TAtlasCrashSkips = class
  private
    FItems: TList<TAtlasCrashSkip>;
    function IndexOf(const AMethod, AUri: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Beginn bzw. Ende übernehmen; True, wenn sich die Liste geändert hat.</summary>
    function Apply(const ASkip: TAtlasCrashSkip): Boolean;
    procedure Clear;
    function Count: Integer;
    function Items: TArray<TAtlasCrashSkip>;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Defaults,
  Atlas.Core.Localization.Language,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TCrashCasesText = (ExceededTheTimeLimitOf, Raised, Crash, TheAtlasServerCrashed, Method, FileText, Line, Exception,
    CaseText, FilesAttachedReproduceWithAtlasServer);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TCrashCasesText] of string = (
    ('überschritt das Zeitlimit von %d ms',
     'löste %s aus',
     'Absturz: ',
     'Der Atlas-Server ist abgestürzt: ',
     '- Methode: `',
     '- Datei: `',
     ', Zeile ',
     '- Ausnahme: `',
     '- Fall: `',
     '` (Dateien als Anhang; nachstellen mit `AtlasServer --replay anfrage.json`)'),
    ('exceeded the time limit of %d ms',
     'raised %s',
     'Crash: ',
     'The Atlas server crashed: ',
     '- Method: `',
     '- File: `',
     ', line ',
     '- Exception: `',
     '- Case: `',
     '` (files attached; reproduce with `AtlasServer --replay anfrage.json`)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCrashCasesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasCrashCase }

class function TAtlasCrashCase.Empty: TAtlasCrashCase;
begin
  Result := Default(TAtlasCrashCase);
  Result.Line := -1;
end;

{ TAtlasCrashCases }

class function TAtlasCrashCases.ParseCase(const AParams: TJSONValue; out ACase: TAtlasCrashCase): Boolean;
var
  mObject: TJSONObject;
begin
  ACase := TAtlasCrashCase.Empty;
  Result := AParams is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  mObject := TJSONObject(AParams);
  ACase.Summary := TJsonRead.StrictText(mObject, 'summary');
  ACase.Folder := TJsonRead.StrictText(mObject, 'folder');
  ACase.Method := TJsonRead.StrictText(mObject, 'method');
  ACase.Kind := TJsonRead.StrictText(mObject, 'kind');
  ACase.FileName := TJsonRead.StrictText(mObject, 'file');
  ACase.Uri := TJsonRead.StrictText(mObject, 'uri');
  ACase.Line := TJsonRead.IntOr(mObject, 'line', -1);
  ACase.ExceptionClass := TJsonRead.StrictText(mObject, 'exception');
  ACase.ExceptionMessage := TJsonRead.StrictText(mObject, 'message');
  ACase.Version := TJsonRead.StrictText(mObject, 'version');
  ACase.Skipping := TJsonRead.Flag(mObject, 'skipping');
  Result := (ACase.Summary <> '') and (ACase.Folder <> '');
end;

class function TAtlasCrashCases.ParseSkip(const AParams: TJSONValue; out ASkip: TAtlasCrashSkip): Boolean;
var
  mObject: TJSONObject;
begin
  ASkip := Default(TAtlasCrashSkip);
  Result := AParams is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  mObject := TJSONObject(AParams);
  ASkip.Active := TJsonRead.Flag(mObject, 'active');
  ASkip.Method := TJsonRead.StrictText(mObject, 'method');
  ASkip.Uri := TJsonRead.StrictText(mObject, 'uri');
  ASkip.FileName := TJsonRead.StrictText(mObject, 'file');
  ASkip.Crashes := TJsonRead.IntOr(mObject, 'crashes', 0);
  ASkip.ExceptionClass := TJsonRead.StrictText(mObject, 'exception');
  ASkip.Folder := TJsonRead.StrictText(mObject, 'folder');
  Result := (ASkip.Method <> '') and (ASkip.Uri <> '');
end;

function SummaryOf(const ACase: TAtlasCrashCase; ATimeoutMs: Integer): string;
var
  mWhere, mWhat: string;
begin
  mWhere := '';
  if ACase.FileName <> '' then
  begin
    mWhere := ExtractFileName(ACase.FileName);
  end
  else if ACase.Uri <> '' then
  begin
    mWhere := ACase.Uri;
  end;
  if (mWhere <> '') and (ACase.Line >= 0) then
  begin
    mWhere := mWhere + ':' + IntToStr(ACase.Line + 1);
  end;
  if ACase.Kind = 'timeout' then
  begin
    mWhat := Format(UiText(TCrashCasesText.ExceededTheTimeLimitOf), [ATimeoutMs]);
  end
  else
  begin
    mWhat := Format(UiText(TCrashCasesText.Raised), [ACase.ExceptionClass]);
  end;
  if mWhere <> '' then
  begin
    Result := Format('%s in %s %s', [ACase.Method, mWhere, mWhat]);
  end
  else
  begin
    Result := ACase.Method + ' ' + mWhat;
  end;
end;

class function TAtlasCrashCases.Load(const AFolder: string; out ACase: TAtlasCrashCase): Boolean;
var
  mFile: string;
  mRoot, mValue: TJSONValue;
  mObject: TJSONObject;
begin
  ACase := TAtlasCrashCase.Empty;
  Result := False;
  mFile := TPath.Combine(AFolder, cRequestName);
  if not TFile.Exists(mFile) then
  begin
    Exit;
  end;
  // Ohne Ausnahme parsen: mit RaiseExc = True lässt die RTL bei kaputtem JSON das halb gebaute Objekt liegen.
  // Halb geschrieben oder von Hand verändert: kein Fall (nil).
  try
    mRoot := TJSONValue.ParseJSONValue(TFile.ReadAllText(mFile, TEncoding.UTF8), False, False);
  except
    // Nicht lesbar (Kodierung, Zugriff).
    on Exception do
      Exit;
  end;
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mObject := TJSONObject(mRoot);
    ACase.Folder := AFolder;
    ACase.Method := TJsonRead.StrictText(mObject, 'method');
    ACase.Kind := TJsonRead.StrictText(mObject, 'kind');
    ACase.FileName := TJsonRead.StrictText(mObject, 'file');
    ACase.Uri := TJsonRead.StrictText(mObject, 'uri');
    ACase.Line := TJsonRead.IntOr(mObject, 'line', -1);
    ACase.Version := TJsonRead.StrictText(mObject, 'atlasVersion');
    mValue := mObject.GetValue('exception');
    if mValue is TJSONObject then
    begin
      ACase.ExceptionClass := TJsonRead.StrictText(TJSONObject(mValue), 'class');
      ACase.ExceptionMessage := TJsonRead.StrictText(TJSONObject(mValue), 'message');
    end;
    ACase.Summary := SummaryOf(ACase, TJsonRead.IntOr(mObject, 'timeoutMs', 0));
    Result := ACase.Method <> '';
  finally
    mRoot.Free;
  end;
end;

class function TAtlasCrashCases.DefaultRoot: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetCachePath, 'Atlas'), 'crash');
end;

class function TAtlasCrashCases.Newest(const ARoot: string; ASince: TDateTime; out ACase: TAtlasCrashCase): Boolean;
var
  mFolders: TList<string>;
  mFolder, mFile: string;
  mIndex: Integer;
begin
  ACase := TAtlasCrashCase.Empty;
  Result := False;
  if (ARoot = '') or not TDirectory.Exists(ARoot) then
  begin
    Exit;
  end;
  mFolders := TList<string>.Create;
  try
    for mFolder in TDirectory.GetDirectories(ARoot) do
    begin
      mFile := TPath.Combine(mFolder, cRequestName);
      if TFile.Exists(mFile) and (TFile.GetLastWriteTime(mFile) >= ASince) then
      begin
        mFolders.Add(mFolder);
      end;
    end;
    // Der Name beginnt mit dem Zeitpunkt (JJJJ-MM-TT_hhmmss_pid); jüngster zuletzt.
    mFolders.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareStr(ExtractFileName(ALeft), ExtractFileName(ARight));
      end));
    for mIndex := mFolders.Count - 1 downto 0 do
    begin
      if Load(mFolders[mIndex], ACase) then
      begin
        Exit(True);
      end;
    end;
  finally
    mFolders.Free;
  end;
end;

class function TAtlasCrashCases.SummaryText(const ACase: TAtlasCrashCase): string;
begin
  Result := ACase.Summary;
  if (Result <> '') and (ACase.Version <> '') then
  begin
    Result := Result + ' (Atlas ' + ACase.Version + ')';
  end;
end;

class function TAtlasCrashCases.IssueTitle(const ACase: TAtlasCrashCase): string;
begin
  Result := UiText(TCrashCasesText.Crash) + ACase.Summary;
end;

class function TAtlasCrashCases.IssueDescription(const ACase: TAtlasCrashCase): string;
var
  mLines: TStringBuilder;
  mStack: string;
  mFile: string;
begin
  mStack := '';
  mFile := TPath.Combine(ACase.Folder, cStackName);
  try
    if (ACase.Folder <> '') and TFile.Exists(mFile) then
    begin
      mStack := Trim(TFile.ReadAllText(mFile, TEncoding.UTF8));
    end;
  except
    // Gesperrt oder gelöscht: der Text ohne Stapel.
    on Exception do
      mStack := '';
  end;
  mLines := TStringBuilder.Create;
  try
    mLines.Append(UiText(TCrashCasesText.TheAtlasServerCrashed)).Append(ACase.Summary).Append('.').Append(sLineBreak);
    mLines.Append(sLineBreak);
    mLines.Append(UiText(TCrashCasesText.Method)).Append(ACase.Method).Append('`').Append(sLineBreak);
    if ACase.FileName <> '' then
    begin
      mLines.Append(UiText(TCrashCasesText.FileText)).Append(ExtractFileName(ACase.FileName)).Append('`');
      if ACase.Line >= 0 then
      begin
        mLines.Append(UiText(TCrashCasesText.Line)).Append(IntToStr(ACase.Line + 1));
      end;
      mLines.Append(sLineBreak);
    end;
    if ACase.ExceptionClass <> '' then
    begin
      mLines.Append(UiText(TCrashCasesText.Exception)).Append(ACase.ExceptionClass).Append('`: ')
        .Append(ACase.ExceptionMessage)
        .Append(sLineBreak);
    end;
    if ACase.Version <> '' then
    begin
      mLines.Append('- Atlas-Version: ').Append(ACase.Version).Append(sLineBreak);
    end;
    mLines.Append(UiText(TCrashCasesText.CaseText)).Append(ExtractFileName(ACase.Folder))
      .Append(UiText(TCrashCasesText.FilesAttachedReproduceWithAtlasServer)).Append(sLineBreak);
    if mStack <> '' then
    begin
      mLines.Append(sLineBreak).Append('```').Append(sLineBreak);
      mLines.Append(mStack).Append(sLineBreak);
      mLines.Append('```').Append(sLineBreak);
    end;
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

class function TAtlasCrashCases.AttachFiles(const AFolder: string): TArray<TAtlasCrashCaseFile>;
var
  mFiles: TArray<string>;
  mFile, mName, mText: string;
  mAttach: TAtlasCrashCaseFile;
begin
  Result := nil;
  if (AFolder = '') or not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  mFiles := TDirectory.GetFiles(AFolder);
  TArray.Sort<string>(mFiles, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      // anfrage.json zuerst, dann nach Namen.
      Result := Ord(not SameText(ExtractFileName(ALeft), cRequestName)) -
        Ord(not SameText(ExtractFileName(ARight), cRequestName));
      if Result = 0 then
      begin
        Result := CompareText(ExtractFileName(ALeft), ExtractFileName(ARight));
      end;
    end));
  for mFile in mFiles do
  begin
    mName := ExtractFileName(mFile);
    // Ein Skript im Anhang nützt dem Empfänger nichts und wirkt verdächtig.
    if SameText(ExtractFileExt(mName), '.cmd') then
    begin
      Continue;
    end;
    try
      mText := TFile.ReadAllText(mFile, TEncoding.UTF8);
      if Length(mText) > cMaxAttachChars then
      begin
        Continue;
      end;
      mAttach.Name := mName;
      mAttach.Text := mText;
      Result := Result + [mAttach];
    except
      // Gesperrt: ohne diese Datei.
      on Exception do
        Continue;
    end;
  end;
end;

class function TAtlasCrashCases.RetryArguments(const AUri: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(AUri);
end;

{ TAtlasCrashSkips }

constructor TAtlasCrashSkips.Create;
begin
  inherited Create;
  FItems := TList<TAtlasCrashSkip>.Create;
end;

destructor TAtlasCrashSkips.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TAtlasCrashSkips.IndexOf(const AMethod, AUri: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if (FItems[mIndex].Method = AMethod) and SameText(FItems[mIndex].Uri, AUri) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasCrashSkips.Apply(const ASkip: TAtlasCrashSkip): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(ASkip.Method, ASkip.Uri);
  if ASkip.Active then
  begin
    if mIndex >= 0 then
    begin
      FItems[mIndex] := ASkip;
    end
    else
    begin
      FItems.Add(ASkip);
    end;
    Result := True;
  end
  else
  begin
    Result := mIndex >= 0;
    if Result then
    begin
      FItems.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasCrashSkips.Clear;
begin
  FItems.Clear;
end;

function TAtlasCrashSkips.Count: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasCrashSkips.Items: TArray<TAtlasCrashSkip>;
begin
  Result := FItems.ToArray;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.CrashCases', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
