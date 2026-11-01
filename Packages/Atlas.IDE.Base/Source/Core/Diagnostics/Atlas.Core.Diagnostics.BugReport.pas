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

class function TAtlasBugReport.Build(const AInput: TAtlasBugReportInput): string;
var
  Builder: TStringBuilder;
  Line, Text: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('# Atlas-Fehlerbericht').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Erstellt: ').Append(FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', AInput.Created));
    if AInput.Anonymize then
      Builder.Append(' · anonymisiert');
    Builder.Append(sLineBreak).Append(sLineBreak);
    Builder.Append('Quelltext steht nicht in diesem Bericht. Issue anlegen: ').Append(IssuesUrl);
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append('## Plugin').Append(sLineBreak).Append(sLineBreak);
    Builder.Append('- Atlas: ').Append(AInput.PluginVersion).Append(sLineBreak);
    Builder.Append('- IDE: ').Append(AInput.IdeVersion).Append(sLineBreak);
    Builder.Append('- Plattform: ').Append(AInput.Platform).Append(sLineBreak);
    Builder.Append('- Experimentell: ');
    if Length(AInput.Experimental) = 0 then
      Builder.Append('keine')
    else
      Builder.Append(string.Join(', ', AInput.Experimental));
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append('### Einstellungen').Append(sLineBreak).Append(sLineBreak);
    Text := AInput.Settings;
    if AInput.Anonymize then
      Text := AnonymizePaths(Text, AInput.Roots, AInput.Identity);
    Builder.Append('```json').Append(sLineBreak).Append(Text.TrimRight).Append(sLineBreak).Append('```');
    Builder.Append(sLineBreak).Append(sLineBreak);

    Builder.Append(Format('### Protokoll des Plugins (letzte %d Zeilen)', [Length(AInput.PluginLog)]));
    Builder.Append(sLineBreak).Append(sLineBreak).Append('```').Append(sLineBreak);
    for Line in AInput.PluginLog do
    begin
      Text := Line;
      if AInput.Anonymize then
        Text := AnonymizeLogLine(Text, AInput.Roots, AInput.Identity);
      Builder.Append(TTextAnonymizer.FenceSafe(Text)).Append(sLineBreak);
    end;
    Builder.Append('```').Append(sLineBreak).Append(sLineBreak);

    // Was die Laufzeit des Servers vor einem Absturz noch ausgab (Bericht H5); anonymisiert wie das Protokoll.
    if Length(AInput.ServerErrorOutput) > 0 then
    begin
      Builder.Append(Format('### Fehlerausgabe des Servers (stderr, letzte %d Zeilen)',
        [Length(AInput.ServerErrorOutput)]));
      Builder.Append(sLineBreak).Append(sLineBreak).Append('```').Append(sLineBreak);
      for Line in AInput.ServerErrorOutput do
      begin
        Text := Line;
        if AInput.Anonymize then
          Text := AnonymizeLogLine(Text, AInput.Roots, AInput.Identity);
        Builder.Append(TTextAnonymizer.FenceSafe(Text)).Append(sLineBreak);
      end;
      Builder.Append('```').Append(sLineBreak).Append(sLineBreak);
    end;

    if AInput.ServerReport <> '' then
    begin
      // Überschriften des Servers eine Ebene tiefer, damit der Bericht eine Gliederung hat.
      Text := AInput.ServerReport;
      Text := StringReplace(Text, sLineBreak + '## ', sLineBreak + '### ', [rfReplaceAll]);
      if Text.StartsWith('# ') then
        Text := '#' + Text;
      Builder.Append(Text.TrimRight).Append(sLineBreak);
    end
    else
      Builder.Append('## Server').Append(sLineBreak).Append(sLineBreak).Append(AInput.ServerMissing)
        .Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
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
    Exit;
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
      First := 0;
    SetLength(Result, Lines.Count - First);
    for Index := First to Lines.Count - 1 do
      Result[Index - First] := Lines[Index];
  finally
    Lines.Free;
  end;
end;

class function TAtlasBugReport.DefaultFileName(ANow: TDateTime): string;
begin
  Result := 'atlas-fehlerbericht-' + FormatDateTime('yyyymmdd"-"hhnn', ANow) + '.md';
end;

end.
