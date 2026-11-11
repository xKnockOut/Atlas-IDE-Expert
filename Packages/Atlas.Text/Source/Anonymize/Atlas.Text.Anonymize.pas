unit Atlas.Text.Anonymize;

// Anonymisierung für Fehlerberichte (#108), gemeinsam für Server und Plugin
//, damit beide Teile eines Berichts dieselben Regeln haben:
// - Gekennzeichnete Werte (Atlas.Text.LogMarks, #1478): Name zu <name>, Text
//   zu <text>, Pfad wie unten bzw. ohne erkennbaren Ort zu <datei> mit Endung.
// - Pfade unter einem Arbeitsbereich werden zu <ws>/<datei> mit der Endung
//   (bis #1478 blieben Unterordner und Dateiname stehen), alle anderen
//   absoluten Pfade und Datei-URIs zu <pfad>.
// - Benutzer- und Rechnername zu <benutzer>; in Protokollzeilen zusätzlich
//   Text in Anführungszeichen zu <wert>.
// - Einstellungen als JSON (AnonymizeJsonValues, #1478): Schlüssel, Zahlen und
//   Wahrheitswerte bleiben, Textwerte nur, wenn sie wie ein Schlüsselwort
//   aussehen (Regelkennung, Stufe, Aufzählungswert wie "warning" oder
//   "unused-unit", Standardkonfiguration und -plattform); Unit-Namen, Muster,
//   Adressen und Pfade werden <wert>.

interface

uses
  System.SysUtils;

type
  TTextAnonymizer = class
  public const
    cWorkspaceLabel = '<ws>';
    cPathLabel = '<pfad>';
    cUserLabel = '<benutzer>';
    cValueLabel = '<wert>';
    /// <summary>Gekennzeichneter Name (TLogMarks.Name).</summary>
    cNameLabel = '<name>';
    /// <summary>Gekennzeichneter fremder Text (TLogMarks.Text).</summary>
    cTextLabel = '<text>';
    /// <summary>Datei unter einem Arbeitsbereich oder gekennzeichneter Dateiname, gefolgt von der Endung.</summary>
    cFileLabel = '<datei>';
  public
    /// <summary>Gekennzeichnete Werte (TLogMarks) ersetzen: Name → &lt;name&gt;, Text → &lt;text&gt;, Pfad wie
    /// AnonymizePaths bzw. &lt;datei&gt; mit Endung; der übrige Text bleibt.</summary>
    class function RedactMarks(const AText: string; const ARoots: TArray<string>): string; static;
    /// <summary>Gekennzeichnete Werte wie RedactMarks, Pfade unter ARoots → &lt;ws&gt;/&lt;datei&gt; mit Endung,
    /// andere absolute Pfade und Datei-URIs → &lt;pfad&gt;, AIdentity (Einträge ab drei Zeichen) →
    /// &lt;benutzer&gt;.</summary>
    class function AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>AnonymizePaths, dann Text in Anführungszeichen → &lt;wert&gt;.</summary>
    class function AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Text in "…", '…', „…“, “…”, «…», »…« → &lt;wert&gt;; ein Apostroph im Wort
    /// bleibt.</summary>
    class function ReplaceQuoted(const AText: string): string; static;
    /// <summary>Entschärft ``` in einer Zeile, die in einem Markdown-Codeblock steht.</summary>
    class function FenceSafe(const AText: string): string; static;
    /// <summary>Textwerte in AJson, die kein Schlüsselwort sind (IsKeyword), zu &lt;wert&gt;; Schlüssel, Zahlen und
    /// Wahrheitswerte bleiben. Ergebnis eingerückt mit zwei Leerzeichen; ungültiges JSON wird '{}'.</summary>
    class function AnonymizeJsonValues(const AJson: string): string; static;
    /// <summary>Sieht AValue wie ein fester Wert einer Einstellung aus: klein geschriebenes Wort mit „-“, „_“ oder
    /// „.“ (warning, unused-unit, editor.fontSize), Zahl oder Version, Debug, Release, eine Delphi-Plattform oder
    /// ein schon ersetzter Wert wie &lt;pfad&gt;?</summary>
    class function IsKeyword(const AValue: string): Boolean; static;
    /// <summary>Endung von AName mit Punkt, wenn sie wie eine Dateiendung aussieht (1 bis 8 Buchstaben oder
    /// Ziffern); sonst ''.</summary>
    class function FileExtension(const AName: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Chars,
  Atlas.Text.LogMarks;

const
  // Feste Werte mit Großbuchstaben, die in Einstellungen vorkommen und nichts verraten.
  cKeywords: array[0..10] of string = ('Debug', 'Release', 'Win32', 'Win64', 'Win64x', 'Linux64', 'OSX64',
    'OSXARM64', 'Android', 'Android64', 'iOSDevice64');

const
  // Zeichen, an denen ein Pfad im Fließtext endet.
  cPathEnd: TSysCharSet = [#0..' ', '"', '''', '|', '`', '(', ')', '[', ']', '{', '}', ',', ';', '<', '>', '*', '?'];

function IsPathEnd(AC: Char): Boolean;
begin
  Result := CharInSet(AC, cPathEnd) or (AC = #$201C) or (AC = #$201D) or (AC = #$201E) or (AC = #$00AB) or
    (AC = #$00BB);
end;

function TrimDelimiters(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

/// <summary>Länge eines absoluten Pfads oder einer Datei-URI ab AIndex; 0, wenn dort keiner beginnt.</summary>
function PathLengthAt(const AText: string; AIndex: Integer): Integer;
var
  mStop: Integer;
begin
  Result := 0;
  // Nicht mitten im Wort und nicht direkt hinter einer Marke wie <ws>.
  if (AIndex > 1) and (TTextChars.IsIdentChar(AText[AIndex - 1]) or CharInSet(AText[AIndex - 1], ['<', '>'])) then
  begin
    Exit;
  end;
  if (AIndex + 2 <= Length(AText)) and CharInSet(AText[AIndex], ['A'..'Z', 'a'..'z']) and
    (AText[AIndex + 1] = ':') and CharInSet(AText[AIndex + 2], ['\', '/']) then
  begin
    mStop := AIndex + 3;
  end
  else if (AIndex + 2 <= Length(AText)) and (AText[AIndex] = '\') and (AText[AIndex + 1] = '\') and
    TTextChars.IsIdentChar(AText[AIndex + 2]) then
  begin
    mStop := AIndex + 2;
  end
  else if SameText(Copy(AText, AIndex, 7), 'file://') then
  begin
    mStop := AIndex + 7;
  end
  else
  begin
    Exit;
  end;
  while (mStop <= Length(AText)) and not IsPathEnd(AText[mStop]) do
  begin
    Inc(mStop);
  end;
  Result := mStop - AIndex;
end;

function ReplaceAbsolutePaths(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mLen: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mLen := PathLengthAt(AText, mIndex);
      if mLen > 0 then
      begin
        mBuilder.Append(TTextAnonymizer.cPathLabel);
        Inc(mIndex, mLen);
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TTextAnonymizer }

// Schließendes Anführungszeichen zu AText[AIndex]; #0, wenn dort keins beginnt.
function ClosingQuote(const AText: string; AIndex: Integer): Char;
begin
  case AText[AIndex] of
    '"':
      Result := '"';
    '''':
      begin
        // Apostroph im Wort (z. B. „don't“) ist kein Anführungszeichen.
        Result := #0;
        if (AIndex = 1) or not TTextChars.IsIdentChar(AText[AIndex - 1]) then
        begin
          Result := '''';
        end;
      end;
    // „…“ (deutsch)
    #$201E:
      Result := #$201C;
    // “…” (englisch)
    #$201C:
      Result := #$201D;
    #$00BB:
      Result := #$00AB;
    #$00AB:
      Result := #$00BB;
  else
    Result := #0;
  end;
end;

// Stelle des schließenden Anführungszeichens zu dem bei AIndex; 0 ohne.
function QuoteEnd(const AText: string; AIndex: Integer): Integer;
var
  mClose: Char;
begin
  mClose := ClosingQuote(AText, AIndex);
  if mClose = #0 then
  begin
    Exit(0);
  end;
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (AText[Result] <> mClose) do
  begin
    Inc(Result);
  end;
  if Result > Length(AText) then
  begin
    Result := 0;
  end;
end;

class function TTextAnonymizer.ReplaceQuoted(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mStop: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mStop := QuoteEnd(AText, mIndex);
      if (mStop > mIndex + 1) and (Copy(AText, mIndex + 1, 1) <> '<') then
      begin
        mBuilder.Append(AText[mIndex]).Append(cValueLabel).Append(AText[mStop]);
        mIndex := mStop + 1;
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Endung von AName mit Punkt, wenn sie wie eine Dateiendung aussieht (1 bis 8 Buchstaben oder Ziffern);
/// sonst ''.</summary>
function FileExtensionOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := ExtractFileExt(StringReplace(AName, '/', '\', [rfReplaceAll]));
  if (Length(Result) < 2) or (Length(Result) > 9) then
  begin
    Exit('');
  end;
  for mIndex := 2 to Length(Result) do
  begin
    if not CharInSet(Result[mIndex], ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      Exit('');
    end;
  end;
end;

/// <summary>Hinter jeder Marke &lt;ws&gt; den Rest des Pfads (Unterordner, Dateiname) durch /&lt;datei&gt; mit
/// Endung ersetzen.</summary>
function HideWorkspaceRest(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mStop, mLabel: Integer;
begin
  mLabel := Length(TTextAnonymizer.cWorkspaceLabel);
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if (Copy(AText, mIndex, mLabel) = TTextAnonymizer.cWorkspaceLabel) and (mIndex + mLabel <= Length(AText)) and
        CharInSet(AText[mIndex + mLabel], ['\', '/']) then
      begin
        mStop := mIndex + mLabel;
        while (mStop <= Length(AText)) and not IsPathEnd(AText[mStop]) do
        begin
          Inc(mStop);
        end;
        mBuilder.Append(TTextAnonymizer.cWorkspaceLabel).Append('/').Append(TTextAnonymizer.cFileLabel)
          .Append(FileExtensionOf(Copy(AText, mIndex + mLabel, mStop - mIndex - mLabel)));
        mIndex := mStop;
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Wurzeln ohne leere Einträge und Schlussstriche, die längste zuerst.</summary>
function SortedRoots(const ARoots: TArray<string>): TArray<string>;
var
  mRoot, mSwap: string;
  mIndex, mOther: Integer;
begin
  Result := nil;
  for mRoot in ARoots do
  begin
    if TrimDelimiters(mRoot) <> '' then
    begin
      Result := Result + [TrimDelimiters(mRoot)];
    end;
  end;
  // Längste Wurzel zuerst, damit verschachtelte Arbeitsbereiche vollständig gekürzt werden.
  for mIndex := 0 to High(Result) - 1 do
  begin
    for mOther := mIndex + 1 to High(Result) do
    begin
      if Length(Result[mOther]) > Length(Result[mIndex]) then
      begin
        mSwap := Result[mIndex];
        Result[mIndex] := Result[mOther];
        Result[mOther] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Pfade unter ARoots → &lt;ws&gt;/&lt;datei&gt;, andere absolute Pfade → &lt;pfad&gt;.</summary>
function ReplacePaths(const AText: string; const ARoots: TArray<string>): string;
var
  mRoot, mSlashed: string;
begin
  Result := AText;
  for mRoot in SortedRoots(ARoots) do
  begin
    mSlashed := StringReplace(mRoot, '\', '/', [rfReplaceAll]);
    Result := StringReplace(Result, 'file:///' + StringReplace(mSlashed, ':', '%3A', []),
      TTextAnonymizer.cWorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'file:///' + mSlashed, TTextAnonymizer.cWorkspaceLabel,
      [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, mRoot, TTextAnonymizer.cWorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, mSlashed, TTextAnonymizer.cWorkspaceLabel, [rfReplaceAll, rfIgnoreCase]);
    // In JSON stehen Backslashes verdoppelt.
    Result := StringReplace(Result, StringReplace(mRoot, '\', '\\', [rfReplaceAll]), TTextAnonymizer.cWorkspaceLabel,
      [rfReplaceAll, rfIgnoreCase]);
  end;
  Result := ReplaceAbsolutePaths(HideWorkspaceRest(Result));
end;

/// <summary>Gekennzeichneter Pfad: wie ReplacePaths; ohne erkennbaren Ort (Dateiname, relativer Pfad) &lt;datei&gt;
/// mit Endung.</summary>
function MarkedPath(const AValue: string; const ARoots: TArray<string>): string;
begin
  Result := ReplacePaths(AValue, ARoots);
  if (Pos(TTextAnonymizer.cWorkspaceLabel, Result) = 0) and (Pos(TTextAnonymizer.cPathLabel, Result) = 0) then
  begin
    Result := TTextAnonymizer.cFileLabel + FileExtensionOf(AValue);
  end;
end;

class function TTextAnonymizer.RedactMarks(const AText: string; const ARoots: TArray<string>): string;
var
  mRoots: TArray<string>;
begin
  mRoots := ARoots;
  Result := TLogMarks.Resolve(AText,
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      case AKind of
        TLogMarkKind.Name:
          Result := cNameLabel;
        TLogMarkKind.Path:
          Result := MarkedPath(AValue, mRoots);
      else
        Result := cTextLabel;
      end;
    end);
end;

class function TTextAnonymizer.AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string;
var
  mName: string;
begin
  Result := ReplacePaths(RedactMarks(AText, ARoots), ARoots);
  for mName in AIdentity do
  begin
    if Length(mName) >= 3 then
    begin
      Result := StringReplace(Result, mName, cUserLabel, [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
end;

class function TTextAnonymizer.AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := ReplaceQuoted(AnonymizePaths(ALine, ARoots, AIdentity));
end;

class function TTextAnonymizer.FenceSafe(const AText: string): string;
begin
  Result := StringReplace(AText, '```', '` ` `', [rfReplaceAll]);
end;

/// <summary>Klein geschriebenes Wort aus a-z und 0-9, Teile getrennt durch „-“, „_“ oder „.“.</summary>
function IsLowerWord(const AValue: string): Boolean;
var
  mIndex: Integer;
  mSeparator: Boolean;
begin
  Result := (AValue <> '') and CharInSet(AValue[1], ['a'..'z']) and
    not CharInSet(AValue[Length(AValue)], ['-', '_', '.']);
  mSeparator := False;
  mIndex := 2;
  while Result and (mIndex <= Length(AValue)) do
  begin
    if CharInSet(AValue[mIndex], ['-', '_', '.']) then
    begin
      Result := not mSeparator;
      mSeparator := True;
    end
    else
    begin
      Result := CharInSet(AValue[mIndex], ['a'..'z', '0'..'9']);
      mSeparator := False;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Zahl oder Version aus Ziffern und Punkten.</summary>
function IsVersion(const AValue: string): Boolean;
var
  mChar: Char;
begin
  Result := AValue <> '';
  for mChar in AValue do
  begin
    if not CharInSet(mChar, ['0'..'9', '.']) then
    begin
      Exit(False);
    end;
  end;
end;

class function TTextAnonymizer.FileExtension(const AName: string): string;
begin
  Result := FileExtensionOf(AName);
end;

/// <summary>Schon ersetzter Wert wie &lt;pfad&gt; oder &lt;wert&gt;.</summary>
function IsPlaceholder(const AValue: string): Boolean;
begin
  Result := (Length(AValue) > 2) and (AValue[1] = '<') and (AValue[Length(AValue)] = '>') and
    IsLowerWord(Copy(AValue, 2, Length(AValue) - 2));
end;

class function TTextAnonymizer.IsKeyword(const AValue: string): Boolean;
begin
  Result := (AValue = '') or IsLowerWord(AValue) or IsVersion(AValue) or MatchStr(AValue, cKeywords) or
    IsPlaceholder(AValue);
end;

/// <summary>Text, aber keine Zahl: TJSONNumber erbt von TJSONString.</summary>
function IsJsonText(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

/// <summary>Kopie von AValue mit &lt;wert&gt; statt jedem Text, der kein Schlüsselwort ist.</summary>
function ScrubbedJson(AValue: TJSONValue): TJSONValue;
var
  mPair: TJSONPair;
  mItem: TJSONValue;
  mObject: TJSONObject;
  mArray: TJSONArray;
begin
  if AValue is TJSONObject then
  begin
    mObject := TJSONObject.Create;
    for mPair in TJSONObject(AValue) do
    begin
      mObject.AddPair(mPair.JsonString.Value, ScrubbedJson(mPair.JsonValue));
    end;
    Exit(mObject);
  end;
  if AValue is TJSONArray then
  begin
    mArray := TJSONArray.Create;
    for mItem in TJSONArray(AValue) do
    begin
      mArray.AddElement(ScrubbedJson(mItem));
    end;
    Exit(mArray);
  end;
  if IsJsonText(AValue) and not TTextAnonymizer.IsKeyword(AValue.Value) then
  begin
    Exit(TJSONString.Create(TTextAnonymizer.cValueLabel));
  end;
  Result := TJSONValue(AValue.Clone);
end;

class function TTextAnonymizer.AnonymizeJsonValues(const AJson: string): string;
var
  mValue, mScrubbed: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue = nil then
  begin
    Exit('{}');
  end;
  try
    mScrubbed := ScrubbedJson(mValue);
    try
      Result := mScrubbed.Format(2);
    finally
      mScrubbed.Free;
    end;
  finally
    mValue.Free;
  end;
end;

end.
