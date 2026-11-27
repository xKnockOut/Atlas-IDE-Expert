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
// - Symbolize löst auch Rahmen der Module (Atlas…bpl) über deren Map-Datei auf,
//   geladen beim ersten Rahmen des Moduls; sonst blieben Hänger in Modulen
//   (Willkommensseite, Prüfregeln) bloße Offsets.
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
    class function StackOf(AE: Exception): string; static;
    /// <summary>Hängt an Rahmen "Atlas…bpl+Offset" (z. B. aus dem Einfrier-Wächter) Unit, Routine und Zeile an.
    /// </summary>
    class function Symbolize(const AFrames: TArray<string>): TArray<string>; static;
    /// <summary>Module des Prozesses mit Basis, Größe und dem ausführbaren Teil (Abschnitte mit Code).</summary>
    class function Modules: TArray<TAtlasModuleRange>; static;
  end;

implementation

// Winapi.Windows vor Atlas.Text.MapFile und den eigenen Units; PExceptionRecord kommt nicht vor (eigene Typen).
uses
  Winapi.Windows,
  Winapi.PsAPI,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Text.MapFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.StackRing;

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
  cExceptionContinueSearch = 0;
  cStatusStackOverflow = $C00000FD;
  // Hinweise des Debuggers und Thread-Namen: keine Fehler.
  cDbgPrintException = $40010006;
  cDbgPrintExceptionWide = $4001000A;
  cMsVcThreadName = $406D1388;
  cStatusBreakpoint = $80000003;
  cStatusSingleStep = $80000004;
  /// <summary>Höchstens so viele Zeilen je Fehlerzeile im Protokoll.</summary>
  cMaxLines = 32;

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
  // Map-Dateien der Module nach Dateiname des Moduls (klein); nil = keine lesbar. Unter MapLock.
  ModuleMaps: TObjectDictionary<string, TMapFile>;

/// <summary>Bereich eines geladenen Moduls aus seinem PE-Kopf.</summary>
procedure ModuleRange(AModule: HMODULE; out ABase, AEnd: NativeUInt);
var
  mInfo: TModuleInfo;
begin
  ABase := 0;
  AEnd := 0;
  if (AModule <> 0) and GetModuleInformation(GetCurrentProcess, AModule, @mInfo, SizeOf(mInfo)) then
  begin
    ABase := NativeUInt(mInfo.lpBaseOfDll);
    AEnd := ABase + mInfo.SizeOfImage;
  end;
end;

/// <summary>Beim Stapelüberlauf ist kein Platz für den Mitschnitt; Hinweise des Debuggers sind keine Fehler.</summary>
function Ignored(ACode: Cardinal): Boolean;
begin
  Result := (ACode = cStatusStackOverflow) or (ACode = cDbgPrintException) or (ACode = cDbgPrintExceptionWide) or
    (ACode = cMsVcThreadName) or (ACode = cStatusBreakpoint) or (ACode = cStatusSingleStep);
end;

function InOwnModule(AAddress: NativeUInt): Boolean;
begin
  Result := (AAddress >= OwnBase) and (AAddress < OwnEnd);
end;

/// <summary>Läuft im Ausnahmebehandler des Systems: kein Speicher, keine Sperren, keine Ausnahme nach außen.</summary>
function Handler(AInfo: PRawExceptionPointers): Integer; stdcall;
var
  mRaw: PRawExceptionRecord;
  mCaptured: array[0..TAtlasStackRecord.cMaxFrames + 7] of Pointer;
  mCount, mFirst, mIndex: Integer;
  mItem: TAtlasStackRecord;
  mOurs: Boolean;
begin
  Result := cExceptionContinueSearch;
  if (Ring = nil) or (AInfo = nil) or (AInfo^.ExceptionRecord = nil) then
  begin
    Exit;
  end;
  mRaw := AInfo^.ExceptionRecord;
  if Ignored(mRaw^.ExceptionCode) then
  begin
    Exit;
  end;
  mCount := CaptureStackBackTrace(1, Length(mCaptured), @mCaptured[0], nil);
  // Vorn steht die Ausnahmeverteilung von ntdll; sie sagt nichts über die Ursache.
  mFirst := 0;
  while (mFirst < mCount) and (NativeUInt(mCaptured[mFirst]) >= NtBase) and (NativeUInt(mCaptured[mFirst]) < NtEnd) do
  begin
    Inc(mFirst);
  end;
  mOurs := InOwnModule(NativeUInt(mRaw^.ExceptionAddress));
  for mIndex := mFirst to mCount - 1 do
  begin
    if InOwnModule(NativeUInt(mCaptured[mIndex])) then
    begin
      mOurs := True;
    end;
  end;
  if not mOurs then
  begin
    Exit;
  end;
  mItem := Default(TAtlasStackRecord);
  mItem.ThreadId := GetCurrentThreadId;
  mItem.Code := mRaw^.ExceptionCode;
  mItem.Address := NativeUInt(mRaw^.ExceptionAddress);
  mItem.ParamCount := 0;
  for mIndex := 0 to Integer(mRaw^.NumberParameters) - 1 do
  begin
    if mIndex < TAtlasStackRecord.cMaxParams then
    begin
      mItem.Params[mIndex] := mRaw^.ExceptionInformation[mIndex];
      mItem.ParamCount := mIndex + 1;
    end;
  end;
  mItem.Count := 0;
  for mIndex := mFirst to mCount - 1 do
  begin
    if mItem.Count < TAtlasStackRecord.cMaxFrames then
    begin
      mItem.Frames[mItem.Count] := NativeUInt(mCaptured[mIndex]);
      Inc(mItem.Count);
    end;
  end;
  Ring.Add(mItem);
end;

/// <summary>Neben der BPL unter ihrem Namen (Release-Paket), sonst wie der Linker sie nennt: ohne die
/// Versionsendung von LIBSUFFIX AUTO (Atlas.IDE.Base370.bpl → Atlas.IDE.Base.map).</summary>
function MapCandidates(const AModule: string): TArray<string>;
var
  mName: string;
  mIndex: Integer;
begin
  Result := [ChangeFileExt(AModule, '.map')];
  mName := TPath.GetFileNameWithoutExtension(AModule);
  mIndex := Length(mName);
  while (mIndex > 0) and CharInSet(mName[mIndex], ['0'..'9']) do
  begin
    Dec(mIndex);
  end;
  if mIndex < Length(mName) then
  begin
    Result := Result + [TPath.Combine(ExtractFilePath(AModule), Copy(mName, 1, mIndex) + '.map')];
  end;
end;

/// <summary>Erste vorhandene Map-Datei aus ACandidates; nil ohne oder wenn sie nicht lesbar ist.</summary>
function LoadMapFile(const ACandidates: TArray<string>): TMapFile;
var
  mName: string;
begin
  Result := nil;
  for mName in ACandidates do
  begin
    if TFile.Exists(mName) then
    begin
      try
        Result := TMapFile.CreateFromFile(mName);
        TAtlasGuard.Log('Stacktraces: Map-Datei ' + ExtractFileName(mName) + ' geladen');
      except
        on E: Exception do
        begin
          FreeAndNil(Result);
          TAtlasGuard.Log('Stacktraces: Map-Datei nicht lesbar: ' + TAtlasGuard.MessageText(E.Message));
        end;
      end;
      Break;
    end;
  end;
end;

function LoadedMap: TMapFile;
begin
  MapLock.Enter;
  try
    if not MapLoaded then
    begin
      MapLoaded := True;
      Map := LoadMapFile(MapCandidates(GetModuleName(HInstance)));
      if Map = nil then
      begin
        TAtlasGuard.Log('Stacktraces ohne Map-Datei (Rahmen als Modul+Offset)');
      end;
    end;
    Result := Map;
  finally
    MapLock.Leave;
  end;
end;

/// <summary>Map-Datei des geladenen Moduls AModule (Dateiname wie im Rahmen); nil ohne. Einmal je Modul gelesen.
/// </summary>
function ModuleMap(const AModule: string): TMapFile;
var
  mKey: string;
  mHandle: HMODULE;
begin
  mKey := LowerCase(AModule);
  MapLock.Enter;
  try
    if ModuleMaps.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := nil;
    mHandle := GetModuleHandle(PChar(AModule));
    if mHandle <> 0 then
    begin
      Result := LoadMapFile(MapCandidates(GetModuleName(mHandle)));
    end;
    ModuleMaps.Add(mKey, Result);
  finally
    MapLock.Leave;
  end;
end;

const
  /// <summary>Dateinamen der Atlas-Module beginnen so (wie TAtlasStackScan.FirstIn im Einfrier-Wächter).</summary>
  cAtlasModulePrefix = 'Atlas';

/// <summary>Modul eines Rahmens "Modul+Offset"; '' ohne „+“.</summary>
function FrameModule(const AFrame: string): string;
var
  mPlus: Integer;
begin
  mPlus := Pos('+', AFrame);
  Result := '';
  if mPlus > 1 then
  begin
    Result := Copy(AFrame, 1, mPlus - 1);
  end;
end;

{ TAtlasIdeStackCapture }

class procedure TAtlasIdeStackCapture.Install;
begin
  if Handle <> nil then
  begin
    Exit;
  end;
  ModuleRange(HInstance, OwnBase, OwnEnd);
  ModuleRange(GetModuleHandle('ntdll.dll'), NtBase, NtEnd);
  OwnName := ExtractFileName(GetModuleName(HInstance));
  if Ring = nil then
  begin
    Ring := TAtlasStackRing.Create;
  end;
  Ring.Clear;
  Handle := AddVectoredExceptionHandler(0, @Handler);
  if Handle = nil then
  begin
    TAtlasGuard.Log('Stacktraces: Ausnahmebehandler nicht angemeldet (' + SysErrorMessage(GetLastError) + ')');
    Exit;
  end;
  TAtlasGuard.StackOf :=
    function(AE: Exception): string
    begin
      Result := TAtlasIdeStackCapture.StackOf(AE);
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

class function TAtlasIdeStackCapture.StackOf(AE: Exception): string;
var
  mItem: TAtlasStackRecord;
begin
  Result := '';
  if (Ring = nil) or (AE = nil) then
  begin
    Exit;
  end;
  // Delphi-Ausnahmen tragen ihr Objekt und die Adresse von raise in den Parametern, Prozessorfehler
  // (Zugriffsverletzung) die Fehleradresse im Record; ExceptAddr liefert beides für die laufende Behandlung.
  if not Ring.Find(GetCurrentThreadId, [NativeUInt(Pointer(AE)), NativeUInt(ExceptAddr)], mItem) then
  begin
    Exit;
  end;
  Result := TAtlasStackFrames.Describe(mItem.Addresses, Modules, LoadedMap, OwnName, cMaxLines);
end;

class function TAtlasIdeStackCapture.Symbolize(const AFrames: TArray<string>): TArray<string>;
var
  mIndex: Integer;
  mLoaded: TMapFile;
  mModule: string;
begin
  Result := Copy(AFrames);
  if OwnName = '' then
  begin
    OwnName := ExtractFileName(GetModuleName(HInstance));
  end;
  for mIndex := 0 to High(Result) do
  begin
    mModule := FrameModule(Result[mIndex]);
    if SameText(mModule, OwnName) then
    begin
      mLoaded := LoadedMap;
    end
    else if mModule.StartsWith(cAtlasModulePrefix, True) then
    begin
      mLoaded := ModuleMap(mModule);
    end
    else
    begin
      Continue;
    end;
    Result[mIndex] := TAtlasStackFrames.Symbolize(Result[mIndex], mLoaded, mModule);
  end;
end;

/// <summary>Ausführbarer Teil des geladenen Moduls ab ABase aus seinen Abschnitten (IMAGE_SCN_MEM_EXECUTE), als
/// Abstand zu ABase und Länge; ohne lesbaren PE-Kopf 0 und 0 (dann zählt das ganze Abbild).</summary>
procedure CodeRange(ABase: NativeUInt; ASize: UInt64; out AStart, ALength: UInt64);
var
  mDos: PImageDosHeader;
  mNt: PImageNtHeaders;
  mSection: PImageSectionHeader;
  mIndex: Integer;
  mFirst, mLast: UInt64;
begin
  AStart := 0;
  ALength := 0;
  mDos := PImageDosHeader(ABase);
  if (mDos.e_magic <> IMAGE_DOS_SIGNATURE) or (mDos._lfanew <= 0) or (UInt64(mDos._lfanew) >= ASize) then
  begin
    Exit;
  end;
  mNt := PImageNtHeaders(ABase + NativeUInt(mDos._lfanew));
  if mNt.Signature <> IMAGE_NT_SIGNATURE then
  begin
    Exit;
  end;
  // Die Abschnitte folgen dem optionalen Kopf (IMAGE_FIRST_SECTION).
  mSection := PImageSectionHeader(NativeUInt(@mNt.OptionalHeader) + mNt.FileHeader.SizeOfOptionalHeader);
  mFirst := High(UInt64);
  mLast := 0;
  for mIndex := 1 to mNt.FileHeader.NumberOfSections do
  begin
    if (mSection.Characteristics and IMAGE_SCN_MEM_EXECUTE) <> 0 then
    begin
      if mSection.VirtualAddress < mFirst then
      begin
        mFirst := mSection.VirtualAddress;
      end;
      if UInt64(mSection.VirtualAddress) + mSection.Misc.VirtualSize > mLast then
      begin
        mLast := UInt64(mSection.VirtualAddress) + mSection.Misc.VirtualSize;
      end;
    end;
    Inc(mSection);
  end;
  if (mLast > mFirst) and (mLast <= ASize) then
  begin
    AStart := mFirst;
    ALength := mLast - mFirst;
  end;
end;

class function TAtlasIdeStackCapture.Modules: TArray<TAtlasModuleRange>;
var
  mHandles: array[0..1023] of HMODULE;
  mNeeded: DWORD;
  mIndex: Integer;
  mInfo: TModuleInfo;
  mName: array[0..MAX_PATH] of Char;
  mRange: TAtlasModuleRange;
begin
  Result := nil;
  if not EnumProcessModules(GetCurrentProcess, @mHandles[0], SizeOf(mHandles), mNeeded) then
  begin
    Exit;
  end;
  for mIndex := 0 to Integer(mNeeded div SizeOf(HMODULE)) - 1 do
  begin
    if (mIndex <= High(mHandles)) and GetModuleInformation(GetCurrentProcess, mHandles[mIndex], @mInfo,
      SizeOf(mInfo)) and
      (GetModuleFileName(mHandles[mIndex], mName, Length(mName)) > 0) then
    begin
      mRange := Default(TAtlasModuleRange);
      mRange.Name := ExtractFileName(mName);
      mRange.Base := NativeUInt(mInfo.lpBaseOfDll);
      mRange.Size := mInfo.SizeOfImage;
      // Nur Code zählt als Rahmen: Der Einfrier-Wächter liest den Stapel roh, mit Zeigern auf Daten.
      CodeRange(NativeUInt(mInfo.lpBaseOfDll), mInfo.SizeOfImage, mRange.CodeStart, mRange.CodeSize);
      Result := Result + [mRange];
    end;
  end;
end;

initialization
  MapLock := TCriticalSection.Create;
  ModuleMaps := TObjectDictionary<string, TMapFile>.Create([doOwnsValues], 16);

finalization
  TAtlasIdeStackCapture.Uninstall;
  FreeAndNil(Ring);
  FreeAndNil(Map);
  FreeAndNil(ModuleMaps);
  FreeAndNil(MapLock);

end.
