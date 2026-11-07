unit Atlas.Common.Documents.ChangeTracker;

// Merkt sich einen Stempel je Datei (z. B. Änderungszeit und Größe) und meldet,
// welche Dateien sich seit dem letzten Blick geändert haben, neu entstanden
// oder verschwunden sind (#227: atlas.json und die globale Benutzerdatei, die
// der Server selbst beobachtet). Wie der Stempel entsteht, bestimmt der
// Aufrufer; '' heißt „gibt es nicht“. Threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Stempel einer Datei; '' wenn es sie nicht gibt.</summary>
  TFileStampFunc = reference to function(const AFileName: string): string;

  TFileChangeTracker = class
  private
    FStamp: TFileStampFunc;
    FLock: TObject;
    FStamps: TDictionary<string, string>;
    FFiles: TList<string>;
  public
    constructor Create(const AStamp: TFileStampFunc);
    destructor Destroy; override;
    /// <summary>Beobachtet genau AFiles. Neue Dateien bekommen ihren jetzigen Stempel (keine Meldung), bekannte
    /// behalten ihren gemerkten.</summary>
    procedure SetFiles(const AFiles: TArray<string>);
    /// <summary>Dateien, deren Stempel sich seit dem letzten Aufruf geändert hat; merkt sich die neuen.</summary>
    function Poll: TArray<string>;
    function Files: TArray<string>;
    /// <summary>Ordner der beobachteten Dateien, ohne doppelte.</summary>
    function Directories: TArray<string>;
  end;

implementation

{ TFileChangeTracker }

constructor TFileChangeTracker.Create(const AStamp: TFileStampFunc);
begin
  inherited Create;
  FStamp := AStamp;
  FLock := TObject.Create;
  FStamps := TDictionary<string, string>.Create;
  FFiles := TList<string>.Create;
end;

destructor TFileChangeTracker.Destroy;
begin
  FFiles.Free;
  FStamps.Free;
  FLock.Free;
  inherited;
end;

procedure TFileChangeTracker.SetFiles(const AFiles: TArray<string>);
var
  mFileName, mKey: string;
  mKeep: TDictionary<string, string>;
begin
  TMonitor.Enter(FLock);
  try
    mKeep := TDictionary<string, string>.Create;
    try
      FFiles.Clear;
      for mFileName in AFiles do
      begin
        mKey := LowerCase(mFileName);
        if (mFileName = '') or mKeep.ContainsKey(mKey) then
        begin
          Continue;
        end;
        FFiles.Add(mFileName);
        if FStamps.ContainsKey(mKey) then
        begin
          mKeep.Add(mKey, FStamps[mKey]);
        end
        else
        begin
          mKeep.Add(mKey, FStamp(mFileName));
        end;
      end;
      FStamps.Clear;
      for mKey in mKeep.Keys do
      begin
        FStamps.Add(mKey, mKeep[mKey]);
      end;
    finally
      mKeep.Free;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TFileChangeTracker.Poll: TArray<string>;
var
  mFileName, mKey, mStamp: string;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for mFileName in FFiles do
    begin
      mKey := LowerCase(mFileName);
      mStamp := FStamp(mFileName);
      if mStamp <> FStamps[mKey] then
      begin
        FStamps[mKey] := mStamp;
        Result := Result + [mFileName];
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TFileChangeTracker.Files: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TFileChangeTracker.Directories: TArray<string>;
var
  mFileName, mDir, mKnown: string;
  mFound: Boolean;
begin
  Result := nil;
  for mFileName in Files do
  begin
    mDir := ExtractFileDir(mFileName);
    if mDir = '' then
    begin
      Continue;
    end;
    mFound := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mDir) then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mDir];
    end;
  end;
end;

end.
