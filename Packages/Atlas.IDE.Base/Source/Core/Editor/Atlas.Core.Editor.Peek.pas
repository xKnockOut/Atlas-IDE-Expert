unit Atlas.Core.Editor.Peek;

// Definition und Referenzen einblenden (#505), Kern ohne IDE und VCL:
// - TAtlasPeek.Overloads sucht in der Gliederung der Datei (documentSymbol)
//   alle Fundstellen derselben Routine: Überladungen, Deklaration in der
//   Klasse bzw. im interface und Implementierung („TBar.Add“).
// - TAtlasPeek.Pair ordnet die Fundstellen einer Routine (Überladungen,
//   Deklaration und Implementierung) zu Zielen: Jede Deklaration bekommt die
//   Implementierung, auf die „Gehe zu Definition“ von ihr aus führt.
// - DeclarationStart, DeclarationEnd und BodyEnd grenzen den Ausschnitt in den
//   Zeilen der Zieldatei ab. Ein kleiner Scanner überspringt Strings,
//   Kommentare und Compiler-Direktiven; es ist kein Parser, sondern zählt nur
//   Blöcke (begin/try/case/asm/record … end) und Klammern.
// - DefinitionRows und ReferenceRows bauen die Zeilen der Ansicht (Tabs
//   aufgelöst, Zielzeile und Name markiert, Trennzeile vor der Implementierung).
// - TAtlasPeekView hält Ziele, Auswahl und Scrollstand (Pfeile, Bild auf/ab).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract;

type
  TAtlasPeekPlace = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert.</summary>
    Character: Integer;
    class function Create(const AFileName: string; ALine, ACharacter: Integer): TAtlasPeekPlace; static;
    /// <summary>Gleiche Datei (ohne Groß-/Kleinschreibung) und Zeile.</summary>
    function SameLine(const AOther: TAtlasPeekPlace): Boolean;
  end;

  /// <summary>Ein Ziel der Liste: Deklaration bzw. Fundstelle, bei Routinen mit Implementierung.</summary>
  TAtlasPeekTarget = record
    Place: TAtlasPeekPlace;
    HasBody: Boolean;
    Body: TAtlasPeekPlace;
  end;

  /// <summary>„Gehe zu Definition“ von APlace aus; False ohne Ziel.</summary>
  TAtlasPeekResolve = reference to function(const APlace: TAtlasPeekPlace; out ATarget: TAtlasPeekPlace): Boolean;

{$SCOPEDENUMS ON}
  TAtlasPeekRowKind = (Code, Separator);
  TAtlasPeekMode = (Definition, References);
{$SCOPEDENUMS OFF}

  TAtlasPeekRow = record
    Kind: TAtlasPeekRowKind;
    /// <summary>Zeilentext mit aufgelösten Tabs; leer bei Trennzeilen.</summary>
    Text: string;
    FileName: string;
    /// <summary>Zeile in der Datei, 0-basiert; bei Trennzeilen die erste Zeile des folgenden Abschnitts.</summary>
    Line: Integer;
    /// <summary>Zeile der Deklaration bzw. Fundstelle.</summary>
    Target: Boolean;
    /// <summary>Name auf der Zielzeile in Text, 0-basiert, Stop exklusiv; -1 ohne.</summary>
    NameStart: Integer;
    NameStop: Integer;
  end;

  TAtlasPeekEntry = record
    Target: TAtlasPeekTarget;
    /// <summary>Gekürzte Zielzeile für die Liste.</summary>
    Excerpt: string;
    Rows: TArray<TAtlasPeekRow>;
  end;

  TAtlasPeek = class
  public const
    /// <summary>Höchstens so viele Zeilen je Abschnitt (Deklaration bzw. Implementierung).</summary>
    cMaxBlockLines = 400;
    /// <summary>Zeilen vor und nach einer Referenz.</summary>
    cReferenceBefore = 3;
    cReferenceAfter = 40;
    cMaxExcerpt = 80;
  public
    /// <summary>Erste Zeile des Ausschnitts: ALine samt direkt darüber stehender ///-Kommentare und
    /// Attribute ([...]).</summary>
    class function DeclarationStart(const ALines: TArray<string>; ALine: Integer): Integer; static;
    /// <summary>Letzte Zeile der Deklaration ab ALine: bis zum ersten ";" außerhalb von Klammern samt
    /// folgender Direktiven (overload; virtual; …); bei class/record/interface bis zum passenden end.</summary>
    class function DeclarationEnd(const ALines: TArray<string>; ALine: Integer): Integer; static;
    /// <summary>Letzte Zeile der Implementierung, deren Kopf in ALine beginnt: lokale Abschnitte und
    /// Routinen eingeschlossen, bis zum end des Rumpfs. Ohne Rumpf (external, forward) das Ende des Kopfs.</summary>
    class function BodyEnd(const ALines: TArray<string>; ALine: Integer): Integer; static;
    /// <summary>Alle Fundstellen der Routine, deren Name in ALine steht (nach Zeile sortiert); leer, wenn dort
    /// keine Routine steht. Gleich sind Name und Besitzer (Container bzw. „TBar.“ vor dem Namen); interface
    /// und implementation gelten als derselbe Besitzer.</summary>
    class function Overloads(const ASymbols: TArray<TAtlasSymbol>; ALine: Integer): TArray<TAtlasPeekPlace>; static;
    /// <summary>Ordnet APlaces (nach Datei und Zeile sortiert) zu Zielen: Führt AResolve von einer
    /// Fundstelle zu einer anderen der Liste, ist diese die Implementierung und kein eigenes Ziel. Führt es
    /// an eine Stelle außerhalb der Liste, ist diese die Implementierung.</summary>
    class function Pair(const APlaces: TArray<TAtlasPeekPlace>; const AResolve: TAtlasPeekResolve):
      TArray<TAtlasPeekTarget>; static;
    class function ExpandTabs(const AText: string; ATabWidth: Integer): string; static;
    /// <summary>Getrimmte, gekürzte Zeile für die Liste.</summary>
    class function Excerpt(const ALine: string): string; static;
    /// <summary>Zeilen für ein Definitionsziel: Deklaration aus ADeclLines, bei AShowBody und HasBody eine
    /// Trennzeile und die Implementierung aus ABodyLines.</summary>
    class function DefinitionRows(const ATarget: TAtlasPeekTarget; const ADeclLines, ABodyLines: TArray<string>;
      AShowBody: Boolean; ATabWidth: Integer): TArray<TAtlasPeekRow>; static;
    /// <summary>Zeilen um eine Referenz: ReferenceBefore davor, ReferenceAfter danach.</summary>
    class function ReferenceRows(const APlace: TAtlasPeekPlace; const ALines: TArray<string>;
      ATabWidth: Integer): TArray<TAtlasPeekRow>; static;
  end;

  /// <summary>Zustand des offenen Fensters: Ziele, Auswahl, oberste sichtbare Zeile.</summary>
  TAtlasPeekView = class
  private
    FMode: TAtlasPeekMode;
    FTitle: string;
    FEntries: TArray<TAtlasPeekEntry>;
    FSelected: Integer;
    FTop: Integer;
    FPageRows: Integer;
    procedure SetPageRows(AValue: Integer);
    procedure SetTop(AValue: Integer);
  public
    constructor Create(AMode: TAtlasPeekMode; const ATitle: string; const AEntries: TArray<TAtlasPeekEntry>);
    function Count: Integer;
    function Entry(AIndex: Integer): TAtlasPeekEntry;
    /// <summary>Gewähltes Ziel; Count > 0 vorausgesetzt.</summary>
    function Current: TAtlasPeekEntry;
    /// <summary>Wählt AIndex (begrenzt) und scrollt an den Anfang des Ausschnitts.</summary>
    procedure Select(AIndex: Integer);
    procedure SelectNext;
    procedure SelectPrevious;
    procedure PageDown;
    procedure PageUp;
    procedure ScrollBy(ADelta: Integer);
    /// <summary>Größte sinnvolle oberste Zeile.</summary>
    function MaxTop: Integer;
    /// <summary>Stelle, die Enter öffnet: die Zielzeile, ohne Ziel die oberste sichtbare Codezeile.</summary>
    function OpenPlace: TAtlasPeekPlace;
    property Mode: TAtlasPeekMode read FMode;
    property Title: string read FTitle;
    property Selected: Integer read FSelected;
    property Top: Integer read FTop write SetTop;
    /// <summary>Sichtbare Zeilen; setzt das Fenster nach dem Messen.</summary>
    property PageRows: Integer read FPageRows write SetPageRows;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars;

type
  /// <summary>Wörter (klein) und Satzzeichen über mehrere Zeilen; Strings, Kommentare und {$…} zählen nicht.</summary>
  TPeekScanner = record
  private
    FLines: TArray<string>;
    FLine: Integer;
    FPos: Integer;
    FLastLine: Integer;
    /// <summary>Zeichen AIndex der aktuellen Zeile; #0 außerhalb.</summary>
    function CharAt(AIndex: Integer): Char;
    procedure SkipBraceComment;
    procedure SkipParenComment;
    procedure SkipString;
    /// <summary>Überspringt Zeilenende, Leerraum, einen Kommentar oder String; False vor einem Token.</summary>
    function SkipTrivia: Boolean;
    function ReadToken: string;
  public
    /// <summary>Ab ALine (0-basiert), höchstens bis ALastLine.</summary>
    procedure Init(const ALines: TArray<string>; ALine, ALastLine: Integer);
    /// <summary>Nächstes Token; AToken ist ein Wort in Kleinbuchstaben oder ein einzelnes Zeichen.</summary>
    function Next(out AToken: string; out ALine: Integer): Boolean;
    /// <summary>Nächstes Token, ohne weiterzugehen.</summary>
    function Peek(out AToken: string): Boolean;
  end;

{ TPeekScanner }

procedure TPeekScanner.Init(const ALines: TArray<string>; ALine, ALastLine: Integer);
begin
  FLines := ALines;
  FLine := ALine;
  FPos := 1;
  FLastLine := Min(ALastLine, High(ALines));
end;

function TPeekScanner.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(FLines[FLine])) then
  begin
    Result := FLines[FLine][AIndex];
  end;
end;

procedure TPeekScanner.SkipBraceComment;
var
  mText: string;
  mFound: Boolean;
begin
  Inc(FPos);
  mFound := False;
  while not mFound and (FLine <= FLastLine) do
  begin
    mText := FLines[FLine];
    while (FPos <= Length(mText)) and (mText[FPos] <> '}') do
    begin
      Inc(FPos);
    end;
    mFound := FPos <= Length(mText);
    if not mFound then
    begin
      Inc(FLine);
      FPos := 1;
    end;
  end;
  Inc(FPos);
end;

procedure TPeekScanner.SkipParenComment;
var
  mText: string;
  mFound: Boolean;
begin
  Inc(FPos, 2);
  mFound := False;
  while not mFound and (FLine <= FLastLine) do
  begin
    mText := FLines[FLine];
    while (FPos < Length(mText)) and not ((mText[FPos] = '*') and (mText[FPos + 1] = ')')) do
    begin
      Inc(FPos);
    end;
    mFound := FPos < Length(mText);
    if not mFound then
    begin
      Inc(FLine);
      FPos := 1;
    end;
  end;
  Inc(FPos, 2);
end;

procedure TPeekScanner.SkipString;
var
  mText: string;
begin
  mText := FLines[FLine];
  Inc(FPos);
  while (FPos <= Length(mText)) and (mText[FPos] <> '''') do
  begin
    Inc(FPos);
  end;
  Inc(FPos);
end;

function TPeekScanner.SkipTrivia: Boolean;
var
  mChar: Char;
begin
  Result := True;
  mChar := CharAt(FPos);
  if FPos > Length(FLines[FLine]) then
  begin
    Inc(FLine);
    FPos := 1;
  end
  else if CharInSet(mChar, [' ', #9]) then
  begin
    Inc(FPos);
  end
  // Kommentare über mehrere Zeilen: {…} und (*…*).
  else if mChar = '{' then
  begin
    SkipBraceComment;
  end
  else if (mChar = '(') and (CharAt(FPos + 1) = '*') then
  begin
    SkipParenComment;
  end
  else if (mChar = '/') and (CharAt(FPos + 1) = '/') then
  begin
    FPos := Length(FLines[FLine]) + 1;
  end
  else if mChar = '''' then
  begin
    SkipString;
  end
  else
  begin
    Result := False;
  end;
end;

function TPeekScanner.ReadToken: string;
var
  mText: string;
  mStart: Integer;
begin
  mText := FLines[FLine];
  mStart := FPos;
  Inc(FPos);
  if TTextChars.IsIdentStart(mText[mStart]) or (mText[mStart] = '&') then
  begin
    while (FPos <= Length(mText)) and TTextChars.IsIdentChar(mText[FPos]) do
    begin
      Inc(FPos);
    end;
    Result := LowerCase(Copy(mText, mStart, FPos - mStart));
  end
  else
  begin
    Result := mText[mStart];
  end;
end;

function TPeekScanner.Next(out AToken: string; out ALine: Integer): Boolean;
begin
  AToken := '';
  ALine := FLine;
  Result := False;
  while not Result and (FLine <= FLastLine) do
  begin
    if not SkipTrivia then
    begin
      ALine := FLine;
      AToken := ReadToken;
      Result := True;
    end;
  end;
end;

function TPeekScanner.Peek(out AToken: string): Boolean;
var
  mProbe: TPeekScanner;
  mLine: Integer;
begin
  mProbe := Self;
  Result := mProbe.Next(AToken, mLine);
end;

const
  // Direktiven, die nach dem ";" einer Routinen-Deklaration folgen können.
  cDirectives: array[0..23] of string = ('overload', 'virtual', 'override', 'abstract', 'inline', 'stdcall',
    'cdecl', 'pascal', 'register', 'safecall', 'reintroduce', 'static', 'dynamic', 'deprecated', 'platform',
    'final', 'message', 'external', 'forward', 'assembler', 'experimental', 'dispid', 'library', 'varargs');

function IsOneOf(const AToken: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in AWords do
  begin
    Result := Result or (mWord = AToken);
  end;
end;

function IsDirective(const AToken: string): Boolean;
begin
  Result := IsOneOf(AToken, cDirectives);
end;

function BracketDelta(const AToken: string): Integer;
begin
  Result := 0;
  if (AToken = '(') or (AToken = '[') then
  begin
    Result := 1;
  end
  else if (AToken = ')') or (AToken = ']') then
  begin
    Result := -1;
  end;
end;

/// <summary>Ende eines Kopfs: erstes ";" außerhalb von Klammern samt folgender Direktiven. AHasBody wird
/// False bei external oder forward.</summary>
function HeaderEnd(var AScanner: TPeekScanner; AStart: Integer; out AHasBody: Boolean): Integer;
var
  mToken, mFollowing: string;
  mLine, mDepth: Integer;
begin
  Result := AStart;
  AHasBody := True;
  mDepth := 0;
  while AScanner.Next(mToken, mLine) do
  begin
    Result := mLine;
    Inc(mDepth, BracketDelta(mToken));
    if (mToken = 'external') or (mToken = 'forward') then
    begin
      AHasBody := False;
    end
    // Direktiven nach dem ";": "procedure A; overload; virtual;" oder in den Folgezeilen.
    else if (mToken = ';') and (mDepth <= 0) and not (AScanner.Peek(mFollowing) and IsDirective(mFollowing)) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ein folgendes ";" gehört noch zum end in ALine.</summary>
function EndWithSemicolon(var AScanner: TPeekScanner; ALine: Integer): Integer;
var
  mFollowing: string;
begin
  Result := ALine;
  if AScanner.Peek(mFollowing) and (mFollowing = ';') then
  begin
    AScanner.Next(mFollowing, Result);
  end;
end;

/// <summary>Überspringt eine Klammer "( … )" samt Inhalt; ALine: Zeile des letzten Tokens.</summary>
procedure SkipParens(var AScanner: TPeekScanner; var ALine: Integer);
var
  mToken: string;
  mTokenLine, mDepth: Integer;
  mDone: Boolean;
begin
  mDepth := 0;
  mDone := False;
  while not mDone and AScanner.Next(mToken, mTokenLine) do
  begin
    ALine := mTokenLine;
    if mToken = '(' then
    begin
      Inc(mDepth);
    end
    else if mToken = ')' then
    begin
      Dec(mDepth);
      mDone := mDepth = 0;
    end;
  end;
end;

/// <summary>Tiefe, um die ein verschachteltes "= class/interface/object" den Block vertieft: 0 bei "class of",
/// "class;" und "class(TBase);".</summary>
function NestedBlockDepth(var AScanner: TPeekScanner): Integer;
var
  mFollowing: string;
  mLine: Integer;
begin
  Result := 0;
  AScanner.Peek(mFollowing);
  if mFollowing = '(' then
  begin
    // Verschachtelte Klasse mit Vorfahr: Block, außer "class(TBase);".
    mLine := 0;
    SkipParens(AScanner, mLine);
    if AScanner.Peek(mFollowing) and (mFollowing <> ';') then
    begin
      Result := 1;
    end;
  end
  else if (mFollowing <> '') and (mFollowing <> 'of') and (mFollowing <> ';') then
  begin
    Result := 1;
  end;
end;

/// <summary>Block bis zum passenden end; darin zählen nur weitere record und "= class/interface".</summary>
function BlockEnd(var AScanner: TPeekScanner; ALine: Integer): Integer;
var
  mToken, mPrevious: string;
  mLine, mDepth: Integer;
begin
  Result := ALine;
  mDepth := 1;
  mPrevious := '';
  while AScanner.Next(mToken, mLine) do
  begin
    Result := mLine;
    if mToken = 'end' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(EndWithSemicolon(AScanner, Result));
      end;
    end
    else if mToken = 'record' then
    begin
      Inc(mDepth);
    end
    else if (mPrevious = '=') and IsOneOf(mToken, ['class', 'interface', 'object']) then
    begin
      Inc(mDepth, NestedBlockDepth(AScanner));
    end;
    mPrevious := mToken;
  end;
end;

/// <summary>Ende eines Typs ab dem Schlüsselwort AToken (class, record, …, packed) in ALine.</summary>
function TypeBlockEnd(var AScanner: TPeekScanner; const AToken: string; ALine: Integer): Integer;
var
  mToken, mFollowing: string;
  mLine: Integer;
  mHasBody: Boolean;
begin
  Result := ALine;
  mLine := ALine;
  if (AToken = 'packed') and not AScanner.Next(mToken, mLine) then
  begin
    Exit;
  end;
  // "class of", "class;" und "class(TBase);" sind keine Blöcke.
  if not AScanner.Peek(mFollowing) then
  begin
    Exit;
  end;
  if mFollowing = '(' then
  begin
    SkipParens(AScanner, mLine);
    Result := mLine;
    AScanner.Peek(mFollowing);
    if mFollowing = ';' then
    begin
      Exit(HeaderEnd(AScanner, mLine, mHasBody));
    end;
  end
  else if (mFollowing = 'of') or (mFollowing = ';') then
  begin
    Exit(HeaderEnd(AScanner, mLine, mHasBody));
  end;
  Result := BlockEnd(AScanner, Result);
end;

/// <summary>Ende nach dem ";" in ALine: folgen Direktiven, geht es wie bei einem Routinenkopf weiter.</summary>
function DeclarationTail(var AScanner: TPeekScanner; ALine: Integer): Integer;
var
  mFollowing: string;
  mHasBody: Boolean;
begin
  Result := ALine;
  if AScanner.Peek(mFollowing) and IsDirective(mFollowing) then
  begin
    Result := HeaderEnd(AScanner, ALine, mHasBody);
  end;
end;

/// <summary>Beginnt mit AToken nach APrevious eine lokale Routine vor dem Rumpf?</summary>
function IsLocalRoutineStart(ADepth: Integer; AStarted: Boolean; const AToken, APrevious: string): Boolean;
begin
  Result := (ADepth = 0) and not AStarted and
    IsOneOf(AToken, ['procedure', 'function', 'constructor', 'destructor']) and
    not IsOneOf(APrevious, ['=', 'to', 'class']);
end;

/// <summary>end auf Tiefe ADepth: True, wenn es den Rumpf beendet. Das end einer lokalen Routine zählt
/// APending herunter.</summary>
function CloseBlock(var ADepth, APending: Integer; AStarted: Boolean): Boolean;
begin
  Dec(ADepth);
  Result := False;
  if ADepth > 0 then
  begin
    Exit;
  end;
  ADepth := 0;
  Result := AStarted;
  if not Result and (APending > 0) then
  begin
    Dec(APending);
  end;
end;

{ TAtlasPeekPlace }

class function TAtlasPeekPlace.Create(const AFileName: string; ALine, ACharacter: Integer): TAtlasPeekPlace;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function TAtlasPeekPlace.SameLine(const AOther: TAtlasPeekPlace): Boolean;
begin
  Result := SameText(FileName, AOther.FileName) and (Line = AOther.Line);
end;

{ TAtlasPeek }

class function TAtlasPeek.DeclarationStart(const ALines: TArray<string>; ALine: Integer): Integer;
var
  mText: string;
begin
  Result := Max(0, Min(ALine, High(ALines)));
  while Result > 0 do
  begin
    mText := Trim(ALines[Result - 1]);
    if (Copy(mText, 1, 3) = '///') or ((mText <> '') and (mText[1] = '[') and (mText[Length(mText)] = ']')) then
    begin
      Dec(Result);
    end
    else
    begin
      Break;
    end;
  end;
end;

class function TAtlasPeek.DeclarationEnd(const ALines: TArray<string>; ALine: Integer): Integer;
var
  mScanner: TPeekScanner;
  mToken, mPrevious: string;
  mLine, mParens: Integer;
begin
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit(ALine);
  end;
  mScanner.Init(ALines, ALine, ALine + cMaxBlockLines - 1);
  Result := ALine;
  mPrevious := '';
  mParens := 0;
  // Bis zum "=" auf Ebene 0 bzw. zum ";" schauen, ob ein Typblock beginnt.
  while mScanner.Next(mToken, mLine) do
  begin
    Result := mLine;
    if (mToken = ';') and (mParens <= 0) then
    begin
      Exit(DeclarationTail(mScanner, mLine));
    end;
    if (mParens <= 0) and (mPrevious = '=') and
      IsOneOf(mToken, ['class', 'record', 'interface', 'dispinterface', 'object', 'packed']) then
    begin
      Exit(TypeBlockEnd(mScanner, mToken, mLine));
    end;
    Inc(mParens, BracketDelta(mToken));
    mPrevious := mToken;
  end;
end;

class function TAtlasPeek.BodyEnd(const ALines: TArray<string>; ALine: Integer): Integer;
var
  mScanner: TPeekScanner;
  mToken, mPrevious: string;
  mLine, mDepth, mPending: Integer;
  mHasBody, mStarted: Boolean;
begin
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit(ALine);
  end;
  mScanner.Init(ALines, ALine, ALine + cMaxBlockLines - 1);
  Result := HeaderEnd(mScanner, ALine, mHasBody);
  mDepth := 0;
  // Lokale Routinen vor dem Rumpf: Ihr end bringt die Tiefe auf 0, beendet aber nicht den Rumpf.
  mPending := 0;
  mStarted := False;
  mPrevious := '';
  while mHasBody and mScanner.Next(mToken, mLine) do
  begin
    Result := mLine;
    if IsLocalRoutineStart(mDepth, mStarted, mToken, mPrevious) then
    begin
      // Lokale Routine: ihren Kopf überspringen; external/forward hat keinen eigenen Rumpf.
      HeaderEnd(mScanner, mLine, mHasBody);
      mPending := mPending + Ord(mHasBody);
      mHasBody := True;
      mToken := ';';
    end
    else if IsOneOf(mToken, ['begin', 'asm', 'try', 'case', 'record']) then
    begin
      mStarted := mStarted or ((mDepth = 0) and (mPending = 0) and IsOneOf(mToken, ['begin', 'asm']));
      Inc(mDepth);
    end
    else if (mToken = 'end') and CloseBlock(mDepth, mPending, mStarted) then
    begin
      Exit(EndWithSemicolon(mScanner, Result));
    end;
    mPrevious := mToken;
  end;
end;

const
  // SymbolKind des LSP: Method, Constructor, Function, Operator.
  cRoutineKinds: array[0..3] of Integer = (6, 9, 12, 25);

function IsRoutine(AKind: Integer): Boolean;
var
  mKind: Integer;
begin
  for mKind in cRoutineKinds do
  begin
    if mKind = AKind then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name ohne Besitzer und Besitzer (klein); interface/implementation zählen als kein Besitzer.</summary>
procedure SplitName(const ASymbol: TAtlasSymbol; out AName, AOwner: string);
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', ASymbol.Name);
  if mDot > 0 then
  begin
    AName := Copy(ASymbol.Name, mDot + 1, MaxInt);
    AOwner := Copy(ASymbol.Name, 1, mDot - 1);
  end
  else
  begin
    AName := ASymbol.Name;
    AOwner := ASymbol.Container;
  end;
  AOwner := LowerCase(AOwner);
  if (AOwner = 'interface') or (AOwner = 'implementation') then
  begin
    AOwner := '';
  end;
end;

/// <summary>Erste Routine in ALine; -1 ohne.</summary>
function RoutineAt(const ASymbols: TArray<TAtlasSymbol>; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(ASymbols) downto 0 do
  begin
    if (ASymbols[mIndex].Line = ALine) and IsRoutine(ASymbols[mIndex].Kind) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Nach Zeile einsortieren, doppelte Zeilen nur einmal.</summary>
procedure InsertByLine(var APlaces: TArray<TAtlasPeekPlace>; const APlace: TAtlasPeekPlace);
var
  mIndex: Integer;
begin
  mIndex := Length(APlaces);
  while (mIndex > 0) and (APlaces[mIndex - 1].Line > APlace.Line) do
  begin
    Dec(mIndex);
  end;
  if (mIndex = 0) or (APlaces[mIndex - 1].Line <> APlace.Line) then
  begin
    Insert(APlace, APlaces, mIndex);
  end;
end;

/// <summary>Gleicher Name und Besitzer wie AName/AOwner?</summary>
function SameRoutine(const ASymbol: TAtlasSymbol; const AName, AOwner: string): Boolean;
var
  mName, mOwner: string;
begin
  Result := IsRoutine(ASymbol.Kind);
  if Result then
  begin
    SplitName(ASymbol, mName, mOwner);
    Result := SameText(mName, AName) and (mOwner = AOwner);
  end;
end;

class function TAtlasPeek.Overloads(const ASymbols: TArray<TAtlasSymbol>; ALine: Integer): TArray<TAtlasPeekPlace>;
var
  mIndex, mFound: Integer;
  mName, mOwner: string;
begin
  Result := nil;
  mFound := RoutineAt(ASymbols, ALine);
  if mFound < 0 then
  begin
    Exit;
  end;
  SplitName(ASymbols[mFound], mName, mOwner);
  for mIndex := 0 to High(ASymbols) do
  begin
    if SameRoutine(ASymbols[mIndex], mName, mOwner) then
    begin
      InsertByLine(Result, TAtlasPeekPlace.Create(ASymbols[mIndex].FileName, ASymbols[mIndex].Line,
        ASymbols[mIndex].Character));
    end;
  end;
end;

/// <summary>Implementierung zu AResolved: In der Liste nur eine noch freie Fundstelle (sonst führt eine
/// Implementierung zurück zur Deklaration), außerhalb die Stelle selbst.</summary>
procedure AssignBody(const APlaces: TArray<TAtlasPeekPlace>; var AUsed: TArray<Boolean>;
  const AResolved: TAtlasPeekPlace; var ATarget: TAtlasPeekTarget);
var
  mOther: Integer;
begin
  ATarget.HasBody := True;
  ATarget.Body := AResolved;
  mOther := 0;
  while (mOther <= High(APlaces)) and not APlaces[mOther].SameLine(AResolved) do
  begin
    Inc(mOther);
  end;
  if mOther <= High(APlaces) then
  begin
    ATarget.HasBody := not AUsed[mOther];
    if ATarget.HasBody then
    begin
      AUsed[mOther] := True;
      ATarget.Body := APlaces[mOther];
    end;
  end;
end;

class function TAtlasPeek.Pair(const APlaces: TArray<TAtlasPeekPlace>; const AResolve: TAtlasPeekResolve):
  TArray<TAtlasPeekTarget>;
var
  mUsed: TArray<Boolean>;
  mIndex, mCount: Integer;
  mResolved: TAtlasPeekPlace;
  mTarget: TAtlasPeekTarget;
begin
  Result := nil;
  SetLength(mUsed, Length(APlaces));
  SetLength(Result, Length(APlaces));
  mCount := 0;
  for mIndex := 0 to High(APlaces) do
  begin
    if mUsed[mIndex] then
    begin
      Continue;
    end;
    mUsed[mIndex] := True;
    mTarget.Place := APlaces[mIndex];
    mTarget.HasBody := False;
    mTarget.Body := Default(TAtlasPeekPlace);
    if Assigned(AResolve) and AResolve(APlaces[mIndex], mResolved) and not mResolved.SameLine(APlaces[mIndex]) then
    begin
      AssignBody(APlaces, mUsed, mResolved, mTarget);
    end;
    Result[mCount] := mTarget;
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

class function TAtlasPeek.ExpandTabs(const AText: string; ATabWidth: Integer): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
  mWidth: Integer;
begin
  if Pos(#9, AText) = 0 then
  begin
    Exit(AText);
  end;
  mWidth := Max(1, ATabWidth);
  mBuilder := TStringBuilder.Create;
  try
    for mCh in AText do
    begin
      if mCh = #9 then
      begin
        mBuilder.Append(' ', mWidth - mBuilder.Length mod mWidth);
      end
      else
      begin
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasPeek.Excerpt(const ALine: string): string;
begin
  Result := Trim(StringReplace(ALine, #9, ' ', [rfReplaceAll]));
  if Length(Result) > cMaxExcerpt then
  begin
    Result := Copy(Result, 1, cMaxExcerpt - 1) + '…';
  end;
end;

function CodeRow(const AFileName: string; const ALines: TArray<string>; ALine, ATabWidth: Integer;
  const ATarget: TAtlasPeekPlace; AMarkTarget: Boolean): TAtlasPeekRow;
var
  mOriginal: string;
  mFirst, mLast: Integer;
begin
  mOriginal := ALines[ALine];
  Result.Kind := TAtlasPeekRowKind.Code;
  Result.Text := TAtlasPeek.ExpandTabs(mOriginal, ATabWidth);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Target := AMarkTarget and (ALine = ATarget.Line);
  Result.NameStart := -1;
  Result.NameStop := -1;
  if not Result.Target then
  begin
    Exit;
  end;
  mFirst := Max(0, Min(ATarget.Character, Length(mOriginal)));
  mLast := mFirst;
  while (mFirst > 0) and TTextChars.IsIdentChar(mOriginal[mFirst]) do
  begin
    Dec(mFirst);
  end;
  while (mLast < Length(mOriginal)) and TTextChars.IsIdentChar(mOriginal[mLast + 1]) do
  begin
    Inc(mLast);
  end;
  if mLast > mFirst then
  begin
    Result.NameStart := Length(TAtlasPeek.ExpandTabs(Copy(mOriginal, 1, mFirst), ATabWidth));
    Result.NameStop := Length(TAtlasPeek.ExpandTabs(Copy(mOriginal, 1, mLast), ATabWidth));
  end;
end;

class function TAtlasPeek.DefinitionRows(const ATarget: TAtlasPeekTarget; const ADeclLines,
  ABodyLines: TArray<string>; AShowBody: Boolean; ATabWidth: Integer): TArray<TAtlasPeekRow>;
var
  mLine, mFirst, mLast, mCount: Integer;
  mSeparator: TAtlasPeekRow;
begin
  Result := nil;
  mCount := 0;
  if (ATarget.Place.Line >= 0) and (ATarget.Place.Line <= High(ADeclLines)) then
  begin
    mFirst := DeclarationStart(ADeclLines, ATarget.Place.Line);
    mLast := Min(DeclarationEnd(ADeclLines, ATarget.Place.Line), mFirst + cMaxBlockLines - 1);
    SetLength(Result, mLast - mFirst + 1);
    for mLine := mFirst to mLast do
    begin
      Result[mCount] := CodeRow(ATarget.Place.FileName, ADeclLines, mLine, ATabWidth, ATarget.Place, True);
      Inc(mCount);
    end;
  end;
  if AShowBody and ATarget.HasBody and (ATarget.Body.Line >= 0) and (ATarget.Body.Line <= High(ABodyLines)) then
  begin
    mFirst := DeclarationStart(ABodyLines, ATarget.Body.Line);
    mLast := Min(BodyEnd(ABodyLines, ATarget.Body.Line), mFirst + cMaxBlockLines - 1);
    mSeparator := Default(TAtlasPeekRow);
    mSeparator.Kind := TAtlasPeekRowKind.Separator;
    mSeparator.FileName := ATarget.Body.FileName;
    mSeparator.Line := ATarget.Body.Line;
    mSeparator.NameStart := -1;
    mSeparator.NameStop := -1;
    SetLength(Result, mCount + 1 + mLast - mFirst + 1);
    Result[mCount] := mSeparator;
    Inc(mCount);
    for mLine := mFirst to mLast do
    begin
      Result[mCount] := CodeRow(ATarget.Body.FileName, ABodyLines, mLine, ATabWidth, ATarget.Body, False);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TAtlasPeek.ReferenceRows(const APlace: TAtlasPeekPlace; const ALines: TArray<string>;
  ATabWidth: Integer): TArray<TAtlasPeekRow>;
var
  mLine, mFirst, mLast: Integer;
begin
  Result := nil;
  if (APlace.Line < 0) or (APlace.Line > High(ALines)) then
  begin
    Exit;
  end;
  mFirst := Max(0, APlace.Line - cReferenceBefore);
  mLast := Min(High(ALines), APlace.Line + cReferenceAfter);
  SetLength(Result, mLast - mFirst + 1);
  for mLine := mFirst to mLast do
  begin
    Result[mLine - mFirst] := CodeRow(APlace.FileName, ALines, mLine, ATabWidth, APlace, True);
  end;
end;

{ TAtlasPeekView }

constructor TAtlasPeekView.Create(AMode: TAtlasPeekMode; const ATitle: string;
  const AEntries: TArray<TAtlasPeekEntry>);
begin
  inherited Create;
  FMode := AMode;
  FTitle := ATitle;
  FEntries := AEntries;
  FPageRows := 1;
  FSelected := 0;
  FTop := 0;
end;

function TAtlasPeekView.Count: Integer;
begin
  Result := Length(FEntries);
end;

function TAtlasPeekView.Entry(AIndex: Integer): TAtlasPeekEntry;
begin
  Result := FEntries[AIndex];
end;

function TAtlasPeekView.Current: TAtlasPeekEntry;
begin
  Result := FEntries[FSelected];
end;

procedure TAtlasPeekView.Select(AIndex: Integer);
begin
  if Count = 0 then
  begin
    Exit;
  end;
  FSelected := EnsureRange(AIndex, 0, Count - 1);
  FTop := 0;
end;

procedure TAtlasPeekView.SelectNext;
begin
  if FSelected < Count - 1 then
  begin
    Select(FSelected + 1);
  end;
end;

procedure TAtlasPeekView.SelectPrevious;
begin
  if FSelected > 0 then
  begin
    Select(FSelected - 1);
  end;
end;

function TAtlasPeekView.MaxTop: Integer;
begin
  Result := 0;
  if Count > 0 then
  begin
    Result := Max(0, Length(Current.Rows) - FPageRows);
  end;
end;

procedure TAtlasPeekView.SetTop(AValue: Integer);
begin
  FTop := EnsureRange(AValue, 0, MaxTop);
end;

procedure TAtlasPeekView.SetPageRows(AValue: Integer);
begin
  FPageRows := Max(1, AValue);
  SetTop(FTop);
end;

procedure TAtlasPeekView.ScrollBy(ADelta: Integer);
begin
  SetTop(FTop + ADelta);
end;

procedure TAtlasPeekView.PageDown;
begin
  ScrollBy(Max(1, FPageRows - 1));
end;

procedure TAtlasPeekView.PageUp;
begin
  ScrollBy(-Max(1, FPageRows - 1));
end;

function TAtlasPeekView.OpenPlace: TAtlasPeekPlace;
var
  mRows: TArray<TAtlasPeekRow>;
  mIndex: Integer;
begin
  Result := Default(TAtlasPeekPlace);
  if Count = 0 then
  begin
    Exit;
  end;
  Result := Current.Target.Place;
  mRows := Current.Rows;
  // Zeigt der Ausschnitt die Zielzeile nicht mehr, öffnet Enter die oberste sichtbare Zeile.
  for mIndex := FTop to Min(High(mRows), FTop + FPageRows - 1) do
  begin
    if mRows[mIndex].Target then
    begin
      Exit;
    end;
  end;
  for mIndex := FTop to High(mRows) do
  begin
    if mRows[mIndex].Kind = TAtlasPeekRowKind.Code then
    begin
      Result := TAtlasPeekPlace.Create(mRows[mIndex].FileName, mRows[mIndex].Line, 0);
      Exit;
    end;
  end;
end;

end.
