unit Atlas.UI.Updates.Texts;

// Texte der Update-Installation (#1519): Fehlercodes von AtlasUpdate.exe,
// Stand der Vorbereitung für die Zeile „Version“ (#754), Gründe, warum das
// Plugin nicht selbst installiert, und das Ergebnis nach dem Neustart.

interface

uses
  Atlas.Text.UpdateRun,
  Atlas.Core.Updates.Install;

type
  TAtlasUpdateTexts = class
  public
    /// <summary>Text zu einem Fehlercode aus state.json bzw. result.json; ADetail in Klammern dahinter.</summary>
    class function ErrorText(const ACode, ADetail: string): string; static;
    /// <summary>Kurzer Stand für die Zeile „Version“; '' ohne Vorbereitung.</summary>
    class function StageText(const AStage: TUpdateStage): string; static;
    class function BlockText(ABlock: TAtlasUpdateBlock): string; static;
    /// <summary>Meldung nach dem Einspielen (eine oder mehrere Zeilen).</summary>
    class function OutcomeText(const AOutcome: TUpdateOutcome): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.UI.Updates.Strings;

const
  cCodes: array[0..17] of string = (TUpdateErrors.Manifest, TUpdateErrors.VersionChanged, TUpdateErrors.NoPackage,
    TUpdateErrors.NoCompiler, TUpdateErrors.Download, TUpdateErrors.Hash, TUpdateErrors.Archive,
    TUpdateErrors.Unsigned, TUpdateErrors.Signature, TUpdateErrors.Build, TUpdateErrors.Locked,
    TUpdateErrors.CopyFailed, TUpdateErrors.Registry, TUpdateErrors.Cancelled, TUpdateErrors.Elevation,
    TUpdateErrors.Selection, TUpdateErrors.Unexpected, TAtlasUpdateInstall.StartFailed);
  cCodeTexts: array[0..17] of TAtlasUpdatesTextId = (
    TAtlasUpdatesTextId.UpdatesErrorManifest, TAtlasUpdatesTextId.UpdatesErrorVersion,
    TAtlasUpdatesTextId.UpdatesErrorNoPackage, TAtlasUpdatesTextId.UpdatesErrorNoCompiler,
    TAtlasUpdatesTextId.UpdatesErrorDownload, TAtlasUpdatesTextId.UpdatesErrorHash,
    TAtlasUpdatesTextId.UpdatesErrorArchive, TAtlasUpdatesTextId.UpdatesErrorUnsigned,
    TAtlasUpdatesTextId.UpdatesErrorSignature, TAtlasUpdatesTextId.UpdatesErrorBuild,
    TAtlasUpdatesTextId.UpdatesErrorLocked, TAtlasUpdatesTextId.UpdatesErrorCopy,
    TAtlasUpdatesTextId.UpdatesErrorRegistry, TAtlasUpdatesTextId.UpdatesErrorCancelled,
    TAtlasUpdatesTextId.UpdatesErrorElevation, TAtlasUpdatesTextId.UpdatesErrorSelection,
    TAtlasUpdatesTextId.UpdatesErrorUnexpected, TAtlasUpdatesTextId.UpdatesErrorStart);

{ TAtlasUpdateTexts }

class function TAtlasUpdateTexts.ErrorText(const ACode, ADetail: string): string;
var
  mIndex: Integer;
begin
  mIndex := IndexText(ACode, cCodes);
  if mIndex < 0 then
  begin
    mIndex := High(cCodes) - 1;
  end;
  Result := TAtlasUpdatesStrings.Text(cCodeTexts[mIndex]);
  if ADetail <> '' then
  begin
    Result := Result + ' (' + ADetail + ')';
  end;
end;

class function TAtlasUpdateTexts.StageText(const AStage: TUpdateStage): string;
begin
  Result := '';
  case AStage.Phase of
    TUpdatePhase.Downloading, TUpdatePhase.Verifying:
      Result := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesStagePreparing, [AStage.Progress]);
    TUpdatePhase.Building:
      Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesStageBuilding);
    TUpdatePhase.Ready:
      if AStage.AskSelection then
      begin
        Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesStageChoose);
      end
      else
      begin
        Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesStageReady);
      end;
    TUpdatePhase.Failed:
      Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesStageFailed);
  end;
end;

class function TAtlasUpdateTexts.BlockText(ABlock: TAtlasUpdateBlock): string;
begin
  case ABlock of
    TAtlasUpdateBlock.GetIt:
      Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesBlockedGetIt);
    TAtlasUpdateBlock.NoUpdater:
      Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesBlockedNoUpdater);
    TAtlasUpdateBlock.NoReleaseFolder:
      Result := TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.UpdatesBlockedFolder);
  else
    Result := '';
  end;
end;

function NamesLine(AId: TAtlasUpdatesTextId; const ANames: TArray<string>): string;
begin
  Result := '';
  if Length(ANames) > 0 then
  begin
    Result := sLineBreak + TAtlasUpdatesStrings.Fmt(AId, [string.Join(', ', ANames)]);
  end;
end;

class function TAtlasUpdateTexts.OutcomeText(const AOutcome: TUpdateOutcome): string;
begin
  case AOutcome.Kind of
    TUpdateOutcomeKind.Installed:
      Result := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOutcomeInstalled, [AOutcome.Version,
        AOutcome.Previous]) +
        NamesLine(TAtlasUpdatesTextId.UpdatesOutcomeAdded, AOutcome.Added) +
        NamesLine(TAtlasUpdatesTextId.UpdatesOutcomeRemoved, AOutcome.Removed);
    TUpdateOutcomeKind.RolledBack:
      Result := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOutcomeRolledBack, [AOutcome.Version,
        ErrorText(AOutcome.Reason, AOutcome.Detail), AOutcome.LogFile]);
    TUpdateOutcomeKind.Cancelled:
      Result := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOutcomeCancelled, [AOutcome.Version]);
  else
    Result := TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesOutcomeFailed, [AOutcome.Version,
      ErrorText(AOutcome.Reason, AOutcome.Detail), AOutcome.LogFile]);
  end;
end;

end.
