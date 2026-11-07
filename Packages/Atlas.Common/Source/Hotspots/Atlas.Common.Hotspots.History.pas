unit Atlas.Common.Hotspots.History;

// Verlauf für die Hotspots (#1354): Aufrufe und Zerlegen der Ausgaben von git
// und svn, Verfolgen von Umbenennungen.
//
// Git:
//   git log --no-merges --numstat -M --format=<Kopf> --since=<ISO>
//   Kopf je Commit: #1E Hash #1F Zeitpunkt (Unix) #1F Autor #1F Betreff; danach je Datei
//   "hinzugefügt<TAB>gelöscht<TAB>Pfad" ("-" bei Binärdateien). Umbenennungen
//   stehen als "alt => neu" oder "a/{alt => neu}/b". Merges zählen nicht:
//   Ihre Änderungen stehen schon in den Commits der Branches.
// SVN:
//   svn log -v --xml -r HEAD:{ISO} <Wurzel>
//   <logentry revision="n"><author/><date/><paths><path action="A|M|D|R"
//   kind="file" copyfrom-path="…">/trunk/…</path></paths></logentry>; Pfade
//   im Repository, relativ gemacht über den Pfad der Arbeitskopie im
//   Repository (svn info --show-item relative-url ohne "^"). Eine Kopie mit
//   copyfrom-path, deren Quelle im selben Commit gelöscht wird, ist eine
//   Umbenennung. Zeilenzahlen kennt das Log nicht (-1).
//
// FollowRenames schreibt die Pfade aller Commits auf den heutigen Namen um
// (neueste zuerst durchlaufen: eine Umbenennung alt → neu leitet ältere
// Änderungen an alt auf den heutigen Namen von neu). Wird eine Datei in
// einem Commit neu angelegt, gehören ältere Änderungen unter demselben Pfad
// zu einer früheren, gelöschten Datei und fallen weg.

interface

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract;

type
  THotspotHistory = record
  public const
    cGitRecord = #$1E;
    cGitField = #$1F;
  public
    /// <summary>Argumente für git log ab ASince (UTC), ohne die festen Optionen der Umsetzung.</summary>
    class function GitLogArguments(ASince: TDateTime): TArray<string>; static;
    /// <summary>Zerlegt die Ausgabe von GitLogArguments; Commits ohne Dateien fallen weg.</summary>
    class function ParseGitLog(const AText: string): TArray<THotspotCommit>; static;
    /// <summary>Alter und neuer Pfad aus einer numstat-Angabe mit " => "; False ohne Umbenennung.</summary>
    class function SplitRename(const AText: string; out AOld, ANew: string): Boolean; static;
    /// <summary>Argumente für svn log ab ASince (UTC) über ATarget (Wurzel der Arbeitskopie).</summary>
    class function SvnLogArguments(ASince: TDateTime; const ATarget: string): TArray<string>; static;
    /// <summary>Zerlegt svn log -v --xml; nur Dateien unter APrefix (Pfad im Repository wie "/trunk"),
    /// relativ dazu.</summary>
    class function ParseSvnLog(const AXml, APrefix: string): TArray<THotspotCommit>; static;
    /// <summary>SVN-Zeitpunkt "2026-10-29T21:24:52.123456Z" bzw. ISO ohne Bruchteil; False bei anderem
    /// Format.</summary>
    class function TryParseIsoDate(const AText: string; out ADate: TDateTime): Boolean; static;
    /// <summary>Zeitpunkt für --since bzw. -r {…}: "2026-10-29T21:24:52Z".</summary>
    class function IsoDate(ADate: TDateTime): string; static;
    /// <summary>Pfade auf den heutigen Namen; ACommits neueste zuerst.</summary>
    class function FollowRenames(const ACommits: TArray<THotspotCommit>): TArray<THotspotCommit>; static;
    /// <summary>Hinzugefügte und gelöschte Zeilen eines Unified-Diffs (ohne Kopfzeilen +++/---).</summary>
    class procedure CountPatch(const ALines: TArray<string>; out AAdded, ADeleted: Integer); static;
    /// <summary>Datum ASince für Months Monate vor ANow.</summary>
    class function Since(ANow: TDateTime; AMonths: Integer): TDateTime; static;
  end;

implementation

uses
  System.StrUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

{ THotspotHistory }

class function THotspotHistory.IsoDate(ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ADate);
end;

class function THotspotHistory.Since(ANow: TDateTime; AMonths: Integer): TDateTime;
begin
  Result := IncMonth(ANow, -AMonths);
end;

class function THotspotHistory.GitLogArguments(ASince: TDateTime): TArray<string>;
begin
  Result := TArray<string>.Create('log', '--no-merges', '--numstat', '-M', '--no-color',
    '--format=%x1e%H%x1f%at%x1f%aN%x1f%s', '--since=' + IsoDate(ASince));
end;

class function THotspotHistory.SplitRename(const AText: string; out AOld, ANew: string): Boolean;
var
  mArrow, mOpen, mClose: Integer;
  mPrefix, mSuffix, mInner: string;
begin
  AOld := '';
  ANew := AText;
  mArrow := Pos(' => ', AText);
  Result := mArrow > 0;
  if not Result then
  begin
    Exit;
  end;
  mOpen := Pos('{', AText);
  mClose := Pos('}', AText);
  if (mOpen > 0) and (mOpen < mArrow) and (mClose > mArrow) then
  begin
    mPrefix := Copy(AText, 1, mOpen - 1);
    mSuffix := Copy(AText, mClose + 1, MaxInt);
    mInner := Copy(AText, mOpen + 1, mClose - mOpen - 1);
    mArrow := Pos(' => ', mInner);
    AOld := mPrefix + Copy(mInner, 1, mArrow - 1) + mSuffix;
    ANew := mPrefix + Copy(mInner, mArrow + 4, MaxInt) + mSuffix;
    // "a/{ => b}/c" und "a/{b => }/c": leerer Teil lässt "//" stehen.
    AOld := StringReplace(AOld, '//', '/', [rfReplaceAll]);
    ANew := StringReplace(ANew, '//', '/', [rfReplaceAll]);
  end
  else
  begin
    AOld := Copy(AText, 1, mArrow - 1);
    ANew := Copy(AText, mArrow + 4, MaxInt);
  end;
end;

function CountOf(const AText: string): Integer;
begin
  if not TryStrToInt(AText, Result) then
  begin
    Result := -1;
  end;
end;

/// <summary>Kopfzeile eines git-Datensatzes (Revision, Sekunden, Autor, Betreff); False, wenn sie nicht passt.
/// </summary>
function TryReadGitHead(const ALine: string; out ACommit: THotspotCommit): Boolean;
var
  mHead: TArray<string>;
  mSeconds: Int64;
begin
  ACommit := Default(THotspotCommit);
  mHead := ALine.Split([THotspotHistory.cGitField], 4);
  Result := (Length(mHead) >= 3) and TryStrToInt64(Trim(mHead[1]), mSeconds);
  if not Result then
  begin
    Exit;
  end;
  ACommit.Revision := Trim(mHead[0]);
  ACommit.Date := UnixToDateTime(mSeconds, True);
  ACommit.Author := Trim(mHead[2]);
  if Length(mHead) > 3 then
  begin
    ACommit.Summary := Trim(mHead[3]);
  end;
end;

/// <summary>Dateien aus den numstat-Zeilen ab ALines[1] ("hinzu\tweg\tpfad").</summary>
function GitFiles(const ALines: TArray<string>): TArray<THotspotFileChange>;
var
  mFiles: TList<THotspotFileChange>;
  mFields: TArray<string>;
  mOld, mNew: string;
  mIndex: Integer;
begin
  mFiles := TList<THotspotFileChange>.Create;
  try
    for mIndex := 1 to High(ALines) do
    begin
      mFields := ALines[mIndex].Split([#9], 3);
      if Length(mFields) < 3 then
      begin
        Continue;
      end;
      if THotspotHistory.SplitRename(mFields[2], mOld, mNew) then
      begin
        mFiles.Add(THotspotFileChange.Make(mNew, mOld, THotspotChangeKind.Renamed, CountOf(mFields[0]),
          CountOf(mFields[1])));
      end
      else
      begin
        mFiles.Add(THotspotFileChange.Make(mFields[2], '', THotspotChangeKind.Modified, CountOf(mFields[0]),
          CountOf(mFields[1])));
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mFiles.Free;
  end;
end;

class function THotspotHistory.ParseGitLog(const AText: string): TArray<THotspotCommit>;
var
  mList: TList<THotspotCommit>;
  mRecord: string;
  mLines: TArray<string>;
  mCommit: THotspotCommit;
begin
  mList := TList<THotspotCommit>.Create;
  try
    for mRecord in AText.Split([cGitRecord]) do
    begin
      mLines := StringReplace(mRecord, #13, '', [rfReplaceAll]).Split([#10]);
      if (Length(mLines) = 0) or (Trim(mLines[0]) = '') or not TryReadGitHead(mLines[0], mCommit) then
      begin
        Continue;
      end;
      mCommit.Files := GitFiles(mLines);
      if Length(mCommit.Files) > 0 then
      begin
        mList.Add(mCommit);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function THotspotHistory.SvnLogArguments(ASince: TDateTime; const ATarget: string): TArray<string>;
begin
  Result := TArray<string>.Create('log', '-v', '--xml', '--non-interactive', '-r', 'HEAD:{' + IsoDate(ASince) + '}',
    ATarget);
end;

class function THotspotHistory.TryParseIsoDate(const AText: string; out ADate: TDateTime): Boolean;
var
  mYear, mMonth, mDay, mHour, mMinute, mSecond: Integer;
begin
  ADate := 0;
  Result := (Length(AText) >= 19) and (AText[5] = '-') and (AText[8] = '-') and (AText[11] = 'T') and
    TryStrToInt(Copy(AText, 1, 4), mYear) and TryStrToInt(Copy(AText, 6, 2), mMonth) and
    TryStrToInt(Copy(AText, 9, 2), mDay) and TryStrToInt(Copy(AText, 12, 2), mHour) and
    TryStrToInt(Copy(AText, 15, 2), mMinute) and TryStrToInt(Copy(AText, 18, 2), mSecond) and
    TryEncodeDateTime(mYear, mMonth, mDay, mHour, mMinute, mSecond, 0, ADate);
end;

/// <summary>Zeichencode der Entität AName (amp, lt, gt, quot, apos, #nn, #xhh); -1 unbekannt.</summary>
function EntityCode(const AName: string): Integer;
begin
  Result := -1;
  if AName = 'amp' then
  begin
    Result := Ord('&');
  end
  else if AName = 'lt' then
  begin
    Result := Ord('<');
  end
  else if AName = 'gt' then
  begin
    Result := Ord('>');
  end
  else if AName = 'quot' then
  begin
    Result := Ord('"');
  end
  else if AName = 'apos' then
  begin
    Result := Ord('''');
  end
  else if StartsText('#x', AName) then
  begin
    Result := StrToIntDef('$' + Copy(AName, 3, MaxInt), -1);
  end
  else if StartsText('#', AName) then
  begin
    Result := StrToIntDef(Copy(AName, 2, MaxInt), -1);
  end;
end;

/// <summary>Liest eine Entität ab AText[AIndex] = '&amp;' in ABuilder und setzt AIndex dahinter; False, wenn dort
/// keine gültige steht.</summary>
function ReadEntity(const AText: string; var AIndex: Integer; ABuilder: TStringBuilder): Boolean;
var
  mEnd, mCode: Integer;
begin
  mEnd := PosEx(';', AText, AIndex);
  mCode := -1;
  if mEnd > 0 then
  begin
    mCode := EntityCode(Copy(AText, AIndex + 1, mEnd - AIndex - 1));
  end;
  Result := (mCode >= 0) and (mCode <= $FFFF);
  if Result then
  begin
    ABuilder.Append(Char(mCode));
    AIndex := mEnd + 1;
  end;
end;

/// <summary>Text eines XML-Inhalts ohne Entitäten.</summary>
function XmlText(const AText: string): string;
var
  mIndex: Integer;
  mBuilder: TStringBuilder;
begin
  if Pos('&', AText) = 0 then
  begin
    Exit(AText);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if (AText[mIndex] <> '&') or not ReadEntity(AText, mIndex, mBuilder) then
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Wert des Attributs AName im Starttag ATag ('' ohne).</summary>
function XmlAttribute(const ATag, AName: string): string;
var
  mStart, mEnd: Integer;
  mQuote: Char;
begin
  Result := '';
  mStart := Pos(' ' + AName + '=', ATag);
  if mStart = 0 then
  begin
    Exit;
  end;
  mStart := mStart + Length(AName) + 2;
  if mStart > Length(ATag) then
  begin
    Exit;
  end;
  mQuote := ATag[mStart];
  if (mQuote <> '"') and (mQuote <> '''') then
  begin
    Exit;
  end;
  mEnd := PosEx(mQuote, ATag, mStart + 1);
  if mEnd > 0 then
  begin
    Result := XmlText(Copy(ATag, mStart + 1, mEnd - mStart - 1));
  end;
end;

/// <summary>Inhalt des ersten Elements AName ab AFrom bis ALimit; '' ohne.</summary>
function XmlElement(const AXml, AName: string; AFrom, ALimit: Integer): string;
var
  mStart, mClose, mEnd: Integer;
begin
  Result := '';
  mStart := PosEx('<' + AName, AXml, AFrom);
  if (mStart = 0) or (mStart > ALimit) then
  begin
    Exit;
  end;
  mClose := PosEx('>', AXml, mStart);
  if (mClose = 0) or (AXml[mClose - 1] = '/') then
  begin
    Exit;
  end;
  mEnd := PosEx('</' + AName + '>', AXml, mClose);
  if (mEnd > 0) and (mEnd <= ALimit) then
  begin
    Result := XmlText(Copy(AXml, mClose + 1, mEnd - mClose - 1));
  end;
end;

type
  TSvnPath = record
    Action: string;
    Kind: string;
    Path: string;
    CopyFrom: string;
  end;

function RelativeToPrefix(const APath, APrefix: string; out ARelative: string): Boolean;
var
  mPrefix: string;
begin
  mPrefix := APrefix;
  if (mPrefix <> '') and (mPrefix[Length(mPrefix)] <> '/') then
  begin
    mPrefix := mPrefix + '/';
  end;
  if mPrefix = '/' then
  begin
    mPrefix := '';
  end;
  if mPrefix = '' then
  begin
    ARelative := APath;
    if StartsStr('/', ARelative) then
    begin
      Delete(ARelative, 1, 1);
    end;
    Exit(ARelative <> '');
  end;
  if not StartsStr('/', mPrefix) then
  begin
    mPrefix := '/' + mPrefix;
  end;
  Result := StartsStr(mPrefix, APath) and (Length(APath) > Length(mPrefix));
  if Result then
  begin
    ARelative := Copy(APath, Length(mPrefix) + 1, MaxInt);
  end
  else
  begin
    ARelative := '';
  end;
end;

/// <summary>Kopf eines logentry ab AEntry (Revision, Autor, erste Zeile der Nachricht, Datum); ATagEnd ist das
/// Ende seines Starttags.</summary>
function ReadSvnHead(const AXml: string; AEntry, AEntryEnd: Integer; out ATagEnd: Integer): THotspotCommit;
begin
  ATagEnd := PosEx('>', AXml, AEntry);
  Result := Default(THotspotCommit);
  Result.Revision := XmlAttribute(Copy(AXml, AEntry, ATagEnd - AEntry), 'revision');
  Result.Author := Trim(XmlElement(AXml, 'author', ATagEnd, AEntryEnd));
  Result.Summary := Trim(StringReplace(XmlElement(AXml, 'msg', ATagEnd, AEntryEnd), #13, '', [rfReplaceAll]));
  if Pos(#10, Result.Summary) > 0 then
  begin
    Result.Summary := Trim(Copy(Result.Summary, 1, Pos(#10, Result.Summary) - 1));
  end;
  if not THotspotHistory.TryParseIsoDate(Trim(XmlElement(AXml, 'date', ATagEnd, AEntryEnd)), Result.Date) then
  begin
    Result.Date := 0;
  end;
end;

/// <summary>Die path-Elemente zwischen AFrom und ALimit.</summary>
function ReadSvnPaths(const AXml: string; AFrom, ALimit: Integer): TArray<TSvnPath>;
var
  mPathStart, mPathClose, mPathEnd: Integer;
  mTag: string;
  mItem: TSvnPath;
begin
  Result := nil;
  mPathStart := PosEx('<path ', AXml, AFrom);
  while (mPathStart > 0) and (mPathStart < ALimit) do
  begin
    mPathClose := PosEx('>', AXml, mPathStart);
    mPathEnd := PosEx('</path>', AXml, mPathClose);
    if (mPathClose = 0) or (mPathEnd = 0) or (mPathEnd > ALimit) then
    begin
      Break;
    end;
    mTag := Copy(AXml, mPathStart, mPathClose - mPathStart);
    mItem.Action := XmlAttribute(mTag, 'action');
    mItem.Kind := XmlAttribute(mTag, 'kind');
    mItem.CopyFrom := XmlAttribute(mTag, 'copyfrom-path');
    mItem.Path := Trim(XmlText(Copy(AXml, mPathClose + 1, mPathEnd - mPathClose - 1)));
    Result := Result + [mItem];
    mPathStart := PosEx('<path ', AXml, mPathEnd);
  end;
end;

/// <summary>Änderung zu AItem; False für Ordner, Pfade außerhalb von APrefix und die gelöschte Quelle einer
/// Umbenennung (sie steht beim neuen Pfad).</summary>
function TrySvnChange(const AItem: TSvnPath; const APrefix: string; ADeleted, ACopied: TDictionary<string, Boolean>;
  out AChange: THotspotFileChange): Boolean;
var
  mRelative, mOld: string;
begin
  AChange := Default(THotspotFileChange);
  // Ordner zählen nicht; alte Server lassen kind weg.
  Result := (AItem.Kind <> 'dir') and RelativeToPrefix(AItem.Path, APrefix, mRelative);
  if not Result then
  begin
    Exit;
  end;
  if AItem.Action = 'D' then
  begin
    Result := not ACopied.ContainsKey(AItem.Path);
    AChange := THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Deleted, -1, -1);
  end
  else if (AItem.CopyFrom <> '') and ADeleted.ContainsKey(AItem.CopyFrom) and
    RelativeToPrefix(AItem.CopyFrom, APrefix, mOld) then
  begin
    AChange := THotspotFileChange.Make(mRelative, mOld, THotspotChangeKind.Renamed, -1, -1);
  end
  else if AItem.Action = 'A' then
  begin
    AChange := THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Added, -1, -1);
  end
  else
  begin
    AChange := THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Modified, -1, -1);
  end;
end;

/// <summary>Dateiänderungen eines logentry aus seinen path-Elementen.</summary>
function SvnFiles(const APaths: TArray<TSvnPath>; const APrefix: string): TArray<THotspotFileChange>;
var
  mDeleted, mCopied: TDictionary<string, Boolean>;
  mItem: TSvnPath;
  mChange: THotspotFileChange;
begin
  Result := nil;
  mDeleted := TDictionary<string, Boolean>.Create;
  mCopied := TDictionary<string, Boolean>.Create;
  try
    for mItem in APaths do
    begin
      if mItem.Action = 'D' then
      begin
        mDeleted.AddOrSetValue(mItem.Path, True);
      end;
      if mItem.CopyFrom <> '' then
      begin
        mCopied.AddOrSetValue(mItem.CopyFrom, True);
      end;
    end;
    for mItem in APaths do
    begin
      if TrySvnChange(mItem, APrefix, mDeleted, mCopied, mChange) then
      begin
        Result := Result + [mChange];
      end;
    end;
  finally
    mCopied.Free;
    mDeleted.Free;
  end;
end;

/// <summary>Neueste Revision zuerst, bei Gleichstand nach dem Text der Revision.</summary>
function CompareSvnCommits(const ALeft, ARight: THotspotCommit): Integer;
begin
  Result := StrToIntDef(ARight.Revision, 0) - StrToIntDef(ALeft.Revision, 0);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Revision, ARight.Revision);
  end;
end;

class function THotspotHistory.ParseSvnLog(const AXml, APrefix: string): TArray<THotspotCommit>;
var
  mList: TList<THotspotCommit>;
  mEntry, mEntryEnd, mTagEnd: Integer;
  mCommit: THotspotCommit;
begin
  mList := TList<THotspotCommit>.Create;
  try
    mEntry := Pos('<logentry', AXml);
    while mEntry > 0 do
    begin
      mEntryEnd := PosEx('</logentry>', AXml, mEntry);
      if mEntryEnd = 0 then
      begin
        Break;
      end;
      mCommit := ReadSvnHead(AXml, mEntry, mEntryEnd, mTagEnd);
      mCommit.Files := SvnFiles(ReadSvnPaths(AXml, mTagEnd, mEntryEnd), APrefix);
      if Length(mCommit.Files) > 0 then
      begin
        mList.Add(mCommit);
      end;
      mEntry := PosEx('<logentry', AXml, mEntryEnd);
    end;
    // svn log -r HEAD:{…} liefert die neueste zuerst; sicherheitshalber stabil nach Revision.
    mList.Sort(TComparer<THotspotCommit>.Construct(
      function(const ALeft, ARight: THotspotCommit): Integer
      begin
        Result := CompareSvnCommits(ALeft, ARight);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

const
  // Marke: ältere Änderungen unter diesem Pfad gehören zu einer früheren Datei.
  cGonePath = #0;

/// <summary>AFile mit dem heutigen Pfad aus ANames; merkt Umbenennungen und Neuanlagen vor. False, wenn der Pfad
/// zu einer früheren Datei gehört.</summary>
function TryFollowFile(ANames: TDictionary<string, string>; const AFile: THotspotFileChange;
  out AFollowed: THotspotFileChange): Boolean;
var
  mCurrent: string;
begin
  AFollowed := Default(THotspotFileChange);
  if not ANames.TryGetValue(LowerCase(AFile.Path), mCurrent) then
  begin
    mCurrent := AFile.Path;
  end;
  Result := mCurrent <> cGonePath;
  if not Result then
  begin
    Exit;
  end;
  case AFile.Kind of
    THotspotChangeKind.Renamed:
      if AFile.OldPath <> '' then
      begin
        ANames.AddOrSetValue(LowerCase(AFile.OldPath), mCurrent);
      end;
    THotspotChangeKind.Added:
      ANames.AddOrSetValue(LowerCase(AFile.Path), cGonePath);
    THotspotChangeKind.Modified, THotspotChangeKind.Deleted: ;
  end;
  AFollowed := THotspotFileChange.Make(mCurrent, AFile.OldPath, AFile.Kind, AFile.Added, AFile.Deleted);
end;

class function THotspotHistory.FollowRenames(const ACommits: TArray<THotspotCommit>): TArray<THotspotCommit>;
var
  mNames: TDictionary<string, string>;
  mCommit, mFollowed: THotspotCommit;
  mFile, mChange: THotspotFileChange;
  mFiles: TList<THotspotFileChange>;
  mList: TList<THotspotCommit>;
begin
  mNames := TDictionary<string, string>.Create;
  mFiles := TList<THotspotFileChange>.Create;
  mList := TList<THotspotCommit>.Create;
  try
    for mCommit in ACommits do
    begin
      mFiles.Clear;
      for mFile in mCommit.Files do
      begin
        if TryFollowFile(mNames, mFile, mChange) then
        begin
          mFiles.Add(mChange);
        end;
      end;
      if mFiles.Count > 0 then
      begin
        mFollowed := mCommit;
        mFollowed.Files := mFiles.ToArray;
        mList.Add(mFollowed);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mFiles.Free;
    mNames.Free;
  end;
end;

class procedure THotspotHistory.CountPatch(const ALines: TArray<string>; out AAdded, ADeleted: Integer);
var
  mLine: string;
begin
  AAdded := 0;
  ADeleted := 0;
  for mLine in ALines do
  begin
    if StartsStr('+++', mLine) or StartsStr('---', mLine) then
    begin
      Continue;
    end
    else if StartsStr('+', mLine) then
    begin
      Inc(AAdded);
    end
    else if StartsStr('-', mLine) then
    begin
      Inc(ADeleted);
    end;
  end;
end;

end.
