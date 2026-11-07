unit Atlas.Core.Files.WatchedChanges;

// Dateiänderungen außerhalb der IDE für den Server (#395, Ersatz für #22):
// Git, Claude Code oder ein anderer Editor ändern Quelltexte, ohne dass die
// IDE es meldet. Der Beobachter (Adapters.FolderWatcher) liefert rohe
// Ereignisse; diese Klasse filtert sie nach Endung, fasst mehrere Ereignisse
// derselben Datei zusammen und gibt sie erst heraus, wenn QuietMs lang nichts
// mehr kam (git checkout ändert viele Dateien kurz nacheinander).
// Zusammenfassen: angelegt + gelöscht entfällt, gelöscht + angelegt ist
// geändert, angelegt + geändert bleibt angelegt.
// Beobachtet werden die Wurzeln der Projekte: das Git-Arbeitsverzeichnis, in
// dem ein Projekt liegt, sonst sein Ordner.
// Threadsicher: Add kommt aus den Beobachter-Threads, Take aus dem Hauptthread.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
  /// <summary>Werte wie FileChangeType im LSP (1, 2, 3).</summary>
  TAtlasFileChangeKind = (Created = 1, Changed = 2, Deleted = 3);

  TAtlasFileChange = record
    FileName: string;
    Kind: TAtlasFileChangeKind;
    class function Create(const AFileName: string; AKind: TAtlasFileChangeKind): TAtlasFileChange; static;
  end;

  /// <summary>Gibt es die Datei oder den Ordner? Für Roots, damit Tests ohne Platte auskommen.</summary>
  TAtlasPathExists = reference to function(const APath: string): Boolean;

  TAtlasWatchedChanges = class
  public const
    QuietMs = 300;
    /// <summary>Rohe Ereignisse wie FILE_ACTION_* von ReadDirectoryChangesW.</summary>
    ActionAdded = 1;
    ActionRemoved = 2;
    ActionModified = 3;
    ActionRenamedOld = 4;
    ActionRenamedNew = 5;
  private
    FLock: TCriticalSection;
    FPending: TDictionary<string, TAtlasFileChange>;
    FOrder: TList<string>;
    FLastAdd: Cardinal;
    procedure Merge(const AFileName: string; AKind: TAtlasFileChangeKind);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Rohes Ereignis zu einem vollen Pfad zum Zeitpunkt ANow (ms).</summary>
    procedure Add(const AFileName: string; AAction: Cardinal; ANow: Cardinal);
    /// <summary>Gesammelte Änderungen, wenn seit dem letzten Add QuietMs vergangen sind; sonst leer.</summary>
    function Take(ANow: Cardinal): TArray<TAtlasFileChange>;
    /// <summary>Quelltext, Formular oder Projektdatei, nicht in .git, __history oder __recovery.</summary>
    class function IsWatched(const AFileName: string): Boolean; static;
    /// <summary>Zu beobachtende Ordner zu den Projektdateien: Git-Arbeitsverzeichnis darüber,
    /// sonst der Projektordner; ohne doppelte und ohne Ordner unterhalb eines anderen.</summary>
    class function Roots(const AProjects: TArray<string>; const AExists: TAtlasPathExists): TArray<string>; static;
  end;

  /// <summary>Beobachtet Ordner und meldet an TAtlasWatchedChanges; die Freigabe hält die Threads an. Die
  /// Umsetzung (TAtlasFolderWatcher) setzt die Kompositionswurzel ein (A-09).</summary>
  IAtlasFolderWatcher = interface
    ['{967E5852-0525-40F5-815C-047BF4E416F1}']
    /// <summary>Beobachtet genau diese Ordner; neue starten, weggefallene enden.</summary>
    procedure SetRoots(const ARoots: TArray<string>);
    function Roots: TArray<string>;
  end;

implementation

{ TAtlasFileChange }

class function TAtlasFileChange.Create(const AFileName: string; AKind: TAtlasFileChangeKind): TAtlasFileChange;
begin
  Result.FileName := AFileName;
  Result.Kind := AKind;
end;

{ TAtlasWatchedChanges }

constructor TAtlasWatchedChanges.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPending := TDictionary<string, TAtlasFileChange>.Create;
  FOrder := TList<string>.Create;
end;

destructor TAtlasWatchedChanges.Destroy;
begin
  FOrder.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasWatchedChanges.IsWatched(const AFileName: string): Boolean;
const
  cExtensions: array[0..6] of string = ('.pas', '.inc', '.dpr', '.dpk', '.dfm', '.dproj', '.groupproj');
var
  mExtension, mLower: string;
  mCandidate: string;
begin
  mLower := AnsiLowerCase(AFileName);
  if (Pos('\.git\', mLower) > 0) or (Pos('\__history\', mLower) > 0) or (Pos('\__recovery\', mLower) > 0) then
  begin
    Exit(False);
  end;
  mExtension := ExtractFileExt(mLower);
  for mCandidate in cExtensions do
  begin
    if mExtension = mCandidate then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasWatchedChanges.Merge(const AFileName: string; AKind: TAtlasFileChangeKind);
var
  mKey: string;
  mKnown: TAtlasFileChange;
begin
  mKey := AnsiLowerCase(AFileName);
  if not FPending.TryGetValue(mKey, mKnown) then
  begin
    FPending.Add(mKey, TAtlasFileChange.Create(AFileName, AKind));
    FOrder.Add(mKey);
    Exit;
  end;
  case mKnown.Kind of
    TAtlasFileChangeKind.Created:
      if AKind = TAtlasFileChangeKind.Deleted then
      begin
        // Nur kurz da gewesen (z. B. Sicherungsdatei eines Editors): nichts melden.
        FPending.Remove(mKey);
        FOrder.Remove(mKey);
        Exit;
      end;
    TAtlasFileChangeKind.Changed:
      if AKind = TAtlasFileChangeKind.Deleted then
      begin
        mKnown.Kind := TAtlasFileChangeKind.Deleted;
      end;
    TAtlasFileChangeKind.Deleted:
      if AKind <> TAtlasFileChangeKind.Deleted then
      begin
        mKnown.Kind := TAtlasFileChangeKind.Changed;
      end;
  end;
  FPending[mKey] := mKnown;
end;

procedure TAtlasWatchedChanges.Add(const AFileName: string; AAction: Cardinal; ANow: Cardinal);
begin
  if not IsWatched(AFileName) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    case AAction of
      ActionAdded, ActionRenamedNew:
        Merge(AFileName, TAtlasFileChangeKind.Created);
      ActionRemoved, ActionRenamedOld:
        Merge(AFileName, TAtlasFileChangeKind.Deleted);
      ActionModified:
        Merge(AFileName, TAtlasFileChangeKind.Changed);
    else
      Exit;
    end;
    FLastAdd := ANow;
  finally
    FLock.Leave;
  end;
end;

function TAtlasWatchedChanges.Take(ANow: Cardinal): TArray<TAtlasFileChange>;
var
  mKey: string;
begin
  Result := nil;
  FLock.Enter;
  try
    if (FOrder.Count = 0) or (ANow - FLastAdd < QuietMs) then
    begin
      Exit;
    end;
    for mKey in FOrder do
    begin
      Result := Result + [FPending[mKey]];
    end;
    FOrder.Clear;
    FPending.Clear;
  finally
    FLock.Leave;
  end;
end;

/// <summary>Nach oben bis zum Git-Arbeitsverzeichnis; ohne Git der Ordner selbst.</summary>
function GitRootOf(const AFolder: string; const AExists: TAtlasPathExists): string;
var
  mCandidate: string;
begin
  Result := AFolder;
  mCandidate := AFolder;
  while mCandidate <> '' do
  begin
    if AExists(IncludeTrailingPathDelimiter(mCandidate) + '.git') then
    begin
      Result := mCandidate;
      Break;
    end;
    if ExtractFileDir(mCandidate) = mCandidate then
    begin
      Break;
    end;
    mCandidate := ExtractFileDir(mCandidate);
  end;
end;

/// <summary>Doppelt (der erste bleibt) oder unterhalb eines anderen Ordners.</summary>
function IsCovered(const AFound: TArray<string>; AIndex: Integer): Boolean;
var
  mOther: Integer;
  mCurrent: string;
begin
  Result := False;
  mCurrent := AFound[AIndex];
  for mOther := 0 to High(AFound) do
  begin
    if ((mOther < AIndex) and SameText(AFound[mOther], mCurrent)) or
      ((mOther <> AIndex) and mCurrent.StartsWith(IncludeTrailingPathDelimiter(AFound[mOther]), True)) then
    begin
      Result := True;
      Break;
    end;
  end;
end;
class function TAtlasWatchedChanges.Roots(const AProjects: TArray<string>;
  const AExists: TAtlasPathExists): TArray<string>;
var
  mProject, mFolder: string;
  mFound: TArray<string>;
  mIndex: Integer;
begin
  mFound := nil;
  for mProject in AProjects do
  begin
    mFolder := ExcludeTrailingPathDelimiter(ExtractFilePath(mProject));
    if mFolder <> '' then
    begin
      mFound := mFound + [GitRootOf(mFolder, AExists)];
    end;
  end;
  Result := nil;
  for mIndex := 0 to High(mFound) do
  begin
    if not IsCovered(mFound, mIndex) then
    begin
      Result := Result + [mFound[mIndex]];
    end;
  end;
end;

end.
