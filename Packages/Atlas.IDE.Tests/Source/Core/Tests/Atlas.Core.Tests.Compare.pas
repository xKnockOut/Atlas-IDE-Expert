unit Atlas.Core.Tests.Compare;

// Erwartet und erhalten eines fehlgeschlagenen Tests vergleichen (#1779,
// tests.compare), ohne VCL und Open Tools API, auch unter FPC prüfbar:
// - FormatOf, PrettyJson, PrettyXml: Sind beide Werte JSON bzw. XML, rückt
//   Build sie gleich ein (tests.compare.format), damit der Unterschied in
//   einer eigenen Zeile steht statt irgendwo in einer langen.
// - VisibleLines: Zeilen mit sichtbarem Leerraum: Tab „→“, Leerzeichen am
//   Zeilenende „·“, Zeilenende „↵“ (LF) bzw. „␍↵“ (CRLF) und „␍“ (CR allein).
//   Ein Unterschied nur im Zeilenende oder in nachgestellten Leerzeichen wird
//   so zu einem sichtbaren Zeichen.
// - Build: Zeilen über Atlas.Text.Diff einander zuordnen; geänderte Zeilen
//   paarweise mit dem abweichenden Zeichenbereich (gleicher Anfang und gleiches
//   Ende abgezogen), übrige als entfernt bzw. hinzugefügt mit Lücke
//   gegenüber.
// - IsTruncated: Werte, die mit „...“ bzw. „…“ enden, gelten als gekürzt.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Art einer Zeile im Vergleich: gleich, geändert (beide Seiten), nur erwartet, nur erhalten.</summary>
  TAtlasCompareKind = (Same, Changed, Removed, Added);
  TAtlasCompareFormat = (Plain, Json, Xml);

  /// <summary>Eine Zeile beider Seiten; ohne Zeile auf einer Seite ist HasLeft bzw. HasRight False (Lücke).
  /// </summary>
  TAtlasCompareRow = record
    Kind: TAtlasCompareKind;
    Left: string;
    Right: string;
    HasLeft: Boolean;
    HasRight: Boolean;
    /// <summary>Abweichender Bereich einer geänderten Zeile (0-basiert); Länge 0 = keiner.</summary>
    LeftStart: Integer;
    LeftLength: Integer;
    RightStart: Integer;
    RightLength: Integer;
  end;

  TAtlasCompareResult = record
    Rows: TArray<TAtlasCompareRow>;
    /// <summary>Beide Seiten als JSON bzw. XML eingerückt; Plain = unverändert.</summary>
    Format: TAtlasCompareFormat;
    ExpectedTruncated: Boolean;
    ActualTruncated: Boolean;
    /// <summary>Zeilen, die nicht gleich sind.</summary>
    function Differences: Integer;
  end;

  TAtlasTestCompare = class
  public const
    cTab = '→';
    cTrailingSpace = '·';
    cLineFeed = '↵';
    cCarriageReturn = '␍';
    cIndent = '  ';
  public
    /// <summary>JSON (Objekt oder Liste), XML (Element) oder anderes.</summary>
    class function FormatOf(const AText: string): TAtlasCompareFormat; static;
    /// <summary>JSON eingerückt, ein Wert je Zeile; Strings bleiben unverändert.</summary>
    class function PrettyJson(const AText: string): string; static;
    /// <summary>XML eingerückt, ein Element je Zeile; Element mit nur Text bleibt in einer Zeile.</summary>
    class function PrettyXml(const AText: string): string; static;
    /// <summary>Zeilen mit sichtbarem Leerraum (Tab, Leerzeichen am Ende, Zeilenende).</summary>
    class function VisibleLines(const AText: string): TArray<string>; static;
    /// <summary>Abweichender Bereich zweier Zeilen nach gleichem Anfang und Ende.</summary>
    class procedure DiffRange(const AOld, ANew: string; out AOldStart, AOldLength, ANewStart,
      ANewLength: Integer); static;
    /// <summary>Hat DUnitX den Wert gekürzt (endet mit „...“ bzw. „…“)?</summary>
    class function IsTruncated(const AText: string): Boolean; static;
    /// <summary>Vergleich von AExpected und AActual; AFormat rückt gleichartiges JSON bzw. XML ein.</summary>
    class function Build(const AExpected, AActual: string; AFormat: Boolean): TAtlasCompareResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Diff;

const
  cNewLine = #10;

/// <summary>AText ACount-mal; eigene Routine, weil DupeString unter FPC über AnsiString geht (Zeichen wie „·“).
/// </summary>
function Repeated(const AText: string; ACount: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to ACount do
  begin
    Result := Result + AText;
  end;
end;

{ TAtlasCompareResult }

function TAtlasCompareResult.Differences: Integer;
var
  mRow: TAtlasCompareRow;
begin
  Result := 0;
  for mRow in Rows do
  begin
    if mRow.Kind <> TAtlasCompareKind.Same then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasTestCompare }

class function TAtlasTestCompare.FormatOf(const AText: string): TAtlasCompareFormat;
var
  mText: string;
begin
  Result := TAtlasCompareFormat.Plain;
  mText := Trim(AText);
  if Length(mText) < 2 then
  begin
    Exit;
  end;
  if ((mText[1] = '{') and (mText[Length(mText)] = '}')) or ((mText[1] = '[') and (mText[Length(mText)] = ']')) then
  begin
    Result := TAtlasCompareFormat.Json;
  end
  else if (mText[1] = '<') and (mText[Length(mText)] = '>') then
  begin
    Result := TAtlasCompareFormat.Xml;
  end;
end;

function Indent(ADepth: Integer): string;
begin
  Result := cNewLine + Repeated(TAtlasTestCompare.cIndent, Max(0, ADepth));
end;

/// <summary>Nächstes Zeichen ab AIndex, das kein Leerraum ist; #0 am Ende. AIndex zeigt danach darauf.</summary>
function NextSolid(const AText: string; var AIndex: Integer): Char;
begin
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], [' ', #9, #13, #10]) do
  begin
    Inc(AIndex);
  end;
  Result := #0;
  if AIndex <= Length(AText) then
  begin
    Result := AText[AIndex];
  end;
end;

/// <summary>JSON-String ab AIndex (auf dem Anführungszeichen) an AResult hängen; AIndex danach auf dem
/// schließenden Zeichen.</summary>
procedure CopyJsonString(const AText: string; var AIndex: Integer; var AResult: string);
var
  mEnd: Integer;
begin
  mEnd := AIndex + 1;
  while (mEnd <= Length(AText)) and (AText[mEnd] <> '"') do
  begin
    // Maskiertes Zeichen (\" \\) überspringen.
    if AText[mEnd] = '\' then
    begin
      Inc(mEnd);
    end;
    Inc(mEnd);
  end;
  mEnd := Min(mEnd, Length(AText));
  AResult := AResult + Copy(AText, AIndex, mEnd - AIndex + 1);
  AIndex := mEnd;
end;

/// <summary>Öffnende Klammer: leeres {} bzw. [] bleibt zusammen, sonst neue Zeile und tiefer.</summary>
procedure OpenJson(const AText: string; var AIndex, ADepth: Integer; var AResult: string);
var
  mNext: Integer;
  mChar: Char;
begin
  AResult := AResult + AText[AIndex];
  mNext := AIndex + 1;
  mChar := NextSolid(AText, mNext);
  if ((AText[AIndex] = '{') and (mChar = '}')) or ((AText[AIndex] = '[') and (mChar = ']')) then
  begin
    AResult := AResult + mChar;
    AIndex := mNext;
    Exit;
  end;
  Inc(ADepth);
  AResult := AResult + Indent(ADepth);
end;

class function TAtlasTestCompare.PrettyJson(const AText: string): string;
var
  mIndex, mDepth: Integer;
  mChar: Char;
begin
  Result := '';
  mDepth := 0;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mChar := AText[mIndex];
    case mChar of
      '"':
        CopyJsonString(AText, mIndex, Result);
      '{', '[':
        OpenJson(AText, mIndex, mDepth, Result);
      '}', ']':
        begin
          Dec(mDepth);
          Result := Result + Indent(mDepth) + mChar;
        end;
      ',':
        Result := Result + mChar + Indent(mDepth);
      ':':
        Result := Result + ': ';
      ' ', #9, #13, #10:
        ;
    else
      Result := Result + mChar;
    end;
    Inc(mIndex);
  end;
end;

const
  cXmlComment = '<!--';
  cXmlCData = '<![CDATA[';
  // Element mit nur Text: öffnende Marke, Text, schließende Marke.
  cTextElementTokens = 3;

/// <summary>Position hinter der Marke, die bei AIndex beginnt; Kommentare und CDATA bis zu ihrem Ende.</summary>
function TagEnd(const AText: string; AIndex: Integer): Integer;
var
  mClose: string;
begin
  mClose := '>';
  if Copy(AText, AIndex, Length(cXmlComment)) = cXmlComment then
  begin
    mClose := '-->';
  end
  else if Copy(AText, AIndex, Length(cXmlCData)) = cXmlCData then
  begin
    mClose := ']]>';
  end;
  Result := Pos(mClose, AText, AIndex + 1);
  if Result = 0 then
  begin
    Exit(Length(AText) + 1);
  end;
  Result := Result + Length(mClose);
end;

/// <summary>XML in Marken und Text zerlegen; Kommentare und CDATA bleiben eine Marke.</summary>
function XmlTokens(const AText: string): TArray<string>;
var
  mIndex, mEnd: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '<' then
    begin
      mEnd := TagEnd(AText, mIndex);
      Result := Result + [Copy(AText, mIndex, mEnd - mIndex)];
      mIndex := mEnd;
    end
    else
    begin
      mEnd := Pos('<', AText, mIndex);
      if mEnd = 0 then
      begin
        mEnd := Length(AText) + 1;
      end;
      if Trim(Copy(AText, mIndex, mEnd - mIndex)) <> '' then
      begin
        Result := Result + [Trim(Copy(AText, mIndex, mEnd - mIndex))];
      end;
      mIndex := mEnd;
    end;
  end;
end;

function IsTag(const AToken: string): Boolean;
begin
  Result := (AToken <> '') and (AToken[1] = '<');
end;

/// <summary>Öffnende Marke eines Elements (nicht schließend, nicht leer, keine Deklaration oder Kommentar)?</summary>
function IsOpening(const AToken: string): Boolean;
begin
  Result := IsTag(AToken) and (Length(AToken) > 2) and not CharInSet(AToken[2], ['/', '?', '!']) and
    not AToken.EndsWith('/>');
end;

class function TAtlasTestCompare.PrettyXml(const AText: string): string;
var
  mTokens: TArray<string>;
  mIndex, mDepth: Integer;
  mLines: TArray<string>;
begin
  mTokens := XmlTokens(AText);
  mLines := nil;
  mDepth := 0;
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    if IsOpening(mTokens[mIndex]) and (mIndex + 2 <= High(mTokens)) and not IsTag(mTokens[mIndex + 1]) and
      mTokens[mIndex + 2].StartsWith('</') then
    begin
      // Element mit nur Text: eine Zeile.
      mLines := mLines + [Repeated(cIndent, mDepth) + mTokens[mIndex] + mTokens[mIndex + 1] + mTokens[mIndex + 2]];
      Inc(mIndex, cTextElementTokens);
      Continue;
    end;
    if mTokens[mIndex].StartsWith('</') then
    begin
      mDepth := Max(0, mDepth - 1);
    end;
    mLines := mLines + [Repeated(cIndent, mDepth) + mTokens[mIndex]];
    if IsOpening(mTokens[mIndex]) then
    begin
      Inc(mDepth);
    end;
    Inc(mIndex);
  end;
  Result := string.Join(cNewLine, mLines);
end;

/// <summary>Leerzeichen am Ende sichtbar, Tabs überall.</summary>
function ShowSpaces(const ALine: string): string;
var
  mEnd: Integer;
begin
  mEnd := Length(ALine);
  while (mEnd > 0) and (ALine[mEnd] = ' ') do
  begin
    Dec(mEnd);
  end;
  Result := Copy(ALine, 1, mEnd) + Repeated(TAtlasTestCompare.cTrailingSpace, Length(ALine) - mEnd);
  Result := StringReplace(Result, #9, TAtlasTestCompare.cTab, [rfReplaceAll]);
end;

class function TAtlasTestCompare.VisibleLines(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
  mMark: string;
begin
  Result := nil;
  mStart := 1;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mMark := '';
    if AText[mIndex] = #10 then
    begin
      mMark := cLineFeed;
    end
    else if (AText[mIndex] = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
    begin
      mMark := cCarriageReturn + cLineFeed;
    end
    else if AText[mIndex] = #13 then
    begin
      mMark := cCarriageReturn;
    end;
    if mMark = '' then
    begin
      Inc(mIndex);
      Continue;
    end;
    Result := Result + [ShowSpaces(Copy(AText, mStart, mIndex - mStart)) + mMark];
    // CRLF: zwei Zeichen.
    Inc(mIndex, Length(mMark));
    mStart := mIndex;
  end;
  Result := Result + [ShowSpaces(Copy(AText, mStart, MaxInt))];
end;

class procedure TAtlasTestCompare.DiffRange(const AOld, ANew: string; out AOldStart, AOldLength, ANewStart,
  ANewLength: Integer);
var
  mPrefix, mSuffix: Integer;
begin
  mPrefix := 0;
  while (mPrefix < Min(Length(AOld), Length(ANew))) and (AOld[mPrefix + 1] = ANew[mPrefix + 1]) do
  begin
    Inc(mPrefix);
  end;
  mSuffix := 0;
  while (mSuffix < Min(Length(AOld), Length(ANew)) - mPrefix) and
    (AOld[Length(AOld) - mSuffix] = ANew[Length(ANew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  AOldStart := mPrefix;
  AOldLength := Length(AOld) - mPrefix - mSuffix;
  ANewStart := mPrefix;
  ANewLength := Length(ANew) - mPrefix - mSuffix;
end;

class function TAtlasTestCompare.IsTruncated(const AText: string): Boolean;
begin
  Result := AText.EndsWith('...') or AText.EndsWith('…');
end;

function SameRow(const ALine: string): TAtlasCompareRow;
begin
  Result := Default(TAtlasCompareRow);
  Result.Kind := TAtlasCompareKind.Same;
  Result.Left := ALine;
  Result.Right := ALine;
  Result.HasLeft := True;
  Result.HasRight := True;
end;

function ChangedRow(const AOld, ANew: string): TAtlasCompareRow;
begin
  Result := SameRow(AOld);
  Result.Kind := TAtlasCompareKind.Changed;
  Result.Right := ANew;
  TAtlasTestCompare.DiffRange(AOld, ANew, Result.LeftStart, Result.LeftLength, Result.RightStart,
    Result.RightLength);
end;

function OneSided(const ALine: string; ALeft: Boolean): TAtlasCompareRow;
begin
  Result := Default(TAtlasCompareRow);
  if ALeft then
  begin
    Result.Kind := TAtlasCompareKind.Removed;
    Result.Left := ALine;
    Result.HasLeft := True;
    Result.LeftLength := Length(ALine);
  end
  else
  begin
    Result.Kind := TAtlasCompareKind.Added;
    Result.Right := ALine;
    Result.HasRight := True;
    Result.RightLength := Length(ALine);
  end;
end;

/// <summary>Zeilen eines geänderten Blocks: paarweise geändert, der Rest einseitig.</summary>
function HunkRows(const AOld, ANew: TArray<string>; const AHunk: TTextLineHunk): TArray<TAtlasCompareRow>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to Max(AHunk.OldCount, AHunk.NewCount) - 1 do
  begin
    if (mIndex < AHunk.OldCount) and (mIndex < AHunk.NewCount) then
    begin
      Result := Result + [ChangedRow(AOld[AHunk.OldStart + mIndex], ANew[AHunk.NewStart + mIndex])];
    end
    else if mIndex < AHunk.OldCount then
    begin
      Result := Result + [OneSided(AOld[AHunk.OldStart + mIndex], True)];
    end
    else
    begin
      Result := Result + [OneSided(ANew[AHunk.NewStart + mIndex], False)];
    end;
  end;
end;

class function TAtlasTestCompare.Build(const AExpected, AActual: string; AFormat: Boolean): TAtlasCompareResult;
var
  mExpected, mActual: string;
  mOld, mNew: TArray<string>;
  mHunk: TTextLineHunk;
  mOldIndex: Integer;
begin
  Result := Default(TAtlasCompareResult);
  Result.ExpectedTruncated := IsTruncated(AExpected);
  Result.ActualTruncated := IsTruncated(AActual);
  mExpected := AExpected;
  mActual := AActual;
  if AFormat and (FormatOf(AExpected) = FormatOf(AActual)) then
  begin
    Result.Format := FormatOf(AExpected);
    case Result.Format of
      TAtlasCompareFormat.Plain:
        ;
      TAtlasCompareFormat.Json:
        begin
          mExpected := PrettyJson(AExpected);
          mActual := PrettyJson(AActual);
        end;
      TAtlasCompareFormat.Xml:
        begin
          mExpected := PrettyXml(AExpected);
          mActual := PrettyXml(AActual);
        end;
    end;
  end;
  mOld := VisibleLines(mExpected);
  mNew := VisibleLines(mActual);
  mOldIndex := 0;
  for mHunk in TTextDiff.Hunks(mOld, mNew) do
  begin
    while mOldIndex < mHunk.OldStart do
    begin
      Result.Rows := Result.Rows + [SameRow(mOld[mOldIndex])];
      Inc(mOldIndex);
    end;
    Result.Rows := Result.Rows + HunkRows(mOld, mNew, mHunk);
    mOldIndex := mHunk.OldStart + mHunk.OldCount;
  end;
  while mOldIndex <= High(mOld) do
  begin
    Result.Rows := Result.Rows + [SameRow(mOld[mOldIndex])];
    Inc(mOldIndex);
  end;
end;

end.
