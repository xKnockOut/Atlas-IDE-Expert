unit Atlas.Common.Diagnostics.BugReport;

// Fehlerbericht des Servers (#108): Version, wirksame Konfiguration, Auszug
// aus dem Protokoll und die letzten Anfragen (Methode, Dauer, Ergebnis) als
// Markdown. Quelltext steht nie darin: Die Anfragen kommen aus dem Ringpuffer
// der Statistik, der keine Parameter kennt.
// Anonymisiert (Vorgabe) werden Pfade unter einem Arbeitsbereich zu
// <ws>/…, alle anderen absoluten Pfade und Datei-URIs zu <pfad>, Benutzer- und
// Rechnername zu <benutzer>; im Protokoll zusätzlich Text in Anführungszeichen
// (Bezeichner, Werte) zu <wert>. Die Regeln stehen in Atlas.Text.Anonymize
// und gelten gleich im Plugin. Seit #1478 bleiben in der
// Konfiguration nur Schlüssel, Zahlen, Wahrheitswerte und Schlüsselwörter
// (TTextAnonymizer.AnonymizeJsonValues); gekennzeichnete Werte im Protokoll
// werden ersetzt, ohne Anonymisierung nur von ihren Kennzeichen befreit. Ohne
// Anonymisierung vermerkt der Kopf „mit Klarnamen“.

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Statistics;

type
  TBugReportInput = record
    ServerVersion: string;
    /// <summary>Angaben des Editors, z. B. „Atlas-Plugin 0.1.0, IDE 37.0, Win32“; '' ohne.</summary>
    Client: string;
    /// <summary>Wirksame Konfiguration als formatiertes JSON.</summary>
    Configuration: string;
    LogLines: TArray<string>;
    Requests: TArray<TRecentRequest>;
    /// <summary>Wurzelordner der Arbeitsbereiche, für die Kürzung auf &lt;ws&gt;.</summary>
    Workspaces: TArray<string>;
    /// <summary>Benutzer- und Rechnername; Einträge unter drei Zeichen zählen nicht.</summary>
    Identity: TArray<string>;
    Anonymize: Boolean;
    Created: TDateTime;
  end;

  TBugReport = class
  public const
    /// <summary>Befehl des Servers; Argument optional {"anonymize": true, "client": "…", "target": "…"}.</summary>
    cCommand = 'atlas.server.bugReport';
  public
    class function Build(const AInput: TBugReportInput): string; static;
    /// <summary>Pfade unter AWorkspaces zu &lt;ws&gt;, übrige absolute Pfade zu &lt;pfad&gt;,
    /// AIdentity zu &lt;benutzer&gt;.</summary>
    class function AnonymizePaths(const AText: string; const AWorkspaces, AIdentity: TArray<string>): string; static;
    /// <summary>Wie AnonymizePaths, dazu Text in Anführungszeichen zu &lt;wert&gt;.</summary>
    class function AnonymizeLogLine(const ALine: string; const AWorkspaces, AIdentity: TArray<string>): string;
      static;
  end;

implementation

uses
  Atlas.Text.Anonymize,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBugReportText = (WithRealNamesExplicitlyChosen, SourceCodeIsNotPart, Error, TimeMethodDurationMsResult,
    LogLastLines, AtlasBugReportServer, Created, Anonymized, EffectiveConfiguration, RecentRequests);

const
  cTexts: array[TBugReportText] of TAtlasText = (
    (De: ' · mit Klarnamen (ausdrücklich gewählt)'; En: ' · with real names (explicitly chosen)'),
    (De: 'Quelltext steht nicht in diesem Bericht.'; En: 'Source code is not part of this report.'),
    (De: ' | Fehler |'; En: ' | Error |'),
    (De: '| Zeit | Methode | Dauer ms | Ergebnis |'; En: '| Time | Method | Duration ms | Result |'),
    (De: '## Protokoll (letzte %d Zeilen)'; En: '## Log (last %d lines)'),
    (De: '# Atlas-Fehlerbericht (Server)'; En: '# Atlas bug report (server)'),
    (De: 'Erstellt: '; En: 'Created: '),
    (De: ' · anonymisiert'; En: ' · anonymized'),
    (De: '## Wirksame Konfiguration'; En: '## Effective configuration'),
    (De: '## Letzte Anfragen (%d)'; En: '## Recent requests (%d)'));

{$SCOPEDENUMS OFF}

{ TBugReport }

class function TBugReport.AnonymizePaths(const AText: string; const AWorkspaces, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizePaths(AText, AWorkspaces, AIdentity);
end;

class function TBugReport.AnonymizeLogLine(const ALine: string; const AWorkspaces, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizeLogLine(ALine, AWorkspaces, AIdentity);
end;

/// <summary>Kopf, Version und wirksame Konfiguration.</summary>
procedure AppendHeader(ABuilder: TStringBuilder; const AInput: TBugReportInput);
var
  mText: string;
begin
  ABuilder.Append(cTexts[TBugReportText.AtlasBugReportServer].Text).Append(sLineBreak).Append(sLineBreak);
  ABuilder.Append(cTexts[TBugReportText.Created].Text).Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss',
    AInput.Created));
  if AInput.Anonymize then
  begin
    ABuilder.Append(cTexts[TBugReportText.Anonymized].Text);
  end
  else
  begin
    ABuilder.Append(cTexts[TBugReportText.WithRealNamesExplicitlyChosen].Text);
  end;
  ABuilder.Append(sLineBreak).Append(sLineBreak);
  ABuilder.Append(cTexts[TBugReportText.SourceCodeIsNotPart].Text).Append(sLineBreak).Append(sLineBreak);

  ABuilder.Append('## Version').Append(sLineBreak).Append(sLineBreak);
  ABuilder.Append('- Server: ').Append(AInput.ServerVersion).Append(sLineBreak);
  if AInput.Client <> '' then
  begin
    ABuilder.Append('- Editor: ').Append(AInput.Client).Append(sLineBreak);
  end;
  ABuilder.Append(sLineBreak);

  ABuilder.Append(cTexts[TBugReportText.EffectiveConfiguration].Text).Append(sLineBreak).Append(sLineBreak);
  mText := AInput.Configuration;
  if AInput.Anonymize then
  begin
    mText := TTextAnonymizer.AnonymizePaths(TTextAnonymizer.AnonymizeJsonValues(mText), AInput.Workspaces,
      AInput.Identity);
  end;
  ABuilder.Append('```json').Append(sLineBreak).Append(mText.TrimRight).Append(sLineBreak).Append('```');
  ABuilder.Append(sLineBreak).Append(sLineBreak);
end;

/// <summary>Tabelle der letzten Anfragen.</summary>
procedure AppendRequests(ABuilder: TStringBuilder; const AInput: TBugReportInput);
var
  mRequest: TRecentRequest;
begin
  ABuilder.Append(cTexts[TBugReportText.RecentRequests].Fmt([Length(AInput.Requests)])).Append(sLineBreak);
  ABuilder.Append(sLineBreak);
  if Length(AInput.Requests) = 0 then
  begin
    ABuilder.Append('Keine.').Append(sLineBreak);
  end
  else
  begin
    ABuilder.Append(cTexts[TBugReportText.TimeMethodDurationMsResult].Text).Append(sLineBreak);
    ABuilder.Append('|---|---|---:|---|').Append(sLineBreak);
    for mRequest in AInput.Requests do
    begin
      ABuilder.Append('| ').Append(FormatDateTime('hh":"nn":"ss"."zzz', mRequest.Finished));
      ABuilder.Append(' | ').Append(mRequest.Method);
      ABuilder.Append(' | ').Append(mRequest.ElapsedMs);
      if mRequest.Failed then
      begin
        ABuilder.Append(cTexts[TBugReportText.Error].Text);
      end
      else
      begin
        ABuilder.Append(' | ok |');
      end;
      ABuilder.Append(sLineBreak);
    end;
  end;
  ABuilder.Append(sLineBreak);
end;

/// <summary>Letzte Zeilen des Protokolls als Codeblock.</summary>
procedure AppendLog(ABuilder: TStringBuilder; const AInput: TBugReportInput);
var
  mLine, mText: string;
begin
  ABuilder.Append(cTexts[TBugReportText.LogLastLines].Fmt([Length(AInput.LogLines)])).Append(sLineBreak);
  ABuilder.Append(sLineBreak).Append('```').Append(sLineBreak);
  for mLine in AInput.LogLines do
  begin
    if AInput.Anonymize then
    begin
      mText := TTextAnonymizer.AnonymizeLogLine(mLine, AInput.Workspaces, AInput.Identity);
    end
    else
    begin
      mText := TLogMarks.Plain(mLine);
    end;
    // Mehrzeilige Einträge (z. B. Status) bleiben lesbar; ``` würde den Block schließen.
    ABuilder.Append(TTextAnonymizer.FenceSafe(mText)).Append(sLineBreak);
  end;
  ABuilder.Append('```').Append(sLineBreak);
end;

class function TBugReport.Build(const AInput: TBugReportInput): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    AppendHeader(mBuilder, AInput);
    AppendRequests(mBuilder, AInput);
    AppendLog(mBuilder, AInput);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Diagnostics.BugReport', cTexts);

end.
