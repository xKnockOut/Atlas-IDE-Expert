unit Atlas.IDE.BuildPipeline.Summary;

// Schranke für Hinweise und Warnungen in der IDE (#530); die Bewertung steht
// in Atlas.Core.Build.Verdict.
// - Zusammenfassung nach einem Build des Benutzers in der Atlas-Gruppe des
//   Meldungsfensters: „Build Kasse erfolgreich, aber 2 Warnungen, 1 Hinweis“
//   und darunter die maßgebliche Meldung als Zeile mit Datei und Position
//   (Doppelklick springt hin). Mit build.summary aus nur dann, wenn
//   build.zeroHints oder build.warningsAsErrors den Build scheitern lassen;
//   dann holt Atlas die Gruppe auch nach vorn, sonst bleibt der Reiter „Build“
//   der IDE vorn.
// Die Meldungen des letzten Builds je Projekt merkt sich Base
// (Atlas.IDE.Build.LastMessages, #1455).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Verdict;

type
  TAtlasIdeBuildSummary = class
  public const
    cMessageGroup = 'Atlas';
  public
    /// <summary>Kopfzeile der Zusammenfassung.</summary>
    class function Headline(const AProject: string; const AVerdict: TAtlasBuildVerdict): string; static;
    /// <summary>Zusammenfassung in die Atlas-Gruppe; ASummary = build.summary.</summary>
    class procedure Report(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict; ASummary: Boolean); static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.UI.BuildPipeline.Strings;

class function TAtlasIdeBuildSummary.Headline(const AProject: string; const AVerdict: TAtlasBuildVerdict): string;
var
  mName, mCounts: string;
begin
  mName := ChangeFileExt(ExtractFileName(AProject), '');
  mCounts := TAtlasStrings.BuildCounts(AVerdict.Warnings, AVerdict.Hints);
  case AVerdict.Reason of
    TAtlasBuildVerdictReason.CompilerFailed:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryFailed, [mName, AVerdict.Errors]);
    TAtlasBuildVerdictReason.WarningsAsErrors:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryRejectedCodes,
        [mName, mCounts, AVerdict.PromotedCode]);
    TAtlasBuildVerdictReason.ZeroHints:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryRejected, [mName, mCounts]);
  else
    if mCounts = '' then
    begin
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryClean, [mName]);
    end
    else
    begin
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryCounts, [mName, mCounts]);
    end;
  end;
  if AVerdict.Baselined > 0 then
  begin
    Result := Result + TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryBaselined,
      [AVerdict.Baselined]);
  end;
end;

class procedure TAtlasIdeBuildSummary.Report(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict; ASummary: Boolean);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
  mLineRef: Pointer;
  mTarget: TAtlasCompilerMessage;
  mRejected: Boolean;
  mText: string;
begin
  mRejected := (AVerdict.Reason = TAtlasBuildVerdictReason.WarningsAsErrors) or
    (AVerdict.Reason = TAtlasBuildVerdictReason.ZeroHints);
  if not (ASummary or mRejected) then
  begin
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  mGroup := mMessages.GetGroup(cMessageGroup);
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup(cMessageGroup);
  end;
  mMessages.AddTitleMessage(Headline(AProject.FileName, AVerdict), mGroup);
  if (AVerdict.First >= 0) and (AVerdict.First <= High(AMessages)) then
  begin
    mTarget := AMessages[AVerdict.First];
    mText := mTarget.Text;
    if mTarget.Code <> '' then
    begin
      mText := mTarget.Code + ' ' + mText;
    end;
    mMessages.AddToolMessage(mTarget.FileName, mText, TAtlasCompilerMessages.SeverityText(mTarget.Severity),
      mTarget.Line, mTarget.Column, nil, mLineRef, mGroup);
  end;
  // Nur ein Build, den Atlas anders bewertet als der Compiler, holt die Gruppe nach vorn.
  if mRejected then
  begin
    mMessages.ShowMessageView(mGroup);
  end;
end;

end.
