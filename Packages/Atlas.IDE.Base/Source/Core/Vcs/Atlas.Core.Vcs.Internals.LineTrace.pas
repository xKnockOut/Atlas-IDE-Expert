unit Atlas.Core.Vcs.Internals.LineTrace;

// Zeilenbereich rückwärts durch Revisionen verfolgen (#1275). Git kann das
// selbst (log -L); SVN nicht. Für SVN liest Atlas einmal „svn log --diff“
// (je Revision der Unterschied der Datei, neueste zuerst) und geht damit
// zurück:
// - Touches: Ändert eine Revision den Bereich? Ja, wenn sie eine Zeile im
//   Bereich hinzufügt (auch geänderte Zeilen sind „-“ und „+“) oder zwischen
//   zwei Zeilen des Bereichs etwas löscht.
// - MapBack: Wo lag der Bereich vor der Revision? Unveränderte Zeilen haben
//   eine Zeile im alten Stand; vom ersten Ende geht es zur nächsten alten
//   Zeile, vom letzten zur vorigen. Hat die Revision den Bereich ganz
//   hinzugefügt, gab es ihn davor nicht: Die Suche endet.
// Zeilen sind 1-basiert wie im Unified-Diff. Ein Block „@@ -a,0 +b,n @@“ fügt
// hinter der alten Zeile a ein, „@@ -a,n +b,0 @@“ löscht hinter der neuen
// Zeile b.

interface

uses
  System.SysUtils;

type
  /// <summary>Block eines Unified-Diffs.</summary>
  TAtlasVcsHunk = record
    OldStart: Integer;
    OldCount: Integer;
    NewStart: Integer;
    NewCount: Integer;
    /// <summary>Zeilen des Blocks mit dem Zeichen vorn (" ", "+", "-"); „\ No newline …“ entfällt.</summary>
    Lines: TArray<string>;
  end;

  TAtlasVcsLineTrace = class
  public
    /// <summary>"@@ -a,b +c,d @@ …" (fehlende Anzahl = 1); False bei anderem Text.</summary>
    class function ParseHunkHeader(const ALine: string; out AHunk: TAtlasVcsHunk): Boolean; static;
    /// <summary>Blöcke eines Unified-Diffs; Kopfzeilen (Index:, ===, ---, +++) und Eigenschaften dazwischen
    /// entfallen. Ein Block endet, sobald seine Zeilenzahlen erreicht sind.</summary>
    class function ParseHunks(const ALines: TArray<string>): TArray<TAtlasVcsHunk>; static;
    /// <summary>Ändern AHunks den Bereich AFirst..ALast (Zählung nach der Änderung)?</summary>
    class function Touches(const AHunks: TArray<TAtlasVcsHunk>; AFirst, ALast: Integer): Boolean; static;
    /// <summary>Bereich vor der Änderung; False, wenn AHunks ihn ganz hinzugefügt haben.</summary>
    class function MapBack(const AHunks: TArray<TAtlasVcsHunk>; var AFirst, ALast: Integer): Boolean; static;
    /// <summary>Indizes der Revisionen aus APatches (Unterschiede, neueste zuerst), die AFirst..ALast (Stand nach
    /// der neuesten) geändert haben; endet, wo der Bereich entstand.</summary>
    class function Trace(const APatches: TArray<TArray<string>>; AFirst, ALast: Integer): TArray<Integer>; static;
  end;

implementation

function ReadNumber(const AText: string; var APos: Integer; out AValue: Integer): Boolean;
var
  mStart: Integer;
begin
  mStart := APos;
  while (APos <= Length(AText)) and CharInSet(AText[APos], ['0'..'9']) do
    Inc(APos);
  Result := (APos > mStart) and (APos - mStart <= 9);
  if Result then
    AValue := StrToInt(Copy(AText, mStart, APos - mStart))
  else
    AValue := 0;
end;

/// <summary>"a" oder "a,b" ab APos; ohne Anzahl 1.</summary>
function ReadRange(const AText: string; var APos: Integer; out AStart, ACount: Integer): Boolean;
begin
  ACount := 1;
  Result := ReadNumber(AText, APos, AStart);
  if Result and (APos <= Length(AText)) and (AText[APos] = ',') then
  begin
    Inc(APos);
    Result := ReadNumber(AText, APos, ACount);
  end;
end;

/// <summary>Erste neue bzw. alte Zeile eines Blocks; bei Anzahl 0 die Stelle hinter der genannten Zeile.</summary>
function FirstOf(AStart, ACount: Integer): Integer;
begin
  Result := AStart;
  if ACount = 0 then
    Result := AStart + 1;
end;

{ TAtlasVcsLineTrace }

class function TAtlasVcsLineTrace.ParseHunkHeader(const ALine: string; out AHunk: TAtlasVcsHunk): Boolean;
var
  mPos: Integer;
begin
  AHunk := Default(TAtlasVcsHunk);
  Result := False;
  if Copy(ALine, 1, 4) <> '@@ -' then
    Exit;
  mPos := 5;
  if not ReadRange(ALine, mPos, AHunk.OldStart, AHunk.OldCount) then
    Exit;
  if Copy(ALine, mPos, 2) <> ' +' then
    Exit;
  Inc(mPos, 2);
  if not ReadRange(ALine, mPos, AHunk.NewStart, AHunk.NewCount) then
    Exit;
  Result := Copy(ALine, mPos, 3) = ' @@';
end;

class function TAtlasVcsLineTrace.ParseHunks(const ALines: TArray<string>): TArray<TAtlasVcsHunk>;
var
  mIndex, mOld, mNew, mCount, mFound: Integer;
  mHunk: TAtlasVcsHunk;
  mLine: string;
begin
  // Die Zahl der Blöcke ist vorher unbekannt: Platz verdoppeln, am Ende kürzen.
  Result := nil;
  mFound := 0;
  mIndex := 0;
  while mIndex < Length(ALines) do
  begin
    if not ParseHunkHeader(ALines[mIndex], mHunk) then
    begin
      Inc(mIndex);
      Continue;
    end;
    Inc(mIndex);
    mOld := mHunk.OldCount;
    mNew := mHunk.NewCount;
    mCount := 0;
    SetLength(mHunk.Lines, mOld + mNew);
    while (mIndex < Length(ALines)) and ((mOld > 0) or (mNew > 0)) do
    begin
      mLine := ALines[mIndex];
      Inc(mIndex);
      // Manche Werkzeuge kürzen die Leerzeile im Kontext auf "".
      if mLine = '' then
        mLine := ' ';
      case mLine[1] of
        ' ':
          begin
            Dec(mOld);
            Dec(mNew);
          end;
        '-':
          Dec(mOld);
        '+':
          Dec(mNew);
        '\':
          Continue;
      else
        // Kaputter Block: hier aufhören, die Zeile neu ansehen.
        Dec(mIndex);
        Break;
      end;
      mHunk.Lines[mCount] := mLine;
      Inc(mCount);
    end;
    SetLength(mHunk.Lines, mCount);
    if mFound = Length(Result) then
      SetLength(Result, mFound * 2 + 4);
    Result[mFound] := mHunk;
    Inc(mFound);
  end;
  SetLength(Result, mFound);
end;

class function TAtlasVcsLineTrace.Touches(const AHunks: TArray<TAtlasVcsHunk>; AFirst, ALast: Integer): Boolean;
var
  mHunk: TAtlasVcsHunk;
  mLine: string;
  mNew: Integer;
begin
  Result := False;
  for mHunk in AHunks do
  begin
    mNew := FirstOf(mHunk.NewStart, mHunk.NewCount);
    if mNew > ALast + 1 then
      Break;
    for mLine in mHunk.Lines do
      case mLine[1] of
        ' ':
          Inc(mNew);
        '+':
          begin
            if (mNew >= AFirst) and (mNew <= ALast) then
              Exit(True);
            Inc(mNew);
          end;
        '-':
          // Gelöscht vor der neuen Zeile mNew: nur zwischen zwei Zeilen des Bereichs.
          if (mNew > AFirst) and (mNew <= ALast) then
            Exit(True);
      end;
  end;
end;

/// <summary>Alte Zeile zur neuen Zeile ALine; hinzugefügte Zeilen gehen bei AForward zur nächsten alten Zeile,
/// sonst zur vorigen.</summary>
function OldLineOf(const AHunks: TArray<TAtlasVcsHunk>; ALine: Integer; AForward: Boolean): Integer;
var
  mHunk: TAtlasVcsHunk;
  mLine: string;
  mOld, mNew, mDelta: Integer;
begin
  mDelta := 0;
  for mHunk in AHunks do
  begin
    mNew := FirstOf(mHunk.NewStart, mHunk.NewCount);
    if ALine < mNew then
      Break;
    mOld := FirstOf(mHunk.OldStart, mHunk.OldCount);
    for mLine in mHunk.Lines do
      case mLine[1] of
        ' ':
          begin
            if mNew = ALine then
              Exit(mOld);
            Inc(mOld);
            Inc(mNew);
          end;
        '-':
          Inc(mOld);
        '+':
          begin
            if mNew = ALine then
            begin
              if AForward then
                Exit(mOld);
              Exit(mOld - 1);
            end;
            Inc(mNew);
          end;
      end;
    mDelta := mOld - mNew;
  end;
  Result := ALine + mDelta;
end;

class function TAtlasVcsLineTrace.MapBack(const AHunks: TArray<TAtlasVcsHunk>; var AFirst, ALast: Integer): Boolean;
var
  mFirst, mLast: Integer;
begin
  mFirst := OldLineOf(AHunks, AFirst, True);
  mLast := OldLineOf(AHunks, ALast, False);
  Result := (mFirst <= mLast) and (mLast >= 1);
  if not Result then
    Exit;
  AFirst := mFirst;
  ALast := mLast;
end;

class function TAtlasVcsLineTrace.Trace(const APatches: TArray<TArray<string>>; AFirst, ALast: Integer):
  TArray<Integer>;
var
  mIndex, mFirst, mLast, mFound: Integer;
  mHunks: TArray<TAtlasVcsHunk>;
begin
  // Höchstens ein Eintrag je Patch: Länge vorab, am Ende kürzen.
  Result := nil;
  SetLength(Result, Length(APatches));
  mFound := 0;
  mFirst := AFirst;
  mLast := ALast;
  for mIndex := 0 to High(APatches) do
  begin
    mHunks := ParseHunks(APatches[mIndex]);
    if Touches(mHunks, mFirst, mLast) then
    begin
      Result[mFound] := mIndex;
      Inc(mFound);
    end;
    if not MapBack(mHunks, mFirst, mLast) then
      Break;
  end;
  SetLength(Result, mFound);
end;

end.
