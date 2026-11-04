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
    procedure ReadTag;
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
  Start: Integer;
begin
  Start := 0;
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    Start := 3;
  end;
  if Length(ABytes) <= Start then
  begin
    Exit('');
  end;
  Result := TEncoding.UTF8.GetString(ABytes, Start, Length(ABytes) - Start);
end;

function VcsIsUtf8(const ABytes: TBytes): Boolean;
var
  mIndex, mFollow, mStep: Integer;
  mByte: Byte;
begin
  Result := True;
  mIndex := 0;
  while mIndex < Length(ABytes) do
  begin
    mByte := ABytes[mIndex];
    if mByte < $80 then
    begin
      mFollow := 0;
    end
    else if (mByte >= $C2) and (mByte <= $DF) then
    begin
      mFollow := 1;
    end
    else if (mByte >= $E0) and (mByte <= $EF) then
    begin
      mFollow := 2;
    end
    else if (mByte >= $F0) and (mByte <= $F4) then
    begin
      mFollow := 3;
    end
    else
    begin
      Exit(False);
    end;
    if mIndex + mFollow >= Length(ABytes) then
    begin
      Exit(False);
    end;
    for mStep := 1 to mFollow do
    begin
      if (ABytes[mIndex + mStep] and $C0) <> $80 then
      begin
        Exit(False);
      end;
    end;
    // Überlange Folgen für drei und vier Bytes.
    if ((mByte = $E0) and (ABytes[mIndex + 1] < $A0)) or ((mByte = $F0) and (ABytes[mIndex + 1] < $90)) then
    begin
      Exit(False);
    end;
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
  Root, FileName, Prefix: string;
  Matches: Boolean;
begin
  ARelative := '';
  Root := VcsNormalizeDir(ARoot);
  FileName := VcsNormalizeDir(AFileName);
  if (Root = '') or (FileName = '') then
  begin
    Exit(False);
  end;
  Prefix := IncludeTrailingPathDelimiter(Root);
  if PathDelim = '\' then
  begin
    Matches := SameText(Copy(FileName, 1, Length(Prefix)), Prefix);
  end
  else
  begin
    Matches := Copy(FileName, 1, Length(Prefix)) = Prefix;
  end;
  if not Matches then
  begin
    Exit(False);
  end;
  ARelative := StringReplace(Copy(FileName, Length(Prefix) + 1, MaxInt), '\', '/', [rfReplaceAll]);
  Result := ARelative <> '';
end;

function VcsRelativeOrRoot(const ARoot, AFileName: string; out ARelative: string): Boolean;
var
  Root, FileName: string;
begin
  ARelative := '';
  Root := VcsNormalizeDir(ARoot);
  FileName := VcsNormalizeDir(AFileName);
  if (Root <> '') and ((PathDelim = '\') and SameText(Root, FileName) or (Root = FileName)) then
  begin
    Exit(True);
  end;
  Result := VcsRelativePath(ARoot, AFileName, ARelative);
end;

function VcsFullPath(const ARoot, ARelative: string): string;
var
  Relative: string;
begin
  Relative := StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
  if PathDelim = '/' then
  begin
    Relative := StringReplace(Relative, '\', '/', [rfReplaceAll]);
  end;
  while (Relative <> '') and (Relative[1] = PathDelim) do
  begin
    Delete(Relative, 1, 1);
  end;
  if (Relative = '') or (Relative = '.') then
  begin
    Exit(VcsNormalizeDir(ARoot));
  end;
  if (Length(Relative) > 2) and (Relative[1] = '.') and (Relative[2] = PathDelim) then
  begin
    Delete(Relative, 1, 2);
  end;
  Result := IncludeTrailingPathDelimiter(VcsNormalizeDir(ARoot)) + Relative;
end;

function Digits(const AText: string; AStart, ACount: Integer; out AValue: Integer): Boolean;
var
  Index: Integer;
begin
  AValue := 0;
  if AStart + ACount - 1 > Length(AText) then
  begin
    Exit(False);
  end;
  for Index := AStart to AStart + ACount - 1 do
  begin
    if (AText[Index] < '0') or (AText[Index] > '9') then
    begin
      Exit(False);
    end;
    AValue := AValue * 10 + Ord(AText[Index]) - Ord('0');
  end;
  Result := True;
end;

function VcsParseIsoDate(const AText: string; out ADate: TDateTime): Boolean;
var
  Year, Month, Day, Hour, Minute, Second, Index, Fraction, Scale: Integer;
  Text: string;
  Date, Time: TDateTime;
begin
  ADate := 0;
  Text := Trim(AText);
  // JJJJ-MM-TTTHH:MM:SS
  if (Length(Text) < 19) or (Text[5] <> '-') or (Text[8] <> '-') or ((Text[11] <> 'T') and (Text[11] <> ' ')) or
    (Text[14] <> ':') or (Text[17] <> ':') then
  begin
    Exit(False);
  end;
  if not (Digits(Text, 1, 4, Year) and Digits(Text, 6, 2, Month) and Digits(Text, 9, 2, Day) and
    Digits(Text, 12, 2, Hour) and Digits(Text, 15, 2, Minute) and Digits(Text, 18, 2, Second)) then
  begin
    Exit(False);
  end;
  if not TryEncodeDate(Year, Month, Day, Date) or not TryEncodeTime(Hour, Minute, Second, 0, Time) then
  begin
    Exit(False);
  end;
  ADate := Date + Time;
  // Bruchteile der Sekunde: auf Millisekunden gerundet.
  Index := 20;
  if (Index <= Length(Text)) and (Text[Index] = '.') then
  begin
    Inc(Index);
    Fraction := 0;
    Scale := 1;
    while (Index <= Length(Text)) and (Text[Index] >= '0') and (Text[Index] <= '9') do
    begin
      if Scale < 1000 then
      begin
        Fraction := Fraction * 10 + Ord(Text[Index]) - Ord('0');
        Scale := Scale * 10;
      end;
      Inc(Index);
    end;
    ADate := ADate + (Fraction * (1000 div Scale)) / MSecsPerDay;
  end;
  Result := True;
end;

function VcsUnixToDate(ASeconds: Int64): TDateTime;
begin
  Result := UnixDateDelta + ASeconds / SecsPerDay;
end;

function VcsSafeBranchName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (AName = '') or (AName[1] = '-') or (AName[1] = '/') then
  begin
    Exit;
  end;
  if (AName[Length(AName)] = '/') or (AName[Length(AName)] = '.') then
  begin
    Exit;
  end;
  if (Pos('..', AName) > 0) or (Pos('@{', AName) > 0) or (Pos('//', AName) > 0) then
  begin
    Exit;
  end;
  for Index := 1 to Length(AName) do
  begin
    if Ord(AName[Index]) <= 32 then
    begin
      Exit;
    end;
    case AName[Index] of
      '\', '^', '~', ':', '?', '*', '[', #127:
        Exit;
    end;
  end;
  Result := True;
end;

function VcsXmlDecode(const AText: string): string;
var
  Index, Stop, Code: Integer;
  Entity: string;
begin
  if Pos('&', AText) = 0 then
  begin
    Exit(AText);
  end;
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] <> '&' then
    begin
      Result := Result + AText[Index];
      Inc(Index);
      Continue;
    end;
    Stop := Index + 1;
    while (Stop <= Length(AText)) and (AText[Stop] <> ';') and (Stop - Index < 12) do
    begin
      Inc(Stop);
    end;
    if (Stop > Length(AText)) or (AText[Stop] <> ';') then
    begin
      Result := Result + '&';
      Inc(Index);
      Continue;
    end;
    Entity := Copy(AText, Index + 1, Stop - Index - 1);
    if Entity = 'amp' then
    begin
      Result := Result + '&';
    end
    else if Entity = 'lt' then
    begin
      Result := Result + '<';
    end
    else if Entity = 'gt' then
    begin
      Result := Result + '>';
    end
    else if Entity = 'quot' then
    begin
      Result := Result + '"';
    end
    else if Entity = 'apos' then
    begin
      Result := Result + '''';
    end
    else if (Length(Entity) > 2) and (Entity[1] = '#') and ((Entity[2] = 'x') or (Entity[2] = 'X')) and
      TryStrToInt('$' + Copy(Entity, 3, MaxInt), Code) then
    begin
      Result := Result + Char(Code);
    end
    else if (Length(Entity) > 1) and (Entity[1] = '#') and TryStrToInt(Copy(Entity, 2, MaxInt), Code) then
    begin
      Result := Result + Char(Code);
    end
    else
    begin
      Result := Result + '&' + Entity + ';';
    end;
    Index := Stop + 1;
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
  Index: Integer;
begin
  for Index := 0 to High(FAttrNames) do
  begin
    if FAttrNames[Index] = AName then
    begin
      Exit(FAttrValues[Index]);
    end;
  end;
  Result := '';
end;

function IsSpace(AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9) or (AChar = #10) or (AChar = #13);
end;

procedure TAtlasVcsXmlReader.ReadTag;
var
  Start: Integer;
  AttrName: string;
  Quote: Char;
begin
  // FPos steht hinter '<'.
  FAttrNames := nil;
  FAttrValues := nil;
  FEmpty := False;
  if (FPos <= Length(FText)) and (FText[FPos] = '/') then
  begin
    FNode := TAtlasVcsXmlNode.EndTag;
    Inc(FPos);
  end
  else
  begin
    FNode := TAtlasVcsXmlNode.StartTag;
  end;
  Start := FPos;
  while (FPos <= Length(FText)) and not IsSpace(FText[FPos]) and (FText[FPos] <> '>') and (FText[FPos] <> '/') do
  begin
    Inc(FPos);
  end;
  FName := Copy(FText, Start, FPos - Start);
  if FName = '' then
  begin
    raise EAtlasVcsParse.Create('XML: Element ohne Namen');
  end;
  while FPos <= Length(FText) do
  begin
    while (FPos <= Length(FText)) and IsSpace(FText[FPos]) do
    begin
      Inc(FPos);
    end;
    if FPos > Length(FText) then
    begin
      Break;
    end;
    if FText[FPos] = '>' then
    begin
      Inc(FPos);
      Exit;
    end;
    if FText[FPos] = '/' then
    begin
      FEmpty := True;
      Inc(FPos);
      Continue;
    end;
    Start := FPos;
    while (FPos <= Length(FText)) and (FText[FPos] <> '=') and not IsSpace(FText[FPos]) and (FText[FPos] <> '>') do
    begin
      Inc(FPos);
    end;
    AttrName := Copy(FText, Start, FPos - Start);
    while (FPos <= Length(FText)) and IsSpace(FText[FPos]) do
    begin
      Inc(FPos);
    end;
    if (FPos > Length(FText)) or (FText[FPos] <> '=') then
    begin
      raise EAtlasVcsParse.CreateFmt('XML: Attribut %s ohne Wert', [AttrName]);
    end;
    Inc(FPos);
    while (FPos <= Length(FText)) and IsSpace(FText[FPos]) do
    begin
      Inc(FPos);
    end;
    if (FPos > Length(FText)) or ((FText[FPos] <> '"') and (FText[FPos] <> '''')) then
    begin
      raise EAtlasVcsParse.CreateFmt('XML: Attribut %s ohne Anführungszeichen', [AttrName]);
    end;
    Quote := FText[FPos];
    Inc(FPos);
    Start := FPos;
    while (FPos <= Length(FText)) and (FText[FPos] <> Quote) do
    begin
      Inc(FPos);
    end;
    if FPos > Length(FText) then
    begin
      raise EAtlasVcsParse.Create('XML: Attribut nicht abgeschlossen');
    end;
    FAttrNames := FAttrNames + [AttrName];
    FAttrValues := FAttrValues + [VcsXmlDecode(Copy(FText, Start, FPos - Start))];
    Inc(FPos);
  end;
  raise EAtlasVcsParse.Create('XML: Element nicht abgeschlossen');
end;

function TAtlasVcsXmlReader.Next: Boolean;
var
  Start, Stop: Integer;
begin
  while FPos <= Length(FText) do
  begin
    if FText[FPos] <> '<' then
    begin
      Start := FPos;
      while (FPos <= Length(FText)) and (FText[FPos] <> '<') do
      begin
        Inc(FPos);
      end;
      FValue := VcsXmlDecode(Copy(FText, Start, FPos - Start));
      if Trim(FValue) = '' then
      begin
        Continue;
      end;
      FNode := TAtlasVcsXmlNode.Text;
      FName := '';
      FEmpty := False;
      Exit(True);
    end;
    // Deklaration, Verarbeitungsanweisung, Kommentar und DOCTYPE überspringen.
    if Copy(FText, FPos, 4) = '<!--' then
    begin
      Stop := Pos('-->', Copy(FText, FPos + 4, MaxInt));
      if Stop = 0 then
      begin
        raise EAtlasVcsParse.Create('XML: Kommentar nicht abgeschlossen');
      end;
      FPos := FPos + 4 + Stop + 2;
      Continue;
    end;
    if Copy(FText, FPos, 9) = '<![CDATA[' then
    begin
      Stop := Pos(']]>', Copy(FText, FPos + 9, MaxInt));
      if Stop = 0 then
      begin
        raise EAtlasVcsParse.Create('XML: CDATA nicht abgeschlossen');
      end;
      FValue := Copy(FText, FPos + 9, Stop - 1);
      FPos := FPos + 9 + Stop + 2;
      FNode := TAtlasVcsXmlNode.Text;
      FName := '';
      FEmpty := False;
      Exit(True);
    end;
    if (Copy(FText, FPos, 2) = '<?') or (Copy(FText, FPos, 2) = '<!') then
    begin
      while (FPos <= Length(FText)) and (FText[FPos] <> '>') do
      begin
        Inc(FPos);
      end;
      Inc(FPos);
      Continue;
    end;
    Inc(FPos);
    ReadTag;
    Exit(True);
  end;
  Result := False;
end;

end.
