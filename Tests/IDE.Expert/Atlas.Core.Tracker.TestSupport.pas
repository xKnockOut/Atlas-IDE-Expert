unit Atlas.Core.Tracker.TestSupport;

// Gemeinsames der Tracker-Tests: Transporte mit festen Antworten (lesen und schreiben), Beispieldateien aus
// Tests\Data und Ziele für GitHub und YouTrack.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Transport mit festen Antworten je Adressanfang; zählt die Aufrufe.</summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    FFail: TAtlasCiFetchError;
  public
    Calls: TArray<string>;
    procedure Answer(const APrefix: string; AStatus: Integer; const AText: string);
    procedure FailWith(AError: TAtlasCiFetchError);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Transport, der auch schreibt (#1279): merkt sich Methoden, Adressen und Inhalte, Antworten je
  /// Adressanfang.</summary>
  TFakePostTransport = class(TFakeTransport, IAtlasCiSend)
  private
    FPostPrefixes: TArray<string>;
    FPostStatus: TArray<Integer>;
    FPostTexts: TArray<string>;
  public
    Methods: TArray<string>;
    Posts: TArray<string>;
    Bodies: TArray<string>;
    procedure AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
/// <summary>GitHub-Ziel beispiel/atlas auf github.com.</summary>
function GitHubTarget: TAtlasTrackerTarget;
/// <summary>YouTrack-Ziel ATL auf beispiel.youtrack.cloud.</summary>
function YouTrackTarget: TAtlasTrackerTarget;
/// <summary>Leeres Issue mit Schlüssel, Nummer und Titel.</summary>
function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;

implementation

uses
  System.SysUtils,
  System.IOUtils;

procedure TFakeTransport.Answer(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

procedure TFakeTransport.FailWith(AError: TAtlasCiFetchError);
begin
  FFail := AError;
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AStatus := 0;
  AText := '';
  AError := FFail;
  if FFail <> TAtlasCiFetchError.None then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(FPrefixes) do
  begin
    if Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex] then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit(True);
    end;
  end;
  AStatus := 404;
  Result := True;
end;

procedure TFakePostTransport.AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPostPrefixes := FPostPrefixes + [APrefix];
  FPostStatus := FPostStatus + [AStatus];
  FPostTexts := FPostTexts + [AText];
end;

function TFakePostTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mIndex: Integer;
begin
  Methods := Methods + [AMethod];
  Posts := Posts + [AUrl];
  Bodies := Bodies + [ABody];
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  AResponse.Status := 404;
  Result := True;
  for mIndex := 0 to High(FPostPrefixes) do
  begin
    if Copy(AUrl, 1, Length(FPostPrefixes[mIndex])) = FPostPrefixes[mIndex] then
    begin
      AResponse.Status := FPostStatus[mIndex];
      AResponse.Text := FPostTexts[mIndex];
      Exit;
    end;
  end;
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
    begin
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud/', 'ATL', '');
end;

function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

end.
