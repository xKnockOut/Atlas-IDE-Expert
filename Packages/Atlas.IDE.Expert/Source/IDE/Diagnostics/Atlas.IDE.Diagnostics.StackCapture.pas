unit Atlas.IDE.Diagnostics.StackCapture;

// Stacktraces für die Sicherung (#493) im IDE-Prozess. Ohne sie nannte jede
// Fehlerzeile nur Klasse und Meldung, und eine ausgelöste Sicherung ließ sich
// nicht bis zur Codezeile zurückverfolgen.
// - Install meldet einen Vectored Exception Handler an. Er läuft bei jeder
//   Ausnahme im Prozess, bevor der Stapel abgebaut wird, nimmt die
//   Rücksprungadressen auf (RtlCaptureStackBackTrace, ohne Speicher) und legt
//   sie nur ab, wenn ein Rahmen im Atlas-Modul liegt. Er ändert nichts an der
//   Ausnahme und gibt immer an die nächsten Behandler weiter. Anders als
//   Exception.GetExceptionStackInfoProc bleibt so die Einstellung der IDE
//   und anderer Experten unberührt.
// - TAtlasGuard.StackOf (Haken) sucht beim Melden den passenden Eintrag
//   (Objekt der Ausnahme bzw. Fehleradresse aus ExceptAddr) und beschreibt
//   ihn als "Modul+$Offset"; Rahmen im Atlas-Modul bekommen mit der
//   Map-Datei neben der BPL (DCC_MapFile=3) Unit, Routine und Zeile.
// - Uninstall vor dem Entladen meldet den Behandler wieder ab.
// Nur im Hauptthread installieren und abbauen; der Behandler läuft in jedem Thread.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Hangs;

type
  TAtlasIdeStackCapture = class
  public
    /// <summary>Behandler anmelden und TAtlasGuard.StackOf setzen.</summary>
    class procedure Install; static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
    /// <summary>Stacktrace zur gerade behandelten Ausnahme E (im except-Block aufrufen); '' ohne Mitschnitt.</summary>
    class function StackOf(E: Exception): string; static;
    /// <summary>Aufrufstapel des laufenden Threads ohne die ASkip innersten Rahmen (ohne diese Routine).</summary>
    class function CurrentStack(ASkip: Integer): string; static;
    /// <summary>Hängt an Rahmen "Atlas…bpl+Offset" (z. B. aus dem Einfrier-Wächter) Unit, Routine und Zeile an.
    /// </summary>
    class function Symbolize(const AFrames: TArray<string>): TArray<string>; static;
    /// <summary>Module des Prozesses mit Basis und Größe.</summary>
    class function Modules: TArray<TAtlasModuleRange>; static;
  end;

implementation

// Winapi.Windows vor Atlas.Text.MapFile und den eigenen Units; PExceptionRecord kommt nicht vor (eigene Typen).
uses
  Winapi.Windows,
  Winapi.PsAPI,
  System.IOUtils,
  System.SyncObjs,
  Atlas.Text.MapFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.StackRing,
  Atlas.Core.Files.TextFile;

type
  // Eigene Fassungen von EXCEPTION_RECORD/EXCEPTION_POINTERS: SysUtils und Winapi.Windows deklarieren
  // PExceptionRecord unterschiedlich.
  PRawExceptionRecord = ^TRawExceptionRecord;
  TRawExceptionRecord = record
    ExceptionCode: Cardinal;
    ExceptionFlags: Cardinal;
    ExceptionRecord: PRawExceptionRecord;
    ExceptionAddress: Pointer;
    NumberParameters: Cardinal;
    ExceptionInformation: array[0..14] of NativeUInt;
  end;
  PRawExceptionPointers = ^TRawExceptionPointers;
  TRawExceptionPointers = record
    ExceptionRecord: PRawExceptionRecord;
    ContextRecord: Pointer;
  end;

const
  ExceptionContinueSearch = 0;
  StatusStackOverflow = $C00000FD;
  // Hinweise des Debuggers und Thread-Namen: keine Fehler.
  DbgPrintException = $40010006;
  DbgPrintExceptionWide = $4001000A;
  MsVcThreadName = $406D1388;
  StatusBreakpoint = $80000003;
  StatusSingleStep = $80000004;
  /// <summary>Höchstens so viele Zeilen je Fehlerzeile im Protokoll.</summary>
  MaxLines = 32;

function AddVectoredExceptionHandler(AFirst: ULONG; AHandler: Pointer): Pointer; stdcall;
  external kernel32 name 'AddVectoredExceptionHandler';
function RemoveVectoredExceptionHandler(AHandle: Pointer): ULONG; stdcall;
  external kernel32 name 'RemoveVectoredExceptionHandler';
function CaptureStackBackTrace(AFramesToSkip, AFramesToCapture: ULONG; ABackTrace: Pointer;
  ABackTraceHash: PULONG): USHORT; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';

var
  Handle: Pointer;
  Ring: TAtlasStackRing;
  // Bereich des Atlas-Moduls und von ntdll (dessen Rahmen vorn sind die Ausnahmeverteilung selbst).
  OwnBase, OwnEnd, NtBase, NtEnd: NativeUInt;
  OwnName: string;
  MapLock: TCriticalSection;
  MapLoaded: Boolean;
  Map: TMapFile;

/// <summary>Bereich eines geladenen Moduls aus seinem PE-Kopf.</summary>
procedure ModuleRange(AModule: HMODULE; out ABase, AEnd: NativeUInt);
var
  Info: TModuleInfo;
begin
  ABase := 0;
  AEnd := 0;
  if (AModule <> 0) and GetModuleInformation(GetCurrentProcess, AModule, @Info, SizeOf(Info)) then
  begin
    ABase := NativeUInt(Info.lpBaseOfDll);
    AEnd := ABase + Info.SizeOfImage;
  end;
end;

/// <summary>Beim Stapelüberlauf ist kein Platz für den Mitschnitt; Hinweise des Debuggers sind keine Fehler.</summary>
function Ignored(ACode: Cardinal): Boolean;
begin
  Result := (ACode = StatusStackOverflow) or (ACode = DbgPrintException) or (ACode = DbgPrintExceptionWide) or
    (ACode = MsVcThreadName) or (ACode = StatusBreakpoint) or (ACode = StatusSingleStep);
end;

function InOwnModule(AAddress: NativeUInt): Boolean;
begin
  Result := (AAddress >= OwnBase) and (AAddress < OwnEnd);
end;

/// <summary>Läuft im Ausnahmebehandler des Systems: kein Speicher, keine Sperren, keine Ausnahme nach außen.</summary>
function Handler(AInfo: PRawExceptionPointers): Integer; stdcall;
var
  Raw: PRawExceptionRecord;
  Captured: array[0..TAtlasStackRecord.MaxFrames + 7] of Pointer;
  Count, First, Index: Integer;
  Item: TAtlasStackRecord;
  Ours: Boolean;
begin
  Result := ExceptionContinueSearch;
  if (Ring = nil) or (AInfo = nil) or (AInfo^.ExceptionRecord = nil) then
    Exit;
  Raw := AInfo^.ExceptionRecord;
  if Ignored(Raw^.ExceptionCode) then
    Exit;
  Count := CaptureStackBackTrace(1, Length(Captured), @Captured[0], nil);
  // Vorn steht die Ausnahmeverteilung von ntdll; sie sagt nichts über die Ursache.
  First := 0;
  while (First < Count) and (NativeUInt(Captured[First]) >= NtBase) and (NativeUInt(Captured[First]) < NtEnd) do
    Inc(First);
  Ours := InOwnModule(NativeUInt(Raw^.ExceptionAddress));
  for Index := First to Count - 1 do
    if InOwnModule(NativeUInt(Captured[Index])) then
      Ours := True;
  if not Ours then
    Exit;
  Item := Default(TAtlasStackRecord);
  Item.ThreadId := GetCurrentThreadId;
  Item.Code := Raw^.ExceptionCode;
  Item.Address := NativeUInt(Raw^.ExceptionAddress);
  Item.ParamCount := 0;
  for Index := 0 to Integer(Raw^.NumberParameters) - 1 do
    if Index < TAtlasStackRecord.MaxParams then
    begin
      Item.Params[Index] := Raw^.ExceptionInformation[Index];
      Item.ParamCount := Index + 1;
    end;
  Item.Count := 0;
  for Index := First to Count - 1 do
    if Item.Count < TAtlasStackRecord.MaxFrames then
    begin
      Item.Frames[Item.Count] := NativeUInt(Captured[Index]);
      Inc(Item.Count);
    end;
  Ring.Add(Item);
end;

function LoadedMap: TMapFile;
var
  Candidates: TArray<string>;
  Name, Module, Digits: string;
  Index: Integer;
begin
  MapLock.Enter;
  try
    if not MapLoaded then
    begin
      MapLoaded := True;
      Module := GetModuleName(HInstance);
      // Neben der BPL unter ihrem Namen (Installer, Release), sonst wie der Linker sie nennt: ohne die
      // Versionsendung von LIBSUFFIX AUTO (Atlas.IDE.Expert370.bpl → Atlas.IDE.Expert.map).
      Candidates := [ChangeFileExt(Module, '.map')];
      Name := TPath.GetFileNameWithoutExtension(Module);
      Index := Length(Name);
      while (Index > 0) and CharInSet(Name[Index], ['0'..'9']) do
        Dec(Index);
      Digits := Copy(Name, Index + 1, MaxInt);
      if Digits <> '' then
        Candidates := Candidates + [TPath.Combine(ExtractFilePath(Module), Copy(Name, 1, Index) + '.map')];
      for Name in Candidates do
        if TFile.Exists(Name) then
        begin
          try
            Map := TMapFile.Create(TAtlasTextFile.LoadText(Name));
            TAtlasGuard.Log('Stacktraces: Map-Datei ' + ExtractFileName(Name) + ' geladen');
          except
            on E: Exception do
            begin
              FreeAndNil(Map);
              TAtlasGuard.Log('Stacktraces: Map-Datei nicht lesbar: ' + TAtlasGuard.SafeMessage(E.Message));
            end;
          end;
          Break;
        end;
      if Map = nil then
        TAtlasGuard.Log('Stacktraces ohne Map-Datei (Rahmen als Modul+Offset)');
    end;
    Result := Map;
  finally
    MapLock.Leave;
  end;
end;

{ TAtlasIdeStackCapture }

class procedure TAtlasIdeStackCapture.Install;
begin
  if Handle <> nil then
    Exit;
  ModuleRange(HInstance, OwnBase, OwnEnd);
  ModuleRange(GetModuleHandle('ntdll.dll'), NtBase, NtEnd);
  OwnName := ExtractFileName(GetModuleName(HInstance));
  if Ring = nil then
    Ring := TAtlasStackRing.Create;
  Ring.Clear;
  Handle := AddVectoredExceptionHandler(0, @Handler);
  if Handle = nil then
  begin
    TAtlasGuard.Log('Stacktraces: Ausnahmebehandler nicht angemeldet (' + SysErrorMessage(GetLastError) + ')');
    Exit;
  end;
  TAtlasGuard.StackOf :=
    function(E: Exception): string
    begin
      Result := TAtlasIdeStackCapture.StackOf(E);
    end;
end;

class procedure TAtlasIdeStackCapture.Uninstall;
begin
  TAtlasGuard.StackOf := nil;
  if Handle <> nil then
  begin
    RemoveVectoredExceptionHandler(Handle);
    Handle := nil;
  end;
end;

class function TAtlasIdeStackCapture.Installed: Boolean;
begin
  Result := Handle <> nil;
end;

class function TAtlasIdeStackCapture.StackOf(E: Exception): string;
var
  Item: TAtlasStackRecord;
begin
  Result := '';
  if (Ring = nil) or (E = nil) then
    Exit;
  // Delphi-Ausnahmen tragen ihr Objekt und die Adresse von raise in den Parametern, Prozessorfehler
  // (Zugriffsverletzung) die Fehleradresse im Record; ExceptAddr liefert beides für die laufende Behandlung.
  if not Ring.Find(GetCurrentThreadId, [NativeUInt(Pointer(E)), NativeUInt(ExceptAddr)], Item) then
    Exit;
  Result := TAtlasStackFrames.Describe(Item.Addresses, Modules, LoadedMap, OwnName, MaxLines);
end;

class function TAtlasIdeStackCapture.CurrentStack(ASkip: Integer): string;
var
  Frames: array[0..TAtlasStackRecord.MaxFrames - 1] of Pointer;
  Count, Index: Integer;
  Addresses: TArray<UInt64>;
begin
  Count := CaptureStackBackTrace(ASkip + 1, Length(Frames), @Frames[0], nil);
  SetLength(Addresses, Count);
  for Index := 0 to Count - 1 do
    Addresses[Index] := UInt64(NativeUInt(Frames[Index]));
  if OwnName = '' then
    OwnName := ExtractFileName(GetModuleName(HInstance));
  Result := TAtlasStackFrames.Describe(Addresses, Modules, LoadedMap, OwnName, MaxLines);
end;

class function TAtlasIdeStackCapture.Symbolize(const AFrames: TArray<string>): TArray<string>;
var
  Index: Integer;
  Loaded: TMapFile;
begin
  Result := Copy(AFrames);
  Loaded := LoadedMap;
  if Loaded = nil then
    Exit;
  if OwnName = '' then
    OwnName := ExtractFileName(GetModuleName(HInstance));
  for Index := 0 to High(Result) do
    Result[Index] := TAtlasStackFrames.Symbolize(Result[Index], Loaded, OwnName);
end;

class function TAtlasIdeStackCapture.Modules: TArray<TAtlasModuleRange>;
var
  Handles: array[0..1023] of HMODULE;
  Needed: DWORD;
  Index: Integer;
  Info: TModuleInfo;
  Name: array[0..MAX_PATH] of Char;
  Range: TAtlasModuleRange;
begin
  Result := nil;
  if not EnumProcessModules(GetCurrentProcess, @Handles[0], SizeOf(Handles), Needed) then
    Exit;
  for Index := 0 to Integer(Needed div SizeOf(HMODULE)) - 1 do
    if (Index <= High(Handles)) and GetModuleInformation(GetCurrentProcess, Handles[Index], @Info, SizeOf(Info)) and
      (GetModuleFileName(Handles[Index], Name, Length(Name)) > 0) then
    begin
      Range.Name := ExtractFileName(Name);
      Range.Base := NativeUInt(Info.lpBaseOfDll);
      Range.Size := Info.SizeOfImage;
      Result := Result + [Range];
    end;
end;

initialization
  MapLock := TCriticalSection.Create;

finalization
  TAtlasIdeStackCapture.Uninstall;
  FreeAndNil(Ring);
  FreeAndNil(Map);
  FreeAndNil(MapLock);

end.
