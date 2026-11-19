unit Atlas.Common.History.Commits;

// Commits der Symbolgeschichte (#2641) zerlegen: erste Zeile der Nachricht, Issue-Kennungen, Datei und Einführung
// aus dem Unterschied von git log -L.
// - Kennungen ohne Einstellungen des Plugins: GitHub „#123“ und „owner/repo#123“ mit denselben Wortgrenzen wie
//   im Plugin (nicht nach „&“, nicht vor oder nach „#“/„$“, damit „&#123;“ und „#13#10“ keine Issues sind) und
//   ein Kürzel „ABC-123“ am Anfang der Nachricht (Commit-Präfix wie issues.commitPattern). Ein freies Kürzel mitten
//   im Text würde „UTF-8“ treffen.
// - Datei: „+++ b/<Pfad>“ im Unterschied, der Name in diesem Commit.
// - Commits mit Unterschied aus git log -L (cLineLogFormat), geänderte Dateien aus git show --name-status.
// - Einführung: Der Bereich war im Stand davor leer („@@ -0,0 …“ bzw. „@@ -57,0 …“, eingefügt in eine bestehende
//   Datei) und der Commit löscht keine Zeile darin.

interface

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Contract;

type
  TSymbolCommits = class
  public const
    /// <summary>--format für git log -L: Satz (#$1E), Commit, Autor, Unix-Zeit, Nachricht, je mit #$1F getrennt,
    /// danach der Unterschied.</summary>
    cLineLogFormat = '%x1e%H%x1f%an%x1f%ct%x1f%B%x1f';
  public
    /// <summary>Ausgabe von git log -L mit cLineLogFormat; unvollständige Sätze fallen weg.</summary>
    class function ParseLineLog(const AText: string): TArray<TSymbolLineCommit>; static;
    /// <summary>Erste nicht leere Zeile von AMessage ohne Leerraum.</summary>
    class function Summary(const AMessage: string): string; static;
    /// <summary>Kennungen in AMessage ohne Doppelte in der Reihenfolge des Auftretens.</summary>
    class function IssueKeys(const AMessage: string): TArray<string>; static;
    /// <summary>Datei nach dem Commit aus "+++ b/…"; '' ohne.</summary>
    class function PatchPath(const APatch: TArray<string>): string; static;
    /// <summary>Hat der Commit den Bereich angelegt?</summary>
    class function IsIntroduction(const APatch: TArray<string>): Boolean; static;
    /// <summary>Ausgabe von git show --format= --name-status -M: "M\tPfad", "A …", "D …", "R087\talt\tneu".
    /// </summary>
    class function ParseNameStatus(const AText: string): TArray<THotspotFileChange>; static;
  end;

implementation

uses
  System.StrUtils,
  System.DateUtils,
  System.Character;

class function TSymbolCommits.Summary(const AMessage: string): string;
var
  mLines: TArray<string>;
  mLine: string;
begin
  Result := '';
  mLines := AMessage.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for mLine in mLines do
  begin
    if Trim(mLine) <> '' then
    begin
      Exit(Trim(mLine));
    end;
  end;
end;

function IsWordChar(AChar: Char): Boolean;
begin
  Result := AChar.IsLetterOrDigit or (AChar = '_');
end;

function IsRepoChar(AChar: Char): Boolean;
begin
  Result := IsWordChar(AChar) or (AChar = '.') or (AChar = '-');
end;

function IsDigit(AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

/// <summary>Anfang von "owner/repo" direkt vor APos (Position von "#"); APos selbst ohne.</summary>
function RepositoryStart(const AText: string; APos: Integer): Integer;
var
  mPos: Integer;
begin
  Result := APos;
  mPos := APos - 1;
  while (mPos >= 1) and IsRepoChar(AText[mPos]) do
  begin
    Dec(mPos);
  end;
  if (mPos = APos - 1) or (mPos < 1) or (AText[mPos] <> '/') then
  begin
    Exit;
  end;
  Dec(mPos);
  if (mPos < 1) or not IsRepoChar(AText[mPos]) then
  begin
    Exit;
  end;
  while (mPos >= 1) and IsRepoChar(AText[mPos]) do
  begin
    Dec(mPos);
  end;
  Result := mPos + 1;
end;

/// <summary>Darf vor einer Kennung ab APos stehen?</summary>
function FreeBefore(const AText: string; APos: Integer): Boolean;
begin
  Result := (APos = 1) or not (IsWordChar(AText[APos - 1]) or CharInSet(AText[APos - 1], ['&', '#', '$', '/']));
end;

/// <summary>GitHub-Kennung mit "#" an APos; '' ohne. AEnd: Position hinter der Kennung.</summary>
function GitHubKey(const AText: string; APos: Integer; out AEnd: Integer): string;
var
  mStart: Integer;
begin
  Result := '';
  AEnd := APos + 1;
  while (AEnd <= Length(AText)) and IsDigit(AText[AEnd]) do
  begin
    Inc(AEnd);
  end;
  if (AEnd = APos + 1) or ((AEnd <= Length(AText)) and (IsWordChar(AText[AEnd]) or
    CharInSet(AText[AEnd], ['#', '$']))) then
  begin
    Exit;
  end;
  mStart := RepositoryStart(AText, APos);
  if FreeBefore(AText, mStart) then
  begin
    Result := Copy(AText, mStart, AEnd - mStart);
  end
  else if (mStart < APos) and FreeBefore(AText, APos) then
  begin
    Result := Copy(AText, APos, AEnd - APos);
  end;
end;

/// <summary>Kürzel "ABC-123" am Anfang von AText; '' ohne.</summary>
function PrefixKey(const AText: string): string;
var
  mPos, mDigits: Integer;
begin
  Result := '';
  mPos := 1;
  while (mPos <= Length(AText)) and (CharInSet(AText[mPos], ['A'..'Z']) or ((mPos > 1) and IsDigit(AText[mPos]))) do
  begin
    Inc(mPos);
  end;
  if (mPos < 3) or (mPos > Length(AText)) or (AText[mPos] <> '-') then
  begin
    Exit;
  end;
  mDigits := mPos + 1;
  while (mDigits <= Length(AText)) and IsDigit(AText[mDigits]) do
  begin
    Inc(mDigits);
  end;
  if (mDigits > mPos + 1) and ((mDigits > Length(AText)) or not IsWordChar(AText[mDigits])) then
  begin
    Result := Copy(AText, 1, mDigits - 1);
  end;
end;

procedure AddKey(var AKeys: TArray<string>; const AKey: string);
var
  mKey: string;
begin
  for mKey in AKeys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit;
    end;
  end;
  AKeys := AKeys + [AKey];
end;

class function TSymbolCommits.IssueKeys(const AMessage: string): TArray<string>;
var
  mPos, mEnd: Integer;
  mKey: string;
begin
  Result := nil;
  mKey := PrefixKey(TrimLeft(AMessage));
  if mKey <> '' then
  begin
    AddKey(Result, mKey);
  end;
  mPos := Pos('#', AMessage);
  while mPos > 0 do
  begin
    mKey := GitHubKey(AMessage, mPos, mEnd);
    if mKey <> '' then
    begin
      AddKey(Result, mKey);
    end;
    mPos := PosEx('#', AMessage, mPos + 1);
  end;
end;

class function TSymbolCommits.PatchPath(const APatch: TArray<string>): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in APatch do
  begin
    if StartsStr('+++ b/', mLine) then
    begin
      Exit(TrimRight(Copy(mLine, 7, MaxInt)));
    end;
  end;
end;

/// <summary>Kopf eines Abschnitts, der im Stand davor keine Zeile hatte: "@@ -0,0 +4,12 @@" oder "@@ -57,0 +58,17 @@".
/// </summary>
function IsEmptyHunk(const ALine: string): Boolean;
var
  mPos: Integer;
begin
  Result := False;
  if not StartsStr('@@ -', ALine) then
  begin
    Exit;
  end;
  mPos := 5;
  while (mPos <= Length(ALine)) and IsDigit(ALine[mPos]) do
  begin
    Inc(mPos);
  end;
  Result := (mPos > 5) and (Copy(ALine, mPos, 4) = ',0 +');
end;

class function TSymbolCommits.IsIntroduction(const APatch: TArray<string>): Boolean;
var
  mLine: string;
begin
  Result := False;
  for mLine in APatch do
  begin
    if IsEmptyHunk(mLine) then
    begin
      Result := True;
    end
    else if StartsStr('-', mLine) and not StartsStr('---', mLine) then
    begin
      Exit(False);
    end;
  end;
end;

class function TSymbolCommits.ParseNameStatus(const AText: string): TArray<THotspotFileChange>;
var
  mLine: string;
  mParts: TArray<string>;
  mKind: THotspotChangeKind;
begin
  Result := nil;
  for mLine in AText.Replace(#13#10, #10).Split([#10]) do
  begin
    mParts := mLine.Split([#9]);
    if (Length(mParts) < 2) or (mParts[0] = '') then
    begin
      Continue;
    end;
    case UpCase(mParts[0][1]) of
      'A':
        mKind := THotspotChangeKind.Added;
      'D':
        mKind := THotspotChangeKind.Deleted;
      'R':
        mKind := THotspotChangeKind.Renamed;
    else
      mKind := THotspotChangeKind.Modified;
    end;
    if (mKind = THotspotChangeKind.Renamed) and (Length(mParts) >= 3) then
    begin
      Result := Result + [THotspotFileChange.Make(mParts[2], mParts[1], mKind, -1, -1)];
    end
    else
    begin
      Result := Result + [THotspotFileChange.Make(mParts[High(mParts)], '', mKind, -1, -1)];
    end;
  end;
end;

/// <summary>Ein Satz aus git log -L ohne das führende #$1E; False, wenn Felder fehlen.</summary>
function ParseLineRecord(const ARecord: string; out ACommit: TSymbolLineCommit): Boolean;
var
  mFields: TArray<string>;
  mSeconds: Int64;
begin
  ACommit := Default(TSymbolLineCommit);
  mFields := ARecord.Split([#$1F]);
  Result := (Length(mFields) >= 5) and TryStrToInt64(Trim(mFields[2]), mSeconds);
  if not Result then
  begin
    Exit;
  end;
  ACommit.Revision := Trim(mFields[0]);
  ACommit.Author := mFields[1];
  ACommit.Date := UnixToDateTime(mSeconds, True);
  ACommit.Message := TrimRight(mFields[3]);
  ACommit.Patch := Trim(mFields[4]).Replace(#13#10, #10).Split([#10]);
end;

class function TSymbolCommits.ParseLineLog(const AText: string): TArray<TSymbolLineCommit>;
var
  mRecord: string;
  mCommit: TSymbolLineCommit;
begin
  Result := nil;
  for mRecord in AText.Split([#$1E]) do
  begin
    if (Trim(mRecord) <> '') and ParseLineRecord(mRecord, mCommit) then
    begin
      Result := Result + [mCommit];
    end;
  end;
end;

end.
