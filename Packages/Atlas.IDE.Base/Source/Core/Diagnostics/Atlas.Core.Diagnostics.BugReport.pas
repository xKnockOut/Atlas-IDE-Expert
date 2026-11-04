unit Atlas.Core.Diagnostics.BugReport;

// Fehlerbericht des Plugins (#108): Teil des Plugins (Atlas-, IDE-Version,
// Plattform, Einstellungen, Auszug aus atlas.log, Ende von server-stderr.log,
// Bericht H5) und dahinter der Bericht des
// Servers (atlas.server.bugReport mit Version, wirksamer Konfiguration,
// Protokoll und den letzten Anfragen). Quelltext steht nie darin.
// Anonymisiert (Einstellung diagnostics.bugReport.anonymize, Vorgabe an)
// werden Pfade unter einem Projektordner zu <ws>\…, alle anderen absoluten
// Pfade zu <pfad>, Benutzer- und Rechnername zu <benutzer> und im Protokoll
// Text in Anführungszeichen zu <wert>. Die Regeln stehen einmal in
// Atlas.Text.Anonymize und gelten für Server und Plugin gleich (ADR 0012).

interface

uses
  System.SysUtils;

type
  TAtlasBugReportInput = record
    PluginVersion: string;
    IdeVersion: string;
    Platform: string;
    /// <summary>Einstellungen des Plugins als JSON.</summary>
    Settings: string;
    /// <summary>Wirksame experimentelle Schalter (#834), nur Schlüssel; leer = keine.</summary>
    Experimental: TArray<string>;
    PluginLog: TArray<string>;
    /// <summary>Letzte Zeilen aus server-stderr.log (Bericht H5); leer = Abschnitt entfällt.</summary>
    ServerErrorOutput: TArray<string>;
    /// <summary>Text des Servers; '' wenn er nicht läuft oder nicht antwortet.</summary>
    ServerReport: string;
    /// <summary>Warum der Teil des Servers fehlt; '' wenn er da ist.</summary>
    ServerMissing: string;
    /// <summary>Projektordner für die Kürzung auf &lt;ws&gt;.</summary>
    Roots: TArray<string>;
    Identity: TArray<string>;
    Anonymize: Boolean;
    Created: TDateTime;
  end;

  TAtlasBugReport = class
  public const
    ServerCommand = 'atlas.server.bugReport';
    IssuesUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new/choose';
    /// <summary>So viele Zeilen aus atlas.log.</summary>
    LogLines = 100;
    /// <summary>So viele Zeilen aus server-stderr.log.</summary>
    ErrorOutputLines = 50;
  private
    class procedure AppendPlugin(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput); static;
    class procedure AppendSettings(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput); static;
    /// <summary>Zeilen in einem Codeblock unter ATitle, anonymisiert wie das Protokoll.</summary>
    class procedure AppendLines(ABuilder: TStringBuilder; const ATitle: string; const ALines: TArray<string>;
      const AInput: TAtlasBugReportInput); static;
    class procedure AppendServer(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput); static;
  public
    /// <summary>Angaben für den Server: [{"anonymize": …, "client": "Atlas-Plugin …, IDE …, Win32"}].</summary>
    class function ServerArguments(const AInput: TAtlasBugReportInput): string; static;
    class function Build(const AInput: TAtlasBugReportInput): string; static;
    class function AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string; static;
    class function AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string; static;
    /// <summary>Die letzten ACount Zeilen einer Textdatei, die gerade beschrieben werden darf;
    /// leer ohne Datei.</summary>
    class function Tail(const AFileName: string; ACount: Integer): TArray<string>; static;
    /// <summary>Vorgeschlagener Dateiname, z. B. atlas-fehlerbericht-20261014-1530.md.</summary>
    class function DefaultFileName(ANow: TDateTime): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Classes,
  System.JSON,
  System.IOUtils,
  Atlas.Text.Anonymize;

{ TAtlasBugReport }

class function TAtlasBugReport.AnonymizePaths(const AText: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizePaths(AText, ARoots, AIdentity);
end;

class function TAtlasBugReport.AnonymizeLogLine(const ALine: string; const ARoots, AIdentity: TArray<string>): string;
begin
  Result := TTextAnonymizer.AnonymizeLogLine(ALine, ARoots, AIdentity);
end;

class function TAtlasBugReport.ServerArguments(const AInput: TAtlasBugReportInput): string;
var
  Options: TJSONObject;
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Options := TJSONObject.Create;
    Arguments.AddElement(Options);
    Options.AddPair('anonymize', TJSONBool.Create(AInput.Anonymize));
    Options.AddPair('client', Format('Atlas-Plugin %s, IDE %s, %s', [AInput.PluginVersion, AInput.IdeVersion,
      AInput.Platform]));
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

class procedure TAtlasBugReport.AppendPlugin(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput);
begin
  ABuilder.Append('## Plugin').Append(sLineBreak).Append(sLineBreak);
  ABuilder.Append('- Atlas: ').Append(AInput.PluginVersion).Append(sLineBreak);
  ABuilder.Append('- IDE: ').Append(AInput.IdeVersion).Append(sLineBreak);
  ABuilder.Append('- Plattform: ').Append(AInput.Platform).Append(sLineBreak);
  ABuilder.Append('- Experimentell: ');
  if Length(AInput.Experimental) = 0 then
  begin
    ABuilder.Append('keine');
  end
  else
  begin
    ABuilder.Append(string.Join(', ', AInput.Experimental));
  end;
  ABuilder.Append(sLineBreak).Append(sLineBreak);
end;

class procedure TAtlasBugReport.AppendSettings(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput);
var
  mText: string;
begin
  ABuilder.Append('### Einstellungen').Append(sLineBreak).Append(sLineBreak);
  mText := AInput.Settings;
  if AInput.Anonymize then
  begin
    mText := AnonymizePaths(mText, AInput.Roots, AInput.Identity);
  end;
  ABuilder.Append('```json').Append(sLineBreak).Append(mText.TrimRight).Append(sLineBreak).Append('```');
  ABuilder.Append(sLineBreak).Append(sLineBreak);
end;

class procedure TAtlasBugReport.AppendLines(ABuilder: TStringBuilder; const ATitle: string;
  const ALines: TArray<string>; const AInput: TAtlasBugReportInput);
var
  mLine, mText: string;
begin
  ABuilder.Append(ATitle);
  ABuilder.Append(sLineBreak).Append(sLineBreak).Append('```').Append(sLineBreak);
  for mLine in ALines do
  begin
    mText := mLine;
    if AInput.Anonymize then
    begin
      mText := AnonymizeLogLine(mText, AInput.Roots, AInput.Identity);
    end;
    ABuilder.Append(TTextAnonymizer.FenceSafe(mText)).Append(sLineBreak);
  end;
  ABuilder.Append('```').Append(sLineBreak).Append(sLineBreak);
end;

class procedure TAtlasBugReport.AppendServer(ABuilder: TStringBuilder; const AInput: TAtlasBugReportInput);
var
  mText: string;
begin
  if AInput.ServerReport = '' then
  begin
    ABuilder.Append('## Server').Append(sLineBreak).Append(sLineBreak).Append(AInput.ServerMissing)
      .Append(sLineBreak);
    Exit;
  end;
  // Überschriften des Servers eine Ebene tiefer, damit der Bericht eine Gliederung hat.
  mText := AInput.ServerReport;
  mText := StringReplace(mText, sLineBreak + '## ', sLineBreak + '### ', [rfReplaceAll]);
  if mText.StartsWith('# ') then
  begin
    mText := '#' + mText;
  end;
  ABuilder.Append(mText.TrimRight).Append(sLineBreak);
end;

class function TAtlasBugReport.Build(const AInput: TAtlasBugReportInput): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('# Atlas-Fehlerbericht').Append(sLineBreak).Append(sLineBreak);
    mBuilder.Append('Erstellt: ').Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', AInput.Created));
    if AInput.Anonymize then
    begin
      mBuilder.Append(' · anonymisiert');
    end;
    mBuilder.Append(sLineBreak).Append(sLineBreak);
    mBuilder.Append('Quelltext steht nicht in diesem Bericht. Issue anlegen: ').Append(IssuesUrl);
    mBuilder.Append(sLineBreak).Append(sLineBreak);
    AppendPlugin(mBuilder, AInput);
    AppendSettings(mBuilder, AInput);
    AppendLines(mBuilder, Format('### Protokoll des Plugins (letzte %d Zeilen)', [Length(AInput.PluginLog)]),
      AInput.PluginLog, AInput);
    // Was die Laufzeit des Servers vor einem Absturz noch ausgab (Bericht H5); anonymisiert wie das Protokoll.
    if Length(AInput.ServerErrorOutput) > 0 then
    begin
      AppendLines(mBuilder, Format('### Fehlerausgabe des Servers (stderr, letzte %d Zeilen)',
        [Length(AInput.ServerErrorOutput)]), AInput.ServerErrorOutput, AInput);
    end;
    AppendServer(mBuilder, AInput);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasBugReport.Tail(const AFileName: string; ACount: Integer): TArray<string>;
var
  Stream: TFileStream;
  Lines: TStringList;
  Index, First: Integer;
begin
  Result := nil;
  if not TFile.Exists(AFileName) then
  begin
    Exit;
  end;
  Lines := TStringList.Create;
  try
    // Das Protokoll kann gerade beschrieben werden: lesend ohne Sperre öffnen.
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Lines.LoadFromStream(Stream, TEncoding.UTF8);
    finally
      Stream.Free;
    end;
    First := Lines.Count - ACount;
    if First < 0 then
    begin
      First := 0;
    end;
    SetLength(Result, Lines.Count - First);
    for Index := First to Lines.Count - 1 do
    begin
      Result[Index - First] := Lines[Index];
    end;
  finally
    Lines.Free;
  end;
end;

class function TAtlasBugReport.DefaultFileName(ANow: TDateTime): string;
begin
  Result := 'atlas-fehlerbericht-' + FormatDateTime('yyyymmdd"-"hhnn', ANow) + '.md';
end;

end.
