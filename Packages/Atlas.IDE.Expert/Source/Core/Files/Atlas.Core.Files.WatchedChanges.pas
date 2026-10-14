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
  Extensions: array[0..6] of string = ('.pas', '.inc', '.dpr', '.dpk', '.dfm', '.dproj', '.groupproj');
var
  Extension, Lower: string;
  Candidate: string;
begin
  Lower := AnsiLowerCase(AFileName);
  if (Pos('\.git\', Lower) > 0) or (Pos('\__history\', Lower) > 0) or (Pos('\__recovery\', Lower) > 0) then
    Exit(False);
  Extension := ExtractFileExt(Lower);
  for Candidate in Extensions do
    if Extension = Candidate then
      Exit(True);
  Result := False;
end;

procedure TAtlasWatchedChanges.Merge(const AFileName: string; AKind: TAtlasFileChangeKind);
var
  Key: string;
  Known: TAtlasFileChange;
begin
  Key := AnsiLowerCase(AFileName);
  if not FPending.TryGetValue(Key, Known) then
  begin
    FPending.Add(Key, TAtlasFileChange.Create(AFileName, AKind));
    FOrder.Add(Key);
    Exit;
  end;
  case Known.Kind of
    TAtlasFileChangeKind.Created:
      if AKind = TAtlasFileChangeKind.Deleted then
      begin
        // Nur kurz da gewesen (z. B. Sicherungsdatei eines Editors): nichts melden.
        FPending.Remove(Key);
        FOrder.Remove(Key);
        Exit;
      end;
    TAtlasFileChangeKind.Changed:
      if AKind = TAtlasFileChangeKind.Deleted then
        Known.Kind := TAtlasFileChangeKind.Deleted;
    TAtlasFileChangeKind.Deleted:
      if AKind <> TAtlasFileChangeKind.Deleted then
        Known.Kind := TAtlasFileChangeKind.Changed;
  end;
  FPending[Key] := Known;
end;

procedure TAtlasWatchedChanges.Add(const AFileName: string; AAction: Cardinal; ANow: Cardinal);
begin
  if not IsWatched(AFileName) then
    Exit;
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
  Key: string;
begin
  Result := nil;
  FLock.Enter;
  try
    if (FOrder.Count = 0) or (ANow - FLastAdd < QuietMs) then
      Exit;
    for Key in FOrder do
      Result := Result + [FPending[Key]];
    FOrder.Clear;
    FPending.Clear;
  finally
    FLock.Leave;
  end;
end;

class function TAtlasWatchedChanges.Roots(const AProjects: TArray<string>;
  const AExists: TAtlasPathExists): TArray<string>;
var
  Project, Folder, Candidate, Root, Current: string;
  Found: TList<string>;
  Index, Other: Integer;
  Nested: Boolean;
begin
  Found := TList<string>.Create;
  try
    for Project in AProjects do
    begin
      Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(Project));
      if Folder = '' then
        Continue;
      // Nach oben bis zum Git-Arbeitsverzeichnis; ohne Git der Projektordner.
      Root := Folder;
      Candidate := Folder;
      while Candidate <> '' do
      begin
        if AExists(IncludeTrailingPathDelimiter(Candidate) + '.git') then
        begin
          Root := Candidate;
          Break;
        end;
        if ExtractFileDir(Candidate) = Candidate then
          Break;
        Candidate := ExtractFileDir(Candidate);
      end;
      Found.Add(Root);
    end;
    Result := nil;
    for Index := 0 to Found.Count - 1 do
    begin
      Nested := False;
      Current := Found[Index];
      for Other := 0 to Found.Count - 1 do
        // Doppelt (der erste bleibt) oder unterhalb eines anderen Ordners.
        if ((Other < Index) and SameText(Found[Other], Current)) or
          ((Other <> Index) and Current.StartsWith(IncludeTrailingPathDelimiter(Found[Other]), True)) then
        begin
          Nested := True;
          Break;
        end;
      if not Nested then
        Result := Result + [Current];
    end;
  finally
    Found.Free;
  end;
end;

end.
