unit Atlas.Core.Vcs.Internals.SvnExternals;

// svn:externals lesen und einzelne Zeilen umschreiben (#1291), ohne Prozesse
// und ohne VCL. Quelle ist svn propget svn:externals --xml -R . (ein
// <target path="…"> je Ordner mit der Eigenschaft).
// Formate einer Zeile:
//   neu (ab svn 1.5): [-r N] URL[@Peg] Ordner
//   alt:              Ordner [-r N] URL         (URL immer vollständig)
// Erkannt wird wie bei svn: Steht vorn eine URL (auch relativ), gilt das neue
// Format, sonst das alte. Relative Angaben: ^/ (Wurzel des Repositorys, auch
// ^/../ für ein Nachbar-Repository), ../ (relativ zum Ordner mit der
// Eigenschaft), // (gleiches Schema), / (gleicher Server). Kommentare (#) und
// Leerzeilen bleiben stehen und zählen bei den Zeilennummern mit;
// Anführungszeichen ("Mein Ordner") und Escapes mit \ werden aufgelöst, %20
// in URLs dekodiert.
// Umschreiben ändert nur die betroffene Zeile (gleiches Format, Einrückung
// bleibt); alle anderen Zeilen bleiben Zeichen für Zeichen erhalten.
// Dazu: Zustand einer External-Arbeitskopie aus svnversion, ab welcher
// Version svn copy --pin-externals kennt (1.9) und die Auswahl, was mit einem
// External im Branch geschieht (Regeln vor Vorgaben, fremde Repositories und
// Datei-Externals nie mitverzweigen, feste Revision bleibt).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasSvnExternals = class
  public
    /// <summary>Definitionen je Ordner aus der Ausgabe von propget --xml -R; Pfade relativ zu ARoot (auch wenn
    /// svn sie vollständig oder mit "\" schreibt), mit "/". Löst EAtlasVcsParse bei kaputtem XML aus.</summary>
    class function Definitions(const AXml, ARoot: string): TArray<TAtlasVcsSvnExternalDefinition>; static;
    /// <summary>Zeilen von ADefinition; AOwnerUrl ist die URL des Ordners mit der Eigenschaft (für ../),
    /// ARepositoryRoot die Wurzel des Repositorys. Ungültige Zeilen entfallen.</summary>
    class function Parse(const ADefinition: TAtlasVcsSvnExternalDefinition; const AOwnerUrl,
      ARepositoryRoot: string): TArray<TAtlasVcsSvnExternal>; static;
    /// <summary>Alle Zeilen aller Definitionen; ARootUrl ist die URL der Wurzel der Arbeitskopie.</summary>
    class function ParseAll(const ADefinitions: TArray<TAtlasVcsSvnExternalDefinition>; const ARootUrl,
      ARepositoryRoot: string): TArray<TAtlasVcsSvnExternal>; static;
    /// <summary>Vollständige URL zu AUrl (^/, ../, //, / oder vollständig).</summary>
    class function ResolveUrl(const AUrl, AOwnerUrl, ARepositoryRoot: string): string; static;
    /// <summary>%XX dekodiert (UTF-8).</summary>
    class function UrlDecode(const AText: string): string; static;
    /// <summary>Zeile ALine (ab 0) von AText durch ANewLine ersetzt; übrige Zeilen und Zeilenenden unverändert.
    /// </summary>
    class function ReplaceLine(const AText: string; ALine: Integer; const ANewLine: string): string; static;
    /// <summary>Zeile AExternal.Line aus AText, festgeschrieben auf ARevision (neu: "-r N URL Ordner", alt:
    /// "Ordner -r N URL"); '' wenn die Zeile fehlt.</summary>
    class function PinnedLine(const AText: string; const AExternal: TAtlasVcsSvnExternal;
      const ARevision: string): string; static;
    /// <summary>Zeile AExternal.Line aus AText mit neuer Quelle APath (Pfad im Repository ohne "^/"): neu
    /// "^/APath Ordner", alt "Ordner ARepositoryRoot/APath"; Revision und Peg entfallen.</summary>
    class function RetargetedLine(const AText: string; const AExternal: TAtlasVcsSvnExternal;
      const APath, ARepositoryRoot: string): string; static;
    /// <summary>Ausgabe von svnversion: höchste Revision, gemischt (":"), lokal geändert („M“). False ohne
    /// Revision.</summary>
    class function VersionState(const ASvnVersion: string; out ARevision: string; out AMixed,
      AModified: Boolean): Boolean; static;
    /// <summary>svn copy kennt --pin-externals (ab 1.9); AVersion wie "1.14.3" oder "svn, version 1.8.19".
    /// </summary>
    class function PinExternalsSupported(const AVersion: string): Boolean; static;
    /// <summary>Längste Regel aus ARules, deren Source Präfix von "^/Source" bzw. FullUrl ist (ganze
    /// Pfadteile, ohne Groß-/Kleinschreibung).</summary>
    class function MatchRule(const AExternal: TAtlasVcsSvnExternal; const ARules: TArray<TAtlasVcsExternalRule>;
      out AAction: TAtlasVcsExternalAction): Boolean; static;
    /// <summary>Vorgabe für AExternal: feste Revision Keep; sonst die Regel (Branch nur, wenn erlaubt), dann
    /// „mitverzweigen vorschlagen“, dann ExternalsOnBranch (Pin, Keep oder Ask = keine Vorauswahl).</summary>
    class function DefaultAction(const AExternal: TAtlasVcsSvnExternal;
      const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsExternalAction; static;
    /// <summary>AAction ist für AExternal erlaubt (feste Revision nur Keep, Branch nur mit CanBranch, Ask nie).
    /// </summary>
    class function Allowed(const AExternal: TAtlasVcsSvnExternal; AAction: TAtlasVcsExternalAction): Boolean;
      static;
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text;

type
  TToken = record
    Raw: string;
    Value: string;
  end;

  TParsedLine = record
    Indent: string;
    Tokens: TArray<TToken>;
    /// <summary>Index der Tokens von URL und Ordner; -1 bei ungültiger Zeile.</summary>
    UrlIndex: Integer;
    FolderIndex: Integer;
    Revision: string;
    OldFormat: Boolean;
  end;

function Lines(const AText: string): TArray<string>;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
end;

function IsBlank(AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9);
end;

/// <summary>Teilt wie svn (apr_tokenize_to_argv): Leerraum trennt, "…" und '…' halten zusammen, \ schützt das
/// nächste Leer-, Anführungs- oder \-Zeichen.</summary>
function Tokenize(const ALine: string; out AIndent: string): TArray<TToken>;
var
  mIndex, mStart: Integer;
  mQuote: Char;
  mToken: TToken;
begin
  Result := nil;
  mIndex := 1;
  while (mIndex <= Length(ALine)) and IsBlank(ALine[mIndex]) do
    Inc(mIndex);
  AIndent := Copy(ALine, 1, mIndex - 1);
  while mIndex <= Length(ALine) do
  begin
    while (mIndex <= Length(ALine)) and IsBlank(ALine[mIndex]) do
      Inc(mIndex);
    if mIndex > Length(ALine) then
      Break;
    mStart := mIndex;
    mToken.Value := '';
    mQuote := #0;
    while mIndex <= Length(ALine) do
    begin
      if (mQuote = #0) and IsBlank(ALine[mIndex]) then
        Break;
      if (ALine[mIndex] = '\') and (mIndex < Length(ALine)) and
        CharInSet(ALine[mIndex + 1], [' ', #9, '"', '''', '\']) then
      begin
        mToken.Value := mToken.Value + ALine[mIndex + 1];
        Inc(mIndex, 2);
        Continue;
      end;
      if (mQuote = #0) and CharInSet(ALine[mIndex], ['"', '''']) then
        mQuote := ALine[mIndex]
      else if (mQuote <> #0) and (ALine[mIndex] = mQuote) then
        mQuote := #0
      else
        mToken.Value := mToken.Value + ALine[mIndex];
      Inc(mIndex);
    end;
    mToken.Raw := Copy(ALine, mStart, mIndex - mStart);
    Result := Result + [mToken];
  end;
end;

function IsUrlish(const AText: string): Boolean;
begin
  Result := (Pos('://', AText) > 0) or (Copy(AText, 1, 2) = '^/') or (Copy(AText, 1, 3) = '../') or
    (Copy(AText, 1, 1) = '/');
end;

function ParseLine(const ALine: string): TParsedLine;
var
  mIndex: Integer;
  mOthers: TArray<Integer>;
  mText: string;
begin
  Result.UrlIndex := -1;
  Result.FolderIndex := -1;
  Result.Revision := '';
  Result.OldFormat := False;
  Result.Tokens := Tokenize(ALine, Result.Indent);
  if (Length(Result.Tokens) = 0) or (Copy(Result.Tokens[0].Raw, 1, 1) = '#') then
    Exit;
  mOthers := nil;
  mIndex := 0;
  while mIndex <= High(Result.Tokens) do
  begin
    mText := Result.Tokens[mIndex].Value;
    if (mText = '-r') and (mIndex < High(Result.Tokens)) then
    begin
      Result.Revision := Result.Tokens[mIndex + 1].Value;
      Inc(mIndex, 2);
      Continue;
    end;
    if (Length(mText) > 2) and (Copy(mText, 1, 2) = '-r') then
      Result.Revision := Copy(mText, 3, MaxInt)
    else
      mOthers := mOthers + [mIndex];
    Inc(mIndex);
  end;
  if (Length(mOthers) <> 2) or ((Result.Revision <> '') and (StrToIntDef(Result.Revision, -1) < 0)) then
    Exit;
  if IsUrlish(Result.Tokens[mOthers[0]].Value) then
  begin
    Result.UrlIndex := mOthers[0];
    Result.FolderIndex := mOthers[1];
  end
  else if Pos('://', Result.Tokens[mOthers[1]].Value) > 0 then
  begin
    Result.OldFormat := True;
    Result.FolderIndex := mOthers[0];
    Result.UrlIndex := mOthers[1];
  end;
end;

/// <summary>Schema und Server ("https://svn.firma.de") einer URL.</summary>
function ServerOf(const AUrl: string): string;
var
  mStart, mIndex: Integer;
begin
  mStart := Pos('://', AUrl);
  if mStart = 0 then
    Exit('');
  mIndex := mStart + 3;
  while (mIndex <= Length(AUrl)) and (AUrl[mIndex] <> '/') do
    Inc(mIndex);
  Result := Copy(AUrl, 1, mIndex - 1);
end;

/// <summary>"." und ".." im Pfadteil aufgelöst; nie über den Server hinaus.</summary>
function Normalized(const AUrl: string): string;
var
  mServer, mPart: string;
  mParts, mOut: TArray<string>;
begin
  mServer := ServerOf(AUrl);
  if mServer = '' then
    Exit(AUrl);
  mParts := Copy(AUrl, Length(mServer) + 1, MaxInt).Split(['/'], TStringSplitOptions.ExcludeEmpty);
  mOut := nil;
  for mPart in mParts do
    if mPart = '..' then
    begin
      if Length(mOut) > 0 then
        SetLength(mOut, Length(mOut) - 1);
    end
    else if mPart <> '.' then
      mOut := mOut + [mPart];
  Result := mServer;
  for mPart in mOut do
    Result := Result + '/' + mPart;
end;

function WithoutSlash(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

{ TAtlasSvnExternals }

class function TAtlasSvnExternals.Definitions(const AXml, ARoot: string): TArray<TAtlasVcsSvnExternalDefinition>;
var
  mReader: TAtlasVcsXmlReader;
  mPath, mText, mRelative: string;
  mInProperty: Boolean;
begin
  Result := nil;
  mPath := '';
  mText := '';
  mInProperty := False;
  mReader := TAtlasVcsXmlReader.Create(AXml);
  try
    while mReader.Next do
      case mReader.Node of
        TAtlasVcsXmlNode.StartTag:
          if mReader.Name = 'target' then
            mPath := mReader.Attr('path')
          else if (mReader.Name = 'property') and (mReader.Attr('name') = 'svn:externals') and
            not mReader.EmptyElement then
          begin
            mInProperty := True;
            mText := '';
          end;
        TAtlasVcsXmlNode.EndTag:
          if (mReader.Name = 'property') and mInProperty then
          begin
            mInProperty := False;
            // Relativ wie angegeben ("." bzw. "Sub\X"), vollständig nur mit vollständigem Aufruf.
            mRelative := StringReplace(Trim(mPath), '\', '/', [rfReplaceAll]);
            if (ExtractFileDrive(mPath) <> '') or (Copy(mRelative, 1, 1) = '/') then
            begin
              if not VcsRelativePath(ARoot, mPath, mRelative) then
                Continue;
            end
            else if Copy(mRelative, 1, 2) = './' then
              Delete(mRelative, 1, 2);
            if mRelative = '.' then
              mRelative := '';
            Result := Result + [TAtlasVcsSvnExternalDefinition.Make(WithoutSlash(mRelative),
              StringReplace(mText, #13#10, #10, [rfReplaceAll]))];
          end;
        TAtlasVcsXmlNode.Text:
          if mInProperty then
            mText := mText + mReader.Value;
      end;
  finally
    mReader.Free;
  end;
end;

class function TAtlasSvnExternals.UrlDecode(const AText: string): string;
var
  mBytes: TBytes;
  mIndex, mCount, mValue: Integer;
  mChar: TBytes;
begin
  if Pos('%', AText) = 0 then
    Exit(AText);
  mChar := TEncoding.UTF8.GetBytes(AText);
  SetLength(mBytes, Length(mChar));
  mCount := 0;
  mIndex := 0;
  while mIndex <= High(mChar) do
  begin
    if (mChar[mIndex] = Ord('%')) and (mIndex + 2 <= High(mChar)) and
      TryStrToInt('$' + Chr(mChar[mIndex + 1]) + Chr(mChar[mIndex + 2]), mValue) then
    begin
      mBytes[mCount] := Byte(mValue);
      Inc(mIndex, 3);
    end
    else
    begin
      mBytes[mCount] := mChar[mIndex];
      Inc(mIndex);
    end;
    Inc(mCount);
  end;
  SetLength(mBytes, mCount);
  Result := TEncoding.UTF8.GetString(mBytes);
end;

class function TAtlasSvnExternals.ResolveUrl(const AUrl, AOwnerUrl, ARepositoryRoot: string): string;
var
  mRest, mBase, mScheme: string;
begin
  if Copy(AUrl, 1, 2) = '^/' then
  begin
    // ^/../Anderes: Nachbar-Repository neben der Wurzel.
    mRest := Copy(AUrl, 3, MaxInt);
    mBase := WithoutSlash(ARepositoryRoot);
    Exit(Normalized(mBase + '/' + mRest));
  end;
  if Copy(AUrl, 1, 2) = '//' then
  begin
    mScheme := Copy(AOwnerUrl, 1, Pos('://', AOwnerUrl) - 1);
    Exit(Normalized(mScheme + ':' + AUrl));
  end;
  if Copy(AUrl, 1, 1) = '/' then
    Exit(Normalized(ServerOf(AOwnerUrl) + AUrl));
  if Copy(AUrl, 1, 3) = '../' then
    Exit(Normalized(WithoutSlash(AOwnerUrl) + '/' + AUrl));
  Result := Normalized(AUrl);
end;

class function TAtlasSvnExternals.Parse(const ADefinition: TAtlasVcsSvnExternalDefinition; const AOwnerUrl,
  ARepositoryRoot: string): TArray<TAtlasVcsSvnExternal>;
var
  mLines: TArray<string>;
  mIndex, mAt: Integer;
  mLine: TParsedLine;
  mItem: TAtlasVcsSvnExternal;
  mUrl, mRoot: string;
begin
  Result := nil;
  mRoot := WithoutSlash(ARepositoryRoot);
  mLines := Lines(ADefinition.Text);
  for mIndex := 0 to High(mLines) do
  begin
    mLine := ParseLine(mLines[mIndex]);
    if mLine.UrlIndex < 0 then
      Continue;
    mItem := Default(TAtlasVcsSvnExternal);
    mItem.Owner := ADefinition.Owner;
    mItem.Line := mIndex;
    mItem.Folder := WithoutSlash(StringReplace(mLine.Tokens[mLine.FolderIndex].Value, '\', '/', [rfReplaceAll]));
    mItem.Revision := mLine.Revision;
    mItem.OldFormat := mLine.OldFormat;
    mUrl := mLine.Tokens[mLine.UrlIndex].Value;
    // Peg nur im neuen Format: "@" nach dem letzten "/" (ein "@" in "user@server" steht davor).
    mAt := LastDelimiter('@', mUrl);
    if not mItem.OldFormat and (mAt > LastDelimiter('/', mUrl)) then
    begin
      mItem.Peg := Copy(mUrl, mAt + 1, MaxInt);
      mUrl := Copy(mUrl, 1, mAt - 1);
    end;
    mItem.Url := mUrl;
    mItem.FullUrl := ResolveUrl(mUrl, AOwnerUrl, mRoot);
    mItem.Foreign := (mRoot = '') or not SameText(Copy(mItem.FullUrl, 1, Length(mRoot) + 1), mRoot + '/');
    if not mItem.Foreign then
      mItem.Source := UrlDecode(Copy(mItem.FullUrl, Length(mRoot) + 2, MaxInt));
    if mItem.Folder <> '' then
      Result := Result + [mItem];
  end;
end;

class function TAtlasSvnExternals.ParseAll(const ADefinitions: TArray<TAtlasVcsSvnExternalDefinition>;
  const ARootUrl, ARepositoryRoot: string): TArray<TAtlasVcsSvnExternal>;
var
  mDefinition: TAtlasVcsSvnExternalDefinition;
  mOwnerUrl: string;
begin
  Result := nil;
  for mDefinition in ADefinitions do
  begin
    mOwnerUrl := WithoutSlash(ARootUrl);
    if mDefinition.Owner <> '' then
      mOwnerUrl := mOwnerUrl + '/' + StringReplace(mDefinition.Owner, ' ', '%20', [rfReplaceAll]);
    Result := Result + Parse(mDefinition, mOwnerUrl, ARepositoryRoot);
  end;
end;

class function TAtlasSvnExternals.ReplaceLine(const AText: string; ALine: Integer; const ANewLine: string): string;
var
  mIndex, mStart, mLine: Integer;
begin
  // Zeilenenden bleiben, wie sie sind: nur der Inhalt der Zeile ALine wird getauscht.
  mLine := 0;
  mStart := 1;
  mIndex := 1;
  while mLine < ALine do
  begin
    if mIndex > Length(AText) then
      Exit(AText);
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mStart := mIndex + 1;
    end;
    Inc(mIndex);
  end;
  mIndex := mStart;
  while (mIndex <= Length(AText)) and not CharInSet(AText[mIndex], [#10, #13]) do
    Inc(mIndex);
  Result := Copy(AText, 1, mStart - 1) + ANewLine + Copy(AText, mIndex, MaxInt);
end;

function LineOf(const AText: string; AIndex: Integer; out ALine: TParsedLine): Boolean;
var
  mLines: TArray<string>;
begin
  mLines := Lines(AText);
  Result := (AIndex >= 0) and (AIndex <= High(mLines));
  if Result then
  begin
    ALine := ParseLine(mLines[AIndex]);
    Result := ALine.UrlIndex >= 0;
  end;
end;

class function TAtlasSvnExternals.PinnedLine(const AText: string; const AExternal: TAtlasVcsSvnExternal;
  const ARevision: string): string;
var
  mLine: TParsedLine;
begin
  Result := '';
  if not LineOf(AText, AExternal.Line, mLine) then
    Exit;
  if mLine.OldFormat then
    Result := mLine.Indent + mLine.Tokens[mLine.FolderIndex].Raw + ' -r' + ARevision + ' ' +
      mLine.Tokens[mLine.UrlIndex].Raw
  else
    Result := mLine.Indent + '-r ' + ARevision + ' ' + mLine.Tokens[mLine.UrlIndex].Raw + ' ' +
      mLine.Tokens[mLine.FolderIndex].Raw;
end;

class function TAtlasSvnExternals.RetargetedLine(const AText: string; const AExternal: TAtlasVcsSvnExternal;
  const APath, ARepositoryRoot: string): string;
var
  mLine: TParsedLine;
begin
  Result := '';
  if not LineOf(AText, AExternal.Line, mLine) then
    Exit;
  // Altes Format kennt keine relativen URLs: vollständig schreiben.
  if mLine.OldFormat then
    Result := mLine.Indent + mLine.Tokens[mLine.FolderIndex].Raw + ' ' + WithoutSlash(ARepositoryRoot) + '/' +
      StringReplace(APath, ' ', '%20', [rfReplaceAll])
  else
    Result := mLine.Indent + '^/' + StringReplace(APath, ' ', '%20', [rfReplaceAll]) + ' ' +
      mLine.Tokens[mLine.FolderIndex].Raw;
end;

class function TAtlasSvnExternals.VersionState(const ASvnVersion: string; out ARevision: string; out AMixed,
  AModified: Boolean): Boolean;
var
  mText: string;
begin
  ARevision := '';
  AMixed := False;
  AModified := False;
  mText := Trim(ASvnVersion);
  // Marken am Ende: M geändert, S umgeschaltet, P teilweise.
  while (mText <> '') and CharInSet(mText[Length(mText)], ['M', 'S', 'P']) do
  begin
    if mText[Length(mText)] = 'M' then
      AModified := True;
    Delete(mText, Length(mText), 1);
  end;
  if Pos(':', mText) > 0 then
  begin
    AMixed := True;
    mText := Copy(mText, Pos(':', mText) + 1, MaxInt);
  end;
  Result := (mText <> '') and (StrToIntDef(mText, -1) >= 0);
  if Result then
    ARevision := mText
  else
  begin
    AMixed := False;
    AModified := False;
  end;
end;

class function TAtlasSvnExternals.PinExternalsSupported(const AVersion: string): Boolean;
var
  mText: string;
  mIndex, mStart, mMajor, mMinor: Integer;
  mParts: TArray<string>;
begin
  // Erste Zahlenfolge "x.y" im Text.
  mText := Trim(AVersion);
  mIndex := 1;
  while (mIndex <= Length(mText)) and not CharInSet(mText[mIndex], ['0'..'9']) do
    Inc(mIndex);
  mStart := mIndex;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['0'..'9', '.']) do
    Inc(mIndex);
  mParts := Copy(mText, mStart, mIndex - mStart).Split(['.']);
  Result := False;
  if (Length(mParts) < 2) or not TryStrToInt(mParts[0], mMajor) or not TryStrToInt(mParts[1], mMinor) then
    Exit;
  Result := (mMajor > 1) or ((mMajor = 1) and (mMinor >= 9));
end;

function PrefixOf(const APrefix, AText: string): Boolean;
begin
  Result := (APrefix <> '') and (SameText(AText, APrefix) or SameText(Copy(AText, 1, Length(APrefix) + 1),
    APrefix + '/'));
end;

class function TAtlasSvnExternals.MatchRule(const AExternal: TAtlasVcsSvnExternal;
  const ARules: TArray<TAtlasVcsExternalRule>; out AAction: TAtlasVcsExternalAction): Boolean;
var
  mRule: TAtlasVcsExternalRule;
  mSource, mBest: string;
begin
  AAction := TAtlasVcsExternalAction.Ask;
  mBest := '';
  for mRule in ARules do
  begin
    mSource := WithoutSlash(mRule.Source);
    if Length(mSource) <= Length(mBest) then
      Continue;
    if (not AExternal.Foreign and PrefixOf(mSource, '^/' + AExternal.Source)) or
      PrefixOf(mSource, AExternal.FullUrl) then
    begin
      mBest := mSource;
      AAction := mRule.Action;
    end;
  end;
  Result := mBest <> '';
end;

class function TAtlasSvnExternals.Allowed(const AExternal: TAtlasVcsSvnExternal;
  AAction: TAtlasVcsExternalAction): Boolean;
begin
  case AAction of
    TAtlasVcsExternalAction.Keep:
      Result := True;
    TAtlasVcsExternalAction.Pin:
      Result := not AExternal.Fixed;
    TAtlasVcsExternalAction.Branch:
      Result := AExternal.CanBranch;
  else
    Result := False;
  end;
end;

class function TAtlasSvnExternals.DefaultAction(const AExternal: TAtlasVcsSvnExternal;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsExternalAction;
var
  mAction: TAtlasVcsExternalAction;
begin
  // Mit Revision behält ein External sie immer.
  if AExternal.Fixed then
    Exit(TAtlasVcsExternalAction.Keep);
  if MatchRule(AExternal, AOptions.ExternalsRules, mAction) and Allowed(AExternal, mAction) then
    Exit(mAction);
  if AExternal.CanBranch and ((AOptions.ExternalsSuggest = TAtlasVcsExternalSuggest.Always) or
    ((AOptions.ExternalsSuggest = TAtlasVcsExternalSuggest.Modified) and AExternal.Modified)) then
    Exit(TAtlasVcsExternalAction.Branch);
  if AOptions.ExternalsOnBranch = TAtlasVcsExternalAction.Branch then
    Exit(TAtlasVcsExternalAction.Pin);
  Result := AOptions.ExternalsOnBranch;
end;

end.
