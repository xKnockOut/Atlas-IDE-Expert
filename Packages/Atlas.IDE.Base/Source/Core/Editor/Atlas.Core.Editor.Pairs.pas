unit Atlas.Core.Editor.Pairs;

// Klammer- und Blockpaare (#514), ohne Open Tools API: Ein kleiner Lexer
// überspringt Strings, Kommentare und Direktiven und liefert für jede Klammer
// und jedes Blockwort die Verschachtelungstiefe; unpaarige sind markiert.
// - Klammern ( ) [ ] und Blockwörter haben je eine eigene Tiefe.
// - Öffnen: begin, try, case, repeat, asm; class, record, object, interface
//   nur als Typdeklaration (nach "=", record auch nach ":", "of", "packed").
//   class/interface ohne Rumpf (TFoo = class; TFoo = class(TBase);) öffnen nicht,
//   "class function", "procedure of object" ebenso nicht; case im record
//   (variante Teile) teilt sich das end des records.
// - Schließen: end (nicht repeat), until (nur repeat); finally/except
//   bekommen die Tiefe ihres try. "end." ohne Öffner ist das Ende der Unit.
// - Escapte Bezeichner (&begin), Sprungmarken (@@End, #861) und Mitglieder hinter "."
//   sind keine Schlüsselwörter; Steuerzeichen wie ^[ sind keine Klammern (#862).
// Besitzer (#653): Schlüsselwörter der Anweisung, zu der ein Block gehört,
// bekommen Tiefe und Paarstatus ihres Blocks (Owner = True):
//   if … then begin          → if, then (davor ein else: auch else)
//   else begin               → else
//   for/while/with/on … do begin → for/while/with/on, do
//   case … of                → of
//   Rumpf einer Routine      → procedure/function/constructor/destructor/operator, davor class
// Ohne begin (if X then Foo;) gibt es keinen Block und keine Besitzer. Routinenköpfe
// zählen nur außerhalb von Blöcken (nicht in Klassen, nicht als Prozedurtyp nach
// "=", ":", "to", "of"); forward/external und implementation verwerfen offene Köpfe.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasPairToken = record
    /// <summary>0-basierte Zeile und Zeichenindex in der Zeile.</summary>
    Line: Integer;
    Character: Integer;
    Length: Integer;
    Depth: Integer;
    Unpaired: Boolean;
    IsWord: Boolean;
    /// <summary>Schlüsselwort der Anweisung, zu der der Block gehört (if, then, for, procedure …, #653).</summary>
    Owner: Boolean;
  end;

  /// <summary>Gepaarter Block (begin … end, repeat … until, class … end …), 0-basiert.</summary>
  TAtlasPairBlock = record
    OpenLine: Integer;
    OpenCharacter: Integer;
    CloseLine: Integer;
    CloseCharacter: Integer;
    Depth: Integer;
    /// <summary>Erstes Besitzer-Schlüsselwort vor dem Öffner (if, else, for, procedure …), sonst der Öffner (#653).</summary>
    OwnerLine: Integer;
    OwnerCharacter: Integer;
  end;

  /// <summary>Gefärbter Teil eines abgeleiteten Texts, z. B. des mitlaufenden Kopfs (#1229); Start 1-basiert.
  /// </summary>
  TAtlasPairSpan = record
    Start: Integer;
    Length: Integer;
    Depth: Integer;
    Unpaired: Boolean;
  end;

  TAtlasPairs = class
  public
    /// <summary>Token der Quellzeile ALine (ALineTokens, Zeichenindex 0-basiert in ALine) als Teile von AText, der
    /// die Zeile ohne Einrückung zeigt (#1229, mitlaufender Kopf). Nur Token, die dort unverändert stehen;
    /// Besitzer (procedure, if …) nur mit AOwners.</summary>
    class function Spans(const AText, ALine: string; const ALineTokens: TArray<TAtlasPairToken>;
      AOwners: Boolean): TArray<TAtlasPairSpan>; static;
    /// <summary>Klammern und Blockwörter in AText, nach Position sortiert.</summary>
    class function Analyze(const AText: string): TArray<TAtlasPairToken>; overload; static;
    /// <summary>Wie Analyze; ABlocks erhält zusätzlich die gepaarten Blöcke in der Reihenfolge ihres Endes.</summary>
    class function Analyze(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
      overload; static;
    /// <summary>Zeile wie im Editor: Tabs bis zur nächsten Tabstelle als Leerzeichen, ohne #13.</summary>
    class function DisplayLine(const ALine: string; ATabWidth: Integer): string; static;
    /// <summary>True, wenn der Textlauf ARun ab der 1-basierten Spalte AColumn in ADisplayLine steht.</summary>
    class function RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean; static;
    /// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
    class function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
  end;

implementation

uses
  System.Generics.Defaults;

type
  TLexToken = record
    Text: string;
    Line: Integer;
    Character: Integer;
    IsWord: Boolean;
    /// <summary>Bezeichner mit &amp; oder hinter einem Punkt: kein Schlüsselwort.</summary>
    Plain: Boolean;
  end;

  TOpen = record
    Word: string;
    Index: Integer;
    /// <summary>Indizes der Besitzer in den Ergebnissen (#653).</summary>
    Owners: TArray<Integer>;
    OwnerLine: Integer;
    OwnerCharacter: Integer;
  end;

  /// <summary>Zerlegt den Text in Klammern, Wörter und Satzzeichen; Strings, Kommentare und Zahlen zählen nicht.
  /// </summary>
  TPairLexer = class
  private
    FText: string;
    FIndex: Integer;
    FLine: Integer;
    FLineStart: Integer;
    FList: TList<TLexToken>;
    function CharAt(AIndex: Integer): Char;
    procedure Add(AStart, ALength: Integer; AIsWord, APlain: Boolean);
    procedure NewLine;
    function AfterDot: Boolean;
    procedure SkipBraceComment;
    procedure LexSlash;
    procedure LexParen;
    procedure LexCaret;
    function LexString: Boolean;
    procedure LexWord;
    procedure SkipNumber;
    /// <summary>Verarbeitet das Zeichen an FIndex; True: danach ein Zeichen weiter.</summary>
    function Step: Boolean;
  public
    function Run(const AText: string): TArray<TLexToken>;
  end;

  /// <summary>Paart Klammern und Blockwörter und sammelt die Besitzer (#653).</summary>
  TPairAnalyzer = class
  private
    FTokens: TArray<TLexToken>;
    FResults: TList<TAtlasPairToken>;
    FBlocks: TList<TOpen>;
    FBrackets: TList<TOpen>;
    FClosed: TList<TAtlasPairBlock>;
    /// <summary>Token-Indizes von Routinenköpfen, deren Rumpf noch kommt (#653).</summary>
    FHeaders: TList<Integer>;
    function Emit(AIndex, ADepth: Integer; AUnpaired: Boolean): Integer;
    function TextAt(AIndex: Integer): string;
    function TopWord: string;
    function AfterParens(AIndex: Integer): string;
    procedure CloseBlock(AIndex: Integer);
    function Opens(AIndex: Integer; const AWord: string): Boolean;
    procedure AddOwner(var AOpen: TOpen; AIndex, ADepth: Integer);
    function FindBack(AFrom: Integer; const AWords: array of string): Integer;
    procedure AddCaseOwner(var AOpen: TOpen; AIndex, ADepth: Integer);
    procedure AddIfOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
    procedure AddLoopOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
    procedure AddRoutineOwners(var AOpen: TOpen; ADepth: Integer);
    procedure AddStatementOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
    procedure AddOwners(var AOpen: TOpen; AIndex: Integer);
    function IsRoutineHeader(AIndex: Integer; const AWord: string): Boolean;
    procedure TrackHeaders(AIndex: Integer; const AWord: string);
    procedure OpenBracket(AIndex: Integer);
    procedure CloseBracket(AIndex: Integer);
    procedure OpenBlock(AIndex: Integer; const AWord: string);
    procedure HandleEnd(AIndex: Integer);
    procedure HandleClose(AIndex: Integer; const AWord: string);
    procedure HandleToken(AIndex: Integer);
    procedure MarkUnpaired;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
  end;

function IsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in AWords do
  begin
    Result := Result or (mWord = AText);
  end;
end;

{ TPairLexer }

function TPairLexer.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(FText)) then
  begin
    Result := FText[AIndex];
  end;
end;

procedure TPairLexer.Add(AStart, ALength: Integer; AIsWord, APlain: Boolean);
var
  mToken: TLexToken;
begin
  mToken.Text := Copy(FText, AStart, ALength);
  mToken.Line := FLine;
  mToken.Character := AStart - FLineStart;
  mToken.IsWord := AIsWord;
  mToken.Plain := APlain;
  FList.Add(mToken);
end;

procedure TPairLexer.NewLine;
begin
  Inc(FLine);
  FLineStart := FIndex + 1;
end;

function TPairLexer.AfterDot: Boolean;
begin
  Result := (FList.Count > 0) and (FList.Last.Text = '.') and (FList.Last.Line = FLine);
end;

procedure TPairLexer.SkipBraceComment;
begin
  while (FIndex <= Length(FText)) and (FText[FIndex] <> '}') do
  begin
    if FText[FIndex] = #10 then
    begin
      NewLine;
    end;
    Inc(FIndex);
  end;
end;

procedure TPairLexer.LexSlash;
begin
  if CharAt(FIndex + 1) <> '/' then
  begin
    Add(FIndex, 1, False, False);
    Exit;
  end;
  while (FIndex < Length(FText)) and (FText[FIndex + 1] <> #10) do
  begin
    Inc(FIndex);
  end;
end;

procedure TPairLexer.LexParen;
begin
  if CharAt(FIndex + 1) <> '*' then
  begin
    Add(FIndex, 1, False, False);
    Exit;
  end;
  Inc(FIndex, 2);
  while (FIndex < Length(FText)) and not ((FText[FIndex] = '*') and (FText[FIndex + 1] = ')')) do
  begin
    if FText[FIndex] = #10 then
    begin
      NewLine;
    end;
    Inc(FIndex);
  end;
  Inc(FIndex);
end;

procedure TPairLexer.LexCaret;
begin
  Add(FIndex, 1, False, False);
  // ^[ ^] ^( ^) sind Steuerzeichen (#862), keine Klammern; P^[1] und F()^[1] bleiben
  // Dereferenzierung mit Index.
  if CharInSet(CharAt(FIndex + 1), ['[', ']', '(', ')']) and
    not CharInSet(CharAt(FIndex - 1), ['A'..'Z', 'a'..'z', '0'..'9', '_', ')', ']', '^']) then
  begin
    Inc(FIndex);
  end;
end;

function TPairLexer.LexString: Boolean;
begin
  Inc(FIndex);
  while (FIndex <= Length(FText)) and (FText[FIndex] <> '''') and (FText[FIndex] <> #10) do
  begin
    Inc(FIndex);
  end;
  // Am Zeilenende offen: das #10 zählt die nächste Runde.
  Result := CharAt(FIndex) <> #10;
end;

procedure TPairLexer.LexWord;
var
  mStart: Integer;
  mEscaped: Boolean;
begin
  mEscaped := FText[FIndex] = '&';
  mStart := FIndex;
  if mEscaped then
  begin
    Inc(FIndex);
  end;
  // @@End im asm-Block ist eine Sprungmarke, kein Blockende (#861).
  mEscaped := mEscaped or (CharAt(mStart - 1) = '@');
  while (FIndex <= Length(FText)) and CharInSet(FText[FIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Inc(FIndex);
  end;
  Add(mStart, FIndex - mStart, True, mEscaped or AfterDot);
end;

procedure TPairLexer.SkipNumber;
begin
  while (FIndex < Length(FText)) and CharInSet(FText[FIndex + 1], ['0'..'9', 'A'..'F', 'a'..'f', '$']) do
  begin
    Inc(FIndex);
  end;
end;

function TPairLexer.Step: Boolean;
begin
  Result := True;
  case FText[FIndex] of
    #10:
      begin
        NewLine;
      end;
    '{':
      begin
        SkipBraceComment;
      end;
    '/':
      begin
        LexSlash;
      end;
    '(':
      begin
        LexParen;
      end;
    '^':
      begin
        LexCaret;
      end;
    '''':
      begin
        Result := LexString;
      end;
    'A'..'Z', 'a'..'z', '_', '&':
      begin
        LexWord;
        Result := False;
      end;
    '0'..'9', '$', '#':
      begin
        SkipNumber;
      end;
    ' ', #9, #13:
      begin
      end;
  else
    begin
      Add(FIndex, 1, False, False);
    end;
  end;
end;

function TPairLexer.Run(const AText: string): TArray<TLexToken>;
begin
  FText := AText;
  FIndex := 1;
  FLine := 0;
  FLineStart := 1;
  FList := TList<TLexToken>.Create;
  try
    while FIndex <= Length(FText) do
    begin
      if Step then
      begin
        Inc(FIndex);
      end;
    end;
    Result := FList.ToArray;
  finally
    FreeAndNil(FList);
  end;
end;

{ TPairAnalyzer }

constructor TPairAnalyzer.Create;
begin
  inherited Create;
  FResults := TList<TAtlasPairToken>.Create;
  FBlocks := TList<TOpen>.Create;
  FBrackets := TList<TOpen>.Create;
  FClosed := TList<TAtlasPairBlock>.Create;
  FHeaders := TList<Integer>.Create;
end;

destructor TPairAnalyzer.Destroy;
begin
  FHeaders.Free;
  FClosed.Free;
  FBrackets.Free;
  FBlocks.Free;
  FResults.Free;
  inherited;
end;

function TPairAnalyzer.Emit(AIndex, ADepth: Integer; AUnpaired: Boolean): Integer;
var
  mPair: TAtlasPairToken;
begin
  mPair.Line := FTokens[AIndex].Line;
  mPair.Character := FTokens[AIndex].Character;
  mPair.Length := Length(FTokens[AIndex].Text);
  mPair.Depth := ADepth;
  mPair.Unpaired := AUnpaired;
  mPair.IsWord := FTokens[AIndex].IsWord;
  mPair.Owner := False;
  Result := FResults.Add(mPair);
end;

function TPairAnalyzer.TextAt(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FTokens)) and not FTokens[AIndex].Plain then
  begin
    Result := LowerCase(FTokens[AIndex].Text);
  end;
end;

function TPairAnalyzer.TopWord: string;
begin
  Result := '';
  if FBlocks.Count > 0 then
  begin
    Result := FBlocks.Last.Word;
  end;
end;

/// <summary>Nach "class(TBase)" bzw. "interface(IBase)": Token hinter der Klammer.</summary>
function TPairAnalyzer.AfterParens(AIndex: Integer): string;
var
  mDepth, mIndex: Integer;
begin
  Result := TextAt(AIndex);
  if Result <> '(' then
  begin
    Exit;
  end;
  Result := '';
  mDepth := 0;
  mIndex := AIndex;
  while mIndex <= High(FTokens) do
  begin
    if FTokens[mIndex].Text = '(' then
    begin
      Inc(mDepth);
    end
    else if FTokens[mIndex].Text = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(TextAt(mIndex + 1));
      end;
    end;
    Inc(mIndex);
  end;
end;

// Der oberste offene Block endet am Token AIndex.
procedure TPairAnalyzer.CloseBlock(AIndex: Integer);
var
  mBlock: TAtlasPairBlock;
begin
  mBlock.OpenLine := FResults.List[FBlocks.Last.Index].Line;
  mBlock.OpenCharacter := FResults.List[FBlocks.Last.Index].Character;
  mBlock.CloseLine := FTokens[AIndex].Line;
  mBlock.CloseCharacter := FTokens[AIndex].Character;
  mBlock.OwnerLine := FBlocks.Last.OwnerLine;
  mBlock.OwnerCharacter := FBlocks.Last.OwnerCharacter;
  FBlocks.Delete(FBlocks.Count - 1);
  mBlock.Depth := FBlocks.Count;
  FClosed.Add(mBlock);
  Emit(AIndex, FBlocks.Count, False);
end;

function TPairAnalyzer.Opens(AIndex: Integer; const AWord: string): Boolean;
var
  mPrevious: string;
begin
  mPrevious := TextAt(AIndex - 1);
  if IsOneOf(AWord, ['begin', 'try', 'repeat', 'asm']) then
  begin
    Result := True;
  end
  else if AWord = 'case' then
  begin
    Result := not IsOneOf(TopWord, ['record', 'class', 'object']);
  end
  else if AWord = 'record' then
  begin
    Result := IsOneOf(mPrevious, ['=', ':', 'of', 'packed']);
  end
  else if IsOneOf(AWord, ['class', 'interface', 'dispinterface']) then
  begin
    Result := IsOneOf(mPrevious, ['=', 'packed']) and (TextAt(AIndex + 1) <> 'of') and
      (AfterParens(AIndex + 1) <> ';');
  end
  else
  begin
    Result := (AWord = 'object') and (mPrevious = '=');
  end;
end;

/// <summary>AIndex als Besitzer des Blocks AOpen in der Tiefe ADepth (#653).</summary>
procedure TPairAnalyzer.AddOwner(var AOpen: TOpen; AIndex, ADepth: Integer);
var
  mAdded: Integer;
begin
  mAdded := Emit(AIndex, ADepth, False);
  FResults.List[mAdded].Owner := True;
  AOpen.Owners := AOpen.Owners + [mAdded];
  if (FTokens[AIndex].Line < AOpen.OwnerLine) or
    ((FTokens[AIndex].Line = AOpen.OwnerLine) and (FTokens[AIndex].Character < AOpen.OwnerCharacter)) then
  begin
    AOpen.OwnerLine := FTokens[AIndex].Line;
    AOpen.OwnerCharacter := FTokens[AIndex].Character;
  end;
end;

/// <summary>Rückwärts ab AFrom das erste der Wörter AWords; -1 bei einem Ende der Anweisung davor.</summary>
function TPairAnalyzer.FindBack(AFrom: Integer; const AWords: array of string): Integer;
var
  mText: string;
begin
  Result := AFrom;
  while Result >= 0 do
  begin
    mText := TextAt(Result);
    if IsOneOf(mText, AWords) then
    begin
      Exit;
    end;
    if IsOneOf(mText, [';', 'begin', 'end', 'then', 'do', 'else', 'of', 'try', 'finally', 'except', 'repeat',
      'until', 'asm']) then
    begin
      Break;
    end;
    Dec(Result);
  end;
  Result := -1;
end;

/// <summary>Besitzer von case: das "of" dahinter.</summary>
procedure TPairAnalyzer.AddCaseOwner(var AOpen: TOpen; AIndex, ADepth: Integer);
var
  mFound, mParens: Integer;
  mText: string;
  mDone: Boolean;
begin
  mParens := 0;
  mFound := AIndex + 1;
  mDone := False;
  while not mDone and (mFound <= High(FTokens)) do
  begin
    mText := TextAt(mFound);
    if IsOneOf(mText, ['(', '[']) then
    begin
      Inc(mParens);
    end
    else if IsOneOf(mText, [')', ']']) then
    begin
      Dec(mParens);
    end
    else if (mParens = 0) and (mText = 'of') then
    begin
      AddOwner(AOpen, mFound, ADepth);
      mDone := True;
    end
    else
    begin
      mDone := IsOneOf(mText, [';', 'begin', 'end']);
    end;
    Inc(mFound);
  end;
end;

/// <summary>if … then begin: then, if und ein else davor.</summary>
procedure TPairAnalyzer.AddIfOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
var
  mFound: Integer;
begin
  mFound := FindBack(AIndex - 2, ['if']);
  if mFound < 0 then
  begin
    Exit;
  end;
  AddOwner(AOpen, AIndex - 1, ADepth);
  AddOwner(AOpen, mFound, ADepth);
  if TextAt(mFound - 1) = 'else' then
  begin
    AddOwner(AOpen, mFound - 1, ADepth);
  end;
end;

/// <summary>for/while/with/on … do begin: do und das Schlüsselwort davor.</summary>
procedure TPairAnalyzer.AddLoopOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
var
  mFound: Integer;
begin
  mFound := FindBack(AIndex - 2, ['for', 'while', 'with', 'on']);
  if mFound >= 0 then
  begin
    AddOwner(AOpen, AIndex - 1, ADepth);
    AddOwner(AOpen, mFound, ADepth);
  end;
end;

/// <summary>Rumpf der zuletzt begonnenen Routine (lokale Routinen kommen vor dem äußeren Rumpf).</summary>
procedure TPairAnalyzer.AddRoutineOwners(var AOpen: TOpen; ADepth: Integer);
var
  mFound: Integer;
begin
  mFound := FHeaders.Last;
  FHeaders.Delete(FHeaders.Count - 1);
  AddOwner(AOpen, mFound, ADepth);
  if TextAt(mFound - 1) = 'class' then
  begin
    AddOwner(AOpen, mFound - 1, ADepth);
  end;
end;

/// <summary>Besitzer von begin bzw. asm: die Anweisung davor.</summary>
procedure TPairAnalyzer.AddStatementOwners(var AOpen: TOpen; AIndex, ADepth: Integer);
var
  mBefore: string;
begin
  mBefore := TextAt(AIndex - 1);
  if mBefore = 'then' then
  begin
    AddIfOwners(AOpen, AIndex, ADepth);
  end
  else if mBefore = 'do' then
  begin
    AddLoopOwners(AOpen, AIndex, ADepth);
  end
  else if mBefore = 'else' then
  begin
    AddOwner(AOpen, AIndex - 1, ADepth);
  end
  else if (ADepth = 0) and (FHeaders.Count > 0) then
  begin
    AddRoutineOwners(AOpen, ADepth);
  end;
end;

/// <summary>Besitzer des Öffners am Token AIndex: Anweisung davor bzw. "of" hinter case.</summary>
procedure TPairAnalyzer.AddOwners(var AOpen: TOpen; AIndex: Integer);
begin
  if AOpen.Word = 'case' then
  begin
    AddCaseOwner(AOpen, AIndex, FBlocks.Count);
  end
  else if IsOneOf(AOpen.Word, ['begin', 'asm']) then
  begin
    AddStatementOwners(AOpen, AIndex, FBlocks.Count);
  end;
end;

function TPairAnalyzer.IsRoutineHeader(AIndex: Integer; const AWord: string): Boolean;
var
  mPrevious: string;
begin
  mPrevious := TextAt(AIndex - 1);
  Result := (FBlocks.Count = 0) and not IsOneOf(mPrevious, ['=', ':', 'to', 'of', '(', ',']);
  if Result and (AWord = 'operator') then
  begin
    Result := mPrevious = 'class';
  end
  else if Result then
  begin
    Result := IsOneOf(AWord, ['procedure', 'function', 'constructor', 'destructor']);
  end;
end;

procedure TPairAnalyzer.TrackHeaders(AIndex: Integer; const AWord: string);
begin
  if IsRoutineHeader(AIndex, AWord) then
  begin
    FHeaders.Add(AIndex);
  end
  else if AWord = 'implementation' then
  begin
    FHeaders.Clear;
  end
  else if IsOneOf(AWord, ['forward', 'external']) and (FBlocks.Count = 0) and (FHeaders.Count > 0) then
  begin
    FHeaders.Delete(FHeaders.Count - 1);
  end;
end;

procedure TPairAnalyzer.OpenBracket(AIndex: Integer);
var
  mOpen: TOpen;
begin
  mOpen := Default(TOpen);
  mOpen.Word := FTokens[AIndex].Text;
  mOpen.Index := Emit(AIndex, FBrackets.Count, False);
  FBrackets.Add(mOpen);
end;

procedure TPairAnalyzer.CloseBracket(AIndex: Integer);
begin
  if (FBrackets.Count > 0) and ((FBrackets.Last.Word = '(') = (FTokens[AIndex].Text = ')')) then
  begin
    FBrackets.Delete(FBrackets.Count - 1);
    Emit(AIndex, FBrackets.Count, False);
  end
  else
  begin
    Emit(AIndex, 0, True);
  end;
end;

procedure TPairAnalyzer.OpenBlock(AIndex: Integer; const AWord: string);
var
  mOpen: TOpen;
begin
  mOpen.Word := AWord;
  mOpen.Index := Emit(AIndex, FBlocks.Count, False);
  mOpen.Owners := nil;
  mOpen.OwnerLine := FTokens[AIndex].Line;
  mOpen.OwnerCharacter := FTokens[AIndex].Character;
  AddOwners(mOpen, AIndex);
  FBlocks.Add(mOpen);
end;

procedure TPairAnalyzer.HandleEnd(AIndex: Integer);
begin
  if (FBlocks.Count > 0) and (TopWord <> 'repeat') then
  begin
    CloseBlock(AIndex);
  end
  // "end." ohne Öffner: Ende der Unit bzw. des Programms.
  else if (FBlocks.Count > 0) or (TextAt(AIndex + 1) <> '.') then
  begin
    Emit(AIndex, 0, True);
  end;
end;

procedure TPairAnalyzer.HandleClose(AIndex: Integer; const AWord: string);
begin
  if AWord = 'end' then
  begin
    HandleEnd(AIndex);
  end
  else if (AWord = 'until') and (TopWord = 'repeat') then
  begin
    CloseBlock(AIndex);
  end
  else if AWord = 'until' then
  begin
    Emit(AIndex, 0, True);
  end
  else if IsOneOf(AWord, ['finally', 'except']) and (TopWord = 'try') then
  begin
    Emit(AIndex, FBlocks.Count - 1, False);
  end;
end;

procedure TPairAnalyzer.HandleToken(AIndex: Integer);
var
  mWord: string;
begin
  if not FTokens[AIndex].IsWord then
  begin
    if IsOneOf(FTokens[AIndex].Text, ['(', '[']) then
    begin
      OpenBracket(AIndex);
    end
    else if IsOneOf(FTokens[AIndex].Text, [')', ']']) then
    begin
      CloseBracket(AIndex);
    end;
  end
  else if not FTokens[AIndex].Plain then
  begin
    mWord := LowerCase(FTokens[AIndex].Text);
    TrackHeaders(AIndex, mWord);
    if Opens(AIndex, mWord) then
    begin
      OpenBlock(AIndex, mWord);
    end
    else
    begin
      HandleClose(AIndex, mWord);
    end;
  end;
end;

/// <summary>Offen geblieben: unpaarig.</summary>
procedure TPairAnalyzer.MarkUnpaired;
var
  mOpen: TOpen;
  mOwner: Integer;
begin
  for mOpen in FBlocks do
  begin
    FResults.List[mOpen.Index].Unpaired := True;
    for mOwner in mOpen.Owners do
    begin
      FResults.List[mOwner].Unpaired := True;
    end;
  end;
  for mOpen in FBrackets do
  begin
    FResults.List[mOpen.Index].Unpaired := True;
  end;
end;

function TPairAnalyzer.Run(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
var
  mLexer: TPairLexer;
  mIndex: Integer;
begin
  mLexer := TPairLexer.Create;
  try
    FTokens := mLexer.Run(AText);
  finally
    mLexer.Free;
  end;
  for mIndex := 0 to High(FTokens) do
  begin
    HandleToken(mIndex);
  end;
  MarkUnpaired;
  FResults.Sort(TComparer<TAtlasPairToken>.Construct(
    function(const A, B: TAtlasPairToken): Integer
    begin
      Result := A.Line - B.Line;
      if Result = 0 then
      begin
        Result := A.Character - B.Character;
      end;
    end));
  Result := FResults.ToArray;
  ABlocks := FClosed.ToArray;
end;

{ TAtlasPairs }

class function TAtlasPairs.Spans(const AText, ALine: string; const ALineTokens: TArray<TAtlasPairToken>;
  AOwners: Boolean): TArray<TAtlasPairSpan>;
var
  Offset: Integer;
  Token: TAtlasPairToken;
  Span: TAtlasPairSpan;
begin
  Result := nil;
  // AText beginnt ohne Einrückung: Zeichenindex in der Zeile minus Einrückung.
  Offset := System.Length(ALine) - System.Length(TrimLeft(ALine));
  for Token in ALineTokens do
  begin
    if Token.Owner and not AOwners then
    begin
      Continue;
    end;
    Span.Start := Token.Character - Offset + 1;
    Span.Length := Token.Length;
    Span.Depth := Token.Depth;
    Span.Unpaired := Token.Unpaired;
    // Hinter einem gekürzten „(…)“ steht anderer Text: nur, was dort wirklich steht.
    if (Span.Start < 1) or (Span.Start + Span.Length - 1 > System.Length(AText)) or
      (Copy(AText, Span.Start, Span.Length) <> Copy(ALine, Token.Character + 1, Token.Length)) then
    begin
      Continue;
    end;
    Result := Result + [Span];
  end;
end;

class function TAtlasPairs.DisplayLine(const ALine: string; ATabWidth: Integer): string;
var
  Builder: TStringBuilder;
  Ch: Char;
begin
  Builder := TStringBuilder.Create;
  try
    for Ch in ALine do
    begin
      if (Ch = #9) and (ATabWidth > 0) then
      begin
        Builder.Append(' ', ATabWidth - Builder.Length mod ATabWidth);
      end
      else if Ch <> #13 then
      begin
        Builder.Append(Ch);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasPairs.RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean;
begin
  Result := (ARun <> '') and (AColumn >= 1) and (Copy(ADisplayLine, AColumn, Length(ARun)) = ARun);
end;

class function TAtlasPairs.ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 1;
  for Index := 1 to ACharacter do
  begin
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
    begin
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasPairs.Analyze(const AText: string): TArray<TAtlasPairToken>;
var
  Blocks: TArray<TAtlasPairBlock>;
begin
  Result := Analyze(AText, Blocks);
end;

class function TAtlasPairs.Analyze(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
var
  mAnalyzer: TPairAnalyzer;
begin
  mAnalyzer := TPairAnalyzer.Create;
  try
    Result := mAnalyzer.Run(AText, ABlocks);
  finally
    mAnalyzer.Free;
  end;
end;

end.
