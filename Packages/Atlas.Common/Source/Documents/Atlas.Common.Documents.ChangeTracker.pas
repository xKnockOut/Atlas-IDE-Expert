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
  FileName, Key: string;
  Keep: TDictionary<string, string>;
begin
  TMonitor.Enter(FLock);
  try
    Keep := TDictionary<string, string>.Create;
    try
      FFiles.Clear;
      for FileName in AFiles do
      begin
        Key := LowerCase(FileName);
        if (FileName = '') or Keep.ContainsKey(Key) then
          Continue;
        FFiles.Add(FileName);
        if FStamps.ContainsKey(Key) then
          Keep.Add(Key, FStamps[Key])
        else
          Keep.Add(Key, FStamp(FileName));
      end;
      FStamps.Clear;
      for Key in Keep.Keys do
        FStamps.Add(Key, Keep[Key]);
    finally
      Keep.Free;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TFileChangeTracker.Poll: TArray<string>;
var
  FileName, Key, Stamp: string;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for FileName in FFiles do
    begin
      Key := LowerCase(FileName);
      Stamp := FStamp(FileName);
      if Stamp <> FStamps[Key] then
      begin
        FStamps[Key] := Stamp;
        Result := Result + [FileName];
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
  FileName, Dir, Known: string;
  Found: Boolean;
begin
  Result := nil;
  for FileName in Files do
  begin
    Dir := ExtractFileDir(FileName);
    if Dir = '' then
      Continue;
    Found := False;
    for Known in Result do
      if SameText(Known, Dir) then
        Found := True;
    if not Found then
      Result := Result + [Dir];
  end;
end;

end.
