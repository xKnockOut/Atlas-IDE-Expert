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
    Exit;
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
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
    Start := 3;
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
    SetLength(Lines, Length(Lines) - 1);
  First := Length(Lines) - ACount;
  if First < 0 then
    First := 0;
  Result := nil;
  SetLength(Result, Length(Lines) - First);
  for Index := First to High(Lines) do
    Result[Index - First] := Lines[Index];
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

class function TAtlasDiagnosticPackage.LooksLikePath(const AValue: string): Boolean;
var
  Value: string;
begin
  Value := Trim(AValue);
  Result := False;
  if Value = '' then
    Exit;
  if Pos('\', Value) > 0 then
    Exit(True);
  if StartsText('file:', Value) then
    Exit(True);
  if Value[1] = '/' then
    Exit(True);
  // Laufwerk: „C:“ allein oder „C:/…“.
  if (Length(Value) >= 2) and CharInSet(Value[1], ['A'..'Z', 'a'..'z']) and (Value[2] = ':') and
    ((Length(Value) = 2) or CharInSet(Value[3], ['\', '/'])) then
    Exit(True);
end;

class function TAtlasDiagnosticPackage.SettingsWithoutPaths(const AJson: string): string;
var
  Builder: TStringBuilder;
  Index, Stop, Next, Code: Integer;
  Decoded: string;
  IsKey: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AJson) do
    begin
      if AJson[Index] <> '"' then
      begin
        Builder.Append(AJson[Index]);
        Inc(Index);
        Continue;
      end;
      // Zeichenkette bis zum schließenden Anführungszeichen, Escapes entschlüsselt.
      Decoded := '';
      Stop := Index + 1;
      while (Stop <= Length(AJson)) and (AJson[Stop] <> '"') do
      begin
        if (AJson[Stop] = '\') and (Stop < Length(AJson)) then
        begin
          case AJson[Stop + 1] of
            'n':
              Decoded := Decoded + #10;
            't':
              Decoded := Decoded + #9;
            'r':
              Decoded := Decoded + #13;
            'b':
              Decoded := Decoded + #8;
            'f':
              Decoded := Decoded + #12;
            'u':
              begin
                Code := StrToIntDef('$' + Copy(AJson, Stop + 2, 4), 63);
                Decoded := Decoded + Char(Code);
                Inc(Stop, 4);
              end;
          else
            Decoded := Decoded + AJson[Stop + 1];
          end;
          Inc(Stop, 2);
        end
        else
        begin
          Decoded := Decoded + AJson[Stop];
          Inc(Stop);
        end;
      end;
      // Schlüssel stehen vor einem Doppelpunkt.
      Next := Stop + 1;
      while (Next <= Length(AJson)) and CharInSet(AJson[Next], [' ', #9, #10, #13]) do
        Inc(Next);
      IsKey := (Next <= Length(AJson)) and (AJson[Next] = ':');
      if not IsKey and LooksLikePath(Decoded) then
        Builder.Append('"').Append(PathValue).Append('"')
      else
        Builder.Append(Copy(AJson, Index, Stop - Index + 1));
      Index := Stop + 1;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
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
    Files := Files + [TAtlasPackageFile.Create(InfoFileName, TAtlasPackagePart.Versions,
      Anonymize(Info(AInput), AInput.Roots, AInput.Identity))];
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
          Builder.Append(AnonymizeLog(Line, AInput.Roots, AInput.Identity)).Append(sLineBreak);
        Text := Builder.ToString;
      finally
        Builder.Free;
      end;
      Files := Files + [TAtlasPackageFile.Create(PluginFolder + '/' + ExtractFileName(AInput.PluginLog),
        TAtlasPackagePart.Logs, Text)];
    end;
    for FileName in AInput.ServerLogs do
      if FileExists(FileName) then
        Files := Files + [TAtlasPackageFile.Create(ServerFolder + '/' + ExtractFileName(FileName),
          TAtlasPackagePart.Logs, Anonymize(ReadText(FileName), AInput.Roots, AInput.Identity))];
  end;
  if (TAtlasPackagePart.LastData in AParts) and FileExists(AInput.LastDataFile) then
    Files := Files + [TAtlasPackageFile.Create(LastDataFileName, TAtlasPackagePart.LastData,
      Anonymize(ReadText(AInput.LastDataFile), AInput.Roots, AInput.Identity))];
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
    System.SysUtils.DeleteFile(ATarget);
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
    Inc(Result, Item.Size);
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
      if (Trim(Value) <> '') and (Pos(LowerCase(ExcludeTrailingPathDelimiter(Trim(Value))), Text) > 0) then
        Found := True;
    for Value in AIdentity do
      if (Length(Trim(Value)) >= 3) and (Pos(LowerCase(Trim(Value)), Text) > 0) then
        Found := True;
    if Found then
      Result := Result + [Item.Name];
  end;
end;

class function TAtlasDiagnosticPackage.IssueTemplate(const ADescription: string; const AInput: TAtlasPackageInput;
  AParts: TAtlasPackageParts; const AZipName: string; AEnglish: Boolean): string;
var
  Builder: TStringBuilder;
  Description: string;
begin
  Builder := TStringBuilder.Create;
  try
    Description := Trim(ADescription);
    if AEnglish then
    begin
      Builder.Append('## Description').Append(sLineBreak).Append(sLineBreak);
      if Description = '' then
        Description := '(What happened? What did you expect? Steps to reproduce.)';
    end
    else
    begin
      Builder.Append('## Beschreibung').Append(sLineBreak).Append(sLineBreak);
      if Description = '' then
        Description := '(Was ist passiert? Was hast du erwartet? Schritte zum Nachstellen.)';
    end;
    Builder.Append(Description).Append(sLineBreak).Append(sLineBreak);

    if AEnglish then
      Builder.Append('## Versions')
    else
      Builder.Append('## Versionen');
    Builder.Append(sLineBreak).Append(sLineBreak);
    if TAtlasPackagePart.Versions in AParts then
    begin
      Builder.Append('- Atlas: ').Append(AInput.AtlasVersion).Append(sLineBreak);
      Builder.Append('- RAD Studio: ').Append(AInput.IdeVersion).Append(', ').Append(AInput.Platform)
        .Append(sLineBreak);
      Builder.Append('- Windows: ').Append(AInput.WindowsVersion).Append(sLineBreak);
    end
    else if AEnglish then
      Builder.Append('(not included)').Append(sLineBreak)
    else
      Builder.Append('(nicht angegeben)').Append(sLineBreak);
    Builder.Append(sLineBreak);

    if AEnglish then
      Builder.Append('## Diagnostic package')
    else
      Builder.Append('## Diagnosepaket');
    Builder.Append(sLineBreak).Append(sLineBreak);
    if (AZipName <> '') and AEnglish then
      Builder.Append('`').Append(ExtractFileName(AZipName))
        .Append('` (anonymized, checked before sharing; please attach it to this issue)')
    else if AZipName <> '' then
      Builder.Append('`').Append(ExtractFileName(AZipName))
        .Append('` (anonymisiert, vor dem Weitergeben geprüft; bitte an dieses Issue anhängen)')
    else if AEnglish then
      Builder.Append('No diagnostic package created.')
    else
      Builder.Append('Kein Diagnosepaket angelegt.');
    Builder.Append(sLineBreak).Append(sLineBreak);
    if AEnglish then
      Builder.Append('_Created with Atlas › Report a problem; Atlas itself sends nothing._')
    else
      Builder.Append('_Erstellt mit Atlas › Problem melden; Atlas selbst sendet nichts._');
    Builder.Append(sLineBreak);
    Result := Anonymize(Builder.ToString, AInput.Roots, AInput.Identity);
  finally
    Builder.Free;
  end;
end;

class function TAtlasDiagnosticPackage.IsWebUrl(const AUrl: string): Boolean;
var
  Rest: string;
  Index: Integer;
begin
  Result := False;
  if StartsText('https://', AUrl) then
    Rest := Copy(AUrl, 9, MaxInt)
  else if StartsText('http://', AUrl) then
    Rest := Copy(AUrl, 8, MaxInt)
  else
    Exit;
  // Ein Host muss folgen.
  if (Rest = '') or CharInSet(Rest[1], ['/', '?', '#', ':']) then
    Exit;
  for Index := 1 to Length(AUrl) do
    if (Ord(AUrl[Index]) <= 32) or CharInSet(AUrl[Index], ['"', '<', '>', '\', '`', '^', '{', '}', '|']) then
      Exit;
  Result := True;
end;

end.
