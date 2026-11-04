unit Atlas.Core.Diagnostics.Package;

// Diagnosepaket für „Problem melden“ (#766), ohne VCL und Open Tools API.
// Build stellt die gewählten Teile anonymisiert zusammen, genau so, wie sie in
// die ZIP-Datei kommen; die Vorschau zeigt dieselben Dateien mit Größe und
// Inhalt. Teile:
// - Logs: Ende von atlas.log des Plugins (Pfade unter einem Projekt zu <ws>,
//   andere Pfade zu <pfad>, Benutzer- und Rechnername zu <benutzer>, Text in
//   Anführungszeichen zu <wert>, wie der Fehlerbericht #108) und die
//   Diagnoselogs des Servers (#647, schon beim Schreiben anonym; zur
//   Sicherheit noch einmal über die Pfadregeln).
// - Versionen: atlas-info.txt mit Atlas, RAD Studio, Windows und Plattform.
// - Einstellungen: einstellungen.json, jeder Wert, der wie ein Pfad aussieht,
//   wird zu "<pfad>"; Benutzer- und Rechnername werden ersetzt.
// - Letzte Diagnosedaten (#479): atlas-diagnosemodus.txt, ohne Dateinamen
//   geschrieben; zur Sicherheit über die Pfadregeln.
// Die Kurzbeschreibung steht nicht in der ZIP, sondern nur in der
// Issue-Vorlage, die der Nutzer selbst in die Zwischenablage legt. Atlas
// sendet nichts; WriteZip schreibt nur die lokale Datei.

interface

uses
  System.SysUtils,
  System.Classes;

type
{$SCOPEDENUMS ON}
  TAtlasPackagePart = (Logs, Versions, Settings, LastData);
{$SCOPEDENUMS OFF}
  TAtlasPackageParts = set of TAtlasPackagePart;

  TAtlasPackageFile = record
    /// <summary>Name in der ZIP-Datei, Unterordner mit „/“ (plugin/atlas.log).</summary>
    Name: string;
    Part: TAtlasPackagePart;
    /// <summary>Anonymisierter Inhalt (UTF-8), so wie er in die ZIP kommt.</summary>
    Content: TBytes;
    function Size: Int64;
    function Text: string;
    class function Create(const AName: string; APart: TAtlasPackagePart; const AText: string): TAtlasPackageFile;
      static;
  end;

  TAtlasPackageFiles = TArray<TAtlasPackageFile>;

  TAtlasPackageInput = record
    AtlasVersion: string;
    /// <summary>RAD Studio, z. B. „Delphi 13 (37.0)“.</summary>
    IdeVersion: string;
    /// <summary>Windows-Version ohne Benutzer- oder Rechnernamen.</summary>
    WindowsVersion: string;
    Platform: string;
    /// <summary>atlas.log des Plugins; '' ohne.</summary>
    PluginLog: string;
    /// <summary>Diagnoselogs des Servers (diag-*.log, ohne Zuordnungsdatei).</summary>
    ServerLogs: TArray<string>;
    /// <summary>Einstellungen des Plugins als JSON.</summary>
    SettingsJson: string;
    /// <summary>Letzte Diagnosedaten (#479); '' ohne.</summary>
    LastDataFile: string;
    /// <summary>Projektordner für die Kürzung auf &lt;ws&gt;.</summary>
    Roots: TArray<string>;
    /// <summary>Benutzer-, Rechner- und Domänenname.</summary>
    Identity: TArray<string>;
    Created: TDateTime;
  end;

  TAtlasDiagnosticPackage = class
  public const
    InfoFileName = 'atlas-info.txt';
    SettingsFileName = 'einstellungen.json';
    LastDataFileName = 'atlas-diagnosemodus.txt';
    PluginFolder = 'plugin';
    ServerFolder = 'server';
    /// <summary>So viele Zeilen aus atlas.log.</summary>
    PluginLogLines = 2000;
    ZipPrefix = 'Atlas-Diagnose-';
    PathValue = '<pfad>';
    AllParts = [TAtlasPackagePart.Logs, TAtlasPackagePart.Versions, TAtlasPackagePart.Settings,
      TAtlasPackagePart.LastData];
  private
    class function IsDrive(const AValue: string): Boolean; static;
    /// <summary>Escape-Folge ab AIndex (Backslash) entschlüsseln; AIndex danach hinter der Folge.</summary>
    class function DecodeEscape(const AJson: string; var AIndex: Integer): string; static;
    /// <summary>Zeichenkette ab AStart (öffnendes Anführungszeichen); AStop = schließendes.</summary>
    class function DecodeString(const AJson: string; AStart: Integer; out AStop: Integer): string; static;
    /// <summary>Folgt ab AIndex nach Leerraum ein Doppelpunkt?</summary>
    class function ColonFollows(const AJson: string; AIndex: Integer): Boolean; static;
    class function Pick(AEnglish: Boolean; const AEnglishText, AGermanText: string): string; static;
    class procedure AppendVersions(ABuilder: TStringBuilder; const AInput: TAtlasPackageInput;
      AParts: TAtlasPackageParts; AEnglish: Boolean); static;
    class procedure AppendZip(ABuilder: TStringBuilder; const AZipName: string; AEnglish: Boolean); static;
  public
    /// <summary>Die Dateien der Teile AParts, anonymisiert, in fester Reihenfolge (Versionen, Einstellungen,
    /// Logs, letzte Diagnosedaten). Fehlende Quelldateien fallen weg.</summary>
    class function Build(const AInput: TAtlasPackageInput; AParts: TAtlasPackageParts): TAtlasPackageFiles; static;
    /// <summary>Inhalt von atlas-info.txt.</summary>
    class function Info(const AInput: TAtlasPackageInput): string; static;
    /// <summary>Pfade, Benutzer- und Rechnername ersetzen (Regeln des Fehlerberichts #108).</summary>
    class function Anonymize(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Wie Anonymize, dazu Text in Anführungszeichen zu &lt;wert&gt; (Protokollzeilen).</summary>
    class function AnonymizeLog(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Jeder String-Wert, der wie ein Pfad aussieht, wird zu "&lt;pfad&gt;"; Schlüssel bleiben.</summary>
    class function SettingsWithoutPaths(const AJson: string): string; static;
    /// <summary>Sieht AValue wie ein Pfad aus (Laufwerk, „\“, „/“ am Anfang, file:)?</summary>
    class function LooksLikePath(const AValue: string): Boolean; static;
    /// <summary>Atlas-Diagnose-2026-10-15.zip.</summary>
    class function ZipName(ANow: TDateTime): string; static;
    /// <summary>Freier Name in AFolder: Atlas-Diagnose-&lt;Datum&gt;.zip, sonst …-2.zip, …-3.zip.</summary>
    class function ZipTarget(const AFolder: string; ANow: TDateTime; const AExists: TFunc<string, Boolean>): string;
      static;
    /// <summary>Schreibt die Dateien in die ZIP-Datei ATarget; eine vorhandene wird ersetzt.</summary>
    class procedure WriteZip(const AFiles: TAtlasPackageFiles; const ATarget: string); static;
    /// <summary>Summe der Größen.</summary>
    class function TotalSize(const AFiles: TAtlasPackageFiles): Int64; static;
    /// <summary>Namen der Dateien, in denen noch ein Projektordner oder ein Name aus AIdentity (ab 3 Zeichen)
    /// steht; leer, wenn das Paket sauber ist.</summary>
    class function Leaks(const AFiles: TAtlasPackageFiles; const ARoots, AIdentity: TArray<string>): TArray<string>;
      static;
    /// <summary>Ausgefüllte Issue-Vorlage (Markdown): Beschreibung, Versionen (nur mit dem Teil Versionen),
    /// Hinweis auf das ZIP (nur Dateiname, ohne Ordner).</summary>
    class function IssueTemplate(const ADescription: string; const AInput: TAtlasPackageInput;
      AParts: TAtlasPackageParts; const AZipName: string; AEnglish: Boolean): string; static;
    /// <summary>Nur http:// und https:// mit Host, ohne Leer- und Steuerzeichen.</summary>
    class function IsWebUrl(const AUrl: string): Boolean; static;
    /// <summary>Datei lesen, auch wenn sie gerade beschrieben wird; leer ohne Datei.</summary>
    class function ReadShared(const AFileName: string): TBytes; static;
  end;

implementation

uses
  System.Zip,
  System.StrUtils,
  Atlas.Core.Diagnostics.BugReport;

{ TAtlasPackageFile }

function TAtlasPackageFile.Size: Int64;
begin
  Result := Length(Content);
end;

function TAtlasPackageFile.Text: string;
begin
  Result := TEncoding.UTF8.GetString(Content);
end;

class function TAtlasPackageFile.Create(const AName: string; APart: TAtlasPackagePart;
  const AText: string): TAtlasPackageFile;
begin
  Result.Name := AName;
  Result.Part := APart;
  Result.Content := TEncoding.UTF8.GetBytes(AText);
end;

{ TAtlasDiagnosticPackage }

class function TAtlasDiagnosticPackage.ReadShared(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Result := nil;
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
    begin
      Stream.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    Stream.Free;
  end;
end;

/// <summary>Text einer Datei als UTF-8 (ein BOM fällt weg).</summary>
function ReadText(const AFileName: string): string;
var
  Bytes: TBytes;
  Start: Integer;
begin
  Bytes := TAtlasDiagnosticPackage.ReadShared(AFileName);
  Start := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
  begin
    Start := 3;
  end;
  Result := TEncoding.UTF8.GetString(Bytes, Start, Length(Bytes) - Start);
end;

/// <summary>Die letzten ACount Zeilen von AText.</summary>
function LastLines(const AText: string; ACount: Integer): TArray<string>;
var
  Lines: TArray<string>;
  First, Index: Integer;
begin
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  // Zeilenumbruch am Ende: keine leere letzte Zeile.
  if (Length(Lines) > 0) and (Lines[High(Lines)] = '') then
  begin
    SetLength(Lines, Length(Lines) - 1);
  end;
  First := Length(Lines) - ACount;
  if First < 0 then
  begin
    First := 0;
  end;
  Result := nil;
  SetLength(Result, Length(Lines) - First);
  for Index := First to High(Lines) do
  begin
    Result[Index - First] := Lines[Index];
  end;
end;

class function TAtlasDiagnosticPackage.Anonymize(const AText: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := TAtlasBugReport.AnonymizePaths(AText, ARoots, AIdentity);
end;

class function TAtlasDiagnosticPackage.AnonymizeLog(const AText: string; const ARoots,
  AIdentity: TArray<string>): string;
begin
  Result := TAtlasBugReport.AnonymizeLogLine(AText, ARoots, AIdentity);
end;

class function TAtlasDiagnosticPackage.IsDrive(const AValue: string): Boolean;
begin
  // Laufwerk: „C:“ allein oder „C:/…“.
  Result := (Length(AValue) >= 2) and CharInSet(AValue[1], ['A'..'Z', 'a'..'z']) and (AValue[2] = ':');
  if Result and (Length(AValue) > 2) then
  begin
    Result := CharInSet(AValue[3], ['\', '/']);
  end;
end;

class function TAtlasDiagnosticPackage.LooksLikePath(const AValue: string): Boolean;
var
  mValue: string;
begin
  mValue := Trim(AValue);
  if mValue = '' then
  begin
    Exit(False);
  end;
  Result := (Pos('\', mValue) > 0) or StartsText('file:', mValue) or (mValue[1] = '/') or IsDrive(mValue);
end;

class function TAtlasDiagnosticPackage.DecodeEscape(const AJson: string; var AIndex: Integer): string;
begin
  // AIndex steht auf dem Backslash; danach hinter der Folge.
  case AJson[AIndex + 1] of
    'n':
      Result := #10;
    't':
      Result := #9;
    'r':
      Result := #13;
    'b':
      Result := #8;
    'f':
      Result := #12;
    'u':
      begin
        Result := Char(StrToIntDef('$' + Copy(AJson, AIndex + 2, 4), 63));
        Inc(AIndex, 4);
      end;
  else
    Result := AJson[AIndex + 1];
  end;
  Inc(AIndex, 2);
end;

class function TAtlasDiagnosticPackage.DecodeString(const AJson: string; AStart: Integer;
  out AStop: Integer): string;
begin
  // Zeichenkette bis zum schließenden Anführungszeichen, Escapes entschlüsselt; AStart steht auf dem öffnenden.
  Result := '';
  AStop := AStart + 1;
  while (AStop <= Length(AJson)) and (AJson[AStop] <> '"') do
  begin
    if (AJson[AStop] = '\') and (AStop < Length(AJson)) then
    begin
      Result := Result + DecodeEscape(AJson, AStop);
    end
    else
    begin
      Result := Result + AJson[AStop];
      Inc(AStop);
    end;
  end;
end;

class function TAtlasDiagnosticPackage.ColonFollows(const AJson: string; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := AIndex;
  while (mNext <= Length(AJson)) and CharInSet(AJson[mNext], [' ', #9, #10, #13]) do
  begin
    Inc(mNext);
  end;
  Result := (mNext <= Length(AJson)) and (AJson[mNext] = ':');
end;

class function TAtlasDiagnosticPackage.SettingsWithoutPaths(const AJson: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mStop: Integer;
  mDecoded: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AJson) do
    begin
      if AJson[mIndex] <> '"' then
      begin
        mBuilder.Append(AJson[mIndex]);
        Inc(mIndex);
        Continue;
      end;
      mDecoded := DecodeString(AJson, mIndex, mStop);
      // Schlüssel stehen vor einem Doppelpunkt.
      if not ColonFollows(AJson, mStop + 1) and LooksLikePath(mDecoded) then
      begin
        mBuilder.Append('"').Append(PathValue).Append('"');
      end
      else
      begin
        mBuilder.Append(Copy(AJson, mIndex, mStop - mIndex + 1));
      end;
      mIndex := mStop + 1;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDiagnosticPackage.Info(const AInput: TAtlasPackageInput): string;
begin
  Result := 'Atlas ' + AInput.AtlasVersion + sLineBreak +
    'RAD Studio ' + AInput.IdeVersion + sLineBreak +
    'Windows ' + AInput.WindowsVersion + sLineBreak +
    'Plattform ' + AInput.Platform + sLineBreak +
    'Erstellt ' + FormatDateTime('yyyy"-"mm"-"dd hh":"nn', AInput.Created) + sLineBreak;
end;

class function TAtlasDiagnosticPackage.Build(const AInput: TAtlasPackageInput;
  AParts: TAtlasPackageParts): TAtlasPackageFiles;
var
  Files: TAtlasPackageFiles;
  FileName, Text, Line: string;
  Builder: TStringBuilder;
begin
  Files := nil;
  if TAtlasPackagePart.Versions in AParts then
  begin
    Files := Files + [TAtlasPackageFile.Create(InfoFileName, TAtlasPackagePart.Versions,
      Anonymize(Info(AInput), AInput.Roots, AInput.Identity))];
  end;
  if TAtlasPackagePart.Settings in AParts then
  begin
    Text := Anonymize(SettingsWithoutPaths(AInput.SettingsJson), AInput.Roots, AInput.Identity);
    Files := Files + [TAtlasPackageFile.Create(SettingsFileName, TAtlasPackagePart.Settings, Text)];
  end;
  if TAtlasPackagePart.Logs in AParts then
  begin
    if FileExists(AInput.PluginLog) then
    begin
      Builder := TStringBuilder.Create;
      try
        for Line in LastLines(ReadText(AInput.PluginLog), PluginLogLines) do
        begin
          Builder.Append(AnonymizeLog(Line, AInput.Roots, AInput.Identity)).Append(sLineBreak);
        end;
        Text := Builder.ToString;
      finally
        Builder.Free;
      end;
      Files := Files + [TAtlasPackageFile.Create(PluginFolder + '/' + ExtractFileName(AInput.PluginLog),
        TAtlasPackagePart.Logs, Text)];
    end;
    for FileName in AInput.ServerLogs do
    begin
      if FileExists(FileName) then
      begin
        Files := Files + [TAtlasPackageFile.Create(ServerFolder + '/' + ExtractFileName(FileName),
          TAtlasPackagePart.Logs, Anonymize(ReadText(FileName), AInput.Roots, AInput.Identity))];
      end;
    end;
  end;
  if (TAtlasPackagePart.LastData in AParts) and FileExists(AInput.LastDataFile) then
  begin
    Files := Files + [TAtlasPackageFile.Create(LastDataFileName, TAtlasPackagePart.LastData,
      Anonymize(ReadText(AInput.LastDataFile), AInput.Roots, AInput.Identity))];
  end;
  Result := Files;
end;

class function TAtlasDiagnosticPackage.ZipName(ANow: TDateTime): string;
begin
  Result := ZipPrefix + FormatDateTime('yyyy"-"mm"-"dd', ANow) + '.zip';
end;

class function TAtlasDiagnosticPackage.ZipTarget(const AFolder: string; ANow: TDateTime;
  const AExists: TFunc<string, Boolean>): string;
var
  Folder: string;
  Number: Integer;
begin
  Folder := IncludeTrailingPathDelimiter(AFolder);
  Result := Folder + ZipName(ANow);
  Number := 2;
  while Assigned(AExists) and AExists(Result) do
  begin
    Result := Folder + ZipPrefix + FormatDateTime('yyyy"-"mm"-"dd', ANow) + '-' + IntToStr(Number) + '.zip';
    Inc(Number);
  end;
end;

class procedure TAtlasDiagnosticPackage.WriteZip(const AFiles: TAtlasPackageFiles; const ATarget: string);
var
  Zip: TZipFile;
  Item: TAtlasPackageFile;
  Content: TBytesStream;
begin
  if FileExists(ATarget) then
  begin
    System.SysUtils.DeleteFile(ATarget);
  end;
  Zip := TZipFile.Create;
  try
    Zip.Open(ATarget, TZipMode.zmWrite);
    for Item in AFiles do
    begin
      Content := TBytesStream.Create(Item.Content);
      try
        Zip.Add(Content, Item.Name);
      finally
        Content.Free;
      end;
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

class function TAtlasDiagnosticPackage.TotalSize(const AFiles: TAtlasPackageFiles): Int64;
var
  Item: TAtlasPackageFile;
begin
  Result := 0;
  for Item in AFiles do
  begin
    Inc(Result, Item.Size);
  end;
end;

class function TAtlasDiagnosticPackage.Leaks(const AFiles: TAtlasPackageFiles; const ARoots,
  AIdentity: TArray<string>): TArray<string>;
var
  Item: TAtlasPackageFile;
  Text, Value: string;
  Found: Boolean;
begin
  Result := nil;
  for Item in AFiles do
  begin
    Text := LowerCase(Item.Text);
    Found := False;
    for Value in ARoots do
    begin
      if (Trim(Value) <> '') and (Pos(LowerCase(ExcludeTrailingPathDelimiter(Trim(Value))), Text) > 0) then
      begin
        Found := True;
      end;
    end;
    for Value in AIdentity do
    begin
      if (Length(Trim(Value)) >= 3) and (Pos(LowerCase(Trim(Value)), Text) > 0) then
      begin
        Found := True;
      end;
    end;
    if Found then
    begin
      Result := Result + [Item.Name];
    end;
  end;
end;

class function TAtlasDiagnosticPackage.Pick(AEnglish: Boolean; const AEnglishText, AGermanText: string): string;
begin
  if AEnglish then
  begin
    Result := AEnglishText;
  end
  else
  begin
    Result := AGermanText;
  end;
end;

class procedure TAtlasDiagnosticPackage.AppendVersions(ABuilder: TStringBuilder; const AInput: TAtlasPackageInput;
  AParts: TAtlasPackageParts; AEnglish: Boolean);
begin
  ABuilder.Append(Pick(AEnglish, '## Versions', '## Versionen'));
  ABuilder.Append(sLineBreak).Append(sLineBreak);
  if TAtlasPackagePart.Versions in AParts then
  begin
    ABuilder.Append('- Atlas: ').Append(AInput.AtlasVersion).Append(sLineBreak);
    ABuilder.Append('- RAD Studio: ').Append(AInput.IdeVersion).Append(', ').Append(AInput.Platform)
      .Append(sLineBreak);
    ABuilder.Append('- Windows: ').Append(AInput.WindowsVersion).Append(sLineBreak);
  end
  else
  begin
    ABuilder.Append(Pick(AEnglish, '(not included)', '(nicht angegeben)')).Append(sLineBreak);
  end;
  ABuilder.Append(sLineBreak);
end;

class procedure TAtlasDiagnosticPackage.AppendZip(ABuilder: TStringBuilder; const AZipName: string;
  AEnglish: Boolean);
begin
  ABuilder.Append(Pick(AEnglish, '## Diagnostic package', '## Diagnosepaket'));
  ABuilder.Append(sLineBreak).Append(sLineBreak);
  if AZipName <> '' then
  begin
    ABuilder.Append('`').Append(ExtractFileName(AZipName)).Append(Pick(AEnglish,
      '` (anonymized, checked before sharing; please attach it to this issue)',
      '` (anonymisiert, vor dem Weitergeben geprüft; bitte an dieses Issue anhängen)'));
  end
  else
  begin
    ABuilder.Append(Pick(AEnglish, 'No diagnostic package created.', 'Kein Diagnosepaket angelegt.'));
  end;
  ABuilder.Append(sLineBreak).Append(sLineBreak);
end;

class function TAtlasDiagnosticPackage.IssueTemplate(const ADescription: string; const AInput: TAtlasPackageInput;
  AParts: TAtlasPackageParts; const AZipName: string; AEnglish: Boolean): string;
var
  mBuilder: TStringBuilder;
  mDescription: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(Pick(AEnglish, '## Description', '## Beschreibung')).Append(sLineBreak).Append(sLineBreak);
    mDescription := Trim(ADescription);
    if mDescription = '' then
    begin
      mDescription := Pick(AEnglish, '(What happened? What did you expect? Steps to reproduce.)',
        '(Was ist passiert? Was hast du erwartet? Schritte zum Nachstellen.)');
    end;
    mBuilder.Append(mDescription).Append(sLineBreak).Append(sLineBreak);
    AppendVersions(mBuilder, AInput, AParts, AEnglish);
    AppendZip(mBuilder, AZipName, AEnglish);
    mBuilder.Append(Pick(AEnglish, '_Created with Atlas › Report a problem; Atlas itself sends nothing._',
      '_Erstellt mit Atlas › Problem melden; Atlas selbst sendet nichts._'));
    mBuilder.Append(sLineBreak);
    Result := Anonymize(mBuilder.ToString, AInput.Roots, AInput.Identity);
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDiagnosticPackage.IsWebUrl(const AUrl: string): Boolean;
var
  Rest: string;
  Index: Integer;
begin
  Result := False;
  if StartsText('https://', AUrl) then
  begin
    Rest := Copy(AUrl, 9, MaxInt);
  end
  else if StartsText('http://', AUrl) then
  begin
    Rest := Copy(AUrl, 8, MaxInt);
  end
  else
  begin
    Exit;
  end;
  // Ein Host muss folgen.
  if (Rest = '') or CharInSet(Rest[1], ['/', '?', '#', ':']) then
  begin
    Exit;
  end;
  for Index := 1 to Length(AUrl) do
  begin
    if (Ord(AUrl[Index]) <= 32) or CharInSet(AUrl[Index], ['"', '<', '>', '\', '`', '^', '{', '}', '|']) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

end.
