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
    GitBranchPattern = 'feature/{kennung}-{kurztitel}';
    /// <summary>Vorgabe unter SVN: der Name unter ^/branches/.</summary>
    SvnBranchPattern = '{kennung}-{kurztitel}';
    /// <summary>Vorgabe für issues.commitPattern.</summary>
    CommitPattern = '{kennung} ';
    GitBase = 'main';
    /// <summary>Zweiter Versuch unter Git, wenn es main nicht gibt.</summary>
    GitBaseFallback = 'master';
    SvnBase = 'trunk';
    /// <summary>Höchstens so viele Wörter im Kurztitel.</summary>
    ShortTitleWords = 3;
    /// <summary>Höchstlänge eines Branch-Namens.</summary>
    MaxBranchLength = 100;
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
    /// <summary>Name nach git check-ref-format: nicht leer, ohne Leer- und Steuerzeichen, ~ ^ : ? * [ \, "..",
    /// "@{", "//"; kein "/", "-" oder "." am Anfang, kein "/" oder "." am Ende, kein ".lock" am Ende eines Stücks.
    /// </summary>
    class function ValidBranchName(const AName: string): Boolean; static;
    /// <summary>Kennung des Issues, an dem der Branch arbeitet; '' ohne. AProvider "github": Nummer als eigenes
    /// Stück (nach Anfang, "/", "-", "_" oder "#", vor Ende, "-" oder "_") → "#753". "youtrack": "&lt;Projekt&gt;-
    /// &lt;Nummer&gt;" (AProject leer: jedes Kürzel aus Buchstaben und Ziffern).</summary>
    class function KeyOfBranch(const AProvider, AProject, ABranch: string): string; static;
  end;

implementation

const
  // Paare: Zeichen und Ersatz. Großbuchstaben mit, weil LowerCase nur ASCII kennt.
  Folding: array[0..63] of string = (
    'ä', 'ae', 'ö', 'oe', 'ü', 'ue', 'ß', 'ss', 'Ä', 'ae', 'Ö', 'oe', 'Ü', 'ue', 'ẞ', 'ss',
    'à', 'a', 'á', 'a', 'â', 'a', 'ã', 'a', 'å', 'a', 'æ', 'ae', 'ç', 'c', 'è', 'e',
    'é', 'e', 'ê', 'e', 'ë', 'e', 'ì', 'i', 'í', 'i', 'î', 'i', 'ï', 'i', 'ñ', 'n',
    'ò', 'o', 'ó', 'o', 'ô', 'o', 'õ', 'o', 'ø', 'o', 'œ', 'oe', 'ù', 'u', 'ú', 'u');
  FoldingMore: array[0..27] of string = (
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
  Index: Integer;
begin
  Result := AText;
  Index := 0;
  while Index < High(Folding) do
  begin
    Result := StringReplace(Result, Folding[Index], Folding[Index + 1], [rfReplaceAll]);
    Inc(Index, 2);
  end;
  Index := 0;
  while Index < High(FoldingMore) do
  begin
    Result := StringReplace(Result, FoldingMore[Index], FoldingMore[Index + 1], [rfReplaceAll]);
    Inc(Index, 2);
  end;
  Result := LowerCase(Result);
end;

/// <summary>"Plugin: Titel" → "Titel": ein Wort ohne Leerzeichen vor ": ".</summary>
function WithoutPrefix(const ATitle: string): string;
var
  Colon, Index: Integer;
begin
  Result := Trim(ATitle);
  Colon := Pos(': ', Result);
  if Colon <= 1 then
    Exit;
  for Index := 1 to Colon - 1 do
    if Result[Index] = ' ' then
      Exit;
  Result := Trim(Copy(Result, Colon + 2, MaxInt));
end;

class function TAtlasTrackerNaming.ShortTitle(const ATitle: string): string;
var
  Text, Word: string;
  Index, Count: Integer;
begin
  Result := '';
  Text := Fold(WithoutPrefix(ATitle));
  Count := 0;
  Word := '';
  for Index := 1 to Length(Text) + 1 do
  begin
    if (Index <= Length(Text)) and IsAsciiAlnum(Text[Index]) then
    begin
      Word := Word + Text[Index];
      Continue;
    end;
    if Word = '' then
      Continue;
    if Result <> '' then
      Result := Result + '-';
    Result := Result + Word;
    Word := '';
    Inc(Count);
    if Count >= ShortTitleWords then
      Break;
  end;
end;

class function TAtlasTrackerNaming.BranchKey(const AKey: string): string;
begin
  Result := Trim(AKey);
  while (Result <> '') and (Result[1] = '#') do
    Delete(Result, 1, 1);
end;

function Fill(const APattern, AKey: string; const AIssue: TAtlasTrackerIssue): string;
var
  Number: string;
begin
  Number := '';
  if AIssue.Number > 0 then
    Number := IntToStr(AIssue.Number);
  Result := StringReplace(APattern, '{kennung}', AKey, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{nummer}', Number, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{kurztitel}', TAtlasTrackerNaming.ShortTitle(AIssue.Title),
    [rfReplaceAll, rfIgnoreCase]);
end;

function Sanitize(const AName: string): string;
var
  Index: Integer;
  Parts: TArray<string>;
  Part: string;
  PartIndex: Integer;
  Changed: Boolean;
begin
  Result := '';
  for Index := 1 to Length(AName) do
    case AName[Index] of
      #0..' ', '~', '^', ':', '?', '*', '[', '\', #127:
        Result := Result + '-';
    else
      Result := Result + AName[Index];
    end;
  Result := StringReplace(Result, '@{', '-', [rfReplaceAll]);
  repeat
    Changed := False;
    if Pos('..', Result) > 0 then
    begin
      Result := StringReplace(Result, '..', '.', [rfReplaceAll]);
      Changed := True;
    end;
    if Pos('--', Result) > 0 then
    begin
      Result := StringReplace(Result, '--', '-', [rfReplaceAll]);
      Changed := True;
    end;
  until not Changed;
  // Stücke einzeln: leere entfallen, keines beginnt mit "." oder "-" oder endet mit ".", "-" oder ".lock".
  Parts := Result.Split(['/']);
  Result := '';
  for PartIndex := 0 to High(Parts) do
  begin
    Part := Parts[PartIndex];
    while (Part <> '') and ((Part[1] = '.') or (Part[1] = '-')) do
      Delete(Part, 1, 1);
    repeat
      Changed := False;
      while (Part <> '') and ((Part[Length(Part)] = '.') or (Part[Length(Part)] = '-')) do
      begin
        Delete(Part, Length(Part), 1);
        Changed := True;
      end;
      if SameText(Copy(Part, Length(Part) - 4, 5), '.lock') then
      begin
        Delete(Part, Length(Part) - 4, 5);
        Changed := True;
      end;
    until not Changed;
    if Part = '' then
      Continue;
    if Result <> '' then
      Result := Result + '/';
    Result := Result + Part;
  end;
  if Length(Result) > TAtlasTrackerNaming.MaxBranchLength then
  begin
    Result := Copy(Result, 1, TAtlasTrackerNaming.MaxBranchLength);
    while (Result <> '') and CharInSet(Result[Length(Result)], ['.', '-', '/']) do
      Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasTrackerNaming.BranchName(const APattern: string; const AIssue: TAtlasTrackerIssue): string;
begin
  Result := Sanitize(Fill(Trim(APattern), BranchKey(AIssue.Key), AIssue));
  if not ValidBranchName(Result) then
    Result := '';
end;

class function TAtlasTrackerNaming.CommitPrefix(const APattern: string; const AIssue: TAtlasTrackerIssue): string;
begin
  Result := '';
  if (APattern = '') or (Trim(AIssue.Key) = '') then
    Exit;
  Result := Fill(APattern, Trim(AIssue.Key), AIssue);
  // Zeilenumbrüche gehören nicht in einen Präfix.
  Result := StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

class function TAtlasTrackerNaming.Prefixed(const AMessage, APrefix: string): string;
var
  Bare: string;
begin
  Result := AMessage;
  if APrefix = '' then
    Exit;
  Bare := TrimRight(APrefix);
  if (Copy(AMessage, 1, Length(APrefix)) = APrefix) or ((Bare <> '') and (Copy(AMessage, 1, Length(Bare)) = Bare))
  then
    Exit;
  Result := APrefix + AMessage;
end;

class function TAtlasTrackerNaming.ValidBranchName(const AName: string): Boolean;
var
  Index: Integer;
  Part: string;
begin
  Result := False;
  if (AName = '') or CharInSet(AName[1], ['/', '-', '.']) or CharInSet(AName[Length(AName)], ['/', '.']) then
    Exit;
  if (Pos('..', AName) > 0) or (Pos('@{', AName) > 0) or (Pos('//', AName) > 0) or (AName = '@') then
    Exit;
  for Index := 1 to Length(AName) do
    case AName[Index] of
      #0..' ', '~', '^', ':', '?', '*', '[', '\', #127:
        Exit;
    end;
  for Part in AName.Split(['/']) do
    if (Part = '') or (Part[1] = '.') or SameText(Copy(Part, Length(Part) - 4, 5), '.lock') then
      Exit;
  Result := True;
end;

function GitHubKeyOf(const ABranch: string): string;
var
  Index, Stop: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(ABranch) do
  begin
    if not IsDigit(ABranch[Index]) then
    begin
      Inc(Index);
      Continue;
    end;
    Stop := Index;
    while (Stop <= Length(ABranch)) and IsDigit(ABranch[Stop]) do
      Inc(Stop);
    if ((Index = 1) or CharInSet(ABranch[Index - 1], ['/', '-', '_', '#'])) and
      ((Stop > Length(ABranch)) or CharInSet(ABranch[Stop], ['-', '_'])) then
    begin
      Result := Copy(ABranch, Index, Stop - Index);
      // Führende Nullen gehören nicht zur Nummer.
      while (Length(Result) > 1) and (Result[1] = '0') do
        Delete(Result, 1, 1);
      if Result = '0' then
        Result := ''
      else
        Result := '#' + Result;
      Exit;
    end;
    Index := Stop;
  end;
end;

function YouTrackKeyOf(const AProject, ABranch: string): string;
var
  Upper, Project: string;
  Index, Start, Stop: Integer;
begin
  Result := '';
  Upper := UpperCase(ABranch);
  Project := UpperCase(Trim(AProject));
  Index := 1;
  while Index <= Length(Upper) do
  begin
    // Anfang eines Kürzels: Buchstabe am Anfang oder nach einem Zeichen, das kein Buchstabe und keine Ziffer ist.
    if not ((Upper[Index] >= 'A') and (Upper[Index] <= 'Z')) or ((Index > 1) and IsAsciiAlnum(Upper[Index - 1])) then
    begin
      Inc(Index);
      Continue;
    end;
    Start := Index;
    while (Index <= Length(Upper)) and IsAsciiAlnum(Upper[Index]) do
      Inc(Index);
    if (Index >= Length(Upper)) or (Upper[Index] <> '-') or not IsDigit(Upper[Index + 1]) then
      Continue;
    if (Project <> '') and (Copy(Upper, Start, Index - Start) <> Project) then
      Continue;
    Stop := Index + 1;
    while (Stop <= Length(Upper)) and IsDigit(Upper[Stop]) do
      Inc(Stop);
    if (Stop <= Length(Upper)) and IsAsciiAlnum(Upper[Stop]) then
    begin
      Index := Stop;
      Continue;
    end;
    Exit(Copy(Upper, Start, Stop - Start));
  end;
end;

class function TAtlasTrackerNaming.KeyOfBranch(const AProvider, AProject, ABranch: string): string;
begin
  Result := '';
  if SameText(AProvider, TAtlasTrackerTarget.GitHub) then
    Result := GitHubKeyOf(Trim(ABranch))
  else if SameText(AProvider, TAtlasTrackerTarget.YouTrack) then
    Result := YouTrackKeyOf(AProject, Trim(ABranch));
end;

end.
