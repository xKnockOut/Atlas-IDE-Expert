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
    cDefaultDays = 7;
    cPreviewLines = 400;
    cInfoFileName = 'atlas-info.txt';
  public
    /// <summary>Ordner des Servers: %LOCALAPPDATA%\Atlas\Logs\Diagnose.</summary>
    class function DefaultFolder: string; static;
    /// <summary>Diagnoselogs in AFolder, die in den letzten ADays Tagen geschrieben wurden, sortiert.</summary>
    class function Files(const AFolder: string; ADays: Integer; ANow: TDateTime): TArray<string>; static;
    /// <summary>Inhalt wie in der ZIP: je Datei eine Kopfzeile, danach die Zeilen (höchstens AMaxLines
    /// insgesamt).</summary>
    class function Preview(const AFiles: TArray<string>; AMaxLines: Integer): string; overload;
      static;
    /// <summary>Wie oben mit AMaxLines = PreviewLines.</summary>
    class function Preview(const AFiles: TArray<string>): string; overload; static;
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
  // Wie TDiagnosticLogFolder.cFilePattern im Server; die Map-Dateien heißen diag-map-*.txt.
  cLogPattern = 'diag-*.log';

function ReadShared(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, mStream.Size);
    if Length(Result) > 0 then
    begin
      mStream.ReadBuffer(Result, Length(Result));
    end;
  finally
    mStream.Free;
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
  mFileName: string;
  mLimit: TDateTime;
  mList: TList<string>;
begin
  Result := nil;
  if (AFolder = '') or not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  if ADays <= 0 then
  begin
    ADays := cDefaultDays;
  end;
  mLimit := IncDay(ANow, -ADays);
  mList := TList<string>.Create;
  try
    for mFileName in TDirectory.GetFiles(AFolder, cLogPattern) do
    begin
      if not ExtractFileName(mFileName).StartsWith('diag-map-', True) and (TFile.GetLastWriteTime(mFileName) >= mLimit) then
      begin
        mList.Add(mFileName);
      end;
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasDiagnosticExport.Preview(const AFiles: TArray<string>): string;
begin
  Result := Preview(AFiles, cPreviewLines);
end;

class function TAtlasDiagnosticExport.Preview(const AFiles: TArray<string>; AMaxLines: Integer): string;
var
  mBuilder: TStringBuilder;
  mFileName, mLine: string;
  mBytes: TBytes;
  mShown, mTotal: Integer;
  mLines: TArray<string>;
begin
  mBuilder := TStringBuilder.Create;
  try
    mShown := 0;
    mTotal := 0;
    for mFileName in AFiles do
    begin
      mBytes := ReadShared(mFileName);
      mLines := TEncoding.UTF8.GetString(mBytes).Split([#13#10, #10], TStringSplitOptions.ExcludeEmpty);
      Inc(mTotal, Length(mLines));
      mBuilder.Append('== ').Append(ExtractFileName(mFileName)).Append(' (').Append(Length(mLines))
        .Append(' Zeilen) ==').Append(sLineBreak);
      for mLine in mLines do
      begin
        if mShown >= AMaxLines then
        begin
          Break;
        end;
        mBuilder.Append(mLine).Append(sLineBreak);
        Inc(mShown);
      end;
    end;
    if mTotal > mShown then
    begin
      mBuilder.Append(Format('… %d weitere Zeilen', [mTotal - mShown])).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDiagnosticExport.Info(const AAtlasVersion, AIdeVersion, APlatform: string): string;
begin
  Result := 'Atlas ' + AAtlasVersion + sLineBreak + 'IDE ' + AIdeVersion + sLineBreak + 'Plattform ' + APlatform +
    sLineBreak;
end;

class function TAtlasDiagnosticExport.Preview(const AFiles: TArray<string>; const AInfo: string): string;
begin
  Result := '== ' + cInfoFileName + ' ==' + sLineBreak + AInfo + Preview(AFiles);
end;

class procedure TAtlasDiagnosticExport.WriteZip(const AFiles: TArray<string>; const ATarget: string);
begin
  WriteZip(AFiles, ATarget, '');
end;

class procedure TAtlasDiagnosticExport.WriteZip(const AFiles: TArray<string>; const ATarget, AInfo: string);
var
  mZip: TZipFile;
  mFileName: string;
  mContent: TBytesStream;
begin
  if FileExists(ATarget) then
  begin
    System.SysUtils.DeleteFile(ATarget);
  end;
  mZip := TZipFile.Create;
  try
    mZip.Open(ATarget, TZipMode.zmWrite);
    if AInfo <> '' then
    begin
      mContent := TBytesStream.Create(TEncoding.UTF8.GetBytes(AInfo));
      try
        mZip.Add(mContent, cInfoFileName);
      finally
        mContent.Free;
      end;
    end;
    for mFileName in AFiles do
    begin
      mContent := TBytesStream.Create(ReadShared(mFileName));
      try
        mZip.Add(mContent, ExtractFileName(mFileName));
      finally
        mContent.Free;
      end;
    end;
    mZip.Close;
  finally
    mZip.Free;
  end;
end;

end.
