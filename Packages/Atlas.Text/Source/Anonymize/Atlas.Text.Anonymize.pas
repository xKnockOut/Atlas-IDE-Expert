unit Atlas.Text.Anonymize;

// Anonymisierung für Fehlerberichte (#108), gemeinsam für Server und Plugin
// (ADR 0012), damit beide Teile eines Berichts dieselben Regeln haben:
// Pfade unter einem Arbeitsbereich werden zu <ws>…, alle anderen absoluten
// Pfade und Datei-URIs zu <pfad>, Benutzer- und Rechnername zu <benutzer>; in
// Protokollzeilen zusätzlich Text in Anführungszeichen zu <wert>.

interface

uses
  System.SysUtils;

type
  TTextAnonymizer = class
  public const
    WorkspaceLabel = '<ws>';
    PathLabel = '<pfad>';
    UserLabel = '<benutzer>';
    ValueLabel = '<wert>';
  public
    /// <summary>Pfade unter ARoots → &lt;ws&gt;…, andere absolute Pfade und Datei-URIs → &lt;pfad&gt;,
    /// AIdentity (Einträge ab drei Zeichen) → &lt;benutzer&gt;.</summary>
    class function AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>AnonymizePaths, dann Text in Anführungszeichen → &lt;wert&gt;.</summary>
    class function AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Text in "…", '…', „…“, “…”, «…», »…« → &lt;wert&gt;; ein Apostroph im Wort
    /// bleibt.</summary>
    class function ReplaceQuoted(const AText: string): string; static;
    /// <summary>Entschärft ``` in einer Zeile, die in einem Markdown-Codeblock steht.</summary>
    class function FenceSafe(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Text.Chars;

const
  // Zeichen, an denen ein Pfad im Fließtext endet.
  PathEnd: TSysCharSet = [#0..' ', '"', '''', '|', '`', '(', ')', '[', ']', '{', '}', ',', ';', '<', '>', '*', '?'];

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
  if (AIndex > 1) and (TTextChars.IsIdentChar(AText[AIndex - 1]) or CharInSet(AText[AIndex - 1], ['<', '>'])) then
    Exit;
  if (AIndex + 2 <= Length(AText)) and CharInSet(AText[AIndex], ['A'..'Z', 'a'..'z']) and
    (AText[AIndex + 1] = ':') and CharInSet(AText[AIndex + 2], ['\', '/']) then
    Stop := AIndex + 3
  else if (AIndex + 2 <= Length(AText)) and (AText[AIndex] = '\') and (AText[AIndex + 1] = '\') and
    TTextChars.IsIdentChar(AText[AIndex + 2]) then
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
        Builder.Append(TTextAnonymizer.PathLabel);
        Inc(Index, Len);
      end
      else
      begin
        Builder.Append(AText[Index]);
        Inc(Index);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TTextAnonymizer }

class function TTextAnonymizer.ReplaceQuoted(const AText: string): string;
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
        if (Index = 1) or not TTextChars.IsIdentChar(AText[Index - 1]) then
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
        Builder.Append(AText[Index]).Append(ValueLabel).Append(AText[Stop]);
        Index := Stop + 1;
      end
      else
      begin
        Builder.Append(AText[Index]);
        Inc(Index);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTextAnonymizer.AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string;
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
  // Längste Wurzel zuerst, damit verschachtelte Arbeitsbereiche vollständig gekürzt werden.
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

class function TTextAnonymizer.AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := ReplaceQuoted(AnonymizePaths(ALine, ARoots, AIdentity));
end;

class function TTextAnonymizer.FenceSafe(const AText: string): string;
begin
  Result := StringReplace(AText, '```', '` ` `', [rfReplaceAll]);
end;

end.
