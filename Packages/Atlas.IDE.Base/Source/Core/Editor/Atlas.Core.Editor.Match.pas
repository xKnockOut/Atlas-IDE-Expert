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

  /// <summary>Suche der Gruppe zum Token am Cursor (Blöcke und Klammern).</summary>
  TPairSearch = record
  private
    FLines: TArray<string>;
    FTokens: TArray<TAtlasPairToken>;
    FIsWord: Boolean;
    FWord: string;
    FHit: Integer;
    function Relevant(AIndex: Integer): Boolean;
    function RoleAt(AIndex: Integer): TRole;
    /// <summary>Gleiche Art, Tiefe ADepth und gepaart?</summary>
    function Peer(AIndex, ADepth: Integer): Boolean;
    function UnpairedAs(AIndex: Integer; ARole: TRole): Boolean;
    /// <summary>Gehört AIndex zur Gruppe AFirst..ALast (Öffner, Mittelteil, Schließer)?</summary>
    function InGroup(AIndex, AFirst, ALast: Integer): Boolean;
    function FindHit(ALine, ACharacter: Integer): Integer;
    function FindFirst: Integer;
    function FindLast(AFirst: Integer): Integer;
    function Ambiguous(AFirst, ALast: Integer): Boolean;
    procedure Collect(AFirst, ALast: Integer; var AMatch: TAtlasMatch);
  public
    function Run(const AText: string; ALine, ACharacter: Integer; var AMatch: TAtlasMatch): Boolean;
  end;

  /// <summary>Liest bedingte Direktiven außerhalb von Strings und Zeilenkommentaren.</summary>
  TDirectiveScanner = record
  private
    FText: string;
    FIndex: Integer;
    FLine: Integer;
    FLineStart: Integer;
    FResult: TArray<TDirective>;
    function CharAt(AIndex: Integer): Char;
    procedure NewLine;
    procedure SkipString;
    procedure SkipLineComment;
    /// <summary>Letztes Zeichen des Kommentars ab AStart ("}" bzw. ")").</summary>
    function CommentStop(AStart: Integer): Integer;
    procedure AddDirective(AStart, AStop: Integer);
    procedure LexComment;
    procedure Step;
  public
    function Run(const AText: string): TArray<TDirective>;
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
  begin
    Result := LowerCase(Copy(ALines[AToken.Line], AToken.Character + 1, AToken.Length));
  end;
end;

function RoleOfWord(const AWord: string): TRole;
begin
  if (AWord = 'end') or (AWord = 'until') then
  begin
    Result := TRole.Closer;
  end
  else if (AWord = 'finally') or (AWord = 'except') then
  begin
    Result := TRole.Middle;
  end
  else
  begin
    Result := TRole.Opener;
  end;
end;

function RoleOfBracket(const AText: string): TRole;
begin
  if (AText = '(') or (AText = '[') then
  begin
    Result := TRole.Opener;
  end
  else
  begin
    Result := TRole.Closer;
  end;
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

{ TPairSearch }

function TPairSearch.Relevant(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].IsWord = FIsWord) and not FTokens[AIndex].Owner;
  if Result and not FIsWord then
  begin
    Result := SameBracket(TextOf(FLines, FTokens[AIndex]), FWord);
  end;
end;

function TPairSearch.RoleAt(AIndex: Integer): TRole;
begin
  if FIsWord then
  begin
    Result := RoleOfWord(TextOf(FLines, FTokens[AIndex]));
  end
  else
  begin
    Result := RoleOfBracket(TextOf(FLines, FTokens[AIndex]));
  end;
end;

function TPairSearch.Peer(AIndex, ADepth: Integer): Boolean;
begin
  Result := Relevant(AIndex) and (FTokens[AIndex].Depth = ADepth) and not FTokens[AIndex].Unpaired;
end;

function TPairSearch.UnpairedAs(AIndex: Integer; ARole: TRole): Boolean;
begin
  Result := Relevant(AIndex) and FTokens[AIndex].Unpaired and (RoleAt(AIndex) = ARole);
end;

function TPairSearch.InGroup(AIndex, AFirst, ALast: Integer): Boolean;
begin
  Result := (AIndex = AFirst) or (AIndex = ALast) or (Relevant(AIndex) and
    (FTokens[AIndex].Depth = FTokens[AFirst].Depth) and (RoleAt(AIndex) = TRole.Middle));
end;

function TPairSearch.FindHit(ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
  mDone: Boolean;
begin
  // Token am Cursor: beginnt dort, sonst enthält es den Cursor oder endet davor.
  Result := -1;
  mIndex := 0;
  mDone := False;
  while not mDone and (mIndex <= High(FTokens)) do
  begin
    if not FTokens[mIndex].Owner and Touches(SpotOf(FTokens[mIndex]), ALine, ACharacter) then
    begin
      Result := mIndex;
      mDone := FTokens[mIndex].Character = ACharacter;
    end;
    Inc(mIndex);
  end;
end;

function TPairSearch.FindFirst: Integer;
var
  mIndex: Integer;
  mDone: Boolean;
begin
  // Öffner rückwärts auf derselben Tiefe; Mittelteile (finally/except) überspringen.
  Result := FHit;
  if RoleAt(FHit) <> TRole.Opener then
  begin
    Result := -1;
    mIndex := FHit - 1;
    mDone := False;
    while not mDone and (mIndex >= 0) do
    begin
      if Peer(mIndex, FTokens[FHit].Depth) then
      begin
        if RoleAt(mIndex) = TRole.Opener then
        begin
          Result := mIndex;
        end;
        mDone := RoleAt(mIndex) <> TRole.Middle;
      end;
      Dec(mIndex);
    end;
  end;
end;

function TPairSearch.FindLast(AFirst: Integer): Integer;
var
  mIndex: Integer;
  mRole: TRole;
  mDone: Boolean;
begin
  Result := -1;
  mIndex := AFirst + 1;
  mDone := False;
  while not mDone and (mIndex <= High(FTokens)) do
  begin
    if Peer(mIndex, FTokens[AFirst].Depth) then
    begin
      mRole := RoleAt(mIndex);
      if mRole = TRole.Closer then
      begin
        Result := mIndex;
      end;
      mDone := mRole in [TRole.Opener, TRole.Closer];
    end;
    Inc(mIndex);
  end;
end;

function TPairSearch.Ambiguous(AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  // Mehrdeutig: unpaariger Öffner davor bzw. unpaariger Schließer dahinter.
  Result := False;
  for mIndex := 0 to AFirst - 1 do
  begin
    Result := Result or UnpairedAs(mIndex, TRole.Opener);
  end;
  for mIndex := ALast + 1 to High(FTokens) do
  begin
    Result := Result or UnpairedAs(mIndex, TRole.Closer);
  end;
end;

procedure TPairSearch.Collect(AFirst, ALast: Integer; var AMatch: TAtlasMatch);
var
  mIndex: Integer;
begin
  AMatch.Kind := TAtlasMatchKind.Bracket;
  if FIsWord then
  begin
    AMatch.Kind := TAtlasMatchKind.Block;
  end;
  AMatch.Current := -1;
  for mIndex := AFirst to ALast do
  begin
    if InGroup(mIndex, AFirst, ALast) then
    begin
      if mIndex = FHit then
      begin
        AMatch.Current := Length(AMatch.Spots);
      end;
      AMatch.Spots := AMatch.Spots + [SpotOf(FTokens[mIndex])];
    end;
  end;
end;

function TPairSearch.Run(const AText: string; ALine, ACharacter: Integer; var AMatch: TAtlasMatch): Boolean;
var
  mFirst, mLast: Integer;
begin
  Result := False;
  FLines := TTextLines.SplitLines(AText);
  FTokens := TAtlasPairs.Analyze(AText);
  FHit := FindHit(ALine, ACharacter);
  if (FHit >= 0) and not FTokens[FHit].Unpaired then
  begin
    FIsWord := FTokens[FHit].IsWord;
    FWord := TextOf(FLines, FTokens[FHit]);
    mFirst := FindFirst;
    mLast := -1;
    if mFirst >= 0 then
    begin
      mLast := FindLast(mFirst);
    end;
    if (mLast >= 0) and not Ambiguous(mFirst, mLast) then
    begin
      Collect(mFirst, mLast, AMatch);
      Result := (AMatch.Current >= 0) and (Length(AMatch.Spots) >= 2);
    end;
  end;
end;

/// <summary>Blöcke und Klammern: Gruppe zum Token am Cursor.</summary>
function FindPair(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  mSearch: TPairSearch;
begin
  AMatch := Default(TAtlasMatch);
  mSearch := Default(TPairSearch);
  Result := mSearch.Run(AText, ALine, ACharacter, AMatch);
end;

function IsOneOf(const AText: string; const AList: array of string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    Result := Result or (AText = mItem);
  end;
end;

function RoleOfDirective(const AName: string): TRole;
begin
  Result := TRole.Other;
  if IsOneOf(AName, ['IFDEF', 'IFNDEF', 'IF', 'IFOPT']) then
  begin
    Result := TRole.Opener;
  end
  else if IsOneOf(AName, ['ELSE', 'ELSEIF']) then
  begin
    Result := TRole.Middle;
  end
  else if IsOneOf(AName, ['ENDIF', 'IFEND']) then
  begin
    Result := TRole.Closer;
  end;
end;

{ TDirectiveScanner }

function TDirectiveScanner.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(FText)) then
  begin
    Result := FText[AIndex];
  end;
end;

procedure TDirectiveScanner.NewLine;
begin
  Inc(FLine);
  FLineStart := FIndex + 1;
end;

procedure TDirectiveScanner.SkipString;
begin
  // Bis zum schließenden Hochkomma; am Zeilenende stehen bleiben, damit die Zeile zählt.
  Inc(FIndex);
  while not CharInSet(CharAt(FIndex), ['''', #10, #0]) do
  begin
    Inc(FIndex);
  end;
  if CharAt(FIndex) <> #10 then
  begin
    Inc(FIndex);
  end;
end;

procedure TDirectiveScanner.SkipLineComment;
begin
  while (FIndex < Length(FText)) and (FText[FIndex + 1] <> #10) do
  begin
    Inc(FIndex);
  end;
  Inc(FIndex);
end;

function TDirectiveScanner.CommentStop(AStart: Integer): Integer;
begin
  if FText[AStart] = '{' then
  begin
    Result := Pos('}', FText, AStart + 1);
    if Result = 0 then
    begin
      Result := Length(FText);
    end;
  end
  else
  begin
    Result := Pos('*)', FText, AStart + 2);
    if Result = 0 then
    begin
      Result := Length(FText);
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

procedure TDirectiveScanner.AddDirective(AStart, AStop: Integer);
var
  mNameEnd: Integer;
  mName: string;
  mDirective: TDirective;
begin
  // Direktive: {$ bzw. (*$ ; der Name endet am ersten Nicht-Buchstaben.
  mNameEnd := AStart + 1;
  if FText[AStart] = '(' then
  begin
    Inc(mNameEnd);
  end;
  if CharAt(mNameEnd) = '$' then
  begin
    Inc(mNameEnd);
    mName := '';
    while (mNameEnd <= AStop) and CharInSet(CharAt(mNameEnd), ['A'..'Z', 'a'..'z']) do
    begin
      mName := mName + UpCase(FText[mNameEnd]);
      Inc(mNameEnd);
    end;
    mDirective.Role := RoleOfDirective(mName);
    if (mDirective.Role <> TRole.Other) and (Pos(#10, Copy(FText, AStart, AStop - AStart + 1)) = 0) then
    begin
      mDirective.Spot := TAtlasMatchSpot.Create(FLine, AStart - FLineStart, AStop - AStart + 1);
      mDirective.Group := -1;
      FResult := FResult + [mDirective];
    end;
  end;
end;

procedure TDirectiveScanner.LexComment;
var
  mStop: Integer;
begin
  mStop := CommentStop(FIndex);
  AddDirective(FIndex, mStop);
  // Zeilen im Kommentar mitzählen.
  while FIndex < mStop do
  begin
    if FText[FIndex] = #10 then
    begin
      NewLine;
    end;
    Inc(FIndex);
  end;
  Inc(FIndex);
end;

procedure TDirectiveScanner.Step;
begin
  case FText[FIndex] of
    #10:
      begin
        NewLine;
        Inc(FIndex);
      end;
    '''':
      SkipString;
    '/':
      if CharAt(FIndex + 1) = '/' then
      begin
        SkipLineComment;
      end
      else
      begin
        Inc(FIndex);
      end;
    '{':
      LexComment;
    '(':
      if CharAt(FIndex + 1) = '*' then
      begin
        LexComment;
      end
      else
      begin
        Inc(FIndex);
      end;
  else
    Inc(FIndex);
  end;
end;

function TDirectiveScanner.Run(const AText: string): TArray<TDirective>;
begin
  FText := AText;
  FIndex := 1;
  FLine := 0;
  FLineStart := 1;
  FResult := nil;
  while FIndex <= Length(FText) do
  begin
    Step;
  end;
  Result := FResult;
end;

/// <summary>Bedingte Direktiven in AText (außerhalb von Strings und Kommentaren), mit Rolle.</summary>
function Directives(const AText: string): TArray<TDirective>;
var
  mScanner: TDirectiveScanner;
begin
  mScanner := Default(TDirectiveScanner);
  Result := mScanner.Run(AText);
end;

/// <summary>Index der Direktive am Cursor; -1 ohne.</summary>
function DirectiveAt(const AList: TArray<TDirective>; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(AList)) do
  begin
    if Touches(AList[mIndex].Spot, ALine, ACharacter) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Gruppen bilden; ein ELSE oder ENDIF ohne IF bleibt ohne Gruppe. Ergebnis: offen gebliebene IFs.
/// </summary>
function AssignGroups(var AList: TArray<TDirective>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].Role = TRole.Opener then
    begin
      AList[mIndex].Group := mIndex;
      Result := Result + [mIndex];
    end
    else if Length(Result) > 0 then
    begin
      AList[mIndex].Group := Result[High(Result)];
      if AList[mIndex].Role = TRole.Closer then
      begin
        SetLength(Result, Length(Result) - 1);
      end;
    end;
  end;
end;

/// <summary>Offen gebliebene IFs (die eigene Gruppe unvollständig, eine davor umschließt sie) oder ein Schließer
/// ohne IF dahinter machen die Gruppe mehrdeutig.</summary>
function GroupAmbiguous(const AList: TArray<TDirective>; const AOpen: TArray<Integer>; AGroup: Integer): Boolean;
var
  mIndex, mOpened: Integer;
begin
  Result := False;
  for mOpened in AOpen do
  begin
    Result := Result or (mOpened <= AGroup);
  end;
  for mIndex := AGroup + 1 to High(AList) do
  begin
    Result := Result or ((AList[mIndex].Group < 0) and (AList[mIndex].Role = TRole.Closer));
  end;
end;

procedure CollectGroup(const AList: TArray<TDirective>; AGroup, AHit: Integer; var AMatch: TAtlasMatch);
var
  mIndex: Integer;
begin
  AMatch.Kind := TAtlasMatchKind.Directive;
  AMatch.Current := -1;
  for mIndex := AGroup to High(AList) do
  begin
    if AList[mIndex].Group = AGroup then
    begin
      if mIndex = AHit then
      begin
        AMatch.Current := Length(AMatch.Spots);
      end;
      AMatch.Spots := AMatch.Spots + [AList[mIndex].Spot];
    end;
  end;
end;

function FindDirective(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  mList: TArray<TDirective>;
  mOpen: TArray<Integer>;
  mHit, mGroup: Integer;
begin
  Result := False;
  AMatch := Default(TAtlasMatch);
  mList := Directives(AText);
  mHit := DirectiveAt(mList, ALine, ACharacter);
  if mHit >= 0 then
  begin
    mOpen := AssignGroups(mList);
    mGroup := mList[mHit].Group;
    if (mGroup >= 0) and not GroupAmbiguous(mList, mOpen, mGroup) then
    begin
      CollectGroup(mList, mGroup, mHit, AMatch);
      Result := (AMatch.Current >= 0) and (Length(AMatch.Spots) >= 2);
    end;
  end;
end;

function FindMethod(const AText: string; ALine, ACharacter: Integer; out AMatch: TAtlasMatch): Boolean;
var
  mPlaces: TArray<TAtlasMethodPlace>;
  mSource, mTarget: TAtlasMethodPlace;
  mName: string;
  mSpot, mOther: TAtlasMatchSpot;
begin
  Result := False;
  AMatch := Default(TAtlasMatch);
  mPlaces := TAtlasMethodToggle.Places(AText);
  if not TAtlasMethodToggle.PlaceAt(mPlaces, ALine, ACharacter, mSource) then
  begin
    Exit;
  end;
  // Nur auf dem Namen (letzter Teil von TFoo.Bar).
  mName := Copy(mSource.Name, LastDelimiter('.', mSource.Name) + 1, MaxInt);
  mSpot := TAtlasMatchSpot.Create(mSource.Line, mSource.Character, Length(mName));
  if not Touches(mSpot, ALine, ACharacter) then
  begin
    Exit;
  end;
  if not TAtlasMethodToggle.Match(mPlaces, mSource, mTarget) then
  begin
    Exit;
  end;
  mOther := TAtlasMatchSpot.Create(mTarget.Line, mTarget.Character, Length(mName));
  AMatch.Kind := TAtlasMatchKind.Method;
  if Before(mSpot.Line, mSpot.Character, mOther) then
  begin
    AMatch.Spots := [mSpot, mOther];
    AMatch.Current := 0;
  end
  else
  begin
    AMatch.Spots := [mOther, mSpot];
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
  begin
    AMatch := Default(TAtlasMatch);
  end;
end;

class function TAtlasJumpToMatch.Target(const AText: string; ALine, ACharacter: Integer;
  out ATarget: TAtlasMatchSpot): Boolean;
var
  mMatch: TAtlasMatch;
begin
  ATarget := Default(TAtlasMatchSpot);
  Result := Find(AText, ALine, ACharacter, mMatch);
  if Result then
  begin
    ATarget := mMatch.Next;
  end;
end;

class function TAtlasJumpToMatch.Selection(const AText: string; ALine, ACharacter: Integer; out AStart,
  AEnd: TAtlasMatchSpot): Boolean;
var
  mTarget_: TAtlasMatchSpot;
begin
  AStart := TAtlasMatchSpot.Create(ALine, ACharacter, 0);
  AEnd := AStart;
  Result := Target(AText, ALine, ACharacter, mTarget_);
  if not Result then
  begin
    Exit;
  end;
  if Before(ALine, ACharacter, mTarget_) then
  begin
    AEnd := TAtlasMatchSpot.Create(mTarget_.Line, mTarget_.Character + mTarget_.Length, 0);
  end
  else
  begin
    AStart := TAtlasMatchSpot.Create(mTarget_.Line, mTarget_.Character, 0);
  end;
end;

end.
