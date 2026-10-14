unit Atlas.Core.Diagnostics.BugReport;

// Fehlerbericht des Plugins (#108): Teil des Plugins (Atlas-, IDE-Version,
// Plattform, Einstellungen, Auszug aus atlas.log) und davor der Bericht des
// Servers (atlas.server.bugReport mit Version, wirksamer Konfiguration,
// Protokoll und den letzten Anfragen). Quelltext steht nie darin.
// Anonymisiert (Einstellung diagnostics.bugReport.anonymize, Vorgabe an)
// werden Pfade unter einem Projektordner zu <ws>\…, alle anderen absoluten
// Pfade zu <pfad>, Benutzer- und Rechnername zu <benutzer> und im Protokoll
// Text in Anführungszeichen zu <wert>; die Regeln entsprechen denen des
// Servers (das Plugin bindet Atlas.Common nicht ein, ADR 0006).

interface

uses
  System.SysUtils;

type
  TAtlasBugReportInput = record
    PluginVersion: string;
    IdeVersion: string;
    Platform: string;
    /// <summary>Einstellungen des Plugins als JSON.</summary>
    Settings: string;
    PluginLog: TArray<string>;
    /// <summary>Text des Servers; '' wenn er nicht läuft oder nicht antwortet.</summary>
    ServerReport: string;
    /// <summary>Warum der Teil des Servers fehlt; '' wenn er da ist.</summary>
    ServerMissing: string;
    /// <summary>Projektordner für die Kürzung auf &lt;ws&gt;.</summary>
    Roots: TArray<string>;
    Identity: TArray<string>;
    Anonymize: Boolean;
    Created: TDateTime;
  end;

  TAtlasBugReport = class
  public const
    ServerCommand = 'atlas.server.bugReport';
    IssuesUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new/choose';
    /// <summary>So viele Zeilen aus atlas.log.</summary>
    LogLines = 100;
  public
    /// <summary>Angaben für den Server: [{"anonymize": …, "client": "Atlas-Plugin …, IDE …, Win32"}].</summary>
    class function ServerArguments(const AInput: TAtlasBugReportInput): string; static;
    class function Build(const AInput: TAtlasBugReportInput): string; static;
    class function AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    class function AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Die letzten ACount Zeilen einer Textdatei, die gerade beschrieben werden darf;
    /// leer ohne Datei.</summary>
    class function Tail(const AFileName: string; ACount: Integer): TArray<string>; static;
    /// <summary>Vorgeschlagener Dateiname, z. B. atlas-fehlerbericht-20261014-1530.md.</summary>
    class function DefaultFileName(ANow: TDateTime): string; static;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.IOUtils;

const
  WorkspaceLabel = '<ws>';
  PathLabel = '<pfad>';
  UserLabel = '<benutzer>';
  ValueLabel = '<wert>';

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'A'..'Z', 'a'..'z', '_']) or (Ord(C) > 127);
end;

function IsPathEnd(C: Char): Boolean;
begin
  Result := (Ord(C) <= 32) or CharInSet(C, ['"', '''', '|', '`', '(', ')', '[', ']', '{', '}', ',', ';', '<', '>',
    '*', '?']) or (C = #$201C) or (C = #$201D) or (C = #$201E) or (C = #$00AB) or (C = #$00BB);
end;

function TrimDelimiters(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
    SetLength(Result, Length(Result) - 1);
end;

function PathLengthAt(const AText: string; AIndex: Integer): Integer;
var
  Stop: Integer;
begin
  Result := 0;
  // Nicht mitten im Wort und nicht direkt hinter einer Marke wie <ws>.
  if (AIndex > 1) and (IsWordChar(AText[AIndex - 1]) or CharInSet(AText[AIndex - 1], ['<', '>'])) then
    Exit;
  if (AIndex + 2 <= Length(AText)) and CharInSet(AText[AIndex], ['A'..'Z', 'a'..'z']) and
    (AText[AIndex + 1] = ':') and CharInSet(AText[AIndex + 2], ['\', '/']) then
    Stop := AIndex + 3
  else if (AIndex + 2 <= Length(AText)) and (AText[AIndex] = '\') and (AText[AIndex + 1] = '\') and
    IsWordChar(AText[AIndex + 2]) then
    Stop := AIndex + 2
  else if SameText(Copy(AText, AIndex, 7), 'file://') then
    Stop := AIndex + 7
  else
    Exit;
  while (Stop <= Length(AText)) and not IsPathEnd(AText[Stop]) do
    Inc(Stop);
  Result := Stop - AIndex;
end;

function ReplaceAbsolutePaths(const AText: string): string;
var
  Builder: TStringBuilder;
  Index, Len: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      Len := PathLengthAt(AText, Index);
      if Len > 0 then
      begin
        Builder.Append(PathLabel);
        Inc(Index, Len);
      end
      else
      begin
        Builder.Append(Copy(AText, Index, 1));
        Inc(Index);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function ReplaceQuoted(const AText: string): string;
var
  Builder: TStringBuilder;
  Index, Stop: Integer;
  Open, Close: Char;
begin
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      Close := #0;
      Open := AText[Index];
      if Open = '"' then
        Close := '"'
      else if Open = '''' then
      begin
        // Apostroph im Wort (z. B. „don't“) ist kein Anführungszeichen.
        if (Index = 1) or not IsWordChar(AText[Index - 1]) then
          Close := '''';
      end
      else if Open = #$201E then
        Close := #$201C
      else if Open = #$201C then
        Close := #$201D
      else if Open = #$00BB then
        Close := #$00AB
      else if Open = #$00AB then
        Close := #$00BB;
      Stop := 0;
      if Close <> #0 then
      begin
        Stop := Index + 1;
        while (Stop <= Length(AText)) and (AText[Stop] <> Close) do
          Inc(Stop);
        if Stop > Length(AText) then
          Stop := 0;
      end;
      if (Stop > Index + 1) and (Copy(AText, Index + 1, 1) <> '<') then
      begin
        Builder.Append(Copy(AText, Index, 1)).Append(ValueLabel).Append(Copy(AText, Stop, 1));
        Index := Stop + 1;
      end
      else
      begin
        Builder.Append(Copy(AText, Index, 1));
        Inc(Index);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TAtlasBugReport }

class function TAtlasBugReport.AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string;
var
  Root, Slashed, Swap: string;
  Roots: TArray<string>;
  Index, Other: Integer;
begin
  Result := AText;
  Roots := nil;
  for Root in ARoots do
    if TrimDelimiters(Root) <> '' then
      Roots := Roots + [TrimDelimiters(Root)];
  // Längste Wurzel zuerst, damit verschachtelte Ordner vollständig gekürzt werden.
  for Index := 0 to High(Roots) - 1 do
    for Other := Index + 1 to High(Roots) do
      if Length(Roots[Other]) > Length(Roots[Index]) then
      begin
        Swap := Roots[Index];
        Roots[Index] := Roots[Other];
        Roots[Other] := Swap;
      end;
  for Root in Roots do
  begin
    Slashed := StringReplace(Root, '\', '/', [rfReplaceAll]);
    Result := StringReplace(Result, 'file:///' + StringReplace(Slashed, ':', '%3A', []), WorkspaceLabel,
      [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'file:///' + Slashed, WorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, Root, WorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, Slashed, WorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, StringReplace(Root, '\', '\\', [rfReplaceAll]), WorkspaceLabel,
      [rfReplaceAll, rfIgnoreCase]);
  end;
  Result := ReplaceAbsolutePaths(Result);
  for Root in AIdentity do
    if Length(Root) >= 3 then
      Result := StringReplace(Result, Root, UserLabel, [rfReplaceAll, rfIgnoreCase]);
end;

class function TAtlasBugReport.AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := ReplaceQuoted(AnonymizePaths(ALine, ARoots, AIdentity));
end;

class function TAtlasBugReport.ServerArguments(const AInput: TAtlasBugReportInput): string;
var
  Options: TJSONObject;
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Options := TJSONObject.Create;
    Arguments.AddElement(Options);
    Options.AddPair('anonymize', TJSONBool.Create(AInput.Anonymize));
    Options.AddPair('client', Format('Atlas-Plugin %s, IDE %s, %s', [AInput.PluginVersion, AInput.IdeVersion,
      AInput.Platform]));
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

class function TAtlasBugReport.Build(const AInput: TAtlasBugReportInput): string;
var
  Builder: TStringBuilder;
  Line, Text: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('# Atlas-Fehlerbericht').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Erstellt: ').Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', AInput.Created));
    if AInput.Anonymize then
      Builder.Append(' · anonymisiert');
    Builder.Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Quelltext steht nicht in diesem Bericht. Issue anlegen: ').Append(IssuesUrl);
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append('## Plugin').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('- Atlas: ').Append(AInput.PluginVersion).Append(sLineBreak);
    Builder.Append('- IDE: ').Append(AInput.IdeVersion).Append(sLineBreak);
    Builder.Append('- Plattform: ').Append(AInput.Platform).Append(sLineBreak).Append(sLineBreak);

    Builder.Append('### Einstellungen').Append(sLineBreak).Append(sLineBreak);
    Text := AInput.Settings;
    if AInput.Anonymize then
      Text := AnonymizePaths(Text, AInput.Roots, AInput.Identity);
    Builder.Append('```json').Append(sLineBreak).Append(Text.TrimRight).Append(sLineBreak).Append('```');
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append(Format('### Protokoll des Plugins (letzte %d Zeilen)', [Length(AInput.PluginLog)]));
    Builder.Append(sLineBreak).Append(sLineBreak).Append('```').Append(sLineBreak);
    for Line in AInput.PluginLog do
    begin
      Text := Line;
      if AInput.Anonymize then
        Text := AnonymizeLogLine(Text, AInput.Roots, AInput.Identity);
      Builder.Append(StringReplace(Text, '```', '` ` `', [rfReplaceAll])).Append(sLineBreak);
    end;
    Builder.Append('```').Append(sLineBreak).Append(sLineBreak);

    if AInput.ServerReport <> '' then
    begin
      // Überschriften des Servers eine Ebene tiefer, damit der Bericht eine Gliederung hat.
      Text := AInput.ServerReport;
      Text := StringReplace(Text, sLineBreak + '## ', sLineBreak + '### ', [rfReplaceAll]);
      if Text.StartsWith('# ') then
        Text := '#' + Text;
      Builder.Append(Text.TrimRight).Append(sLineBreak);
    end
    else
      Builder.Append('## Server').Append(sLineBreak).Append(sLineBreak).Append(AInput.ServerMissing)
        .Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasBugReport.Tail(const AFileName: string; ACount: Integer): TArray<string>;
var
  Stream: TFileStream;
  Lines: TStringList;
  Index, First: Integer;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
    Exit;
  Lines := TStringList.Create;
  try
    // Das Protokoll kann gerade beschrieben werden: lesend ohne Sperre öffnen.
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Lines.LoadFromStream(Stream, TEncoding.UTF8);
    finally
      Stream.Free;
    end;
    First := Lines.Count - ACount;
    if First < 0 then
      First := 0;
    SetLength(Result, Lines.Count - First);
    for Index := First to Lines.Count - 1 do
      Result[Index - First] := Lines[Index];
  finally
    Lines.Free;
  end;
end;

class function TAtlasBugReport.DefaultFileName(ANow: TDateTime): string;
begin
  Result := 'atlas-fehlerbericht-' + FormatDateTime('yyyymmdd"-"hhnn', ANow) + '.md';
end;

end.
