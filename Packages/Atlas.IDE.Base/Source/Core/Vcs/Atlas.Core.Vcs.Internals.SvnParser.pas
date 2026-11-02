unit Atlas.Core.Vcs.Internals.SvnParser;

// Liest die Ausgaben von svn für die Versionsverwaltung (#571, Weg aus #276).
// Alle Aufrufe mit --xml: Die Ausgabe ist dann UTF-8, unabhängig von Sprache
// und Codepage der Konsole.
//   svn info --xml        Wurzel der Arbeitskopie, Pfad im Repository, Revision
//   svn status --xml      geänderte, neue und unversionierte Dateien
//   svn blame --xml       Zeilenherkunft
//   svn log --xml         Revisionen mit Autor, Zeit und Nachricht (#1275)
// Nur „svn log --diff“ (#1275) gibt es nicht als XML: Je Revision eine Zeile
// aus 72 „-“, der Kopf „r12 | autor | zeit | 3 lines“ (die Anzahl der
// Nachrichtenzeilen steht vorn im letzten Feld, das Wort ist übersetzt), eine
// Leerzeile, die Nachricht und der Unterschied. Den Unterschied liest der
// Parser nach seinen Blockgrößen; eine gelöschte Zeile aus lauter „-“ beendet
// die Revision deshalb nicht. Der Text kommt in der Kodierung der Konsole;
// gebraucht werden nur Revision und Unterschied.
// Der Branch ist der Pfad im Repository: "^/trunk" wird "trunk",
// "^/projekt/branches/x/src" wird "branches/x"; ohne übliche Ablage
// (trunk, branches, tags) der ganze Pfad ohne "^/".
// Für die Entwicklung zu einem Issue (#1269):
//   svn log --xml -v --search <Text> -l <N> ^/   Commits mit Dateien im ganzen
//                                                Repository; Pfade im Repository
//                                                ("/branches/x/src/A.pas")
//   svn list --xml ^/branches                     Branches mit letztem Commit
// Ein Pfad im Repository gehört zur Arbeitskopie, wenn er im selben Projekt
// liegt (Teil vor trunk/branches/tags) und hinter dem Branch mit dem Unterordner
// der Arbeitskopie beginnt: "/branches/x/src/A.pas" ist bei einer Arbeitskopie von
// "^/trunk" die Datei "src\A.pas" unter der Wurzel.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasSvnInfo = record
    /// <summary>Wurzel der Arbeitskopie (wcroot-abspath).</summary>
    Root: string;
    /// <summary>Pfad im Repository ohne "^/", z. B. "projekt/branches/x".</summary>
    RelativeUrl: string;
    /// <summary>Revision der Arbeitskopie.</summary>
    Revision: string;
  end;

  /// <summary>Revision aus svn log --diff (#1275).</summary>
  TAtlasSvnLogDiff = record
    Revision: string;
    /// <summary>Zeilen des Unterschieds (ab „Index:“).</summary>
    Patch: TArray<string>;
  end;

  TAtlasSvnParser = class
  public const
    /// <summary>Trennzeile vor jeder Revision in svn log.</summary>
    LogSeparator = '------------------------------------------------------------------------';
  public
    /// <summary>Ausgabe von "svn info --xml" (erster Eintrag).</summary>
    class function ParseInfo(const AText: string): TAtlasSvnInfo; static;
    /// <summary>Branch aus dem Pfad im Repository (siehe Kopf der Unit).</summary>
    class function BranchOf(const ARelativeUrl: string): string; static;
    /// <summary>Ausgabe von "svn status --xml"; relative Pfade gelten unter ARoot. Unveränderte, ignorierte
    /// und externe Einträge entfallen.</summary>
    class function ParseStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>; static;
    /// <summary>Ausgabe von "svn blame --xml".</summary>
    class function ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>; static;
    /// <summary>Art aus wc-status item und props; False für Einträge ohne Änderung.</summary>
    class function KindOf(const AItem, AProps: string; out AKind: TAtlasVcsChangeKind): Boolean; static;
    /// <summary>Ausgabe von "svn log --xml" (#1275): Revision, Autor, Zeit und Nachricht, ohne Patch.</summary>
    class function ParseLog(const AText: string): TArray<TAtlasVcsLineCommit>; overload; static;
    /// <summary>Ausgabe von "svn log --diff" (#1275): je Revision ihr Unterschied, in der Reihenfolge der Ausgabe.
    /// Löst EAtlasVcsParse aus, wenn ein Kopf fehlt.</summary>
    class function ParseLogDiff(const AText: string): TArray<TAtlasSvnLogDiff>; static;
    /// <summary>Ausgabe von "svn log --xml -v"; ARelativeUrl: Pfad der Arbeitskopie im Repository (ohne "^/"),
    /// ARoot ihre Wurzel. Dateien außerhalb der Arbeitskopie behalten nur RepositoryPath.</summary>
    class function ParseLog(const AText, ARoot, ARelativeUrl: string): TArray<TAtlasVcsLogEntry>; overload; static;
    /// <summary>Ausgabe von "svn list --xml": Einträge mit Name und letztem Commit; ACurrent ist der Branch der
    /// Arbeitskopie (wie BranchOf, z. B. "branches/x").</summary>
    class function ParseList(const AText, ACurrent: string): TArray<TAtlasVcsRef>; static;
    /// <summary>Vollständiger Pfad in der Arbeitskopie zu ARepositoryPath; '' außerhalb (siehe Kopf der Unit).
    /// </summary>
    class function LocalPath(const ARoot, ARelativeUrl, ARepositoryPath: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.LineTrace;

class function TAtlasSvnParser.ParseInfo(const AText: string): TAtlasSvnInfo;
var
  Reader: TAtlasVcsXmlReader;
  Element: string;
  Depth: Integer;
  Url, RepositoryRoot: string;
begin
  Result.Root := '';
  Result.RelativeUrl := '';
  Result.Revision := '';
  Url := '';
  RepositoryRoot := '';
  Element := '';
  Depth := 0;
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          begin
            if Reader.Name = 'entry' then
            begin
              Inc(Depth);
              // Nur der erste Eintrag zählt.
              if Depth = 1 then
                Result.Revision := Reader.Attr('revision');
            end;
            if not Reader.EmptyElement then
              Element := Reader.Name;
          end;
        TAtlasVcsXmlNode.EndTag:
          begin
            Element := '';
            if Reader.Name = 'entry' then
              Break;
          end;
        TAtlasVcsXmlNode.Text:
          if Element = 'wcroot-abspath' then
            Result.Root := VcsNormalizeDir(Reader.Value)
          else if Element = 'relative-url' then
            Result.RelativeUrl := Trim(Reader.Value)
          else if Element = 'url' then
            Url := Trim(Reader.Value)
          else if Element = 'root' then
            RepositoryRoot := Trim(Reader.Value);
      end;
  finally
    Reader.Free;
  end;
  if Depth = 0 then
    raise EAtlasVcsParse.Create('svn info: kein Eintrag');
  // svn vor 1.8 kennt relative-url nicht: aus url und root bilden.
  if (Result.RelativeUrl = '') and (RepositoryRoot <> '') and (Copy(Url, 1, Length(RepositoryRoot)) = RepositoryRoot) then
    Result.RelativeUrl := '^' + Copy(Url, Length(RepositoryRoot) + 1, MaxInt);
  if Copy(Result.RelativeUrl, 1, 1) = '^' then
    Delete(Result.RelativeUrl, 1, 1);
  while Copy(Result.RelativeUrl, 1, 1) = '/' do
    Delete(Result.RelativeUrl, 1, 1);
end;

class function TAtlasSvnParser.BranchOf(const ARelativeUrl: string): string;
var
  Parts: TArray<string>;
  Index: Integer;
  Part: string;
begin
  Parts := ARelativeUrl.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Parts) do
  begin
    Part := LowerCase(Parts[Index]);
    if Part = 'trunk' then
      Exit(Parts[Index]);
    if ((Part = 'branches') or (Part = 'tags')) and (Index < High(Parts)) then
      Exit(Parts[Index] + '/' + Parts[Index + 1]);
  end;
  Result := string.Join('/', Parts);
end;

class function TAtlasSvnParser.KindOf(const AItem, AProps: string; out AKind: TAtlasVcsChangeKind): Boolean;
begin
  Result := True;
  if AItem = 'modified' then
    AKind := TAtlasVcsChangeKind.Modified
  else if AItem = 'added' then
    AKind := TAtlasVcsChangeKind.Added
  else if AItem = 'deleted' then
    AKind := TAtlasVcsChangeKind.Deleted
  else if AItem = 'replaced' then
    AKind := TAtlasVcsChangeKind.Replaced
  else if AItem = 'unversioned' then
    AKind := TAtlasVcsChangeKind.Untracked
  else if (AItem = 'conflicted') or (AProps = 'conflicted') then
    AKind := TAtlasVcsChangeKind.Conflicted
  else if (AItem = 'missing') or (AItem = 'incomplete') then
    AKind := TAtlasVcsChangeKind.Missing
  else if AItem = 'obstructed' then
    AKind := TAtlasVcsChangeKind.TypeChanged
  else if AItem = 'merged' then
    AKind := TAtlasVcsChangeKind.Modified
  else if AProps = 'modified' then
    // Nur Eigenschaften geändert (svn:eol-style und ähnliche).
    AKind := TAtlasVcsChangeKind.Modified
  else
  begin
    // normal, none, ignored, external
    AKind := TAtlasVcsChangeKind.Modified;
    Result := False;
  end;
end;

class function TAtlasSvnParser.ParseStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>;
var
  Reader: TAtlasVcsXmlReader;
  Path, Item, Props: string;
  Change: TAtlasVcsChange;
  Kind: TAtlasVcsChangeKind;
  InEntry: Boolean;
begin
  Result := nil;
  InEntry := False;
  Path := '';
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          if Reader.Name = 'entry' then
          begin
            InEntry := True;
            Path := Reader.Attr('path');
          end
          else if (Reader.Name = 'wc-status') and InEntry then
          begin
            Item := Reader.Attr('item');
            Props := Reader.Attr('props');
            if KindOf(Item, Props, Kind) and (Path <> '') then
            begin
              // Absolute Pfade (bei absolutem Ziel) bleiben, relative gelten unter der Wurzel.
              if (Pos(':', Path) = 2) or (Copy(Path, 1, 1) = '/') or (Copy(Path, 1, 2) = '\\') then
                Change.Path := VcsNormalizeDir(Path)
              else
                Change.Path := VcsFullPath(ARoot, Path);
              Change.OldPath := '';
              Change.Kind := Kind;
              Change.Staged := False;
              Change.Unstaged := True;
              Result := Result + [Change];
            end;
            // Nur der erste wc-status je Eintrag; repos-status (mit --show-updates) folgt getrennt.
            InEntry := False;
          end;
        TAtlasVcsXmlNode.EndTag:
          if Reader.Name = 'entry' then
            InEntry := False;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Reader.Free;
  end;
end;

/// <summary>Zerlegt einen Pfad im Repository in Projekt (vor trunk/branches/x/tags/x), Branch und Rest; False ohne
/// übliche Ablage.</summary>
function SplitLayout(const APath: string; out AProject, ABranch, ARest: string): Boolean;
var
  mParts: TArray<string>;
  mIndex, mStart: Integer;
  mPart: string;
begin
  AProject := '';
  ABranch := '';
  ARest := '';
  mParts := APath.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mParts) do
  begin
    mPart := LowerCase(mParts[mIndex]);
    mStart := -1;
    if mPart = 'trunk' then
      mStart := mIndex + 1
    else if ((mPart = 'branches') or (mPart = 'tags')) and (mIndex < High(mParts)) then
      mStart := mIndex + 2;
    if mStart < 0 then
      Continue;
    AProject := string.Join('/', Copy(mParts, 0, mIndex));
    ABranch := string.Join('/', Copy(mParts, mIndex, mStart - mIndex));
    ARest := string.Join('/', Copy(mParts, mStart, Length(mParts) - mStart));
    Exit(True);
  end;
  Result := False;
end;

class function TAtlasSvnParser.LocalPath(const ARoot, ARelativeUrl, ARepositoryPath: string): string;
var
  mProject, mBranch, mRest, mWcProject, mWcBranch, mWcRest: string;
begin
  Result := '';
  if not SplitLayout(ARepositoryPath, mProject, mBranch, mRest) then
    Exit;
  if not SplitLayout(ARelativeUrl, mWcProject, mWcBranch, mWcRest) or not SameText(mProject, mWcProject) then
    Exit;
  // Arbeitskopie eines Unterordners: nur Dateien darunter, relativ dazu.
  if mWcRest <> '' then
  begin
    if not SameText(Copy(mRest, 1, Length(mWcRest) + 1), mWcRest + '/') then
      Exit;
    mRest := Copy(mRest, Length(mWcRest) + 2, MaxInt);
  end;
  if mRest <> '' then
    Result := VcsFullPath(ARoot, mRest);
end;

function ActionKind(const AAction: string): TAtlasVcsChangeKind;
begin
  if AAction = 'A' then
    Result := TAtlasVcsChangeKind.Added
  else if AAction = 'D' then
    Result := TAtlasVcsChangeKind.Deleted
  else if AAction = 'R' then
    Result := TAtlasVcsChangeKind.Replaced
  else
    Result := TAtlasVcsChangeKind.Modified;
end;

class function TAtlasSvnParser.ParseLog(const AText, ARoot, ARelativeUrl: string): TArray<TAtlasVcsLogEntry>;
var
  mReader: TAtlasVcsXmlReader;
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mElement, mKind: string;
  mInEntry: Boolean;
  mDate: TDateTime;
  mBreak: Integer;
  mFiles: TList<TAtlasVcsLogFile>;
  mEntries: TList<TAtlasVcsLogEntry>;
begin
  mEntries := TList<TAtlasVcsLogEntry>.Create;
  mFiles := TList<TAtlasVcsLogFile>.Create;
  mReader := TAtlasVcsXmlReader.Create(AText);
  try
    mInEntry := False;
    mElement := '';
    mKind := '';
    mEntry := Default(TAtlasVcsLogEntry);
    mFile := Default(TAtlasVcsLogFile);
    while mReader.Next do
      case mReader.Node of
        TAtlasVcsXmlNode.StartTag:
          if mReader.Name = 'logentry' then
          begin
            mEntry := Default(TAtlasVcsLogEntry);
            mEntry.Revision := mReader.Attr('revision');
            if mEntry.Revision = '' then
              raise EAtlasVcsParse.Create('svn log: revision fehlt');
            mFiles.Clear;
            mInEntry := not mReader.EmptyElement;
            if not mInEntry then
              mEntries.Add(mEntry);
          end
          else if mInEntry and (mReader.Name = 'path') then
          begin
            mFile := Default(TAtlasVcsLogFile);
            mFile.Kind := ActionKind(mReader.Attr('action'));
            mKind := mReader.Attr('kind');
            if not mReader.EmptyElement then
              mElement := 'path';
          end
          else if not mReader.EmptyElement then
            mElement := mReader.Name;
        TAtlasVcsXmlNode.EndTag:
          begin
            if mInEntry and (mReader.Name = 'path') and (mFile.RepositoryPath <> '') and (mKind <> 'dir') then
            begin
              mFile.Path := LocalPath(ARoot, ARelativeUrl, mFile.RepositoryPath);
              mFiles.Add(mFile);
            end
            else if mInEntry and (mReader.Name = 'logentry') then
            begin
              mEntry.Files := mFiles.ToArray;
              mEntries.Add(mEntry);
              mInEntry := False;
            end;
            mElement := '';
          end;
        TAtlasVcsXmlNode.Text:
          if mInEntry then
            if mElement = 'author' then
              mEntry.Author := mReader.Value
            else if (mElement = 'date') and VcsParseIsoDate(mReader.Value, mDate) then
              mEntry.Date := mDate
            else if mElement = 'path' then
              mFile.RepositoryPath := Trim(mReader.Value)
            else if mElement = 'msg' then
            begin
              mEntry.Message := StringReplace(mReader.Value, #13#10, #10, [rfReplaceAll]).TrimRight([#10, #13, ' ']);
              mBreak := Pos(#10, mEntry.Message);
              if mBreak > 0 then
                mEntry.Summary := Copy(mEntry.Message, 1, mBreak - 1)
              else
                mEntry.Summary := mEntry.Message;
            end;
      end;
    Result := mEntries.ToArray;
  finally
    mReader.Free;
    mFiles.Free;
    mEntries.Free;
  end;
end;

class function TAtlasSvnParser.ParseList(const AText, ACurrent: string): TArray<TAtlasVcsRef>;
var
  mReader: TAtlasVcsXmlReader;
  mRef: TAtlasVcsRef;
  mElement: string;
  mInEntry: Boolean;
  mDate: TDateTime;
begin
  Result := nil;
  mInEntry := False;
  mElement := '';
  mRef := Default(TAtlasVcsRef);
  mReader := TAtlasVcsXmlReader.Create(AText);
  try
    while mReader.Next do
      case mReader.Node of
        TAtlasVcsXmlNode.StartTag:
          if mReader.Name = 'entry' then
          begin
            mRef := Default(TAtlasVcsRef);
            mRef.Remote := True;
            // Nur Ordner sind Branches.
            mInEntry := (mReader.Attr('kind') = 'dir') and not mReader.EmptyElement;
          end
          else if not mReader.EmptyElement then
            mElement := mReader.Name;
        TAtlasVcsXmlNode.EndTag:
          begin
            if mInEntry and (mReader.Name = 'entry') then
            begin
              mInEntry := False;
              if mRef.Name <> '' then
              begin
                mRef.LocalName := mRef.Name;
                mRef.Current := SameText('branches/' + mRef.Name, ACurrent);
                Result := Result + [mRef];
              end;
            end;
            mElement := '';
          end;
        TAtlasVcsXmlNode.Text:
          if mInEntry then
            if mElement = 'name' then
              mRef.Name := Trim(mReader.Value)
            else if (mElement = 'date') and VcsParseIsoDate(mReader.Value, mDate) then
              mRef.TipDate := mDate;
      end;
  finally
    mReader.Free;
  end;
end;

class function TAtlasSvnParser.ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>;
var
  Reader: TAtlasVcsXmlReader;
  Item: TAtlasVcsBlameLine;
  InEntry, InMerged: Boolean;
  Element: string;
  Number: Integer;
  Date: TDateTime;
begin
  Result := nil;
  InEntry := False;
  InMerged := False;
  Element := '';
  Item := Default(TAtlasVcsBlameLine);
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          if Reader.Name = 'entry' then
          begin
            Item := Default(TAtlasVcsBlameLine);
            if not TryStrToInt(Reader.Attr('line-number'), Number) then
              raise EAtlasVcsParse.Create('svn blame: line-number fehlt');
            Item.Line := Number;
            InEntry := True;
            if Reader.EmptyElement then
            begin
              Result := Result + [Item];
              InEntry := False;
            end;
          end
          else if Reader.Name = 'merged' then
            InMerged := not Reader.EmptyElement
          else if (Reader.Name = 'commit') and InEntry and not InMerged then
            Item.Revision := Reader.Attr('revision')
          else if not Reader.EmptyElement then
            Element := Reader.Name;
        TAtlasVcsXmlNode.EndTag:
          begin
            Element := '';
            if Reader.Name = 'merged' then
              InMerged := False
            else if (Reader.Name = 'entry') and InEntry then
            begin
              Result := Result + [Item];
              InEntry := False;
            end;
          end;
        TAtlasVcsXmlNode.Text:
          if InEntry and not InMerged then
            if Element = 'author' then
              Item.Author := Reader.Value
            else if (Element = 'date') and VcsParseIsoDate(Reader.Value, Date) then
              Item.Date := Date;
      end;
  finally
    Reader.Free;
  end;
end;

class function TAtlasSvnParser.ParseLog(const AText: string): TArray<TAtlasVcsLineCommit>;
var
  mReader: TAtlasVcsXmlReader;
  mItem: TAtlasVcsLineCommit;
  mInEntry: Boolean;
  mElement: string;
  mDate: TDateTime;
begin
  Result := nil;
  mInEntry := False;
  mElement := '';
  mItem := Default(TAtlasVcsLineCommit);
  mReader := TAtlasVcsXmlReader.Create(AText);
  try
    while mReader.Next do
      case mReader.Node of
        TAtlasVcsXmlNode.StartTag:
          if mReader.Name = 'logentry' then
          begin
            mItem := Default(TAtlasVcsLineCommit);
            mItem.Revision := mReader.Attr('revision');
            if mItem.Revision = '' then
              raise EAtlasVcsParse.Create('svn log: revision fehlt');
            mInEntry := not mReader.EmptyElement;
            if not mInEntry then
              Result := Result + [mItem];
          end
          else if not mReader.EmptyElement then
            mElement := mReader.Name;
        TAtlasVcsXmlNode.EndTag:
          begin
            mElement := '';
            if (mReader.Name = 'logentry') and mInEntry then
            begin
              mItem.Message := TrimRight(mItem.Message);
              Result := Result + [mItem];
              mInEntry := False;
            end;
          end;
        TAtlasVcsXmlNode.Text:
          if mInEntry then
            if mElement = 'author' then
              mItem.Author := mReader.Value
            else if (mElement = 'date') and VcsParseIsoDate(mReader.Value, mDate) then
              mItem.Date := mDate
            else if mElement = 'msg' then
              mItem.Message := mItem.Message + mReader.Value;
      end;
  finally
    mReader.Free;
  end;
end;

/// <summary>Kopf "r12 | autor | zeit | 3 lines": Revision und Anzahl der Nachrichtenzeilen.</summary>
function ReadLogHeader(const ALine: string; out ARevision: string; out ALines: Integer): Boolean;
var
  mBar, mPos: Integer;
  mLast: string;
begin
  ARevision := '';
  ALines := 0;
  mBar := Pos(' | ', ALine);
  Result := (Length(ALine) > 1) and (ALine[1] = 'r') and (mBar > 2);
  if not Result then
    Exit;
  ARevision := Copy(ALine, 2, mBar - 2);
  for mPos := 1 to Length(ARevision) do
    if not CharInSet(ARevision[mPos], ['0'..'9']) then
      Exit(False);
  mLast := ALine;
  while Pos(' | ', mLast) > 0 do
    mLast := Copy(mLast, Pos(' | ', mLast) + 3, MaxInt);
  mPos := 1;
  while (mPos <= Length(mLast)) and CharInSet(mLast[mPos], ['0'..'9']) do
    Inc(mPos);
  if (mPos = 1) or (mPos > 7) or not TryStrToInt(Copy(mLast, 1, mPos - 1), ALines) then
    ALines := 0;
end;

class function TAtlasSvnParser.ParseLogDiff(const AText: string): TArray<TAtlasSvnLogDiff>;
var
  mLines, mPatch: TArray<string>;
  mIndex, mCount, mMessage, mOld, mNew, mFound: Integer;
  mItem: TAtlasSvnLogDiff;
  mHunk: TAtlasVcsHunk;
  mLine: string;

  procedure Add(const ALine: string);
  begin
    if mCount = Length(mPatch) then
      SetLength(mPatch, mCount * 2 + 16);
    mPatch[mCount] := ALine;
    Inc(mCount);
  end;

begin
  // Die Zahl der Revisionen ist vorher unbekannt: Platz verdoppeln, am Ende kürzen.
  Result := nil;
  mFound := 0;
  mLines := AText.Split([#10]);
  for mIndex := 0 to High(mLines) do
    mLines[mIndex] := mLines[mIndex].TrimRight([#13]);
  mIndex := 0;
  while (mIndex <= High(mLines)) and (mLines[mIndex] <> LogSeparator) do
    Inc(mIndex);
  while mIndex <= High(mLines) do
  begin
    // mLines[mIndex] ist eine Trennzeile; danach ein Kopf oder das Ende.
    Inc(mIndex);
    if (mIndex > High(mLines)) or (mLines[mIndex] = '') then
      Break;
    mItem := Default(TAtlasSvnLogDiff);
    if not ReadLogHeader(mLines[mIndex], mItem.Revision, mMessage) then
      raise EAtlasVcsParse.Create('svn log --diff: Kopf erwartet');
    Inc(mIndex);
    // Leerzeile, dann die Nachricht.
    if (mIndex <= High(mLines)) and (mLines[mIndex] = '') then
      Inc(mIndex);
    Inc(mIndex, mMessage);
    mPatch := nil;
    mCount := 0;
    while (mIndex <= High(mLines)) and (mLines[mIndex] <> LogSeparator) do
    begin
      mLine := mLines[mIndex];
      Inc(mIndex);
      if (mCount = 0) and (mLine = '') then
        Continue;
      Add(mLine);
      if not TAtlasVcsLineTrace.ParseHunkHeader(mLine, mHunk) then
        Continue;
      // Block nach seinen Größen lesen: Auch "-----…" ist hier eine Zeile des Unterschieds.
      mOld := mHunk.OldCount;
      mNew := mHunk.NewCount;
      while (mIndex <= High(mLines)) and ((mOld > 0) or (mNew > 0)) do
      begin
        mLine := mLines[mIndex];
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
            ;
        else
          Break;
        end;
        Add(mLines[mIndex]);
        Inc(mIndex);
      end;
    end;
    while (mCount > 0) and (mPatch[mCount - 1] = '') do
      Dec(mCount);
    SetLength(mPatch, mCount);
    mItem.Patch := mPatch;
    if mFound = Length(Result) then
      SetLength(Result, mFound * 2 + 4);
    Result[mFound] := mItem;
    Inc(mFound);
  end;
  SetLength(Result, mFound);
end;

end.
