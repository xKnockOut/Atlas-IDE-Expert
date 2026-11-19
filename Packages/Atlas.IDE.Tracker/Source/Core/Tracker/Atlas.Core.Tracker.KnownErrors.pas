unit Atlas.Core.Tracker.KnownErrors;

// Bekannte Fehler beim Exception-Halt (#2460), Teil des Trackers, ohne VCL und
// Open Tools API. Der Debugger meldet den Halt über den Vertrag
// Atlas.Core.KnownErrors.Contract; hier steht, was der Tracker daraus macht:
// - Signatur: Exception-Klasse, Meldung ohne Zahlen, Adressen, Pfade und
//   Anführungsinhalte, oberste eigene Methode ohne Unit ("TFoo.Bar").
// - Suche: bis zu drei Freitextsuchen beim Tracker in der Rangfolge Klasse und
//   Methode, Klasse und Wörter der Meldung, nur Methode. Ohne Methode und ohne
//   Wörter wird nicht gesucht (nur die Klasse träfe zu viel).
// - Rangfolge: Treffer der früheren Suche zuerst, jede Kennung einmal,
//   höchstens cMaxErrors; erledigt nach Zustand wie beim Arbeitsstand (#2052).
// - Zwischenspeicher je Signatur für die Sitzung der IDE: Eine Signatur wird
//   einmal gesucht, auch ohne Netz (dann ohne Treffer).
// - Text für „Als Kommentar anhängen“ und „Neues Issue …“ (Markdown) mit
//   Klasse, Meldung, Ort, eigenen Rahmen und Branch; die Beschriftungen kommen
//   vom Aufrufer (Modultexte).

interface

uses
  System.Generics.Collections,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.KnownErrors.Contract;

type
  /// <summary>Signatur eines Halts.</summary>
  TAtlasKnownErrorSignature = record
    ExceptionClass: string;
    /// <summary>Meldung ohne Zahlen, Adressen, Pfade und Anführungsinhalte.</summary>
    Message: string;
    /// <summary>Oberste eigene Methode ohne Unit ("TFoo.Bar", "DoIt"); '' ohne.</summary>
    Method: string;
    class function FromReport(const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorSignature; static;
    /// <summary>AText ohne Anführungsinhalte, Pfade, Adressen und Zahlen; Leerraum zusammengefasst.</summary>
    class function CleanMessage(const AText: string): string; static;
    /// <summary>"Unit1.TFoo.Bar" → "TFoo.Bar", "Unit1.DoIt" → "DoIt".</summary>
    class function ShortMethod(const ARoutine: string): string; static;
    /// <summary>Schlüssel für den Zwischenspeicher, ohne Groß/klein.</summary>
    function Key: string;
    /// <summary>Wörter der Meldung (ab vier Buchstaben, höchstens vier, jedes einmal).</summary>
    function Words: TArray<string>;
  end;

  /// <summary>Beschriftungen des Kommentars bzw. des neuen Issues (Modultexte, Sprache der IDE).</summary>
  TAtlasKnownErrorLabels = record
    /// <summary>Erste Zeile des Kommentars („Wieder aufgetreten beim Debuggen“).</summary>
    Again: string;
    Location: string;
    /// <summary>Überschrift der eigenen Rahmen („Aufrufstapel (eigener Code)“).</summary>
    Stack: string;
    Branch: string;
  end;

  TAtlasKnownErrorSearch = class
  public const
    /// <summary>Höchstens so viele Treffer zeigt die Leiste.</summary>
    cMaxErrors = 4;
    /// <summary>Höchstens so viele Issues je Suche.</summary>
    cMaxPerQuery = 5;
    /// <summary>Höchstens so viele eigene Rahmen im Text.</summary>
    cMaxFrames = 10;
    /// <summary>Höchstens so lang wird der Titel eines neuen Issues.</summary>
    cMaxTitle = 120;
  public
    /// <summary>Suchtexte in der Rangfolge; leer, wenn nicht gesucht werden soll.</summary>
    class function Queries(const ASignature: TAtlasKnownErrorSignature): TArray<string>; static;
    /// <summary>Treffer aus den Antworten AFound (je Suchtext eine, in derselben Reihenfolge).</summary>
    class function Rank(const AFound: TArray<TArray<TAtlasTrackerIssue>>; const AProvider: string;
      const AEndStates: TArray<string>): TArray<TAtlasKnownError>; static;
    /// <summary>Kommentar „wieder aufgetreten“ zu AReport.</summary>
    class function CommentText(const AReport: TAtlasDebugExceptionReport; const ALabels: TAtlasKnownErrorLabels;
      const ABranch: string): string; static;
    /// <summary>Beschreibung eines neuen Issues zu AReport (wie der Kommentar, ohne erste Zeile).</summary>
    class function IssueText(const AReport: TAtlasDebugExceptionReport; const ALabels: TAtlasKnownErrorLabels;
      const ABranch: string): string; static;
    /// <summary>Titel eines neuen Issues: „EClass in TFoo.Bar: Meldung“, gekürzt.</summary>
    class function IssueTitle(const AReport: TAtlasDebugExceptionReport): string; static;
    /// <summary>Branch aus dem Inhalt von &lt;gitdir&gt;/HEAD ("ref: refs/heads/x" → "x"); losgelöst die ersten acht
    /// Zeichen des Commits.</summary>
    class function BranchOfHead(const AHead: string): string; static;
  end;

  /// <summary>Ergebnisse je Signatur für die Sitzung der IDE. Nur im Hauptthread.</summary>
  TAtlasKnownErrorsCache = class
  public const
    /// <summary>So viele Signaturen merkt sich der Speicher; danach beginnt er von vorn.</summary>
    cMaxEntries = 64;
  private
    FDone: TDictionary<string, TArray<TAtlasKnownError>>;
    FBusy: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Stand zu AKey: Done mit AErrors, Busy, sonst Off (noch nie gesucht).</summary>
    function StateOf(const AKey: string; out AErrors: TArray<TAtlasKnownError>): TAtlasKnownErrorsState;
    /// <summary>Suche für AKey beginnt.</summary>
    procedure Started(const AKey: string);
    /// <summary>Suche für AKey fertig; ohne Netz mit leeren AErrors.</summary>
    procedure Finished(const AKey: string; const AErrors: TArray<TAtlasKnownError>);
    procedure Clear;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars,
  Atlas.Core.Tracker.IssueWork;

const
  cMinWordLength = 4;
  cMaxWords = 4;
  cQuote = '"';

function IsLetter(AChar: Char): Boolean;
begin
  Result := TTextChars.IsIdentStart(AChar) and (AChar <> '_');
end;

/// <summary>Nur Hexziffern und mindestens eine Ziffer?</summary>
function IsHexWithDigit(const AText: string): Boolean;
var
  mChar: Char;
  mDigit: Boolean;
begin
  mDigit := False;
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      Exit(False);
    end;
    mDigit := mDigit or CharInSet(mChar, ['0'..'9']);
  end;
  Result := mDigit;
end;

/// <summary>Beginnt an AIndex ein Anführungsinhalt (Zeichen am Wortanfang)?</summary>
function OpensQuote(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (CharInSet(AText[AIndex], ['''', '"']) or (AText[AIndex] = #$201E) or (AText[AIndex] = #$201C)) and
    ((AIndex = 1) or CharInSet(AText[AIndex - 1], [' ', '(', ':', '=', #9]));
end;

/// <summary>Teil zwischen Anführungszeichen (auch „…“ und '…') entfernen.</summary>
function WithoutQuoted(const AText: string): string;
var
  mIndex: Integer;
  mClose: Char;
  mInside: Boolean;
begin
  Result := '';
  mInside := False;
  mClose := #0;
  for mIndex := 1 to Length(AText) do
  begin
    if mInside then
    begin
      mInside := AText[mIndex] <> mClose;
    end
    else if OpensQuote(AText, mIndex) then
    begin
      mInside := True;
      mClose := AText[mIndex];
      if mClose = #$201E then
      begin
        mClose := #$201C;
      end;
    end
    else
    begin
      Result := Result + AText[mIndex];
    end;
  end;
end;

/// <summary>Pfad ("C:\…", "\\server\…", "/usr/…") oder Adresse ("$0040A1B2", "0x1F", "0040A1B2")?</summary>
function IsNoise(const AWord: string): Boolean;
var
  mHex: string;
begin
  Result := (Pos('\', AWord) > 0) or (Pos('/', AWord) > 0);
  if Result or (AWord = '') then
  begin
    Exit;
  end;
  mHex := AWord;
  if StartsText('0x', mHex) then
  begin
    mHex := Copy(mHex, 3, MaxInt);
  end
  else if mHex[1] = '$' then
  begin
    mHex := Copy(mHex, 2, MaxInt);
  end;
  mHex := mHex.TrimRight(['.', ',', ';', ':', ')']);
  Result := (Length(mHex) >= 4) and IsHexWithDigit(mHex);
end;

function WithoutDigits(const AText: string): string;
var
  mChar: Char;
begin
  Result := '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9']) then
    begin
      Result := Result + mChar;
    end;
  end;
  // Aus (5) wird (): leere Klammern fallen weg.
  Result := Result.Replace('()', '').Replace('[]', '');
end;

/// <summary>Leerraum zusammenfassen, kein Leerzeichen vor Satzzeichen.</summary>
function Tidy(const AWords: TArray<string>): string;
var
  mWord: string;
begin
  Result := '';
  for mWord in AWords do
  begin
    if mWord = '' then
    begin
      Continue;
    end;
    if (Result <> '') and not CharInSet(mWord[1], ['.', ',', ';', ':', ')', '!', '?']) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mWord;
  end;
end;

{ TAtlasKnownErrorSignature }

class function TAtlasKnownErrorSignature.CleanMessage(const AText: string): string;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  mWords := WithoutQuoted(AText).Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ').Split([' ']);
  for mIndex := 0 to High(mWords) do
  begin
    if IsNoise(mWords[mIndex]) then
    begin
      mWords[mIndex] := '';
    end
    else
    begin
      mWords[mIndex] := WithoutDigits(mWords[mIndex]);
    end;
  end;
  Result := Tidy(mWords);
end;

class function TAtlasKnownErrorSignature.ShortMethod(const ARoutine: string): string;
var
  mParts: TArray<string>;
  mIndex, mPart: Integer;
begin
  mParts := Trim(ARoutine).Split(['.']);
  if Length(mParts) = 0 then
  begin
    Exit('');
  end;
  // Von vorn der erste Teil, der wie ein Typ aussieht (T bzw. I und ein Großbuchstabe), samt Rest: verschachtelte
  // Typen bleiben ganz.
  for mIndex := 0 to High(mParts) - 1 do
  begin
    if (Length(mParts[mIndex]) > 1) and CharInSet(mParts[mIndex][1], ['T', 'I']) and
      CharInSet(mParts[mIndex][2], ['A'..'Z']) then
    begin
      Result := mParts[mIndex];
      for mPart := mIndex + 1 to High(mParts) do
      begin
        Result := Result + '.' + mParts[mPart];
      end;
      Exit;
    end;
  end;
  Result := mParts[High(mParts)];
end;

class function TAtlasKnownErrorSignature.FromReport(
  const AReport: TAtlasDebugExceptionReport): TAtlasKnownErrorSignature;
begin
  Result.ExceptionClass := Trim(AReport.ExceptionClass);
  Result.Message := CleanMessage(AReport.ExceptionMessage);
  Result.Method := '';
  if Length(AReport.OwnMethods) > 0 then
  begin
    Result.Method := ShortMethod(AReport.OwnMethods[0]);
  end;
end;

function TAtlasKnownErrorSignature.Key: string;
begin
  Result := LowerCase(ExceptionClass + '|' + Message + '|' + Method);
end;

function TAtlasKnownErrorSignature.Words: TArray<string>;
var
  mWord, mCurrent: string;
  mChar: Char;
begin
  Result := nil;
  mCurrent := '';
  for mChar in Message + ' ' do
  begin
    if IsLetter(mChar) then
    begin
      mCurrent := mCurrent + mChar;
      Continue;
    end;
    mWord := mCurrent;
    mCurrent := '';
    if (Length(mWord) >= cMinWordLength) and (Length(Result) < cMaxWords) and
      not MatchText(mWord, Result) then
    begin
      Result := Result + [mWord];
    end;
  end;
end;

{ TAtlasKnownErrorSearch }

class function TAtlasKnownErrorSearch.Queries(const ASignature: TAtlasKnownErrorSignature): TArray<string>;
var
  mWords: TArray<string>;
  mClass, mMethod: string;
begin
  Result := nil;
  if ASignature.ExceptionClass = '' then
  begin
    Exit;
  end;
  mClass := cQuote + ASignature.ExceptionClass + cQuote;
  mMethod := '';
  if ASignature.Method <> '' then
  begin
    mMethod := cQuote + ASignature.Method + cQuote;
    Result := Result + [mClass + ' ' + mMethod];
  end;
  mWords := ASignature.Words;
  if Length(mWords) > 0 then
  begin
    Result := Result + [mClass + ' ' + string.Join(' ', mWords)];
  end;
  if mMethod <> '' then
  begin
    Result := Result + [mMethod];
  end;
end;

class function TAtlasKnownErrorSearch.Rank(const AFound: TArray<TArray<TAtlasTrackerIssue>>;
  const AProvider: string; const AEndStates: TArray<string>): TArray<TAtlasKnownError>;
var
  mIssues: TArray<TAtlasTrackerIssue>;
  mIssue: TAtlasTrackerIssue;
  mError: TAtlasKnownError;
  mSeen: TArray<string>;
begin
  Result := nil;
  mSeen := nil;
  for mIssues in AFound do
  begin
    for mIssue in mIssues do
    begin
      if (Length(Result) >= cMaxErrors) or (mIssue.Key = '') or MatchText(mIssue.Key, mSeen) then
      begin
        Continue;
      end;
      mSeen := mSeen + [mIssue.Key];
      mError := Default(TAtlasKnownError);
      mError.Key := mIssue.Key;
      mError.Title := mIssue.Title;
      mError.State := mIssue.State;
      mError.Assignee := mIssue.Assignee;
      mError.Resolved := TAtlasTrackerIssueStates.IsResolvedState(AProvider, mIssue.State, AEndStates);
      Result := Result + [mError];
    end;
  end;
end;

/// <summary>Klasse, Meldung, Ort, Branch und eigene Rahmen als Markdown.</summary>
function Details(const AReport: TAtlasDebugExceptionReport; const ALabels: TAtlasKnownErrorLabels;
  const ABranch: string): string;
var
  mIndex: Integer;
begin
  Result := '`' + AReport.ExceptionClass + '`';
  if Trim(AReport.ExceptionMessage) <> '' then
  begin
    Result := Result + ': ' + Trim(AReport.ExceptionMessage);
  end;
  Result := Result + #10;
  if AReport.FileName <> '' then
  begin
    Result := Result + #10 + ALabels.Location + ': `' + ExtractFileName(AReport.FileName);
    if AReport.Line > 0 then
    begin
      Result := Result + ':' + IntToStr(AReport.Line);
    end;
    Result := Result + '`' + #10;
  end;
  if ABranch <> '' then
  begin
    Result := Result + ALabels.Branch + ': `' + ABranch + '`' + #10;
  end;
  if Length(AReport.OwnFrames) > 0 then
  begin
    Result := Result + #10 + ALabels.Stack + ':' + #10;
    for mIndex := 0 to High(AReport.OwnFrames) do
    begin
      if mIndex >= TAtlasKnownErrorSearch.cMaxFrames then
      begin
        Break;
      end;
      Result := Result + '- `' + AReport.OwnFrames[mIndex] + '`' + #10;
    end;
  end;
end;

class function TAtlasKnownErrorSearch.CommentText(const AReport: TAtlasDebugExceptionReport;
  const ALabels: TAtlasKnownErrorLabels; const ABranch: string): string;
begin
  Result := '**' + ALabels.Again + '**' + #10#10 + Details(AReport, ALabels, ABranch);
end;

class function TAtlasKnownErrorSearch.IssueText(const AReport: TAtlasDebugExceptionReport;
  const ALabels: TAtlasKnownErrorLabels; const ABranch: string): string;
begin
  Result := Details(AReport, ALabels, ABranch);
end;

class function TAtlasKnownErrorSearch.IssueTitle(const AReport: TAtlasDebugExceptionReport): string;
var
  mSignature: TAtlasKnownErrorSignature;
begin
  mSignature := TAtlasKnownErrorSignature.FromReport(AReport);
  Result := mSignature.ExceptionClass;
  if mSignature.Method <> '' then
  begin
    Result := Result + ' in ' + mSignature.Method;
  end;
  if mSignature.Message <> '' then
  begin
    Result := Result + ': ' + mSignature.Message;
  end;
  if Length(Result) > cMaxTitle then
  begin
    Result := Copy(Result, 1, cMaxTitle - 1) + #$2026;
  end;
end;

class function TAtlasKnownErrorSearch.BranchOfHead(const AHead: string): string;
const
  cRef = 'ref: refs/heads/';
  cShortSha = 8;
begin
  Result := Trim(AHead);
  if StartsText(cRef, Result) then
  begin
    Result := Copy(Result, Length(cRef) + 1, MaxInt);
  end
  else
  begin
    Result := Copy(Result, 1, cShortSha);
  end;
end;

{ TAtlasKnownErrorsCache }

constructor TAtlasKnownErrorsCache.Create;
begin
  inherited Create;
  FDone := TDictionary<string, TArray<TAtlasKnownError>>.Create;
  FBusy := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasKnownErrorsCache.Destroy;
begin
  FBusy.Free;
  FDone.Free;
  inherited;
end;

function TAtlasKnownErrorsCache.StateOf(const AKey: string;
  out AErrors: TArray<TAtlasKnownError>): TAtlasKnownErrorsState;
var
  mErrors: TArray<TAtlasKnownError>;
begin
  AErrors := nil;
  if FDone.TryGetValue(AKey, mErrors) then
  begin
    AErrors := mErrors;
    Result := TAtlasKnownErrorsState.Done;
  end
  else if FBusy.ContainsKey(AKey) then
  begin
    Result := TAtlasKnownErrorsState.Busy;
  end
  else
  begin
    Result := TAtlasKnownErrorsState.Off;
  end;
end;

procedure TAtlasKnownErrorsCache.Started(const AKey: string);
begin
  FBusy.AddOrSetValue(AKey, True);
end;

procedure TAtlasKnownErrorsCache.Finished(const AKey: string; const AErrors: TArray<TAtlasKnownError>);
begin
  FBusy.Remove(AKey);
  if FDone.Count >= cMaxEntries then
  begin
    FDone.Clear;
  end;
  FDone.AddOrSetValue(AKey, AErrors);
end;

procedure TAtlasKnownErrorsCache.Clear;
begin
  FDone.Clear;
  FBusy.Clear;
end;

end.
