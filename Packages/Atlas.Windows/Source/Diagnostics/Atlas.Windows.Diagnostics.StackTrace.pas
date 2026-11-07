unit Atlas.Windows.Diagnostics.StackTrace;

// Platform-Feature "Diagnostics", Root: Stacktraces für Exceptions.
// Install hängt sich in Exception.GetExceptionStackInfoProc ein; danach
// liefert Exception.StackTrace die Aufrufkette zum Zeitpunkt des raise als
// "Modul+$Offset" je Zeile. Liegt die .map-Datei des Builds neben der EXE
// (Linker-Option "Map-Datei: detailliert", #282), steht dahinter Unit, Routine
// und Zeile; die Map wird beim ersten Stacktrace gelesen.

interface

type
  TStackTrace = record
  public
    /// <summary>Aktiviert Exception.StackTrace für alle folgenden Exceptions.</summary>
    class procedure Install; static;
    /// <summary>Stellt den vorherigen Zustand wieder her.</summary>
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
    /// <summary>Aktuelle Aufrufkette ohne diese Funktion, eine Zeile je Rücksprungadresse.</summary>
    class function Current: string; static;
    /// <summary>Formatiert eine Adresse als "Modul+$Offset".</summary>
    class function DescribeAddress(AAddress: Pointer): string; static;
  end;

implementation

// Winapi.Windows vor System.SysUtils: Beide deklarieren PExceptionRecord,
// Exception.GetExceptionStackInfoProc erwartet den aus System.SysUtils.
uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  Atlas.Text.MapFile,
  Atlas.Common.Documents.FileEncoding;

const
  cMaxFrames = 48;
  cModuleFromAddress = $00000004; // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
  cModuleUnchangedRefCount = $00000002; // GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT

// Winapi.Windows deklariert GetModuleHandleEx nicht.
function GetModuleHandleEx(ADwFlags: DWORD; ALpModuleName: LPCWSTR; var APhModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';

type
  PStackInfo = ^TStackInfo;
  TStackInfo = record
    Count: Integer;
    Frames: array[0..cMaxFrames - 1] of Pointer;
  end;

function CaptureStackBackTrace(AFramesToSkip, AFramesToCapture: ULONG; ABackTrace: Pointer;
  ABackTraceHash: PULONG): USHORT; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';

var
  PreviousGetInfo: function(AP: PExceptionRecord): Pointer;
  PreviousGetString: function(AInfo: Pointer): string;
  PreviousCleanUp: procedure(AInfo: Pointer);
  IsInstalled: Boolean;
  MapLock: TObject;
  MapLoaded: Boolean;
  Map: TMapFile;
  MapModule: string;

/// <summary>Map der EXE, beim ersten Aufruf gelesen; nil ohne .map-Datei.</summary>
function LoadedMap: TMapFile;
var
  mMapName: string;
begin
  TMonitor.Enter(MapLock);
  try
    if not MapLoaded then
    begin
      MapLoaded := True;
      mMapName := ChangeFileExt(ParamStr(0), '.map');
      MapModule := ExtractFileName(ParamStr(0));
      try
        if TFile.Exists(mMapName) then
        begin
          Map := TMapFile.Create(TFileEncoding.LoadText(mMapName));
        end;
      except
        // Eine unlesbare Map darf das Absturzprotokoll nicht verhindern.
        FreeAndNil(Map);
      end;
    end;
    Result := Map;
  finally
    TMonitor.Exit(MapLock);
  end;
end;

function Capture(ASkip: Integer): PStackInfo;
begin
  New(Result);
  Result.Count := CaptureStackBackTrace(ASkip + 1, cMaxFrames, @Result.Frames[0], nil);
end;

function Describe(AInfo: PStackInfo): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to AInfo.Count - 1 do
  begin
    Result := Result + TStackTrace.DescribeAddress(AInfo.Frames[mIndex]) + sLineBreak;
  end;
  if LoadedMap <> nil then
  begin
    Result := LoadedMap.Symbolize(Result, MapModule);
  end;
end;

function GetExceptionStackInfo(AP: PExceptionRecord): Pointer;
begin
  // Die ersten Rahmen gehören zur RTL (RaisingException); sie bleiben drin,
  // damit nichts Wichtiges fehlt, falls sich die RTL ändert.
  Result := Capture(1);
end;

function GetStackInfoString(AInfo: Pointer): string;
begin
  if AInfo = nil then
  begin
    Result := '';
  end
  else
  begin
    Result := Describe(PStackInfo(AInfo));
  end;
end;

procedure CleanUpStackInfo(AInfo: Pointer);
begin
  if AInfo <> nil then
  begin
    Dispose(PStackInfo(AInfo));
  end;
end;

{ TStackTrace }

class procedure TStackTrace.Install;
begin
  if IsInstalled then
  begin
    Exit;
  end;
  PreviousGetInfo := Exception.GetExceptionStackInfoProc;
  PreviousGetString := Exception.GetStackInfoStringProc;
  PreviousCleanUp := Exception.CleanUpStackInfoProc;
  Exception.GetExceptionStackInfoProc := GetExceptionStackInfo;
  Exception.GetStackInfoStringProc := GetStackInfoString;
  Exception.CleanUpStackInfoProc := CleanUpStackInfo;
  IsInstalled := True;
end;

class procedure TStackTrace.Uninstall;
begin
  if not IsInstalled then
  begin
    Exit;
  end;
  Exception.GetExceptionStackInfoProc := PreviousGetInfo;
  Exception.GetStackInfoStringProc := PreviousGetString;
  Exception.CleanUpStackInfoProc := PreviousCleanUp;
  IsInstalled := False;
end;

class function TStackTrace.Installed: Boolean;
begin
  Result := IsInstalled;
end;

class function TStackTrace.Current: string;
var
  mInfo: PStackInfo;
begin
  mInfo := Capture(1);
  try
    Result := Describe(mInfo);
  finally
    Dispose(mInfo);
  end;
end;

class function TStackTrace.DescribeAddress(AAddress: Pointer): string;
var
  mModule: HMODULE;
  mFileName: array[0..MAX_PATH] of Char;
begin
  if GetModuleHandleEx(cModuleFromAddress or cModuleUnchangedRefCount, PChar(AAddress), mModule) and
    (GetModuleFileName(mModule, mFileName, Length(mFileName)) > 0) then
  begin
    Result := Format('%s+$%x', [ExtractFileName(mFileName), NativeUInt(AAddress) - NativeUInt(mModule)]);
  end
  else
  begin
    Result := Format('$%p', [AAddress]);
  end;
end;

initialization
  MapLock := TObject.Create;

finalization
  Map.Free;
  MapLock.Free;

end.
