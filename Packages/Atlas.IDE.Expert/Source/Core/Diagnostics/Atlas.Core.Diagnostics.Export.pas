unit Atlas.Core.Diagnostics.Export;

// Export des Diagnoselogs des Servers (#647): packt die Tagesdateien der letzten Tage in
// eine ZIP-Datei. Vorher zeigt das Plugin mit Preview den Inhalt, so wie er
// in der ZIP landet. Die Zuordnung Kurz-ID → Name (diag-map-*.txt) gehört nie
// dazu. Die Dateien sind beim Export oft noch offen (laufender Server), daher
// wird lesend ohne Sperre geöffnet. Mit Kopf (#495) steht vorn eine Datei
// atlas-info.txt mit Atlas-Version, IDE-Version und Plattform.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasDiagnosticExport = record
  public const
    DefaultDays = 7;
    PreviewLines = 400;
    InfoFileName = 'atlas-info.txt';
  public
    /// <summary>Ordner des Servers: %LOCALAPPDATA%\Atlas\Logs\Diagnose.</summary>
    class function DefaultFolder: string; static;
    /// <summary>Diagnoselogs in AFolder, die in den letzten ADays Tagen geschrieben wurden, sortiert.</summary>
    class function Files(const AFolder: string; ADays: Integer; ANow: TDateTime): TArray<string>; static;
    /// <summary>Inhalt wie in der ZIP: je Datei eine Kopfzeile, danach die Zeilen (höchstens AMaxLines insgesamt).</summary>
    class function Preview(const AFiles: TArray<string>; AMaxLines: Integer = PreviewLines): string; overload;
      static;
    /// <summary>Wie oben, davor AInfo als atlas-info.txt.</summary>
    class function Preview(const AFiles: TArray<string>; const AInfo: string): string; overload; static;
    /// <summary>Schreibt die Dateien ohne Ordner in die ZIP-Datei ATarget; eine vorhandene wird ersetzt.</summary>
    class procedure WriteZip(const AFiles: TArray<string>; const ATarget: string); overload; static;
    /// <summary>Wie oben, dazu AInfo als atlas-info.txt.</summary>
    class procedure WriteZip(const AFiles: TArray<string>; const ATarget, AInfo: string); overload; static;
    /// <summary>Inhalt von atlas-info.txt: Atlas-Version, IDE-Version, Plattform; keine Pfade.</summary>
    class function Info(const AAtlasVersion, AIdeVersion, APlatform: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.Zip,
  System.Generics.Collections;

const
  // Wie TDiagnosticLogFolder.FilePattern im Server; die Map-Dateien heißen diag-map-*.txt.
  LogPattern = 'diag-*.log';

function ReadShared(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result, Length(Result));
  finally
    Stream.Free;
  end;
end;

{ TAtlasDiagnosticExport }

class function TAtlasDiagnosticExport.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'Logs'),
    'Diagnose');
end;

class function TAtlasDiagnosticExport.Files(const AFolder: string; ADays: Integer; ANow: TDateTime): TArray<string>;
var
  FileName: string;
  Limit: TDateTime;
  List: TList<string>;
begin
  Result := nil;
  if (AFolder = '') or not TDirectory.Exists(AFolder) then
    Exit;
  if ADays <= 0 then
    ADays := DefaultDays;
  Limit := IncDay(ANow, -ADays);
  List := TList<string>.Create;
  try
    for FileName in TDirectory.GetFiles(AFolder, LogPattern) do
      if not ExtractFileName(FileName).StartsWith('diag-map-', True) and (TFile.GetLastWriteTime(FileName) >= Limit) then
        List.Add(FileName);
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TAtlasDiagnosticExport.Preview(const AFiles: TArray<string>; AMaxLines: Integer): string;
var
  Builder: TStringBuilder;
  FileName, Line: string;
  Bytes: TBytes;
  Shown, Total: Integer;
  Lines: TArray<string>;
begin
  Builder := TStringBuilder.Create;
  try
    Shown := 0;
    Total := 0;
    for FileName in AFiles do
    begin
      Bytes := ReadShared(FileName);
      Lines := TEncoding.UTF8.GetString(Bytes).Split([#13#10, #10], TStringSplitOptions.ExcludeEmpty);
      Inc(Total, Length(Lines));
      Builder.Append('== ').Append(ExtractFileName(FileName)).Append(' (').Append(Length(Lines))
        .Append(' Zeilen) ==').Append(sLineBreak);
      for Line in Lines do
      begin
        if Shown >= AMaxLines then
          Break;
        Builder.Append(Line).Append(sLineBreak);
        Inc(Shown);
      end;
    end;
    if Total > Shown then
      Builder.Append(Format('… %d weitere Zeilen', [Total - Shown])).Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasDiagnosticExport.Info(const AAtlasVersion, AIdeVersion, APlatform: string): string;
begin
  Result := 'Atlas ' + AAtlasVersion + sLineBreak + 'IDE ' + AIdeVersion + sLineBreak + 'Plattform ' + APlatform +
    sLineBreak;
end;

class function TAtlasDiagnosticExport.Preview(const AFiles: TArray<string>; const AInfo: string): string;
begin
  Result := '== ' + InfoFileName + ' ==' + sLineBreak + AInfo + Preview(AFiles);
end;

class procedure TAtlasDiagnosticExport.WriteZip(const AFiles: TArray<string>; const ATarget: string);
begin
  WriteZip(AFiles, ATarget, '');
end;

class procedure TAtlasDiagnosticExport.WriteZip(const AFiles: TArray<string>; const ATarget, AInfo: string);
var
  Zip: TZipFile;
  FileName: string;
  Content: TBytesStream;
begin
  if FileExists(ATarget) then
    System.SysUtils.DeleteFile(ATarget);
  Zip := TZipFile.Create;
  try
    Zip.Open(ATarget, TZipMode.zmWrite);
    if AInfo <> '' then
    begin
      Content := TBytesStream.Create(TEncoding.UTF8.GetBytes(AInfo));
      try
        Zip.Add(Content, InfoFileName);
      finally
        Content.Free;
      end;
    end;
    for FileName in AFiles do
    begin
      Content := TBytesStream.Create(ReadShared(FileName));
      try
        Zip.Add(Content, ExtractFileName(FileName));
      finally
        Content.Free;
      end;
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

end.
