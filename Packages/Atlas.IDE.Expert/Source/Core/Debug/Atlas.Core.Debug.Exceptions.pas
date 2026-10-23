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
  System.SysUtils;

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
    class function Create(ATime: TDateTime; const AClass, AMessage: string; AThreadId: Cardinal;
      const AThreadName, AFileName: string; ALine: Integer; const ARoutine: string): TAtlasDebugException; static;
    /// <summary>Schlüssel für „gleiche Exception am gleichen Ort“: Klasse, Datei und Zeile ohne Groß/klein.
    /// </summary>
    function Key: string;
    /// <summary>„Unit1.pas:42“ bzw. die Routine, wenn die Datei fehlt; '' ganz ohne Ort.</summary>
    function LocationText: string;
    /// <summary>„Hauptthread 1234“ bzw. „Name (1234)“.</summary>
    function ThreadText(const AMainLabel: string): string;
    /// <summary>Klasse, Meldung, Ort, Thread und Anzahl als Text zum Kopieren.</summary>
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
    MaxEntries = 1000;
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
  const AThreadName, AFileName: string; ALine: Integer; const ARoutine: string): TAtlasDebugException;
begin
  Result := Default(TAtlasDebugException);
  Result.FirstTime := ATime;
  Result.LastTime := ATime;
  Result.ExceptionClass := AClass;
  Result.Message := AMessage;
  Result.ThreadId := AThreadId;
  Result.ThreadName := AThreadName;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Routine := ARoutine;
  Result.Count := 1;
end;

function TAtlasDebugException.Key: string;
var
  Where: string;
begin
  Where := FileName;
  // Ohne Datei unterscheidet die Routine die Orte (Bibliothekscode ohne Quelltext).
  if Where = '' then
    Where := Routine;
  Result := LowerCase(ExceptionClass) + '|' + LowerCase(Where) + '|' + IntToStr(Line);
end;

function TAtlasDebugException.HasSource: Boolean;
begin
  Result := (FileName <> '') and (Line > 0);
end;

class function TAtlasDebugException.FilterWords(const AText: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in AText.ToLower.Split([' ', #9]) do
    if Part <> '' then
      Result := Result + [Part];
end;

function TAtlasDebugException.Matches(const AClass: string; const AWords: TArray<string>): Boolean;
var
  Haystack, Word: string;
begin
  Result := (AClass = '') or SameText(ExceptionClass, AClass);
  if not Result or (AWords = nil) then
    Exit;
  Haystack := (ExceptionClass + ' ' + Message + ' ' + LocationText + ' ' + Routine + ' ' + ThreadName + ' ' +
    IntToStr(ThreadId)).ToLower;
  for Word in AWords do
    if Pos(Word, Haystack) = 0 then
      Exit(False);
end;

function TAtlasDebugException.LocationText: string;
begin
  if FileName <> '' then
  begin
    Result := ExtractFileName(FileName);
    if Line > 0 then
      Result := Result + ':' + IntToStr(Line);
  end
  else
    Result := Routine;
end;

function TAtlasDebugException.ThreadText(const AMainLabel: string): string;
begin
  if ThreadName <> '' then
    Result := Format('%s (%d)', [ThreadName, ThreadId])
  else if AMainLabel <> '' then
    Result := Format('%s %d', [AMainLabel, ThreadId])
  else
    Result := IntToStr(ThreadId);
end;

function TAtlasDebugException.CopyText: string;
var
  Lines: TStringBuilder;
begin
  Lines := TStringBuilder.Create;
  try
    Lines.Append(ExceptionClass);
    if Message <> '' then
      Lines.Append(': ').Append(Message);
    Lines.AppendLine;
    if Routine <> '' then
      Lines.Append(Routine).AppendLine;
    if FileName <> '' then
    begin
      Lines.Append(FileName);
      if Line > 0 then
        Lines.Append('(').Append(Line).Append(')');
      Lines.AppendLine;
    end;
    Lines.Append('Thread ').Append(ThreadText('')).AppendLine;
    if Count > 1 then
      Lines.Append(Count).Append(' x').AppendLine;
    Result := Lines.ToString.TrimRight;
  finally
    Lines.Free;
  end;
end;

{ TAtlasDebugExceptionHistory }

constructor TAtlasDebugExceptionHistory.Create;
begin
  Create(MaxEntries);
end;

constructor TAtlasDebugExceptionHistory.Create(AMaxEntries: Integer);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  if FMaxEntries < 1 then
    FMaxEntries := 1;
end;

procedure TAtlasDebugExceptionHistory.StartSession;
begin
  Inc(FSession);
  Clear;
end;

procedure TAtlasDebugExceptionHistory.Clear;
begin
  if FItems <> nil then
    FChanged := True;
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
  Index: Integer;
begin
  for Index := 0 to High(FItems) do
    if FItems[Index].Key = AKey then
      Exit(Index);
  Result := -1;
end;

function TAtlasDebugExceptionHistory.OldestIndex: Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to High(FItems) do
    if FItems[Index].LastTime < FItems[Result].LastTime then
      Result := Index;
end;

function TAtlasDebugExceptionHistory.Add(const AException: TAtlasDebugException): Integer;
var
  Entry: TAtlasDebugException;
begin
  FChanged := True;
  Result := IndexOfKey(AException.Key);
  if Result >= 0 then
  begin
    Entry := FItems[Result];
    Inc(Entry.Count, Max(1, AException.Count));
    Entry.LastTime := AException.LastTime;
    Entry.Message := AException.Message;
    Entry.ThreadId := AException.ThreadId;
    Entry.ThreadName := AException.ThreadName;
    // Ein Halt mit Dialog zählt als „nicht ignoriert“.
    Entry.Ignored := Entry.Ignored and AException.Ignored;
    FItems[Result] := Entry;
    Exit;
  end;
  Entry := AException;
  if Entry.Count < 1 then
    Entry.Count := 1;
  if Length(FItems) >= FMaxEntries then
    Delete(FItems, OldestIndex, 1);
  FItems := FItems + [Entry];
  Result := High(FItems);
end;

function TAtlasDebugExceptionHistory.Filter(const AClass, AText: string): TArray<Integer>;
var
  Words: TArray<string>;
  Index: Integer;
  List: TList<Integer>;
begin
  Words := TAtlasDebugException.FilterWords(AText);
  List := TList<Integer>.Create;
  try
    for Index := 0 to High(FItems) do
      if FItems[Index].Matches(AClass, Words) then
        List.Add(Index);
    // Zuletzt gesehen zuerst; bei gleicher Zeit der spätere Eintrag zuerst (TList.Sort ist nicht stabil).
    List.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        if FItems[ALeft].LastTime > FItems[ARight].LastTime then
          Result := -1
        else if FItems[ALeft].LastTime < FItems[ARight].LastTime then
          Result := 1
        else
          Result := ARight - ALeft;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TAtlasDebugExceptionHistory.Classes: TArray<string>;
var
  Entry: TAtlasDebugException;
  Known: TList<string>;
  Name: string;
  Found: Boolean;
begin
  Known := TList<string>.Create;
  try
    for Entry in FItems do
    begin
      Found := False;
      for Name in Known do
        if SameText(Name, Entry.ExceptionClass) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Known.Add(Entry.ExceptionClass);
    end;
    Known.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
        if Result = 0 then
          Result := CompareStr(ALeft, ARight);
      end));
    Result := Known.ToArray;
  finally
    Known.Free;
  end;
end;

function TAtlasDebugExceptionHistory.Total: Integer;
var
  Entry: TAtlasDebugException;
begin
  Result := 0;
  for Entry in FItems do
    Inc(Result, Entry.Count);
end;

function TAtlasDebugExceptionHistory.TryFind(const AKey: string; out AException: TAtlasDebugException): Boolean;
var
  Index: Integer;
begin
  Index := IndexOfKey(AKey);
  Result := Index >= 0;
  if Result then
    AException := FItems[Index]
  else
    AException := Default(TAtlasDebugException);
end;

function TAtlasDebugExceptionHistory.TakeChanged: Boolean;
begin
  Result := FChanged;
  FChanged := False;
end;

{ TAtlasDebugExceptionText }

class function TAtlasDebugExceptionText.IsClassName(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  if not Result then
    Exit;
  if not CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']) then
    Exit(False);
  for Index := 2 to Length(AText) do
    if not CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit(False);
end;

function TokenAfter(const AText, AKeyword: string; out AToken: string): Boolean;
var
  Start, Stop: Integer;
begin
  AToken := '';
  Start := Pos(LowerCase(AKeyword), LowerCase(AText));
  Result := Start > 0;
  if not Result then
    Exit;
  Start := Start + Length(AKeyword);
  while (Start <= Length(AText)) and (AText[Start] = ' ') do
    Inc(Start);
  Stop := Start;
  while (Stop <= Length(AText)) and CharInSet(AText[Stop], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '$']) do
    Inc(Stop);
  // Ein Punkt am Ende gehört zum Satz.
  while (Stop > Start) and (AText[Stop - 1] = '.') do
    Dec(Stop);
  AToken := Copy(AText, Start, Stop - Start);
  Result := AToken <> '';
end;

function QuotedAfter(const AText, AKeyword: string; out AQuoted: string): Boolean;
var
  Start, Stop: Integer;
begin
  AQuoted := '';
  Start := Pos(LowerCase(AKeyword), LowerCase(AText));
  Result := Start > 0;
  if not Result then
    Exit;
  Start := PosEx('''', AText, Start + Length(AKeyword));
  if Start = 0 then
    Exit(False);
  // Die Meldung selbst darf Hochkommas enthalten; sie endet am letzten Hochkomma des Texts.
  Stop := LastDelimiter('''', AText);
  if Stop <= Start then
    Exit(False);
  AQuoted := Copy(AText, Start + 1, Stop - Start - 1);
end;

class function TAtlasDebugExceptionText.Parse(const AText: string; out AClass, AMessage: string): Boolean;
const
  // Englisch und deutsch; „class“ zuletzt, weil es auch in anderen Wörtern steckt.
  ClassKeywords: array[0..3] of string = ('exception class', 'der Klasse', 'Exception-Klasse', 'class');
  MessageKeywords: array[0..2] of string = ('with message', 'mit der Meldung', 'Meldung');
var
  Keyword: string;
  Text: string;
begin
  AClass := '';
  AMessage := '';
  Text := StringReplace(AText, sLineBreak, ' ', [rfReplaceAll]);
  Text := StringReplace(Text, #10, ' ', [rfReplaceAll]);
  for Keyword in ClassKeywords do
    if TokenAfter(Text, Keyword + ' ', AClass) then
      if IsClassName(AClass) or (Copy(AClass, 1, 1) = '$') then
        Break
      else
        AClass := '';
  Result := AClass <> '';
  if not Result then
    Exit;
  for Keyword in MessageKeywords do
    if QuotedAfter(Text, Keyword, AMessage) then
      Break;
end;

class function TAtlasDebugExceptionText.Unquote(const AText: string): string;
var
  Text: string;
begin
  Text := Trim(AText);
  if (Length(Text) >= 2) and (Text[1] = '''') and (Text[Length(Text)] = '''') then
    Result := StringReplace(Copy(Text, 2, Length(Text) - 2), '''''', '''', [rfReplaceAll])
  else
    Result := Text;
end;

end.
