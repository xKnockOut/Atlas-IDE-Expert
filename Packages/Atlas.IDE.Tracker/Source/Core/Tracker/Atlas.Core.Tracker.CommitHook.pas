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
    cHookName = 'prepare-commit-msg';
    cPrefixFile = 'atlas-commit-prefix';
    /// <summary>Zweite Zeile des eigenen Hooks.</summary>
    cMarker = '# atlas-commit-prefix (#765)';
  public
    /// <summary>Inhalt des Hooks, Zeilenende LF (sh von Git für Windows); die Kommentarzeilen in der Sprache der
    /// Oberfläche (AEnglish, #1458).</summary>
    class function Script(AEnglish: Boolean): string; static;
    /// <summary>Eigener Hook: die Marke steht in den ersten Zeilen.</summary>
    class function IsOwn(const AContent: string): Boolean; static;
    class function HookFile(const AHooksDir: string): string; static;
    class function PrefixFileOf(const AGitDir: string): string; static;
    /// <summary>Zustand des Hooks im Ordner AHooksDir.</summary>
    class function State(const AHooksDir: string): TAtlasCommitHookState; static;
    /// <summary>Eigenen Hook anlegen (Ordner falls nötig); ein fremder bleibt. True, wenn danach der eigene dort
    /// liegt.</summary>
    class function Install(const AHooksDir: string; AEnglish: Boolean): Boolean; static;
    /// <summary>Eigenen Hook entfernen; einen fremden nie. True, wenn danach kein eigener mehr dort liegt.</summary>
    class function Uninstall(const AHooksDir: string): Boolean; static;
    /// <summary>Präfix für den Hook schreiben; leer = Datei entfernen. False bei Fehler.</summary>
    class function WritePrefix(const AGitDir, APrefix: string): Boolean; static;
    /// <summary>Gespeicherter Präfix; '' ohne.</summary>
    class function ReadPrefix(const AGitDir: string): string; static;
  end;

implementation

uses
  Atlas.Core.Tracker.Files;

const
  cLf = #10;
  /// <summary>So viel liest State vom Hook; die Marke steht in den ersten Zeilen.</summary>
  cMaxHookBytes = 4096;
  cMaxPrefixBytes = 1024;
  /// <summary>Kommentar des Hooks je Sprache (False deutsch, True englisch).</summary>
  cHookComment: array[Boolean, 0..1] of string = (
    ('# Von Atlas angelegt: setzt den Präfix des aktiven Issues an den Anfang der Commit-Nachricht.', // german-ok
     '# Ohne aktives Issue tut der Hook nichts. Entfernen: diese Datei löschen.'), // german-ok
    ('# Created by Atlas: puts the prefix of the active issue at the start of the commit message.',
     '# Without an active issue the hook does nothing. To remove it, delete this file.'));

class function TAtlasCommitHook.Script(AEnglish: Boolean): string;
begin
  Result :=
    '#!/bin/sh' + cLf +
    cMarker + cLf +
    cHookComment[AEnglish, 0] + cLf +
    cHookComment[AEnglish, 1] + cLf +
    'case "$2" in merge|squash|commit) exit 0 ;; esac' + cLf +
    'dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0' + cLf +
    'file="$dir/' + cPrefixFile + '"' + cLf +
    '[ -f "$file" ] || exit 0' + cLf +
    'prefix=$(cat "$file")' + cLf +
    '[ -n "$prefix" ] || exit 0' + cLf +
    'bare=$(printf ''%s'' "$prefix" | sed ''s/[[:space:]]*$//'')' + cLf +
    'first=$(head -n 1 "$1")' + cLf +
    'case "$first" in "$bare"*) exit 0 ;; esac' + cLf +
    '{ printf ''%s'' "$prefix"; cat "$1"; } > "$1.atlas" && mv "$1.atlas" "$1"' + cLf +
    'exit 0' + cLf;
end;

class function TAtlasCommitHook.IsOwn(const AContent: string): Boolean;
begin
  Result := Pos(cMarker, Copy(AContent, 1, 200)) > 0;
end;

class function TAtlasCommitHook.HookFile(const AHooksDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AHooksDir) + cHookName;
end;

class function TAtlasCommitHook.PrefixFileOf(const AGitDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AGitDir) + cPrefixFile;
end;

/// <summary>Höchstens AMax Bytes vom Anfang als UTF-8.</summary>
function ReadText(const AFileName: string; AMax: Integer; out AText: string): Boolean;
var
  mBytes: TBytes;
begin
  AText := '';
  Result := TAtlasTrackerFiles.Files.ReadHead(AFileName, AMax, mBytes);
  if Result then
  begin
    AText := TEncoding.UTF8.GetString(mBytes);
  end;
end;

/// <summary>UTF-8 ohne BOM: sh und cat von Git lesen die Bytes unverändert.</summary>
function WriteText(const AFileName, AText: string): Boolean;
begin
  Result := TAtlasTrackerFiles.Files.WriteBytes(AFileName, TEncoding.UTF8.GetBytes(AText));
end;

class function TAtlasCommitHook.State(const AHooksDir: string): TAtlasCommitHookState;
var
  mContent: string;
begin
  if (AHooksDir = '') or not TAtlasTrackerFiles.Files.FileExists(HookFile(AHooksDir)) then
  begin
    Exit(TAtlasCommitHookState.Missing);
  end;
  if ReadText(HookFile(AHooksDir), cMaxHookBytes, mContent) and IsOwn(mContent) then
  begin
    Result := TAtlasCommitHookState.Own;
  end
  else
  begin
    Result := TAtlasCommitHookState.Foreign;
  end;
end;

class function TAtlasCommitHook.Install(const AHooksDir: string; AEnglish: Boolean): Boolean;
begin
  Result := False;
  if AHooksDir = '' then
  begin
    Exit;
  end;
  case State(AHooksDir) of
    TAtlasCommitHookState.Own:
      // Neu schreiben: eine ältere Fassung des Skripts wird so ersetzt.
      Result := WriteText(HookFile(AHooksDir), Script(AEnglish));
    TAtlasCommitHookState.Missing:
      Result := TAtlasTrackerFiles.Files.ForceFolder(AHooksDir) and WriteText(HookFile(AHooksDir), Script(AEnglish));
  end;
end;

class function TAtlasCommitHook.Uninstall(const AHooksDir: string): Boolean;
begin
  case State(AHooksDir) of
    TAtlasCommitHookState.Own:
      Result := TAtlasTrackerFiles.Files.DeleteFile(HookFile(AHooksDir));
  else
    Result := True;
  end;
end;

class function TAtlasCommitHook.WritePrefix(const AGitDir, APrefix: string): Boolean;
var
  mFileName: string;
begin
  Result := False;
  if AGitDir = '' then
  begin
    Exit;
  end;
  mFileName := PrefixFileOf(AGitDir);
  if APrefix = '' then
  begin
    Exit(TAtlasTrackerFiles.Files.DeleteFile(mFileName));
  end;
  Result := WriteText(mFileName, APrefix);
end;

class function TAtlasCommitHook.ReadPrefix(const AGitDir: string): string;
begin
  Result := '';
  if (AGitDir = '') or not TAtlasTrackerFiles.Files.FileExists(PrefixFileOf(AGitDir)) then
  begin
    Exit;
  end;
  if not ReadText(PrefixFileOf(AGitDir), cMaxPrefixBytes, Result) then
  begin
    Result := '';
  end;
end;

end.
