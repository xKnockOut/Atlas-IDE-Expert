unit Atlas.Core.Tracker.Naming;

// Namen rund um „Beginnen“ (#765), ohne VCL, Open Tools API und Netz:
// - Kurztitel: die ersten drei Wörter des Titels, klein, Umlaute ersetzt
//   (ä → ae, ß → ss), Akzente entfernt, mit Bindestrichen. Eine Vorsilbe aus
//   einem Wort mit Doppelpunkt („Plugin: …“) entfällt, wie im Mockup.
// - Branch-Name aus issues.branchPattern mit den Platzhaltern
//   {kennung} (753 bzw. ATL-123; das „#“ von GitHub entfällt), {nummer} und
//   {kurztitel}; danach nach den Regeln von git check-ref-format bereinigt,
//   damit der Name für Git und SVN gültig ist.
// - Commit-Präfix aus issues.commitPattern ({kennung} mit „#“).
// - Gültigkeit und Basen eines Branchs: Atlas.Core.VersionControl.BranchNames (Base).
// - Kennung aus einem Branch-Namen (Branch → Ticket): GitHub die Nummer als
//   eigenes Stück („feature/753-x“ → #753), YouTrack „ATL-123“.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract;

type
  TAtlasTrackerNaming = class
  public const
    /// <summary>Vorgabe für issues.branchPattern unter Git.</summary>
    cGitBranchPattern = 'feature/{kennung}-{kurztitel}';
    /// <summary>Vorgabe unter SVN: der Name unter ^/branches/.</summary>
    cSvnBranchPattern = '{kennung}-{kurztitel}';
    /// <summary>Vorgabe für issues.commitPattern.</summary>
    cCommitPattern = '{kennung} ';
    /// <summary>Höchstens so viele Wörter im Kurztitel.</summary>
    cShortTitleWords = 3;
  public
    /// <summary>Erste drei Wörter, klein, nur a–z, 0–9 und „-“; '' ohne Wörter.</summary>
    class function ShortTitle(const ATitle: string): string; static;
    /// <summary>Kennung für Branch-Namen: "#753" → "753", "ATL-123" bleibt.</summary>
    class function BranchKey(const AKey: string): string; static;
    /// <summary>Platzhalter {kennung} (wie BranchKey), {nummer}, {kurztitel} ersetzen und bereinigen; '' wenn
    /// nichts Gültiges bleibt.</summary>
    class function BranchName(const APattern: string; const AIssue: TAtlasTrackerIssue): string; static;
    /// <summary>Platzhalter {kennung} (mit „#“), {nummer} und {kurztitel} ersetzen; nicht gekürzt, das
    /// Leerzeichen am Ende bleibt. '' bei leerem Muster.</summary>
    class function CommitPrefix(const APattern: string; const AIssue: TAtlasTrackerIssue): string; static;
    /// <summary>APrefix vor AMessage; unverändert, wenn APrefix leer ist oder AMessage schon damit (oder mit der
    /// Kennung ohne Leerzeichen) beginnt.</summary>
    class function Prefixed(const AMessage, APrefix: string): string; static;
    /// <summary>Kennung des Issues, an dem der Branch arbeitet; '' ohne. AProvider "github": Nummer als eigenes
    /// Stück (nach Anfang, "/", "-", "_" oder "#", vor Ende, "-" oder "_") → "#753". "youtrack": "&lt;Projekt&gt;-
    /// &lt;Nummer&gt;" (AProject leer: jedes Kürzel aus Buchstaben und Ziffern).</summary>
    class function KeyOfBranch(const AProvider, AProject, ABranch: string): string; static;
  end;

implementation

uses
  Atlas.Core.VersionControl.BranchNames;

const
  // Paare: Zeichen und Ersatz. Großbuchstaben mit, weil LowerCase nur ASCII kennt.
  cFolding: array[0..63] of string = (
    'ä', 'ae', 'ö', 'oe', 'ü', 'ue', 'ß', 'ss', 'Ä', 'ae', 'Ö', 'oe', 'Ü', 'ue', 'ẞ', 'ss',
    'à', 'a', 'á', 'a', 'â', 'a', 'ã', 'a', 'å', 'a', 'æ', 'ae', 'ç', 'c', 'è', 'e',
    'é', 'e', 'ê', 'e', 'ë', 'e', 'ì', 'i', 'í', 'i', 'î', 'i', 'ï', 'i', 'ñ', 'n',
    'ò', 'o', 'ó', 'o', 'ô', 'o', 'õ', 'o', 'ø', 'o', 'œ', 'oe', 'ù', 'u', 'ú', 'u');
  cFoldingMore: array[0..27] of string = (
    'û', 'u', 'ý', 'y', 'ÿ', 'y', 'À', 'a', 'Á', 'a', 'Â', 'a', 'Ç', 'c', 'È', 'e',
    'É', 'e', 'Ê', 'e', 'Î', 'i', 'Ñ', 'n', 'Ó', 'o', 'Ô', 'o');

function IsAsciiAlnum(AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or ((AChar >= 'A') and (AChar <= 'Z')) or
    ((AChar >= '0') and (AChar <= '9'));
end;

function IsDigit(AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

function Fold(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  mIndex := 0;
  while mIndex < High(cFolding) do
  begin
    Result := StringReplace(Result, cFolding[mIndex], cFolding[mIndex + 1], [rfReplaceAll]);
    Inc(mIndex, 2);
  end;
  mIndex := 0;
  while mIndex < High(cFoldingMore) do
  begin
    Result := StringReplace(Result, cFoldingMore[mIndex], cFoldingMore[mIndex + 1], [rfReplaceAll]);
    Inc(mIndex, 2);
  end;
  Result := LowerCase(Result);
end;

/// <summary>"Plugin: Titel" → "Titel": ein Wort ohne Leerzeichen vor ": ".</summary>
function WithoutPrefix(const ATitle: string): string;
var
  mColon, mIndex: Integer;
begin
  Result := Trim(ATitle);
  mColon := Pos(': ', Result);
  if mColon <= 1 then
  begin
    Exit;
  end;
  for mIndex := 1 to mColon - 1 do
  begin
    if Result[mIndex] = ' ' then
    begin
      Exit;
    end;
  end;
  Result := Trim(Copy(Result, mColon + 2, MaxInt));
end;

class function TAtlasTrackerNaming.ShortTitle(const ATitle: string): string;
var
  mText, mWord: string;
  mIndex, mCount: Integer;
begin
  Result := '';
  mText := Fold(WithoutPrefix(ATitle));
  mCount := 0;
  mWord := '';
  for mIndex := 1 to Length(mText) + 1 do
  begin
    if (mIndex <= Length(mText)) and IsAsciiAlnum(mText[mIndex]) then
    begin
      mWord := mWord + mText[mIndex];
      Continue;
    end;
    if mWord = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + '-';
    end;
    Result := Result + mWord;
    mWord := '';
    Inc(mCount);
    if mCount >= cShortTitleWords then
    begin
      Break;
    end;
  end;
end;

class function TAtlasTrackerNaming.BranchKey(const AKey: string): string;
begin
  Result := Trim(AKey);
  while (Result <> '') and (Result[1] = '#') do
  begin
    Delete(Result, 1, 1);
  end;
end;

function Fill(const APattern, AKey: string; const AIssue: TAtlasTrackerIssue): string;
var
  mNumber: string;
begin
  mNumber := '';
  if AIssue.Number > 0 then
  begin
    mNumber := IntToStr(AIssue.Number);
  end;
  Result := StringReplace(APattern, '{kennung}', AKey, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{nummer}', mNumber, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{kurztitel}', TAtlasTrackerNaming.ShortTitle(AIssue.Title),
    [rfReplaceAll, rfIgnoreCase]);
end;

/// <summary>Zeichen, die Git in Namen verbietet, als "-"; "@{" ebenso.</summary>
function ReplaceForbidden(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to Length(AName) do
  begin
    case AName[mIndex] of
      #0..' ', '~', '^', ':', '?', '*', '[', '\', #127:
        Result := Result + '-';
    else
      Result := Result + AName[mIndex];
    end;
  end;
  Result := StringReplace(Result, '@{', '-', [rfReplaceAll]);
end;

/// <summary>".." und "--" so lange zusammenziehen, bis keines mehr vorkommt.</summary>
function CollapseRepeats(const AName: string): string;
begin
  Result := AName;
  while (Pos('..', Result) > 0) or (Pos('--', Result) > 0) do
  begin
    Result := StringReplace(Result, '..', '.', [rfReplaceAll]);
    Result := StringReplace(Result, '--', '-', [rfReplaceAll]);
  end;
end;

/// <summary>Ein Stück ohne "." oder "-" am Anfang und ohne ".", "-" oder ".lock" am Ende.</summary>
function TrimPart(const APart: string): string;
var
  mChanged: Boolean;
begin
  Result := APart;
  while (Result <> '') and CharInSet(Result[1], ['.', '-']) do
  begin
    Delete(Result, 1, 1);
  end;
  repeat
    mChanged := False;
    while (Result <> '') and CharInSet(Result[Length(Result)], ['.', '-']) do
    begin
      Delete(Result, Length(Result), 1);
      mChanged := True;
    end;
    if SameText(Copy(Result, Length(Result) - 4, 5), '.lock') then
    begin
      Delete(Result, Length(Result) - 4, 5);
      mChanged := True;
    end;
  until not mChanged;
end;

/// <summary>Stücke einzeln: leere entfallen.</summary>
function TrimParts(const AName: string): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AName.Split(['/']) do
  begin
    if TrimPart(mPart) = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + '/';
    end;
    Result := Result + TrimPart(mPart);
  end;
end;

function Sanitize(const AName: string): string;
begin
  Result := TrimParts(CollapseRepeats(ReplaceForbidden(AName)));
  if Length(Result) > TAtlasVcsBranchNames.cMaxLength then
  begin
    Result := Copy(Result, 1, TAtlasVcsBranchNames.cMaxLength);
    while (Result <> '') and CharInSet(Result[Length(Result)], ['.', '-', '/']) do
    begin
      Delete(Result, Length(Result), 1);
    end;
  end;
end;

class function TAtlasTrackerNaming.BranchName(const APattern: string; const AIssue: TAtlasTrackerIssue): string;
begin
  Result := Sanitize(Fill(Trim(APattern), BranchKey(AIssue.Key), AIssue));
  if not TAtlasVcsBranchNames.Valid(Result) then
  begin
    Result := '';
  end;
end;

class function TAtlasTrackerNaming.CommitPrefix(const APattern: string; const AIssue: TAtlasTrackerIssue): string;
begin
  Result := '';
  if (APattern = '') or (Trim(AIssue.Key) = '') then
  begin
    Exit;
  end;
  Result := Fill(APattern, Trim(AIssue.Key), AIssue);
  // Zeilenumbrüche gehören nicht in einen Präfix.
  Result := StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

class function TAtlasTrackerNaming.Prefixed(const AMessage, APrefix: string): string;
var
  mBare: string;
begin
  Result := AMessage;
  if APrefix = '' then
  begin
    Exit;
  end;
  mBare := TrimRight(APrefix);
  if (Copy(AMessage, 1, Length(APrefix)) = APrefix) or ((mBare <> '') and (Copy(AMessage, 1, Length(mBare)) = mBare))
  then
  begin
    Exit;
  end;
  Result := APrefix + AMessage;
end;

/// <summary>Erste Stelle ab AIndex, die keine Ziffer ist.</summary>
function DigitsEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and IsDigit(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>"#" und die Nummer ohne führende Nullen; '' für 0.</summary>
function IssueNumber(const ADigits: string): string;
begin
  Result := ADigits;
  while (Length(Result) > 1) and (Result[1] = '0') do
  begin
    Delete(Result, 1, 1);
  end;
  if Result = '0' then
  begin
    Result := '';
  end
  else
  begin
    Result := '#' + Result;
  end;
end;

/// <summary>Die Ziffern von AStart bis vor AStop stehen allein: am Anfang bzw. nach "/", "-", "_", "#" und am
/// Ende bzw. vor "-", "_".</summary>
function StandsAlone(const ABranch: string; AStart, AStop: Integer): Boolean;
begin
  Result := ((AStart = 1) or CharInSet(ABranch[AStart - 1], ['/', '-', '_', '#'])) and
    ((AStop > Length(ABranch)) or CharInSet(ABranch[AStop], ['-', '_']));
end;

function GitHubKeyOf(const ABranch: string): string;
var
  mIndex, mStop: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(ABranch) do
  begin
    if not IsDigit(ABranch[mIndex]) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mStop := DigitsEnd(ABranch, mIndex);
    if StandsAlone(ABranch, mIndex, mStop) then
    begin
      Exit(IssueNumber(Copy(ABranch, mIndex, mStop - mIndex)));
    end;
    mIndex := mStop;
  end;
end;

/// <summary>Anfang eines Kürzels: Buchstabe am Anfang oder nach einem Zeichen, das kein Buchstabe und keine
/// Ziffer ist.</summary>
function IsKeyStart(const AUpper: string; AIndex: Integer): Boolean;
begin
  Result := CharInSet(AUpper[AIndex], ['A'..'Z']) and ((AIndex = 1) or not IsAsciiAlnum(AUpper[AIndex - 1]));
end;

function YouTrackKeyOf(const AProject, ABranch: string): string;
var
  mUpper, mProject: string;
  mIndex, mStart, mStop: Integer;
begin
  Result := '';
  mUpper := UpperCase(ABranch);
  mProject := UpperCase(Trim(AProject));
  mIndex := 1;
  while mIndex <= Length(mUpper) do
  begin
    if not IsKeyStart(mUpper, mIndex) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mStart := mIndex;
    while (mIndex <= Length(mUpper)) and IsAsciiAlnum(mUpper[mIndex]) do
    begin
      Inc(mIndex);
    end;
    if (mIndex >= Length(mUpper)) or (mUpper[mIndex] <> '-') or not IsDigit(mUpper[mIndex + 1]) or
      ((mProject <> '') and (Copy(mUpper, mStart, mIndex - mStart) <> mProject)) then
    begin
      Continue;
    end;
    mStop := DigitsEnd(mUpper, mIndex + 1);
    if (mStop > Length(mUpper)) or not IsAsciiAlnum(mUpper[mStop]) then
    begin
      Exit(Copy(mUpper, mStart, mStop - mStart));
    end;
    mIndex := mStop;
  end;
end;

class function TAtlasTrackerNaming.KeyOfBranch(const AProvider, AProject, ABranch: string): string;
begin
  Result := '';
  if SameText(AProvider, TAtlasTrackerTarget.cGitHub) then
  begin
    Result := GitHubKeyOf(Trim(ABranch));
  end
  else if SameText(AProvider, TAtlasTrackerTarget.cYouTrack) then
  begin
    Result := YouTrackKeyOf(AProject, Trim(ABranch));
  end;
end;

end.
