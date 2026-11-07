unit Atlas.Core.Vcs.Internals.Text;

// Hilfen für die Parser der Versionsverwaltung (#571): Pfade relativ zur
// Wurzel der Arbeitskopie, Zeitangaben aus Git (Unix-Sekunden) und SVN
// (ISO 8601) sowie ein kleiner XML-Leser für die Ausgabe von svn --xml.
// Der XML-Leser kennt nur, was svn schreibt: Elemente mit Attributen, Text,
// Entitäten, Kommentare und die XML-Deklaration; keine DTD, keine Namensräume.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasVcsXmlNode = (StartTag, EndTag, Text);
{$SCOPEDENUMS OFF}

  /// <summary>Liest XML Knoten für Knoten. Ein leeres Element (&lt;a/&gt;) liefert StartTag mit
  /// EmptyElement = True und kein EndTag.</summary>
  TAtlasVcsXmlReader = class
  private
    FText: string;
    FPos: Integer;
    FNode: TAtlasVcsXmlNode;
    FName: string;
    FValue: string;
    FEmpty: Boolean;
    FAttrNames: TArray<string>;
    FAttrValues: TArray<string>;
    procedure SkipSpaces;
    function AtChar(AChar: Char): Boolean;
    procedure ReadTagName;
    function ReadAttrName: string;
    function ReadAttrValue(const AAttrName: string): string;
    procedure ReadAttribute;
    procedure ReadTag;
    procedure SetText(const AValue: string);
    function ReadText: Boolean;
    function EndOf(const AOpen, AClose, AWhat: string): Integer;
    function ReadMarkup: Boolean;
  public
    constructor Create(const AText: string);
    /// <summary>Nächster Knoten; False am Ende. Löst EAtlasVcsParse bei kaputtem XML aus.</summary>
    function Next: Boolean;
    /// <summary>Attribut des aktuellen StartTag; '' ohne.</summary>
    function Attr(const AName: string): string;
    property Node: TAtlasVcsXmlNode read FNode;
    /// <summary>Name des Elements bei StartTag und EndTag.</summary>
    property Name: string read FName;
    /// <summary>Text mit aufgelösten Entitäten bei Text.</summary>
    property Value: string read FValue;
    property EmptyElement: Boolean read FEmpty;
  end;

/// <summary>UTF-8-Bytes als Text; ein BOM am Anfang entfällt.</summary>
function VcsUtf8(const ABytes: TBytes): string;
/// <summary>Ausgabe ohne --xml (svn log --diff, #1275): gültiges UTF-8 als UTF-8, sonst in der ANSI-Codepage.
/// </summary>
function VcsConsoleText(const ABytes: TBytes): string;
/// <summary>Sind ABytes gültiges UTF-8 (ohne überlange Folgen)?</summary>
function VcsIsUtf8(const ABytes: TBytes): Boolean;
/// <summary>Pfad von AFileName relativ zu ARoot mit "/" getrennt; False, wenn AFileName nicht unter ARoot liegt.
/// Unter Windows ohne Unterscheidung von Groß- und Kleinschreibung.</summary>
function VcsRelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean;
/// <summary>Wie VcsRelativePath, aber ARoot selbst gehört dazu (ARelative '', #1292): Ordner und Einträge "."
/// der Wurzel.</summary>
function VcsRelativeOrRoot(const ARoot, AFileName: string; out ARelative: string): Boolean;
/// <summary>Vollständiger Pfad zu einem Pfad relativ zu ARoot ("/" oder "\" getrennt).</summary>
function VcsFullPath(const ARoot, ARelative: string): string;
/// <summary>Ordner ohne abschließenden Trenner, "/" unter Windows als "\".</summary>
function VcsNormalizeDir(const ADir: string): string;
/// <summary>"2026-10-01T08:00:00.123456Z" als UTC; False bei anderem Format.</summary>
function VcsParseIsoDate(const AText: string; out ADate: TDateTime): Boolean;
/// <summary>Unix-Sekunden als UTC.</summary>
function VcsUnixToDate(ASeconds: Int64): TDateTime;
/// <summary>&amp;amp; &amp;lt; &amp;gt; &amp;quot; &amp;apos; und &amp;#…; aufgelöst.</summary>
function VcsXmlDecode(const AText: string): string;
/// <summary>Branchname für Git und SVN, der nicht als Option oder Pfad missverstanden werden kann: nicht leer,
/// ohne Leer- und Steuerzeichen, ohne "-" oder "/" am Anfang, ohne "..", "\", "^", "~", ":", "?", "*", "[", "@{"
/// und ohne "/" oder "." am Ende (#765).</summary>
function VcsSafeBranchName(const AName: string): Boolean;

implementation

uses
  Atlas.Core.Vcs.Contract;

function VcsUtf8(const ABytes: TBytes): string;
var
  mStart: Integer;
begin
  mStart := 0;
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    mStart := 3;
  end;
  if Length(ABytes) <= mStart then
  begin
    Exit('');
  end;
  Result := TEncoding.UTF8.GetString(ABytes, mStart, Length(ABytes) - mStart);
end;

/// <summary>Anzahl der Folgebytes zum Startbyte AByte; -1, wenn AByte keine Folge beginnen darf.</summary>
function Utf8FollowCount(AByte: Byte): Integer;
begin
  case AByte of
    $00..$7F:
      Result := 0;
    $C2..$DF:
      Result := 1;
    $E0..$EF:
      Result := 2;
    $F0..$F4:
      Result := 3;
  else
    Result := -1;
  end;
end;

/// <summary>Ist die Folge ab AIndex mit AFollow Folgebytes vollständig, richtig markiert und nicht überlang?
/// </summary>
function Utf8SequenceValid(const ABytes: TBytes; AIndex, AFollow: Integer): Boolean;
var
  mStep: Integer;
begin
  if AIndex + AFollow >= Length(ABytes) then
  begin
    Exit(False);
  end;
  for mStep := 1 to AFollow do
  begin
    if (ABytes[AIndex + mStep] and $C0) <> $80 then
    begin
      Exit(False);
    end;
  end;
  // Überlange Folgen für drei und vier Bytes.
  Result := not (((ABytes[AIndex] = $E0) and (ABytes[AIndex + 1] < $A0)) or
    ((ABytes[AIndex] = $F0) and (ABytes[AIndex + 1] < $90)));
end;

function VcsIsUtf8(const ABytes: TBytes): Boolean;
var
  mIndex, mFollow: Integer;
begin
  Result := True;
  mIndex := 0;
  while Result and (mIndex < Length(ABytes)) do
  begin
    mFollow := Utf8FollowCount(ABytes[mIndex]);
    Result := (mFollow >= 0) and Utf8SequenceValid(ABytes, mIndex, mFollow);
    Inc(mIndex, mFollow + 1);
  end;
end;

function VcsConsoleText(const ABytes: TBytes): string;
begin
  if VcsIsUtf8(ABytes) then
  begin
    Result := VcsUtf8(ABytes);
  end
  else
  begin
    Result := TEncoding.ANSI.GetString(ABytes);
  end;
end;

function VcsNormalizeDir(const ADir: string): string;
begin
  Result := Trim(ADir);
  if PathDelim = '\' then
  begin
    Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  end;
  // Laufwerkswurzel ("C:\") und Unix-Wurzel ("/") behalten ihren Trenner.
  while (Length(Result) > 1) and (Result[Length(Result)] = PathDelim) and
    not ((Length(Result) = 3) and (Result[2] = ':')) do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

function VcsRelativePath(const ARoot, AFileName: string; out ARelative: string): Boolean;
var
  mRoot, mFileName, mPrefix: string;
  mMatches: Boolean;
begin
  ARelative := '';
  mRoot := VcsNormalizeDir(ARoot);
  mFileName := VcsNormalizeDir(AFileName);
  if (mRoot = '') or (mFileName = '') then
  begin
    Exit(False);
  end;
  mPrefix := IncludeTrailingPathDelimiter(mRoot);
  if PathDelim = '\' then
  begin
    mMatches := SameText(Copy(mFileName, 1, Length(mPrefix)), mPrefix);
  end
  else
  begin
    mMatches := Copy(mFileName, 1, Length(mPrefix)) = mPrefix;
  end;
  if not mMatches then
  begin
    Exit(False);
  end;
  ARelative := StringReplace(Copy(mFileName, Length(mPrefix) + 1, MaxInt), '\', '/', [rfReplaceAll]);
  Result := ARelative <> '';
end;

function VcsRelativeOrRoot(const ARoot, AFileName: string; out ARelative: string): Boolean;
var
  mRoot, mFileName: string;
begin
  ARelative := '';
  mRoot := VcsNormalizeDir(ARoot);
  mFileName := VcsNormalizeDir(AFileName);
  if (mRoot <> '') and ((PathDelim = '\') and SameText(mRoot, mFileName) or (mRoot = mFileName)) then
  begin
    Exit(True);
  end;
  Result := VcsRelativePath(ARoot, AFileName, ARelative);
end;

function VcsFullPath(const ARoot, ARelative: string): string;
var
  mRelative: string;
begin
  mRelative := StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
  if PathDelim = '/' then
  begin
    mRelative := StringReplace(mRelative, '\', '/', [rfReplaceAll]);
  end;
  while (mRelative <> '') and (mRelative[1] = PathDelim) do
  begin
    Delete(mRelative, 1, 1);
  end;
  if (mRelative = '') or (mRelative = '.') then
  begin
    Exit(VcsNormalizeDir(ARoot));
  end;
  if (Length(mRelative) > 2) and (mRelative[1] = '.') and (mRelative[2] = PathDelim) then
  begin
    Delete(mRelative, 1, 2);
  end;
  Result := IncludeTrailingPathDelimiter(VcsNormalizeDir(ARoot)) + mRelative;
end;

function Digits(const AText: string; AStart, ACount: Integer; out AValue: Integer): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  if AStart + ACount - 1 > Length(AText) then
  begin
    Exit(False);
  end;
  for mIndex := AStart to AStart + ACount - 1 do
  begin
    if (AText[mIndex] < '0') or (AText[mIndex] > '9') then
    begin
      Exit(False);
    end;
    AValue := AValue * 10 + Ord(AText[mIndex]) - Ord('0');
  end;
  Result := True;
end;

/// <summary>Stehen die Trenner von "JJJJ-MM-TTTHH:MM:SS" an ihrem Platz?</summary>
function IsoSeparatorsOk(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 19) and (AText[5] = '-') and (AText[8] = '-') and CharInSet(AText[11], ['T', ' ']);
  Result := Result and (AText[14] = ':') and (AText[17] = ':');
end;

/// <summary>Datum und Uhrzeit aus "JJJJ-MM-TTTHH:MM:SS" (Trenner geprüft); False bei ungültigen Ziffern oder Werten.
/// </summary>
function IsoDateTime(const AText: string; out ADate: TDateTime): Boolean;
var
  mYear, mMonth, mDay, mHour, mMinute, mSecond: Integer;
  mDate, mTime: TDateTime;
begin
  ADate := 0;
  Result := Digits(AText, 1, 4, mYear) and Digits(AText, 6, 2, mMonth) and Digits(AText, 9, 2, mDay);
  Result := Result and Digits(AText, 12, 2, mHour) and Digits(AText, 15, 2, mMinute) and
    Digits(AText, 18, 2, mSecond);
  Result := Result and TryEncodeDate(mYear, mMonth, mDay, mDate) and
    TryEncodeTime(mHour, mMinute, mSecond, 0, mTime);
  if Result then
  begin
    ADate := mDate + mTime;
  end;
end;

/// <summary>Bruchteil der Sekunde ab Position 20 (".123456"), auf Millisekunden gerundet, in Tagen; 0 ohne.
/// </summary>
function IsoFraction(const AText: string): Double;
var
  mIndex, mFraction, mScale, mMillis: Integer;
begin
  Result := 0;
  mIndex := 20;
  if (mIndex > Length(AText)) or (AText[mIndex] <> '.') then
  begin
    Exit;
  end;
  Inc(mIndex);
  mFraction := 0;
  mScale := 1;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['0'..'9']) do
  begin
    if mScale < 1000 then
    begin
      mFraction := mFraction * 10 + Ord(AText[mIndex]) - Ord('0');
      mScale := mScale * 10;
    end;
    Inc(mIndex);
  end;
  mMillis := mFraction * (1000 div mScale);
  Result := mMillis / MSecsPerDay;
end;

function VcsParseIsoDate(const AText: string; out ADate: TDateTime): Boolean;
var
  mText: string;
begin
  ADate := 0;
  mText := Trim(AText);
  Result := IsoSeparatorsOk(mText) and IsoDateTime(mText, ADate);
  if Result then
  begin
    ADate := ADate + IsoFraction(mText);
  end;
end;

function VcsUnixToDate(ASeconds: Int64): TDateTime;
begin
  Result := UnixDateDelta + ASeconds / SecsPerDay;
end;

/// <summary>Anfang und Ende eines Branchnamens: nicht leer, nicht "-" oder "/" vorn, nicht "/" oder "." hinten.
/// </summary>
function BranchEdgesOk(const AName: string): Boolean;
begin
  Result := (AName <> '') and not CharInSet(AName[1], ['-', '/']) and
    not CharInSet(AName[Length(AName)], ['/', '.']);
end;

/// <summary>Kein Zeichen eines Branchnamens ist Leer- oder Steuerzeichen oder eines von \ ^ ~ : ? * [.</summary>
function BranchCharsOk(const AName: string): Boolean;
var
  mChar: Char;
begin
  for mChar in AName do
  begin
    if (Ord(mChar) <= 32) or CharInSet(mChar, ['\', '^', '~', ':', '?', '*', '[', #127]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function VcsSafeBranchName(const AName: string): Boolean;
begin
  Result := BranchEdgesOk(AName) and (Pos('..', AName) = 0) and (Pos('@{', AName) = 0) and (Pos('//', AName) = 0);
  Result := Result and BranchCharsOk(AName);
end;

/// <summary>Zeichen zu einer Entität ohne "&amp;" und ";" (benannt oder &amp;#…;); unbekannte bleiben stehen.
/// </summary>
function DecodeEntity(const AEntity: string): string;
var
  mCode: Integer;
begin
  if AEntity = 'amp' then
  begin
    Result := '&';
  end
  else if AEntity = 'lt' then
  begin
    Result := '<';
  end
  else if AEntity = 'gt' then
  begin
    Result := '>';
  end
  else if AEntity = 'quot' then
  begin
    Result := '"';
  end
  else if AEntity = 'apos' then
  begin
    Result := '''';
  end
  else if (Length(AEntity) > 2) and (AEntity[1] = '#') and CharInSet(AEntity[2], ['x', 'X']) and
    TryStrToInt('$' + Copy(AEntity, 3, MaxInt), mCode) then
  begin
    Result := Char(mCode);
  end
  else if (Length(AEntity) > 1) and (AEntity[1] = '#') and TryStrToInt(Copy(AEntity, 2, MaxInt), mCode) then
  begin
    Result := Char(mCode);
  end
  else
  begin
    Result := '&' + AEntity + ';';
  end;
end;

/// <summary>Position des ";" einer Entität ab AStart ("&amp;"); 0, wenn innerhalb von 12 Zeichen keines folgt.
/// </summary>
function EntityStop(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart + 1;
  while (Result <= Length(AText)) and (AText[Result] <> ';') and (Result - AStart < 12) do
  begin
    Inc(Result);
  end;
  if (Result > Length(AText)) or (AText[Result] <> ';') then
  begin
    Result := 0;
  end;
end;

function VcsXmlDecode(const AText: string): string;
var
  mIndex, mStop: Integer;
begin
  if Pos('&', AText) = 0 then
  begin
    Exit(AText);
  end;
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mStop := 0;
    if AText[mIndex] = '&' then
    begin
      mStop := EntityStop(AText, mIndex);
    end;
    if mStop = 0 then
    begin
      Result := Result + AText[mIndex];
      Inc(mIndex);
      Continue;
    end;
    Result := Result + DecodeEntity(Copy(AText, mIndex + 1, mStop - mIndex - 1));
    mIndex := mStop + 1;
  end;
end;

{ TAtlasVcsXmlReader }

constructor TAtlasVcsXmlReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

function TAtlasVcsXmlReader.Attr(const AName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FAttrNames) do
  begin
    if FAttrNames[mIndex] = AName then
    begin
      Exit(FAttrValues[mIndex]);
    end;
  end;
  Result := '';
end;

function IsSpace(AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9) or (AChar = #10) or (AChar = #13);
end;

procedure TAtlasVcsXmlReader.SkipSpaces;
begin
  while (FPos <= Length(FText)) and IsSpace(FText[FPos]) do
  begin
    Inc(FPos);
  end;
end;

function TAtlasVcsXmlReader.AtChar(AChar: Char): Boolean;
begin
  Result := (FPos <= Length(FText)) and (FText[FPos] = AChar);
end;

procedure TAtlasVcsXmlReader.ReadTagName;
var
  mStart: Integer;
begin
  if AtChar('/') then
  begin
    FNode := TAtlasVcsXmlNode.EndTag;
    Inc(FPos);
  end
  else
  begin
    FNode := TAtlasVcsXmlNode.StartTag;
  end;
  mStart := FPos;
  while (FPos <= Length(FText)) and not IsSpace(FText[FPos]) and not CharInSet(FText[FPos], ['>', '/']) do
  begin
    Inc(FPos);
  end;
  FName := Copy(FText, mStart, FPos - mStart);
  if FName = '' then
  begin
    raise EAtlasVcsParse.Create('XML: Element ohne Namen');
  end;
end;

function TAtlasVcsXmlReader.ReadAttrName: string;
var
  mStart: Integer;
begin
  mStart := FPos;
  while (FPos <= Length(FText)) and not IsSpace(FText[FPos]) and not CharInSet(FText[FPos], ['=', '>']) do
  begin
    Inc(FPos);
  end;
  Result := Copy(FText, mStart, FPos - mStart);
end;

function TAtlasVcsXmlReader.ReadAttrValue(const AAttrName: string): string;
var
  mStart: Integer;
  mQuote: Char;
begin
  SkipSpaces;
  if not AtChar('=') then
  begin
    raise EAtlasVcsParse.CreateFmt('XML: Attribut %s ohne Wert', [AAttrName]);
  end;
  Inc(FPos);
  SkipSpaces;
  if not (AtChar('"') or AtChar('''')) then
  begin
    raise EAtlasVcsParse.CreateFmt('XML: Attribut %s ohne Anführungszeichen', [AAttrName]);
  end;
  mQuote := FText[FPos];
  Inc(FPos);
  mStart := FPos;
  while (FPos <= Length(FText)) and (FText[FPos] <> mQuote) do
  begin
    Inc(FPos);
  end;
  if FPos > Length(FText) then
  begin
    raise EAtlasVcsParse.Create('XML: Attribut nicht abgeschlossen');
  end;
  Result := VcsXmlDecode(Copy(FText, mStart, FPos - mStart));
  Inc(FPos);
end;

procedure TAtlasVcsXmlReader.ReadAttribute;
var
  mName: string;
begin
  mName := ReadAttrName;
  FAttrValues := FAttrValues + [ReadAttrValue(mName)];
  FAttrNames := FAttrNames + [mName];
end;

procedure TAtlasVcsXmlReader.ReadTag;
begin
  // FPos steht hinter '<'.
  FAttrNames := nil;
  FAttrValues := nil;
  FEmpty := False;
  ReadTagName;
  SkipSpaces;
  while (FPos <= Length(FText)) and not AtChar('>') do
  begin
    if AtChar('/') then
    begin
      FEmpty := True;
      Inc(FPos);
    end
    else
    begin
      ReadAttribute;
    end;
    SkipSpaces;
  end;
  if FPos > Length(FText) then
  begin
    raise EAtlasVcsParse.Create('XML: Element nicht abgeschlossen');
  end;
  Inc(FPos);
end;

procedure TAtlasVcsXmlReader.SetText(const AValue: string);
begin
  FValue := AValue;
  FNode := TAtlasVcsXmlNode.Text;
  FName := '';
  FEmpty := False;
end;

function TAtlasVcsXmlReader.ReadText: Boolean;
var
  mStart: Integer;
begin
  mStart := FPos;
  while (FPos <= Length(FText)) and (FText[FPos] <> '<') do
  begin
    Inc(FPos);
  end;
  SetText(VcsXmlDecode(Copy(FText, mStart, FPos - mStart)));
  Result := Trim(FValue) <> '';
end;

function TAtlasVcsXmlReader.EndOf(const AOpen, AClose, AWhat: string): Integer;
begin
  Result := Pos(AClose, Copy(FText, FPos + Length(AOpen), MaxInt));
  if Result = 0 then
  begin
    raise EAtlasVcsParse.CreateFmt('XML: %s nicht abgeschlossen', [AWhat]);
  end;
end;

function TAtlasVcsXmlReader.ReadMarkup: Boolean;
var
  mStop: Integer;
begin
  // Deklaration, Verarbeitungsanweisung, Kommentar und DOCTYPE überspringen.
  Result := False;
  if Copy(FText, FPos, 4) = '<!--' then
  begin
    mStop := EndOf('<!--', '-->', 'Kommentar');
    FPos := FPos + 4 + mStop + 2;
  end
  else if Copy(FText, FPos, 9) = '<![CDATA[' then
  begin
    mStop := EndOf('<![CDATA[', ']]>', 'CDATA');
    SetText(Copy(FText, FPos + 9, mStop - 1));
    FPos := FPos + 9 + mStop + 2;
    Result := True;
  end
  else if (Copy(FText, FPos, 2) = '<?') or (Copy(FText, FPos, 2) = '<!') then
  begin
    while (FPos <= Length(FText)) and (FText[FPos] <> '>') do
    begin
      Inc(FPos);
    end;
    Inc(FPos);
  end
  else
  begin
    Inc(FPos);
    ReadTag;
    Result := True;
  end;
end;

function TAtlasVcsXmlReader.Next: Boolean;
begin
  Result := False;
  while not Result and (FPos <= Length(FText)) do
  begin
    if FText[FPos] <> '<' then
    begin
      Result := ReadText;
    end
    else
    begin
      Result := ReadMarkup;
    end;
  end;
end;

end.
