unit Atlas.Core.Tracker.CodeLinks;

// Issue-Kennungen im Quelltext und in Commit-Nachrichten (#1265, #1275), ohne
// VCL, Open Tools API und Netz.
// - Muster aus dem Tracker des Projekts (TAtlasIssueKeyPattern.ForTarget;
//   .atlas, sonst Zuordnung #1261 mit Verbindung #1260): YouTrack
//   „<KÜRZEL>-<Zahl>“ mit dem Kürzel des Tracker-Projekts (mehrere durch Komma,
//   Groß-/Kleinschreibung egal), GitHub „#<Zahl>“ und „<owner>/<repo>#<Zahl>“.
//   Ohne Tracker (oder YouTrack ohne Kürzel) erkennt nichts etwas: Ein freies
//   Kürzel würde „UTF-8“ oder „ISO-9001“ treffen.
// - Wortgrenzen: vor und hinter der Kennung kein Buchstabe, keine Ziffer, kein
//   „_“ („XATL-1“ und „ATL-1a“ zählen nicht). GitHub zusätzlich nicht nach
//   „&“ (HTML-Entität „&#123;“) und nicht vor oder nach „#“/„$“, damit
//   Zeichenkonstanten wie „#13#10“ in Kommentaren keine Issues werden.
// - Im Quelltext nur in Kommentaren („//“, „{ }“, „(* *)“, damit auch in
//   TODO-Kommentaren) und in String-Literalen, die mit dem Commit-Präfix
//   (issues.commitPattern, #765, etwa „ATL-123 “) beginnen – das sind
//   Commit-Nachrichten im Code. Compiler-Direktiven („{$…}“, „(*$…*)“) und
//   Code zählen nicht.
// - Der Zustand am Zeilenanfang (in einem mehrzeiligen Kommentar oder nicht)
//   hängt von den Zeilen davor ab: States rechnet ihn für alle Zeilen in einem
//   Durchgang aus, LineMatches findet dann die Kennungen einer einzelnen
//   (sichtbaren) Zeile. So muss der Editor beim Zeichnen nur die sichtbaren
//   Zeilen ansehen.
// Dieselbe Erkennung nutzen die Zeilenhistorie (#1275, FindKeys über die
// Commit-Nachricht) und künftig die TODO-Liste (#897).

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand am Anfang einer Zeile: im Code oder in einem mehrzeiligen Kommentar bzw. einer
  /// mehrzeiligen Direktive.</summary>
  TAtlasCodeLinkState = (Code, BraceComment, ParenComment, BraceDirective, ParenDirective);
  /// <summary>Wo eine Kennung steht: Kommentar oder String-Literal.</summary>
  TAtlasCodeLinkPlace = (Comment, Literal);
{$SCOPEDENUMS OFF}

  /// <summary>Kommentar bzw. Literal einer Zeile: Zeichen ab 0, AStop ausschließlich; ohne Begrenzer.</summary>
  TAtlasCodeLinkRange = record
    Start: Integer;
    Stop: Integer;
    Place: TAtlasCodeLinkPlace;
  end;

  /// <summary>Wonach gesucht wird; aus dem Tracker des Projekts.</summary>
  TAtlasIssueKeyPattern = record
    /// <summary>"github" oder "youtrack"; '' = keine Erkennung.</summary>
    Provider: string;
    /// <summary>YouTrack: Kürzel der Projekte in Großbuchstaben.</summary>
    Projects: TArray<string>;
    /// <summary>GitHub: "owner/repo" des Projekts in Kleinbuchstaben.</summary>
    Repository: string;
    class function Empty: TAtlasIssueKeyPattern; static;
    /// <summary>Muster für ATarget; Empty, wenn ATarget nicht eingerichtet ist (ohne Anbieter, GitHub ohne
    /// owner/repo, YouTrack ohne Kürzel).</summary>
    class function ForTarget(const ATarget: TAtlasTrackerTarget): TAtlasIssueKeyPattern; static;
    function Active: Boolean;
    /// <summary>Für Vergleiche: Anbieter, Projekte und Repository.</summary>
    function Key: string;
  end;

  /// <summary>Gefundene Kennung.</summary>
  TAtlasIssueKeyMatch = record
    /// <summary>Erstes Zeichen ab 0 und Länge im durchsuchten Text.</summary>
    Character: Integer;
    Length: Integer;
    /// <summary>Wie gezeigt und kopiert: "ATL-123" (Kürzel wie im Muster), "#42", "owner/repo#42".</summary>
    Key: string;
    /// <summary>Nummer der Kennung.</summary>
    Number: Integer;
    /// <summary>GitHub "owner/repo" einer fremden Kennung ("owner/repo#42"); '' im eigenen Repository und bei
    /// YouTrack.</summary>
    Repository: string;
    Place: TAtlasCodeLinkPlace;
    /// <summary>Kennung im Tracker von IssueTarget: "ATL-123" bzw. "#42".</summary>
    function IssueKey: string;
    /// <summary>Tracker der Kennung: ATarget, für "owner/repo#42" dasselbe GitHub mit owner/repo als Projekt.
    /// </summary>
    function IssueTarget(const ATarget: TAtlasTrackerTarget): TAtlasTrackerTarget;
  end;

  /// <summary>Kennung einer Zeile im ganzen Text.</summary>
  TAtlasIssueKeyLineMatch = record
    /// <summary>Zeile ab 0.</summary>
    Line: Integer;
    Match: TAtlasIssueKeyMatch;
  end;

  TAtlasCodeLinks = class
  public const
    /// <summary>Höchstens so viele Ziffern hat eine Nummer.</summary>
    cMaxDigits = 9;
  public
    /// <summary>Alle Kennungen in AText (etwa einer Commit-Nachricht), Place Comment.</summary>
    class function FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string):
      TArray<TAtlasIssueKeyMatch>; overload; static;
    /// <summary>Kennungen, die ganz in AText[AStart, AStop) liegen (Zeichen ab 0); die Wortgrenzen gelten im
    /// ganzen Text.</summary>
    class function FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string; AStart, AStop: Integer;
      APlace: TAtlasCodeLinkPlace): TArray<TAtlasIssueKeyMatch>; overload; static;
    /// <summary>Kommentare und Literale von ALine; AState ist der Zustand am Zeilenanfang und danach der am
    /// Anfang der nächsten Zeile.</summary>
    class function Ranges(const ALine: string; var AState: TAtlasCodeLinkState): TArray<TAtlasCodeLinkRange>;
      static;
    /// <summary>Zustand am Anfang der Zeile nach ALine.</summary>
    class function NextState(const ALine: string; AState: TAtlasCodeLinkState): TAtlasCodeLinkState; static;
    /// <summary>Zustand am Anfang jeder Zeile (gleich lang wie ALines).</summary>
    class function States(const ALines: TArray<string>): TArray<TAtlasCodeLinkState>; static;
    /// <summary>Präfix der Commit-Nachricht für AMatch aus ACommitPattern ({kennung}, {nummer}; ab {kurztitel}
    /// abgeschnitten), ohne Leerraum am Ende; '' ohne Muster.</summary>
    class function CommitPrefix(const ACommitPattern: string; const AMatch: TAtlasIssueKeyMatch): string; static;
    /// <summary>Zählt eine Kennung in einem String-Literal mit dem Inhalt ALiteral? Nur, wenn das Literal mit
    /// dem Commit-Präfix dieser Kennung beginnt.</summary>
    class function LiteralAllowed(const ALiteral, ACommitPattern: string; const AMatch: TAtlasIssueKeyMatch):
      Boolean; static;
    /// <summary>Kennungen von ALine mit dem Zustand AState am Zeilenanfang (aus States).</summary>
    class function LineMatches(const APattern: TAtlasIssueKeyPattern; const ALine: string;
      AState: TAtlasCodeLinkState; const ACommitPattern: string): TArray<TAtlasIssueKeyMatch>; static;
    /// <summary>Alle Kennungen eines Textes in Zeilen (für Tests, Benchmark und Listen).</summary>
    class function Find(const APattern: TAtlasIssueKeyPattern; const ALines: TArray<string>;
      const ACommitPattern: string): TArray<TAtlasIssueKeyLineMatch>; static;
    /// <summary>Kennung unter dem Zeichen ACharacter (ab 0) von AMatches; -1 ohne.</summary>
    class function MatchAt(const AMatches: TArray<TAtlasIssueKeyMatch>; ACharacter: Integer): Integer; static;
    /// <summary>Kennungen ohne Doppelte (nach Key, ohne Groß-/Kleinschreibung), in der Reihenfolge des Auftretens.
    /// </summary>
    class function DistinctKeys(const AMatches: TArray<TAtlasIssueKeyMatch>): TArray<TAtlasIssueKeyMatch>; static;
  end;

implementation

uses
  System.Math;

function IsAsciiLetter(AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or ((AChar >= 'A') and (AChar <= 'Z'));
end;

function IsDigit(AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

/// <summary>Buchstabe, Ziffer oder „_“; Buchstaben außerhalb von ASCII grob über ihre Bereiche (ohne Satzzeichen
/// wie „„“, „“ “ oder „–“, die eine Kennung begrenzen dürfen).</summary>
function IsWordChar(AChar: Char): Boolean;
begin
  case AChar of
    'a'..'z', 'A'..'Z', '0'..'9', '_':
      Result := True;
    #$00C0..#$00D6, #$00D8..#$00F6, #$00F8..#$1FFF, #$2C00..#$2DFF, #$3040..#$D7FF, #$F900..#$FDFF,
    #$FE70..#$FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Zeichen eines GitHub-Repository-Namens.</summary>
function IsRepoChar(AChar: Char): Boolean;
begin
  Result := IsAsciiLetter(AChar) or IsDigit(AChar) or (AChar = '-') or (AChar = '_') or (AChar = '.');
end;

/// <summary>Zeichen eines GitHub-Benutzer- bzw. Organisationsnamens.</summary>
function IsOwnerChar(AChar: Char): Boolean;
begin
  Result := IsAsciiLetter(AChar) or IsDigit(AChar) or (AChar = '-');
end;

{ TAtlasIssueKeyPattern }

class function TAtlasIssueKeyPattern.Empty: TAtlasIssueKeyPattern;
begin
  Result.Provider := '';
  Result.Projects := nil;
  Result.Repository := '';
end;

/// <summary>Kürzel eines YouTrack-Projekts: Buchstabe, dann Buchstaben, Ziffern und "_".</summary>
function IsProjectName(const AProject: string): Boolean;
var
  mChar: Char;
begin
  Result := (AProject <> '') and IsAsciiLetter(AProject[1]);
  for mChar in AProject do
  begin
    if not (IsAsciiLetter(mChar) or IsDigit(mChar) or (mChar = '_')) then
    begin
      Result := False;
    end;
  end;
end;

/// <summary>Gültige Kürzel aus einer Liste mit Komma, Semikolon oder Leerzeichen, groß geschrieben.</summary>
function YouTrackProjects(const AProjects: string): TArray<string>;
var
  mPart, mProject: string;
begin
  Result := nil;
  for mPart in AProjects.Split([',', ';', ' ']) do
  begin
    mProject := UpperCase(Trim(mPart));
    if IsProjectName(mProject) then
    begin
      Result := Result + [mProject];
    end;
  end;
end;

class function TAtlasIssueKeyPattern.ForTarget(const ATarget: TAtlasTrackerTarget): TAtlasIssueKeyPattern;
var
  mProject: string;
begin
  Result := Empty;
  if SameText(ATarget.Provider, TAtlasTrackerTarget.cGitHub) then
  begin
    mProject := LowerCase(Trim(ATarget.Project));
    if (Pos('/', mProject) > 1) and (Pos('/', mProject) < Length(mProject)) then
    begin
      Result.Provider := TAtlasTrackerTarget.cGitHub;
      Result.Repository := mProject;
    end;
  end
  else if SameText(ATarget.Provider, TAtlasTrackerTarget.cYouTrack) then
  begin
    Result.Projects := YouTrackProjects(ATarget.Project);
    if Length(Result.Projects) > 0 then
    begin
      Result.Provider := TAtlasTrackerTarget.cYouTrack;
    end;
  end;
end;

function TAtlasIssueKeyPattern.Active: Boolean;
begin
  Result := Provider <> '';
end;

function TAtlasIssueKeyPattern.Key: string;
begin
  Result := Provider + '|' + string.Join(',', Projects) + '|' + Repository;
end;

{ TAtlasIssueKeyMatch }

function TAtlasIssueKeyMatch.IssueKey: string;
begin
  if Repository <> '' then
  begin
    Result := '#' + IntToStr(Number);
  end
  else
  begin
    Result := Key;
  end;
end;

function TAtlasIssueKeyMatch.IssueTarget(const ATarget: TAtlasTrackerTarget): TAtlasTrackerTarget;
begin
  Result := ATarget;
  if Repository <> '' then
  begin
    Result.Project := Repository;
  end;
end;

{ TAtlasCodeLinks }

/// <summary>YouTrack-Kennung ab AIndex (1-basiert, Buchstabe nach einer Wortgrenze); False ohne.</summary>
function YouTrackAt(const APattern: TAtlasIssueKeyPattern; const AText: string; AIndex, ALast: Integer;
  out AMatch: TAtlasIssueKeyMatch): Boolean;
var
  mEnd, mDigits, mNumberEnd: Integer;
  mPrefix, mProject: string;
begin
  Result := False;
  AMatch := Default(TAtlasIssueKeyMatch);
  mEnd := AIndex;
  while (mEnd <= ALast) and (IsAsciiLetter(AText[mEnd]) or IsDigit(AText[mEnd]) or (AText[mEnd] = '_')) do
  begin
    Inc(mEnd);
  end;
  if (mEnd > ALast) or (AText[mEnd] <> '-') then
  begin
    Exit;
  end;
  mPrefix := UpperCase(Copy(AText, AIndex, mEnd - AIndex));
  mNumberEnd := mEnd + 1;
  while (mNumberEnd <= ALast) and IsDigit(AText[mNumberEnd]) do
  begin
    Inc(mNumberEnd);
  end;
  mDigits := mNumberEnd - mEnd - 1;
  if (mDigits < 1) or (mDigits > TAtlasCodeLinks.cMaxDigits) then
  begin
    Exit;
  end;
  // Hinter der Nummer eine Wortgrenze, auch über das Ende des Bereichs hinaus.
  if (mNumberEnd <= Length(AText)) and IsWordChar(AText[mNumberEnd]) then
  begin
    Exit;
  end;
  for mProject in APattern.Projects do
  begin
    if mProject = mPrefix then
    begin
      AMatch.Character := AIndex - 1;
      AMatch.Length := mNumberEnd - AIndex;
      AMatch.Number := StrToIntDef(Copy(AText, mEnd + 1, mDigits), 0);
      AMatch.Key := mProject + '-' + IntToStr(AMatch.Number);
      Result := AMatch.Number > 0;
      Exit;
    end;
  end;
end;

/// <summary>Erste Stelle ab AFrom (höchstens bis ALast), die keine Ziffer ist.</summary>
function DigitsEnd(const AText: string; AFrom, ALast: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= ALast) and IsDigit(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>"owner/" vor dem Repository ab ARepoStart: Anfang und Name "owner/repo"; False, wenn davor noch ein
/// Wort, "/", "." oder "-" steht.</summary>
function OwnerBefore(const AText: string; AIndex, AFirst, ARepoStart: Integer; var AStart: Integer;
  var ARepository: string): Boolean;
var
  mOwnerStart: Integer;
begin
  mOwnerStart := ARepoStart - 1;
  while (mOwnerStart > AFirst) and IsOwnerChar(AText[mOwnerStart - 1]) do
  begin
    Dec(mOwnerStart);
  end;
  Result := (mOwnerStart < ARepoStart - 1) and ((mOwnerStart = AFirst) or
    not (IsWordChar(AText[mOwnerStart - 1]) or CharInSet(AText[mOwnerStart - 1], ['/', '.', '-'])));
  if Result then
  begin
    AStart := mOwnerStart;
    ARepository := LowerCase(Copy(AText, mOwnerStart, AIndex - mOwnerStart));
  end;
end;

/// <summary>Was vor dem „#“ an AIndex steht: nichts Störendes (AStart = AIndex) oder „owner/repo“ (AStart dort,
/// ARepository gesetzt). False bei einem Wort ohne „/“ („Nr#12“, „C#7“) und nach „&amp;“, „#“, „$“, „/“.</summary>
function PrefixOf(const AText: string; AIndex, AFirst: Integer; out AStart: Integer;
  out ARepository: string): Boolean;
var
  mRepoStart: Integer;
begin
  AStart := AIndex;
  ARepository := '';
  mRepoStart := AIndex;
  while (mRepoStart > AFirst) and IsRepoChar(AText[mRepoStart - 1]) do
  begin
    Dec(mRepoStart);
  end;
  if (mRepoStart < AIndex) and (mRepoStart > AFirst) and (AText[mRepoStart - 1] = '/') then
  begin
    Exit(OwnerBefore(AText, AIndex, AFirst, mRepoStart, AStart, ARepository));
  end;
  Result := (mRepoStart = AIndex) and
    not ((AIndex > AFirst) and CharInSet(AText[AIndex - 1], ['&', '#', '$', '/']));
end;

/// <summary>GitHub-Kennung mit dem „#“ an AIndex (1-basiert); AFirst ist der Anfang des Bereichs. Erkennt auch
/// „owner/repo#42“ davor.</summary>
function GitHubAt(const APattern: TAtlasIssueKeyPattern; const AText: string; AIndex, AFirst, ALast: Integer;
  out AMatch: TAtlasIssueKeyMatch): Boolean;
var
  mNumberEnd, mDigits, mStart: Integer;
  mRepository: string;
begin
  Result := False;
  AMatch := Default(TAtlasIssueKeyMatch);
  mNumberEnd := DigitsEnd(AText, AIndex + 1, ALast);
  mDigits := mNumberEnd - AIndex - 1;
  if (mDigits < 1) or (mDigits > TAtlasCodeLinks.cMaxDigits) or ((mNumberEnd <= Length(AText)) and
    (IsWordChar(AText[mNumberEnd]) or CharInSet(AText[mNumberEnd], ['#', '$']))) then
  begin
    Exit;
  end;
  if not PrefixOf(AText, AIndex, AFirst, mStart, mRepository) then
  begin
    Exit;
  end;
  AMatch.Character := mStart - 1;
  AMatch.Length := mNumberEnd - mStart;
  AMatch.Number := StrToIntDef(Copy(AText, AIndex + 1, mDigits), 0);
  if (mRepository <> '') and (mRepository <> APattern.Repository) then
  begin
    AMatch.Repository := mRepository;
    AMatch.Key := Copy(AText, mStart, AIndex - mStart) + '#' + IntToStr(AMatch.Number);
  end
  else
  begin
    AMatch.Key := '#' + IntToStr(AMatch.Number);
  end;
  Result := AMatch.Number > 0;
end;

class function TAtlasCodeLinks.FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string):
  TArray<TAtlasIssueKeyMatch>;
begin
  Result := FindKeys(APattern, AText, 0, Length(AText), TAtlasCodeLinkPlace.Comment);
end;

/// <summary>Anfang eines Worts mit Buchstaben, an dem eine YouTrack-Kennung stehen kann.</summary>
function YouTrackStart(const APattern: TAtlasIssueKeyPattern; const AText: string; AIndex: Integer): Boolean;
begin
  Result := (APattern.Provider = TAtlasTrackerTarget.cYouTrack) and IsAsciiLetter(AText[AIndex]) and
    ((AIndex = 1) or not IsWordChar(AText[AIndex - 1]));
end;

/// <summary>Kennung ab AIndex; AIndex dahinter. Ohne Kennung bei YouTrack hinter das Wort, sonst ein Zeichen
/// weiter.</summary>
function KeyAt(const APattern: TAtlasIssueKeyPattern; const AText: string; AFirst, ALast: Integer;
  var AIndex: Integer; out AMatch: TAtlasIssueKeyMatch): Boolean;
begin
  if YouTrackStart(APattern, AText, AIndex) then
  begin
    Result := YouTrackAt(APattern, AText, AIndex, ALast, AMatch);
    if not Result then
    begin
      // Rest des Worts überspringen.
      while (AIndex <= ALast) and IsWordChar(AText[AIndex]) do
      begin
        Inc(AIndex);
      end;
      Exit;
    end;
  end
  else
  begin
    Result := (APattern.Provider = TAtlasTrackerTarget.cGitHub) and (AText[AIndex] = '#') and
      GitHubAt(APattern, AText, AIndex, AFirst, ALast, AMatch);
  end;
  if Result then
  begin
    AIndex := AMatch.Character + AMatch.Length + 1;
  end
  else
  begin
    Inc(AIndex);
  end;
end;

class function TAtlasCodeLinks.FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string; AStart,
  AStop: Integer; APlace: TAtlasCodeLinkPlace): TArray<TAtlasIssueKeyMatch>;
var
  mIndex, mFirst, mLast: Integer;
  mMatch: TAtlasIssueKeyMatch;
begin
  Result := nil;
  if not APattern.Active then
  begin
    Exit;
  end;
  mFirst := Max(AStart + 1, 1);
  mLast := Min(AStop, Length(AText));
  mIndex := mFirst;
  while mIndex <= mLast do
  begin
    if KeyAt(APattern, AText, mFirst, mLast, mIndex, mMatch) then
    begin
      mMatch.Place := APlace;
      Result := Result + [mMatch];
    end;
  end;
end;

type
  /// <summary>Durchläuft eine Zeile ab einem Zustand und sammelt Kommentare und Literale.</summary>
  TLineScanner = record
    Line: string;
    Index: Integer;
    State: TAtlasCodeLinkState;
    Collect: Boolean;
    Ranges: TArray<TAtlasCodeLinkRange>;
    procedure Add(AStart, AStop: Integer; APlace: TAtlasCodeLinkPlace);
    function NextIs(AChar: Char): Boolean;
    function ClosesParen(AIndex: Integer): Boolean;
    function InBrace: Boolean;
    function InParen: Boolean;
    procedure OpenBrace;
    procedure OpenParen;
    procedure ReadLiteral;
    function InCode: Boolean;
    function Step: Boolean;
  end;

procedure TLineScanner.Add(AStart, AStop: Integer; APlace: TAtlasCodeLinkPlace);
var
  mRange: TAtlasCodeLinkRange;
begin
  if Collect and (AStop > AStart) then
  begin
    mRange.Start := AStart;
    mRange.Stop := AStop;
    mRange.Place := APlace;
    Ranges := Ranges + [mRange];
  end;
end;

function TLineScanner.NextIs(AChar: Char): Boolean;
begin
  Result := (Index < Length(Line)) and (Line[Index + 1] = AChar);
end;

function TLineScanner.ClosesParen(AIndex: Integer): Boolean;
begin
  Result := (Line[AIndex] = '*') and (Line[AIndex + 1] = ')');
end;

/// <summary>In { … } bzw. {$ … }: bis zur "}"; False, wenn die Zeile vorher endet.</summary>
function TLineScanner.InBrace: Boolean;
var
  mClose: Integer;
begin
  mClose := Index;
  while (mClose <= Length(Line)) and (Line[mClose] <> '}') do
  begin
    Inc(mClose);
  end;
  if State = TAtlasCodeLinkState.BraceComment then
  begin
    Add(Index - 1, mClose - 1, TAtlasCodeLinkPlace.Comment);
  end;
  Result := mClose <= Length(Line);
  if Result then
  begin
    State := TAtlasCodeLinkState.Code;
    Index := mClose + 1;
  end;
end;

/// <summary>In (* … *) bzw. (*$ … *): bis zum "*)"; False, wenn die Zeile vorher endet.</summary>
function TLineScanner.InParen: Boolean;
var
  mClose: Integer;
begin
  mClose := Index;
  while (mClose < Length(Line)) and not ClosesParen(mClose) do
  begin
    Inc(mClose);
  end;
  Result := (mClose < Length(Line)) and ClosesParen(mClose);
  if (State = TAtlasCodeLinkState.ParenComment) and Result then
  begin
    Add(Index - 1, mClose - 1, TAtlasCodeLinkPlace.Comment);
  end
  else if State = TAtlasCodeLinkState.ParenComment then
  begin
    Add(Index - 1, Length(Line), TAtlasCodeLinkPlace.Comment);
  end;
  if Result then
  begin
    State := TAtlasCodeLinkState.Code;
    Index := mClose + 2;
  end;
end;

procedure TLineScanner.OpenBrace;
begin
  if NextIs('$') then
  begin
    State := TAtlasCodeLinkState.BraceDirective;
  end
  else
  begin
    State := TAtlasCodeLinkState.BraceComment;
  end;
  Inc(Index);
end;

procedure TLineScanner.OpenParen;
begin
  if not NextIs('*') then
  begin
    Inc(Index);
    Exit;
  end;
  if (Index + 1 < Length(Line)) and (Line[Index + 2] = '$') then
  begin
    State := TAtlasCodeLinkState.ParenDirective;
  end
  else
  begin
    State := TAtlasCodeLinkState.ParenComment;
  end;
  Inc(Index, 2);
end;

/// <summary>Literal bis zum schließenden Hochkomma; '' ist ein Hochkomma im Text. Offen am Zeilenende: endet dort.
/// </summary>
procedure TLineScanner.ReadLiteral;
var
  mStart, mClose: Integer;
begin
  mStart := Index + 1;
  mClose := mStart;
  while mClose <= Length(Line) do
  begin
    if Line[mClose] <> '''' then
    begin
      Inc(mClose);
    end
    else if (mClose < Length(Line)) and (Line[mClose + 1] = '''') then
    begin
      Inc(mClose, 2);
    end
    else
    begin
      Break;
    end;
  end;
  Add(mStart - 1, mClose - 1, TAtlasCodeLinkPlace.Literal);
  Index := mClose + 1;
end;

/// <summary>Im Code: Anfang von Kommentar oder Literal erkennen; False beim Zeilenkommentar (Rest der Zeile).
/// </summary>
function TLineScanner.InCode: Boolean;
begin
  Result := True;
  case Line[Index] of
    '/':
      if NextIs('/') then
      begin
        Add(Index + 1, Length(Line), TAtlasCodeLinkPlace.Comment);
        Result := False;
      end
      else
      begin
        Inc(Index);
      end;
    '{':
      OpenBrace;
    '(':
      OpenParen;
    '''':
      ReadLiteral;
  else
    Inc(Index);
  end;
end;

function TLineScanner.Step: Boolean;
begin
  case State of
    TAtlasCodeLinkState.BraceComment, TAtlasCodeLinkState.BraceDirective:
      Result := InBrace;
    TAtlasCodeLinkState.ParenComment, TAtlasCodeLinkState.ParenDirective:
      Result := InParen;
  else
    Result := InCode;
  end;
end;

/// <summary>Durchläuft ALine ab AState; mit ACollect die Bereiche in ARanges.</summary>
procedure Scan(const ALine: string; var AState: TAtlasCodeLinkState; ACollect: Boolean;
  var ARanges: TArray<TAtlasCodeLinkRange>);
var
  mScanner: TLineScanner;
begin
  mScanner := Default(TLineScanner);
  mScanner.Line := ALine;
  mScanner.Index := 1;
  mScanner.State := AState;
  mScanner.Collect := ACollect;
  mScanner.Ranges := ARanges;
  while mScanner.Index <= Length(ALine) do
  begin
    if not mScanner.Step then
    begin
      Break;
    end;
  end;
  AState := mScanner.State;
  ARanges := mScanner.Ranges;
end;

class function TAtlasCodeLinks.Ranges(const ALine: string; var AState: TAtlasCodeLinkState):
  TArray<TAtlasCodeLinkRange>;
begin
  Result := nil;
  Scan(ALine, AState, True, Result);
end;

class function TAtlasCodeLinks.NextState(const ALine: string; AState: TAtlasCodeLinkState): TAtlasCodeLinkState;
var
  mNone: TArray<TAtlasCodeLinkRange>;
begin
  Result := AState;
  mNone := nil;
  Scan(ALine, Result, False, mNone);
end;

class function TAtlasCodeLinks.States(const ALines: TArray<string>): TArray<TAtlasCodeLinkState>;
var
  mIndex: Integer;
  mState: TAtlasCodeLinkState;
begin
  SetLength(Result, Length(ALines));
  mState := TAtlasCodeLinkState.Code;
  for mIndex := 0 to High(ALines) do
  begin
    Result[mIndex] := mState;
    mState := NextState(ALines[mIndex], mState);
  end;
end;

class function TAtlasCodeLinks.CommitPrefix(const ACommitPattern: string; const AMatch: TAtlasIssueKeyMatch): string;
var
  mCut: Integer;
begin
  Result := ACommitPattern;
  mCut := Pos('{kurztitel}', LowerCase(Result));
  if mCut > 0 then
  begin
    Result := Copy(Result, 1, mCut - 1);
  end;
  Result := StringReplace(Result, '{kennung}', AMatch.Key, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{nummer}', IntToStr(AMatch.Number), [rfReplaceAll, rfIgnoreCase]);
  Result := TrimRight(Result);
end;

class function TAtlasCodeLinks.LiteralAllowed(const ALiteral, ACommitPattern: string;
  const AMatch: TAtlasIssueKeyMatch): Boolean;
var
  mPrefix: string;
begin
  mPrefix := CommitPrefix(ACommitPattern, AMatch);
  // Ein Präfix ohne die Kennung (nur Text) sagt nichts über sie.
  Result := (mPrefix <> '') and (Pos(LowerCase(AMatch.Key), LowerCase(mPrefix)) > 0) and
    (Pos(LowerCase(mPrefix), LowerCase(TrimLeft(ALiteral))) = 1);
end;

class function TAtlasCodeLinks.LineMatches(const APattern: TAtlasIssueKeyPattern; const ALine: string;
  AState: TAtlasCodeLinkState; const ACommitPattern: string): TArray<TAtlasIssueKeyMatch>;
var
  mRanges: TArray<TAtlasCodeLinkRange>;
  mRange: TAtlasCodeLinkRange;
  mMatch: TAtlasIssueKeyMatch;
  mLiteral: string;
begin
  Result := nil;
  if not APattern.Active or (ALine = '') then
  begin
    Exit;
  end;
  mRanges := Ranges(ALine, AState);
  for mRange in mRanges do
  begin
    if mRange.Place = TAtlasCodeLinkPlace.Comment then
    begin
      Result := Result + FindKeys(APattern, ALine, mRange.Start, mRange.Stop, TAtlasCodeLinkPlace.Comment);
    end
    else if Trim(ACommitPattern) <> '' then
    begin
      mLiteral := Copy(ALine, mRange.Start + 1, mRange.Stop - mRange.Start);
      for mMatch in FindKeys(APattern, ALine, mRange.Start, mRange.Stop, TAtlasCodeLinkPlace.Literal) do
      begin
        if LiteralAllowed(mLiteral, ACommitPattern, mMatch) then
        begin
          Result := Result + [mMatch];
        end;
      end;
    end;
  end;
end;

class function TAtlasCodeLinks.Find(const APattern: TAtlasIssueKeyPattern; const ALines: TArray<string>;
  const ACommitPattern: string): TArray<TAtlasIssueKeyLineMatch>;
var
  mStates: TArray<TAtlasCodeLinkState>;
  mIndex: Integer;
  mMatch: TAtlasIssueKeyMatch;
  mItem: TAtlasIssueKeyLineMatch;
begin
  Result := nil;
  if not APattern.Active then
  begin
    Exit;
  end;
  mStates := States(ALines);
  for mIndex := 0 to High(ALines) do
  begin
    for mMatch in LineMatches(APattern, ALines[mIndex], mStates[mIndex], ACommitPattern) do
    begin
      mItem.Line := mIndex;
      mItem.Match := mMatch;
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasCodeLinks.MatchAt(const AMatches: TArray<TAtlasIssueKeyMatch>; ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AMatches) do
  begin
    if (ACharacter >= AMatches[mIndex].Character) and
      (ACharacter < AMatches[mIndex].Character + AMatches[mIndex].Length) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasCodeLinks.DistinctKeys(const AMatches: TArray<TAtlasIssueKeyMatch>):
  TArray<TAtlasIssueKeyMatch>;
var
  mMatch, mSeen: TAtlasIssueKeyMatch;
  mKnown: Boolean;
begin
  Result := nil;
  for mMatch in AMatches do
  begin
    mKnown := False;
    for mSeen in Result do
    begin
      if SameText(mSeen.Key, mMatch.Key) then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mMatch];
    end;
  end;
end;

end.
