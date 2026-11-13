unit Shell.Platform;

// Plattformadapter des Servers an einer Stelle (#1109): Unter Windows die
// Units aus Atlas.Windows, unter Linux (Free Pascal, Tools/Linux) die aus
// Atlas.Linux. Die übrigen Shell-Units binden nur diese Unit ein und kennen
// keine Plattform. Typen mit gleicher Form heißen auf beiden Plattformen
// gleich; was es nur unter einer Plattform gibt, kapselt TShellPlatform.

interface

uses
  System.SysUtils,
  Atlas.Common.Editing.Colors,
  Atlas.Common.Logging.Contract,
  Atlas.Core.VersionControl.Contract,
{$IFDEF MSWINDOWS}
  Atlas.Windows.Console.StdStreams,
  Atlas.Windows.Process.ParentWatcher,
  Atlas.Windows.Process.Instances,
  Atlas.Windows.Documents.FileWatcher,
  Atlas.Windows.Compiler.Adapters.ProcessRunner,
  Atlas.Windows.Projects.DelphiInstallation,
  Atlas.Windows.Diagnostics.DebugOutput,
  Atlas.Windows.Diagnostics.StackTrace,
  Atlas.Windows.Diagnostics.ProcessInfo;
{$ELSE}
  Atlas.Linux.Console.StdStreams,
  Atlas.Linux.Process.ParentWatcher,
  Atlas.Linux.Process.Instances,
  Atlas.Linux.Documents.FileWatcher,
  Atlas.Linux.Compiler.Adapters.ProcessRunner,
  Atlas.Linux.Projects.DelphiInstallation,
  Atlas.Linux.Diagnostics.DebugOutput,
  Atlas.Linux.Diagnostics.StackTrace,
  Atlas.Linux.Diagnostics.ProcessInfo;
{$ENDIF}

type
{$IFDEF MSWINDOWS}
  TStdStreams = Atlas.Windows.Console.StdStreams.TStdStreams;
  TParentWatcher = Atlas.Windows.Process.ParentWatcher.TParentWatcher;
  TProcessInstances = Atlas.Windows.Process.Instances.TProcessInstances;
  TFileWatcherChanged = Atlas.Windows.Documents.FileWatcher.TFileWatcherChanged;
  TFileWatcher = Atlas.Windows.Documents.FileWatcher.TFileWatcher;
  TProcessRunner = Atlas.Windows.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = Atlas.Windows.Projects.DelphiInstallation.TDelphiInstallation;
  TDebugOutput = Atlas.Windows.Diagnostics.DebugOutput.TDebugOutput;
  TStackTrace = Atlas.Windows.Diagnostics.StackTrace.TStackTrace;
  TProcessInfo = Atlas.Windows.Diagnostics.ProcessInfo.TProcessInfo;
{$ELSE}
  TStdStreams = Atlas.Linux.Console.StdStreams.TStdStreams;
  TParentWatcher = Atlas.Linux.Process.ParentWatcher.TParentWatcher;
  TProcessInstances = Atlas.Linux.Process.Instances.TProcessInstances;
  TFileWatcherChanged = Atlas.Linux.Documents.FileWatcher.TFileWatcherChanged;
  TFileWatcher = Atlas.Linux.Documents.FileWatcher.TFileWatcher;
  TProcessRunner = Atlas.Linux.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = Atlas.Linux.Projects.DelphiInstallation.TDelphiInstallation;
  TDebugOutput = Atlas.Linux.Diagnostics.DebugOutput.TDebugOutput;
  TStackTrace = Atlas.Linux.Diagnostics.StackTrace.TStackTrace;
  TProcessInfo = Atlas.Linux.Diagnostics.ProcessInfo.TProcessInfo;
{$ENDIF}

  TShellPlatform = record
  public
    /// <summary>Pfad in der Schreibweise des Dateisystems (Windows: echte Groß- und Kleinschreibung, langer
    /// Name; Linux: ohne symbolische Verweise); unverändert, wenn es ihn nicht gibt.</summary>
    class function CanonicalizePath(const APath: string): string; static;
    /// <summary>Nummer des eigenen Prozesses.</summary>
    class function CurrentProcessId: Cardinal; static;
    /// <summary>Schutz, den nur eine Plattform braucht: unter Windows die Schutzseite nach einem
    /// Stapelüberlauf (#1094) und Lesen mit FILE_SHARE_DELETE. Linux ersetzt geöffnete Dateien
    /// ohnehin und meldet einen Stapelüberlauf als Signal; dort tut Install nichts.</summary>
    class procedure InstallGuards; static;
    /// <summary>Senke für Debug-Ausgaben an den Debugger (Windows: OutputDebugString); nil unter Linux, wo
    /// stderr schon das Protokoll des Servers trägt.</summary>
    class function DebugLogSink: ILogSink; static;
    /// <summary>Aufrufkette der Exception AError bis zum raise.</summary>
    class function StackTraceOf(AError: Exception): string; static;
    /// <summary>Benennt ASource in ATarget um und ersetzt ein vorhandenes ATarget in einem Schritt.</summary>
    class function MoveReplacing(const ASource, ATarget: string): Boolean; static;
    /// <summary>Prozessläufer für git und svn.</summary>
    class function CreateVcsRunner(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>): IAtlasVcsRunner;
      static;
    /// <summary>Warteschritt für das Warten auf eine Datei in AFolder (Antwort des Plugins, P-101): Unter Windows
    /// kehrt er zurück, sobald sich dort Dateinamen ändern, spätestens nach ASafetyMs; lässt sich der Ordner nicht
    /// beobachten, und unter Linux, schläft er APollMs.</summary>
    class function FolderWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc; static;
  end;

/// <summary>Systemfarbe AIndex (GetSysColor) für Farbangaben im Quelltext; unter Linux keine.</summary>
function PlatformSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Atlas.Windows.Documents.PathCanonicalizer,
  Atlas.Windows.Documents.SharedRead,
  Atlas.Windows.Diagnostics.StackGuard,
  Atlas.Windows.Diagnostics.Adapters.DebugOutputSink,
  Atlas.Windows.Editing.SystemColors,
  Atlas.Core.VersionControl.Adapters.ProcessRunner;
{$ELSE}
  BaseUnix,
  Atlas.Linux.Documents.PathCanonicalizer,
  Shell.Platform.VersionControlRunner;
{$ENDIF}

function PlatformSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := WindowsSystemColor(AIndex, AColor);
{$ELSE}
  AColor := Default(TRgbColor);
  Result := False;
{$ENDIF}
end;

{$IFDEF MSWINDOWS}
type
  /// <summary>Änderungssignal eines Ordners (FindFirstChangeNotification) für FolderWait.</summary>
  TFolderChangeWait = class(TInterfacedObject)
  private
    FHandle: THandle;
  public
    constructor Create(const AFolder: string);
    destructor Destroy; override;
    /// <summary>Wartet auf eine Änderung, höchstens AMs; False, wenn der Ordner nicht beobachtet wird.</summary>
    function Wait(AMs: Cardinal): Boolean;
  end;

constructor TFolderChangeWait.Create(const AFolder: string);
begin
  inherited Create;
  FHandle := INVALID_HANDLE_VALUE;
  if ForceDirectories(AFolder) then
  begin
    FHandle := FindFirstChangeNotification(PChar(AFolder), False, FILE_NOTIFY_CHANGE_FILE_NAME);
  end;
end;

destructor TFolderChangeWait.Destroy;
begin
  if FHandle <> INVALID_HANDLE_VALUE then
  begin
    FindCloseChangeNotification(FHandle);
  end;
  inherited Destroy;
end;

function TFolderChangeWait.Wait(AMs: Cardinal): Boolean;
begin
  if FHandle = INVALID_HANDLE_VALUE then
  begin
    Exit(False);
  end;
  if (WaitForSingleObject(FHandle, AMs) = WAIT_OBJECT_0) and not FindNextChangeNotification(FHandle) then
  begin
    // Nicht wieder scharf zu machen (Ordner gelöscht): ab jetzt im Takt.
    FindCloseChangeNotification(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
  Result := True;
end;

function FolderChangeWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc;
var
  mWait: TFolderChangeWait;
  mKeep: IInterface;
begin
  mWait := TFolderChangeWait.Create(AFolder);
  mKeep := mWait;
  Result :=
    procedure
    begin
      // mKeep hält das Signal, solange der Warteschritt lebt.
      if (mKeep = nil) or not mWait.Wait(ASafetyMs) then
      begin
        Sleep(APollMs);
      end;
    end;
end;
{$ENDIF}

{ TShellPlatform }

class function TShellPlatform.CanonicalizePath(const APath: string): string;
begin
{$IFDEF MSWINDOWS}
  Result := TWindowsPathCanonicalizer.Canonicalize(APath);
{$ELSE}
  Result := TLinuxPathCanonicalizer.Canonicalize(APath);
{$ENDIF}
end;

class function TShellPlatform.CurrentProcessId: Cardinal;
begin
  Result := TParentWatcher.CurrentProcessId;
end;

class procedure TShellPlatform.InstallGuards;
begin
{$IFDEF MSWINDOWS}
  // Ohne neue Schutzseite beendet Windows den Prozess beim nächsten Überlauf (#1094).
  TWindowsStackGuard.Install;
  // Lesen teilt auch Löschen, damit Plugin und zweiter Server Dateien atomar ersetzen können.
  TWindowsSharedRead.Install;
{$ENDIF}
end;

class function TShellPlatform.DebugLogSink: ILogSink;
begin
{$IFDEF MSWINDOWS}
  Result := TDebugOutputLogSink.Create;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

class function TShellPlatform.StackTraceOf(AError: Exception): string;
begin
{$IFDEF MSWINDOWS}
  Result := AError.StackTrace;
{$ELSE}
  Result := TStackTrace.OfException(AError);
{$ENDIF}
end;

class function TShellPlatform.MoveReplacing(const ASource, ATarget: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := MoveFileEx(PChar(ASource), PChar(ATarget), MOVEFILE_REPLACE_EXISTING);
{$ELSE}
  // rename(2) ersetzt ein vorhandenes Ziel atomar.
  Result := FpRename(UTF8String(ASource), UTF8String(ATarget)) = 0;
{$ENDIF}
end;

class function TShellPlatform.CreateVcsRunner(AAllowMainThread: Boolean;
  const ACancelled: TFunc<Boolean>): IAtlasVcsRunner;
begin
{$IFDEF MSWINDOWS}
  Result := TAtlasVcsProcessRunner.Create(AAllowMainThread, ACancelled);
{$ELSE}
  Result := TLinuxVcsRunner.Create(AAllowMainThread, ACancelled);
{$ENDIF}
end;

class function TShellPlatform.FolderWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc;
begin
{$IFDEF MSWINDOWS}
  Result := FolderChangeWait(AFolder, APollMs, ASafetyMs);
{$ELSE}
  // Unter Linux läuft keine IDE mit Plugin; das Warten endet dort ohnehin nach der ersten Frist.
  Result :=
    procedure
    begin
      Sleep(APollMs);
    end;
{$ENDIF}
end;

end.
