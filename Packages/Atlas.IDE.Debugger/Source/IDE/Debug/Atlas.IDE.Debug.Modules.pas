unit Atlas.IDE.Debug.Modules;

// Modul der Fehleradresse (#1820) in der IDE: liest beim Halt die geladenen Module des debuggten Prozesses
// (Name, Pfad, Basisadresse, Größe) und die Ordner für die Einstufung (Delphi-Installation, Windows).
//   - Die Liste kommt aus dem Prozess selbst (EnumProcessModulesEx, alle Module auch eines 32-Bit-Programms
//     unter einer 64-Bit-IDE). Sie wird bei jeder Zugriffsverletzung neu gelesen; mit LoadLibrary nachgeladene
//     DLLs sind damit dabei, ohne dass Atlas Lade- und Entladeereignisse mitschreiben muss.
//   - Kann eine 32-Bit-IDE ein 64-Bit-Programm nicht lesen, bleibt die Liste leer; die Einstufung nimmt dann den
//     Namen aus der Meldung der RTL bzw. den obersten Rahmen ohne Symbole (TAtlasDebugModuleMap.Resolve).
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Modules,
  Atlas.Core.Debug.ExceptionBanner;

type
  /// <summary>Was die Erklärung einer Zugriffsverletzung über das Modul der Fehleradresse sagt (#1820).</summary>
  TAtlasDebugModuleNote = record
    Known: Boolean;
    Module: TAtlasDebugFaultModule;
    Frames: TAtlasDebugFrames;
    /// <summary>Ort für Kopf und Meldungen: die letzte eigene Stelle, sonst der Modulname.</summary>
    FileName: string;
    /// <summary>0-basiert; -1 = nur der Modulname.</summary>
    Line: Integer;
    /// <summary>„Adresse liegt in …“; '' ohne bekanntes Modul.</summary>
    function Text: string;
    /// <summary>Erklärung nur aus dem Modul (Halt nicht in eigenem Code); AHeader für den kopierten Text.</summary>
    function Explanation(const AHeader: string): TAtlasDebugBannerExplanation;
  end;

  TAtlasIdeDebugModules = class
  public const
    /// <summary>Höchstens so viele Module liest Atlas.</summary>
    cMaxModules = 4096;
  public
    /// <summary>Geladene Module des Prozesses AProcessId; leer, wenn er sich nicht lesen lässt.</summary>
    class function Snapshot(AProcessId: Cardinal): TAtlasDebugModuleList; static;
    /// <summary>Programm (erstes Modul der Liste), Delphi-Installation und Windows-Ordner.</summary>
    class function Environment(const AModules: TAtlasDebugModuleList): TAtlasDebugModuleEnvironment; static;
    /// <summary>Modul der Fehleradresse des aktuellen Halts aus Meldung und Aufrufstapel (eigene Rahmen gesetzt).
    /// </summary>
    class function Note(const AMessage: string; const AFrames: TAtlasDebugFrames): TAtlasDebugModuleNote; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.PsAPI,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.AccessViolation;

const
  cListModulesAll = $03;

function AtlasEnumProcessModulesEx(AProcess: THandle; AModules: Pointer; ASize: DWORD; var ANeeded: DWORD;
  AFilter: DWORD): BOOL; stdcall; external 'psapi.dll' name 'EnumProcessModulesEx';

class function TAtlasIdeDebugModules.Snapshot(AProcessId: Cardinal): TAtlasDebugModuleList;
var
  mProcess: THandle;
  mHandles: array of HMODULE;
  mNeeded: DWORD;
  mIndex, mCount: Integer;
  mInfo: TModuleInfo;
  mName: array[0..MAX_PATH] of Char;
begin
  Result := nil;
  if AProcessId = 0 then
  begin
    Exit;
  end;
  mProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, AProcessId);
  if mProcess = 0 then
  begin
    TAtlasGuard.Log(Format('Module des Prozesses nicht lesbar (OpenProcess, Fehler %d)', // german-ok: Protokoll
      [GetLastError]));
    Exit;
  end;
  try
    SetLength(mHandles, cMaxModules);
    mNeeded := 0;
    if not AtlasEnumProcessModulesEx(mProcess, @mHandles[0], DWORD(Length(mHandles) * SizeOf(HMODULE)), mNeeded,
      cListModulesAll) then
    begin
      // 32-Bit-IDE und 64-Bit-Programm (ERROR_PARTIAL_COPY): Name aus der Meldung bzw. dem Stapel.
      TAtlasGuard.Log(Format('Module nicht lesbar (EnumProcessModulesEx, Fehler %d)', // german-ok: Protokoll

        [GetLastError]));
      Exit;
    end;
    mCount := Integer(mNeeded div SizeOf(HMODULE));
    if mCount > Length(mHandles) then
    begin
      mCount := Length(mHandles);
    end;
    for mIndex := 0 to mCount - 1 do
    begin
      if GetModuleInformation(mProcess, mHandles[mIndex], @mInfo, SizeOf(mInfo)) and
        (GetModuleFileNameEx(mProcess, mHandles[mIndex], mName, Length(mName)) > 0) then
      begin
        Result := Result + [TAtlasDebugLoadedModule.Create(mName, UInt64(NativeUInt(mInfo.lpBaseOfDll)),
          mInfo.SizeOfImage)];
      end;
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

class function TAtlasIdeDebugModules.Environment(const AModules: TAtlasDebugModuleList): TAtlasDebugModuleEnvironment;
var
  mServices: IOTAServices;
  mWindows: array[0..MAX_PATH] of Char;
begin
  Result := Default(TAtlasDebugModuleEnvironment);
  // Das erste Modul der Liste ist das Programm selbst.
  if Length(AModules) > 0 then
  begin
    Result.ProgramFile := AModules[0].FileName;
  end;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result.BdsDir := ExcludeTrailingPathDelimiter(mServices.GetRootDirectory);
  end;
  if GetWindowsDirectory(mWindows, Length(mWindows)) > 0 then
  begin
    Result.WindowsDir := mWindows;
  end;
end;

class function TAtlasIdeDebugModules.Note(const AMessage: string;
  const AFrames: TAtlasDebugFrames): TAtlasDebugModuleNote;
var
  mProcess: IOTAProcess;
  mModules: TAtlasDebugModuleList;
begin
  mModules := nil;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    mModules := Snapshot(mProcess.ProcessId);
  end;
  Result := Default(TAtlasDebugModuleNote);
  Result.Module := TAtlasDebugModuleMap.Resolve(AMessage, AFrames, mModules, Environment(mModules));
  Result.Known := Result.Module.Known;
  Result.Frames := AFrames;
  if Result.Module.OwnFrame >= 0 then
  begin
    Result.FileName := AFrames[Result.Module.OwnFrame].FileName;
    Result.Line := AFrames[Result.Module.OwnFrame].Line - 1;
  end
  else
  begin
    Result.FileName := Result.Module.Name;
    Result.Line := -1;
  end;
end;

{ TAtlasDebugModuleNote }

function TAtlasDebugModuleNote.Text: string;
begin
  Result := TAtlasAvTexts.ModuleText(Module);
end;

function TAtlasDebugModuleNote.Explanation(const AHeader: string): TAtlasDebugBannerExplanation;
begin
  Result := TAtlasAvTexts.ModuleOnly(Module, Frames, AHeader);
end;


end.
