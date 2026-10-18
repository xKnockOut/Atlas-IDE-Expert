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

const
  // Hinter diesen Wörtern kommt kein Semikolon.
  OpenWords: array[0..23] of string = ('then', 'do', 'of', 'begin', 'else', 'try', 'repeat', 'finally', 'except',
    'var', 'const', 'type', 'private', 'protected', 'public', 'published', 'interface', 'implementation',
    'initialization', 'finalization', 'record', 'class', 'label', 'resourcestring');
  RoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');
  BodyStartWords: array[0..5] of string = ('begin', 'var', 'const', 'type', 'label', 'asm');

function LinesOf(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
    if Result[Index].EndsWith(#13) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

function LeadingSpace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

function InList(const AWord: string; const AList: array of string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in AList do
    if Item = AWord then
      Exit(True);
end;

/// <summary>Erstes Wort der Zeile (kleingeschrieben) gleich AWord?</summary>
function StartsWord(const ALine, AWord: string): Boolean;
var
  Text: string;
begin
  Text := LowerCase(TrimLeft(ALine));
  Result := Text.StartsWith(AWord) and ((Length(Text) = Length(AWord)) or not TTextChars.IsAsciiIdentChar(Text[Length(AWord) + 1]));
end;

function StartsAnyWord(const ALine: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  for Word in AWords do
    if StartsWord(ALine, Word) then
      Exit(True);
end;

/// <summary>Beginnt ALine in einem Blockkommentar?</summary>
function StartsInComment(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  Line, Index: Integer;
  Text: string;
  Brace, ParenStar: Boolean;
begin
  Brace := False;
  ParenStar := False;
  for Line := 0 to ALine - 1 do
  begin
    Text := ALines[Line];
    Index := 1;
    while Index <= Length(Text) do
    begin
      if Brace then
      begin
        if Text[Index] = '}' then
          Brace := False;
      end
      else if ParenStar then
      begin
        if (Text[Index] = '*') and (Index < Length(Text)) and (Text[Index + 1] = ')') then
        begin
          ParenStar := False;
          Inc(Index);
        end;
      end
      else if Text[Index] = '''' then
      begin
        Inc(Index);
        while (Index <= Length(Text)) and (Text[Index] <> '''') do
          Inc(Index);
      end
      else if (Text[Index] = '/') and (Index < Length(Text)) and (Text[Index + 1] = '/') then
        Index := Length(Text)
      else if Text[Index] = '{' then
        Brace := True
      else if (Text[Index] = '(') and (Index < Length(Text)) and (Text[Index + 1] = '*') then
      begin
        ParenStar := True;
        Inc(Index);
      end;
      Inc(Index);
    end;
  end;
  Result := Brace or ParenStar;
end;

function ScanLine(const ABody: string): TLineScan;
var
  Index, CommentAt, Close, Start: Integer;
  Stack: string;
  InString: Boolean;
begin
  Result := Default(TLineScan);
  Stack := '';
  InString := False;
  CommentAt := 0;
  Index := 1;
  while Index <= Length(ABody) do
  begin
    if InString then
    begin
      if ABody[Index] = '''' then
        InString := False;
      Inc(Index);
      Continue;
    end;
    case ABody[Index] of
      '''':
        InString := True;
      '(', '[':
        if (ABody[Index] = '(') and (Index < Length(ABody)) and (ABody[Index + 1] = '*') then
        begin
          Close := Pos('*)', ABody, Index + 2);
          if (Close = 0) or (Trim(Copy(ABody, Close + 2, MaxInt)) = '') then
          begin
            CommentAt := Index;
            Break;
          end;
          Index := Close + 1;
        end
        else
          Stack := Stack + ABody[Index];
      ')', ']':
        if (Stack <> '') and (((ABody[Index] = ')') and (Stack[Length(Stack)] = '(')) or
          ((ABody[Index] = ']') and (Stack[Length(Stack)] = '['))) then
          Delete(Stack, Length(Stack), 1);
      '/':
        if (Index < Length(ABody)) and (ABody[Index + 1] = '/') then
        begin
          CommentAt := Index;
          Break;
        end;
      '{':
        begin
          Close := Pos('}', ABody, Index + 1);
          // Direktiven zählen wie Code; ein Kommentar mitten in der Zeile wird übersprungen.
          if (Index = Length(ABody)) or (ABody[Index + 1] <> '$') then
            if (Close = 0) or (Trim(Copy(ABody, Close + 1, MaxInt)) = '') then
            begin
              CommentAt := Index;
              Break;
            end;
          if Close = 0 then
            Index := Length(ABody)
          else
            Index := Close;
        end;
      ':':
        if (Index < Length(ABody)) and (ABody[Index + 1] = '=') then
          Result.HasAssign := True;
      'A'..'Z', 'a'..'z', '_':
        begin
          Start := Index;
          while (Index < Length(ABody)) and TTextChars.IsAsciiIdentChar(ABody[Index + 1]) do
            Inc(Index);
          // "&begin" ist ein Bezeichner, kein Schlüsselwort.
          if (Start = 1) or (ABody[Start - 1] <> '&') then
          begin
            Result.Words := Result.Words + [LowerCase(Copy(ABody, Start, Index - Start + 1))];
            Result.Starts := Result.Starts + [Start];
          end;
        end;
    end;
    Inc(Index);
  end;
  if CommentAt > 0 then
  begin
    Result.Code := TrimRight(Copy(ABody, 1, CommentAt - 1));
    Result.Comment := Copy(ABody, Length(Result.Code) + 1, MaxInt);
  end
  else
    Result.Code := TrimRight(ABody);
  Result.OpenString := InString;
  for Index := Length(Stack) downto 1 do
    if Stack[Index] = '(' then
      Result.Closers := Result.Closers + ')'
    else
      Result.Closers := Result.Closers + ']';
end;

function HasWord(const AScan: TLineScan; const AWord: string): Boolean;
begin
  Result := InList(AWord, AScan.Words);
end;

function WordIndex(const AScan: TLineScan; const AWord: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(AScan.Words) do
    if AScan.Words[Index] = AWord then
      Exit(Index);
end;

/// <summary>Nächste nicht leere Zeile nach ALine; -1 ohne.</summary>
function NextCode(const ALines: TArray<string>; ALine: Integer): Integer;
begin
  Result := ALine + 1;
  while (Result <= High(ALines)) and (Trim(ALines[Result]) = '') do
    Inc(Result);
  if Result > High(ALines) then
    Result := -1;
end;

/// <summary>Letzte Zeile des tiefer eingerückten Rumpfs nach ALine (Leerzeilen dazwischen zählen mit); ALine ohne.
/// </summary>
function BodyEnd(const ALines: TArray<string>; ALine, AIndent: Integer): Integer;
var
  Next: Integer;
begin
  Result := ALine;
  Next := NextCode(ALines, Result);
  while (Next >= 0) and (Length(LeadingSpace(ALines[Next])) > AIndent) do
  begin
    Result := Next;
    Next := NextCode(ALines, Result);
  end;
end;

/// <summary>Anweisungen in den Zeilen AFirst..ALast: Zeilen, die mit ";" enden, und die letzte.</summary>
function StatementCount(const ALines: TArray<string>; AFirst, ALast: Integer): Integer;
var
  Line: Integer;
  Code: string;
begin
  Result := 0;
  for Line := AFirst to ALast do
  begin
    Code := ScanLine(Trim(ALines[Line])).Code;
    if (Code <> '') and (Code.EndsWith(';') or (Line = ALast)) then
      Inc(Result);
  end;
end;

/// <summary>Steht ALine im Rumpf einer Klasse, eines Records oder Interfaces?</summary>
function InTypeBody(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  Line, Indent: Integer;
  Text: string;
begin
  Result := False;
  Indent := Length(LeadingSpace(ALines[ALine]));
  for Line := ALine - 1 downto 0 do
  begin
    Text := LowerCase(Trim(ScanLine(Trim(ALines[Line])).Code));
    if Text = '' then
      Continue;
    if (Text = 'implementation') or (Text = 'begin') then
      Exit;
    if Length(LeadingSpace(ALines[Line])) >= Indent then
      Continue;
    // Ein Typkopf links von der Zeile: "TFoo = class", "TFoo = class(TBar)", "= record", "= interface".
    Text := StringReplace(Text, ' ', '', [rfReplaceAll]);
    if (Pos('=class', Text) > 0) or (Pos('=record', Text) > 0) or (Pos('=packedrecord', Text) > 0) or
      (Pos('=interface', Text) > 0) or (Pos('=dispinterface', Text) > 0) or (Pos('=object', Text) > 0) then
      Exit(not Text.EndsWith(';'));
    if Text.StartsWith('end') then
      Exit;
  end;
end;

function InImplementation(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  Line: Integer;
begin
  Result := False;
  for Line := ALine - 1 downto 0 do
    if StartsWord(ALines[Line], 'implementation') then
      Exit(True);
end;

function Kind(const AScan: TLineScan; out AFirst: Integer): TStatementKind;
var
  Words: TArray<string>;
  First: string;
begin
  Words := AScan.Words;
  AFirst := 0;
  Result := TStatementKind.Plain;
  if Length(Words) = 0 then
    Exit;
  // "end else …" und "else if …" wie das, was nach else kommt.
  if (Words[0] = 'end') and (Length(Words) > 1) and (Words[1] = 'else') then
    AFirst := 1;
  if (Words[AFirst] = 'else') and (Length(Words) > AFirst + 1) and (Words[AFirst + 1] = 'if') then
    Inc(AFirst);
  First := Words[AFirst];
  if (First = 'class') and (Length(Words) > AFirst + 1) and InList(Words[AFirst + 1], RoutineWords) then
    First := Words[AFirst + 1];
  if First = 'if' then
    Result := TStatementKind.IfHeader
  else if (First = 'while') or (First = 'with') or (First = 'on') then
    Result := TStatementKind.LoopHeader
  else if First = 'for' then
    Result := TStatementKind.ForHeader
  else if First = 'else' then
    Result := TStatementKind.ElseHeader
  else if First = 'case' then
    Result := TStatementKind.CaseHeader
  else if (First = 'try') and (Length(Words) = AFirst + 1) then
    Result := TStatementKind.TryLine
  else if (First = 'repeat') and (Length(Words) = AFirst + 1) then
    Result := TStatementKind.RepeatLine
  else if (First = 'begin') and (Length(Words) = AFirst + 1) then
    Result := TStatementKind.BeginLine
  else if InList(First, RoutineWords) and (Pos(':=', AScan.Code) = 0) then
    Result := TStatementKind.Routine;
end;

/// <summary>Soll hinter ACode ein Semikolon? Nicht hinter Schlüsselwörtern, die etwas öffnen, Marken und "end.".
/// </summary>
function WantsSemicolon(const ACode: string; const AScan: TLineScan): Boolean;
var
  Last: string;
begin
  Result := False;
  if (ACode = '') or ACode.EndsWith(';') or ACode.EndsWith(':') or ACode.EndsWith('.') then
    Exit;
  if Length(AScan.Words) > 0 then
  begin
    Last := AScan.Words[High(AScan.Words)];
    // Nur wenn das Wort wirklich am Ende steht.
    if InList(Last, OpenWords) and (AScan.Starts[High(AScan.Starts)] + Length(Last) - 1 = Length(AScan.Code)) then
      Exit;
  end;
  Result := True;
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
  Lines: TArray<string>;
  Output: TList<string>;
  Scan: TLineScan;
  Indent, Step, Code, Original, EndWord, Keyword, Rest: string;
  First, Cursor, Last, After, Index, Width, Name: Integer;
  StatementKind: TStatementKind;
  Changed, HasBody, Wrap, Plain, HeaderCursor: Boolean;
  CursorLine, CursorCharacter: Integer;

  procedure CursorAt(ALineIndex, ACharacter: Integer);
  begin
    CursorLine := ALineIndex;
    CursorCharacter := ACharacter;
  end;

  /// <summary>Neue Zeile AText vor der Zeile AAt der Ausgabe.</summary>
  procedure InsertLine(AAt: Integer; const AText: string);
  begin
    Output.Insert(AAt, AText);
  end;

  /// <summary>Cursorzeile mit Einzug AIndent nach Zeile AAt.</summary>
  procedure CursorLineAfter(AAt: Integer; const AIndent: string);
  begin
    InsertLine(AAt + 1, AIndent);
    CursorAt(AAt + 1, Length(AIndent));
  end;

  /// <summary>Zeile hinter dem Rumpf auf derselben Einrückung, die mit AWord beginnt?</summary>
  function AfterStarts(const AWords: array of string): Boolean;
  begin
    Result := (After >= 0) and (Length(LeadingSpace(Lines[After])) = Length(Indent)) and
      StartsAnyWord(Lines[After], AWords);
  end;

  procedure EnsureSemicolon;
  var
    Next: Integer;
  begin
    Next := NextCode(Lines, ALine);
    if (Next >= 0) and StartsWord(Lines[Next], 'else') then
    begin
      // Vor else kein Semikolon.
      if Code.EndsWith(';') then
        Delete(Code, Length(Code), 1);
      Exit;
    end;
    if not WantsSemicolon(Code, Scan) then
      Exit;
    if (Cursor < 0) and (Scan.Code.EndsWith(':=') or CharInSet(Scan.Code[Length(Scan.Code)],
      ['+', '-', '*', '/', '<', '>', ',', '(', '['])) then
    begin
      // Hinter einem Operator geht es mit einem Leerzeichen weiter.
      if not CharInSet(Scan.Code[Length(Scan.Code)], ['(', '[']) then
        Code := Code + ' ';
      Cursor := Length(Code);
    end;
    Code := Code + ';';
  end;

begin
  AEdit := Default(TAtlasStatementEdit);
  Result := False;
  Lines := LinesOf(AText);
  if (ALine < 0) or (ALine > High(Lines)) or StartsInComment(Lines, ALine) then
    Exit;
  Original := Lines[ALine];
  Indent := LeadingSpace(Original);
  Scan := ScanLine(Copy(Original, Length(Indent) + 1, MaxInt));
  if Scan.Code = '' then
    Exit;
  Width := AOptions.IndentWidth;
  if Width < 1 then
    Width := 2;
  Step := StringOfChar(' ', Width);
  if Pos(#9, Indent) > 0 then
    Step := #9;
  Code := Scan.Code;
  Cursor := -1;
  if Scan.OpenString then
    Code := Code + '''';
  if Scan.Closers <> '' then
  begin
    if CharInSet(Scan.Code[Length(Scan.Code)], ['(', '[', ',']) then
    begin
      // Nach dem Komma geht es mit einem Leerzeichen weiter.
      if Scan.Code.EndsWith(',') and not Scan.OpenString then
        Code := Code + ' ';
      Cursor := Length(Code);
    end;
    Code := Code + Scan.Closers;
  end;
  StatementKind := Kind(Scan, First);
  Keyword := '';
  case StatementKind of
    TStatementKind.IfHeader:
      Keyword := 'then';
    TStatementKind.LoopHeader:
      Keyword := 'do';
    TStatementKind.ForHeader:
      begin
        Keyword := 'do';
        if not HasWord(Scan, 'do') and not HasWord(Scan, 'in') and not HasWord(Scan, 'to') and
          not HasWord(Scan, 'downto') then
        begin
          // Ohne Grenze: Platz für sie, der Cursor steht dort.
          if not Scan.HasAssign then
          begin
            Code := Code + ' := ';
            Cursor := Length(Code);
            Code := Code + ' to';
          end
          else
          begin
            Code := Code + ' to ';
            Cursor := Length(Code);
          end;
        end;
      end;
    TStatementKind.CaseHeader:
      if not HasWord(Scan, 'of') then
        Code := Code + ' of';
  end;
  Rest := '';
  Plain := StatementKind = TStatementKind.Plain;
  if Keyword <> '' then
  begin
    Index := WordIndex(Scan, Keyword);
    if Index < 0 then
      Code := Code + ' ' + Keyword
    else
      Rest := Trim(Copy(Code, Scan.Starts[Index] + Length(Keyword), MaxInt));
  end
  else if StatementKind = TStatementKind.ElseHeader then
    Rest := Trim(Copy(Code, Scan.Starts[First] + 4, MaxInt));
  if Rest <> '' then
  begin
    // Etwas hinter then/do/else: begin öffnet einen Block, sonst eine Anweisung in derselben Zeile.
    if SameText(Rest, 'begin') then
      StatementKind := TStatementKind.BeginLine
    else
      Plain := True;
  end;
  if StatementKind = TStatementKind.Routine then
    Plain := True;
  if Plain then
    EnsureSemicolon;
  Output := TList<string>.Create;
  try
    Output.AddRange(Lines);
    Output[ALine] := Indent + Code + Scan.Comment;
    Changed := TrimRight(Output[ALine]) <> TrimRight(Original);
    // Platzhalter (for-Grenze) oder offene Klammer: Der Cursor bleibt in der Zeile.
    HeaderCursor := Cursor >= 0;
    if Cursor < 0 then
      Cursor := Length(Code);
    CursorAt(ALine, Length(Indent) + Cursor);
    Last := BodyEnd(Lines, ALine, Length(Indent));
    HasBody := Last > ALine;
    After := NextCode(Lines, Last);
    EndWord := 'end;';
    if AfterStarts(['else']) then
      EndWord := 'end';
    // Zeilen ab ALine + 1 stehen in der Ausgabe noch an derselben Stelle; eingefügt wird von hinten.
    if Plain and (StatementKind <> TStatementKind.Routine) then
    begin
      // Vollständig: neue Zeile darunter, vor else aber keine (dort darf keine Anweisung stehen).
      if not Changed and not ((After >= 0) and StartsWord(Lines[After], 'else')) then
        CursorLineAfter(ALine, Indent);
    end
    else if Plain then
    begin
      // Routinenkopf.
      if InTypeBody(Lines, ALine) then
      begin
        if AOptions.MethodBody then
        begin
          // Position im Namen hinter procedure/function: Die Klassenvervollständigung gilt dann nur ihr.
          Name := First;
          if Scan.Words[Name] = 'class' then
            Inc(Name);
          if Name < High(Scan.Words) then
            Inc(Name);
          AEdit.FollowUp := TAtlasStatementFollowUp.MethodBody;
          AEdit.FollowLine := ALine;
          AEdit.FollowCharacter := Length(Indent) + Scan.Starts[Name];
        end
        else if not Changed then
          CursorLineAfter(ALine, Indent);
      end
      else if InImplementation(Lines, ALine) and not HasWord(Scan, 'forward') and not HasWord(Scan, 'external') and
        ((After < 0) or not StartsAnyWord(Lines[After], BodyStartWords)) then
      begin
        InsertLine(ALine + 1, Indent + 'end;');
        InsertLine(ALine + 1, Indent + Step);
        InsertLine(ALine + 1, Indent + 'begin');
        CursorAt(ALine + 2, Length(Indent + Step));
      end
      else if not Changed then
        CursorLineAfter(ALine, Indent);
    end
    else
      case StatementKind of
        TStatementKind.IfHeader, TStatementKind.LoopHeader, TStatementKind.ForHeader, TStatementKind.ElseHeader:
          begin
            Wrap := (AOptions.BeginEnd = TAtlasBeginEndMode.Always) or
              ((AOptions.BeginEnd = TAtlasBeginEndMode.MultiLine) and HasBody and
              (StatementCount(Lines, ALine + 1, Last) >= 2));
            if not HasBody and AfterStarts(['begin']) then
              // Der Block steht schon da: in ihn hinein.
              CursorLineAfter(After, Indent + Step)
            else if Wrap and HasBody then
            begin
              InsertLine(Last + 1, Indent + EndWord);
              InsertLine(ALine + 1, Indent + 'begin');
              CursorAt(Last + 1, Length(Output[Last + 1]));
            end
            else if Wrap then
            begin
              InsertLine(ALine + 1, Indent + EndWord);
              InsertLine(ALine + 1, Indent + Step);
              InsertLine(ALine + 1, Indent + 'begin');
              CursorAt(ALine + 2, Length(Indent + Step));
            end
            else if HasBody and Changed then
              CursorAt(Last, Length(Output[Last]))
            else if HasBody then
              CursorLineAfter(Last, Indent)
            else
              CursorLineAfter(ALine, Indent + Step);
          end;
        TStatementKind.BeginLine, TStatementKind.CaseHeader:
          begin
            if StatementKind = TStatementKind.CaseHeader then
            begin
              AEdit.FollowUp := TAtlasStatementFollowUp.CaseBranches;
              AEdit.FollowLine := ALine;
              AEdit.FollowCharacter := Length(Indent) + Scan.Starts[First] - 1;
            end;
            if AfterStarts(['end']) then
            begin
              if HasBody then
                CursorLineAfter(Last, Indent + Step)
              else
                CursorLineAfter(ALine, Indent + Step);
            end
            else if HasBody then
            begin
              InsertLine(Last + 1, Indent + EndWord);
              CursorAt(Last, Length(Output[Last]));
            end
            else
            begin
              InsertLine(ALine + 1, Indent + EndWord);
              CursorLineAfter(ALine, Indent + Step);
            end;
          end;
        TStatementKind.TryLine:
          if AfterStarts(['finally', 'except', 'end']) then
          begin
            if HasBody then
              CursorLineAfter(Last, Indent + Step)
            else
              CursorLineAfter(ALine, Indent + Step);
          end
          else
          begin
            Keyword := 'finally';
            if AOptions.TryKind = TAtlasTryKind.TryExcept then
              Keyword := 'except';
            if HasBody then
            begin
              InsertLine(Last + 1, Indent + EndWord);
              InsertLine(Last + 1, Indent + Step);
              InsertLine(Last + 1, Indent + Keyword);
              CursorAt(Last + 2, Length(Indent + Step));
            end
            else
            begin
              InsertLine(ALine + 1, Indent + EndWord);
              InsertLine(ALine + 1, '');
              InsertLine(ALine + 1, Indent + Keyword);
              CursorLineAfter(ALine, Indent + Step);
            end;
          end;
        TStatementKind.RepeatLine:
          if AfterStarts(['until']) then
          begin
            if HasBody then
              CursorLineAfter(Last, Indent + Step)
            else
              CursorLineAfter(ALine, Indent + Step);
          end
          else if HasBody then
          begin
            // Rumpf steht schon da: until dahinter, Cursor an die Bedingung.
            InsertLine(Last + 1, Indent + 'until ;');
            CursorAt(Last + 1, Length(Indent) + 6);
          end
          else
          begin
            InsertLine(ALine + 1, Indent + 'until ;');
            CursorLineAfter(ALine, Indent + Step);
          end;
      end;
    if HeaderCursor then
      CursorAt(ALine, Length(Indent) + Cursor);
    // Kleinster Bereich, der sich ändert.
    Index := 0;
    while (Index < Length(Lines)) and (Index < Output.Count) and (Lines[Index] = Output[Index]) do
      Inc(Index);
    Last := 0;
    while (Last < Length(Lines) - Index) and (Last < Output.Count - Index) and
      (Lines[High(Lines) - Last] = Output[Output.Count - 1 - Last]) do
      Inc(Last);
    // Ohne Änderung bleibt nur der Sprung des Cursors.
    if (Index <> Length(Lines)) or (Index <> Output.Count) then
    begin
      AEdit.StartLine := Index;
      AEdit.OldCount := Length(Lines) - Index - Last;
      AEdit.Lines := Copy(Output.ToArray, Index, Output.Count - Index - Last);
    end;
    AEdit.CursorLine := CursorLine;
    AEdit.CursorCharacter := CursorCharacter;
    Result := True;
  finally
    Output.Free;
  end;
end;

class function TAtlasStatementCompleter.NeedsTryKind(const AText: string; ALine: Integer): Boolean;
var
  Lines: TArray<string>;
  Indent, Last, After: Integer;
begin
  Result := False;
  Lines := LinesOf(AText);
  if (ALine < 0) or (ALine > High(Lines)) or StartsInComment(Lines, ALine) or
    not SameText(ScanLine(Trim(Lines[ALine])).Code, 'try') then
    Exit;
  Indent := Length(LeadingSpace(Lines[ALine]));
  Last := BodyEnd(Lines, ALine, Indent);
  After := NextCode(Lines, Last);
  Result := (After < 0) or (Length(LeadingSpace(Lines[After])) <> Indent) or
    not StartsAnyWord(Lines[After], ['finally', 'except', 'end']);
end;

class function TAtlasStatementCompleter.Apply(const ALines: TArray<string>;
  const AEdit: TAtlasStatementEdit): TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ALines) - AEdit.OldCount + Length(AEdit.Lines));
  for Index := 0 to AEdit.StartLine - 1 do
    Result[Index] := ALines[Index];
  for Index := 0 to High(AEdit.Lines) do
    Result[AEdit.StartLine + Index] := AEdit.Lines[Index];
  for Index := AEdit.StartLine + AEdit.OldCount to High(ALines) do
    Result[Index - AEdit.OldCount + Length(AEdit.Lines)] := ALines[Index];
end;

class function TAtlasStatementCompleter.AfterCaseBranches(var ALines: TArray<string>;
  var ACursorLine, ACursorCharacter: Integer): Boolean;
var
  Branch: string;
begin
  Result := False;
  if (ACursorLine < 0) or (ACursorLine >= High(ALines)) or (Trim(ALines[ACursorLine]) <> '') then
    Exit;
  Branch := TrimRight(ALines[ACursorLine + 1]);
  if not Branch.EndsWith(': ;') then
    Exit;
  Delete(ALines, ACursorLine, 1);
  ACursorCharacter := Length(Branch) - 1;
  Result := True;
end;

end.
