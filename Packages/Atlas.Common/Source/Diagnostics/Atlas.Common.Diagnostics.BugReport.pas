unit Atlas.Common.Diagnostics.BugReport;

// Fehlerbericht des Servers (#108): Version, wirksame Konfiguration, Auszug
// aus dem Protokoll und die letzten Anfragen (Methode, Dauer, Ergebnis) als
// Markdown. Quelltext steht nie darin: Die Anfragen kommen aus dem Ringpuffer
// der Statistik, der keine Parameter kennt.
// Anonymisiert (Vorgabe) werden Pfade unter einem Arbeitsbereich zu
// <ws>/…, alle anderen absoluten Pfade und Datei-URIs zu <pfad>, Benutzer- und
// Rechnername zu <benutzer>; im Protokoll zusätzlich Text in Anführungszeichen
// (Bezeichner, Werte) zu <wert>.

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Statistics;

type
  TBugReportInput = record
    ServerVersion: string;
    /// <summary>Angaben des Editors, z. B. „Atlas-Plugin 0.1.0, IDE 37.0, Win32“; '' ohne.</summary>
    Client: string;
    /// <summary>Wirksame Konfiguration als formatiertes JSON.</summary>
    Configuration: string;
    LogLines: TArray<string>;
    Requests: TArray<TRecentRequest>;
    /// <summary>Wurzelordner der Arbeitsbereiche, für die Kürzung auf &lt;ws&gt;.</summary>
    Workspaces: TArray<string>;
    /// <summary>Benutzer- und Rechnername; Einträge unter drei Zeichen zählen nicht.</summary>
    Identity: TArray<string>;
    Anonymize: Boolean;
    Created: TDateTime;
  end;

  TBugReport = class
  public const
    /// <summary>Befehl des Servers; Argument optional {"anonymize": true, "client": "…", "target": "…"}.</summary>
    Command = 'atlas.server.bugReport';
    WorkspaceLabel = '<ws>';
    PathLabel = '<pfad>';
    UserLabel = '<benutzer>';
    ValueLabel = '<wert>';
  public
    class function Build(const AInput: TBugReportInput): string; static;
    /// <summary>Pfade unter AWorkspaces zu &lt;ws&gt;, übrige absolute Pfade zu &lt;pfad&gt;,
    /// AIdentity zu &lt;benutzer&gt;.</summary>
    class function AnonymizePaths(const AText: string; const AWorkspaces, AIdentity: TArray<string>): string; static;
    /// <summary>Wie AnonymizePaths, dazu Text in Anführungszeichen zu &lt;wert&gt;.</summary>
    class function AnonymizeLogLine(const ALine: string; const AWorkspaces, AIdentity: TArray<string>): string;
      static;
  end;

implementation

const
  // Zeichen, an denen ein Pfad im Fließtext endet.
  PathEnd: TSysCharSet = [#0..' ', '"', '''', '|', '`', '(', ')', '[', ']', '{', '}', ',', ';', '<', '>', '*', '?'];

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'A'..'Z', 'a'..'z', '_']) or (Ord(C) > 127);
end;

function IsPathEnd(C: Char): Boolean;
begin
  Result := CharInSet(C, PathEnd) or (C = #$201C) or (C = #$201D) or (C = #$201E) or (C = #$00AB) or
    (C = #$00BB);
end;

function TrimDelimiters(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
    SetLength(Result, Length(Result) - 1);
end;

/// <summary>Länge eines absoluten Pfads oder einer Datei-URI ab AIndex; 0, wenn dort keiner beginnt.</summary>
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
        Builder.Append(TBugReport.PathLabel);
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
        // „…“ (deutsch)
        Close := #$201C
      else if Open = #$201C then
        // “…” (englisch)
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
        Builder.Append(Copy(AText, Index, 1)).Append(TBugReport.ValueLabel).Append(Copy(AText, Stop, 1));
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

{ TBugReport }

class function TBugReport.AnonymizePaths(const AText: string; const AWorkspaces, AIdentity: TArray<string>): string;
var
  Root, Slashed: string;
  Roots: TArray<string>;
  Index, Other: Integer;
  Swap: string;
begin
  Result := AText;
  // Längste Wurzel zuerst, damit verschachtelte Arbeitsbereiche vollständig gekürzt werden.
  Roots := nil;
  for Root in AWorkspaces do
    if TrimDelimiters(Root) <> '' then
      Roots := Roots + [TrimDelimiters(Root)];
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
    // In JSON stehen Backslashes verdoppelt.
    Result := StringReplace(Result, StringReplace(Root, '\', '\\', [rfReplaceAll]), WorkspaceLabel,
      [rfReplaceAll, rfIgnoreCase]);
  end;
  Result := ReplaceAbsolutePaths(Result);
  for Root in AIdentity do
    if Length(Root) >= 3 then
      Result := StringReplace(Result, Root, UserLabel, [rfReplaceAll, rfIgnoreCase]);
end;

class function TBugReport.AnonymizeLogLine(const ALine: string; const AWorkspaces, AIdentity: TArray<string>): string;
begin
  Result := ReplaceQuoted(AnonymizePaths(ALine, AWorkspaces, AIdentity));
end;

class function TBugReport.Build(const AInput: TBugReportInput): string;
var
  Builder: TStringBuilder;
  Request: TRecentRequest;
  Line, Text: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('# Atlas-Fehlerbericht (Server)').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Erstellt: ').Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', AInput.Created));
    if AInput.Anonymize then
      Builder.Append(' · anonymisiert');
    Builder.Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Quelltext steht nicht in diesem Bericht.').Append(sLineBreak).Append(sLineBreak);

    Builder.Append('## Version').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('- Server: ').Append(AInput.ServerVersion).Append(sLineBreak);
    if AInput.Client <> '' then
      Builder.Append('- Editor: ').Append(AInput.Client).Append(sLineBreak);
    Builder.Append(sLineBreak);

    Builder.Append('## Wirksame Konfiguration').Append(sLineBreak).Append(sLineBreak);
    Text := AInput.Configuration;
    if AInput.Anonymize then
      Text := AnonymizePaths(Text, AInput.Workspaces, AInput.Identity);
    Builder.Append('```json').Append(sLineBreak).Append(Text.TrimRight).Append(sLineBreak).Append('```');
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append(Format('## Letzte Anfragen (%d)', [Length(AInput.Requests)])).Append(sLineBreak);
    Builder.Append(sLineBreak);
    if Length(AInput.Requests) = 0 then
      Builder.Append('Keine.').Append(sLineBreak)
    else
    begin
      Builder.Append('| Zeit | Methode | Dauer ms | Ergebnis |').Append(sLineBreak);
      Builder.Append('|---|---|---:|---|').Append(sLineBreak);
      for Request in AInput.Requests do
      begin
        Builder.Append('| ').Append(FormatDateTime('hh":"nn":"ss"."zzz', Request.Finished));
        Builder.Append(' | ').Append(Request.Method);
        Builder.Append(' | ').Append(Request.ElapsedMs);
        if Request.Failed then
          Builder.Append(' | Fehler |')
        else
          Builder.Append(' | ok |');
        Builder.Append(sLineBreak);
      end;
    end;
    Builder.Append(sLineBreak);

    Builder.Append(Format('## Protokoll (letzte %d Zeilen)', [Length(AInput.LogLines)])).Append(sLineBreak);
    Builder.Append(sLineBreak).Append('```').Append(sLineBreak);
    for Line in AInput.LogLines do
    begin
      Text := Line;
      if AInput.Anonymize then
        Text := AnonymizeLogLine(Text, AInput.Workspaces, AInput.Identity);
      // Mehrzeilige Einträge (z. B. Status) bleiben lesbar; ``` würde den Block schließen.
      Builder.Append(StringReplace(Text, '```', '` ` `', [rfReplaceAll])).Append(sLineBreak);
    end;
    Builder.Append('```').Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
