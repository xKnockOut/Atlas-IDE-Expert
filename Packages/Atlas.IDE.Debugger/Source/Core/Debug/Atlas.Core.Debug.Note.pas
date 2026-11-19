unit Atlas.Core.Debug.Note;

// Debug-Notiz als Markdown (#582, genutzt von „An Issue anhängen“ #1276), ohne
// VCL und Open Tools API. Die IDE-Schicht sammelt den Zustand des Halts
// (TAtlasDebugNoteData); hier entsteht daraus der Text:
//   # Debug-Notiz
//   Projekt, Konfiguration, Plattform, Zeit, Thread
//   ## Ort – Datei:Zeile, Routine, Codeausschnitt (±ContextLines) mit Marke
//   ## Aufrufstapel – eigener Code (#578) fett
//   ## Lokale Variablen, ## Überwachte Ausdrücke – Name = Wert, Teile
//      strukturierter Werte eine Stufe tiefer (aus TAtlasEvalList)
//   ## Letzte Exception (#517) – Klasse, Meldung, Ort, Anzahl
//   ## Ereignisprotokoll (#580) – die letzten Zeilen
// Werte, die wie Geheimnisse aussehen (Name enthält Password, Passwort, Pwd,
// Secret, Token, ApiKey, Credential), erscheinen als ***: in den
// Codezeilen, bei Variablen (auch Teile unter einem solchen Namen), im
// Ereignisprotokoll und in der Meldung der Exception (Redact).
// Die Überschriften kommen in der Sprache der Oberfläche von außen
// (TAtlasDebugNoteTexts), Core kennt Atlas.UI.Strings nicht und hat keine
// eigenen Texte.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Evaluate,
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
    Locals: string;
    Watches: string;
    Events: string;
    /// <summary>Wert eines Ausdrucks, der sich nicht auswerten ließ.</summary>
    Unavailable: string;
    /// <summary>Wert, der bis zum Erstellen der Notiz nicht kam.</summary>
    Pending: string;
  end;

  /// <summary>Eine Zeile unter „Lokale Variablen“ bzw. „Überwachte Ausdrücke“.</summary>
  TAtlasDebugNoteValue = record
    Name: string;
    Value: string;
    /// <summary>0 = Variable bzw. Ausdruck, 1 = Teil eines strukturierten Werts.</summary>
    Level: Integer;
    /// <summary>Name einer Variablen bzw. des umgebenden Werts sieht nach einem Geheimnis aus.</summary>
    Secret: Boolean;
    class function Create(const AName, AValue: string; ALevel: Integer; ASecret: Boolean): TAtlasDebugNoteValue;
      static;
  end;

  TAtlasDebugNoteValues = TArray<TAtlasDebugNoteValue>;

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
    /// <summary>Lokale Variablen bzw. überwachte Ausdrücke des Halts; leer = Abschnitt fehlt.</summary>
    Locals: TAtlasDebugNoteValues;
    Watches: TAtlasDebugNoteValues;
    /// <summary>Zeilen des Ereignisprotokolls, älteste zuerst; die Notiz nimmt die letzten cMaxEvents.</summary>
    Events: TArray<string>;
    class function Empty: TAtlasDebugNoteData; static;
  end;

  TAtlasDebugNote = record
  public const
    cContextLines = 5;
    cMaxFrames = 30;
    /// <summary>Längere Codezeilen bzw. Meldungen werden gekürzt.</summary>
    cMaxLineLength = 300;
    /// <summary>Längere Werte von Variablen werden gekürzt.</summary>
    cMaxValueLength = 200;
    /// <summary>Höchstens so viele Variablen bzw. Ausdrücke je Abschnitt und Teile je Wert.</summary>
    cMaxValues = 50;
    cMaxParts = 20;
    cMaxEvents = 20;
    cMask = '***';
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
    /// <summary>Dateiname „AStem-JJJJ-MM-TT-hhmm.md“; AStem in der Sprache der Oberfläche (debug-notiz, debug-note).
    /// </summary>
    class function FileName(const AStem: string; ATime: TDateTime): string; static;
    /// <summary>Exception-Verlauf als Text zum Anhängen: höchstens AMax Einträge (in der Reihenfolge von
    /// AExceptions) wie „Kopieren“ im Fenster, durch Leerzeilen getrennt, Geheimnisse ausgeblendet.</summary>
    class function HistoryText(const AExceptions: TAtlasDebugExceptions; AMax: Integer): string; static;
    /// <summary>Zeilen der Notiz aus den Wurzeln von AList (höchstens cMaxValues): Wert, Fehlertext bzw.
    /// ATexts.Unavailable/Pending; Teile strukturierter Werte (TAtlasEvalText.Parts, höchstens cMaxParts) eine
    /// Stufe tiefer.</summary>
    class function ValuesOf(AList: TAtlasEvalList; const ATexts: TAtlasDebugNoteTexts): TAtlasDebugNoteValues;
      static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Text.Anonymize;

const
  cSecretWords: array[0..7] of string = ('password', 'passwort', 'passwd', 'pwd', 'secret', 'token', 'apikey',
    'credential');


{ TAtlasDebugNoteValue }

class function TAtlasDebugNoteValue.Create(const AName, AValue: string; ALevel: Integer;
  ASecret: Boolean): TAtlasDebugNoteValue;
begin
  Result.Name := AName;
  Result.Value := AValue;
  Result.Level := ALevel;
  Result.Secret := ASecret;
end;

{ TAtlasDebugNoteData }

class function TAtlasDebugNoteData.Empty: TAtlasDebugNoteData;
begin
  Result := Default(TAtlasDebugNoteData);
  Result.Source := nil;
  Result.Frames := nil;
  Result.Locals := nil;
  Result.Watches := nil;
  Result.Events := nil;
end;

{ TAtlasDebugNote }

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

function IsNameChar(AC: Char): Boolean;
begin
  Result := CharInSet(AC, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']);
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
    Result := Copy(Result, 1, mValueStart - 1) + TAtlasDebugNote.cMask + Copy(Result, mValueEnd, MaxInt);
    mIndex := mValueStart + Length(TAtlasDebugNote.cMask);
  end;
end;

class function TAtlasDebugNote.IsSecretName(const AName: string): Boolean;
var
  mName, mWord: string;
begin
  mName := LowerCase(StringReplace(StringReplace(AName, '_', '', [rfReplaceAll]), '-', '', [rfReplaceAll]));
  for mWord in cSecretWords do
  begin
    if Pos(mWord, mName) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugNote.Redact(const AText: string): string;
begin
  Result := Masked(AText, True);
end;

class function TAtlasDebugNote.RedactCode(const ALine: string): string;
begin
  Result := Masked(ALine, False);
end;

class function TAtlasDebugNote.FileName(const AStem: string; ATime: TDateTime): string;
begin
  Result := AStem + '-' + FormatDateTime('yyyy-mm-dd-hhnn', ATime) + '.md';
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

/// <summary>Was die Notiz für einen Knoten zeigt: Wert, Fehlertext oder Hinweis.</summary>
function NodeText(ANode: TAtlasEvalNode; const ATexts: TAtlasDebugNoteTexts): string;
begin
  case ANode.State of
    TAtlasEvalState.Value, TAtlasEvalState.Error:
      Result := ANode.Value;
    TAtlasEvalState.Unavailable:
      Result := ATexts.Unavailable;
  else
    Result := ATexts.Pending;
  end;
end;

class function TAtlasDebugNote.ValuesOf(AList: TAtlasEvalList;
  const ATexts: TAtlasDebugNoteTexts): TAtlasDebugNoteValues;
var
  mIndex, mPart: Integer;
  mNode: TAtlasEvalNode;
  mName: string;
  mSecret: Boolean;
  mParts: TAtlasEvalParts;
begin
  Result := nil;
  if AList = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to Min(AList.Count, cMaxValues) - 1 do
  begin
    mNode := AList.Roots[mIndex];
    mName := mNode.Name;
    if mName = '' then
    begin
      mName := mNode.Expression;
    end;
    mSecret := IsSecretName(mName);
    Result := Result + [TAtlasDebugNoteValue.Create(mName, NodeText(mNode, ATexts), 0, mSecret)];
    if (mNode.State <> TAtlasEvalState.Value) or not TAtlasEvalText.IsStructured(mNode.Value) then
    begin
      Continue;
    end;
    mParts := TAtlasEvalText.Parts(mNode.Value);
    for mPart := 0 to Min(Length(mParts), cMaxParts) - 1 do
    begin
      Result := Result + [TAtlasDebugNoteValue.Create(mParts[mPart].Name, mParts[mPart].Value, 1,
        mSecret or IsSecretName(mParts[mPart].Name))];
    end;
  end;
end;

function Shortened(const AText: string): string;
begin
  Result := AText;
  if Length(Result) > TAtlasDebugNote.cMaxLineLength then
  begin
    Result := Copy(Result, 1, TAtlasDebugNote.cMaxLineLength - 1) + '…';
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
    TAtlasDebugNote.cContextLines, mStart);
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
  for mIndex := 0 to Min(Length(AData.Frames), TAtlasDebugNote.cMaxFrames) - 1 do
  begin
    ALines.Append('- ').Append(FrameText(AData.Frames[mIndex])).Append(#13#10);
  end;
  if Length(AData.Frames) > TAtlasDebugNote.cMaxFrames then
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

/// <summary>AText als Code im Fließtext; enthält er selbst „`“, mit doppelten Backticks.</summary>
function InlineCode(const AText: string): string;
begin
  if AText = '' then
  begin
    Result := '–';
  end
  else if Pos('`', AText) > 0 then
  begin
    Result := '`` ' + AText + ' ``';
  end
  else
  begin
    Result := '`' + AText + '`';
  end;
end;

/// <summary>Zeilenumbrüche eines Werts als Leerzeichen: Eine Variable bleibt eine Zeile der Liste.</summary>
function OneLine(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function ValueText(const AValue: TAtlasDebugNoteValue): string;
begin
  if AValue.Secret then
  begin
    Exit(TAtlasDebugNote.cMask);
  end;
  Result := TAtlasDebugNote.Redact(OneLine(AValue.Value));
  if Length(Result) > TAtlasDebugNote.cMaxValueLength then
  begin
    Result := Copy(Result, 1, TAtlasDebugNote.cMaxValueLength - 1) + '…';
  end;
end;

/// <summary>Abschnitt mit Variablen bzw. Ausdrücken; Teile eingerückt.</summary>
procedure AppendValues(ALines: TStringBuilder; const ATitle: string; const AValues: TAtlasDebugNoteValues);
var
  mValue: TAtlasDebugNoteValue;
begin
  if Length(AValues) = 0 then
  begin
    Exit;
  end;
  ALines.Append(#13#10).Append('## ').Append(ATitle).Append(#13#10#13#10);
  for mValue in AValues do
  begin
    ALines.Append(StringOfChar(' ', 2 * mValue.Level)).Append('- ').Append(InlineCode(mValue.Name));
    ALines.Append(' = ').Append(InlineCode(ValueText(mValue))).Append(#13#10);
  end;
end;

/// <summary>Die letzten cMaxEvents Zeilen des Ereignisprotokolls (#580) als Textblock.</summary>
procedure AppendEvents(ALines: TStringBuilder; const AData: TAtlasDebugNoteData;
  const ATexts: TAtlasDebugNoteTexts);
var
  mIndex: Integer;
begin
  if Length(AData.Events) = 0 then
  begin
    Exit;
  end;
  ALines.Append(#13#10).Append('## ').Append(ATexts.Events).Append(#13#10#13#10).Append('```text').Append(#13#10);
  for mIndex := Max(0, Length(AData.Events) - TAtlasDebugNote.cMaxEvents) to High(AData.Events) do
  begin
    ALines.Append(TTextAnonymizer.FenceSafe(Shortened(TAtlasDebugNote.Redact(OneLine(AData.Events[mIndex])))));
    ALines.Append(#13#10);
  end;
  ALines.Append('```').Append(#13#10);
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
    AppendValues(mLines, ATexts.Locals, AData.Locals);
    AppendValues(mLines, ATexts.Watches, AData.Watches);
    AppendException(mLines, AData, ATexts);
    AppendEvents(mLines, AData, ATexts);
    Result := TrimRight(mLines.ToString) + #13#10;
  finally
    mLines.Free;
  end;
end;

end.
