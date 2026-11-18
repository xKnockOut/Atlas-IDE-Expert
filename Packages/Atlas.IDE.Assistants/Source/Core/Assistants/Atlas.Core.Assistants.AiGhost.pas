unit Atlas.Core.Assistants.AiGhost;

// Schattentext vom KI-Anbieter (#1922), reine Logik ohne IDE:
// - Prompt: Ausschnitt um die leere Zeile (assistants.contextLines Zeilen
//   davor, wenige danach) mit einer Marke an der Schreibmarke, dazu die Köpfe
//   der Klasse aus dem Index (atlas.server.suggestionContext). Nur Name der
//   Datei, kein Pfad.
// - Antwort → Zeilen: Codezäune und leere Ränder weg, höchstens cMaxLines
//   Zeilen, Einrückung der leeren Zeile vorn, relative Einrückung bleibt,
//   Tabulatoren nach den Einstellungen des Editors.
// - Ausnahmen (assistants.exclude): Masken mit * und ?, getrennt durch ; oder
//   Zeilenumbruch, gegen den Namen und den ganzen Pfad der Datei.
// - Tageszähler (assistants.dailyLimit): Anfragen je Kalendertag; gespeichert
//   als {"day":"JJJJ-MM-TT","count":N}.

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  /// <summary>Was der Anbieter zur leeren Zeile bekommt.</summary>
  TAtlasAiGhostRequest = record
    FileName: string;
    /// <summary>Die leere Zeile (0-basiert).</summary>
    Line: Integer;
    Text: string;
    /// <summary>Zeilen vor der leeren Zeile (assistants.contextLines).</summary>
    ContextLines: Integer;
    /// <summary>Köpfe der Klasse und ihrer Mitglieder aus dem Index.</summary>
    Declarations: TArray<string>;
  end;

  TAtlasAiGhost = class
  public const
    /// <summary>Höchstens so viele Zeilen schlägt der Schattentext vor.</summary>
    cMaxLines = 8;
    /// <summary>Zeilen nach der leeren Zeile im Ausschnitt.</summary>
    cLinesAfter = 8;
    cMarker = '<|cursor|>';
    cMaxTokens = 400;
  public
    class function Prompt(const ARequest: TAtlasAiGhostRequest; ATimeoutMs: Integer): TAtlasAiPrompt; static;
    /// <summary>Zeilen für die leere Zeile ALine von AText aus der Antwort AAnswer; leer = kein Vorschlag.</summary>
    class function LinesOf(const AAnswer, AText: string; ALine, ATabSize: Integer; AInsertSpaces: Boolean):
      TArray<string>; static;
    /// <summary>Einrückung der leeren Zeile ALine: ihre eigene, sonst die der letzten Zeile mit Text davor.
    /// </summary>
    class function IndentAt(const AText: string; ALine: Integer): string; static;
    /// <summary>Passt AFileName auf eine der Masken in APatterns?</summary>
    class function Excluded(const AFileName, APatterns: string): Boolean; static;
    /// <summary>Passt AText auf die Maske AMask (* und ?, ohne Groß-/Kleinschreibung)?</summary>
    class function Matches(const AText, AMask: string): Boolean; static;
  end;

  /// <summary>Anfragen des Tages; nicht threadsicher (nur im Hauptthread).</summary>
  TAtlasAiDailyCount = class
  private
    FDay: string;
    FCount: Integer;
    FChanged: Boolean;
  public
    /// <summary>Eine Anfrage am Tag ADay ("JJJJ-MM-TT") zählen, wenn noch unter ALimit; sonst False.</summary>
    function TryTake(const ADay: string; ALimit: Integer): Boolean;
    /// <summary>Anfragen am Tag ADay.</summary>
    function CountOn(const ADay: string): Integer;
    function ToJson: string;
    /// <summary>False, wenn AText kein gültiger Stand ist (dann bleibt der alte).</summary>
    function FromJson(const AText: string): Boolean;
    property Changed: Boolean read FChanged;
    procedure MarkSaved;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.JSON,
  Atlas.Text.Lines;

const
  cInstructions =
    'You complete Delphi (Object Pascal) code in an editor. The user sends the code around the cursor; ' +
    'the cursor stands on an empty line marked with ' + TAtlasAiGhost.cMarker + '. ' +
    'Answer with the code that belongs on that line and, if needed, the few lines right after it ' +
    '(at most 8 lines). Answer with code only: no explanation, no Markdown, no code fences, ' +
    'nothing from the surrounding code repeated. Use only identifiers that exist in the code or the ' +
    'declarations given. If nothing fits, answer with an empty message.';

{ TAtlasAiGhost }

class function TAtlasAiGhost.Prompt(const ARequest: TAtlasAiGhostRequest; ATimeoutMs: Integer): TAtlasAiPrompt;
var
  mLines: TArray<string>;
  mBuilder: TStringBuilder;
  mFirst, mLast, mIndex: Integer;
  mDeclaration: string;
begin
  Result := Default(TAtlasAiPrompt);
  Result.Instructions := cInstructions;
  Result.MaxTokens := cMaxTokens;
  Result.TimeoutMs := ATimeoutMs;
  mLines := TTextLines.SplitLines(ARequest.Text);
  mFirst := Max(0, ARequest.Line - Max(ARequest.ContextLines, 1));
  mLast := Min(High(mLines), ARequest.Line + cLinesAfter);
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('File: ').Append(ExtractFileName(ARequest.FileName.Replace('/', '\'))).Append(#10);
    if Length(ARequest.Declarations) > 0 then
    begin
      mBuilder.Append('Declarations of the class:').Append(#10);
      for mDeclaration in ARequest.Declarations do
      begin
        mBuilder.Append(mDeclaration).Append(#10);
      end;
    end;
    mBuilder.Append('Code:').Append(#10);
    for mIndex := mFirst to mLast do
    begin
      if mIndex = ARequest.Line then
      begin
        mBuilder.Append(IndentAt(ARequest.Text, ARequest.Line)).Append(cMarker);
      end
      else
      begin
        mBuilder.Append(mLines[mIndex]);
      end;
      mBuilder.Append(#10);
    end;
    Result.Task := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Breite der Einrückung AIndent in Spalten.</summary>
function WidthOf(const AIndent: string; ATabSize: Integer): Integer;
var
  mChar: Char;
begin
  Result := 0;
  for mChar in AIndent do
  begin
    if mChar = #9 then
    begin
      Result := Result + Max(ATabSize, 1);
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Einrückung der Breite AWidth: Leerzeichen oder Tabulatoren mit Rest.</summary>
function IndentForWidth(AWidth, ATabSize: Integer; AInsertSpaces: Boolean): string;
begin
  if AInsertSpaces or (ATabSize < 1) then
  begin
    Result := StringOfChar(' ', AWidth);
  end
  else
  begin
    Result := StringOfChar(#9, AWidth div ATabSize) + StringOfChar(' ', AWidth mod ATabSize);
  end;
end;

class function TAtlasAiGhost.IndentAt(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mLines := TTextLines.SplitLines(AText);
  if (ALine < 0) or (ALine > High(mLines)) then
  begin
    Exit;
  end;
  if mLines[ALine] <> '' then
  begin
    Exit(TTextLines.IndentOf(mLines[ALine]));
  end;
  for mIndex := ALine - 1 downto 0 do
  begin
    if Trim(mLines[mIndex]) <> '' then
    begin
      Exit(TTextLines.IndentOf(mLines[mIndex]));
    end;
  end;
end;

/// <summary>Antwort ohne Codezäune und ohne leere Zeilen am Anfang und Ende.</summary>
function CleanLines(const AAnswer: string): TArray<string>;
var
  mLine: string;
  mAll: TArray<string>;
  mFirst, mLast, mIndex: Integer;
begin
  Result := nil;
  mAll := nil;
  for mLine in TTextLines.SplitLines(AAnswer) do
  begin
    if StartsText('```', TrimLeft(mLine)) or (Pos(TAtlasAiGhost.cMarker, mLine) > 0) then
    begin
      Continue;
    end;
    mAll := mAll + [TrimRight(mLine)];
  end;
  mFirst := 0;
  while (mFirst <= High(mAll)) and (Trim(mAll[mFirst]) = '') do
  begin
    Inc(mFirst);
  end;
  mLast := High(mAll);
  while (mLast >= mFirst) and (Trim(mAll[mLast]) = '') do
  begin
    Dec(mLast);
  end;
  for mIndex := mFirst to mLast do
  begin
    Result := Result + [mAll[mIndex]];
  end;
end;

class function TAtlasAiGhost.LinesOf(const AAnswer, AText: string; ALine, ATabSize: Integer;
  AInsertSpaces: Boolean): TArray<string>;
var
  mLines: TArray<string>;
  mBase, mCommon, mWidth, mIndex: Integer;
begin
  Result := nil;
  mLines := CleanLines(AAnswer);
  if Length(mLines) > cMaxLines then
  begin
    SetLength(mLines, cMaxLines);
  end;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  // Gemeinsame Einrückung der Antwort weg, die der leeren Zeile davor.
  mCommon := MaxInt;
  for mIndex := 0 to High(mLines) do
  begin
    if Trim(mLines[mIndex]) <> '' then
    begin
      mCommon := Min(mCommon, WidthOf(TTextLines.IndentOf(mLines[mIndex]), ATabSize));
    end;
  end;
  mBase := WidthOf(IndentAt(AText, ALine), ATabSize);
  SetLength(Result, Length(mLines));
  for mIndex := 0 to High(mLines) do
  begin
    if Trim(mLines[mIndex]) = '' then
    begin
      Result[mIndex] := '';
      Continue;
    end;
    mWidth := mBase + WidthOf(TTextLines.IndentOf(mLines[mIndex]), ATabSize) - mCommon;
    Result[mIndex] := IndentForWidth(mWidth, ATabSize, AInsertSpaces) + TrimLeft(mLines[mIndex]);
  end;
end;

class function TAtlasAiGhost.Matches(const AText, AMask: string): Boolean;
var
  mText, mMask: string;
  mT, mM, mStar, mMark: Integer;
begin
  mText := LowerCase(AText);
  mMask := LowerCase(AMask);
  mT := 1;
  mM := 1;
  mStar := 0;
  mMark := 0;
  while mT <= Length(mText) do
  begin
    if (mM <= Length(mMask)) and ((mMask[mM] = '?') or (mMask[mM] = mText[mT])) then
    begin
      Inc(mT);
      Inc(mM);
    end
    else if (mM <= Length(mMask)) and (mMask[mM] = '*') then
    begin
      mStar := mM;
      mMark := mT;
      Inc(mM);
    end
    else if mStar > 0 then
    begin
      mM := mStar + 1;
      Inc(mMark);
      mT := mMark;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (mM <= Length(mMask)) and (mMask[mM] = '*') do
  begin
    Inc(mM);
  end;
  Result := mM > Length(mMask);
end;

class function TAtlasAiGhost.Excluded(const AFileName, APatterns: string): Boolean;
var
  mPath, mName, mMask: string;
begin
  mPath := AFileName.Replace('/', '\');
  mName := ExtractFileName(mPath);
  for mMask in APatterns.Replace(#13, ';').Replace(#10, ';').Split([';']) do
  begin
    if (Trim(mMask) <> '') and (Matches(mName, Trim(mMask)) or
      Matches(mPath, Trim(mMask).Replace('/', '\'))) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasAiDailyCount }

function TAtlasAiDailyCount.CountOn(const ADay: string): Integer;
begin
  Result := 0;
  if FDay = ADay then
  begin
    Result := FCount;
  end;
end;

function TAtlasAiDailyCount.TryTake(const ADay: string; ALimit: Integer): Boolean;
begin
  Result := CountOn(ADay) < ALimit;
  if Result then
  begin
    if FDay <> ADay then
    begin
      FDay := ADay;
      FCount := 0;
    end;
    Inc(FCount);
    FChanged := True;
  end;
end;

function TAtlasAiDailyCount.ToJson: string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('day', FDay);
    mObject.AddPair('count', TJSONNumber.Create(FCount));
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

function TAtlasAiDailyCount.FromJson(const AText: string): Boolean;
var
  mValue, mCount: TJSONValue;
  mDay: string;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mDay := TJSONObject(mValue).GetValue<string>('day', '');
    mCount := TJSONObject(mValue).GetValue('count');
    if not (mCount is TJSONNumber) then
    begin
      Exit;
    end;
    FDay := mDay;
    FCount := Max(TJSONNumber(mCount).AsInt, 0);
    FChanged := False;
    Result := True;
  finally
    mValue.Free;
  end;
end;

procedure TAtlasAiDailyCount.MarkSaved;
begin
  FChanged := False;
end;

end.
