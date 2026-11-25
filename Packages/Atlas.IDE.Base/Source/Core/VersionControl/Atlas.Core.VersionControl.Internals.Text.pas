unit Atlas.Core.VersionControl.Internals.Text;

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
  Atlas.Core.VersionControl.Contract,
  Atlas.Text.Encoding,
  Atlas.Text.Entities,
  Atlas.Text.Timestamps;

const
  // Gründe von EAtlasVcsParse. Die Aufrufer fangen die Ausnahme und melden nur, dass das Lesen scheiterte; die
  // Texte erscheinen nie in der Oberfläche.
  cXmlNoName = 'XML: Element ohne Namen';
  cXmlNoValue = 'XML: Attribut %s ohne Wert';
  cXmlNoQuote = 'XML: Attribut %s ohne Anführungszeichen';
  cXmlOpenAttribute = 'XML: Attribut nicht abgeschlossen';
  cXmlOpenElement = 'XML: Element nicht abgeschlossen';
  cXmlOpenMarkup = 'XML: %s nicht abgeschlossen';
  cXmlComment = 'Kommentar';
  cXmlCData = 'CDATA';

  cCommentOpen = '<!--';
  cCommentClose = '-->';
  cCDataOpen = '<![CDATA[';
  cCDataClose = ']]>';
  /// <summary>Länge einer Laufwerkswurzel ("C:\").</summary>
  cDriveRootLength = 3;

function VcsUtf8(const ABytes: TBytes): string;
var
  mStart: Integer;
begin
  mStart := 0;
  if TTextEncodingProbe.BomOf(ABytes) = TTextBom.Utf8 then
  begin
    mStart := TTextEncodingProbe.BomLength(TTextBom.Utf8);
  end;
  if Length(ABytes) <= mStart then
  begin
    Exit('');
  end;
  Result := TEncoding.UTF8.GetString(ABytes, mStart, Length(ABytes) - mStart);
end;

function VcsIsUtf8(const ABytes: TBytes): Boolean;
begin
  Result := TTextEncodingProbe.IsValidUtf8(ABytes, 0);
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
    not ((Length(Result) = cDriveRootLength) and (Result[2] = ':')) do
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

function VcsParseIsoDate(const AText: string; out ADate: TDateTime): Boolean;
begin
  Result := TTextTimestamp.TryParse(AText, ADate);
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
    if (mChar <= ' ') or CharInSet(mChar, ['\', '^', '~', ':', '?', '*', '[', #127]) then
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

function VcsXmlDecode(const AText: string): string;
begin
  Result := TTextEntities.Decode(AText);
end;

{ TAtlasVcsXmlReader }

constructor TAtlasVcsXmlReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

function TAtlasVcsXmlReader.AtChar(AChar: Char): Boolean;
begin
  Result := (FPos <= Length(FText)) and (FText[FPos] = AChar);
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
    raise EAtlasVcsParse.Create(cXmlNoName);
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
    raise EAtlasVcsParse.CreateFmt(cXmlNoValue, [AAttrName]);
  end;
  Inc(FPos);
  SkipSpaces;
  if not (AtChar('"') or AtChar('''')) then
  begin
    raise EAtlasVcsParse.CreateFmt(cXmlNoQuote, [AAttrName]);
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
    raise EAtlasVcsParse.Create(cXmlOpenAttribute);
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
    raise EAtlasVcsParse.Create(cXmlOpenElement);
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
    raise EAtlasVcsParse.CreateFmt(cXmlOpenMarkup, [AWhat]);
  end;
end;

function TAtlasVcsXmlReader.ReadMarkup: Boolean;
var
  mStop: Integer;
begin
  // Deklaration, Verarbeitungsanweisung, Kommentar und DOCTYPE überspringen.
  Result := False;
  if Copy(FText, FPos, Length(cCommentOpen)) = cCommentOpen then
  begin
    mStop := EndOf(cCommentOpen, cCommentClose, cXmlComment);
    FPos := FPos + Length(cCommentOpen) + mStop + Length(cCommentClose) - 1;
  end
  else if Copy(FText, FPos, Length(cCDataOpen)) = cCDataOpen then
  begin
    mStop := EndOf(cCDataOpen, cCDataClose, cXmlCData);
    SetText(Copy(FText, FPos + Length(cCDataOpen), mStop - 1));
    FPos := FPos + Length(cCDataOpen) + mStop + Length(cCDataClose) - 1;
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

end.
