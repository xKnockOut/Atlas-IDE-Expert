unit Atlas.Common.Editing.TypeComments;

// Kommentar über dem Abschnitt eines Typs im implementation-Teil (#1835).
// Vier Formen (classCompletion.typeComment):
//   brace    { TKunde }                       wie die IDE
//   line     //----- / // TKunde / //-----     Trennlinie über drei Zeilen
//   summary  { TKunde: Kurzbeschreibung }      erste Zeile der <summary> der Klasse
//   region   {$REGION 'TKunde'} … {$ENDREGION} um alle Rümpfe des Typs
// Find erkennt jede Form über dem ersten Rumpf eines Typs (auch (* TKunde *)
// und // TKunde), Header schreibt die gewählte. Renamed ersetzt den Typnamen
// in einer Kopfzeile, NameSpots findet ihn in allen Kopfzeilen über Rümpfen
// des Typs (Umbenennen, #1838).

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Form des Kommentars über dem Abschnitt eines Typs.</summary>
  TTypeCommentStyle = (Off, Brace, Line, Summary, Region);
  {$SCOPEDENUMS OFF}

  /// <summary>Gefundener Kommentar über den Rümpfen eines Typs.</summary>
  TTypeComment = record
    /// <summary>Erste und letzte Zeile des Kopfs (ab 0); -1 ohne.</summary>
    First, Last: Integer;
    /// <summary>Zeile von {$ENDREGION} bei der Form Region, sonst -1.</summary>
    RegionEnd: Integer;
    Style: TTypeCommentStyle;
    function Found: Boolean;
    /// <summary>Gehört ALine zum Kommentar (Kopf oder Ende der Region)?</summary>
    function Covers(ALine: Integer): Boolean;
    class function None: TTypeComment; static;
  end;

  /// <summary>Stelle des Typnamens in einem Typkommentar (Zeile und Spalte ab 0).</summary>
  TTypeNameSpot = record
    Line, Character: Integer;
  end;

  TTypeComments = class
  public const
    cRegionEndText = '{$ENDREGION}';
    /// <summary>Breite der Trennlinie ohne Formatierer-Vorgabe.</summary>
    cDefaultLineLength = 80;
  public
    /// <summary>brace, line, summary, region, off; unbekannt oder leer: Brace.</summary>
    class function StyleOf(const AName: string): TTypeCommentStyle; static;
    class function StyleName(AStyle: TTypeCommentStyle): string; static;
    /// <summary>Kommentar für ATypeName über AFirstLine (Leerzeilen dazwischen erlaubt); bei einer Region muss
    /// hinter ALastLine (Leerzeilen erlaubt) {$ENDREGION} stehen.</summary>
    class function Find(const ALines: TArray<string>; AFirstLine, ALastLine: Integer;
      const ATypeName: string): TTypeComment; static;
    /// <summary>Zeilen des Kommentars ohne Leerzeilen; bei Region nur {$REGION …}. Summary ohne Text wie Brace.
    /// </summary>
    class function Header(AStyle: TTypeCommentStyle; const ATypeName, ASummary: string;
      ALineLength: Integer): TArray<string>; static;
    /// <summary>Erste Zeile der &lt;summary&gt; im Doku-Kommentar über ATypeLine (/// oder {** **}); '' ohne.
    /// </summary>
    class function SummaryAbove(const ALines: TArray<string>; ATypeLine: Integer): string; static;
    /// <summary>Ersetzt AOld durch ANew in einer Kopfzeile eines Typkommentars; False, wenn ALine keine ist.
    /// </summary>
    class function Renamed(const ALine, AOld, ANew: string; out ANewLine: string): Boolean; static;
    /// <summary>Stellen von ATypeName in allen Kopfzeilen von Typkommentaren, unter denen (nach Leer- und
    /// Kommentarzeilen) ein Rumpf von ATypeName beginnt; Kommentare ohne solchen Rumpf bleiben.</summary>
    class function NameSpots(const ALines: TArray<string>; const ATypeName: string): TArray<TTypeNameSpot>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

const
  cStyleNames: array[TTypeCommentStyle] of string = ('off', 'brace', 'line', 'summary', 'region');
  // Mindestlänge einer Trennlinie aus Bindestrichen oder Gleichheitszeichen.
  cMinRule = 10;

{ TTypeComment }

function TTypeComment.Found: Boolean;
begin
  Result := First >= 0;
end;

function TTypeComment.Covers(ALine: Integer): Boolean;
begin
  Result := Found and (((ALine >= First) and (ALine <= Last)) or (ALine = RegionEnd));
end;

class function TTypeComment.None: TTypeComment;
begin
  Result.First := -1;
  Result.Last := -1;
  Result.RegionEnd := -1;
  Result.Style := TTypeCommentStyle.Off;
end;

{ Hilfen }

function IsRuleLine(const ALine: string): Boolean;
var
  mBody: string;
  mChar: Char;
begin
  mBody := Trim(ALine);
  if not StartsStr('//', mBody) then
  begin
    Exit(False);
  end;
  mBody := Trim(Copy(mBody, 3, MaxInt));
  Result := Length(mBody) >= cMinRule;
  for mChar in mBody do
  begin
    if (mChar <> '-') and (mChar <> '=') then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Inhalt eines einzeiligen Kommentars ({ … }, (* … *), // …); False ohne oder bei Direktiven.</summary>
function CommentBody(const ALine: string; out ABody: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALine);
  ABody := '';
  if StartsStr('{$', mText) then
  begin
    Exit(False);
  end;
  if StartsStr('{', mText) and EndsStr('}', mText) then
  begin
    ABody := Copy(mText, 2, Length(mText) - 2);
  end
  else if StartsStr('(*', mText) and EndsStr('*)', mText) and (Length(mText) >= 4) then
  begin
    ABody := Copy(mText, 3, Length(mText) - 4);
  end
  else if StartsStr('//', mText) and not StartsStr('///', mText) then
  begin
    ABody := Copy(mText, 3, MaxInt);
  end
  else
  begin
    Exit(False);
  end;
  ABody := Trim(ABody);
  Result := Pos('}', ABody) = 0;
end;

/// <summary>Name in {$REGION 'Name'}; False, wenn ALine keine solche Zeile ist.</summary>
function RegionName(const ALine: string; out AName: string): Boolean;
var
  mText, mUpper: string;
begin
  AName := '';
  mText := Trim(ALine);
  mUpper := UpperCase(mText);
  Result := StartsStr('{$REGION', mUpper) and EndsStr('}', mText);
  if Result then
  begin
    AName := Trim(Copy(mText, Length('{$REGION') + 1, Length(mText) - Length('{$REGION') - 1));
    if (Length(AName) >= 2) and StartsStr('''', AName) and EndsStr('''', AName) then
    begin
      AName := Copy(AName, 2, Length(AName) - 2);
    end;
  end;
end;

function IsRegionEnd(const ALine: string): Boolean;
begin
  Result := StartsText('{$ENDREGION', Trim(ALine));
end;

/// <summary>Nennt der Inhalt ABody eines Kommentars genau den Typ (auch "TKunde: Text")?</summary>
function NamesType(const ABody, ATypeName: string; out ASummary: Boolean): Boolean;
begin
  ASummary := False;
  Result := SameText(ABody, ATypeName);
  if not Result and StartsText(ATypeName + ':', ABody) then
  begin
    Result := True;
    ASummary := True;
  end;
end;

/// <summary>Erste Zeile ohne Leerraum über bzw. unter ALine in Richtung AStep; -1 ohne.</summary>
function NextFilled(const ALines: TArray<string>; ALine, AStep: Integer): Integer;
begin
  Result := ALine;
  while (Result >= 0) and (Result <= High(ALines)) and (Trim(ALines[Result]) = '') do
  begin
    Inc(Result, AStep);
  end;
  if (Result < 0) or (Result > High(ALines)) then
  begin
    Result := -1;
  end;
end;

/// <summary>Dreizeilige Trennlinie, die in ALast endet.</summary>
function IsLineHeader(const ALines: TArray<string>; ALast: Integer; const ATypeName: string): Boolean;
var
  mBody: string;
  mSummary: Boolean;
begin
  Result := (ALast >= 2) and IsRuleLine(ALines[ALast]) and IsRuleLine(ALines[ALast - 2]) and
    CommentBody(ALines[ALast - 1], mBody) and NamesType(mBody, ATypeName, mSummary);
end;

{ TTypeComments }

class function TTypeComments.StyleOf(const AName: string): TTypeCommentStyle;
var
  mStyle: TTypeCommentStyle;
begin
  for mStyle := Low(TTypeCommentStyle) to High(TTypeCommentStyle) do
  begin
    if SameText(AName, cStyleNames[mStyle]) then
    begin
      Exit(mStyle);
    end;
  end;
  Result := TTypeCommentStyle.Brace;
end;

class function TTypeComments.StyleName(AStyle: TTypeCommentStyle): string;
begin
  Result := cStyleNames[AStyle];
end;

class function TTypeComments.Find(const ALines: TArray<string>; AFirstLine, ALastLine: Integer;
  const ATypeName: string): TTypeComment;
var
  mLine, mEnd: Integer;
  mBody, mName: string;
  mSummary: Boolean;
begin
  Result := TTypeComment.None;
  mLine := NextFilled(ALines, AFirstLine - 1, -1);
  if mLine < 0 then
  begin
    Exit;
  end;
  if IsLineHeader(ALines, mLine, ATypeName) then
  begin
    Result.First := mLine - 2;
    Result.Last := mLine;
    Result.Style := TTypeCommentStyle.Line;
  end
  else if CommentBody(ALines[mLine], mBody) and NamesType(mBody, ATypeName, mSummary) then
  begin
    Result.First := mLine;
    Result.Last := mLine;
    Result.Style := TTypeCommentStyle.Brace;
    if mSummary then
    begin
      Result.Style := TTypeCommentStyle.Summary;
    end;
  end
  else if RegionName(ALines[mLine], mName) and SameText(mName, ATypeName) then
  begin
    mEnd := NextFilled(ALines, ALastLine + 1, 1);
    if (mEnd >= 0) and IsRegionEnd(ALines[mEnd]) then
    begin
      Result.First := mLine;
      Result.Last := mLine;
      Result.RegionEnd := mEnd;
      Result.Style := TTypeCommentStyle.Region;
    end;
  end;
end;

class function TTypeComments.Header(AStyle: TTypeCommentStyle; const ATypeName, ASummary: string;
  ALineLength: Integer): TArray<string>;
var
  mRule: string;
begin
  Result := nil;
  if ALineLength < cMinRule + 2 then
  begin
    ALineLength := cDefaultLineLength;
  end;
  case AStyle of
    TTypeCommentStyle.Brace:
      Result := TArray<string>.Create('{ ' + ATypeName + ' }');
    TTypeCommentStyle.Line:
      begin
        mRule := '//' + StringOfChar('-', ALineLength - 2);
        Result := TArray<string>.Create(mRule, '// ' + ATypeName, mRule);
      end;
    TTypeCommentStyle.Summary:
      if ASummary = '' then
      begin
        Result := TArray<string>.Create('{ ' + ATypeName + ' }');
      end
      else
      begin
        Result := TArray<string>.Create('{ ' + ATypeName + ': ' + StringReplace(ASummary, '}', ')', [rfReplaceAll]) +
          ' }');
      end;
    TTypeCommentStyle.Region:
      Result := TArray<string>.Create('{$REGION ''' + ATypeName + '''}');
    TTypeCommentStyle.Off:
      Result := nil;
  end;
end;

/// <summary>Text hinter &lt;summary&gt; bis vor &lt;/summary&gt; bzw. Zeilenende, ohne Kommentarzeichen.</summary>
function SummaryText(const ALine: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(ALine);
  if StartsStr('///', Result) then
  begin
    Result := Trim(Copy(Result, 4, MaxInt));
  end;
  mIndex := Pos('<summary>', LowerCase(Result));
  if mIndex > 0 then
  begin
    Result := Trim(Copy(Result, mIndex + Length('<summary>'), MaxInt));
  end;
  mIndex := Pos('</summary>', LowerCase(Result));
  if mIndex > 0 then
  begin
    Result := Trim(Copy(Result, 1, mIndex - 1));
  end;
end;

class function TTypeComments.SummaryAbove(const ALines: TArray<string>; ATypeLine: Integer): string;
var
  mLine, mFirst: Integer;
begin
  Result := '';
  mFirst := ATypeLine;
  mLine := ATypeLine - 1;
  while (mLine >= 0) and (mLine <= High(ALines)) and StartsStr('///', Trim(ALines[mLine])) do
  begin
    mFirst := mLine;
    Dec(mLine);
  end;
  for mLine := mFirst to ATypeLine - 1 do
  begin
    if Pos('<summary>', LowerCase(ALines[mLine])) > 0 then
    begin
      Result := SummaryText(ALines[mLine]);
      // Steht der Text erst in der nächsten Zeile, diese nehmen.
      if (Result = '') and (mLine + 1 < ATypeLine) then
      begin
        Result := SummaryText(ALines[mLine + 1]);
      end;
      Exit;
    end;
  end;
end;

/// <summary>Ist ALine eine Kopfzeile eines Typkommentars für ATypeName?</summary>
function IsHeaderLine(const ALine, ATypeName: string): Boolean;
var
  mBody, mName: string;
  mSummary: Boolean;
begin
  Result := (CommentBody(ALine, mBody) and NamesType(mBody, ATypeName, mSummary)) or
    (RegionName(ALine, mName) and SameText(mName, ATypeName));
end;

/// <summary>ALine ohne die Schlüsselwörter eines Routinenkopfs vorn (class function …).</summary>
function WithoutHeadWords(const ALine: string): string;
const
  cWords: array[0..5] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator', 'class');
var
  mWord: string;
  mFound: Boolean;
begin
  Result := Trim(ALine);
  mFound := True;
  while mFound do
  begin
    mFound := False;
    for mWord in cWords do
    begin
      if StartsText(mWord + ' ', Result) then
      begin
        Result := TrimLeft(Copy(Result, Length(mWord) + 1, MaxInt));
        mFound := True;
      end;
    end;
  end;
end;

/// <summary>Teile des qualifizierten Typnamens im Kopf eines Rumpfs (TAussen.TKunde.Foo → TAussen, TKunde; ohne
/// generische Parameter); leer, wenn ALine kein Rumpf ist.</summary>
function BodyTypeParts(const ALine: string): TArray<string>;
var
  mText, mName: string;
  mIndex, mDepth: Integer;
begin
  Result := nil;
  mText := WithoutHeadWords(ALine);
  if mText = Trim(ALine) then
  begin
    Exit;
  end;
  mName := '';
  mDepth := 0;
  for mIndex := 1 to Length(mText) do
  begin
    case mText[mIndex] of
      '<': Inc(mDepth);
      '>': Dec(mDepth);
      '(', ';', ':', ' ':
        if mDepth = 0 then
        begin
          Break;
        end;
    else
      if mDepth = 0 then
      begin
        mName := mName + mText[mIndex];
      end;
    end;
  end;
  Result := mName.Split(['.']);
  SetLength(Result, Max(Length(Result) - 1, 0));
end;

/// <summary>Teile des Namens in einer Kopfzeile ({ TAussen.TKunde }, // TKunde, { TKunde: Text },
/// {$REGION 'TKunde'}) und die Spalte (ab 0) des ersten Teils; False, wenn ALine keine Kopfzeile ist.</summary>
function HeaderParts(const ALine: string; out AParts: TArray<string>; out AColumn: Integer): Boolean;
var
  mBody, mName: string;
  mColon: Integer;
begin
  AParts := nil;
  AColumn := -1;
  if RegionName(ALine, mName) then
  begin
    mBody := mName;
  end
  else if CommentBody(ALine, mBody) then
  begin
    mColon := Pos(':', mBody);
    if mColon > 0 then
    begin
      mBody := Trim(Copy(mBody, 1, mColon - 1));
    end;
  end
  else
  begin
    Exit(False);
  end;
  Result := (mBody <> '') and (Pos(' ', mBody) = 0) and IsValidIdent(mBody, True);
  if Result then
  begin
    AParts := mBody.Split(['.']);
    AColumn := Pos(mBody, ALine) - 1;
  end;
end;

/// <summary>Index von ATypeName in AParts; -1 ohne.</summary>
function PartIndex(const AParts: TArray<string>; const ATypeName: string): Integer;
begin
  for Result := 0 to High(AParts) do
  begin
    if SameText(AParts[Result], ATypeName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Teile des Typs im ersten Rumpf nach ALine (Leer-, Kommentar- und Direktivzeilen dazwischen); leer,
/// wenn vorher anderer Code steht.</summary>
function FollowingBodyParts(const ALines: TArray<string>; ALine: Integer): TArray<string>;
var
  mLine: Integer;
  mText: string;
begin
  for mLine := ALine + 1 to High(ALines) do
  begin
    mText := Trim(ALines[mLine]);
    if (mText <> '') and not StartsStr('//', mText) and not StartsStr('{', mText) and
      not StartsStr('(*', mText) then
    begin
      Exit(BodyTypeParts(mText));
    end;
  end;
  Result := nil;
end;

/// <summary>Stelle von ATypeName in der Kopfzeile ALine, wenn darunter ein Rumpf dieses Typs beginnt.</summary>
function SpotIn(const ALines: TArray<string>; ALine: Integer; const ATypeName: string;
  out ASpot: TTypeNameSpot): Boolean;
var
  mParts, mBody: TArray<string>;
  mColumn, mIndex, mPart: Integer;
begin
  Result := HeaderParts(ALines[ALine], mParts, mColumn);
  if not Result then
  begin
    Exit;
  end;
  mIndex := PartIndex(mParts, ATypeName);
  mBody := FollowingBodyParts(ALines, ALine);
  // Gleiche Teile wie der Rumpf: { TAussen.TKunde } über TAussen.TKunde.Foo.
  Result := (mIndex >= 0) and (Length(mBody) = Length(mParts)) and SameText(mBody[mIndex], ATypeName);
  if Result then
  begin
    ASpot.Line := ALine;
    ASpot.Character := mColumn;
    for mPart := 0 to mIndex - 1 do
    begin
      Inc(ASpot.Character, Length(mParts[mPart]) + 1);
    end;
  end;
end;

class function TTypeComments.NameSpots(const ALines: TArray<string>; const ATypeName: string): TArray<TTypeNameSpot>;
var
  mLine: Integer;
  mSpot: TTypeNameSpot;
begin
  Result := nil;
  for mLine := 0 to High(ALines) do
  begin
    if SpotIn(ALines, mLine, ATypeName, mSpot) then
    begin
      Result := Result + [mSpot];
    end;
  end;
end;

class function TTypeComments.Renamed(const ALine, AOld, ANew: string; out ANewLine: string): Boolean;
var
  mIndex: Integer;
begin
  ANewLine := ALine;
  Result := IsHeaderLine(ALine, AOld);
  if Result then
  begin
    // Nur das erste Vorkommen als ganzes Wort: der Name steht vorn im Kommentar.
    mIndex := Pos(LowerCase(AOld), LowerCase(ALine));
    ANewLine := Copy(ALine, 1, mIndex - 1) + ANew + Copy(ALine, mIndex + Length(AOld), MaxInt);
  end;
end;

end.
