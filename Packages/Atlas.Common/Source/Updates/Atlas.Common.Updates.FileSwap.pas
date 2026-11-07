unit Atlas.Common.Updates.FileSwap;

// Platform-Feature "Updates" (#1519), Root: Dateien des Atlas-Ordners
// tauschen und bei einem Fehler genau zurücknehmen.
// - Vor dem Überschreiben oder Löschen kommt die alte Datei in den
//   Sicherungsordner; der Rückfall kopiert sie zurück und löscht neu
//   hinzugekommene Dateien.
// - Eine laufende EXE (z. B. AtlasServer.exe für KI-Assistenten (MCP)) lässt sich nicht
//   überschreiben, aber umbenennen: Sie wird als <Name>.atlas-old
//   beiseitegelegt; aufgeräumt wird beim nächsten Update.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Updates.Contract;

type
  TUpdateFileStep = record
    /// <summary>Pfad relativ zum Atlas-Ordner.</summary>
    Path: string;
    /// <summary>Die Datei gab es vorher (Sicherung vorhanden).</summary>
    Existed: Boolean;
    Deleted: Boolean;
  end;

  TUpdateFileSwap = class
  private
    FFiles: IUpdateFiles;
    FTarget: string;
    FBackup: string;
    FSteps: TList<TUpdateFileStep>;
    function Backup(const APath: string): Boolean;
    procedure Replace(const ASource, ATarget: string);
  public
    constructor Create(const AFiles: IUpdateFiles; const ATarget, ABackup: string);
    destructor Destroy; override;
    /// <summary>ASource nach Atlas-Ordner\APath (mit Sicherung).</summary>
    procedure CopyIn(const ASource, APath: string);
    /// <summary>Atlas-Ordner\APath löschen (mit Sicherung); fehlt die Datei, geschieht nichts.</summary>
    procedure Remove(const APath: string);
    /// <summary>Alle Schritte rückwärts zurücknehmen; Fehler einzelner Dateien landen in ALog.</summary>
    procedure Rollback(const ALog: TUpdateLog);
    /// <summary>Beiseitegelegte EXE-Dateien (*.atlas-old) im Atlas-Ordner löschen, soweit nicht mehr gesperrt.
    /// </summary>
    class procedure CleanupOld(const AFiles: IUpdateFiles; const ATarget: string; const ALog: TUpdateLog); static;
    function Steps: TArray<TUpdateFileStep>;
  end;

implementation

uses
  Atlas.Text.UpdateRun,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TFileSwapText = (NotRestored, StillLocked);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TFileSwapText] of TAtlasText = (
    (De: 'Rückfall: %s nicht wiederhergestellt (%s)'; En: 'Rollback: %s not restored (%s)'),
    (De: '%s ist noch gesperrt und wird beim nächsten Update entfernt.';
    En: '%s is still locked and will be removed by the next update.'));

{ TUpdateFileSwap }

constructor TUpdateFileSwap.Create(const AFiles: IUpdateFiles; const ATarget, ABackup: string);
begin
  inherited Create;
  FFiles := AFiles;
  FTarget := ATarget;
  FBackup := ABackup;
  FSteps := TList<TUpdateFileStep>.Create;
end;

destructor TUpdateFileSwap.Destroy;
begin
  FSteps.Free;
  inherited Destroy;
end;

function TUpdateFileSwap.Steps: TArray<TUpdateFileStep>;
begin
  Result := FSteps.ToArray;
end;

function TUpdateFileSwap.Backup(const APath: string): Boolean;
begin
  Result := FFiles.FileExists(TUpdateLayout.Join(FTarget, APath));
  if Result then
  begin
    FFiles.CopyFile(TUpdateLayout.Join(FTarget, APath), TUpdateLayout.Join(FBackup, APath));
  end;
end;

procedure TUpdateFileSwap.Replace(const ASource, ATarget: string);
begin
  try
    FFiles.CopyFile(ASource, ATarget);
  except
    on EInOutError do
    begin
      // Gesperrt (laufende EXE): umbenennen geht, dann neu schreiben.
      FFiles.MoveFile(ATarget, ATarget + TUpdateLayout.cOldSuffix);
      FFiles.CopyFile(ASource, ATarget);
    end;
  end;
end;

procedure TUpdateFileSwap.CopyIn(const ASource, APath: string);
var
  mStep: TUpdateFileStep;
begin
  mStep := Default(TUpdateFileStep);
  mStep.Path := APath;
  mStep.Existed := Backup(APath);
  FSteps.Add(mStep);
  Replace(ASource, TUpdateLayout.Join(FTarget, APath));
end;

procedure TUpdateFileSwap.Remove(const APath: string);
var
  mStep: TUpdateFileStep;
begin
  if not FFiles.FileExists(TUpdateLayout.Join(FTarget, APath)) then
  begin
    Exit;
  end;
  mStep := Default(TUpdateFileStep);
  mStep.Path := APath;
  mStep.Existed := Backup(APath);
  mStep.Deleted := True;
  FSteps.Add(mStep);
  FFiles.DeleteFile(TUpdateLayout.Join(FTarget, APath));
end;

procedure TUpdateFileSwap.Rollback(const ALog: TUpdateLog);
var
  mIndex: Integer;
  mStep: TUpdateFileStep;
begin
  for mIndex := FSteps.Count - 1 downto 0 do
  begin
    mStep := FSteps[mIndex];
    try
      if mStep.Existed then
      begin
        Replace(TUpdateLayout.Join(FBackup, mStep.Path), TUpdateLayout.Join(FTarget, mStep.Path));
      end
      else
      begin
        FFiles.DeleteFile(TUpdateLayout.Join(FTarget, mStep.Path));
      end;
    except
      // lsp-ignore: catch-all-without-raise -- Wiederherstellen nach Kräften; ALog protokolliert
      on mError: Exception do
      begin
        ALog(cTexts[TFileSwapText.NotRestored].Fmt([mStep.Path, mError.Message]));
      end;
    end;
  end;
end;

class procedure TUpdateFileSwap.CleanupOld(const AFiles: IUpdateFiles; const ATarget: string;
  const ALog: TUpdateLog);
var
  mFile: string;
begin
  for mFile in AFiles.FilesIn(ATarget) do
  begin
    if mFile.EndsWith(TUpdateLayout.cOldSuffix, True) then
    begin
      try
        AFiles.DeleteFile(TUpdateLayout.Join(ATarget, mFile));
      except
        on EInOutError do
        begin
          ALog(cTexts[TFileSwapText.StillLocked].Fmt([mFile]));
        end;
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Updates.FileSwap', cTexts);

end.
