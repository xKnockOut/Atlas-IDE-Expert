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
    MessageGroup = 'Atlas';
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
  Name, Counts: string;
begin
  Name := ChangeFileExt(ExtractFileName(AProject), '');
  Counts := TAtlasStrings.BuildCounts(AVerdict.Warnings, AVerdict.Hints);
  case AVerdict.Reason of
    TAtlasBuildVerdictReason.CompilerFailed:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryFailed, [Name, AVerdict.Errors]);
    TAtlasBuildVerdictReason.WarningsAsErrors:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryRejectedCodes,
        [Name, Counts, AVerdict.PromotedCode]);
    TAtlasBuildVerdictReason.ZeroHints:
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryRejected, [Name, Counts]);
  else
    if Counts = '' then
    begin
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryClean, [Name]);
    end
    else
    begin
      Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.BuildSummaryCounts, [Name, Counts]);
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
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  LineRef: Pointer;
  Target: TAtlasCompilerMessage;
  Rejected: Boolean;
  Text: string;
begin
  Rejected := (AVerdict.Reason = TAtlasBuildVerdictReason.WarningsAsErrors) or
    (AVerdict.Reason = TAtlasBuildVerdictReason.ZeroHints);
  if not (ASummary or Rejected) then
  begin
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup(MessageGroup);
  end;
  Messages.AddTitleMessage(Headline(AProject.FileName, AVerdict), Group);
  if (AVerdict.First >= 0) and (AVerdict.First <= High(AMessages)) then
  begin
    Target := AMessages[AVerdict.First];
    Text := Target.Text;
    if Target.Code <> '' then
    begin
      Text := Target.Code + ' ' + Text;
    end;
    Messages.AddToolMessage(Target.FileName, Text, TAtlasCompilerMessages.SeverityText(Target.Severity),
      Target.Line, Target.Column, nil, LineRef, Group);
  end;
  // Nur ein Build, den Atlas anders bewertet als der Compiler, holt die Gruppe nach vorn.
  if Rejected then
  begin
    Messages.ShowMessageView(Group);
  end;
end;

end.
