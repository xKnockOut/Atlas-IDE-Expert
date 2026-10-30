unit Atlas.Core.Vcs.WorkingCopies;

// Arbeitskopien eines Projekts samt Externals bzw. Submodulen (#1292), ohne
// VCL. Kommen die Packages einer Gruppe über svn:externals, ist jeder
// External-Ordner eine eigene Arbeitskopie mit eigenem Pfad und eigener
// Revision; die Tabelle „Arbeitskopien“ zeigt sie zusammen:
//   Kasse              ^/Kasse/branches/KASSE-42   r48231          2
//   └ Packages\Basis   ^/Packages/Basis/trunk      r48190 · fest   0
// Collect liest ohne Server: Kopf der Wurzel, svn:externals (Parser aus
// #1291) und svn status --xml (je External ein eigener target-Abschnitt,
// Einträge mit item="external" nennen auch verschachtelte Externals); Git
// liest git submodule status. FillRevision holt danach je Zeile die Revision
// (svnversion), damit sich die Tabelle zeilenweise füllt. „Neu auf dem
// Server“ zählt CheckServer nur auf Klick (svn log). Pin schreibt die Zeile
// eines Externals im definierenden Ordner auf die Revision der
// External-Arbeitskopie fest (propset, ohne Commit). Folders liefert nur die
// Ordner (ohne svn:externals) und Split teilt Änderungen der Wurzel auf sie
// auf („Nicht gesichert“, #762).
// Nur im Plugin (nicht im Server), wie BranchPlan.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasVcsWorkingCopyKind = (Main, External, Submodule);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Arbeitskopie: das Projekt selbst, ein External oder ein Submodul.</summary>
  TAtlasVcsWorkingCopyRow = record
    Kind: TAtlasVcsWorkingCopyKind;
    /// <summary>Ordner relativ zur Wurzel mit "/" ('' = Wurzel).</summary>
    Path: string;
    /// <summary>Vollständiger Ordner.</summary>
    Folder: string;
    /// <summary>Einrückung: 0 Wurzel, 1 External darunter, 2 External in einem External …</summary>
    Depth: Integer;
    /// <summary>SVN: Pfad im Repository ohne "^/" ('' fremdes Repository oder unbekannt); Git: Branch bzw.
    /// '' bei Submodulen.</summary>
    RepositoryPath: string;
    /// <summary>URL, wenn das External aus einem anderen Repository kommt; sonst ''.</summary>
    Url: string;
    /// <summary>Revision der Arbeitskopie (SVN die höchste aus svnversion, Git der kurze Hash); '' unbekannt.
    /// </summary>
    Revision: string;
    /// <summary>External mit fester Revision (-r bzw. Peg); FixedRevision ist sie.</summary>
    Fixed: Boolean;
    FixedRevision: string;
    /// <summary>Geänderte Dateien ohne unversionierte; -1 unbekannt.</summary>
    Changed: Integer;
    /// <summary>Neue Commits auf dem Server (CheckServer); -1 nicht geprüft.</summary>
    Incoming: Integer;
    /// <summary>Index in TAtlasVcsWorkingCopyList.Externals; -1 ohne (Wurzel, Submodul, nur aus dem Status).
    /// </summary>
    ExternalIndex: Integer;
    /// <summary>Ergebnis der letzten Abfrage dieser Zeile.</summary>
    Outcome: TAtlasVcsOutcome;
    /// <summary>Revision schon abgefragt (FillRevision).</summary>
    Loaded: Boolean;
    class function Make(AKind: TAtlasVcsWorkingCopyKind; const ARoot, APath: string): TAtlasVcsWorkingCopyRow;
      static;
    /// <summary>Ordner mit "\" ("Packages\Basis"); bei der Wurzel AName.</summary>
    function Caption(const AName: string): string;
    /// <summary>„Revision festschreiben …“ möglich: External ohne feste Revision mit bekannter Revision.</summary>
    function CanPin: Boolean;
  end;

  TAtlasVcsWorkingCopyList = record
    Kind: TAtlasVcsKind;
    Root: string;
    Outcome: TAtlasVcsOutcome;
    Rows: TArray<TAtlasVcsWorkingCopyRow>;
    /// <summary>SVN: Zeilen und Definitionen aus svn:externals (für Pin).</summary>
    Externals: TArray<TAtlasVcsSvnExternal>;
    Definitions: TArray<TAtlasVcsSvnExternalDefinition>;
    class function Empty: TAtlasVcsWorkingCopyList; static;
    /// <summary>Mehr als eine Arbeitskopie: die Tabelle lohnt sich.</summary>
    function Several: Boolean;
  end;

  TAtlasVcsWorkingCopies = class
  public
    /// <summary>Arbeitskopien unter AVcs ohne Server und ohne Revisionen der Externals (FillRevision):
    /// Wurzel mit Kopf, SVN die Externals aus svn:externals und svn status --xml mit geänderten Dateien je
    /// Arbeitskopie, Git die Submodule. Outcome der Wurzel; ohne Externals eine Zeile.</summary>
    class function Collect(const AVcs: IAtlasVersionControl): TAtlasVcsWorkingCopyList; static;
    /// <summary>SVN: Zeilen für ARoot (Pfad im Repository ARootPath, Revision ARevision) und die
    /// Verzeichnis-Externals aus AExternals; Datei-Externals entfallen. Externals, die nur AStatusXml nennt
    /// (verschachtelt), kommen dazu. Geänderte Dateien aus AStatusXml ('' = unbekannt).</summary>
    class function FromSvn(const ARoot, ARootPath, ARevision: string; const AExternals: TArray<TAtlasVcsSvnExternal>;
      const AStatusXml: string): TArray<TAtlasVcsWorkingCopyRow>; static;
    /// <summary>Git: Wurzel und je Zeile aus git submodule status ("+1a2b… Libs/Json (v1.2)") ein Submodul
    /// mit kurzem Hash; Submodule ohne Checkout ("-…") ohne Revision.</summary>
    class function FromSubmodules(const ARoot, ABranch, ARevision, AStatus: string): TArray<TAtlasVcsWorkingCopyRow>;
      static;
    /// <summary>Geänderte Dateien je Zeile aus svn status --xml: je target der Abschnitt der Arbeitskopie,
    /// gezählt wird modified, added, deleted, replaced, conflicted, missing, obstructed, incomplete und
    /// geänderte Eigenschaften; unversionierte nicht.</summary>
    class procedure CountChanges(var ARows: TArray<TAtlasVcsWorkingCopyRow>; const AStatusXml: string); static;
    /// <summary>Ordner der Externals, die AStatusXml mit item="external" nennt (relativ zur Wurzel, "/").
    /// </summary>
    class function StatusExternals(const AStatusXml: string): TArray<string>; static;
    /// <summary>Revision der Zeile AIndex (SVN svnversion des Ordners) über ASvn der Wurzel.</summary>
    class procedure FillRevision(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
      const ASvn: IAtlasVcsSvnWorkingCopy); static;
    /// <summary>Geänderte Dateien der Zeile AIndex aus der eigenen Arbeitskopie AVcs (Git-Submodule).</summary>
    class procedure FillChanges(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
      const AVcs: IAtlasVersionControl); static;
    /// <summary>„Neu auf dem Server“ für Zeile AIndex: Commits auf ihrem Pfad nach ihrer Revision (bei fester
    /// Revision nach dieser). Ohne Pfad (fremdes Repository, Git) bleibt Incoming -1.</summary>
    class function CheckServer(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
      const ASvn: IAtlasVcsSvnExternals): TAtlasVcsOutcome; static;
    /// <summary>Neuer Text von svn:externals im definierenden Ordner (AOwner) mit der Zeile von AIndex
    /// festgeschrieben auf deren Revision; False, wenn die Zeile das nicht erlaubt.</summary>
    class function PinnedText(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer; out AOwner,
      AText: string): Boolean; static;
    /// <summary>PinnedText über ASvn der Wurzel setzen (nur Arbeitskopie, kein Commit).</summary>
    class function Pin(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
      const ASvn: IAtlasVcsSvnExternals): TAtlasVcsOutcome; static;
    /// <summary>Nur die Ordner der Arbeitskopien unter AVcs ohne Server und ohne svn:externals (für „Nicht
    /// gesichert“, #762): SVN aus svn status --xml (item="external"), Git aus git submodule status. Ohne
    /// Externals bzw. bei Fehler nur die Wurzel; ohne Arbeitskopie leer.</summary>
    class function Folders(const AVcs: IAtlasVersionControl): TArray<TAtlasVcsWorkingCopyRow>; static;
    /// <summary>Je Zeile die Zahl der Änderungen aus AChanges (alle Arten; der Aufrufer filtert), jede in der
    /// tiefsten Zeile, deren Ordner sie enthält.</summary>
    class function Split(const AChanges: TArray<TAtlasVcsChange>;
      const ARows: TArray<TAtlasVcsWorkingCopyRow>): TArray<Integer>; static;
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnExternals,
  Atlas.Core.Vcs.Internals.SvnLayout;

function Slashed(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
  while Copy(Result, 1, 2) = './' do
    Delete(Result, 1, 2);
  if Result = '.' then
    Result := '';
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function Inside(const APath, AFolder: string): Boolean;
begin
  // AFolder '' (Wurzel) enthält alles.
  Result := (AFolder = '') or SameText(APath, AFolder) or SameText(Copy(APath, 1, Length(AFolder) + 1), AFolder + '/');
end;

function RowOf(const ARows: TArray<TAtlasVcsWorkingCopyRow>; const APath: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARows) do
    if SameText(ARows[mIndex].Path, APath) then
      Exit(mIndex);
  Result := -1;
end;

/// <summary>Zeile, deren Ordner APath enthält, mit dem längsten Ordner; -1 ohne.</summary>
function DeepestRow(const ARows: TArray<TAtlasVcsWorkingCopyRow>; const APath: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ARows) do
    if Inside(APath, ARows[mIndex].Path) and
      ((Result < 0) or (Length(ARows[mIndex].Path) > Length(ARows[Result].Path))) then
      Result := mIndex;
end;

procedure SortAndIndent(var ARows: TArray<TAtlasVcsWorkingCopyRow>);
var
  mIndex, mOther: Integer;
  mRow: TAtlasVcsWorkingCopyRow;
begin
  // Wurzel zuerst, dann nach Ordner (eindeutig, also stabil); ein Ordner steht so direkt unter dem darüber.
  for mIndex := 1 to High(ARows) do
  begin
    mRow := ARows[mIndex];
    mOther := mIndex - 1;
    while (mOther >= 0) and (ARows[mOther].Path <> '') and (CompareText(ARows[mOther].Path, mRow.Path) > 0) do
    begin
      ARows[mOther + 1] := ARows[mOther];
      Dec(mOther);
    end;
    ARows[mOther + 1] := mRow;
  end;
  for mIndex := 0 to High(ARows) do
  begin
    ARows[mIndex].Depth := 0;
    if ARows[mIndex].Path = '' then
      Continue;
    for mOther := 0 to High(ARows) do
      if (mOther <> mIndex) and Inside(ARows[mIndex].Path, ARows[mOther].Path) and
        not SameText(ARows[mIndex].Path, ARows[mOther].Path) then
        Inc(ARows[mIndex].Depth);
  end;
end;

{ TAtlasVcsWorkingCopyRow }

class function TAtlasVcsWorkingCopyRow.Make(AKind: TAtlasVcsWorkingCopyKind; const ARoot,
  APath: string): TAtlasVcsWorkingCopyRow;
begin
  Result := Default(TAtlasVcsWorkingCopyRow);
  Result.Kind := AKind;
  Result.Path := Slashed(APath);
  Result.Folder := VcsFullPath(ARoot, Result.Path);
  if Result.Path = '' then
    Result.Folder := VcsNormalizeDir(ARoot);
  Result.Changed := -1;
  Result.Incoming := -1;
  Result.ExternalIndex := -1;
  Result.Outcome := TAtlasVcsOutcome.Ok;
end;

function TAtlasVcsWorkingCopyRow.Caption(const AName: string): string;
begin
  if Path = '' then
    Exit(AName);
  Result := StringReplace(Path, '/', '\', [rfReplaceAll]);
end;

function TAtlasVcsWorkingCopyRow.CanPin: Boolean;
begin
  Result := (Kind = TAtlasVcsWorkingCopyKind.External) and not Fixed and (ExternalIndex >= 0) and
    (StrToIntDef(Revision, -1) >= 0);
end;

{ TAtlasVcsWorkingCopyList }

class function TAtlasVcsWorkingCopyList.Empty: TAtlasVcsWorkingCopyList;
begin
  Result := Default(TAtlasVcsWorkingCopyList);
  Result.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
end;

function TAtlasVcsWorkingCopyList.Several: Boolean;
begin
  Result := Length(Rows) > 1;
end;

{ TAtlasVcsWorkingCopies }

class function TAtlasVcsWorkingCopies.StatusExternals(const AStatusXml: string): TArray<string>;
var
  mReader: TAtlasVcsXmlReader;
  mPath: string;
  mInEntry: Boolean;
begin
  Result := nil;
  if Trim(AStatusXml) = '' then
    Exit;
  mPath := '';
  mInEntry := False;
  mReader := TAtlasVcsXmlReader.Create(AStatusXml);
  try
    while mReader.Next do
      if mReader.Node = TAtlasVcsXmlNode.StartTag then
      begin
        if mReader.Name = 'entry' then
        begin
          mInEntry := True;
          mPath := Slashed(mReader.Attr('path'));
        end
        else if (mReader.Name = 'wc-status') and mInEntry then
        begin
          // Einträge sind relativ zum Arbeitsordner von svn (wie das target "."), nicht zum target.
          if (mReader.Attr('item') = 'external') and (mPath <> '') then
            Result := Result + [mPath];
          mInEntry := False;
        end;
      end
      else if (mReader.Node = TAtlasVcsXmlNode.EndTag) and (mReader.Name = 'entry') then
        mInEntry := False;
  finally
    mReader.Free;
  end;
end;

class procedure TAtlasVcsWorkingCopies.CountChanges(var ARows: TArray<TAtlasVcsWorkingCopyRow>;
  const AStatusXml: string);
var
  mReader: TAtlasVcsXmlReader;
  mPath, mItem, mProps: string;
  mInEntry: Boolean;
  mIndex, mRow: Integer;
begin
  if Trim(AStatusXml) = '' then
    Exit;
  for mIndex := 0 to High(ARows) do
    if ARows[mIndex].Kind <> TAtlasVcsWorkingCopyKind.Submodule then
      ARows[mIndex].Changed := 0;
  mPath := '';
  mInEntry := False;
  mReader := TAtlasVcsXmlReader.Create(AStatusXml);
  try
    while mReader.Next do
      if mReader.Node = TAtlasVcsXmlNode.StartTag then
      begin
        if mReader.Name = 'entry' then
        begin
          mInEntry := True;
          mPath := Slashed(mReader.Attr('path'));
        end
        else if (mReader.Name = 'wc-status') and mInEntry then
        begin
          mInEntry := False;
          mItem := mReader.Attr('item');
          mProps := mReader.Attr('props');
          if not ((mItem = 'modified') or (mItem = 'added') or (mItem = 'deleted') or (mItem = 'replaced') or
            (mItem = 'conflicted') or (mItem = 'missing') or (mItem = 'obstructed') or (mItem = 'incomplete') or
            (mProps = 'modified') or (mProps = 'conflicted')) then
            Continue;
          // Jede Datei in der tiefsten Arbeitskopie, die sie enthält; der Ordner eines Externals selbst
          // (geänderte Eigenschaft) gehört zu ihm.
          mRow := DeepestRow(ARows, mPath);
          if mRow >= 0 then
            Inc(ARows[mRow].Changed);
        end;
      end
      else if (mReader.Node = TAtlasVcsXmlNode.EndTag) and (mReader.Name = 'entry') then
        mInEntry := False;
  finally
    mReader.Free;
  end;
end;

class function TAtlasVcsWorkingCopies.FromSvn(const ARoot, ARootPath, ARevision: string;
  const AExternals: TArray<TAtlasVcsSvnExternal>; const AStatusXml: string): TArray<TAtlasVcsWorkingCopyRow>;
var
  mRow: TAtlasVcsWorkingCopyRow;
  mIndex: Integer;
  mPath: string;
begin
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Main, ARoot, '');
  mRow.RepositoryPath := ARootPath;
  mRow.Revision := ARevision;
  mRow.Loaded := True;
  Result := TArray<TAtlasVcsWorkingCopyRow>.Create(mRow);
  for mIndex := 0 to High(AExternals) do
  begin
    // Datei-Externals sind keine eigene Arbeitskopie.
    if AExternals[mIndex].IsFile or (RowOf(Result, Slashed(AExternals[mIndex].Path)) >= 0) then
      Continue;
    mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.External, ARoot, AExternals[mIndex].Path);
    mRow.RepositoryPath := AExternals[mIndex].Source;
    if AExternals[mIndex].Foreign or (mRow.RepositoryPath = '') then
      mRow.Url := AExternals[mIndex].FullUrl;
    mRow.Fixed := AExternals[mIndex].Fixed;
    mRow.FixedRevision := AExternals[mIndex].Revision;
    if mRow.FixedRevision = '' then
      mRow.FixedRevision := AExternals[mIndex].Peg;
    mRow.ExternalIndex := mIndex;
    Result := Result + [mRow];
  end;
  for mPath in StatusExternals(AStatusXml) do
    if RowOf(Result, mPath) < 0 then
      Result := Result + [TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.External, ARoot, mPath)];
  SortAndIndent(Result);
  CountChanges(Result, AStatusXml);
end;

class function TAtlasVcsWorkingCopies.FromSubmodules(const ARoot, ABranch, ARevision,
  AStatus: string): TArray<TAtlasVcsWorkingCopyRow>;
var
  mRow: TAtlasVcsWorkingCopyRow;
  mLine, mText, mHash, mPath: string;
  mState: Char;
  mSpace: Integer;
begin
  mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Main, ARoot, '');
  mRow.RepositoryPath := ABranch;
  mRow.Revision := ARevision;
  mRow.Loaded := True;
  Result := TArray<TAtlasVcsWorkingCopyRow>.Create(mRow);
  for mLine in StringReplace(AStatus, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    // "<Zustand><Hash> <Pfad>[ (<Beschreibung>)]"; Zustand ' ', '+', '-' oder 'U'.
    if Length(mLine) < 3 then
      Continue;
    mState := mLine[1];
    mText := Copy(mLine, 2, MaxInt);
    mSpace := Pos(' ', mText);
    if mSpace < 2 then
      Continue;
    mHash := Copy(mText, 1, mSpace - 1);
    mPath := Copy(mText, mSpace + 1, MaxInt);
    if (Length(mPath) > 1) and (mPath[Length(mPath)] = ')') and (Pos(' (', mPath) > 0) then
      mPath := Copy(mPath, 1, Pos(' (', mPath) - 1);
    mPath := Slashed(mPath);
    if (mPath = '') or (RowOf(Result, mPath) >= 0) then
      Continue;
    mRow := TAtlasVcsWorkingCopyRow.Make(TAtlasVcsWorkingCopyKind.Submodule, ARoot, mPath);
    if mState <> '-' then
      mRow.Revision := Copy(mHash, 1, 7);
    mRow.Loaded := True;
    Result := Result + [mRow];
  end;
  SortAndIndent(Result);
end;

class function TAtlasVcsWorkingCopies.Collect(const AVcs: IAtlasVersionControl): TAtlasVcsWorkingCopyList;
var
  mHead: TAtlasVcsHead;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mStatus: IAtlasVcsSvnExternals;
  mSubmodules: IAtlasVcsSubmodules;
  mXml, mRepository, mStatusXml, mText: string;
begin
  Result := TAtlasVcsWorkingCopyList.Empty;
  if AVcs = nil then
    Exit;
  Result.Kind := AVcs.Kind;
  Result.Root := AVcs.WorkingCopy.Root;
  Result.Outcome := AVcs.Head(mHead);
  if Result.Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  if Result.Kind = TAtlasVcsKind.Git then
  begin
    mText := '';
    if Supports(AVcs, IAtlasVcsSubmodules, mSubmodules) and
      (mSubmodules.SubmoduleStatus(mText) <> TAtlasVcsOutcome.Ok) then
      mText := '';
    Result.Rows := FromSubmodules(Result.Root, mHead.Branch, mHead.ShortRevision(TAtlasVcsKind.Git), mText);
    Exit;
  end;
  mStatusXml := '';
  if Supports(AVcs, IAtlasVcsSvnExternals, mStatus) and (mStatus.StatusXml(mStatusXml) <> TAtlasVcsOutcome.Ok) then
    mStatusXml := '';
  // Ohne lesbare Externals bleiben die Zeilen aus dem Status (ohne Quelle).
  if Supports(AVcs, IAtlasVcsSvnWorkingCopy, mSvn) and (mSvn.ExternalsXml(mXml) = TAtlasVcsOutcome.Ok) and
    (mSvn.RepositoryRoot(mRepository) = TAtlasVcsOutcome.Ok) and (mRepository <> '') then
    try
      Result.Definitions := TAtlasSvnExternals.Definitions(mXml, Result.Root);
      Result.Externals := TAtlasSvnExternals.ParseAll(Result.Definitions, mRepository + '/' +
        StringReplace(mHead.Branch, ' ', '%20', [rfReplaceAll]), mRepository);
    except
      on EAtlasVcsParse do
      begin
        Result.Definitions := nil;
        Result.Externals := nil;
      end;
    end;
  try
    Result.Rows := FromSvn(Result.Root, mHead.Branch, mHead.Revision, Result.Externals, mStatusXml);
  except
    on EAtlasVcsParse do
      Result.Rows := FromSvn(Result.Root, mHead.Branch, mHead.Revision, Result.Externals, '');
  end;
end;

class procedure TAtlasVcsWorkingCopies.FillRevision(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const ASvn: IAtlasVcsSvnWorkingCopy);
var
  mText, mRevision: string;
  mMixed: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(AList.Rows)) or AList.Rows[AIndex].Loaded then
    Exit;
  AList.Rows[AIndex].Loaded := True;
  if ASvn = nil then
  begin
    AList.Rows[AIndex].Outcome := TAtlasVcsOutcome.Failed;
    Exit;
  end;
  AList.Rows[AIndex].Outcome := ASvn.WorkingRevisions(AList.Rows[AIndex].Path, mText);
  if (AList.Rows[AIndex].Outcome = TAtlasVcsOutcome.Ok) and TAtlasSvnLayout.WorkingRevision(mText, mRevision,
    mMixed) then
    AList.Rows[AIndex].Revision := mRevision;
end;

class procedure TAtlasVcsWorkingCopies.FillChanges(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const AVcs: IAtlasVersionControl);
var
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  if (AIndex < 0) or (AIndex > High(AList.Rows)) then
    Exit;
  if AVcs = nil then
  begin
    AList.Rows[AIndex].Outcome := TAtlasVcsOutcome.NoWorkingCopy;
    Exit;
  end;
  AList.Rows[AIndex].Outcome := AVcs.Changes(mChanges);
  if AList.Rows[AIndex].Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  AList.Rows[AIndex].Changed := 0;
  for mChange in mChanges do
    if mChange.Kind <> TAtlasVcsChangeKind.Untracked then
      Inc(AList.Rows[AIndex].Changed);
end;

class function TAtlasVcsWorkingCopies.CheckServer(var AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const ASvn: IAtlasVcsSvnExternals): TAtlasVcsOutcome;
var
  mRevision: string;
  mCount: Integer;
begin
  Result := TAtlasVcsOutcome.Failed;
  if (AIndex < 0) or (AIndex > High(AList.Rows)) or (ASvn = nil) or (AList.Rows[AIndex].RepositoryPath = '') or
    (AList.Kind <> TAtlasVcsKind.Svn) then
    Exit;
  // Fest: Ist der Trunk des Packages weiter als die feste Revision?
  mRevision := AList.Rows[AIndex].Revision;
  if AList.Rows[AIndex].Fixed and (AList.Rows[AIndex].FixedRevision <> '') then
    mRevision := AList.Rows[AIndex].FixedRevision;
  Result := ASvn.CommitsSince(AList.Rows[AIndex].RepositoryPath, mRevision, mCount);
  AList.Rows[AIndex].Outcome := Result;
  if Result = TAtlasVcsOutcome.Ok then
    AList.Rows[AIndex].Incoming := mCount;
end;

class function TAtlasVcsWorkingCopies.PinnedText(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  out AOwner, AText: string): Boolean;
var
  mExternal: TAtlasVcsSvnExternal;
  mDefinition: Integer;
  mLine: string;
begin
  AOwner := '';
  AText := '';
  Result := False;
  if (AIndex < 0) or (AIndex > High(AList.Rows)) or not AList.Rows[AIndex].CanPin or
    (AList.Rows[AIndex].ExternalIndex > High(AList.Externals)) then
    Exit;
  mExternal := AList.Externals[AList.Rows[AIndex].ExternalIndex];
  for mDefinition := 0 to High(AList.Definitions) do
    if SameText(AList.Definitions[mDefinition].Owner, mExternal.Owner) then
    begin
      mLine := TAtlasSvnExternals.PinnedLine(AList.Definitions[mDefinition].Text, mExternal,
        AList.Rows[AIndex].Revision);
      if mLine = '' then
        Exit;
      AOwner := mExternal.Owner;
      AText := TAtlasSvnExternals.ReplaceLine(AList.Definitions[mDefinition].Text, mExternal.Line, mLine);
      Exit(True);
    end;
end;

class function TAtlasVcsWorkingCopies.Pin(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const ASvn: IAtlasVcsSvnExternals): TAtlasVcsOutcome;
var
  mOwner, mText: string;
begin
  if (ASvn = nil) or not PinnedText(AList, AIndex, mOwner, mText) then
    Exit(TAtlasVcsOutcome.Failed);
  Result := ASvn.SetExternals(mOwner, mText);
end;

class function TAtlasVcsWorkingCopies.Folders(const AVcs: IAtlasVersionControl): TArray<TAtlasVcsWorkingCopyRow>;
var
  mStatus: IAtlasVcsSvnExternals;
  mSubmodules: IAtlasVcsSubmodules;
  mRoot, mText: string;
begin
  Result := nil;
  if AVcs = nil then
    Exit;
  mRoot := AVcs.WorkingCopy.Root;
  if mRoot = '' then
    Exit;
  mText := '';
  if AVcs.Kind = TAtlasVcsKind.Git then
  begin
    if Supports(AVcs, IAtlasVcsSubmodules, mSubmodules) and
      (mSubmodules.SubmoduleStatus(mText) <> TAtlasVcsOutcome.Ok) then
      mText := '';
    Result := FromSubmodules(mRoot, '', '', mText);
    Exit;
  end;
  if Supports(AVcs, IAtlasVcsSvnExternals, mStatus) and (mStatus.StatusXml(mText) <> TAtlasVcsOutcome.Ok) then
    mText := '';
  try
    Result := FromSvn(mRoot, '', '', nil, mText);
  except
    on EAtlasVcsParse do
      Result := FromSvn(mRoot, '', '', nil, '');
  end;
end;

class function TAtlasVcsWorkingCopies.Split(const AChanges: TArray<TAtlasVcsChange>;
  const ARows: TArray<TAtlasVcsWorkingCopyRow>): TArray<Integer>;
var
  mChange: TAtlasVcsChange;
  mRow, mIndex: Integer;
  mRoot, mPath: string;
begin
  SetLength(Result, Length(ARows));
  for mIndex := 0 to High(Result) do
    Result[mIndex] := 0;
  if Length(ARows) = 0 then
    Exit;
  mRoot := ARows[0].Folder;
  for mIndex := 0 to High(ARows) do
    if ARows[mIndex].Path = '' then
      mRoot := ARows[mIndex].Folder;
  for mChange in AChanges do
  begin
    // Der Wurzelordner selbst (geänderte Eigenschaft) gehört zur Wurzel.
    if not VcsRelativeOrRoot(mRoot, mChange.Path, mPath) then
      Continue;
    mRow := DeepestRow(ARows, Slashed(mPath));
    if mRow >= 0 then
      Inc(Result[mRow]);
  end;
end;

end.
