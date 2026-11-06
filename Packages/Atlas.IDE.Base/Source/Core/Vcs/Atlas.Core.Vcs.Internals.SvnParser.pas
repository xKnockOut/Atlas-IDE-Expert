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

function ActionKind(const AAction: string): TAtlasVcsChangeKind;
begin
  if AAction = 'A' then
  begin
    Result := TAtlasVcsChangeKind.Added;
  end
  else if AAction = 'D' then
  begin
    Result := TAtlasVcsChangeKind.Deleted;
  end
  else if AAction = 'R' then
  begin
    Result := TAtlasVcsChangeKind.Replaced;
  end
  else
  begin
    Result := TAtlasVcsChangeKind.Modified;
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
  begin
    Exit;
  end;
  ARevision := Copy(ALine, 2, mBar - 2);
  for mPos := 1 to Length(ARevision) do
  begin
    if not CharInSet(ARevision[mPos], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
  mLast := ALine;
  while Pos(' | ', mLast) > 0 do
  begin
    mLast := Copy(mLast, Pos(' | ', mLast) + 3, MaxInt);
  end;
  mPos := 1;
  while (mPos <= Length(mLast)) and CharInSet(mLast[mPos], ['0'..'9']) do
  begin
    Inc(mPos);
  end;
  if (mPos = 1) or (mPos > 7) or not TryStrToInt(Copy(mLast, 1, mPos - 1), ALines) then
  begin
    ALines := 0;
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
    begin
      mStart := mIndex + 1;
    end
    else if ((mPart = 'branches') or (mPart = 'tags')) and (mIndex < High(mParts)) then
    begin
      mStart := mIndex + 2;
    end;
    if mStart < 0 then
    begin
      Continue;
    end;
    AProject := string.Join('/', Copy(mParts, 0, mIndex));
    ABranch := string.Join('/', Copy(mParts, mIndex, mStart - mIndex));
    ARest := string.Join('/', Copy(mParts, mStart, Length(mParts) - mStart));
    Exit(True);
  end;
  Result := False;
end;

type
  /// <summary>Grundgerüst der Leser für svn --xml: verteilt die Knoten auf OnStart, OnEnd und OnText.</summary>
  TSvnXmlScan = class
  strict protected
    FReader: TAtlasVcsXmlReader;
    /// <summary>Offenes Element für Text; die Leser setzen es selbst.</summary>
    FElement: string;
    /// <summary>True beendet den Lauf vor dem nächsten Knoten.</summary>
    FDone: Boolean;
    procedure OnStart; virtual;
    procedure OnEnd; virtual;
    procedure OnText; virtual;
    /// <summary>Merkt sich das Element des StartTag, wenn es nicht leer ist.</summary>
    procedure KeepElement;
  public
    procedure Run(const AText: string);
  end;

  TSvnInfoScan = class(TSvnXmlScan)
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
    procedure OnText; override;
  public
    Info: TAtlasSvnInfo;
    Depth: Integer;
    Url, RepositoryRoot: string;
  end;

  TSvnStatusScan = class(TSvnXmlScan)
  strict private
    FRoot, FPath: string;
    FInEntry: Boolean;
    procedure AddChange(const AItem, AProps: string);
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
  public
    Changes: TArray<TAtlasVcsChange>;
    constructor Create(const ARoot: string);
  end;

  TSvnLogScan = class(TSvnXmlScan)
  strict private
    FRoot, FRelativeUrl, FKind: string;
    FInEntry: Boolean;
    FEntry: TAtlasVcsLogEntry;
    FFile: TAtlasVcsLogFile;
    FFiles: TList<TAtlasVcsLogFile>;
    FEntries: TList<TAtlasVcsLogEntry>;
    procedure StartEntry;
    procedure StartPath;
    procedure SetMessage(const AText: string);
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
    procedure OnText; override;
  public
    constructor Create(const ARoot, ARelativeUrl: string);
    destructor Destroy; override;
    function Entries: TArray<TAtlasVcsLogEntry>;
  end;

  TSvnListScan = class(TSvnXmlScan)
  strict private
    FCurrent: string;
    FRef: TAtlasVcsRef;
    FInEntry: Boolean;
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
    procedure OnText; override;
  public
    Refs: TArray<TAtlasVcsRef>;
    constructor Create(const ACurrent: string);
  end;

  TSvnBlameScan = class(TSvnXmlScan)
  strict private
    FItem: TAtlasVcsBlameLine;
    FInEntry, FInMerged: Boolean;
    procedure StartEntry;
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
    procedure OnText; override;
  public
    Lines: TArray<TAtlasVcsBlameLine>;
  end;

  TSvnLineLogScan = class(TSvnXmlScan)
  strict private
    FItem: TAtlasVcsLineCommit;
    FInEntry: Boolean;
  strict protected
    procedure OnStart; override;
    procedure OnEnd; override;
    procedure OnText; override;
  public
    Commits: TArray<TAtlasVcsLineCommit>;
  end;

  /// <summary>Liest svn log --diff Revision für Revision (#1275).</summary>
  TSvnLogDiffReader = class
  strict private
    FLines, FPatch: TArray<string>;
    FIndex, FCount: Integer;
    procedure Add(const ALine: string);
    function AtSeparator: Boolean;
    procedure ReadHunk(const AHunk: TAtlasVcsHunk);
    function ReadPatch: TArray<string>;
  public
    constructor Create(const AText: string);
    /// <summary>Nächste Revision; False am Ende. Löst EAtlasVcsParse aus, wenn ein Kopf fehlt.</summary>
    function Next(out AItem: TAtlasSvnLogDiff): Boolean;
  end;

{ TSvnXmlScan }

procedure TSvnXmlScan.Run(const AText: string);
begin
  FReader := TAtlasVcsXmlReader.Create(AText);
  try
    while not FDone and FReader.Next do
    begin
      case FReader.Node of
        TAtlasVcsXmlNode.StartTag:
          OnStart;
        TAtlasVcsXmlNode.EndTag:
          OnEnd;
        TAtlasVcsXmlNode.Text:
          OnText;
      end;
    end;
  finally
    FreeAndNil(FReader);
  end;
end;

procedure TSvnXmlScan.OnStart;
begin
  // Ohne Wirkung, wenn der Leser StartTag nicht braucht.
end;

procedure TSvnXmlScan.OnEnd;
begin
  // Ohne Wirkung, wenn der Leser EndTag nicht braucht.
end;

procedure TSvnXmlScan.OnText;
begin
  // Ohne Wirkung, wenn der Leser keinen Text braucht.
end;

procedure TSvnXmlScan.KeepElement;
begin
  if not FReader.EmptyElement then
  begin
    FElement := FReader.Name;
  end;
end;

{ TSvnInfoScan }

procedure TSvnInfoScan.OnStart;
begin
  if FReader.Name = 'entry' then
  begin
    Inc(Depth);
    // Nur der erste Eintrag zählt.
    if Depth = 1 then
    begin
      Info.Revision := FReader.Attr('revision');
    end;
  end;
  KeepElement;
end;

procedure TSvnInfoScan.OnEnd;
begin
  FElement := '';
  FDone := FReader.Name = 'entry';
end;

procedure TSvnInfoScan.OnText;
begin
  if FElement = 'wcroot-abspath' then
  begin
    Info.Root := VcsNormalizeDir(FReader.Value);
  end
  else if FElement = 'relative-url' then
  begin
    Info.RelativeUrl := Trim(FReader.Value);
  end
  else if FElement = 'url' then
  begin
    Url := Trim(FReader.Value);
  end
  else if FElement = 'root' then
  begin
    RepositoryRoot := Trim(FReader.Value);
  end;
end;

/// <summary>Pfad im Repository ohne "^/"; svn vor 1.8 kennt relative-url nicht: dann aus url und root.</summary>
function InfoRelativeUrl(const ARelativeUrl, AUrl, ARepositoryRoot: string): string;
begin
  Result := ARelativeUrl;
  if (Result = '') and (ARepositoryRoot <> '') and (Copy(AUrl, 1, Length(ARepositoryRoot)) = ARepositoryRoot) then
  begin
    Result := '^' + Copy(AUrl, Length(ARepositoryRoot) + 1, MaxInt);
  end;
  if Copy(Result, 1, 1) = '^' then
  begin
    Delete(Result, 1, 1);
  end;
  while Copy(Result, 1, 1) = '/' do
  begin
    Delete(Result, 1, 1);
  end;
end;

{ TSvnStatusScan }

constructor TSvnStatusScan.Create(const ARoot: string);
begin
  inherited Create;
  FRoot := ARoot;
end;

/// <summary>Absoluter Pfad (Laufwerk, "/" oder UNC)?</summary>
function IsAbsolutePath(const APath: string): Boolean;
begin
  Result := (Pos(':', APath) = 2) or (Copy(APath, 1, 1) = '/') or (Copy(APath, 1, 2) = '\\');
end;

procedure TSvnStatusScan.AddChange(const AItem, AProps: string);
var
  mChange: TAtlasVcsChange;
  mKind: TAtlasVcsChangeKind;
begin
  if not TAtlasSvnParser.KindOf(AItem, AProps, mKind) or (FPath = '') then
  begin
    Exit;
  end;
  // Absolute Pfade (bei absolutem Ziel) bleiben, relative gelten unter der Wurzel.
  if IsAbsolutePath(FPath) then
  begin
    mChange.Path := VcsNormalizeDir(FPath);
  end
  else
  begin
    mChange.Path := VcsFullPath(FRoot, FPath);
  end;
  mChange.OldPath := '';
  mChange.Kind := mKind;
  mChange.Staged := False;
  mChange.Unstaged := True;
  Changes := Changes + [mChange];
end;

procedure TSvnStatusScan.OnStart;
begin
  if FReader.Name = 'entry' then
  begin
    FInEntry := True;
    FPath := FReader.Attr('path');
  end
  else if (FReader.Name = 'wc-status') and FInEntry then
  begin
    AddChange(FReader.Attr('item'), FReader.Attr('props'));
    // Nur der erste wc-status je Eintrag; repos-status (mit --show-updates) folgt getrennt.
    FInEntry := False;
  end;
end;

procedure TSvnStatusScan.OnEnd;
begin
  if FReader.Name = 'entry' then
  begin
    FInEntry := False;
  end;
end;

{ TSvnLogScan }

constructor TSvnLogScan.Create(const ARoot, ARelativeUrl: string);
begin
  inherited Create;
  FRoot := ARoot;
  FRelativeUrl := ARelativeUrl;
  FFiles := TList<TAtlasVcsLogFile>.Create;
  FEntries := TList<TAtlasVcsLogEntry>.Create;
end;

destructor TSvnLogScan.Destroy;
begin
  FreeAndNil(FFiles);
  FreeAndNil(FEntries);
  inherited;
end;

function TSvnLogScan.Entries: TArray<TAtlasVcsLogEntry>;
begin
  Result := FEntries.ToArray;
end;

procedure TSvnLogScan.StartEntry;
begin
  FEntry := Default(TAtlasVcsLogEntry);
  FEntry.Revision := FReader.Attr('revision');
  if FEntry.Revision = '' then
  begin
    raise EAtlasVcsParse.Create('svn log: revision fehlt');
  end;
  FFiles.Clear;
  FInEntry := not FReader.EmptyElement;
  if not FInEntry then
  begin
    FEntries.Add(FEntry);
  end;
end;

procedure TSvnLogScan.StartPath;
begin
  FFile := Default(TAtlasVcsLogFile);
  FFile.Kind := ActionKind(FReader.Attr('action'));
  FKind := FReader.Attr('kind');
  KeepElement;
end;

procedure TSvnLogScan.OnStart;
begin
  if FReader.Name = 'logentry' then
  begin
    StartEntry;
  end
  else if FInEntry and (FReader.Name = 'path') then
  begin
    StartPath;
  end
  else
  begin
    KeepElement;
  end;
end;

procedure TSvnLogScan.OnEnd;
begin
  if FInEntry and (FReader.Name = 'path') and (FFile.RepositoryPath <> '') and (FKind <> 'dir') then
  begin
    FFile.Path := TAtlasSvnParser.LocalPath(FRoot, FRelativeUrl, FFile.RepositoryPath);
    FFiles.Add(FFile);
  end
  else if FInEntry and (FReader.Name = 'logentry') then
  begin
    FEntry.Files := FFiles.ToArray;
    FEntries.Add(FEntry);
    FInEntry := False;
  end;
  FElement := '';
end;

procedure TSvnLogScan.SetMessage(const AText: string);
var
  mBreak: Integer;
begin
  FEntry.Message := StringReplace(AText, #13#10, #10, [rfReplaceAll]).TrimRight([#10, #13, ' ']);
  mBreak := Pos(#10, FEntry.Message);
  if mBreak > 0 then
  begin
    FEntry.Summary := Copy(FEntry.Message, 1, mBreak - 1);
  end
  else
  begin
    FEntry.Summary := FEntry.Message;
  end;
end;

procedure TSvnLogScan.OnText;
var
  mDate: TDateTime;
begin
  if not FInEntry then
  begin
    Exit;
  end;
  if FElement = 'author' then
  begin
    FEntry.Author := FReader.Value;
  end
  else if (FElement = 'date') and VcsParseIsoDate(FReader.Value, mDate) then
  begin
    FEntry.Date := mDate;
  end
  else if FElement = 'path' then
  begin
    FFile.RepositoryPath := Trim(FReader.Value);
  end
  else if FElement = 'msg' then
  begin
    SetMessage(FReader.Value);
  end;
end;

{ TSvnListScan }

constructor TSvnListScan.Create(const ACurrent: string);
begin
  inherited Create;
  FCurrent := ACurrent;
end;

procedure TSvnListScan.OnStart;
begin
  if FReader.Name = 'entry' then
  begin
    FRef := Default(TAtlasVcsRef);
    FRef.Remote := True;
    // Nur Ordner sind Branches.
    FInEntry := (FReader.Attr('kind') = 'dir') and not FReader.EmptyElement;
  end
  else
  begin
    KeepElement;
  end;
end;

procedure TSvnListScan.OnEnd;
begin
  if FInEntry and (FReader.Name = 'entry') then
  begin
    FInEntry := False;
    if FRef.Name <> '' then
    begin
      FRef.LocalName := FRef.Name;
      FRef.Current := SameText('branches/' + FRef.Name, FCurrent);
      Refs := Refs + [FRef];
    end;
  end;
  FElement := '';
end;

procedure TSvnListScan.OnText;
var
  mDate: TDateTime;
begin
  if not FInEntry then
  begin
    Exit;
  end;
  if FElement = 'name' then
  begin
    FRef.Name := Trim(FReader.Value);
  end
  else if (FElement = 'date') and VcsParseIsoDate(FReader.Value, mDate) then
  begin
    FRef.TipDate := mDate;
  end;
end;

{ TSvnBlameScan }

procedure TSvnBlameScan.StartEntry;
var
  mNumber: Integer;
begin
  FItem := Default(TAtlasVcsBlameLine);
  if not TryStrToInt(FReader.Attr('line-number'), mNumber) then
  begin
    raise EAtlasVcsParse.Create('svn blame: line-number fehlt');
  end;
  FItem.Line := mNumber;
  FInEntry := not FReader.EmptyElement;
  if not FInEntry then
  begin
    Lines := Lines + [FItem];
  end;
end;

procedure TSvnBlameScan.OnStart;
begin
  if FReader.Name = 'entry' then
  begin
    StartEntry;
  end
  else if FReader.Name = 'merged' then
  begin
    FInMerged := not FReader.EmptyElement;
  end
  else if (FReader.Name = 'commit') and FInEntry and not FInMerged then
  begin
    FItem.Revision := FReader.Attr('revision');
  end
  else
  begin
    KeepElement;
  end;
end;

procedure TSvnBlameScan.OnEnd;
begin
  FElement := '';
  if FReader.Name = 'merged' then
  begin
    FInMerged := False;
  end
  else if (FReader.Name = 'entry') and FInEntry then
  begin
    Lines := Lines + [FItem];
    FInEntry := False;
  end;
end;

procedure TSvnBlameScan.OnText;
var
  mDate: TDateTime;
begin
  if not FInEntry or FInMerged then
  begin
    Exit;
  end;
  if FElement = 'author' then
  begin
    FItem.Author := FReader.Value;
  end
  else if (FElement = 'date') and VcsParseIsoDate(FReader.Value, mDate) then
  begin
    FItem.Date := mDate;
  end;
end;

{ TSvnLineLogScan }

procedure TSvnLineLogScan.OnStart;
begin
  if FReader.Name <> 'logentry' then
  begin
    KeepElement;
    Exit;
  end;
  FItem := Default(TAtlasVcsLineCommit);
  FItem.Revision := FReader.Attr('revision');
  if FItem.Revision = '' then
  begin
    raise EAtlasVcsParse.Create('svn log: revision fehlt');
  end;
  FInEntry := not FReader.EmptyElement;
  if not FInEntry then
  begin
    Commits := Commits + [FItem];
  end;
end;

procedure TSvnLineLogScan.OnEnd;
begin
  FElement := '';
  if (FReader.Name = 'logentry') and FInEntry then
  begin
    FItem.Message := TrimRight(FItem.Message);
    Commits := Commits + [FItem];
    FInEntry := False;
  end;
end;

procedure TSvnLineLogScan.OnText;
var
  mDate: TDateTime;
begin
  if not FInEntry then
  begin
    Exit;
  end;
  if FElement = 'author' then
  begin
    FItem.Author := FReader.Value;
  end
  else if (FElement = 'date') and VcsParseIsoDate(FReader.Value, mDate) then
  begin
    FItem.Date := mDate;
  end
  else if FElement = 'msg' then
  begin
    FItem.Message := FItem.Message + FReader.Value;
  end;
end;

{ TSvnLogDiffReader }

constructor TSvnLogDiffReader.Create(const AText: string);
var
  mIndex: Integer;
begin
  inherited Create;
  FLines := AText.Split([#10]);
  for mIndex := 0 to High(FLines) do
  begin
    FLines[mIndex] := FLines[mIndex].TrimRight([#13]);
  end;
  FIndex := 0;
  while (FIndex <= High(FLines)) and not AtSeparator do
  begin
    Inc(FIndex);
  end;
end;

function TSvnLogDiffReader.AtSeparator: Boolean;
begin
  Result := FLines[FIndex] = TAtlasSvnParser.LogSeparator;
end;

procedure TSvnLogDiffReader.Add(const ALine: string);
begin
  // Die Länge ist vorher unbekannt: Platz verdoppeln, am Ende kürzen.
  if FCount = Length(FPatch) then
  begin
    SetLength(FPatch, FCount * 2 + 16);
  end;
  FPatch[FCount] := ALine;
  Inc(FCount);
end;

procedure TSvnLogDiffReader.ReadHunk(const AHunk: TAtlasVcsHunk);
var
  mOld, mNew: Integer;
  mLine: string;
begin
  // Block nach seinen Größen lesen: Auch "-----…" ist hier eine Zeile des Unterschieds.
  mOld := AHunk.OldCount;
  mNew := AHunk.NewCount;
  while (FIndex <= High(FLines)) and ((mOld > 0) or (mNew > 0)) do
  begin
    mLine := FLines[FIndex] + ' ';
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
    Add(FLines[FIndex]);
    Inc(FIndex);
  end;
end;

function TSvnLogDiffReader.ReadPatch: TArray<string>;
var
  mLine: string;
  mHunk: TAtlasVcsHunk;
begin
  FPatch := nil;
  FCount := 0;
  while (FIndex <= High(FLines)) and not AtSeparator do
  begin
    mLine := FLines[FIndex];
    Inc(FIndex);
    if (FCount > 0) or (mLine <> '') then
    begin
      Add(mLine);
      if TAtlasVcsLineTrace.ParseHunkHeader(mLine, mHunk) then
      begin
        ReadHunk(mHunk);
      end;
    end;
  end;
  while (FCount > 0) and (FPatch[FCount - 1] = '') do
  begin
    Dec(FCount);
  end;
  Result := Copy(FPatch, 0, FCount);
end;

function TSvnLogDiffReader.Next(out AItem: TAtlasSvnLogDiff): Boolean;
var
  mMessage: Integer;
begin
  AItem := Default(TAtlasSvnLogDiff);
  // FLines[FIndex] ist eine Trennzeile; danach ein Kopf oder das Ende.
  Inc(FIndex);
  Result := (FIndex <= High(FLines)) and (FLines[FIndex] <> '');
  if not Result then
  begin
    Exit;
  end;
  if not ReadLogHeader(FLines[FIndex], AItem.Revision, mMessage) then
  begin
    raise EAtlasVcsParse.Create('svn log --diff: Kopf erwartet');
  end;
  Inc(FIndex);
  // Leerzeile, dann die Nachricht.
  if (FIndex <= High(FLines)) and (FLines[FIndex] = '') then
  begin
    Inc(FIndex);
  end;
  Inc(FIndex, mMessage);
  AItem.Patch := ReadPatch;
end;

{ TAtlasSvnParser }

class function TAtlasSvnParser.ParseInfo(const AText: string): TAtlasSvnInfo;
var
  mScan: TSvnInfoScan;
begin
  mScan := TSvnInfoScan.Create;
  try
    mScan.Run(AText);
    if mScan.Depth = 0 then
    begin
      raise EAtlasVcsParse.Create('svn info: kein Eintrag');
    end;
    Result := mScan.Info;
    Result.RelativeUrl := InfoRelativeUrl(Result.RelativeUrl, mScan.Url, mScan.RepositoryRoot);
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>;
var
  mScan: TSvnStatusScan;
begin
  mScan := TSvnStatusScan.Create(ARoot);
  try
    mScan.Run(AText);
    Result := mScan.Changes;
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseLog(const AText, ARoot, ARelativeUrl: string): TArray<TAtlasVcsLogEntry>;
var
  mScan: TSvnLogScan;
begin
  mScan := TSvnLogScan.Create(ARoot, ARelativeUrl);
  try
    mScan.Run(AText);
    Result := mScan.Entries;
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseList(const AText, ACurrent: string): TArray<TAtlasVcsRef>;
var
  mScan: TSvnListScan;
begin
  mScan := TSvnListScan.Create(ACurrent);
  try
    mScan.Run(AText);
    Result := mScan.Refs;
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>;
var
  mScan: TSvnBlameScan;
begin
  mScan := TSvnBlameScan.Create;
  try
    mScan.Run(AText);
    Result := mScan.Lines;
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseLog(const AText: string): TArray<TAtlasVcsLineCommit>;
var
  mScan: TSvnLineLogScan;
begin
  mScan := TSvnLineLogScan.Create;
  try
    mScan.Run(AText);
    Result := mScan.Commits;
  finally
    mScan.Free;
  end;
end;

class function TAtlasSvnParser.ParseLogDiff(const AText: string): TArray<TAtlasSvnLogDiff>;
var
  mReader: TSvnLogDiffReader;
  mItem: TAtlasSvnLogDiff;
  mFound: Integer;
begin
  // Die Zahl der Revisionen ist vorher unbekannt: Platz verdoppeln, am Ende kürzen.
  Result := nil;
  mFound := 0;
  mReader := TSvnLogDiffReader.Create(AText);
  try
    while mReader.Next(mItem) do
    begin
      if mFound = Length(Result) then
      begin
        SetLength(Result, mFound * 2 + 4);
      end;
      Result[mFound] := mItem;
      Inc(mFound);
    end;
  finally
    mReader.Free;
  end;
  SetLength(Result, mFound);
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
    begin
      Exit(Parts[Index]);
    end;
    if ((Part = 'branches') or (Part = 'tags')) and (Index < High(Parts)) then
    begin
      Exit(Parts[Index] + '/' + Parts[Index + 1]);
    end;
  end;
  Result := string.Join('/', Parts);
end;

class function TAtlasSvnParser.KindOf(const AItem, AProps: string; out AKind: TAtlasVcsChangeKind): Boolean;
begin
  Result := True;
  if AItem = 'modified' then
  begin
    AKind := TAtlasVcsChangeKind.Modified;
  end
  else if AItem = 'added' then
  begin
    AKind := TAtlasVcsChangeKind.Added;
  end
  else if AItem = 'deleted' then
  begin
    AKind := TAtlasVcsChangeKind.Deleted;
  end
  else if AItem = 'replaced' then
  begin
    AKind := TAtlasVcsChangeKind.Replaced;
  end
  else if AItem = 'unversioned' then
  begin
    AKind := TAtlasVcsChangeKind.Untracked;
  end
  else if (AItem = 'conflicted') or (AProps = 'conflicted') then
  begin
    AKind := TAtlasVcsChangeKind.Conflicted;
  end
  else if (AItem = 'missing') or (AItem = 'incomplete') then
  begin
    AKind := TAtlasVcsChangeKind.Missing;
  end
  else if AItem = 'obstructed' then
  begin
    AKind := TAtlasVcsChangeKind.TypeChanged;
  end
  else if AItem = 'merged' then
  begin
    AKind := TAtlasVcsChangeKind.Modified;
  end
  else if AProps = 'modified' then
  begin
    // Nur Eigenschaften geändert (svn:eol-style und ähnliche).
    AKind := TAtlasVcsChangeKind.Modified;
  end
  else
  begin
    // normal, none, ignored, external
    AKind := TAtlasVcsChangeKind.Modified;
    Result := False;
  end;
end;

class function TAtlasSvnParser.LocalPath(const ARoot, ARelativeUrl, ARepositoryPath: string): string;
var
  mProject, mBranch, mRest, mWcProject, mWcBranch, mWcRest: string;
begin
  Result := '';
  if not SplitLayout(ARepositoryPath, mProject, mBranch, mRest) then
  begin
    Exit;
  end;
  if not SplitLayout(ARelativeUrl, mWcProject, mWcBranch, mWcRest) or not SameText(mProject, mWcProject) then
  begin
    Exit;
  end;
  // Arbeitskopie eines Unterordners: nur Dateien darunter, relativ dazu.
  if mWcRest <> '' then
  begin
    if not SameText(Copy(mRest, 1, Length(mWcRest) + 1), mWcRest + '/') then
    begin
      Exit;
    end;
    mRest := Copy(mRest, Length(mWcRest) + 2, MaxInt);
  end;
  if mRest <> '' then
  begin
    Result := VcsFullPath(ARoot, mRest);
  end;
end;

end.
