unit Shell.Workspace.Encodings;

// Internals-Rolle Shell: Hinweis auf gemischte Kodierungen der Projektdateien (#121), ins Protokoll und einmal je
// Sitzung als Meldung im Editor.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract;

type
  TShellEncodingReport = class
  private
    FName: string;
    FRoot: string;
    FLogger: ILogger;
    FTransport: IJsonRpcTransport;
    FIndex: ISymbolIndex;
    /// <summary>Hinweis schon im Editor gezeigt; einmal je Sitzung.</summary>
    FShown: Boolean;
    function Survey(const AFiles: TArray<string>): TEncodingSurvey;
    procedure Show(const AText: string);
  public
    constructor Create(const AName, ARoot: string; const ALogger: ILogger; const ATransport: IJsonRpcTransport;
      const AIndex: ISymbolIndex);
    /// <summary>Erhebt die Kodierungen von AFiles, ihren Formularen und Include-Dateien; binäre Formulare zählt
    /// die Erhebung nicht. Im Index-Thread.</summary>
    procedure Report(const AFiles: TArray<string>);
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Messages;

type
  /// <summary>Jede Datei einmal in die Erhebung.</summary>
  TSurveyFiles = class
  private
    FSeen: TDictionary<string, Boolean>;
    FSurvey: TEncodingSurvey;
  public
    constructor Create(AAnsiCodePage: Integer);
    destructor Destroy; override;
    procedure Add(const AFileName: string);
    property Survey: TEncodingSurvey read FSurvey;
  end;

constructor TSurveyFiles.Create(AAnsiCodePage: Integer);
begin
  inherited Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FSurvey := Default(TEncodingSurvey);
  FSurvey.AnsiCodePage := AAnsiCodePage;
end;

destructor TSurveyFiles.Destroy;
begin
  FSeen.Free;
  inherited;
end;

procedure TSurveyFiles.Add(const AFileName: string);
begin
  if FSeen.ContainsKey(AnsiUpperCase(AFileName)) or not FileExists(AFileName) then
  begin
    Exit;
  end;
  FSeen.Add(AnsiUpperCase(AFileName), True);
  // Über TFileEncoding: teilt Löschen, damit das Plugin die Unit währenddessen ersetzen kann (Bericht M5).
  FSurvey.Add(TFileEncoding.ReadAllBytes(AFileName));
end;

{ TShellEncodingReport }

constructor TShellEncodingReport.Create(const AName, ARoot: string; const ALogger: ILogger;
  const ATransport: IJsonRpcTransport; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FName := AName;
  FRoot := ARoot;
  FLogger := ALogger;
  FTransport := ATransport;
  FIndex := AIndex;
end;

function TShellEncodingReport.Survey(const AFiles: TArray<string>): TEncodingSurvey;
var
  mFiles: TSurveyFiles;
  mFileName, mInclude: string;
  mUnit: TUnitIndex;
begin
  mFiles := TSurveyFiles.Create(TFileEncodingDefaults.CodePageFor(TPath.Combine(FRoot, 'x.pas')));
  try
    for mFileName in AFiles do
    begin
      mFiles.Add(mFileName);
      mFiles.Add(ChangeFileExt(mFileName, '.dfm'));
      mFiles.Add(ChangeFileExt(mFileName, '.fmx'));
      if FIndex.FindFile(mFileName, mUnit) then
      begin
        for mInclude in mUnit.Includes do
        begin
          mFiles.Add(mInclude);
        end;
      end;
    end;
    Result := mFiles.Survey;
  finally
    mFiles.Free;
  end;
end;

procedure TShellEncodingReport.Show(const AText: string);
var
  mParams: TJSONObject;
  mNotification: TJSONObject;
begin
  // Das Protokoll sieht im Editor kaum jemand: einmal als Meldung zeigen.
  if FShown or (FTransport = nil) then
  begin
    Exit;
  end;
  FShown := True;
  mParams := TJSONObject.Create;
  mParams.AddPair('type', TJSONNumber.Create(2));
  mParams.AddPair('message', AText);
  mNotification := TJsonRpcMessages.Notification('window/showMessage', mParams);
  try
    FTransport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

procedure TShellEncodingReport.Report(const AFiles: TArray<string>);
var
  mSurvey: TEncodingSurvey;
  mText: string;
begin
  mSurvey := Survey(AFiles);
  if not mSurvey.IsMixed then
  begin
    FLogger.Debug(Format('Kodierungen im Projekt %s: %s', [FName, mSurvey.Describe]));
    Exit;
  end;
  mText := Format('Gemischte Kodierungen im Projekt %s: %s. Beim Schreiben behält jede Datei ihre Kodierung.',
    [FName, mSurvey.Describe]);
  FLogger.Warning(mText);
  Show(mText);
end;

end.
