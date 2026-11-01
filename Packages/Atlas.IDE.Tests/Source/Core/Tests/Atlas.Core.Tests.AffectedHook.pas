unit Atlas.Core.Tests.AffectedHook;

// Betroffene Tests vor dem Commit anbieten (#1353, tests.affectedBeforeCommit)
// über den Git-Hook pre-commit, ohne VCL und Open Tools API:
// - Atlas legt <hooks>/pre-commit an, wenn dort keiner liegt (ein fremder Hook
//   wird nie überschrieben), und entfernt nur den eigenen. Den eigenen erkennt
//   Atlas an der Marke in der zweiten Zeile.
// - Was der Hook braucht, steht in <gitdir>/atlas-affected-tests (UTF-8 ohne
//   BOM, LF): Zeile 1 AtlasServer.exe, Zeile 2 Testprojekt für --check,
//   Zeile 3 Test-EXE; Pfade mit „/“ für das sh von Git für Windows.
// - Der Hook fragt AtlasServer --affected-tests HEAD --include-uncommitted
//   --format dunitx. Die Zusammenfassung schreibt der Server auf stderr, sie
//   steht also im Terminal bzw. im Protokoll des VCS-Werkzeugs. Mit Terminal
//   (/dev/tty) fragt der Hook, ob die Tests laufen sollen, und nach
//   Fehlschlägen, ob trotzdem committet wird. Ohne Terminal (Commit aus der
//   IDE) bleibt es bei der Liste; der Commit läuft weiter.
// - Fehlt die Datei, der Server oder die Test-EXE, tut der Hook nichts. SVN hat
//   keine Hooks auf dem Client; dort gibt es das Angebot nicht.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Was in hooks/pre-commit liegt.</summary>
  TAtlasAffectedHookState = (Missing, Own, Foreign);
{$SCOPEDENUMS OFF}

  /// <summary>Inhalt von &lt;gitdir&gt;/atlas-affected-tests.</summary>
  TAtlasAffectedHookConfig = record
    ServerPath: string;
    /// <summary>.dproj bzw. .groupproj für --check.</summary>
    Project: string;
    Executable: string;
  end;

  TAtlasAffectedHook = class
  public const
    HookName = 'pre-commit';
    ConfigFile = 'atlas-affected-tests';
    /// <summary>Zweite Zeile des eigenen Hooks.</summary>
    Marker = '# atlas-affected-tests (#1353)';
  public
    /// <summary>Inhalt des Hooks, Zeilenende LF.</summary>
    class function Script: string; static;
    /// <summary>Eigener Hook: die Marke steht in den ersten Zeilen.</summary>
    class function IsOwn(const AContent: string): Boolean; static;
    class function HookFile(const AHooksDir: string): string; static;
    class function ConfigFileOf(const AGitDir: string): string; static;
    /// <summary>Pfad für sh: „\“ wird „/“.</summary>
    class function ShellPath(const AFileName: string): string; static;
    /// <summary>Text der Datei atlas-affected-tests.</summary>
    class function ConfigText(const AConfig: TAtlasAffectedHookConfig): string; static;
    /// <summary>Zustand des Hooks im Ordner AHooksDir.</summary>
    class function State(const AHooksDir: string): TAtlasAffectedHookState; static;
    /// <summary>Eigenen Hook anlegen bzw. erneuern und die Angaben schreiben; ein fremder Hook bleibt. True, wenn
    /// danach der eigene Hook mit diesen Angaben dort liegt.</summary>
    class function Install(const AHooksDir, AGitDir: string; const AConfig: TAtlasAffectedHookConfig): Boolean;
      static;
    /// <summary>Eigenen Hook und die Angaben entfernen; einen fremden Hook nie. True, wenn danach kein eigener mehr
    /// dort liegt.</summary>
    class function Uninstall(const AHooksDir, AGitDir: string): Boolean; static;
  end;

implementation

uses
  System.Classes;

const
  cLf = #10;

class function TAtlasAffectedHook.Script: string;
begin
  Result :=
    '#!/bin/sh' + cLf +
    Marker + cLf +
    '# Von Atlas angelegt (tests.affectedBeforeCommit): nennt vor dem Commit die betroffenen Tests und' + cLf +
    '# führt sie im Terminal auf Wunsch aus. Entfernen: Einstellung ausschalten oder diese Datei löschen.' + cLf +
    'dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0' + cLf +
    'conf="$dir/' + ConfigFile + '"' + cLf +
    '[ -f "$conf" ] || exit 0' + cLf +
    'server=$(sed -n 1p "$conf")' + cLf +
    'project=$(sed -n 2p "$conf")' + cLf +
    'exe=$(sed -n 3p "$conf")' + cLf +
    '[ -n "$server" ] && [ -f "$server" ] || exit 0' + cLf +
    '[ -n "$project" ] && [ -f "$project" ] || exit 0' + cLf +
    'run=$("$server" --check "$project" --affected-tests HEAD --include-uncommitted --format dunitx)' + cLf +
    'code=$?' + cLf +
    '# 0 = Liste (leer: keine betroffenen Tests), 2 = alle Tests nötig, sonst (3 = aus, Fehler) nichts tun.' + cLf +
    'case $code in' + cLf +
    '  0) [ -n "$run" ] || exit 0 ;;' + cLf +
    '  2) run= ;;' + cLf +
    '  *) exit 0 ;;' + cLf +
    'esac' + cLf +
    '[ -n "$exe" ] && [ -f "$exe" ] || exit 0' + cLf +
    '# Ohne Terminal (Commit aus der IDE) bleibt es bei der Liste.' + cLf +
    '( : < /dev/tty ) 2>/dev/null || exit 0' + cLf +
    'printf ''Atlas: Betroffene Tests jetzt ausführen (Test-EXE ohne neuen Build)? [j/N] '' > /dev/tty' + cLf +
    'read answer < /dev/tty' + cLf +
    'case "$answer" in j|J|y|Y) ;; *) exit 0 ;; esac' + cLf +
    '"$exe" $run --exitbehavior:Continue < /dev/null && exit 0' + cLf +
    'printf ''Atlas: Tests fehlgeschlagen. Trotzdem committen? [j/N] '' > /dev/tty' + cLf +
    'read answer < /dev/tty' + cLf +
    'case "$answer" in j|J|y|Y) exit 0 ;; esac' + cLf +
    'exit 1' + cLf;
end;

class function TAtlasAffectedHook.IsOwn(const AContent: string): Boolean;
begin
  Result := Pos(Marker, Copy(AContent, 1, 200)) > 0;
end;

class function TAtlasAffectedHook.HookFile(const AHooksDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AHooksDir) + HookName;
end;

class function TAtlasAffectedHook.ConfigFileOf(const AGitDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AGitDir) + ConfigFile;
end;

class function TAtlasAffectedHook.ShellPath(const AFileName: string): string;
begin
  Result := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
end;

class function TAtlasAffectedHook.ConfigText(const AConfig: TAtlasAffectedHookConfig): string;
begin
  Result := ShellPath(AConfig.ServerPath) + cLf + ShellPath(AConfig.Project) + cLf +
    ShellPath(AConfig.Executable) + cLf;
end;

function ReadHead(const AFileName: string; out AText: string): Boolean;
const
  cMaxBytes = 4096;
var
  mStream: TFileStream;
  mBytes: TBytes;
  mSize: Int64;
begin
  AText := '';
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      mSize := mStream.Size;
      if mSize > cMaxBytes then
        mSize := cMaxBytes;
      SetLength(mBytes, mSize);
      if mSize > 0 then
        mStream.ReadBuffer(mBytes[0], mSize);
    finally
      mStream.Free;
    end;
    AText := TEncoding.UTF8.GetString(mBytes);
    Result := True;
  except
    on EStreamError do
      Result := False;
    on EOSError do
      Result := False;
  end;
end;

// Ohne BOM: Eine BOM vor „#!“ macht das Skript für sh unbrauchbar.
function WriteText(const AFileName, AText: string): Boolean;
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText);
  try
    mStream := TFileStream.Create(AFileName, fmCreate);
    try
      if Length(mBytes) > 0 then
        mStream.WriteBuffer(mBytes[0], Length(mBytes));
    finally
      mStream.Free;
    end;
    Result := True;
  except
    on EStreamError do
      Result := False;
    on EOSError do
      Result := False;
  end;
end;

class function TAtlasAffectedHook.State(const AHooksDir: string): TAtlasAffectedHookState;
var
  mContent: string;
begin
  if (AHooksDir = '') or not FileExists(HookFile(AHooksDir)) then
    Exit(TAtlasAffectedHookState.Missing);
  if ReadHead(HookFile(AHooksDir), mContent) and IsOwn(mContent) then
    Result := TAtlasAffectedHookState.Own
  else
    Result := TAtlasAffectedHookState.Foreign;
end;

class function TAtlasAffectedHook.Install(const AHooksDir, AGitDir: string;
  const AConfig: TAtlasAffectedHookConfig): Boolean;
begin
  Result := False;
  if (AHooksDir = '') or (AGitDir = '') then
    Exit;
  case State(AHooksDir) of
    TAtlasAffectedHookState.Own:
      // Neu schreiben: eine ältere Fassung des Skripts wird so ersetzt.
      Result := WriteText(HookFile(AHooksDir), Script);
    TAtlasAffectedHookState.Missing:
      Result := ForceDirectories(AHooksDir) and WriteText(HookFile(AHooksDir), Script);
  end;
  if Result then
    Result := WriteText(ConfigFileOf(AGitDir), ConfigText(AConfig));
end;

class function TAtlasAffectedHook.Uninstall(const AHooksDir, AGitDir: string): Boolean;
begin
  if State(AHooksDir) = TAtlasAffectedHookState.Own then
    Result := DeleteFile(HookFile(AHooksDir))
  else
    Result := True;
  if (AGitDir <> '') and FileExists(ConfigFileOf(AGitDir)) then
    DeleteFile(ConfigFileOf(AGitDir));
end;

end.
