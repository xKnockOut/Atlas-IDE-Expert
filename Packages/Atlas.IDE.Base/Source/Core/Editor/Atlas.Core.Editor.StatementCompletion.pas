unit Atlas.Core.Editor.StatementCompletion;

// Anweisung vervollständigen (#697), ohne Open Tools API: Complete ergänzt,
// was der angefangenen Anweisung in der Cursorzeile fehlt, und sagt, wo der
// Cursor danach steht.
// - Offene Strings werden beendet, offene runde und eckige Klammern
//   geschlossen. Endet der Text auf "(", "[" oder ",", steht der Cursor vor
//   den ergänzten Klammern.
// - Kopfzeilen: "then" nach if, "do" nach while, with, on E: X und for (ohne
//   to/downto/in: "for I := 0" bekommt " to  do", der Cursor steht an der
//   Grenze), "of" nach case. Folgt nichts hinter then/do, entscheidet
//   BeginEnd über den Rumpf: Always immer begin/end, MultiLine nur, wenn
//   schon zwei Anweisungen eingerückt folgen (wie #676), Never nie. Ohne
//   Rumpf kommt eine eingerückte Zeile für den Cursor dazu.
// - begin, case … of, try und repeat bekommen ihr Ende (end; bzw. finally/
//   except … end; bzw. until), wenn es auf derselben Einrückung fehlt. Vor
//   else heißt es "end" ohne Semikolon.
// - Sonst kommt ein Semikolon ans Ende, vor einer else-Zeile keins (ein
//   vorhandenes fällt weg).
// - Routinenköpfe bekommen ihr Semikolon; im Typ meldet FollowUp, dass der
//   Rumpf über die Klassenvervollständigung des Servers kommen soll, im
//   implementation-Teil ohne Rumpf entsteht begin/end. case meldet FollowUp
//   für die Zweige eines Aufzählungstyps.
// - Ist nichts zu ergänzen, steht der Cursor in einer neuen Zeile darunter.
// Zeilen und Zeichen sind 0-basiert; Kommentare am Zeilenende bleiben stehen.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasBeginEndMode = (Always, MultiLine, Never);
  TAtlasTryKind = (TryFinally, TryExcept);
  TAtlasStatementFollowUp = (None, CaseBranches, MethodBody);
  {$SCOPEDENUMS OFF}

  TAtlasStatementOptions = record
    BeginEnd: TAtlasBeginEndMode;
    TryKind: TAtlasTryKind;
    /// <summary>Einrückungsweite (Blockeinzug der IDE).</summary>
    IndentWidth: Integer;
    /// <summary>Bei Methodendeklarationen im Typ den Rumpf anlegen lassen (FollowUp).</summary>
    MethodBody: Boolean;
    class function Defaults: TAtlasStatementOptions; static;
  end;

  /// <summary>Ersetzt OldCount Zeilen ab StartLine durch Lines; danach steht der Cursor in CursorLine,
  /// CursorCharacter. FollowUp: zusätzliche Code-Aktion des Servers an FollowLine, FollowCharacter (im neuen
  /// Text).</summary>
  TAtlasStatementEdit = record
    StartLine: Integer;
    OldCount: Integer;
    Lines: TArray<string>;
    CursorLine: Integer;
    CursorCharacter: Integer;
    FollowUp: TAtlasStatementFollowUp;
    FollowLine: Integer;
    FollowCharacter: Integer;
  end;

  TAtlasStatementCompleter = class
  public
    /// <summary>Vervollständigt die Anweisung in Zeile ALine. False, wenn nichts zu tun ist (leere Zeile,
    /// Kommentar).</summary>
    class function Complete(const AText: string; ALine: Integer; const AOptions: TAtlasStatementOptions;
      out AEdit: TAtlasStatementEdit): Boolean; static;
    /// <summary>Steht in ALine ein try ohne finally/except/end? Dann fragt die IDE bei tryKind "ask".</summary>
    class function NeedsTryKind(const AText: string; ALine: Integer): Boolean; static;
    /// <summary>AEdit auf ALines angewandt.</summary>
    class function Apply(const ALines: TArray<string>; const AEdit: TAtlasStatementEdit): TArray<string>; static;
    /// <summary>Nach den case-Zweigen des Servers: Folgt auf die leere Cursorzeile ACursorLine ein neuer Zweig
    /// ("alLeft: ;"), fällt sie weg und der Cursor steht vor dem ";" des ersten Zweigs. False ohne Zweige.
    /// </summary>
    class function AfterCaseBranches(var ALines: TArray<string>; var ACursorLine, ACursorCharacter: Integer):
      Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Chars;

type
  {$SCOPEDENUMS ON}
  TStatementKind = (Plain, IfHeader, LoopHeader, ForHeader, ElseHeader, CaseHeader, TryLine, RepeatLine,
    BeginLine, Routine);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Zeile ohne Einzug: Code bis zum Kommentar am Ende und was offen geblieben ist.</summary>
  TLineScan = record
    Code: string;
    /// <summary>Kommentar am Zeilenende samt Leerraum davor; '' ohne.</summary>
    Comment: string;
    OpenString: Boolean;
    Closers: string;
    HasAssign: Boolean;
    /// <summary>Wörter außerhalb von Strings und Kommentaren, kleingeschrieben, mit 1-basiertem Anfang in Code.
    /// </summary>
    Words: TArray<string>;
    Starts: TArray<Integer>;
  end;

  /// <summary>Ein Lauf von Complete: Zeilen, Ausgabe und was über die Cursorzeile bekannt ist.</summary>
  TStatementJob = class
  private
    FLines: TArray<string>;
    FOutput: TList<string>;
    FLine: Integer;
    FOptions: TAtlasStatementOptions;
    FEdit: TAtlasStatementEdit;
    FScan: TLineScan;
    FIndent: string;
    FStep: string;
    FCode: string;
    FEndWord: string;
    FKind: TStatementKind;
    /// <summary>Erstes Wort der Anweisung in FScan.Words.</summary>
    FFirst: Integer;
    /// <summary>Cursor in FCode (0-basiert); -1, solange nichts ihn festlegt.</summary>
    FCursor: Integer;
    /// <summary>Letzte Zeile des eingerückten Rumpfs; FLine ohne.</summary>
    FLast: Integer;
    /// <summary>Nächste Codezeile hinter dem Rumpf; -1 ohne.</summary>
    FAfter: Integer;
    FPlain: Boolean;
    FChanged: Boolean;
    FHasBody: Boolean;
    procedure CursorAt(ALineIndex, ACharacter: Integer);
    /// <summary>Neue Zeile AText vor der Zeile AAt der Ausgabe.</summary>
    procedure InsertLine(AAt: Integer; const AText: string);
    /// <summary>Cursorzeile mit Einzug AIndent nach Zeile AAt.</summary>
    procedure CursorLineAfter(AAt: Integer; const AIndent: string);
    /// <summary>Cursorzeile eingerückt hinter dem Rumpf bzw. hinter der Kopfzeile.</summary>
    procedure CursorInBody;
    /// <summary>begin, leere Zeile mit Cursor und AEndWord hinter der Cursorzeile.</summary>
    procedure InsertBeginEnd(const AEndWord: string);
    /// <summary>Beginnt die Zeile hinter dem Rumpf auf derselben Einrückung mit einem der Wörter?</summary>
    function AfterStarts(const AWords: array of string): Boolean;
    function Prepare: Boolean;
    /// <summary>Offenen String beenden, offene Klammern schließen.</summary>
    procedure CloseOpen;
    procedure AddForBounds;
    procedure EnsureSemicolon;
    /// <summary>Art der Anweisung bestimmen und die Kopfzeile ergänzen.</summary>
    procedure CompleteHead;
    procedure CompletePlain;
    procedure CompleteRoutine;
    procedure CompleteHeader;
    procedure CompleteBlock;
    procedure CompleteTry;
    procedure CompleteRepeat;
    /// <summary>Rumpf, Ende und Cursor nach der Art der Anweisung.</summary>
    procedure CompleteBody;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(const AText: string; ALine: Integer; const AOptions: TAtlasStatementOptions;
      var AEdit: TAtlasStatementEdit): Boolean;
  end;

const
  // Hinter diesen Wörtern kommt kein Semikolon.
  cOpenWords: array[0..23] of string = ('then', 'do', 'of', 'begin', 'else', 'try', 'repeat', 'finally', 'except',
    'var', 'const', 'type', 'private', 'protected', 'public', 'published', 'interface', 'implementation',
    'initialization', 'finalization', 'record', 'class', 'label', 'resourcestring');
  cRoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');
  cBodyStartWords: array[0..5] of string = ('begin', 'var', 'const', 'type', 'label', 'asm');

function LinesOf(const AText: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := AText.Split([#10]);
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex].EndsWith(#13) then
    begin
      Result[mIndex] := Copy(Result[mIndex], 1, Length(Result[mIndex]) - 1);
    end;
  end;
end;

function LeadingSpace(const ALine: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(ALine, 1, mIndex - 1);
end;

function InList(const AWord: string; const AList: array of string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    if mItem = AWord then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Erstes Wort der Zeile (kleingeschrieben) gleich AWord?</summary>
function StartsWord(const ALine, AWord: string): Boolean;
var
  mText: string;
begin
  mText := LowerCase(TrimLeft(ALine));
  Result := mText.StartsWith(AWord) and ((Length(mText) = Length(AWord)) or not TTextChars.IsAsciiIdentChar(mText[Length(AWord) + 1]));
end;

function StartsAnyWord(const ALine: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in AWords do
  begin
    if StartsWord(ALine, mWord) then
    begin
      Exit(True);
    end;
  end;
end;

function CharAt(const AText: string; AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(AText)) then
  begin
    Result := AText[AIndex];
  end;
end;

/// <summary>Ein Zeichen Code ab AIndex: String überspringen, Zeilenkommentar, Beginn eines Blockkommentars.
/// Ergebnis: Stelle des zuletzt gelesenen Zeichens.</summary>
function CodeStep(const AText: string; AIndex: Integer; var ABrace, AParenStar: Boolean): Integer;
begin
  Result := AIndex;
  if AText[AIndex] = '''' then
  begin
    Inc(Result);
    while (Result <= Length(AText)) and (AText[Result] <> '''') do
    begin
      Inc(Result);
    end;
  end
  else if (AText[AIndex] = '/') and (CharAt(AText, AIndex + 1) = '/') then
  begin
    Result := Length(AText);
  end
  else if AText[AIndex] = '{' then
  begin
    ABrace := True;
  end
  else if (AText[AIndex] = '(') and (CharAt(AText, AIndex + 1) = '*') then
  begin
    AParenStar := True;
    Inc(Result);
  end;
end;

/// <summary>Verfolgt offene Blockkommentare über die Zeile AText.</summary>
procedure TrackComments(const AText: string; var ABrace, AParenStar: Boolean);
var
  mIndex: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if ABrace then
    begin
      ABrace := AText[mIndex] <> '}';
    end
    else if AParenStar then
    begin
      if (AText[mIndex] = '*') and (CharAt(AText, mIndex + 1) = ')') then
      begin
        AParenStar := False;
        Inc(mIndex);
      end;
    end
    else
    begin
      mIndex := CodeStep(AText, mIndex, ABrace, AParenStar);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Beginnt ALine in einem Blockkommentar?</summary>
function StartsInComment(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mLine: Integer;
  mBrace, mParenStar: Boolean;
begin
  mBrace := False;
  mParenStar := False;
  for mLine := 0 to ALine - 1 do
  begin
    TrackComments(ALines[mLine], mBrace, mParenStar);
  end;
  Result := mBrace or mParenStar;
end;

type
  /// <summary>Liest eine Zeile ohne Einzug für ScanLine.</summary>
  TLineScanner = record
  private
    FBody: string;
    FIndex: Integer;
    FStack: string;
    FInString: Boolean;
    FCommentAt: Integer;
    FScan: TLineScan;
    function OpenBracket: Boolean;
    procedure CloseBracket;
    function Brace: Boolean;
    procedure Word;
    /// <summary>Verarbeitet das Zeichen an FIndex; False: Ab hier ist der Rest der Zeile Kommentar.</summary>
    function Step: Boolean;
    procedure Finish;
  public
    function Run(const ABody: string): TLineScan;
  end;

function TLineScanner.OpenBracket: Boolean;
var
  mClose: Integer;
begin
  Result := True;
  if (FBody[FIndex] <> '(') or (CharAt(FBody, FIndex + 1) <> '*') then
  begin
    FStack := FStack + FBody[FIndex];
    Exit;
  end;
  mClose := Pos('*)', FBody, FIndex + 2);
  if (mClose = 0) or (Trim(Copy(FBody, mClose + 2, MaxInt)) = '') then
  begin
    FCommentAt := FIndex;
    Result := False;
  end
  else
  begin
    FIndex := mClose + 1;
  end;
end;

procedure TLineScanner.CloseBracket;
var
  mOpen: Char;
begin
  mOpen := '[';
  if FBody[FIndex] = ')' then
  begin
    mOpen := '(';
  end;
  if (FStack <> '') and (FStack[Length(FStack)] = mOpen) then
  begin
    Delete(FStack, Length(FStack), 1);
  end;
end;

function TLineScanner.Brace: Boolean;
var
  mClose: Integer;
begin
  mClose := Pos('}', FBody, FIndex + 1);
  // Direktiven zählen wie Code; ein Kommentar mitten in der Zeile wird übersprungen.
  Result := (CharAt(FBody, FIndex + 1) = '$') or ((mClose > 0) and (Trim(Copy(FBody, mClose + 1, MaxInt)) <> ''));
  if not Result then
  begin
    FCommentAt := FIndex;
  end
  else if mClose = 0 then
  begin
    FIndex := Length(FBody);
  end
  else
  begin
    FIndex := mClose;
  end;
end;

procedure TLineScanner.Word;
var
  mStart: Integer;
begin
  mStart := FIndex;
  while (FIndex < Length(FBody)) and TTextChars.IsAsciiIdentChar(FBody[FIndex + 1]) do
  begin
    Inc(FIndex);
  end;
  // "&begin" ist ein Bezeichner, kein Schlüsselwort.
  if CharAt(FBody, mStart - 1) <> '&' then
  begin
    FScan.Words := FScan.Words + [LowerCase(Copy(FBody, mStart, FIndex - mStart + 1))];
    FScan.Starts := FScan.Starts + [mStart];
  end;
end;

function TLineScanner.Step: Boolean;
begin
  Result := True;
  if FInString then
  begin
    FInString := FBody[FIndex] <> '''';
    Exit;
  end;
  case FBody[FIndex] of
    '''':
      begin
        FInString := True;
      end;
    '(', '[':
      begin
        Result := OpenBracket;
      end;
    ')', ']':
      begin
        CloseBracket;
      end;
    '/':
      begin
        Result := CharAt(FBody, FIndex + 1) <> '/';
        if not Result then
        begin
          FCommentAt := FIndex;
        end;
      end;
    '{':
      begin
        Result := Brace;
      end;
    ':':
      begin
        FScan.HasAssign := FScan.HasAssign or (CharAt(FBody, FIndex + 1) = '=');
      end;
    'A'..'Z', 'a'..'z', '_':
      begin
        Word;
      end;
  end;
end;

procedure TLineScanner.Finish;
var
  mIndex: Integer;
begin
  if FCommentAt > 0 then
  begin
    FScan.Code := TrimRight(Copy(FBody, 1, FCommentAt - 1));
    FScan.Comment := Copy(FBody, Length(FScan.Code) + 1, MaxInt);
  end
  else
  begin
    FScan.Code := TrimRight(FBody);
  end;
  FScan.OpenString := FInString;
  for mIndex := Length(FStack) downto 1 do
  begin
    if FStack[mIndex] = '(' then
    begin
      FScan.Closers := FScan.Closers + ')';
    end
    else
    begin
      FScan.Closers := FScan.Closers + ']';
    end;
  end;
end;

function TLineScanner.Run(const ABody: string): TLineScan;
begin
  FBody := ABody;
  FIndex := 1;
  FStack := '';
  FInString := False;
  FCommentAt := 0;
  FScan := Default(TLineScan);
  while (FIndex <= Length(FBody)) and Step do
  begin
    Inc(FIndex);
  end;
  Finish;
  Result := FScan;
end;

function ScanLine(const ABody: string): TLineScan;
var
  mScanner: TLineScanner;
begin
  Result := mScanner.Run(ABody);
end;

function HasWord(const AScan: TLineScan; const AWord: string): Boolean;
begin
  Result := InList(AWord, AScan.Words);
end;

function WordIndex(const AScan: TLineScan; const AWord: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AScan.Words) do
  begin
    if AScan.Words[mIndex] = AWord then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Nächste nicht leere Zeile nach ALine; -1 ohne.</summary>
function NextCode(const ALines: TArray<string>; ALine: Integer): Integer;
begin
  Result := ALine + 1;
  while (Result <= High(ALines)) and (Trim(ALines[Result]) = '') do
  begin
    Inc(Result);
  end;
  if Result > High(ALines) then
  begin
    Result := -1;
  end;
end;

/// <summary>Letzte Zeile des tiefer eingerückten Rumpfs nach ALine (Leerzeilen dazwischen zählen mit); ALine ohne.
/// </summary>
function BodyEnd(const ALines: TArray<string>; ALine, AIndent: Integer): Integer;
var
  mNext: Integer;
begin
  Result := ALine;
  mNext := NextCode(ALines, Result);
  while (mNext >= 0) and (Length(LeadingSpace(ALines[mNext])) > AIndent) do
  begin
    Result := mNext;
    mNext := NextCode(ALines, Result);
  end;
end;

/// <summary>Anweisungen in den Zeilen AFirst..ALast: Zeilen, die mit ";" enden, und die letzte.</summary>
function StatementCount(const ALines: TArray<string>; AFirst, ALast: Integer): Integer;
var
  mLine: Integer;
  mCode: string;
begin
  Result := 0;
  for mLine := AFirst to ALast do
  begin
    mCode := ScanLine(Trim(ALines[mLine])).Code;
    if (mCode <> '') and (mCode.EndsWith(';') or (mLine = ALast)) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Ein Typkopf: "TFoo = class", "TFoo = class(TBar)", "= record", "= interface" (ohne Leerzeichen).
/// </summary>
function IsTypeHead(const AText: string): Boolean;
const
  cHeads: array[0..5] of string = ('=class', '=record', '=packedrecord', '=interface', '=dispinterface', '=object');
var
  mHead: string;
begin
  Result := False;
  for mHead in cHeads do
  begin
    Result := Result or (Pos(mHead, AText) > 0);
  end;
end;

/// <summary>Steht ALine im Rumpf einer Klasse, eines Records oder Interfaces?</summary>
function InTypeBody(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mLine, mIndent: Integer;
  mText: string;
begin
  Result := False;
  mIndent := Length(LeadingSpace(ALines[ALine]));
  for mLine := ALine - 1 downto 0 do
  begin
    mText := LowerCase(Trim(ScanLine(Trim(ALines[mLine])).Code));
    if (mText = 'implementation') or (mText = 'begin') then
    begin
      Exit;
    end;
    if (mText = '') or (Length(LeadingSpace(ALines[mLine])) >= mIndent) then
    begin
      Continue;
    end;
    // Ein Typkopf links von der Zeile.
    mText := StringReplace(mText, ' ', '', [rfReplaceAll]);
    if IsTypeHead(mText) then
    begin
      Exit(not mText.EndsWith(';'));
    end;
    if mText.StartsWith('end') then
    begin
      Exit;
    end;
  end;
end;

function InImplementation(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mLine: Integer;
begin
  Result := False;
  for mLine := ALine - 1 downto 0 do
  begin
    if StartsWord(ALines[mLine], 'implementation') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Das Wort, das die Art bestimmt: "end else …" und "else if …" wie das, was nach else kommt;
/// "class procedure" wie procedure. AFirst: Stelle in AWords.</summary>
function EffectiveFirst(const AWords: TArray<string>; var AFirst: Integer): string;
begin
  if (AWords[0] = 'end') and (Length(AWords) > 1) and (AWords[1] = 'else') then
  begin
    AFirst := 1;
  end;
  if (AWords[AFirst] = 'else') and (Length(AWords) > AFirst + 1) and (AWords[AFirst + 1] = 'if') then
  begin
    Inc(AFirst);
  end;
  Result := AWords[AFirst];
  if (Result = 'class') and (Length(AWords) > AFirst + 1) and InList(AWords[AFirst + 1], cRoutineWords) then
  begin
    Result := AWords[AFirst + 1];
  end;
end;

/// <summary>Art einer Zeile, die mit AWord beginnt; AAlone: Es ist das einzige Wort danach.</summary>
function KindOfWord(const AWord: string; AAlone: Boolean; const ACode: string): TStatementKind;
begin
  if AWord = 'if' then
  begin
    Result := TStatementKind.IfHeader;
  end
  else if InList(AWord, ['while', 'with', 'on']) then
  begin
    Result := TStatementKind.LoopHeader;
  end
  else if AWord = 'for' then
  begin
    Result := TStatementKind.ForHeader;
  end
  else if AWord = 'else' then
  begin
    Result := TStatementKind.ElseHeader;
  end
  else if AWord = 'case' then
  begin
    Result := TStatementKind.CaseHeader;
  end
  else if AAlone and (AWord = 'try') then
  begin
    Result := TStatementKind.TryLine;
  end
  else if AAlone and (AWord = 'repeat') then
  begin
    Result := TStatementKind.RepeatLine;
  end
  else if AAlone and (AWord = 'begin') then
  begin
    Result := TStatementKind.BeginLine;
  end
  else if InList(AWord, cRoutineWords) and (Pos(':=', ACode) = 0) then
  begin
    Result := TStatementKind.Routine;
  end
  else
  begin
    Result := TStatementKind.Plain;
  end;
end;

function Kind(const AScan: TLineScan; out AFirst: Integer): TStatementKind;
var
  mFirst: string;
begin
  AFirst := 0;
  Result := TStatementKind.Plain;
  if Length(AScan.Words) > 0 then
  begin
    mFirst := EffectiveFirst(AScan.Words, AFirst);
    Result := KindOfWord(mFirst, Length(AScan.Words) = AFirst + 1, AScan.Code);
  end;
end;

/// <summary>Soll hinter ACode ein Semikolon? Nicht hinter Schlüsselwörtern, die etwas öffnen, Marken und "end.".
/// </summary>
function WantsSemicolon(const ACode: string; const AScan: TLineScan): Boolean;
var
  mLast: string;
begin
  Result := False;
  if (ACode = '') or ACode.EndsWith(';') or ACode.EndsWith(':') or ACode.EndsWith('.') then
  begin
    Exit;
  end;
  if Length(AScan.Words) > 0 then
  begin
    mLast := AScan.Words[High(AScan.Words)];
    // Nur wenn das Wort wirklich am Ende steht.
    if InList(mLast, cOpenWords) and (AScan.Starts[High(AScan.Starts)] + Length(mLast) - 1 = Length(AScan.Code)) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

/// <summary>Einrückungsschritt: Tabulator, wenn der Einzug einen hat, sonst AWidth Leerzeichen (mindestens 1,
/// sonst 2).</summary>
function StepText(const AIndent: string; AWidth: Integer): string;
begin
  if Pos(#9, AIndent) > 0 then
  begin
    Result := #9;
  end
  else if AWidth < 1 then
  begin
    Result := StringOfChar(' ', 2);
  end
  else
  begin
    Result := StringOfChar(' ', AWidth);
  end;
end;

/// <summary>Endet ACode auf einen Operator, eine öffnende Klammer oder ein Komma?</summary>
function EndsWithOperator(const ACode: string): Boolean;
begin
  Result := ACode.EndsWith(':=') or CharInSet(CharAt(ACode, Length(ACode)),
    ['+', '-', '*', '/', '<', '>', ',', '(', '[']);
end;

/// <summary>Schlüsselwort, das der Kopf AKind braucht: then, do oder ''.</summary>
function HeaderKeyword(AKind: TStatementKind): string;
begin
  Result := '';
  if AKind = TStatementKind.IfHeader then
  begin
    Result := 'then';
  end
  else if AKind in [TStatementKind.LoopHeader, TStatementKind.ForHeader] then
  begin
    Result := 'do';
  end;
end;

/// <summary>Wort des Routinennamens hinter procedure/function (auch nach class).</summary>
function NameIndex(const AScan: TLineScan; AFirst: Integer): Integer;
begin
  Result := AFirst;
  if AScan.Words[Result] = 'class' then
  begin
    Inc(Result);
  end;
  if Result < High(AScan.Words) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Kleinster Bereich, in dem sich AOutput von ALines unterscheidet, in AEdit. Ohne Änderung bleibt AEdit
/// leer (nur der Sprung des Cursors).</summary>
procedure SmallestEdit(const ALines: TArray<string>; AOutput: TList<string>; var AEdit: TAtlasStatementEdit);
var
  mFirst, mTail: Integer;
begin
  mFirst := 0;
  while (mFirst < Length(ALines)) and (mFirst < AOutput.Count) and (ALines[mFirst] = AOutput[mFirst]) do
  begin
    Inc(mFirst);
  end;
  mTail := 0;
  while (mTail < Length(ALines) - mFirst) and (mTail < AOutput.Count - mFirst) and
    (ALines[High(ALines) - mTail] = AOutput[AOutput.Count - 1 - mTail]) do
  begin
    Inc(mTail);
  end;
  if (mFirst <> Length(ALines)) or (mFirst <> AOutput.Count) then
  begin
    AEdit.StartLine := mFirst;
    AEdit.OldCount := Length(ALines) - mFirst - mTail;
    AEdit.Lines := Copy(AOutput.ToArray, mFirst, AOutput.Count - mFirst - mTail);
  end;
end;

{ TStatementJob }

constructor TStatementJob.Create;
begin
  inherited Create;
  FOutput := TList<string>.Create;
end;

destructor TStatementJob.Destroy;
begin
  FOutput.Free;
  inherited Destroy;
end;

procedure TStatementJob.CursorAt(ALineIndex, ACharacter: Integer);
begin
  FEdit.CursorLine := ALineIndex;
  FEdit.CursorCharacter := ACharacter;
end;

procedure TStatementJob.InsertLine(AAt: Integer; const AText: string);
begin
  FOutput.Insert(AAt, AText);
end;

procedure TStatementJob.CursorLineAfter(AAt: Integer; const AIndent: string);
begin
  InsertLine(AAt + 1, AIndent);
  CursorAt(AAt + 1, Length(AIndent));
end;

procedure TStatementJob.CursorInBody;
begin
  if FHasBody then
  begin
    CursorLineAfter(FLast, FIndent + FStep);
  end
  else
  begin
    CursorLineAfter(FLine, FIndent + FStep);
  end;
end;

procedure TStatementJob.InsertBeginEnd(const AEndWord: string);
begin
  InsertLine(FLine + 1, FIndent + AEndWord);
  InsertLine(FLine + 1, FIndent + FStep);
  InsertLine(FLine + 1, FIndent + 'begin');
  CursorAt(FLine + 2, Length(FIndent + FStep));
end;

function TStatementJob.AfterStarts(const AWords: array of string): Boolean;
begin
  Result := (FAfter >= 0) and (Length(LeadingSpace(FLines[FAfter])) = Length(FIndent)) and
    StartsAnyWord(FLines[FAfter], AWords);
end;

function TStatementJob.Prepare: Boolean;
begin
  Result := (FLine >= 0) and (FLine <= High(FLines)) and not StartsInComment(FLines, FLine);
  if Result then
  begin
    FIndent := LeadingSpace(FLines[FLine]);
    FScan := ScanLine(Copy(FLines[FLine], Length(FIndent) + 1, MaxInt));
    FStep := StepText(FIndent, FOptions.IndentWidth);
    Result := FScan.Code <> '';
  end;
end;

procedure TStatementJob.CloseOpen;
begin
  FCode := FScan.Code;
  FCursor := -1;
  if FScan.OpenString then
  begin
    FCode := FCode + '''';
  end;
  if FScan.Closers <> '' then
  begin
    if CharInSet(CharAt(FScan.Code, Length(FScan.Code)), ['(', '[', ',']) then
    begin
      // Nach dem Komma geht es mit einem Leerzeichen weiter.
      if FScan.Code.EndsWith(',') and not FScan.OpenString then
      begin
        FCode := FCode + ' ';
      end;
      FCursor := Length(FCode);
    end;
    FCode := FCode + FScan.Closers;
  end;
end;

procedure TStatementJob.AddForBounds;
begin
  if not (HasWord(FScan, 'do') or HasWord(FScan, 'in') or HasWord(FScan, 'to') or HasWord(FScan, 'downto')) then
  begin
    // Ohne Grenze: Platz für sie, der Cursor steht dort.
    if not FScan.HasAssign then
    begin
      FCode := FCode + ' := ';
      FCursor := Length(FCode);
      FCode := FCode + ' to';
    end
    else
    begin
      FCode := FCode + ' to ';
      FCursor := Length(FCode);
    end;
  end;
end;

procedure TStatementJob.EnsureSemicolon;
var
  mNext: Integer;
begin
  mNext := NextCode(FLines, FLine);
  if (mNext >= 0) and StartsWord(FLines[mNext], 'else') then
  begin
    // Vor else kein Semikolon.
    if FCode.EndsWith(';') then
    begin
      Delete(FCode, Length(FCode), 1);
    end;
  end
  else if WantsSemicolon(FCode, FScan) then
  begin
    if (FCursor < 0) and EndsWithOperator(FScan.Code) then
    begin
      // Hinter einem Operator geht es mit einem Leerzeichen weiter.
      if not CharInSet(CharAt(FScan.Code, Length(FScan.Code)), ['(', '[']) then
      begin
        FCode := FCode + ' ';
      end;
      FCursor := Length(FCode);
    end;
    FCode := FCode + ';';
  end;
end;

procedure TStatementJob.CompleteHead;
var
  mKeyword, mRest: string;
  mIndex: Integer;
begin
  FKind := Kind(FScan, FFirst);
  if FKind = TStatementKind.ForHeader then
  begin
    AddForBounds;
  end;
  if (FKind = TStatementKind.CaseHeader) and not HasWord(FScan, 'of') then
  begin
    FCode := FCode + ' of';
  end;
  mKeyword := HeaderKeyword(FKind);
  mRest := '';
  FPlain := FKind = TStatementKind.Plain;
  if mKeyword <> '' then
  begin
    mIndex := WordIndex(FScan, mKeyword);
    if mIndex < 0 then
    begin
      FCode := FCode + ' ' + mKeyword;
    end
    else
    begin
      mRest := Trim(Copy(FCode, FScan.Starts[mIndex] + Length(mKeyword), MaxInt));
    end;
  end
  else if FKind = TStatementKind.ElseHeader then
  begin
    mRest := Trim(Copy(FCode, FScan.Starts[FFirst] + 4, MaxInt));
  end;
  // Etwas hinter then/do/else: begin öffnet einen Block, sonst eine Anweisung in derselben Zeile.
  if SameText(mRest, 'begin') then
  begin
    FKind := TStatementKind.BeginLine;
  end
  else if (mRest <> '') or (FKind = TStatementKind.Routine) then
  begin
    FPlain := True;
  end;
  if FPlain then
  begin
    EnsureSemicolon;
  end;
end;

procedure TStatementJob.CompletePlain;
begin
  // Vollständig: neue Zeile darunter, vor else aber keine (dort darf keine Anweisung stehen).
  if not FChanged and not ((FAfter >= 0) and StartsWord(FLines[FAfter], 'else')) then
  begin
    CursorLineAfter(FLine, FIndent);
  end;
end;

procedure TStatementJob.CompleteRoutine;
var
  mDeclarationOnly: Boolean;
begin
  mDeclarationOnly := HasWord(FScan, 'forward') or HasWord(FScan, 'external');
  if InTypeBody(FLines, FLine) and FOptions.MethodBody then
  begin
    // Position im Namen hinter procedure/function: Die Klassenvervollständigung gilt dann nur ihr.
    FEdit.FollowUp := TAtlasStatementFollowUp.MethodBody;
    FEdit.FollowLine := FLine;
    FEdit.FollowCharacter := Length(FIndent) + FScan.Starts[NameIndex(FScan, FFirst)];
  end
  else if not InTypeBody(FLines, FLine) and InImplementation(FLines, FLine) and not mDeclarationOnly and
    ((FAfter < 0) or not StartsAnyWord(FLines[FAfter], cBodyStartWords)) then
  begin
    InsertBeginEnd('end;');
  end
  else if not FChanged then
  begin
    CursorLineAfter(FLine, FIndent);
  end;
end;

procedure TStatementJob.CompleteHeader;
var
  mWrap: Boolean;
begin
  mWrap := (FOptions.BeginEnd = TAtlasBeginEndMode.Always) or ((FOptions.BeginEnd = TAtlasBeginEndMode.MultiLine)
    and FHasBody and (StatementCount(FLines, FLine + 1, FLast) >= 2));
  if not FHasBody and AfterStarts(['begin']) then
  begin
    // Der Block steht schon da: in ihn hinein.
    CursorLineAfter(FAfter, FIndent + FStep);
  end
  else if mWrap and FHasBody then
  begin
    InsertLine(FLast + 1, FIndent + FEndWord);
    InsertLine(FLine + 1, FIndent + 'begin');
    CursorAt(FLast + 1, Length(FOutput[FLast + 1]));
  end
  else if mWrap then
  begin
    InsertBeginEnd(FEndWord);
  end
  else if FHasBody and FChanged then
  begin
    CursorAt(FLast, Length(FOutput[FLast]));
  end
  else if FHasBody then
  begin
    CursorLineAfter(FLast, FIndent);
  end
  else
  begin
    CursorLineAfter(FLine, FIndent + FStep);
  end;
end;

procedure TStatementJob.CompleteBlock;
begin
  if FKind = TStatementKind.CaseHeader then
  begin
    FEdit.FollowUp := TAtlasStatementFollowUp.CaseBranches;
    FEdit.FollowLine := FLine;
    FEdit.FollowCharacter := Length(FIndent) + FScan.Starts[FFirst] - 1;
  end;
  if AfterStarts(['end']) then
  begin
    CursorInBody;
  end
  else if FHasBody then
  begin
    InsertLine(FLast + 1, FIndent + FEndWord);
    CursorAt(FLast, Length(FOutput[FLast]));
  end
  else
  begin
    InsertLine(FLine + 1, FIndent + FEndWord);
    CursorLineAfter(FLine, FIndent + FStep);
  end;
end;

procedure TStatementJob.CompleteTry;
var
  mKeyword: string;
begin
  if AfterStarts(['finally', 'except', 'end']) then
  begin
    CursorInBody;
  end
  else
  begin
    mKeyword := 'finally';
    if FOptions.TryKind = TAtlasTryKind.TryExcept then
    begin
      mKeyword := 'except';
    end;
    if FHasBody then
    begin
      InsertLine(FLast + 1, FIndent + FEndWord);
      InsertLine(FLast + 1, FIndent + FStep);
      InsertLine(FLast + 1, FIndent + mKeyword);
      CursorAt(FLast + 2, Length(FIndent + FStep));
    end
    else
    begin
      InsertLine(FLine + 1, FIndent + FEndWord);
      InsertLine(FLine + 1, '');
      InsertLine(FLine + 1, FIndent + mKeyword);
      CursorLineAfter(FLine, FIndent + FStep);
    end;
  end;
end;

procedure TStatementJob.CompleteRepeat;
begin
  if AfterStarts(['until']) then
  begin
    CursorInBody;
  end
  else if FHasBody then
  begin
    // Rumpf steht schon da: until dahinter, Cursor an die Bedingung.
    InsertLine(FLast + 1, FIndent + 'until ;');
    CursorAt(FLast + 1, Length(FIndent) + 6);
  end
  else
  begin
    InsertLine(FLine + 1, FIndent + 'until ;');
    CursorLineAfter(FLine, FIndent + FStep);
  end;
end;

procedure TStatementJob.CompleteBody;
begin
  // Zeilen ab FLine + 1 stehen in der Ausgabe noch an derselben Stelle; eingefügt wird von hinten.
  if FPlain and (FKind <> TStatementKind.Routine) then
  begin
    CompletePlain;
  end
  else if FPlain then
  begin
    CompleteRoutine;
  end
  else if FKind in [TStatementKind.IfHeader, TStatementKind.LoopHeader, TStatementKind.ForHeader,
    TStatementKind.ElseHeader] then
  begin
    CompleteHeader;
  end
  else if FKind in [TStatementKind.BeginLine, TStatementKind.CaseHeader] then
  begin
    CompleteBlock;
  end
  else if FKind = TStatementKind.TryLine then
  begin
    CompleteTry;
  end
  else if FKind = TStatementKind.RepeatLine then
  begin
    CompleteRepeat;
  end;
end;

function TStatementJob.Run(const AText: string; ALine: Integer; const AOptions: TAtlasStatementOptions;
  var AEdit: TAtlasStatementEdit): Boolean;
var
  mHeaderCursor: Boolean;
begin
  FLines := LinesOf(AText);
  FLine := ALine;
  FOptions := AOptions;
  FEdit := AEdit;
  Result := Prepare;
  if Result then
  begin
    CloseOpen;
    CompleteHead;
    FOutput.AddRange(FLines);
    FOutput[FLine] := FIndent + FCode + FScan.Comment;
    FChanged := TrimRight(FOutput[FLine]) <> TrimRight(FLines[FLine]);
    // Platzhalter (for-Grenze) oder offene Klammer: Der Cursor bleibt in der Zeile.
    mHeaderCursor := FCursor >= 0;
    if not mHeaderCursor then
    begin
      FCursor := Length(FCode);
    end;
    CursorAt(FLine, Length(FIndent) + FCursor);
    FLast := BodyEnd(FLines, FLine, Length(FIndent));
    FHasBody := FLast > FLine;
    FAfter := NextCode(FLines, FLast);
    FEndWord := 'end;';
    if AfterStarts(['else']) then
    begin
      FEndWord := 'end';
    end;
    CompleteBody;
    if mHeaderCursor then
    begin
      CursorAt(FLine, Length(FIndent) + FCursor);
    end;
    SmallestEdit(FLines, FOutput, FEdit);
    AEdit := FEdit;
  end;
end;
{ TAtlasStatementOptions }

class function TAtlasStatementOptions.Defaults: TAtlasStatementOptions;
begin
  Result.BeginEnd := TAtlasBeginEndMode.MultiLine;
  Result.TryKind := TAtlasTryKind.TryFinally;
  Result.IndentWidth := 2;
  Result.MethodBody := True;
end;

{ TAtlasStatementCompleter }

class function TAtlasStatementCompleter.Complete(const AText: string; ALine: Integer;
  const AOptions: TAtlasStatementOptions; out AEdit: TAtlasStatementEdit): Boolean;
var
  mJob: TStatementJob;
begin
  AEdit := Default(TAtlasStatementEdit);
  mJob := TStatementJob.Create;
  try
    Result := mJob.Run(AText, ALine, AOptions, AEdit);
  finally
    mJob.Free;
  end;
end;

class function TAtlasStatementCompleter.NeedsTryKind(const AText: string; ALine: Integer): Boolean;
var
  mLines: TArray<string>;
  mIndent, mLast, mAfter: Integer;
begin
  Result := False;
  mLines := LinesOf(AText);
  if (ALine < 0) or (ALine > High(mLines)) or StartsInComment(mLines, ALine) or
    not SameText(ScanLine(Trim(mLines[ALine])).Code, 'try') then
  begin
    Exit;
  end;
  mIndent := Length(LeadingSpace(mLines[ALine]));
  mLast := BodyEnd(mLines, ALine, mIndent);
  mAfter := NextCode(mLines, mLast);
  Result := (mAfter < 0) or (Length(LeadingSpace(mLines[mAfter])) <> mIndent) or
    not StartsAnyWord(mLines[mAfter], ['finally', 'except', 'end']);
end;

class function TAtlasStatementCompleter.Apply(const ALines: TArray<string>;
  const AEdit: TAtlasStatementEdit): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ALines) - AEdit.OldCount + Length(AEdit.Lines));
  for mIndex := 0 to AEdit.StartLine - 1 do
  begin
    Result[mIndex] := ALines[mIndex];
  end;
  for mIndex := 0 to High(AEdit.Lines) do
  begin
    Result[AEdit.StartLine + mIndex] := AEdit.Lines[mIndex];
  end;
  for mIndex := AEdit.StartLine + AEdit.OldCount to High(ALines) do
  begin
    Result[mIndex - AEdit.OldCount + Length(AEdit.Lines)] := ALines[mIndex];
  end;
end;

class function TAtlasStatementCompleter.AfterCaseBranches(var ALines: TArray<string>;
  var ACursorLine, ACursorCharacter: Integer): Boolean;
var
  mBranch: string;
begin
  Result := False;
  if (ACursorLine < 0) or (ACursorLine >= High(ALines)) or (Trim(ALines[ACursorLine]) <> '') then
  begin
    Exit;
  end;
  mBranch := TrimRight(ALines[ACursorLine + 1]);
  if not mBranch.EndsWith(': ;') then
  begin
    Exit;
  end;
  Delete(ALines, ACursorLine, 1);
  ACursorCharacter := Length(mBranch) - 1;
  Result := True;
end;

end.
