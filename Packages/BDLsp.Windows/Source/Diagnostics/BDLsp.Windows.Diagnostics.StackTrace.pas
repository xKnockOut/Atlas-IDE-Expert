unit BDLsp.Windows.Diagnostics.StackTrace;

// Platform-Feature "Diagnostics", Root: Stacktraces für Exceptions.
// Install hängt sich in Exception.GetExceptionStackInfoProc ein; danach
// liefert Exception.StackTrace die Aufrufkette zum Zeitpunkt des raise als
// "Modul+$Offset" je Zeile. Den Offset löst die .map-Datei des Builds auf
// (Linker-Option "Map-Datei: detailliert"; Adresse = Offset - $1000 im
// Codeabschnitt).

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
  System.SysUtils;

const
  MaxFrames = 48;
  ModuleFromAddress = $00000004; // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
  ModuleUnchangedRefCount = $00000002; // GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT

// Winapi.Windows deklariert GetModuleHandleEx nicht.
function GetModuleHandleEx(dwFlags: DWORD; lpModuleName: LPCWSTR; var phModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';

type
  PStackInfo = ^TStackInfo;
  TStackInfo = record
    Count: Integer;
    Frames: array[0..MaxFrames - 1] of Pointer;
  end;

function CaptureStackBackTrace(AFramesToSkip, AFramesToCapture: ULONG; ABackTrace: Pointer;
  ABackTraceHash: PULONG): USHORT; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';

var
  PreviousGetInfo: function(P: PExceptionRecord): Pointer;
  PreviousGetString: function(Info: Pointer): string;
  PreviousCleanUp: procedure(Info: Pointer);
  IsInstalled: Boolean;

function Capture(ASkip: Integer): PStackInfo;
begin
  New(Result);
  Result.Count := CaptureStackBackTrace(ASkip + 1, MaxFrames, @Result.Frames[0], nil);
end;

function Describe(AInfo: PStackInfo): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to AInfo.Count - 1 do
    Result := Result + TStackTrace.DescribeAddress(AInfo.Frames[Index]) + sLineBreak;
end;

function GetExceptionStackInfo(P: PExceptionRecord): Pointer;
begin
  // Die ersten Rahmen gehören zur RTL (RaisingException); sie bleiben drin,
  // damit nichts Wichtiges fehlt, falls sich die RTL ändert.
  Result := Capture(1);
end;

function GetStackInfoString(Info: Pointer): string;
begin
  if Info = nil then
    Result := ''
  else
    Result := Describe(PStackInfo(Info));
end;

procedure CleanUpStackInfo(Info: Pointer);
begin
  if Info <> nil then
    Dispose(PStackInfo(Info));
end;

{ TStackTrace }

class procedure TStackTrace.Install;
begin
  if IsInstalled then
    Exit;
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
    Exit;
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
  Info: PStackInfo;
begin
  Info := Capture(1);
  try
    Result := Describe(Info);
  finally
    Dispose(Info);
  end;
end;

class function TStackTrace.DescribeAddress(AAddress: Pointer): string;
var
  Module: HMODULE;
  FileName: array[0..MAX_PATH] of Char;
begin
  if GetModuleHandleEx(ModuleFromAddress or ModuleUnchangedRefCount, PChar(AAddress), Module) and
    (GetModuleFileName(Module, FileName, Length(FileName)) > 0) then
    Result := Format('%s+$%x', [ExtractFileName(FileName), NativeUInt(AAddress) - NativeUInt(Module)])
  else
    Result := Format('$%p', [AAddress]);
end;

end.
