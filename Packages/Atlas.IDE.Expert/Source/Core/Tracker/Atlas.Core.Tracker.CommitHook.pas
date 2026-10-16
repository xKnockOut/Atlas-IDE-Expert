unit Atlas.Core.Tracker.CommitHook;

// Commit-Präfix des aktiven Issues über den Git-Hook prepare-commit-msg
// (#765), ohne VCL und Open Tools API. Nur nach Zustimmung im Projekt:
// - Atlas legt den Hook <hooks>/prepare-commit-msg an, wenn dort keiner liegt
//   (ein fremder Hook wird nie überschrieben, Atlas fragt dann nicht wieder).
//   Den eigenen erkennt Atlas an der Marke in der zweiten Zeile.
// - Den Präfix schreibt Atlas in <gitdir>/atlas-commit-prefix (UTF-8 ohne
//   BOM, ohne Zeilenende); ohne aktives Issue fehlt die Datei, und der Hook
//   tut nichts. Bei Worktrees ist <gitdir> der eigene Ordner des Worktrees.
// - Der Hook lässt Merge-, Squash- und Amend-Nachrichten (Quelle "merge",
//   "squash", "commit") unverändert, ebenso Nachrichten, die schon mit dem
//   Präfix beginnen.
// Grenze: Beginnt der Präfix mit dem Kommentarzeichen von Git („#753 “) und
// wird die Nachricht im Editor geschrieben, entfernt Git die Zeile als
// Kommentar; mit „git commit -m“ und in der VCS der IDE bleibt sie. Für GitHub
// ist deshalb ein Muster wie "{kennung}: " oder "[{kennung}] " sicherer.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Was in hooks/prepare-commit-msg liegt.</summary>
  TAtlasCommitHookState = (Missing, Own, Foreign);
{$SCOPEDENUMS OFF}

  TAtlasCommitHook = class
  public const
    HookName = 'prepare-commit-msg';
    PrefixFile = 'atlas-commit-prefix';
    /// <summary>Zweite Zeile des eigenen Hooks.</summary>
    Marker = '# atlas-commit-prefix (#765)';
  public
    /// <summary>Inhalt des Hooks, Zeilenende LF (sh von Git für Windows).</summary>
    class function Script: string; static;
    /// <summary>Eigener Hook: die Marke steht in den ersten Zeilen.</summary>
    class function IsOwn(const AContent: string): Boolean; static;
    class function HookFile(const AHooksDir: string): string; static;
    class function PrefixFileOf(const AGitDir: string): string; static;
    /// <summary>Zustand des Hooks im Ordner AHooksDir.</summary>
    class function State(const AHooksDir: string): TAtlasCommitHookState; static;
    /// <summary>Eigenen Hook anlegen (Ordner falls nötig); ein fremder bleibt. True, wenn danach der eigene dort
    /// liegt.</summary>
    class function Install(const AHooksDir: string): Boolean; static;
    /// <summary>Eigenen Hook entfernen; einen fremden nie. True, wenn danach kein eigener mehr dort liegt.</summary>
    class function Uninstall(const AHooksDir: string): Boolean; static;
    /// <summary>Präfix für den Hook schreiben; leer = Datei entfernen. False bei Fehler.</summary>
    class function WritePrefix(const AGitDir, APrefix: string): Boolean; static;
    /// <summary>Gespeicherter Präfix; '' ohne.</summary>
    class function ReadPrefix(const AGitDir: string): string; static;
  end;

implementation

uses
  System.Classes;

const
  Lf = #10;

class function TAtlasCommitHook.Script: string;
begin
  Result :=
    '#!/bin/sh' + Lf +
    Marker + Lf +
    '# Von Atlas angelegt: setzt den Präfix des aktiven Issues an den Anfang der Commit-Nachricht.' + Lf +
    '# Ohne aktives Issue tut der Hook nichts. Entfernen: diese Datei löschen.' + Lf +
    'case "$2" in merge|squash|commit) exit 0 ;; esac' + Lf +
    'dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0' + Lf +
    'file="$dir/' + PrefixFile + '"' + Lf +
    '[ -f "$file" ] || exit 0' + Lf +
    'prefix=$(cat "$file")' + Lf +
    '[ -n "$prefix" ] || exit 0' + Lf +
    'bare=$(printf ''%s'' "$prefix" | sed ''s/[[:space:]]*$//'')' + Lf +
    'first=$(head -n 1 "$1")' + Lf +
    'case "$first" in "$bare"*) exit 0 ;; esac' + Lf +
    '{ printf ''%s'' "$prefix"; cat "$1"; } > "$1.atlas" && mv "$1.atlas" "$1"' + Lf +
    'exit 0' + Lf;
end;

class function TAtlasCommitHook.IsOwn(const AContent: string): Boolean;
begin
  Result := Pos(Marker, Copy(AContent, 1, 200)) > 0;
end;

class function TAtlasCommitHook.HookFile(const AHooksDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AHooksDir) + HookName;
end;

class function TAtlasCommitHook.PrefixFileOf(const AGitDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AGitDir) + PrefixFile;
end;

function ReadText(const AFileName: string; AMax: Integer; out AText: string): Boolean;
var
  Stream: TFileStream;
  Bytes: TBytes;
  Size: Int64;
begin
  AText := '';
  Result := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Size := Stream.Size;
      if Size > AMax then
        Size := AMax;
      SetLength(Bytes, Size);
      if Size > 0 then
        Stream.ReadBuffer(Bytes[0], Size);
    finally
      Stream.Free;
    end;
    AText := TEncoding.UTF8.GetString(Bytes);
    Result := True;
  except
    on EStreamError do
      Result := False;
    on EOSError do
      Result := False;
  end;
end;

function WriteText(const AFileName, AText: string): Boolean;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Result := False;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  try
    Stream := TFileStream.Create(AFileName, fmCreate);
    try
      if Length(Bytes) > 0 then
        Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
    Result := True;
  except
    on EStreamError do
      Result := False;
    on EOSError do
      Result := False;
  end;
end;

class function TAtlasCommitHook.State(const AHooksDir: string): TAtlasCommitHookState;
var
  Content: string;
begin
  if (AHooksDir = '') or not FileExists(HookFile(AHooksDir)) then
    Exit(TAtlasCommitHookState.Missing);
  if ReadText(HookFile(AHooksDir), 4096, Content) and IsOwn(Content) then
    Result := TAtlasCommitHookState.Own
  else
    Result := TAtlasCommitHookState.Foreign;
end;

class function TAtlasCommitHook.Install(const AHooksDir: string): Boolean;
begin
  Result := False;
  if AHooksDir = '' then
    Exit;
  case State(AHooksDir) of
    TAtlasCommitHookState.Own:
      // Neu schreiben: eine ältere Fassung des Skripts wird so ersetzt.
      Result := WriteText(HookFile(AHooksDir), Script);
    TAtlasCommitHookState.Missing:
      Result := ForceDirectories(AHooksDir) and WriteText(HookFile(AHooksDir), Script);
  end;
end;

class function TAtlasCommitHook.Uninstall(const AHooksDir: string): Boolean;
begin
  case State(AHooksDir) of
    TAtlasCommitHookState.Own:
      Result := DeleteFile(HookFile(AHooksDir));
  else
    Result := True;
  end;
end;

class function TAtlasCommitHook.WritePrefix(const AGitDir, APrefix: string): Boolean;
var
  FileName: string;
begin
  Result := False;
  if AGitDir = '' then
    Exit;
  FileName := PrefixFileOf(AGitDir);
  if APrefix = '' then
    Exit(not FileExists(FileName) or DeleteFile(FileName));
  Result := WriteText(FileName, APrefix);
end;

class function TAtlasCommitHook.ReadPrefix(const AGitDir: string): string;
begin
  Result := '';
  if (AGitDir = '') or not FileExists(PrefixFileOf(AGitDir)) then
    Exit;
  if not ReadText(PrefixFileOf(AGitDir), 1024, Result) then
    Result := '';
end;

end.
