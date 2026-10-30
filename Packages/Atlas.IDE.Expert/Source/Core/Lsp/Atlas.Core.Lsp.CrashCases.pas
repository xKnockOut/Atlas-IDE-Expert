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
    CaseNotification = 'atlas/crashCase';
    SkipNotification = 'atlas/crashSkip';
    RetryCommand = 'atlas.crash.retry';
    RequestName = 'anfrage.json';
    StackName = 'stapel.txt';
    /// <summary>Quelle der Einträge im Prüffenster.</summary>
    ProblemSource = 'Atlas-Server';
    ProblemCode = 'crash-skip';
    /// <summary>Höchstens so lang wird eine Datei des Falls angehängt (Schnappschüsse großer Units).</summary>
    MaxAttachChars = 2 * 1024 * 1024;
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
  System.Generics.Defaults;

function StringOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    Result := mValue.Value;
end;

function IntegerOf(const AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsInt;
end;

function BooleanOf(const AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
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
    Exit;
  mObject := TJSONObject(AParams);
  ACase.Summary := StringOf(mObject, 'summary');
  ACase.Folder := StringOf(mObject, 'folder');
  ACase.Method := StringOf(mObject, 'method');
  ACase.Kind := StringOf(mObject, 'kind');
  ACase.FileName := StringOf(mObject, 'file');
  ACase.Uri := StringOf(mObject, 'uri');
  ACase.Line := IntegerOf(mObject, 'line', -1);
  ACase.ExceptionClass := StringOf(mObject, 'exception');
  ACase.ExceptionMessage := StringOf(mObject, 'message');
  ACase.Version := StringOf(mObject, 'version');
  ACase.Skipping := BooleanOf(mObject, 'skipping');
  Result := (ACase.Summary <> '') and (ACase.Folder <> '');
end;

class function TAtlasCrashCases.ParseSkip(const AParams: TJSONValue; out ASkip: TAtlasCrashSkip): Boolean;
var
  mObject: TJSONObject;
begin
  ASkip := Default(TAtlasCrashSkip);
  Result := AParams is TJSONObject;
  if not Result then
    Exit;
  mObject := TJSONObject(AParams);
  ASkip.Active := BooleanOf(mObject, 'active');
  ASkip.Method := StringOf(mObject, 'method');
  ASkip.Uri := StringOf(mObject, 'uri');
  ASkip.FileName := StringOf(mObject, 'file');
  ASkip.Crashes := IntegerOf(mObject, 'crashes', 0);
  ASkip.ExceptionClass := StringOf(mObject, 'exception');
  ASkip.Folder := StringOf(mObject, 'folder');
  Result := (ASkip.Method <> '') and (ASkip.Uri <> '');
end;

function SummaryOf(const ACase: TAtlasCrashCase; ATimeoutMs: Integer): string;
var
  mWhere, mWhat: string;
begin
  mWhere := '';
  if ACase.FileName <> '' then
    mWhere := ExtractFileName(ACase.FileName)
  else if ACase.Uri <> '' then
    mWhere := ACase.Uri;
  if (mWhere <> '') and (ACase.Line >= 0) then
    mWhere := mWhere + ':' + IntToStr(ACase.Line + 1);
  if ACase.Kind = 'timeout' then
    mWhat := Format('überschritt das Zeitlimit von %d ms', [ATimeoutMs])
  else
    mWhat := 'löste ' + ACase.ExceptionClass + ' aus';
  if mWhere <> '' then
    Result := Format('%s in %s %s', [ACase.Method, mWhere, mWhat])
  else
    Result := ACase.Method + ' ' + mWhat;
end;

class function TAtlasCrashCases.Load(const AFolder: string; out ACase: TAtlasCrashCase): Boolean;
var
  mFile: string;
  mRoot, mValue: TJSONValue;
  mObject: TJSONObject;
begin
  ACase := TAtlasCrashCase.Empty;
  Result := False;
  mFile := TPath.Combine(AFolder, RequestName);
  if not TFile.Exists(mFile) then
    Exit;
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
      Exit;
    mObject := TJSONObject(mRoot);
    ACase.Folder := AFolder;
    ACase.Method := StringOf(mObject, 'method');
    ACase.Kind := StringOf(mObject, 'kind');
    ACase.FileName := StringOf(mObject, 'file');
    ACase.Uri := StringOf(mObject, 'uri');
    ACase.Line := IntegerOf(mObject, 'line', -1);
    ACase.Version := StringOf(mObject, 'atlasVersion');
    mValue := mObject.GetValue('exception');
    if mValue is TJSONObject then
    begin
      ACase.ExceptionClass := StringOf(TJSONObject(mValue), 'class');
      ACase.ExceptionMessage := StringOf(TJSONObject(mValue), 'message');
    end;
    ACase.Summary := SummaryOf(ACase, IntegerOf(mObject, 'timeoutMs', 0));
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
    Exit;
  mFolders := TList<string>.Create;
  try
    for mFolder in TDirectory.GetDirectories(ARoot) do
    begin
      mFile := TPath.Combine(mFolder, RequestName);
      if TFile.Exists(mFile) and (TFile.GetLastWriteTime(mFile) >= ASince) then
        mFolders.Add(mFolder);
    end;
    // Der Name beginnt mit dem Zeitpunkt (JJJJ-MM-TT_hhmmss_pid); jüngster zuletzt.
    mFolders.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareStr(ExtractFileName(ALeft), ExtractFileName(ARight));
      end));
    for mIndex := mFolders.Count - 1 downto 0 do
      if Load(mFolders[mIndex], ACase) then
        Exit(True);
  finally
    mFolders.Free;
  end;
end;

class function TAtlasCrashCases.SummaryText(const ACase: TAtlasCrashCase): string;
begin
  Result := ACase.Summary;
  if (Result <> '') and (ACase.Version <> '') then
    Result := Result + ' (Atlas ' + ACase.Version + ')';
end;

class function TAtlasCrashCases.IssueTitle(const ACase: TAtlasCrashCase): string;
begin
  Result := 'Absturz: ' + ACase.Summary;
end;

class function TAtlasCrashCases.IssueDescription(const ACase: TAtlasCrashCase): string;
var
  mLines: TStringBuilder;
  mStack: string;
  mFile: string;
begin
  mStack := '';
  mFile := TPath.Combine(ACase.Folder, StackName);
  try
    if (ACase.Folder <> '') and TFile.Exists(mFile) then
      mStack := Trim(TFile.ReadAllText(mFile, TEncoding.UTF8));
  except
    // Gesperrt oder gelöscht: der Text ohne Stapel.
    on Exception do
      mStack := '';
  end;
  mLines := TStringBuilder.Create;
  try
    mLines.Append('Der Atlas-Server ist abgestürzt: ').Append(ACase.Summary).Append('.').Append(sLineBreak);
    mLines.Append(sLineBreak);
    mLines.Append('- Methode: `').Append(ACase.Method).Append('`').Append(sLineBreak);
    if ACase.FileName <> '' then
    begin
      mLines.Append('- Datei: `').Append(ExtractFileName(ACase.FileName)).Append('`');
      if ACase.Line >= 0 then
        mLines.Append(', Zeile ').Append(IntToStr(ACase.Line + 1));
      mLines.Append(sLineBreak);
    end;
    if ACase.ExceptionClass <> '' then
      mLines.Append('- Ausnahme: `').Append(ACase.ExceptionClass).Append('`: ').Append(ACase.ExceptionMessage)
        .Append(sLineBreak);
    if ACase.Version <> '' then
      mLines.Append('- Atlas-Version: ').Append(ACase.Version).Append(sLineBreak);
    mLines.Append('- Fall: `').Append(ExtractFileName(ACase.Folder)).Append('` (Dateien als Anhang; ')
      .Append('nachstellen mit `AtlasServer --replay anfrage.json`)').Append(sLineBreak);
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
    Exit;
  mFiles := TDirectory.GetFiles(AFolder);
  TArray.Sort<string>(mFiles, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      // anfrage.json zuerst, dann nach Namen.
      Result := Ord(not SameText(ExtractFileName(ALeft), RequestName)) -
        Ord(not SameText(ExtractFileName(ARight), RequestName));
      if Result = 0 then
        Result := CompareText(ExtractFileName(ALeft), ExtractFileName(ARight));
    end));
  for mFile in mFiles do
  begin
    mName := ExtractFileName(mFile);
    // Ein Skript im Anhang nützt dem Empfänger nichts und wirkt verdächtig.
    if SameText(ExtractFileExt(mName), '.cmd') then
      Continue;
    try
      mText := TFile.ReadAllText(mFile, TEncoding.UTF8);
      if Length(mText) > MaxAttachChars then
        Continue;
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
    if (FItems[mIndex].Method = AMethod) and SameText(FItems[mIndex].Uri, AUri) then
      Exit(mIndex);
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
      FItems[mIndex] := ASkip
    else
      FItems.Add(ASkip);
    Result := True;
  end
  else
  begin
    Result := mIndex >= 0;
    if Result then
      FItems.Delete(mIndex);
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

end.
