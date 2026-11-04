unit Atlas.Core.Debug.Note;

// Debug-Notiz als Markdown (#582, genutzt von „An Issue anhängen“ #1276), ohne
// VCL und Open Tools API. Die IDE-Schicht sammelt den Zustand des Halts
// (TAtlasDebugNoteData); hier entsteht daraus der Text:
//   # Debug-Notiz
//   Projekt, Konfiguration, Plattform, Zeit, Thread
//   ## Ort – Datei:Zeile, Routine, Codeausschnitt (±ContextLines) mit Marke
//   ## Aufrufstapel – eigener Code (#578) fett
//   ## Letzte Exception (#517) – Klasse, Meldung, Ort, Anzahl
// Werte, die wie Geheimnisse aussehen (Name enthält Password, Passwort, Pwd,
// Secret, Token, ApiKey, Credential), erscheinen als ***: in den
// Codezeilen und in der Meldung der Exception (Redact).
// Die Überschriften kommen in der Sprache der Oberfläche von außen
// (TAtlasDebugNoteTexts), Core kennt Atlas.UI.Strings nicht.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions;

type
  TAtlasDebugNoteTexts = record
    Title: string;
    Project: string;
    Configuration: string;
    TargetPlatform: string;
    Time: string;
    Thread: string;
    Location: string;
    CallStack: string;
    LastException: string;
    /// <summary>„%d x an dieser Stelle“.</summary>
    Count: string;
    /// <summary>„Kein Halt mit Quelltext.“</summary>
    NoLocation: string;
    /// <summary>Deutsche Vorgaben (Tests, Rückfall).</summary>
    class function Default: TAtlasDebugNoteTexts; static;
  end;

  TAtlasDebugNoteData = record
    Project: string;
    Configuration: string;
    TargetPlatform: string;
    /// <summary>Ortszeit des Halts.</summary>
    Time: TDateTime;
    /// <summary>„Hauptthread 1234“ bzw. „Name (1234)“; '' = unbekannt.</summary>
    Thread: string;
    /// <summary>Ort des Halts; '' ohne Quelltext.</summary>
    FileName: string;
    Line: Integer;
    Routine: string;
    /// <summary>Zeilen der Datei (oder ein Ausschnitt ab SourceFirstLine); leer = ohne Ausschnitt.</summary>
    Source: TArray<string>;
    /// <summary>Zeilennummer von Source[0], 1-basiert.</summary>
    SourceFirstLine: Integer;
    Frames: TAtlasDebugFrames;
    HasException: Boolean;
    Exception: TAtlasDebugException;
    class function Empty: TAtlasDebugNoteData; static;
  end;

  TAtlasDebugNote = record
  public const
    ContextLines = 5;
    MaxFrames = 30;
    /// <summary>Längere Codezeilen bzw. Meldungen werden gekürzt.</summary>
    MaxLineLength = 300;
    Mask = '***';
  public
    /// <summary>Notiz als Markdown.</summary>
    class function Markdown(const AData: TAtlasDebugNoteData; const ATexts: TAtlasDebugNoteTexts): string; static;
    /// <summary>Zeilen ALine ± AContext aus ALines (ab AFirstLine nummeriert); AStart ist die Nummer der ersten.
    /// </summary>
    class function Excerpt(const ALines: TArray<string>; AFirstLine, ALine, AContext: Integer;
      out AStart: Integer): TArray<string>; static;
    /// <summary>Name sieht nach einem Geheimnis aus (Password, Passwort, Pwd, Secret, Token, ApiKey, Credential).
    /// </summary>
    class function IsSecretName(const AName: string): Boolean; static;
    /// <summary>Werte hinter geheimen Namen („Password := 'x'“, „Token=abc“, „ApiKey: 123“) werden ***; für
    /// Meldungen und Protokolltext.</summary>
    class function Redact(const AText: string): string; static;
    /// <summary>Wie Redact für eine Zeile Pascal: nur nach „:=“ und „=“, denn „Password: string“ ist eine
    /// Deklaration und kein Wert.</summary>
    class function RedactCode(const ALine: string): string; static;
    /// <summary>„debug-notiz-JJJJ-MM-TT-hhmm.md“.</summary>
    class function FileName(ATime: TDateTime): string; static;
    /// <summary>Exception-Verlauf als Text zum Anhängen: höchstens AMax Einträge (in der Reihenfolge von
    /// AExceptions) wie „Kopieren“ im Fenster, durch Leerzeilen getrennt, Geheimnisse ausgeblendet.</summary>
    class function HistoryText(const AExceptions: TAtlasDebugExceptions; AMax: Integer): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Text.Anonymize;

const
  SecretWords: array[0..7] of string = ('password', 'passwort', 'passwd', 'pwd', 'secret', 'token', 'apikey',
    'credential');

{ TAtlasDebugNoteTexts }

class function TAtlasDebugNoteTexts.Default: TAtlasDebugNoteTexts;
begin
  Result.Title := 'Debug-Notiz';
  Result.Project := 'Projekt';
  Result.Configuration := 'Konfiguration';
  Result.TargetPlatform := 'Plattform';
  Result.Time := 'Zeit';
  Result.Thread := 'Thread';
  Result.Location := 'Ort';
  Result.CallStack := 'Aufrufstapel';
  Result.LastException := 'Letzte Exception';
  Result.Count := '%d x an dieser Stelle';
  Result.NoLocation := 'Kein Halt mit Quelltext.';
end;

{ TAtlasDebugNoteData }

class function TAtlasDebugNoteData.Empty: TAtlasDebugNoteData;
begin
  Result := Default(TAtlasDebugNoteData);
  Result.Source := nil;
  Result.Frames := nil;
end;

{ TAtlasDebugNote }

class function TAtlasDebugNote.IsSecretName(const AName: string): Boolean;
var
  mName, mWord: string;
begin
  mName := LowerCase(StringReplace(StringReplace(AName, '_', '', [rfReplaceAll]), '-', '', [rfReplaceAll]));
  for mWord in SecretWords do
  begin
    if Pos(mWord, mName) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsNameChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']);
end;

/// <summary>Erste Stelle ab AFrom, die kein Leerzeichen ist.</summary>
function SkipSpaces(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(AText)) and (AText[Result] = ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erste Stelle ab AFrom, die nicht zu einem Namen gehört.</summary>
function NameEnd(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(AText)) and IsNameChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Beginn des Werts nach einem Namen, der bei AFrom endet: nach „:=“, „=“ oder (AColon) „:“ und
/// Leerraum; 0 ohne Zuweisung. Länge + 1, wenn nach der Zuweisung nichts mehr folgt.</summary>
function ValueStart(const AText: string; AFrom: Integer; AColon: Boolean): Integer;
var
  mPos: Integer;
begin
  Result := 0;
  mPos := SkipSpaces(AText, AFrom);
  if (mPos < Length(AText)) and (AText[mPos] = ':') and (AText[mPos + 1] = '=') then
  begin
    Result := SkipSpaces(AText, mPos + 2);
  end
  else if (mPos <= Length(AText)) and ((AText[mPos] = '=') or (AColon and (AText[mPos] = ':'))) then
  begin
    Result := SkipSpaces(AText, mPos + 1);
  end;
end;

/// <summary>Ende (exklusiv) des Werts ab AStart: in Hochkommas bzw. Anführungszeichen bis zum schließenden,
/// sonst bis Leerraum, „;“, „,“ oder „)“.</summary>
function ValueEnd(const AText: string; AStart: Integer): Integer;
var
  mQuote: Char;
begin
  Result := AStart;
  if not CharInSet(AText[AStart], ['''', '"']) then
  begin
    while (Result <= Length(AText)) and not CharInSet(AText[Result], [' ', #9, ';', ',', ')', #13, #10]) do
    begin
      Inc(Result);
    end;
    Exit;
  end;
  mQuote := AText[AStart];
  Result := AStart + 1;
  while (Result <= Length(AText)) and (AText[Result] <> mQuote) do
  begin
    Inc(Result);
  end;
  if Result <= Length(AText) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Redact bzw. RedactCode (AColon: auch „Name: Wert“).</summary>
function Masked(const AText: string; AColon: Boolean): string;
var
  mIndex, mNameStart, mValueStart, mValueEnd: Integer;
begin
  Result := AText;
  mIndex := 1;
  while mIndex <= Length(Result) do
  begin
    if not IsNameChar(Result[mIndex]) then
    begin
      Inc(mIndex);
      Continue;
    end;
    // Ein Name, gefolgt von „:=“, „=“ oder „:“ (mit Leerraum).
    mNameStart := mIndex;
    mIndex := NameEnd(Result, mIndex);
    if not TAtlasDebugNote.IsSecretName(Copy(Result, mNameStart, mIndex - mNameStart)) then
    begin
      Continue;
    end;
    mValueStart := ValueStart(Result, mIndex, AColon);
    if mValueStart = 0 then
    begin
      Continue;
    end;
    if mValueStart > Length(Result) then
    begin
      Break;
    end;
    mValueEnd := ValueEnd(Result, mValueStart);
    if mValueEnd = mValueStart then
    begin
      Continue;
    end;
    Result := Copy(Result, 1, mValueStart - 1) + TAtlasDebugNote.Mask + Copy(Result, mValueEnd, MaxInt);
    mIndex := mValueStart + Length(TAtlasDebugNote.Mask);
  end;
end;

class function TAtlasDebugNote.Redact(const AText: string): string;
begin
  Result := Masked(AText, True);
end;

class function TAtlasDebugNote.RedactCode(const ALine: string): string;
begin
  Result := Masked(ALine, False);
end;

class function TAtlasDebugNote.Excerpt(const ALines: TArray<string>; AFirstLine, ALine, AContext: Integer;
  out AStart: Integer): TArray<string>;
var
  mFrom, mTo: Integer;
begin
  Result := nil;
  AStart := 0;
  if (Length(ALines) = 0) or (ALine < AFirstLine) or (ALine >= AFirstLine + Length(ALines)) then
  begin
    Exit;
  end;
  mFrom := ALine - AContext;
  if mFrom < AFirstLine then
  begin
    mFrom := AFirstLine;
  end;
  mTo := ALine + AContext;
  if mTo > AFirstLine + High(ALines) then
  begin
    mTo := AFirstLine + High(ALines);
  end;
  AStart := mFrom;
  Result := Copy(ALines, mFrom - AFirstLine, mTo - mFrom + 1);
end;

class function TAtlasDebugNote.FileName(ATime: TDateTime): string;
begin
  Result := 'debug-notiz-' + FormatDateTime('yyyy-mm-dd-hhnn', ATime) + '.md';
end;

class function TAtlasDebugNote.HistoryText(const AExceptions: TAtlasDebugExceptions; AMax: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to Min(Length(AExceptions), AMax) - 1 do
  begin
    if Result <> '' then
    begin
      Result := Result + #13#10#13#10;
    end;
    Result := Result + Redact(TrimRight(AExceptions[mIndex].CopyText));
  end;
  if Result <> '' then
  begin
    Result := Result + #13#10;
  end;
end;

function Shortened(const AText: string): string;
begin
  Result := AText;
  if Length(Result) > TAtlasDebugNote.MaxLineLength then
  begin
    Result := Copy(Result, 1, TAtlasDebugNote.MaxLineLength - 1) + '…';
  end;
end;

procedure AppendField(ALines: TStringBuilder; const ALabel, AValue: string);
begin
  if AValue <> '' then
  begin
    ALines.Append('- **').Append(ALabel).Append(':** ').Append(AValue).Append(#13#10);
  end;
end;

procedure AppendHeader(ALines: TStringBuilder; const AData: TAtlasDebugNoteData; const ATexts: TAtlasDebugNoteTexts);
begin
  ALines.Append('# ').Append(ATexts.Title).Append(#13#10#13#10);
  AppendField(ALines, ATexts.Project, ExtractFileName(AData.Project));
  AppendField(ALines, ATexts.Configuration, AData.Configuration);
  AppendField(ALines, ATexts.TargetPlatform, AData.TargetPlatform);
  if AData.Time > 0 then
  begin
    // Feste Schreibweise: Die Notiz geht in Issues und Chats, das Gebietsschema ersetzte sonst den „:“.
    AppendField(ALines, ATexts.Time, FormatDateTime('yyyy-mm-dd hh:nn:ss', AData.Time, TFormatSettings.Invariant));
  end;
  AppendField(ALines, ATexts.Thread, AData.Thread);
end;

/// <summary>Quelltext um die Haltezeile, die Haltezeile mit „>“ markiert.</summary>
procedure AppendExcerpt(ALines: TStringBuilder; const AData: TAtlasDebugNoteData);
var
  mExcerpt: TArray<string>;
  mStart, mIndex, mWidth: Integer;
  mText: string;
begin
  mExcerpt := TAtlasDebugNote.Excerpt(AData.Source, AData.SourceFirstLine, AData.Line,
    TAtlasDebugNote.ContextLines, mStart);
  if Length(mExcerpt) = 0 then
  begin
    Exit;
  end;
  mWidth := Length(IntToStr(mStart + High(mExcerpt)));
  ALines.Append(#13#10).Append('```pascal').Append(#13#10);
  for mIndex := 0 to High(mExcerpt) do
  begin
    if mStart + mIndex = AData.Line then
    begin
      mText := '> ';
    end
    else
    begin
      mText := '  ';
    end;
    mText := mText + StringOfChar(' ', mWidth - Length(IntToStr(mStart + mIndex))) + IntToStr(mStart + mIndex) +
      ' ' + Shortened(TAtlasDebugNote.RedactCode(TrimRight(mExcerpt[mIndex])));
    ALines.Append(TTextAnonymizer.FenceSafe(mText)).Append(#13#10);
  end;
  ALines.Append('```').Append(#13#10);
end;

procedure AppendLocation(ALines: TStringBuilder; const AData: TAtlasDebugNoteData;
  const ATexts: TAtlasDebugNoteTexts);
begin
  ALines.Append(#13#10).Append('## ').Append(ATexts.Location).Append(#13#10#13#10);
  if (AData.FileName = '') or (AData.Line <= 0) then
  begin
    ALines.Append(ATexts.NoLocation).Append(#13#10);
    Exit;
  end;
  ALines.Append('`').Append(ExtractFileName(AData.FileName)).Append(':').Append(AData.Line).Append('`');
  if AData.Routine <> '' then
  begin
    ALines.Append(' – `').Append(AData.Routine).Append('`');
  end;
  ALines.Append(#13#10);
  AppendExcerpt(ALines, AData);
end;

function FrameText(const AFrame: TAtlasDebugFrame): string;
begin
  Result := '`' + Shortened(AFrame.Header) + '`';
  if AFrame.HasSource then
  begin
    Result := Result + ' (' + ExtractFileName(AFrame.FileName) + ':' + IntToStr(AFrame.Line) + ')';
  end;
  if AFrame.Own then
  begin
    Result := '**' + Result + '**';
  end;
end;

/// <summary>Aufrufstapel: eigener Code fett (#578).</summary>
procedure AppendFrames(ALines: TStringBuilder; const AData: TAtlasDebugNoteData;
  const ATexts: TAtlasDebugNoteTexts);
var
  mIndex: Integer;
begin
  if Length(AData.Frames) = 0 then
  begin
    Exit;
  end;
  ALines.Append(#13#10).Append('## ').Append(ATexts.CallStack).Append(#13#10#13#10);
  for mIndex := 0 to Min(Length(AData.Frames), TAtlasDebugNote.MaxFrames) - 1 do
  begin
    ALines.Append('- ').Append(FrameText(AData.Frames[mIndex])).Append(#13#10);
  end;
  if Length(AData.Frames) > TAtlasDebugNote.MaxFrames then
  begin
    ALines.Append('- …').Append(#13#10);
  end;
end;

/// <summary>Letzte Exception (#517).</summary>
procedure AppendException(ALines: TStringBuilder; const AData: TAtlasDebugNoteData;
  const ATexts: TAtlasDebugNoteTexts);
begin
  if not AData.HasException then
  begin
    Exit;
  end;
  ALines.Append(#13#10).Append('## ').Append(ATexts.LastException).Append(#13#10#13#10);
  ALines.Append('**').Append(AData.Exception.ExceptionClass).Append('**');
  if AData.Exception.Message <> '' then
  begin
    ALines.Append(': ').Append(Shortened(TAtlasDebugNote.Redact(AData.Exception.Message)));
  end;
  ALines.Append(#13#10);
  if AData.Exception.LocationText <> '' then
  begin
    ALines.Append(#13#10).Append('`').Append(AData.Exception.LocationText).Append('`').Append(#13#10);
  end;
  if AData.Exception.Count > 1 then
  begin
    ALines.Append(#13#10).Append(Format(ATexts.Count, [AData.Exception.Count])).Append(#13#10);
  end;
end;

class function TAtlasDebugNote.Markdown(const AData: TAtlasDebugNoteData; const ATexts: TAtlasDebugNoteTexts): string;
var
  mLines: TStringBuilder;
begin
  mLines := TStringBuilder.Create;
  try
    AppendHeader(mLines, AData, ATexts);
    AppendLocation(mLines, AData, ATexts);
    AppendFrames(mLines, AData, ATexts);
    AppendException(mLines, AData, ATexts);
    Result := TrimRight(mLines.ToString) + #13#10;
  finally
    mLines.Free;
  end;
end;

end.
