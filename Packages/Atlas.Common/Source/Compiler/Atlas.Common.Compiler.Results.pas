unit Atlas.Common.Compiler.Results;

// Letzte Compilermeldungen je Datei (#40), threadsicher. Ein neuer Lauf
// ersetzt alle Meldungen; die Diagnosen der geöffneten Dokumente lesen sie.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract;

type
  TCompilerResults = class
  private
    FLock: TObject;
    FByFile: TDictionary<string, TArray<TCompilerMessage>>;
    FGeneral: TArray<TCompilerMessage>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ersetzt alle Meldungen; liefert die Dateien vor und nach dem Lauf.</summary>
    function Replace(const AMessages: TArray<TCompilerMessage>): TArray<string>;
    /// <summary>Meldungen zu AFileName (Groß-/Kleinschreibung egal).</summary>
    function MessagesFor(const AFileName: string): TArray<TCompilerMessage>;
    /// <summary>Meldungen ohne Datei, z. B. "F1026 File not found".</summary>
    function General: TArray<TCompilerMessage>;
  end;

implementation

uses
  Atlas.Common.Projects.Paths;

function KeyOf(const AFileName: string): string;
begin
  Result := LowerCase(TProjectPaths.Normalize(AFileName));
end;

{ TCompilerResults }

constructor TCompilerResults.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FByFile := TDictionary<string, TArray<TCompilerMessage>>.Create;
end;

destructor TCompilerResults.Destroy;
begin
  FByFile.Free;
  FLock.Free;
  inherited;
end;

function TCompilerResults.Replace(const AMessages: TArray<TCompilerMessage>): TArray<string>;
var
  Item: TCompilerMessage;
  Key: string;
  Files: TDictionary<string, string>;
  Existing: TArray<TCompilerMessage>;
begin
  Files := TDictionary<string, string>.Create;
  TMonitor.Enter(FLock);
  try
    for Key in FByFile.Keys do
      Files.AddOrSetValue(Key, FByFile[Key][0].FileName);
    FByFile.Clear;
    FGeneral := nil;
    for Item in AMessages do
      if Item.FileName = '' then
        FGeneral := FGeneral + [Item]
      else
      begin
        Key := KeyOf(Item.FileName);
        if not FByFile.TryGetValue(Key, Existing) then
          Existing := nil;
        FByFile.AddOrSetValue(Key, Existing + [Item]);
        Files.AddOrSetValue(Key, Item.FileName);
      end;
    Result := Files.Values.ToArray;
  finally
    TMonitor.Exit(FLock);
    Files.Free;
  end;
end;

function TCompilerResults.MessagesFor(const AFileName: string): TArray<TCompilerMessage>;
begin
  TMonitor.Enter(FLock);
  try
    if not FByFile.TryGetValue(KeyOf(AFileName), Result) then
      Result := nil;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCompilerResults.General: TArray<TCompilerMessage>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FGeneral;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
