unit Atlas.Core.Debug.Exceptions;

// Exception-Verlauf beim Debuggen (#517), ohne VCL und Open Tools API:
//   - TAtlasDebugException: eine Exception der Sitzung mit Uhrzeit, Klasse,
//     Meldung, Thread und Ort (Datei, Zeile, Routine). Gleiche Exceptions
//     (Klasse, Datei, Zeile) zählen in einem Eintrag hoch.
//   - TAtlasDebugExceptionHistory: höchstens MaxEntries Einträge; ist die
//     Liste voll, fällt der am längsten nicht mehr gesehene heraus. Filter nach
//     Klasse und Text; gezeigt wird der zuletzt gesehene zuerst. Die Liste
//     bleibt bis zum Start der nächsten Debug-Sitzung (StartSession).
//   - TAtlasDebugExceptionText: Klasse und Meldung aus den Texten des
//     Debuggers lesen. Quellen sind die Meldung der IDE („Project X.exe raised
//     exception class EConvertError with message '…'.“ bzw. „Im Projekt X.exe
//     ist eine Exception der Klasse … mit der Meldung '…' aufgetreten.“) und
//     die Ergebnisse von IOTAThread.Evaluate (Strings in Hochkommas). Welche
//     Quelle in welcher IDE-Version greift, klärt die Studie aus #783.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack;

type
  TAtlasDebugException = record
    /// <summary>Zuerst gesehen (Ortszeit).</summary>
    FirstTime: TDateTime;
    /// <summary>Zuletzt gesehen (Ortszeit).</summary>
    LastTime: TDateTime;
    ExceptionClass: string;
    Message: string;
    ThreadId: Cardinal;
    /// <summary>Name des Threads ('' = ohne Namen, etwa der Hauptthread ohne TThread.NameThreadForDebugging).
    /// </summary>
    ThreadName: string;
    /// <summary>Datei des Orts ('' = unbekannt, z. B. ohne Quelltext).</summary>
    FileName: string;
    /// <summary>Zeile des Orts, 1-basiert; 0 = unbekannt.</summary>
    Line: Integer;
    /// <summary>Routine wie im Aufrufstapel der IDE, z. B. „Unit1.TForm1.Button1Click“.</summary>
    Routine: string;
    /// <summary>Wie oft diese Exception an diesem Ort in der Sitzung kam.</summary>
    Count: Integer;
    /// <summary>Atlas hat die Exception still fortgesetzt (Ignorier-Liste, #783); nur im Verlauf gezählt.</summary>
    Ignored: Boolean;
    /// <summary>Aufrufstapel des letzten Auftretens (#578: Anzeige im Fenster, Kopieren).</summary>
    Frames: TAtlasDebugFrames;
    /// <summary>Exception ohne Ort; den Ort setzt At.</summary>
    class function Create(ATime: TDateTime; const AClass, AMessage: string; AThreadId: Cardinal;
      const AThreadName: string): TAtlasDebugException; static;
    /// <summary>Kopie mit dem Ort: Datei, Zeile (1-basiert, 0 = unbekannt) und Routine.</summary>
    function At(const AFileName: string; ALine: Integer; const ARoutine: string): TAtlasDebugException;
    /// <summary>Schlüssel für „gleiche Exception am gleichen Ort“: Klasse, Datei und Zeile ohne Groß/klein.
    /// </summary>
    function Key: string;
    /// <summary>„Unit1.pas:42“ bzw. die Routine, wenn die Datei fehlt; '' ganz ohne Ort.</summary>
    function LocationText: string;
    /// <summary>„Hauptthread 1234“ bzw. „Name (1234)“.</summary>
    function ThreadText(const AMainLabel: string): string;
    /// <summary>Klasse, Meldung, Ort, Thread, Anzahl und Aufrufstapel als Text zum Kopieren.</summary>
    function CopyText: string;
    function HasSource: Boolean;
    /// <summary>Passt zum Filter? AClass = '' für alle Klassen, sonst genau diese (ohne Groß/klein); jedes Wort
    /// aus AWords (klein, siehe FilterWords) kommt in Klasse, Meldung, Ort, Routine oder Thread vor.</summary>
    function Matches(const AClass: string; const AWords: TArray<string>): Boolean;
    /// <summary>Filtertext in kleine Wörter zerlegen.</summary>
    class function FilterWords(const AText: string): TArray<string>; static;
  end;

  TAtlasDebugExceptions = TArray<TAtlasDebugException>;

  TAtlasDebugExceptionHistory = class
  public const
    cMaxEntries = 1000;
  private
    FItems: TAtlasDebugExceptions;
    FSession: Integer;
    FChanged: Boolean;
    FMaxEntries: Integer;
    function IndexOfKey(const AKey: string): Integer;
    function OldestIndex: Integer;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TAtlasDebugException;
  public
    constructor Create; overload;
    /// <summary>Für Tests: eigene Höchstzahl.</summary>
    constructor Create(AMaxEntries: Integer); overload;
    /// <summary>Neue Debug-Sitzung: Liste leeren, Sitzungszähler weiter.</summary>
    procedure StartSession;
    procedure Clear;
    /// <summary>Exception aufnehmen; gleiche (Key) zählt hoch, übernimmt Uhrzeit, Meldung und Thread des letzten
    /// Auftretens. Liefert den Index des Eintrags.</summary>
    function Add(const AException: TAtlasDebugException): Integer;
    /// <summary>Indizes der Einträge, die zum Filter passen, zuletzt gesehene zuerst. AClass = '' für alle
    /// Klassen, sonst genau diese Klasse (ohne Groß/klein). AText: Jedes Wort muss in Klasse, Meldung, Ort,
    /// Routine oder Thread vorkommen.</summary>
    function Filter(const AClass, AText: string): TArray<Integer>;
    /// <summary>Klassen im Verlauf, sortiert, ohne Doppel.</summary>
    function Classes: TArray<string>;
    /// <summary>Anzahl aller Auftreten (Summe der Zähler).</summary>
    function Total: Integer;
    /// <summary>Eintrag zum Schlüssel; False, wenn es ihn nicht gibt.</summary>
    function TryFind(const AKey: string; out AException: TAtlasDebugException): Boolean;
    /// <summary>Seit dem letzten Aufruf geändert? Setzt den Merker zurück.</summary>
    function TakeChanged: Boolean;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TAtlasDebugException read GetItem; default;
    property Session: Integer read FSession;
  end;

  TAtlasDebugExceptionText = record
  public
    /// <summary>Klasse und Meldung aus einer Meldung des Debuggers (deutsch oder englisch). Die Klasse kann auch
    /// ein Code wie „$C0000005“ sein. False, wenn keine Klasse erkennbar ist.</summary>
    class function Parse(const AText: string; out AClass, AMessage: string): Boolean; static;
    /// <summary>Ergebnis einer Auswertung ohne Hochkommas: „'Abc'“ → „Abc“, „''“ innen → „'“. Ohne Hochkommas
    /// unverändert.</summary>
    class function Unquote(const AText: string): string; static;
    /// <summary>Ist AText ein gültiger Klassenname (Bezeichner, auch mit Punkten)?</summary>
    class function IsClassName(const AText: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  System.StrUtils;

{ TAtlasDebugException }

class function TAtlasDebugException.Create(ATime: TDateTime; const AClass, AMessage: string; AThreadId: Cardinal;
  const AThreadName: string): TAtlasDebugException;
begin
  Result := Default(TAtlasDebugException);
  Result.FirstTime := ATime;
  Result.LastTime := ATime;
  Result.ExceptionClass := AClass;
  Result.Message := AMessage;
  Result.ThreadId := AThreadId;
  Result.ThreadName := AThreadName;
  Result.Count := 1;
end;

function TAtlasDebugException.At(const AFileName: string; ALine: Integer; const ARoutine: string):
  TAtlasDebugException;
begin
  Result := Self;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Routine := ARoutine;
end;

function TAtlasDebugException.Key: string;
var
  mWhere: string;
begin
  mWhere := FileName;
  // Ohne Datei unterscheidet die Routine die Orte (Bibliothekscode ohne Quelltext).
  if mWhere = '' then
  begin
    mWhere := Routine;
  end;
  Result := LowerCase(ExceptionClass) + '|' + LowerCase(mWhere) + '|' + IntToStr(Line);
end;

function TAtlasDebugException.HasSource: Boolean;
begin
  Result := (FileName <> '') and (Line > 0);
end;

class function TAtlasDebugException.FilterWords(const AText: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in AText.ToLower.Split([' ', #9]) do
  begin
    if mPart <> '' then
    begin
      Result := Result + [mPart];
    end;
  end;
end;

function TAtlasDebugException.Matches(const AClass: string; const AWords: TArray<string>): Boolean;
var
  mHaystack, mWord: string;
begin
  Result := (AClass = '') or SameText(ExceptionClass, AClass);
  if not Result or (AWords = nil) then
  begin
    Exit;
  end;
  mHaystack := (ExceptionClass + ' ' + Message + ' ' + LocationText + ' ' + Routine + ' ' + ThreadName + ' ' +
    IntToStr(ThreadId)).ToLower;
  for mWord in AWords do
  begin
    if Pos(mWord, mHaystack) = 0 then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasDebugException.LocationText: string;
begin
  if FileName <> '' then
  begin
    Result := ExtractFileName(FileName);
    if Line > 0 then
    begin
      Result := Result + ':' + IntToStr(Line);
    end;
  end
  else
  begin
    Result := Routine;
  end;
end;

function TAtlasDebugException.ThreadText(const AMainLabel: string): string;
begin
  if ThreadName <> '' then
  begin
    Result := Format('%s (%d)', [ThreadName, ThreadId]);
  end
  else if AMainLabel <> '' then
  begin
    Result := Format('%s %d', [AMainLabel, ThreadId]);
  end
  else
  begin
    Result := IntToStr(ThreadId);
  end;
end;

function TAtlasDebugException.CopyText: string;
var
  mLines: TStringBuilder;
  mFrame: TAtlasDebugFrame;
begin
  mLines := TStringBuilder.Create;
  try
    mLines.Append(ExceptionClass);
    if Message <> '' then
    begin
      mLines.Append(': ').Append(Message);
    end;
    mLines.AppendLine;
    if Routine <> '' then
    begin
      mLines.Append(Routine).AppendLine;
    end;
    if FileName <> '' then
    begin
      mLines.Append(FileName);
      if Line > 0 then
      begin
        mLines.Append('(').Append(Line).Append(')');
      end;
      mLines.AppendLine;
    end;
    mLines.Append('Thread ').Append(ThreadText('')).AppendLine;
    if Count > 1 then
    begin
      mLines.Append(Count).Append(' x').AppendLine;
    end;
    for mFrame in Frames do
    begin
      mLines.Append('  ').Append(mFrame.Header);
      if mFrame.HasSource then
      begin
        mLines.Append(' (').Append(ExtractFileName(mFrame.FileName)).Append(':').Append(mFrame.Line).Append(')');
      end;
      mLines.AppendLine;
    end;
    Result := mLines.ToString.TrimRight;
  finally
    mLines.Free;
  end;
end;

{ TAtlasDebugExceptionHistory }

constructor TAtlasDebugExceptionHistory.Create;
begin
  Create(cMaxEntries);
end;

constructor TAtlasDebugExceptionHistory.Create(AMaxEntries: Integer);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  if FMaxEntries < 1 then
  begin
    FMaxEntries := 1;
  end;
end;

procedure TAtlasDebugExceptionHistory.StartSession;
begin
  Inc(FSession);
  Clear;
end;

procedure TAtlasDebugExceptionHistory.Clear;
begin
  if FItems <> nil then
  begin
    FChanged := True;
  end;
  FItems := nil;
end;

function TAtlasDebugExceptionHistory.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasDebugExceptionHistory.GetItem(AIndex: Integer): TAtlasDebugException;
begin
  Result := FItems[AIndex];
end;

function TAtlasDebugExceptionHistory.IndexOfKey(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Key = AKey then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDebugExceptionHistory.OldestIndex: Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to High(FItems) do
  begin
    if FItems[mIndex].LastTime < FItems[Result].LastTime then
    begin
      Result := mIndex;
    end;
  end;
end;

function TAtlasDebugExceptionHistory.Add(const AException: TAtlasDebugException): Integer;
var
  mEntry: TAtlasDebugException;
begin
  FChanged := True;
  Result := IndexOfKey(AException.Key);
  if Result >= 0 then
  begin
    mEntry := FItems[Result];
    Inc(mEntry.Count, Max(1, AException.Count));
    mEntry.LastTime := AException.LastTime;
    mEntry.Message := AException.Message;
    mEntry.ThreadId := AException.ThreadId;
    mEntry.ThreadName := AException.ThreadName;
    mEntry.Frames := AException.Frames;
    // Ein Halt mit Dialog zählt als „nicht ignoriert“.
    mEntry.Ignored := mEntry.Ignored and AException.Ignored;
    FItems[Result] := mEntry;
    Exit;
  end;
  mEntry := AException;
  if mEntry.Count < 1 then
  begin
    mEntry.Count := 1;
  end;
  if Length(FItems) >= FMaxEntries then
  begin
    Delete(FItems, OldestIndex, 1);
  end;
  FItems := FItems + [mEntry];
  Result := High(FItems);
end;

function TAtlasDebugExceptionHistory.Filter(const AClass, AText: string): TArray<Integer>;
var
  mWords: TArray<string>;
  mIndex: Integer;
  mList: TList<Integer>;
begin
  mWords := TAtlasDebugException.FilterWords(AText);
  mList := TList<Integer>.Create;
  try
    for mIndex := 0 to High(FItems) do
    begin
      if FItems[mIndex].Matches(AClass, mWords) then
      begin
        mList.Add(mIndex);
      end;
    end;
    // Zuletzt gesehen zuerst; bei gleicher Zeit der spätere Eintrag zuerst (TList.Sort ist nicht stabil).
    mList.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        if FItems[ALeft].LastTime > FItems[ARight].LastTime then
        begin
          Result := -1;
        end
        else if FItems[ALeft].LastTime < FItems[ARight].LastTime then
        begin
          Result := 1;
        end
        else
        begin
          Result := ARight - ALeft;
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasDebugExceptionHistory.Classes: TArray<string>;
var
  mEntry: TAtlasDebugException;
  mKnown: TList<string>;
  mName: string;
  mFound: Boolean;
begin
  mKnown := TList<string>.Create;
  try
    for mEntry in FItems do
    begin
      mFound := False;
      for mName in mKnown do
      begin
        if SameText(mName, mEntry.ExceptionClass) then
        begin
          mFound := True;
          Break;
        end;
      end;
      if not mFound then
      begin
        mKnown.Add(mEntry.ExceptionClass);
      end;
    end;
    mKnown.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
        if Result = 0 then
        begin
          Result := CompareStr(ALeft, ARight);
        end;
      end));
    Result := mKnown.ToArray;
  finally
    mKnown.Free;
  end;
end;

function TAtlasDebugExceptionHistory.Total: Integer;
var
  mEntry: TAtlasDebugException;
begin
  Result := 0;
  for mEntry in FItems do
  begin
    Inc(Result, mEntry.Count);
  end;
end;

function TAtlasDebugExceptionHistory.TryFind(const AKey: string; out AException: TAtlasDebugException): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOfKey(AKey);
  Result := mIndex >= 0;
  if Result then
  begin
    AException := FItems[mIndex];
  end
  else
  begin
    AException := Default(TAtlasDebugException);
  end;
end;

function TAtlasDebugExceptionHistory.TakeChanged: Boolean;
begin
  Result := FChanged;
  FChanged := False;
end;

{ TAtlasDebugExceptionText }

class function TAtlasDebugExceptionText.IsClassName(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  if not Result then
  begin
    Exit;
  end;
  if not CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Exit(False);
  end;
  for mIndex := 2 to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit(False);
    end;
  end;
end;

function TokenAfter(const AText, AKeyword: string; out AToken: string): Boolean;
var
  mStart, mStop: Integer;
begin
  AToken := '';
  mStart := Pos(LowerCase(AKeyword), LowerCase(AText));
  Result := mStart > 0;
  if not Result then
  begin
    Exit;
  end;
  mStart := mStart + Length(AKeyword);
  while (mStart <= Length(AText)) and (AText[mStart] = ' ') do
  begin
    Inc(mStart);
  end;
  mStop := mStart;
  while (mStop <= Length(AText)) and CharInSet(AText[mStop], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '$']) do
  begin
    Inc(mStop);
  end;
  // Ein Punkt am Ende gehört zum Satz.
  while (mStop > mStart) and (AText[mStop - 1] = '.') do
  begin
    Dec(mStop);
  end;
  AToken := Copy(AText, mStart, mStop - mStart);
  Result := AToken <> '';
end;

function QuotedAfter(const AText, AKeyword: string; out AQuoted: string): Boolean;
var
  mStart, mStop: Integer;
begin
  AQuoted := '';
  mStart := Pos(LowerCase(AKeyword), LowerCase(AText));
  Result := mStart > 0;
  if not Result then
  begin
    Exit;
  end;
  mStart := PosEx('''', AText, mStart + Length(AKeyword));
  if mStart = 0 then
  begin
    Exit(False);
  end;
  // Die Meldung selbst darf Hochkommas enthalten; sie endet am letzten Hochkomma des Texts.
  mStop := LastDelimiter('''', AText);
  if mStop <= mStart then
  begin
    Exit(False);
  end;
  AQuoted := Copy(AText, mStart + 1, mStop - mStart - 1);
end;

class function TAtlasDebugExceptionText.Parse(const AText: string; out AClass, AMessage: string): Boolean;
const
  // Englisch und deutsch; „class“ zuletzt, weil es auch in anderen Wörtern steckt.
  cClassKeywords: array[0..3] of string = ('exception class', 'der Klasse', 'Exception-Klasse', 'class');
  cMessageKeywords: array[0..2] of string = ('with message', 'mit der Meldung', 'Meldung');
var
  mKeyword: string;
  mText: string;
begin
  AClass := '';
  AMessage := '';
  mText := StringReplace(AText, sLineBreak, ' ', [rfReplaceAll]);
  mText := StringReplace(mText, #10, ' ', [rfReplaceAll]);
  for mKeyword in cClassKeywords do
  begin
    if TokenAfter(mText, mKeyword + ' ', AClass) then
    begin
      if IsClassName(AClass) or (Copy(AClass, 1, 1) = '$') then
      begin
        Break;
      end
      else
      begin
        AClass := '';
      end;
    end;
  end;
  Result := AClass <> '';
  if not Result then
  begin
    Exit;
  end;
  for mKeyword in cMessageKeywords do
  begin
    if QuotedAfter(mText, mKeyword, AMessage) then
    begin
      Break;
    end;
  end;
end;

class function TAtlasDebugExceptionText.Unquote(const AText: string): string;
var
  mText: string;
begin
  mText := Trim(AText);
  if (Length(mText) >= 2) and (mText[1] = '''') and (mText[Length(mText)] = '''') then
  begin
    Result := StringReplace(Copy(mText, 2, Length(mText) - 2), '''''', '''', [rfReplaceAll]);
  end
  else
  begin
    Result := mText;
  end;
end;

end.
