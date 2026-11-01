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
    if Pos(mWord, mName) > 0 then
      Exit(True);
  Result := False;
end;

function IsNameChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']);
end;

/// <summary>Redact bzw. RedactCode (AColon: auch „Name: Wert“).</summary>
function Masked(const AText: string; AColon: Boolean): string;
var
  mIndex, mNameStart, mValueStart, mValueEnd: Integer;
  mName: string;
  mQuote: Char;
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
    // Ein Name …
    mNameStart := mIndex;
    while (mIndex <= Length(Result)) and IsNameChar(Result[mIndex]) do
      Inc(mIndex);
    mName := Copy(Result, mNameStart, mIndex - mNameStart);
    if not TAtlasDebugNote.IsSecretName(mName) then
      Continue;
    // … gefolgt von „:=“, „=“ oder „:“ (mit Leerraum).
    mValueStart := mIndex;
    while (mValueStart <= Length(Result)) and (Result[mValueStart] = ' ') do
      Inc(mValueStart);
    if (mValueStart < Length(Result)) and (Result[mValueStart] = ':') and (Result[mValueStart + 1] = '=') then
      Inc(mValueStart, 2)
    else if (mValueStart <= Length(Result)) and ((Result[mValueStart] = '=') or (AColon and
      (Result[mValueStart] = ':'))) then
      Inc(mValueStart)
    else
      Continue;
    while (mValueStart <= Length(Result)) and (Result[mValueStart] = ' ') do
      Inc(mValueStart);
    if mValueStart > Length(Result) then
      Break;
    // Wert: in Hochkommas bzw. Anführungszeichen bis zum schließenden, sonst bis Leerraum, „;“, „,“ oder „)“.
    mValueEnd := mValueStart;
    if CharInSet(Result[mValueStart], ['''', '"']) then
    begin
      mQuote := Result[mValueStart];
      mValueEnd := mValueStart + 1;
      while (mValueEnd <= Length(Result)) and (Result[mValueEnd] <> mQuote) do
        Inc(mValueEnd);
      if mValueEnd <= Length(Result) then
        Inc(mValueEnd);
    end
    else
      while (mValueEnd <= Length(Result)) and not CharInSet(Result[mValueEnd], [' ', #9, ';', ',', ')', #13, #10])
        do
        Inc(mValueEnd);
    if mValueEnd = mValueStart then
      Continue;
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
    Exit;
  mFrom := ALine - AContext;
  if mFrom < AFirstLine then
    mFrom := AFirstLine;
  mTo := ALine + AContext;
  if mTo > AFirstLine + High(ALines) then
    mTo := AFirstLine + High(ALines);
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
      Result := Result + #13#10#13#10;
    Result := Result + Redact(TrimRight(AExceptions[mIndex].CopyText));
  end;
  if Result <> '' then
    Result := Result + #13#10;
end;

function Shortened(const AText: string): string;
begin
  Result := AText;
  if Length(Result) > TAtlasDebugNote.MaxLineLength then
    Result := Copy(Result, 1, TAtlasDebugNote.MaxLineLength - 1) + '…';
end;

class function TAtlasDebugNote.Markdown(const AData: TAtlasDebugNoteData; const ATexts: TAtlasDebugNoteTexts): string;
var
  mLines: TStringBuilder;
  mExcerpt: TArray<string>;
  mStart, mIndex, mWidth: Integer;
  mFrame: TAtlasDebugFrame;
  mText: string;

  procedure Field(const ALabel, AValue: string);
  begin
    if AValue <> '' then
      mLines.Append('- **').Append(ALabel).Append(':** ').Append(AValue).Append(#13#10);
  end;

begin
  mLines := TStringBuilder.Create;
  try
    mLines.Append('# ').Append(ATexts.Title).Append(#13#10#13#10);
    Field(ATexts.Project, ExtractFileName(AData.Project));
    Field(ATexts.Configuration, AData.Configuration);
    Field(ATexts.TargetPlatform, AData.TargetPlatform);
    if AData.Time > 0 then
      Field(ATexts.Time, FormatDateTime('yyyy-mm-dd hh:nn:ss', AData.Time));
    Field(ATexts.Thread, AData.Thread);
    // Ort mit Ausschnitt.
    mLines.Append(#13#10).Append('## ').Append(ATexts.Location).Append(#13#10#13#10);
    if (AData.FileName = '') or (AData.Line <= 0) then
      mLines.Append(ATexts.NoLocation).Append(#13#10)
    else
    begin
      mLines.Append('`').Append(ExtractFileName(AData.FileName)).Append(':').Append(AData.Line).Append('`');
      if AData.Routine <> '' then
        mLines.Append(' – `').Append(AData.Routine).Append('`');
      mLines.Append(#13#10);
      mExcerpt := Excerpt(AData.Source, AData.SourceFirstLine, AData.Line, ContextLines, mStart);
      if Length(mExcerpt) > 0 then
      begin
        mWidth := Length(IntToStr(mStart + High(mExcerpt)));
        mLines.Append(#13#10).Append('```pascal').Append(#13#10);
        for mIndex := 0 to High(mExcerpt) do
        begin
          if mStart + mIndex = AData.Line then
            mText := '> '
          else
            mText := '  ';
          mText := mText + StringOfChar(' ', mWidth - Length(IntToStr(mStart + mIndex))) + IntToStr(mStart + mIndex) +
            ' ' + Shortened(RedactCode(TrimRight(mExcerpt[mIndex])));
          mLines.Append(TTextAnonymizer.FenceSafe(mText)).Append(#13#10);
        end;
        mLines.Append('```').Append(#13#10);
      end;
    end;
    // Aufrufstapel: eigener Code fett (#578).
    if Length(AData.Frames) > 0 then
    begin
      mLines.Append(#13#10).Append('## ').Append(ATexts.CallStack).Append(#13#10#13#10);
      mIndex := 0;
      for mFrame in AData.Frames do
      begin
        if mIndex >= MaxFrames then
        begin
          mLines.Append('- …').Append(#13#10);
          Break;
        end;
        Inc(mIndex);
        mText := '`' + Shortened(mFrame.Header) + '`';
        if mFrame.HasSource then
          mText := mText + ' (' + ExtractFileName(mFrame.FileName) + ':' + IntToStr(mFrame.Line) + ')';
        if mFrame.Own then
          mText := '**' + mText + '**';
        mLines.Append('- ').Append(mText).Append(#13#10);
      end;
    end;
    // Letzte Exception (#517).
    if AData.HasException then
    begin
      mLines.Append(#13#10).Append('## ').Append(ATexts.LastException).Append(#13#10#13#10);
      mLines.Append('**').Append(AData.Exception.ExceptionClass).Append('**');
      if AData.Exception.Message <> '' then
        mLines.Append(': ').Append(Shortened(Redact(AData.Exception.Message)));
      mLines.Append(#13#10);
      if AData.Exception.LocationText <> '' then
        mLines.Append(#13#10).Append('`').Append(AData.Exception.LocationText).Append('`').Append(#13#10);
      if AData.Exception.Count > 1 then
        mLines.Append(#13#10).Append(Format(ATexts.Count, [AData.Exception.Count])).Append(#13#10);
    end;
    Result := TrimRight(mLines.ToString) + #13#10;
  finally
    mLines.Free;
  end;
end;

end.
