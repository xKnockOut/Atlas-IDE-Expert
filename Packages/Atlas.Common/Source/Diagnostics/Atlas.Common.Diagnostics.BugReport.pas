unit Atlas.Common.Diagnostics.BugReport;

// Fehlerbericht des Servers (#108): Version, wirksame Konfiguration, Auszug
// aus dem Protokoll und die letzten Anfragen (Methode, Dauer, Ergebnis) als
// Markdown. Quelltext steht nie darin: Die Anfragen kommen aus dem Ringpuffer
// der Statistik, der keine Parameter kennt.
// Anonymisiert (Vorgabe) werden Pfade unter einem Arbeitsbereich zu
// <ws>/…, alle anderen absoluten Pfade und Datei-URIs zu <pfad>, Benutzer- und
// Rechnername zu <benutzer>; im Protokoll zusätzlich Text in Anführungszeichen
// (Bezeichner, Werte) zu <wert>. Die Regeln stehen in Atlas.Text.Anonymize
// und gelten gleich im Plugin (ADR 0012).

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Text.Anonymize;

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
    Command = 'atlas.server.bugReport';
    WorkspaceLabel = TTextAnonymizer.WorkspaceLabel;
    PathLabel = TTextAnonymizer.PathLabel;
    UserLabel = TTextAnonymizer.UserLabel;
    ValueLabel = TTextAnonymizer.ValueLabel;
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

{ TBugReport }

class function TBugReport.AnonymizePaths(const AText: string; const AWorkspaces, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizePaths(AText, AWorkspaces, AIdentity);
end;

class function TBugReport.AnonymizeLogLine(const ALine: string; const AWorkspaces, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizeLogLine(ALine, AWorkspaces, AIdentity);
end;

class function TBugReport.Build(const AInput: TBugReportInput): string;
var
  Builder: TStringBuilder;
  Request: TRecentRequest;
  Line, Text: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('# Atlas-Fehlerbericht (Server)').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Erstellt: ').Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', AInput.Created));
    if AInput.Anonymize then
      Builder.Append(' · anonymisiert');
    Builder.Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Quelltext steht nicht in diesem Bericht.').Append(sLineBreak).Append(sLineBreak);

    Builder.Append('## Version').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('- Server: ').Append(AInput.ServerVersion).Append(sLineBreak);
    if AInput.Client <> '' then
      Builder.Append('- Editor: ').Append(AInput.Client).Append(sLineBreak);
    Builder.Append(sLineBreak);

    Builder.Append('## Wirksame Konfiguration').Append(sLineBreak).Append(sLineBreak);
    Text := AInput.Configuration;
    if AInput.Anonymize then
      Text := AnonymizePaths(Text, AInput.Workspaces, AInput.Identity);
    Builder.Append('```json').Append(sLineBreak).Append(Text.TrimRight).Append(sLineBreak).Append('```');
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append(Format('## Letzte Anfragen (%d)', [Length(AInput.Requests)])).Append(sLineBreak);
    Builder.Append(sLineBreak);
    if Length(AInput.Requests) = 0 then
      Builder.Append('Keine.').Append(sLineBreak)
    else
    begin
      Builder.Append('| Zeit | Methode | Dauer ms | Ergebnis |').Append(sLineBreak);
      Builder.Append('|---|---|---:|---|').Append(sLineBreak);
      for Request in AInput.Requests do
      begin
        Builder.Append('| ').Append(FormatDateTime('hh":"nn":"ss"."zzz', Request.Finished));
        Builder.Append(' | ').Append(Request.Method);
        Builder.Append(' | ').Append(Request.ElapsedMs);
        if Request.Failed then
          Builder.Append(' | Fehler |')
        else
          Builder.Append(' | ok |');
        Builder.Append(sLineBreak);
      end;
    end;
    Builder.Append(sLineBreak);

    Builder.Append(Format('## Protokoll (letzte %d Zeilen)', [Length(AInput.LogLines)])).Append(sLineBreak);
    Builder.Append(sLineBreak).Append('```').Append(sLineBreak);
    for Line in AInput.LogLines do
    begin
      Text := Line;
      if AInput.Anonymize then
        Text := AnonymizeLogLine(Text, AInput.Workspaces, AInput.Identity);
      // Mehrzeilige Einträge (z. B. Status) bleiben lesbar; ``` würde den Block schließen.
      Builder.Append(TTextAnonymizer.FenceSafe(Text)).Append(sLineBreak);
    end;
    Builder.Append('```').Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
