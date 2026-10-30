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
    GitRecord = #$1E;
    GitField = #$1F;
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
    /// <summary>SVN-Zeitpunkt "2026-10-29T21:24:52.123456Z" bzw. ISO ohne Bruchteil; False bei anderem Format.</summary>
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
    Exit;
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
    Result := -1;
end;

class function THotspotHistory.ParseGitLog(const AText: string): TArray<THotspotCommit>;
var
  mList: TList<THotspotCommit>;
  mFiles: TList<THotspotFileChange>;
  mRecord, mLine, mOld, mNew: string;
  mLines, mHead, mFields: TArray<string>;
  mCommit: THotspotCommit;
  mSeconds: Int64;
  mIndex: Integer;
begin
  mList := TList<THotspotCommit>.Create;
  mFiles := TList<THotspotFileChange>.Create;
  try
    for mRecord in AText.Split([GitRecord]) do
    begin
      mLines := StringReplace(mRecord, #13, '', [rfReplaceAll]).Split([#10]);
      if (Length(mLines) = 0) or (Trim(mLines[0]) = '') then
        Continue;
      mHead := mLines[0].Split([GitField], 4);
      if (Length(mHead) < 3) or not TryStrToInt64(Trim(mHead[1]), mSeconds) then
        Continue;
      mCommit := Default(THotspotCommit);
      mCommit.Revision := Trim(mHead[0]);
      mCommit.Date := UnixToDateTime(mSeconds, True);
      mCommit.Author := Trim(mHead[2]);
      if Length(mHead) > 3 then
        mCommit.Summary := Trim(mHead[3]);
      mFiles.Clear;
      for mIndex := 1 to High(mLines) do
      begin
        mLine := mLines[mIndex];
        mFields := mLine.Split([#9], 3);
        if Length(mFields) < 3 then
          Continue;
        if SplitRename(mFields[2], mOld, mNew) then
          mFiles.Add(THotspotFileChange.Make(mNew, mOld, THotspotChangeKind.Renamed, CountOf(mFields[0]),
            CountOf(mFields[1])))
        else
          mFiles.Add(THotspotFileChange.Make(mFields[2], '', THotspotChangeKind.Modified, CountOf(mFields[0]),
            CountOf(mFields[1])));
      end;
      if mFiles.Count = 0 then
        Continue;
      mCommit.Files := mFiles.ToArray;
      mList.Add(mCommit);
    end;
    Result := mList.ToArray;
  finally
    mFiles.Free;
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

/// <summary>Text eines XML-Inhalts ohne Entitäten.</summary>
function XmlText(const AText: string): string;
var
  mIndex, mEnd, mCode: Integer;
  mName: string;
  mBuilder: TStringBuilder;
begin
  if Pos('&', AText) = 0 then
    Exit(AText);
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if AText[mIndex] = '&' then
      begin
        mEnd := PosEx(';', AText, mIndex);
        if mEnd > 0 then
        begin
          mName := Copy(AText, mIndex + 1, mEnd - mIndex - 1);
          mCode := -1;
          if mName = 'amp' then
            mCode := Ord('&')
          else if mName = 'lt' then
            mCode := Ord('<')
          else if mName = 'gt' then
            mCode := Ord('>')
          else if mName = 'quot' then
            mCode := Ord('"')
          else if mName = 'apos' then
            mCode := Ord('''')
          else if StartsText('#x', mName) then
            mCode := StrToIntDef('$' + Copy(mName, 3, MaxInt), -1)
          else if StartsText('#', mName) then
            mCode := StrToIntDef(Copy(mName, 2, MaxInt), -1);
          if (mCode >= 0) and (mCode <= $FFFF) then
          begin
            mBuilder.Append(Char(mCode));
            mIndex := mEnd + 1;
            Continue;
          end;
        end;
      end;
      mBuilder.Append(AText[mIndex]);
      Inc(mIndex);
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
    Exit;
  mStart := mStart + Length(AName) + 2;
  if mStart > Length(ATag) then
    Exit;
  mQuote := ATag[mStart];
  if (mQuote <> '"') and (mQuote <> '''') then
    Exit;
  mEnd := PosEx(mQuote, ATag, mStart + 1);
  if mEnd > 0 then
    Result := XmlText(Copy(ATag, mStart + 1, mEnd - mStart - 1));
end;

/// <summary>Inhalt des ersten Elements AName ab AFrom bis ALimit; '' ohne.</summary>
function XmlElement(const AXml, AName: string; AFrom, ALimit: Integer): string;
var
  mStart, mClose, mEnd: Integer;
begin
  Result := '';
  mStart := PosEx('<' + AName, AXml, AFrom);
  if (mStart = 0) or (mStart > ALimit) then
    Exit;
  mClose := PosEx('>', AXml, mStart);
  if (mClose = 0) or (AXml[mClose - 1] = '/') then
    Exit;
  mEnd := PosEx('</' + AName + '>', AXml, mClose);
  if (mEnd > 0) and (mEnd <= ALimit) then
    Result := XmlText(Copy(AXml, mClose + 1, mEnd - mClose - 1));
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
    mPrefix := mPrefix + '/';
  if mPrefix = '/' then
    mPrefix := '';
  if mPrefix = '' then
  begin
    ARelative := APath;
    if StartsStr('/', ARelative) then
      Delete(ARelative, 1, 1);
    Exit(ARelative <> '');
  end;
  if not StartsStr('/', mPrefix) then
    mPrefix := '/' + mPrefix;
  Result := StartsStr(mPrefix, APath) and (Length(APath) > Length(mPrefix));
  if Result then
    ARelative := Copy(APath, Length(mPrefix) + 1, MaxInt)
  else
    ARelative := '';
end;

class function THotspotHistory.ParseSvnLog(const AXml, APrefix: string): TArray<THotspotCommit>;
var
  mList: TList<THotspotCommit>;
  mFiles: TList<THotspotFileChange>;
  mPaths: TList<TSvnPath>;
  mDeleted, mCopied: TDictionary<string, Boolean>;
  mEntry, mEntryEnd, mTagEnd, mPathStart, mPathClose, mPathEnd: Integer;
  mTag, mRelative, mOld: string;
  mCommit: THotspotCommit;
  mItem: TSvnPath;
begin
  mList := TList<THotspotCommit>.Create;
  mFiles := TList<THotspotFileChange>.Create;
  mPaths := TList<TSvnPath>.Create;
  mDeleted := TDictionary<string, Boolean>.Create;
  mCopied := TDictionary<string, Boolean>.Create;
  try
    mEntry := Pos('<logentry', AXml);
    while mEntry > 0 do
    begin
      mEntryEnd := PosEx('</logentry>', AXml, mEntry);
      if mEntryEnd = 0 then
        Break;
      mTagEnd := PosEx('>', AXml, mEntry);
      mTag := Copy(AXml, mEntry, mTagEnd - mEntry);
      mCommit := Default(THotspotCommit);
      mCommit.Revision := XmlAttribute(mTag, 'revision');
      mCommit.Author := Trim(XmlElement(AXml, 'author', mTagEnd, mEntryEnd));
      mCommit.Summary := Trim(StringReplace(XmlElement(AXml, 'msg', mTagEnd, mEntryEnd), #13, '', [rfReplaceAll]));
      if Pos(#10, mCommit.Summary) > 0 then
        mCommit.Summary := Trim(Copy(mCommit.Summary, 1, Pos(#10, mCommit.Summary) - 1));
      if not TryParseIsoDate(Trim(XmlElement(AXml, 'date', mTagEnd, mEntryEnd)), mCommit.Date) then
        mCommit.Date := 0;
      mPaths.Clear;
      mDeleted.Clear;
      mCopied.Clear;
      mPathStart := PosEx('<path ', AXml, mTagEnd);
      while (mPathStart > 0) and (mPathStart < mEntryEnd) do
      begin
        mPathClose := PosEx('>', AXml, mPathStart);
        mPathEnd := PosEx('</path>', AXml, mPathClose);
        if (mPathClose = 0) or (mPathEnd = 0) or (mPathEnd > mEntryEnd) then
          Break;
        mTag := Copy(AXml, mPathStart, mPathClose - mPathStart);
        mItem.Action := XmlAttribute(mTag, 'action');
        mItem.Kind := XmlAttribute(mTag, 'kind');
        mItem.CopyFrom := XmlAttribute(mTag, 'copyfrom-path');
        mItem.Path := Trim(XmlText(Copy(AXml, mPathClose + 1, mPathEnd - mPathClose - 1)));
        mPaths.Add(mItem);
        if mItem.Action = 'D' then
          mDeleted.AddOrSetValue(mItem.Path, True);
        if mItem.CopyFrom <> '' then
          mCopied.AddOrSetValue(mItem.CopyFrom, True);
        mPathStart := PosEx('<path ', AXml, mPathEnd);
      end;
      mFiles.Clear;
      for mItem in mPaths do
      begin
        // Ordner zählen nicht; alte Server lassen kind weg.
        if (mItem.Kind = 'dir') or not RelativeToPrefix(mItem.Path, APrefix, mRelative) then
          Continue;
        if mItem.Action = 'D' then
        begin
          // Die gelöschte Quelle einer Umbenennung steht beim neuen Pfad.
          if not mCopied.ContainsKey(mItem.Path) then
            mFiles.Add(THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Deleted, -1, -1));
          Continue;
        end;
        if (mItem.CopyFrom <> '') and mDeleted.ContainsKey(mItem.CopyFrom) and
          RelativeToPrefix(mItem.CopyFrom, APrefix, mOld) then
          mFiles.Add(THotspotFileChange.Make(mRelative, mOld, THotspotChangeKind.Renamed, -1, -1))
        else if mItem.Action = 'A' then
          mFiles.Add(THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Added, -1, -1))
        else
          mFiles.Add(THotspotFileChange.Make(mRelative, '', THotspotChangeKind.Modified, -1, -1));
      end;
      if mFiles.Count > 0 then
      begin
        mCommit.Files := mFiles.ToArray;
        mList.Add(mCommit);
      end;
      mEntry := PosEx('<logentry', AXml, mEntryEnd);
    end;
    // svn log -r HEAD:{…} liefert die neueste zuerst; sicherheitshalber stabil nach Revision.
    mList.Sort(TComparer<THotspotCommit>.Construct(
      function(const ALeft, ARight: THotspotCommit): Integer
      begin
        Result := StrToIntDef(ARight.Revision, 0) - StrToIntDef(ALeft.Revision, 0);
        if Result = 0 then
          Result := CompareStr(ALeft.Revision, ARight.Revision);
      end));
    Result := mList.ToArray;
  finally
    mCopied.Free;
    mDeleted.Free;
    mPaths.Free;
    mFiles.Free;
    mList.Free;
  end;
end;

class function THotspotHistory.FollowRenames(const ACommits: TArray<THotspotCommit>): TArray<THotspotCommit>;
const
  // Marke: ältere Änderungen unter diesem Pfad gehören zu einer früheren Datei.
  cGone = #0;
var
  mNames: TDictionary<string, string>;
  mCommit, mFollowed: THotspotCommit;
  mFile: THotspotFileChange;
  mFiles: TList<THotspotFileChange>;
  mList: TList<THotspotCommit>;
  mCurrent: string;
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
        if not mNames.TryGetValue(LowerCase(mFile.Path), mCurrent) then
          mCurrent := mFile.Path;
        if mCurrent = cGone then
          Continue;
        case mFile.Kind of
          THotspotChangeKind.Renamed:
            if mFile.OldPath <> '' then
              mNames.AddOrSetValue(LowerCase(mFile.OldPath), mCurrent);
          THotspotChangeKind.Added:
            mNames.AddOrSetValue(LowerCase(mFile.Path), cGone);
        end;
        mFiles.Add(THotspotFileChange.Make(mCurrent, mFile.OldPath, mFile.Kind, mFile.Added, mFile.Deleted));
      end;
      if mFiles.Count = 0 then
        Continue;
      mFollowed := mCommit;
      mFollowed.Files := mFiles.ToArray;
      mList.Add(mFollowed);
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
    if StartsStr('+++', mLine) or StartsStr('---', mLine) then
      Continue
    else if StartsStr('+', mLine) then
      Inc(AAdded)
    else if StartsStr('-', mLine) then
      Inc(ADeleted);
end;

end.
