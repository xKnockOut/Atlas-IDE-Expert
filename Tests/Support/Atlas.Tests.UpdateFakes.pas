unit Atlas.Tests.UpdateFakes;

// Attrappen des Update-Systems (#1519): Registry, Dateien, Prozesse,
// Prüfsummen, Netz, ZIP und Compiler im Speicher, damit Vorbereitung und
// Tausch ohne Windows und ohne Netz laufen. Pfade sind Windows-Pfade; Groß-
// und Kleinschreibung zählt wie unter Windows nicht.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Updates.Contract;

type
  TFakeRegistry = class(TInterfacedObject, IUpdateRegistry)
  private
    FKeys: TObjectDictionary<string, TList<TUpdateRegistryValue>>;
    FNames: TDictionary<string, string>;
    FRootDirs: TDictionary<string, string>;
    function ListOf(const AKey: string; ACreate: Boolean): TList<TUpdateRegistryValue>;
  public
    constructor Create;
    destructor Destroy; override;
    function SubKeys(const AKey: string): TArray<string>;
    function Values(const AKey: string): TArray<TUpdateRegistryValue>;
    procedure WriteValue(const AKey, AName, AData: string);
    procedure DeleteValue(const AKey, AName: string);
    function RootDir(const ABdsVersion: string): string;
    procedure SetRootDir(const ABdsVersion, ADir: string);
    function Has(const AKey, AName: string): Boolean;
    /// <summary>Werte als „Name=Data“ in Reihenfolge.</summary>
    function Dump(const AKey: string): string;
  end;

  TFakeFiles = class(TInterfacedObject, IUpdateFiles)
  private
    FContent: TDictionary<string, string>;
    FNames: TDictionary<string, string>;
    FLocked: TList<string>;
    FReadOnly: TList<string>;
    FBroken: TList<string>;
    procedure CheckLocked(const AFileName: string);
  public
    constructor Create;
    destructor Destroy; override;
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    function FilesIn(const ADirectory: string): TArray<string>;
    procedure CopyFile(const ASource, ATarget: string);
    procedure MoveFile(const ASource, ATarget: string);
    procedure DeleteFile(const AFileName: string);
    procedure DeleteDirectory(const ADirectory: string);
    procedure ForceDirectories(const ADirectory: string);
    function ReadText(const AFileName: string): string;
    procedure WriteText(const AFileName, AText: string);
    procedure AppendText(const AFileName, AText: string);
    function CanWrite(const ADirectory: string): Boolean;
    /// <summary>Gesperrt: überschreiben und löschen schlägt fehl, umbenennen geht (laufende EXE).</summary>
    procedure Lock(const AFileName: string);
    procedure Unlock(const AFileName: string);
    procedure DenyWrite(const ADirectory: string);
    /// <summary>Weder schreiben noch umbenennen (Datenträgerfehler).</summary>
    procedure Damage(const AFileName: string);
    function Count: Integer;
  end;

  TFakeProcesses = class(TInterfacedObject, IUpdateProcesses)
  private
    FUsing: TList<TUpdateProcess>;
    FRunning: TList<Cardinal>;
    FSleeps: Integer;
    FCancelAfter: Integer;
    FFinishAfter: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function UsingPackages(const AFolder: string): TArray<TUpdateProcess>;
    function IsRunning(APid: Cardinal): Boolean;
    procedure Sleep(AMilliseconds: Integer);
    function CancelRequested: Boolean;
    /// <summary>Prozess APid läuft und hat Packages geladen, bis AFinishAfter Wartezeiten vergangen sind.</summary>
    procedure Run(APid: Cardinal; const AName: string; AFinishAfter: Integer);
    /// <summary>Abbruch nach ASleeps Wartezeiten; -1 = nie.</summary>
    property CancelAfter: Integer read FCancelAfter write FCancelAfter;
    property Sleeps: Integer read FSleeps;
  end;

  TFakeTrust = class(TInterfacedObject, IUpdateTrust)
  private
    FFiles: TFakeFiles;
    FSigners: TDictionary<string, string>;
  public
    constructor Create(AFiles: TFakeFiles);
    destructor Destroy; override;
    function Sha256(const AFileName: string): string;
    function Signature(const AFileName: string): TUpdateSignature;
    /// <summary>Datei signiert von ASubject ('' = unsigniert).</summary>
    procedure Sign(const AFileName, ASubject: string);
    /// <summary>Alle Dateien unter ADirectory signieren.</summary>
    procedure SignAll(const ADirectory, ASubject: string);
    class function HashOf(const AText: string): string; static;
  end;

  TFakeNetwork = class(TInterfacedObject, IUpdateNetwork)
  private
    FFiles: TFakeFiles;
    FServer: TDictionary<string, string>;
  public
    constructor Create(AFiles: TFakeFiles);
    destructor Destroy; override;
    function Fetch(const AUrl: string; out AText, AError: string): Boolean;
    function Download(const AUrl, AFileName: string; const AProgress: TUpdateProgress; out AError: string): Boolean;
    procedure Serve(const AUrl, AContent: string);
  end;

  TFakeArchive = class(TInterfacedObject, IUpdateArchive)
  private
    FFiles: TFakeFiles;
    FZips: TObjectDictionary<string, TDictionary<string, string>>;
    FOrder: TObjectDictionary<string, TList<string>>;
  public
    constructor Create(AFiles: TFakeFiles);
    destructor Destroy; override;
    function Entries(const AZipFile: string): TArray<string>;
    procedure Extract(const AZipFile, AEntry, ATargetFile: string);
    /// <summary>Inhalt eines ZIP mit Kennung AId (so steht es nach dem Laden in der Datei).</summary>
    procedure Add(const AId, AEntry, AContent: string);
  end;

  TFakeBuilder = class(TInterfacedObject, IUpdateBuilder)
  private
    FFiles: TFakeFiles;
    FProjects: TList<string>;
    FCanBuild: Boolean;
    FFailOn: string;
  public
    constructor Create(AFiles: TFakeFiles);
    destructor Destroy; override;
    function CanBuild(const ABdsVersion, APlatform: string; out AReason: string): Boolean;
    /// <summary>Schreibt Output\APlatform\Release\Bpl\&lt;Projekt&gt;&lt;Endung der BDS-Version&gt;.bpl.</summary>
    function Build(const ABdsVersion, APlatform, AProject: string; const AOnLine: TUpdateLog): Integer;
    function Projects: TArray<string>;
    property Available: Boolean read FCanBuild write FCanBuild;
    /// <summary>Projektname, dessen Bau fehlschlägt.</summary>
    property FailOn: string read FFailOn write FFailOn;
  end;

  /// <summary>Alle Attrappen zusammen; hält die Interfaces.</summary>
  TFakeUpdateSystem = class
  private
    FRegistry: TFakeRegistry;
    FFiles: TFakeFiles;
    FProcesses: TFakeProcesses;
    FTrust: TFakeTrust;
    FNetwork: TFakeNetwork;
    FArchive: TFakeArchive;
    FBuilder: TFakeBuilder;
    FSystem: TUpdateSystem;
    FLog: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function System: TUpdateSystem;
    function LogText: string;
    property Registry: TFakeRegistry read FRegistry;
    property Files: TFakeFiles read FFiles;
    property Processes: TFakeProcesses read FProcesses;
    property Trust: TFakeTrust read FTrust;
    property Network: TFakeNetwork read FNetwork;
    property Archive: TFakeArchive read FArchive;
    property Builder: TFakeBuilder read FBuilder;
  end;

implementation

uses
  System.StrUtils;

function KeyOf(const APath: string): string;
begin
  Result := LowerCase(APath.Replace('/', '\'));
  while Result.EndsWith('\') do
  begin
    Result := Result.Substring(0, Length(Result) - 1);
  end;
end;

function Under(const APath, ADirectory: string): Boolean;
begin
  Result := KeyOf(APath).StartsWith(KeyOf(ADirectory) + '\');
end;

{ TFakeRegistry }

constructor TFakeRegistry.Create;
begin
  inherited Create;
  FKeys := TObjectDictionary<string, TList<TUpdateRegistryValue>>.Create([doOwnsValues]);
  FNames := TDictionary<string, string>.Create;
  FRootDirs := TDictionary<string, string>.Create;
end;

destructor TFakeRegistry.Destroy;
begin
  FRootDirs.Free;
  FNames.Free;
  FKeys.Free;
  inherited Destroy;
end;

function TFakeRegistry.ListOf(const AKey: string; ACreate: Boolean): TList<TUpdateRegistryValue>;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mPath: string;
begin
  if FKeys.TryGetValue(KeyOf(AKey), Result) or not ACreate then
  begin
    Exit;
  end;
  // Übergeordnete Schlüssel mit ihrer Schreibweise merken (für SubKeys).
  mParts := AKey.Split(['\']);
  mPath := '';
  for mIndex := 0 to High(mParts) do
  begin
    if mPath <> '' then
    begin
      mPath := mPath + '\';
    end;
    mPath := mPath + mParts[mIndex];
    FNames.AddOrSetValue(KeyOf(mPath), mPath);
  end;
  Result := TList<TUpdateRegistryValue>.Create;
  FKeys.Add(KeyOf(AKey), Result);
end;

function TFakeRegistry.SubKeys(const AKey: string): TArray<string>;
var
  mList: TList<string>;
  mPath, mRest: string;
begin
  mList := TList<string>.Create;
  try
    for mPath in FNames.Values do
    begin
      if Under(mPath, AKey) then
      begin
        mRest := mPath.Substring(Length(KeyOf(AKey)) + 1);
        if (Pos('\', mRest) = 0) and (mList.IndexOf(mRest) < 0) then
        begin
          mList.Add(mRest);
        end;
      end;
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TFakeRegistry.Values(const AKey: string): TArray<TUpdateRegistryValue>;
var
  mList: TList<TUpdateRegistryValue>;
begin
  mList := ListOf(AKey, False);
  if mList = nil then
  begin
    Result := nil;
  end
  else
  begin
    Result := mList.ToArray;
  end;
end;

procedure TFakeRegistry.WriteValue(const AKey, AName, AData: string);
var
  mList: TList<TUpdateRegistryValue>;
  mValue: TUpdateRegistryValue;
  mIndex: Integer;
begin
  mList := ListOf(AKey, True);
  mValue.Name := AName;
  mValue.Data := AData;
  for mIndex := 0 to mList.Count - 1 do
  begin
    if SameText(mList[mIndex].Name, AName) then
    begin
      mList[mIndex] := mValue;
      Exit;
    end;
  end;
  mList.Add(mValue);
end;

procedure TFakeRegistry.DeleteValue(const AKey, AName: string);
var
  mList: TList<TUpdateRegistryValue>;
  mIndex: Integer;
begin
  mList := ListOf(AKey, False);
  if mList = nil then
  begin
    Exit;
  end;
  for mIndex := mList.Count - 1 downto 0 do
  begin
    if SameText(mList[mIndex].Name, AName) then
    begin
      mList.Delete(mIndex);
    end;
  end;
end;

function TFakeRegistry.RootDir(const ABdsVersion: string): string;
begin
  if not FRootDirs.TryGetValue(ABdsVersion, Result) then
  begin
    Result := '';
  end;
end;

procedure TFakeRegistry.SetRootDir(const ABdsVersion, ADir: string);
begin
  FRootDirs.AddOrSetValue(ABdsVersion, ADir);
end;

function TFakeRegistry.Has(const AKey, AName: string): Boolean;
var
  mValue: TUpdateRegistryValue;
begin
  for mValue in Values(AKey) do
  begin
    if SameText(mValue.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFakeRegistry.Dump(const AKey: string): string;
var
  mValue: TUpdateRegistryValue;
begin
  Result := '';
  for mValue in Values(AKey) do
  begin
    Result := Result + mValue.Name + '=' + mValue.Data + ';';
  end;
end;

{ TFakeFiles }

constructor TFakeFiles.Create;
begin
  inherited Create;
  FContent := TDictionary<string, string>.Create;
  FNames := TDictionary<string, string>.Create;
  FLocked := TList<string>.Create;
  FReadOnly := TList<string>.Create;
  FBroken := TList<string>.Create;
end;

destructor TFakeFiles.Destroy;
begin
  FBroken.Free;
  FReadOnly.Free;
  FLocked.Free;
  FNames.Free;
  FContent.Free;
  inherited Destroy;
end;

procedure TFakeFiles.CheckLocked(const AFileName: string);
begin
  if FLocked.Contains(KeyOf(AFileName)) or FBroken.Contains(KeyOf(AFileName)) then
  begin
    raise EInOutError.Create('gesperrt: ' + AFileName);
  end;
end;

function TFakeFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := FContent.ContainsKey(KeyOf(AFileName));
end;

function TFakeFiles.DirectoryExists(const ADirectory: string): Boolean;
var
  mKey: string;
begin
  for mKey in FContent.Keys do
  begin
    if Under(mKey, ADirectory) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFakeFiles.FilesIn(const ADirectory: string): TArray<string>;
var
  mList: TList<string>;
  mName: string;
begin
  mList := TList<string>.Create;
  try
    for mName in FNames.Values do
    begin
      if Under(mName, ADirectory) then
      begin
        mList.Add(mName.Replace('/', '\').Substring(Length(KeyOf(ADirectory)) + 1));
      end;
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

procedure TFakeFiles.CopyFile(const ASource, ATarget: string);
begin
  if not FileExists(ASource) then
  begin
    raise EInOutError.Create('fehlt: ' + ASource);
  end;
  CheckLocked(ATarget);
  WriteText(ATarget, FContent[KeyOf(ASource)]);
end;

procedure TFakeFiles.MoveFile(const ASource, ATarget: string);
var
  mText: string;
  mLocked: Boolean;
begin
  if FBroken.Contains(KeyOf(ASource)) then
  begin
    raise EInOutError.Create('defekt: ' + ASource);
  end;
  mText := ReadText(ASource);
  mLocked := FLocked.Contains(KeyOf(ASource));
  FLocked.Remove(KeyOf(ASource));
  DeleteFile(ASource);
  WriteText(ATarget, mText);
  if mLocked then
  begin
    FLocked.Add(KeyOf(ATarget));
  end;
end;

procedure TFakeFiles.DeleteFile(const AFileName: string);
begin
  CheckLocked(AFileName);
  FContent.Remove(KeyOf(AFileName));
  FNames.Remove(KeyOf(AFileName));
end;

procedure TFakeFiles.DeleteDirectory(const ADirectory: string);
var
  mKey: string;
begin
  for mKey in FContent.Keys.ToArray do
  begin
    if Under(mKey, ADirectory) then
    begin
      DeleteFile(mKey);
    end;
  end;
end;

procedure TFakeFiles.ForceDirectories(const ADirectory: string);
begin
  // Ordner entstehen mit ihren Dateien.
end;

function TFakeFiles.ReadText(const AFileName: string): string;
begin
  if not FContent.TryGetValue(KeyOf(AFileName), Result) then
  begin
    Result := '';
  end;
end;

procedure TFakeFiles.WriteText(const AFileName, AText: string);
begin
  FContent.AddOrSetValue(KeyOf(AFileName), AText);
  FNames.AddOrSetValue(KeyOf(AFileName), AFileName.Replace('/', '\'));
end;

procedure TFakeFiles.AppendText(const AFileName, AText: string);
begin
  WriteText(AFileName, ReadText(AFileName) + AText);
end;

function TFakeFiles.CanWrite(const ADirectory: string): Boolean;
begin
  Result := not FReadOnly.Contains(KeyOf(ADirectory));
end;

procedure TFakeFiles.Lock(const AFileName: string);
begin
  FLocked.Add(KeyOf(AFileName));
end;

procedure TFakeFiles.Unlock(const AFileName: string);
begin
  FLocked.Remove(KeyOf(AFileName));
end;

procedure TFakeFiles.DenyWrite(const ADirectory: string);
begin
  FReadOnly.Add(KeyOf(ADirectory));
end;

procedure TFakeFiles.Damage(const AFileName: string);
begin
  FBroken.Add(KeyOf(AFileName));
end;

function TFakeFiles.Count: Integer;
begin
  Result := FContent.Count;
end;

{ TFakeProcesses }

constructor TFakeProcesses.Create;
begin
  inherited Create;
  FUsing := TList<TUpdateProcess>.Create;
  FRunning := TList<Cardinal>.Create;
  FCancelAfter := -1;
  FFinishAfter := 0;
end;

destructor TFakeProcesses.Destroy;
begin
  FRunning.Free;
  FUsing.Free;
  inherited Destroy;
end;

function TFakeProcesses.UsingPackages(const AFolder: string): TArray<TUpdateProcess>;
begin
  if FSleeps >= FFinishAfter then
  begin
    Result := nil;
  end
  else
  begin
    Result := FUsing.ToArray;
  end;
end;

function TFakeProcesses.IsRunning(APid: Cardinal): Boolean;
begin
  Result := (FSleeps < FFinishAfter) and FRunning.Contains(APid);
end;

procedure TFakeProcesses.Sleep(AMilliseconds: Integer);
begin
  Inc(FSleeps);
end;

function TFakeProcesses.CancelRequested: Boolean;
begin
  Result := (FCancelAfter >= 0) and (FSleeps >= FCancelAfter);
end;

procedure TFakeProcesses.Run(APid: Cardinal; const AName: string; AFinishAfter: Integer);
var
  mProcess: TUpdateProcess;
begin
  mProcess.Pid := APid;
  mProcess.Name := AName;
  FUsing.Add(mProcess);
  FRunning.Add(APid);
  FFinishAfter := AFinishAfter;
end;

{ TFakeTrust }

constructor TFakeTrust.Create(AFiles: TFakeFiles);
begin
  inherited Create;
  FFiles := AFiles;
  FSigners := TDictionary<string, string>.Create;
end;

destructor TFakeTrust.Destroy;
begin
  FSigners.Free;
  inherited Destroy;
end;

// FNV-1a läuft gewollt über (#1980: Tests prüfen Überläufe).
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
class function TFakeTrust.HashOf(const AText: string): string;
var
  mHash: Cardinal;
  mChar: Char;
  mIndex: Integer;
begin
  mHash := 2166136261;
  for mChar in AText do
  begin
    mHash := (mHash xor Ord(mChar)) * 16777619;
  end;
  Result := '';
  for mIndex := 1 to 8 do
  begin
    Result := Result + LowerCase(IntToHex(mHash xor Cardinal(mIndex), 8));
  end;
end;
{$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

function TFakeTrust.Sha256(const AFileName: string): string;
begin
  Result := HashOf(FFiles.ReadText(AFileName));
end;

function TFakeTrust.Signature(const AFileName: string): TUpdateSignature;
begin
  Result := Default(TUpdateSignature);
  Result.Valid := FSigners.TryGetValue(KeyOf(AFileName), Result.Subject) and (Result.Subject <> '');
end;

procedure TFakeTrust.Sign(const AFileName, ASubject: string);
begin
  FSigners.AddOrSetValue(KeyOf(AFileName), ASubject);
end;

procedure TFakeTrust.SignAll(const ADirectory, ASubject: string);
var
  mFile: string;
begin
  for mFile in FFiles.FilesIn(ADirectory) do
  begin
    Sign(ADirectory + '\' + mFile, ASubject);
  end;
end;

{ TFakeNetwork }

constructor TFakeNetwork.Create(AFiles: TFakeFiles);
begin
  inherited Create;
  FFiles := AFiles;
  FServer := TDictionary<string, string>.Create;
end;

destructor TFakeNetwork.Destroy;
begin
  FServer.Free;
  inherited Destroy;
end;

function TFakeNetwork.Fetch(const AUrl: string; out AText, AError: string): Boolean;
begin
  AError := '';
  Result := FServer.TryGetValue(AUrl, AText);
  if not Result then
  begin
    AText := '';
    AError := '404';
  end;
end;

function TFakeNetwork.Download(const AUrl, AFileName: string; const AProgress: TUpdateProgress;
  out AError: string): Boolean;
var
  mText: string;
begin
  Result := Fetch(AUrl, mText, AError);
  if Result then
  begin
    AProgress(50);
    FFiles.WriteText(AFileName, mText);
    AProgress(100);
  end;
end;

procedure TFakeNetwork.Serve(const AUrl, AContent: string);
begin
  FServer.AddOrSetValue(AUrl, AContent);
end;

{ TFakeArchive }

constructor TFakeArchive.Create(AFiles: TFakeFiles);
begin
  inherited Create;
  FFiles := AFiles;
  FZips := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  FOrder := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
end;

destructor TFakeArchive.Destroy;
begin
  FOrder.Free;
  FZips.Free;
  inherited Destroy;
end;

function TFakeArchive.Entries(const AZipFile: string): TArray<string>;
var
  mOrder: TList<string>;
begin
  if FOrder.TryGetValue(FFiles.ReadText(AZipFile), mOrder) then
  begin
    Result := mOrder.ToArray;
  end
  else
  begin
    raise EInOutError.Create('kein ZIP: ' + AZipFile);
  end;
end;

procedure TFakeArchive.Extract(const AZipFile, AEntry, ATargetFile: string);
begin
  FFiles.WriteText(ATargetFile, FZips[FFiles.ReadText(AZipFile)][AEntry]);
end;

procedure TFakeArchive.Add(const AId, AEntry, AContent: string);
begin
  if not FZips.ContainsKey(AId) then
  begin
    FZips.Add(AId, TDictionary<string, string>.Create);
    FOrder.Add(AId, TList<string>.Create);
  end;
  FZips[AId].AddOrSetValue(AEntry, AContent);
  FOrder[AId].Add(AEntry);
end;

{ TFakeBuilder }

constructor TFakeBuilder.Create(AFiles: TFakeFiles);
begin
  inherited Create;
  FFiles := AFiles;
  FProjects := TList<string>.Create;
  FCanBuild := True;
end;

destructor TFakeBuilder.Destroy;
begin
  FProjects.Free;
  inherited Destroy;
end;

function TFakeBuilder.CanBuild(const ABdsVersion, APlatform: string; out AReason: string): Boolean;
begin
  Result := FCanBuild;
  AReason := '';
  if not Result then
  begin
    AReason := 'dcc32 fehlt';
  end;
end;

function TFakeBuilder.Build(const ABdsVersion, APlatform, AProject: string; const AOnLine: TUpdateLog): Integer;
var
  mName, mRoot: string;
begin
  mName := AProject.Substring(AProject.LastDelimiter('\') + 1).Replace('.dproj', '');
  FProjects.Add(mName);
  AOnLine('Erzeuge ' + mName);
  if SameText(mName, FFailOn) then
  begin
    Exit(1);
  end;
  // Quelltext\Packages\X\X.dproj → Quelltext\Output\…
  mRoot := AProject.Substring(0, AProject.LastDelimiter('\'));
  mRoot := mRoot.Substring(0, mRoot.LastDelimiter('\'));
  mRoot := mRoot.Substring(0, mRoot.LastDelimiter('\'));
  FFiles.WriteText(mRoot + '\Output\' + APlatform + '\Release\Bpl\' + mName + '290.bpl', 'built ' + mName);
  Result := 0;
end;

function TFakeBuilder.Projects: TArray<string>;
begin
  Result := FProjects.ToArray;
end;

{ TFakeUpdateSystem }

constructor TFakeUpdateSystem.Create;
var
  mLog: TList<string>;
begin
  inherited Create;
  FLog := TList<string>.Create;
  FRegistry := TFakeRegistry.Create;
  FFiles := TFakeFiles.Create;
  FProcesses := TFakeProcesses.Create;
  FTrust := TFakeTrust.Create(FFiles);
  FNetwork := TFakeNetwork.Create(FFiles);
  FArchive := TFakeArchive.Create(FFiles);
  FBuilder := TFakeBuilder.Create(FFiles);
  FSystem.Registry := FRegistry;
  FSystem.Files := FFiles;
  FSystem.Processes := FProcesses;
  FSystem.Trust := FTrust;
  FSystem.Network := FNetwork;
  FSystem.Archive := FArchive;
  FSystem.Builder := FBuilder;
  mLog := FLog;
  FSystem.Log :=
    procedure(const AText: string)
    begin
      mLog.Add(AText);
    end;
end;

destructor TFakeUpdateSystem.Destroy;
begin
  // Die Interfaces im Record geben die Attrappen frei.
  FSystem := Default(TUpdateSystem);
  FLog.Free;
  inherited Destroy;
end;

function TFakeUpdateSystem.System: TUpdateSystem;
begin
  Result := FSystem;
end;

function TFakeUpdateSystem.LogText: string;
begin
  Result := string.Join(#10, FLog.ToArray);
end;

end.
