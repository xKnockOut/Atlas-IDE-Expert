unit Atlas.Core.Editor.Match;

// Sprung zum Gegenstück (#635), ohne Open Tools API und ohne Server. Find
// liefert zur Stelle am Cursor alle zusammengehörenden Stellen in
// Textreihenfolge; Next ist die reihum folgende:
// - Blöcke aus TAtlasPairs (#514): begin ⇄ end, case ⇄ end, record/class/
//   object/interface ⇄ end, asm ⇄ end, repeat ⇄ until,
//   try → finally/except → end → try. Besitzer (if, then, procedure …) zählen
//   nicht. Strings und Kommentare überspringt der Lexer von TAtlasPairs.
// - Klammern ( ) und [ ].
// - Bedingte Direktiven {$IFDEF}/{$IFNDEF}/{$IF}/{$IFOPT} → {$ELSE}/
//   {$ELSEIF} → {$ENDIF}/{$IFEND}, auch über inaktive Zweige (es zählt nur
//   der Text, nicht die Auswertung).
// - Methodenname in Deklaration ⇄ Implementierung (TAtlasMethodToggle, #775),
//   nur wenn der Cursor auf dem Namen steht.
// Fehlertoleranz: Ein unpaariger Öffner davor (er umschließt das Paar) oder
// ein unpaariger Schließer dahinter derselben Art macht das Paar mehrdeutig;
// dann gibt es keinen Sprung, ebenso für Teile ohne Gegenstück.
// Der Cursor gehört zu einem Wort, wenn er darin oder direkt dahinter steht.
// Zeilen und Zeichen sind 0-basiert, #13 zählt nicht.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasMatchKind = (None, Block, Bracket, Directive, Method);
{$SCOPEDENUMS OFF}

  TAtlasMatchSpot = record
    Line: Integer;
    Character: Integer;
    Length: Integer;
    class function Create(ALine, ACharacter, ALength: Integer): TAtlasMatchSpot; static;
  end;

  TAtlasMatch = record
    Kind: TAtlasMatchKind;
    /// <summary>Zusammengehörende Stellen in Textreihenfolge.</summary>
    Spots: TArray<TAtlasMatchSpot>;
    /// <summary>Index der Stelle am Cursor in Spots.</summary>
    Current: Integer;
    /// <summary>Reihum folgende Stelle (nach der letzten die erste).</summary>
    function Next: TAtlasMatchSpot;
  end;

  TAtlasJumpToMatch = class
  public
    /// <summary>Zusammengehörende Stellen zur Stelle am Cursor; False ohne eindeutiges Gegenstück.</summary>
    class function Find(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
      static;
    /// <summary>Sprungziel: Anfang der reihum folgenden Stelle.</summary>
    class function Target(const AText: string; ALine, ACharacter: Integer; out ATarget: TAtlasMatchSpot): Boolean;
      static;
    /// <summary>Markierung vom Cursor bis zum Gegenstück einschließlich: vorwärts bis zu dessen Ende, rückwärts
    /// von dessen Anfang bis zum Cursor. AStart liegt vor AEnd.</summary>
    class function Selection(const AText: string; ALine, ACharacter: Integer; out AStart,
      AEnd: TAtlasMatchSpot): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.MethodToggle;

type
{$SCOPEDENUMS ON}
  TRole = (Other, Opener, Middle, Closer);
{$SCOPEDENUMS OFF}

  TDirective = record
    Spot: TAtlasMatchSpot;
    Role: TRole;
    /// <summary>Gruppe (Index des öffnenden IF); -1 ohne.</summary>
    Group: Integer;
  end;

class function TAtlasMatchSpot.Create(ALine, ACharacter, ALength: Integer): TAtlasMatchSpot;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Length := ALength;
end;

function TAtlasMatch.Next: TAtlasMatchSpot;
begin
  Result := Spots[(Current + 1) mod Length(Spots)];
end;

function Before(ALine, ACharacter: Integer; const ASpot: TAtlasMatchSpot): Boolean;
begin
  Result := (ALine < ASpot.Line) or ((ALine = ASpot.Line) and (ACharacter < ASpot.Character));
end;

/// <summary>Steht der Cursor auf der Stelle oder direkt dahinter?</summary>
function Touches(const ASpot: TAtlasMatchSpot; ALine, ACharacter: Integer): Boolean;
begin
  Result := (ASpot.Line = ALine) and (ACharacter >= ASpot.Character) and
    (ACharacter <= ASpot.Character + ASpot.Length);
end;

function TextOf(const ALines: TArray<string>; const AToken: TAtlasPairToken): string;
begin
  Result := '';
  if (AToken.Line >= 0) and (AToken.Line <= High(ALines)) then
    Result := LowerCase(Copy(ALines[AToken.Line], AToken.Character + 1, AToken.Length));
end;

function RoleOfWord(const AWord: string): TRole;
begin
  if (AWord = 'end') or (AWord = 'until') then
    Result := TRole.Closer
  else if (AWord = 'finally') or (AWord = 'except') then
    Result := TRole.Middle
  else
    Result := TRole.Opener;
end;

function RoleOfBracket(const AText: string): TRole;
begin
  if (AText = '(') or (AText = '[') then
    Result := TRole.Opener
  else
    Result := TRole.Closer;
end;

/// <summary>Gleiche Klammerart: ( mit ), [ mit ].</summary>
function SameBracket(const A, B: string): Boolean;
begin
  Result := ((A = '(') or (A = ')')) = ((B = '(') or (B = ')'));
end;

function SpotOf(const AToken: TAtlasPairToken): TAtlasMatchSpot;
begin
  Result := TAtlasMatchSpot.Create(AToken.Line, AToken.Character, AToken.Length);
end;

/// <summary>Blöcke und Klammern: Gruppe zum Token am Cursor.</summary>
function FindPair(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  Lines: TArray<string>;
  Tokens: TArray<TAtlasPairToken>;
  Index, Hit, First, Last, Step: Integer;
  Word: string;
  IsWord: Boolean;
  Role: TRole;

  function Relevant(AIndex: Integer): Boolean;
  begin
    Result := (Tokens[AIndex].IsWord = IsWord) and not Tokens[AIndex].Owner;
    if Result and not IsWord then
      Result := SameBracket(TextOf(Lines, Tokens[AIndex]), Word);
  end;

  function RoleAt(AIndex: Integer): TRole;
  begin
    if IsWord then
      Result := RoleOfWord(TextOf(Lines, Tokens[AIndex]))
    else
      Result := RoleOfBracket(TextOf(Lines, Tokens[AIndex]));
  end;

begin
  Result := False;
  AMatch := Default(TAtlasMatch);
  Lines := TTextLines.SplitLines(AText);
  Tokens := TAtlasPairs.Analyze(AText);
  // Token am Cursor: beginnt dort, sonst enthält es den Cursor oder endet davor.
  Hit := -1;
  for Index := 0 to High(Tokens) do
    if not Tokens[Index].Owner and Touches(SpotOf(Tokens[Index]), ALine, ACharacter) then
    begin
      Hit := Index;
      if Tokens[Index].Character = ACharacter then
        Break;
    end;
  if (Hit < 0) or Tokens[Hit].Unpaired then
    Exit;
  IsWord := Tokens[Hit].IsWord;
  Word := TextOf(Lines, Tokens[Hit]);
  Role := RoleAt(Hit);
  // Öffner suchen (rückwärts dieselbe Tiefe), dann den Schließer (vorwärts).
  First := Hit;
  if Role <> TRole.Opener then
  begin
    First := -1;
    for Index := Hit - 1 downto 0 do
      if Relevant(Index) and (Tokens[Index].Depth = Tokens[Hit].Depth) and not Tokens[Index].Unpaired then
      begin
        if RoleAt(Index) = TRole.Opener then
          First := Index;
        if RoleAt(Index) <> TRole.Middle then
          Break;
      end;
    if First < 0 then
      Exit;
  end;
  Last := -1;
  for Index := First + 1 to High(Tokens) do
    if Relevant(Index) and (Tokens[Index].Depth = Tokens[First].Depth) and not Tokens[Index].Unpaired then
    begin
      if RoleAt(Index) = TRole.Closer then
      begin
        Last := Index;
        Break;
      end;
      if RoleAt(Index) = TRole.Opener then
        Break;
    end;
  if Last < 0 then
    Exit;
  // Mehrdeutig: unpaariger Öffner davor bzw. unpaariger Schließer dahinter.
  for Index := 0 to First - 1 do
    if Relevant(Index) and Tokens[Index].Unpaired and (RoleAt(Index) = TRole.Opener) then
      Exit;
  for Index := Last + 1 to High(Tokens) do
    if Relevant(Index) and Tokens[Index].Unpaired and (RoleAt(Index) = TRole.Closer) then
      Exit;
  if IsWord then
    AMatch.Kind := TAtlasMatchKind.Block
  else
    AMatch.Kind := TAtlasMatchKind.Bracket;
  AMatch.Current := -1;
  Step := First;
  while Step <= Last do
  begin
    if (Step = First) or (Step = Last) or (Relevant(Step) and (Tokens[Step].Depth = Tokens[First].Depth) and
      (RoleAt(Step) = TRole.Middle)) then
    begin
      if Step = Hit then
        AMatch.Current := Length(AMatch.Spots);
      AMatch.Spots := AMatch.Spots + [SpotOf(Tokens[Step])];
    end;
    Inc(Step);
  end;
  Result := (AMatch.Current >= 0) and (Length(AMatch.Spots) >= 2);
end;

/// <summary>Bedingte Direktiven in AText (außerhalb von Strings und Kommentaren), mit Rolle.</summary>
function Directives(const AText: string): TArray<TDirective>;
var
  Index, Line, LineStart, Start, Stop, NameEnd: Integer;
  Name: string;
  Directive: TDirective;
begin
  Result := nil;
  Index := 1;
  Line := 0;
  LineStart := 1;
  while Index <= Length(AText) do
  begin
    case AText[Index] of
      #10:
        begin
          Inc(Line);
          LineStart := Index + 1;
        end;
      '''':
        begin
          Inc(Index);
          while (Index <= Length(AText)) and (AText[Index] <> '''') and (AText[Index] <> #10) do
            Inc(Index);
          if (Index <= Length(AText)) and (AText[Index] = #10) then
            Continue;
        end;
      '/':
        if (Index < Length(AText)) and (AText[Index + 1] = '/') then
          while (Index < Length(AText)) and (AText[Index + 1] <> #10) do
            Inc(Index);
      '{', '(':
        if (AText[Index] = '{') or ((Index < Length(AText)) and (AText[Index + 1] = '*')) then
        begin
          Start := Index;
          if AText[Index] = '{' then
          begin
            Stop := Pos('}', AText, Index + 1);
            if Stop = 0 then
              Stop := Length(AText);
          end
          else
          begin
            Stop := Pos('*)', AText, Index + 2);
            if Stop = 0 then
              Stop := Length(AText)
            else
              Inc(Stop);
          end;
          // Direktive: {$ bzw. (*$ ; der Name endet am ersten Nicht-Buchstaben.
          NameEnd := Start + 1;
          if AText[Start] = '(' then
            Inc(NameEnd);
          if (NameEnd <= Length(AText)) and (AText[NameEnd] = '$') then
          begin
            Inc(NameEnd);
            Name := '';
            while (NameEnd <= Stop) and CharInSet(AText[NameEnd], ['A'..'Z', 'a'..'z']) do
            begin
              Name := Name + UpCase(AText[NameEnd]);
              Inc(NameEnd);
            end;
            Directive.Role := TRole.Other;
            if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IF') or (Name = 'IFOPT') then
              Directive.Role := TRole.Opener
            else if (Name = 'ELSE') or (Name = 'ELSEIF') then
              Directive.Role := TRole.Middle
            else if (Name = 'ENDIF') or (Name = 'IFEND') then
              Directive.Role := TRole.Closer;
            if (Directive.Role <> TRole.Other) and (Pos(#10, Copy(AText, Start, Stop - Start + 1)) = 0) then
            begin
              Directive.Spot := TAtlasMatchSpot.Create(Line, Start - LineStart, Stop - Start + 1);
              Directive.Group := -1;
              Result := Result + [Directive];
            end;
          end;
          // Zeilen im Kommentar mitzählen.
          while Index < Stop do
          begin
            if AText[Index] = #10 then
            begin
              Inc(Line);
              LineStart := Index + 1;
            end;
            Inc(Index);
          end;
        end;
    end;
    Inc(Index);
  end;
end;

function FindDirective(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  List: TArray<TDirective>;
  Stack: TArray<Integer>;
  Index, Hit, Group, Opened: Integer;
begin
  Result := False;
  AMatch := Default(TAtlasMatch);
  List := Directives(AText);
  Hit := -1;
  for Index := 0 to High(List) do
    if (List[Index].Spot.Line = ALine) and (ACharacter >= List[Index].Spot.Character) and
      (ACharacter <= List[Index].Spot.Character + List[Index].Spot.Length) then
    begin
      Hit := Index;
      Break;
    end;
  if Hit < 0 then
    Exit;
  // Gruppen bilden; ein ELSE oder ENDIF ohne IF bleibt ohne Gruppe.
  Stack := nil;
  for Index := 0 to High(List) do
    case List[Index].Role of
      TRole.Opener:
        begin
          List[Index].Group := Index;
          Stack := Stack + [Index];
        end;
      TRole.Middle:
        if Length(Stack) > 0 then
          List[Index].Group := Stack[High(Stack)];
      TRole.Closer:
        if Length(Stack) > 0 then
        begin
          List[Index].Group := Stack[High(Stack)];
          SetLength(Stack, Length(Stack) - 1);
        end;
    end;
  Group := List[Hit].Group;
  if Group < 0 then
    Exit;
  // Offen gebliebene IFs: die eigene Gruppe unvollständig, eine davor umschließt sie (mehrdeutig).
  for Opened in Stack do
    if Opened <= Group then
      Exit;
  // Schließer ohne IF dahinter: mehrdeutig.
  for Index := Group + 1 to High(List) do
    if (List[Index].Group < 0) and (List[Index].Role = TRole.Closer) then
      Exit;
  AMatch.Kind := TAtlasMatchKind.Directive;
  AMatch.Current := -1;
  for Index := Group to High(List) do
    if List[Index].Group = Group then
    begin
      if Index = Hit then
        AMatch.Current := Length(AMatch.Spots);
      AMatch.Spots := AMatch.Spots + [List[Index].Spot];
    end;
  Result := (AMatch.Current >= 0) and (Length(AMatch.Spots) >= 2);
end;

function FindMethod(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  Places: TArray<TAtlasMethodPlace>;
  Source, Target: TAtlasMethodPlace;
  Name: string;
  Spot, Other: TAtlasMatchSpot;
begin
  Result := False;
  AMatch := Default(TAtlasMatch);
  Places := TAtlasMethodToggle.Places(AText);
  if not TAtlasMethodToggle.PlaceAt(Places, ALine, ACharacter, Source) then
    Exit;
  // Nur auf dem Namen (letzter Teil von TFoo.Bar).
  Name := Copy(Source.Name, LastDelimiter('.', Source.Name) + 1, MaxInt);
  Spot := TAtlasMatchSpot.Create(Source.Line, Source.Character, Length(Name));
  if not Touches(Spot, ALine, ACharacter) then
    Exit;
  if not TAtlasMethodToggle.Match(Places, Source, Target) then
    Exit;
  Other := TAtlasMatchSpot.Create(Target.Line, Target.Character, Length(Name));
  AMatch.Kind := TAtlasMatchKind.Method;
  if Before(Spot.Line, Spot.Character, Other) then
  begin
    AMatch.Spots := [Spot, Other];
    AMatch.Current := 0;
  end
  else
  begin
    AMatch.Spots := [Other, Spot];
    AMatch.Current := 1;
  end;
  Result := True;
end;

{ TAtlasJumpToMatch }

class function TAtlasJumpToMatch.Find(const AText: string; ALine, ACharacter: Integer;
  out AMatch: TAtlasMatch): Boolean;
begin
  Result := FindDirective(AText, ALine, ACharacter, AMatch) or FindPair(AText, ALine, ACharacter, AMatch) or
    FindMethod(AText, ALine, ACharacter, AMatch);
  if not Result then
    AMatch := Default(TAtlasMatch);
end;

class function TAtlasJumpToMatch.Target(const AText: string; ALine, ACharacter: Integer;
  out ATarget: TAtlasMatchSpot): Boolean;
var
  Match: TAtlasMatch;
begin
  ATarget := Default(TAtlasMatchSpot);
  Result := Find(AText, ALine, ACharacter, Match);
  if Result then
    ATarget := Match.Next;
end;

class function TAtlasJumpToMatch.Selection(const AText: string; ALine, ACharacter: Integer; out AStart,
  AEnd: TAtlasMatchSpot): Boolean;
var
  Target_: TAtlasMatchSpot;
begin
  AStart := TAtlasMatchSpot.Create(ALine, ACharacter, 0);
  AEnd := AStart;
  Result := Target(AText, ALine, ACharacter, Target_);
  if not Result then
    Exit;
  if Before(ALine, ACharacter, Target_) then
    AEnd := TAtlasMatchSpot.Create(Target_.Line, Target_.Character + Target_.Length, 0)
  else
    AStart := TAtlasMatchSpot.Create(Target_.Line, Target_.Character, 0);
end;

end.
