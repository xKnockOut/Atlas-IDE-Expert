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
    MaxDigits = 9;
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

class function TAtlasIssueKeyPattern.ForTarget(const ATarget: TAtlasTrackerTarget): TAtlasIssueKeyPattern;
var
  mPart, mProject: string;
  mValid: Boolean;
  mIndex: Integer;
begin
  Result := Empty;
  if SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) then
  begin
    mProject := LowerCase(Trim(ATarget.Project));
    if (Pos('/', mProject) > 1) and (Pos('/', mProject) < Length(mProject)) then
    begin
      Result.Provider := TAtlasTrackerTarget.GitHub;
      Result.Repository := mProject;
    end;
  end
  else if SameText(ATarget.Provider, TAtlasTrackerTarget.YouTrack) then
  begin
    for mPart in ATarget.Project.Split([',', ';', ' ']) do
    begin
      mProject := UpperCase(Trim(mPart));
      mValid := (mProject <> '') and IsAsciiLetter(mProject[1]);
      for mIndex := 1 to Length(mProject) do
        if not (IsAsciiLetter(mProject[mIndex]) or IsDigit(mProject[mIndex]) or (mProject[mIndex] = '_')) then
          mValid := False;
      if mValid then
        Result.Projects := Result.Projects + [mProject];
    end;
    if Length(Result.Projects) > 0 then
      Result.Provider := TAtlasTrackerTarget.YouTrack;
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
    Result := '#' + IntToStr(Number)
  else
    Result := Key;
end;

function TAtlasIssueKeyMatch.IssueTarget(const ATarget: TAtlasTrackerTarget): TAtlasTrackerTarget;
begin
  Result := ATarget;
  if Repository <> '' then
    Result.Project := Repository;
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
    Inc(mEnd);
  if (mEnd > ALast) or (AText[mEnd] <> '-') then
    Exit;
  mPrefix := UpperCase(Copy(AText, AIndex, mEnd - AIndex));
  mNumberEnd := mEnd + 1;
  while (mNumberEnd <= ALast) and IsDigit(AText[mNumberEnd]) do
    Inc(mNumberEnd);
  mDigits := mNumberEnd - mEnd - 1;
  if (mDigits < 1) or (mDigits > TAtlasCodeLinks.MaxDigits) then
    Exit;
  // Hinter der Nummer eine Wortgrenze, auch über das Ende des Bereichs hinaus.
  if (mNumberEnd <= Length(AText)) and IsWordChar(AText[mNumberEnd]) then
    Exit;
  for mProject in APattern.Projects do
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

/// <summary>GitHub-Kennung mit dem „#“ an AIndex (1-basiert); AFirst ist der Anfang des Bereichs. Erkennt auch
/// „owner/repo#42“ davor.</summary>
function GitHubAt(const APattern: TAtlasIssueKeyPattern; const AText: string; AIndex, AFirst, ALast: Integer;
  out AMatch: TAtlasIssueKeyMatch): Boolean;
var
  mNumberEnd, mDigits, mRepoStart, mOwnerStart, mStart: Integer;
  mRepository: string;
begin
  Result := False;
  AMatch := Default(TAtlasIssueKeyMatch);
  mNumberEnd := AIndex + 1;
  while (mNumberEnd <= ALast) and IsDigit(AText[mNumberEnd]) do
    Inc(mNumberEnd);
  mDigits := mNumberEnd - AIndex - 1;
  if (mDigits < 1) or (mDigits > TAtlasCodeLinks.MaxDigits) then
    Exit;
  if (mNumberEnd <= Length(AText)) and (IsWordChar(AText[mNumberEnd]) or (AText[mNumberEnd] = '#') or
    (AText[mNumberEnd] = '$')) then
    Exit;
  mStart := AIndex;
  mRepository := '';
  // owner/repo davor?
  mRepoStart := AIndex;
  while (mRepoStart > AFirst) and IsRepoChar(AText[mRepoStart - 1]) do
    Dec(mRepoStart);
  if (mRepoStart < AIndex) and (mRepoStart > AFirst) and (AText[mRepoStart - 1] = '/') then
  begin
    mOwnerStart := mRepoStart - 1;
    while (mOwnerStart > AFirst) and IsOwnerChar(AText[mOwnerStart - 1]) do
      Dec(mOwnerStart);
    if (mOwnerStart < mRepoStart - 1) and ((mOwnerStart = AFirst) or not (IsWordChar(AText[mOwnerStart - 1]) or
      (AText[mOwnerStart - 1] = '/') or (AText[mOwnerStart - 1] = '.') or (AText[mOwnerStart - 1] = '-'))) then
    begin
      mStart := mOwnerStart;
      mRepository := LowerCase(Copy(AText, mOwnerStart, AIndex - mOwnerStart));
    end
    else
      Exit;
  end
  else if mRepoStart < AIndex then
    // Direkt vor dem „#“ steht ein Wort ohne „/“ (etwa „Nr#12“ oder „C#7“): keine Kennung.
    Exit
  else if (AIndex > AFirst) and ((AText[AIndex - 1] = '&') or (AText[AIndex - 1] = '#') or (AText[AIndex - 1] = '$') or
    (AText[AIndex - 1] = '/')) then
    Exit;
  AMatch.Character := mStart - 1;
  AMatch.Length := mNumberEnd - mStart;
  AMatch.Number := StrToIntDef(Copy(AText, AIndex + 1, mDigits), 0);
  if (mRepository <> '') and (mRepository <> APattern.Repository) then
  begin
    AMatch.Repository := mRepository;
    AMatch.Key := Copy(AText, mStart, AIndex - mStart) + '#' + IntToStr(AMatch.Number);
  end
  else
    AMatch.Key := '#' + IntToStr(AMatch.Number);
  Result := AMatch.Number > 0;
end;

class function TAtlasCodeLinks.FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string):
  TArray<TAtlasIssueKeyMatch>;
begin
  Result := FindKeys(APattern, AText, 0, Length(AText), TAtlasCodeLinkPlace.Comment);
end;

class function TAtlasCodeLinks.FindKeys(const APattern: TAtlasIssueKeyPattern; const AText: string; AStart,
  AStop: Integer; APlace: TAtlasCodeLinkPlace): TArray<TAtlasIssueKeyMatch>;
var
  mIndex, mFirst, mLast: Integer;
  mGitHub, mYouTrack: Boolean;
  mMatch: TAtlasIssueKeyMatch;
begin
  Result := nil;
  if not APattern.Active then
    Exit;
  mFirst := AStart + 1;
  if mFirst < 1 then
    mFirst := 1;
  mLast := AStop;
  if mLast > Length(AText) then
    mLast := Length(AText);
  mGitHub := APattern.Provider = TAtlasTrackerTarget.GitHub;
  mYouTrack := APattern.Provider = TAtlasTrackerTarget.YouTrack;
  mIndex := mFirst;
  while mIndex <= mLast do
  begin
    if mYouTrack and IsAsciiLetter(AText[mIndex]) and ((mIndex = 1) or not IsWordChar(AText[mIndex - 1])) then
    begin
      if YouTrackAt(APattern, AText, mIndex, mLast, mMatch) then
      begin
        mMatch.Place := APlace;
        Result := Result + [mMatch];
        mIndex := mMatch.Character + mMatch.Length + 1;
        Continue;
      end;
      // Rest des Worts überspringen.
      while (mIndex <= mLast) and IsWordChar(AText[mIndex]) do
        Inc(mIndex);
      Continue;
    end;
    if mGitHub and (AText[mIndex] = '#') and GitHubAt(APattern, AText, mIndex, mFirst, mLast, mMatch) then
    begin
      mMatch.Place := APlace;
      Result := Result + [mMatch];
      mIndex := mMatch.Character + mMatch.Length + 1;
      Continue;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Durchläuft ALine ab AState; mit ACollect die Bereiche in ARanges.</summary>
procedure Scan(const ALine: string; var AState: TAtlasCodeLinkState; ACollect: Boolean;
  var ARanges: TArray<TAtlasCodeLinkRange>);

  procedure Add(AStart, AStop: Integer; APlace: TAtlasCodeLinkPlace);
  var
    mRange: TAtlasCodeLinkRange;
  begin
    if not ACollect or (AStop <= AStart) then
      Exit;
    mRange.Start := AStart;
    mRange.Stop := AStop;
    mRange.Place := APlace;
    ARanges := ARanges + [mRange];
  end;

var
  mIndex, mLength, mStart: Integer;
  mClose: Integer;
begin
  mLength := Length(ALine);
  mIndex := 1;
  while mIndex <= mLength do
  begin
    case AState of
      TAtlasCodeLinkState.BraceComment, TAtlasCodeLinkState.BraceDirective:
        begin
          mStart := mIndex;
          mClose := mIndex;
          while (mClose <= mLength) and (ALine[mClose] <> '}') do
            Inc(mClose);
          if AState = TAtlasCodeLinkState.BraceComment then
            Add(mStart - 1, mClose - 1, TAtlasCodeLinkPlace.Comment);
          if mClose > mLength then
            Exit;
          AState := TAtlasCodeLinkState.Code;
          mIndex := mClose + 1;
        end;
      TAtlasCodeLinkState.ParenComment, TAtlasCodeLinkState.ParenDirective:
        begin
          mStart := mIndex;
          mClose := mIndex;
          while (mClose < mLength) and not ((ALine[mClose] = '*') and (ALine[mClose + 1] = ')')) do
            Inc(mClose);
          if (mClose >= mLength) or not ((ALine[mClose] = '*') and (ALine[mClose + 1] = ')')) then
          begin
            if AState = TAtlasCodeLinkState.ParenComment then
              Add(mStart - 1, mLength, TAtlasCodeLinkPlace.Comment);
            Exit;
          end;
          if AState = TAtlasCodeLinkState.ParenComment then
            Add(mStart - 1, mClose - 1, TAtlasCodeLinkPlace.Comment);
          AState := TAtlasCodeLinkState.Code;
          mIndex := mClose + 2;
        end;
    else
      case ALine[mIndex] of
        '/':
          if (mIndex < mLength) and (ALine[mIndex + 1] = '/') then
          begin
            Add(mIndex + 1, mLength, TAtlasCodeLinkPlace.Comment);
            Exit;
          end
          else
            Inc(mIndex);
        '{':
          begin
            if (mIndex < mLength) and (ALine[mIndex + 1] = '$') then
              AState := TAtlasCodeLinkState.BraceDirective
            else
              AState := TAtlasCodeLinkState.BraceComment;
            Inc(mIndex);
          end;
        '(':
          if (mIndex < mLength) and (ALine[mIndex + 1] = '*') then
          begin
            if (mIndex + 1 < mLength) and (ALine[mIndex + 2] = '$') then
              AState := TAtlasCodeLinkState.ParenDirective
            else
              AState := TAtlasCodeLinkState.ParenComment;
            Inc(mIndex, 2);
          end
          else
            Inc(mIndex);
        '''':
          begin
            // Literal bis zum schließenden Hochkomma; '' ist ein Hochkomma im Text. Offen am Zeilenende: endet dort.
            mStart := mIndex + 1;
            mClose := mStart;
            while mClose <= mLength do
            begin
              if ALine[mClose] = '''' then
              begin
                if (mClose < mLength) and (ALine[mClose + 1] = '''') then
                  Inc(mClose, 2)
                else
                  Break;
              end
              else
                Inc(mClose);
            end;
            Add(mStart - 1, mClose - 1, TAtlasCodeLinkPlace.Literal);
            mIndex := mClose + 1;
          end;
      else
        Inc(mIndex);
      end;
    end;
  end;
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
    Result := Copy(Result, 1, mCut - 1);
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
    Exit;
  mRanges := Ranges(ALine, AState);
  for mRange in mRanges do
    if mRange.Place = TAtlasCodeLinkPlace.Comment then
      Result := Result + FindKeys(APattern, ALine, mRange.Start, mRange.Stop, TAtlasCodeLinkPlace.Comment)
    else if Trim(ACommitPattern) <> '' then
    begin
      mLiteral := Copy(ALine, mRange.Start + 1, mRange.Stop - mRange.Start);
      for mMatch in FindKeys(APattern, ALine, mRange.Start, mRange.Stop, TAtlasCodeLinkPlace.Literal) do
        if LiteralAllowed(mLiteral, ACommitPattern, mMatch) then
          Result := Result + [mMatch];
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
    Exit;
  mStates := States(ALines);
  for mIndex := 0 to High(ALines) do
    for mMatch in LineMatches(APattern, ALines[mIndex], mStates[mIndex], ACommitPattern) do
    begin
      mItem.Line := mIndex;
      mItem.Match := mMatch;
      Result := Result + [mItem];
    end;
end;

class function TAtlasCodeLinks.MatchAt(const AMatches: TArray<TAtlasIssueKeyMatch>; ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AMatches) do
    if (ACharacter >= AMatches[mIndex].Character) and
      (ACharacter < AMatches[mIndex].Character + AMatches[mIndex].Length) then
      Exit(mIndex);
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
      if SameText(mSeen.Key, mMatch.Key) then
        mKnown := True;
    if not mKnown then
      Result := Result + [mMatch];
  end;
end;

end.
