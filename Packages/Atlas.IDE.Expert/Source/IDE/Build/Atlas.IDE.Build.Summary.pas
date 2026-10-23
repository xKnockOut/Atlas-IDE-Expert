unit Atlas.IDE.Build.Summary;

// Schranke für Hinweise und Warnungen in der IDE (#530); die Bewertung steht
// in Atlas.Core.Build.Verdict.
// - Zusammenfassung nach einem Build des Benutzers in der Atlas-Gruppe des
//   Meldungsfensters: „Build Kasse erfolgreich, aber 2 Warnungen, 1 Hinweis“
//   und darunter die maßgebliche Meldung als Zeile mit Datei und Position
//   (Doppelklick springt hin). Mit build.summary aus nur dann, wenn
//   build.zeroHints oder build.warningsAsErrors den Build scheitern lassen;
//   dann holt Atlas die Gruppe auch nach vorn, sonst bleibt der Reiter „Build“
//   der IDE vorn.
// - Merkt sich die Meldungen des letzten Builds je Projekt für den Befehl
//   „Aktuelle Compilermeldungen in die Basislinie“.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Verdict;

type
  TAtlasIdeBuildSummary = class
  public const
    MessageGroup = 'Atlas';
  private
    FLast: TDictionary<string, TArray<TAtlasCompilerMessage>>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Meldungen des letzten Builds von AProject merken.</summary>
    procedure Remember(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>);
    /// <summary>Warnungen und Hinweise des letzten Builds von AProject, die in die Basislinie können.</summary>
    function Baselinable(const AProject: string): TArray<TAtlasCompilerMessage>;
    /// <summary>Kopfzeile der Zusammenfassung.</summary>
    class function Headline(const AProject: string; const AVerdict: TAtlasBuildVerdict): string; static;
    /// <summary>Zusammenfassung in die Atlas-Gruppe; ASummary = build.summary.</summary>
    class procedure Report(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict; ASummary: Boolean); static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.UI.Strings;

{ TAtlasIdeBuildSummary }

constructor TAtlasIdeBuildSummary.Create;
begin
  inherited Create;
  FLast := TDictionary<string, TArray<TAtlasCompilerMessage>>.Create;
end;

destructor TAtlasIdeBuildSummary.Destroy;
begin
  FLast.Free;
  inherited;
end;

procedure TAtlasIdeBuildSummary.Remember(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>);
begin
  FLast.AddOrSetValue(AnsiLowerCase(AProject), AMessages);
end;

function TAtlasIdeBuildSummary.Baselinable(const AProject: string): TArray<TAtlasCompilerMessage>;
var
  Messages: TArray<TAtlasCompilerMessage>;
  Message: TAtlasCompilerMessage;
begin
  Result := nil;
  if not FLast.TryGetValue(AnsiLowerCase(AProject), Messages) then
    Exit;
  for Message in Messages do
    if TAtlasBuildVerdicts.Baselinable(Message) then
      Result := Result + [Message];
end;

class function TAtlasIdeBuildSummary.Headline(const AProject: string; const AVerdict: TAtlasBuildVerdict): string;
var
  Name, Counts: string;
begin
  Name := ChangeFileExt(ExtractFileName(AProject), '');
  Counts := TAtlasStrings.BuildCounts(AVerdict.Warnings, AVerdict.Hints);
  case AVerdict.Reason of
    TAtlasBuildVerdictReason.CompilerFailed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryFailed, [Name, AVerdict.Errors]);
    TAtlasBuildVerdictReason.WarningsAsErrors:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryRejectedCodes, [Name, Counts, AVerdict.PromotedCode]);
    TAtlasBuildVerdictReason.ZeroHints:
      Result := TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryRejected, [Name, Counts]);
  else
    if Counts = '' then
      Result := TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryClean, [Name])
    else
      Result := TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryCounts, [Name, Counts]);
  end;
  if AVerdict.Baselined > 0 then
    Result := Result + TAtlasStrings.Fmt(TAtlasTextId.BuildSummaryBaselined, [AVerdict.Baselined]);
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
    Exit;
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
    Group := Messages.AddMessageGroup(MessageGroup);
  Messages.AddTitleMessage(Headline(AProject.FileName, AVerdict), Group);
  if (AVerdict.First >= 0) and (AVerdict.First <= High(AMessages)) then
  begin
    Target := AMessages[AVerdict.First];
    Text := Target.Text;
    if Target.Code <> '' then
      Text := Target.Code + ' ' + Text;
    Messages.AddToolMessage(Target.FileName, Text, TAtlasCompilerMessages.SeverityText(Target.Severity),
      Target.Line, Target.Column, nil, LineRef, Group);
  end;
  // Nur ein Build, den Atlas anders bewertet als der Compiler, holt die Gruppe nach vorn.
  if Rejected then
    Messages.ShowMessageView(Group);
end;

end.
