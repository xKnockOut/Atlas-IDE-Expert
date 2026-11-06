unit Atlas.Common.Index.Adapters.Processes;

// Prozesse am selben Index-Cache (#62), für „Atlas › Diagnose › Prozesse am
// Projekt“. Jeder Server-Prozess (LSP aus der IDE oder aus Claude Code, MCP)
// meldet sich je Cache mit einer Datei "<cache>.prozesse\<pid>-<n>.json" an,
// die er offen hält und bei jeder Änderung neu schreibt: Art, Client, Zustand
// ("baut Index", "liest Cache", "bereit"), ob er die Cache-Sperre hält, und
// seine letzten Sperr- und Cache-Ereignisse. Andere Prozesse lesen die Dateien
// mit Mitbenutzung; lässt sich eine exklusiv öffnen, ist ihr Prozess beendet,
// und sie wird gelöscht. Ohne Windows: die Prozessnummer gibt der Aufrufer an.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Index.Processes;

type
  /// <summary>Anmeldung des eigenen Prozesses an einem Cache; Freigeben meldet ab.</summary>
  TIndexProcessEntry = class
  public const
    cMaxEvents = 20;
  private
    FFileName: string;
    FCacheFile: string;
    FStream: TStream;
    FInfo: TIndexProcessInfo;
    FLock: TObject;
    procedure Save;
  public
    /// <summary>Legt die Datei an; ohne Schreibrecht bleibt die Anmeldung nur im Speicher.</summary>
    constructor Create(const ACacheFile: string; const AInfo: TIndexProcessInfo);
    destructor Destroy; override;
    /// <summary>Neuer Zustand und Sperre; AEvent '' = ohne Ereignis. Threadsicher.</summary>
    procedure Update(const AState: string; AWriter: Boolean; const AEvent: string); overload;
    /// <summary>Nur ein Ereignis, Zustand bleibt. Threadsicher.</summary>
    procedure Update(const AEvent: string); overload;
    function Info: TIndexProcessInfo;
    property FileName: string read FFileName;
    property CacheFile: string read FCacheFile;
  end;

  TIndexProcesses = class
  public const
    cFolderExtension = '.prozesse';
  public
    class function FolderFor(const ACacheFile: string): string; static;
    /// <summary>Angemeldete Prozesse am Cache, nach Start sortiert; Dateien beendeter Prozesse werden gelöscht.
    /// </summary>
    class function List(const ACacheFile: string): TArray<TIndexProcessInfo>; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults;

{ TIndexProcessEntry }

constructor TIndexProcessEntry.Create(const ACacheFile: string; const AInfo: TIndexProcessInfo);
var
  mFolder: string;
  mIndex: Integer;
begin
  inherited Create;
  FLock := TObject.Create;
  FCacheFile := ACacheFile;
  FInfo := AInfo;
  if FInfo.Started = 0 then
  begin
    FInfo.Started := Now;
  end;
  mFolder := TIndexProcesses.FolderFor(ACacheFile);
  // Mehrere Arbeitsbereiche desselben Prozesses können denselben Cache nutzen: laufende Nummer.
  for mIndex := 0 to 99 do
  begin
    FFileName := TPath.Combine(mFolder, Format('%d-%d.json', [AInfo.Pid, mIndex]));
    try
      ForceDirectories(mFolder);
      if TFile.Exists(FFileName) then
      begin
        TFile.Delete(FFileName);
      end;
      FStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyWrite);
      Break;
    except
      // Belegt (eigener zweiter Arbeitsbereich) oder ohne Schreibrecht: nächste Nummer.
      on Exception do
        FStream := nil;
    end;
  end;
  if FStream = nil then
  begin
    FFileName := '';
  end;
  Save;
end;

destructor TIndexProcessEntry.Destroy;
begin
  FStream.Free;
  if FFileName <> '' then
    try
      TFile.Delete(FFileName);
    except
      // Liest gerade ein anderer Prozess: Er löscht die Datei beim nächsten Mal selbst.
      on Exception do
        FFileName := '';
    end;
  FLock.Free;
  inherited;
end;

procedure TIndexProcessEntry.Save;
var
  mJson: TJSONObject;
  mBytes: TBytes;
begin
  if FStream = nil then
  begin
    Exit;
  end;
  mJson := FInfo.ToJson;
  try
    mBytes := TEncoding.UTF8.GetBytes(mJson.ToJSON);
  finally
    mJson.Free;
  end;
  try
    FStream.Size := 0;
    FStream.Position := 0;
    if Length(mBytes) > 0 then
    begin
      FStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  except
    // Platte voll oder Netzlaufwerk weg: Die Anzeige ist nur Diagnose.
    on Exception do
      Exit;
  end;
end;

procedure TIndexProcessEntry.Update(const AState: string; AWriter: Boolean; const AEvent: string);
var
  mEvent: TIndexProcessEvent;
begin
  TMonitor.Enter(FLock);
  try
    FInfo.State := AState;
    FInfo.Writer := AWriter;
    if AEvent <> '' then
    begin
      mEvent.Time := Now;
      mEvent.Text := AEvent;
      FInfo.Events := FInfo.Events + [mEvent];
      if Length(FInfo.Events) > cMaxEvents then
      begin
        Delete(FInfo.Events, 0, Length(FInfo.Events) - cMaxEvents);
      end;
    end;
    Save;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexProcessEntry.Update(const AEvent: string);
begin
  TMonitor.Enter(FLock);
  try
    Update(FInfo.State, FInfo.Writer, AEvent);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexProcessEntry.Info: TIndexProcessInfo;
begin
  TMonitor.Enter(FLock);
  try
    Result := FInfo;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TIndexProcesses }

class function TIndexProcesses.FolderFor(const ACacheFile: string): string;
begin
  Result := ACacheFile + cFolderExtension;
end;

function ReadShared(const AFileName: string; out AText: string): Boolean;
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  AText := '';
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(mBytes, mStream.Size);
      if Length(mBytes) > 0 then
      begin
        mStream.ReadBuffer(mBytes[0], Length(mBytes));
      end;
    finally
      mStream.Free;
    end;
    AText := TEncoding.UTF8.GetString(mBytes);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

/// <summary>True, wenn kein Prozess die Datei mehr offen hält.</summary>
function IsOrphan(const AFileName: string): Boolean;
var
  mStream: TFileStream;
begin
  try
    mStream := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareExclusive);
    mStream.Free;
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

class function TIndexProcesses.List(const ACacheFile: string): TArray<TIndexProcessInfo>;
var
  mFolder, mFileName, mText: string;
  mInfo: TIndexProcessInfo;
  mFiles: TArray<string>;
begin
  Result := nil;
  mFolder := FolderFor(ACacheFile);
  try
    if not TDirectory.Exists(mFolder) then
    begin
      Exit;
    end;
    mFiles := TDirectory.GetFiles(mFolder, '*.json');
  except
    on Exception do
      Exit;
  end;
  for mFileName in mFiles do
  begin
    if IsOrphan(mFileName) then
    begin
      try
        TFile.Delete(mFileName);
      except
        on Exception do
          Continue;
      end;
      Continue;
    end;
    if ReadShared(mFileName, mText) and TIndexProcessInfo.FromJson(mText, mInfo) then
    begin
      Result := Result + [mInfo];
    end;
  end;
  TArray.Sort<TIndexProcessInfo>(Result, TComparer<TIndexProcessInfo>.Construct(
    function(const ALeft, ARight: TIndexProcessInfo): Integer
    begin
      Result := CompareDateTime(ALeft.Started, ARight.Started);
      if Result = 0 then
      begin
        Result := Integer(ALeft.Pid > ARight.Pid) - Integer(ALeft.Pid < ARight.Pid);
      end;
    end));
end;

end.
