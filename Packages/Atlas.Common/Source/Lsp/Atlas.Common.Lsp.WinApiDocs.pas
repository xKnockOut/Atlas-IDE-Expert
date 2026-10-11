unit Atlas.Common.Lsp.WinApiDocs;

// Links zur Microsoft-Dokumentation für Funktionen und Strukturen aus Winapi.*
// im Hover (#120). learn.microsoft.com ordnet Seiten nach Header und
// A/W-Variante (…/api/winuser/nf-winuser-sendmessagew); Winapi.Windows bündelt
// viele Header. Deshalb liefert eine gepflegte Tabelle den direkten Link, ohne
// Eintrag gilt die Such-URL. Dazu die …Ptr-Varianten für 64 Bit, die auch die
// Win64-Migrationsregeln (#112) nutzen.

interface

uses
  System.SysUtils;

type
  /// <summary>32-Bit-Funktion und ihre 64-Bit-taugliche …Ptr-Variante.</summary>
  TPtrVariant = record
    Name: string;
    Replacement: string;
  end;

  TWinApiDocs = class
  public const
    ApiBase = 'https://learn.microsoft.com/windows/win32/api/';
    SearchBase = 'https://learn.microsoft.com/search/?terms=';
  public
    /// <summary>True für Units unter Winapi.*.</summary>
    class function IsWinApiUnit(const AUnitName: string): Boolean; static;
    /// <summary>Direkter Link aus der Tabelle (bei A/W-Funktionen die W-Variante, ausdrücklich A bleibt A);
    /// ohne Eintrag die Such-URL.</summary>
    class function Url(const AName: string): string; static;
    /// <summary>Steht AName in der Tabelle?</summary>
    class function IsKnown(const AName: string): Boolean; static;
    /// <summary>…Ptr-Variante zu AName (auch mit A/W-Suffix); '' ohne.</summary>
    class function PtrVariant(const AName: string): string; static;
    /// <summary>Alle …Ptr-Varianten, für #112 und die Tests.</summary>
    class function PtrVariants: TArray<TPtrVariant>; static;
    /// <summary>Alle Tabellen-Links, für die Tests.</summary>
    class function KnownUrls: TArray<string>; static;
    /// <summary>Markdown für den Hover: Link und ggf. Hinweis auf die …Ptr-Variante.</summary>
    class function HoverText(const AName: string): string; static;
  end;

implementation

uses
  System.StrUtils;

type
  /// <summary>Kind: nf = Funktion, ns = Struktur. WideVariant: Seite gibt es als …a und …w.</summary>
  TApiPage = record
    Name: string;
    Header: string;
    Kind: string;
    WideVariant: Boolean;
  end;

function Page(const AName, AHeader, AKind: string; AWideVariant: Boolean): TApiPage;
begin
  Result.Name := AName;
  Result.Header := AHeader;
  Result.Kind := AKind;
  Result.WideVariant := AWideVariant;
end;

function Pages: TArray<TApiPage>;
begin
  Result := [
    // winuser
    Page('SendMessage', 'winuser', 'nf', True), Page('PostMessage', 'winuser', 'nf', True),
    Page('MessageBox', 'winuser', 'nf', True), Page('FindWindow', 'winuser', 'nf', True),
    Page('GetWindowText', 'winuser', 'nf', True), Page('SetWindowText', 'winuser', 'nf', True),
    Page('CreateWindowEx', 'winuser', 'nf', True), Page('DefWindowProc', 'winuser', 'nf', True),
    Page('RegisterClassEx', 'winuser', 'nf', True), Page('GetMessage', 'winuser', 'nf', True),
    Page('DispatchMessage', 'winuser', 'nf', True), Page('PeekMessage', 'winuser', 'nf', True),
    Page('LoadIcon', 'winuser', 'nf', True), Page('LoadCursor', 'winuser', 'nf', True),
    Page('SetWindowLong', 'winuser', 'nf', True), Page('GetWindowLong', 'winuser', 'nf', True),
    Page('SetWindowLongPtr', 'winuser', 'nf', True), Page('GetWindowLongPtr', 'winuser', 'nf', True),
    Page('SetClassLong', 'winuser', 'nf', True), Page('GetClassLong', 'winuser', 'nf', True),
    Page('SetClassLongPtr', 'winuser', 'nf', True), Page('GetClassLongPtr', 'winuser', 'nf', True),
    Page('ShowWindow', 'winuser', 'nf', False), Page('GetWindowRect', 'winuser', 'nf', False),
    Page('SetWindowPos', 'winuser', 'nf', False), Page('GetDC', 'winuser', 'nf', False),
    Page('ReleaseDC', 'winuser', 'nf', False), Page('InvalidateRect', 'winuser', 'nf', False),
    Page('GetSystemMetrics', 'winuser', 'nf', False), Page('SetTimer', 'winuser', 'nf', False),
    Page('KillTimer', 'winuser', 'nf', False), Page('GetCursorPos', 'winuser', 'nf', False),
    Page('GetForegroundWindow', 'winuser', 'nf', False), Page('SetForegroundWindow', 'winuser', 'nf', False),
    Page('EnumWindows', 'winuser', 'nf', False), Page('IsWindow', 'winuser', 'nf', False),
    Page('IsWindowVisible', 'winuser', 'nf', False), Page('DestroyWindow', 'winuser', 'nf', False),
    Page('MSG', 'winuser', 'ns', False), Page('WNDCLASSEX', 'winuser', 'ns', True),
    // windef
    Page('RECT', 'windef', 'ns', False), Page('POINT', 'windef', 'ns', False),
    // fileapi, handleapi
    Page('CreateFile', 'fileapi', 'nf', True), Page('ReadFile', 'fileapi', 'nf', False),
    Page('WriteFile', 'fileapi', 'nf', False), Page('DeleteFile', 'fileapi', 'nf', True),
    Page('GetFileSize', 'fileapi', 'nf', False), Page('GetFileAttributes', 'fileapi', 'nf', True),
    Page('FindFirstFile', 'fileapi', 'nf', True), Page('FindNextFile', 'fileapi', 'nf', True),
    Page('FindClose', 'fileapi', 'nf', False), Page('CloseHandle', 'handleapi', 'nf', False),
    // synchapi
    Page('WaitForSingleObject', 'synchapi', 'nf', False), Page('CreateEvent', 'synchapi', 'nf', True),
    Page('SetEvent', 'synchapi', 'nf', False), Page('ResetEvent', 'synchapi', 'nf', False),
    Page('CreateMutex', 'synchapi', 'nf', True), Page('Sleep', 'synchapi', 'nf', False),
    Page('InitializeCriticalSection', 'synchapi', 'nf', False),
    Page('EnterCriticalSection', 'synchapi', 'nf', False), Page('LeaveCriticalSection', 'synchapi', 'nf', False),
    // processthreadsapi
    Page('CreateProcess', 'processthreadsapi', 'nf', True),
    Page('GetCurrentProcess', 'processthreadsapi', 'nf', False),
    Page('GetCurrentProcessId', 'processthreadsapi', 'nf', False),
    Page('GetCurrentThreadId', 'processthreadsapi', 'nf', False),
    Page('TerminateProcess', 'processthreadsapi', 'nf', False), Page('OpenProcess', 'processthreadsapi', 'nf', False),
    Page('GetExitCodeProcess', 'processthreadsapi', 'nf', False),
    // libloaderapi, errhandlingapi, sysinfoapi, profileapi, memoryapi
    Page('LoadLibrary', 'libloaderapi', 'nf', True), Page('FreeLibrary', 'libloaderapi', 'nf', False),
    Page('GetProcAddress', 'libloaderapi', 'nf', False), Page('GetModuleHandle', 'libloaderapi', 'nf', True),
    Page('GetModuleFileName', 'libloaderapi', 'nf', True), Page('GetLastError', 'errhandlingapi', 'nf', False),
    Page('SetLastError', 'errhandlingapi', 'nf', False), Page('GetTickCount', 'sysinfoapi', 'nf', False),
    Page('GetTickCount64', 'sysinfoapi', 'nf', False), Page('GetSystemInfo', 'sysinfoapi', 'nf', False),
    Page('GetLocalTime', 'sysinfoapi', 'nf', False), Page('GetSystemTime', 'sysinfoapi', 'nf', False),
    Page('QueryPerformanceCounter', 'profileapi', 'nf', False),
    Page('QueryPerformanceFrequency', 'profileapi', 'nf', False),
    Page('VirtualAlloc', 'memoryapi', 'nf', False), Page('VirtualFree', 'memoryapi', 'nf', False),
    // winbase, winreg, shellapi
    Page('FormatMessage', 'winbase', 'nf', True), Page('GetComputerName', 'winbase', 'nf', True),
    Page('RegOpenKeyEx', 'winreg', 'nf', True), Page('RegQueryValueEx', 'winreg', 'nf', True),
    Page('RegSetValueEx', 'winreg', 'nf', True), Page('RegCreateKeyEx', 'winreg', 'nf', True),
    Page('RegCloseKey', 'winreg', 'nf', False), Page('ShellExecute', 'shellapi', 'nf', True),
    Page('ShellExecuteEx', 'shellapi', 'nf', True)];
end;

const
  PtrPairs: array[0..3, 0..1] of string = (
    ('SetWindowLong', 'SetWindowLongPtr'), ('GetWindowLong', 'GetWindowLongPtr'),
    ('SetClassLong', 'SetClassLongPtr'), ('GetClassLong', 'GetClassLongPtr'));

/// <summary>Sucht AName, auch mit A/W-Suffix; ASuffix ist dann 'a' oder 'w', sonst ''.</summary>
function FindPage(const AName: string; out APage: TApiPage; out ASuffix: string): Boolean;
var
  Candidate: TApiPage;
  Base: string;
begin
  ASuffix := '';
  for Candidate in Pages do
    if SameText(Candidate.Name, AName) then
    begin
      APage := Candidate;
      if Candidate.WideVariant then
        ASuffix := 'w';
      Exit(True);
    end;
  if (Length(AName) > 1) and CharInSet(AName[Length(AName)], ['A', 'W']) then
  begin
    Base := Copy(AName, 1, Length(AName) - 1);
    for Candidate in Pages do
      if Candidate.WideVariant and SameText(Candidate.Name, Base) then
      begin
        APage := Candidate;
        ASuffix := LowerCase(AName[Length(AName)]);
        Exit(True);
      end;
  end;
  Result := False;
end;

function PageUrl(const APage: TApiPage; const ASuffix: string): string;
begin
  Result := TWinApiDocs.ApiBase + APage.Header + '/' + APage.Kind + '-' + APage.Header + '-' +
    LowerCase(APage.Name) + ASuffix;
end;

class function TWinApiDocs.IsWinApiUnit(const AUnitName: string): Boolean;
begin
  Result := StartsText('Winapi.', AUnitName);
end;

class function TWinApiDocs.IsKnown(const AName: string): Boolean;
var
  Found: TApiPage;
  Suffix: string;
begin
  Result := FindPage(AName, Found, Suffix);
end;

class function TWinApiDocs.Url(const AName: string): string;
var
  Found: TApiPage;
  Suffix: string;
begin
  if FindPage(AName, Found, Suffix) then
    Result := PageUrl(Found, Suffix)
  else
    Result := SearchBase + AName;
end;

class function TWinApiDocs.PtrVariants: TArray<TPtrVariant>;
var
  Index: Integer;
begin
  SetLength(Result, Length(PtrPairs));
  for Index := 0 to High(PtrPairs) do
  begin
    Result[Index].Name := PtrPairs[Index, 0];
    Result[Index].Replacement := PtrPairs[Index, 1];
  end;
end;

class function TWinApiDocs.PtrVariant(const AName: string): string;
var
  Variant: TPtrVariant;
  Base: string;
begin
  Base := AName;
  if (Length(Base) > 1) and CharInSet(Base[Length(Base)], ['A', 'W']) then
    Base := Copy(Base, 1, Length(Base) - 1);
  for Variant in PtrVariants do
    if SameText(Variant.Name, AName) or SameText(Variant.Name, Base) then
      Exit(Variant.Replacement);
  Result := '';
end;

class function TWinApiDocs.KnownUrls: TArray<string>;
var
  Candidate: TApiPage;
begin
  Result := nil;
  for Candidate in Pages do
    if Candidate.WideVariant then
      Result := Result + [PageUrl(Candidate, 'w')]
    else
      Result := Result + [PageUrl(Candidate, '')];
end;

class function TWinApiDocs.HoverText(const AName: string): string;
var
  Replacement: string;
begin
  Result := '[Microsoft-Dokumentation](' + Url(AName) + ')';
  Replacement := PtrVariant(AName);
  if Replacement <> '' then
    Result := Result + #10#10 + Format('Für 64 Bit `%s` verwenden; `%s` schneidet Zeiger und Handles ab.',
      [Replacement, AName]);
end;

end.
