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
    MaxBlockLines = 400;
    /// <summary>Zeilen vor und nach einer Referenz.</summary>
    ReferenceBefore = 3;
    ReferenceAfter = 40;
    MaxExcerpt = 80;
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

function TPeekScanner.Next(out AToken: string; out ALine: Integer): Boolean;
var
  Text: string;
  Start: Integer;
begin
  AToken := '';
  ALine := FLine;
  while FLine <= FLastLine do
  begin
    Text := FLines[FLine];
    if FPos > Length(Text) then
    begin
      Inc(FLine);
      FPos := 1;
      Continue;
    end;
    if CharInSet(Text[FPos], [' ', #9]) then
    begin
      Inc(FPos);
      Continue;
    end;
    // Kommentare über mehrere Zeilen: {…} und (*…*).
    if Text[FPos] = '{' then
    begin
      Inc(FPos);
      while FLine <= FLastLine do
      begin
        Text := FLines[FLine];
        while (FPos <= Length(Text)) and (Text[FPos] <> '}') do
          Inc(FPos);
        if FPos <= Length(Text) then
          Break;
        Inc(FLine);
        FPos := 1;
      end;
      Inc(FPos);
      Continue;
    end;
    if (Text[FPos] = '(') and (FPos < Length(Text)) and (Text[FPos + 1] = '*') then
    begin
      Inc(FPos, 2);
      while FLine <= FLastLine do
      begin
        Text := FLines[FLine];
        while (FPos < Length(Text)) and not ((Text[FPos] = '*') and (Text[FPos + 1] = ')')) do
          Inc(FPos);
        if FPos < Length(Text) then
          Break;
        Inc(FLine);
        FPos := 1;
      end;
      Inc(FPos, 2);
      Continue;
    end;
    if (Text[FPos] = '/') and (FPos < Length(Text)) and (Text[FPos + 1] = '/') then
    begin
      FPos := Length(Text) + 1;
      Continue;
    end;
    if Text[FPos] = '''' then
    begin
      Inc(FPos);
      while (FPos <= Length(Text)) and (Text[FPos] <> '''') do
        Inc(FPos);
      Inc(FPos);
      Continue;
    end;
    ALine := FLine;
    if TTextChars.IsIdentStart(Text[FPos]) or (Text[FPos] = '&') then
    begin
      Start := FPos;
      Inc(FPos);
      while (FPos <= Length(Text)) and TTextChars.IsIdentChar(Text[FPos]) do
        Inc(FPos);
      AToken := LowerCase(Copy(Text, Start, FPos - Start));
    end
    else
    begin
      AToken := Text[FPos];
      Inc(FPos);
    end;
    Exit(True);
  end;
  Result := False;
end;

function TPeekScanner.Peek(out AToken: string): Boolean;
var
  Probe: TPeekScanner;
  Line: Integer;
begin
  Probe := Self;
  Result := Probe.Next(AToken, Line);
end;

const
  // Direktiven, die nach dem ";" einer Routinen-Deklaration folgen können.
  Directives: array[0..23] of string = ('overload', 'virtual', 'override', 'abstract', 'inline', 'stdcall',
    'cdecl', 'pascal', 'register', 'safecall', 'reintroduce', 'static', 'dynamic', 'deprecated', 'platform',
    'final', 'message', 'external', 'forward', 'assembler', 'experimental', 'dispid', 'library', 'varargs');

function IsDirective(const AToken: string): Boolean;
var
  Word: string;
begin
  for Word in Directives do
    if Word = AToken then
      Exit(True);
  Result := False;
end;

/// <summary>Ende eines Kopfs: erstes ";" außerhalb von Klammern samt folgender Direktiven. AHasBody wird
/// False bei external oder forward.</summary>
function HeaderEnd(var AScanner: TPeekScanner; AStart: Integer; out AHasBody: Boolean): Integer;
var
  Token, Following: string;
  Line, Depth: Integer;
begin
  Result := AStart;
  AHasBody := True;
  Depth := 0;
  while AScanner.Next(Token, Line) do
  begin
    Result := Line;
    if (Token = '(') or (Token = '[') then
      Inc(Depth)
    else if (Token = ')') or (Token = ']') then
      Dec(Depth)
    else if (Token = 'external') or (Token = 'forward') then
      AHasBody := False
    else if (Token = ';') and (Depth <= 0) then
    begin
      // Direktiven nach dem ";": "procedure A; overload; virtual;" oder in den Folgezeilen.
      if not AScanner.Peek(Following) or not IsDirective(Following) then
        Exit;
    end;
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
  Text: string;
begin
  Result := Max(0, Min(ALine, High(ALines)));
  while Result > 0 do
  begin
    Text := Trim(ALines[Result - 1]);
    if (Copy(Text, 1, 3) = '///') or ((Text <> '') and (Text[1] = '[') and (Text[Length(Text)] = ']')) then
      Dec(Result)
    else
      Break;
  end;
end;

class function TAtlasPeek.DeclarationEnd(const ALines: TArray<string>; ALine: Integer): Integer;
var
  Scanner: TPeekScanner;
  Token, Previous, Following: string;
  Line, Depth, Parens: Integer;
  HasBody: Boolean;
begin
  if (ALine < 0) or (ALine > High(ALines)) then
    Exit(ALine);
  Scanner.Init(ALines, ALine, ALine + MaxBlockLines - 1);
  Result := ALine;
  Previous := '';
  Parens := 0;
  // Bis zum "=" auf Ebene 0 bzw. zum ";" schauen, ob ein Typblock beginnt.
  while Scanner.Next(Token, Line) do
  begin
    Result := Line;
    if (Token = '(') or (Token = '[') then
      Inc(Parens)
    else if (Token = ')') or (Token = ']') then
      Dec(Parens)
    else if (Token = ';') and (Parens <= 0) then
    begin
      if not Scanner.Peek(Following) or not IsDirective(Following) then
        Exit;
      // Direktiven: wie ein Routinenkopf weiter.
      Exit(HeaderEnd(Scanner, Line, HasBody));
    end
    else if (Parens <= 0) and (Previous = '=') and ((Token = 'class') or (Token = 'record') or
      (Token = 'interface') or (Token = 'dispinterface') or (Token = 'object') or (Token = 'packed')) then
    begin
      if Token = 'packed' then
        if not Scanner.Next(Token, Line) then
          Exit;
      // "class of", "class;" und "class(TBase);" sind keine Blöcke.
      if not Scanner.Peek(Following) then
        Exit;
      if (Following = 'of') or (Following = ';') then
        Exit(HeaderEnd(Scanner, Line, HasBody));
      if Following = '(' then
      begin
        Depth := 0;
        while Scanner.Next(Token, Line) do
        begin
          Result := Line;
          if Token = '(' then
            Inc(Depth)
          else if Token = ')' then
          begin
            Dec(Depth);
            if Depth = 0 then
              Break;
          end;
        end;
        if Scanner.Peek(Following) and (Following = ';') then
          Exit(HeaderEnd(Scanner, Line, HasBody));
      end;
      // Block bis zum passenden end; darin zählen nur weitere record und "= class/interface".
      Depth := 1;
      Previous := '';
      while Scanner.Next(Token, Line) do
      begin
        Result := Line;
        if Token = 'end' then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            if Scanner.Peek(Following) and (Following = ';') then
              Scanner.Next(Token, Result);
            Exit;
          end;
        end
        else if Token = 'record' then
          Inc(Depth)
        else if (Previous = '=') and ((Token = 'class') or (Token = 'interface') or (Token = 'object')) then
        begin
          if Scanner.Peek(Following) and (Following <> 'of') and (Following <> ';') and (Following <> '(') then
            Inc(Depth)
          else if Following = '(' then
          begin
            // Verschachtelte Klasse mit Vorfahr: Block, außer "class(TBase);".
            Parens := 0;
            while Scanner.Next(Token, Line) do
            begin
              if Token = '(' then
                Inc(Parens)
              else if Token = ')' then
              begin
                Dec(Parens);
                if Parens = 0 then
                  Break;
              end;
            end;
            if Scanner.Peek(Following) and (Following <> ';') then
              Inc(Depth);
          end;
        end;
        Previous := Token;
      end;
      Exit;
    end;
    Previous := Token;
  end;
end;

class function TAtlasPeek.BodyEnd(const ALines: TArray<string>; ALine: Integer): Integer;
var
  Scanner: TPeekScanner;
  Token, Previous: string;
  Line, Depth, Pending: Integer;
  HasBody, Started: Boolean;
begin
  if (ALine < 0) or (ALine > High(ALines)) then
    Exit(ALine);
  Scanner.Init(ALines, ALine, ALine + MaxBlockLines - 1);
  Result := HeaderEnd(Scanner, ALine, HasBody);
  if not HasBody then
    Exit;
  Depth := 0;
  // Lokale Routinen vor dem Rumpf: Ihr end bringt die Tiefe auf 0, beendet aber nicht den Rumpf.
  Pending := 0;
  Started := False;
  Previous := '';
  while Scanner.Next(Token, Line) do
  begin
    Result := Line;
    if (Depth = 0) and not Started and ((Token = 'procedure') or (Token = 'function') or
      (Token = 'constructor') or (Token = 'destructor')) and (Previous <> '=') and (Previous <> 'to') and
      (Previous <> 'class') then
    begin
      // Lokale Routine: ihren Kopf überspringen; external/forward hat keinen eigenen Rumpf.
      HeaderEnd(Scanner, Line, HasBody);
      if HasBody then
        Inc(Pending);
      Previous := ';';
      Continue;
    end;
    if (Token = 'begin') or (Token = 'asm') or (Token = 'try') or (Token = 'case') or (Token = 'record') then
    begin
      if (Depth = 0) and ((Token = 'begin') or (Token = 'asm')) and (Pending = 0) then
        Started := True;
      Inc(Depth);
    end
    else if Token = 'end' then
    begin
      Dec(Depth);
      if Depth <= 0 then
      begin
        Depth := 0;
        if Started then
        begin
          if Scanner.Peek(Token) and (Token = ';') then
            Scanner.Next(Token, Result);
          Exit;
        end;
        if Pending > 0 then
          Dec(Pending);
      end;
    end;
    Previous := Token;
  end;
end;

const
  // SymbolKind des LSP: Method, Constructor, Function, Operator.
  RoutineKinds: array[0..3] of Integer = (6, 9, 12, 25);

function IsRoutine(AKind: Integer): Boolean;
var
  Kind: Integer;
begin
  for Kind in RoutineKinds do
    if Kind = AKind then
      Exit(True);
  Result := False;
end;

/// <summary>Name ohne Besitzer und Besitzer (klein); interface/implementation zählen als kein Besitzer.</summary>
procedure SplitName(const ASymbol: TAtlasSymbol; out AName, AOwner: string);
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', ASymbol.Name);
  if Dot > 0 then
  begin
    AName := Copy(ASymbol.Name, Dot + 1, MaxInt);
    AOwner := Copy(ASymbol.Name, 1, Dot - 1);
  end
  else
  begin
    AName := ASymbol.Name;
    AOwner := ASymbol.Container;
  end;
  AOwner := LowerCase(AOwner);
  if (AOwner = 'interface') or (AOwner = 'implementation') then
    AOwner := '';
end;

class function TAtlasPeek.Overloads(const ASymbols: TArray<TAtlasSymbol>; ALine: Integer): TArray<TAtlasPeekPlace>;
var
  Index, Found, Other: Integer;
  Name, Owner, OtherName, OtherOwner: string;
  Place: TAtlasPeekPlace;
begin
  Result := nil;
  Found := -1;
  for Index := 0 to High(ASymbols) do
    if (ASymbols[Index].Line = ALine) and IsRoutine(ASymbols[Index].Kind) then
    begin
      Found := Index;
      Break;
    end;
  if Found < 0 then
    Exit;
  SplitName(ASymbols[Found], Name, Owner);
  for Index := 0 to High(ASymbols) do
  begin
    if not IsRoutine(ASymbols[Index].Kind) then
      Continue;
    SplitName(ASymbols[Index], OtherName, OtherOwner);
    if not SameText(OtherName, Name) or (OtherOwner <> Owner) then
      Continue;
    Place := TAtlasPeekPlace.Create(ASymbols[Index].FileName, ASymbols[Index].Line, ASymbols[Index].Character);
    // Nach Zeile einsortieren, doppelte Zeilen nur einmal.
    Other := Length(Result);
    while (Other > 0) and (Result[Other - 1].Line > Place.Line) do
      Dec(Other);
    if (Other > 0) and (Result[Other - 1].Line = Place.Line) then
      Continue;
    Insert(Place, Result, Other);
  end;
end;

class function TAtlasPeek.Pair(const APlaces: TArray<TAtlasPeekPlace>; const AResolve: TAtlasPeekResolve):
  TArray<TAtlasPeekTarget>;
var
  Used: TArray<Boolean>;
  Index, Other, Count: Integer;
  Resolved: TAtlasPeekPlace;
  Target: TAtlasPeekTarget;
begin
  Result := nil;
  SetLength(Used, Length(APlaces));
  SetLength(Result, Length(APlaces));
  Count := 0;
  for Index := 0 to High(APlaces) do
  begin
    if Used[Index] then
      Continue;
    Used[Index] := True;
    Target.Place := APlaces[Index];
    Target.HasBody := False;
    Target.Body := Default(TAtlasPeekPlace);
    if Assigned(AResolve) and AResolve(APlaces[Index], Resolved) and not Resolved.SameLine(APlaces[Index]) then
    begin
      // In der Liste: nur eine noch freie Fundstelle (sonst führt eine Implementierung zurück zur Deklaration).
      Target.HasBody := True;
      Target.Body := Resolved;
      for Other := 0 to High(APlaces) do
        if APlaces[Other].SameLine(Resolved) then
        begin
          Target.HasBody := not Used[Other];
          if Target.HasBody then
          begin
            Used[Other] := True;
            Target.Body := APlaces[Other];
          end;
          Break;
        end;
    end;
    Result[Count] := Target;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

class function TAtlasPeek.ExpandTabs(const AText: string; ATabWidth: Integer): string;
var
  Builder: TStringBuilder;
  Ch: Char;
  Width: Integer;
begin
  if Pos(#9, AText) = 0 then
    Exit(AText);
  Width := Max(1, ATabWidth);
  Builder := TStringBuilder.Create;
  try
    for Ch in AText do
      if Ch = #9 then
        Builder.Append(' ', Width - Builder.Length mod Width)
      else
        Builder.Append(Ch);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasPeek.Excerpt(const ALine: string): string;
begin
  Result := Trim(StringReplace(ALine, #9, ' ', [rfReplaceAll]));
  if Length(Result) > MaxExcerpt then
    Result := Copy(Result, 1, MaxExcerpt - 1) + '…';
end;

function CodeRow(const AFileName: string; const ALines: TArray<string>; ALine, ATabWidth: Integer;
  const ATarget: TAtlasPeekPlace; AMarkTarget: Boolean): TAtlasPeekRow;
var
  Original: string;
  First, Last: Integer;
begin
  Original := ALines[ALine];
  Result.Kind := TAtlasPeekRowKind.Code;
  Result.Text := TAtlasPeek.ExpandTabs(Original, ATabWidth);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Target := AMarkTarget and (ALine = ATarget.Line);
  Result.NameStart := -1;
  Result.NameStop := -1;
  if not Result.Target then
    Exit;
  First := Max(0, Min(ATarget.Character, Length(Original)));
  Last := First;
  while (First > 0) and TTextChars.IsIdentChar(Original[First]) do
    Dec(First);
  while (Last < Length(Original)) and TTextChars.IsIdentChar(Original[Last + 1]) do
    Inc(Last);
  if Last > First then
  begin
    Result.NameStart := Length(TAtlasPeek.ExpandTabs(Copy(Original, 1, First), ATabWidth));
    Result.NameStop := Length(TAtlasPeek.ExpandTabs(Copy(Original, 1, Last), ATabWidth));
  end;
end;

class function TAtlasPeek.DefinitionRows(const ATarget: TAtlasPeekTarget; const ADeclLines,
  ABodyLines: TArray<string>; AShowBody: Boolean; ATabWidth: Integer): TArray<TAtlasPeekRow>;
var
  Line, First, Last, Count: Integer;
  Separator: TAtlasPeekRow;
begin
  Result := nil;
  Count := 0;
  if (ATarget.Place.Line >= 0) and (ATarget.Place.Line <= High(ADeclLines)) then
  begin
    First := DeclarationStart(ADeclLines, ATarget.Place.Line);
    Last := Min(DeclarationEnd(ADeclLines, ATarget.Place.Line), First + MaxBlockLines - 1);
    SetLength(Result, Last - First + 1);
    for Line := First to Last do
    begin
      Result[Count] := CodeRow(ATarget.Place.FileName, ADeclLines, Line, ATabWidth, ATarget.Place, True);
      Inc(Count);
    end;
  end;
  if AShowBody and ATarget.HasBody and (ATarget.Body.Line >= 0) and (ATarget.Body.Line <= High(ABodyLines)) then
  begin
    First := DeclarationStart(ABodyLines, ATarget.Body.Line);
    Last := Min(BodyEnd(ABodyLines, ATarget.Body.Line), First + MaxBlockLines - 1);
    Separator := Default(TAtlasPeekRow);
    Separator.Kind := TAtlasPeekRowKind.Separator;
    Separator.FileName := ATarget.Body.FileName;
    Separator.Line := ATarget.Body.Line;
    Separator.NameStart := -1;
    Separator.NameStop := -1;
    SetLength(Result, Count + 1 + Last - First + 1);
    Result[Count] := Separator;
    Inc(Count);
    for Line := First to Last do
    begin
      Result[Count] := CodeRow(ATarget.Body.FileName, ABodyLines, Line, ATabWidth, ATarget.Body, False);
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

class function TAtlasPeek.ReferenceRows(const APlace: TAtlasPeekPlace; const ALines: TArray<string>;
  ATabWidth: Integer): TArray<TAtlasPeekRow>;
var
  Line, First, Last: Integer;
begin
  Result := nil;
  if (APlace.Line < 0) or (APlace.Line > High(ALines)) then
    Exit;
  First := Max(0, APlace.Line - ReferenceBefore);
  Last := Min(High(ALines), APlace.Line + ReferenceAfter);
  SetLength(Result, Last - First + 1);
  for Line := First to Last do
    Result[Line - First] := CodeRow(APlace.FileName, ALines, Line, ATabWidth, APlace, True);
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
    Exit;
  FSelected := EnsureRange(AIndex, 0, Count - 1);
  FTop := 0;
end;

procedure TAtlasPeekView.SelectNext;
begin
  if FSelected < Count - 1 then
    Select(FSelected + 1);
end;

procedure TAtlasPeekView.SelectPrevious;
begin
  if FSelected > 0 then
    Select(FSelected - 1);
end;

function TAtlasPeekView.MaxTop: Integer;
begin
  Result := 0;
  if Count > 0 then
    Result := Max(0, Length(Current.Rows) - FPageRows);
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
  Rows: TArray<TAtlasPeekRow>;
  Index: Integer;
begin
  Result := Default(TAtlasPeekPlace);
  if Count = 0 then
    Exit;
  Result := Current.Target.Place;
  Rows := Current.Rows;
  // Zeigt der Ausschnitt die Zielzeile nicht mehr, öffnet Enter die oberste sichtbare Zeile.
  for Index := FTop to Min(High(Rows), FTop + FPageRows - 1) do
    if Rows[Index].Target then
      Exit;
  for Index := FTop to High(Rows) do
    if Rows[Index].Kind = TAtlasPeekRowKind.Code then
    begin
      Result := TAtlasPeekPlace.Create(Rows[Index].FileName, Rows[Index].Line, 0);
      Exit;
    end;
end;

end.
